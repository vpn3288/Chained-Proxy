# Agent-Proxy

双层 Xray-core 部署脚本：中转机（SNI 路由）+ 落地机（TLS 终端）。

## 架构

```
Client (TLS SNI)
      │
      ▼
┌─────────────────────────────────┐
│  中转机 Transit                  │
│  Nginx stream ssl_preread        │
│  读取 TLS ClientHello SNI 字段   │
│  → 路由到对应落地机 IP:443        │
│  不解密、不终止 TLS               │
└───────────────┬─────────────────┘
                │ 原始 TCP
                ▼
┌─────────────────────────────────┐
│  落地机 Landing                  │
│  Xray-core Trojan-TLS           │
│  Let's Encrypt ECDSA 证书        │
│  终结 TLS，接管真实流量           │
└─────────────────────────────────┘
```

## 安装

### 中转机（一台）

```bash
curl -sL https://raw.githubusercontent.com/vpn3288/Agent-Proxy/main/install_transit.sh | sudo bash
```

### 落地机（多台）

```bash
curl -sL https://raw.githubusercontent.com/vpn3288/Agent-Proxy/main/install_landing.sh | sudo bash -s -- --cloudflare <CF_TOKEN>
```

## 中转机管理

```bash
# 添加落地机节点（交互式）
sudo bash install_transit.sh

# 导入节点（从落地机安装输出复制）
sudo bash install_transit.sh --import

# 卸载
sudo bash install_transit.sh --uninstall
```

## 落地机管理

```bash
# 交互式安装
sudo bash install_landing.sh

# 添加节点
sudo bash install_landing.sh --add-node

# 变更端口
sudo bash install_landing.sh --set-port

# 卸载
sudo bash install_landing.sh --uninstall
```

## 端口与共存

| 组件 | 端口 | 说明 |
|------|------|------|
| Transit Nginx | 443 | SNI 路由入口 |
| Landing Xray | 8443 | Trojan TLS 监听 |
| SSH | 自动探测 | 保持原端口 |

与 mack-a/v2ray-agent 完全物理隔离，不共享文件、端口、进程。

## 文件布局

```
/etc/transit_manager/          # 中转机配置
  conf/*.meta                   # 节点元数据
  snippets/landing_*.map        # Nginx SNI 路由表
  nodes/*.conf                  # 节点连接信息
  tmp/                          # 原子写入临时目录

/etc/xray-landing/              # 落地机配置
  config.json                   # Xray 运行配置
  certs/<domain>/              # Let's Encrypt 证书
  nodes/*.conf                  # 节点信息

/var/log/
  xray-landing-access.log      # 访问日志
  xray-landing-error.log       # 错误日志
```

## 安全特性

- **Xray 隔离**: `NoNewPrivileges=true`, `ProtectSystem=strict`, `ProtectHome=true`
- **证书权限**: 私钥 `640 root:xray-landing`，acme.sh reload 失败时拒绝启动
- **防火墙**: iptables 自定义链，仅允许已知 Transit IP 连接落地机
- **原子化写入**: 所有配置通过 `mktemp → chmod → chown → mv` 写入
- **幂等安装**: 重复运行不产生重复规则或配置块

## 前置要求

- Debian 11+ / Ubuntu 20.04+
- root 权限
- 落地机需要可解析的域名 + Cloudflare API Token（DNS-01 验证）
- 中转机需要 443 端口未被占用

## 版本

当前版本：v1.0
