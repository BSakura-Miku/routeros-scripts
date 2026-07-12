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

### 使用背景

RouterOS 自带 [MikroTik Cloud DDNS](https://help.mikrotik.com/docs/spaces/ROS/pages/97779929/Cloud#Cloud-DDNS)，一般场景直接使用它即可。

这个脚本主要面向以下情况：宽带没有公网 IPv4，但具有动态公网 IPv6；WireGuard 等服务需要使用只解析到 IPv6 的自定义域名。RouterOS Cloud 可能同时发布运营商分配的非公网 IPv4，客户端优先尝试该 IPv4 时会造成连接失败。因此这里单独维护 Cloudflare AAAA 记录，不创建 A 记录。

![RouterOS 脚本展示](Resource/iShot_2025-08-23_06.39.45.png)

### 功能特性

- 自动获取指定 PPPoE 接口的公网 IPv6。
- 排除 link-local、无效、禁用及 Deprecated 地址。
- 只更新 Cloudflare AAAA 记录，不写入 IPv4 A 记录。
- 仅在 IPv6 变化时调用 Cloudflare API。
- 使用 `check-certificate=yes` 验证 HTTPS 证书。
- 解析 Cloudflare JSON，只有 `success=true` 才缓存最新地址。
- 地址未变化时保持静默，避免每 5 分钟产生重复日志。

### 配置参数

需要替换：

```routeros
:local CFAPITOKEN "YOUR_CLOUDFLARE_API_TOKEN"
:local CFZoneID "YOUR_CLOUDFLARE_ZONE_ID"
:local CFRecordID "YOUR_CLOUDFLARE_RECORD_ID"
:local CFDNSNAME "YOUR_DDNS_HOSTNAME"
```

| 参数 | 含义 |
| --- | --- |
| `CFAPITOKEN` | Cloudflare API Token，不是 Zone ID 或 Global API Key |
| `CFZoneID` | 域名所在 Zone 的区域 ID |
| `CFRecordID` | 需要更新的那一条 AAAA DNS 记录 ID |
| `CFDNSNAME` | 完整域名，例如 `router.example.com` |
| `WANInterface` | 获取公网 IPv6 的 RouterOS 接口，默认 `pppoe-out1` |

### 创建 Cloudflare API Token

打开 [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)：

1. 登录 Cloudflare，进入右上角个人资料。
2. 打开“API 令牌”。
3. 选择“创建令牌”。
4. 使用“编辑区域 DNS”模板，或创建自定义令牌。
5. 权限设置为 `Zone / DNS / Edit` 和 `Zone / Zone / Read`。
6. Zone Resources 只选择需要更新的域名。
7. 创建令牌并妥善保存；Cloudflare 不会再次完整显示它。

不建议使用 Global API Key。最小权限 Token 即使泄露，影响范围也更小。

### 获取 Zone ID

1. 打开 [Cloudflare Dashboard](https://dash.cloudflare.com)。
2. 选择目标域名。
3. 进入“概述”。
4. 在页面右侧或底部的 API 区域找到 `Zone ID`。

### 创建 AAAA 记录

先在 Cloudflare DNS 页面手工创建一条 AAAA 记录：

```text
类型：AAAA
名称：router（按实际子域名填写）
IPv6：可以先填一个临时地址，例如 2001:db8::1
代理状态：仅 DNS（DNS only）
TTL：Auto
```

脚本第一次成功运行后会覆盖临时 IPv6。

### 获取 Record ID

Linux 或 macOS 安装 `curl` 和 `jq` 后执行：

```bash
CFAPITOKEN="你的 API Token"
CFZoneID="你的 Zone ID"
CFDNSNAME="router.example.com"

curl -sS \
  "https://api.cloudflare.com/client/v4/zones/${CFZoneID}/dns_records?type=AAAA&name=${CFDNSNAME}" \
  -H "Authorization: Bearer ${CFAPITOKEN}" \
  -H "Content-Type: application/json" | jq
```

返回结果示例：

```json
{
  "result": [
    {
      "id": "这里就是 CFRecordID",
      "name": "router.example.com",
      "type": "AAAA",
      "content": "2001:db8::1",
      "proxied": false,
      "ttl": 1
    }
  ],
  "success": true,
  "errors": [],
  "messages": []
}
```

将 `result[0].id` 填入脚本的 `CFRecordID`。如果 `result` 是空数组，请检查：

- `CFDNSNAME` 是否为完整域名。
- Cloudflare 是否已经存在对应的 AAAA 记录。
- Token 是否有目标 Zone 的读取权限。
- 查询的记录类型是否确实为 AAAA。

不使用 `jq` 时也可以删除命令最后的 `| jq`，然后手工查找 JSON 中的 `result[0].id`。

### 创建 RouterOS 脚本

在 `System -> Scripts` 新建：

```text
Name: cloudflare-ddns-ipv6
Policy: read, write, test, sensitive
```

将 [`scripts/cloudflare-ddns-ipv6.rsc`](scripts/cloudflare-ddns-ipv6.rsc) 的内容粘贴到 `Source`，替换参数后先手动运行一次。

正常更新时日志类似：

```text
CF-DDNS: updated successfully to 2001:db8::1234
```

再次运行时如果 IPv6 没变化，脚本不会写入新日志。

### 创建 Scheduler

```routeros
/system scheduler add name=CloudflareDDNS interval=5m \
    on-event="/system script run cloudflare-ddns-ipv6" \
    policy=read,write,test,sensitive
```

查看运行状态：

```routeros
/system scheduler print detail where name="CloudflareDDNS"
/log print where message~"CF-DDNS"
```

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

## 参考资料

- [MikroTik Cloud DDNS](https://help.mikrotik.com/docs/spaces/ROS/pages/97779929/Cloud#Cloud-DDNS)
- [bajodel/mikrotik-cloudflare-dns](https://github.com/bajodel/mikrotik-cloudflare-dns)
- [Mikrotik RouterOS 7.15 Cloudflare DDNS 脚本](https://tccmu.com/2024/08/06/rosddns/)
