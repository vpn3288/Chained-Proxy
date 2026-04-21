#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# install_transit_optimized.sh — 中转机 SNI 路由脚本
# 架构：Nginx stream ssl_preread → 落地机 TCP 直连
# 优化：精简臃肿代码 | 加强隐蔽性 | 确保连通性

readonly VERSION="v1.0-optimized"
readonly SCRIPT_NAME="$(basename "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

readonly MANAGER_BASE="/etc/transit_manager"
readonly CONF_DIR="${MANAGER_BASE}/conf"
readonly INSTALLED_FLAG="${MANAGER_BASE}/.installed"
readonly NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
readonly NGINX_STREAM_CONF="/etc/nginx/stream-transit.conf"
readonly SNIPPETS_DIR="/etc/nginx/stream-snippets"
readonly STREAM_INCLUDE_MARKER="transit-manager-stream-include"
readonly LISTEN_PORT=443
readonly FW_CHAIN="TRANSIT-MANAGER"
readonly FW_CHAIN6="TRANSIT-MANAGER-v6"
readonly LOG_DIR="/var/log/transit-manager"
readonly LOGROTATE_FILE="/etc/logrotate.d/transit-manager"

[[ $EUID -eq 0 ]] || die "必须以 root 身份运行"

# 清理临时文件
_cleanup(){
  find /etc/transit_manager /etc/nginx -maxdepth 5 \
    \( -name '.transit-mgr.*' -o -name '.snap-recover.*' \) \
    -type f -delete 2>/dev/null || true
}
trap '_cleanup' EXIT

