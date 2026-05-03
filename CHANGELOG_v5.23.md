# CHANGELOG v5.23

**发布日期**: 2025-05-03  
**主笔AI**: NAS-2 (落地机) + N5105 (中转机)  
**版本类型**: 专项优化版本 - 修复v5.22遗留问题

---

## 📋 版本概述

v5.23是针对v5.22的专项优化版本，由审查AI发现的4个CRITICAL问题和3个HIGH问题驱动。本版本重点修复：
1. 承诺未兑现的功能（证书延迟、健康检查）
2. 死代码清理（流量模拟、IPv6残留）
3. 用户体验优化（1Panel端口提示、防火墙规则验证）

---

## 🔴 CRITICAL 修复

### [L-C1] 删除流量模拟死代码
**问题**: `setup_background_traffic()` 函数从未被调用，占用31行代码  
**修复**: 删除整个函数及相关注释  
**影响**: 代码更简洁，减少维护负担  
**文件**: `install_landing_v5.23.sh` (行3761-3791删除)

### [L-C2] 证书申请延迟功能实现
**问题**: v5.18承诺的"30-90分钟随机延迟"功能未实现  
**修复**: 在 `issue_certificate()` 函数中添加延迟逻辑：
- 随机延迟30-90分钟（防止批量申请被CF限流）
- 支持Ctrl+C跳过延迟（用户可选）
- 显示倒计时和跳过提示  
**影响**: 批量部署时避免证书申请失败  
**文件**: `install_landing_v5.23.sh` (行1199新增)

```bash
# 延迟逻辑示例
local delay_minutes=$((30 + RANDOM % 61))  # 30-90分钟
echo "证书申请将在 ${delay_minutes} 分钟后开始（按Ctrl+C跳过）..."
trap 'echo "已跳过延迟"; return 0' INT
sleep $((delay_minutes * 60)) &
wait $! 2>/dev/null
trap - INT
```

### [T-C1] 中转机IPv6代码彻底删除
**问题**: 中转机是纯IPv4环境，但残留90+处IPv6代码  
**修复**: 系统性删除所有IPv6相关代码：
- 删除 `FW_CHAIN6` 变量定义
- 删除 `have_ipv6()` 函数
- 删除 `_bulldoze_input_refs6_t()` 函数
- 删除 `setup_firewall_transit()` 中71行ip6tables代码
- 删除 `_persist_iptables()` heredoc中的IPv6块  
**影响**: 代码更清晰，减少104行无用代码  
**文件**: `install_transit_v5.23.sh` (删除104行)

### [T-C2] 健康检查调用确认
**问题**: v4.50承诺的健康检查功能是否真正调用？  
**修复**: 确认 `setup_health_check_transit()` 已在 `fresh_install()` 中调用  
**影响**: 无需修改，功能正常  
**文件**: `install_transit_v5.23.sh` (行1679)

---

## 🟡 HIGH 优先级修复

### [L-H1] IPv6策略确认
**问题**: 审查AI认为落地机应保留IPv6能力  
**用户决策**: 架构要求落地机必须禁用IPv6（中转机纯IPv4，链式代理要求）  
**结论**: v5.22的IPv6强制禁用是**正确的**，不是过度精简  
**影响**: 无需修改，保持v5.22策略  
**文件**: `install_landing_v5.23.sh` (行724-731)

### [L-H2] 1Panel端口交互优化
**问题**: 端口放行提示不够明确，用户可能忽略导致服务无法访问  
**修复**: 添加醒目的黄色边框提示：
- 明确说明1Panel/Docker端口放行的重要性
- 提供示例（1Panel默认10086，Docker容器8080等）
- 强调不填写将导致服务无法访问  
**影响**: 减少用户配置错误  
**文件**: `install_landing_v5.23.sh` (行3497-3507)

```bash
echo -e "${BOLD}${YELLOW}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${YELLOW}  ⚠  1Panel/Docker 端口放行提示${NC}"
echo -e "${YELLOW}     如果您安装了 1Panel、Docker 容器或其他需要外部访问的服务，${NC}"
echo -e "${YELLOW}     请在此处提供需要放行的端口号，否则这些服务将无法访问。${NC}"
echo -e "${YELLOW}     示例：1Panel 默认端口 10086，Docker 容器端口 8080 等${NC}"
echo -e "${BOLD}${YELLOW}══════════════════════════════════════════════════════${NC}"
```

