# CHANGELOG v5.24 - 落地机脚本优化

**发布日期**: 2026-05-03  
**主笔AI**: NAS-2（资深老教授级代码审查专家）  
**审查AI**: 提供详细审查报告

---

## 🎯 核心修复

### [CRITICAL-1] 删除证书申请延迟功能
**问题**: v5.23引入的30-90分钟证书延迟属于过度设计  
**原因**: DNS-01验证通过Cloudflare API进行，GFW仅能看到加密HTTPS请求，无探测风险  
**修复**: 彻底删除delay_minutes、delay_seconds及相关倒计时逻辑，恢复直接申请证书  
**影响**: 大幅提升安装体验，符合"小白友好"原则

### [HIGH-1] Xray出站策略修复
**问题**: v5.23使用`domainStrategy: "UseIPv4"`会强制重新DNS解析  
**原因**: 链式代理架构下，落地机接收的是中转机已解析的IP地址  
**修复**: 改为`domainStrategy: "AsIs"`，直接使用传入地址  
**影响**: 降低延迟，避免DNS泄露风险

### [MEDIUM-1] 端口输入验证增强
**问题**: v5.23的1Panel端口输入无格式校验  
**修复**: 添加端口范围验证（1-65535），输入错误可重试  
**代码**:
```bash
while true; do
  read -rp "需要放行的额外端口（多个用空格隔开，无则直接回车）: " EXTRA_PORTS
  EXTRA_PORTS=$(trim "$EXTRA_PORTS")
  
  # 端口格式验证
  if [[ -z "$EXTRA_PORTS" ]]; then
    break  # 空输入合法
  fi
  
  local _invalid=0
  for _port in $EXTRA_PORTS; do
    if ! [[ "$_port" =~ ^[0-9]+$ ]] || (( _port < 1 || _port > 65535 )); then
      warn "无效端口: $_port（必须是 1-65535 之间的数字）"
      _invalid=1
      break
    fi
  done
  
  if (( _invalid == 0 )); then
    break  # 所有端口合法
  fi
  echo "请重新输入..."
done
```

---

## 📝 技术细节

### Xray配置变更
```json
// v5.23（错误）
"outbounds": [
  {
    "protocol": "freedom",
    "tag": "direct",
    "settings": {"domainStrategy": "UseIPv4"}
  }
]

// v5.24（正确）
"outbounds": [
  {
    "protocol": "freedom",
    "tag": "direct",
    "settings": {"domainStrategy": "AsIs"}
  }
]
```

### 证书申请流程简化
```bash
# v5.23（复杂）
local delay_minutes=$((30 + RANDOM % 61))
local delay_seconds=$((delay_minutes * 60))
# ... 45行倒计时逻辑 ...
info "申请证书（DNS-01/Cloudflare）: ${domain} ..."

# v5.24（简洁）
info "申请证书（DNS-01/Cloudflare）: ${domain} ..."
```

---

## 🔄 版本对比

| 项目 | v5.23 | v5.24 |
|------|-------|-------|
| 证书延迟 | 30-90分钟随机 | 立即申请 |
| Xray出站策略 | UseIPv4 | AsIs |
| 端口输入验证 | 无 | 有（1-65535） |
| 安装体验 | 复杂 | 简洁 |

---

## ⚠️ 升级建议

- **新部署**: 直接使用v5.24
- **已部署v5.23**: 无需升级（证书已申请，出站策略影响较小）
- **如需升级**: 重新运行脚本，选择"重新配置"

---

## 🎓 设计原则

1. **小白友好**: 删除不必要的等待和复杂逻辑
2. **安全第一**: DNS-01验证本身已足够安全，无需额外伪装
3. **架构优先**: 链式代理架构决定了AsIs是最优策略
4. **输入验证**: 防止用户输入错误导致防火墙配置失败

---

**下一步**: 等待审查AI复审v5.24