trim(){ local s=${1-}; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

atomic_write(){
  local target="$1" mode="$2" owner_group="${3:-root:root}" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir" || die "创建目录失败: $dir"
  tmp="$(mktemp "$dir/.transit-mgr.XXXXXX")" || die "mktemp 失败: $dir"
  [[ -n "$tmp" ]] || die "mktemp 返回空路径"
  trap 'rm -f "$tmp" 2>/dev/null || true' RETURN
  cat >"$tmp" || die "写入临时文件失败"
  chmod "$mode" "$tmp" || die "chmod 失败"
  chown "$owner_group" "$tmp" 2>/dev/null || die "chown 失败"
  sync -d "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$target" || die "mv 失败: $tmp -> $target"
}

readonly TRANSIT_LOCK_FILE="${MANAGER_BASE}/tmp/transit-manager.lock"
_acquire_lock(){
  mkdir -p "${MANAGER_BASE}/tmp" || die "无法创建锁目录"
  exec 200>"$TRANSIT_LOCK_FILE" || die "无法创建锁文件"
  flock -w 10 200 || die "配置正在被其他进程修改，请稍后重试"
}
_release_lock(){ flock -u 200 2>/dev/null || true; exec 200>&- 2>/dev/null || true; }

have_ipv6(){
  [[ -f /proc/net/if_inet6 && $(wc -l < /proc/net/if_inet6 2>/dev/null || echo 0) -gt 0 ]] \
    && command -v ip6tables >/dev/null 2>&1 && ip6tables -nL >/dev/null 2>&1 \
    && [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)" != "1" ]]
}

detect_ssh_port(){
  local p=""
  command -v sshd >/dev/null 2>&1 && p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"
  [[ -z "$p" ]] && p="$(ss -H -tlnp 2>/dev/null | awk '$1=="LISTEN" && /sshd/ {sub(/^.*:/,"",$4); if($4~/^[0-9]+$/) print $4}' | head -1)"
  [[ -z "$p" ]] && p="$(grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config* 2>/dev/null | awk '{print $2}' | head -1)"
  [[ "$p" =~ ^[0-9]+$ && $p -ge 1 && $p -le 65535 ]] || die "无法探测 SSH 端口"
  printf '%s\n' "$p"
}

validate_domain(){
  local d; d="$(trim "$1")"; d="${d%.}"
  (( ${#d} >= 4 && ${#d} <= 253 )) || die "域名长度非法: $d"
  [[ "$d" == *"."* ]] || die "域名必须包含点: $d"
  command -v python3 >/dev/null 2>&1 || die "需要 python3"
  printf '%s' "$d" | python3 -c "import sys,re; d=sys.stdin.read().strip(); sys.exit(0 if re.match(r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]{2,}$', d) else 1)" \
    || die "域名格式非法: $d"
}

validate_ipv4(){
  local ip="$1"
  command -v python3 >/dev/null 2>&1 || die "需要 python3"
  printf '%s' "$ip" | python3 -c "import ipaddress,sys; a=ipaddress.IPv4Address(sys.stdin.read().strip()); sys.exit(1 if a.is_private or a.is_loopback or a.is_reserved else 0)" \
    || die "IPv4 格式非法或为私有地址: $ip"
}

validate_port(){
  [[ "$1" =~ ^[0-9]+$ ]] || die "端口格式非法: $1"
  (( $1 >= 1 && $1 <= 65535 )) || die "端口超范围: $1"
}

domain_to_safe(){
  local raw hash
  raw="$(printf '%s' "$1" | tr '.' '_' | tr -cd 'a-zA-Z0-9_-')"
  hash="$(printf '%s' "$1" | sha256sum | cut -c1-16)"
  printf '%s_%s' "${raw:0:40}" "$hash"
}

get_public_ip(){
  local ip="" src
  for src in "https://api.ipify.org" "https://ifconfig.me" "https://checkip.amazonaws.com"; do
    ip=$(curl -4 -fsSL --connect-timeout 3 --max-time 5 "$src" 2>/dev/null | tr -d '[:space:]') && [[ -n "$ip" ]] && break
  done
  [[ -n "$ip" ]] || die "无法获取公网 IP"
  printf '%s' "$ip"
}

show_help(){
  cat <<HELP
用法: bash ${SCRIPT_NAME} [选项]
  （无参数）        交互式安装或管理
  --uninstall       清除所有内容
  --import <token>  从落地机导入路由
  --status          显示状态
  --help            显示帮助
HELP
}

check_deps(){
  export DEBIAN_FRONTEND=noninteractive
  local missing=()
  for cmd in curl wget iptables python3 ip nginx; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    if command -v apt-get &>/dev/null; then
      apt-get update -qq 2>/dev/null || true
      apt-get install -y curl wget iptables python3 iproute2 nginx 2>/dev/null || die "依赖安装失败"
    else
      die "缺少依赖: ${missing[*]}"
    fi
  fi
}

optimize_kernel_network(){
  local bbr_conf="/etc/sysctl.d/99-transit-bbr.conf"
  [[ -f "$bbr_conf" ]] && return 0
  
  info "优化内核参数..."
  local ram_mb; ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); ram_mb=${ram_mb:-1024}
  local tw_max=$(( ram_mb * 100 )); (( tw_max < 10000 )) && tw_max=10000; (( tw_max > 250000 )) && tw_max=250000
  local fd_max=$(( ram_mb * 800 )); (( fd_max < 524288 )) && fd_max=524288; (( fd_max > 10485760 )) && fd_max=10485760
  
  cat > "$bbr_conf" <<EOF
net.netfilter.nf_conntrack_max=1048576
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_max_tw_buckets=${tw_max}
net.ipv4.ip_local_port_range=1024 65535
net.core.somaxconn=65535
fs.nr_open=${fd_max}
fs.file-max=${fd_max}
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
fs.protected_hardlinks=1
fs.protected_symlinks=1
EOF
  
  local ct_mem=$(( ram_mb * 1024 * 1024 / 8 / 300 )); (( ct_mem < 131072 )) && ct_mem=131072
  atomic_write "/etc/modprobe.d/nf_conntrack.conf" 644 root:root <<EOF
options nf_conntrack hashsize=${ct_mem}
EOF
  modprobe nf_conntrack 2>/dev/null || true
  echo "$ct_mem" > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
  sysctl --system &>/dev/null || true
  success "内核参数已优化"
}

install_nginx(){
  if command -v nginx &>/dev/null; then
    if echo 'events{} stream{}' | nginx -t -c /dev/stdin 2>/dev/null; then
      success "Nginx 已安装且 stream 模块可用"
      return 0
    fi
  fi
  
  info "安装 Nginx..."
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get &>/dev/null; then
    apt-get install -y nginx-common libnginx-mod-stream nginx 2>/dev/null || die "Nginx 安装失败"
  else
    die "不支持的包管理器"
  fi
  success "Nginx 安装完成"
}

init_nginx_stream(){
  mkdir -p "$LOG_DIR" "$SNIPPETS_DIR" "$CONF_DIR"
  chown root:adm "$LOG_DIR" 2>/dev/null || true
  chmod 750 "$LOG_DIR"; chmod 700 "$SNIPPETS_DIR" "$CONF_DIR"
  
  [[ -f "$NGINX_STREAM_CONF" ]] && return 0
  
  info "配置 Nginx stream..."
  local ram_mb; ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); ram_mb=${ram_mb:-1024}
  local zone_mb=$(( ram_mb / 32 )); (( zone_mb < 5 )) && zone_mb=5; (( zone_mb > 64 )) && zone_mb=64
  local ipv6_listen=""; have_ipv6 && ipv6_listen="        listen [::]:${LISTEN_PORT} fastopen=256 so_keepalive=3m:10s:3 backlog=65535;"
  
  # 关键隐蔽性配置：空/无匹配 SNI → Apple CDN (17.253.144.10:443)，完全沉默
  atomic_write "$NGINX_STREAM_CONF" 644 root:root <<EOF
# stream-transit.conf — SNI 盲传配置
stream {
    access_log off;
    error_log  ${LOG_DIR}/transit_stream_error.log emerg;
    
    limit_conn_zone \$binary_remote_addr zone=transit_stream_conn:${zone_mb}m;
    
    # 隐蔽性核心：无效/空 SNI → Apple CDN，不返回任何响应
    map \$ssl_preread_server_name \$backend_upstream {
        hostnames;
        include /etc/nginx/stream-snippets/landing_*.map;
        "~^.{254,}"      17.253.144.10:443;  # 超长 SNI
        "~[\x00-\x1F]"   17.253.144.10:443;  # 控制字符
        ""               17.253.144.10:443;  # 空 SNI
        default          17.253.144.10:443;  # 无匹配
    }
    
    server {
        listen      ${LISTEN_PORT} fastopen=256 so_keepalive=3m:10s:3 backlog=65535;
${ipv6_listen}
        ssl_preread on;
        preread_buffer_size 64k;
        preread_timeout        5s;
        proxy_pass             \$backend_upstream;
        proxy_connect_timeout  5s;
        proxy_timeout          315s;
        proxy_socket_keepalive on;
        tcp_nodelay            on;
        limit_conn transit_stream_conn 100;
    }
}
EOF
  
  # 注入到 nginx.conf
  if ! grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null; then
    local mc_tmp; mc_tmp=$(mktemp "${NGINX_MAIN_CONF%/*}/.snap-recover.XXXXXX")
    cp -f "$NGINX_MAIN_CONF" "$mc_tmp"
    printf '\n# %s\ninclude %s;\n' "$STREAM_INCLUDE_MARKER" "$NGINX_STREAM_CONF" >> "$mc_tmp"
    chmod 644 "$mc_tmp"
    mv -f "$mc_tmp" "$NGINX_MAIN_CONF"
  fi
  
  nginx -t 2>&1 || die "Nginx 配置验证失败"
  success "Nginx stream 配置完成（隐蔽性：空 SNI → Apple CDN）"
}

generate_landing_snippet(){
  local domain="$1" ip="$2" port="${3:-443}"
  local safe; safe=$(domain_to_safe "$domain")
  [[ -n "$safe" ]] || die "域名转换失败: $domain"
  
  atomic_write "${SNIPPETS_DIR}/landing_${safe}.map" 600 root:root <<EOF
    $(printf '%s' "$domain" | tr -cd 'a-zA-Z0-9._-')    $(printf '%s' "$ip" | tr -cd 'a-zA-Z0-9.'):${port};
EOF
  
  mkdir -p "$CONF_DIR"
  atomic_write "${CONF_DIR}/${safe}.meta" 600 root:root <<EOF
DOMAIN=${domain}
TRANSIT_IP=${ip}
PORT=${port}
CREATED=$(date +%Y%m%d_%H%M%S)
EOF
  success "路由片段已生成: ${domain} → ${ip}:${port}"
}

nginx_reload(){
  mkdir -p "$LOG_DIR"
  nginx -t 2>&1 || die "Nginx 配置验证失败"
  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx || systemctl restart nginx || die "Nginx 重载失败"
  else
    systemctl start nginx || die "Nginx 启动失败"
  fi
  systemctl is-active --quiet nginx || die "Nginx 未运行"
  success "Nginx 重载成功"
}

setup_firewall_transit(){
  local ssh_port; ssh_port="$(detect_ssh_port)"
  info "配置防火墙: SSH(${ssh_port}) + TCP(${LISTEN_PORT})..."
  
  # 清理旧规则
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true
  iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null || true
  
  # 创建新链
  iptables -w 2 -N "$FW_CHAIN"
  iptables -w 2 -A "$FW_CHAIN" -i lo -j ACCEPT
  iptables -w 2 -A "$FW_CHAIN" -p tcp --dport "$ssh_port" -j ACCEPT
  iptables -w 2 -A "$FW_CHAIN" -m conntrack --ctstate INVALID,UNTRACKED -j DROP
  iptables -w 2 -A "$FW_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -w 2 -A "$FW_CHAIN" -p icmp --icmp-type echo-request -m limit --limit 10/second -j ACCEPT
  iptables -w 2 -A "$FW_CHAIN" -p icmp -j DROP
  iptables -w 2 -A "$FW_CHAIN" -p tcp --dport "$LISTEN_PORT" -m connlimit --connlimit-above 2000 --connlimit-mask 32 -j DROP
  iptables -w 2 -A "$FW_CHAIN" -p tcp --dport "$LISTEN_PORT" -m hashlimit --hashlimit-upto 8000/sec --hashlimit-burst 9999 --hashlimit-mode srcip --hashlimit-name transit_443 -j ACCEPT
  iptables -w 2 -A "$FW_CHAIN" -p tcp --dport "$LISTEN_PORT" -j DROP
  iptables -w 2 -A "$FW_CHAIN" -j DROP
  iptables -w 2 -I INPUT 1 -j "$FW_CHAIN"
  
  # IPv6
  if have_ipv6; then
    ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true
    ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
    ip6tables -w 2 -D INPUT -j "$FW_CHAIN6" 2>/dev/null || true
    ip6tables -w 2 -N "$FW_CHAIN6"
    ip6tables -w 2 -A "$FW_CHAIN6" -i lo -j ACCEPT
    ip6tables -w 2 -A "$FW_CHAIN6" -p tcp --dport "$ssh_port" -j ACCEPT
    ip6tables -w 2 -A "$FW_CHAIN6" -m conntrack --ctstate INVALID,UNTRACKED -j DROP
    ip6tables -w 2 -A "$FW_CHAIN6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -w 2 -A "$FW_CHAIN6" -p ipv6-icmp -m limit --limit 10/second -j ACCEPT
    ip6tables -w 2 -A "$FW_CHAIN6" -p tcp --dport "$LISTEN_PORT" -j ACCEPT
    ip6tables -w 2 -A "$FW_CHAIN6" -j DROP
    ip6tables -w 2 -I INPUT 1 -j "$FW_CHAIN6"
  fi
  
  # 持久化
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  have_ipv6 && ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  
  success "防火墙配置完成"
}

write_logrotate(){
  atomic_write "$LOGROTATE_FILE" 644 root:root <<EOF
${LOG_DIR}/*.log {
    su root root
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    create 0640 root adm
    sharedscripts
    postrotate
        systemctl kill --kill-who=main -s USR1 nginx.service >/dev/null 2>&1 || true
    endscript
}
EOF
}

fresh_install(){
  info "开始全新安装..."
  _acquire_lock
  
  check_deps
  optimize_kernel_network
  install_nginx
  init_nginx_stream
  write_logrotate
  setup_firewall_transit
  
  mkdir -p "$MANAGER_BASE"
  touch "$INSTALLED_FLAG"
  
  systemctl enable nginx 2>/dev/null || true
  nginx_reload
  
  _release_lock
  success "安装完成！"
  info "使用 'bash $0 --import <token>' 导入落地机路由"
}

import_token(){
  local token="$1"
  [[ -n "$token" ]] || die "Token 不能为空"
  
  _acquire_lock
  
  local decoded
  decoded=$(printf '%s' "$token" | base64 -d 2>/dev/null) || die "Token 解码失败"
  
  local domain ip port
  domain=$(printf '%s' "$decoded" | grep '^DOMAIN=' | cut -d= -f2-)
  ip=$(printf '%s' "$decoded" | grep '^IP=' | cut -d= -f2-)
  port=$(printf '%s' "$decoded" | grep '^PORT=' | cut -d= -f2-)
  
  [[ -n "$domain" && -n "$ip" && -n "$port" ]] || die "Token 格式错误"
  
  validate_domain "$domain"
  validate_ipv4 "$ip"
  validate_port "$port"
  
  generate_landing_snippet "$domain" "$ip" "$port"
  nginx_reload
  
  _release_lock
  success "路由导入成功: ${domain} → ${ip}:${port}"
}

show_status(){
  if [[ ! -f "$INSTALLED_FLAG" ]]; then
    warn "未安装"
    return 1
  fi
  
  info "中转机状态:"
  echo "  Nginx: $(systemctl is-active nginx 2>/dev/null || echo 'inactive')"
  echo "  监听端口: ${LISTEN_PORT}"
  
  if [[ -d "$CONF_DIR" ]]; then
    local count=0
    for meta in "$CONF_DIR"/*.meta; do
      [[ -f "$meta" ]] || continue
      ((count++))
      local d=$(grep '^DOMAIN=' "$meta" | cut -d= -f2-)
      local i=$(grep '^TRANSIT_IP=' "$meta" | cut -d= -f2-)
      local p=$(grep '^PORT=' "$meta" | cut -d= -f2-)
      echo "  [$count] ${d} → ${i}:${p}"
    done
    [[ $count -eq 0 ]] && echo "  (无路由规则)"
  fi
}

uninstall(){
  warn "开始卸载..."
  _acquire_lock
  
  systemctl stop nginx 2>/dev/null || true
  
  # 清理防火墙
  iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null || true
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true
  iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  have_ipv6 && {
    ip6tables -w 2 -D INPUT -j "$FW_CHAIN6" 2>/dev/null || true
    ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true
    ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
  }
  
  # 清理配置
  sed -i "/$STREAM_INCLUDE_MARKER/d" "$NGINX_MAIN_CONF" 2>/dev/null || true
  sed -i "\|$NGINX_STREAM_CONF|d" "$NGINX_MAIN_CONF" 2>/dev/null || true
  rm -rf "$MANAGER_BASE" "$NGINX_STREAM_CONF" "$SNIPPETS_DIR" "$LOG_DIR" "$LOGROTATE_FILE"
  
  nginx -t 2>&1 && systemctl restart nginx 2>/dev/null || true
  
  _release_lock
  success "卸载完成"
}

# 主逻辑
case "${1:-}" in
  --help) show_help; exit 0 ;;
  --uninstall) uninstall; exit 0 ;;
  --status) show_status; exit 0 ;;
  --import)
    [[ -n "${2:-}" ]] || die "需要提供 token"
    [[ -f "$INSTALLED_FLAG" ]] || fresh_install
    import_token "$2"
    ;;
  *)
    if [[ -f "$INSTALLED_FLAG" ]]; then
      show_status
      echo ""
      echo "管理选项:"
      echo "  bash $0 --import <token>  # 导入路由"
      echo "  bash $0 --status          # 查看状态"
      echo "  bash $0 --uninstall       # 卸载"
    else
      fresh_install
    fi
    ;;
esac
