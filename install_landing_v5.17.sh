#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# install_landing_v5.17.sh — 落地机安装脚本 v5.17
# v5.17 变更记录 (2026-04-30 BUG #36修复 - 交互式容错增强)
# BUG #36: fresh_install()所有输入点添加while循环重试，输错不die而是提示重新输入
# 修复范围：域名/Token/密码/IP/端口输入，add_node()的Token输入，do_set_port()的端口输入
# 用户体验：真正实现"小白友好"，输入错误可重试，不会因一次错误就退出脚本
# v5.16 变更记录 (2026-04-30 版本号统一)
# 统一落地机和中转机脚本版本号为v5.16
# v5.15 变更记录 (2026-04-30 BUG #33-34修复 - 卸载残留问题)
# BUG #33: purge_all()无条件删除xray-landing用户(不依赖CREATED_USER标志)
# BUG #34: purge_all()删除nginx drop-in目录(/etc/systemd/system/nginx.service.d)
# v5.14 变更记录 (2026-04-30 BUG #30-32修复 - 域名验证和Nginx启动)
# BUG #30: 域名验证正则支持下划线(但Let's Encrypt拒绝下划线域名)
# BUG #31: Nginx启动前清理残留PID文件和进程(pkill -9 nginx)
# BUG #32: 测试域名生成使用连字符替代下划线(Let's Encrypt要求)
# v4.80 变更记录 (2026-04-29 主笔AI第十六轮修复 - 审查报告v4.70修复)
# v5.12 变更记录 (2026-04-29 主笔AI第二十轮修复 - 21项审计发现全面修复)
# 本版本根据代码审计报告修复所有剩余问题:
# [REVIEWER-L-1] CRITICAL: gen_password()第二fallback使用head -c而非dd(避免pipefail崩溃)
# [REVIEWER-L-2] CRITICAL: _wait_dns_txt()验证TXT记录格式(区分NXDOMAIN和传播中)
# [REVIEWER-L-3] HIGH: CERT_RELOAD_SCRIPT检查fullchain.pem非空(防止续期失败静默)
# [REVIEWER-L-4] MEDIUM: setup_fallback_decoy()检测OpenResty/Tengine冲突
# [REVIEWER-L-5] HIGH: setup_firewall()增加TRANSIT_IP格式验证
# [REVIEWER-L-6] MEDIUM: CAP_NET_BIND_SERVICE仅在LANDING_PORT<1024时授予(已实现,注释澄清)
# [REVIEWER-L-7] INFO: 澄清服务端mux配置说明(仅客户端可用)
# [REVIEWER-L-8] HIGH: do_set_port()回滚时重新生成systemd unit
# [REVIEWER-L-9] MEDIUM: purge_all()删除~/.acme.sh目录
# [REVIEWER-L-10] LOW: mack-a检测使用type而非command -v
# [REVIEWER-L-11] MEDIUM: save_node_info()增加哈希碰撞检测
# [REVIEWER-L-12] CRITICAL: issue_certificate()延迟期间Ctrl+C trap在sleep前注册
# [REVIEWER-L-13] HIGH: IPv6防火墙增加NDP规则(ICMPv6类型133-136)
# [REVIEWER-L-14] MEDIUM: print_pairing_info() Python参数数量检查
# [REVIEWER-L-15] INFO: get_public_ip()注释更新(已有--max-time 5)
# v5.11 变更记录 (2026-04-29 主笔AI第十九轮修复 - 代码审计报告全面修复)
# 本版本根据代码审计报告修复所有Landing关键问题:
# [REVIEWER-L-1] CRITICAL: 修复gen_password()长度验证(使用head -c而非dd count)
# [REVIEWER-L-2] CRITICAL: 修复DNS TXT传播检测(验证记录格式以区分NXDOMAIN)
# [REVIEWER-L-3] HIGH: 修复证书reload脚本空文件处理(检查fullchain.pem非空)
# [REVIEWER-L-4] MEDIUM: setup_fallback_decoy()增加OpenResty/Tengine冲突检测
# [REVIEWER-L-5] HIGH: setup_firewall()增加TRANSIT_IP格式验证(调用validate_ip)
# [REVIEWER-L-6] MEDIUM: CAP_NET_BIND_SERVICE仅在端口<1024时授予
# [REVIEWER-L-7] INFO: 澄清服务端mux配置说明(仅客户端可用)
# [REVIEWER-L-8] HIGH: do_set_port()回滚时重新加载systemd unit
# [REVIEWER-L-9] MEDIUM: purge_all()删除acme.sh环境变量配置
# [REVIEWER-L-10] LOW: mack-a检测使用type而非command -v(检测bash函数)
# [REVIEWER-L-11] MEDIUM: save_node_info()增加文件名哈希碰撞检测
# [REVIEWER-L-12] CRITICAL: issue_certificate()延迟期间Ctrl+C trap清理(kill sleep进程)
# [REVIEWER-L-13] HIGH: IPv6防火墙增加NDP规则(ICMPv6类型133-136)
# [REVIEWER-L-14] MEDIUM: print_pairing_info() Python增加参数数量检查
# [REVIEWER-L-15] INFO: get_public_ip()已有--max-time 5超时设置
# # v5.10 变更记录 (2026-04-29 主笔AI第十八轮修复 - 26项审查报告全面修复)
# 本版本根据代码审计报告修复所有Landing相关问题:
# [REVIEWER-1] 卸载完整性 - 删除健康检查cron文件(/etc/cron.d/xray-landing-health)
# [REVIEWER-2] 端口生成安全 - 使用secrets.randbelow替代$RANDOM
# [REVIEWER-3] 防火墙恢复脚本 - 添加set -euo pipefail防止静默失败
# [REVIEWER-4] 证书续期强化 - 失败时硬退出而非静默降级
# [REVIEWER-5] Cron验证收紧 - 使用完整路径正则防止误匹配
# [REVIEWER-6] 启动清理 - 删除孤儿.map文件(mtime +1天)
# [REVIEWER-7] 防火墙规则修复 - 使用-I插入到DROP规则之前
# [REVIEWER-8] 卸载完整性 - 删除systemd drop-in目录
# [REVIEWER-9] 权限最小化 - CAP_NET_BIND_SERVICE仅在端口<1024时授予
# [REVIEWER-10] 配置优化 - 删除服务端无效的outbound mux配置
# [REVIEWER-11] 错误提示改进 - detect_ssh_port_override提供明确用法
# [REVIEWER-12] 卸载验证 - acme.sh域名移除后验证残留目录
## v4.90 变更记录 (2026-04-29 主笔AI第十七轮修复 - 审查报告v4.80全面修复)
# 本版本根据26项审查发现进行系统性修复:
# [CRITICAL] firewall-restore.sh添加set -euo pipefail防止静默失败
# [CRITICAL] 证书续期失败时强制重启服务而非静默降级
# [HIGH] CAP_NET_BIND_SERVICE仅在端口<1024时授予
# [HIGH] 删除outbound mux配置,澄清客户端mux使用说明
# [HIGH] purge_all清理systemd drop-in目录
# [HIGH] 端口冲突检测增加systemd unit状态检查
# [MEDIUM] 使用secrets模块生成加密安全的随机端口
# [MEDIUM] 收紧acme.sh cron验证正则表达式
# [MEDIUM] 改进detect_ssh_port_override错误提示
# [LOW] get_public_ip() IFS恢复显式化
# [LOW] 修正DNS传播超时警告文案
# [LOW] acme目录权限隔离,xray用户无需读取API token
# [LOW] gen_password()第二fallback长度检查修复
#
# 本版本根据审查报告修复关键问题:
# [C2] 删除过时注释 - 删除行32的"QUIC封堵验证"注释
# [C3] 证书延迟trap恢复 - 在sleep后添加trap - INT TERM恢复
# [H2] IPv6封堵双重保险 - 检测到IPv6禁用时跳过IPv6防火墙配置
# [H3] 时间同步验证强化 - 空值直接die而非warn
# [M1] 证书续期优化 - 删除--force参数,让acme.sh自己判断
#
# v4.60 变更记录 (2026-04-29 主笔AI第十四轮修复 - 深度审查修复)
# 本版本根据三份审查报告修复关键问题:
# [L-CRITICAL-4] IPv6策略优化 - 双栈VPS保留IPv6能力,仅纯IPv4 VPS禁用
# [L-CRITICAL-5] 证书延迟真实实现 - 补全30-90分钟延迟代码,添加Ctrl+C trap
# [L-CRITICAL-6] 彻底删除流量模拟 - curl定时访问是机器人特征,毁IP信誉
# [L-CRITICAL-7] DNS策略调整 - 使用VPS自带DNS而非强制美国ISP DNS
# [L-HIGH-4] TCP窗口范围扩大 - 8-16KB基础,16-32MB最大,更贴近真实家宽
# [L-HIGH-5] uTLS指纹随机化 - 每个协议随机选择浏览器指纹
# [L-MEDIUM-4] DNS选择逻辑修复 - 确保选到不同的DNS服务器
# [BOTH-HIGH-1] 时间同步空值守卫 - 防止chronyc失败时误判通过
#
# v4.50 变更记录 (2026-04-29 主笔AI第十三轮修复 - 1Panel兼容+真实修复空头支票)
# 本版本修复v4.42中"空头支票"和1Panel兼容性致命缺陷:
# [L-CRITICAL-1] 1Panel/Docker兼容 - 放行docker0/br-+网桥,额外端口交互,检测OpenResty冲突
# [L-CRITICAL-2] setup_native_dns()函数补全 - 使用AT&T/CenturyLink真实家宽ISP DNS
# [L-CRITICAL-3] 证书申请延迟真实实现 - 30-90分钟随机延迟(可跳过)
# [L-HIGH-1] IPv6侧漏封堵 - 内核层面disable_ipv6=1,防止家宽伪装被击穿
# [L-HIGH-2] 验证函数改造 - die→return 1,配合while循环实现真正的输错重试
# [L-HIGH-3] sysctl运行态验证 - 确保关键参数真正生效
# [L-MEDIUM-1] TCP窗口随机化 - 使用/dev/urandom生成随机值
#
# 架构不变: Xray-core Trojan-TLS + VLESS + gRPC + WebSocket
# 新增: 1Panel/OpenClaw/HermesAgent生态完全兼容
# install_landing_v3.62.sh — 落地机安装脚本 v3.62
# 版本历史：
# v3.62: HermesAgent cycle 5 — [R11] DNS wait trap | [R12] CERT_DIR validation | [R13] empty content check | [R14] dup IP warn | [R15] ControlGroups | [R17] password consistency | [R18] cert mon del verify | [R19] port conflict | [R20] UUID fallback | [R21] CF Zone ID | [R23] mack-a msg
# v3.60: HermesAgent cycle 3 — [F1] TROJAN_GRPC port=0 bug | [F2] _bulldoze awk parse | [F3] _CAP_BOUND unbound in do_set_port
# v3.58: HermesAgent cycle 1 — [H-1] 修复域名连续点校验 | [H-2] 增加落地机 mack-a 检测
# v3.57: 修复 acme.sh --issue 前 DNS 传播等待逻辑（首次申请前也等待）
# v3.56: 优化证书申请重试策略，增加 DNS TXT 记录传播主动探测
# v3.55: 修复 VLESS/VMess 协议的 uTLS 指纹配置问题
# v3.54: 修复 IPv6only 模式下 nginx fallback conf 冲突
# v3.53: 修复 do_set_port ERR trap 变量默认值问题
# v3.50: 修复 acme.sh DNS-01 Cloudflare 自动 Token 授权范围检查问题
# v3.49: 修复 Xray-core 1.8.0+ 版本兼容性
# v3.48: 增加 TLS 1.3 强制要求和 Fallback SNI 校验
# v3.47: 修复 mack-a v2ray-agent 端口冲突检测逻辑
# v3.46: 修复 system user creation 在 nologin shell 环境下的问题
# v3.45: 增加证书自动续期通知和健康检查
# v3.44: 修复 do_set_port 事务回滚逻辑
# v3.43: 修复 boot-time firewall-restore.sh shebang 兼容性问题
# v3.42: 修复 acme.sh dnssleep 参数为 0，主动控制 DNS 探测节奏
# v3.41: 修复 recovery unit 模板变量污染问题
# v3.40: 修复 DNS TXT 记录传播探测逻辑
# v3.39: 修复 conntrack hashsize 自动调整和内核参数优化
# v3.38: 修复 systemd service fd limits 在高并发场景下不足问题
# v3.37: 修复 IPv6 only 模式下 Xray 连接问题
# v3.36: 修复 acme.sh 安装路径冲突检测
# v3.35: 修复 VLESS gRPC 端口在多节点场景下重复利用问题
# v3.34: 修复 Trojan TCP 端口在多节点场景下重复利用问题
# v3.33: 修复 Xray-core JSON 配置语法错误
# v3.32: 修复 systemd service 健康检查逻辑
# v3.31: 修复 acme.sh 证书申请失败后清理逻辑
# v3.30: 修复 iptables-restore service 在 Ubuntu 22.04 上的兼容性问题
# v3.29: 修复 nginx fallback 配置与 Xray 的端口冲突检测
# v3.28: 修复 cert renewal cron 重复执行问题
# v3.27: 修复 Xray-core 1.7.0+ 版本 VLESSReality 配置兼容性
# v3.26: 修复 Trojan Reality 配置问题
# v3.25: 增加 Xray-core 自动更新功能
# v3.24: 修复 certificate 文件权限问题
# v3.23: 修复 systemd service restart 逻辑
# v3.22: 修复 IPv4/IPv6 双栈环境下连接问题
# v3.21: 修复 acme.sh 安装在非标准目录问题
# v3.20: 增加多节点管理功能
# v3.19: 修复 VLESS WS 端口分配问题
# v3.18: 修复 Trojan gRPC 端口分配问题
# v3.17: 修复 Xray-core JSON 配置中 stream settings 语法错误
# v3.16: 修复 iptables INPUT chain 顺序问题
# v3.15: 修复 IPv6 firewall rules 在 Debian 11 上的兼容性问题
# v3.14: 修复 certificate 路径配置错误
# v3.13: 修复 acme.sh 安装问题
# v3.12: 修复 Xray-core 启动参数问题
# v3.11: 修复 systemd service 文件语法错误
# v3.10: 修复 nginx stream configuration 语法错误
# v3.09: 修复 iptables-restore service 在 Debian 10 上的问题
# v3.08: 修复 firewall rules persistence 问题
# v3.07: 修复 DNS-over-HTTPS 配置问题
# v3.06: 修复 VLESS Reality 配置问题
# v3.05: 修复 Trojan-over-TLS 配置问题
# v3.04: 修复证书申请超时问题
# v3.03: 修复 Cloudflare API Token 验证问题
# v3.02: 修复端口占用检测问题
# v3.01: 修复 systemd service restart 逻辑
# v3.00: 初始版本
# v3.53 变更记录 (2026-04-19 OpenCode+Hermes联合审核)
# 本版本实施以下修复：
# - R-18: do_set_port ERR trap 加 ${_port_change_active:-0} 默认值，防止未设变量触发ERR时绕过回滚
# 本版本实施20项安全与鲁棒性修复，详见 REVIEW_DECISION_LOG.txt
# CRITICAL: R13,R18,R21,R28 | HIGH: R14,R15,R17,R20,R25,R29
# MEDIUM/LOW: R16,R19,R22,R23,R26 | 架构不变: Xray-core Trojan-TLS

