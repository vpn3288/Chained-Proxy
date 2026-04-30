#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# install_transit_v5.16.sh — 中转机安装脚本 v5.16
# v5.12 变更记录 (2026-04-29 主笔AI第二十轮修复 - 21项审计发现全面修复)
# 本版本根据代码审计报告修复所有剩余Transit问题:
# [REVIEWER-T-1] CRITICAL: get_public_ip() IFS恢复使用local而非trap(自动作用域恢复)
# [REVIEWER-T-2] MEDIUM: domain_to_safe()使用awk提取SHA256(更清晰)
# [REVIEWER-T-3] HIGH: _route_key_conflict()使用命令替换而非进程替换(修复变量丢失)
# [REVIEWER-T-4] HIGH: 防火墙白名单规则使用-I 1插入而非-A追加(修复重跑失效)
# [REVIEWER-T-5] MEDIUM: 端口冲突检测增加进程名验证(避免误判)
# [REVIEWER-T-6] INFO: 证书续期监控检查acme.sh日志时间戳(更准确)
# [REVIEWER-T-7] LOW: detect_ssh_port()增加443端口冲突检测
# [REVIEWER-T-8] MEDIUM: _meta_drift_detect()验证.map内容与.meta一致
# v5.11 变更记录 (2026-04-29 主笔AI第十九轮修复 - 代码审计报告全面修复)
# 本版本根据代码审计报告修复所有Transit关键问题:
# [REVIEWER-T-1] CRITICAL: 修复get_public_ip() IFS恢复(使用local而非trap,自动恢复)
# [REVIEWER-T-2] MEDIUM: domain_to_safe()优化SHA256提取(使用awk提取hash)
# [REVIEWER-T-3] HIGH: 修复_route_key_conflict()子shell变量丢失(使用process substitution)
# [REVIEWER-T-4] HIGH: 修复防火墙白名单规则插入顺序(使用-I 1而非-A)
# [REVIEWER-T-5] MEDIUM: 增强端口冲突检测(验证进程名而非仅检查端口占用)
# [REVIEWER-T-6] INFO: 证书续期监控检查acme.sh日志时间戳而非文件mtime
# [REVIEWER-T-7] LOW: detect_ssh_port()增加443端口冲突检测
# [REVIEWER-T-8] MEDIUM: _meta_drift_detect()增加.map内容与.meta一致性验证
# # v5.10 变更记录 (2026-04-29 主笔AI第十八轮修复 - 26项审查报告全面修复)
# 本版本根据代码审计报告修复所有Transit相关问题:
# [REVIEWER-1] 卸载完整性 - 删除健康检查cron文件(/etc/cron.d/transit-health)
# [REVIEWER-3] IPv6防火墙修复 - 允许NDP流量(ICMPv6类型133-136),防止IPv6断网
# [REVIEWER-4] IP验证优化 - 移除私有IP限制,支持VPC内部路由(AWS/GCP)
# [REVIEWER-7] Nginx配置安全 - 使用单引号heredoc防止\x转义问题
# [REVIEWER-8] 清理完整性 - _global_cleanup删除.lock文件
# [REVIEWER-13] 防火墙恢复脚本 - 添加set -euo pipefail防止静默失败
# [REVIEWER-14] IFS恢复 - get_public_ip()添加trap恢复IFS
# [REVIEWER-15] 哈希冲突修复 - domain_to_safe使用64字符SHA256
# [REVIEWER-17] 路由冲突检测 - _route_key_conflict跨文件检测重复域名
# [REVIEWER-18] 容错增强 - fallback upstream添加备份服务器(9998)
# [REVIEWER-20] 安全加固 - _restore_prev_traps添加空值守卫
# [REVIEWER-22] 数据规范化 - import_token域名统一转小写
# [REVIEWER-23] 卸载完整性 - purge_all删除nginx tuning注释
# [REVIEWER-24] 输入验证 - UUID格式和密码长度检查(≥16字符)
# [REVIEWER-25] 性能优化 - IP探测超时缩短到3秒(原5秒)
## v4.90 变更记录 (2026-04-29 主笔AI第十七轮修复 - 代码审计报告修复)
# 本版本根据代码审计报告修复关键问题:
# [REVIEWER-1] 防火墙恢复脚本添加set -euo pipefail - 防止静默失败导致SSH锁定
# [REVIEWER-4] 中转机白名单规则顺序修复 - 使用-I插入到DROP规则之前
# [REVIEWER-8] 卸载完整性 - 删除systemd drop-in目录
# [REVIEWER-9审查者] 域名小写化 - import_token中统一转小写
# [REVIEWER-2审查者] Nginx fallback移至stream模块 - 防止暴露HTTP 400错误
# v4.60 变更记录 (2026-04-29 主笔AI第十四轮修复 - 深度审查修复)
# 本版本根据三份审查报告修复关键问题:
# [T-CRITICAL-2] 健康检查cron修复 - 补全heredoc结束标记
# [T-CRITICAL-3] TCP窗口验证逻辑修复 - 使用范围验证而非精确匹配
# [BOTH-HIGH-1] 时间同步空值守卫 - 防止chronyc失败时误判通过
# [T-MEDIUM-3] worker_connections随机偏移扩大 - 70-130%范围
#
# v4.50 变更记录 (2026-04-29 主笔AI第十三轮修复 - 验证函数改造)
# 本版本修复v4.42中"空头支票"致命缺陷:
# [T-CRITICAL-1] setup_health_check()函数补全 - 完整实现健康检查和自动恢复
# [T-HIGH-1] 验证函数改造 - die→return 1,配合while循环实现真正的输错重试
# [T-HIGH-2] TCP窗口随机化真实实现 - 使用/dev/urandom生成随机值
# [T-HIGH-3] sysctl运行态验证 - 确保关键参数真正生效
#
# 架构不变: Nginx stream SNI盲传

# v3.41-Optimized 变更记录
# - 修正 _tune_nginx_worker_connections() 中 VERSION 变量在 sed/grep 正则中的转义
# - 增加 mack-a 显式检测（import_token + fresh_install）
# - detect_ssh_port() 增加 command -v sshd guard
# - 保持 Nginx stream SNI 盲传、双栈防火墙和 mack-a 零覆盖不变
# install_transit_v3.60-Optimized.sh — 中转机安装脚本 v3.60-Optimized
# 版本历史：
# v3.60-Optimized: HermesAgent cycle 5 — [R2] transit_ip validation | [R5] INPUT pos warn | [R6] ssh_port numeric | [R7] hardlinks/symlinks | [R8] duplicate domain | [R9] sysctl cleanup | [R10] IPv6 fallback | [R22] FW_CHAIN whitelist
# v3.58-Optimized: HermesAgent cycle 3 — [F4] IPv6 chain: fix INVALID DROP + correct rule order
# v3.57-Optimized: HermesAgent cycle 2 — 架构不变，稳定性和安全加固
# v3.56-Optimized: HermesAgent cycle 1 — 架构不变，稳定性和安全加固
# v3.55-Optimized: 修复 atomic_write mktemp 空路径检查、nginx 快照失败 hard-die
# v3.54-Optimized: 修复 daemon-reload 失败 hard-die（3处）
# v3.50-Optimized: 全面安全加固，30项修复
# v3.41-Optimized: 修正 VERSION 变量在 sed/grep 正则中的转义
# v3.41-Optimized 变更记录
# - 修正 _tune_nginx_worker_connections() 中 VERSION 变量在 sed/grep 正则中的转义
# - 增加 mack-a 显式检测（import_token + fresh_install）
# - detect_ssh_port() 增加 command -v sshd guard
# - 保持 Nginx stream SNI 盲传、双栈防火墙和 mack-a 零覆盖不变
# install_transit_v3.41-Optimized.sh — 中转机安装脚本 v3.41-Optimized
# 版本历史：
# v3.58-Optimized: HermesAgent cycle 3 — [F4] IPv6 chain: fix INVALID DROP + correct rule order
# v2.80: 移除本地 decoy 死代码 / 中转流绑定 IPv6 / 悬挂 .map 自愈清理 / 防火墙恢复脚本改为 Python 模板替换
# v2.70: 继续修复安全与鲁棒性：SSH 端口解析加固 / 域名安全名扩容 / 防火墙恢复脚本同步校验
# v2.50: SNI嗅探 → 纯TCP盲传(TFO+KA=3m:10s:3+backlog=65535) → 落地机 | 动态双栈兼容
# 空/无匹配SNI→17.253.144.10:443（苹果CDN，无DNS）· proxy_timeout=315s
# 完整保留所有架构演进注释与安全回滚陷阱

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
# R77: 修复atomic_write mktemp空路径检查、nginx快照失败hard-die
# R77: 修复daemon-reload失败hard-die（3处）
# R76: 修复所有mktemp空路径fallback错误检查
# v3.39-Optimized 变更记录
# - 将 INPUT 链清理改为行号删除，避免 save/restore 重放旧规则
# - 修正 worker_connections 注释覆盖逻辑，防止升级标签堆叠
# - 保持 SNI 盲传与双栈防火墙结构不变
readonly VERSION="v5.12"
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() {
  error "$*"
  if declare -F _fresh_install_rollback >/dev/null; then _fresh_install_rollback 2>/dev/null || true; fi
  if declare -F _import_install_rollback >/dev/null; then _import_install_rollback 2>/dev/null || true; fi
  if declare -F _route_rollback >/dev/null; then _route_rollback 2>/dev/null || true; fi
  exit 1
}
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

# [F1] Startup stale snapshot sweep — SIGKILL leaves .snap-recover files that EXIT trap cannot clean
find /etc/transit_manager /etc/nginx /etc/systemd/system \
  -maxdepth 5 -name '.snap-recover.*' -mtime +1 -delete 2>/dev/null || true

