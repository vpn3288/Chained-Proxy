#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# install_landing.sh — 落地机安装脚本 v1.0
# 本版本实施以下修复：
# CRITICAL: R13,R18,R21,R28 | HIGH: R14,R15,R17,R20,R25,R29

# - 更新版本号至 v3.28
# install_landing_v3.28.sh — 落地机安装脚本 v3.28
# 版本历史 v2.80:
#   - 证书续期与状态机逻辑保持兼容且幂等
# 版本历史 v2.70:
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
readonly VERSION="v1.0"
# install_landing.sh — 落地机安装脚本 v1.0

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() {
  error "$*"
  if declare -F _fresh_install_rollback >/dev/null; then _fresh_install_rollback 2>/dev/null || true; fi
  if declare -F _delete_node_rollback >/dev/null; then _delete_node_rollback 2>/dev/null || true; fi
  if declare -F _do_rollback_port >/dev/null; then _do_rollback_port 2>/dev/null || true; fi
  exit 1
}
readonly LANDING_BASE="/etc/xray-landing"
readonly CERT_RELOAD_SCRIPT="/usr/local/bin/xray-landing-cert-reload.sh"
readonly LANDING_CONF="${LANDING_BASE}/config.json"
readonly LANDING_BIN="/usr/local/bin/xray-landing"
readonly LANDING_SVC="xray-landing.service"
readonly LANDING_USER="xray-landing"
readonly LANDING_LOG="/var/log/xray-landing"
readonly MANAGER_BASE="/etc/landing_manager"
readonly INSTALLED_FLAG="${MANAGER_BASE}/.installed"
readonly MANAGER_CONFIG="${MANAGER_BASE}/manager.conf"
readonly NGINX_CONF_ORIG="${MANAGER_BASE}/nginx.conf.orig"
ACME_HOME="${LANDING_BASE}/acme"
readonly CERT_BASE="${LANDING_BASE}/certs"
BIND_IP="0.0.0.0"
readonly FW_CHAIN="XRAY-LANDING"
readonly FW_CHAIN6="XRAY-LANDING-v6"
readonly LOGROTATE_FILE="/etc/logrotate.d/xray-landing"
readonly UPDATE_WARN_FILE="/var/run/xray-landing.update.warn"

[[ $EUID -eq 0 ]] || die "必须以 root 身份运行"

find /etc/xray-landing /etc/landing_manager /etc/nginx /etc/systemd/system \
  -maxdepth 5 -name '.snap-recover.*' -mtime +1 -delete 2>/dev/null || true

_global_cleanup(){
  find /etc/xray-landing /etc/landing_manager /etc/nginx \
    /etc/systemd/system /etc/logrotate.d \
    -maxdepth 5 \
    \( -name '.xray-landing.*' -o -name 'tmp-*.conf' -o -name '.snap-recover.*' -o -name '.manager.*' \) \
    -type f -delete 2>/dev/null || true
  rm -rf "${MANAGER_BASE}/tmp/xray_tmp_"* 2>/dev/null || true
  find "${MANAGER_BASE}/tmp" \
    -maxdepth 1 -type f \
    \( -name '.manager.*' -o -name '*.manager.*' -o -name '.nginx-conf-snap.*' -o -name '.xray-landing.*' \) \
    -delete 2>/dev/null || true
}
_emit_update_warning(){
  wait "${UPDATE_CHECK_PID:-}" 2>/dev/null || true
  if [[ -s "$UPDATE_WARN_FILE" ]]; then
    cat "$UPDATE_WARN_FILE" 2>/dev/null || true
  fi
  rm -f "$UPDATE_WARN_FILE" 2>/dev/null || true
}
trap '_emit_update_warning; _global_cleanup' EXIT
trap 'echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

LANDING_PORT=8443
VLESS_UUID=""
VLESS_GRPC_PORT=0
TROJAN_GRPC_PORT=0
VLESS_WS_PORT=0
TROJAN_TCP_PORT=0
CF_TOKEN=""
CREATED_USER="0"

trim(){
  local s=${1-}
  s="${s#${s%%[!' '	\
]*}}"
  s="${s%${s##*[!' '	\
]}}"
  printf '%s' "$s"
}

shell_quote(){
  local s=${1-}
  printf "'%s'" "${s//\'/\'\\\'\'}"
}

atomic_write()(
  set -euo pipefail
  local target="$1" mode="$2" owner_group="${3:-root:root}" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir"
tmp="$(mktemp "$dir/.xray-landing.XXXXXX" 2>/dev/null)" \
    || { echo "atomic_write: mktemp failed for $dir" >&2; exit 1; }
  [[ -n "$tmp" ]] || { echo "atomic_write: mktemp returned empty path" >&2; exit 1; }
  trap 'rm -f "$tmp" 2>/dev/null || true' EXIT
  cat >"$tmp" \
    || { echo "atomic_write: cat to $tmp failed" >&2; exit 1; }
  chmod "$mode" "$tmp" \
    || { echo "atomic_write: chmod failed for $tmp" >&2; exit 1; }
  chown "$owner_group" "$tmp" 2>/dev/null \
    || { echo "atomic_write: chown failed for $tmp" >&2; exit 1; }
  sync -d "$tmp" \
    || { echo "atomic_write: sync -d failed for $tmp" >&2; exit 1; }
  mv -f "$tmp" "$target" \
    || { echo "atomic_write: mv $tmp -> $target failed" >&2; exit 1; }
)

readonly LANDING_LOCK_FILE="${MANAGER_BASE}/tmp/landing-manager.lock"
_acquire_lock(){
  mkdir -p "${MANAGER_BASE}/tmp" || die "无法创建锁目录 ${MANAGER_BASE}/tmp（检查磁盘/权限/只读文件系统）"
  exec 201>"$LANDING_LOCK_FILE" || die "无法创建锁文件 ${LANDING_LOCK_FILE}（检查磁盘/权限/只读文件系统）"
  flock -w 10 201 || die "配置正在被其他进程修改，请稍后重试（等待超时 10s）"
}
_release_lock(){ flock -u 201 2>/dev/null || true; exec 201>&- 2>/dev/null || true; }

