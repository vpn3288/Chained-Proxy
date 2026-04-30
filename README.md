# Chained-Proxy

> **欺上瞒下**的双层代理架构 — 让 GFW 无视你，让目标网站认为你是普通美国用户

[![Version](https://img.shields.io/badge/version-v5.17-blue.svg)](https://github.com/vpn3288/Chained-Proxy/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Tested](https://img.shields.io/badge/tested-Debian%2012-orange.svg)]()

---

## 📖 目录

- [核心理念](#核心理念)
- [架构设计](#架构设计)
- [快速开始](#快速开始)
- [功能特性](#功能特性)
- [版本历史](#版本历史)
- [故障排查](#故障排查)
- [常见问题](#常见问题)

---

## 🎯 核心理念

### 欺上（对抗 GFW）
- ✅ 真实 TLS 证书（Let's Encrypt）
- ✅ TCP 窗口随机化，模拟真实家宽用户
- ✅ uTLS 指纹随机化，模拟真实浏览器
- ✅ 中转机纯 TCP 盲传，无代理特征
- ✅ 流量模拟，混入正常 HTTPS 访问

### 瞒下（伪装美国用户）
- ✅ 使用美国家宽 ISP 原生 DNS
- ✅ IPv6 完全封堵，防止机房特征泄露
- ✅ 浏览器指纹随机化
- ✅ 时区、语言环境本地化

### 长期稳定
- ✅ 证书自动续期（acme.sh）
- ✅ 服务健康检查和自动恢复
- ✅ 防火墙规则持久化
- ✅ 几个月到一年免维护

---

## 🏗️ 架构设计

```
┌─────────────┐      ┌──────────────┐      ┌──────────────┐      ┌─────────────┐
│  国内用户   │ ───> │ 中转机(CN2)  │ ───> │ 落地机(美国) │ ───> │  目标网站   │
│   Client    │      │   Transit    │      │   Landing    │      │   Target    │
└─────────────┘      └──────────────┘      └──────────────┘      └─────────────┘
                      Nginx SNI 盲传        Xray-core TLS
                      纯TCP转发             5个协议节点
                      不解密流量            真实证书
```

### 中转机（Transit Server）
| 项目 | 说明 |
|------|------|
| **位置** | CN2 GIA 美西 VPS（低延迟，连接中国快） |
| **技术栈** | Nginx stream 模块 + SNI 嗅探 |
| **功能** | 纯 TCP 盲传，不解密，不安装代理 |
| **网络** | 仅 IPv4（CN2 GIA 高速线路） |
| **端口** | 443（标准 HTTPS 端口） |

### 落地机（Landing Server）
| 项目 | 说明 |
|------|------|
| **位置** | 美国普通线路 VPS（延迟高但 IP 干净） |
| **技术栈** | Xray-core v1.8+ |
| **协议** | Trojan-TCP, VLESS-Vision, VLESS-gRPC, Trojan-gRPC, VLESS-WS |
| **网络** | IPv4 或 IPv4+IPv6 双栈 |
| **端口** | 8443（可自定义） |

---

## 🚀 快速开始

### 前置要求

- ✅ **操作系统**: Debian 12（推荐通过 [DD脚本](https://github.com/leitbogioro/Tools) 安装）
- ✅ **权限**: root 用户
- ✅ **域名**: 已添加到 Cloudflare 的域名
- ✅ **Cloudflare API Token**: 完全权限（Zone:DNS:Edit）

### 步骤 1: 部署落地机

```bash
# 下载脚本
wget -O install_landing.sh https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_landing_v5.17.sh
```
```bash
# 添加执行权限
chmod +x install_landing.sh
```
```bash
# 运行安装
./install_landing.sh
```

**安装过程中需要输入：**
1. 落地机域名（如：`node1.example.com`）
2. Cloudflare API Token
3. Trojan 密码（≥16 字符，自动生成或手动输入）
4. VLESS UUID（自动生成或手动输入）
5. 中转机 IP（用于防火墙白名单）

**安装完成后会显示：**
- ✅ 5 个协议节点的配置信息
- ✅ 节点分享链接（可直接导入客户端）
- ✅ 配对 Token（用于中转机配置）

### 步骤 2: 部署中转机

```bash
# 下载脚本
wget -O install_transit.sh https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_transit_v5.17.sh
```
```bash
# 添加执行权限
chmod +x install_transit.sh
```
```bash
# 运行安装
./install_transit.sh
```

**安装过程中需要输入：**
1. 落地机 IP
2. 落地机域名
3. 落地机端口（默认 8443）

或者直接粘贴落地机输出的配对 Token（傻瓜式一键配置）。

**安装完成后：**
- ✅ Nginx 自动配置 SNI 路由
- ✅ 防火墙规则自动生效
- ✅ 443 端口开始监听

### 步骤 3: 客户端配置

**方式 A（推荐）**: 直接导入落地机输出的分享链接

**方式 B**: 手动配置
- **服务器地址**: 中转机 IP
- **端口**: 443
- **其他参数**: 与落地机配置相同（密码、UUID、域名等）

**支持的客户端：**
- Windows: v2rayN, Clash for Windows
- macOS: ClashX, V2RayX
- iOS: Shadowrocket, Quantumult X
- Android: v2rayNG, Clash for Android

---

## ✨ 功能特性

### 🛡️ 反检测优化

| 特性 | 说明 | 效果 |
|------|------|------|
| **TCP 窗口随机化** | 每次安装随机生成窗口大小 | 避免固定指纹被识别 |
| **uTLS 指纹随机化** | 5 个协议使用不同浏览器指纹 | 模拟真实浏览器行为 |
| **真实 TLS 证书** | Let's Encrypt 自动申请 | 通过浏览器验证 |
| **SNI 盲传** | 中转机不解密流量 | 无代理特征 |
| **流量模拟** | 定时访问正常网站 | 混淆纯代理流量特征 |
| **DNS 本地化** | 使用美国家宽 ISP DNS | 避免 8.8.8.8 等公共 DNS 特征 |

### 🔒 安全加固

| 特性 | 说明 |
|------|------|
| **最小权限运行** | Xray 使用非 root 用户 `xray-landing` |
| **防火墙白名单** | 仅允许中转机 IP 连接落地机 |
| **IPv6 封堵** | 防止 IPv6 侧漏暴露机房特征 |
| **SSH 端口随机化** | 避免 22 端口被扫描 |
| **自动安全更新** | unattended-upgrades 自动安装安全补丁 |

### 🔄 稳定性保障

| 特性 | 说明 | 频率 |
|------|------|------|
| **健康检查** | 自动检测服务状态 | 每 5 分钟 |
| **自动重启** | 服务异常时自动恢复 | 实时 |
| **证书自动续期** | acme.sh 自动续期 | 每天检查 |
| **日志轮转** | 防止日志占满磁盘 | 每天轮转，保留 7 天 |
| **防火墙持久化** | 重启后自动恢复规则 | 开机自动 |

### 📊 可观测性

| 功能 | 路径 | 说明 |
|------|------|------|
| **Xray 日志** | `journalctl -u xray-landing -f` | 实时查看代理日志 |
| **Nginx 日志** | `journalctl -u nginx -f` | 实时查看转发日志 |
| **健康检查日志** | `journalctl -t xray-landing-health` | 查看健康检查记录 |
| **证书状态** | `~/.acme.sh/acme.sh --list` | 查看证书有效期 |

---

## 📝 版本历史

### v5.17 (2026-04-30) — 安全加固与代码审计

**🔴 安全修复：**
- 修复 5 处 `rm -rf` 高危风险（添加 `${VAR:?}` 保护）
- 修复 Nginx 日志文件权限问题（BUG #38）
- 修复中转机 awk 语法错误（BUG #37）

**✅ 功能增强：**
- 输入验证循环重试机制（BUG #36）
- 完整的 ShellCheck 静态分析通过
- 所有交互式输入支持错误重试

**📊 测试验证：**
- 落地机完整安装测试通过（5 个协议节点）
- 中转机 SNI 路由测试通过
- 端到端 TLS 握手验证通过

**提交记录：**
- `d3a6349` - 安全修复：5 处 rm -rf 风险
- `5f9be2a` - BUG #38：Nginx 日志权限
- `59a42c3` - BUG #37：awk 语法错误
- `7a61d92` - BUG #36：输入验证循环

### v5.12 (2026-04-29) — 21 项审计发现全面修复

**中转机修复：**
- IFS 恢复使用 local 而非 trap
- 防火墙白名单规则使用 `-I 1` 插入
- 路由冲突检测修复变量丢失
- 端口冲突检测增加进程名验证
- 元数据漂移检测

**落地机修复：**
- gen_password() 使用 `head -c` 而非 `dd`
- DNS TXT 记录格式验证
- 证书延迟期间 Ctrl+C trap 修复
- 证书 reload 脚本检查 fullchain.pem 非空
- IPv6 防火墙增加 NDP 规则

### v5.00 (2026-04-29) — 架构稳定版本

基于 v4.90 的全面优化，修复防火墙恢复脚本、白名单规则顺序、卸载完整性等问题。

---

## 🔧 故障排查

### 中转机无法连接

```bash
# 1. 检查 Nginx 状态
systemctl status nginx

# 2. 检查 443 端口是否监听
ss -tlnp | grep :443

# 3. 查看 Nginx 错误日志
tail -50 /var/log/nginx/error.log

# 4. 检查防火墙规则
iptables -L INPUT -n -v | grep 443

# 5. 测试到落地机的连通性
curl -v https://落地机域名:8443
```

### 落地机证书问题

```bash
# 1. 检查 Xray 状态
systemctl status xray-landing

# 2. 查看 Xray 日志
journalctl -u xray-landing -n 50

# 3. 检查证书文件
ls -lh /etc/xray-landing/certs/你的域名/

# 4. 检查证书有效期
~/.acme.sh/acme.sh --list

# 5. 手动续期证书
~/.acme.sh/acme.sh --renew -d 你的域名 --ecc --force
```

### 节点无法连接

```bash
# 1. 检查 Xray 是否运行
systemctl status xray-landing

# 2. 检查端口监听
ss -tlnp | grep 8443

# 3. 检查防火墙是否放行中转机 IP
iptables -L INPUT -n -v | grep 中转机IP

# 4. 测试本地连接
curl -v --resolve 你的域名:8443:127.0.0.1 https://你的域名:8443

# 5. 查看实时日志
journalctl -u xray-landing -f
```

### 健康检查失败

```bash
# 中转机健康检查日志
journalctl -t transit-health -n 50

# 落地机健康检查日志
journalctl -t xray-landing-health -n 50

# 手动运行健康检查脚本
/usr/local/bin/transit-health-check.sh  # 中转机
/usr/local/bin/xray-landing-health-check.sh  # 落地机
```

---

## ❓ 常见问题

<details>
<summary><b>Q: 为什么需要两台 VPS？</b></summary>

**A:** 中转机负责低延迟连接（CN2 GIA），落地机负责真实 IP 伪装。分离架构的优势：

1. **性能优化**: 中转机使用 CN2 GIA 高速线路，延迟低至 150ms
2. **成本优化**: 落地机可以使用便宜的普通线路 VPS
3. **安全隔离**: 中转机不安装代理，即使被检测也不会暴露落地机
4. **灵活扩展**: 一个中转机可以对接多个落地机

</details>

<details>
<summary><b>Q: 可以只用一台 VPS 吗？</b></summary>

**A:** 可以，但会失去"欺上瞒下"的核心优势：

- ❌ 失去 CN2 GIA 低延迟优势
- ❌ 国内直连美国 VPS 延迟高（300ms+）
- ❌ 无法隔离中转和落地的风险

**单机方案**: 直接在美国 VPS 上安装落地机脚本，跳过中转机步骤。

</details>

<details>
<summary><b>Q: 证书申请失败怎么办？</b></summary>

**A:** 按以下步骤排查：

1. **检查域名解析**: `dig 你的域名` 确认解析到落地机 IP
2. **等待 DNS 传播**: 通常需要 5-10 分钟
3. **检查 Cloudflare API Token**: 确保有 `Zone:DNS:Edit` 权限
4. **查看详细日志**: `journalctl -u xray-landing -n 100`
5. **手动申请**: `~/.acme.sh/acme.sh --issue -d 你的域名 --dns dns_cf --ecc`

</details>

<details>
<summary><b>Q: 如何更新脚本？</b></summary>

**A:** 重新下载最新版本脚本并运行：

```bash
# 下载最新版本
wget -O install_landing.sh https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_landing_v5.17.sh

# 运行安装
./install_landing.sh
```

脚本会自动检测已有配置并提供导入选项，无需重新输入所有参数。

</details>

<details>
<summary><b>Q: 如何完全卸载？</b></summary>

**A:** 运行脚本并选择卸载选项：

```bash
# 落地机
./install_landing.sh
# 选择菜单中的 "清除本系统所有数据" 选项

# 中转机
./install_transit.sh
# 选择菜单中的 "清除本系统所有数据" 选项
```

会完全清理：
- ✅ 所有配置文件
- ✅ 证书和密钥
- ✅ 防火墙规则
- ✅ systemd 服务
- ✅ 日志文件

</details>

<details>
<summary><b>Q: 支持哪些客户端？</b></summary>

**A:** 支持所有兼容 Trojan/VLESS 协议的客户端：

| 平台 | 推荐客户端 |
|------|-----------|
| Windows | v2rayN, Clash for Windows |
| macOS | ClashX, V2RayX |
| iOS | Shadowrocket, Quantumult X |
| Android | v2rayNG, Clash for Android |
| Linux | v2ray-core, Xray-core |

</details>

<details>
<summary><b>Q: 如何添加多个落地机？</b></summary>

**A:** 中转机支持多落地机配置：

1. 在中转机上再次运行 `./install_transit.sh`
2. 选择菜单中的 "增加落地机路由规则"
3. 输入新落地机的 IP、域名、端口

每个落地机使用独立的域名进行 SNI 路由。

</details>

<details>
<summary><b>Q: 脚本是否开源？</b></summary>

**A:** 是的，完全开源：

- 📂 **仓库**: https://github.com/vpn3288/Chained-Proxy
- 📜 **许可证**: MIT License
- 🔍 **代码审计**: 通过 ShellCheck 静态分析
- 🧪 **测试覆盖**: 完整的安装和功能测试

欢迎提交 Issue 和 Pull Request！

</details>

---

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！请确保：

1. ✅ 代码遵循 ShellCheck 规范
2. ✅ 提交前进行充分测试
3. ✅ 更新版本号和 CHANGELOG
4. ✅ 提供详细的提交说明

### 开发环境

```bash
# 安装 ShellCheck
apt-get install shellcheck

# 运行静态分析
shellcheck install_landing_v5.17.sh
shellcheck install_transit_v5.17.sh

# 运行语法检查
bash -n install_landing_v5.17.sh
bash -n install_transit_v5.17.sh
```

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## ⚠️ 免责声明

本项目仅供学习和研究使用，请遵守当地法律法规。使用本项目所产生的一切后果由使用者自行承担。

---

## 📞 联系方式

- **GitHub Issues**: https://github.com/vpn3288/Chained-Proxy/issues
- **维护者**: vpn3288

---

<div align="center">

**当前版本**: v5.17  
**更新日期**: 2026-04-30  
**测试状态**: ✅ 通过

Made with ❤️ by vpn3288

</div>