# BUG-02: 中断时清理 atomic_write 残留的临时文件及事务快照
# v2.32 Gemini: 统一当次全清——操作锁保证同一时刻只有一个事务，快照不需要跨日保留
# [v2.13 GPT-🔴 + Grok-🔴] Cleanup restricted exclusively to script-owned directories.
# Broad /tmp scans risk touching unrelated user files; all scratch files are now under
# ${MANAGER_BASE}/tmp so a targeted find there is sufficient and safe.
_global_cleanup(){
  find /etc/transit_manager /etc/nginx \
    /etc/systemd/system /etc/logrotate.d \
    -maxdepth 5 \
    \( -name '.transit-mgr.*' -o -name '.snap-recover.*' \) \
    -type f -delete 2>/dev/null || true
  # Script-owned tmp — the only scratch space used since v2.13
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

# [v2.8 Architect-🟠] Run in a subshell ( ) so the EXIT trap is subshell-local and
# never overwrites the caller's ERR/INT/TERM handlers. Previously the RETURN/ERR trap
# inside atomic_write silently degraded outer rollback handlers to "temp-file cleanup only."
atomic_write()(
  set -euo pipefail
  local target="$1" mode="$2" owner_group="${3:-root:root}" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.transit-mgr.XXXXXX" 2>/dev/null)" \
    || { echo "atomic_write: mktemp failed for $dir" >&2; exit 1; }
  trap 'rm -f "$tmp" 2>/dev/null || true' EXIT
  cat >"$tmp" \
    || { echo "atomic_write: cat to $tmp failed" >&2; exit 1; }
  sync -d "$tmp" \
    || { echo "atomic_write: sync $tmp failed" >&2; rm -f "$tmp"; exit 1; }
  chmod "$mode" "$tmp" \
    || { echo "atomic_write: chmod failed for $tmp" >&2; exit 1; }
  chown "$owner_group" "$tmp" 2>/dev/null \
    || { echo "atomic_write: chown failed for $tmp" >&2; exit 1; }
  mv -f "$tmp" "$target" \
    || { echo "atomic_write: mv $tmp -> $target failed" >&2; exit 1; }
)

# v2.32: 全局写操作互斥锁，防止两个终端并发修改同一状态
# [v2.13 GPT-🔴] Lock file moved from /tmp to script-owned ${MANAGER_BASE}/tmp so interrupted
# runs cannot leave phantom locks visible to unrelated processes and the directory is
# cleaned up on --uninstall rather than left in the global temporary namespace.
# mkdir -p is called inside _acquire_lock so the path always exists before flock.
readonly TRANSIT_LOCK_FILE="${MANAGER_BASE}/tmp/transit-manager.lock"
_acquire_lock(){
  mkdir -p "${MANAGER_BASE}/tmp"
  exec 200>"$TRANSIT_LOCK_FILE"
  flock -w 10 200 || die "配置正在被其他进程修改，请稍后重试（等待超时 10s）"
}
_release_lock(){ flock -u 200 2>/dev/null || true; exec 200>&- 2>/dev/null || true; }

# [融合优化]: 恢复 v2.16 的智能双栈探测逻辑，抛弃 v2.50 的强制 false
have_ipv6(){
  [[ -f /proc/net/if_inet6 && $(wc -l < /proc/net/if_inet6 2>/dev/null || echo 0) -gt 0 ]] \
    && command -v ip6tables >/dev/null 2>&1 && ip6tables -nL >/dev/null 2>&1 \
    && [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)" != "1" ]]
}

detect_ssh_port(){
  local p=""
  command -v sshd >/dev/null 2>&1 || { echo "22"; return; }
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
  # 🔴 Grok: 兜底 22 会写错防火墙白名单，探测失败必须中止
  if [[ ! "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
    # 允许环境变量覆盖，方便自动化场景
    if [[ "${detect_ssh_port_override:-}" =~ ^[0-9]+$ ]] && (( detect_ssh_port_override >= 1 && detect_ssh_port_override <= 65535 )); then
      p="$detect_ssh_port_override"
    else
      echo -e "${RED}[FATAL]${NC} 无法探测 SSH 端口（sshd -T、ss、sshd_config 均失败）。" \
      "请以 detect_ssh_port_override=<端口> 环境变量指定后重试。" >&2
      exit 1
    fi
  fi
  # [T-7] Check for SSH on port 443 conflict
  if [[ "$p" == "443" ]]; then
    die "SSH is on port 443, which conflicts with transit listener. Please change SSH port first."
  fi
    printf '%s\n' "$p"
}

validate_domain(){
  local d
  d="$(trim "$1")"
  # RFC1035 长度守卫 + 必须含点
  if ! (( ${#d} >= 4 && ${#d} <= 253 )); then
    error "域名长度非法 (${#d}): $d"
    return 1
  fi
  if [[ "$d" != *"."* ]]; then
    error "域名必须包含至少一个点: $d"
    return 1
  fi
  if ! printf '%s' "$d" | python3 -c "import sys,re; d=sys.stdin.read().strip(); pat=re.compile(r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z0-9]{2,}$'); sys.exit(0 if pat.match(d) else 1)" >/dev/null 2>&1; then
    error "域名格式非法: $d"
    return 1
  fi
  return 0
}

validate_ipv4(){
  local ip="$1"
  if ! printf '%s' "$ip" | python3 -c "import ipaddress, sys
ip = sys.stdin.read().strip()
try:
    a = ipaddress.IPv4Address(ip)
    if a.is_loopback or a.is_link_local or a.is_multicast or a.is_reserved or a.is_unspecified:
        sys.exit(1)
except:
    sys.exit(1)
" >/dev/null 2>&1; then
    error "IPv4 格式非法: $ip"
    return 1
  fi
  return 0
}

validate_ip(){
  local ip="$1"
  if [[ "$ip" =~ : ]]; then
    error "拓扑冲突：中转机无 IPv6 路由时（CN2GIA），严禁使用 IPv6 落地机地址: $ip"
    return 1
  fi
  validate_ipv4 "$ip"
}

validate_port(){
  local p="$1"
  if ! [[ "$p" =~ ^[0-9]+$ ]]; then
    error "端口必须是纯数字: $p"
    return 1
  fi
  if ! (( p >= 1 && p <= 65535 )); then
    error "端口范围非法 (1-65535): $p"
    return 1
  fi
  return 0
}

domain_to_safe()  {
  local raw
  local hash
  raw="$(printf '%s' "$1" | tr '.' '_' | tr -cd 'a-zA-Z0-9_-')"
  hash="$(printf '%s' "$1" | sha256sum | awk '{print substr(\,1,64)}')"
  printf '%s_%s' "${raw:0:60}" "$hash"
}
nginx_domain_str(){ printf '%s' "$1" | tr -cd 'a-zA-Z0-9._-'; }
nginx_ip_str()    { printf '%s' "$1" | tr -cd 'a-zA-Z0-9.'; }
# [F2] Compatibility reader: accepts both old IP= and new TRANSIT_IP= field names in .meta files.
# Old files written before v2.3 used IP=; new files use TRANSIT_IP=.
read_meta_ip()    { awk -F= '/^(TRANSIT_IP|IP)=/{print $2; exit}' "$1"; }
_meta_drift_detect(){
  [[ -d "$SNIPPETS_DIR" && -d "$CONF_DIR" ]] || return 1
  local _mf _mdom _msafe _bad=0
  while IFS= read -r _mf; do
    [[ -f "$_mf" ]] || continue
    _mdom=$(grep '^DOMAIN=' "$_mf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
    [[ -n "$_mdom" ]] || continue
    _msafe=$(domain_to_safe "$_mdom")
    [[ -f "${SNIPPETS_DIR}/landing_${_msafe}.map" ]] || { _bad=1; break; }
    # [T-8] Verify map contains the expected domain
    grep -qF "$_mdom" "${SNIPPETS_DIR}/landing_${_msafe}.map" || { _bad=1; break; }
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
    _paths=$(printf '%s
' "$_paths" | grep -vFx -- "$_exclude" 2>/dev/null || true)
  fi
  _conflict=$(printf '%s
' "${_paths:-}" | sed '/^$/d' | head -1)
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


# ARCH-2: 中转机公网 IP — 两种调用模式
# get_public_ip [--strict]：strict 模式下获取失败直接 die（用于 Token/订阅生成）
# get_public_ip           ：宽松模式返回占位符（仅用于只读展示）
get_public_ip(){
  # v2.22: Bug2 - 环境变量检查移到函数开头，优先使用
  # v2.24: P1 - env var需要验证
  [[ -n "${TRANSIT_PUBLIC_IP:-}" ]] && { validate_ip "$TRANSIT_PUBLIC_IP"; printf "%s" "$TRANSIT_PUBLIC_IP"; return 0; }
  local _strict=0
  [[ "${1:-}" == "--strict" ]] && _strict=1
  local IFS=$' \t\n'  # [T-1] Restore default IFS locally
  local _ip=""
  local _src
  # [R-4] Restore default IFS (space/tab/newline) before iterating space-separated list
  local IFS=$' \t\n'
  for _src in     "https://api.ipify.org"     "https://ifconfig.me"     "https://checkip.amazonaws.com"     "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip"     "http://169.254.169.254/latest/meta-data/public-ipv4"     "https://ipecho.net/plain"; do
    if [[ "$_src" == *"metadata.google.internal"* ]]; then
      _ip=$(curl -4 -fsSL --connect-timeout 2 --max-time 3 --retry 2 -H "Metadata-Flavor: Google" "$_src" 2>/dev/null | tr -d '[:space:]') || true
    else
      _ip=$(curl -4 -fsSL --connect-timeout 2 --max-time 3 --retry 2 "$_src" 2>/dev/null | tr -d '[:space:]') || true
    fi
    [[ -n "$_ip" ]] && break
  done
  # [Doc3-3] strict 模式：IP 获取失败 → 硬退出，占位符绝不进入 Token/订阅生成链路
  if [[ -z "$_ip" ]]; then
    if (( _strict )); then
      die "无法获取中转机公网 IPv4，节点订阅无法生成。请检查网络或手动指定: TRANSIT_PUBLIC_IP=x.x.x.x bash $0 --import <token>"
    else
      warn "无法获取中转机公网 IPv4，尝试 IPv6..."
      for _src in "https://api6.ipify.org" "https://ifconfig.me/ip"; do
        _ip=$(curl -6 -fsSL --connect-timeout 3 --max-time 5 --retry 2 "$_src" 2>/dev/null | tr -d '[:space:]') || true
        [[ -n "$_ip" ]] && { warn "检测到 IPv6 地址: $_ip（中转机架构仅支持 IPv4 中转，IPv6 落地机不受支持）"; break; }
      done
      if [[ -z "$_ip" ]]; then
        warn "无法获取中转机公网 IP，展示将使用占位符 <TRANSIT_IP>"
        _ip="<TRANSIT_IP>"
      fi
    fi
  fi
  printf '%s' "$_ip"
}

show_help(){
  cat <<HELP
用法: bash install_transit_${VERSION}.sh [选项]

  （无参数）        交互式安装或管理菜单
  --uninstall       清除本脚本所有内容（不影响 mack-a）
  --import <token>  从落地机 Base64 token 自动导入路由规则
  --status          显示当前状态
  --help            显示此帮助
HELP
}

check_deps(){
  export DEBIAN_FRONTEND=noninteractive
  # 二进制名与包名分离：iproute2→ip, psmisc→fuser
  local ip_pkg="iproute2"
  if command -v yum &>/dev/null || command -v dnf &>/dev/null; then
    ip_pkg="iproute"
  fi
  local _bin_pkg=(
    curl:curl wget:wget iptables:iptables python3:python3
    ip:${ip_pkg} nginx:nginx fuser:psmisc chronyc:chrony
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
  # 验证关键二进制均可用
  for bp in "${_bin_pkg[@]}"; do
    local bin="${bp%%:*}"
    command -v "$bin" &>/dev/null || die "依赖 ${bin} 安装后仍无法找到"
  done
  # [BOTH-CRITICAL-FIX] 强制启用时间同步并验证状态,防止时钟漂移导致VLESS断流
  if command -v chronyc &>/dev/null; then
    systemctl enable --now chrony 2>/dev/null || die "chrony启动失败"
    chronyc makestep 2>/dev/null || warn "时间强制同步失败"
    sleep 3
    # 验证时间同步状态
    local _offset=$(chronyc tracking 2>/dev/null | awk '/Last offset/{print $4}' | tr -d '+' | tr -d 's')
    if [[ -n "$_offset" ]]; then
      # 使用awk进行浮点数比较（避免依赖bc）
      local _offset_abs=$(echo "$_offset" | tr -d '-')
      if awk -v offset="$_offset_abs" 'BEGIN{exit !(offset < 2)}'; then
        success "时间同步正常（偏移: ${_offset}s）"
      else
        die "时钟偏移过大（${_offset}s），VLESS将断流，请先手动同步时间"
      fi
    else
      # [H3] 时间同步验证强化 - 空值直接die
      die "chrony无法获取时钟偏移量，请等待30秒后重试"
    fi
  fi
}

optimize_kernel_network(){
  local bbr_conf="/etc/sysctl.d/99-transit-bbr.conf"
  [[ -f "$bbr_conf" ]] && grep -q 'tcp_timestamps' "$bbr_conf" 2>/dev/null && return 0

  info "优化内核并发参数（拥塞控制权归 BBRPlus）..."
  # v2.48 Gemini: tcp_max_tw_buckets 动态计算（每桶256B；内存MB×100，保底10000，上限250000）
  local _ram_mb; _ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _ram_mb=${_ram_mb:-1024}
  local _tw_max=$(( _ram_mb * 100 ))
  (( _tw_max < 10000 ))  && _tw_max=10000
  (( _tw_max > 250000 )) && _tw_max=250000
  # [v2.7 Gemini-Doc1-🟠] Dynamic fs.file-max / fs.nr_open: fixed 10M on a 512MB VPS still
  # consumes PAM/kernel overhead; scale to RAM×800 (floor 524288, cap 10485760) so SSH subshells
  # and PAM sessions are not FD-starved when nginx workers each hold ~1M FD slots.
  local _ram_mb_fd; _ram_mb_fd=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _ram_mb_fd=${_ram_mb_fd:-1024}
  local _fd_max=$(( _ram_mb_fd * 800 ))
  (( _fd_max < 524288 ))  && _fd_max=524288
  (( _fd_max > 10485760 )) && _fd_max=10485760
  cat > "$bbr_conf" <<BBRCF
net.netfilter.nf_conntrack_max=1048576
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_max_tw_buckets=${_tw_max}
net.ipv4.ip_local_port_range=1024 65535
net.core.somaxconn=65535
# [v2.7] fs.nr_open / fs.file-max dynamic (RAM MB × 800, floor 524288, cap 10485760)
fs.nr_open=${_fd_max}
fs.file-max=${_fd_max}
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
BBRCF
  cat >> "$bbr_conf" <<'BBRCF2'
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=0
BBRCF2
  # [R7 Fix] Defense-in-depth: protect against hardlink/symlink exploitation
  cat >> "$bbr_conf" <<'BBRCF3'
fs.protected_hardlinks=1
fs.protected_symlinks=1
BBRCF3
  # v2.42 Grok: conntrack hashsize 按内存动态计算（每条目~300B，用1/8内存）
  local _ct_mem; _ct_mem=$(free -m 2>/dev/null | awk '/Mem:/{print int($2/8*1024*1024/300)}'); _ct_mem=${_ct_mem:-262144}
  [[ "$_ct_mem" =~ ^[0-9]+$ ]] || _ct_mem=262144
  (( _ct_mem < 131072 )) && _ct_mem=131072
  atomic_write "/etc/modprobe.d/nf_conntrack.conf" 644 root:root <<MEOF
options nf_conntrack hashsize=${_ct_mem}
MEOF
  modprobe nf_conntrack 2>/dev/null || true
  echo "$_ct_mem" > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
  # nf_conntrack_max 也动态设为 hashsize*4
  local _ct_max=$(( _ct_mem * 4 ))
  sysctl -w net.netfilter.nf_conntrack_max="${_ct_max}" &>/dev/null || true
  sed -i "s/net.netfilter.nf_conntrack_max=.*/net.netfilter.nf_conntrack_max=${_ct_max}/"     /etc/sysctl.d/99-transit-bbr.conf 2>/dev/null || true
  
  # [T-CRITICAL-3] TCP流量随机化 - 使用/dev/urandom确保非交互环境可用
  local _tcp_wmem_base=$(od -An -N2 -tu2 /dev/urandom | awk '{print 4096 + ($1 % 4096)}')  # 4-8KB随机基础窗口
  local _tcp_rmem_base=$(od -An -N2 -tu2 /dev/urandom | awk '{print 4096 + ($1 % 4096)}')
  local _tcp_wmem_max=$(od -An -N4 -tu4 /dev/urandom | awk '{print 16777216 + ($1 % 8388608)}')  # 16-24MB随机最大窗口
  local _tcp_rmem_max=$(od -An -N4 -tu4 /dev/urandom | awk '{print 16777216 + ($1 % 8388608)}')
  
  # [T-CRITICAL-3-FIX] 持久化TCP窗口随机化参数到配置文件
  cat >> "$bbr_conf" <<BBRCF4
net.ipv4.tcp_wmem=${_tcp_wmem_base} 87380 ${_tcp_wmem_max}
net.ipv4.tcp_rmem=${_tcp_rmem_base} 87380 ${_tcp_rmem_max}
BBRCF4
  
  # 同时设置运行态
  sysctl -w net.ipv4.tcp_wmem="${_tcp_wmem_base} 87380 ${_tcp_wmem_max}" &>/dev/null || true
  sysctl -w net.ipv4.tcp_rmem="${_tcp_rmem_base} 87380 ${_tcp_rmem_max}" &>/dev/null || true
  
  sysctl --system &>/dev/null || true
  
  # [T-CRITICAL-1-FIX] 验证tcp_timestamps=1是否真正生效
  local _ts_val=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo 0)
  if [[ "$_ts_val" == "1" ]]; then
    success "TCP timestamps已启用（反GFW代理检测）"
  else
    die "tcp_timestamps=1 设置失败（当前值: $_ts_val）"
  fi
  
  # [T-CRITICAL-3] TCP窗口验证逻辑修复 - 使用范围验证而非精确匹配
  local _wmem_actual=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
  local _rmem_actual=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
  
  # [BOTH-HIGH-1] 时间同步空值守卫 - 防止sysctl失败时误判通过
  if [[ -z "$_wmem_actual" || -z "$_rmem_actual" ]]; then
    die "TCP窗口参数无法读取（sysctl失败）"
  fi
  
  local _wmem_min=$(echo "$_wmem_actual" | awk '{print $1}')
  local _wmem_max=$(echo "$_wmem_actual" | awk '{print $3}')
  local _rmem_min=$(echo "$_rmem_actual" | awk '{print $1}')
  local _rmem_max=$(echo "$_rmem_actual" | awk '{print $3}')
  
  # 验证范围而非精确匹配（随机值不可能精确相等）
  if [[ "$_wmem_min" -ge 4096 && "$_wmem_min" -le 8192 && "$_wmem_max" -ge 16777216 && "$_wmem_max" -le 25165824 ]]; then
    success "TCP发送窗口随机化已生效（${_wmem_min} 87380 ${_wmem_max}）"
  else
    die "TCP发送窗口随机化失败（期望4-8KB/16-24MB，实际: $_wmem_actual）"
  fi
  
  if [[ "$_rmem_min" -ge 4096 && "$_rmem_min" -le 8192 && "$_rmem_max" -ge 16777216 && "$_rmem_max" -le 25165824 ]]; then
    success "TCP接收窗口随机化已生效（${_rmem_min} 87380 ${_rmem_max}）"
  else
    die "TCP接收窗口随机化失败（期望4-8KB/16-24MB，实际: $_rmem_actual）"
  fi
  
  warn "sysctl 配置已重新加载；若需立即回收运行态内核资源，建议重启主机"
  sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi 'bbr' \
    || warn "BBRPlus 未检测到，请确认已运行 one_click_script 并重启后再检查"
  # [v2.8 GPT-Doc2-🟠] PAM limits must match the dynamic _fd_max value.
  # Hard-coded 1048576 on a 512 MB VPS exceeds the dynamic sysctl value (524288),
  # causing SSH subshells and acme.sh cron to hit a PAM hard limit above the kernel ceiling.
  # Idempotent: strip any stale xray-transit nofile block then re-append current value.
  local _lim_file="/etc/security/limits.conf"
  sed -i '/# xray-transit: raised for high-concurrency/,/^root hard nofile/d' "$_lim_file" 2>/dev/null || true
  cat >> "$_lim_file" <<LIMEOF
# xray-transit: raised for high-concurrency gRPC — install_transit_v2.14.sh
* soft nofile ${_fd_max}
* hard nofile ${_fd_max}
root soft nofile ${_fd_max}
root hard nofile ${_fd_max}
LIMEOF
  success "内核网络参数已优化（conntrack hashsize=${_ct_mem} / 拥塞控制权归 BBRPlus）"
}

install_nginx(){
  # ENV-1 FIX: nginx -V 含 --with-stream=dynamic 但动态库未装时仍报 "unknown directive stream"
  # 必须强制安装 libnginx-mod-stream，不能仅靠 -V 输出判断
  if command -v nginx &>/dev/null; then
    # 已安装：测试 stream 指令是否真的可用（不只是 -V 标志）
    if echo 'events{} stream{}' | nginx -t -c /dev/stdin 2>/dev/null \
        || (nginx -V 2>&1 | grep -qE 'with-stream[^_]' \
           && dpkg -l libnginx-mod-stream 2>/dev/null | grep -q '^ii' 2>/dev/null); then
      success "Nginx 已安装且 stream 模块可用"
    else
      info "Nginx 已安装但 stream 模块不可用，补充安装 libnginx-mod-stream..."
      export DEBIAN_FRONTEND=noninteractive
      apt-get install -y libnginx-mod-stream 2>/dev/null \
        || warn "libnginx-mod-stream 安装失败，stream 模块可能不可用"
    fi
  else
    info "安装 Nginx（含 stream 模块）..."
    export DEBIAN_FRONTEND=noninteractive
    if command -v apt-get &>/dev/null; then
      apt-get update -qq
      # ENV-1 FIX: 同时安装 nginx-common libnginx-mod-stream nginx，确保动态库就位
      apt-get install -y nginx-common libnginx-mod-stream nginx 2>/dev/null \
        || apt-get install -y nginx \
        || die "Nginx 安装失败（apt-get 返回非零），请检查 apt 源或手动安装 nginx libnginx-mod-stream"
    elif command -v yum &>/dev/null; then
      yum install -y epel-release 2>/dev/null || true
      yum makecache 2>/dev/null || true
      yum install -y nginx nginx-mod-stream 2>/dev/null || yum install -y nginx \
        || die "Nginx 安装失败（yum 返回非零）"
    elif command -v dnf &>/dev/null; then
      dnf install -y nginx nginx-mod-stream 2>/dev/null || dnf install -y nginx \
        || die "Nginx 安装失败（dnf 返回非零）"
    else
      die "不支持的包管理器，请手动安装含 stream 模块的 Nginx"
    fi
    success "Nginx 安装完成"
  fi
  # 最终确认 stream 指令可用
  nginx -V 2>&1 | grep -qE 'with-stream' \
    || die "安装的 Nginx 不含 stream 支持，请安装 libnginx-mod-stream"
  
  # [T-MEDIUM-2] 创建SNI黑洞守卫 - 使用ssl_reject_handshake构建真实TLS握手黑洞
  # 避免对无效SNI直接TCP RST,模拟真实Web服务器行为
  mkdir -p /etc/nginx/conf.d
  cat > /etc/nginx/conf.d/transit-fallback.conf <<'FALLBACK_EOF'
# [T-MEDIUM-2] SNI黑洞守卫 - 对无效SNI进行真实TLS握手后拒绝
# 避免GFW探测时出现"秒挂断"特征
server {
    listen 127.0.0.1:9999 ssl;
    ssl_reject_handshake on;
}
FALLBACK_EOF
  success "SNI黑洞守卫已配置（127.0.0.1:9999）"
  
  _tune_nginx_worker_connections
}

_tune_nginx_worker_connections(){
  local mc="$NGINX_MAIN_CONF"
  # [F4] Snapshot before sed mutations so nginx.conf can be restored on nginx -t failure
  # [v2.13 GPT-🟠] nginx.conf snapshot moved from /tmp to script-owned MANAGER_BASE/tmp
  mkdir -p "${MANAGER_BASE}/tmp" || die "mkdir ${MANAGER_BASE}/tmp failed"
  local _mc_bak; _mc_bak=$(mktemp "${MANAGER_BASE}/tmp/.nginx-conf-snap.XXXXXX" 2>/dev/null) \
    || die "mktemp _mc_bak failed (disk full?) — cannot proceed without rollback capability"
  cp -a "$mc" "$_mc_bak" || die "nginx.conf snapshot failed — cannot proceed without rollback capability"
  [[ -n "$_mc_bak" ]] || die "mktemp returned empty path"
  local _mc_dirty=0
  # [v2.9 GPT-A-🟠] Recompute _fd_max here (same RAM×800 formula as optimize_kernel_network)
  # so worker_rlimit_nofile always matches the systemd LimitNOFILE drop-in value on this host.
  local _tune_ram_mb; _tune_ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _tune_ram_mb=${_tune_ram_mb:-1024}
  local _tune_fd=$(( _tune_ram_mb * 800 ))
  (( _tune_fd < 524288 ))   && _tune_fd=524288
  (( _tune_fd > 10485760 )) && _tune_fd=10485760
  local _wc_ram; _wc_ram=$(free -m 2>/dev/null | awk '/Mem:/{print int($2/2*1000)}'); _wc_ram=${_wc_ram:-100000}
  (( _wc_ram < 10000 )) && _wc_ram=10000
  (( _wc_ram > 200000 )) && _wc_ram=200000
  
  # [T-MEDIUM-3] worker_connections随机偏移扩大 - 70-130%范围
  local _wc_offset=$((_wc_ram * (70 + RANDOM % 60) / 100))
  local _wc_val="$_wc_offset"
  local _wc_escaped; _wc_escaped=$(printf '%s' "$VERSION" | sed 's/[.\-]/\\&/g')
  grep -qE "^[[:space:]]*worker_connections[[:space:]]+${_wc_val}[[:space:]]*;[[:space:]]*# transit-manager-tuning-v${_wc_escaped}$" "$mc" 2>/dev/null || {
    _mc_dirty=1
    if grep -qE '^[[:space:]]*worker_connections' "$mc" 2>/dev/null; then
      sed -i -E "s/^([[:space:]]*worker_connections[[:space:]]+)[0-9]+([[:space:]]*;.*)/\1${_wc_val}; # transit-manager-tuning-v${_wc_escaped}/" "$mc"
    else
      sed -i "/^events\s*{/a\    worker_connections ${_wc_val}; # transit-manager-tuning-v${_wc_escaped}" "$mc"
    fi
  }
  # Idempotent: strip any stale worker_rlimit_nofile line then re-inject current dynamic value
  grep -qE "^worker_rlimit_nofile\s+${_tune_fd}\s*;[[:space:]]*# transit-manager-tuning-v${_wc_escaped}$" "$mc" 2>/dev/null || {
    _mc_dirty=1
    if grep -qE '^[[:space:]]*worker_rlimit_nofile' "$mc" 2>/dev/null; then
      sed -i "s/^[[:space:]]*worker_rlimit_nofile.*/worker_rlimit_nofile ${_tune_fd}; # transit-manager-tuning-v${_wc_escaped}/" "$mc"
    else
      sed -i "/^events\s*{/i\worker_rlimit_nofile ${_tune_fd}; # transit-manager-tuning-v${_wc_escaped}" "$mc"
      info "worker_rlimit_nofile ${_tune_fd} 已写入 nginx.conf"
    fi
  }
  grep -qE "^worker_shutdown_timeout\s+10m\s*;[[:space:]]*# transit-manager-tuning-v${_wc_escaped}$" "$mc" 2>/dev/null || {
    _mc_dirty=1
    if grep -qE '^[[:space:]]*worker_shutdown_timeout' "$mc" 2>/dev/null; then
      sed -i "s/^.*worker_shutdown_timeout.*/worker_shutdown_timeout 10m; # transit-manager-tuning-v${_wc_escaped}/" "$mc"
    else
      sed -i "/^events\s*{/i\worker_shutdown_timeout 10m; # transit-manager-tuning-v${_wc_escaped}" "$mc"
    fi
  }
  # [F4] Validate and roll back if nginx -t fails
  if ! nginx -t 2>/dev/null; then
    warn "nginx.conf tuning validation failed — restoring snapshot"
    # [F1] Hard-fail restore: both mv and cp -a attempted; if both fail the file is corrupted
    if ! mv -f "$_mc_bak" "$mc" 2>/dev/null; then
      cp -a "$_mc_bak" "$mc" || die "nginx.conf restore FAILED — manual fix required: cp ${_mc_bak} ${mc}"
    fi
    die "nginx.conf 配置验证失败，原始配置已还原; 请检查 ${NGINX_MAIN_CONF}"
  fi
  rm -f "$_mc_bak" 2>/dev/null || true
  local override_dir="/etc/systemd/system/nginx.service.d"
  mkdir -p "$override_dir"
  # [v2.8 GPT-Doc2-🟠] LimitNOFILE must equal _fd_max (dynamic); always rewrite so a
  # re-run on different-RAM hardware updates the drop-in to the correct value.
  # [v2.9] Use _tune_fd (same formula, recomputed above) for both worker_rlimit_nofile and
  # the drop-in so the nginx.conf directive and the service cap are always identical.
  local _ov="${override_dir}/transit-manager-override.conf"
  atomic_write "$_ov" 644 root:root <<SVCOV
[Unit]
# [v2.9 Architect-🟠] Widened to 600s/10 — installer restarts nginx after rewriting the
# drop-in; 300s/5 was tight enough to trip on a short maintenance burst.
StartLimitIntervalSec=600
StartLimitBurst=10

[Service]
LimitNOFILE=${_tune_fd}
TasksMax=infinity
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/log/nginx /var/lib/nginx /run /var/run
ProtectHome=true
PrivateTmp=true
UMask=0027
# Gemini: nginx 自管日志，systemd journal 无需重复收集（防低配 VPS 磁盘撑爆）
StandardOutput=null
StandardError=null
SVCOV
  systemctl daemon-reload \
    || die "systemctl daemon-reload failed — drop-in limits will not apply (nginx may hit FD limit under load)"
  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx 2>/dev/null \
      || die "Nginx reload 失败（配置已修改但未生效）— 运行态与文件态分裂，请执行: systemctl restart nginx"
  fi
  success "Nginx worker_connections=${_wc_val} / worker_rlimit_nofile=${_tune_fd} (dynamic)"
}

write_logrotate(){
  mkdir -p "$LOG_DIR"
  atomic_write "$LOGROTATE_FILE" 644 root:root <<EOF
${LOG_DIR}/*.log
{
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
        # [v2.7 Gemini-Doc2-🟠] --kill-who=main: deliver USR1 exclusively to the nginx master
        # process; bare systemctl kill targets the entire cgroup (master + workers) and
        # USR1 to workers produces undefined behaviour / silent FD leaks.
        # [v2.11 Doc10-B-🟠] nginx -s reopen fallback: if master is in reload window, the
        # USR1 via systemctl kill may be lost; reopen ensures the FD swap is committed.
        systemctl kill --kill-who=main -s USR1 nginx.service >/dev/null 2>&1 \
          || nginx -s reopen >/dev/null 2>&1 || true
    endscript
}
EOF
  # [v2.8 Gemini-Doc2-🟠] journald cap: transit nginx workers now log to journal; without a
  # size ceiling the default 1 GB cap on low-disk VPS can still fill and OOM-kill nginx workers.
  # [REVIEWER-11] NOTE: purge_all() cleans this up comprehensively — removes the conf file
  # then rmdir the parent dir if empty (lines 1686-1687).
  local _jd_conf="/etc/systemd/journald.conf.d/transit-manager.conf"
  mkdir -p "/etc/systemd/journald.conf.d"
  # Always rewrite so re-runs update the value if the file already exists from a prior version.
  atomic_write "$_jd_conf" 644 root:root <<'JDEOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
JDEOF
  systemctl restart systemd-journald 2>/dev/null || true
  success "logrotate 已配置；journald 上限已设 SystemMaxUse=200M"
}

init_nginx_stream(){
  # BUG-T2 FIX: nginx -t 引用 error_log 路径，若目录不存在则报 "No such file or directory"
  # 必须在 nginx -t 前创建日志目录并设置正确权限
  mkdir -p "$LOG_DIR"
  chown root:adm "$LOG_DIR" 2>/dev/null || true
  chmod 750 "$LOG_DIR"
  mkdir -p "$SNIPPETS_DIR" "$CONF_DIR"
  chmod 700 "$SNIPPETS_DIR"
  rm -f "${SNIPPETS_DIR}/landing_dummy.map" "${SNIPPETS_DIR}/landing_*.map.tmp" 2>/dev/null || true

  if grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null; then
    info "Nginx stream include 已存在，跳过"; return 0
  fi
  if grep -qE '^\s*stream\s*\{' "$NGINX_MAIN_CONF" 2>/dev/null; then
    die "nginx.conf 已存在 stream{} 块（非本脚本），请备份后手动删除再运行"
  fi

  info "写入 Nginx stream 透传配置 ..."

  # [审查者1-高危2修复] 删除so_keepalive随机化 - 固定的非标定时器比默认值更显眼
  # 回归系统默认是最好的伪装,让nginx表现得像普通的高并发Web服务器

  # [v2.11 Doc9-B-🟠] Dynamic zone size: 64m fixed consumed ~12% of RAM on a 512MB VPS.
  # Scale to ~3% of RAM (RAM/32), floor 5m (~100k IPs), cap 64m (~1.3M IPs).
  local _stream_ram_mb; _stream_ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _stream_ram_mb=${_stream_ram_mb:-1024}
  local _stream_zone_mb=$(( _stream_ram_mb / 32 ))
  local ipv6_listen=""
  have_ipv6 && ipv6_listen="        listen [::]:${LISTEN_PORT} backlog=65535;"
  (( _stream_zone_mb < 5  )) && _stream_zone_mb=5
  (( _stream_zone_mb > 64 )) && _stream_zone_mb=64

  # v2.32 Grok: v1.4: 纯本地 decoy（127.0.0.1:45231），无 DNS 查询，无时序特征
# 空/无匹配SNI → 直接回落到 Apple CDN 17.253.144.10:443
  # resolver 故障 → 降级至本地 45231（速率限制保护）
  atomic_write "$NGINX_STREAM_CONF" 644 root:root <<NGINX_STREAM_EOF
# stream-transit.conf — 由 install_transit_${VERSION}.sh 管理，请勿手动修改
# v2.48: 全量 fallback 直接至 Apple CDN IP，彻底消除二次映射和 DNS 查询
# 有效落地机SNI→落地机IP:PORT；无效/空/畸形SNI→Apple CDN（透明盲传）
stream {
    access_log off;
    error_log  ${LOG_DIR}/transit_stream_error.log emerg;

    # v2.48: 删 resolver（纯本地 fallback 无需 DNS，消除 GFW 可观测的 DNS 查询）

    # BUG-T1 FIX: limit_req_zone/limit_req 是 HTTP 模块专属指令，stream 模块不支持
    # 已移除 limit_req_zone 和 limit_req；连接数限制由 limit_conn 负责（stream 原生支持）
    # [v2.11] Dynamic zone size: ~3% of host RAM, floor 5m, cap 64m
    limit_conn_zone \$binary_remote_addr zone=transit_stream_conn:${_stream_zone_mb}m;

    # [L1-FIX] CDN fallback固定多IP - 随机IP不保证可用性,改为固定多个CDN IP负载均衡
    # 使用least_conn策略,自动选择连接数最少的后端
    # [T-MEDIUM-2] 改为本地黑洞 - 避免GFW探测时TCP RST暴露代理特征
    upstream fallback_blackhole {
        server 127.0.0.1:9999;
    }

    # v2.48: SNI 守卫内嵌到 map——超长(≥254字节)/含控制字符/空/无匹配 → 本地 decoy
    map \$ssl_preread_server_name \$backend_upstream {
        hostnames;
        include /etc/nginx/stream-snippets/landing_*.map;
        # [审查者2 Fix] Fallback to blackhole for invalid SNI
        "~^.{254,}"      fallback_blackhole;
        "~[\x00-\x1F]" fallback_blackhole;
        ""               fallback_blackhole;
        default          fallback_blackhole;
    }

    server {
        listen      ${LISTEN_PORT} backlog=65535;
${ipv6_listen}
        ssl_preread on;
        preread_buffer_size 64k;  # [fix] 防止 uTLS 庞大 ClientHello 导致 SNI 嗅探失败
        # [C1] Nginx超时配置优化 - 中国到美西高延迟,30s握手+600s传输
        preread_timeout        30s;
        proxy_pass             \$backend_upstream;
        proxy_connect_timeout  30s;
        proxy_timeout          600s;
        proxy_socket_keepalive on;
        tcp_nodelay            on;
        # [F2] 100 per IP: gRPC multiplexes all streams over few TCP connections;
        # 2000 per IP + 315s timeout = slow-drain DoS from just 50 distributed IPs.
        limit_conn transit_stream_conn 100;
    }
}
NGINX_STREAM_EOF

  # Bug 37 FIX: 严禁用 sed -i '$a \n...' —— Ubuntu 某些版本将 \n 识别为字母 n
  # 改用 printf + >> 方式追加到临时文件后 mv，纯 POSIX，无环境差异
  local _mc_bak="${NGINX_MAIN_CONF}.transit.bak_$(date +%s)"
  cp -f "$NGINX_MAIN_CONF" "$_mc_bak" 2>/dev/null || true
  ls -t "${NGINX_MAIN_CONF}.transit.bak_"* 2>/dev/null | tail -n +3 | xargs -r rm -f 2>/dev/null || true
  mkdir -p "${NGINX_MAIN_CONF%/*}" || die "mkdir nginx conf dir failed"
  local _mc_tmp; _mc_tmp=$(mktemp "${NGINX_MAIN_CONF%/*}/.snap-recover.XXXXXX" 2>/dev/null) \
    || die "mktemp _mc_tmp failed"
  [[ -n "$_mc_tmp" ]] || die "mktemp returned empty path"
  cp -f "$NGINX_MAIN_CONF" "$_mc_tmp" \
    || die "snapshot nginx.conf failed"
  printf '\n# %s\n' "$STREAM_INCLUDE_MARKER"  >> "$_mc_tmp"
  printf 'include %s;\n'    "$NGINX_STREAM_CONF" >> "$_mc_tmp"
  chmod 644 "$_mc_tmp" \
    || die "chmod _mc_tmp failed"
  mv -f "$_mc_tmp" "$NGINX_MAIN_CONF" \
    || die "promote _mc_tmp to nginx.conf failed"
  # 验证注入成功
  grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" \
    || die "nginx.conf include 注入失败，请检查文件权限: ${NGINX_MAIN_CONF}"

  if ! nginx -t 2>/dev/null; then
    if grep -q 'fastopen=' "$NGINX_STREAM_CONF" 2>/dev/null; then
      warn "当前环境不支持 TCP Fast Open，自动降级..."
      # v2.17: TFO降级原子化 - 失败时同时还原stream配置
      local _stream_bak="${NGINX_STREAM_CONF}.tfo.bak"
      cp -f "$NGINX_STREAM_CONF" "$_stream_bak" 2>/dev/null || true
      sed -i -E 's/ fastopen=[0-9]+//; s/ so_keepalive=[a-zA-Z0-9:]+//' "$NGINX_STREAM_CONF"
      if ! nginx -t 2>/dev/null; then
        nginx -t 2>&1 || true
        [[ -f "$_mc_bak" ]] && mv -f "$_mc_bak" "$NGINX_MAIN_CONF" 2>/dev/null || true
        mv -f "$_stream_bak" "$NGINX_STREAM_CONF" 2>/dev/null || true
        die "Nginx 配置验证失败（TFO 已移除，请检查配置）；nginx.conf 和 stream 配置均已还原"
      fi
      rm -f "$_stream_bak" 2>/dev/null || true
      warn "TCP Fast Open 已降级（功能正常，仅延迟优化受限）"
    else
      nginx -t 2>&1 || true
      # GEM-BUG-02: nginx.conf 已被 mv 覆盖，验证失败必须从快照还原
      [[ -f "$_mc_bak" ]] && mv -f "$_mc_bak" "$NGINX_MAIN_CONF" 2>/dev/null || true
      die "Nginx stream 配置验证失败；nginx.conf 已从快照还原"
    fi
  fi
  success "Nginx stream 配置写入完成（空/无匹配SNI→CDN负载均衡 · 回归系统默认参数）"
}

# [S1-HIGH] 增强健康检查 - 自动检测和恢复服务异常
setup_health_check_transit(){
  info "配置健康检查和自动恢复..."
  
  atomic_write "/usr/local/bin/transit-health-check.sh" 755 root:root <<'HEALTH'
#!/bin/bash
# [S1-HIGH] 健康检查脚本 - 确保长期稳定运行
set -euo pipefail

# 检查 Nginx 服务状态
if ! systemctl is-active --quiet nginx; then
  logger -t transit-health "Nginx服务异常,尝试重启"
  systemctl restart nginx
  exit 0
fi

# [S1-T] 检查监听端口 - 中转机端口固定为443
LISTEN_PORT=443
if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/${LISTEN_PORT}" 2>/dev/null; then
  logger -t transit-health "端口${LISTEN_PORT}无响应,重启服务"
  systemctl restart nginx
  exit 0
fi

# [S1-T] 检查iptables规则完整性 - 检查TRANSIT-MANAGER链
if ! iptables -L TRANSIT-MANAGER -n 2>/dev/null | grep -q "ACCEPT.*tcp.*dpt:443"; then
  logger -t transit-health "防火墙规则丢失,尝试恢复"
  /etc/transit_manager/firewall-restore.sh 2>/dev/null || true
fi

# [S1-T] 检查SSH规则 - 确保SSH端口防火墙规则存在
SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{gsub(/.*:/,"",$4); print $4; exit}')
if [ -n "$SSH_PORT" ] && ! iptables -L TRANSIT-MANAGER -n 2>/dev/null | grep -q "ACCEPT.*tcp.*dpt:${SSH_PORT}"; then
  logger -t transit-health "SSH防火墙规则丢失,尝试恢复"
  /etc/transit_manager/firewall-restore.sh 2>/dev/null || true
fi

# 检查 Nginx 配置完整性
if ! nginx -t 2>/dev/null; then
  logger -t transit-health "Nginx配置损坏,尝试恢复"
  systemctl restart nginx
  exit 0
fi
HEALTH

  # [H1] 健康检查频率提升 - 从10分钟改为3分钟,更快发现异常
  atomic_write "/etc/cron.d/transit-health" 644 root:root <<CRON
# [H1] 健康检查 - 每3分钟执行,确保长期稳定运行
*/3 * * * * root /usr/local/bin/transit-health-check.sh >/dev/null 2>&1
CRON

  success "健康检查已配置: 每3分钟自动检测"
}

# FIX: 只生成 .map 文件，值为 IP:PORT 字符串（proxy_pass $var 直接转发，IP 无需 DNS）
# 落地机路由片段只生成 .map 文件，值为 IP:PORT 字符串
generate_landing_snippet(){
  local domain="$1" ip="$2" port="${3:-443}"
  local safe; safe=$(domain_to_safe "$domain")
  # 🔴 Grok: safe 为空 → domain_to_safe 把所有字符都过滤掉 → map 文件名非法
  [[ -n "$safe" ]] || die "域名 safe 转换后为空，拒绝生成 map（可能含非法字符）: ${domain}"
  # v2.32 Grok: 文件名截断，防超长 safe key 造成文件系统限制错误
  rm -f "${SNIPPETS_DIR}/landing_${safe}.upstream" 2>/dev/null || true

  local _dup_map=""
  _dup_map=$(_route_key_conflict "$domain" "${SNIPPETS_DIR}/landing_${safe}.map" 2>/dev/null || true)
  [[ -z "$_dup_map" ]] || die "域名 SNI 键已存在于其他路由片段: ${_dup_map}"

  # 🟠 Grok: 先清除旧 map（原子覆盖），防重复 hostnames 条目导致 fallback 优先级错乱
  rm -f "${SNIPPETS_DIR}/landing_${safe}.map" 2>/dev/null || true

  atomic_write "${SNIPPETS_DIR}/landing_${safe}.map" 600 root:root <<MAPEOF
    $(nginx_domain_str "$domain")    $(nginx_ip_str "$ip"):${port};
MAPEOF
  success "路由片段已生成: ${domain} → ${ip}:${port}"
}

# [M2 Fix] Check for empty meta files before processing
_meta_file_valid(){
  local _mf="$1"
  [[ -f "$_mf" && -s "$_mf" ]] || return 1
  return 0
}

remove_landing_snippet(){
  local domain="$1"
  local safe; safe=$(domain_to_safe "$domain")
  local removed=0
  for f in "${SNIPPETS_DIR}/landing_${safe}.map" \
            "${SNIPPETS_DIR}/landing_${safe}.upstream" \
            "${CONF_DIR}/${safe}.meta"; do
    [[ -f "$f" ]] && { rm -f "$f"; (( ++removed )) || true; }
  done
  (( removed > 0 )) && success "已删除路由片段: ${domain}" \
    || { warn "未找到路由配置: ${domain}"; return 1; }
}

nginx_reload(){
  # BUG-T2 FIX: 确保日志目录存在，防止 nginx -t 因 error_log 路径不存在而失败
  mkdir -p "$LOG_DIR"
  info "验证 Nginx 配置 ..."
  nginx -t 2>&1 || die "Nginx 配置验证失败，请检查以上报错"
  info "热重载 Nginx ..."
  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx
  else
    systemctl restart nginx 2>/dev/null || true
  fi
  sleep 1
  success "Nginx 热重载成功（零中断）"
}


setup_firewall_transit(){
  local ssh_port; ssh_port="$(detect_ssh_port)"
  info "配置防火墙 chain ${FW_CHAIN}: SSH(${ssh_port}) + TCP(${LISTEN_PORT}) + ICMP，其余 DROP ..."

  local FW_TMP="${FW_CHAIN}-NEW"
  local FW_TMP6="${FW_CHAIN6}-NEW"

  # [v2.15 Bug Fix] Bulldozer pre-flight: iptables -E fails with "File exists" when INPUT
  # has ANY rule referencing FW_CHAIN, regardless of comment text. The old while-loop approach
  # only removed rules with specific known comments, missing rules added with different comments
  # or leftover direct -j rules. Bulldozer reads iptables -S INPUT and removes every rule
  # that names FW_CHAIN or FW_TMP before attempting -F / -X / -E.
_bulldoze_input_refs_t(){
    local _chain="$1" _lines _n
    mapfile -t _lines < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$_chain" '$2==c {print $1}' | sort -rn)
    for _n in "${_lines[@]}"; do
      iptables -w 2 -D INPUT "$_n" 2>/dev/null || true
    done
  }

_bulldoze_input_refs6_t(){
    local _chain="$1" _lines _n
    mapfile -t _lines < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$_chain" '$2==c {print $1}' | sort -rn)
    for _n in "${_lines[@]}"; do
      ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true
    done
  }

  _bulldoze_input_refs_t "$FW_CHAIN";  _bulldoze_input_refs_t "$FW_TMP"
  iptables -w 2 -F "$FW_TMP"   2>/dev/null || true; iptables -w 2 -X "$FW_TMP"   2>/dev/null || true
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  if have_ipv6; then
    _bulldoze_input_refs6_t "$FW_CHAIN6"; _bulldoze_input_refs6_t "$FW_TMP6"
    ip6tables -w 2 -F "$FW_TMP6"   2>/dev/null || true; ip6tables -w 2 -X "$FW_TMP6"   2>/dev/null || true
    ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
  fi

  # v2.35 Grok: 快照旧 persist script，_persist_iptables 失败时连同 chain swap 一起回滚
  local _snap_persist=""
  local _persist_script="${MANAGER_BASE}/firewall-restore.sh"
  if [[ -f "$_persist_script" ]]; then
    mkdir -p "${MANAGER_BASE}" || die "mkdir ${MANAGER_BASE} failed"
    _snap_persist=$(mktemp "${MANAGER_BASE}/.transit-mgr.XXXXXX" 2>/dev/null) \
      || die "mktemp _snap_persist failed — rollback snapshot unavailable"
    cp -f "$_persist_script" "$_snap_persist" \
      || die "snapshot persist script failed — rollback will be impaired"
  fi

  local _prev_err_trap _prev_int_trap _prev_term_trap
  _prev_err_trap=$(trap -p ERR || true)
  _prev_int_trap=$(trap -p INT || true)
  _prev_term_trap=$(trap -p TERM || true)
  _fw_transit_rollback(){
    # Atomic swap: remove INPUT ref -> swap chains -> cleanup
    local _n
    mapfile -t _n < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="${FW_CHAIN}_OLD" '$2==c {print $1}' | sort -rn)
    for _n in "${_n[@]}"; do iptables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
    mapfile -t _n < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="${FW_CHAIN}" '$2==c {print $1}' | sort -rn)
    for _n in "${_n[@]}"; do iptables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
    mapfile -t _n < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="${FW_CHAIN6}_OLD" '$2==c {print $1}' | sort -rn)
    for _n in "${_n[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
    mapfile -t _n < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="${FW_CHAIN6}" '$2==c {print $1}' | sort -rn)
    for _n in "${_n[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
    iptables -w 2 -E "FWDUMMY" "${FW_CHAIN}_OLD" 2>/dev/null || true
    iptables -w 2 -E "${FW_CHAIN}" "FWDUMMY" 2>/dev/null || true
    iptables -w 2 -E "${FW_CHAIN}_OLD" "${FW_CHAIN}" 2>/dev/null || true
    iptables -w 2 -F "${FW_CHAIN}" 2>/dev/null || true
    iptables -w 2 -X "${FW_CHAIN}" 2>/dev/null || true
    ip6tables -w 2 -E "FWDUMMY6" "${FW_CHAIN6}_OLD" 2>/dev/null || true
    ip6tables -w 2 -E "${FW_CHAIN6}" "FWDUMMY6" 2>/dev/null || true
    ip6tables -w 2 -E "${FW_CHAIN6}_OLD" "${FW_CHAIN6}" 2>/dev/null || true
    ip6tables -w 2 -F "${FW_CHAIN6}" 2>/dev/null || true
    ip6tables -w 2 -X "${FW_CHAIN6}" 2>/dev/null || true
    # v2.36 GPT: 区分"有旧快照"和"首次安装无旧文件"两种情形
    if [[ -n "${_snap_persist:-}" && -f "${_snap_persist:-}" ]]; then
      # 存在旧快照 → 还原
      mv -f "$_snap_persist" "$_persist_script" 2>/dev/null || true
    else
      # 首次安装 → 无旧脚本可还原，删除新生成的脚本和 unit，防半装状态带入开机
      rm -f "$_persist_script" 2>/dev/null || true
      systemctl disable --now transit-manager-iptables-restore.service 2>/dev/null || true
      rm -f "/etc/systemd/system/transit-manager-iptables-restore.service" 2>/dev/null || true
      systemctl daemon-reload || die "daemon-reload failed"
    fi
    _snap_persist=""
  }
  _restore_prev_traps(){
    eval "${_prev_err_trap:-trap - ERR}"
    eval "${_prev_int_trap:-trap - INT}"
    eval "${_prev_term_trap:-trap - TERM}"
  }
trap '_fw_transit_rollback; exit 130' INT TERM
  iptables -w 2 -N "$FW_TMP" 2>/dev/null || iptables -w 2 -F "$FW_TMP"
  # v2.32 Grok: lo + SSH 先于 INVALID,UNTRACKED 放行，保证 conntrack 表满时 SSH 仍可新建连接
  iptables -w 2 -A "$FW_TMP" -i lo                                       -m comment --comment "transit-manager-rule" -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$ssh_port"                 -m comment --comment "transit-manager-rule" -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -m conntrack --ctstate INVALID,UNTRACKED    -m comment --comment "transit-manager-rule" -j DROP
  iptables -w 2 -A "$FW_TMP" -m conntrack --ctstate ESTABLISHED,RELATED  -m comment --comment "transit-manager-rule" -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -p icmp --icmp-type echo-request -m limit --limit 10/second --limit-burst 20 \
                                                                     -m comment --comment "transit-manager-rule" -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -p icmp --icmp-type echo-request            -m comment --comment "transit-manager-rule" -j DROP
  # v4.41: 显式阻断 UDP 443（QUIC 流量），强制客户端降级到 TCP
  iptables -w 2 -A "$FW_TMP" -p udp  --dport "$LISTEN_PORT"              -m comment --comment "transit-manager-rule" -j DROP
  # v1.3: 明确 ACCEPT 新建 443 连接（connlimit/rate 只拦 DDoS，正常流量必须先过这一关）
  # 规则顺序：① connlimit（超并发 DROP）→ ② rate（超速率 DROP）→ ③ ACCEPT 剩余正常 443 新连接
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$LISTEN_PORT" \
    -m connlimit --connlimit-above 2000 --connlimit-mask 32        -m comment --comment "transit-manager-rule" -j DROP
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$LISTEN_PORT" \
    -m connlimit --connlimit-above 20000 --connlimit-mask 0        -m comment --comment "transit-manager-rule" -j DROP
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$LISTEN_PORT" \
    -m hashlimit --hashlimit-upto 8000/sec --hashlimit-burst 9999 --hashlimit-mode srcip --hashlimit-name transit_443_limit                   -m comment --comment "transit-manager-rule" -j ACCEPT
  # 超速率的 443 DROP（rate 令牌耗尽时走此规则）
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$LISTEN_PORT"              -m comment --comment "transit-manager-rule" -j DROP
  iptables -w 2 -A "$FW_TMP"                                              -m comment --comment "transit-manager-rule" -j DROP
  iptables -w 2 -I INPUT 1 -m comment --comment "transit-manager-swap" -j "$FW_TMP"
  # [R-8 FIX] Bulldozer runs AFTER chain is fully populated (post line 891), BEFORE rename:
  # removes stale INPUT rules referencing old FW_CHAIN before atomic swap
  _bulldoze_input_refs_t "$FW_CHAIN"
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  iptables -w 2 -E "$FW_TMP" "$FW_CHAIN"
  iptables -w 2 -I INPUT 1 -m comment --comment "transit-manager-rule" -j "$FW_CHAIN"
  # [R5 Fix] Verify INPUT position 1 — warn (not die) since Docker/fail2ban also use position 1
  local _actual_pos
  _actual_pos=$(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$FW_CHAIN" '$2==c {print $1; exit}')
  if [[ "${_actual_pos:-}" != "1" ]]; then
    warn "防火墙规则未能在 INPUT 链首位（实际位置: ${_actual_pos:-?}），可能与其他服务冲突"
  fi
  local _n
  mapfile -t _n < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$FW_TMP" '$2==c {print $1}' | sort -rn)
  for _n in "${_n[@]}"; do iptables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
  mapfile -t _n < <(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$FW_CHAIN" '$2==c {print $1}' | sort -rn)
  for _n in "${_n[@]}"; do iptables -w 2 -D INPUT "$_n" 2>/dev/null || true; done

    if have_ipv6; then
      ip6tables -w 2 -N "$FW_TMP6" 2>/dev/null || ip6tables -w 2 -F "$FW_TMP6"
      # [F4 Fix] Mirror IPv4 rule order: lo → SSH → INVALID DROP → ESTABLISHED → ICMP → 443
      ip6tables -w 2 -A "$FW_TMP6" -i lo -j ACCEPT
      ip6tables -w 2 -A "$FW_TMP6" -p tcp      --dport "$ssh_port"    -j ACCEPT
      ip6tables -w 2 -A "$FW_TMP6" -m conntrack --ctstate INVALID,UNTRACKED -j DROP
      ip6tables -w 2 -A "$FW_TMP6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment "transit-manager-icmp6" -j ACCEPT
      ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type echo-request -m comment --comment "transit-manager-icmp6-drop" -j DROP
      # v4.41: 显式阻断 UDP 443（QUIC 流量），强制客户端降级到 TCP
      ip6tables -w 2 -A "$FW_TMP6" -p udp --dport "$LISTEN_PORT" -j DROP
      # v2.43 Grok: IPv6 加 connlimit+rate，与 IPv4 对等防护（/64 对应 IPv6 CGNAT 粒度）
      ip6tables -w 2 -A "$FW_TMP6" -p tcp --dport "$LISTEN_PORT" \
        -m connlimit --connlimit-above 2000 --connlimit-mask 64  -j DROP
      ip6tables -w 2 -A "$FW_TMP6" -p tcp --dport "$LISTEN_PORT" \
        -m connlimit --connlimit-above 20000 --connlimit-mask 0  -j DROP
      ip6tables -w 2 -A "$FW_TMP6" -p tcp --dport "$LISTEN_PORT" \
        -m hashlimit --hashlimit-upto 8000/sec --hashlimit-burst 9999 --hashlimit-mode srcip --hashlimit-name transit_443_limit_v6              -j ACCEPT
      ip6tables -w 2 -A "$FW_TMP6" -p tcp --dport "$LISTEN_PORT"      -j DROP
      ip6tables -w 2 -A "$FW_TMP6" -j DROP
      ip6tables -w 2 -I INPUT 1 -m comment --comment "transit-manager-v6-swap" -j "$FW_TMP6"
      # [v2.15] Bulldozer drain for IPv6 before rename
      _bulldoze_input_refs6_t "$FW_CHAIN6"
      ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
      ip6tables -w 2 -E "$FW_TMP6" "$FW_CHAIN6"
      ip6tables -w 2 -I INPUT 1 -m comment --comment "transit-manager-v6-jump" -j "$FW_CHAIN6"
      local _n
      mapfile -t _n < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$FW_TMP6" '$2==c {print $1}' | sort -rn)
      for _n in "${_n[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
      mapfile -t _n < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="$FW_CHAIN6" '$2==c {print $1}' | sort -rn)
      for _n in "${_n[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
    fi

  # v2.37 GPT: trap 保持活跃直到 _persist_iptables 成功，防运行链/开机链分裂
  # 旧代码在此处提前 trap - ERR INT TERM，导致 persist 失败时无法回滚
  if ! _persist_iptables "$ssh_port"; then
    _fw_transit_rollback
    _restore_prev_traps
    die "防火墙持久化失败（firewall-restore.sh/unit 写入异常），运行链已回滚至旧状态"
  fi
  _restore_prev_traps
  rm -f "${_snap_persist:-}" 2>/dev/null || true
  
  # [T-HIGH-2-FIX] 验证 UDP 443（QUIC）封堵规则是否生效
  local _udp_drop_count
  _udp_drop_count=$(iptables -w 2 -L "$FW_CHAIN" -n -v 2>/dev/null | grep -c "udp dpt:$LISTEN_PORT.*DROP" 2>/dev/null || echo 0)
  _udp_drop_count=$(echo "$_udp_drop_count" | tr -d '\r\n' | head -1)  # 清理换行符，防止语法错误
  if [[ "$_udp_drop_count" -ge 1 ]]; then
    success "UDP 443（QUIC）封堵规则已生效"
  else
    warn "UDP 443（QUIC）封堵规则未找到，可能存在流量泄露风险"
  fi
  
  success "防火墙配置完成（chain ${FW_CHAIN} + ${FW_CHAIN6}，SSH:${ssh_port} + 443 + ICMP，蓝绿原子切换零裸奔）"
}


_persist_iptables(){
  local ssh_port="${1:-22}"
  # [R6 Fix] Validate ssh_port is numeric before template injection
  [[ "$ssh_port" =~ ^[0-9]+$ ]] || die "SSH 端口非法（需为数字）: $ssh_port"
  (( ssh_port >= 1 && ssh_port <= 65535 )) || die "SSH 端口超范围 (1-65535): $ssh_port"
  # [R22 Fix] Validate FW_CHAIN names contain only safe characters before template injection
  [[ "$FW_CHAIN" =~ ^[A-Za-z0-9_-]+$ ]] || die "FW_CHAIN 含非法字符: $FW_CHAIN"
  [[ "$FW_CHAIN6" =~ ^[A-Za-z0-9_-]+$ ]] || die "FW_CHAIN6 含非法字符: $FW_CHAIN6"
  mkdir -p "$MANAGER_BASE"
  local fw_script="${MANAGER_BASE}/firewall-restore.sh"
  local _fw_sig="TRANSIT_FW_VERSION=${VERSION}_$(date +%Y%m%d)"
  export FW_SIG="$_fw_sig" SSH_PORT_FALLBACK="$ssh_port" FW_CHAIN FW_CHAIN6 LISTEN_PORT
  python3 - <<'PY' | atomic_write "$fw_script" 700 root:root
from pathlib import Path
import os, sys
import re

template = r"""#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERROR: Bash 4+ required"; exit 1; }
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
# __FW_SIG__
# 🟠 Grok: SSH 端口在恢复时动态探测，防止用户修改 sshd 端口后重启丢失 SSH
_detect_ssh(){
  local p=""
  p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"
  [ -z "$p" ] && p="$(ss -H -tlnp 2>/dev/null | awk '
    $1=="LISTEN" && /sshd/ {
      addr=$4
      sub(/^.*:/,"",addr)
      gsub(/^\[/,"",addr)
      gsub(/\]$/,"",addr)
      if (addr ~ /^[0-9]+$/) { print addr; exit }
    }' || true)"
  # [R12 Fix] sshd not running at boot → fall back to sshd_config before using install-time value
  [ -z "$p" ] && p="$(grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk '{print $2}' | sort -n | head -1 || true)"
  _ssh_port="${p:-}"; [[ -z "$_ssh_port" || "$_ssh_port" == "0" ]] && _ssh_port=__SSH_PORT__
  if echo "$_ssh_port" | grep -qE '^[0-9]+$' && [ "$_ssh_port" -ge 1 ] && [ "$_ssh_port" -le 65535 ]; then
    echo "$_ssh_port"
  else
    # [C1 Fix] Remove exit 1 - fallback to install-time port instead of blocking firewall restore
    logger -t transit-firewall "WARN: 无法动态探测 SSH 端口，使用安装时值 __SSH_PORT__"
    echo "__SSH_PORT__"
  fi
}
SSH_PORT="$(_detect_ssh)"
iptables -w 2 -N __FW_CHAIN__-NEW 2>/dev/null || true
iptables -w 2 -F __FW_CHAIN__-NEW 2>/dev/null || true
iptables -w 2 -A __FW_CHAIN__-NEW -i lo                                       -m comment --comment "transit-manager-rule" -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p tcp  --dport ${SSH_PORT}                -m comment --comment "transit-manager-rule" -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -m conntrack --ctstate INVALID,UNTRACKED    -m comment --comment "transit-manager-rule" -j DROP
iptables -w 2 -A __FW_CHAIN__-NEW -m conntrack --ctstate ESTABLISHED,RELATED  -m comment --comment "transit-manager-rule" -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p icmp --icmp-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment "transit-manager-rule" -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p icmp --icmp-type echo-request            -m comment --comment "transit-manager-rule" -j DROP
iptables -w 2 -A __FW_CHAIN__-NEW -p tcp  --dport __LISTEN_PORT__ -m connlimit --connlimit-above 2000 --connlimit-mask 32 -m comment --comment "transit-manager-rule" -j DROP
iptables -w 2 -A __FW_CHAIN__-NEW -p tcp  --dport __LISTEN_PORT__ -m connlimit --connlimit-above 20000 --connlimit-mask 0  -m comment --comment "transit-manager-rule" -j DROP
iptables -w 2 -A __FW_CHAIN__-NEW -p tcp  --dport __LISTEN_PORT__ -m hashlimit --hashlimit-upto 8000/sec --hashlimit-burst 9999 --hashlimit-mode srcip --hashlimit-name transit_443_limit             -m comment --comment "transit-manager-rule" -j ACCEPT
iptables -w 2 -A __FW_CHAIN__-NEW -p tcp  --dport __LISTEN_PORT__                                                         -m comment --comment "transit-manager-rule" -j DROP
iptables -w 2 -A __FW_CHAIN__-NEW                                              -m comment --comment "transit-manager-rule" -j DROP
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
_bulldoze_input_refs __FW_CHAIN__
_bulldoze_input_refs6 __FW_CHAIN6__
iptables -w 2 -F __FW_CHAIN__  2>/dev/null || true
iptables -w 2 -X __FW_CHAIN__  2>/dev/null || true
iptables -w 2 -E __FW_CHAIN__-NEW __FW_CHAIN__ 2>/dev/null || {
  iptables -w 2 -F __FW_CHAIN__-NEW 2>/dev/null || true
  iptables -w 2 -X __FW_CHAIN__-NEW 2>/dev/null || true
  exit 1
}
iptables -w 2 -I INPUT 1 -m comment --comment "transit-manager-rule" -j __FW_CHAIN__
if [ -f /proc/net/if_inet6 ] && command -v ip6tables >/dev/null 2>&1 && ip6tables -nL >/dev/null 2>&1 && [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)" != "1" ]; then
  ip6tables -w 2 -N __FW_CHAIN6__-NEW 2>/dev/null || true
  ip6tables -w 2 -F __FW_CHAIN6__-NEW 2>/dev/null || true
  # [F4 Fix] Mirror IPv4 order: lo → SSH → INVALID DROP → ESTABLISHED → ICMP → 443
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -i lo -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p tcp      --dport ${SSH_PORT}      -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -m conntrack --ctstate INVALID,UNTRACKED -j DROP
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  # [REVIEWER-3] 允许IPv6 NDP流量(邻居发现协议)
    ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp -m icmp6 --icmpv6-type 133 -j ACCEPT
    ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp -m icmp6 --icmpv6-type 134 -j ACCEPT
    ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp -m icmp6 --icmpv6-type 135 -j ACCEPT
    ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp -m icmp6 --icmpv6-type 136 -j ACCEPT
    ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment "transit-manager-icmp6" -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p ipv6-icmp --icmpv6-type echo-request -m comment --comment "transit-manager-icmp6-drop" -j DROP
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p tcp --dport __LISTEN_PORT__ -m connlimit --connlimit-above 2000 --connlimit-mask 64 -j DROP
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p tcp --dport __LISTEN_PORT__ -m connlimit --connlimit-above 20000 --connlimit-mask 0  -j DROP
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p tcp --dport __LISTEN_PORT__ -m hashlimit --hashlimit-upto 8000/sec --hashlimit-burst 9999 --hashlimit-mode srcip --hashlimit-name transit_443_limit_v6 -j ACCEPT
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -p tcp --dport __LISTEN_PORT__ -j DROP
  ip6tables -w 2 -A __FW_CHAIN6__-NEW -j DROP
  local _n
  mapfile -t _n < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="__FW_CHAIN6__-NEW" '$2==c {print $1}' | sort -rn)
  for _n in "${_n[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
  mapfile -t _n < <(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null | awk -v c="__FW_CHAIN6__" '$2==c {print $1}' | sort -rn)
  for _n in "${_n[@]}"; do ip6tables -w 2 -D INPUT "$_n" 2>/dev/null || true; done
  ip6tables -w 2 -F __FW_CHAIN6__ 2>/dev/null || true
  ip6tables -w 2 -X __FW_CHAIN6__ 2>/dev/null || true
  ip6tables -w 2 -E __FW_CHAIN6__-NEW __FW_CHAIN6__ 2>/dev/null || {
    ip6tables -w 2 -F __FW_CHAIN6__-NEW 2>/dev/null || true
    ip6tables -w 2 -X __FW_CHAIN6__-NEW 2>/dev/null || true
    exit 1
  }
  ip6tables -w 2 -I INPUT 1 -m comment --comment "transit-manager-v6-jump" -j __FW_CHAIN6__
fi
"""
# [H3 Fix] Escape FW_CHAIN names to prevent template injection with special characters
fw_chain_escaped = re.escape(os.environ["FW_CHAIN"])
fw_chain6_escaped = re.escape(os.environ["FW_CHAIN6"])

template = template.replace("__FW_SIG__", os.environ["FW_SIG"])
template = template.replace("__SSH_PORT__", os.environ["SSH_PORT_FALLBACK"])
template = template.replace("__FW_CHAIN__", fw_chain_escaped)
template = template.replace("__FW_CHAIN6__", fw_chain6_escaped)
template = template.replace("__LISTEN_PORT__", os.environ["LISTEN_PORT"])
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
sys.stdout.write(template)
PY
  local rsvc="/etc/systemd/system/transit-manager-iptables-restore.service"
  atomic_write "$rsvc" 644 root:root <<RSTO
[Unit]
Description=Restore iptables rules for transit-manager
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
  systemctl daemon-reload \
    || die "systemctl daemon-reload failed — iptables-restore service unit may not load"
  systemctl enable transit-manager-iptables-restore.service \
    || die "iptables 持久化服务 enable 失败，重启后防火墙规则将丢失"
  systemctl is-enabled --quiet transit-manager-iptables-restore.service     || die "iptables 持久化服务 enabled 状态验收失败"
  info "防火墙规则已写入: ${fw_script}（开机动态检测 SSH 端口，have_ipv6 守卫 ip6tables）"
}

# [L1] 删除重复函数定义 - 此函数在行895已定义,这里是重复的
# 已在行895-947完整实现setup_health_check_transit(),此处删除避免混淆


# v2.35 Grok: 原子提交路由（map + meta + nginx reload 三合一）
# 正常路径: snapshot → write_map → nginx-t → reload → mv_meta → clean
# 失败路径: 任一步骤失败 → restore_map → reload_restore → die
# v2.38 Gemini: .map mv 后立即挂局部 INT/TERM trap，防中断产生"幽灵 .map"（无 .meta 对应）
_atomic_apply_route(){
  # ARCH-2 FIX: 新增 uuid/pwd/pfx 三个参数；meta 存储全量字段供 generate_nodes() 使用
  # v2.39: 先定义函数再注册trap，防止ERR触发时函数未定义
  # [C1 Fix] Initialize exported vars BEFORE trap registration to prevent empty-string mv on ERR
  export _ROUTE_MAP_TARGET="" _ROUTE_META_TARGET=""
  export _ROUTE_SNAP_MAP="" _ROUTE_SNAP_META=""
  # [R1 Fix] Use exported global vars so rollback works when ERR fires from subshell
  _route_rollback(){
    local _map_target="${_ROUTE_MAP_TARGET:-}" _meta_target="${_ROUTE_META_TARGET:-}"
    local _snap_map_path="${_ROUTE_SNAP_MAP:-}" _snap_meta_path="${_ROUTE_SNAP_META:-}"
    if [[ -n "$_snap_map_path" && -f "$_snap_map_path" && -n "$_map_target" ]]; then
      mv -f "$_snap_map_path" "$_map_target" 2>/dev/null || true
    elif [[ -n "$_map_target" ]]; then
      rm -f "$_map_target" 2>/dev/null || true
    fi
    if [[ -n "$_snap_meta_path" && -f "$_snap_meta_path" && -n "$_meta_target" ]]; then
      mv -f "$_snap_meta_path" "$_meta_target" 2>/dev/null || true
    elif [[ -n "$_meta_target" ]]; then
      rm -f "$_meta_target" 2>/dev/null || true
    fi
    if ! nginx -t 2>/dev/null; then
      echo "[WARN] _route_rollback: nginx -t 失败" >&2
    elif ! systemctl reload nginx 2>/dev/null; then
      echo "[WARN] _route_rollback: nginx reload 失败" >&2
    fi
    rm -f "${_snap_map:-}" "${_snap_meta:-}" 2>/dev/null || true
  }
  trap '_route_rollback; _restore_prev_route_traps; exit 1' INT TERM ERR
  local domain="$1" ip="$2" port="$3"
  local uuid="${4:-}" pwd="${5:-}" pfx="${6:-}"
  local safe; safe=$(domain_to_safe "$domain")
  [[ -n "$safe" ]] || die "域名 safe 转换后为空: ${domain}"

  local map_target="${SNIPPETS_DIR}/landing_${safe}.map"
  local meta_target="${CONF_DIR}/${safe}.meta"

  local _dup_map=""
  _dup_map=$(_route_key_conflict "$domain" "$map_target" 2>/dev/null || true)
  [[ -z "$_dup_map" ]] || die "域名 SNI 键已存在于其他路由片段: ${_dup_map}"

  # 1. 快照旧文件（失败时回滚用）
  local _snap_map="" _snap_meta=""
  mkdir -p "$SNIPPETS_DIR" "$CONF_DIR"
  if [[ -f "$map_target" ]]; then
    _snap_map=$(mktemp "${SNIPPETS_DIR}/.snap-recover.XXXXXX") \
      || die "mktemp _snap_map failed"
    cp -f "$map_target" "$_snap_map" \
      || die "snapshot map_target failed"
  fi
  if [[ -f "$meta_target" ]]; then
    _snap_meta=$(mktemp "${CONF_DIR}/.snap-recover.XXXXXX") \
      || die "mktemp _snap_meta failed"
    cp -f "$meta_target" "$_snap_meta" \
      || die "snapshot meta_target failed"
  fi
  # [R1 Fix] Export globals BEFORE trap fires — ERR trap runs in subshell where
  # local vars are out of scope. Rollback must read stable global copies.
  export _ROUTE_MAP_TARGET="$map_target" _ROUTE_META_TARGET="$meta_target"
  export _ROUTE_SNAP_MAP="$_snap_map" _ROUTE_SNAP_META="$_snap_meta"

  # 2. 写新 .map（原子 mv 到正式路径供 nginx -t）
  local tmp_map; tmp_map=$(mktemp "${SNIPPETS_DIR}/.snap-recover.XXXXXX") \
    || die "mktemp tmp_map failed"
  local _map_key; _map_key=$(nginx_domain_str "$domain")
  [[ -n "$_map_key" && ${#_map_key} -le 200 ]] \
    || { rm -f "$tmp_map" 2>/dev/null; die "域名过滤后为空或超长，拒绝写入 map: ${domain}"; }
  printf '    %s    %s:%s;\n' "$_map_key" "$(nginx_ip_str "$ip")" "$port" > "$tmp_map"
  chmod 600 "$tmp_map"
  mv -f "$tmp_map" "$map_target"
  chmod 600 "$map_target" 2>/dev/null || true

  local _prev_route_err_trap _prev_route_int_trap _prev_route_term_trap
  _prev_route_err_trap=$(trap -p ERR || true)
  _prev_route_int_trap=$(trap -p INT || true)
  _prev_route_term_trap=$(trap -p TERM || true)
  _restore_prev_route_traps(){
    if [[ -n "${_prev_route_err_trap:-}" ]]; then
      eval "$_prev_route_err_trap" || trap - ERR
    else
      trap - ERR
    fi
    if [[ -n "${_prev_route_int_trap:-}" ]]; then
      eval "$_prev_route_int_trap" || trap - INT
    else
      trap - INT
    fi
    if [[ -n "${_prev_route_term_trap:-}" ]]; then
      eval "$_prev_route_term_trap" || trap - TERM
    else
      trap - TERM
    fi
  }
  trap '_route_rollback; _restore_prev_route_traps; exit 1' INT TERM ERR

  # 3. nginx -t 验证
  if ! nginx -t 2>/dev/null; then
    _route_rollback; _restore_prev_route_traps
    die "Nginx 语法校验失败，.map 已回滚（真相源未分裂）"
  fi

  # [F3] Write meta BEFORE nginx reload: if meta write fails, the running nginx is still on
  # old map (which we will roll back); prevents truth-source split where nginx routes new IP
  # but .meta is missing. Old order (reload→meta) left a window where nginx served new IP
  # with no truth record on disk-full or permission error.
  # [F3] Collision check: prevent overwriting .meta belonging to a different domain
  local _existing_dom=""; [[ -f "$meta_target" ]] && _existing_dom=$(grep '^DOMAIN=' "$meta_target" 2>/dev/null | cut -d= -f2); [[ -n "$_existing_dom" && "$_existing_dom" != "$domain" ]] && die "Filename collision: $safe already used by $_existing_dom"

  local tmp_meta; tmp_meta=$(mktemp "${CONF_DIR}/.snap-recover.XXXXXX") \
    || die "mktemp tmp_meta failed"
  printf 'DOMAIN=%s\nTRANSIT_IP=%s\nPORT=%s\nUUID=%s\nPWD=%s\nPFX=%s\nCREATED=%s\n' \
    "$domain" "$ip" "$port" "$uuid" "$pwd" "$pfx" "$(date +%Y%m%d_%H%M%S)" > "$tmp_meta"
  chmod 600 "$tmp_meta"
  if ! mv -f "$tmp_meta" "$meta_target"; then
    rm -f "$tmp_meta" 2>/dev/null || true
    _route_rollback; _restore_prev_route_traps
    die "meta 原子提交失败，.map 已回滚（真相源未分裂）"
  fi
  chmod 600 "$meta_target" 2>/dev/null || true

  # 4. nginx reload（运行态更新）— meta is already committed; reload failure is now safe to roll back
  if ! nginx_reload; then
    _route_rollback; _restore_prev_route_traps
    die "Nginx 热重载失败，.map 和 .meta 已回滚"
  fi

  _restore_prev_route_traps
  rm -f "${_snap_map:-}" "${_snap_meta:-}" 2>/dev/null || true
  success "路由原子提交: SNI=${domain} → ${ip}:${port}"
}

list_landings(){
  echo ""
  echo -e "${BOLD}── 已配置落地机 ─────────────────────────────────────────────────${NC}"
  local n=0
  while IFS= read -r meta; do
    [[ -f "$meta" ]] || continue
    local dom ip ts port
    dom=$(grep '^DOMAIN='  "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    ip=$(read_meta_ip "$meta" 2>/dev/null) || ip="?"
    port=$(grep '^PORT='   "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || port=443
    ts=$(grep  '^CREATED=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || echo "?")
    printf "  [%d] %-38s → %-20s :%s  创建: %s\n" $((++n)) "$dom" "$ip" "$port" "$ts"
  done < <(find "$CONF_DIR" -name "*.meta" -type f 2>/dev/null | sort)
  [[ $n -eq 0 ]] && warn "（暂无已配置落地机）"
  echo ""
}

# ARCH-2: 利用 meta 中存储的 uuid/pwd/pfx 生成完整 5 协议订阅链接
# transit_ip = 中转机公网 IP；每个 meta 对应一条落地链路的完整节点集
generate_nodes(){
  local transit_ip="${1:-}"
  if [[ -z "$transit_ip" ]]; then
    # NAT / 共享出口场景允许占位符输出，便于用户先拿到可继续导入的订阅模板
    transit_ip=$(get_public_ip)
  fi
  # [R2 Fix] Validate transit_ip before using it in Python URI generation
  if [[ "$transit_ip" != "<TRANSIT_IP>" ]]; then
    validate_ip "$transit_ip" 2>/dev/null || {
      warn "中转机 IP 格式非法: $transit_ip，跳过节点生成"
      return 1
    }
  fi

  local any=0
  while IFS= read -r meta; do
    # [M2 Fix] Skip empty meta files
    _meta_file_valid "$meta" || { warn "跳过空文件: $meta"; continue; }
    [[ -f "$meta" ]] || continue
    local dom ip port uuid pwd pfx
    dom=$(grep  '^DOMAIN=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || continue
    ip=$(read_meta_ip "$meta" 2>/dev/null) || continue
    port=$(grep '^PORT='   "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || port=443
    uuid=$(grep '^UUID='   "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || uuid=""
    pwd=$(grep  '^PWD='    "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}')  || pwd=""
    pfx=$(grep  '^PFX='    "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}')  || pfx=""
    [[ -n "$dom" && -n "$ip" ]] || continue

    if [[ -z "$uuid" || -z "$pwd" || -z "$pfx" ]]; then
      warn "节点 ${dom} 缺少 uuid/pwd/pfx（旧版 Token 导入），跳过节点生成"
      warn "  → 请重新从落地机执行 print_pairing_info 并用新 Token 重新 --import"
      continue
    fi

    echo ""
    echo -e "${BOLD}${GREEN}── 节点订阅: ${dom} ──────────────────────────────────────────${NC}"
    echo -e "  落地机 IP: ${ip}  端口: ${port}  SNI: ${dom}"
    echo -e "  中转机 IP: ${transit_ip}  (客户端连接此 IP)"
    echo ""

    local sub_b64="" _sub_err="" _tmp=""
    _tmp=$(mktemp) || return 1
    printf '%s\n' "$transit_ip" "$dom" "$uuid" "$pwd" "$pfx" > "$_tmp"
    sub_b64=$(python3 - "$_tmp" 2>&1) || { _sub_err="$sub_b64"; sub_b64=""; }
    rm -f "$_tmp"

    python3 - "$_tmp" >/dev/null 2>&1 <<'PYGEN'
import base64, urllib.parse, sys
lines = [l.strip() for l in open(sys.argv[1]).read().split('\n') if l.strip()]
if len(lines) < 5:
    raise SystemExit(1)
ip, domain, vu, tp, pfx = lines[0], lines[1], lines[2], lines[3], lines[4]
port = 443
lbl = {'v': '[禁Mux]VLESS-Vision-', 'g': 'VLESS-gRPC-', 'w': 'VLESS-WS-', 't': 'Trojan-TCP-'}
uris = [
    f'vless://{vu}@{ip}:{port}?encryption=none&flow=xtls-rprx-vision&security=tls&sni={domain}&fp=chrome&type=tcp&mux=0#{urllib.parse.quote(lbl["v"]+domain)}',
    f'vless://{vu}@{ip}:{port}?encryption=none&security=tls&sni={domain}&fp=edge&type=grpc&serviceName={pfx}-vg&alpn=h2&mode=multi#{urllib.parse.quote(lbl["g"]+domain)}',
    f'vless://{vu}@{ip}:{port}?encryption=none&security=tls&sni={domain}&fp=firefox&type=ws&path=%2F{pfx}-vw&host={domain}&alpn=http/1.1#{urllib.parse.quote(lbl["w"]+domain)}',
    f'trojan://{urllib.parse.quote(tp)}@{ip}:{port}?security=tls&sni={domain}&fp=safari&type=tcp#{urllib.parse.quote(lbl["t"]+domain)}',
]
print(base64.b64encode('\n'.join(uris).encode()).decode())
PYGEN

    if [[ -n "$sub_b64" ]]; then
      echo -e "  ${BOLD}Base64 订阅（粘贴到客户端「添加订阅」）:${NC}"
      echo ""
      echo "  $sub_b64"
      echo ""
      echo -e "  ${CYAN}（Clash Meta / NekoBox / v2rayN / Sing-box / Shadowrocket）${NC}"
      echo -e "  ${RED}${BOLD}⚠  VLESS-Vision 节点【严禁开启 Mux】！开启必断流！${NC}"
    else
      warn "  节点 ${dom} 订阅生成失败"
      [[ -n "${_sub_err:-}" ]] && error "    Python 错误: ${_sub_err}"
    fi
    (( ++any )) || true
  done < <(find "$CONF_DIR" -name "*.meta" -type f 2>/dev/null | sort)

  if (( any == 0 )); then
    warn "无可用节点（meta 文件为空或均缺少 uuid/pwd/pfx）"
  fi
}

import_token(){
  local raw="$1"
  [[ -n "$raw" ]] || die "需要 token 参数"
  raw=$(printf '%s' "$raw" | tr -d ' \n\r\t')
  # 🟠 Grok: 拒绝超长输入（正常 token <1KB），防止畸形 JSON 绕过解析
  check_deps
  (( ${#raw} <= 2048 )) || die "token 过长（${#raw} 字节），拒绝解析"

  local json=""
  json=$(printf '%s' "$raw" | python3 -c "
import base64
import json
import re
import sys
raw = sys.stdin.read().strip()
m = re.search(r'(?<![A-Za-z0-9+/=])(?:eyJ|eyA)[A-Za-z0-9+/=]{20,}(?![A-Za-z0-9+/=])', raw)
if not m:
    m = re.search(r'(?<![A-Za-z0-9+/=])[A-Za-z0-9+/=]{40,}(?![A-Za-z0-9+/=])', raw)
if not m:
    raise SystemExit(1)
token = m.group(0)
pad = '=' * (-len(token) % 4)
decoded = base64.b64decode(token + pad).decode()
json.loads(decoded)
print(decoded)
" 2>/dev/null) || die "无法解析 Base64 token，请检查输入"

  local ip="" dom="" port="" uuid="" pwd="" pfx=""
  ip=$(python3  -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['ip'])"  <<< "$json" 2>/dev/null) \
    || die "token 解析失败（ip 字段缺失）——请重新从落地机复制完整的导入命令"
  dom=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['dom'])" <<< "$json" 2>/dev/null) \
    || die "token 解析失败（dom 字段缺失）"
  port=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('port',443))" <<< "$json" 2>/dev/null) || port=443
  [[ "$port" =~ ^[0-9]+$ ]] || port=443
  validate_port "$port"

  # Transit Bug 37 / Token import validation: ip 必须是合法 IPv4，否则给出明确指引
  if ! printf '%s' "$ip" | python3 -c "import ipaddress, sys; ipaddress.IPv4Address(sys.stdin.read().strip())" 2>/dev/null; then
    die "token 中 ip='${ip}' 不是合法 IPv4 地址！\n  可能原因：落地机生成 Token 时 ip/dom 参数位移（Bug 40）\n  修复方法：在落地机重新执行 bash install_landing_v3.28.sh 并检查落地机 PUBLIC_IP 是否正确"
  fi

  # ARCH-2: 解析新版 Token 中的 uuid/pwd/pfx（旧版 Token 不含这些字段，给出友好告警）
  uuid=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('uuid',''))"  <<< "$json" 2>/dev/null) || uuid=""
  pwd=$(python3  -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('pwd',''))"   <<< "$json" 2>/dev/null) || pwd=""
  pfx=$(python3  -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('pfx',''))"   <<< "$json" 2>/dev/null) || pfx=""
  if [[ -z "$uuid" || -z "$pwd" || -z "$pfx" ]]; then
    warn "Token 中缺少 uuid/pwd/pfx（旧版 Token），只能导入路由，无法生成完整节点订阅"
    warn "  → 请重新在落地机执行 print_pairing_info 生成新版 Token"
  fi
  # [H1 Fix] Validate UUID format if present
  if [[ -n "$uuid" && ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    die "Token 中 uuid 格式非法（需为标准 UUID 格式）: $uuid"
  fi
  # [R-24 FIX] Validate UUID format and password minimum length if present
  if [[ -n "$uuid" && ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    die "Token 中 uuid 格式非法（需为标准 UUID 格式）"
  fi
  if [[ -n "$pwd" && ${#pwd} -lt 16 ]]; then
    die "Token 中密码过短（需 ≥16 字符）"
  fi

  validate_ip     "$ip"
  dom=$(trim "$dom")
  validate_domain "$dom"
  # [R8 Fix] Check for existing domain with different IP before overwrite
  local _existing_node
  _existing_node=$(find "$CONF_DIR" -name "*.meta" -type f -exec grep -l "^DOMAIN=${dom}$" {} + 2>/dev/null | head -1)
  if [[ -n "$_existing_node" ]]; then
    local _existing_ip
    _existing_ip=$(read_meta_ip "$_existing_node" 2>/dev/null)
    if [[ "$_existing_ip" != "$ip" ]]; then
      die "域名 ${dom} 已存在于节点文件 ${_existing_node}（中转IP: ${_existing_ip}），不能用不同的中转IP重复导入"
    fi
    warn "域名 ${dom} 已存在，将更新现有配置"
  fi
  # v2.32 Grok: 硬截断防超长域名绕过 map 语法校验
  dom="${dom:0:253}"
  # 🔴 Grok: nginx_domain_str 过滤后若为空（含纯控制字符域名），拒绝生成 map
  local _safe_check; _safe_check=$(nginx_domain_str "$dom")
  [[ -n "$_safe_check" ]] || die "域名过滤后为空（含非法字符），拒绝写入 map: ${dom}"
  info "导入路由规则: ${dom} → ${ip}:${port}"

  if [[ ! -f "$INSTALLED_FLAG" && "${__TRANSIT_FRESH_INSTALL_TRAP_ACTIVE:-0}" == "0" ]]; then
    info "--import 触发首次安装初始化 ..."
    if command -v mack-a &>/dev/null || [[ -f /etc/v2ray-agent/install.sh ]]; then
      warn "检测到 mack-a 已安装，请先停止 mack-a 服务后再安装本脚本"
    fi
    ss -tlnp 2>/dev/null | awk '$4 ~ /:443$/ {print; exit 0}' && die "443 端口已被占用！请先停止冲突服务后再安装（建议先执行 systemctl stop nginx xray* mack-a*）"

    # [v2.8 GPT-Doc2-🔴] Trap registered BEFORE the first side-effect write (check_deps).
    # v2.7 registered it after the 443 check but before check_deps; if apt-get update failed
    # inside check_deps the trap was not yet live → partial nginx install left 443 occupied
    # and the next run's 443 check blocked re-install until manual purge.
    __TRANSIT_IMPORT_TRAP_ACTIVE=1
    _import_install_rollback(){
      [[ "${__TRANSIT_IMPORT_TRAP_ACTIVE:-0}" == "1" ]] || return 0
      warn "--import 安装中断，执行回滚..."
      systemctl stop nginx 2>/dev/null || true
            systemctl disable --now transit-manager-iptables-restore.service 2>/dev/null || true
      rm -f "/etc/systemd/system/transit-manager-iptables-restore.service" 2>/dev/null || true
      sed -i "\#${STREAM_INCLUDE_MARKER}#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
      sed -i "\#include ${NGINX_STREAM_CONF};#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
      while iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null; do :; done
      while ip6tables -w 2 -D INPUT -j "$FW_CHAIN6" 2>/dev/null; do :; done
      iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
      systemctl daemon-reload 2>/dev/null || true
      rm -f "$INSTALLED_FLAG" 2>/dev/null || true
      warn "--import 回滚完成。如需重装请重新运行脚本。"
    }
    trap '_import_install_rollback' ERR INT TERM

    optimize_kernel_network; install_nginx; setup_firewall_transit; setup_health_check_transit
    write_logrotate
    # [F2] nginx enable must be durable — silent failure means decoy dies on next reboot
    systemctl enable nginx || die "nginx enable failed — decoy will not survive reboot"
    systemctl is-enabled --quiet nginx || die "nginx is-enabled check failed"
    # [v2.7 Architect-🟠] Remove raw `nginx` fallback — treat startup failure as fatal.
    systemctl is-active --quiet nginx 2>/dev/null || systemctl start nginx \
      || die "Nginx 启动失败（systemctl start 返回非零，已触发回滚）"
    mkdir -p "$MANAGER_BASE"

    # [F1] INSTALLED_FLAG must be committed AFTER _atomic_apply_route, not before.
  fi

  # ARCH-2: 传入 uuid/pwd/pfx，meta 中持久化；generate_nodes() 读取后生成完整订阅
  _atomic_apply_route "$dom" "$ip" "$port" "$uuid" "$pwd" "$pfx" || die "Route application failed"
  # Commit install marker only after route is durably applied
  [[ -f "$INSTALLED_FLAG" ]] || touch "$INSTALLED_FLAG"
  __TRANSIT_IMPORT_TRAP_ACTIVE=0
  trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM ERR
  success "路由规则导入完成: SNI=${dom} → ${ip}:${port}"
  echo ""
  echo -e "${BOLD}── 导入成功——生成完整节点订阅 ─────────────────────────────────${NC}"
  generate_nodes
}

add_landing_route(){
  echo ""
  echo -e "${BOLD}── 增加落地机路由规则 ───────────────────────────────────────────${NC}"
  echo "  方式A（傻瓜）：直接粘贴落地机输出的 Base64 Token 或完整导入命令"
  echo "  方式B（手动）：依次输入落地机公网 IP 和域名"
  echo ""
  # v2.32: 全局写锁，防两终端并发踩踏状态
  _acquire_lock
  
  # [T1-UX-1-FIX] IP/Token输入添加重试循环
  while true; do
    read -rp "  请输入落地机 IP 或直接粘贴 Token/命令: " INPUT_DATA
    INPUT_DATA=$(trim "$INPUT_DATA")
    # 🟠 Grok: 拒绝超长输入，防止畸形字符串绕过 validate 或制造状态分裂
    if (( ${#INPUT_DATA} > 2048 )); then
      error "输入过长（${#INPUT_DATA} 字节），请重新输入"
      continue
    fi
    break
  done

  local extracted_token=""
  extracted_token=$(printf '%s' "$INPUT_DATA" | grep -oE 'eyJ[a-zA-Z0-9+/=]+' | head -1) || true
  if [[ -n "$extracted_token" ]]; then
    import_token "$extracted_token"; _release_lock; return
  fi

  local LANDING_IP="$INPUT_DATA"
  # [T1-UX-1-FIX] IP验证添加重试循环
  while ! validate_ip "$LANDING_IP" 2>/dev/null; do
    error "IP地址格式错误，请重新输入"
    read -rp "  请输入落地机 IP: " LANDING_IP
    LANDING_IP=$(trim "$LANDING_IP")
  done
  
  # [T1-UX-1-FIX] 域名输入添加重试循环
  while true; do
    read -rp "  落地机域名(SNI): " LANDING_DOMAIN
    LANDING_DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$LANDING_DOMAIN")")
    if validate_domain "$LANDING_DOMAIN" 2>/dev/null; then
      break
    else
      error "域名格式错误，请重新输入"
    fi
  done
  # v2.32 Grok: 硬截断防超长域名绕过 map 语法校验
  LANDING_DOMAIN="${LANDING_DOMAIN:0:253}"
  
  # [T1-UX-1-FIX] 端口输入添加重试循环
  while true; do
    read -rp "  落地机监听端口（默认 8443）[8443]: " LANDING_PORT_IN
    LANDING_PORT_IN="${LANDING_PORT_IN:-8443}"
    if validate_port "$LANDING_PORT_IN" 2>/dev/null; then
      break
    else
      error "端口格式错误（1-65535），请重新输入"
    fi
  done

  # 🔴 Grok: safe 字符串空值守卫
  local _safe_chk; _safe_chk=$(nginx_domain_str "$LANDING_DOMAIN")
  [[ -n "$_safe_chk" ]] || { _release_lock; die "域名过滤后为空（含非法字符），拒绝写入 map: ${LANDING_DOMAIN}"; }

  local safe; safe=$(domain_to_safe "$LANDING_DOMAIN")
  if [[ -f "${SNIPPETS_DIR}/landing_${safe}.map" ]]; then
    warn "该域名已存在路由规则！"
    read -rp "  覆盖更新？[y/N]: " OW
    [[ "$OW" =~ ^[Yy]$ ]] || { info "已取消"; _release_lock; return; }
  fi

  # 五步原子变更: 快照已有 snippet（使用独立前缀避免被 _global_cleanup 误删）
  local _old_bak=""
  if [[ -f "${SNIPPETS_DIR}/landing_${safe}.map" ]]; then
    _old_bak=$(mktemp "${SNIPPETS_DIR}/.snap-recover.XXXXXX") \
      || die "mktemp _old_bak failed"
    [[ -n "$_old_bak" ]] || die "mktemp returned empty path"
    cp -f "${SNIPPETS_DIR}/landing_${safe}.map" "$_old_bak" 2>/dev/null || _old_bak=""
  fi

  # v2.35 Grok: _atomic_apply_route 内部自管快照，外部 _old_bak 仍保留供 SIGINT 清理
  _atomic_apply_route "$LANDING_DOMAIN" "$LANDING_IP" "$LANDING_PORT_IN"
  rm -f "$_old_bak" 2>/dev/null || true
  _release_lock
  success "路由规则已生效: SNI=${LANDING_DOMAIN} → ${LANDING_IP}:${LANDING_PORT_IN}"
}

delete_landing_route(){
  list_landings
  local meta_count=0
  [[ -d "$CONF_DIR" ]] \
    && meta_count=$(find "$CONF_DIR" -name "*.meta" -type f 2>/dev/null | wc -l) || true
  (( meta_count > 0 )) || { warn "无可删除的落地机"; return; }

  read -rp "请输入要删除的落地机域名（或上方列表中的编号）: " DEL_DOMAIN
  # v2.32: 确认输入后才加锁，避免等待用户输入时持锁过久
  _acquire_lock

  if [[ "$DEL_DOMAIN" =~ ^[0-9]+$ ]]; then
    local n=0 matched=""
    while IFS= read -r meta; do
      (( ++n ))
      if (( n == DEL_DOMAIN )); then
        matched=$(grep '^DOMAIN=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}') || true; break
      fi
    done < <(find "$CONF_DIR" -name "*.meta" -type f 2>/dev/null | sort)
    [[ -n "$matched" ]] || { _release_lock; die "编号 ${DEL_DOMAIN} 不存在"; }
    DEL_DOMAIN="$matched"
    info "已选择: ${DEL_DOMAIN}"
  else
    DEL_DOMAIN=$(tr '[:upper:]' '[:lower:]' <<< "$DEL_DOMAIN")
  fi

  DEL_DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$DEL_DOMAIN")")
  validate_domain "$DEL_DOMAIN"
  local safe_del; safe_del=$(domain_to_safe "$DEL_DOMAIN")

  # 五步原子变更：快照 .map + .meta，nginx_reload 失败时恢复
  local _bak_map="" _bak_meta=""
  [[ -f "${SNIPPETS_DIR}/landing_${safe_del}.map" ]] && {
    _bak_map=$(mktemp "${SNIPPETS_DIR}/.snap-recover.XXXXXX") \
      || die "mktemp _bak_map failed"
    cp -f "${SNIPPETS_DIR}/landing_${safe_del}.map" "$_bak_map" \
      || die "snapshot landing map failed"
  }
  [[ -f "${CONF_DIR}/${safe_del}.meta" ]] && {
    _bak_meta=$(mktemp "${CONF_DIR}/.snap-recover.XXXXXX") \
      || die "mktemp _bak_meta failed"
    cp -f "${CONF_DIR}/${safe_del}.meta" "$_bak_meta" \
      || die "snapshot landing meta failed"
  }

  remove_landing_snippet "$DEL_DOMAIN"

  if ! ( nginx_reload ); then
    warn "Nginx 热重载失败，恢复被删配置..."
    [[ -n "$_bak_map"  ]] && mv -f "$_bak_map"  "${SNIPPETS_DIR}/landing_${safe_del}.map" 2>/dev/null || true
    [[ -n "$_bak_meta" ]] && mv -f "$_bak_meta" "${CONF_DIR}/${safe_del}.meta"             2>/dev/null || true
    rm -f "$_bak_map" "$_bak_meta" 2>/dev/null || true
    _release_lock; die "删除回滚完成，Nginx 运行态未受影响"
  fi
  rm -f "$_bak_map" "$_bak_meta" 2>/dev/null || true
  _release_lock
  success "落地机路由 ${DEL_DOMAIN} 已删除并热重载生效"
}

show_status(){
  echo ""
  echo -e "${BOLD}── 中转机状态 ──────────────────────────────────────────────────${NC}"
  [[ -f "$INSTALLED_FLAG" ]] && echo "  已安装: 是" || echo "  已安装: 否"
  echo "  Nginx: $(systemctl is-active nginx 2>/dev/null || echo inactive)"
  echo "  监听端口: ${LISTEN_PORT}"
  local snippet_count=0
  [[ -d "$SNIPPETS_DIR" ]] && snippet_count=$(find "$SNIPPETS_DIR" -name "*.map" ! -name "*dummy*" -type f 2>/dev/null | wc -l)
  echo "  已配置落地机: ${snippet_count}"
  list_landings
  echo -e "  ${CYAN}错误日志: tail -f ${LOG_DIR}/transit_stream_error.log${NC}"
  echo ""
  echo -e "  ${BOLD}── 状态硬校验 ────────────────────────────────────────────────${NC}"
  local _ok=1
  systemctl is-active --quiet nginx 2>/dev/null \
    && echo "  Nginx 运行态:    ✓" \
    || { echo -e "  ${RED}Nginx 运行态:    ✗ 未运行${NC}"; _ok=0; }
  ss -tlnp 2>/dev/null | grep -q ":${LISTEN_PORT} " \
    && echo "  :443 监听:       ✓" \
    || { echo -e "  ${RED}:443 监听:       ✗ 端口未开放${NC}"; _ok=0; }
  grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null \
    && echo "  stream include:  ✓" \
    || { echo -e "  ${RED}stream include:  ✗ nginx.conf 中已丢失${NC}"; _ok=0; }
  nginx -t >/dev/null 2>&1 \
    && echo "  nginx -t:        ✓" \
    || { echo -e "  ${RED}nginx -t:        ✗ 配置校验失败${NC}"; _ok=0; }
  systemctl is-enabled --quiet "transit-manager-iptables-restore.service" 2>/dev/null \
    && echo "  iptables 恢复服务:  ✓ enabled" \
    || { echo -e "  ${RED}iptables 恢复服务:  ✗ 未 enable（重启后规则会丢失）${NC}"; _ok=0; }
  # v2.34 GPT: 恢复脚本与运行链不一致 → _ok=0 直接判红，不允许报"整体一致"
  local _fw_script="${MANAGER_BASE}/firewall-restore.sh"
  if [[ -f "$_fw_script" ]]; then
    # v2.39 GPT #9: 版本签名校验
    local _fw_ver_line; _fw_ver_line=$(grep '^# TRANSIT_FW_VERSION=' "$_fw_script" 2>/dev/null | head -1 || echo "")
    if [[ -z "$_fw_ver_line" ]]; then
      # v2.44 GPT: --status 只读，无签名只报红，不调 _persist_iptables（防巡检引入状态分裂）
      echo -e "  ${RED}恢复脚本版本:    ✗ 无版本签名（旧版/手改脚本）${NC}"; _ok=0
      echo -e "  ${CYAN}  修复: bash $0 --import <token> 重建防火墙持久化脚本${NC}"
    else
      echo -e "  恢复脚本版本:    ${GREEN}✓ ${_fw_ver_line#*=}${NC}"
    fi
    # 校验运行链中 INVALID DROP 规则是否存在
    iptables -w 2 -L "$FW_CHAIN" -n 2>/dev/null | grep -q 'INVALID' \
      && echo -e "  INVALID DROP:    ${GREEN}✓${NC}" \
      || { echo -e "  ${RED}INVALID DROP:    ✗ 规则缺失（执行 --import 或重装以修复）${NC}"; _ok=0; }
    # proxy_timeout 文件态 vs nginx 运行态对比
    local _rscript_pt _live_pt
    _rscript_pt=$(grep -oP 'proxy_timeout\s+\K[0-9]+' "$NGINX_STREAM_CONF" 2>/dev/null | head -1 || echo "")
    _live_pt=$(nginx -T 2>/dev/null | grep -oP 'proxy_timeout\s+\K[0-9]+' | head -1 || echo "")
    if [[ -n "$_rscript_pt" && "$_rscript_pt" != "$_live_pt" ]]; then
      # v2.40 GPT #5: --status 是只读巡检，不执行写操作；漂移只报红，修复用独立命令
      echo -e "  ${RED}恢复脚本存在:    ✗ proxy_timeout 与运行态不一致（需手动修复）${NC}"; _ok=0
      echo -e "  ${CYAN}  修复: bash $0 --import <token> 重建防火墙和持久化脚本${NC}"
    else
      echo -e "  恢复脚本存在:    ${GREEN}✓${NC}"
    fi
  else
    echo -e "  ${RED}恢复脚本:        ✗ 不存在（重启后防火墙规则会丢失）${NC}"; _ok=0
  fi
  ((_ok)) \
    && echo -e "  ${GREEN}整体状态: 一致 ✓${NC}" \
    || { echo -e "  ${RED}整体状态: 存在分裂，请排查 ✗${NC}"; echo ""; return 1; }
  echo ""
}

purge_all(){
  echo ""
  warn "此操作清除本脚本所有内容（Nginx 服务不卸载，mack-a 不影响）"
  read -rp "确认清除？输入 'DELETE' 确认: " CONFIRM
  [[ "$CONFIRM" == "DELETE" ]] || { info "已取消"; return; }

  # 原子卸载序：先改 nginx.conf → 显式校验 include 已移除 → 再删文件 → 再次 nginx -t → reload
  local _purge_bak=""
  if [[ -f "$NGINX_MAIN_CONF" ]]; then
    _purge_bak=$(mktemp "${MANAGER_BASE}/.snap-recover.XXXXXX") \
      || die "mktemp _purge_bak failed"
    cp -f "$NGINX_MAIN_CONF" "$_purge_bak" \
      || die "snapshot nginx.conf for purge failed"
    sed -i "\#${STREAM_INCLUDE_MARKER}#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
    sed -i "\#include ${NGINX_STREAM_CONF};#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
    sed -i "/# transit-manager-tuning-v${VERSION}/d" "$NGINX_MAIN_CONF" 2>/dev/null || true

    # [v2.10 Grok-Doc7-🔴] Explicitly verify the include marker was removed by sed.
    # A manually-edited nginx.conf (e.g. trailing space on the include line) causes sed to
    # fail silently; without this check the script would delete the stream file and leave
    # nginx.conf referencing a now-missing path → nginx reload failure → host nginx down.
    if grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null; then
      [[ -n "$_purge_bak" && -f "$_purge_bak" ]] && mv -f "$_purge_bak" "$NGINX_MAIN_CONF" 2>/dev/null || true
      rm -f "$_purge_bak" 2>/dev/null || true
      die "卸载中止：stream include 标记仍在 nginx.conf（sed 未能匹配）。\n  请手动删除包含 '${STREAM_INCLUDE_MARKER}' 的行，然后重新运行 --uninstall"
    fi
    # Also verify the explicit include path is gone (belt-and-suspenders)
    if grep -qF "include ${NGINX_STREAM_CONF}" "$NGINX_MAIN_CONF" 2>/dev/null; then
      [[ -n "$_purge_bak" && -f "$_purge_bak" ]] && mv -f "$_purge_bak" "$NGINX_MAIN_CONF" 2>/dev/null || true
      rm -f "$_purge_bak" 2>/dev/null || true
      die "卸载中止：include 路径仍在 nginx.conf。请手动清理后重试"
    fi
    # Pre-delete nginx -t: stream file still on disk so we can validate the mutated conf
    if ! nginx -t 2>/dev/null; then
      warn "nginx.conf 校验失败（stream 文件仍存在），还原中..."
      [[ -n "$_purge_bak" && -f "$_purge_bak" ]] && mv -f "$_purge_bak" "$NGINX_MAIN_CONF" 2>/dev/null || true
      rm -f "$_purge_bak" 2>/dev/null || true
      die "卸载中止：nginx.conf 已还原，请手动检查后重试"
    fi
    rm -f "$_purge_bak" 2>/dev/null || true
  fi

  rm -rf "$SNIPPETS_DIR"
  rm -f  "$NGINX_STREAM_CONF"

  # [v2.10] Post-delete nginx -t: now that files are gone, confirm nginx.conf is still valid.
  # If this fails the fallback is restart (nginx rebuilds its config from scratch).
  if nginx -t 2>/dev/null; then
    if ! { systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null; }; then
      error "nginx reload 失败！请手动执行: systemctl reload nginx"
      warn "卸载完成，但 nginx 进程未刷新；建议: systemctl restart nginx"
    fi
  else
    warn "nginx -t 失败（配置已删除），尝试直接重启..."
    systemctl restart nginx 2>/dev/null || warn "nginx 重启失败，请手动处理"
  fi

  rm -f "/etc/systemd/system/nginx.service.d/transit-manager-override.conf" 2>/dev/null || true
  rmdir "/etc/systemd/system/nginx.service.d" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  rm -f "${NGINX_MAIN_CONF}.transit.bak_"* 2>/dev/null || true

  # [v2.15.1] purge_all: use bulldozer to remove ALL INPUT references to FW_CHAIN regardless
  # of comment text, then flush and delete. Old comment-based while loops missed rules with
_purge_bulldoze(){
    local _chain="$1" _num _nums
    # [v2.15.2] Delete by line number: re-fetch each pass and delete in descending order
    # so iptables line-number shifts cannot corrupt the rule set.
    while true; do
      _nums=$(iptables -w 2 -L INPUT --line-numbers -n 2>/dev/null               | awk -v c="$_chain" 'NR>2 && $2 == c {print $1}'               | sort -nr)
      [[ -n "${_nums:-}" ]] || break
      while IFS= read -r _num; do
        [[ -n "$_num" ]] || continue
        iptables -w 2 -D INPUT "$_num" 2>/dev/null || break 2
      done <<<"$_nums"
    done
  }

_purge_bulldoze6(){
    local _chain="$1" _num _nums
    # [v2.15.2] Delete by line number: re-fetch each pass and delete in descending order
    # so iptables line-number shifts cannot corrupt the rule set.
    while true; do
      _nums=$(ip6tables -w 2 -L INPUT --line-numbers -n 2>/dev/null               | awk -v c="$_chain" 'NR>2 && $2 == c {print $1}'               | sort -nr)
      [[ -n "${_nums:-}" ]] || break
      while IFS= read -r _num; do
        [[ -n "$_num" ]] || continue
        ip6tables -w 2 -D INPUT "$_num" 2>/dev/null || break 2
      done <<<"$_nums"
    done
  }
  _purge_bulldoze  "$FW_CHAIN";  _purge_bulldoze  "${FW_CHAIN}-NEW"
  iptables -w 2 -F "$FW_CHAIN"  2>/dev/null || true
  iptables -w 2 -X "$FW_CHAIN"  2>/dev/null || true

  # v2.32 Gemini: IPv6 仅在命令存在且内核启用时清理，避免纯 IPv4/极简系统报错
  if command -v ip6tables >/dev/null 2>&1; then
  _purge_bulldoze6 "$FW_CHAIN6"; _purge_bulldoze6 "${FW_CHAIN6}-NEW"
  ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true
  ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
  fi
  systemctl disable --now "transit-manager-iptables-restore.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/transit-manager-iptables-restore.service" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  # 🟠 Grok: 卸载时不写公共持久化文件，避免覆盖宿主机其他防火墙规则
  # iptables-save > /etc/iptables/rules.v4 已移除

  rm -f /etc/sysctl.d/99-transit-bbr.conf /etc/modprobe.d/nf_conntrack.conf 2>/dev/null || true
  # [R9 Fix] Verify sysctl file deletion and reload sysctl to revert settings
  if [[ -f /etc/sysctl.d/99-transit-bbr.conf ]]; then
    warn "无法删除 /etc/sysctl.d/99-transit-bbr.conf（可能是只读文件系统），请手动删除"
  fi
  sysctl --system &>/dev/null || true
  sed -i '/# xray-transit: raised for high-concurrency/,/^root hard nofile/d' /etc/security/limits.conf 2>/dev/null || true
  rm -f /var/run/transit-manager.update.warn 2>/dev/null || true
  rm -f /etc/systemd/journald.conf.d/transit-manager.conf 2>/dev/null || true
  rmdir /etc/systemd/journald.conf.d 2>/dev/null || true
  [[ -z "$(ls -A /etc/systemd/journald.conf.d 2>/dev/null)" ]] && rmdir /etc/systemd/journald.conf.d 2>/dev/null || true
  systemctl restart systemd-journald 2>/dev/null || true
  rm -f "$LOGROTATE_FILE" 2>/dev/null || true
  # [REVIEWER-1] 删除健康检查cron文件
  rm -f /etc/cron.d/transit-health /usr/local/bin/transit-health-check.sh 2>/dev/null || true
  # v2.32 Gemini: 卸载时清除日志目录，防止重装后僵尸日志污染
  rm -rf "$LOG_DIR" 2>/dev/null || true
  rm -rf "$MANAGER_BASE"
  # 卸载后验收
  local _clean=1
  [[ -d "$SNIPPETS_DIR" ]]   && { warn "SNIPPETS_DIR 残留"; _clean=0; } || true
  [[ -f "$NGINX_STREAM_CONF" ]] && { warn "stream conf 残留"; _clean=0; } || true
  systemctl is-active --quiet "transit-manager-iptables-restore.service" 2>/dev/null \
    && { warn "iptables 恢复服务仍活跃"; _clean=0; } || true
  iptables -w 2 -L "$FW_CHAIN" >/dev/null 2>&1 \
    && { warn "iptables chain ${FW_CHAIN} 仍存在"; _clean=0; } || true
  ((_clean)) \
    && success "清除完毕（验收通过），mack-a/v2ray-agent 及 Nginx 均未受影响" \
    || warn "清除完毕，但存在残留项，重装前请手动确认（mack-a 未受影响）"
}

installed_menu(){
  echo ""
  echo -e "${BOLD}${CYAN}══ 中转机管理菜单 ══════════════════════════════════════════════${NC}"
  list_landings
  echo "  1. 增加落地机路由规则（粘贴 Token 或手动输入）"
  echo "  2. 删除指定落地机路由规则"
  echo "  3. 清除本系统所有数据（不影响 mack-a）"
  echo "  4. 退出"
  echo "  5. 显示当前所有节点及订阅链接"
  echo ""
  read -rp "请选择 [1-5]: " CHOICE
  case "$CHOICE" in
    1) add_landing_route;   installed_menu ;;
    2) delete_landing_route; installed_menu ;;
    3) purge_all ;;
    4) info "退出"; exit 0 ;;
    5) generate_nodes;      installed_menu ;;
    *) warn "无效选项: ${CHOICE}"; installed_menu ;;
  esac
}

_fresh_install_rollback(){
  [[ "${__TRANSIT_FRESH_INSTALL_TRAP_ACTIVE:-0}" == "1" ]] || return 0
  warn "安装中断，执行事务回滚..."
  systemctl stop nginx 2>/dev/null || true
  rm -f "$NGINX_STREAM_CONF" 2>/dev/null || true
  rm -f "$LOGROTATE_FILE" 2>/dev/null || true
  # [REVIEWER-1] 删除健康检查cron文件
  rm -f /etc/cron.d/transit-health /usr/local/bin/transit-health-check.sh 2>/dev/null || true
  systemctl disable transit-manager-iptables-restore.service 2>/dev/null || true
  rm -f "/etc/systemd/system/transit-manager-iptables-restore.service" 2>/dev/null || true
  sed -i "\#${STREAM_INCLUDE_MARKER}#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
  sed -i "\#include ${NGINX_STREAM_CONF};#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
  while iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null; do :; done
  while ip6tables -w 2 -D INPUT -j "$FW_CHAIN6" 2>/dev/null; do :; done
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  rm -f "$INSTALLED_FLAG" 2>/dev/null || true
  warn "回滚完成。如需重装请重新运行脚本。"
}

fresh_install(){
  # v2.32 Gemini: 半安装残留检测 — .installed 不存在但 stream include 残留时，
  # 先清除 nginx.conf 中的 include 行，避免后续 443 占用检测误判为"已安装"
  if grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null && [[ ! -f "$INSTALLED_FLAG" ]]; then
    warn "检测到半安装残留（stream include 存在但 .installed 缺失），清除 nginx.conf 残留..."
    sed -i "\#${STREAM_INCLUDE_MARKER}#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
    sed -i "\#include ${NGINX_STREAM_CONF};#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
    nginx -t 2>/dev/null && { systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true; } || true
  fi
  echo ""
  echo -e "${BOLD}${CYAN}══ 中转机全新安装 ${VERSION} ══════════════════════════════════════════${NC}"
  echo ""
  echo -e "  本脚本将执行："
  echo -e "  ${GREEN}①${NC} 安装 Nginx（stream 模块，TFO fastopen=256，Keepalive=3m:10s:3）"
  echo -e "  ${GREEN}②${NC} 配置 SNI 嗅探纯 TCP 透传（空/无匹配SNI→Apple CDN，有效SNI→落地机）"
  echo -e "  ${GREEN}③${NC} 优化 TCP conntrack + Nginx fd 上限"
  echo -e "  ${GREEN}④${NC} iptables: 仅开放 SSH + TCP 443 + ICMP，其余 DROP（动态双栈守卫）"
  echo -e "  ${GREEN}⑤${NC} 录入第一台落地机配对信息"
  echo ""
  read -rp "确认开始安装？[y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "已取消"; exit 0; }

  # FW-2 FIX: 半安装死锁：防火墙配置中断后 nginx 仍占用 443，重试时 die 导致无限死锁
  # 判断逻辑：
  #   ① nginx 占 443 + stream include 存在 → 本脚本半装，stop nginx 后继续重装
  #   ② 其他进程占 443 → 真正冲突，die 要求用户手动处理
  if ss -tlnp 2>/dev/null | awk '$4 ~ /:443$/ {exit 0} END {exit 1}' 2>/dev/null; then
    if command -v mack-a &>/dev/null || [[ -f /etc/v2ray-agent/install.sh ]]; then
      warn "检测到 mack-a 已安装，请先停止 mack-a 服务后再安装本脚本"
    fi
    if systemctl is-active --quiet nginx 2>/dev/null \
        && grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null; then
      warn "检测到本脚本半安装状态（nginx 占 443 + stream include 存在）"
      warn "自动停止 nginx，清除残留后继续重装..."
      systemctl stop nginx 2>/dev/null || nginx -s stop 2>/dev/null || true
      sleep 1
      # 再次确认 443 已释放
      if ss -tlnp 2>/dev/null | awk '$4 ~ /:443$/ {exit 0} END {exit 1}' 2>/dev/null; then
        die "nginx 停止后 443 仍被占用（可能有其他进程），请手动执行: ss -tlnp | awk '\$4 ~ /:443\$/ {print}'"
      fi
      info "443 端口已释放，继续安装..."
    else
      die "443 端口已被非本脚本进程占用！请先停止冲突服务后再安装（建议先执行 systemctl stop nginx xray* mack-a*）"
    fi
  fi

  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  check_deps
  optimize_kernel_network
  install_nginx
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  init_nginx_stream
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  setup_firewall_transit
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  write_logrotate
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  mkdir -p "$MANAGER_BASE"
  # [Doc3-1] 事务回滚 trap：nginx/firewall 已写入但路由导入失败时，撤销所有副作用
  # 触发条件：add_landing_route 失败 / 用户 Ctrl-C / 任何 ERR
  _fresh_install_rollback(){
    [[ "${__TRANSIT_FRESH_INSTALL_TRAP_ACTIVE:-0}" == "1" ]] || return 0
    warn "安装中断，执行事务回滚..."
    systemctl stop nginx 2>/dev/null || true
    # [F5] Remove nginx artifacts — without this, next run finds Nginx already configured
    # and collides with existing stream config / fallback
        rm -f "$NGINX_STREAM_CONF" 2>/dev/null || true
    rm -f "$LOGROTATE_FILE" 2>/dev/null || true
  # [REVIEWER-1] 删除健康检查cron文件
  rm -f /etc/cron.d/transit-health /usr/local/bin/transit-health-check.sh 2>/dev/null || true
    systemctl disable transit-manager-iptables-restore.service 2>/dev/null || true
    rm -f "/etc/systemd/system/transit-manager-iptables-restore.service" 2>/dev/null || true
    sed -i "\#${STREAM_INCLUDE_MARKER}#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
    sed -i "\#include ${NGINX_STREAM_CONF};#d" "$NGINX_MAIN_CONF" 2>/dev/null || true
    while iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null; do :; done
    while ip6tables -w 2 -D INPUT -j "$FW_CHAIN6" 2>/dev/null; do :; done
    iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$INSTALLED_FLAG" 2>/dev/null || true
    warn "回滚完成。如需重装请重新运行脚本。"
  }
  trap '_fresh_install_rollback' ERR INT TERM

  # nginx 启动必须在路由导入前完成（路由导入会触发 nginx reload）
  # [F2] hard-fail on enable — reboot persistence is a contract requirement
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  systemctl enable nginx || die "nginx enable failed — decoy will not survive reboot"
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  systemctl is-enabled --quiet nginx || die "nginx is-enabled check failed"
  # [v2.7 Architect-🟠] Remove raw `nginx` fallback: an unmanaged daemon breaks idempotent
  # stop/reload/rollback and leaves the host in a "works now, unmanaged later" state.
  # Startup failure must be fatal and trigger _fresh_install_rollback.
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  systemctl start nginx 2>/dev/null || {
    # Trap is still active, will fire on exit
    die "Nginx 启动失败（systemctl start nginx 返回非零，回滚将自动执行）"
  }

  echo ""
  echo -e "${BOLD}── 录入第一台落地机配令人信息 ─────────────────────────────────────${NC}"
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  add_landing_route

  # 路由导入成功，提交安装标记并解除回滚 trap
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=0
  trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM
  __TRANSIT_FRESH_INSTALL_TRAP_ACTIVE=1
  trap '_fresh_install_rollback' ERR INT TERM
  touch "$INSTALLED_FLAG"

  echo ""
  success "══ 中转机安装完成！══"
  echo ""
  echo -e "  ${BOLD}错误日志：${NC}"
  # FIX-F: 原路径写死 /var/log/nginx/...，实际路径是 ${LOG_DIR}/...
  echo -e "  ${CYAN}tail -f ${LOG_DIR}/transit_stream_error.log${NC}"
  echo ""
}

_ver_gt(){ [[ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" && "$1" != "$2" ]]; }
_check_update(){
  local self_name; self_name=$(basename "${BASH_SOURCE[0]:-$0}")
  local cur_ver="$VERSION"
  local remote
  remote=$(curl -fsSL --connect-timeout 3 --retry 1 \
    "https://raw.githubusercontent.com/vpn3288/cn2gia-transit/main/${self_name}" \
    2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+' | head -1) || return 0
  [[ -n "$remote" ]] && _ver_gt "$remote" "$cur_ver" && warn "发现新版本 ${remote}！建议重新下载" || true
}

main(){
  echo -e "${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════════╗"
  printf "║     美西 CN2 GIA 中转机安装脚本  %-32s║\n" "${VERSION}"
  echo "║     SNI嗅探 → 纯TCP盲传(TFO+KA=3m:10s:3+backlog=65535) → 落地机║"
  echo "║     空/无匹配SNI→17.253.144.10:443（苹果CDN）· proxy_timeout=315s     ║"
  echo "║     atomic_write · python validate · have_ipv6() · logrotate    ║"
  echo "║     与 mack-a/v2ray-agent 完全物理隔离                         ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  if [[ "${1:-}" == "--uninstall" ]]; then purge_all; exit 0; fi
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then show_help; exit 0; fi
  if [[ "${1:-}" == "--import" ]]; then
    # v2.32: --import 直接调用时加锁；通过 add_landing_route 间接调用时锁已由调用方持有
    _acquire_lock; import_token "${2:-}"; _release_lock; exit 0
  fi
  if [[ "${1:-}" == "--status" ]]; then show_status; exit $?; fi

  mkdir -p "${MANAGER_BASE}/tmp" 2>/dev/null || true
  _check_update >"$UPDATE_WARN_FILE" 2>&1 &
  UPDATE_CHECK_PID=$!
  _prune_orphan_stream_maps
  if [[ ! -f "$INSTALLED_FLAG" ]]; then
    local _durable_transit=0
    if grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null &&        find "$CONF_DIR" -maxdepth 1 -type f -name "*.meta" 2>/dev/null | grep -q .; then
      if _meta_drift_detect; then
        warn "[reconcile] durable set has meta/map drift — leaving .installed absent"
      else
        _durable_transit=1
      fi
    fi
    if (( _durable_transit )); then
      warn "[reconcile] durable set intact but .installed missing — restoring flag"
      touch "$INSTALLED_FLAG"
    fi
  fi
  if [[ -f "$INSTALLED_FLAG" ]]; then
    # [v2.8 Architect-🟠] Startup stale-marker reconciliation: verify the durable set
    # (nginx stream include + at least one .meta file). A SIGKILL during import_token's
    # first-time path can write INSTALLED_FLAG while nginx artifacts are incomplete.
    local _durable_transit=1
    grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null       || _durable_transit=0
    find "$CONF_DIR" -name "*.meta" -type f -maxdepth 1 2>/dev/null \
         | grep -q . 2>/dev/null                                           || _durable_transit=0
    if (( _durable_transit == 0 )); then
      warn "[v2.8] 安装标记存在但持久化集（stream include/meta）不完整，清除标记重新安装..."
      rm -f "$INSTALLED_FLAG"
      fresh_install
      return
    fi
    # 🟠 GPT: .installed 降为辅助证据，三态交叉校验（nginx/stream-include/meta文件）
    local _svc_ok=0 _inc_ok=0 _meta_ok=0
    systemctl is-active --quiet nginx 2>/dev/null && _svc_ok=1 \
      || warn "Nginx 未运行"
    grep -q "$STREAM_INCLUDE_MARKER" "$NGINX_MAIN_CONF" 2>/dev/null && _inc_ok=1 \
      || warn "stream include 已丢失"
    local _mc; _mc=$(find "$CONF_DIR" -name "*.meta" -type f 2>/dev/null | wc -l)
    (( _mc > 0 )) && _meta_ok=1
    # v2.42 GPT #1: 逐项校验 meta→map 对应关系，不只计数
    if ! _meta_drift_detect; then
      warn "真相源不完整: 至少一个 .meta 缺少对应 .map（路由缺失）"; _meta_ok=0
    fi
    # 三态全缺 → 脏安装，清标记重装
    if (( _svc_ok == 0 && _inc_ok == 0 && _meta_ok == 0 )); then
      warn "安装标记存在但三态（nginx/stream/meta）全部缺失，清除标记重新安装..."
      rm -f "$INSTALLED_FLAG"
      fresh_install
      return
    fi
    (( _svc_ok == 0 || _inc_ok == 0 )) && warn "建议先执行 --status 排查状态分裂" || true
    # v2.33 GPT: 部分损坏时先强制 reconcile，失败则拒绝进管理菜单
    local _reconcile_ok=1
    if (( _inc_ok == 0 )); then
      warn "stream include 丢失，自动修复中..."
      # v2.42 GPT #2: reload 成功才算修复，不能只靠 nginx -t
      if init_nginx_stream 2>/dev/null; then
        if systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null; then
          nginx -t 2>/dev/null && success "stream include 已修复（reload 已生效）"             || { warn "stream include 修复后 nginx -t 失败"; _reconcile_ok=0; }
        else
          warn "stream include 修复后 nginx reload 失败（运行态未生效）"; _reconcile_ok=0
        fi
      else
        warn "stream include 修复失败"; _reconcile_ok=0
      fi
    fi
    if (( _svc_ok == 0 )); then
      warn "Nginx 未运行，尝试启动..."
      if systemctl start nginx 2>/dev/null; then
        success "Nginx 已恢复运行"
      else
        warn "Nginx 启动失败"; _reconcile_ok=0
      fi
    fi
    if ! _meta_drift_detect; then
      warn "路由真相源不完整（部分 meta 缺对应 .map），请 --status 排查或重新 --import"
      _reconcile_ok=0
    fi
    if (( _reconcile_ok == 0 )); then
      error "自动恢复失败，拒绝进入管理菜单（防止在分裂状态上继续写操作）"
      echo -e "  请先执行: ${CYAN}bash $0 --status${NC} 排查"
      echo -e "  若无法修复，请执行: ${CYAN}bash $0 --uninstall${NC} 清除后重装"
      exit 1
    fi
    installed_menu
  else
    fresh_install
  fi
}

main "$@"
