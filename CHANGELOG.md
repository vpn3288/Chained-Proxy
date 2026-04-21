# Changelog v3.63 - 欺上瞒下策略完整实现

## 版本信息
- **版本号**: v3.63
- **发布日期**: 2025-01-XX
- **核心目标**: 完善"欺上瞒下"策略的技术实现，提升隐蔽性、安全性和稳定性

## 修复摘要

本次更新完成了 5 项关键修复，全部围绕"欺上瞒下"策略（欺骗 GFW + 欺骗目标网站）：

### ✅ 修复 1: Nginx Fallback 真实网站模拟（隐蔽性 CRITICAL）

**问题**: 
- 当前 Nginx Fallback 返回 444（直接关闭连接），这在流量分析中很容易被识别为代理特征
- 缺少常见网站路径（robots.txt, favicon.ico），不像真实网站

**修复**:
- 修改 `setup_fallback_decoy()` 函数，返回真实 HTTP 响应：
  - 主路径返回 403 "Access Denied"（而不是 444）
  - 添加 `/robots.txt` 路径，返回标准 robots.txt 内容
  - 添加 `/favicon.ico` 路径，返回 204 No Content
- 更新 Nginx 配置注释，说明隐蔽性增强

**效果**:
- 探针访问时看到的是"拒绝访问"的网站，而不是"连接被重置"
- 模拟真实网站行为，降低被识别为代理的风险

**文件**: `install_landing_enhanced.sh` (第 753-870 行)

---

### ✅ 修复 2: Apple CDN IP 轮换池（隐蔽性 HIGH）

**问题**:
- 当前使用固定 IP 17.253.144.10，如果这个 IP 被识别，可能被封
- 单个 IP 容易被流量分析识别

**修复**:
- 在 `setup_nginx_stream()` 函数中添加 Apple CDN IP 轮换池
- 使用 4 个 Apple CDN IP 地址：17.253.144.10-13
- 每次安装时随机选择一个 IP，降低单个 IP 被识别的风险
- 保持无 DNS 查询的设计（避免被 GFW 观测）

**效果**:
- 降低单个 IP 被识别的风险
- 提供 IP 轮换能力，增强隐蔽性
- 保持无 DNS 查询，避免额外的流量特征

**文件**: `install_transit_enhanced.sh` (第 708-735 行)

---

### ✅ 修复 3: Cloudflare Token 加密存储（安全性 CRITICAL）

**问题**:
- CF_TOKEN 以明文形式存储在 manager.conf 中
- 虽然文件权限是 600，但如果服务器被攻破，攻击者可以直接读取 token
- Token 泄露可能导致 DNS 记录被篡改，节点被劫持

**修复**:
- 添加 `encrypt_cf_token()` 和 `decrypt_cf_token()` 函数
- 使用 OpenSSL AES-256-CBC 加密，密钥基于机器唯一标识符（/etc/machine-id）
- 修改 `save_manager_config()` 函数，在写入前加密 CF_TOKEN
- 修改 `load_manager_config()` 函数，在读取后解密 CF_TOKEN
- 修改 `fresh_install()` 函数中的临时 manager.conf 写入逻辑
- 兼容旧版本明文存储（自动检测并解密）

**效果**:
- CF_TOKEN 以加密形式存储，即使文件被读取也无法直接使用
- 密钥基于机器唯一标识符，无法在其他机器上解密
- 向后兼容，旧版本的明文 token 仍可正常读取

**文件**: `install_landing_enhanced.sh` (第 238-283 行, 341-360 行, 3207-3229 行)

---

### ✅ 修复 4: 完善回滚机制（部署可靠性 CRITICAL）

**问题**:
- 安装失败时，IPv6 防火墙规则可能无法回滚
- 部分回滚可能导致不一致状态

**修复**:
- 增强 `_fresh_install_rollback()` 函数，添加 IPv6 防火墙规则清理
- 使用 `ip6tables` 清理 IPv6 防火墙链（FW_CHAIN6）
- 确保回滚时清理所有资源（IPv4 + IPv6）

**效果**:
- 安装失败时，IPv4 和 IPv6 防火墙规则都能正确回滚
- 避免残留防火墙规则导致的端口冲突或安全问题
- 提高重新安装的成功率

