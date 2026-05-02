# Chained-Proxy v5.18

**链式代理脚本 - 中转机 + 落地机**

## 🎯 项目简介

本项目提供两个Bash脚本，用于快速部署链式代理架构：
- **中转机**: CN2 GIA线路，Nginx stream SNI盲传
- **落地机**: 国际线路VPS，Xray-core多协议支持

## 📦 v5.18 版本特性

### 核心修复
- ✅ 修复15项审查报告发现的问题（CRITICAL×3, HIGH×6, MEDIUM×3, LOW×2, GLOBAL×1）
- ✅ 完美兼容 1Panel/OpenClaw/HermesAgent 生态
- ✅ IPv6侧漏封堵，防止家宽伪装被击穿
- ✅ 端口冲突全面检测（包括systemd unit状态）
- ✅ 防火墙规则顺序修复，确保白名单生效

### 稳定性增强
- 🛡️ 证书续期失败主动告警（90天后断流前预警）
- 🛡️ 健康检查cron验证（确保真正生效）
- 🛡️ DNS传播智能等待（减少不必要延迟）
- 🛡️ 卸载完整性保障（彻底清理残留）

### 安全性增强
- 🔒 删除流量模拟功能（避免机器人特征）
- 🔒 worker_connections随机化增强（抗指纹识别）
- 🔒 mack-a冲突检测增强（nginx配置检查）

## 🚀 快速开始

### 中转机安装
\\\ash
# 下载脚本
wget https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_transit_v5.18.sh

# 执行安装
bash install_transit_v5.18.sh
\\\

### 落地机安装
\\\ash
# 下载脚本
wget https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_landing_v5.18.sh

# 执行安装
bash install_landing_v5.18.sh
\\\

### 1Panel用户
安装时会提示输入额外端口，输入1Panel管理端口：
\\\
额外放行端口（多个用空格隔开，无则回车）: 8888
\\\

## 📋 系统要求

### 中转机
- 系统: Debian 12（推荐通过DD安装）
- 网络: CN2 GIA线路，仅IPv4
- 端口: 443（TCP）、SSH端口

### 落地机
- 系统: Debian 12（推荐通过DD安装）
- 网络: 国际线路，IPv4或IPv4+IPv6双栈
- 端口: 自定义主端口（默认8443）、SSH端口
- 域名: 需要Cloudflare托管的域名
- API: Cloudflare API Token（Zone:DNS:Edit权限）

## 🔧 环境变量

### 跳过证书申请延迟（测试用）
\\\ash
LANDING_SKIP_CERT_DELAY=1 bash install_landing_v5.18.sh
\\\

### 指定中转机公网IP
\\\ash
TRANSIT_PUBLIC_IP=x.x.x.x bash install_transit_v5.18.sh
\\\

## 📊 架构说明

\\\
用户 → 中转机(CN2 GIA) → 落地机(国际线路) → 目标网站
      ↓ Nginx SNI盲传    ↓ Xray多协议
      443端口            Trojan/VLESS/gRPC/WS
\\\

### 中转机特性
- Nginx stream模块SNI嗅探
- TCP盲传（TFO + Keepalive）
- 空/无匹配SNI → Apple CDN（17.253.144.10:443）
- 防火墙白名单（SSH + 443 + ICMP）

### 落地机特性
- Xray-core 5协议单端口回落
- Trojan-TLS + VLESS + gRPC + WebSocket
- TLS 1.2/1.3双栈
- 异构uTLS指纹
- 自动证书申请与续期

## 📖 详细文档

- [完整变更日志](CHANGELOG_v5.18.md)
- [审查报告修复详情](CHANGELOG_v5.18.md#-critical-级别修复)

## 🛠️ 管理命令

### 中转机
\\\ash
# 查看状态
bash install_transit_v5.18.sh --status

# 卸载
bash install_transit_v5.18.sh --uninstall

# 导入落地机Token
bash install_transit_v5.18.sh --import <token>
\\\

### 落地机
\\\ash
# 查看状态
bash install_landing_v5.18.sh --status

# 卸载
bash install_landing_v5.18.sh --uninstall

# 修改端口
bash install_landing_v5.18.sh set-port <新端口>
\\\

## ⚠️ 注意事项

1. **中转机和落地机必须统一使用Debian 12**
2. **中转机仅支持IPv4**（CN2 GIA特性）
3. **落地机需要Cloudflare托管的域名**
4. **不要与mack-a/v2ray-agent共存**（会自动检测冲突）
5. **1Panel用户需要在安装时指定额外端口**

## 🔄 版本历史

- **v5.18** (2026-05-02): 审查报告全面修复，15项问题修复
- **v5.17** (2026-04-30): 交互式容错增强
- **v5.16** (2026-04-30): 版本号统一
- **v5.14** (2026-04-30): 域名验证和Nginx启动修复

## 🙏 致谢

感谢三位审查AI的详细审查报告，确保了v5.18版本的高质量修复。

## 📄 许可证

MIT License

## 🔗 相关链接

- GitHub仓库: https://github.com/vpn3288/Chained-Proxy
- DD安装工具: https://github.com/leitbogioro/Tools

---

**主笔AI**: Kiro  
**发布日期**: 2026-05-02  
**版本**: v5.18
