#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# v3.34-Optimized 变更记录
# - 更新版本号至 v3.34-Optimized
# - 修正 SSH 端口恢复探测的 ss 兜底仅取首条端口，避免多行输出误判
# - journald 上限应用改为 restart，确保 sysctl/journal drop-in 立即生效
# - 保持 flock FD 关闭、IPv6 探测、firewall bulldozer/connlimit、meta/map 回收修正
# - 保持 detect_ssh_port_override 的 1-65535 范围校验与 non-strict 订阅生成
# - 保持 IPv6 ICMP 限速、Token 导入强化、sysctl 运行态回收与 marker 化 nginx tuning
# install_transit_v3.34-Optimized.sh — 中转机安装脚本 v3.34-Optimized

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
readonly VERSION="v3.34-Optimized"
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
readonly UPDATE_WARN_FILE="/var/run/transit-manager.update.warn"

[[ $EUID -eq 0 ]] || die "必须以 root 身份运行"

find /etc/transit_manager /etc/nginx /etc/systemd/system \
  -maxdepth 5 -name '.snap-recover.*' -mtime +1 -delete 2>/dev/null || true

_global_cleanup(){
  find /etc/transit_manager /etc/nginx \
    /etc/systemd/system /etc/logrotate.d \
    -maxdepth 5 \
    \( -name '.transit-mgr.*' -o -name '.snap-recover.*' \) \
    -type f -delete 2>/dev/null || true
  find "${MANAGER_BASE}/tmp" \
    -maxdepth 1 -type f \
    \( -name '.transit-mgr.*' -o -name '.snap-recover.*' -o -name '.nginx-conf-snap.*' \) \
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
trap 'echo -e "\n${RED}[中断] 安装已中断。如需清理残留，请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

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
  tmp="$(mktemp "$dir/.transit-mgr.XXXXXX")" \
    || { echo "atomic_write: mktemp failed for $dir" >&2; exit 1; }
  trap 'rm -f "$tmp" 2>/dev/null || true' EXIT
  cat >"$tmp" \
    || { echo "atomic_write: cat to $tmp failed" >&2; exit 1; }
  chmod "$mode" "$tmp" \
    || { echo "atomic_write: chmod failed for $tmp" >&2; exit 1; }
  chown "$owner_group" "$tmp" 2>/dev/null \
    || { echo "atomic_write: chown failed for $tmp" >&2; exit 1; }
  mv -f "$tmp" "$target" \
    || { echo "atomic_write: mv $tmp -> $target failed" >&2; exit 1; }
)

readonly TRANSIT_LOCK_FILE="${MANAGER_BASE}/tmp/transit-manager.lock"
_acquire_lock(){
  mkdir -p "${MANAGER_BASE}/tmp"
  exec 200>"$TRANSIT_LOCK_FILE"
  flock -w 10 200 || die "配置正在被其他进程修改，请稍后重试（等待超时 10s）"
}
_release_lock(){ flock -u 200 2>/dev/null || true; exec 200>&- 2>/dev/null || true; }

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
      echo -e "${RED}[FATAL]${NC} 无法探测 SSH 端口（sshd -T、ss、sshd_config 均失败）。" \
      "请以 detect_ssh_port_override=<端口> 环境变量指定后重试。" >&2
      exit 1
    fi
  fi
  printf '%s\n' "$p"
}