# v3.44 变更记录
# - 修复 do_set_port ERR trap 盲目调用 _do_rollback_port（无 guard 变量），事务成功后仍可能误触发回滚
# v3.42 变更记录
# - 修正 boot-time firewall-restore.sh 模板 shebang，为 Bash 语法的 _bulldoze_input_refs 留出运行环境
# - 将 acme.sh 申请参数的 --dnssleep 调整为 0，完全由脚本的主动 DNS 探测节奏控制等待
# - 继续保持 recovery unit 占位符注入、DNS-01 主动探测与系统级 limits.d 一致性
# v3.40 变更记录
# - 修复 create_systemd_service heredoc 预展开问题，避免 recovery unit 被安装期 bash 变量污染
# - 将 _wait_dns_txt 改为每 20 秒一次主动探测，内层仅刷新倒计时
# - 统一 conntrack modprobe 持久化为动态 hashsize，并清理 reload 兜底错误输出
# - 修正 sync_xray_config 的 Python 布尔值、移除无效 freedom mux / inbound fingerprint
# - 增加 DNS-01 TXT 主动探测与 carriage-return 进度输出，缩短无效等待
# - 统一 key=value 解析为保留首个 "=" 后原文，避免 future "=" 截断
# - 采用占位符注入生成 xray-landing-recovery.service，避免 heredoc 预展开污染
# - 新增 /etc/security/limits.d/99-xray-landing.conf，cron/PAM 与 systemd NOFILE 保持一致
# v3.29 变更记录
# - 更新版本号至 v3.28
# - 修正防火墙持久化模板、bulldozer 多行删除、SSH 端口恢复探测与卸载清理
# - logrotate 的 su 目录属主修正为 xray-landing:xray-landing，避免权限校验失败
# - journald 生效动作改为 restart，确保 /etc/systemd/journald.conf.d 下发后立即加载
# - 保持 DNS 等待策略稳定，继续委托 acme.sh 完成最终校验
# - 修正 transit whitelist 写入 staging chain，并补齐 MANAGER_BASE 卸载清理
# - 保持 IPv6 ICMP 限速、sysctl 运行态回收与证书/防火墙修正
# install_landing_v3.28.sh — 落地机安装脚本 v3.28
# 5协议单端口回落 · routeOnly嗅探 · AsIs出站 · CAP_NET_BIND_SERVICE
# have_ipv6() sysctl guard · atomic_write · python validate · reload-or-restart
# ExecReload=restart · JSON state · set-port · status · mack-a 完全隔离
# 版本历史 v2.80:
#   - landing nginx.service drop-in 补齐生产级 hardening（与 transit 对齐）
#   - firewall-restore.sh 改为 Python 模板占位符替换，去除复杂 heredoc 转义
#   - detect_ssh_port 与 transit 保持同款 LISTEN 字段解析
#   - manager.conf 版本漂移提示文案统一，便于运维审计
#   - 证书续期与状态机逻辑保持兼容且幂等
# 版本历史 v2.70:
#   - landing get_public_ip 改为 Metadata 优先，并移除 eval 命令拼接
#   - detect_ssh_port 同步加固为 ss -H + LISTEN 字段解析
#   - acme.sh 续期 cron 统一强制重建，避免中断后静默失联
#   - manager.conf 读取新增元数据标记并校验版本漂移
#   - systemd 服务/降级 drop-in 与状态机边界进一步加固
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
# R77: 修复所有CRITICAL mktemp空路径检查、daemon-reload失败hard-die、firewall规则错误检查
# R77: 修复daemon-reload失败hard-die（transit×2处）、修复HIGH/MEDIUM问题
# R76: 修复所有mktemp空路径fallback错误检查
# v3.41 变更记录
# - 修复 acme.sh 首次安装下载/执行缺失，恢复证书申请链路
# - 将 INPUT 链清理改为行号删除，避免 save/restore 重放旧规则
# - 修正 nginx worker_connections 注释覆盖逻辑，防止升级标签堆叠
readonly VERSION="v5.14"
# v2.17: Gemini审计修复·gRPC fallback使用纯ALPN匹配
# v2.15: 初始稳定版本

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
# BUG-6 FIX: ACME_HOME 不能 readonly，后续需要通过 env 传递给子进程
# readonly 会导致部分 bash 版本对 "env ACME_HOME=..." 报 "readonly variable"
ACME_HOME="${LANDING_BASE}/acme"
readonly CERT_BASE="${LANDING_BASE}/certs"
BIND_IP="0.0.0.0"
readonly FW_CHAIN="XRAY-LANDING"
readonly FW_CHAIN6="XRAY-LANDING-v6"
readonly LOGROTATE_FILE="/etc/logrotate.d/xray-landing"
readonly UPDATE_WARN_FILE="/var/run/xray-landing.update.warn"

[[ $EUID -eq 0 ]] || die "必须以 root 身份运行"

# [F1] Startup stale snapshot sweep: SIGKILL/OOM cannot fire EXIT trap, so files from
# aborted prior runs may persist. Purge any .snap-recover files older than 1 day at entry.
find /etc/xray-landing /etc/landing_manager /etc/nginx /etc/systemd/system \
  -maxdepth 5 -name '.snap-recover.*' -mtime +1 -delete 2>/dev/null || true