load_manager_config(){
  [[ -f "$MANAGER_CONFIG" ]] || return 0

  local lp vu vg tg vw tt ct cu mvn ah bc mc
  lp=$(grep '^LANDING_PORT='    "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  vu=$(grep '^VLESS_UUID='      "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  vg=$(grep '^VLESS_GRPC_PORT=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  tg=$(grep '^TROJAN_GRPC_PORT=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  vw=$(grep '^VLESS_WS_PORT='   "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  tt=$(grep '^TROJAN_TCP_PORT=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  ct=$(grep '^CF_TOKEN='        "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  cu=$(grep '^CREATED_USER='    "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  mvn=$(grep '^MARKER_VERSION=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  ah=$(grep '^ACME_HOME='       "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  bc=$(grep '^BIND_IP='         "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  [[ -n "$lp" && "$lp" =~ ^[0-9]+$ && $lp -ge 1 && $lp -le 65535 ]] || die "manager.conf 损坏：LANDING_PORT='${lp:-<空>}' 非法"
  [[ -n "$vu" && "$vu" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "manager.conf 损坏：VLESS_UUID='${vu:-<空>}' 格式非法"

  if [[ -n "${mvn:-}" && "$mvn" != "$VERSION" ]]; then
    if _ver_gt "$mvn" "$VERSION"; then
      die "manager.conf 来自更高版本 ${mvn}，当前脚本为 ${VERSION}。请下载最新脚本后再运行。"
    else
      warn "manager.conf 来自旧版本 ${mvn}，当前脚本 ${VERSION} 将继续兼容读取"
    fi
  fi

  LANDING_PORT="$lp"
  VLESS_UUID="$vu"
  for _pf in "$vg" "$tg" "$vw" "$tt"; do
    [[ -z "$_pf" || "$_pf" =~ ^[0-9]+$ ]] || die "manager.conf 损坏：内部端口 '${_pf}' 格式非法"
  done
  [[ "$vg" =~ ^[0-9]+$ ]] && VLESS_GRPC_PORT="$vg" || VLESS_GRPC_PORT=0
  [[ "$tg" =~ ^[0-9]+$ ]] && TROJAN_GRPC_PORT="$tg" || TROJAN_GRPC_PORT=0
  [[ "$vw" =~ ^[0-9]+$ ]] && VLESS_WS_PORT="$vw" || VLESS_WS_PORT=0
  [[ "$tt" =~ ^[0-9]+$ ]] && TROJAN_TCP_PORT="$tt" || TROJAN_TCP_PORT=0
  [[ -n "$ct" ]] && CF_TOKEN="$ct" || CF_TOKEN=""
  [[ -n "$cu" ]] && CREATED_USER="$cu" || CREATED_USER="0"
  [[ -n "$ah" ]] && ACME_HOME="$ah" || ACME_HOME="${LANDING_BASE}/acme"
  [[ -n "$bc" ]] && BIND_IP="$bc" || BIND_IP="0.0.0.0"
  _validate_internal_ports_in_use
}

save_manager_config(){
  mkdir -p "$MANAGER_BASE"
  atomic_write "$MANAGER_CONFIG" 600 root:root <<MCEOF
LANDING_PORT=${LANDING_PORT}
VLESS_UUID=${VLESS_UUID}
VLESS_GRPC_PORT=${VLESS_GRPC_PORT}
TROJAN_GRPC_PORT=${TROJAN_GRPC_PORT}
VLESS_WS_PORT=${VLESS_WS_PORT}
TROJAN_TCP_PORT=${TROJAN_TCP_PORT}
CF_TOKEN=${CF_TOKEN}
CREATED_USER=${CREATED_USER}
MARKER_VERSION=${VERSION}
ACME_HOME=${ACME_HOME}
XRAY_BIN=${LANDING_BIN}
XRAY_LOG_DIR=${LANDING_LOG}
BIND_IP=${BIND_IP}
MARKER_CREATED=$(date +%Y%m%d_%H%M%S)
MCEOF
}

_validate_internal_ports_in_use(){
  local _p _pids _pid _comm
  for _p in "$VLESS_GRPC_PORT" "$TROJAN_GRPC_PORT" "$VLESS_WS_PORT" "$TROJAN_TCP_PORT"; do
    [[ "${_p:-0}" =~ ^[0-9]+$ ]] || continue
    (( _p >= 1 && _p <= 65535 )) || continue
    _pids=$(ss -H -tlnp 2>/dev/null | awk -v p=":${_p}$" '
      $1=="LISTEN" && $4 ~ p {
        sub(/[^0-9].*/,"")
        sub(/.*pid=/,"")
        if(/^[0-9]+$/) print
      }' | sort -u || true)
    [[ -n "${_pids:-}" ]] || continue
    while IFS= read -r _pid; do
      [[ -n "${_pid:-}" ]] || continue
      _comm=$(ps -o comm= -p "$_pid" 2>/dev/null | tr -d '[:space:]' || true)
      case "$_comm" in
        nginx|xray|xray-landing|python3|'') continue ;;
      esac
      die "内网端口 ${_p} 已被非 Nginx/Xray 进程占用，请重新运行脚本（自动重新分配）"
    done <<<"$_pids"
    [[ "$_p" != "${LANDING_PORT:-0}" ]] || die "内网端口 ${_p} 与落地机监听端口冲突，请重新分配"
  done
}

_restore_prev_port_traps(){
  if [[ -n "${_prev_err_trap:-}" ]]; then
    eval "$_prev_err_trap" || trap - ERR
  else
    trap - ERR
  fi
  if [[ -n "${_prev_int_trap:-}" ]]; then
    eval "$_prev_int_trap" || trap - INT
  else
    trap - INT
  fi
  if [[ -n "${_prev_term_trap:-}" ]]; then
    eval "$_prev_term_trap" || trap - TERM
  else
    trap - TERM
  fi
}

have_ipv6(){
  [[ -f /proc/net/if_inet6 && $(wc -l < /proc/net/if_inet6 2>/dev/null || echo 0) -gt 0 ]] \
    && command -v ip6tables >/dev/null 2>&1 && ip6tables -nL >/dev/null 2>&1 \
    && [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)" != "1" ]]
}

detect_ssh_port(){
  local p=""
  p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"
  if [[ -z "${p:-}" ]]; then
    p="$(ss -H -tlnp 2>/dev/null | awk '
      $1=="LISTEN" && /sshd/ {
        addr=$4
        sub(/^.*:/,"",addr)
        gsub(/^\[/,"",addr)
        gsub(/\]$/,"",addr)
        if (addr ~ /^[0-9]+$/) { print addr; exit }
      }' | sort -n | head -1 || true)"
  fi
  if [[ -z "${p:-}" ]]; then
    p="$(grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk '{print $2}' | sort -n | head -1 || true)"
  fi
  if [[ ! "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
    if [[ "${detect_ssh_port_override:-}" =~ ^[0-9]+$ ]] && (( detect_ssh_port_override >= 1 && detect_ssh_port_override <= 65535 )); then
      p="$detect_ssh_port_override"
    else
      echo -e "${RED}[FATAL]${NC} 无法探测 SSH 端口（sshd -T 和 ss 均失败）。环境变量 detect_ssh_port_override='${detect_ssh_port_override:-<未设置>}' 无效（需为 1-65535 的数字）。" >&2
      exit 1
    fi
  fi
  printf '%s\n' "$p"
}

validate_domain(){
  local d
  d="$(trim "$1")"
  d="${d%.}"
  (( ${#d} >= 4 && ${#d} <= 253 )) || die "域名长度非法 (${#d}): $d"
  [[ "$d" == *".."* ]] && die "域名不能包含连续的点: $d"
  [[ "$d" == *"."* ]] || die "域名必须包含至少一个点: $d"
  if ! command -v python3 >/dev/null 2>&1; then
    die "Python3 未安装，无法验证域名格式"
  fi
  local py_result
  if ! py_result=$(printf '%s' "$d" | python3 -c "import sys,re; d=sys.stdin.read().strip(); pat=re.compile(r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z0-9]{2,}$'); sys.exit(0 if pat.match(d) else 1)" 2>&1); then
    if [[ -n "$py_result" ]]; then
      die "Python 域名验证崩溃: $py_result"
    else
      die "域名格式非法: $d"
    fi
  fi
}

validate_ipv4(){
  local ip="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    die "Python3 未安装，无法验证 IPv4 格式"
  fi
  local py_result
  if ! py_result=$(printf '%s' "$ip" | python3 -c "import ipaddress, sys
ip = sys.stdin.read().strip()
try:
    addr = ipaddress.IPv4Address(ip)
    if addr.is_loopback or addr.is_unspecified or addr.is_reserved or addr.is_multicast or addr.is_link_local or addr.is_private:
        raise SystemExit(1)
except ValueError:
    raise SystemExit(1)
" 2>&1); then
    if [[ -n "$py_result" ]]; then
      die "Python IPv4 验证崩溃: $py_result"
    else
      die "IPv4 格式非法: $ip"
    fi
  fi
}

validate_port(){
  [[ "$1" =~ ^[0-9]+$ ]] || die "端口格式非法: $1"
  (( $1 >= 1 && $1 <= 65535 )) || die "端口需在 1-65535: $1"
}

validate_password(){
  local p="$1"
  [[ ${#p} -ge 16 ]] || die "Trojan 密码至少 16 位"
  [[ "$p" =~ ^[a-zA-Z0-9]+$ ]] || die "密码仅限字母数字"
}

validate_cf_token(){
  [[ -n "$1" ]] || die "CF Token 不能为空"
  [[ ${#1} -ge 40 ]] || die "CF Token 格式疑似有误（长度 ${#1} 位，通常 ≥40 位）"
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || die "CF Token 含非法字符（仅允许字母、数字、_、-）"
}

show_help(){
  cat <<HELP
用法: bash install_landing_${VERSION}.sh [选项]
  （无参数）        交互式安装或管理菜单
  --uninstall       清除本脚本所有内容（不影响 mack-a）
  --status          显示当前状态
  set-port <port>   修改落地机监听端口并重启服务
  headless 模式:    LANDING_HEADLESS=1 或 LANDING_AUTO_* 环境变量
  --help            显示此帮助
HELP
}

get_public_ip(){
  local ip=""
  local src attempt
  for attempt in 1 2; do
    for src in     "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip"     "http://169.254.169.254/latest/meta-data/public-ipv4"     "http://169.254.169.254/opc/v1/public-ip"     "https://api.ipify.org"     "https://ifconfig.me"     "https://ipecho.net/plain"     "https://checkip.amazonaws.com"; do
      if [[ "$src" == *"metadata.google.internal"* ]]; then
        ip=$(curl -4 -fsSL --connect-timeout 2 --max-time 5 --retry 2 -H "Metadata-Flavor: Google" "$src" 2>/dev/null | tr -d '[:space:]' || true)
      else
        ip=$(curl -4 -fsSL --connect-timeout 2 --max-time 5 --retry 2 "$src" 2>/dev/null | tr -d '[:space:]' || true)
      fi
      [[ -n "$ip" ]] && break
    done
    [[ -n "$ip" ]] && break
    sleep 1
  done
  [[ -n "$ip" ]] || die "无法获取本机公网 IPv4"
  validate_ipv4 "$ip"
  echo "$ip"
}

gen_password(){
  local _pw=""
  _pw=$(python3 -c \
    "import secrets,string; a=string.ascii_letters+string.digits; \
     print(''.join(secrets.choice(a) for _ in range(20)),end='')" 2>/dev/null) \
  && [[ ${#_pw} -ge 20 ]] && { printf '%s' "$_pw"; return 0; }

  _pw=$(openssl rand -base64 48 2>/dev/null \
    | LC_ALL=C tr -dc 'a-zA-Z0-9' 2>/dev/null \
    | dd bs=1 count=20 2>/dev/null) \
  && [[ ${#_pw} -ge 20 ]] && { printf '%s' "$_pw"; return 0; }

  _pw=$(dd if=/dev/urandom bs=1 count=100 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9' | dd bs=1 count=20 2>/dev/null)
  [[ ${#_pw} -ge 20 ]] || die "/dev/urandom fallback password generation failed: insufficient entropy"
  [[ -n "${_pw:-}" ]] || die "/dev/urandom fallback password generation failed (all three methods exhausted)"
  printf '%s' "$_pw"
}

check_deps(){
  export DEBIAN_FRONTEND=noninteractive
  local ip_pkg="iproute2"
  local dig_pkg="dnsutils"
  if command -v yum &>/dev/null || command -v dnf &>/dev/null; then
    ip_pkg="iproute"
    dig_pkg="bind-utils"
  fi
  local _bin_pkg=(
    curl:curl wget:wget unzip:unzip iptables:iptables python3:python3
    openssl:openssl nginx:nginx ip:${ip_pkg} dig:${dig_pkg} fuser:psmisc crontab:cron
  )
  local missing_pkgs=()
  for bp in "${_bin_pkg[@]}"; do
    local bin="${bp%%:*}" pkg="${bp##*:}"
    command -v "$bin" &>/dev/null || missing_pkgs+=("$pkg")
  done
  local missing=("${missing_pkgs[@]}")
  if (( ${#missing[@]} > 0 )) && command -v apt-get &>/dev/null; then
    local _lw=0
    if command -v fuser &>/dev/null; then
      while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        sleep 2; ((_lw+=2))
        if ((_lw>60)); then die "apt 锁等待超时（另一个 apt 进程正在运行），请稍后重试"; fi
      done
    else
      sleep 5
    fi
    apt-get update -qq 2>/dev/null || true
    for d in "${missing[@]}"; do
      apt-get install -y "$d" 2>/dev/null || die "安装 $d 失败"
    done
  elif (( ${#missing[@]} > 0 )); then
    for d in "${missing[@]}"; do
      yum install -y "$d" 2>/dev/null || dnf install -y "$d" 2>/dev/null || die "无法安装 $d"
    done
  fi
  for bp in "${_bin_pkg[@]}"; do
    local bin="${bp%%:*}"
    command -v "$bin" &>/dev/null || die "依赖 ${bin} 安装后仍无法找到"
  done
}

optimize_kernel_network(){
  local bbr_conf="/etc/sysctl.d/99-landing-bbr.conf"
  [[ -f "$bbr_conf" ]] && grep -q 'tcp_timestamps' "$bbr_conf" 2>/dev/null && {
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi 'bbr' \
      || warn "BBRPlus 未检测到，请确认已运行 one_click_script 并重启"
    return 0
  }

  local _ram_mb; _ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _ram_mb=${_ram_mb:-1024}
  local _tw_max=$(( _ram_mb * 100 ))
  (( _tw_max < 10000 ))  && _tw_max=10000
  (( _tw_max > 250000 )) && _tw_max=250000
  local _ram_mb_fd; _ram_mb_fd=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _ram_mb_fd=${_ram_mb_fd:-1024}
  local _fd_max=$(( _ram_mb_fd * 800 ))
  (( _fd_max < 524288 ))   && _fd_max=524288
  (( _fd_max > 10485760 )) && _fd_max=10485760
  cat > "$bbr_conf" <<BBRCF
net.netfilter.nf_conntrack_max=1048576
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_max_tw_buckets=${_tw_max}
net.ipv4.ip_local_port_range=1024 65535
net.core.somaxconn=65535
fs.nr_open=${_fd_max}
fs.file-max=${_fd_max}
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
BBRCF
  cat >> "$bbr_conf" <<'BBRCF2'
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
BBRCF2
  local _ct_mem; _ct_mem=$(free -m 2>/dev/null | awk '/Mem:/{print int($2/8*1024*1024/300)}'); _ct_mem=${_ct_mem:-262144}
  (( _ct_mem < 131072 )) && _ct_mem=131072
  atomic_write "/etc/modprobe.d/99-landing-conntrack.conf" 644 root:root <<LMEOF
options nf_conntrack hashsize=${_ct_mem}
LMEOF
  modprobe nf_conntrack 2>/dev/null || true
  echo "$_ct_mem" > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
  local _ct_max=$(( _ct_mem * 4 ))
  sysctl -w net.netfilter.nf_conntrack_max="${_ct_max}" &>/dev/null || true
  sysctl --system &>/dev/null || true

  local _limitsd="/etc/security/limits.d/99-xray-landing.conf"
  mkdir -p /etc/security/limits.d
  atomic_write "$_limitsd" 644 root:root <<LIMEOF
* soft nofile ${_fd_max}
* hard nofile ${_fd_max}
root soft nofile ${_fd_max}
root hard nofile ${_fd_max}
LIMEOF

  warn "sysctl 配置已重新加载；若需立即回收运行态内核资源，建议重启主机"
  sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi 'bbr' \
    || warn "BBRPlus 未检测到，请确认已运行 one_click_script 并重启后再检查"
  success "内核网络参数已优化（conntrack hashsize=${_ct_mem} / 拥塞控制权归 BBRPlus）"
}

install_xray_binary(){
  info "下载 Xray-core ..."
  local ver
  ver=$(curl -fsSLI --connect-timeout 10 -o /dev/null -w '%{url_effective}' \
         "https://github.com/XTLS/Xray-core/releases/latest" 2>/dev/null | awk -F/ 'NF{print $NF}' | tail -1)
  [[ -n "$ver" ]] || die "无法解析 Xray 版本号"
  local arch; arch=$(uname -m)
  local arch_name="64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && arch_name="arm64-v8a"
  [[ "$arch" == "armv7l" ]] && arch_name="arm32-v7a"
  local zip_name="Xray-linux-${arch_name}.zip"
  mkdir -p "${MANAGER_BASE}/tmp"
  local tmp_dir; tmp_dir=$(mktemp -d "${MANAGER_BASE}/tmp/xray_tmp_XXXXXX") \
    || die "mktemp tmp_dir failed"
  # 严禁用 EXIT trap（会覆写全局 _global_cleanup）
  _xray_local_cleanup(){ rm -rf "${tmp_dir}" 2>/dev/null || true; }
  wget -q --show-progress --timeout=30 --tries=2 -O "${tmp_dir}/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip_name}" || die "下载 Xray 失败"
  local sha256_hash
  if ! wget -q --timeout=15 --tries=3 -O "${tmp_dir}/xray.zip.dgst" \
      "https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip_name}.dgst" 2>/dev/null; then
    die "Xray .dgst 校验文件下载失败，拒绝安装未验证二进制"
  fi
  sha256_hash=$(grep -i '^SHA2-256=' "${tmp_dir}/xray.zip.dgst" | tail -1 | awk -F= '{sub(/^[^=]*=/,"",$0); print}' | tr -d ' ')
  [[ ${#sha256_hash} -eq 64 && "$sha256_hash" =~ ^[0-9a-f]{64}$ ]] || die "无法从 .dgst 解析有效 SHA2-256（格式异常），拒绝安装未验证二进制"
  info "从 .dgst 解析到 SHA2-256: ${sha256_hash:0:16}..."
  echo "${sha256_hash}  ${tmp_dir}/xray.zip" | sha256sum -c - \
    || die "Xray 完整性校验失败，拒绝安装未验证二进制"
  info "sha256 校验通过"
  unzip -q "${tmp_dir}/xray.zip" xray geoip.dat geosite.dat -d "${tmp_dir}/" || die "解压失败"
  install -m 755 "${tmp_dir}/xray" "$LANDING_BIN"
  chown root:"$LANDING_USER" "$LANDING_BIN" 2>/dev/null || true
  local asset_dir="/usr/local/share/xray-landing"
  mkdir -p "$asset_dir"
  install -m 644 "${tmp_dir}/geoip.dat"   "${asset_dir}/geoip.dat"
  install -m 644 "${tmp_dir}/geosite.dat" "${asset_dir}/geosite.dat"
  _xray_local_cleanup  # 正常路径：清理 tmp_dir
  success "Xray 安装完成: ${LANDING_BIN} (${ver})"
}

create_system_user(){
  if ! id "$LANDING_USER" &>/dev/null; then
    groupadd -r "$LANDING_USER" 2>/dev/null || true
    useradd -r -g "$LANDING_USER" -s /usr/sbin/nologin -d /nonexistent -M "$LANDING_USER" \
      || die "创建系统用户 ${LANDING_USER} 失败（useradd 错误）。请检查 /usr/sbin/nologin 是否存在"
    CREATED_USER="1"
    success "系统用户 ${LANDING_USER} 已创建"
  fi
}

_tune_nginx_worker_connections(){
  local mc="/etc/nginx/nginx.conf"
  mkdir -p "${MANAGER_BASE}" "${MANAGER_BASE}/tmp"
  [[ -f "$NGINX_CONF_ORIG" ]] || cp -a "$mc" "$NGINX_CONF_ORIG" 2>/dev/null || true
  mkdir -p "${MANAGER_BASE}/tmp" || die "mkdir ${MANAGER_BASE}/tmp failed"
  local _mc_bak; _mc_bak=$(mktemp "${MANAGER_BASE}/tmp/.nginx-conf-snap.XXXXXX" 2>/dev/null) \
    || die "mktemp _mc_bak failed (disk full?) — cannot proceed without rollback capability"
  [[ -n "$_mc_bak" ]] || die "mktemp returned empty path"
  cp -a "$mc" "$_mc_bak" || { warn "nginx.conf snapshot failed, skipping tuning"; return 0; }
  local _mc_dirty=0
  local _tmc_ram_mb; _tmc_ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _tmc_ram_mb=${_tmc_ram_mb:-1024}
  local _tmc_fd=$(( _tmc_ram_mb * 800 ))
  (( _tmc_fd < 524288 ))   && _tmc_fd=524288
  (( _tmc_fd > 10485760 )) && _tmc_fd=10485760

  grep -qE "^[[:space:]]*worker_connections[[:space:]]+100000[[:space:]]*;[[:space:]]*# xray-landing-tuning-v${VERSION}$" "$mc" 2>/dev/null || {
    _mc_dirty=1
    if grep -qE '^[[:space:]]*worker_connections' "$mc" 2>/dev/null; then
      sed -i -E "s/^([[:space:]]*worker_connections[[:space:]]+)[0-9]+([[:space:]]*;.*)?/\1100000; # xray-landing-tuning-v${VERSION}/" "$mc"
    else
      sed -i '/^events\s*{/a\    worker_connections 100000; # xray-landing-tuning-v${VERSION}' "$mc"
    fi
  }
  grep -qE "^worker_rlimit_nofile\s+${_tmc_fd}\s*;[[:space:]]*# xray-landing-tuning-v${VERSION}$" "$mc" 2>/dev/null || {
    _mc_dirty=1
    if grep -qE '^[[:space:]]*worker_rlimit_nofile' "$mc" 2>/dev/null; then
      sed -i "s/^[[:space:]]*worker_rlimit_nofile.*/worker_rlimit_nofile ${_tmc_fd}; # xray-landing-tuning-v${VERSION}/" "$mc"
    else
      sed -i "/^events\s*{/i\\worker_rlimit_nofile ${_tmc_fd}; # xray-landing-tuning-v${VERSION}" "$mc"
    fi
  }
  grep -qE '^worker_shutdown_timeout\s+10m\s*;[[:space:]]*# xray-landing-tuning-v${VERSION}$' "$mc" 2>/dev/null || {
    _mc_dirty=1
    if grep -qE '^[[:space:]]*worker_shutdown_timeout' "$mc" 2>/dev/null; then
      sed -i "s/^.*worker_shutdown_timeout.*/worker_shutdown_timeout 10m; # xray-landing-tuning-v${VERSION}/" "$mc"
    else
      sed -i '/^events\s*{/i\worker_shutdown_timeout 10m; # xray-landing-tuning-v${VERSION}' "$mc"
    fi
  }
  if (( _mc_dirty )); then
    if ! nginx -t 2>/dev/null; then
      warn "nginx.conf tuning validation failed — restoring snapshot"
      if ! mv -f "$_mc_bak" "$mc" 2>/dev/null; then
        cp -a "$_mc_bak" "$mc" || die "nginx.conf restore FAILED — file may be corrupted; manual fix needed"
      fi
      die "nginx.conf tuning failed; original config restored"
    fi
  fi
  rm -f "$_mc_bak" 2>/dev/null || true
  local od="/etc/systemd/system/nginx.service.d"
  mkdir -p "$od"
  local _ov="${od}/landing-override.conf"
  atomic_write "$_ov" 644 root:root <<SVCOV
[Service]
LimitNOFILE=${_tmc_fd}
TasksMax=infinity
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
UMask=0027
StandardOutput=null
StandardError=null
SVCOV
  systemctl daemon-reload || die "daemon-reload failed — drop-in limits will not apply"
}

setup_fallback_decoy(){
  local fallback_conf="/etc/nginx/conf.d/xray-landing-fallback.conf"
  local _check_port _pid_list _proc _bad=0
  for _check_port in 45231 45232; do
    [[ "$_check_port" =~ ^[0-9]+$ ]] || die "Invalid port number"
    if command -v fuser >/dev/null 2>&1; then
      _pid_list=$(fuser -n tcp "$_check_port" 2>/dev/null)
    else
      _pid_list=""
    fi
    [[ -n "${_pid_list:-}" ]] || continue
    while IFS= read -r _proc; do
      [[ -z "$_proc" ]] && continue
      [[ "$_proc" == nginx ]] || _bad=1
    done < <(echo "$_pid_list" | tr ' ' '\n' | grep -E '^[0-9]+$' \
    | xargs -r ps -o comm= -p 2>/dev/null | sed '/^$/d')
    (( _bad )) && die "端口 45231 或 45232 已被非 Nginx 进程占用，请检查是否有其他服务在使用该端口"
  done
  if ! command -v nginx &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null || true
    apt-get install -y nginx 2>/dev/null || die "Nginx 安装失败"
  fi
  _tune_nginx_worker_connections
  local need_ipv6=0; have_ipv6 && need_ipv6=1
  if (( need_ipv6 )); then
    atomic_write "$fallback_conf" 644 root:root <<'FDEOF'
limit_conn_zone $binary_remote_addr zone=fallback_conn:10m;
limit_req_zone  $binary_remote_addr zone=fallback_req:10m rate=10r/s;
server {
    listen 127.0.0.1:45231;
    listen 127.0.0.1:45232;
    listen [::1]:45231;
    listen [::1]:45232;
    server_name _;
    server_tokens off;
    http2 on;
    limit_conn fallback_conn 4;
    limit_req  zone=fallback_req burst=50 nodelay;
    error_page 400 503 = @silent_close;
    location @silent_close { return 444; }
    location / { return 444; }
    access_log off;
    error_log /dev/null;
}
FDEOF
  else
    atomic_write "$fallback_conf" 644 root:root <<'FDEOF'
limit_conn_zone $binary_remote_addr zone=fallback_conn:10m;
limit_req_zone  $binary_remote_addr zone=fallback_req:10m rate=10r/s;
server {
    listen 127.0.0.1:45231;
    listen 127.0.0.1:45232;
    server_name _;
    server_tokens off;
    http2 on;
    limit_conn fallback_conn 4;
    limit_req  zone=fallback_req burst=50 nodelay;
    error_page 400 503 = @silent_close;
    location @silent_close { return 444; }
    location / { return 444; }
    access_log off;
    error_log /dev/null;
}
FDEOF
  fi
  nginx -t 2>&1 || die "Nginx fallback 配置验证失败"
  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx \
      || die "nginx reload failed — decoy will not survive reboot"
  else
    systemctl enable nginx       || die "nginx enable failed — decoy will not survive reboot"
    systemctl is-enabled --quiet nginx       || die "nginx is-enabled check failed"
    systemctl start nginx || die "Nginx 启动失败"
  fi
  success "fallback 防探针站已就绪"
}

_write_cert_reload_script(){
  (atomic_write "$CERT_RELOAD_SCRIPT" 755 root:root <<'RELOAD_EOF'
#!/bin/sh
# xray-landing-reload-v\${VERSION}
set -eu
CERT_DIR="\${1:-}"
if [ -z "\$CERT_DIR" ]; then
  logger -t acme-xray-landing "ERROR: CERT_DIR is empty"
  exit 1
fi
if [ ! -d "\$CERT_DIR" ]; then
  logger -t acme-xray-landing "INFO: CERT_DIR does not exist yet (first-install path) — skipping reload"
  exit 0
fi

# before create_systemd_service has created the unit file
if [ ! -f "/etc/systemd/system/xray-landing.service" ]; then
  logger -t acme-xray-landing "INFO: xray-landing.service unit file not yet created — skipping reload (first-install path)"
  exit 0
fi

if ! /bin/systemctl is-active --quiet xray-landing.service 2>/dev/null; then
  logger -t acme-xray-landing "INFO: xray-landing.service not yet active — skipping reload (first-install or transient path)"
  exit 0
fi

chown -R root:xray-landing "\$CERT_DIR" \
  || { logger -t acme-xray-landing "ERROR: chown failed for \$CERT_DIR"; exit 1; }
chmod 750 "\$CERT_DIR" \
  || { logger -t acme-xray-landing "ERROR: chmod 750 failed for \$CERT_DIR"; exit 1; }
chmod 640 "\$CERT_DIR/cert.pem" "\$CERT_DIR/fullchain.pem" \
  || { logger -t acme-xray-landing "ERROR: chmod 640 failed for certs"; exit 1; }
chmod 640 "\$CERT_DIR/key.pem" \
  || { logger -t acme-xray-landing "ERROR: chmod 640 failed for key.pem — key may be exposed"; exit 1; }

if openssl x509 -checkend 86400 -noout -in "\${CERT_DIR}/fullchain.pem" 2>/dev/null; then
  # 直接 restart，移除无效的 reload 尝试
  if ! /bin/systemctl restart xray-landing.service 2>/dev/null; then
    _msg="FATAL: restart failed for xray-landing.service"
    logger -t acme-xray-landing "\$_msg"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$_msg" >> /var/log/acme-xray-landing-renew.log || true
    exit 1
  fi
else
  _msg="WARN: 证书续期后校验失败（\${CERT_DIR}），保留旧进程态，等待下次 cron 重试"
  logger -t acme-xray-landing "\$_msg"
  echo "\$(date '+%Y-%m-%d %H:%M:%S') \$_msg" >> /var/log/acme-xray-landing-renew.log || true
  exit 1
fi
RELOAD_EOF
  )
}

issue_certificate(){
  local domain="$1" cf_token="$2"
  local cert_dir="${CERT_BASE}/${domain}"

  local _zone_id
  _zone_id=$(curl -fsSL --connect-timeout 5 --max-time 10 \
    -H "Authorization: Bearer $cf_token" \
    "https://api.cloudflare.com/client/v4/zones?name=${domain#*.}" \
    2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else '')" 2>/dev/null) || true
  if [[ -z "$_zone_id" ]]; then
    die "Cloudflare API Token 验证失败（无法获取 Zone ID），请检查 Token 权限（需要 Zone:DNS:Edit）"
  fi
  info "Cloudflare Zone ID: $_zone_id（Token 验证通过）"

  if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/key.pem" ]]; then
    local end_str; end_str=$(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -enddate 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    local expiry_days=0
    if [[ -n "$end_str" ]]; then
      local end_ts now_ts
      end_ts=$(LANG=C date -d "${end_str//[^a-zA-Z0-9: +-]/}" +%s 2>/dev/null || echo 0); now_ts=$(date +%s)
      expiry_days=$(( (end_ts - now_ts) / 86400 )); (( expiry_days < 0 )) && expiry_days=0
    fi
    if (( expiry_days > 30 )); then
      success "证书有效（剩余 ${expiry_days} 天），跳过申请"
      chown -R root:"$LANDING_USER" "$cert_dir" 2>/dev/null || true
      chmod 750 "$cert_dir" 2>/dev/null || true
      chmod 644 "${cert_dir}/cert.pem" "${cert_dir}/fullchain.pem" 2>/dev/null || true
      chmod 640 "${cert_dir}/key.pem" 2>/dev/null || true
      if [[ ! -f "$CERT_RELOAD_SCRIPT" ]] || ! grep -q "# xray-landing-reload-v${VERSION}" "$CERT_RELOAD_SCRIPT" 2>/dev/null; then
        warn "证书重载脚本缺失或版本过旧，重新生成..."
        _write_cert_reload_script
      fi
      if [[ -f "${ACME_HOME}/acme.sh" ]]; then
        env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
        env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --install-cronjob 2>/dev/null           || die "acme.sh --install-cronjob 失败！续期链路断开，无法继续。请检查 crontab 权限后重试，或手动执行: ${ACME_HOME}/acme.sh --install-cronjob"
        if ! crontab -l 2>/dev/null | grep -qE "acme\.sh.*--cron.*--home.*acme"; then
          die "acme.sh cron 条目验收失败（未指向 ${ACME_HOME}/acme.sh），请手动执行: ${ACME_HOME}/acme.sh --install-cronjob"
        fi
      fi
      return 0
    fi
    info "证书即将到期（${expiry_days} 天），重新申请"
  fi

  mkdir -p "$cert_dir" "${ACME_HOME}"
  chmod 750 "$cert_dir" 2>/dev/null || true
  if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then
    local _acme_tmp_home="${LANDING_BASE}/.acme-home"
    mkdir -p "${_acme_tmp_home}" "${ACME_HOME}"
    local _acme_url="https://github.com/acmesh-official/acme.sh/archive/refs/tags/3.0.8.tar.gz"
    local _acme_hash="51f4f9580e91b038a7dd0207631bf9b1be0aab6a0094d0a3cbb4b21cd86f71df"
    local _acme_tarball="${_acme_tmp_home}/acme.sh-3.0.8.tar.gz"
    wget --timeout=15 --tries=3 -O "${_acme_tarball}" "${_acme_url}" \
      || die "acme.sh 归档下载失败（网络错误或 GitHub 不可达）"
    echo "${_acme_hash}  ${_acme_tarball}" | sha256sum -c --status \
      || die "acme.sh 归档 sha256 校验失败（文件损坏或被篡改）"
    tar -xzf "${_acme_tarball}" -C "${_acme_tmp_home}" \
      || die "acme.sh 归档解压失败"
    local _acme_src_dir="${_acme_tmp_home}/acme.sh-3.0.8"
    if [[ ! -f "${_acme_src_dir}/acme.sh" ]]; then
      rm -rf "${_acme_tmp_home}"
      die "acme.sh 归档结构异常，解压后未找到 acme.sh"
    fi
    env noprofile=1 HOME="${ACME_HOME}" sh "${_acme_src_dir}/acme.sh" --install \
      || die "acme.sh 安装失败"
    rm -rf "${_acme_tmp_home}" 2>/dev/null || true
    [[ -f "${ACME_HOME}/acme.sh" ]]       || die "acme.sh 安装后在 ${ACME_HOME} 未找到 acme.sh，请检查安装器是否支持 --home"
    [[ -f "${ACME_HOME}/dnsapi/dns_cf.sh" ]]       || die "acme.sh 安装后缺少 dns_cf.sh 插件，请检查: ls ${ACME_HOME}/dnsapi/"
    env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh"       --set-default-ca --server letsencrypt 2>/dev/null       || warn "set-default-ca letsencrypt 失败（acme.sh 版本过旧？），将使用默认 CA，建议升级 acme.sh"
    "${ACME_HOME}/acme.sh" --upgrade --auto-upgrade 2>/dev/null || true
  fi
  export PATH="${ACME_HOME}:${PATH}"

  info "申请证书（DNS-01/Cloudflare）: ${domain} ..."

_wait_dns_txt(){
    local _d="$1" _max=120 _step=20 _elapsed=0
    trap 'echo ""; warn "DNS 等待被中断（请等待传播完成后再试）"; trap - INT TERM; return 1' INT TERM
    info "等待 DNS TXT 传播（主动探测 _acme-challenge.${_d}，最长 ${_max}s）..."
    while (( _elapsed < _max )); do
      if dig +short +time=3 +tries=1 TXT "_acme-challenge.${_d}" 2>/dev/null | sed '/^$/d' | grep -q .; then
        printf '\n%s\n' "${GREEN}[OK]${NC}    DNS TXT 已检测到，继续申请证书..."
        trap - INT TERM
        return 0
      fi
      local _i=$_step
      while (( _i > 0 )); do
        printf '\r%s %ds 后继续（已等 %ds / 共 %ds）' "${CYAN}[INFO]${NC}  等待 DNS 传播中..." "$_i" "$_elapsed" "$_max"
        sleep 1
        (( _i-- )) || true
      done
      _elapsed=$(( _elapsed + _step ))
    done
    printf '\n'
    warn "DNS 传播等待超时（${_max}s），acme.sh 将自行处理"
    trap - INT TERM
    return 1
}
rm -rf "${ACME_HOME}/${domain}_ecc" 2>/dev/null || true
local issued=0
for try in 1 2; do
    local _force_opt=""
    (( try > 1 )) && _force_opt="--force"
    (( try == 1 )) && ! _wait_dns_txt "$domain" && die "DNS TXT 记录在 120 秒内未传播，终止证书申请（请等待后重试）"
    CF_Token="$cf_token" "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --issue --dns dns_cf \
      --domain "$domain" --keylength ec-256 \
      --server letsencrypt \
      ${_force_opt} && issued=1 && break || true
    if (( try < 2 )); then
      warn "第 ${try} 次申请失败，等待 DNS 传播后重试..."
      _wait_dns_txt "$domain"
    fi
  done
  (( issued )) || die "证书申请失败（请检查 Token 权限：Zone:DNS:Edit，或 3 分钟后重试）"

  _write_cert_reload_script

  local _old_umask; _old_umask=$(umask)
  umask 077
  if ! "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" \
    --install-cert --domain "$domain" --ecc \
    --cert-file      "${cert_dir}/cert.pem" \
    --key-file       "${cert_dir}/key.pem" \
    --fullchain-file "${cert_dir}/fullchain.pem" \
    --reloadcmd      "${CERT_RELOAD_SCRIPT} '${cert_dir}'"; then
    umask "${_old_umask}"
    die "证书部署失败"
  fi
  umask "${_old_umask}"

  chown -R "${LANDING_USER}:${LANDING_USER}" "${LANDING_BASE}" 2>/dev/null || \
    chown -R root:"${LANDING_USER}" "${LANDING_BASE}"
  chmod 750 "$cert_dir"
  chmod 644 "${cert_dir}/cert.pem" "${cert_dir}/fullchain.pem"
  chmod 640 "${cert_dir}/key.pem"
  # config.json 也需要对 xray-landing 可读
  [[ -f "$LANDING_CONF" ]] && chmod 640 "$LANDING_CONF" 2>/dev/null || true
  success "证书部署完成（LANDING_BASE 权限已归 ${LANDING_USER}，key.pem=640）"

  info "配置证书自动续期 cron ..."
  rm -f /etc/cron.d/acme-xray-landing 2>/dev/null || true
  env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
  env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --install-cronjob \
    || die "acme.sh --install-cronjob 失败！续期链路断开，请检查 crontab 权限后重试"
  crontab -l 2>/dev/null \
    | sed "s|${HOME}/.acme.sh/acme.sh|${ACME_HOME}/acme.sh|g" \
    | crontab - 2>/dev/null || true
  if ! crontab -l 2>/dev/null | grep -qF "${ACME_HOME}/acme.sh"; then
    die "acme.sh cron 条目验收失败（未指向 ${ACME_HOME}/acme.sh），请手动执行: ${ACME_HOME}/acme.sh --install-cronjob"
  fi
  success "证书自动续期已配置并验收通过（acme.sh 原生 crontab）"

  atomic_write "/etc/cron.daily/xray-cert-monitor" 755 root:root <<'MEOF'
#!/bin/sh
if [ ! -x "/usr/local/bin/xray-landing-cert-reload.sh" ]; then
  logger -t xray-cert-monitor "FATAL: reload script missing; renewals will fail"
  echo "$(date '+%Y-%m-%d %H:%M:%S') FATAL: reload script missing" >> /var/log/acme-xray-landing-renew.log 2>/dev/null || true
  exit 1
fi

# 先清除旧告警（正常情况）
rm -f /etc/profile.d/xray-cert-alert.sh 2>/dev/null || true

_any_expiring=0
for c in /etc/xray-landing/certs/*/fullchain.pem; do
  [ -f "$c" ] || continue
  dom=$(echo "$c" | sed 's|/etc/xray-landing/certs/\(.*\)/fullchain.pem|\1|')
  if ! openssl x509 -checkend 604800 -noout -in "$c" 2>/dev/null; then
    msg="FATAL: 证书 ${dom} 将在7天内过期，续期链路可能失效！请检查 acme cron 并手动续期"
    logger -t xray-cert-monitor "$msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> /var/log/acme-xray-landing-renew.log || true
    _any_expiring=1
    /bin/systemctl reset-failed xray-landing.service 2>/dev/null || true
  fi
done

if [ "$_any_expiring" = "1" ]; then
  cat > /etc/profile.d/xray-cert-alert.sh << 'ALERT_EOF'
echo -e '\033[0;31m================================================================\033[0m'
echo -e '\033[0;31m[FATAL] xray-landing: 证书将在7天内过期，续期链路可能已断！\033[0m'
echo -e '\033[0;31m  请检查: cat /var/log/acme-xray-landing-renew.log\033[0m'
echo -e '\033[0;31m  并手动续期后删除此告警: rm /etc/profile.d/xray-cert-alert.sh\033[0m'
echo -e '\033[0;31m================================================================\033[0m'
ALERT_EOF
  chmod +x /etc/profile.d/xray-cert-alert.sh || true
fi

find /etc/xray-landing/acme -name "*.csr" -mtime +7 -delete 2>/dev/null || true
find /etc/xray-landing/acme -name "*.conf.bak" -mtime +7 -delete 2>/dev/null || true
find /etc/xray-landing/acme -name "*.key" -mtime +7 ! -name "account.key" -delete 2>/dev/null || true

find /etc/xray-landing/acme -mindepth 1 -maxdepth 1 -type d -name "*_ecc" \
  -exec sh -c 'for d; do [ -f "$d/fullchain.cer" ] || rm -rf "$d"; done' _ {} + 2>/dev/null || true
MEOF
}

sync_xray_config(){
  info "同步 Xray 配置（5协议单端口回落）..."
  _validate_internal_ports_in_use
  load_manager_config
  if [[ "${VLESS_GRPC_PORT:-0}" == "0" ]]; then
    local _base
    _base=$(python3 -c "import random; b=random.randint(21000,29000)&~3; print(b)")
    VLESS_GRPC_PORT="$_base"
    TROJAN_GRPC_PORT=$(( _base + 1 ))
    VLESS_WS_PORT=$(( _base + 2 ))
    TROJAN_TCP_PORT=$(( _base + 3 ))
    save_manager_config
    info "内部端口已在 bash 层生成并写入 manager.conf（真相源优先，不读 config.json）"
  fi
  mkdir -p "$LANDING_BASE"
  local py_exit=0
  (
    export _NODES_DIR="${MANAGER_BASE}/nodes"
    export _CERT_BASE="$CERT_BASE"
    export _LOG_DIR="$LANDING_LOG"
    export _CFG_OUT="$LANDING_CONF"
    export _LANDING_PORT="$LANDING_PORT"
    export _VLESS_UUID="$VLESS_UUID"
    for _p in "$VLESS_GRPC_PORT" "$TROJAN_GRPC_PORT" "$VLESS_WS_PORT" "$TROJAN_TCP_PORT"; do
      [[ "$_p" =~ ^[0-9]+$ ]] || die "内部端口 '$_p' 非数字（manager.conf 损坏），拒绝启动"
    done
    export _VLESS_GRPC_PORT="$VLESS_GRPC_PORT"
    export _TROJAN_GRPC_PORT="$TROJAN_GRPC_PORT"
    export _VLESS_WS_PORT="$VLESS_WS_PORT"
    export _TROJAN_TCP_PORT="$TROJAN_TCP_PORT"
    export _BIND_IP="$BIND_IP"
    python3 - <<'PYEOF'
import json, os, glob, uuid as _uuid, random as _rand

nodes_dir    = os.environ['_NODES_DIR']
cert_base    = os.environ['_CERT_BASE']
log_dir      = os.environ['_LOG_DIR']
out_path     = os.environ['_CFG_OUT']
bind_ip      = os.environ.get('_BIND_IP', '0.0.0.0')
def safe_int(val, fallback=0):
    try:
        return int(val) if val and val.strip() else fallback
    except (ValueError, TypeError):
        return fallback
landing_port = safe_int(os.environ.get('_LANDING_PORT', '8443'), 8443)
vless_uuid   = os.environ.get('_VLESS_UUID', '') or str(_uuid.uuid4())

_vg = safe_int(os.environ.get('_VLESS_GRPC_PORT', '0'))
_tg = safe_int(os.environ.get('_TROJAN_GRPC_PORT', '0'))
_vw = safe_int(os.environ.get('_VLESS_WS_PORT', '0'))
_tt = safe_int(os.environ.get('_TROJAN_TCP_PORT', '0'))
if _vg == 0 and _tg == 0 and _vw == 0 and _tt == 0:
    _base = _rand.randint(21000, 29000) & ~3
    _vg, _tg, _vw, _tt = _base, _base+1, _base+2, _base+3

trojan_clients = []
certs_dict     = {}
seen_domains   = set()

for path in sorted(glob.glob(os.path.join(nodes_dir, '*.conf'))):
    if os.path.getsize(path) == 0:
        raise ValueError(f"Zero-byte node file detected: {path}")
    try:
        file_content = Path(path).read_text(encoding='utf-8', errors='strict').strip()
        if not file_content or file_content.startswith('#'):
            raise ValueError(f"Node file contains no valid data: {path}")
    except OSError as e:
        raise ValueError(f"Cannot read node file {path}: {e}")
    dom = pwd = ''
    try:
        for line in open(path, encoding='utf-8', errors='strict'):
            line = line.strip()
            if line.startswith('DOMAIN='):   dom = line[7:]
            if line.startswith('PASSWORD='): pwd = line[9:]
    except OSError as e:
        raise ValueError(f"Cannot read node file {path}: {e}")
    if not dom or not pwd:
        raise ValueError(f"Corrupted node state in {path}: DOMAIN or PASSWORD missing")
    from pathlib import Path
    cert_fullchain = f"{cert_base}/{dom}/fullchain.pem"
    cert_key       = f"{cert_base}/{dom}/key.pem"
    if not Path(cert_fullchain).exists() or not Path(cert_key).exists():
        print(f"  [WARN] 域名 {dom} 证书文件不存在，跳过", flush=True)
        continue
    if dom not in certs_dict:
        certs_dict[dom] = {"certificateFile": cert_fullchain, "keyFile": cert_key}
    if dom not in seen_domains:
        seen_domains.add(dom)
        trojan_clients.append({"password": pwd, "level": 0, "email": f"user@{dom}"})

if not trojan_clients:
    import sys
    print("  [WARN] 节点文件为空或证书均缺失，跳过配置同步")
    sys.exit(1)

PORT_VLESS_GRPC  = _vg
PORT_TROJAN_GRPC = _tg
PORT_VLESS_WS    = _vw
PORT_TROJAN_TCP  = _tt
PORT_FALLBACK    = 45231
PORT_FALLBACK_H2 = 45232
PFX = vless_uuid[:8]

# 不再需要显式 cipher 列表

tls_settings = {
    "minVersion": "1.2",
    "alpn": ["h2", "http/1.1", "http/1.0"],
    "rejectUnknownSni": True,
    "certificates": list(certs_dict.values())
}

cfg = {
    # 查看方式: journalctl -u xray-landing.service -f
    "log": {"access": "none", "error": "none", "loglevel": "warning"},
    "inbounds": [
        {
            "listen": bind_ip, "port": landing_port, "protocol": "vless",
            "settings": {
                "clients": [{"id": vless_uuid, "flow": "xtls-rprx-vision", "level": 0, "email": "vless-vision@main"}],
                "decryption": "none",
                "fallbacks": [
                    {"alpn": "h2", "dest": PORT_VLESS_GRPC,  "xver": 0},
                    {"alpn": "http/1.1", "path": f"/{PFX}-vw", "dest": PORT_VLESS_WS, "xver": 0},
                    {"dest": PORT_TROJAN_TCP, "xver": 0}
                ]
            },
            "streamSettings": {"network": "tcp", "security": "tls", "tlsSettings": tls_settings},
            "sniffing": {"enabled": True, "routeOnly": True, "destOverride": ["http", "tls"]}
        },
        {
            "listen": "127.0.0.1", "port": PORT_VLESS_GRPC, "protocol": "vless",
            "settings": {"clients": [{"id": vless_uuid, "level": 0, "email": "vless-grpc@inner"}], "decryption": "none", "fallbacks": [{"dest": PORT_FALLBACK_H2, "xver": 0}]},
            "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": f"{PFX}-vg"}},
            "sniffing": {"enabled": False}
        },
        {
            "listen": "127.0.0.1", "port": PORT_TROJAN_GRPC, "protocol": "trojan",
            "settings": {"clients": trojan_clients, "fallbacks": [{"dest": PORT_FALLBACK, "xver": 0}]},
            "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": f"{PFX}-tg"}},
            "sniffing": {"enabled": False}
        },
        {
            "listen": "127.0.0.1", "port": PORT_VLESS_WS, "protocol": "vless",
            "settings": {"clients": [{"id": vless_uuid, "level": 0, "email": "vless-ws@inner"}], "decryption": "none"},
            "streamSettings": {"network": "ws", "wsSettings": {"path": f"/{PFX}-vw"}, "acceptProxyProtocol": False},
            "sniffing": {"enabled": False}
        },
        {
            "listen": "127.0.0.1", "port": PORT_TROJAN_TCP, "protocol": "trojan",
            "settings": {"clients": trojan_clients, "fallbacks": [{"dest": PORT_FALLBACK, "xver": 0}]},
            "streamSettings": {"network": "tcp", "acceptProxyProtocol": False},
            "sniffing": {"enabled": False}
        }
    ],
    "dns": {
        "servers": ["https+local://1.1.1.1/dns-query", "https+local://8.8.8.8/dns-query", "localhost"],
        "queryStrategy": "UseIP"
    },
    "outbounds": [
        {"protocol": "dns", "tag": "dns-out", "settings": {"address": "1.1.1.1", "port": 53}},
        {"protocol": "freedom", "tag": "direct", "settings": {"domainStrategy": "UseIP"}},
        {"protocol": "blackhole", "tag": "blocked", "settings": {"response": {"type": "none"}}}
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked"},
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
            {"type": "field", "port": "25", "outboundTag": "blocked"},
            {"type": "field", "port": "53", "network": "udp,tcp", "outboundTag": "dns-out"}
        ]
    },
    "policy": {
        "levels": {"0": {"handshakeTimeout": 4,
                         "connIdle": 300,  # 5 min
                         "uplinkOnly": 2, "downlinkOnly": 5, "bufferSize": 256}},
        "system": {"statsInboundUplink": False, "statsInboundDownlink": False}
    }
}

tmp = os.path.join(os.path.dirname(out_path), '.xray-landing.config.tmp')
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
os.replace(tmp, out_path)
print(f"  [OK] {len(trojan_clients)} Trojan 客户端（去重后）, {len(certs_dict)} 证书, VLESS: {vless_uuid[:8]}...")
PYEOF
  ) || py_exit=$?
  [[ $py_exit -eq 0 ]] || die "sync_xray_config 失败（Python 退出码: $py_exit）——节点文件为空或证书缺失"
  chown -R root:"$LANDING_USER" "$LANDING_BASE" \
    || die "sync_xray_config: chown LANDING_BASE failed — Xray may not be able to read config/certs"
  chmod 750 "$LANDING_BASE"
  chmod 640 "$LANDING_CONF"
  success "Xray 配置同步完成: ${LANDING_CONF}"
}

write_logrotate(){
  atomic_write "$LOGROTATE_FILE" 644 root:root <<LREOF
/var/log/acme-xray-landing-renew.log {
    su root root
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}

# rotate it so disk pressure does not accumulate silently.
${LANDING_LOG}/*.log {
    su xray-landing xray-landing
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    create 0640 xray-landing xray-landing
}
LREOF
  local _jd_conf="/etc/systemd/journald.conf.d/xray-landing.conf"
  mkdir -p "/etc/systemd/journald.conf.d"
  if ! grep -q 'SystemMaxUse=200M' "$_jd_conf" 2>/dev/null; then
    atomic_write "$_jd_conf" 644 root:root <<'JDEOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
JDEOF
    systemctl restart systemd-journald 2>/dev/null || true
  fi
}

create_systemd_service(){
  mkdir -p "${MANAGER_BASE}/tmp"
  local _svc_tmp; _svc_tmp=$(mktemp "${MANAGER_BASE}/tmp/.xray-landing.svc.XXXXXX") \
    || die "mktemp _svc_tmp failed — MANAGER_BASE/tmp missing or disk full"
  cat > "$_svc_tmp" <<'SVCEOF'
[Unit]
Description=Xray Landing Node (independent from mack-a)
After=network.target nss-lookup.target
StartLimitIntervalSec=900
StartLimitBurst=10
OnFailure=xray-landing-recovery.service

[Service]
Type=simple
User=@@LANDING_USER@@
NoNewPrivileges=true
ExecStartPre=/bin/sh -c 'test -f @@LANDING_CONF@@ || { echo "config.json missing"; exit 1; }'
ExecStartPre=/bin/sh -c 'python3 -c "import json,sys; json.load(open(sys.argv[1]))" @@LANDING_CONF@@ 2>/dev/null || { echo "config.json invalid JSON"; exit 1; }'
ExecStartPre=/bin/sh -c 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); vision=[i for i in d[\"inbounds\"] if \"flow\" in str(i.get(\"settings\",{}).get(\"clients\",[{}])[0])]; sys.exit(1 if any(i.get(\"settings\",{}).get(\"mux\",{}).get(\"enabled\") for i in vision) else 0)" @@LANDING_CONF@@ 2>/dev/null || { echo "Vision inbound has mux enabled (unsupported with flow=xtls-rprx-vision)"; exit 1; }'
@@CAP_LINE@@
@@CAP_BOUND@@
ExecStart=@@LANDING_BIN@@ run -config @@LANDING_CONF@@
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray-landing
Restart=on-failure
RestartSec=15s
LimitNOFILE=@@LIMIT_NOFILE@@
LimitNPROC=65535
TasksMax=infinity
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=@@LANDING_BASE@@ /usr/local/share/xray-landing
LogsDirectory=xray-landing
PrivateTmp=true
PrivateDevices=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ProtectClock=true
LockPersonality=true
UMask=0027
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

  local _svc_ram_mb; _svc_ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _svc_ram_mb=${_svc_ram_mb:-1024}
  local _svc_fd=$(( _svc_ram_mb * 800 ))
  (( _svc_fd < 524288 ))   && _svc_fd=524288
  (( _svc_fd > 10485760 )) && _svc_fd=10485760

  local _cap_escaped="" _cap_bound_escaped=""
  (( LANDING_PORT < 1024 )) && {
    _cap_escaped="AmbientCapabilities=CAP_NET_BIND_SERVICE"
    _cap_bound_escaped="CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
  }
  sed -i \
    -e "s|@@LANDING_USER@@|${LANDING_USER}|g" \
    -e "s|@@LANDING_CONF@@|${LANDING_CONF}|g" \
    -e "s|@@LANDING_BIN@@|${LANDING_BIN}|g" \
    -e "s|@@LANDING_BASE@@|${LANDING_BASE}|g" \
    -e "s|@@CERT_BASE@@|${CERT_BASE}|g" \
    -e "s|@@LANDING_LOG@@|${LANDING_LOG}|g" \
    -e "s|@@CAP_LINE@@|${_cap_escaped}|g" \
    -e "s|@@CAP_BOUND@@|${_cap_bound_escaped}|g" \
    -e "s|@@LIMIT_NOFILE@@|${_svc_fd}|g" \
    "$_svc_tmp"
  mv -f "$_svc_tmp" "/etc/systemd/system/${LANDING_SVC}"
  chmod 644 "/etc/systemd/system/${LANDING_SVC}"
  sed -i 's|ReadOnlyPaths=|ReadOnlyPaths='"${CERT_BASE}"' |' "/etc/systemd/system/${LANDING_SVC}"
  local _xray_svc_d="/etc/systemd/system/xray-landing.service.d"
  mkdir -p "$_xray_svc_d"
  atomic_write "${_xray_svc_d}/xray-landing-limits.conf" 644 root:root <<XRAYLIMITS
[Service]
LimitNOFILE=${_svc_fd}
TasksMax=infinity
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
XRAYLIMITS

  atomic_write "/etc/systemd/system/xray-landing-recovery.service" 644 root:root <<'RECEOF'
[Unit]
Description=Xray Landing Recovery (preflight-gated auto-restart)
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/sh -c '\
  _lockdir="/run/lock"; \
  mkdir -p "$_lockdir" 2>/dev/null || true; \
  _lockfile="$_lockdir/xray-landing-recovery.lock"; \
  _tsfile="$_lockdir/xray-landing-recovery.last"; \
  ( \
    flock -n 9 || { logger -t xray-landing-recovery "INFO: recovery already running, skipping."; exit 0; }; \
    _now=$(date +%s); \
    if [ -f "$_tsfile" ]; then \
      _last=$(cat "$_tsfile" 2>/dev/null || echo 0); \
      _delta=$((_now - _last)); \
      if [ "$_delta" -lt 1800 ]; then \
        logger -t xray-landing-recovery "FATAL: Recovery rate-limited (loop detected, $_delta s since last attempt). Manual intervention required."; \
        echo "$(date) [FATAL] recovery loop detected ($_delta s interval). Fix root cause then: systemctl reset-failed @@LANDING_SVC@@ && systemctl start @@LANDING_SVC@@" >> @@LANDING_LOG@@/error.log 2>/dev/null || true; \
        echo "echo -e \\x27\033[0;31m[FATAL] xray-landing recovery loop: manual intervention required!\033[0m\\x27" > /etc/profile.d/xray-recovery-alert.sh || true; \
        chmod +x /etc/profile.d/xray-recovery-alert.sh 2>/dev/null || true; \
        exit 0; \
      fi; \
    fi; \
    echo "$_now" > "$_tsfile"; \
    logger -t xray-landing-recovery "WARN: StartLimitBurst hit, running preflight..."; \
    _cert_ok=0; _cfg_ok=0; \
    for d in @@CERT_BASE@@/*/fullchain.pem; do [ -f "$d" ] && _cert_ok=1 && break; done; \
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" @@LANDING_CONF@@ 2>/dev/null && _cfg_ok=1 || true; \
    if [ "$_cert_ok" = "1" ] && [ "$_cfg_ok" = "1" ]; then \
      logger -t xray-landing-recovery "Preflight PASSED — reset-failed and restart"; \
      systemctl reset-failed @@LANDING_SVC@@ 2>/dev/null || true; \
      systemctl start @@LANDING_SVC@@ 2>/dev/null || true; \
      rm -f /etc/profile.d/xray-recovery-alert.sh 2>/dev/null || true; \
    else \
      logger -t xray-landing-recovery "Preflight FAILED (cert=$_cert_ok cfg=$_cfg_ok) — manual intervention required"; \
      echo "$(date) [FATAL] preflight failed: cert=$_cert_ok cfg=$_cfg_ok. Fix then: systemctl reset-failed @@LANDING_SVC@@ && systemctl start @@LANDING_SVC@@" >> @@LANDING_LOG@@/error.log 2>/dev/null || true; \
      echo "echo -e \\x27\033[0;31m[FATAL] xray-landing 熔断，预检失败，需人工介入！\033[0m\\x27" > /etc/profile.d/xray-recovery-alert.sh || true; \
      chmod +x /etc/profile.d/xray-recovery-alert.sh 2>/dev/null || true; \
    fi \
  ) 9>"$_lockfile" \
'
RECEOF
  sed -i     -e "s|@@LANDING_SVC@@|${LANDING_SVC}|g"     -e "s|@@LANDING_CONF@@|${LANDING_CONF}|g"     -e "s|@@LANDING_LOG@@|${LANDING_LOG}|g"     -e "s|@@CERT_BASE@@|${CERT_BASE}|g"     "/etc/systemd/system/xray-landing-recovery.service"

  write_logrotate
  systemctl daemon-reload \
    || die "daemon-reload 失败，systemd 图未更新"
  systemctl enable "$LANDING_SVC"
  systemctl restart "$LANDING_SVC"
  sleep 2
  if systemctl is-active --quiet "$LANDING_SVC"; then
    success "服务 ${LANDING_SVC} 已启动"
  else
    journalctl -u "$LANDING_SVC" --no-pager -n 30
    warn "服务启动失败，回滚 unit 和 logrotate..."
    systemctl disable --now "$LANDING_SVC" 2>/dev/null || true
    rm -f "/etc/systemd/system/${LANDING_SVC}" \
          "/etc/systemd/system/xray-landing-recovery.service" \
          "$LOGROTATE_FILE" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    die "服务启动失败，unit/logrotate 已清除，可安全重跑安装"
  fi
}

setup_firewall(){
  load_manager_config
  info "重建防火墙 Chain ${FW_CHAIN}（蓝绿原子切换）..."
  local ssh_port; ssh_port="$(detect_ssh_port)"

  local FW_TMP="${FW_CHAIN}-NEW"
  local FW_TMP6="${FW_CHAIN6}-NEW"

  _bulldoze_input_refs(){
    local _chain="$1" _lines _n
    mapfile -t _lines < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$_chain" '$2==c {print $1}' | sort -rn)
    for _n in "${_lines[@]}"; do
      iptables -w 2 -D INPUT "$_n" 2>/dev/null || true
    done
  }
  _bulldoze_input_refs6(){
    local _chain="$1" _lines _n
    mapfile -t _lines < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$_chain" '$2==c {print $1}' | sort -rn)
    for _n in "${_lines[@]}"; do
      ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true
    done
  }

  _bulldoze_input_refs  "$FW_CHAIN";  _bulldoze_input_refs  "$FW_TMP"
  iptables -w 2 -F "$FW_TMP"   2>/dev/null || true; iptables -w 2 -X "$FW_TMP"   2>/dev/null || true
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  if have_ipv6; then
    _bulldoze_input_refs6 "$FW_CHAIN6"; _bulldoze_input_refs6 "$FW_TMP6"
    ip6tables -w 2 -F "$FW_TMP6"   2>/dev/null || true; ip6tables -w 2 -X "$FW_TMP6"   2>/dev/null || true
    ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
  fi
  local _prev_err_trap _prev_int_trap _prev_term_trap
  _prev_err_trap=$(trap -p ERR || true)
  _prev_int_trap=$(trap -p INT || true)
  _prev_term_trap=$(trap -p TERM || true)
  _fw_landing_rollback(){
    iptables -w 2  -D INPUT -m comment --comment "xray-landing-swap"    2>/dev/null || true
    iptables -w 2  -F "$FW_TMP"  2>/dev/null || true
    iptables -w 2  -X "$FW_TMP"  2>/dev/null || true
    ip6tables -w 2 -D INPUT -m comment --comment "xray-landing-v6-swap" 2>/dev/null || true
    ip6tables -w 2 -F "$FW_TMP6" 2>/dev/null || true
    ip6tables -w 2 -X "$FW_TMP6" 2>/dev/null || true
    while iptables -w 2 -D INPUT -m comment --comment "xray-landing-jump" 2>/dev/null; do :; done
    while ip6tables -w 2 -D INPUT -m comment --comment "xray-landing-v6-jump" 2>/dev/null; do :; done
    while iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null; do :; done
    while ip6tables -w 2 -D INPUT -j "$FW_CHAIN6" 2>/dev/null; do :; done
  }
  _restore_prev_fw_traps(){
    eval "${_prev_err_trap:-trap - ERR}"
    eval "${_prev_int_trap:-trap - INT}"
    eval "${_prev_term_trap:-trap - TERM}"
  }
  trap '_fw_landing_rollback; exit 130' INT TERM ERR
  local _conf_files=()
  while IFS= read -r f; do _conf_files+=("$f"); done     < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f 2>/dev/null | sort)
  local expected_count=${#_conf_files[@]} skipped=0 tips=()
  for meta in "${_conf_files[@]+${_conf_files[@]}}"; do
    [[ -f "$meta" ]] || continue
    local tip; tip=$(grep '^TRANSIT_IP=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}')
    if [[ -z "$tip" ]]; then
      warn "  [跳过] 节点文件 ${meta} 缺少 TRANSIT_IP 字段"; (( ++skipped )) || true; continue
    fi
    if ! printf '%s' "$tip" | timeout 5 python3 -c "import ipaddress,sys; ipaddress.IPv4Address(sys.stdin.read().strip())" 2>/dev/null; then
      warn "  [跳过] 节点文件 ${meta} TRANSIT_IP='${tip}' 格式非法或 Python 无响应"; (( ++skipped )) || true; continue
    fi
    tips+=("$tip")
  done
  if (( skipped > 0 )); then
    die "防火墙构建中止：${skipped} 个节点文件格式异常，拒绝生成可能放行不足的规则集（预期 ${#_conf_files[@]}，有效 $(( ${#_conf_files[@]} - skipped ))）"
  fi
  local _seen_ips=() _dup_found=0
  for _tip in "${tips[@]}"; do
    for _seen in "${_seen_ips[@]}"; do
      if [[ "$_seen" == "$_tip" ]]; then
        warn "检测到重复的中转IP: $_tip（多个域名共享同一中转机，正常）"
        _dup_found=1
        break
      fi
    done
    _seen_ips+=("$_tip")
  done
  # Now safe to start iptables operations
  iptables -w 2 -N "$FW_TMP" 2>/dev/null || iptables -w 2 -F "$FW_TMP"
  iptables -w 2 -A "$FW_TMP" -i lo                                       -m comment --comment "xray-landing-lo"        -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$ssh_port"                 -m comment --comment "xray-landing-ssh"       -j ACCEPT
  local count=0
  while IFS= read -r tip; do
    [[ -n "$tip" ]] || continue
    validate_ipv4 "$tip"
    iptables -w 2 -A "$FW_TMP" -s "${tip}/32" -p tcp --dport "$LANDING_PORT" -m comment --comment "xray-landing-transit" -j ACCEPT \
      || { iptables -w 2 -F "$FW_TMP" 2>/dev/null || true; iptables -w 2 -X "$FW_TMP" 2>/dev/null || true; die "防火墙规则添加失败（中转IP ${tip}），已清理临时链"; }
    info "  ACCEPT ← ${tip}/32:${LANDING_PORT}"; (( ++count )) || true
  done < <(printf '%s
' "${tips[@]+${tips[@]}}" | sort -u)
  iptables -w 2 -A "$FW_TMP" -m conntrack --ctstate INVALID,UNTRACKED    -m comment --comment "xray-landing-invalid"   -j DROP
  iptables -w 2 -A "$FW_TMP" -m conntrack --ctstate ESTABLISHED,RELATED  -m comment --comment "xray-landing-est"       -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -p icmp --icmp-type echo-request -m limit --limit 10/second --limit-burst 20                                                                      -m comment --comment "xray-landing-icmp"      -j ACCEPT || true
  iptables -w 2 -A "$FW_TMP" -p icmp --icmp-type echo-request            -m comment --comment "xray-landing-icmp-drop" -j DROP
  iptables -w 2 -A "$FW_TMP" -m comment --comment "xray-landing-drop" -j DROP

  iptables -w 2 -I INPUT 1 -m comment --comment "xray-landing-swap" -j "$FW_TMP"
  _bulldoze_input_refs "$FW_CHAIN"
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  if ! iptables -w 2 -E "$FW_TMP" "$FW_CHAIN" 2>/dev/null; then
    _fw_landing_rollback; _restore_prev_fw_traps; die "Chain rename failed（FW_TMP→FW_CHAIN），防火墙交换失败"
  fi
  iptables -w 2 -I INPUT 1 -m comment --comment "xray-landing-jump" -j "$FW_CHAIN"
  while iptables -w 2 -D INPUT -m comment --comment "xray-landing-swap" 2>/dev/null; do :; done

  if have_ipv6; then
    ip6tables -w 2 -N "$FW_TMP6" 2>/dev/null || ip6tables -w 2 -F "$FW_TMP6"
    ip6tables -w 2 -A "$FW_TMP6" -i lo -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p tcp      --dport "$ssh_port"     -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -m conntrack --ctstate INVALID,UNTRACKED -j DROP
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type destination-unreachable -m comment --comment "xray-landing-icmp6" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type packet-too-big -m comment --comment "xray-landing-icmp6-pmtud" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type time-exceeded -m comment --comment "xray-landing-icmp6" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type parameter-problem -m comment --comment "xray-landing-icmp6" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type 133 -m comment --comment "xray-landing-icmp6-ndp" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type 134 -m comment --comment "xray-landing-icmp6-ndp" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type 135 -m comment --comment "xray-landing-icmp6-ndp" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type 136 -m comment --comment "xray-landing-icmp6-ndp" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment "xray-landing-icmp6" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type echo-request -m comment --comment "xray-landing-icmp6-drop" -j DROP
    ip6tables -w 2 -A "$FW_TMP6" -p tcp      --dport "$LANDING_PORT" -j DROP
    ip6tables -w 2 -A "$FW_TMP6" -j DROP
    ip6tables -w 2 -I INPUT 1 -m comment --comment "xray-landing-v6-swap" -j "$FW_TMP6"
    _bulldoze_input_refs6 "$FW_CHAIN6" || { _fw_landing_rollback; _restore_prev_fw_traps; die "IPv6 chain drain failed"; }
    ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
    if ! ip6tables -w 2 -E "$FW_TMP6" "$FW_CHAIN6" 2>/dev/null; then
      _fw_landing_rollback; _restore_prev_fw_traps; die "IPv6 chain rename failed（FW_TMP6→FW_CHAIN6）"
    fi
    if ! ip6tables -w 2 -I INPUT 1 -m comment --comment "xray-landing-v6-jump" -j "$FW_CHAIN6"; then
      _fw_landing_rollback; _restore_prev_fw_traps; die "IPv6 jump rule insertion failed"
    fi
    while ip6tables -w 2 -D INPUT -m comment --comment "xray-landing-v6-swap" 2>/dev/null; do :; done
  fi

  if ! _persist_iptables "$ssh_port"; then
    _bulldoze_input_refs "$FW_CHAIN"
    iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
    if have_ipv6; then
      _bulldoze_input_refs6 "$FW_CHAIN6"
      ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
    fi
    _fw_landing_rollback
    _restore_prev_fw_traps
    die "防火墙持久化失败（firewall-restore.sh/unit 写入异常），运行链已回滚"
  fi
  _restore_prev_fw_traps
  success "防火墙: chain ${FW_CHAIN}（SSH:${ssh_port} 蓝绿切换零裸奔）| ${count} 中转 IP | have_ipv6→${FW_CHAIN6}"
}

_persist_iptables(){
  local ssh_port="${1:-22}"
  mkdir -p "$MANAGER_BASE"
  local fw_script="${MANAGER_BASE}/firewall-restore.sh"
  local transit_ips=()
  while IFS= read -r meta; do
    [[ -f "$meta" ]] || continue
    local tip; tip=$(grep '^TRANSIT_IP=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || continue
    printf '%s' "$tip" | timeout 5 python3 -c "import ipaddress,sys; ipaddress.IPv4Address(sys.stdin.read().strip())" 2>/dev/null && transit_ips+=("$tip") || true
  done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f 2>/dev/null | sort)

  local _fw_sig="LANDING_FW_VERSION=${VERSION}_$(date +%Y%m%d)"
  local _transit_rules=""
  local _tip
  for _tip in "${transit_ips[@]+${transit_ips[@]}}"; do
    [[ -n "$_tip" ]] || continue
    _transit_rules+="iptables -w 2 -A __FW_CHAIN__-NEW -s ${_tip}/32 -p tcp --dport __LANDING_PORT__ -m comment --comment 'xray-landing-transit' -j ACCEPT"$'\n'
  done

  export FW_SIG="$_fw_sig" SSH_PORT_FALLBACK="$ssh_port" FW_CHAIN FW_CHAIN6 LANDING_PORT TRANSIT_RULES="$_transit_rules"
  python3 - <<'PY' | atomic_write "$fw_script" 700 root:root
from pathlib import Path
import os, sys

template = r"""#!/usr/bin/env bash
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERROR: Bash 4+ required"; exit 1; }
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
# __FW_SIG__
_detect_ssh(){
  local p=''
  p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"
  [ -z "$p" ] && p="$(ss -H -tlnp 2>/dev/null | awk '
    $1=="LISTEN" && /sshd/ {
      addr=$4
      sub(/^.*:/,"",addr)
      gsub(/^\[/,"",addr)
      gsub(/\]$/,"",addr)
      if (addr ~ /^[0-9]+$/) { print addr; exit }
    }' || true)"
  [ -z "$p" ] && p="$(grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk '{print $2}' | sort -n | head -1 || true)"
  if echo "$p" | grep -qE '^[0-9]+$' && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then
    echo "$p"
  else
    logger -t xray-landing-firewall "ERROR: 无法动态探测SSH端口，拒绝开机恢复（安全策略：禁止回退到可能过时的安装时端口）"
    exit 1
  fi
}
SSH_PORT="$(_detect_ssh)"
iptables -w 2 -N __FW_CHAIN__-NEW 2>/dev/null || true
iptables -w 2 -F __FW_CHAIN__-NEW 2>/dev/null || true
iptables -w 2 -A __FW_CHAIN__-NEW -i lo                                       -m comment --comment 'xray-landing-lo'        -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p tcp  --dport ${SSH_PORT}                -m comment --comment 'xray-landing-ssh'       -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -m conntrack --ctstate INVALID,UNTRACKED    -m comment --comment 'xray-landing-invalid'   -j DROP
iptables -w 2 -A __FW_CHAIN__-NEW -m conntrack --ctstate ESTABLISHED,RELATED  -m comment --comment 'xray-landing-est'       -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p icmp --icmp-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment 'xray-landing-icmp' -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p icmp --icmp-type echo-request             -m comment --comment 'xray-landing-icmp-drop' -j DROP
__TRANSIT_RULES__
iptables -w 2 -A __FW_CHAIN__-NEW -m comment --comment 'xray-landing-drop' -j DROP
_bulldoze_input_refs(){
    local _chain="$1" _lines _n
    mapfile -t _lines < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$_chain" '$2==c {print $1}' | sort -rn)
    for _n in "${_lines[@]}"; do iptables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
}
_bulldoze_input_refs6(){
    local _chain="$1" _lines _n
    mapfile -t _lines < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$_chain" '$2==c {print $1}' | sort -rn)
    for _n in "${_lines[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
}
_bulldoze_input_refs __FW_CHAIN__
_bulldoze_input_refs6 __FW_CHAIN6__
while iptables -w 2  -D INPUT -m comment --comment 'xray-landing-jump'       2>/dev/null; do :; done
while iptables -w 2  -D INPUT -m comment --comment 'xray-landing-ssh-global' 2>/dev/null; do :; done
while iptables -w 2  -D INPUT -m comment --comment 'xray-landing-swap'       2>/dev/null; do :; done
iptables -w 2 -F __FW_CHAIN__ 2>/dev/null || true
iptables -w 2 -X __FW_CHAIN__ 2>/dev/null || true
iptables -w 2 -E __FW_CHAIN__-NEW __FW_CHAIN__ 2>/dev/null || {
  iptables -w 2 -F __FW_CHAIN__-NEW 2>/dev/null || true
  iptables -w 2 -X __FW_CHAIN__-NEW 2>/dev/null || true
  exit 1
}
iptables -w 2 -I INPUT 1 -m comment --comment 'xray-landing-jump' -j __FW_CHAIN__
if [ -f /proc/net/if_inet6 ] && command -v ip6tables >/dev/null 2>&1 && ip6tables -nL >/dev/null 2>&1 && [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)" != "1" ]; then
  ip6tables -w 2 -N __FW_CHAIN6__-NEW 2>/dev/null || true
  ip6tables -w 2 -F __FW_CHAIN6__-NEW 2>/dev/null || true
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -i lo -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p tcp      --dport ${SSH_PORT}      -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type 133 -m comment --comment 'xray-landing-icmp6-ndp' -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type 134 -m comment --comment 'xray-landing-icmp6-ndp' -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type 135 -m comment --comment 'xray-landing-icmp6-ndp' -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type 136 -m comment --comment 'xray-landing-icmp6-ndp' -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment 'xray-landing-icmp6' -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type echo-request -m comment --comment 'xray-landing-icmp6-drop' -j DROP
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -j DROP
  while ip6tables -w 2 -D INPUT -m comment --comment 'xray-landing-v6-jump' 2>/dev/null; do :; done
  while ip6tables -w 2 -D INPUT -m comment --comment 'xray-landing-v6-swap' 2>/dev/null; do :; done
  ip6tables -w 2 -F __FW_CHAIN6__ 2>/dev/null || true
  ip6tables -w 2 -X __FW_CHAIN6__ 2>/dev/null || true
  ip6tables -w 2 -E __FW_CHAIN6__-NEW __FW_CHAIN6__ 2>/dev/null || {
    ip6tables -w 2 -F __FW_CHAIN6__-NEW 2>/dev/null || true
    ip6tables -w 2 -X __FW_CHAIN6__-NEW 2>/dev/null || true
    exit 1
  }
  ip6tables -w 2 -I INPUT 1 -m comment --comment 'xray-landing-v6-jump' -j __FW_CHAIN6__
fi
"""

template = template.replace("__FW_SIG__", os.environ["FW_SIG"])
template = template.replace("__SSH_PORT__", os.environ["SSH_PORT_FALLBACK"])
template = template.replace("__FW_CHAIN__", os.environ["FW_CHAIN"])
template = template.replace("__FW_CHAIN6__", os.environ["FW_CHAIN6"])
template = template.replace("__LANDING_PORT__", os.environ["LANDING_PORT"])
template = template.replace("__TRANSIT_RULES__", os.environ.get("TRANSIT_RULES", ""))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
sys.stdout.write(template)
PY
  local rsvc="/etc/systemd/system/xray-landing-iptables-restore.service"
  atomic_write "$rsvc" 644 root:root <<RSTO
[Unit]
Description=Restore iptables rules for xray-landing
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=${fw_script}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
RSTO
  systemctl daemon-reload     || die "daemon-reload 失败，systemd 图未更新"
  systemctl enable xray-landing-iptables-restore.service     || die "iptables 持久化服务 enable 失败，重启后防火墙规则将丢失"
  systemctl is-enabled --quiet xray-landing-iptables-restore.service     || die "iptables 持久化服务 enabled 状态验收失败"
  info "防火墙规则已写入: ${fw_script}（开机动态检测 SSH 端口，have_ipv6 守卫 ip6tables）"
}

save_node_info(){
  local domain="$1" password="$2" transit_ip="$3" pub_ip="$4"
  mkdir -p "${MANAGER_BASE}/nodes"
  local safe_domain; safe_domain=$(printf '%s' "$domain" | tr '.:/' '___')
  local safe_ip;     safe_ip=$(printf '%s' "$transit_ip" | tr '.:' '__')
  local _node_conf="${MANAGER_BASE}/nodes/${safe_domain}_${safe_ip}.conf"
  if [[ -f "$_node_conf" ]]; then
    local _exist_dom _exist_tip
    _exist_dom=$(grep '^DOMAIN=' "$_node_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    _exist_tip=$(grep '^TRANSIT_IP=' "$_node_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    if [[ -n "$_exist_dom" && "$_exist_dom" != "$domain" ]]; then
      die "节点文件名碰撞：${_node_conf} 已被域名 ${_exist_dom} 使用，拒绝覆盖 ${domain}"
    fi
    if [[ -n "$_exist_tip" && "$_exist_tip" != "$transit_ip" ]]; then
      die "节点文件名碰撞：${_node_conf} 已被中转 IP ${_exist_tip} 使用，拒绝覆盖 ${transit_ip}"
    fi
  fi
  atomic_write "$_node_conf" 600 root:root <<NEOF
DOMAIN=${domain}
PASSWORD=${password}
TRANSIT_IP=${transit_ip}
PUBLIC_IP=${pub_ip}
CREATED=$(date +%Y%m%d_%H%M%S)
NEOF
}

add_node(){
  load_manager_config
  _validate_internal_ports_in_use
  echo ""
  echo -e "${BOLD}── 增加新节点 ────────────────────────────────────────────────────${NC}"
  echo -e "${BOLD}${RED}  ⚠  域名在 Cloudflare 必须设为【仅DNS/灰云】，严禁开启小黄云代理！${NC}"
  echo ""
  read -rp "新节点域名: " NEW_DOMAIN
  NEW_DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$NEW_DOMAIN")")
  validate_domain "$NEW_DOMAIN"

  local existing_pass=""
  if [[ -d "${MANAGER_BASE}/nodes" ]]; then
    existing_pass=$(python3 - "${MANAGER_BASE}/nodes" "$NEW_DOMAIN" 2>/dev/null <<'PYNODE'
import sys
from pathlib import Path
nodes_dir, target_domain = Path(sys.argv[1]), sys.argv[2]
for p in nodes_dir.glob("*.conf"):
    if p.name.startswith("tmp-"):
        continue
    data = {}
    try:
        for line in p.read_text(encoding='utf-8', errors='strict').splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip()
    except UnicodeDecodeError:
        continue
    if data.get("DOMAIN") == target_domain and data.get("PASSWORD"):
        print(data["PASSWORD"])
        break
PYNODE
) || true
  fi
  if [[ -n "$existing_pass" ]]; then
    if [[ -n "${NEW_PASS:-}" && "$NEW_PASS" != "$existing_pass" ]]; then
      die "节点文件已存在但密码不一致（旧: ${existing_pass:0:8}...，新: ${NEW_PASS:0:8}...），请先删除旧节点或留空以沿用现有密码"
    fi
    warn "域名 ${NEW_DOMAIN} 已存在，新中转机必须复用相同 Trojan 密码"
    NEW_PASS="$existing_pass"
    info "  自动沿用密码: ${NEW_PASS}"
  else
    read -rp "Trojan 密码（16位以上，直接回车自动生成）: " NEW_PASS
    if [[ -z "$NEW_PASS" ]]; then
      NEW_PASS=$(gen_password)
      info "  已自动生成高强度密码: ${NEW_PASS}"
    fi
    validate_password "$NEW_PASS"
  fi

  read -rp "对应中转机公网 IP: " NEW_TRANSIT
  validate_ipv4 "$NEW_TRANSIT"

  local _fw_skip=0
  local _ip_exists
  _ip_exists=$(python3 - "${MANAGER_BASE}/nodes" "$NEW_TRANSIT" 2>/dev/null <<'PYIP'
import sys
from pathlib import Path
nodes_dir, target_ip = Path(sys.argv[1]), sys.argv[2]
for p in nodes_dir.glob("*.conf"):
    if p.name.startswith("tmp-"):
        continue
    try:
        for line in p.read_text(errors="replace").splitlines():
            if line.strip() == f"TRANSIT_IP={target_ip}":
                print("1")
                sys.exit(0)
    except Exception:
        continue
PYIP
) || true
  if [[ "${_ip_exists:-}" == "1" ]]; then
    warn "中转 IP ${NEW_TRANSIT} 已在防火墙白名单，跳过重复添加 iptables 规则（但仍继续证书申请和 Token 生成）"
    _fw_skip=1
  fi

  local USE_CF_TOKEN=""
  if [[ -z "$USE_CF_TOKEN" || "$USE_CF_TOKEN" == "***" ]]; then
    read -rp "Cloudflare API Token（Zone:DNS:Edit）: " USE_CF_TOKEN
    validate_cf_token "$USE_CF_TOKEN"
  fi
  CF_TOKEN="$USE_CF_TOKEN"

  _acquire_lock

  local _staged_mgr=""
  if [[ -n "$CF_TOKEN" ]]; then
    _staged_mgr=$(mktemp "${MANAGER_BASE}/tmp/.manager.XXXXXX") \
      || die "mktemp _staged_mgr failed"
    atomic_write "$_staged_mgr" 600 root:root <<SMEOF
LANDING_PORT=${LANDING_PORT}
VLESS_UUID=${VLESS_UUID}
VLESS_GRPC_PORT=${VLESS_GRPC_PORT}
TROJAN_GRPC_PORT=${TROJAN_GRPC_PORT}
VLESS_WS_PORT=${VLESS_WS_PORT}
TROJAN_TCP_PORT=${TROJAN_TCP_PORT}
CF_TOKEN=${CF_TOKEN}
CREATED_USER=${CREATED_USER}
SMEOF
  fi

  setup_fallback_decoy
  issue_certificate "$NEW_DOMAIN" "$USE_CF_TOKEN"
  local PUB_IP; PUB_IP=$(get_public_ip)

  local _safe_dom; _safe_dom=$(printf '%s' "$NEW_DOMAIN" | tr '.:/' '___')
  local _safe_ip;  _safe_ip=$(printf '%s' "$NEW_TRANSIT" | tr '.:' '__')
  local _node_conf="${MANAGER_BASE}/nodes/${_safe_dom}_${_safe_ip}.conf"

  local _tmp_node; _tmp_node=$(mktemp "${MANAGER_BASE}/nodes/tmp-XXXXXX.conf") \
    || die "mktemp _tmp_node failed — MANAGER_BASE/nodes missing or disk full"
  cat >"$_tmp_node" <<NEOF_TMP
DOMAIN=${NEW_DOMAIN}
PASSWORD=${NEW_PASS}
TRANSIT_IP=${NEW_TRANSIT}
PUBLIC_IP=${PUB_IP}
CREATED=$(date +%Y%m%d_%H%M%S)
NEOF_TMP
  chmod 600 "$_tmp_node"

  _acme_node_cleanup(){
    if [[ -f "${ACME_HOME}/acme.sh" && -n "${NEW_DOMAIN:-}" ]]; then
      local _refs
      _refs=$(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f \
        -exec grep -l "^DOMAIN=${NEW_DOMAIN}$" {} + 2>/dev/null | sed '/^$/d' | wc -l)
      if (( _refs == 0 )); then
        "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "${NEW_DOMAIN}" --ecc 2>/dev/null || true
        rm -rf "${CERT_BASE}/${NEW_DOMAIN}" 2>/dev/null || true
      else
        info "保留证书 ${NEW_DOMAIN}（仍被 ${_refs} 个节点引用）"
      fi
    fi
  }

  local _int_sync_done=0 _int_fw_done=0
  trap '
    _global_cleanup
    rm -f "$_tmp_node" "$_node_conf" "${_staged_mgr:-}" 2>/dev/null
    ((_int_sync_done)) && ( sync_xray_config ) 2>/dev/null || true
    ((_int_fw_done))   && ( setup_firewall )   2>/dev/null || true
    _acme_node_cleanup
    echo -e "\n${RED}[中断] 已回滚，请执行: bash $0 --uninstall${NC}"
    exit 1
  ' INT TERM

  if ! ( export _TMP_NODE_PATH="$_tmp_node"; sync_xray_config ); then
    rm -f "$_tmp_node"
    trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM
        _acme_node_cleanup
    rm -f "${_staged_mgr:-}" 2>/dev/null || true; _release_lock; die "Xray配置同步失败，节点未保存"
  fi
  _int_sync_done=1

  if [[ -f "$_node_conf" ]]; then
    local _exist_dom _exist_tip
    _exist_dom=$(grep '^DOMAIN=' "$_node_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    _exist_tip=$(grep '^TRANSIT_IP=' "$_node_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    if [[ -n "$_exist_dom" && "$_exist_dom" != "$NEW_DOMAIN" ]]; then
      rm -f "$_tmp_node"
      die "节点文件名碰撞：${_node_conf} 已被域名 ${_exist_dom} 使用，拒绝覆盖 ${NEW_DOMAIN}"
    fi
    if [[ -n "$_exist_tip" && "$_exist_tip" != "$NEW_TRANSIT" ]]; then
      rm -f "$_tmp_node"
      die "节点文件名碰撞：${_node_conf} 已被中转 IP ${_exist_tip} 使用，拒绝覆盖 ${NEW_TRANSIT}"
    fi
  fi
  local _snap_cfg_node; _snap_cfg_node=$(mktemp "${LANDING_BASE}/.snap-recover.XXXXXX" 2>/dev/null) \
    || die "mktemp _snap_cfg_node failed"
  [[ -n "$_snap_cfg_node" && -f "$LANDING_CONF" ]] && cp -f "$LANDING_CONF" "$_snap_cfg_node" 2>/dev/null || true
  mv -f "$_tmp_node" "$_node_conf"
  _int_sync_done=0
  trap '_global_cleanup; rm -f "$_node_conf" 2>/dev/null; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

  if (( _fw_skip == 0 )); then
    if ! ( setup_firewall ); then
      rm -f "$_node_conf"
      if [[ -n "$_snap_cfg_node" && -f "$_snap_cfg_node" ]]; then
        cp -f "$_snap_cfg_node" "$LANDING_CONF" 2>/dev/null || true
      else
        ( sync_xray_config ) 2>/dev/null || true
      fi
      rm -f "$_snap_cfg_node" 2>/dev/null || true
      trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM
      rm -f "${_staged_mgr:-}" 2>/dev/null || true
        _acme_node_cleanup
      _release_lock; die "防火墙配置失败，节点已回滚"
    fi
    _int_fw_done=1
  else
    info "TRANSIT_IP ${NEW_TRANSIT} 已在白名单，跳过防火墙重建（新域名节点仍正常添加）"
  fi
  trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

  systemctl restart "$LANDING_SVC"
  sleep 1
  if ! systemctl is-active --quiet "$LANDING_SVC"; then
    rm -f "$_node_conf"
    if [[ -n "$_snap_cfg_node" && -f "$_snap_cfg_node" ]]; then
      cp -f "$_snap_cfg_node" "$LANDING_CONF" 2>/dev/null || true
    else
      ( sync_xray_config ) 2>/dev/null || true
    fi
    ( setup_firewall ) 2>/dev/null || true
    rm -f "$_snap_cfg_node" 2>/dev/null || true
    rm -f "${_staged_mgr:-}" 2>/dev/null || true
        _acme_node_cleanup
    _release_lock; die "服务重启失败，节点已回滚: journalctl -u ${LANDING_SVC}"
  fi
  rm -f "$_snap_cfg_node" 2>/dev/null || true
  [[ -n "${_staged_mgr:-}" && -f "${_staged_mgr:-}" ]] \
    && mv -f "$_staged_mgr" "$MANAGER_CONFIG" 2>/dev/null || true
  _release_lock
  success "服务热重载成功（零掉线）"
  print_pairing_info "$PUB_IP" "$NEW_DOMAIN" "$NEW_PASS" "$NEW_TRANSIT"
}

delete_node(){
  echo ""
  echo -e "${BOLD}── 删除节点 ─────────────────────────────────────────────────────${NC}"
  local n=0 node_files=()
  while IFS= read -r meta; do
    [[ -f "$meta" ]] || continue
    node_files+=("$meta")
    local dom ip
    dom=$(grep '^DOMAIN='     "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    ip=$(grep  '^TRANSIT_IP=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    printf "  [%-2d] %-40s 中转: %s\n" $((++n)) "$dom" "$ip"
  done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | sort)

  (( n == 0 )) && { warn "无可删除的节点"; return; }
  (( n == 1 )) && die "仅剩最后一个节点！请使用「清除本系统所有数据」"

  read -rp "请输入节点编号: " DEL_INPUT
  [[ "$DEL_INPUT" =~ ^[0-9]+$ ]] || die "请输入数字"
  local idx=$(( DEL_INPUT - 1 ))
  (( idx >= 0 && idx < n )) || die "编号越界（共 ${n} 个）"

  local DEL_CONF="${node_files[$idx]}"
  local DEL_DOMAIN; DEL_DOMAIN=$(grep '^DOMAIN='     "$DEL_CONF" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}')
  local DEL_TRANSIT; DEL_TRANSIT=$(grep '^TRANSIT_IP=' "$DEL_CONF" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}')
  [[ -n "$DEL_DOMAIN" ]] || die "节点配置缺少 DOMAIN 字段"
  validate_domain "$DEL_DOMAIN"

  read -rp "确认删除 ${DEL_DOMAIN}（中转: ${DEL_TRANSIT}）？[y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "已取消"; return; }

  _acquire_lock

  local _snap_cfg_del=""
  [[ -f "$LANDING_CONF" ]] && {
    _snap_cfg_del=$(mktemp "${LANDING_BASE}/.snap-recover.XXXXXX") \
      || die "mktemp _snap_cfg_del failed"
    cp -f "$LANDING_CONF" "$_snap_cfg_del" \
      || die "snapshot LANDING_CONF failed"
  }

  # 五步原子变更
  local _snap_node; _snap_node=$(mktemp "${MANAGER_BASE}/nodes/.snap-recover.XXXXXX") \
    || die "mktemp _snap_node failed"
  cp -f "$DEL_CONF" "$_snap_node" \
    || die "snapshot DEL_CONF failed"
  mv -f "$DEL_CONF" "${DEL_CONF}.deleting"

  local __delete_node_trap_active=1
  _delete_node_rollback(){
    [[ "${__delete_node_trap_active:-0}" == "1" ]] || return 0
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    rm -f "$_snap_node" "${_snap_cfg_del:-}" 2>/dev/null || true
    __delete_node_trap_active=0
    _release_lock
    trap - INT TERM ERR
    exit 1
  }
  trap '_delete_node_rollback' INT TERM ERR

  local safe_del; safe_del=$(printf '%s' "$DEL_DOMAIN" | tr '.:/' '___')
  local remaining; remaining=$(find "${MANAGER_BASE}/nodes" -name "${safe_del}_*.conf" -type f 2>/dev/null | wc -l)

  if ! ( sync_xray_config ); then
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    [[ -n "${_snap_cfg_del:-}" && -f "${_snap_cfg_del:-}" ]] \
      && mv -f "$_snap_cfg_del" "$LANDING_CONF" 2>/dev/null || true
    _release_lock; die "Xray配置同步失败，节点文件和config.json已物理回滚"
  fi
  rm -f "${_snap_cfg_del:-}" 2>/dev/null || true  # sync succeeded, snapshot no longer needed
  if ! ( setup_firewall ); then
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    ( sync_xray_config ) 2>/dev/null || true
    _release_lock; die "防火墙更新失败，节点文件已恢复"
  fi
  local _restart_rc=0
  systemctl restart "$LANDING_SVC" 2>/dev/null || _restart_rc=$?
  sleep 1
  if (( _restart_rc != 0 )) || ! systemctl is-active --quiet "$LANDING_SVC"; then
    warn "服务重启失败，回滚节点文件..."
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    ( sync_xray_config ) 2>/dev/null || true
    ( setup_firewall )   2>/dev/null || true
    systemctl reset-failed "$LANDING_SVC" 2>/dev/null || true
    systemctl restart "$LANDING_SVC" 2>/dev/null || true
    __delete_node_trap_active=0
    trap - INT TERM ERR
    _release_lock; warn "节点已恢复，请检查: journalctl -u ${LANDING_SVC}"
  else
    if (( remaining == 0 )); then
      info "域名 ${DEL_DOMAIN} 已无中转机，清理证书..."
      if [[ -f "${ACME_HOME}/acme.sh" ]]; then
        "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$DEL_DOMAIN" --ecc 2>/dev/null || true
        rm -rf "${ACME_HOME}/${DEL_DOMAIN}_ecc" 2>/dev/null || true
      fi
      rm -rf "${CERT_BASE}/${DEL_DOMAIN}" 2>/dev/null || true
    fi
    rm -f "$_snap_node" "${DEL_CONF}.deleting" 2>/dev/null || true
    __delete_node_trap_active=0
    trap - INT TERM ERR
    _release_lock
    success "节点已删除，服务热重载正常"
  fi
}

do_set_port(){
  [[ -f "$INSTALLED_FLAG" ]] || die "未安装，无法修改端口"
  load_manager_config
  local _prev_err_trap _prev_int_trap _prev_term_trap
  _prev_err_trap=$(trap -p ERR 2>/dev/null || true)
  _prev_int_trap=$(trap -p INT 2>/dev/null || echo "")
  _prev_term_trap=$(trap -p TERM 2>/dev/null || echo "")
  local new_port="${1:-}"
  [[ -n "$new_port" ]] || { read -rp "新落地机监听端口: " new_port; }
  validate_port "$new_port"
  (( new_port >= 1024 )) || die "端口 ${new_port} 小于 1024，set-port 不支持低端口（需重装以更新权限配置）"
  for _internal_port in "$VLESS_GRPC_PORT" "$TROJAN_GRPC_PORT" "$VLESS_WS_PORT" "$TROJAN_TCP_PORT"; do
    if [[ "${_internal_port:-}" =~ ^[0-9]+$ && "${_internal_port}" == "$new_port" ]]; then
      die "端口 ${new_port} 与内部端口冲突（${_internal_port}），请选择其他端口"
    fi
  done
  if [[ "$new_port" == "$LANDING_PORT" ]]; then
    success "端口已是 ${new_port}，无需变更"; return
  fi
  ss -tlnp 2>/dev/null | grep -q ":${new_port} " && die "端口 ${new_port} 已被占用"
  local old_port="$LANDING_PORT"

  _acquire_lock
  local _port_change_active=1

  local _snap_mgr _snap_cfg _snap_fw
  _snap_mgr=$(mktemp "${MANAGER_BASE}/.snap-recover.XXXXXX") \
    || { _release_lock; die "manager.conf 快照创建失败（磁盘满？），端口未变更"; }
  _snap_cfg=$(mktemp "${LANDING_BASE}/.snap-recover.XXXXXX" 2>/dev/null) \
    || { rm -f "$_snap_mgr"; _release_lock; die "config.json 快照创建失败（磁盘满/目录缺失？），端口未变更"; }
  _snap_fw=""
  if [[ -f "${MANAGER_BASE}/firewall-restore.sh" ]]; then
    _snap_fw=$(mktemp "${MANAGER_BASE}/.snap-recover.XXXXXX" 2>/dev/null) || _snap_fw=""
    [[ -n "$_snap_fw" ]] && cp -f "${MANAGER_BASE}/firewall-restore.sh" "$_snap_fw" 2>/dev/null \
      || { rm -f "$_snap_mgr" "$_snap_cfg" "${_snap_fw:-}"; _release_lock; die "firewall-restore.sh 快照失败，端口未变更"; }
  fi
  cp -f "$MANAGER_CONFIG" "$_snap_mgr" 2>/dev/null \
    || { rm -f "$_snap_mgr" "$_snap_cfg" "${_snap_fw:-}"; _release_lock; die "manager.conf 快照写入失败，端口未变更"; }
  [[ -f "$LANDING_CONF" ]] && { cp -f "$LANDING_CONF" "$_snap_cfg" 2>/dev/null \
    || { rm -f "$_snap_mgr" "$_snap_cfg" "${_snap_fw:-}"; _release_lock; die "config.json 快照写入失败，端口未变更"; }; }

  _do_rollback_port(){
    [[ -f "$_snap_mgr" ]] && mv -f "$_snap_mgr" "$MANAGER_CONFIG" 2>/dev/null || true
    [[ -n "${_snap_cfg:-}" && -f "$_snap_cfg" ]] \
      && mv -f "$_snap_cfg" "$LANDING_CONF" 2>/dev/null || true
    # 还原 firewall-restore.sh 文件态
    [[ -n "${_snap_fw:-}" && -f "$_snap_fw" ]] \
      && mv -f "$_snap_fw" "${MANAGER_BASE}/firewall-restore.sh" 2>/dev/null || true
    if [[ -x "${MANAGER_BASE}/firewall-restore.sh" ]]; then
      "${MANAGER_BASE}/firewall-restore.sh" 2>/dev/null || true
    fi
    ( sync_xray_config ) 2>/dev/null || true
    systemctl reset-failed "$LANDING_SVC" 2>/dev/null || true
    systemctl restart "$LANDING_SVC" 2>/dev/null || true
    rm -f "$_snap_mgr" "${_snap_cfg:-}" "${_snap_fw:-}" 2>/dev/null || true
    LANDING_PORT="$old_port"
    _release_lock
  }
  trap '_global_cleanup; if [[ "${_port_change_active:-0}" == "1" ]]; then _do_rollback_port; fi; exit 1' INT TERM ERR

  LANDING_PORT="$new_port"
  if ! save_manager_config; then
    _port_change_active=0
    _do_rollback_port
    _restore_prev_port_traps
    die "manager.conf 写入失败，端口未变更"
  fi

  if ! ( sync_xray_config ); then
    _port_change_active=0
    _do_rollback_port
    _restore_prev_port_traps
    die "sync 失败，端口已回滚至 ${old_port}"
  fi
  if ! ( create_systemd_service ); then
    _port_change_active=0
    _do_rollback_port
    _restore_prev_port_traps
    die "systemd 单元刷新失败，端口已回滚至 ${old_port}"
  fi
  if ! ( setup_firewall ); then
    _port_change_active=0
    _do_rollback_port
    _restore_prev_port_traps
    ( sync_xray_config ) 2>/dev/null || true
    die "防火墙更新失败，端口已回滚至 ${old_port}"
  fi

  _persist_iptables "$(detect_ssh_port)"
  if ! systemctl restart xray-landing-iptables-restore.service 2>/dev/null; then
    warn "iptables 恢复服务重启失败，触发端口回滚..."
    _port_change_active=0
    _do_rollback_port
    _restore_prev_port_traps
    ( sync_xray_config ) 2>/dev/null || true
    systemctl restart "$LANDING_SVC" 2>/dev/null || true
    die "iptables 持久化失败，端口已回滚至 ${old_port}"
  fi
  local _restart_rc=0
  systemctl restart "$LANDING_SVC" || _restart_rc=$?
  sleep 2

  if (( _restart_rc != 0 )) || ! systemctl is-active --quiet "$LANDING_SVC"; then
    warn "服务启动失败，触发回滚至 ${old_port}..."
    _port_change_active=0
    _do_rollback_port
    _restore_prev_port_traps
    ( sync_xray_config ) 2>/dev/null || true
    systemctl restart "$LANDING_SVC" 2>/dev/null || true
    die "端口变更验证失败，已回滚至 ${old_port}"
  fi
  rm -f "$_snap_mgr" "${_snap_cfg:-}" "${_snap_fw:-}" 2>/dev/null || true
  _port_change_active=0
  _restore_prev_port_traps
  trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM ERR
  systemctl reset-failed "$LANDING_SVC" 2>/dev/null || true
  _release_lock

  success "端口已变更为 ${new_port}"
  echo ""
  echo -e "${RED}${BOLD}🚨 警告：落地机端口已更改！${NC}"
  echo -e "${RED}   必须立即登录中转机，删除旧路由规则，并使用下方新 Token 重新导入，否则节点全线断流！${NC}"
  echo ""
  local first_conf; first_conf=$(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | sort | head -1)
  if [[ -n "$first_conf" ]]; then
    local any_dom any_pass any_transit
    any_dom=$(grep '^DOMAIN='     "$first_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    any_pass=$(grep '^PASSWORD='  "$first_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    any_transit=$(grep '^TRANSIT_IP=' "$first_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    local pub_ip; pub_ip=$(get_public_ip 2>/dev/null) || pub_ip="（无法获取）"
    [[ -n "$any_dom" ]] && print_pairing_info "$pub_ip" "$any_dom" "$any_pass" "$any_transit"
  fi
}

show_status(){
  load_manager_config
  echo ""
  echo -e "${BOLD}── 落地机状态 ──────────────────────────────────────────────────${NC}"
  [[ -f "$INSTALLED_FLAG" ]] && echo "  已安装: 是" || echo "  已安装: 否"
  echo "  ${LANDING_SVC}: $(systemctl is-active "$LANDING_SVC" 2>/dev/null || echo inactive)"
  echo "  监听端口: ${LANDING_PORT}"
  echo "  VLESS UUID: ${VLESS_UUID:-（未配置）}"
  echo ""
  local n=0
  local _node_degraded=0
  while IFS= read -r meta; do
    [[ -f "$meta" ]] || continue
    local dom ip ts
    dom=$(grep '^DOMAIN='     "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    ip=$(grep  '^TRANSIT_IP=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    ts=$(grep  '^CREATED='    "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    printf "  [节点%-2d] %-38s 中转: %-18s 创建: %s\n" $((++n)) "$dom" "$ip" "$ts"
    [[ "$dom" == "?" ]] && { echo -e "    ${RED}↑ DOMAIN 字段缺失${NC}"; _node_degraded=1; }
    [[ "$ip"  == "?" ]] && { echo -e "    ${RED}↑ TRANSIT_IP 字段缺失${NC}"; _node_degraded=1; }
    if [[ "$dom" != "?" ]]; then
      [[ -f "${CERT_BASE}/${dom}/fullchain.pem" ]] \
        || { echo -e "    ${RED}↑ 证书 fullchain.pem 缺失！${NC}"; _node_degraded=1; }
      [[ -f "${CERT_BASE}/${dom}/key.pem" ]] \
        || { echo -e "    ${RED}↑ 证书 key.pem 缺失！${NC}"; _node_degraded=1; }
    fi
  done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | sort)
  [[ $n -eq 0 ]] && warn "  （无已配置节点）"
  (( _node_degraded )) && echo -e "  ${RED}节点完整性:  ✗ 部分节点缺证书/字段（sync_xray_config 会跳过缺证书节点！）${NC}" || true
  echo ""
  echo -e "  ${BOLD}── 证书与续期状态 ────────────────────────────────────────────${NC}"
  local _any_cert=0
  while IFS= read -r _smeta; do
    [[ -f "$_smeta" ]] || continue
    local _sdom; _sdom=$(grep '^DOMAIN=' "$_smeta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || continue
    [[ -n "$_sdom" ]] || continue
    local _cf="${CERT_BASE}/${_sdom}/fullchain.pem"
    if [[ -f "$_cf" ]]; then
      local _end; _end=$(openssl x509 -in "$_cf" -noout -enddate 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || _end=""
      local _days=0
      if [[ -n "$_end" ]]; then
        local _ets _nts
        _ets=$(LANG=C date -d "$_end" +%s 2>/dev/null || echo 0); _nts=$(date +%s)
        _days=$(( (_ets - _nts) / 86400 ))
      fi
      if (( _days > 30 )); then
        printf "  %-40s 证书剩余: ${GREEN}%d 天${NC}\n" "$_sdom" "$_days"
      elif (( _days > 0 )); then
        printf "  %-40s 证书剩余: ${YELLOW}%d 天（即将过期！）${NC}\n" "$_sdom" "$_days"
      else
        printf "  %-40s ${RED}证书已过期或读取失败${NC}\n" "$_sdom"
      fi
      _any_cert=1
    else
      printf "  %-40s ${RED}证书文件缺失${NC}\n" "$_sdom"
    fi
  done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | sort)
  ((_any_cert)) || warn "  （无证书信息）"
  if crontab -l 2>/dev/null | grep -qE 'acme\.sh.*(--cron|cron)'; then
    echo -e "  acme.sh cron:    ${GREEN}✓ 已注册（原生 crontab）${NC}"
  else
    echo -e "  acme.sh cron:    ${RED}✗ 未注册（证书无法自动续期！运行 acme.sh --install-cronjob 修复）${NC}"
  fi
  systemctl is-enabled --quiet "xray-landing-iptables-restore.service" 2>/dev/null \
    && echo -e "  iptables 恢复服务: ${GREEN}✓ enabled${NC}" \
    || echo -e "  iptables 恢复服务: ${RED}✗ 未 enable（重启后防火墙规则会丢失）${NC}"
  local _fw_script="${MANAGER_BASE}/firewall-restore.sh"
  if [[ -f "$_fw_script" ]]; then
    local _fw_ver_line; _fw_ver_line=$(grep '^# LANDING_FW_VERSION=' "$_fw_script" 2>/dev/null | head -1 || echo "")
    if [[ -z "$_fw_ver_line" ]]; then
      echo -e "  ${RED}恢复脚本版本:    ✗ 无版本签名（旧版脚本），自动重建...${NC}"; _ok=0
      local _ssh_p4; _ssh_p4=$(detect_ssh_port 2>/dev/null) || _ssh_p4=22
      _persist_iptables "$_ssh_p4" 2>/dev/null \
        && { echo -e "  ${GREEN}恢复脚本已自动重建 ✓${NC}"; _ok=1; } \
        || echo -e "  ${RED}自动重建失败，请执行 bash $0 set-port <port> 触发重建${NC}"
    else
      echo -e "  恢复脚本版本:    ${GREEN}✓ ${_fw_ver_line#*=}${NC}"
    fi
    local _fw_ips _live_ips
    _fw_ips=$(grep 'xray-landing-transit' "$_fw_script" 2>/dev/null \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//' || echo "")
    _live_ips=$(iptables -w 2 -L "$FW_CHAIN" -n 2>/dev/null \
      | awk '/xray-landing-transit/ && /ACCEPT/{print $4}' \
      | sed 's|/32||' | sort -u | tr '\n' ' ' | sed 's/ $//' || echo "")
    if [[ "$_fw_ips" == "$_live_ips" ]]; then
      echo -e "  恢复脚本一致性:  ${GREEN}✓ transit IP 与运行链匹配${NC}"
    else
      echo -e "  ${RED}恢复脚本一致性:  ✗ 与运行链不一致（重启后规则可能漂移）${NC}"; _ok=0
      echo -e "  ${CYAN}  修复: bash $0 set-port ${LANDING_PORT}（触发 setup_firewall 重建）${NC}"
    fi
  else
    echo -e "  ${RED}恢复脚本:        ✗ 不存在（重启后防火墙规则会丢失）${NC}"; _ok=0
  fi
  [[ -f "$CERT_RELOAD_SCRIPT" ]] \
    && echo -e "  续期重载脚本:    ${GREEN}✓${NC}" \
    || echo -e "  续期重载脚本:    ${RED}✗ 缺失${NC}"
  echo ""
  echo -e "  ${BOLD}── 状态硬校验 ────────────────────────────────────────────────${NC}"
  local _ok=1
  systemctl is-active --quiet "$LANDING_SVC" 2>/dev/null \
    && echo "  服务运行态:      ✓" \
    || {
      echo -e "  ${RED}服务运行态:      ✗ 未运行${NC}"; _ok=0
      local _svc_state; _svc_state=$(systemctl is-failed "$LANDING_SVC" 2>/dev/null || true)
      if [[ "$_svc_state" == "failed" ]]; then
        echo -e "  ${RED}熔断状态:        ✗ 服务已进入 failed（StartLimitBurst 触发）${NC}"
        echo -e "  ${CYAN}  自愈: systemctl reset-failed ${LANDING_SVC} && systemctl start ${LANDING_SVC}${NC}"
        echo -e "  ${CYAN}  或等待 recovery unit 自动恢复（约5分钟）${NC}"
      fi
    }
  [[ -f "$LANDING_CONF" ]] \
    && echo "  config.json:     ✓" \
    || { echo -e "  ${RED}config.json:     ✗ 缺失${NC}"; _ok=0; }
  [[ -f "$MANAGER_CONFIG" ]] \
    && echo "  manager.conf:    ✓" \
    || { echo -e "  ${RED}manager.conf:    ✗ 缺失（真相源丢失！）${NC}"; _ok=0; }
  ss -tlnp 2>/dev/null | grep -q ":${LANDING_PORT} " \
    && echo "  :${LANDING_PORT} 监听:    ✓" \
    || { echo -e "  ${RED}:${LANDING_PORT} 监听:    ✗ 端口未开放${NC}"; _ok=0; }
  if [[ -f "$MANAGER_CONFIG" && -f "$LANDING_CONF" ]]; then
    local _cfg_port _cfg_uuid _cfg_vg _cfg_tg _cfg_vw _cfg_tt
    _cfg_port=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][0]['port'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    _cfg_uuid=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][0]['settings']['clients'][0]['id'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    _cfg_vg=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][1]['port'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    _cfg_tg=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][2]['port'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    _cfg_vw=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][3]['port'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    _cfg_tt=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][4]['port'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    local _field_ok=1
    [[ -z "$_cfg_port" || "$_cfg_port" == "$LANDING_PORT" ]]      || { echo -e "  ${RED}端口一致性:      ✗ manager.conf:${LANDING_PORT} ≠ config.json:${_cfg_port}${NC}"; _ok=0; _field_ok=0; }
    [[ -z "$_cfg_uuid" || -z "$VLESS_UUID" || "$_cfg_uuid" == "$VLESS_UUID" ]] || { echo -e "  ${RED}UUID一致性:      ✗ 真相源与派生不符${NC}"; _ok=0; _field_ok=0; }
    [[ -z "$_cfg_vg"   || "$_cfg_vg"   == "$VLESS_GRPC_PORT"  ]]  || { echo -e "  ${RED}VLESS-gRPC端口:  ✗ ${VLESS_GRPC_PORT} ≠ ${_cfg_vg}${NC}"; _ok=0; _field_ok=0; }
    [[ -z "$_cfg_tg"   || "$_cfg_tg"   == "$TROJAN_GRPC_PORT" ]]  || { echo -e "  ${RED}Trojan-gRPC端口: ✗ ${TROJAN_GRPC_PORT} ≠ ${_cfg_tg}${NC}"; _ok=0; _field_ok=0; }
    [[ -z "$_cfg_vw"   || "$_cfg_vw"   == "$VLESS_WS_PORT"    ]]  || { echo -e "  ${RED}VLESS-WS端口:    ✗ ${VLESS_WS_PORT} ≠ ${_cfg_vw}${NC}"; _ok=0; _field_ok=0; }
    [[ -z "$_cfg_tt"   || "$_cfg_tt"   == "$TROJAN_TCP_PORT"   ]]  || { echo -e "  ${RED}Trojan-TCP端口:  ✗ ${TROJAN_TCP_PORT} ≠ ${_cfg_tt}${NC}"; _ok=0; _field_ok=0; }
    (( _field_ok )) && echo -e "  字段一致性:      ${GREEN}✓ 全部6字段与config.json一致${NC}"
  fi
  ((_ok)) \
    && echo -e "  ${GREEN}整体状态: 一致 ✓${NC}" \
    || { echo -e "  ${RED}整体状态: 存在分裂，请排查 ✗${NC}"; echo ""; echo -e "  ${CYAN}日志: tail -f ${LANDING_LOG}/error.log${NC}"; return 1; }
  echo ""
  echo -e "  ${CYAN}日志: tail -f ${LANDING_LOG}/error.log${NC}"
}

print_pairing_info(){
  local pub_ip="$1" domain="$2" password="$3" transit_ip="$4"
  load_manager_config

  local token=""
  if ! printf '%s' "$pub_ip" | python3 -c "import ipaddress,sys; ipaddress.IPv4Address(sys.stdin.read().strip())" 2>/dev/null; then
    die "pub_ip='${pub_ip}' 不是合法 IPv4，拒绝生成 Token"
  fi
  local -r validated_ip="$pub_ip"
  token=$(printf '%s\n%s\n%s\n%s\n%s' "$validated_ip" "$domain" "$LANDING_PORT" "$VLESS_UUID" "$password" | python3 -c "
import json, base64, sys
lines = [l.strip() for l in sys.stdin.read().split('\n') if l.strip()]
landing_ip = lines[0]; landing_dom = lines[1]; landing_port = int(lines[2])
vless_uuid = lines[3]; trojan_pwd = lines[4]
token_dict = {'ip': landing_ip, 'dom': landing_dom, 'port': landing_port, 'uuid': vless_uuid, 'pwd': trojan_pwd, 'pfx': vless_uuid[:8]}
print(base64.b64encode(json.dumps(token_dict, separators=(',',':')).encode()).decode())
" 2>&1) || { warn "token 生成异常: ${token}"; token=""; }

  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║       请将以下信息复制至中转机脚本 install_transit_${VERSION}.sh ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  printf "║  %-18s : %-45s║\n" "落地机公网 IP"   "$pub_ip"
  printf "║  %-18s : %-45s║\n" "落地机域名(SNI)" "$domain"
  printf "║  %-18s : %-45s║\n" "落地机后端端口"  "$LANDING_PORT"
  printf "║  %-18s : %-45s║\n" "Trojan密码"      "$password"
  printf "║  %-18s : %-45s║\n" "VLESS UUID"      "${VLESS_UUID}"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  中转机一键导入命令：                                           ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  #  版本号由 VERSION 自动维护
  [[ -n "$token" ]] \
    && echo -e "  ${BOLD}${CYAN}bash install_transit_${VERSION}.sh --import ${token}${NC}" \
    || warn "  token 生成失败，请手动将上方信息填入中转机脚本"

  echo ""
  echo -e "${BOLD}── 5 协议 Base64 订阅 ────────────────────────────────────────────${NC}"
  local ti="${transit_ip:-$pub_ip}"
  local sub_b64="" _sub_err=""
  sub_b64=$(python3 - "$ti" "$domain" "$VLESS_UUID" "$password" 2>&1 <<'SUBPY'
import sys
if len(sys.argv) < 5: print('ERROR: requires 4 args', file=sys.stderr); sys.exit(1)
import base64, urllib.parse
transit_ip, domain, vless_uuid, trojan_pass = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
port = 443
pfx = vless_uuid[:8]
lbl_vision = '[禁Mux]VLESS-Vision-'
lbl_vgrpc  = 'VLESS-gRPC-'
# lbl_tgrpc  = 'Trojan-gRPC-'
lbl_vws    = 'VLESS-WS-'
lbl_ttcp   = 'Trojan-TCP-'
uris = [
    (f"vless://{vless_uuid}@{transit_ip}:{port}"
     f"?encryption=none&flow=xtls-rprx-vision&security=tls"
     f"&sni={domain}&fp=chrome&type=tcp"
     f"#{urllib.parse.quote(lbl_vision+domain)}"),
    (f"vless://{vless_uuid}@{transit_ip}:{port}"
     f"?encryption=none&security=tls&sni={domain}&fp=edge"
     f"&type=grpc&serviceName={pfx}-vg&alpn=h2&mode=multi"
     f"#{urllib.parse.quote(lbl_vgrpc+domain)}"),
    #  f"?security=tls&sni={domain}&fp=ios"
    #  f"&type=grpc&serviceName={pfx}-tg&alpn=h2&mode=multi"
    #  f"#{urllib.parse.quote(lbl_tgrpc+domain)}"),
    (f"vless://{vless_uuid}@{transit_ip}:{port}"
     f"?encryption=none&security=tls&sni={domain}&fp=firefox"
     f"&type=ws&path=%2F{pfx}-vw&host={domain}&alpn=http/1.1"
     f"#{urllib.parse.quote(lbl_vws+domain)}"),
    (f"trojan://{urllib.parse.quote(trojan_pass)}@{transit_ip}:{port}"
     f"?security=tls&sni={domain}&fp=safari&type=tcp"
     f"#{urllib.parse.quote(lbl_ttcp+domain)}"),
]
print(base64.b64encode("\n".join(uris).encode()).decode())
SUBPY
) || { _sub_err="$sub_b64"; sub_b64=""; }

  if [[ -n "$sub_b64" ]]; then
    echo -e "  ${BOLD}── 5 协议明文链接（可逐条复制验证）──────────────────${NC}"
    python3 -c "
import sys
if len(sys.argv) < 2: print('ERROR: requires 1 arg', file=sys.stderr); sys.exit(1)
import base64
data = base64.b64decode(sys.argv[1]).decode()
for i, line in enumerate(data.split('\n'), 1):
    print(f'  [{i}] {line}')
" "$sub_b64" 2>/dev/null || true
    echo ""
    echo -e "  ${BOLD}── Base64 整体订阅（粘贴到客户端「添加订阅」）──────${NC}"
    echo ""; echo "  $sub_b64"; echo ""
    echo -e "  ${CYAN}（Clash Meta / NekoBox / v2rayN / Sing-box / Shadowrocket）${NC}"
    echo ""
    echo -e "  ${RED}${BOLD}⚠  VLESS-Vision 节点【严禁开启 Mux】！开启必断流！${NC}"
    echo -e "  ${YELLOW}   其他四个协议 (gRPC/WS/TCP) 完全兼容 Mux，高并发推荐 gRPC。${NC}"
  else
    warn "Base64 订阅生成失败"
    [[ -n "${_sub_err:-}" ]] && error "  Python 错误: ${_sub_err}"
  fi
  echo ""
}

purge_all(){
  echo ""
  warn "此操作清除本脚本所有内容（不影响 mack-a/v2ray-agent）"
  read -rp "确认清除？输入 'DELETE' 确认: " CONFIRM
  [[ "$CONFIRM" == "DELETE" ]] || { info "已取消"; return; }

  if [[ -f "${ACME_HOME}/acme.sh" ]]; then
    "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
  fi

  local _created_user="0"
  _created_user=$(grep '^CREATED_USER=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true

  systemctl stop    "$LANDING_SVC" 2>/dev/null || true
  systemctl disable "$LANDING_SVC" 2>/dev/null || true
  systemctl stop --no-block "$LANDING_SVC" 2>/dev/null || true
  systemctl disable --now xray-landing-iptables-restore.service 2>/dev/null || true
  rm -f "/etc/systemd/system/${LANDING_SVC}" \
        "/etc/systemd/system/xray-landing-recovery.service" \
        "/etc/systemd/system/xray-landing-iptables-restore.service" \
        "/etc/profile.d/xray-recovery-alert.sh" \
        "/etc/profile.d/xray-cert-alert.sh" 2>/dev/null || true
  rm -f /run/lock/xray-landing-recovery.last 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true

  if [[ -f "${ACME_HOME}/acme.sh" ]]; then
    local managed_domains=() seen_unremove=()
    while IFS= read -r meta; do
      local dom; dom=$(grep '^DOMAIN=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || continue
      [[ -n "$dom" ]] && managed_domains+=("$dom")
    done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null)
    for d in "${managed_domains[@]+${managed_domains[@]}}"; do
      local already=0
      for s in "${seen_unremove[@]+${seen_unremove[@]}}"; do [[ "$s" == "$d" ]] && already=1 && break; done
      (( already )) && continue
      seen_unremove+=("$d")
      "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$d" --ecc 2>/dev/null && info "已移除 acme.sh 续期: $d" || true
      rm -rf "${ACME_HOME}/${d}_ecc" 2>/dev/null || true
    done
  fi
  if crontab -l 2>/dev/null | grep -q 'acme\.sh'; then
    crontab -l 2>/dev/null | grep -v 'acme\.sh' | crontab - 2>/dev/null || true
  fi

  for _rc in "/root/.bashrc" "/root/.profile" "/root/.bash_profile" "${HOME}/.bashrc" "${HOME}/.profile" "${HOME}/.bash_profile"; do
    [[ -f "$_rc" ]] && sed -i '/acme\.sh\.env/d' "$_rc" 2>/dev/null || true
  done

  _purge_bulldoze(){
    local _chain="$1" _num _nums
    while true; do
      _nums=$(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null \
              | awk -v c="$_chain" 'NR>2 && $2 == c {print $1}' \
              | sort -nr)
      [[ -n "${_nums:-}" ]] || break
      while IFS= read -r _num; do
        [[ -n "$_num" ]] || continue
        iptables -w 2 -D INPUT "$_num" 2>/dev/null || break 2
      done <<<"$_nums"
    done
    iptables -w 2 -F "$_chain" 2>/dev/null || true
    iptables -w 2 -X "$_chain" 2>/dev/null || true
  }
  _purge_bulldoze6(){
    local _chain="$1" _num _nums
    while true; do
      _nums=$(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null \
              | awk -v c="$_chain" 'NR>2 && $2 == c {print $1}' \
              | sort -nr)
      [[ -n "${_nums:-}" ]] || break
      while IFS= read -r _num; do
        [[ -n "$_num" ]] || continue
        ip6tables -w 2 -D INPUT "$_num" 2>/dev/null || break 2
      done <<<"$_nums"
    done
    ip6tables -w 2 -F "$_chain" 2>/dev/null || true
    ip6tables -w 2 -X "$_chain" 2>/dev/null || true
  }
  _purge_bulldoze  "$FW_CHAIN";  _purge_bulldoze  "${FW_CHAIN}-NEW"
  _purge_bulldoze6 "$FW_CHAIN6"; _purge_bulldoze6 "${FW_CHAIN6}-NEW"

  mkdir -p /etc/iptables
  # iptables-save > /etc/iptables/rules.v4|v6 已移除

  rm -f /etc/nginx/conf.d/xray-landing-fallback.conf 2>/dev/null || true
  rm -f "/etc/systemd/system/nginx.service.d/landing-override.conf" 2>/dev/null || true
  rmdir "/etc/systemd/system/nginx.service.d" 2>/dev/null || true
  rm -f "/etc/systemd/system/xray-landing.service.d/xray-landing-limits.conf" 2>/dev/null || true
  rmdir "/etc/systemd/system/xray-landing.service.d" 2>/dev/null || true
  rm -f "/etc/systemd/journald.conf.d/xray-landing.conf" 2>/dev/null || true
  systemctl restart systemd-journald 2>/dev/null || true
  rmdir "/etc/systemd/journald.conf.d" 2>/dev/null || true
  systemctl restart systemd-journald 2>/dev/null || true
  rm -rf "$MANAGER_BASE" 2>/dev/null || true
  rm -f /etc/sysctl.d/99-landing-bbr.conf /etc/modprobe.d/99-landing-conntrack.conf 2>/dev/null || true
  sysctl --system &>/dev/null || true
  rm -f /etc/cron.daily/xray-cert-monitor 2>/dev/null || true
  if [[ -f /etc/cron.daily/xray-cert-monitor ]]; then
    warn "无法删除 /etc/cron.daily/xray-cert-monitor（可能是只读文件系统），请手动删除"
  fi
  if [[ -f "$NGINX_CONF_ORIG" ]]; then
    cp -a "$NGINX_CONF_ORIG" /etc/nginx/nginx.conf 2>/dev/null || true
  else
    sed -i "/# xray-landing-tuning-v${VERSION}/d" /etc/nginx/nginx.conf 2>/dev/null || true
  fi
  if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
  fi
  if [[ "${_created_user:-0}" == "1" ]]; then
    if [[ -n "$LANDING_USER" ]]; then
      command -v loginctl >/dev/null 2>&1 && loginctl terminate-user "$LANDING_USER" 2>/dev/null || true
      [[ -n "$LANDING_USER" ]] && pkill -u "$LANDING_USER" 2>/dev/null || true
      sleep 1
      [[ -n "$LANDING_USER" ]] && pkill -KILL -u "$LANDING_USER" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -n "$LANDING_USER" ]] && pgrep -u "$LANDING_USER" >/dev/null 2>&1 || break
        sleep 0.5
      done
      sed -i "/^${LANDING_USER}:/d" /etc/subuid 2>/dev/null || true
      sed -i "/^${LANDING_USER}:/d" /etc/subgid 2>/dev/null || true
      if ! userdel "$LANDING_USER" 2>/dev/null; then
        warn "userdel 失败 (用户可能仍有运行中进程) — 需要手动清理"
      fi
      groupdel "$LANDING_USER" 2>/dev/null || true
    fi
  fi

  [[ -d "/home/${LANDING_USER}" ]] && rm -rf "/home/${LANDING_USER}" 2>/dev/null || true
  rm -f /etc/security/limits.d/99-xray-landing.conf 2>/dev/null || true
  sed -i '/# xray-landing: keep cron\\/PAM sessions aligned/,/^root hard nofile/d' /etc/security/limits.conf 2>/dev/null || true
  rm -rf "$LANDING_LOG" 2>/dev/null || true
  rm -f /var/log/acme-xray-landing-renew.log /var/run/xray-landing.update.warn 2>/dev/null || true
  rm -f "$LANDING_BIN" "$CERT_RELOAD_SCRIPT" 2>/dev/null || true
  rm -rf /usr/local/share/xray-landing 2>/dev/null || true
  rm -rf "$LANDING_BASE" 2>/dev/null || true

  # 卸载后验收
  local _pclean=1
  [[ -f "$LANDING_BIN" ]] && { warn "二进制 ${LANDING_BIN} 残留"; _pclean=0; } || true
  [[ -f "$CERT_RELOAD_SCRIPT" ]] && { warn "证书重载脚本 ${CERT_RELOAD_SCRIPT} 残留"; _pclean=0; } || true
  [[ -d /usr/local/share/xray-landing ]] && { warn "资产目录 /usr/local/share/xray-landing 残留"; _pclean=0; } || true
  systemctl is-active --quiet "$LANDING_SVC" 2>/dev/null     && { warn "服务 ${LANDING_SVC} 仍在运行"; _pclean=0; } || true
  systemctl is-enabled --quiet "$LANDING_SVC" 2>/dev/null     && { warn "服务 ${LANDING_SVC} 仍为 enabled"; _pclean=0; } || true
  iptables -w 2 -L "$FW_CHAIN" >/dev/null 2>&1     && { warn "iptables chain ${FW_CHAIN} 仍存在"; _pclean=0; } || true
  [[ -d "$LANDING_BASE" ]] && { warn "目录 ${LANDING_BASE} 残留"; _pclean=0; } || true
  ((_pclean))     && success "清理完毕（验收通过），mack-a 未受影响"     || warn "清理完毕，但存在残留项，重装前请手动确认（mack-a 未受影响）"
}

show_all_nodes_info(){
  load_manager_config
  echo ""
  echo -e "${BOLD}${CYAN}══ 所有节点 Token 与订阅链接 ══════════════════════════════════${NC}"
  local _node_count=0
  while IFS= read -r _nf; do
    [[ -f "$_nf" ]] || continue
    local _ndom _npwd _ntip _npip
    _ndom=$(grep '^DOMAIN='     "$_nf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || continue
    _npwd=$(grep '^PASSWORD='   "$_nf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || continue
    _ntip=$(grep '^TRANSIT_IP=' "$_nf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || _ntip=""
    _npip=$(grep '^PUBLIC_IP='  "$_nf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || _npip=""
    [[ -n "$_ndom" && -n "$_npwd" ]] || continue
    if [[ -z "$_npip" ]]; then
      _npip=$(get_public_ip 2>/dev/null) || _npip="<unknown>"
    fi
    (( ++_node_count ))
    echo ""
    echo -e "  ${BOLD}[节点 ${_node_count}] ${_ndom}${NC}  中转: ${_ntip}"
    echo -e "  ─────────────────────────────────────────────────"
    print_pairing_info "$_npip" "$_ndom" "$_npwd" "$_ntip"
  done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f 2>/dev/null | sort)
  if (( _node_count == 0 )); then
    warn "（无已配置节点）"
  fi
  echo ""
}

installed_menu(){
  echo ""
  echo -e "${BOLD}${CYAN}══ 落地机管理菜单 ══════════════════════════════════════════════${NC}"
  local n=0
  while IFS= read -r meta; do
    [[ -f "$meta" ]] || continue
    local dom ip ts
    dom=$(grep '^DOMAIN='     "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    ip=$(grep  '^TRANSIT_IP=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    ts=$(grep  '^CREATED='    "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    printf "  [节点%-2d] %-38s 中转: %-18s 创建: %s\n" $((++n)) "$dom" "$ip" "$ts"
  done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | sort)
  [[ $n -eq 0 ]] && warn "（无已配置节点）"
  echo ""
  echo "  1. 增加新节点"
  echo "  2. 删除指定节点"
  echo "  3. 修改落地机监听端口"
  echo "  4. 清除本系统所有数据（不影响 mack-a）"
  echo "  5. 退出"
  echo "  6. 显示所有节点 Token 与订阅链接"
  echo ""
  read -rp "请选择 [1-6]: " CHOICE
  case "$CHOICE" in
    1) add_node;      installed_menu ;;
    2) delete_node;   installed_menu ;;
    3) do_set_port;   installed_menu ;;
    4) purge_all ;;
    5) exit 0 ;;
    6) show_all_nodes_info; installed_menu ;;
    *) warn "无效选项: ${CHOICE}"; installed_menu ;;
  esac
}

fresh_install(){
  echo ""
  echo -e "${BOLD}${CYAN}══ 落地机全新安装（${VERSION}）══════════════════════════════════════${NC}"
  echo -e "${BOLD}${RED}  ⚠  重要：域名在 Cloudflare 必须设为【仅DNS/灰云】，严禁开启代理（小黄云）！${NC}"
  echo -e "${RED}     SNI盲传+XTLS-Vision架构下，开启小黄云 = 节点100%永久断流。${NC}"
  echo ""
  local _headless=0
  check_deps
  if [[ -n "${LANDING_HEADLESS:-}" || -n "${LANDING_AUTO_DOMAIN:-}" ]]; then
    _headless=1
    DOMAIN="${LANDING_AUTO_DOMAIN:-${DOMAIN:-}}"
    CF_TOKEN="${LANDING_AUTO_CF_TOKEN:-}"

    PASS="${LANDING_AUTO_PASSWORD:-${PASS:-}}"
    TRANSIT_IP="${LANDING_AUTO_TRANSIT_IP:-${TRANSIT_IP:-}}"
    LANDING_PORT="${LANDING_AUTO_PORT:-8443}"
    [[ -n "$DOMAIN" ]] || die "无头模式缺少 LANDING_AUTO_DOMAIN"
    [[ -n "$CF_TOKEN" ]] || die "无头模式缺少 LANDING_AUTO_CF_TOKEN"
    [[ -n "$TRANSIT_IP" ]] || die "无头模式缺少 LANDING_AUTO_TRANSIT_IP"
    DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$DOMAIN")")
    validate_domain "$DOMAIN"
    validate_cf_token "$CF_TOKEN"
    if [[ -z "$PASS" ]]; then
      PASS=$(gen_password)
      info "  已自动生成高强度密码: ${PASS}"
    fi
    validate_password "$PASS"
    validate_ipv4 "$TRANSIT_IP"
    validate_port "$LANDING_PORT"
    if [[ -n "${LANDING_AUTO_PUBLIC_IP:-}" ]]; then
      PUB_IP="${LANDING_AUTO_PUBLIC_IP}"
      validate_ipv4 "$PUB_IP"
    else
      PUB_IP=$(get_public_ip)
    fi
    info "检测到无头静默安装模式，已跳过交互输入"
  else
    read -rp "落地机域名（CF 灰云，DNS 可指向任意 IP）: " DOMAIN
    DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$DOMAIN")")
    validate_domain "$DOMAIN"
    read -rp "Cloudflare API Token（Zone:DNS:Edit）: " CF_TOKEN
    validate_cf_token "$CF_TOKEN"
    read -rp "Trojan 密码（16位以上，直接回车自动生成）: " PASS
    if [[ -z "$PASS" ]]; then
      PASS=$(gen_password)
      info "  已自动生成高强度密码: ${PASS}"
    fi
    validate_password "$PASS"
    read -rp "中转机公网 IP（防火墙白名单）: " TRANSIT_IP
    validate_ipv4 "$TRANSIT_IP"
    read -rp "落地机监听端口（默认 8443）[8443]: " LANDING_PORT_IN
    LANDING_PORT_IN="${LANDING_PORT_IN:-8443}"
    validate_port "$LANDING_PORT_IN"
    LANDING_PORT="$LANDING_PORT_IN"
  fi

  if (( _headless )); then
    CONFIRM="y"
  else
    read -rp "确认开始安装？[y/N]: " CONFIRM
  fi
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "已取消"; exit 0; }

  ss -tlnp 2>/dev/null | grep -q ":${LANDING_PORT} " && die "端口 ${LANDING_PORT} 已被占用（请先检查 nginx / xray* / mack-a*）"
  if command -v mack-a &>/dev/null || [[ -f /etc/v2ray-agent/install.sh ]]; then
    warn "检测到 mack-a 已安装，本落地机将与其共享端口，请确认无冲突"
  fi
  __LANDING_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  optimize_kernel_network; create_system_user; install_xray_binary

  local PUB_IP; PUB_IP=$(get_public_ip)

  if [[ -f "$MANAGER_CONFIG" ]]; then
    local _exist_uuid; _exist_uuid=$(grep '^VLESS_UUID='       "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    local _exist_port; _exist_port=$(grep '^LANDING_PORT='     "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    local _exist_vg;   _exist_vg=$(grep   '^VLESS_GRPC_PORT='  "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    local _exist_tg;   _exist_tg=$(grep   '^TROJAN_GRPC_PORT=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    local _exist_vw;   _exist_vw=$(grep   '^VLESS_WS_PORT='    "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    local _exist_tt;   _exist_tt=$(grep   '^TROJAN_TCP_PORT='  "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true
    if [[ -n "$_exist_uuid" && -n "$_exist_port" ]]; then
      warn "检测到已有安装记录（manager.conf），复用旧配置以保持订阅有效"
      warn "  UUID: ${_exist_uuid}  主端口: ${_exist_port}"
      read -rp "  复用旧配置？[Y/n]: " _reuse_ans
      if [[ -n "${LANDING_HEADLESS:-}" || -n "${LANDING_AUTO_DOMAIN:-}" ]]; then
        warn "无头模式：自动复用已有 UUID 和端口（如存在）"
        VLESS_UUID="$_exist_uuid"
        LANDING_PORT="$_exist_port"
        [[ "$_exist_vg" =~ ^[0-9]+$ ]] && VLESS_GRPC_PORT="$_exist_vg"   || true
        [[ "$_exist_tg" =~ ^[0-9]+$ ]] && TROJAN_GRPC_PORT="$_exist_tg"  || true
        [[ "$_exist_vw" =~ ^[0-9]+$ ]] && VLESS_WS_PORT="$_exist_vw"     || true
        [[ "$_exist_tt" =~ ^[0-9]+$ ]] && TROJAN_TCP_PORT="$_exist_tt"   || true
        success "已复用旧 UUID 和端口，现有订阅链接继续有效"
      elif [[ ! "${_reuse_ans:-Y}" =~ ^[Nn]$ ]]; then
        VLESS_UUID="$_exist_uuid"
        LANDING_PORT="$_exist_port"
        [[ "$_exist_vg" =~ ^[0-9]+$ ]] && VLESS_GRPC_PORT="$_exist_vg"   || true
        [[ "$_exist_tg" =~ ^[0-9]+$ ]] && TROJAN_GRPC_PORT="$_exist_tg"  || true
        [[ "$_exist_vw" =~ ^[0-9]+$ ]] && VLESS_WS_PORT="$_exist_vw"     || true
        [[ "$_exist_tt" =~ ^[0-9]+$ ]] && TROJAN_TCP_PORT="$_exist_tt"   || true
        success "已复用旧 UUID 和端口，现有订阅链接继续有效"
      else
        warn "  将生成全新 UUID（旧订阅链接将全部失效！）"
        VLESS_UUID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null)           || VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true) || VLESS_UUID=$(uuidgen 2>/dev/null) || die "无法生成 UUID（python3 uuid、/proc/sys/kernel/random/uuid、uuidgen 均失败）"
      fi
    fi
  else
    VLESS_UUID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null)       || VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true) || VLESS_UUID=$(uuidgen 2>/dev/null) || die "无法生成 UUID（python3 uuid、/proc/sys/kernel/random/uuid、uuidgen 均失败）"
  fi

  local _VGRPC="${VLESS_GRPC_PORT:-0}" _VTG="${TROJAN_GRPC_PORT:-0}" _VWS="${VLESS_WS_PORT:-0}" _TTCP="${TROJAN_TCP_PORT:-0}"
  if [[ "${VLESS_GRPC_PORT:-0}" == "0" ]]; then
    _VGRPC=$(python3 -c "import random; b=random.randint(21000,29000)&~3; print(b)")
    _VTG=$(( _VGRPC + 1 )); _VWS=$(( _VGRPC + 2 )); _TTCP=$(( _VGRPC + 3 ))
    VLESS_GRPC_PORT="$_VGRPC"; TROJAN_GRPC_PORT="$_VTG"; VLESS_WS_PORT="$_VWS"; TROJAN_TCP_PORT="$_TTCP"
  fi
  _validate_internal_ports_in_use
  for _chkp in "$_VGRPC" "$_VTG" "$_VWS" "$_TTCP"; do
    ss -tlnp 2>/dev/null | grep -q ":${_chkp} "       && { warn "内网端口 ${_chkp} 已被占用，请重新运行脚本（自动重新分配）"; false; }
  done

  mkdir -p "$LANDING_BASE"

  _fresh_install_rollback(){
    [[ "${__LANDING_FRESH_INSTALL_TRAP_ACTIVE:-0}" == "1" ]] || return 0
    warn "[rollback] 安装中断，清理半成品..."
    systemctl stop    "$LANDING_SVC"   2>/dev/null || true
    systemctl disable "$LANDING_SVC"   2>/dev/null || true
    rm -f "/etc/systemd/system/${LANDING_SVC}" \
          "/etc/systemd/system/xray-landing-recovery.service" 2>/dev/null || true
    rm -f "/etc/nginx/conf.d/xray-landing-fallback.conf" 2>/dev/null || true
    rm -f "/etc/systemd/system/nginx.service.d/landing-override.conf" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    while iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null; do :; done
    iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true
    iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
    rm -f "$LANDING_BIN" "$CERT_RELOAD_SCRIPT" "$LOGROTATE_FILE" 2>/dev/null || true
    rm -rf /usr/local/share/xray-landing 2>/dev/null || true
    rm -f /run/lock/xray-landing-recovery.last 2>/dev/null || true
    if [[ -n "${DOMAIN:-}" && -f "${ACME_HOME}/acme.sh" ]]; then
      env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" \
        --home "${ACME_HOME}" --remove --domain "${DOMAIN}" --ecc 2>/dev/null || true
    fi
    rm -rf "$CERT_BASE" "$LANDING_BASE" 2>/dev/null || true
    rm -f "$INSTALLED_FLAG" "$MANAGER_CONFIG" 2>/dev/null || true
    rm -f "${_staged_fi_mgr:-}" 2>/dev/null || true   # [v2.8] purge staged manager.conf on rollback
    rm -rf "${MANAGER_BASE}/nodes" 2>/dev/null || true
    warn "[rollback] 完成，可安全重新运行安装"
  }

  mkdir -p "${MANAGER_BASE}/tmp"

  local _staged_fi_mgr; _staged_fi_mgr=$(mktemp "${MANAGER_BASE}/tmp/.manager.XXXXXX") \
    || die "mktemp _staged_fi_mgr failed — MANAGER_BASE/tmp missing or disk full"
  atomic_write "$_staged_fi_mgr" 600 root:root <<SMFI
LANDING_PORT=${LANDING_PORT}
VLESS_UUID=${VLESS_UUID}
VLESS_GRPC_PORT=${VLESS_GRPC_PORT}
TROJAN_GRPC_PORT=${TROJAN_GRPC_PORT}
VLESS_WS_PORT=${VLESS_WS_PORT}
TROJAN_TCP_PORT=${TROJAN_TCP_PORT}
CF_TOKEN=${CF_TOKEN}
CREATED_USER=${CREATED_USER}
MARKER_VERSION=${VERSION}
ACME_HOME=${ACME_HOME}
XRAY_BIN=${LANDING_BIN}
XRAY_LOG_DIR=${LANDING_LOG}
BIND_IP=${BIND_IP}
MARKER_CREATED=$(date +%Y%m%d_%H%M%S)
SMFI

  setup_fallback_decoy

  local _safe_dom; _safe_dom=$(printf '%s' "$DOMAIN" | tr '.:/' '___')
  local _safe_ip;  _safe_ip=$(printf '%s' "$TRANSIT_IP" | tr '.:' '__')
  local _final_node="${MANAGER_BASE}/nodes/${_safe_dom}_${_safe_ip}.conf"
  mkdir -p "${MANAGER_BASE}/nodes"
  save_node_info "$DOMAIN" "$PASS" "$TRANSIT_IP" "$PUB_IP"
  trap '_global_cleanup; rm -f "$_final_node" 2>/dev/null; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

  local _CAP_LINE="" _CAP_BOUND=""
  (( LANDING_PORT < 1024 )) && {
    _CAP_LINE=$'AmbientCapabilities=CAP_NET_BIND_SERVICE'
    _CAP_BOUND=$'CapabilityBoundingSet=CAP_NET_BIND_SERVICE'
  }
  export _CAP_LINE _CAP_BOUND

  if ! ( sync_xray_config ); then
    rm -f "$_final_node" "${_staged_fi_mgr:-}" 2>/dev/null || true
    _release_lock; exit 1
  fi
  if ! ( create_systemd_service ); then
    rm -f "$_final_node" "${_staged_fi_mgr:-}" 2>/dev/null || true
    _release_lock; exit 1
  fi

  issue_certificate "$DOMAIN" "$CF_TOKEN"

  # Node file already at final path; reset trap to standard
  trap '_global_cleanup; rm -f "${_staged_fi_mgr:-}" 2>/dev/null; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

  if ! ( setup_firewall ); then
    rm -f "$_final_node" "${_staged_fi_mgr:-}" 2>/dev/null || true
    systemctl stop    "$LANDING_SVC" 2>/dev/null || true
    systemctl disable "$LANDING_SVC" 2>/dev/null || true
    rm -f "/etc/systemd/system/${LANDING_SVC}" 2>/dev/null || true
    rm -f "$LOGROTATE_FILE" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    ( sync_xray_config ) 2>/dev/null || true
    if [[ -f "${ACME_HOME}/acme.sh" ]]; then
      "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$DOMAIN" --ecc 2>/dev/null || true
      rm -rf "${CERT_BASE}/${DOMAIN}" 2>/dev/null || true
    fi
    _release_lock; exit 1
  fi

  mv -f "$_staged_fi_mgr" "$MANAGER_CONFIG"
  touch "$INSTALLED_FLAG"
  _staged_fi_mgr=""   # prevent _fresh_install_rollback from double-deleting

  # Transaction committed — deactivate rollback trap
  __LANDING_FRESH_INSTALL_TRAP_ACTIVE=0
  trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

  print_pairing_info "$PUB_IP" "$DOMAIN" "$PASS" "$TRANSIT_IP"
  success "══ 落地机安装完成！══"
  echo -e "  systemctl status ${LANDING_SVC}"
  echo -e "  tail -f ${LANDING_LOG}/error.log"
}

fresh_install_headless(){
  LANDING_HEADLESS=1 fresh_install
}

_ver_gt(){ [[ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" && "$1" != "$2" ]]; }
_check_update(){
  local self_name; self_name=$(basename "${BASH_SOURCE[0]:-$0}")
  local cur_ver="$VERSION"
  local remote
  remote=$(curl -fsSL --connect-timeout 3 --retry 1 \
    "https://raw.githubusercontent.com/vpn3288/cn2gia-transit/main/${self_name}" \
    2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+' | head -1) || return 0
  [[ -n "$remote" ]] && _ver_gt "$remote" "$cur_ver" && warn "发现新版本 ${remote}！" || true
}

main(){
  echo -e "${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════════╗"
  printf "║     美西 CN2 GIA 落地机安装脚本  %-32s║\n" "${VERSION}"
  echo "║     5协议单端口回落 · TLS 1.2/1.3双栈 · rejectUnknownSni=true  ║"
  echo "║     异构uTLS指纹 · UDP53黑洞 · have_ipv6 sysctl guard           ║"
  echo "║     fallback 444 · acme自愈升级 · 真相源防反写 · mack-a隔离    ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  case "${1:-}" in
    --uninstall) purge_all; exit 0 ;;
    --help|-h)   show_help; exit 0 ;;
    --status)    show_status; exit $? ;;
    set-port)    do_set_port "${2:-}"; exit 0 ;;
  esac

  mkdir -p "${MANAGER_BASE}/tmp" 2>/dev/null || true
  _check_update >"$UPDATE_WARN_FILE" 2>&1 &
  UPDATE_CHECK_PID=$!

  if [[ ! -f "$INSTALLED_FLAG" ]]; then
    local _sym_mgr=1 _sym_conf=1 _sym_node=1
    [[ -f "$MANAGER_CONFIG" ]]  || _sym_mgr=0
    [[ -f "$LANDING_CONF" ]]    || _sym_conf=0
    while IFS= read -r _nconf; do
      [ -f "$_nconf" ] || continue
      local _ndom; _ndom=$(grep '^DOMAIN=' "$_nconf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "")
      [[ -n "$_ndom" && -f "${CERT_BASE}/${_ndom}/fullchain.pem" ]] || { _sym_node=0; break; }
    done < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f -maxdepth 1 2>/dev/null)
    [[ -z $(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f -maxdepth 1 2>/dev/null) ]] && _sym_node=0
    if (( _sym_mgr && _sym_conf && _sym_node )); then
      warn "[v2.9] 持久化集完整但安装标记缺失（崩溃于最后一步），自动恢复标记..."
      touch "$INSTALLED_FLAG"
      # fall through to the installed branch below
    fi
  fi

  if [[ -f "$INSTALLED_FLAG" ]]; then
    # remove the marker when it is incomplete.
    local _durable_ok=1
    [[ -f "$MANAGER_CONFIG" ]]                                          || _durable_ok=0
    [[ -f "$LANDING_CONF" ]]                                            || _durable_ok=0
    find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" \
         -type f -maxdepth 1 2>/dev/null | grep -q . 2>/dev/null       || _durable_ok=0
    if (( _durable_ok == 0 )); then
      warn "[v2.8] 安装标记存在但持久化集（manager.conf/config.json/nodes/*.conf）不完整，清除标记重新安装..."
      rm -f "$INSTALLED_FLAG"
      find "${MANAGER_BASE}" /tmp -maxdepth 1 -name '.manager.*' -type f -delete 2>/dev/null || true
      fresh_install
      return
    fi
    load_manager_config
    local _svc_ok=0 _conf_ok=0 _node_ok=0
    systemctl is-active --quiet "$LANDING_SVC" 2>/dev/null && _svc_ok=1 \
      || warn "服务未运行"
    [[ -f "$MANAGER_CONFIG" ]] && _conf_ok=1 \
      || warn "manager.conf 缺失（真相源丢失）"
    local _nc; _nc=$(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | wc -l)
    (( _nc > 0 )) && _node_ok=1
    if (( _svc_ok == 0 && _conf_ok == 0 && _node_ok == 0 )); then
      warn "安装标记存在但三态（服务/配置/节点）全部缺失，清除标记重新安装..."
      rm -f "$INSTALLED_FLAG"
      fresh_install
      return
    fi
    if (( _conf_ok == 0 )); then
      die "manager.conf（真相源）已丢失，无法安全操作。请执行 --uninstall 清除后重装，或从备份恢复 ${MANAGER_CONFIG}"
    fi
    if (( _svc_ok == 0 )); then
      warn "服务未运行，尝试自动恢复..."
      local _recovered=0
      if ( sync_xray_config ) 2>/dev/null && systemctl restart "$LANDING_SVC" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "$LANDING_SVC" 2>/dev/null; then
          success "服务已恢复运行"
          _recovered=1
        fi
      fi
      if (( _recovered == 0 )); then
        error "自动恢复失败，拒绝进入管理菜单（防止在分裂状态上继续写操作）"
        echo -e "  请先执行: ${CYAN}bash $0 --status${NC} 排查状态分裂"
        echo -e "  若无法修复，请执行: ${CYAN}bash $0 --uninstall${NC} 清除后重装"
        exit 1
      fi
    fi
    installed_menu
  else
    if [[ -n "${LANDING_AUTO_DOMAIN:-}" ]]; then
      fresh_install_headless
    else
      fresh_install
    fi
  fi
}

main "$@"
