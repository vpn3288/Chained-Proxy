# 修复方案计划

## 🔴 CRITICAL 修复（必须立即实施）

### 1. 添加 Nginx Fallback 配置（隐蔽性）

**问题**：落地机端口 45231/45232 没有配置 Nginx fallback，直接访问会暴露代理特征

**修复方案**：
- 在落地机上配置 Nginx，监听 45231/45232
- 返回真实网站内容（伪装成博客或企业网站）
- 使用反向代理到真实网站（例如 example.com）

**实施步骤**：
1. 创建 Nginx fallback 配置文件
2. 配置反向代理到真实网站
3. 确保 Nginx 在 Xray 之前启动

---

### 2. 添加 uTLS 指纹配置（隐蔽性）

**问题**：Xray 配置中缺少 uTLS 指纹，TLS 握手可能被识别

**修复方案**：
- 在 Xray inbound 配置中添加 fingerprint
- 使用 Chrome 或 Firefox 指纹

**实施步骤**：
1. 修改 sync_xray_config() 中的 Python 代码
2. 在 streamSettings.tlsSettings 中添加 "fingerprint": "chrome"

---

### 3. 加强 Cloudflare Token 安全（安全性）

**问题**：Token 明文存储在 manager.conf 中

**修复方案**：
- 使用最小权限 Token（Zone:DNS:Edit only）
- 添加 Token 加密存储
- 定期轮换 Token

**实施步骤**：
1. 创建 Token 加密/解密函数
2. 修改 save_manager_config() 和 load_manager_config()
3. 添加 Token 轮换提醒

---

### 4. 完善证书续期失败处理（稳定性）

**问题**：证书续期失败时，只在 7 天内过期时告警，可能太晚

**修复方案**：
- 提前到 30 天告警
- 添加邮件/Telegram 通知
- 自动重试续期

**实施步骤**：
1. 修改 /etc/cron.daily/xray-cert-monitor
2. 添加通知机制
3. 添加自动重试逻辑

---

### 5. 完善回滚机制（部署可靠性）

**问题**：回滚函数不完整，可能留下残留配置

**修复方案**：
- 完善所有回滚函数
- 添加回滚测试
- 确保防火墙规则也能回滚

**实施步骤**：
1. 审查所有回滚函数
2. 添加缺失的回滚步骤
3. 添加回滚验证

---

## ⚠️ HIGH 修复（应该尽快实施）

### 6. 调整流量特征参数（隐蔽性）

**修复方案**：
- 调整 proxy_timeout 到 120s
- 添加流量混淆
- 使用域名而非固定 IP

### 7. 加强 DDoS 防护（安全性）

**修复方案**：
- 降低 connlimit 到 500-1000
- 降低 hashlimit 到 1000-2000/sec
- 添加 SYN flood 防护

### 8. 改进服务重启逻辑（稳定性）

**修复方案**：
- 使用 reload 而非 restart
- 添加 graceful restart

### 9. 完善端口冲突检测（部署可靠性）

**修复方案**：
- 检测所有端口（包括 LANDING_PORT）
- 提供端口冲突解决方案

---

## 实施顺序

1. **第一批**（今天完成）：
   - 修复 1：Nginx Fallback
   - 修复 2：uTLS 指纹
   - 修复 4：证书续期

2. **第二批**（明天完成）：
   - 修复 3：Token 安全
   - 修复 5：回滚机制
   - 修复 7：DDoS 防护

3. **第三批**（后天完成）：
   - 修复 6：流量特征
   - 修复 8：服务重启
   - 修复 9：端口冲突

---

## 测试计划

每个修复完成后，需要测试：
1. 功能是否正常
2. 是否引入新问题
3. 回滚是否正常