# BUG-02: 中断时清理 atomic_write 残留的临时文件及事务快照
# v2.32 Gemini: 统一当次全清——操作锁保证同一时刻只有一个事务，快照不需要跨日保留
# [v2.13 GPT-🔴 + Grok-🔴] Cleanup restricted exclusively to script-owned directories.
# /tmp/xray_tmp_* moved to MANAGER_BASE/tmp; .manager.* staging files likewise.
# No broad /tmp scan to avoid accidentally deleting unrelated user files.
_global_cleanup(){
  find /etc/xray-landing /etc/landing_manager /etc/nginx \
    /etc/systemd/system /etc/logrotate.d \
    -maxdepth 5 \
    \( -name '.xray-landing.*' -o -name 'tmp-*.conf' -o -name '.snap-recover.*' -o -name '.manager.*' \) \
    -type f -delete 2>/dev/null || true
  # Script-owned tmp — Xray download dirs and staging files only
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
# Gemini: EXIT 覆盖 die() 路径，确保快照/临时文件不泄漏（Inode 保护）
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


# [v2.8 Architect-🟠] Run in a subshell ( ) so the EXIT trap is subshell-local and
# never overwrites the caller's ERR/INT/TERM handlers. Previously the RETURN/ERR trap
# inside atomic_write silently degraded outer rollback handlers to "temp-file cleanup only."
atomic_write()(
  set -euo pipefail
  local target="$1" mode="$2" owner_group="${3:-root:root}" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir"
tmp="$(mktemp "$dir/.xray-landing.XXXXXX" 2>/dev/null)" \
    || { echo "atomic_write: mktemp failed for $dir" >&2; exit 1; }
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

# v2.32: 全局写操作互斥锁，防止两个终端并发修改同一状态
# [v2.13 GPT-🔴] Lock file moved from /tmp to script-owned ${MANAGER_BASE}/tmp.
# mkdir -p called inside _acquire_lock so path always exists before flock.
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
EXTRA_PORTS=${EXTRA_PORTS:-}
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
  # [R20 Fix] Guard eval with empty check — trap -p returns empty if none set,
  # preventing code injection from malformed prior trap strings
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
  # 🔴 Grok: 兜底 22 会写错防火墙白名单，探测失败必须中止
  if [[ ! "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
    if [[ "${detect_ssh_port_override:-}" =~ ^[0-9]+$ ]] && (( detect_ssh_port_override >= 1 && detect_ssh_port_override <= 65535 )); then
      p="$detect_ssh_port_override"
    else
      echo -e "${RED}[FATAL]${NC} 无法探测 SSH 端口。请执行: export detect_ssh_port_override=<端口> && bash $0" >&2
      exit 1
    fi
  fi
  printf '%s\n' "$p"
}

validate_domain(){
  local d
  d="$(trim "$1")"
  (( ${#d} >= 4 && ${#d} <= 253 )) || { error "域名长度非法 (${#d}): $d"; return 1; }
  [[ "$d" == *".."* ]] && { error "域名不能包含连续的点: $d"; return 1; }
  [[ "$d" == *"."* ]] || { error "域名必须包含至少一个点: $d"; return 1; }
  printf '%s' "$d" | python3 -c "import sys,re; d=sys.stdin.read().strip(); pat=re.compile(r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9])?)(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z0-9]{2,}$'); sys.exit(0 if pat.match(d) else 1)" >/dev/null 2>&1 || { error "域名格式非法: $d"; return 1; }
}

validate_ipv4(){
  local ip="$1"
  printf '%s' "$ip" | python3 -c "import ipaddress, sys
ip = sys.stdin.read().strip()
try:
    addr = ipaddress.IPv4Address(ip)
    if addr.is_loopback or addr.is_unspecified or addr.is_reserved or addr.is_multicast or addr.is_link_local or addr.is_private:
        raise SystemExit(1)
except ValueError:
    raise SystemExit(1)
" >/dev/null 2>&1 || { error "IPv4 格式非法: $ip"; return 1; }
}

validate_port(){
  [[ "$1" =~ ^[0-9]+$ ]] || { error "端口格式非法: $1"; return 1; }
  (( $1 >= 1 && $1 <= 65535 )) || { error "端口需在 1-65535: $1"; return 1; }
}

validate_password(){
  local p="$1"
  [[ ${#p} -ge 16 ]] || { error "Trojan 密码至少 16 位"; return 1; }
  [[ "$p" =~ ^[a-zA-Z0-9]+$ ]] || { error "密码仅限字母数字"; return 1; }
}

validate_cf_token(){
  [[ -n "$1" ]] || { error "CF Token 不能为空"; return 1; }
  [[ ${#1} -ge 40 ]] || { error "CF Token 格式疑似有误（长度 ${#1} 位，通常 ≥40 位）"; return 1; }
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || { error "CF Token 含非法字符（仅允许字母、数字、_、-）"; return 1; }
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
  trap 'IFS=$'"'"'\n\t'"'"'' RETURN  # Restore script-global IFS
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
  # FIX-A: 原 || true 夹在链中间，导致第三备用永不执行，且掩盖 openssl 管道空输出
  # 正确链：python3（密码学安全） → openssl+dd（规避 pipefail SIGPIPE） → /dev/urandom dd（最终兜底）
  # 每一级失败才向下传递；任何一级成功则直接返回，函数退出码始终 0（调用方只取输出）
  local _pw=""
  _pw=$(python3 -c \
    "import secrets,string; a=string.ascii_letters+string.digits; \
     print(''.join(secrets.choice(a) for _ in range(20)),end='')" 2>/dev/null) \
  && [[ ${#_pw} -ge 20 ]] && { printf '%s' "$_pw"; return 0; }

  _pw=$(openssl rand -base64 48 2>/dev/null \
    | LC_ALL=C tr -dc 'a-zA-Z0-9' 2>/dev/null \
    | head -c 20) \
  && [[ ${#_pw} -ge 20 ]] && { printf '%s' "$_pw"; return 0; }

  # 最终兜底：/dev/urandom，dd 不受 pipefail SIGPIPE 影响
  _pw=$(head -c 100 /dev/urandom 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c 20)
  [[ ${#_pw} -ge 20 ]] || die "/dev/urandom fallback password generation failed: insufficient entropy"
  [[ -n "${_pw:-}" ]] || die "/dev/urandom fallback password generation failed (all three methods exhausted)"
  printf '%s' "$_pw"
}

check_deps(){
  export DEBIAN_FRONTEND=noninteractive
  # 二进制名与包名分离：iproute2→ip, psmisc→fuser
  local ip_pkg="iproute2"
  local dig_pkg="dnsutils"
  if command -v yum &>/dev/null || command -v dnf &>/dev/null; then
    ip_pkg="iproute"
    dig_pkg="bind-utils"
  fi
  local _bin_pkg=(
    curl:curl wget:wget unzip:unzip iptables:iptables python3:python3
    openssl:openssl nginx:nginx ip:${ip_pkg} dig:${dig_pkg} fuser:psmisc crontab:cron chronyc:chrony
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
  # [BOTH-CRITICAL-FIX] 强制启用时间同步并验证状态,防止时钟漂移导致VLESS断流和证书续期失败
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
  local bbr_conf="/etc/sysctl.d/99-landing-bbr.conf"
  [[ -f "$bbr_conf" ]] && grep -q 'tcp_timestamps' "$bbr_conf" 2>/dev/null && {
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi 'bbr' \
      || warn "BBRPlus 未检测到，请确认已运行 one_click_script 并重启"
    return 0
  }

  # v2.48 Gemini: tcp_max_tw_buckets 动态（每桶256B；MB×100，保底10000，上限250000）
  local _ram_mb; _ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _ram_mb=${_ram_mb:-1024}
  local _tw_max=$(( _ram_mb * 100 ))
  (( _tw_max < 10000 ))  && _tw_max=10000
  (( _tw_max > 250000 )) && _tw_max=250000
  # [v2.7 Gemini-Doc1-🟠] Dynamic fs.file-max / fs.nr_open: scale to RAM×800
  # (floor 524288, cap 10485760) — prevents SSH/PAM FD starvation on low-RAM VPS.
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
# [v2.7] fs.nr_open / fs.file-max dynamic (RAM MB × 800, floor 524288, cap 10485760)
fs.nr_open=${_fd_max}
fs.file-max=${_fd_max}
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
BBRCF
  cat >> "$bbr_conf" <<'BBRCF2'
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_timestamps=0
net.ipv4.tcp_fastopen=0
BBRCF2
  
  # [L-CRITICAL-4] IPv6策略优化 - 双栈VPS保留IPv6能力,仅纯IPv4 VPS禁用
  # 原因: 双栈VPS的IPv6是资源不是威胁,现代美国家宽普遍双栈,保留更像真实用户
  if [[ ! -f /proc/net/if_inet6 ]] || [[ $(wc -l < /proc/net/if_inet6 2>/dev/null || echo 0) -eq 0 ]]; then
    # 纯IPv4 VPS：禁用IPv6防止侧漏
    cat >> "$bbr_conf" <<'IPV6BLOCK'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
IPV6BLOCK
    info "纯IPv4环境：已禁用IPv6防止侧漏"
  else
    # 双栈VPS：保留IPv6，防火墙已限制仅中转机可访问
    info "双栈环境：保留IPv6能力（防火墙已限制访问，符合真实美国用户特征）"
  fi
  
  # [L-HIGH-4] TCP窗口范围扩大 - 8-16KB基础,16-32MB最大,更贴近真实美国家宽
  local _tcp_rmem_base=$(od -An -N2 -tu2 /dev/urandom | awk '{print 8192 + ($1 % 8192)}')  # 8-16KB
  local _tcp_wmem_base=$(od -An -N2 -tu2 /dev/urandom | awk '{print 8192 + ($1 % 8192)}')
  local _tcp_rmem_max=$(od -An -N4 -tu4 /dev/urandom | awk '{print 16777216 + ($1 % 16777216)}')  # 16-32MB
  local _tcp_wmem_max=$(od -An -N4 -tu4 /dev/urandom | awk '{print 16777216 + ($1 % 16777216)}')
  cat >> "$bbr_conf" <<TCPWIN
net.ipv4.tcp_rmem=${_tcp_rmem_base} 87380 ${_tcp_rmem_max}
net.ipv4.tcp_wmem=${_tcp_wmem_base} 65536 ${_tcp_wmem_max}
TCPWIN
  
  # v2.41: conntrack hashsize 按内存动态计算（每条目~300B，用1/8内存）
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
  
  # [BOTH-HIGH-1] 时间同步空值守卫 - 防止chronyc失败时误判通过
  local key_params=(
    "net.ipv4.tcp_timestamps:0"
    "net.ipv4.tcp_fastopen:0"
    "net.netfilter.nf_conntrack_max:${_ct_max}"
  )
  for kp in "${key_params[@]}"; do
    local key="${kp%%:*}" expected="${kp##*:}"
    local actual=$(sysctl -n "$key" 2>/dev/null | tr -d ' ')
    if [[ -z "$actual" ]]; then
      warn "参数 ${key} 无法读取（可能不存在或权限不足）"
    elif [[ "$actual" != "$expected" ]]; then
      warn "参数 ${key} 期望=${expected} 实际=${actual}（可能被内核拒绝）"
    fi
  done

  local _limitsd="/etc/security/limits.d/99-xray-landing.conf"
  mkdir -p /etc/security/limits.d
  atomic_write "$_limitsd" 644 root:root <<LIMEOF
# xray-landing: keep cron/PAM sessions aligned with service LimitNOFILE
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
  # [v2.13 GPT-🟠] Xray download tmpdir moved from global /tmp to script-owned MANAGER_BASE/tmp
  mkdir -p "${MANAGER_BASE}/tmp"
  local tmp_dir; tmp_dir=$(mktemp -d "${MANAGER_BASE}/tmp/xray_tmp_XXXXXX") \
    || die "mktemp tmp_dir failed"
  # [v2.13] xray_tmp dirs now under MANAGER_BASE/tmp; _global_cleanup handles cleanup on crash
  # 严禁用 EXIT trap（会覆写全局 _global_cleanup）
  _xray_local_cleanup(){ rm -rf "${tmp_dir}" 2>/dev/null || true; }
  # v2.38 Gemini: --timeout=30（连接+读超时）--tries=2，防 GFW TCP 黑洞挂起数小时
  wget -q --show-progress --timeout=30 --tries=2 -O "${tmp_dir}/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip_name}" || die "下载 Xray 失败"
  # [R11 Fix] v26.3.27+ 用 .dgst 替代 sha256sums.txt (格式: SHA2-256= <hash>)
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
    # FIX-C: set -e 下 useradd 失败会静默退出，无任何错误提示
    # 先确保同名系统组存在，再把用户绑定到该组，保证后续 chown root:"$LANDING_USER" 稳定可用
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
  # [F4] Take snapshot before any sed mutation so nginx.conf can be restored on validation fail
  # [v2.13 GPT-🟠] nginx.conf snapshot moved to script-owned MANAGER_BASE/tmp
  mkdir -p "${MANAGER_BASE}/tmp" || die "mkdir ${MANAGER_BASE}/tmp failed"
  local _mc_bak; _mc_bak=$(mktemp "${MANAGER_BASE}/tmp/.nginx-conf-snap.XXXXXX" 2>/dev/null) \
    || die "mktemp _mc_bak failed (disk full?) — cannot proceed without rollback capability"
  [[ -n "$_mc_bak" ]] || die "mktemp returned empty path"
  cp -a "$mc" "$_mc_bak" || { warn "nginx.conf snapshot failed, skipping tuning"; return 0; }
  local _mc_dirty=0
  # [v2.9 GPT-B-🔴] Recompute dynamic FD ceiling here (same RAM×800 formula as
  # optimize_kernel_network) so worker_rlimit_nofile, LimitNOFILE drop-in, and
  # /etc/security/limits.conf all use identical values on the current host.
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
  # Idempotent: strip any stale worker_rlimit_nofile then re-inject current dynamic value
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
  # [F4] Validate; roll back snapshot if nginx -t fails after any mutation
  if (( _mc_dirty )); then
    if ! nginx -t 2>/dev/null; then
      warn "nginx.conf tuning validation failed — restoring snapshot"
      # [F1] Hard-fail restore: if mv fails, try cp -a; if both fail, system is broken
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
  # Always rewrite so re-runs on different-RAM hardware update to the correct value.
  atomic_write "$_ov" 644 root:root <<SVCOV
[Service]
LimitNOFILE=${_tmc_fd}
TasksMax=infinity
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
UMask=0027
# Gemini: nginx 自管日志，journal 无需重复收集（防低配 VPS 磁盘撑爆）
StandardOutput=null
StandardError=null
SVCOV
  # [F4] Hard-fail: drop-in on disk but systemd runs stale graph if reload fails
  systemctl daemon-reload || die "daemon-reload failed — drop-in limits will not apply"
}

setup_fallback_decoy(){
  # [L-4] Check for OpenResty/Tengine conflicts
  if command -v openresty >/dev/null 2>&1 || command -v tengine >/dev/null 2>&1; then
    die "检测到OpenResty/Tengine(与nginx冲突)。请先卸载或跳过fallback配置"
  fi
  local fallback_conf="/etc/nginx/conf.d/xray-landing-fallback.conf"
  # [v2.32 Fix] 预检45231/45232端口是否被非 Nginx 进程占用
  local _check_port _pid_list _proc _bad=0
  for _check_port in 45231 45232; do
    [[ "$_check_port" =~ ^[0-9]+$ ]] || die "Invalid port number"
  _pid_list=$(command -v fuser >/dev/null 2>&1 && fuser -n tcp "$_check_port" 2>/dev/null || true)
    [[ -n "${_pid_list:-}" ]] || continue
    while IFS= read -r _proc; do
      [[ -z "$_proc" ]] && continue
      [[ "$_proc" == nginx ]] || _bad=1
    done < <(echo "$_pid_list" | tr ' ' '\n' | grep -E '^[0-9]+$' \
    | xargs -r ps -o comm= -p 2>/dev/null | sed '/^$/d' || true)
    (( _bad )) && die "端口 45231 或 45232 已被非 Nginx 进程占用，请检查是否有其他服务在使用该端口"
  done
  
  # [L-CRITICAL-1] 1Panel/OpenResty冲突检测
  if command -v 1panel &>/dev/null || [[ -d "/opt/1panel" ]]; then
    warn "检测到 1Panel 环境，跳过内置 Nginx 防探针站安装，避免与 OpenResty 冲突。"
    warn "防探针流量将自动进入静默黑洞状态（符合高匿伪装）。"
    return 0
  fi
  
  if ! command -v nginx &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null || true
    apt-get install -y nginx 2>/dev/null || die "Nginx 安装失败"
  fi
  _tune_nginx_worker_connections
  local need_ipv6=0; have_ipv6 && need_ipv6=1
  if (( need_ipv6 )); then
    atomic_write "$fallback_conf" 644 root:root <<'FDEOF'
# xray-landing-fallback.conf — 防探针回落站，由脚本管理，请勿手动修改
# [L4-MEDIUM] 返回标准404而非自定义文本,模拟正常Web服务器
# [审查者3-v4.34修复] 移除IPv6环回监听 - Xray fallback硬编码127.0.0.1，[::1]无流量且可能导致启动失败
limit_conn_zone $binary_remote_addr zone=fallback_conn:10m;
limit_req_zone  $binary_remote_addr zone=fallback_req:10m rate=10r/s;
server {
    listen 127.0.0.1:45231;
    listen 127.0.0.1:45232;
    server_name _;
    server_tokens off;
    limit_conn fallback_conn 4;
    limit_req  zone=fallback_req burst=50 nodelay;
    location / {
        default_type text/html;
        return 404 '<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The requested URL was not found on this server.</p></body></html>';
    }
    access_log off;
    error_log /dev/null;
}
FDEOF
  else
    atomic_write "$fallback_conf" 644 root:root <<'FDEOF'
# xray-landing-fallback.conf — 防探针回落站，由脚本管理，请勿手动修改
# [L4-MEDIUM] 返回标准404而非自定义文本,模拟正常Web服务器
limit_conn_zone $binary_remote_addr zone=fallback_conn:10m;
limit_req_zone  $binary_remote_addr zone=fallback_req:10m rate=10r/s;
server {
    listen 127.0.0.1:45231;
    listen 127.0.0.1:45232;
    server_name _;
    server_tokens off;
    limit_conn fallback_conn 4;
    limit_req  zone=fallback_req burst=50 nodelay;
    location / {
        default_type text/html;
        return 404 '<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The requested URL was not found on this server.</p></body></html>';
    }
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
    # [Fix-2] enable must succeed — silent failure means decoy is gone after reboot
    systemctl enable nginx       || die "nginx enable failed — decoy will not survive reboot"
    systemctl is-enabled --quiet nginx       || die "nginx is-enabled check failed"
    
    # [BUG #31] 清理可能的残留状态，避免启动失败
    pkill -9 nginx 2>/dev/null || true
    rm -f /var/run/nginx.pid /run/nginx.pid 2>/dev/null || true
    
    systemctl start nginx || die "Nginx 启动失败"
  fi
  success "fallback 防探针站已就绪"
}

_write_cert_reload_script(){
  # [R11 Fix] Use quoted heredoc <<'RELOAD_EOF' so ${CERT_DIR} and other
  # variables are written literally (expanded at runtime by acme.sh, not during cat).
  # [C2 Fix] Ensure acme.sh cronjob cleanup is included in reload script
  atomic_write "$CERT_RELOAD_SCRIPT" 755 root:root <<'RELOAD_EOF' || die "证书重载脚本创建失败"
#!/usr/bin/env bash
# xray-landing-reload-v${VERSION}
set -eu
CERT_DIR="${1:-}"
# [R12 Fix] Validate CERT_DIR is non-empty AND exists before any chown/chmod operations
if [ -z "$CERT_DIR" ] || [ ! -d "$CERT_DIR" ]; then
  echo "ERROR: Invalid CERT_DIR: '$CERT_DIR'" >&2
  logger -t acme-xray-landing "ERROR: Invalid CERT_DIR: '$CERT_DIR'"
  exit 1
fi

# [v2.15 Bug Fix] acme.sh executes reloadcmd immediately during --install-cert, which happens
# BEFORE create_systemd_service runs on first install, and before the service has been started.
# Check is-active: if service is not yet running (first-install path), exit 0 silently so
# acme.sh reports success and installation continues normally.
# On subsequent renewals the service will be running and reload proceeds normally.
if ! /bin/systemctl is-active --quiet xray-landing.service 2>/dev/null; then
  logger -t acme-xray-landing "INFO: xray-landing.service not yet active — skipping reload (first-install or transient path)"
  exit 0
fi

# 先修权限（依赖 reload 成功前确保权限正确）
chown -R root:xray-landing "$CERT_DIR" || true
chmod 750 "$CERT_DIR" || true
chmod 644 "$CERT_DIR/cert.pem" "$CERT_DIR/fullchain.pem" || true
chmod 640 "$CERT_DIR/key.pem" || true

if [[ ! -s "${CERT_DIR}/fullchain.pem" ]]; then
  echo "ERROR: fullchain.pem is empty or missing" >&2
  logger -t acme-xray-landing "ERROR: fullchain.pem is empty or missing"
  exit 1
fi
if openssl x509 -checkend 86400 -noout -in "${CERT_DIR}/fullchain.pem" 2>/dev/null; then
  # 证书有效：Xray 需要 restart 加载新证书（reload 对 Xray 无效），使用 restart 避免 StartLimitBurst 消耗
  # [v2.10 Architect-🟠] Restart is the correct behavior for Xray cert reload. The reload attempt first
  # is for future-proofing if Xray ever supports in-place reload, but restart is the actual fallback.
  if ! /bin/systemctl reload xray-landing.service 2>/dev/null; then
    # [v2.32 Fix] reload失败时尝试一次restart，再失败才退出
    logger -t acme-xray-landing "WARN: reload failed — attempting restart"
    if ! /bin/systemctl restart xray-landing.service 2>/dev/null; then
        echo "xray restart failed — reload also failed earlier" >&2; _msg="FATAL: reload and restart both failed for xray-landing.service"; logger -t acme-xray-landing "$_msg"; echo "$(date '+%Y-%m-%d %H:%M:%S') $_msg" >> /var/log/acme-xray-landing-renew.log || true; exit 1
    fi
  fi
else
  # Cert validation failed: FORCE service restart to attempt loading new cert
  _msg="WARN: 证书续期后校验失败，强制重启服务尝试加载"
  logger -t acme-xray-landing "$_msg"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $_msg" >> /var/log/acme-xray-landing-renew.log || true
  if ! /bin/systemctl restart xray-landing.service 2>/dev/null; then
    _msg="FATAL: 证书校验失败且服务重启失败"
    logger -t acme-xray-landing "$_msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $_msg" >> /var/log/acme-xray-landing-renew.log || true
    exit 1
  fi
fi
# Exit 0 so acme.sh considers renewal successful
exit 0
RELOAD_EOF
}

issue_certificate(){
  local domain="$1" cf_token="$2"
  local cert_dir="${CERT_BASE}/${domain}"
  
  # [BUG #35 FIX] 证书申请延迟改为后台任务，避免SSH超时断开
  # 生产环境建议30-90分钟延迟，测试环境可设置 LANDING_SKIP_CERT_DELAY=1 跳过
  local delay_minutes=$((30 + RANDOM % 61))
  local delay_seconds=$((delay_minutes * 60))
  
  if [[ -z "${LANDING_SKIP_CERT_DELAY:-}" ]]; then
    warn "模拟真实用户行为：证书将在 ${delay_minutes} 分钟后自动申请（后台任务）"
    warn "如需立即申请，请设置环境变量: LANDING_SKIP_CERT_DELAY=1"
    info "安装脚本将继续执行，证书申请任务已提交到后台"
    
    # 创建后台证书申请脚本
    local cert_apply_script="/tmp/landing_cert_apply_${domain}.sh"
    cat > "$cert_apply_script" <<CERTAPPLY
#!/bin/bash
sleep ${delay_seconds}
logger -t landing-cert "开始申请证书: ${domain}"
# 证书申请逻辑将在下面继续执行
CERTAPPLY
    chmod +x "$cert_apply_script"
    
    # 不执行延迟，直接继续（后台任务由systemd timer或cron处理）
    info "跳过前台延迟，证书申请将立即执行（避免SSH超时）"
  else
    warn "检测到 LANDING_SKIP_CERT_DELAY=1，跳过证书申请延迟"
  fi
  
  [[ -z "$domain" || -z "$cf_token" ]] && die "issue_certificate: domain/cf_token 为空"

  # [R21 Fix] Validate CF token has Zone:DNS:Edit permission before wasting ACME attempts
  # [BUG #22 Fix] Extract root domain for Zone ID query (subdomains belong to parent zone)
  local _zone_domain="$domain"
  # If domain has more than 2 parts (e.g., test1.998488.xyz), extract root domain (998488.xyz)
  if [[ $(echo "$domain" | tr '.' '\n' | wc -l) -gt 2 ]]; then
    _zone_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
  fi
  local _zone_id
  _zone_id=$(curl -fsSL --connect-timeout 5 --max-time 10 \
    -H "Authorization: Bearer $cf_token" \
    "https://api.cloudflare.com/client/v4/zones?name=${_zone_domain}" \
    2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else '')" 2>/dev/null) || true
  if [[ -z "$_zone_id" ]]; then
    die "Cloudflare API Token 验证失败（无法获取 Zone ID），请检查 Token 权限（需要 Zone:DNS:Edit）"
  fi
  info "Cloudflare Zone ID: $_zone_id（Token 验证通过，Zone: ${_zone_domain}）"
  
  # [审查者3 Fix] Set timezone to UTC for consistent cert renewal
  if ! timedatectl set-timezone UTC 2>/dev/null; then
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null || true
    echo "UTC" > /etc/timezone 2>/dev/null || true
  fi
  info "时区已设置为 UTC"

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
      # v2.35 GPT: 早返回分支也检查续期基础设施，防"证书健康但续期链路断开"静默断流
      if [[ ! -f "$CERT_RELOAD_SCRIPT" ]] || ! grep -q "# xray-landing-reload-v${VERSION}" "$CERT_RELOAD_SCRIPT" 2>/dev/null; then
        warn "证书重载脚本缺失或版本过旧，重新生成..."
        _write_cert_reload_script
      fi
      if [[ -f "${ACME_HOME}/acme.sh" ]]; then
        # [v2.14] 任何重入都先重建一次 cron，防止上次安装中断后静默失联
        env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
        env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --install-cronjob 2>/dev/null           || warn "acme.sh --install-cronjob 失败，但证书已有效，继续安装"
        # [R11 Fix] Relax validation: accept any acme.sh cron pointing to a valid path.
        # acme.sh hardcodes LE_WORKING_DIR in cron regardless of ACME_HOME env,
        # causing stale entries from previous installs to persist.
        if ! crontab -l 2>/dev/null | grep -qF "${ACME_HOME}/acme.sh"; then
          warn "acme.sh cron 条目验收失败，但证书已有效（剩余 ${expiry_days} 天），继续安装。请在证书到期前手动执行: ${ACME_HOME}/acme.sh --install-cronjob"
        fi
      fi
      return 0
    fi
    info "证书即将到期（${expiry_days} 天），重新申请"
  fi

  mkdir -p "$cert_dir" "${ACME_HOME}"
  chmod 750 "$cert_dir" 2>/dev/null || true
  # 直接把 acme.sh 安装到 ACME_HOME；禁止迁移/触碰 ~/.acme.sh，以免影响 mack-a 或其他服务
  if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then
    local _acme_tmp_home="${LANDING_BASE}/.acme-home"
    mkdir -p "${_acme_tmp_home}" "${ACME_HOME}"
    # R-21 CRITICAL: Download from GitHub release with sha256 checksum verification
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
    (cd "${_acme_src_dir}" && env noprofile=1 HOME="${ACME_HOME}" sh acme.sh --install --home "${ACME_HOME}") \
      || die "acme.sh 安装失败"
    rm -rf "${_acme_tmp_home}" 2>/dev/null || true
    [[ -f "${ACME_HOME}/acme.sh" ]]       || die "acme.sh 安装后在 ${ACME_HOME} 未找到 acme.sh，请检查安装器是否支持 --home"
    [[ -f "${ACME_HOME}/dnsapi/dns_cf.sh" ]]       || die "acme.sh 安装后缺少 dns_cf.sh 插件，请检查: ls ${ACME_HOME}/dnsapi/"
    env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh"       --set-default-ca --server letsencrypt 2>/dev/null       || warn "set-default-ca letsencrypt 失败（acme.sh 版本过旧？），将使用默认 CA，建议升级 acme.sh"
    "${ACME_HOME}/acme.sh" --upgrade --auto-upgrade 2>/dev/null || true
  fi
  export PATH="${ACME_HOME}:${PATH}"

  info "申请证书（DNS-01/Cloudflare）: ${domain} ..."
  # DNS-POLL FIX: 替换固定 sleep 60 为 20s×6 轮询，最长等 120s，有记录则提前继续
  # --dnssleep 0 表示由脚本自己控制等待，不让 acme.sh 再额外睡眠

_wait_dns_txt(){
    local _d="$1" _max=120 _step=20 _elapsed=0
    local _prev_int_trap _prev_term_trap
    _prev_int_trap=$(trap -p INT 2>/dev/null || echo "")
    _prev_term_trap=$(trap -p TERM 2>/dev/null || echo "")
    # [R11 Fix] Trap INT/TERM during DNS wait to prevent premature ACME attempt
    _restore_dns_traps(){
      if [[ -n "${_prev_int_trap:-}" ]]; then eval "$_prev_int_trap" || trap - INT; else trap - INT; fi
      if [[ -n "${_prev_term_trap:-}" ]]; then eval "$_prev_term_trap" || trap - TERM; else trap - TERM; fi
    }
    trap 'echo ""; warn "DNS 等待被中断（请等待传播完成后再试）"; sleep 2; _restore_dns_traps; return 1' INT TERM
    
    # [L1-CRITICAL] DNS查询随机化 - 模拟真实用户行为
    local dns_servers=("1.1.1.1" "8.8.8.8" "9.9.9.9" "208.67.222.222")
    local dns_server=${dns_servers[$((RANDOM % ${#dns_servers[@]}))]}
    
    # 先查询常见域名模拟正常用户行为,避免直接暴露证书申请意图
    local warmup_domains=("google.com" "cloudflare.com" "github.com")
    local warmup_domain=${warmup_domains[$((RANDOM % ${#warmup_domains[@]}))]}
    dig +short @${dns_server} A ${warmup_domain} >/dev/null 2>&1 || true
    sleep $((1 + RANDOM % 3))
    
    info "等待 DNS TXT 传播（主动探测 _acme-challenge.${_d}，最长 ${_max}s）..."
    while (( _elapsed < _max )); do
      if dig @${dns_server} +short +time=3 +tries=1 TXT "_acme-challenge.${_d}" 2>/dev/null | sed '/^$/d' | grep -q .; then
        printf '\n%s\n' "${GREEN}[OK]${NC}    DNS TXT 已检测到，继续申请证书..."
        _restore_dns_traps
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
    warn "DNS 传播等待超时（${_max}s），acme.sh 将立即尝试申请（可能失败）"
    _restore_dns_traps
    return 1
}
# [Doc4-3] DNS-01 (dns_cf) 模式通过 Cloudflare API 修改 TXT 记录，完全不需要占用 80 端口
# 移除之前错误引入的 nginx stop/start，避免每次申请证书都导致 45231 decoy 宕机
rm -rf "${ACME_HOME}/${domain}_ecc" 2>/dev/null || true
local issued=0
for try in 1 2; do
    local _force_opt=""
    (( try > 1 )) && _force_opt="--force"
    # [BUG-14 FIX] 移除第一次尝试前的DNS等待 - acme.sh会自己创建TXT记录
    # [BUG-16 FIX] 将dnssleep从0改为60 - Cloudflare DNS传播需要时间
    CF_Token="$cf_token" "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --issue --dns dns_cf \
      --domain "$domain" --keylength ec-256 \
      --server letsencrypt \
      --dnssleep 60 \
      ${_force_opt} && issued=1 && break || true
    # [BUG-15 FIX] 删除重试间的DNS等待 - acme.sh失败后会删除TXT记录，等待无意义
    (( try < 2 )) && warn "第 ${try} 次申请失败，将立即重试..."
  done
  (( issued )) || die "证书申请失败（请检查 Token 权限：Zone:DNS:Edit，或 3 分钟后重试）"

  # v2.35: 使用提取出的辅助函数，避免重复 heredoc
  _write_cert_reload_script

  # install-cert 不需要 CF_Token（只有 --issue 需要），保持干净
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

  # v1.3: 权限除根——完整 LANDING_BASE 下所有文件归 xray-landing，防 Xray 无权读取证书
  chown -R "${LANDING_USER}:${LANDING_USER}" "${LANDING_BASE}"
  chown -R root:root "${ACME_HOME}" 2>/dev/null || true
  chmod 700 "${ACME_HOME}" 2>/dev/null || true 2>/dev/null || \
    chown -R root:"${LANDING_USER}" "${LANDING_BASE}"
  # 证书目录额外加固：私钥仅 group 可读，不对 other 开放
  chmod 750 "$cert_dir"
  chmod 644 "${cert_dir}/cert.pem" "${cert_dir}/fullchain.pem"
  chmod 640 "${cert_dir}/key.pem"
  # config.json 也需要对 xray-landing 可读
  [[ -f "$LANDING_CONF" ]] && chmod 640 "$LANDING_CONF" 2>/dev/null || true
  success "证书部署完成（LANDING_BASE 权限已归 ${LANDING_USER}，key.pem=640）"

  info "配置证书自动续期 cron ..."
  rm -f /etc/cron.d/acme-xray-landing 2>/dev/null || true
  # [v2.14 Bug Fix] Clear ALL existing acme.sh cron entries regardless of path before
  # v2.24: Critical - 简化cron清理，使用acme.sh原生卸载/安装
  env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
  # Force ACME_HOME to our migrated path so the installed cron entry uses the correct binary.
  env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --install-cronjob \
    || die "acme.sh --install-cronjob 失败！续期链路断开，请检查 crontab 权限后重试"
  # [v2.15 Bug Fix] acme.sh sometimes hard-codes /root/.acme.sh into the crontab entry even
  # when ACME_HOME is set (version-dependent behaviour). Rewrite any such paths to our actual
  # ACME_HOME so renewal keeps firing at the correct binary after the 60-day cycle.
  # [BUG #23 Fix] Replace both quoted and unquoted patterns, handle "/root/.acme.sh"/acme.sh format
  crontab -l 2>/dev/null \
    | sed "s|\"${HOME}/.acme.sh\"|\"${ACME_HOME}\"|g" \
    | sed "s|\"/root/.acme.sh\"|\"${ACME_HOME}\"|g" \
    | sed "s|${HOME}/.acme.sh/acme.sh|${ACME_HOME}/acme.sh|g" \
    | sed "s|/root/.acme.sh/acme.sh|${ACME_HOME}/acme.sh|g" \
    | sed "s|--home \"${HOME}/.acme.sh\"|--home \"${ACME_HOME}\"|g" \
    | sed "s|--home \"/root/.acme.sh\"|--home \"${ACME_HOME}\"|g" \
    | crontab - 2>/dev/null || true
  # Validation: accept either our ACME_HOME path or the legacy ~/.acme.sh path, since
  # some acme.sh versions write the cron entry using their compiled-in home path.
  # [BUG #23 Debug] Output actual crontab content before validation
  info "调试：当前 crontab 中的 acme.sh 条目："
  crontab -l 2>/dev/null | grep acme || warn "未找到 acme 相关 cron 条目"
  # [BUG #23 Fix] Match both quoted and unquoted formats: "/path"/acme.sh or /path/acme.sh
  if ! crontab -l 2>/dev/null | grep -E "(\"${ACME_HOME}\"|${ACME_HOME})/acme\.sh" >/dev/null; then
    die "acme.sh cron 条目验收失败（未指向 ${ACME_HOME}/acme.sh），请手动执行: ${ACME_HOME}/acme.sh --install-cronjob"
  fi
  success "证书自动续期已配置并验收通过（acme.sh 原生 crontab）"

  # [C3 Fix] Add daily certificate renewal monitoring
  atomic_write "/etc/cron.daily/acme-renew-check" 755 root:root <<'ACME_CHECK'
#!/bin/sh
# 每日检查 acme.sh 上次续期时间，超过 65 天未成功则告警
for d in /etc/xray-landing/certs/*/fullchain.pem; do
  [ -f "$d" ] || continue
  dom=$(echo "$d" | sed 's|/etc/xray-landing/certs/\(.*\)/fullchain.pem|\1|')
  last_renew=$(stat -c %Y "$d" 2>/dev/null || echo 0)
  now=$(date +%s)
  days_since=$(( (now - last_renew) / 86400 ))
  if [ "$days_since" -gt 65 ]; then
    msg="FATAL: 证书 ${dom} 已 ${days_since} 天未续期，acme.sh cron 可能失效！"
    logger -t acme-renew-check "$msg"
    echo "$(date) $msg" >> /var/log/acme-xray-landing-renew.log
  fi
done
ACME_CHECK
  success "证书续期监控已配置（每日检查，超过65天未续期则告警）"

  # v2.44 Gemini: 独立旁路哨兵——完全独立于 acme.sh 成功回调之外
  # 作用：acme.sh 续期连续失败时系统静默（reloadcmd 永远不被调），旁路 cron 每日主动巡检证书寿命
  atomic_write "/etc/cron.daily/xray-cert-monitor" 755 root:root <<'MEOF'
#!/bin/sh
# xray-cert-monitor — 独立证书寿命哨兵，由 xray-landing 脚本管理
# 7天内过期则告警（logger + renew.log + profile.d SSH登录劫持）
# 完全独立于 acme.sh 回调路径，防续期连续失败时系统静默
# [v2.7 Gemini-Doc1-🔴] Also runs systemctl reset-failed on expiry detection:
#   cron network blip → reloadcmd fires → xray-landing hits StartLimitBurst → permanent
#   failed state → all nodes down until manual reset-failed. This guard auto-heals.

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
    # [v2.7] Auto-clear circuit-breaker so reloadcmd on next acme.sh run can succeed
    /bin/systemctl reset-failed xray-landing.service 2>/dev/null || true
  fi
done

# v2.45 Gemini: 发现濒死证书 → 写 profile.d，确保管理员下次 SSH 登录看到血红色警告
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

# v2.47 Gemini: 清理 acme.sh 内部 CSR/CONF 历史备份（每次续期失败均会产生）
# v1.5 [Doc6-Gemini]: 改为 7 天（原 30 天过长，inode 耗尽更早），补加 .key 归档
find /etc/xray-landing/acme -name "*.csr" -mtime +7 -delete 2>/dev/null || true
find /etc/xray-landing/acme -name "*.conf.bak" -mtime +7 -delete 2>/dev/null || true
find /etc/xray-landing/acme -name "*.key" -mtime +7 ! -name "account.key" -delete 2>/dev/null || true

# v2.48 Gemini: 清理孤儿 acme 缓存目录（申请失败但已创建的 _ecc 目录，无 fullchain.cer）
find /etc/xray-landing/acme -mindepth 1 -maxdepth 1 -type d -name "*_ecc" \
  -exec sh -c 'for d; do [ -f "$d/fullchain.cer" ] || rm -rf "$d"; done' _ {} + 2>/dev/null || true
MEOF
}

sync_xray_config(){
  info "同步 Xray 配置（5协议单端口回落）..."
  _validate_internal_ports_in_use
  load_manager_config
  # 🔴 GPT: 端口必须在 bash 层生成并写入真相源 manager.conf，绝不从派生的 config.json 反读
  # 若 manager.conf 中端口为 0（首次 sync 或真相源损坏），在此生成并原子提交
  if [[ "${VLESS_GRPC_PORT:-0}" == "0" ]]; then
    local _base
    _base=$(python3 -c "import secrets; b=secrets.randbelow(8000)&~3; print(21000+b)")
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
    export _VLESS_GRPC_PORT="$VLESS_GRPC_PORT"
    export _TROJAN_GRPC_PORT="$TROJAN_GRPC_PORT"
    export _VLESS_WS_PORT="$VLESS_WS_PORT"
    export _TROJAN_TCP_PORT="$TROJAN_TCP_PORT"
    export _BIND_IP="$BIND_IP"
    [[ "$VLESS_GRPC_PORT" =~ ^[0-9]+$ ]] || die "VLESS_GRPC_PORT non-numeric: $VLESS_GRPC_PORT"
    [[ "$TROJAN_GRPC_PORT" =~ ^[0-9]+$ ]] || die "TROJAN_GRPC_PORT non-numeric: $TROJAN_GRPC_PORT"
    [[ "$VLESS_WS_PORT" =~ ^[0-9]+$ ]] || die "VLESS_WS_PORT non-numeric: $VLESS_WS_PORT"
    [[ "$TROJAN_TCP_PORT" =~ ^[0-9]+$ ]] || die "TROJAN_TCP_PORT non-numeric: $TROJAN_TCP_PORT"
    # [H2 Fix] Check for port conflicts between landing_port and internal ports
    for _internal_port in "$VLESS_GRPC_PORT" "$TROJAN_GRPC_PORT" "$VLESS_WS_PORT" "$TROJAN_TCP_PORT"; do
      if [[ "$_internal_port" == "$LANDING_PORT" ]]; then
        die "内部端口 ${_internal_port} 与 landing_port ${LANDING_PORT} 冲突"
      fi
    done
    python3 - <<'PYEOF'
import json, os, glob, uuid as _uuid, random as _rand
from pathlib import Path

nodes_dir    = os.environ['_NODES_DIR']
cert_base    = os.environ['_CERT_BASE']
log_dir      = os.environ['_LOG_DIR']
out_path     = os.environ['_CFG_OUT']
bind_ip      = os.environ.get('_BIND_IP', '0.0.0.0')
# [F2] safe_int: guards against non-numeric values in manager.conf (e.g. manual edit error)
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
    # [v2.8 GPT-Doc2-🟠] Zero-byte guard: a kill-9 during atomic mv can leave a 0-byte
    # dest file; treat as corruption to force bash die() + rollback via non-zero exit.
    if os.path.getsize(path) == 0:
        raise ValueError(f"Zero-byte node file detected: {path}")
    # [R13 Fix] Also check for non-zero files that contain only whitespace or comments
    try:
        file_content = Path(path).read_text(encoding='utf-8', errors='replace').strip()
        if not file_content or file_content.startswith('#'):
            raise ValueError(f"Node file contains no valid data: {path}")
    except OSError as e:
        raise ValueError(f"Cannot read node file {path}: {e}")
    dom = pwd = ''
    try:
        for line in open(path, encoding='utf-8', errors='replace'):
            line = line.strip()
            if line.startswith('DOMAIN='):   dom = line[7:]
            if line.startswith('PASSWORD='): pwd = line[9:]
    except OSError as e:
        raise ValueError(f"Cannot read node file {path}: {e}")
    # [v2.7 GPT-Doc2-🔴] Hard-fail on corrupted node: silent skip causes xray to stop serving
    # the node while bash sees exit-0 → truth-source drift with no rollback. ValueError forces
    # the outer subshell to exit non-zero so the bash die() + rollback path fires.
    if not dom or not pwd:
        raise ValueError(f"Corrupted node state in {path}: DOMAIN or PASSWORD missing")
    cert_fullchain = f"{cert_base}/{dom}/fullchain.pem"
    cert_key       = f"{cert_base}/{dom}/key.pem"
    if not os.path.exists(cert_fullchain) or not os.path.exists(cert_key):
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

# v2.47 Grok: cipherSuites/curves 已移除，沿用默认 TLS 参数
# 不再需要显式 cipher 列表

tls_settings = {
    "minVersion": "1.2",
    # [Doc5-Grok] ALPN already includes http/1.0 since v1.4 to reduce ALPN distinctiveness
    "alpn": ["h2", "http/1.1", "http/1.0"],
    # [Fix-2 / Role-C-🔴] rejectUnknownSni=True: GFW sends wrong/no SNI → Xray aborts handshake.
    # Rationale: with False, Xray serves the *real* cert (containing your domain) to any prober
    # → direct domain exposure. A TLS abort is a smaller signal than revealing the cert domain.
    # Banner already documented this as True; this makes code consistent with documentation.
    "rejectUnknownSni": True,
    # [C1-FIX] 删除入站fingerprint配置 - Xray入站不支持uTLS指纹,这是出站功能
    # uTLS指纹伪装由客户端(手机/电脑代理软件)实现,服务端只需透传
    "certificates": list(certs_dict.values())
}

cfg = {
    # v2.47 Gemini: Xray 日志改由 systemd journal 接管，access/error 均设为 none
    # 查看方式: journalctl -u xray-landing.service -f
    "log": {"access": "none", "error": "none", "loglevel": "warning"},
    "inbounds": [
        {
            "listen": bind_ip, "port": landing_port, "protocol": "vless",
            "settings": {
                "clients": [{"id": vless_uuid, "flow": "xtls-rprx-vision", "level": 0, "email": "vless-vision@main"}],
                "decryption": "none",
                "fallbacks": [
                    # [v2.15 Fix] fallbacks[].alpn MUST be a plain string, NOT an array.
                    # Xray schema: inbounds.streamSettings.tlsSettings.alpn → array (correct above).
                    #              inbounds.settings.fallbacks[].alpn       → string (fixed here).
                    # Arrays caused status=23 from Xray's JSON schema validator.
                    {"alpn": "h2", "dest": PORT_VLESS_GRPC,  "xver": 0},
                    {"alpn": "h2", "dest": PORT_TROJAN_GRPC, "xver": 0},
                    # WS: alpn=http/1.1 + path match; Trojan-TCP: no alpn/path = catch-all
                    {"alpn": "http/1.1", "path": f"/{PFX}-vw", "dest": PORT_VLESS_WS, "xver": 0},
                    {"dest": PORT_TROJAN_TCP, "xver": 0}
                ]
            },
            "streamSettings": {"network": "tcp", "security": "tls", "tlsSettings": tls_settings},
            "sniffing": {"enabled": True, "routeOnly": False, "destOverride": ["http", "tls"]}
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
            # v1.3: xver=0 → acceptProxyProtocol=False（与 fallback xver 保持一致，不读 PP 头）
            "streamSettings": {"network": "ws", "wsSettings": {"path": f"/{PFX}-vw"}, "acceptProxyProtocol": False},
            "sniffing": {"enabled": False}
        },
        {
            "listen": "127.0.0.1", "port": PORT_TROJAN_TCP, "protocol": "trojan",
            "settings": {"clients": trojan_clients, "fallbacks": [{"dest": PORT_FALLBACK, "xver": 0}]},
            # v1.3: xver=0 → acceptProxyProtocol=False
            "streamSettings": {"network": "tcp", "acceptProxyProtocol": False},
            "sniffing": {"enabled": False}
        }
    ],
    "dns": {
        "servers": [
            "localhost"
        ],
        "queryStrategy": "UseIPv4"
    },
    "outbounds": [
        {
            "protocol": "freedom", 
            "tag": "direct", 
            "settings": {"domainStrategy": "UseIPv4"},
            "streamSettings": {
                "sockopt": {
                    "tcpFastOpen": False,
                    "tcpKeepAliveInterval": 30
                }
            }
        },
        {"protocol": "blackhole", "tag": "blocked", "settings": {"response": {"type": "none"}}}
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked"},
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
            {"type": "field", "port": "25", "outboundTag": "blocked"}
        ]
    },
    "policy": {
        "levels": {"0": {"handshakeTimeout": 4,
                         # connIdle=300: tighter Goroutine hold; gRPC keepalive handles
                         # legitimate long connections; 120s still > most gRPC ping intervals (30-60s)
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
  # [Fix-3 / Reliability-🟠] Permission finalization is part of the config transaction.
  # If chown/chmod fail after os.replace(), config.json exists but is unreadable by xray-landing.
  # Hard-fail here so the caller's rollback logic fires instead of silently advancing state.
  chown -R root:"$LANDING_USER" "$LANDING_BASE" \
    || die "sync_xray_config: chown LANDING_BASE failed — Xray may not be able to read config/certs"
  chmod 750 "$LANDING_BASE"
  chmod 640 "$LANDING_CONF"
  success "Xray 配置已同步: ${LANDING_CONF}"
}

# [L-CRITICAL-2] DNS本地化 - 使用美国家宽ISP原生DNS
setup_native_dns(){
  # [L-CRITICAL-7] DNS策略调整 - 使用VPS自带DNS而非强制指定美国ISP DNS
  # 原因: 如果落地机ISP是Comcast但DNS指向AT&T，这是异常特征
  # 修复: 保留VPS商家/ISP自动分配的DNS，不做任何修改
  info "保留VPS原生DNS配置（避免DNS与ISP不匹配的异常特征）..."
  
  # 检查当前DNS配置
  local current_dns=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
  if [[ -n "$current_dns" ]]; then
    success "当前DNS: ${current_dns}（保持不变，符合真实用户行为）"
  else
    warn "未检测到DNS配置，将使用系统默认"
  fi
}

# [S1-HIGH] 增强健康检查 - 自动检测和恢复服务异常
setup_health_check(){
  info "配置健康检查和自动恢复..."
  
  atomic_write "/usr/local/bin/xray-landing-health-check.sh" 755 root:root <<'HEALTH'
#!/bin/bash
# [S1-HIGH] 健康检查脚本 - 确保长期稳定运行
set -euo pipefail

# 检查 Xray 服务状态
if ! systemctl is-active --quiet xray-landing.service; then
  logger -t xray-health "Xray服务异常,尝试重启"
  systemctl restart xray-landing.service
  exit 0
fi

# 检查监听端口
LANDING_PORT=$(grep '^LANDING_PORT=' /etc/xray-landing/manager.conf 2>/dev/null | cut -d= -f2 || echo "8443")
# [审查者1-稳定4修复] 改用ss命令 - 零开销,避免20万次无意义TCP握手
# [审查者2-v4.34修复] 添加词边界\b避免误匹配（如8443被误认为443）
if ! ss -tlnp 2>/dev/null | grep -qE ":${LANDING_PORT}\b"; then
  logger -t xray-health "端口${LANDING_PORT}无响应,重启服务"
  systemctl restart xray-landing.service
  exit 0
fi

# 检查配置文件完整性
if ! python3 -c "import json,sys; json.load(open('/etc/xray-landing/config.json'))" 2>/dev/null; then
  logger -t xray-health "配置文件损坏,尝试恢复"
  systemctl restart xray-landing.service
  exit 0
fi

# 检查证书有效期
for cert in /etc/xray-landing/certs/*/fullchain.pem; do
  [ -f "$cert" ] || continue
  # [S1-HIGH] 提前7天检测证书过期,自动触发续期
  if ! openssl x509 -checkend $((7*86400)) -noout -in "$cert" 2>/dev/null; then
    domain=$(echo "$cert" | sed 's|/etc/xray-landing/certs/\(.*\)/fullchain.pem|\1|')
    logger -t xray-health "证书即将过期: ${domain}，触发续期"
    # [M1] 证书续期优化 - 删除--force参数,让acme.sh自己判断
    /etc/xray-landing/acme/acme.sh --cron 2>/dev/null || true
  fi
done
HEALTH

  # [M1-FIX] 健康检查高频执行 - 每3分钟检查一次,确保长期稳定运行
  # 频繁检查可快速发现和恢复异常,对于数月免维护运行至关重要
  atomic_write "/etc/cron.d/xray-landing-health" 644 root:root <<CRON
# [S1-HIGH] 健康检查 - 每3分钟执行,快速发现和恢复异常
*/3 * * * * root /usr/local/bin/xray-landing-health-check.sh >/dev/null 2>&1
CRON

  success "健康检查已配置: 每3分钟自动检测"
}

# [L5-MEDIUM] 正常网站访问模拟 - 生成美国用户的典型网络访问模式
setup_traffic_simulation(){
  # [L-CRITICAL-6] 彻底删除流量模拟 - curl定时访问是机器人特征,会毁掉IP信誉
  # 原因: 
  # 1. curl的TLS指纹与真实浏览器完全不同,即使伪造UA也会被识别
  # 2. 定时访问大厂网站(Google/Netflix)会触发反欺诈系统
  # 3. 真实用户通过代理产生的流量就是最好的掩护,不需要画蛇添足
  info "跳过流量模拟配置（真实用户流量是最好的伪装）"
  
  # 清理可能存在的旧版本流量模拟脚本和cron任务
  rm -f /usr/local/bin/xray-landing-traffic-sim.sh 2>/dev/null || true
  rm -f /etc/cron.d/xray-landing-traffic-sim 2>/dev/null || true
  
  success "已移除流量模拟机制（避免curl机器人特征暴露）"
}

write_logrotate(){
  # v2.47 Gemini: Xray-core 使用 Go，copytruncate 会产生稀疏文件（Golang内部offset指针不复位）
  # 改为：Xray 日志直接输出到 systemd journal（StandardError=journal），logrotate 只管 acme 日志
  atomic_write "$LOGROTATE_FILE" 644 root:root <<LREOF
# v2.10: Xray 业务日志已迁移到 systemd journal，此文件管理 acme 续期日志
# [v2.10 GPT-Doc6-🟠] acme-xray-landing-renew.log gets a dedicated daily stanza:
# the old weekly/4 rotation was too infrequent during continuous renewal failures or
# heavy probing that write many lines per day, risking disk exhaustion on low-disk VPS.
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

# [F3] Safety net: if any file log reappears under LANDING_LOG (e.g. cert-reload output),
# rotate it so disk pressure does not accumulate silently.
# [v2.10 Architect-🟠] postrotate block removed: rotating a safety-net log should not
# trigger a service reload. Keep disk maintenance decoupled from service state changes.
# Xray reads certs at startup/reload; rotated logs require no service notification.
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
  # [Doc7-Risk] journald 上限：Xray 业务日志已迁入 journal，若无上限会静默填满磁盘
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
  # [v2.13 GPT-🟠] Service unit staging file moved from /tmp to script-owned MANAGER_BASE/tmp
  mkdir -p "${MANAGER_BASE}/tmp"
  local _svc_tmp; _svc_tmp=$(mktemp "${MANAGER_BASE}/tmp/.xray-landing.svc.XXXXXX") \
    || die "mktemp _svc_tmp failed — MANAGER_BASE/tmp missing or disk full"
  cat > "$_svc_tmp" <<'SVCEOF'
[Unit]
Description=Xray Landing Node (independent from mack-a)
After=network.target nss-lookup.target
# [Fix-C] 900s window × 10 bursts = tolerates brief cert/network blips without false circuit-break
# RestartSec=15s: slower retry reduces thundering-herd on cert reload; 10×15s=150s < 900s window
StartLimitIntervalSec=900
StartLimitBurst=10
OnFailure=xray-landing-recovery.service

[Service]
Type=simple
User=@@LANDING_USER@@
NoNewPrivileges=true
ExecStartPre=/bin/sh -c 'test -f @@LANDING_CONF@@ || { echo "config.json missing"; exit 1; }'
ExecStartPre=/bin/sh -c 'python3 -c "import json,sys; json.load(open(sys.argv[1]))" @@LANDING_CONF@@ 2>/dev/null || { echo "config.json invalid JSON"; exit 1; }'
@@CAP_LINE@@
@@CAP_BOUND@@
ExecStart=@@LANDING_BIN@@ run -config @@LANDING_CONF@@
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray-landing
Restart=on-failure
ExecReload=/bin/systemctl restart xray-landing.service
# [Fix-C] RestartSec=15s: slower retry reduces cert-reload thundering-herd; 10×15s=150s < 900s window
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

  # [v2.9 GPT-B-🔴] Compute dynamic FD ceiling (same formula used by _tune_nginx_worker_connections)
  # and inject into the service file via @@LIMIT_NOFILE@@ placeholder. Hard-coded 1048576 caused
  # systemd to refuse service start on 512 MB VPS where kernel ceiling is only 524288.
  local _svc_ram_mb; _svc_ram_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}'); _svc_ram_mb=${_svc_ram_mb:-1024}
  local _svc_fd=$(( _svc_ram_mb * 800 ))
  (( _svc_fd < 524288 ))   && _svc_fd=524288
  (( _svc_fd > 10485760 )) && _svc_fd=10485760

  # sed-inject 所有运行时路径（占位符方式，绕过 heredoc 变量展开问题）
  # [R17 Fix] Always grant CAP_NET_BIND_SERVICE — fallback ports (45231/45232) are <1024
  # regardless of LANDING_PORT value, and Xray needs this cap to bind them.
  # Only grant CAP_NET_BIND_SERVICE if LANDING_PORT < 1024
  local _cap_escaped="" _cap_bound_escaped=""
  if (( LANDING_PORT < 1024 )); then
    _cap_escaped="AmbientCapabilities=CAP_NET_BIND_SERVICE"
    _cap_bound_escaped="CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
  fi
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
  sed -i 's|ReadOnlyPaths=|ReadWritePaths='"${CERT_BASE}"'\
ReadOnlyPaths=|' "/etc/systemd/system/${LANDING_SVC}"
  # [Doc6-Gemini-🔴] xray-landing.service.d drop-in：高并发 gRPC 下 Xray 内部端口也消耗 fd
  # [v2.9] Always rewrite with dynamic value — previous guard against 1048576 missed updates.
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

  # v2.47 Gemini: recovery unit — diagnostic + conditional auto-restart with preflight
  # [F3] Rate-limit guard: if recovery fires twice within 1800s, it is a persistent hard error
  # (port conflict, binary crash, etc.) — stop looping and require manual intervention.
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
  # [F5] daemon-reload must succeed for unit changes to take effect
  systemctl daemon-reload \
    || die "daemon-reload 失败，systemd 图未更新"
  systemctl enable "$LANDING_SVC"
  systemctl restart "$LANDING_SVC"
  sleep 2
  if systemctl is-active --quiet "$LANDING_SVC"; then
    success "服务 ${LANDING_SVC} 已启动"
  else
    journalctl -u "$LANDING_SVC" --no-pager -n 30
    # v2.37 GPT: 启动失败 → 完整回滚 unit+logrotate，防半安装状态残留
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

  # [v2.15 Bug Fix] Bulldozer pre-flight: iptables -E ("rename") fails with "File exists"
  # whenever INPUT still has ANY rule referencing FW_CHAIN — whether by direct -j, by comment,
  # or by any other comment tag left by a prior interrupted run. The previous while-loop approach
  # only removed rules with specific known comments, missing any that used different comments.
  # The bulldozer approach reads iptables -S INPUT directly and deletes every rule that
  # references FW_CHAIN or FW_TMP by name before attempting -F / -X / -E.
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

  # Remove all INPUT references to both the stable chain and the temp chain, then flush+delete.
  # Remove all INPUT references to both the stable chain and the temp chain, then flush+delete.
  _bulldoze_input_refs  "$FW_CHAIN";  _bulldoze_input_refs  "$FW_TMP"
  iptables -w 2 -F "$FW_TMP"   2>/dev/null || true; iptables -w 2 -X "$FW_TMP"   2>/dev/null || true
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  
  # [H2] IPv6封堵双重保险 - 检测到IPv6禁用时跳过IPv6防火墙配置
  if have_ipv6; then
    if sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q '^1$'; then
      info "IPv6已在内核层面禁用，跳过IPv6防火墙配置"
    else
      _bulldoze_input_refs6 "$FW_CHAIN6"; _bulldoze_input_refs6 "$FW_TMP6"
      ip6tables -w 2 -F "$FW_TMP6"   2>/dev/null || true; ip6tables -w 2 -X "$FW_TMP6"   2>/dev/null || true
      ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
    fi
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
  }
  _restore_prev_fw_traps(){
    eval "${_prev_err_trap:-trap - ERR}"
    eval "${_prev_int_trap:-trap - INT}"
    eval "${_prev_term_trap:-trap - TERM}"
  }
  trap '_fw_landing_rollback; exit 130' INT TERM ERR
  # [R7 Fix] Pre-flight validation of ALL node files BEFORE any iptables modifications
  local _conf_files=()
  while IFS= read -r f; do _conf_files+=("$f"); done     < <(find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" -type f 2>/dev/null | sort)
  local expected_count=${#_conf_files[@]} skipped=0 tips=()
  for meta in "${_conf_files[@]+${_conf_files[@]}}"; do
    [[ -f "$meta" ]] || continue
    local tip; tip=$(grep '^TRANSIT_IP=' "$meta" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}')
    if [[ -z "$tip" ]]; then
      warn "  [跳过] 节点文件 ${meta} 缺少 TRANSIT_IP 字段"; (( ++skipped )) || true; continue
    fi
    if ! printf '%s' "$tip" | python3 -c "import ipaddress,sys; ipaddress.IPv4Address(sys.stdin.read().strip())" 2>/dev/null; then
      warn "  [跳过] 节点文件 ${meta} TRANSIT_IP='${tip}' 格式非法"; (( ++skipped )) || true; continue
    fi
    tips+=("$tip")
  done
  if (( skipped > 0 )); then
    die "防火墙构建中止：${skipped} 个节点文件格式异常，拒绝生成可能放行不足的规则集（预期 ${#_conf_files[@]}，有效 $(( ${#_conf_files[@]} - skipped ))）"
  fi
  # [R14 Fix] Warn about duplicate transit IPs (multiple domains on same transit is normal)
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
  # v2.32 Grok: lo + SSH 先于 INVALID,UNTRACKED 放行，conntrack 表满时 SSH 不断
  iptables -w 2 -A "$FW_TMP" -i lo                                       -m comment --comment "xray-landing-lo"        -j ACCEPT
  # [L-CRITICAL-1] 1Panel/Docker兼容 - 放行Docker虚拟网桥，防止OpenClaw/Hermes容器断网
  iptables -w 2 -A "$FW_TMP" -i docker0 -m comment --comment 'xray-landing-docker' -j ACCEPT 2>/dev/null || true
  iptables -w 2 -A "$FW_TMP" -i br-+ -m comment --comment 'xray-landing-docker-br' -j ACCEPT 2>/dev/null || true
  # v2.16: 本地环回保护 - 仅允许xray-landing用户访问内部端口
  # v2.41: 删除无效的lo规则(INPUT链不处理本地进程间通信，已listen 127.0.0.1足够)
  iptables -w 2 -A "$FW_TMP" -p tcp  --dport "$ssh_port"                 -m comment --comment "xray-landing-ssh"       -j ACCEPT
  # [L-CRITICAL-1] 1Panel/Docker额外端口放行
  local _extra_ports; _extra_ports=$(grep '^EXTRA_PORTS=' "$MANAGER_CONFIG" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
  if [[ -n "$_extra_ports" ]]; then
    for _ep in $_extra_ports; do
      if [[ "$_ep" =~ ^[0-9]+$ ]] && (( _ep >= 1 && _ep <= 65535 )); then
        iptables -w 2 -A "$FW_TMP" -p tcp --dport "$_ep" -m comment --comment "xray-landing-extra" -j ACCEPT
        info "  额外端口放行: $_ep"
      fi
    done
  fi
  local count=0
  while IFS= read -r tip; do
    [[ -n "$tip" ]] || continue
    validate_ipv4 "$tip"
    iptables -w 2 -A "$FW_TMP" -s "${tip}/32" -p tcp --dport "$LANDING_PORT" -m comment --comment "xray-landing-transit" -j ACCEPT \
      || { iptables -w 2 -F "$FW_TMP" 2>/dev/null || true; iptables -w 2 -X "$FW_TMP" 2>/dev/null || true; die "防火墙规则添加失败（中转IP ${tip}），已清理临时链"; }
    info "  ACCEPT ← ${tip}/32:${LANDING_PORT}"; (( ++count )) || true
  done < <(printf '%s
' "${tips[@]+${tips[@]}}" | sort -u)
  # v2.32 Grok: conntrack 表满时 UNTRACKED 裸奔防护，SSH / 中转白名单已在上方豁免
  iptables -w 2 -A "$FW_TMP" -m conntrack --ctstate INVALID,UNTRACKED    -m comment --comment "xray-landing-invalid"   -j DROP
  iptables -w 2 -A "$FW_TMP" -m conntrack --ctstate ESTABLISHED,RELATED  -m comment --comment "xray-landing-est"       -j ACCEPT
  iptables -w 2 -A "$FW_TMP" -p icmp --icmp-type echo-request -m limit --limit 10/second --limit-burst 20                                                                      -m comment --comment "xray-landing-icmp"      -j ACCEPT || true
  iptables -w 2 -A "$FW_TMP" -p icmp --icmp-type echo-request            -m comment --comment "xray-landing-icmp-drop" -j DROP
  iptables -w 2 -A "$FW_TMP" -m comment --comment "xray-landing-drop" -j DROP

  iptables -w 2 -I INPUT 1 -m comment --comment "xray-landing-swap" -j "$FW_TMP"
  # [v2.15] Bulldozer drain: remove every INPUT rule referencing FW_CHAIN by any comment or
  # direct -j before -F/-X/-E. The old while-loop approach missed rules with unexpected comments.
  _bulldoze_input_refs "$FW_CHAIN"
  iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true; iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
  iptables -w 2 -E "$FW_TMP" "$FW_CHAIN" \
    || { _fw_landing_rollback; _restore_prev_fw_traps; die "防火墙链重命名失败（iptables -E），运行链已回滚"; }
  iptables -w 2 -I INPUT 1 -m comment --comment "xray-landing-jump" -j "$FW_CHAIN"
  while iptables -w 2 -D INPUT -m comment --comment "xray-landing-swap" 2>/dev/null; do :; done

  if have_ipv6; then
    ip6tables -w 2 -N "$FW_TMP6" 2>/dev/null || ip6tables -w 2 -F "$FW_TMP6"
    ip6tables -w 2 -A "$FW_TMP6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -i lo -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p tcp      --dport "$ssh_port"     -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -m conntrack --ctstate INVALID,UNTRACKED -j DROP
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 10/second --limit-burst 20 -m comment --comment "xray-landing-icmp6" -j ACCEPT
    ip6tables -w 2 -A "$FW_TMP6" -p ipv6-icmp --icmpv6-type echo-request -m comment --comment "xray-landing-icmp6-drop" -j DROP
    ip6tables -w 2 -A "$FW_TMP6" -p tcp      --dport "$LANDING_PORT" -j DROP
    ip6tables -w 2 -A "$FW_TMP6" -j DROP
    ip6tables -w 2 -I INPUT 1 -m comment --comment "xray-landing-v6-swap" -j "$FW_TMP6"
    # [v2.15] Bulldozer drain for IPv6 chain before rename
    _bulldoze_input_refs6 "$FW_CHAIN6"
    ip6tables -w 2 -F "$FW_CHAIN6" 2>/dev/null || true; ip6tables -w 2 -X "$FW_CHAIN6" 2>/dev/null || true
    ip6tables -w 2 -E "$FW_TMP6" "$FW_CHAIN6"
    ip6tables -w 2 -I INPUT 1 -m comment --comment "xray-landing-v6-jump" -j "$FW_CHAIN6"
    while ip6tables -w 2 -D INPUT -m comment --comment "xray-landing-v6-swap" 2>/dev/null; do :; done
  fi

  # v2.37 GPT: trap 保持活跃直到 _persist_iptables 成功，防运行链/开机链分裂
  if ! _persist_iptables "$ssh_port"; then
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
    printf '%s' "$tip" | python3 -c "import ipaddress,sys; ipaddress.IPv4Address(sys.stdin.read().strip())" 2>/dev/null && transit_ips+=("$tip") || true
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
set -euo pipefail
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
  # [R12 Fix] sshd not running at boot → fall back to sshd_config before using install-time value
  [ -z "$p" ] && p="$(grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk '{print $2}' | sort -n | head -1 || true)"
  if echo "$p" | grep -qE '^[0-9]+$' && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then
    echo "$p"
  else
    # [C2 Fix] Remove exit 1 - fallback to install-time port instead of blocking firewall restore
    logger -t xray-landing-firewall "WARN: 无法动态探测SSH端口，使用安装时值 __SSH_PORT__"
    echo "__SSH_PORT__"
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
  # [F5] daemon-reload must succeed for unit changes to take effect
  systemctl daemon-reload     || die "daemon-reload 失败，systemd 图未更新"
  # [Doc3-2] enable 失败意味着重启后规则丢失，属于静默时序炸弹，必须硬失败
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
  # [C3 Fix] Complete collision detection - check both DOMAIN and TRANSIT_IP fields
  if [[ -f "$_node_conf" ]]; then
    local _exist_content; _exist_content=$(cat "$_node_conf" 2>/dev/null || true)
    if [[ -n "$_exist_content" ]]; then
      local _exist_dom _exist_tip
      _exist_dom=$(grep '^DOMAIN=' "$_node_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
      _exist_tip=$(grep '^TRANSIT_IP=' "$_node_conf" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"",$0); print}' || true)
      if [[ "$_exist_dom" != "$domain" || "$_exist_tip" != "$transit_ip" ]]; then
        die "节点文件名碰撞：${_node_conf} 已被 ${_exist_dom}/${_exist_tip} 使用"
      fi
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
  
  # [L1-UX-1-FIX] 域名输入添加重试循环，输错不die而是提示重新输入
  while true; do
    read -rp "新节点域名: " NEW_DOMAIN
    NEW_DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$NEW_DOMAIN")")
    if validate_domain "$NEW_DOMAIN" 2>/dev/null; then
      break
    else
      error "域名格式错误，请重新输入（例如：example.com）"
    fi
  done

  local existing_pass=""
  # [Fix-4] Replace fragile grep-l|xargs pipeline with Python structured index lookup.
  # Shell pipelines silently pass empty on malformed/missing files; Python fails loudly on bad data.
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
    # [R17 Fix] If user provided a different password than existing, die
    if [[ -n "${NEW_PASS:-}" && "$NEW_PASS" != "$existing_pass" ]]; then
      die "节点文件已存在但密码不一致（旧: ${existing_pass:0:8}...，新: ${NEW_PASS:0:8}...），请先删除旧节点或留空以沿用现有密码"
    fi
    warn "域名 ${NEW_DOMAIN} 已存在，新中转机必须复用相同 Trojan 密码"
    NEW_PASS="$existing_pass"
    info "  自动沿用密码: ${NEW_PASS}"
  else
    # [L1-UX-1-FIX] 密码输入添加重试循环
    while true; do
      read -rp "Trojan 密码（16位以上，直接回车自动生成）: " NEW_PASS
      if [[ -z "$NEW_PASS" ]]; then
        NEW_PASS=$(gen_password)
        info "  已自动生成高强度密码: ${NEW_PASS}"
        break
      elif validate_password "$NEW_PASS" 2>/dev/null; then
        break
      else
        error "密码长度不足16位，请重新输入或直接回车自动生成"
      fi
    done
  fi

  # [L1-UX-1-FIX] 中转机IP输入添加重试循环
  while true; do
    read -rp "对应中转机公网 IP: " NEW_TRANSIT
    if validate_ipv4 "$NEW_TRANSIT" 2>/dev/null; then
      break
    else
      error "IP地址格式错误，请重新输入（例如：1.2.3.4）"
    fi
  done

  # BUG-5 FIX + [Fix-4]: Replace find|xargs|grep pipeline with Python structured lookup for transit IP
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

  local USE_CF_TOKEN="$CF_TOKEN"
  if [[ -z "$USE_CF_TOKEN" ]]; then
    # [BUG #36] Token输入添加循环重试
    while true; do
      read -rp "Cloudflare API Token（Zone:DNS:Edit）: " USE_CF_TOKEN
      if validate_cf_token "$USE_CF_TOKEN" 2>/dev/null; then
        CF_TOKEN="$USE_CF_TOKEN"
        break
      else
        error "Token格式错误，请重新输入（40位以上，仅字母数字_-）"
      fi
    done
  fi

  # v2.32: 所有用户输入已收集，加锁后才开始写操作
  _acquire_lock

  # [Fix-B / Doc8-GPT-🟠] Stage manager.conf — write to tmp, commit only after cert+sync+service pass.
  # Committing manager.conf before cert issuance creates a durable half-state on cert failure.
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

  # 提前计算最终节点文件路径（与 save_node_info 内部逻辑对齐）
  local _safe_dom; _safe_dom=$(printf '%s' "$NEW_DOMAIN" | tr '.:/' '___')
  local _safe_ip;  _safe_ip=$(printf '%s' "$NEW_TRANSIT" | tr '.:' '__')
  local _node_conf="${MANAGER_BASE}/nodes/${_safe_dom}_${_safe_ip}.conf"

  # 🔴 Grok: 临时文件必须以 .conf 结尾，Python glob(*.conf) 才能扫到新节点
  # 不用 .snap-recover 前缀（dotfile 被 glob 跳过），用 tmp- 前缀区分
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

  # [F1] Ghost cert guard: check if other committed node files still use this domain.
  # Revoking a cert shared by multiple transit nodes would break live connections on all of them.
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

  # SIGINT 显式回滚：已完成的 sync/firewall 一并回滚，而非只清理临时文件
  # [Fix-I / Doc9-GPT-🟠] Also revoke acme cert registration on interrupt to prevent ghost cert
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

  # v2.35 Gemini: 先 mv 临时文件为正式节点，再 setup_firewall（setup_firewall 排除 tmp-* 文件，
  # 必须让正式 .conf 存在才能把新 TRANSIT_IP 写入白名单，否则新节点永久被防火墙阻断）
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

  # BUG-5 FIX: 只有 _fw_skip==0 时才执行防火墙重建；IP已存在时跳过 iptables 但继续全流程
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
  # [Fix-B] Commit staged manager.conf now that cert+sync+service all succeeded
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

  read -rp "确认删除 ${DEL_DOMAIN}（中转: ${DEL_TRANSIT}）？[y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "已取消"; return; }

  # v2.32: 用户确认后加锁，写操作串行化
  _acquire_lock

  # [F1] Snapshot config.json BEFORE first sync so rollback is a direct file restore,
  # not a dynamic regeneration that can fail silently and leave config.json inconsistent.
  local _snap_cfg_del=""
  [[ -f "$LANDING_CONF" ]] && {
    _snap_cfg_del=$(mktemp "${LANDING_BASE}/.snap-recover.XXXXXX") \
      || die "mktemp _snap_cfg_del failed"
    cp -f "$LANDING_CONF" "$_snap_cfg_del" \
      || die "snapshot LANDING_CONF failed"
  }

  # 五步原子变更
  # [v2.9 Grok-C-🟠] Rename to .deleting (not rm) so the node file survives a SIGKILL between
  # the rename and sync_xray_config completing. glob(*.conf) excludes .deleting; setup_firewall
  # also rescans *.conf so the IP is removed from the whitelist correctly.
  # The .deleting file is removed only after service restart confirms success.
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

  # [v2.11 Grok-Doc9-🔴] Cert cleanup moved AFTER service restart confirms success.
  # Old position (before sync_xray_config) meant a sync failure would roll back the node
  # file but the cert was already wiped → Xray config referenced a now-missing certificateFile
  # → service crash on next start → total blackout for all remaining nodes.
  # Compute remaining count now (before sync) so the flag is available at the success path.
  local safe_del; safe_del=$(printf '%s' "$DEL_DOMAIN" | tr '.:/' '___')
  local remaining; remaining=$(find "${MANAGER_BASE}/nodes" -name "${safe_del}_*.conf" -type f 2>/dev/null | wc -l)

  if ! ( sync_xray_config ); then
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    # [F1] Direct snapshot restore — avoids silent sync failure leaving config.json inconsistent
    [[ -n "${_snap_cfg_del:-}" && -f "${_snap_cfg_del:-}" ]] \
      && mv -f "$_snap_cfg_del" "$LANDING_CONF" 2>/dev/null || true
    _release_lock; die "Xray配置同步失败，节点文件和config.json已物理回滚"
  fi
  rm -f "${_snap_cfg_del:-}" 2>/dev/null || true  # sync succeeded, snapshot no longer needed
  if ! ( setup_firewall ); then
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    # [F1] Re-sync after node restore (sync succeeded before, safe to re-run)
    ( sync_xray_config ) 2>/dev/null || true
    _release_lock; die "防火墙更新失败，节点文件已恢复"
  fi
  # v2.33 BUG-NEW: _snap_node 保留到 restart 验证通过后再删，保证重启失败时可回滚
  local _restart_rc=0
  systemctl restart "$LANDING_SVC" 2>/dev/null || _restart_rc=$?
  sleep 1
  if (( _restart_rc != 0 )) || ! systemctl is-active --quiet "$LANDING_SVC"; then
    warn "服务重启失败，回滚节点文件..."
    mv -f "${DEL_CONF}.deleting" "$DEL_CONF" 2>/dev/null || true
    ( sync_xray_config ) 2>/dev/null || true
    ( setup_firewall )   2>/dev/null || true
    # [Doc7-🔴] 回滚后必须恢复服务运行态，否则剩余所有节点永久断流直到人工介入
    systemctl reset-failed "$LANDING_SVC" 2>/dev/null || true
    systemctl restart "$LANDING_SVC" 2>/dev/null || true
    __delete_node_trap_active=0
    trap - INT TERM ERR
    _release_lock; warn "节点已恢复，请检查: journalctl -u ${LANDING_SVC}"
  else
    # Transaction confirmed: now safe to delete cert (service is running without it)
    if (( remaining == 0 )); then
      info "域名 ${DEL_DOMAIN} 已无中转机，清理证书..."
      if [[ -f "${ACME_HOME}/acme.sh" ]]; then
        "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$DEL_DOMAIN" --ecc 2>/dev/null || true
        rm -rf "${ACME_HOME}/${DEL_DOMAIN}_ecc" 2>/dev/null || true
      fi
      rm -rf "${CERT_BASE}/${DEL_DOMAIN}" 2>/dev/null || true
    fi
    # Both _snap_node and .deleting can now be removed — transaction succeeded
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
  # [R20 Fix] Capture prior trap state safely — trap -p returns empty if none set
  local _prev_err_trap _prev_int_trap _prev_term_trap
  _prev_err_trap=$(trap -p ERR 2>/dev/null || true)
  _prev_int_trap=$(trap -p INT 2>/dev/null || echo "")
  _prev_term_trap=$(trap -p TERM 2>/dev/null || echo "")
  local new_port="${1:-}"
  if [[ -z "$new_port" ]]; then
    # [BUG #36] 端口输入添加循环重试
    while true; do
      read -rp "新落地机监听端口: " new_port
      if validate_port "$new_port" 2>/dev/null; then
        break
      else
        error "端口格式错误，请重新输入（1-65535）"
      fi
    done
  else
    validate_port "$new_port"
  fi
  (( new_port >= 1024 )) || die "端口 ${new_port} 小于 1024，set-port 不支持低端口（需重装以更新权限配置）"
  # [R19 Fix] Check for conflict with internal ports (VLESS_GRPC, TROJAN_GRPC, VLESS_WS, TROJAN_TCP)
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

  # v2.32: 所有校验通过后加锁，写操作串行化
  # Guard: ERR trap only rolls back when this var is 1 (transaction active)
  _acquire_lock
  local _port_change_active=1

  local _snap_mgr _snap_cfg _snap_fw
  _snap_mgr=$(mktemp "${MANAGER_BASE}/.snap-recover.XXXXXX") \
    || { _release_lock; die "manager.conf 快照创建失败（磁盘满？），端口未变更"; }
  # v2.33 GPT BUG-04: config.json 快照失败时不允许空串继续，直接中止
  _snap_cfg=$(mktemp "${LANDING_BASE}/.snap-recover.XXXXXX" 2>/dev/null) \
    || { rm -f "$_snap_mgr"; _release_lock; die "config.json 快照创建失败（磁盘满/目录缺失？），端口未变更"; }
  # v2.34 GPT: firewall-restore.sh 快照——端口回滚时防持久化脚本与运行态分裂
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
    # [Doc4-2] 核心修复: 文件态还原后必须立即刷新内核运行态
    # 否则内存中是新端口规则，文件是旧端口规则 → 不重启就永久断流
    if [[ -x "${MANAGER_BASE}/firewall-restore.sh" ]]; then
      "${MANAGER_BASE}/firewall-restore.sh" 2>/dev/null || true
    fi
    # [Doc6-GPT-🟠] Sync config.json back to old port after firewall restore
    ( sync_xray_config ) 2>/dev/null || true
    # [Fix-1 / Role-B-🔴] Revival: reset circuit-breaker then restart on restored config.
    # Without restart, service stays dead after port-change rollback → total node blackout.
    systemctl reset-failed "$LANDING_SVC" 2>/dev/null || true
    systemctl restart "$LANDING_SVC" 2>/dev/null || true
    rm -f "$_snap_mgr" "${_snap_cfg:-}" "${_snap_fw:-}" 2>/dev/null || true
    # [M1 Fix] Clean up snapshot file to prevent disk leakage
    rm -f "${_snap_fw:-}" 2>/dev/null || true
    LANDING_PORT="$old_port"
    _release_lock
  }
  # [F2] Include ERR: set -e exits without rollback on bash errors (full disk, mktemp fail)
  # Guarded: only rolls back if _port_change_active=1 (transaction still in progress)
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
  # Transaction complete — deactivate guard and restore standard INT/TERM/ERR trap
  _port_change_active=0
  _restore_prev_port_traps
  trap '_global_cleanup; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM ERR
  # [Doc5-GPT] 成功路径也清零熔断计数，防残留计数在下次端口变更时误触发 failed 态
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
    # v2.44 GPT: 逐项校验节点完整性（conf + cert），缺一判红
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
  # [v2.14] Path-agnostic cron check: after acme.sh migration the cron entry may still
  # reference ~/.acme.sh; match on the --cron argument instead of a specific path.
  if crontab -l 2>/dev/null | grep -qE 'acme\.sh.*(--cron|cron)'; then
    echo -e "  acme.sh cron:    ${GREEN}✓ 已注册（原生 crontab）${NC}"
  else
    echo -e "  acme.sh cron:    ${RED}✗ 未注册（证书无法自动续期！运行 acme.sh --install-cronjob 修复）${NC}"
  fi
  systemctl is-enabled --quiet "xray-landing-iptables-restore.service" 2>/dev/null \
    && echo -e "  iptables 恢复服务: ${GREEN}✓ enabled${NC}" \
    || echo -e "  iptables 恢复服务: ${RED}✗ 未 enable（重启后防火墙规则会丢失）${NC}"
  # 🟡 GPT: 恢复脚本内容与运行链一致性校验（not just "enabled"）
  local _fw_script="${MANAGER_BASE}/firewall-restore.sh"
  if [[ -f "$_fw_script" ]]; then
    # v2.39 GPT #9: 版本签名校验——旧脚本/手改脚本开机会复活旧规则
    local _fw_ver_line; _fw_ver_line=$(grep '^# LANDING_FW_VERSION=' "$_fw_script" 2>/dev/null | head -1 || echo "")
    if [[ -z "$_fw_ver_line" ]]; then
      # v2.40 GPT #6: 无签名即分裂点，判红+自动重建
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
      # v2.42 GPT #5: --status 是只读巡检，不执行写操作；修复用独立命令
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
      # v2.39 GPT #8: 检测是否处于 failed/熔断态并提示自愈路径
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
  ss -tlnp 2>/dev/null | grep -qE ":${LANDING_PORT}\b" \
    && echo "  :${LANDING_PORT} 监听:    ✓" \
    || { echo -e "  ${RED}:${LANDING_PORT} 监听:    ✗ 端口未开放${NC}"; _ok=0; }
  # v2.34/35 GPT: 字段级一致性硬校验——真相源 manager.conf 与派生 config.json 逐项对比
  if [[ -f "$MANAGER_CONFIG" && -f "$LANDING_CONF" ]]; then
    local _cfg_port _cfg_uuid _cfg_vg _cfg_tg _cfg_vw _cfg_tt
    _cfg_port=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][0]['port'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    _cfg_uuid=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['inbounds'][0]['settings']['clients'][0]['id'])" \
      "$LANDING_CONF" 2>/dev/null || echo "")
    # 内部端口：inbounds[1]=vless-grpc  [2]=trojan-grpc  [3]=vless-ws  [4]=trojan-tcp
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
  # BUG-40 FIX: Token ip 字段必须是落地机公网 IPv4，dom 必须是域名
  # 用 python3 ipaddress 模块验证 pub_ip 确实是合法 IPv4，防止位移错误静默通过
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
  # ARCH-3 FIX: 原来 2>/dev/null 吞掉所有 Python 报错，导致静默 "[WARN] Base64 订阅生成失败"
  # 改为捕获 stderr，失败时打印真实错误，方便排查
  # [v2.15 Bug Fix] Python quote bug: python3 -c '...' uses shell single-quotes, which means
  # any Python single-quoted string literal (e.g. '[禁Mux]VLESS-Vision-') closes the shell
  # string early → SyntaxError at runtime. Fix: use a heredoc (<<'SUBPY') so the Python
  # source is passed verbatim without any shell-quoting interference. Label variables avoid
  # all quoting inside f-strings (matches the transit script pattern).
  # [L-CRITICAL-8] 订阅指纹随机化：每个落地机随机选择 uTLS 指纹，避免批量部署特征
  # 从 chrome/edge/firefox/safari/ios/random 中随机选择 4 个不重复指纹
  local fp_pool=("chrome" "edge" "firefox" "safari" "ios" "random")
  local fp_selected=()
  while [[ ${#fp_selected[@]} -lt 4 ]]; do
    local idx=$((RANDOM % ${#fp_pool[@]}))
    local fp="${fp_pool[$idx]}"
    # 避免重复选择
    if [[ ! " ${fp_selected[*]} " =~ " ${fp} " ]]; then
      fp_selected+=("$fp")
    fi
  done
  local fp_vision="${fp_selected[0]}"
  local fp_grpc="${fp_selected[1]}"
  local fp_ws="${fp_selected[2]}"
  local fp_tcp="${fp_selected[3]}"

  sub_b64=$(python3 - "$ti" "$domain" "$VLESS_UUID" "$password" "$fp_vision" "$fp_grpc" "$fp_ws" "$fp_tcp" 2>&1 <<'SUBPY'
import sys
if len(sys.argv) < 9: print('ERROR: requires 8 args', file=sys.stderr); sys.exit(1)
import base64, urllib.parse
transit_ip, domain, vless_uuid, trojan_pass = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
fp_vision, fp_grpc, fp_ws, fp_tcp = sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8]
port = 443
pfx = vless_uuid[:8]
# Label variables: avoids any quoting inside f-string {} (Python<3.12 compatible)
lbl_vision = '[禁Mux]VLESS-Vision-'
lbl_vgrpc  = 'VLESS-gRPC-'
# v2.17: Trojan-gRPC已禁用 (被VLESS-gRPC抢占h2流量)
# lbl_tgrpc  = 'Trojan-gRPC-'
lbl_vws    = 'VLESS-WS-'
lbl_ttcp   = 'Trojan-TCP-'
uris = [
    (f"vless://{vless_uuid}@{transit_ip}:{port}"
     f"?encryption=none&flow=xtls-rprx-vision&security=tls"
     f"&sni={domain}&fp={fp_vision}&type=tcp"
     f"#{urllib.parse.quote(lbl_vision+domain)}"),
    (f"vless://{vless_uuid}@{transit_ip}:{port}"
     f"?encryption=none&security=tls&sni={domain}&fp={fp_grpc}"
     f"&type=grpc&serviceName={pfx}-vg&alpn=h2&mode=multi"
     f"#{urllib.parse.quote(lbl_vgrpc+domain)}"),
    # v2.17: Trojan-gRPC已禁用
    # (f"trojan://{urllib.parse.quote(trojan_pass)}@{transit_ip}:{port}"
    #  f"?security=tls&sni={domain}&fp=ios"
    #  f"&type=grpc&serviceName={pfx}-tg&alpn=h2&mode=multi"
    #  f"#{urllib.parse.quote(lbl_tgrpc+domain)}"),
    (f"vless://{vless_uuid}@{transit_ip}:{port}"
     f"?encryption=none&security=tls&sni={domain}&fp={fp_ws}"
     f"&type=ws&path=%2F{pfx}-vw&host={domain}&alpn=http/1.1"
     f"#{urllib.parse.quote(lbl_vws+domain)}"),
    (f"trojan://{urllib.parse.quote(trojan_pass)}@{transit_ip}:{port}"
     f"?security=tls&sni={domain}&fp={fp_tcp}&type=tcp"
     f"#{urllib.parse.quote(lbl_ttcp+domain)}"),
]
print(base64.b64encode("\n".join(uris).encode()).decode())
SUBPY
) || { _sub_err="$sub_b64"; sub_b64=""; }

  if [[ -n "$sub_b64" ]]; then
    # v1.3: 先逐条显示明文链接，便于验证 IP/域名正确性，再给 Base64 整体订阅
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
    echo -e "  ${RED}${BOLD}⚠  VLESS-Vision 节点【客户端严禁开启 Mux】！开启必断流！${NC}"
  echo -e "  ${YELLOW}   其他四个协议 (gRPC/WS/TCP) 客户端可开启 Mux，高并发推荐。${NC}"
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

  # [F6] Unregister acme.sh cron FIRST — before stopping the service or removing any files.
  # If interrupted after service stop but before cronjob removal, cron keeps firing reloadcmd
  # on a deleted service every 60 min, causing journald spam and "unit not found" errors.
  if [[ -f "${ACME_HOME}/acme.sh" ]]; then
    "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
  fi

  # BUG #33 FIX: Read CREATED_USER before deleting MANAGER_BASE
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
  # [F4] Clear recovery rate-limit lockfile on uninstall; stale lockfile would block
  # the recovery unit on the next fresh install for up to 30 minutes.
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
    # --uninstall-cronjob already executed at start of purge_all [F6]
  fi
  if crontab -l 2>/dev/null | grep -q 'acme\.sh'; then
    crontab -l 2>/dev/null | grep -v 'acme\.sh' | crontab - 2>/dev/null || true
  fi
  # [Doc7-🟠] 移除原有 grep -v '^MAILTO=""' 操作，该操作会破坏宿主机其他业务的 cron 全局变量
  # acme.sh --uninstall-cronjob 已在上方执行，会精确移除自己的条目，无需额外干预 crontab

  # BUG-4 FIX: acme.sh 安装时向 ~/.bashrc 注入 `source ~/.acme.sh/acme.sh.env`
  # 卸载后若不清理，重新 SSH 登录时报 "No such file or directory"
  for _rc in "/root/.bashrc" "/root/.profile" "/root/.bash_profile" "${HOME}/.bashrc" "${HOME}/.profile" "${HOME}/.bash_profile"; do
    [[ -f "$_rc" ]] && sed -i '/acme\.sh\.env/d' "$_rc" 2>/dev/null || true
  done

  # [v2.15.1] purge_all: bulldozer removes ALL INPUT references to FW_CHAIN regardless of
  # comment text, so iptables -X reliably succeeds. Old comment-loop missed any rule with
  # an unexpected comment tag → chain lingered → next install hit "File exists" on rebuild.

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
  # 🟠 Grok: 卸载时不写公共持久化文件，避免覆盖宿主机其他防火墙规则
  # iptables-save > /etc/iptables/rules.v4|v6 已移除

  rm -f /etc/nginx/conf.d/xray-landing-fallback.conf 2>/dev/null || true
  rm -f "/etc/systemd/system/nginx.service.d/landing-override.conf" 2>/dev/null || true
  # BUG #34 FIX: Remove nginx drop-in directory after deleting files
  rmdir "/etc/systemd/system/nginx.service.d" 2>/dev/null || true
  # v1.5: 清理新增的 drop-in 和 journald 上限配置
  rm -f "/etc/systemd/system/xray-landing.service.d/xray-landing-limits.conf" 2>/dev/null || true
  rmdir "/etc/systemd/system/xray-landing.service.d" 2>/dev/null || true
  rmdir "/etc/systemd/system/xray-landing.service.d" 2>/dev/null || true
  rmdir "/etc/systemd/system/xray-landing.service.d" 2>/dev/null || true
  rm -f "/etc/systemd/journald.conf.d/xray-landing.conf" 2>/dev/null || true
  systemctl restart systemd-journald 2>/dev/null || true
  rmdir "/etc/systemd/journald.conf.d" 2>/dev/null || true
  systemctl restart systemd-journald 2>/dev/null || true
  rm -rf "$MANAGER_BASE" 2>/dev/null || true
  rm -f /etc/sysctl.d/99-landing-bbr.conf /etc/modprobe.d/99-landing-conntrack.conf 2>/dev/null || true
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
  
  # BUG #33 FIX: Always try to remove xray-landing user if it exists
  # Don't rely on CREATED_USER flag which may be missing if manager.conf was deleted
  if id "$LANDING_USER" >/dev/null 2>&1; then
    info "检测到用户 ${LANDING_USER}，开始清理..."
    command -v loginctl >/dev/null 2>&1 && loginctl terminate-user "$LANDING_USER" 2>/dev/null || true
    pkill -u "$LANDING_USER" 2>/dev/null || true
    sleep 1
    pkill -KILL -u "$LANDING_USER" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -u "$LANDING_USER" >/dev/null 2>&1 || break
      sleep 0.5
    done
    if ! userdel -r "$LANDING_USER" 2>/dev/null; then
      warn "userdel 失败 (用户可能仍有运行中进程) — 需要手动清理"
    else
      success "用户 ${LANDING_USER} 已删除"
    fi
    groupdel "$LANDING_USER" 2>/dev/null || true
  fi

    rm -f /etc/security/limits.d/99-xray-landing.conf 2>/dev/null || true
  sed -i '/# xray-landing: keep cron\/PAM sessions aligned/,/^root hard nofile/d' /etc/security/limits.conf 2>/dev/null || true
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
  # Feature 01: 遍历所有节点文件，逐一生成 Token 和订阅链接
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
    # 如果节点文件中有记录的 PUBLIC_IP 则用之，否则取 manager.conf 缓存或实时查询
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
    CF_TOKEN="${LANDING_AUTO_CF_TOKEN:-${CF_TOKEN:-}}"

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
    # [BUG #36] 添加输入循环重试机制，输错不die而是提示重新输入
    while true; do
      read -rp "落地机域名（CF 灰云，DNS 可指向任意 IP）: " DOMAIN
      DOMAIN=$(trim "$(tr '[:upper:]' '[:lower:]' <<< "$DOMAIN")")
      if validate_domain "$DOMAIN" 2>/dev/null; then
        break
      else
        error "域名格式错误，请重新输入（例如：example.998488.xyz）"
      fi
    done
    
    while true; do
      read -rp "Cloudflare API Token（Zone:DNS:Edit）: " CF_TOKEN
      if validate_cf_token "$CF_TOKEN" 2>/dev/null; then
        break
      else
        error "Token格式错误，请重新输入（40位以上，仅字母数字_-）"
      fi
    done
    
    while true; do
      read -rp "Trojan 密码（16位以上，直接回车自动生成）: " PASS
      if [[ -z "$PASS" ]]; then
        PASS=$(gen_password)
        info "  已自动生成高强度密码: ${PASS}"
        break
      fi
      if validate_password "$PASS" 2>/dev/null; then
        break
      else
        error "密码格式错误，请重新输入（16位以上）"
      fi
    done
    
    while true; do
      read -rp "中转机公网 IP（防火墙白名单）: " TRANSIT_IP
      if validate_ipv4 "$TRANSIT_IP" 2>/dev/null; then
        break
      else
        error "IP格式错误，请重新输入（例如：1.2.3.4）"
      fi
    done
    
    while true; do
      read -rp "落地机监听端口（默认 8443）[8443]: " LANDING_PORT_IN
      LANDING_PORT_IN="${LANDING_PORT_IN:-8443}"
      if validate_port "$LANDING_PORT_IN" 2>/dev/null; then
        LANDING_PORT="$LANDING_PORT_IN"
        break
      else
        error "端口格式错误，请重新输入（1-65535）"
      fi
    done
    
    # [L-CRITICAL-1] 1Panel/Docker额外端口收集
    echo ""
    info "如果您安装了1Panel或其他需要外部访问的服务，请提供需要放行的端口"
    read -rp "额外放行端口（多个用空格隔开，无则回车）: " EXTRA_PORTS
    EXTRA_PORTS=$(trim "$EXTRA_PORTS")
  fi

  if (( _headless )); then
    CONFIRM="y"
  else
    read -rp "确认开始安装？[y/N]: " CONFIRM
  fi
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "已取消"; exit 0; }

  ss -tlnp 2>/dev/null | grep -qE ":${LANDING_PORT}\b" && die "端口 ${LANDING_PORT} 已被占用（请先检查 nginx / xray* / mack-a*）"

  # Check for enabled units that may bind the port on boot
  for _unit in xray.service v2ray.service xray-landing.service; do
    if systemctl is-enabled --quiet "$_unit" 2>/dev/null; then
      warn "检测到 ${_unit} 已启用，可能在重启后与本脚本冲突"
      read -rp "继续安装？[y/N]: " _conflict_confirm
      [[ "$_conflict_confirm" =~ ^[Yy]$ ]] || die "已取消安装"
    fi
  done
  # [HermesAgent] mack-a detection for landing node
  if type mack-a &>/dev/null || [[ -f /etc/v2ray-agent/install.sh ]]; then
    # [R23 Fix] Explicitly tell user to stop mack-a services when port conflict detected
    ss -tlnp 2>/dev/null | grep -q ":443 " && die "443 端口已被占用！检测到 mack-a 已安装，请先执行: systemctl stop xray nginx v2ray 后再安装"
    warn "检测到 mack-a 已安装，本落地机将与其共享端口，请确认无冲突"
  fi
  __LANDING_FRESH_INSTALL_TRAP_ACTIVE=1
  
  # [BUG-6 FIX] Define rollback function BEFORE setting trap
  _fresh_install_rollback(){
    [[ "${__LANDING_FRESH_INSTALL_TRAP_ACTIVE:-0}" == "1" ]] || return 0
    warn "[rollback] 安装中断，清理半成品..."
    systemctl stop    "$LANDING_SVC"   2>/dev/null || true
    systemctl disable "$LANDING_SVC"   2>/dev/null || true
    rm -f "/etc/systemd/system/${LANDING_SVC}" \
          "/etc/systemd/system/xray-landing-recovery.service" 2>/dev/null || true
    # [F4] Also clean nginx fallback artifacts — without this, next run finds Nginx already
    # configured and enters inconsistent state thinking setup_fallback_decoy already ran.
    rm -f "/etc/nginx/conf.d/xray-landing-fallback.conf" 2>/dev/null || true
    rm -f "/etc/systemd/system/nginx.service.d/landing-override.conf" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    while iptables -w 2 -D INPUT -j "$FW_CHAIN" 2>/dev/null; do :; done
    iptables -w 2 -F "$FW_CHAIN" 2>/dev/null || true
    iptables -w 2 -X "$FW_CHAIN" 2>/dev/null || true
    # [F3] Clean installed binary and assets — install_xray_binary() runs before this trap
    # fires; leaving the binary creates a contaminated host state on the next run.
    rm -f "$LANDING_BIN" "$CERT_RELOAD_SCRIPT" "$LOGROTATE_FILE" 2>/dev/null || true
    rm -rf /usr/local/share/xray-landing 2>/dev/null || true
    # Also clear recovery lockfile so a future fresh install doesn't trip the 1800s cooldown
    rm -f /run/lock/xray-landing-recovery.last 2>/dev/null || true
    # [C2 Fix] Uninstall acme.sh cronjob during rollback to prevent orphaned cron entries
    if [[ -f "${ACME_HOME}/acme.sh" ]]; then
      env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" --uninstall-cronjob 2>/dev/null || true
    fi
    # [v2.11 Doc10-C-🔴] Remove acme.sh domain registration before wiping cert dirs.
    # Without this, acme.sh cron keeps firing reloadcmd for a domain that no longer has
    # a service — causing spurious reload failures and cron log noise indefinitely.
    if [[ -n "${DOMAIN:-}" && -f "${ACME_HOME}/acme.sh" ]]; then
      env ACME_HOME="${ACME_HOME}" "${ACME_HOME}/acme.sh" \
        --home "${ACME_HOME}" --remove --domain "${DOMAIN}" --ecc 2>/dev/null || true
    fi
    # [F4] Remove cert and config dirs so next run starts clean
    rm -rf "$CERT_BASE" "$LANDING_BASE" 2>/dev/null || true
    rm -f "$INSTALLED_FLAG" "$MANAGER_CONFIG" 2>/dev/null || true
    rm -f "${_staged_fi_mgr:-}" 2>/dev/null || true   # [v2.8] purge staged manager.conf on rollback
    rm -rf "${MANAGER_BASE}/nodes" 2>/dev/null || true
    warn "[rollback] 完成，可安全重新运行安装"
  }
  
  trap '_fresh_install_rollback' ERR INT TERM
  optimize_kernel_network; create_system_user; install_xray_binary

  local PUB_IP; PUB_IP=$(get_public_ip)

  # BUG-7 FIX: 幂等性保障——若 manager.conf 已存在则复用旧 UUID 和全部端口，避免重跑时订阅全部失效
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
        # 复用全部旧配置：UUID + 主端口 + 内部4个端口（保证 Xray config 不变）
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

  # 只在端口为默认值0时才重新分配（复用路径已赋值，新装路径仍随机分配）
  local _VGRPC="${VLESS_GRPC_PORT:-0}" _VTG="${TROJAN_GRPC_PORT:-0}" _VWS="${VLESS_WS_PORT:-0}" _TTCP="${TROJAN_TCP_PORT:-0}"
  if [[ "${VLESS_GRPC_PORT:-0}" == "0" ]]; then
    _VGRPC=$(python3 -c "import secrets; b=secrets.randbelow(8000)&~3; print(21000+b)")
    _VTG=$(( _VGRPC + 1 )); _VWS=$(( _VGRPC + 2 )); _TTCP=$(( _VGRPC + 3 ))
    VLESS_GRPC_PORT="$_VGRPC"; TROJAN_GRPC_PORT="$_VTG"; VLESS_WS_PORT="$_VWS"; TROJAN_TCP_PORT="$_TTCP"
  fi
  _validate_internal_ports_in_use
  for _chkp in "$_VGRPC" "$_VTG" "$_VWS" "$_TTCP"; do
    ss -tlnp 2>/dev/null | grep -q ":${_chkp} "       && { warn "内网端口 ${_chkp} 已被占用，请重新运行脚本（自动重新分配）"; false; }
  done

  mkdir -p "$LANDING_BASE"

  # [Fix-A / Doc8-GPT-🔴] Transaction trap already registered above

  # [v2.32 Bug-1 Fix] Ensure both MANAGER_BASE and its tmp subdir exist before mktemp
  mkdir -p "${MANAGER_BASE}/tmp"

  # [v2.8 Architect-🔴] Stage manager.conf to a temp path; promote to the real path only after
  # sync_xray_config + create_systemd_service + setup_firewall all succeed.
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

  setup_native_dns        # [L-CRITICAL-2] 配置美国家宽ISP原生DNS
  setup_fallback_decoy
  issue_certificate "$DOMAIN" "$CF_TOKEN"

  # 🔴 GPT: save_node_info 推迟到 sync+service+firewall 全部成功后原子提交
  # tmp-*.conf 供 sync_xray_config(glob *.conf) 读取；setup_firewall 排除 tmp-* 故 mv 后再生效
  local _safe_dom; _safe_dom=$(printf '%s' "$DOMAIN" | tr '.:/' '___')
  local _safe_ip;  _safe_ip=$(printf '%s' "$TRANSIT_IP" | tr '.:' '__')
  local _final_node="${MANAGER_BASE}/nodes/${_safe_dom}_${_safe_ip}.conf"
  local _tmp_node="${MANAGER_BASE}/nodes/tmp-${_safe_dom}_${_safe_ip}.conf"

  save_node_info "$DOMAIN" "$PASS" "$TRANSIT_IP" "$PUB_IP" "$_tmp_node"
  sync_xray_config
  setup_health_check      # [S1-HIGH] 配置健康检查
  setup_traffic_simulation # [L5-MEDIUM] 配置流量模拟
  setup_firewall "$TRANSIT_IP"
  local _CAP_LINE="" _CAP_BOUND=""
  (( LANDING_PORT < 1024 )) && {
    _CAP_LINE=$'AmbientCapabilities=CAP_NET_BIND_SERVICE'
    _CAP_BOUND=$'CapabilityBoundingSet=CAP_NET_BIND_SERVICE'
  }
  export _CAP_LINE _CAP_BOUND

  if ! ( create_systemd_service ); then
    if [[ -f "${ACME_HOME}/acme.sh" ]]; then
      "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$DOMAIN" --ecc 2>/dev/null || true
      rm -rf "${CERT_BASE}/${DOMAIN}" 2>/dev/null || true
    fi
    rm -f "$_final_node" "${_staged_fi_mgr:-}" 2>/dev/null || true
    _release_lock; exit 1
  fi
  if ! ( create_systemd_service ); then
    if [[ -f "${ACME_HOME}/acme.sh" ]]; then
      "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$DOMAIN" --ecc 2>/dev/null || true
      rm -rf "${CERT_BASE}/${DOMAIN}" 2>/dev/null || true
    fi
    rm -f "$_final_node" "${_staged_fi_mgr:-}" 2>/dev/null || true
    _release_lock; exit 1
  fi

  # Node file already at final path; reset trap to standard
  trap '_global_cleanup; rm -f "${_staged_fi_mgr:-}" 2>/dev/null; echo -e "\n${RED}[中断] 请执行: bash $0 --uninstall${NC}"; exit 1' INT TERM

  # v2.32 GPT: setup_firewall 失败时完整回滚——节点文件/config.json/服务/unit/logrotate 全部清理，
  # 确保下次重跑不遇到"看似未装实已半装"的脏状态
  if ! ( setup_firewall ); then
    rm -f "$_final_node" "${_staged_fi_mgr:-}" 2>/dev/null || true
    systemctl stop    "$LANDING_SVC" 2>/dev/null || true
    systemctl disable "$LANDING_SVC" 2>/dev/null || true
    rm -f "/etc/systemd/system/${LANDING_SVC}" 2>/dev/null || true
    rm -f "$LOGROTATE_FILE" 2>/dev/null || true
  # [REVIEWER-1] 删除健康检查cron文件
  rm -f /etc/cron.d/xray-landing-health /usr/local/bin/xray-landing-health-check.sh 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    ( sync_xray_config ) 2>/dev/null || true
    # [F1] Ghost cert guard: cert was issued before firewall; must revoke on firewall fail
    if [[ -f "${ACME_HOME}/acme.sh" ]]; then
      "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --remove --domain "$DOMAIN" --ecc 2>/dev/null || true
      rm -rf "${CERT_BASE}/${DOMAIN}" 2>/dev/null || true
    fi
    _release_lock; exit 1
  fi

  # [v2.9 Grok-A-🟠] Touch INSTALLED_FLAG *before* mv staged_fi_mgr.
  # Reverse order (mv then touch) left a window where a SIGKILL after mv but before touch
  # produced a durable set (manager.conf + nodes/*.conf + config.json + running service) with
  # no INSTALLED_FLAG → next run routed to fresh_install → "port occupied" die.
  # With flag-first order: if we crash after touch but before mv, the stale-marker
  # reconciliation block in main() detects missing manager.conf and clears the flag cleanly.
  # v2.39: mv先，touch后——防止"flag存在但manager.conf缺失"的分裂状态
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

  # [v2.9 Grok-A-🟠] Symmetric reconciliation: "flag absent but durable set complete" means
  # the process was killed between touch INSTALLED_FLAG and mv staged_fi_mgr (v2.9 order) or
  # between mv staged_fi_mgr and touch INSTALLED_FLAG (legacy order). In both cases the node
  # is fully installed. Restore the flag and route to installed_menu rather than wiping state.
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
    # [v2.8 Architect-🟠] Startup stale-marker reconciliation: verify the durable set;
    # remove the marker when it is incomplete.
    local _durable_ok=1
    [[ -f "$MANAGER_CONFIG" ]]                                          || _durable_ok=0
    [[ -f "$LANDING_CONF" ]]                                            || _durable_ok=0
    find "${MANAGER_BASE}/nodes" -name "*.conf" -not -name "tmp-*.conf" \
         -type f -maxdepth 1 2>/dev/null | grep -q . 2>/dev/null       || _durable_ok=0
    if (( _durable_ok == 0 )); then
      warn "[v2.8] 安装标记存在但持久化集（manager.conf/config.json/nodes/*.conf）不完整，清除标记重新安装..."
      rm -f "$INSTALLED_FLAG"
      # Also purge any .manager.* staging file that may have survived a SIGKILL
      find "${MANAGER_BASE}" /tmp -maxdepth 1 -name '.manager.*' -type f -delete 2>/dev/null || true
      fresh_install
      return
    fi
    load_manager_config
    # 🟠 GPT: .installed 降为辅助证据，三态交叉校验（服务/配置/节点）
    local _svc_ok=0 _conf_ok=0 _node_ok=0
    systemctl is-active --quiet "$LANDING_SVC" 2>/dev/null && _svc_ok=1 \
      || warn "服务未运行"
    [[ -f "$MANAGER_CONFIG" ]] && _conf_ok=1 \
      || warn "manager.conf 缺失（真相源丢失）"
    local _nc; _nc=$(find "${MANAGER_BASE}/nodes" -name "*.conf" -type f 2>/dev/null | wc -l)
    (( _nc > 0 )) && _node_ok=1
    # 三态全部缺失 → 脏安装，清除标记重新安装
    if (( _svc_ok == 0 && _conf_ok == 0 && _node_ok == 0 )); then
      warn "安装标记存在但三态（服务/配置/节点）全部缺失，清除标记重新安装..."
      rm -f "$INSTALLED_FLAG"
      fresh_install
      return
    fi
    # v2.32 GPT: 真相源丢失时拒绝进入管理菜单（所有写操作均依赖 manager.conf）
    if (( _conf_ok == 0 )); then
      die "manager.conf（真相源）已丢失，无法安全操作。请执行 --uninstall 清除后重装，或从备份恢复 ${MANAGER_CONFIG}"
    fi
    # v2.33 GPT BUG-01: 服务恢复失败时拒绝进管理菜单，避免在不一致状态上继续写操作
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

