#!/bin/bash
# quick_fix_v5.17_to_v5.18.sh
# 快速修复 v5.17 的配置问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     v5.17 → v5.18 快速修复脚本                                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查是否为root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须以 root 身份运行此脚本${NC}"
   exit 1
fi

# 检查是否安装了中转机
if [[ ! -f /etc/transit_manager/.installed ]]; then
    echo -e "${RED}错误: 未检测到中转机安装${NC}"
    echo "此脚本仅用于修复已安装的 v5.17 中转机"
    exit 1
fi

echo -e "${YELLOW}此脚本将修复 v5.17 中的配置错误${NC}"
echo ""
echo "需要修复的问题："
echo "  - meta文件中的 TRANSIT_IP 字段名错误（应为 LANDING_IP）"
echo "  - map文件中的IP地址错误（应为落地机IP）"
echo ""

# 获取所有meta文件
META_FILES=$(find /etc/transit_manager/conf -name "*.meta" -type f 2>/dev/null)

if [[ -z "$META_FILES" ]]; then
    echo -e "${RED}错误: 未找到任何配置文件${NC}"
    exit 1
fi

echo -e "${CYAN}找到以下配置：${NC}"
echo ""

# 显示当前配置
for meta in $META_FILES; do
    DOMAIN=$(grep '^DOMAIN=' "$meta" 2>/dev/null | cut -d= -f2)
    CURRENT_IP=$(grep '^TRANSIT_IP=' "$meta" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$CURRENT_IP" ]]; then
        CURRENT_IP=$(grep '^LANDING_IP=' "$meta" 2>/dev/null | cut -d= -f2)
    fi
    
    echo -e "  域名: ${GREEN}${DOMAIN}${NC}"
    echo -e "  当前IP: ${YELLOW}${CURRENT_IP}${NC}"
    echo ""
done

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}重要提示：${NC}"
echo "  上面显示的IP地址可能是错误的（中转机IP而非落地机IP）"
echo "  你需要提供每台落地机的真实公网IP地址"
echo ""
echo "  如何获取落地机IP？"
echo "  在每台落地机上执行: ${CYAN}curl -4 ifconfig.me${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "是否继续修复？[y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo -e "${CYAN}开始修复...${NC}"
echo ""

# 备份配置
BACKUP_DIR="/etc/transit_manager/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r /etc/transit_manager/conf "$BACKUP_DIR/"
cp -r /etc/nginx/stream-snippets "$BACKUP_DIR/"
echo -e "${GREEN}✓ 配置已备份到: $BACKUP_DIR${NC}"
echo ""

# 逐个修复
for meta in $META_FILES; do
    DOMAIN=$(grep '^DOMAIN=' "$meta" 2>/dev/null | cut -d= -f2)
    CURRENT_IP=$(grep '^TRANSIT_IP=' "$meta" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$CURRENT_IP" ]]; then
        CURRENT_IP=$(grep '^LANDING_IP=' "$meta" 2>/dev/null | cut -d= -f2)
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "修复域名: ${GREEN}${DOMAIN}${NC}"
    echo -e "当前IP: ${YELLOW}${CURRENT_IP}${NC}"
    echo ""
    
    # 询问正确的落地机IP
    while true; do
        read -p "请输入此域名对应的落地机IP地址: " LANDING_IP
        
        # 验证IP格式
        if [[ "$LANDING_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            echo -e "${RED}错误: IP地址格式不正确，请重新输入${NC}"
        fi
    done
    
    # 获取端口
    PORT=$(grep '^PORT=' "$meta" 2>/dev/null | cut -d= -f2)
    PORT=${PORT:-8443}
    
    # 生成safe名称
    SAFE=$(echo "$DOMAIN" | tr '.' '_' | tr -cd 'a-zA-Z0-9_-')
    HASH=$(echo -n "$DOMAIN" | sha256sum | awk '{print substr($1,1,64)}')
    SAFE="${SAFE:0:60}_${HASH}"
    
    # 修复map文件
    MAP_FILE="/etc/nginx/stream-snippets/landing_${SAFE}.map"
    if [[ -f "$MAP_FILE" ]]; then
        echo "    ${DOMAIN}    ${LANDING_IP}:${PORT};" > "$MAP_FILE"
        chmod 600 "$MAP_FILE"
        echo -e "${GREEN}✓ map文件已修复: $MAP_FILE${NC}"
    else
        echo -e "${YELLOW}⚠ map文件不存在，创建新文件${NC}"
        echo "    ${DOMAIN}    ${LANDING_IP}:${PORT};" > "$MAP_FILE"
        chmod 600 "$MAP_FILE"
    fi
    
    # 修复meta文件（将TRANSIT_IP改为LANDING_IP）
    if grep -q '^TRANSIT_IP=' "$meta"; then
        sed -i "s/^TRANSIT_IP=.*/LANDING_IP=${LANDING_IP}/" "$meta"
        echo -e "${GREEN}✓ meta文件已修复: $meta${NC}"
    elif grep -q '^LANDING_IP=' "$meta"; then
        sed -i "s/^LANDING_IP=.*/LANDING_IP=${LANDING_IP}/" "$meta"
        echo -e "${GREEN}✓ meta文件已更新: $meta${NC}"
    else
        # 添加LANDING_IP字段
        sed -i "/^DOMAIN=/a LANDING_IP=${LANDING_IP}" "$meta"
        echo -e "${GREEN}✓ meta文件已添加LANDING_IP字段: $meta${NC}"
    fi
    
    echo ""
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 测试Nginx配置
echo -e "${CYAN}测试Nginx配置...${NC}"
if nginx -t 2>&1; then
    echo -e "${GREEN}✓ Nginx配置测试通过${NC}"
else
    echo -e "${RED}✗ Nginx配置测试失败！${NC}"
    echo "正在恢复备份..."
    cp -r "$BACKUP_DIR/conf/"* /etc/transit_manager/conf/
    cp -r "$BACKUP_DIR/stream-snippets/"* /etc/nginx/stream-snippets/
    echo -e "${YELLOW}配置已恢复，请检查错误后重试${NC}"
    exit 1
fi

# 重载Nginx
echo ""
echo -e "${CYAN}重载Nginx...${NC}"
if systemctl reload nginx; then
    echo -e "${GREEN}✓ Nginx重载成功${NC}"
else
    echo -e "${RED}✗ Nginx重载失败！${NC}"
    echo "尝试重启..."
    if systemctl restart nginx; then
        echo -e "${GREEN}✓ Nginx重启成功${NC}"
    else
        echo -e "${RED}✗ Nginx重启失败！${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    修复完成！                                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "下一步："
echo "  1. 测试从中转机到落地机的连接："
echo ""

for meta in $META_FILES; do
    LANDING_IP=$(grep '^LANDING_IP=' "$meta" 2>/dev/null | cut -d= -f2)
    PORT=$(grep '^PORT=' "$meta" 2>/dev/null | cut -d= -f2)
    PORT=${PORT:-8443}
    
    if [[ -n "$LANDING_IP" ]]; then
        echo "     nc -zv ${LANDING_IP} ${PORT}"
    fi
done

echo ""
echo "  2. 使用客户端测试连接"
echo ""
echo "备份位置: $BACKUP_DIR"
echo ""
