# v5.22 变更日志 (2026-05-03)

## 主笔AI: NAS-2
## 审查AI: 多位审查者

---

## 🔴 CRITICAL 修复

### [C-L-1] 落地机IPv6强制禁用
**问题**: v5.21恢复了IPv6动态探测，导致双栈VPS保留IPv6，但中转机纯IPv4无法连接
**影响**: 链式代理断链（中转机IPv4 ↔ 落地机IPv6不通）
**修复**: 删除双栈保留逻辑，强制禁用IPv6
```bash
# 修复位置: optimize_kernel_network()
# 删除行724-737的双栈逻辑
# 新增强制禁用IPv6代码
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
```

### [C-L-2] Xray出站策略修复
**问题**: v5.21将domainStrategy改为UseIP，双栈环境会优先IPv6
**影响**: 链式代理中转机纯IPv4无法连接落地机IPv6出站
**修复**: 改回UseIPv4
```json
// 修复位置: sync_xray_config() 行1592
"settings": {"domainStrategy": "UseIPv4"}
```

### [C-T-1] 中转机防火墙规则顺序修复
**问题**: v5.21使用-I 1插入hashlimit规则到链首，导致规则在lo/SSH之前
**影响**: 规则顺序混乱，可能影响防火墙逻辑
**修复**: 改为-A追加，确保规则顺序正确
```bash
# 修复位置: setup_firewall_transit() 行1194
# 正确顺序: lo → SSH → INVALID → ESTABLISHED → ICMP → UDP DROP → connlimit → hashlimit ACCEPT → 443 DROP → 最终DROP
iptables -w 2 -A "$FW_TMP" -p tcp --dport "$LISTEN_PORT" \
  -m hashlimit --hashlimit-upto 8000/sec ... -j ACCEPT
```

---

## 🟢 已确认正确（无需修改）

### [C-L-3] 1Panel端口持久化
**状态**: v5.21已修复
**位置**: _persist_iptables() 行2130-2138
**验证**: EXTRA_PORTS已正确写入_transit_rules变量

### [C-T-2] 中转机健康检查
**状态**: v5.18已实现
**位置**: setup_health_check_transit() 行970
**验证**: 函数完整，每5分钟检测Nginx状态

---

## 📊 修复统计

- **CRITICAL修复**: 3项
- **已确认正确**: 2项
- **版本号统一**: v5.20 → v5.22
- **架构不变**: 链式代理（中转机SNI盲传 + 落地机Xray多协议）

---

## ⚠️ 重要说明

**为什么跳过v5.21？**
v5.21文件名与内部VERSION不一致（文件名v5.21，内部v5.20），且存在致命架构冲突。v5.22直接修复所有问题。

**链式代理架构要求**:
- 中转机: 纯IPv4（CN2 GIA线路特性）
- 落地机: 必须禁用IPv6，确保与中转机兼容
- Xray出站: 必须UseIPv4，不能UseIP

---

## 🎯 测试建议

1. **中转机测试**:
   ```bash
   bash install_transit_v5.22.sh
   iptables -L TRANSIT-MANAGER -n -v --line-numbers
   # 验证规则顺序: hashlimit ACCEPT在DROP之前
   ```

2. **落地机测试**:
   ```bash
   bash install_landing_v5.22.sh
   sysctl net.ipv6.conf.all.disable_ipv6
   # 应输出: net.ipv6.conf.all.disable_ipv6 = 1
   ```

3. **链式代理测试**:
   ```bash
   # 客户端 → 中转机 → 落地机 → 目标网站
   # 验证连接通畅，无IPv6侧漏
   ```

---

## 📝 下一步

- 审查AI复审v5.22
- 生产环境测试
- 如无问题，v5.22作为稳定版本发布