**文件**: `install_landing_enhanced.sh` (第 3167-3203 行)

---

### ✅ 修复 5: 端口冲突检测增强（部署可靠性 HIGH）

**问题**:
- 端口冲突检测分散在多个位置，检测时机不统一
- Nginx fallback 端口（45231, 45232）的检测发生在创建临时文件之后，导致不必要的回滚

**修复**:
- 在 `fresh_install()` 函数开始时集中检测所有端口
- 检测 LANDING_PORT（外网端口）
- 检测 Nginx fallback 端口（45231, 45232）
- 允许 Nginx 占用 fallback 端口（可能是之前的安装）
- 提供详细的端口占用信息（显示占用进程）

**效果**:
- 提前发现端口冲突，避免不必要的安装工作
- 提供更友好的错误提示，帮助用户快速定位问题
- 减少回滚次数，提高安装效率

**文件**: `install_landing_enhanced.sh` (第 3097-3113 行)

---

## 技术细节

### 加密算法
- **算法**: AES-256-CBC
- **密钥来源**: /etc/machine-id（每台机器唯一）
- **编码**: Base64
- **兼容性**: 自动检测加密格式，兼容旧版本明文存储

### IP 轮换池
- **IP 池大小**: 4 个 IP 地址
- **选择方式**: 随机选择（使用 $RANDOM）
- **IP 来源**: Apple CDN 的多个边缘节点

### 端口检测
- **检测工具**: ss -tlnp
- **检测端口**: LANDING_PORT, 45231, 45232
- **检测时机**: fresh_install 函数开始时

---

## 测试建议

### 1. Nginx Fallback 测试
```bash
# 测试 403 响应
curl -k https://your-domain.com:8443

# 测试 robots.txt
curl -k https://your-domain.com:8443/robots.txt

# 测试 favicon.ico
curl -I -k https://your-domain.com:8443/favicon.ico
```

### 2. CF_TOKEN 加密测试
```bash
# 查看加密后的 token（应该是 base64 编码的密文）
grep CF_TOKEN /etc/landing_manager/manager.conf

# 测试解密（脚本会自动解密）
bash install_landing_enhanced.sh --show-nodes
```

### 3. 端口冲突测试
```bash
# 占用 8443 端口
nc -l 8443 &

# 运行安装脚本（应该立即报错）
bash install_landing_enhanced.sh
```

---

## 升级说明

### 从 v3.62 升级到 v3.63

1. **备份现有配置**:
   ```bash
   cp /etc/landing_manager/manager.conf /etc/landing_manager/manager.conf.backup
   ```

2. **下载新版本脚本**:
   ```bash
   wget https://raw.githubusercontent.com/vpn3288/Chained-Proxy/master/install_landing_enhanced.sh
   wget https://raw.githubusercontent.com/vpn3288/Chained-Proxy/master/install_transit_enhanced.sh
   ```

3. **运行升级**:
   ```bash
   # 落地机
   bash install_landing_enhanced.sh
   
   # 中转机
   bash install_transit_enhanced.sh
   ```

4. **验证升级**:
   ```bash
   # 检查 Nginx Fallback 配置
   cat /etc/nginx/conf.d/xray-landing-fallback.conf
   
   # 检查 CF_TOKEN 是否已加密
   grep CF_TOKEN /etc/landing_manager/manager.conf
   ```

### 注意事项

- **CF_TOKEN 加密**: 首次运行 v3.63 时，脚本会自动加密明文 CF_TOKEN
- **向后兼容**: v3.63 可以读取 v3.62 的明文 CF_TOKEN，无需手动迁移
- **Nginx Fallback**: 如果已有 Nginx Fallback 配置，脚本会自动更新为新版本

---

## 已知问题

无

---

## 下一步计划

1. 添加更多 Apple CDN IP 地址到轮换池
2. 实现动态 IP 轮换（定期更换 fallback IP）
3. 添加流量混淆功能（模拟正常 HTTPS 流量）
4. 实现证书指纹轮换（避免证书特征被识别）

---

## 贡献者

- Kiro (AI Assistant) - 主要开发
- Xu Zhenyu - 需求提出和测试

---

## 许可证

MIT License
