# Chained-Proxy

> 链式代理：Transit（中转节点）+ Landing（落地节点）两层架构
>
> 用途：稳定、高速的跨境代理，隐蔽性强，支持 Xray-core + Trojan-over-TLS

## 架构图

```
[用户设备]
    │
    │  (TLS + SNI 混淆)
    ▼
┌─────────────────┐
│   Transit 节点   │  ← 中转机 (境外VPS)
│  Nginx Stream   │     端口: 443 (TCP)
│  SNI 智能路由   │     仅做TCP转发，不解密
└───────┬─────────┘
        │  纯TCP流 (SNI不变)
        ▼
┌─────────────────┐
│  Landing 节点    │  ← 落地机 (境外VPS)
│  Xray-core      │     端口: 443 (TLS终
│  Trojan 协议    │       证书由 acme.sh
│  acme.sh TLS   │       自动申请)
└───────┬─────────┘
        │  原始流量
        ▼
   [目标服务器]
```

## 前提要求

### Transit（中转节点）服务器
- **系统**: Debian 11+ / Ubuntu 20.04+ / CentOS 8+
- **配置**: 1核 1GB 内存 最少
- **网络**: 独立IP，端口 443 开放
- **推荐**: 稳定、低延迟的境外 VPS

### Landing（落地节点）服务器
- **系统**: Debian 11+ / Ubuntu 20.04+ / CentOS 8+
- **配置**: 1核 1GB 内存 最少
- **网络**: 独立IP，端口 443/22 开放
- **域名**: 需要一个解析好的域名（acme.sh 申请 Let's Encrypt 证书用）
- **推荐**: 稳定、高性能的境外 VPS

### 本地设备
- **Xray 客户端**: v2rayN (Windows)、V2RayNG (Android)、Surge (Mac/iOS)、Qv2ray (Linux)
- **协议格式**: Trojan 格式

## 一键安装

### 第1步：在 Landing（落地机）上运行

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_landing_v3.36.sh -o install_landing.sh

# 运行安装（需要 root）
sudo bash install_landing.sh
```

安装过程会要求输入：
- **域名**: 你的落地机域名，如 `landing.example.com`
- **TLS 邮箱**: 用于 acme.sh 申请证书，如 `admin@example.com`

安装完成后，记录输出中的 `trojan_password`，类似：
```
Trojan 密码: trojan://your-password@your-domain:443
```

### 第2步：在 Transit（中转机）上运行

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/vpn3288/Chained-Proxy/main/install_transit_v3.34-Optimized.sh -o install_transit.sh

# 运行安装（需要 root）
sudo bash install_transit.sh
```

安装过程会要求输入：
- **Landing 节点域名**: 你的落地机域名，如 `landing.example.com`
- **落地机 IP（可选）**: 如果域名解析不到，用 IP 直连

### 第3步：配置客户端

在 Xray 客户端中添加节点，格式：

```
trojan://[你的密码]@[Transit的IP]:443?sni=[落地域名]#Chained-Proxy
```

或者在 Clash 格式配置中：

```yaml
proxies:
  - name: Chained-Proxy
    type: trojan
    server: [Transit的IP]
    port: 443
    password: [你的密码]
    sni: [落地域名]
    udp: true
```

## 常用命令

### 查看状态

```bash
# Transit 节点
sudo systemctl status nginx
sudo systemctl status xray

# Landing 节点
sudo systemctl status xray
sudo systemctl status nginx
sudo acme.sh --info
```

### 查看日志

```bash
# Xray 日志
sudo journalctl -u xray -f

# Nginx 日志
sudo tail -f /var/log/nginx/error.log

# acme.sh 日志
tail -f ~/.acme.sh/acme.sh.log
```

### 重启服务

```bash
# Transit
sudo systemctl restart nginx
sudo systemctl restart xray

# Landing
sudo systemctl restart xray
sudo systemctl restart nginx
```

### 重新申请 TLS 证书

```bash
sudo ~/.acme.sh/acme.sh.sh --renew -d your-domain.com --force
```

### 卸载

```bash
# Transit
sudo bash install_transit_v3.34-Optimized.sh --uninstall

# Landing
sudo bash install_landing_v3.36.sh --uninstall
```

## 端口说明

| 端口 | 用途 | 备注 |
|------|------|------|
| 443 | Trojan-over-TLS + SNI代理 | 主入口 |
| 22 | SSH | 服务器管理 |
| 80 | acme.sh HTTP验证 | 仅安装时需要 |

## 故障排查

### 1. 客户端连不上

```bash
# 检查 Transit 443 端口是否开放
sudo ss -tlnp | grep :443

# 检查 Landing 443 端口
sudo ss -tlnp | grep :443

# 检查 Xray 是否在跑
sudo systemctl status xray
```

### 2. TLS 证书过期

```bash
# 查看证书有效期
sudo ~/.acme.sh/acme.sh.sh --info | grep LIVE

# 手动续期
sudo ~/.acme.sh/acme.sh.sh --renew -d your-domain.com --force

# 重启 Nginx
sudo systemctl restart nginx
```

### 3. Nginx 报错

```bash
# 检查 Nginx 配置
sudo nginx -t

# 查看错误日志
sudo tail -f /var/log/nginx/error.log
```

### 4. Xray 报错

```bash
# 检查配置语法
sudo xray run -test -config /etc/xray/config.json

# 查看详细日志
sudo journalctl -u xray -f --lines=50
```

### 5. 连上了但没网速

```bash
# 检查落地机带宽
curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3

# 检查本地到 Transit 的延迟
ping [Transit-IP]

# 检查本地到 Landing 的延迟
ping [Landing-domain]
```

## 安全建议

1. **防火墙**: 只开放必要端口（443, 22）
2. **SSH**: 使用密钥登录，禁用密码
3. **系统**: 保持系统更新 `sudo apt update && sudo apt upgrade -y`
4. **备份**: 重要配置定期备份

## 更新日志

### v3.36 (Landing)
- 优化 Xray Mux 配置
- 改进幂等性
- 修复多出边界情况

### v3.34-Optimized (Transit)
- Nginx Stream 优化
- 改进 SNI 路由逻辑
- 增强卸载完整性

## 技术支持

- GitHub Issues: https://github.com/vpn3288/Chained-Proxy/issues
- Telegram: 联系作者

## 工作原理（高级）

### Transit（中转）节点
Nginx Stream 模块监听 443 端口，通过 `preread` 读取 ClientHello 中的 SNI 字段：
- 如果 SNI 匹配落地节点域名 → 转发到落地节点
- 其他 SNI → 按需处理

```nginx
stream {
    map $ssl_preread_server_name $backend {
        landing.example.com 落地机IP;
        default 127.0.0.1:444;
    }
    upstream天堂 {
        server $backend;
    }
    server {
        listen 443;
        proxy_pass 天堂;
        ssl_preread on;
    }
}
```

### Landing（落地）节点
Xray-core 接收 TLS 流量，识别 Trojan 协议：
1. Nginx 接收 TLS
2. Xray 解密验证 Trojan 密码
3. 流量转发到目标

TLS 证书由 acme.sh 自动申请，存储在 `~/.acme.sh/` 目录。
