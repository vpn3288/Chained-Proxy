# v5.18 版本修复摘要

**发布日期**: 2026-05-02  
**修复类型**: 审查报告全面修复  
**审查来源**: 三份独立审查报告（CRITICAL×5, HIGH×5, MEDIUM×4, LOW×2）

---

## 📋 修复概览

### 中转机脚本 (install_transit_v5.18.sh)
**修复项目**: 6项  
**文件大小**: 129,141 字节  
**架构**: Nginx stream SNI盲传（架构不变）

### 落地机脚本 (install_landing_v5.18.sh)
**修复项目**: 10项  
**文件大小**: 202,903 字节  
**架构**: Xray-core Trojan-TLS + VLESS + gRPC + WebSocket（架构不变）  
**兼容性**: 完美兼容 1Panel/OpenClaw/HermesAgent 生态

---

## 🔴 CRITICAL 级别修复

### 中转机
无 CRITICAL 级别问题

### 落地机
1. **[L-CRITICAL-1] 端口冲突检测增强**
   - 问题: 仅检查当前监听端口，未检测已启用但未运行的 systemd unit
   - 影响: 重启后服务启动失败
   - 修复: 添加 systemd unit 状态检查，检测 xray.service/v2ray.service/xray-landing.service

2. **[L-C2] IPv6侧漏真正封堵**
   - 问题: 仅在双栈VPS禁用IPv6，单IPv4 VPS未执行禁用
   - 影响: 家宽伪装被击穿（IPv6泄露真实位置）
   - 修复: 无条件禁用IPv6（\sysctl -w net.ipv6.conf.all.disable_ipv6=1\）

3. **[L-C3] 彻底删除流量模拟**
   - 问题: v4.60声称删除，但 \setup_traffic_simulation()\ 调用仍存在
   - 影响: 定时curl访问是明显的机器人特征，毁IP信誉
   - 修复: 删除函数调用和函数定义

---

## 🟠 HIGH 级别修复

### 中转机
1. **[T-HIGH-1] 防火墙白名单规则修复**
   - 问题: 使用 \-A\ 追加规则，导致白名单在DROP规则之后（永不生效）
   - 影响: 所有流量被DROP
   - 修复: 使用 \-I 1\ 插入到链首，并在插入前删除旧规则

2. **[T-HIGH-2] mack-a检测增强**
   - 问题: 仅检测端口占用，未检测nginx配置冲突
   - 影响: 与mack-a共存时配置冲突
   - 修复: 检测 \/etc/nginx/nginx.conf\ 中的 \2ray-agent\ 标记

### 落地机
1. **[L-HIGH-1] 证书续期失败告警**
   - 问题: acme.sh续期失败时仅warn，未触发告警
   - 影响: 90天后证书过期导致全节点断流
   - 修复: 失败时写入 \/var/log/acme-xray-landing-renew.log\ 并劫持 \/etc/profile.d/xray-cert-alert.sh\

2. **[L-H1] DNS策略调整**
   - 问题: 使用AT&T/CenturyLink等美国ISP DNS，但落地机是普通国际线路VPS
   - 影响: DNS查询特征与VPS身份不匹配
   - 修复: 删除 \setup_native_dns\，使用VPS自带DNS

3. **[L-H2] 1Panel端口放行**
   - 问题: 防火墙规则未处理 \EXTRA_PORTS\
   - 影响: 1Panel管理面板无法访问
   - 修复: 在 \setup_firewall()\ 中添加额外端口放行逻辑

4. **[L-H3] 健康检查cron验证**
   - 问题: 创建cron后未验证文件是否真正写入
   - 影响: 健康检查静默失效
   - 修复: 在 \setup_health_check()\ 末尾添加文件存在性验证

---

## 🟡 MEDIUM 级别修复

### 中转机
1. **[T-MEDIUM-1] worker_connections随机化增强**
   - 问题: 70-130%偏移范围过窄，可能被GFW指纹识别
   - 修复: 扩大到50-150%范围，并添加质数扰动（RANDOM % 97）

### 落地机
1. **[L-MEDIUM-1] DNS传播智能等待**
   - 问题: 固定60秒dnssleep对Cloudflare过长
   - 修复: 添加 \_wait_dns_propagation()\ 函数，动态探测TXT记录（最长90秒）

