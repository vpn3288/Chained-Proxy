# Chained-Proxy

**欺上瞒下**的双层代理架构 — 中转机 + 落地机链式部署方案

## 核心理念

- **欺上**：欺骗 GFW，流量看起来像普通 HTTPS 用户
- **瞒下**：让国外网站认为你是美国普通公民
- **长期稳定**：几个月到一年免维护，无异常流量行为

## 架构设计

```
[国内用户] → [中转机 CN2GIA] → [落地机 美国VPS] → [目标网站]
              Nginx SNI盲传      Xray-core TLS
```

### 中转机（Transit）
- **位置**：CN2 GIA 美西 VPS（低延迟）
- **技术**：Nginx stream 模块 SNI 盲传
- **特点**：纯 TCP 转发，不解密，不安装代理节点
- **网络**：仅 IPv4

### 落地机（Landing）
- **位置**：美国普通线路 VPS（高延迟可接受）
- **技术**：Xray-core（Trojan-TLS + VLESS + gRPC + WebSocket）
- **特点**：真实 TLS 证书，浏览器指纹随机化
- **网络**：IPv4 或 IPv4+IPv6 双栈

## 快速开始

### 前置要求

- 系统：Debian 12（推荐通过 DD 安装）
- 权限：root 用户
- 域名：已解析到落地机 IP 的域名

### 1. 部署落地机

```bash
# 下载脚本
wget https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_landing_v5.12.sh

# 运行安装
bash install_landing_v5.12.sh
```

安装过程中需要输入：
- 落地机域名（例如：example.com）
- Trojan 密码（≥16 字符）
- VLESS UUID（自动生成或手动输入）

安装完成后会显示**配对令牌**，保存好用于中转机配置。

### 2. 部署中转机

```bash
# 下载脚本
wget https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_transit_v5.12.sh

# 运行安装
bash install_transit_v5.12.sh
```

安装过程中需要输入：
- 落地机配对令牌（从落地机安装输出中复制）

安装完成后会显示中转机 IP，用于客户端连接。

### 3. 客户端配置

使用中转机 IP 作为服务器地址，其他参数（端口、密码、UUID）与落地机相同。

## 版本历史

### v5.12（2026-04-29）— 21 项审计发现全面修复

**中转机修复：**
- [CRITICAL] IFS 恢复使用 local 而非 trap（自动作用域恢复）
- [HIGH] 防火墙白名单规则使用 `-I 1` 插入而非 `-A` 追加
- [HIGH] 路由冲突检测使用命令替换而非进程替换（修复变量丢失）
- [MEDIUM] 端口冲突检测增加进程名验证（避免误判）
- [MEDIUM] 元数据漂移检测验证 .map 内容与 .meta 一致

**落地机修复：**
- [CRITICAL] gen_password() 使用 `head -c` 而非 `dd`（避免 pipefail 崩溃）
- [CRITICAL] DNS TXT 记录格式验证（区分 NXDOMAIN 和传播中）
- [CRITICAL] 证书延迟期间 Ctrl+C trap 在 sleep 前注册
- [HIGH] 证书 reload 脚本检查 fullchain.pem 非空（防止续期失败静默）
- [HIGH] IPv6 防火墙增加 NDP 规则（ICMPv6 类型 133-136）
- [HIGH] TRANSIT_IP 格式验证

### v5.11（2026-04-29）— 代码审计报告全面修复

修复所有 Transit 和 Landing 关键问题，包括 IFS 恢复、DNS 传播检测、证书 reload 脚本等。

### v5.10（2026-04-29）— 26 项审查报告全面修复

包括卸载完整性、IPv6 防火墙修复、IP 验证优化、Nginx 配置安全等。

### v5.00（2026-04-29）— 架构稳定版本

基于 v4.90 的全面优化，修复防火墙恢复脚本、白名单规则顺序、卸载完整性等问题。

## 常见问题

### Q: 为什么需要两台 VPS？

A: 中转机负责低延迟连接（CN2 GIA），落地机负责真实 IP 伪装。分离架构提高稳定性和安全性。

### Q: 可以只用一台 VPS 吗？

A: 可以，但会失去"欺上瞒下"的核心优势。单机方案请直接在落地机安装，跳过中转机步骤。

### Q: 证书申请失败怎么办？

A: 确保域名已正确解析到落地机 IP，等待 DNS 传播完成（通常 5-10 分钟）。脚本会自动检测 DNS 传播状态。

### Q: 如何更新脚本？

A: 重新下载最新版本脚本并运行。脚本会自动检测已有配置并提供导入选项。

### Q: 如何卸载？

A: 运行脚本并选择 `purge_all` 选项，会完全清理所有配置和文件。

### Q: 支持哪些客户端？

A: 支持所有兼容 Trojan/VLESS 协议的客户端，如 v2rayN、Clash、Shadowrocket 等。

## 技术特性

### 反检测优化

- **TCP 窗口随机化**：模拟真实家宽用户
- **uTLS 指纹随机化**：每个协议随机选择浏览器指纹
- **真实 TLS 证书**：Let's Encrypt 自动申请和续期
- **SNI 盲传**：中转机不解密流量，无代理特征

### 稳定性保障

- **健康检查**：每 3 分钟自动检测服务状态
- **自动恢复**：服务异常时自动重启
- **证书自动续期**：acme.sh 自动续期，无需人工干预
- **防火墙自动恢复**：SSH 断开时自动恢复防火墙规则

### 安全加固

- **最小权限**：Xray 使用非 root 用户运行
- **IPv6 封堵**：防止 IPv6 侧漏（可选）
- **端口随机化**：避免固定端口被封
- **白名单机制**：仅允许必要的入站连接

## 故障排查

### 中转机无法连接

```bash
# 检查 Nginx 状态
systemctl status nginx

# 查看 Nginx 日志
journalctl -u nginx -n 50

# 检查防火墙规则
iptables -L -n -v
```

### 落地机证书问题

```bash
# 检查 Xray 状态
systemctl status xray-landing

# 查看 Xray 日志
journalctl -u xray-landing -n 50

# 检查证书有效期
~/.acme.sh/acme.sh --list
```

### 健康检查失败

```bash
# 查看健康检查日志
journalctl -t transit-health -n 50  # 中转机
journalctl -t xray-landing-health -n 50  # 落地机
```

## 贡献指南

欢迎提交 Issue 和 Pull Request。请确保：

1. 代码遵循 ShellCheck 规范
2. 提交前进行充分测试
3. 更新版本号和变更记录

## 许可证

MIT License

## 免责声明

本项目仅供学习和研究使用，请遵守当地法律法规。使用本项目所产生的一切后果由使用者自行承担。

---

**当前版本**：v5.12  
**更新日期**：2026-04-29  
**维护者**：vpn3288