### [T-H1] 防火墙443白名单规则验证
**问题**: 防火墙配置后未验证TCP 443白名单规则是否生效  
**修复**: 在 `setup_firewall_transit()` 末尾添加验证逻辑：
- 检查TCP 443 ACCEPT规则数量（connlimit + hashlimit）
- 检查UDP 443 DROP规则（QUIC封堵）
- TCP规则缺失时直接die（致命错误）
- UDP规则缺失时warn（警告但不阻断）  
**影响**: 及早发现防火墙配置异常  
**文件**: `install_transit_v5.23.sh` (行1197-1213)

```bash
# TCP 443白名单验证
_tcp_accept_count=$(iptables -w 2 -L "$FW_CHAIN" -n -v 2>/dev/null | grep -c "tcp dpt:$LISTEN_PORT.*ACCEPT")
if [[ "$_tcp_accept_count" -ge 1 ]]; then
  success "TCP 443 白名单规则已生效（connlimit + hashlimit）"
else
  die "TCP 443 白名单规则未生效，防火墙配置异常！"
fi

# UDP 443封堵验证
_udp_drop_count=$(iptables -w 2 -L "$FW_CHAIN" -n -v 2>/dev/null | grep -c "udp dpt:$LISTEN_PORT.*DROP")
if [[ "$_udp_drop_count" -ge 1 ]]; then
  success "UDP 443（QUIC）封堵规则已生效"
else
  warn "UDP 443（QUIC）封堵规则未找到，可能存在流量泄露风险"
fi
```

---

## 📊 代码统计

| 文件 | v5.22行数 | v5.23行数 | 变化 |
|------|----------|----------|------|
| install_landing_v5.23.sh | 3852 | 3860 | +8 (证书延迟+1Panel提示-死代码) |
| install_transit_v5.23.sh | 2450 | 2346 | -104 (删除IPv6代码) |
| **总计** | **6302** | **6206** | **-96** |

---

## ✅ 测试建议

### 落地机测试
1. **证书延迟功能**:
   ```bash
   # 测试延迟跳过
   bash install_landing_v5.23.sh
   # 在证书申请延迟时按Ctrl+C，确认可跳过
   ```

2. **1Panel端口放行**:
   ```bash
   # 安装后检查防火墙规则
   iptables -L XRAY-LANDING -n -v | grep "10086"
   ```

### 中转机测试
1. **IPv6代码清理验证**:
   ```bash
   # 确认无IPv6残留
   grep -i "ipv6\|ip6tables" install_transit_v5.23.sh
   # 应该只有注释和变更日志中的历史记录
   ```

2. **防火墙规则验证**:
   ```bash
   # 安装后自动验证
   bash install_transit_v5.23.sh
   # 应该看到 "TCP 443 白名单规则已生效" 和 "UDP 443（QUIC）封堵规则已生效"
   ```

---

## 🔄 升级路径

### 从v5.22升级到v5.23

**落地机**:
```bash
cd /root
wget https://raw.githubusercontent.com/your-repo/main/install_landing_v5.23.sh
bash install_landing_v5.23.sh
```

**中转机**:
```bash
cd /root
wget https://raw.githubusercontent.com/your-repo/main/install_transit_v5.23.sh
bash install_transit_v5.23.sh
```

**注意事项**:
- v5.23是优化版本，不涉及架构变更
- 升级过程中会自动验证防火墙规则
- 1Panel用户需要在升级时重新确认端口放行

---

## 🎯 下一步计划

v5.23完成后，建议进行以下优化（v5.24候选）：

### MEDIUM优先级
- **[BOTH-M1]** 证书续期失败告警机制
- **[L-M1]** TCP窗口根据内存动态调整
- **[T-M1]** 健康检查失败自动重启

### LOW优先级
- **[L-L1]** Nginx配置精简（删除冗余注释）
- **[T-L1]** 防火墙规则注释精简

---

## 📝 变更摘要

| 优先级 | 类型 | 描述 | 文件 |
|--------|------|------|------|
| CRITICAL | 功能补全 | 证书申请延迟（30-90分钟+Ctrl+C跳过） | install_landing_v5.23.sh |
| CRITICAL | 代码清理 | 删除流量模拟死代码（31行） | install_landing_v5.23.sh |
| CRITICAL | 代码清理 | 删除中转机IPv6残留代码（104行） | install_transit_v5.23.sh |
| CRITICAL | 功能确认 | 健康检查调用已存在 | install_transit_v5.23.sh |
| HIGH | 用户体验 | 1Panel端口放行明确提示 | install_landing_v5.23.sh |
| HIGH | 功能增强 | 防火墙443白名单规则验证 | install_transit_v5.23.sh |
| HIGH | 架构确认 | IPv6强制禁用策略保持不变 | install_landing_v5.23.sh |

---

**审查者**: 审查AI (2025-05-03)  
**主笔**: NAS-2 (落地机) + N5105 (中转机)  
**批准**: 徐老师