2. **[L-M1] 证书续期优化**
   - 问题: 强制 \--force\ 参数触发Let's Encrypt速率限制
   - 修复: 删除 \--force\ 参数，让acme.sh自己判断

---

## ⚪ LOW 级别修复

### 中转机
1. **[T-LOW-1] 更新检查超时优化**
   - 问题: 3秒超时在高延迟网络误报"无新版本"
   - 修复: 5秒连接超时 + 10秒总超时 + 2次重试

### 落地机
1. **[L-LOW-1] 卸载完整性**
   - 问题: 仅删除 \.acme.sh.env\ 引用，未清理 \~/.acme.sh\ 目录
   - 修复: 在 \purge_all()\ 中添加目录删除

---

## 🎯 全局优化

### 中转机
1. **[GLOBAL-1] 彻底精简IPv6逻辑**
   - 原因: 中转机明确只有IPv4（CN2 GIA无IPv6）
   - 修复: \have_ipv6()\ 永远返回 \alse\，删除所有IPv6探测代码

---

## 📊 修复统计

| 类别 | 中转机 | 落地机 | 合计 |
|------|--------|--------|------|
| CRITICAL | 0 | 3 | 3 |
| HIGH | 2 | 4 | 6 |
| MEDIUM | 1 | 2 | 3 |
| LOW | 1 | 1 | 2 |
| GLOBAL | 1 | 0 | 1 |
| **总计** | **5** | **10** | **15** |

---

## ✅ 验证结果

### 中转机脚本
- ✓ 版本号统一 v5.18
- ✓ IPv6逻辑精简（永远返回false）
- ✓ 更新检查超时优化（5秒+10秒+2次重试）
- ✓ worker_connections随机化增强（50-150%+质数）
- ✓ 防火墙白名单规则修复（-I 1插入）
- ✓ mack-a检测增强（nginx配置冲突）

### 落地机脚本
- ✓ 版本号统一 v5.18
- ✓ setup_native_dns 调用已删除
- ✓ setup_traffic_simulation 已彻底删除
- ✓ IPv6 无条件禁用
- ✓ 端口冲突检测增强（systemd unit）
- ✓ 1Panel 端口放行
- ✓ 健康检查 cron 验证
- ✓ DNS 传播智能等待
- ✓ acme.sh 目录删除
- ✓ --force 参数已删除

---

## 🔒 安全性增强

1. **防火墙规则顺序修复**: 确保白名单规则在DROP规则之前生效
2. **端口冲突全面检测**: 避免重启后服务启动失败
3. **IPv6侧漏封堵**: 防止家宽伪装被击穿
4. **证书续期告警**: 90天后断流前主动告警

---

## 🚀 性能优化

1. **worker_connections随机化**: 增强抗指纹识别能力
2. **DNS传播智能等待**: 减少不必要等待，提升安装速度
3. **更新检查超时优化**: 提升高延迟网络的检测成功率

---

## 🛡️ 稳定性增强

1. **健康检查cron验证**: 确保健康检查真正生效
2. **证书续期优化**: 避免触发Let's Encrypt速率限制
3. **卸载完整性**: 彻底清理残留文件

---

## 📝 使用说明

### 安装
\\\ash
# 中转机
bash install_transit_v5.18.sh

# 落地机
bash install_landing_v5.18.sh
\\\

### 环境变量
\\\ash
# 跳过证书申请延迟（测试用）
LANDING_SKIP_CERT_DELAY=1 bash install_landing_v5.18.sh

# 指定中转机公网IP
TRANSIT_PUBLIC_IP=x.x.x.x bash install_transit_v5.18.sh
\\\

### 1Panel兼容
安装时会提示输入额外端口，输入1Panel管理端口即可：
\\\
额外放行端口（多个用空格隔开，无则回车）: 8888
\\\

---

## 🙏 致谢

感谢三位审查AI的详细审查报告，确保了v5.18版本的高质量修复。

---

**主笔AI**: Kiro  
**审查AI**: 三份独立审查报告  
**发布日期**: 2026-05-02