validate_domain(){
  local d
  d="$(trim "$1")"
  (( ${#d} >= 4 && ${#d} <= 253 )) || die "域名长度非法 (${#d}): $d"
  [[ "$d" == *"."* ]] || die "域名必须包含至少一个点: $d"
  printf '%s' "$d" | python3 -c "import sys,re; d=sys.stdin.read().strip(); pat=re.compile(r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z0-9]{2,}$'); sys.exit(0 if pat.match(d) else 1)" >/dev/null 2>&1 || die "域名格式非法: $d"
}

validate_ipv4(){
  local ip="$1"
  printf '%s' "$ip" | python3 -c "import ipaddress, sys
ip = sys.stdin.read().strip()
try:
    a = ipaddress.IPv4Address(ip)
    if a.is_loopback or a.is_private or a.is_link_local or a.is_multicast or a.is_reserved or a.is_unspecified:
        sys.exit(1)
except:
    sys.exit(1)
" >/dev/null 2>&1 || die "IPv4 格式非法: $ip"
}

validate_ip(){
  local ip="$1"
  [[ "$ip" =~ : ]] && die "拓扑冲突：中转机无 IPv6 路由时（CN2GIA），严禁使用 IPv6 落地机地址: $ip"
  validate_ipv4 "$ip"
}

validate_port(){
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || die "端口格式非法: $p"
  (( p >= 1 && p <= 65535 )) || die "端口超范围（1-65535）: $p"
}

domain_to_safe()  {
  local raw
  local hash
  raw="$(printf '%s' "$1" | tr '.' '_' | tr -cd 'a-zA-Z0-9_-')"
  hash="$(printf '%s' "$1" | sha256sum | cut -c1-64)"
  printf '%s_%s' "${raw:0:60}" "$hash"
}
nginx_domain_str(){ printf '%s' "$1" | tr -cd 'a-zA-Z0-9._-'; }
nginx_ip_str()    { printf '%s' "$1" | tr -cd 'a-zA-Z0-9.'; }
read_meta_ip()    { awk -F= '/^(TRANSIT_IP|IP)=/{print $2; exit}' "$1"; }
_meta_drift_detect(){
  [[ -d "$SNIPPETS_DIR" && -d "$CONF_DIR" ]] || return 1
  local _mf _mdom _msafe _bad=0
  while IFS= read -r _mf; do
    [[ -f "$_mf" ]] || continue
    _mdom=$(grep '^DOMAIN=' "$_mf" 2>/dev/null | cut -d= -f2- || true)
    [[ -n "$_mdom" ]] || continue
    _msafe=$(domain_to_safe "$_mdom")
    [[ -f "${SNIPPETS_DIR}/landing_${_msafe}.map" ]] || { _bad=1; break; }
  done < <(find "$CONF_DIR" -maxdepth 1 -type f -name '*.meta' 2>/dev/null | sort)
  return $_bad
}
_route_key_conflict(){
  local _dom="$1" _exclude="${2:-}" _needle _paths _conflict=""
  _needle=$(nginx_domain_str "$_dom")
  [[ -d "$SNIPPETS_DIR" ]] || return 0
  _paths=$(find "$SNIPPETS_DIR" -maxdepth 1 -type f -name 'landing_*.map' 2>/dev/null     | while IFS= read -r _map; do
        awk -v d="$_needle" '$1 == d {print FILENAME; exit}' "$_map" 2>/dev/null || true
      done)
  if [[ -n "${_exclude:-}" && -n "${_paths:-}" ]]; then
    _paths=$(printf '%s\n' "$_paths" | grep -vFx -- "$_exclude" 2>/dev/null || true)
  fi
  _conflict=$(printf '%s\n' "${_paths:-}" | sed '/^$/d' | head -1)
  printf '%s' "$_conflict"
}

_prune_orphan_stream_maps(){
  [[ -d "$SNIPPETS_DIR" ]] || return 0
  local _map _safe _pruned=0
  while IFS= read -r _map; do
    [[ -f "$_map" ]] || continue
    _safe="${_map##*/landing_}"
    _safe="${_safe%.map}"
    if [[ ! -f "${CONF_DIR}/${_safe}.meta" ]]; then
      rm -f "$_map" 2>/dev/null || true
      _pruned=1
    fi
  done < <(find "$SNIPPETS_DIR" -maxdepth 1 -type f -name 'landing_*.map' 2>/dev/null | sort)
  if (( _pruned )) && systemctl is-active --quiet nginx 2>/dev/null; then
    nginx_reload 2>/dev/null || warn "已清理孤儿 .map，但 Nginx 重载失败，请手动检查"
  fi
}

get_public_ip(){
  [[ -n "${TRANSIT_PUBLIC_IP:-}" ]] && { validate_ip "$TRANSIT_PUBLIC_IP"; printf "%s" "$TRANSIT_PUBLIC_IP"; return 0; }
  local _strict=0
  [[ "${1:-}" == "--strict" ]] && _strict=1
  local _ip=""
  local _src
  for _src in     "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip"     "http://169.254.169.254/latest/meta-data/public-ipv4"     "https://api.ipify.org"     "https://ifconfig.me"     "https://ipecho.net/plain"     "https://checkip.amazonaws.com"; do
    if [[ "$_src" == *"metadata.google.internal"* ]]; then
      _ip=$(curl -4 -fsSL --connect-timeout 3 --max-time 5 --retry 2 -H "Metadata-Flavor: Google" "$_src" 2>/dev/null | tr -d '[:space:]') || true
    else
      _ip=$(curl -4 -fsSL --connect-timeout 3 --max-time 5 --retry 2 "$_src" 2>/dev/null | tr -d '[:space:]') || true
    fi
    [[ -n "$_ip" ]] && break
  done
  if [[ -z "$_ip" ]]; then
    if (( _strict )); then
      die "无法获取中转机公网 IPv4，节点订阅无法生成。请检查网络或手动指定: TRANSIT_PUBLIC_IP=x.x.x.x bash $0 --import <token>"
    else
      warn "无法获取中转机公网 IP，展示将使用占位符 <TRANSIT_IP>"
      _ip="<TRANSIT_IP>"
    fi
  fi
  printf '%s' "$_ip"
}

show_help(){
  cat 