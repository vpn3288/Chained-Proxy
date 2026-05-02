# v5.19 版本发布说明 (2026-05-02)

## 概述
本版本根据审查AI的深度代码审计报告，修复了所有CRITICAL和HIGH级别的问题，确保中转机和落地机能够长期、稳定、高速运行。

## 中转机脚本 (install_transit_v5.19.sh)

### CRITICAL 修复
- **[T-CRITICAL-1]** 修复健康检查cron heredoc语法错误
  - 问题：CRON结束标记后缺少换行，导致cron文件创建失败
  - 影响：健康检查完全失效，无法实现"几个月不管也能正常运行"的目标
  - 修复：在CRON标记后添加换行符

### HIGH 优先级修复
- **[T-HIGH-1]** 修复防火墙白名单规则顺序
  - 问题：使用-A追加规则，导致白名单在DROP规则之后失效
  - 修复：使用-I 1插入到链首，确保白名单优先生效
  
- **[T-HIGH-2]** 增强mack-a检测（已在v5.18实现）
  - 检测nginx.conf中的v2ray-agent配置冲突
  - 防止与mack-a脚本冲突

### MEDIUM 优化
- **[T-MEDIUM-1]** worker_connections随机化增强
  - 从70-130%扩大到50-150%范围
  - 添加质数扰动（97），增加随机性，防止指纹识别

### LOW 优化
- **[T-LOW-1]** 更新检查超时优化
  - 连接超时：5秒
  - 总超时：10秒
  - 重试次数：2次

## 落地机脚本 (install_landing_v5.19.sh)

### CRITICAL 修复
- **[L-CRITICAL-1]** 端口冲突检测增强
  - 问题：只检查端口占用，未检查systemd unit启用状态
  - 影响：重启后端口冲突导致服务启动失败
  - 修复：检查xray/v2ray/sing-box/hysteria等服务的启用状态

- **[L-C1]** 证书申请延迟真实实现
  - 问题：延迟逻辑写入脚本但未执行，注释说"跳过前台延迟"
  - 影响：无法模拟真实用户行为，GFW可能识别为自动化脚本
  - 修复：实现真实的30-90分钟随机延迟，支持Ctrl+C跳过

- **[L-C2]** IPv6侧漏风险修复
  - 问题：双栈VPS保留IPv6，但家宽伪装场景下IPv6会暴露真实位置
  - 影响：GFW通过IPv6地址识别出VPS而非家宽
  - 修复：无条件禁用IPv6，防止家宽伪装侧漏

### HIGH 优先级修复（已在v5.18实现）
- **[L-HIGH-1]** 证书续期失败告警
  - SSH登录时显示红色警告
  - 写入/etc/profile.d/xray-cert-alert.sh

- **[L-H2]** 1Panel端口放行
  - 在防火墙中放行EXTRA_PORTS
  - 支持1Panel/Docker容器网络

- **[L-H3]** 健康检查cron验证
  - 创建后验证文件是否成功
  - 确保健康检查真正生效

### MEDIUM 优化（已在v5.18实现）
- **[L-MEDIUM-1]** DNS传播智能等待
  - 动态探测TXT记录而非固定90秒
  - 使用dig查询Cloudflare DNS

- **[L-M1]** 证书续期优化
  - 移除--force参数
  - 让acme.sh自己判断是否需要续期

- **[L-M2]** TCP窗口随机化
  - 使用/dev/urandom生成随机值
  - 防止TCP窗口指纹识别

## 架构保持不变
- 中转机：Nginx stream SNI盲传
- 落地机：sing-box + Reality/Hysteria2/Tuic

## 升级建议
1. 备份现有配置：cp /etc/transit_manager/manager.conf /root/backup/
2. 下载新版本脚本
3. 重新运行安装脚本（会自动保留现有节点配置）
4. 验证服务状态：systemctl status nginx / systemctl status xray-landing

## 兼容性
- 完全兼容v5.18的配置文件
- 无需重新配置节点
- 平滑升级，零停机

## 测试环境
- Debian 12 (通过DD安装)
- CN2 GIA中转机（纯IPv4）
- 美国落地机（IPv4/双栈）
- 甲骨文ARM、谷歌云、家宽IP VPS

## 致谢
感谢审查AI团队的深度代码审计和详细修复建议。
