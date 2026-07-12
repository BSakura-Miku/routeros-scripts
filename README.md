# RouterOS Home Network Scripts

一组用于 RouterOS v7 家庭网络的自动化脚本。项目最初只包含 Cloudflare IPv6 DDNS，现已扩展为 DDNS、CNIP、旁路代理健康检查及 ARP/IPv6 Address List 同步工具集。

当前脚本在 RouterOS `7.23.2` 上验证。仓库中的 Token、Secret、Zone ID、Record ID 均为占位符，不包含生产环境凭据。

## 脚本

| 文件 | 用途 | 建议周期 | 权限 |
| --- | --- | --- | --- |
| [`cloudflare-ddns-ipv6.rsc`](scripts/cloudflare-ddns-ipv6.rsc) | 将 PPPoE 公网 IPv6 更新到 Cloudflare AAAA | 5 分钟 | `read,write,test,sensitive` |
| [`cnip-updater.rsc`](scripts/cnip-updater.rsc) | 下载并完整替换 `CN` Address List，失败自动回滚 | 每天 | `read,write,policy,test` |
| [`mihomo-health-check.rsc`](scripts/mihomo-health-check.rsc) | 检测 mihomo `Final` 代理链路，失败时切换备用 WAN | 1 分钟 | `read,write,test,sensitive` |
| [`sync-arp-address-lists.rsc`](scripts/sync-arp-address-lists.rsc) | 根据 ARP Comment 同步 IPv4/IPv6 Address List | 5 分钟 | `read,write` |

根目录的 [`routeros-cloudflare-ddns-ipv6.rsc`](routeros-cloudflare-ddns-ipv6.rsc) 为旧链接兼容副本，新部署建议使用 `scripts/` 中的文件。

## 使用方式

1. 在 RouterOS 打开 `System -> Scripts`。
2. 新建脚本，将对应 `.rsc` 文件内容粘贴到 `Source`。
3. 按下文修改变量、脚本名称和权限。
4. 手动运行一次并检查日志。
5. 验证成功后再创建 Scheduler。

不要直接运行仍包含 `YOUR_*` 占位符的脚本。

## Cloudflare IPv6 DDNS

需要替换：

```routeros
:local CFAPITOKEN "YOUR_CLOUDFLARE_API_TOKEN"
:local CFZoneID "YOUR_CLOUDFLARE_ZONE_ID"
:local CFRecordID "YOUR_CLOUDFLARE_RECORD_ID"
:local CFDNSNAME "YOUR_DDNS_HOSTNAME"
```

脚本会：

- 只选择 PPPoE 接口上有效、未禁用、未 Deprecated 的公网 IPv6。
- 使用 TLS 证书验证访问 Cloudflare API。
- 解析 API JSON，仅在 `success=true` 后缓存最新地址。
- 地址未变化时保持静默。

Scheduler：

```routeros
/system scheduler add name=CloudflareDDNS interval=5m \
    on-event="/system script run cloudflare-ddns-ipv6" \
    policy=read,write,test,sensitive
```

Cloudflare Token 只需要目标 Zone 的 `DNS:Edit` 和 `Zone:Read` 权限。

## CNIP Updater

默认下载：

```text
https://github.com/ruijzhan/chnroute
```

工作流程：

```text
检查旧列表 -> 备份 CN -> TLS 下载 -> 清空 CN -> 导入新列表
                                         |
                                         +-> 数量异常时恢复备份
```

默认接受 `6000-10000` 条记录。首次部署前必须已经存在有效的 `CN` 列表，否则脚本会拒绝覆盖。

Scheduler：

```routeros
/system scheduler add name=update_chnroute interval=1d start-time=08:00:00 \
    on-event="/system script run update_cn_ip" \
    policy=read,write,policy,test
```

## mihomo Health Check

需要替换：

```routeros
:local mihomoAddress "10.10.2.6"
:local controllerPort "9090"
:local apiSecret "YOUR_MIHOMO_API_SECRET"
:local routeComment "ROUTE_PRIMARY_IMM(Check Gateway)"
```

脚本调用 mihomo 控制 API，使 `Final` 当前选中的节点访问 `generate_204`：

```text
成功            -> 失败计数清零，恢复主路由
连续失败 3 次   -> 禁用指定主路由，由更高 distance 的 WAN 路由接管
后续恢复        -> 重新启用主路由
```

使用前需要：

- RouterOS 可以访问 mihomo Controller。
- mihomo 存在名为 `Final` 的策略组。
- 主代理路由具有唯一的 `routeComment`。
- 已配置更高 `distance` 的备用路由。

Scheduler：

```routeros
/system scheduler add name=mihomo_health_check interval=1m start-time=startup \
    on-event="/system script run mihomo_health_check" \
    policy=read,write,test,sensitive
```

## ARP Address List Sync

脚本根据 ARP Comment 中的关键词分类：

| 关键词 | Address List | 用途示例 |
| --- | --- | --- |
| `proxy` | `proxy_clients` | mihomo PBR、高优先级 QoS |
| `iot` | `iot_devices` | IoT 中优先级 QoS |
| `bt` | `bt_downloader` | BT 低优先级 QoS |
| `guest` | `guest_devices` | 访客策略 |
| `service` | `important_services` | 核心服务策略 |

同一 Comment 命中多个关键词时，优先级为：

```text
service > guest > bt > iot > proxy
```

自动条目使用 `AUTO_ARP |` 前缀。手工创建的静态 Address List 不会被修改。

- IPv4 timeout：24 小时，剩余 1 小时时刷新。
- IPv6 timeout：2 小时，剩余 15 分钟时刷新。
- Scheduler 每 5 分钟检查，但不会每次重建条目。
- IPv6 只同步公网地址和 `fd00::/8` ULA。

Scheduler：

```routeros
/system scheduler add name=sync_arp interval=5m \
    on-event="/system script run sync_arp" \
    policy=read,write
```

## 验证

```routeros
# 最近的脚本错误
/log print where topics~"script" and topics~"error"

# Scheduler 状态
/system scheduler print detail

# 自动同步的 IPv4/IPv6 条目
/ip firewall address-list print detail where comment~"^AUTO_ARP"
/ipv6 firewall address-list print detail where comment~"^AUTO_ARP"

# CNIP 数量和临时备份
/ip firewall address-list print count-only where list="CN"
/ip firewall address-list print count-only where list="CN_BACKUP"

# mihomo 健康计数
:global MihomoHealthFailCount
:put $MihomoHealthFailCount
```

## 安全注意事项

- 不要将 Cloudflare Token、mihomo Secret 或 RouterOS 导出文件提交到 Git。
- 限制 RouterOS 用户和脚本的 `sensitive` 权限。
- mihomo Controller 仅应对可信内网开放。
- Cloudflare Token 应使用最小权限并定期轮换。
- 部署前先在测试环境或维护窗口手动运行脚本。

## License

[MIT](LICENSE)
