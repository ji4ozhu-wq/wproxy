# 可交互控件标识表 — 无极 Wuji

> 命名规则：`wuji.<页面>.<控件>`。iOS 用 `accessibilityIdentifier`。
> 本文件由各页面 owner 的分表合并而成（ids-data / ids-engine / ids-pagesA / ids-pagesB），如有冲突以代码为准。

## 全局（Lead）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.home.connectPill` | 首页 | 连接控件（大号胶囊按钮：未连接蓝色 Connect / 已连接灰色 Disconnect；忙时禁用并显示进度） |
| `wuji.tab.connect` / `wuji.tab.nodes` / `wuji.tab.settings` | 主 Tab | 三个标签项（如系统暴露） |


---

<!-- merged from ids-data.md -->

# 数据层说明 — 无极 Wuji（data teammate）

> 对应 `docs/impl-plan.md` B1–B10。数据层没有 UI 控件，因此本文件不登记
> `accessibilityIdentifier`（页面标识见 `docs/ids-pagesA.md` / `docs/ids-pagesB.md` /
> Lead 的 `docs/ids.md`）；这里记录**给页面/引擎调用的 API 契约、数据格式与边界**。
>
> 负责人：data。写权限范围：`Wuji/Core/Store/`、`Wuji/Core/Import/`、`Wuji/Core/Utils/`、
> `Wuji/Core/Routing/CountryDirectory.swift`、`Wuji/Resources/country_cidrs.json`、
> `tools/gen_country_cidrs.py`、`WujiTests/DataTests.swift`、本文件。

## 1. 存储（B1–B4）

- 文件：App Group 容器内 `wuji.sqlite3`（取不到 App Group 时回退 Application Support）；
  主 App 写，NE 扩展只读。打开时启用 `journal_mode=WAL`、`synchronous=NORMAL`、
  `foreign_keys=ON`、`busy_timeout=5000`，并自动建表/补列（旧库用 `ALTER TABLE` 迁移，不丢数据）。
- 全部公开方法线程安全；`transaction(_:)` 内的 `execute`/`query` 会复用同一连接加入事务（可重入，不会死锁）。
- `execute` 支持 `;` 分隔的多语句脚本（设置页“清空数据”直接用一条脚本即可）。
- 表：`groups` / `profiles` / `subscriptions` / `settings`。列名与阶段 1 骨架保持一致，另加
  `profiles.vmess_security TEXT NOT NULL DEFAULT 'auto'`（VMess 加密方式，默认 `auto`）。
- `profileStore.delete(groupID:)` / `subscriptionStore.delete(subscriptionID:)` 依赖
  `ON DELETE CASCADE`，会连带删除该组节点；删除订阅的事务同时删除订阅行、组和节点。
- `SettingsStore` 仍以单行 JSON（key = `app_settings`）持久化 `AppSettings`，`load()` 无数据时返回
  `.default`。新增 `update { inout }`、`reset()`、`rawValue(forKey:)` 便于原子修改设置。
- `ProfileStore.updateLatencies(_:at:)` 批量回写测速结果；`findDuplicate(of:)` 用于表单重复节点校验；
  `setActiveProfile(id:)` 改为通过 SettingsStore 写 `activeProfileID`（旧实现 UPDATE 不存在的行，已修复）。

## 2. URI 解析 / 编码（B5）

入口：`URIParser`（页面用，`AppState.uriParser`）→ `URIParserCore.shared`（实现，`@testable` 单测可直接用）。

| API | 行为 |
|---|---|
| `parse(_:groupID:)` | 解析多行文本/整段 base64 订阅正文；一条都识别不出时抛 `URIParseError` |
| `parseDetailed(_:groupID:) -> URIParseReport` | 返回 `profiles` + `failures`（逐行失败原因），导入页可提示部分失败 |
| `parseLink(_:groupID:)` | 解析单条链接，非法输入抛 `URIParseError` |
| `encode(_:)` | 编码回分享链接；`rawURI` 与节点字段仍一致时原样返回（保留 ALPN/plugin 等未建模字段），否则按字段重建 |
| `parseSubscriptionBody(_:)` | 从订阅正文提取链接：明文列表或 base64（标准/URL-safe、有无 padding、双层 base64 均可） |
| `canParse(_:)` | 首条是否为可导入链接 |

支持的 scheme：`vmess://`、`vless://`、`trojan://`、`ss://`。字段映射：

| 协议 | 支持内容 |
|---|---|
| VMess | legacy `vmess://base64(JSON)`（`ps/add/port/id/aid/scy/net/type/host/path/tls/sni/fp`，数字可为字符串）；`#fragment` 覆盖名称；`net` 支持 tcp/ws/grpc/h2/http；grpc 的 service 取 `path`/`serviceName`；`vmessSecurity` 取 `scy`（缺省 `auto`） |
| VLESS | `vless://uuid@host:port?...`；`security=tls/reality/none`、`pbk`/`sid`/`spx`(忽略)/`fp`/`sni`/`flow`/`type`/`path`/`host`/`serviceName`/`allowInsecure`；UUID 非法会报错 |
| Trojan | `trojan://password@host:port?...`；密码 percent-decode（允许含 `@`）；`security` 缺省 = tls；`type`/`path`/`host`/`sni`/`fp`/`allowInsecure` |
| Shadowsocks | SIP002（userinfo 为 base64url 或明文 `method:password`，支持 `/?plugin=` 结尾）与旧式整段 base64(`method:password@host:port`)；`method` 统一小写；`plugin` 无对应字段，导入时忽略 |

已知取舍（不阻塞交付，记录在此）：kcp/quic 等未建模传输会退化为 `tcp`；SS 的 `plugin`（obfs/v2ray-plugin）
不落库；`alpn`/`spx` 不落库，但 `rawURI` 会保留原链接，复制/二维码分享仍是最初内容。
错误文案：`URIParseError` 走 `Localizable.strings` 已有的 `error.uri.unsupported` / `error.uri.none`，
`malformed` 携带英文技术细节，页面可自行改写成更友好的本地化提示。

## 3. 订阅（B6）

- `SubscriptionService.fetch(url:groupID:name:)`：仅 http/https、UA `Wuji/1.0 (iOS)`、20s 超时、
  忽略本地缓存、响应 ≤8MB；正文按 base64/明文解析；`Subscription-Userinfo` 解析 upload/download/
  total/expire（秒或毫秒）与 `profile-update-interval`（小时→秒），值可能是 base64，也兼容。
- 错误分类 `SubscriptionError`：`invalidURL` / `httpStatus(Int)` / `invalidBody` / `emptySubscription`，
  文案复用已有 `error.subscription.*` 键。
- 刷新流程约定：先 `fetch` 成功后再 `profileStore.upsert(profile:)`（或 `replaceProfiles(inGroup:with:)`）
  写节点、`subscriptionStore.upsert` 更新流量/到期/`lastUpdatedAt`；失败时 `recordFailure(_:error:)`
  只写 `lastError` 并保留旧节点。自动更新判定：`SubscriptionStore.isDue(_:now:)` /
  `dueForAutoUpdate(globalEnabled:)`（间隔从 `lastUpdatedAt ?? createdAt` 起算；全局开关关闭则不判）。
- 页面现有的 `fetch(url:groupID:name:)` 签名保持不变。

## 4. 延迟测速（B7）

- `LatencyTester.test(profile:timeout:)`：TCP 三次握手耗时（ms），失败/超时/取消返回 `nil`；主 App 侧直连、不走隧道。
- 批量：`testAll(profiles:timeout:onResult:)`（原回调 API 保持不变，页面在用）、
  `testAll(profiles:timeout:)`（返回 `[profileID: latency]`）、
  `testAndStore(profiles:store:timeout:onResult:)`（每条完成即写库，失败也写 `latency_at` 便于行状态）。
- 并发默认 8、单节点超时默认 5s（`LatencyTester.defaultConcurrency/defaultTimeout`）。
- 取消：`cancelAll()` 或取消调用方 `Task`；在飞探测立即返回 `nil`，不会等到超时。

## 5. 国家 CIDR 数据与路由（B8/B9）

- 产物：`Wuji/Resources/country_cidrs.json`，**249 个国家/地区、249,596 条 CIDR、4.22 MB**
  （< 8MB 预算），JSON 结构 `{version, source, generated, countries: {CC: [cidr...]}}`；
  每个国家内已折叠成最小 CIDR 集合（IPv4 在前、IPv6 在后），可直接放进 Xray 的 `ip` 规则。
- 生成：`python3 tools/gen_country_cidrs.py`。数据源 `ipverse/rir-ip`（= country-ip-blocks，五家 RIR 委派
  数据、CC0 1.0）；主数据集缺的 11 个 ISO 代码（BV/CC/CX/EH/GS/HM/PN/SH/SJ/TF/UM）从同发布的
  `ipverse/geo-ip-blocks` 补齐。脚本校验国家数 ≥240、常用地区非空、CIDR 合法、产物 <8MB；
  下载用 curl，遵循 env 里的 `HTTPS_PROXY`/`ALL_PROXY`（**代理只存在于开发机环境，不进代码与产物**）。
  离线复现：`python3 tools/gen_country_cidrs.py --source-dir <country-ip-blocks 仓库根> --supplement-source-dir <geo-ip-blocks 仓库根>`；
  校验现有产物：`python3 tools/gen_country_cidrs.py --check`（只校验不写盘）。
- `CountryDirectory`：懒加载（首次访问才解码，避免拖慢冷启动）；`countries`（按系统语言本地化名称排序、
  `CountryInfo.flag` 提供国旗 emoji）、`cidrs(for:)`、`cidrs(for codes:)`（去重）、
  `searchCountries(_:)`、`country(code:)`、`hasCountryCode(_:)`、`totalCIDRCount`、`datasetSource/Generated`。
- B9：`CountryDirectory.bypassCIDRs(for: settings)` 生成 `XrayConfigBuilder` 的 bypassCIDRs——
  `routing_mode=rule` 时 = `privateCIDRs`（10/8、172.16/12、192.168/16、169.254/16、100.64/10、127/8、
  fc00::/7、fe80::/10、::1/128，且 `bypass_lan=1` 时）+ 选中地区 CIDR；`global` 模式返回空数组。
  `CountryDirectory.privateCIDRs` 供引擎/首页复用。
- 署名（关于/开源许可必须写）：国家 CIDR 数据来自 ipverse（CC0 1.0），基于 RIR 委派数据生成。

## 6. 演示数据（B10）

- 仅 `DEBUG`：首次打开数据库时（或 `AppState.reload()` 调用 `DemoSeed.seedIfNeeded(store:)`）种入
  **9 个节点 + 2 个分组 + 1 个演示订阅**；Release 不种。
- 分组：`Manual`（4 条，`ProfileStore.manualGroupID`）与 `Airport Demo`（5 条，订阅组，
  `demo-group-airport`）；协议覆盖 VMess/VLESS/Trojan/Shadowsocks，传输覆盖 tcp/ws/grpc，含 TLS 与 REALITY；
  7 条带延迟、1 条无延迟（演示超时态）；地址全部为 TEST-NET `192.0.2.0/24`、`198.51.100.0/24`。
- 每个演示节点都带可解析的 `rawURI`（复制 URI / 二维码可直接演示）。
- 演示订阅：`Airport Demo`，间隔 24h、100GiB 总量、45 天后到期、`lastUpdatedAt` 1 小时前（不会立刻触发自动更新）；
  URL 用保留域名 `demo.invalid`，不会误连真实服务。
- 幂等：数据库同目录 sidecar 文件 `wuji.sqlite3.demo-seeded` 记录已种入；**清空数据不会复活演示节点**，
  只有数据库已有用户数据时也不会覆盖。测试可直接 `DemoSeed.seedIfNeeded(db:)`（临时库不会被自动种入）。

## 7. 单测（F1，`WujiTests/DataTests.swift`）

覆盖：库打开/WAL/多语句/事务回滚/级联删除；设置与 4 协议节点 round-trip（含 `vmessSecurity`）；
URI 解析 4 协议各 ≥2 例（VMess 含 legacy base64 JSON）+ 编码 round-trip + 非法输入；
订阅正文 base64（标准/URL-safe/无 padding/双层）与 `Subscription-Userinfo`；
订阅拉取（`URLProtocol` mock）与错误分类；国家 CIDR 数据（≥240 国家、常用地区、CIDR 合法、<8MB）
与 bypass 规则（rule/global/LAN）；演示数据幂等与 TEST-NET 约束；测速成功/失败/取消/批量回写。

运行：

```bash
cd app_src/wuji
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'platform=iOS Simulator,id=7EFFAD4E-84B0-4786-8B4D-87B70D6BC452' \
  -derivedDataPath /tmp/wuji-dd-data test
```

---

<!-- merged from ids-engine.md -->

# 交互标识与引擎接口 — 无极 Wuji（engine 负责 C1–C10）

> 本文件记录 **内核 / NetworkExtension** 相关实现与验证口径。隧道与 NE 扩展没有任何
> 用户界面，因此这里没有 `accessibilityIdentifier` 条目；主 App 里与连接相关的按钮、
> 状态文案等控件标识归各自页面角色（`docs/ids.md` 汇总时合并）。
>
> 责任人：engine。代码：`Wuji/Core/Routing/XrayConfigBuilder.swift`、
> `Wuji/Core/Tunnel/TunnelController.swift`、`WujiTunnel/`、`WujiTests/EngineTests.swift`、
> `tools/build_libxray.sh`、`tools/libxray-patch/`。

## 0. 控件标识

无。NE 扩展不参与 UI 测试；主 App 的连接按钮/状态卡片由 Lead（Home）与 pages-b（Settings）
在自己的 `ids` 文件里登记。

## 1. 数据通道（主 App ⇄ 扩展）

两条通道，互相独立：

### 1.1 App Group 文件（`group.com.juejin.ios.wuji`）

| 文件 | 写入方 | 读取方 | 结构（Codable，`Wuji/Core/Models`） |
|---|---|---|---|
| `active_tunnel.json` | 主 App（`TunnelController.prepareAndStart`） | 扩展（`PacketTunnelProvider`） | `TunnelLaunchConfig { xrayJSON: String, onDemandEnabled: Bool, onDemandMode: OnDemandMode }` |
| `tunnel_status.json` | 扩展（启动/停止/出错时） | 主 App（启动失败原因、状态同步） | `TunnelStatusFile { state: "connected"\|"disconnected"\|"error", message: String?, updatedAt: Date }` |
| `tunnel_traffic.json` | 扩展（连接期间每秒） | 主 App（备用，主路径是 provider message） | `TunnelSessionStats { uploadBytes, downloadBytes, connectedAt, uplinkRate, downlinkRate }` |

- `xrayJSON` 是主 App 生成的完整 Xray 配置（不含 fd）；扩展读出后在内存里写入
  `env["xray.tun.fd"]` 再 `runXray`，**App Group 文件里永远不落 fd**。
- `Date` 使用 Foundation 默认编码（自 2001-01-01 的秒数），两端同为 `JSONDecoder()` 默认策略。
- 写入全部 `.atomic`。

### 1.2 `NETunnelProviderSession.sendProviderMessage`

主 App → 扩展（请求是 UTF-8 JSON）：

| 请求 | 扩展响应 |
|---|---|
| `{"type":"traffic"}` | `TunnelSessionStats` JSON（累计字节 + 扩展计算的速率 + `connectedAt`） |
| `{"type":"status"}` | `TunnelStatusFile` JSON（当前 running 状态） |
| `{"type":"version"}` | `{"version":"<xray version>"}` |

- 主 App 侧入口：`TunnelController.requestTrafficStats() async -> TunnelSessionStats?`
  （速率按两次累计值差分重算，`AppState` 每秒调用）。
- 消息类型字符串在两处各自定义：`TunnelController.swift` 与
  `PacketTunnelProvider.swift` 的 `ProviderMessage` 枚举；改动必须同步。

### 1.3 `NETunnelProviderProtocol.providerConfiguration`

```json
{ "wujiTunnelConfig": { "serverHost": "<节点域名/IP>", "configFile": "active_tunnel.json" } }
```

扩展只用它拿 `serverHost`（`tunnelRemoteAddress` 与代理服务器 IP 排除路由），
真正的配置走 App Group 文件（配置可达数 MB，不适合塞进 providerConfiguration）。
`serverAddress` 同时设为节点地址，系统 VPN 列表里可读。

## 2. Xray 配置结构（C1）

`XrayConfigBuilder.build(XrayBuildInput) throws -> String`，输入：

```swift
XrayBuildInput {
    profile: NodeProfile          // 节点（4 协议 + 传输/TLS/REALITY 字段）
    settings: AppSettings         // routingMode / bypassLAN / ...
    bypassCIDRs: [String]         // 主 App 用 CountryDirectory 生成的直连 CIDR
    dnsServer: String = "https://1.1.1.1/dns-query"
    mtu: Int = 1380
    serverIPs: [String] = []      // 已解析的代理服务器 IP（可选，防回环规则更精确）
}
```

生成的 JSON（键按字母序，便于 diff/单测）：

| 段 | 内容 |
|---|---|
| `log` | `{"loglevel":"none"}`（NE 约 50MB jetsam 上限，不写日志） |
| `stats: {}` + `policy.system` | `statsInboundUplink/Downlink = true`：给 `getTrafficStats` 提供 `inbound>>>tun-in>>>traffic>>>uplink/downlink` 计数器 |
| `inbounds` | 单个 `tun` 入站，`tag = "tun-in"`，`settings = {name:"utun", mtu:1380, gateway:["169.254.10.1/30"]}`；`sniffing.enabled=false`（分流按 IP 字面量匹配，不需要域名重写，省 CPU/内存） |
| `outbounds` | 顺序 = `proxy`（节点协议）、`direct`（freedom）、`dns-out`（protocol dns）；`mux` 关闭 |
| `dns` | 单个 DoH `https://1.1.1.1/dns-query`、`queryStrategy:"UseIP"`、`disableFallback:true`（A/AAAA 都返回，IPv6-only 网络可用；查询不走系统解析，避免泄漏） |
| `routing` | 见下 |

routing 规则顺序（命中即停）：

1. `port:"53"` → `dns-out`：tun 里所有 DNS（系统 DNS 指向 `198.18.0.2` / `fd00:1234::2`，任何目的 53 端口）都由 dns app 应答；
2. DoH 上游 IP（默认 `1.1.1.1/32`）→ `proxy`：即使选中的直连国家把该 IP 包进去，DNS 也不会绕开代理泄漏；
3. 代理服务器地址（IP → `/32`、`/128`；域名 → `domain:<host>`）→ `direct`：防回环保守规则；
4. `settings.routingMode == .rule` 时：`bypassCIDRs`（局域网 + 选中地区，去重）→ `direct`；
5. 兜底：`network:"tcp,udp"` → `proxy`。

**全局模式**（`.global`）不生成第 4 条，`bypassCIDRs` 一律忽略；第 2/3 条保留。
`mtu` 与 NE 的 `NEPacketTunnelNetworkSettings.mtu` 都是 1380。

4 协议 / 传输映射：

| 模型 | 配置 |
|---|---|
| VMess | `vnext[].users[].id/alterId/security`（`security` 取 `NodeProfile.vmessSecurity`，空回退 `"auto"`） |
| VLESS | `vnext[].users[].id`、`encryption:"none"`、可选 `flow` |
| Trojan | `servers[].password` |
| Shadowsocks | `servers[].method/password` |
| `.tcp/.ws/.grpc/.h2/.http` | `network = tcp / ws / grpc / xhttp / xhttp`；`h2/http` 用 `xhttpSettings{mode:"stream-one"}`（当前 Xray-core 已移除旧 HTTP/2 传输，`testXray` 会拒绝 `network:"http"`，见 §7） |
| TLS | `tlsSettings{serverName(默认=server), allowInsecure, fingerprint?}` |
| REALITY | `realitySettings{serverName, fingerprint(默认 chrome), publicKey, shortId, spiderX:"/"}`；Shadowsocks 不支持 REALITY（构建期报错） |

构建期校验（`XrayBuildError`）：server 非空、port 1–65535、VMess/VLESS UUID 合法、
Trojan/SS 密码、SS method、REALITY publicKey、gRPC serviceName 非空、产物 >15 MiB 报
`configTooLarge`（libXray Invoke 上限 16 MiB）。

## 3. 隧道控制（C2/C3/C7）

`TunnelController: TunnelControlling`（`Wuji/Core/Tunnel/TunnelController.swift`）

| 成员 | 签名 | 说明 |
|---|---|---|
| `state` | `var state: TunnelState { get }` | 线程安全读；状态变化回调到主线程 |
| `onStateChange` | `var onStateChange: ((TunnelState) -> Void)?` | 主线程回调 |
| `prepareAndStart` | `func prepareAndStart(config: TunnelLaunchConfig, serverHost: String) async throws` | 写 `active_tunnel.json` → 创建/复用 `NETunnelProviderManager` → 下发 `providerConfiguration` / `enforceRoutes` / 按需规则 → 保存 → `startVPNTunnel()` → 等 `connected`（45s 超时） |
| `stop` | `func stop() async` | `stopVPNTunnel()` + 等 disconnected（5s）后置 `.disconnected` |
| `requestTrafficStats` | `func requestTrafficStats() async -> TunnelSessionStats?` | 走 `sendProviderMessage("traffic")`，按累计值差分算速率 |
| `resetConfiguration` | `func resetConfiguration() async throws` | 删除本 App 的所有 NE 配置 + 清 App Group 三个文件 + 状态复位（设置页「重置 VPN 配置」） |
| `syncSystemState` | `func syncSystemState() async` | 重新读系统 VPN 状态（前台刷新/启动时同步，处理系统设置断开、其他 App 占用） |
| `updateOnDemandMode` | `func updateOnDemandMode(_ mode: OnDemandMode) async` | 不改连接状态，只把按需规则写入已存在的配置（设置页开关用） |
| `isConfigured` | `var isConfigured: Bool { get }` | 系统里是否已有本 App 的隧道配置 |

调用现状：`resetConfiguration()` 已由 `AppState.resetVPNConfiguration()`（设置页）接线；
`syncSystemState()` / `updateOnDemandMode(_:)` / `isConfigured` 目前还没有调用点，建议接线方式：

```swift
// RootView / App 前台刷新（D6）
Task { await app.tunnel.syncSystemState() }

// 设置页改「按需连接」并持久化后（C7）
await app.tunnel.updateOnDemandMode(app.settings.onDemandMode)
```

按需规则（C7）：`off` → `isOnDemandEnabled=false`；`always` → `[Connect]`；
`wifi` → `[Connect(.wiFi), Disconnect(.cellular)]`；`cellular` → `[Connect(.cellular), Disconnect(.wiFi)]`
（`NEOnDemandRule.interfaceTypeMatch`）。

## 4. NE 扩展（C4/C5/C6）

`WujiTunnel/PacketTunnelProvider.swift`，`NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).PacketTunnelProvider`。

`startTunnel` 流程：

1. 读 `active_tunnel.json`（缺失 → 出错回调，App 显示「无配置」）；
2. 后台队列解析代理域名 IP（`getaddrinfo`，失败不阻塞）；
3. 主线程 `setTunnelNetworkSettings`：
   - IPv4 `198.18.0.1/16`、IPv6 `fd00:1234::1/64`、MTU 1380；
   - `includedRoutes`：`0.0.0.0/0` + `::/0`；`excludedRoutes`：RFC1918 / 169.254/16 / 127/8 /
     100.64/10 / 224/4 / 255.255.255.255，IPv6 ::1 / fe80::/10 / fc00::/7 / ff00::/8，
     以及解析到的代理服务器 IP /32（防回环）；
   - DNS：`198.18.0.2`（v4）+ `fd00:1234::2`（v6），`matchDomains=[""]`；
4. `setTunnelNetworkSettings` 完成（系统已在扩展进程创建 utun）后，
   `TunFdResolver.utunFileDescriptor(expectedInterfaceAddress: "198.18.0.1")` 找 fd；
5. `XrayRunner.run(configJSON:tunFileDescriptor:)`：解析配置 → 写
   `env["xray.tun.fd"]=fd` → `Invoke(runXray)` → `Invoke(getXrayState)` 复核；
6. 写 `tunnel_status.json = connected`、写一次 `tunnel_traffic.json`、启动 1s 流量定时器、
   回调 success；任何一步失败 → 写 `state:"error"` + `message` 并回传错误。

`stopTunnel`：停定时器 → `Invoke(stopXray)` → 写 `disconnected` + 停止原因 → 回调。
`sleep`/`wake`：暂停/恢复流量定时器。
`handleAppMessage`：见 §1.2。流量定时器里若发现内核已退出（`getXrayState=false`），
写 error 状态并 `cancelTunnelWithError`，让 App 显示错误而不是假「已连接」。

### TunFdResolver（纯 POSIX，无 KVC/私有 API）

`WujiTunnel/TunFdResolver.swift`：

1. `socket(AF_SYSTEM=32, SOCK_DGRAM, SYSPROTO_CONTROL=2)` → `ioctl(CTLIOCGINFO=0xC0644E03, ctl_info)`
   拿到 `com.apple.net.utun_control` 的 control id（`sys/kern_control.h` 未暴露给 Swift，
   该 ABI 常量在文件内声明）；
2. 遍历 fd `0...1024`：`getpeername` 必须是 `AF_SYSTEM`，且 peer `sockaddr_ctl.sc_id == control id`；
3. 用 `getsockopt(SYSPROTO_CONTROL, UTUN_OPT_IFNAME=2)` 取 `utunN` 名字；
4. 优先返回「接口地址 = 扩展刚设置的 198.18.0.1」的那个 fd（`getifaddrs` 反查接口名），
   否则取 unit 最大的（新创建的）socket，并记录日志。

### XrayRunner（libXray 桥）

`WujiTunnel/XrayRunner.swift`：`CGoInvoke/CGoFree` 生命周期、请求/响应封包
（`apiVersion:3`）、16 MiB 保护、`run/stop/isRunning/version/trafficSample`。
扩展里所有 Go/Xray 调用都在 `xrayQueue`（串行后台队列）上执行，不阻塞 NE 回调线程。

## 5. 流量统计（C6）

- 配置开启 `policy.system.statsInboundUplink/Downlink` + `stats:{}`，Xray 为
  `tun-in` 建立 `inbound>>>tun-in>>>traffic>>>uplink|downlink` 计数器。
- 本地 libXray fork 新增 invoke 方法 `getTrafficStats`（见 §6），扩展每秒读一次；
- 主路径 `sendProviderMessage("traffic")` → `TunnelSessionStats`（累计字节）；
  App 内 `requestTrafficStats()` 差分算速率；扩展每秒把同一份数据写 `tunnel_traffic.json` 作兜底；
- 已用真实流量验证（§7）：64 KB HTTP 通过 Xray SOCKS 入站后
  `uplink=103, downlink=65751`。

## 6. libXray 本地 fork（C9）

- 补丁：`tools/libxray-patch/wuji-traffic-stats.patch`（相对上游 commit
  `5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3`），改动 3 个文件：
  - `invoke.go`：`Invoke` 分派 `getTrafficStats`；
  - `invoke_model.go`：方法常量 + `GetTrafficStatsRequest{inboundTag}` / `GetTrafficStatsResponse{uplink,downlink}`；
  - 新增 `traffic_stats.go`（package libXray）与 `xray/traffic.go`（读 `core.Instance` 的
    `stats.Manager` 计数器，与 run/stop 同锁）。
- `tools/build_libxray.sh`：`git clone/fetch` → `checkout -f <pinned commit>` →
  `reset --hard` + `clean -fd` → 应用 `tools/libxray-patch/*.patch` →
  `python3 build/main.py apple go` → `lipo -thin arm64` 模拟器 slice →
  `xcodebuild -create-xcframework` 生成 `Frameworks/LibXray.xcframework`
  （iOS device arm64 + iOS simulator arm64，去掉 macOS/tvOS slice）。
- 已按该脚本重建成功；`Frameworks/LibXray.xcframework` 是**补丁后的产物**（体积 +1.2KB）。
- 迁移上游：`LIBXRAY_COMMIT=<sha> tools/build_libxray.sh`，并重新生成 patch。

## 7. 验证

### 7.1 单元测试（模拟器，通过）

```bash
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'platform=iOS Simulator,id=7EFFAD4E-84B0-4786-8B4D-87B70D6BC452' \
  -derivedDataPath /tmp/wuji-dd-engine test -only-testing:WujiTests/EngineTests
```

`WujiTests/EngineTests.swift` 22 条：4 协议 outbound 字段、VMess security 回退、
ws/grpc/xhttp 传输、TLS/REALITY、tun 入站（tag/mtu/不含 fd/env）、DoH DNS、
policy stats、routing 顺序/53 端口/DoH 上游钉代理/代理服务器直连/域名直连/
bypass 去重/全局模式不生成 bypass、兜底 proxy、确定性输出、非法节点抛错。

全量 `WujiTests`（data + engine + smoke）55 条全绿。

### 7.2 Xray 内核接受性 + 流量（开发机，可复现）

```bash
tools/build_libxray.sh                          # 先重建含补丁的 xcframework
tools/libxray-patch/validation/run_validation.sh
```

用重建后的 **macOS** libXray slice 编译 C driver，直接用 app 的
`Models.swift`+`XrayConfigBuilder.swift` 生成配置，然后：

- `getTrafficStats` 方法存在（未运行时返回 `xray is not running`，而不是 unknown method）；
- 9 份配置全部被 `testXray` 接受：VMess TCP+TLS、VMess WS+TLS、VLESS TCP+REALITY、
  VLESS gRPC+TLS、Trojan TCP+TLS、Trojan XHTTP（旧 h2 映射）、SS TCP、全局模式、
  ~16k CIDR 大分流表（330KB 配置）；
- 真实流量：SOCKS 入站 → `curl` 取 64KB → `getTrafficStats` 返回
  `uplink=103, downlink=65751`；`stopXray` 后再次读取报 `xray is not running`。

> 该验证跑在 macOS 上（`testXray` 只构建/关闭实例，不启动监听；SOCKS 入站代替 tun），
> 不替代真机 NE 验证。

### 7.3 编译

```bash
# 模拟器（主 App + 扩展）
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'platform=iOS Simulator,id=7EFFAD4E-84B0-4786-8B4D-87B70D6BC452' \
  -derivedDataPath /tmp/wuji-dd-engine build
# 真机架构编译（不签名）
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/wuji-dd-engine-device \
  CODE_SIGNING_ALLOWED=NO build
```

`WujiTunnel` 需要链接 `libresolv`（`res_9_ninit/nsearch/nclose`，来自 libXray 的 cgo
DNS resolver），已加在 `project.yml` 的 WujiTunnel `OTHER_LDFLAGS`。

实测：模拟器 build ✅、`generic/platform=iOS`（arm64 真机架构，CODE_SIGNING_ALLOWED=NO）✅；
真机 Debug 包 `Wuji.app` 49MB、其中 `WujiTunnel.appex` 33MB（debug dylib 未 strip，含静态
LibXray；Release 会小很多）。`WujiTunnel.debug.dylib` 中可见 `CGoInvoke` 与
`getTrafficStats` 符号，说明补丁后的 libXray 已进包。

## 8. 真机验证步骤（需 Lead 在 Wanli的iPhone 16 上执行）

前置：Apple Developer 后台为 `com.juejin.ios.wuji` 与 `com.juejin.ios.wuji.tunnel-ext`
开启 **App Groups**（`group.com.juejin.ios.wuji`）与 **Network Extensions**
（`packet-tunnel-provider`）能力；自动签名失败时把 Xcode 报错原文发 engine。

1. 真机安装：`xcodebuild -destination 'platform=iOS,id=00008140-001934312102801C' build`，
   `xcrun devicectl device install app --device 00008140-001934312102801C <Wuji.app>`；
2. 启动 App → 同意协议 → 添加一个真实节点（或订阅）→ 选中 → 点连接；
   首次会出现系统「Wuji 想要添加 VPN 配置」授权弹窗 → Allow；
3. 期望：首页进入「连接中」→「已连接」，状态卡有节点信息，流量/时长开始变化；
4. 验证出网：Safari 打开 `https://ipinfo.io` 看到代理服务器 IP；`1.1.1.1/help` 看
   DNS 是否走代理（无泄漏）；
5. 验证分流：规则模式 + 勾选「中国」直连 → 访问国内站点正常；`curl ifconfig.me`
   应显示代理 IP；全局模式 → 国内站点也走代理；
6. 验证流量：首页上/下行速率非 0，累计值增长；断开后归零；
7. 验证断开：App 内断开 → 系统设置 VPN 状态消失；从系统设置断开 → 回 App 状态同步为未连接；
8. 验证按需：设置「总是」→ 杀掉 App → 打开 Safari 自动连上；「仅 Wi-Fi」切换蜂窝应断开；
9. 验证错误路径：飞行模式连接 → 应有错误横幅 + 重试；拒绝系统 VPN 授权 →
   显示「未获得 VPN 权限」；
10. 稳定性（C8）：连接 10 分钟看是否断流/崩溃；Instruments 观察扩展内存 < 50MB；
11. 验证 4 协议（C10）：VMess / VLESS(含 REALITY) / Trojan / SS 各连一次（需用户提供节点）；
12. 日志：`xcrun devicectl device console --device <udid> --predicate 'subsystem CONTAINS "wuji"'`。

## 9. 已知限制 / 风险

- **模拟器无法验证 NE**：模拟器没有 utun 控制面，`TunFdResolver` 返回 nil，连接必然失败；
  模拟器只用于编译 + UI（首页需 mock 状态）。
- **fd 探测方法为实测常用方案但仍需真机确认**：`getpeername` + `CTLIOCGINFO` + `sc_id`
  比对在 iOS 17–26 的 NE 进程可用（frozensource: Xray-core darwin tun、VLESSKit），
  本机 macOS 上已验证 `CTLIOCGINFO` 常量正确（control id=5），但未在真机跑过完整链路。
  若某系统版本改了 utun 控制面，回退方案见 app-spec §6.4（hev-socks5-tunnel）。
- **旧 HTTP/2 传输已被 Xray-core 移除**：share link 的 `type=h2` / 旧 HTTP 传输节点
  会映射成 XHTTP `stream-one`（H2/H3 时代替方案）。语义接近但不保证所有旧服务端可用；
  REALITY 正常、WS/gRPC 仍工作但有 deprecation warning。
- **DNS**：固定 DoH `https://1.1.1.1/dns-query`（经代理）。若后续需要国内直连域名解析
  更快可加第二个 DNS server，但要注意泄漏与 `disableFallback`。
- **按需模式**与「仅 Wi-Fi/蜂窝」的规则语义：`Connect(.wifi)+Disconnect(.cellular)`；
  真机需按 §8.8 实测。
- **on-demand + 手动断开**：`always` 模式下用户手动断开后系统会按规则重新连接，属系统行为。
- **错误文案**：`TunnelError.configurationFailed/startupTimedOut` 目前返回英文技术文案
  （扩展侧错误消息直接透传），未进本地化表；如需中文化需在 `Localizable.strings` 加 key
  （Lead 负责资源文件）。
- **流量统计精度**：每秒采样，断开前最后不足 1 秒的流量不会写入文件，但 App 断开时归零显示。

---

<!-- merged from ids-pagesA.md -->

# ids — pagesA（启动引导 / 协议同意 / 节点 / 添加 / 导入 / 二维码）

> owner：pages-a。命名规范 `wuji.<page>.<control>`；列表中带节点 id 的后缀保证索引无关的稳定标识。
> 文件：`docs/ids-pagesA.md`（与 Lead 汇总的 `docs/ids.md` 合并时以本表为准）。

## 1. 引导 OnboardingView（D2）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.onboarding.pager` | 引导 | 横向分页容器（可滑动，3 页） |
| `wuji.onboarding.skipButton` | 引导 | 右上角 Skip，标记 onboarding_done 并进入协议同意 |
| `wuji.onboarding.pageIndicator` | 引导 | 页码点（非交互，VoiceOver 播报「第 X 页，共 3 页」） |
| `wuji.onboarding.primaryButton` | 引导 | 底部主按钮：Continue（前两页）/ Get Started（末页） |

## 2. 协议同意 ConsentView（D3）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.consent.termsLink` | 协议同意 | 用户协议行，push App 内 LegalDocumentView(.terms) |
| `wuji.consent.privacyLink` | 协议同意 | 隐私政策行，push App 内 LegalDocumentView(.privacy) |
| `wuji.consent.checkbox` | 协议同意 | 勾选同意；VoiceOver value = 已同意/未同意；`isSelected` trait |
| `wuji.consent.continueButton` | 协议同意 | Agree & Continue；未勾选时 disabled + 50% 透明 |

## 3. 节点列表 NodeListView（D7/D8/D9）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.addButton` | 节点列表 | 导航栏 + → 添加方式弹层 |
| `wuji.nodes.sortMenu` | 节点列表 | 导航栏排序菜单：名称/延迟/添加时间 + 升/降序，写 settings.sortField / sortAscending |
| `wuji.nodes.testAllButton` | 节点列表 | 导航栏全部测速；测速中显示 ProgressView 且禁用 |
| `wuji.nodes.empty.addButton` | 节点空状态 | 主按钮 Add Node → 添加方式弹层 |
| `wuji.nodes.empty.addSubscriptionButton` | 节点空状态 | 次按钮 Add Subscription → 添加订阅页 |
| `wuji.nodes.empty.scanButton` | 节点空状态 | 第三入口 Scan QR Code → 扫码页 |
| `wuji.nodes.row.<profileID>` | 节点列表 | 节点行主体：点按 = 设为当前节点（行内出现 ✓，轻触觉反馈） |
| `wuji.nodes.rowMenu.<profileID>` | 节点列表 | 行内 ⋯ → 节点操作 sheet |
| —（系统滑动操作） | 节点列表 | 行左滑：Edit / Delete（Delete 二次确认）；行右滑：Set as Active |
| —（系统搜索框） | 节点列表 | 搜索框由 SwiftUI `.searchable` 系统注入，无法设置自定义标识；搜索逻辑见 `nodes(in:)` |

## 4. 添加方式弹层 AddNodeMenuSheet（D7 子流程）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.addMenu.manual` | 添加方式 | Enter Manually → 手动添加表单 |
| `wuji.nodes.addMenu.scan` | 添加方式 | Scan QR Code → 扫码页 |
| `wuji.nodes.addMenu.paste` | 添加方式 | Paste from Clipboard → 剪贴板导入页 |
| `wuji.nodes.addMenu.subscription` | 添加方式 | Add Subscription → 添加订阅页 |
| `wuji.nodes.addMenu.cancel` | 添加方式 | Cancel，关闭弹层 |

## 5. 节点操作 NodeActionsSheet（D8）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.actions.header` | 节点操作 | 标题块（节点名 + 协议 · 地址），非交互 |
| `wuji.nodes.actions.setActive` | 节点操作 | Set as Active，写 settings.activeProfileID 后关闭 |
| `wuji.nodes.actions.edit` | 节点操作 | Edit Node，push 预填的编辑表单 |
| `wuji.nodes.actions.copyURI` | 节点操作 | Copy URI；成功后行标题变 Copied（1.6s 后还原） |
| `wuji.nodes.actions.shareQR` | 节点操作 | Share QR Code，push 二维码分享页 |
| `wuji.nodes.actions.share` | 节点操作 | Share，系统分享面板（分享 URI 文本） |
| `wuji.nodes.actions.delete` | 节点操作 | Delete Node（红色），二次确认后删除并关闭 |
| `wuji.nodes.actions.cancel` | 节点操作 | Cancel |
| `wuji.nodes.actions.copyError` | 节点操作 | 无原始 URI 时的红字错误提示（条件显示） |

## 6. 添加 / 编辑节点 AddNodeFormView（D10）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.form.protocolPicker` | 添加/编辑节点 | 协议分段控件 VMess / VLESS / Trojan / Shadowsocks，切换动态字段 |
| `wuji.nodes.form.name` | 添加/编辑节点 | 名称（可选，空则保存为 server:port） |
| `wuji.nodes.form.address` | 添加/编辑节点 | 服务器地址，URL 键盘；校验必填/非法字符 |
| `wuji.nodes.form.port` | 添加/编辑节点 | 端口，数字键盘；校验 1–65535 |
| `wuji.nodes.form.uuid` | 添加/编辑节点 | VMess / VLESS UUID，校验 UUID 格式 |
| `wuji.nodes.form.alterID` | 添加/编辑节点 | VMess Alter ID，数字键盘 |
| `wuji.nodes.form.encryption` | 添加/编辑节点 | VMess 加密方式（auto/aes-128-gcm/chacha20-poly1305/none） |
| `wuji.nodes.form.flow` | 添加/编辑节点 | VLESS 流控（None / xtls-rprx-vision） |
| `wuji.nodes.form.password` | 添加/编辑节点 | Trojan / Shadowsocks 密码 |
| `wuji.nodes.form.method` | 添加/编辑节点 | Shadowsocks 加密方法 |
| `wuji.nodes.form.network` | 添加/编辑节点 | 传输协议（TCP/WebSocket/gRPC/HTTP/2，按协议过滤） |
| `wuji.nodes.form.tls` | 添加/编辑节点 | VMess / Trojan TLS 开关 |
| `wuji.nodes.form.security` | 添加/编辑节点 | VLESS 安全层（None/TLS/REALITY） |
| `wuji.nodes.form.sni` | 添加/编辑节点 | SNI |
| `wuji.nodes.form.path` | 添加/编辑节点 | WebSocket Path（network = ws 时显示） |
| `wuji.nodes.form.host` | 添加/编辑节点 | WebSocket Host（network = ws 时显示） |
| `wuji.nodes.form.grpcService` | 添加/编辑节点 | gRPC Service Name（network = grpc 时显示） |
| `wuji.nodes.form.fingerprint` | 添加/编辑节点 | uTLS 指纹（None/Chrome/Firefox/Safari/iOS/Android/Edge/Randomized） |
| `wuji.nodes.form.allowInsecure` | 添加/编辑节点 | Allow Insecure（TLS/REALITY 时显示） |
| `wuji.nodes.form.realityPublicKey` | 添加/编辑节点 | REALITY 公钥（VLESS + REALITY 时显示，必填） |
| `wuji.nodes.form.realityShortID` | 添加/编辑节点 | REALITY Short ID（十六进制校验） |
| `wuji.nodes.form.cancelButton` | 添加节点 | Cancel（sheet 呈现时显示；push 编辑用系统返回） |
| `wuji.nodes.form.saveButton` | 添加/编辑节点 | Save：先校验，保存中显示 ProgressView |
| `wuji.nodes.form.keyboardDone` | 添加/编辑节点 | 键盘工具栏 Done（收起键盘） |
| `wuji.nodes.form.error.<field>` | 添加/编辑节点 | 行内红字校验错误（server/port/uuid/password/duplicate/realityPublicKey/realityShortID） |
| `wuji.nodes.form.saveError` | 添加/编辑节点 | 保存失败红字（条件显示） |

## 7. 剪贴板导入 PasteImportView（D12）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.paste.editor` | 剪贴板导入 | 多行链接输入框，进入页面自动填充剪贴板；输入实时解析 |
| `wuji.nodes.paste.row.<profileID>` | 剪贴板导入 | 识别结果行，点按切换勾选（✓ 绿色） |
| `wuji.nodes.paste.error` | 剪贴板导入 | 解析失败红字提示（条件显示） |
| `wuji.nodes.paste.cancelButton` | 剪贴板导入 | Cancel |
| `wuji.nodes.paste.importButton` | 剪贴板导入 | 导航栏 Import（与底部主按钮等效，未勾选/导入中 disabled） |
| `wuji.nodes.paste.primaryButton` | 剪贴板导入 | 底部主按钮 Import N Nodes，loading 态，导入后关闭并刷新列表 |

## 8. 扫码导入 ScanQRView（D11）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.scan.closeButton` | 扫码 | 左上角关闭（白圆底 ×） |
| `wuji.nodes.scan.choosePhotoButton` | 扫码 | 底部白圆相机按钮 + Choose from Photos（系统相册选择器，无需相册权限） |
| `wuji.nodes.scan.openSettingsButton` | 扫码·相机被拒 | 打开系统设置 |
| `wuji.nodes.scan.pasteButton` | 扫码·相机被拒 | 降级到剪贴板导入页 |
| `wuji.nodes.scan.unavailableMessage` | 扫码·相机不可用 | 取景框下方提示「当前设备没有可用相机」 |
| `wuji.nodes.scan.error` | 扫码 | 非法二维码/相册无可识别二维码的红底提示（2.5s 自动消失） |
| `wuji.nodes.scan.previewCard` | 扫码 | 识别成功预览卡片（节点名 / 协议 · 地址） |
| `wuji.nodes.scan.cancelSaveButton` | 扫码 | 预览卡片 Cancel（继续扫码） |
| `wuji.nodes.scan.saveButton` | 扫码 | 预览卡片 Save Node：入库、设为当前节点并关闭 |

## 9. 二维码分享 QRShareView（D13）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.qr.image` | 二维码分享 | CIFilter 生成的白底黑码（voiceover: 「<节点名> 的二维码」） |
| `wuji.nodes.qr.emptyState` | 二维码分享 | 无原始 URI 时的空状态（条件显示） |
| `wuji.nodes.qr.saveButton` | 二维码分享 | Save to Photos：PHPhotoLibrary 加相册权限、保存中 loading、失败红字 |
| `wuji.nodes.qr.copyButton` | 二维码分享 | Copy URI，写剪贴板并显示「URI Copied」 |
| `wuji.nodes.qr.shareButton` | 二维码分享 | 导航栏 Share，系统分享面板（URI 文本） |
| `wuji.nodes.qr.status` | 二维码分享 | 成功/失败状态行（绿色/红色，2.5s 自动消失） |

## 10. DEBUG 截图钩子（不进 Release）

`#if DEBUG` 生效，供 headless 模拟器截图核对设计图：

| 启动参数 | 作用 |
|---|---|
| `-WujiScreenshotPage onboarding2` / `onboarding3` | 引导直接显示第 2/3 页 |
| `-WujiScreenshotPage consent-agreed` / `consent-terms` | 协议同意页勾选态 / push 用户协议页 |
| `-WujiScreenshotPage nodes-menu` / `nodes-add` / `nodes-add-vless` / `nodes-add-trojan` / `nodes-add-ss` / `nodes-add-invalid` | 节点页打开添加方式 / 对应协议表单 / 空表单校验态 |
| `-WujiScreenshotPage nodes-add-subscription` | 节点页打开添加订阅页（pagesB） |
| `-WujiScreenshotPage nodes-scan` / `nodes-scan-preview` | 扫码页 / 识别成功预览卡 |
| `-WujiScreenshotPage nodes-paste` / `nodes-paste-data` | 剪贴板导入空态 / 预填四协议链接 |
| `-WujiScreenshotPage nodes-actions`（配 `-WujiScreenshotDetail qr|edit`） | 节点操作 sheet / push 二维码分享 / push 编辑表单 |
| `-WujiScreenshotSearch <text>` | 节点列表预置搜索词（搜索无结果状态） |
| `-WujiScreenshotAction test` | 节点页启动即触发全部测速（行内 loading 状态） |
| `-WujiScreenshotAction sort-name` / `sort-latency-desc` | 预置排序（名称升序 / 延迟降序）并截图 |
| `-WujiScreenshotAction invalid`（配 add 表单） | 空表单点保存的校验失败红字状态 |
| `-WujiScreenshotAction autosave`（配 add 表单） | 自动填有效值并保存，验证表单→入库→列表刷新链路 |
| `-WujiScreenshotAction import`（配 paste 页） | 自动导入已识别节点，验证批量导入链路 |

---

<!-- merged from ids-pagesB.md -->

# 可交互控件标识表 — pages-b（订阅 / 分流 / 设置）

> 归属：`pages-b`（task-4 / impl-plan D14–D21）。命名规则 `wuji.<页面>.<控件>`，与 `docs/ids.md` 一致。
> 动态项使用稳定业务 id（订阅 id / 节点 id / 国家代码），不使用数组索引。
> 页面文件：`Wuji/Features/Subscriptions/`、`Wuji/Features/Routing/`、`Wuji/Features/Settings/`。

## 订阅列表（SubscriptionListView，push 自 设置 → 订阅）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.subscriptions.list` | 列表容器 | 点击卡片进入详情 |
| `wuji.subscriptions.addButton` | 右上 `+` | 弹出添加订阅 sheet |
| `wuji.subscriptions.row.<id>` | 订阅卡片（NavigationLink） | 进入订阅详情 |
| `wuji.subscriptions.row.<id>.progress` | 流量进度条 | 只读（用量/总量） |
| `wuji.subscriptions.swipeDelete.<id>` | 左滑删除 | 弹自定义二次确认 → 删除订阅+分组+节点 |
| `wuji.subscriptions.emptyState` | 空状态容器 | 主按钮打开添加订阅 |
| `wuji.subscriptions.list` 内 footer | “Auto-update runs while the app is open.” | 只读说明 |

## 添加 / 编辑订阅（AddSubscriptionView，自带 NavigationStack 的 sheet）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.subscriptions.add.cancel` | Cancel | 关闭表单（加载中禁用） |
| `wuji.subscriptions.add.save` | 右上 Save | 与底部主按钮同一提交逻辑 |
| `wuji.subscriptions.add.urlField` | 订阅地址输入框 | URL 键盘、校验 http(s) |
| `wuji.subscriptions.add.nameField` | 名称输入框 | 可选，空时用 URL host |
| `wuji.subscriptions.add.autoUpdate` | 自动更新间隔行 | push 间隔选择页 |
| `wuji.subscriptions.add.interval.off` / `.sixHours` / `.twelveHours` / `.twentyFourHours` / `.sevenDays` | 间隔选项 | 单选，写回表单 |
| `wuji.subscriptions.add.submit` | 底部 “Add & Update” / “Save” | 拉取订阅 → 写入订阅/分组/节点，加载态 + 失败原因 |
| `wuji.subscriptions.form.error` | 表单错误区 | 显示失败原因（保留已填内容） |

## 订阅详情（SubscriptionDetailView，push）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.subscriptions.detail.list` | 列表容器 | — |
| `wuji.subscriptions.detail.stat.nodes` / `.used` / `.expires` | 三列统计 | 只读（节点数 / 已用流量 / 到期） |
| `wuji.subscriptions.detail.progress` | 流量进度条 | 只读 |
| `wuji.subscriptions.detail.url` | URL 行 | 复制订阅地址并 toast |
| `wuji.subscriptions.detail.error` | 更新错误区 | 显示 `lastError`（存在才显示） |
| `wuji.subscriptions.detail.node.<nodeID>` | 节点预览行（前 3 条） | 设为当前节点 + toast |
| `wuji.subscriptions.detail.viewAllNodes` | “View All N Nodes” | 弹出全部节点 sheet |
| `wuji.subscriptions.detail.updateNow` | Update Now 主按钮 | 刷新订阅（加载态、失败显示错误、成功 toast） |
| `wuji.subscriptions.detail.edit` | 右上 Edit | 弹出编辑表单 |
| `wuji.subscriptions.detail.delete` | Delete Subscription | 自定义二次确认 → 删除并返回列表 |
| `wuji.subscriptions.detail.notFound` | 订阅已删除时的空状态 | 只读 |
| `wuji.subscriptions.detail.nodesEmpty` | 无节点提示 | 只读 |
| `wuji.subscriptions.nodes.row.<nodeID>` | 全部节点行 | 选中该节点并关闭 |
| `wuji.subscriptions.nodes.done` | 全节点 sheet 的 Done | 关闭 |

## 分流设置（RoutingSettingsView，Home 分流摘要弹出的 sheet）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.routing.list` | 列表容器 | — |
| `wuji.routing.done` | Done | 关闭（修改已即时保存） |
| `wuji.routing.globalModeToggle` | Rule / Global 分段 | 即时写入 `routing_mode`；Global 时禁用下方直连项 |
| `wuji.routing.bypassLanToggle` | 局域网直连开关 | 即时写入 `bypass_lan` |
| `wuji.routing.regionsRow` | “Bypassed Regions / N selected” 行 | 打开地区多选 sheet |
| `wuji.routing.region.<CODE>` | 已选地区行（带勾） | 打开地区多选 sheet |
| `wuji.routing.regionsEmpty` | 未选地区提示 | 只读 |
| `wuji.routing.addRegion` | “Add Region…” | 打开地区多选 sheet |

## 地区多选（CountryPickerView，sheet）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.routing.picker.list` | 列表容器 | — |
| `wuji.routing.picker.cancel` | Cancel | 放弃本次改动并关闭 |
| `wuji.routing.picker.done` | Done | 提交到 `bypass_countries` 并关闭 |
| `wuji.routing.picker.menu` | ALL REGIONS 区块右上 “…” | 展开全选 / 清空 |
| `wuji.routing.picker.selectAll` | 全选 | 选中全部地区（草稿） |
| `wuji.routing.picker.clearAll` | 清空 | 清空草稿选择 |
| `wuji.routing.picker.row.<CODE>` | 地区行 | 勾选/取消（草稿，Done 才保存） |
| `wuji.routing.picker.noResults` | 搜索无结果空状态 | 只读 |
| `wuji.routing.picker.unavailable` | 内置地区数据缺失时的空状态 | 只读（提示重装可恢复） |

> 搜索框由系统 `.searchable` 提供，未单独设置标识（系统控件）。

## 设置（SettingsView，底部 tab 根页）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.settings.list` | 列表容器 | — |
| `wuji.settings.testURL` | 测速 URL 行 | push 编辑页 |
| `wuji.settings.timeout` | 超时时间行 | push 选项页 |
| `wuji.settings.autoUpdate` | 订阅自动更新开关 | 即时持久化 |
| `wuji.settings.subscriptions` | Subscriptions（计数）行 | push 订阅列表 |
| `wuji.settings.about` | About & Licenses | push 关于页 |
| `wuji.settings.contact` | Contact Support | 打开 `mailto:ji4ozhu@gmail.com` |
| `wuji.settings.terms` | Terms of Use | push 用户协议 |
| `wuji.settings.privacy` | Privacy Policy | push 隐私政策 |
| `wuji.settings.clearData` | Clear All Data（红） | 自定义二次确认 → 清 SQLite + App Group 配置，回首次启动状态 |

### 设置子页

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.settings.latency.urlField` | 测速地址输入框 | URL 校验 |
| `wuji.settings.latency.save` | Save | 校验后保存并返回 |
| `wuji.settings.timeout.option.3` / `.5` / `.8` / `.10` / `.15` | 超时选项（秒） | 即时持久化并返回 |

## 关于 / 开源许可（AboutView / LicensesView）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.settings.about.openSource` | Open Source Licenses | push 许可页 |
| `wuji.settings.about.privacy` | Privacy Policy | push 隐私政策 |
| `wuji.settings.about.terms` | Terms of Use | push 用户协议 |
| `wuji.settings.about.contact` | Contact Support | 打开 mailto |
| `wuji.settings.about.viewAllLicenses` | View all licenses | push 许可页 |
| `wuji.settings.licenses.xray-core` / `.libxray` / `.country-cidrs` | 许可 DisclosureGroup | 展开/收起完整许可文本 |

## 用户协议 / 隐私政策（LegalDocumentView）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.settings.legal.scroll` | 文档滚动容器 | — |
| `wuji.settings.legal.email` | 联系邮箱链接 | 打开 mailto |
| `wuji.settings.legal.error` | 文档加载失败状态 | 提供 “Try Again” 重试 |

## 共享弹层

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.confirmation.title` | 自定义二次确认标题 | 只读 |
| `wuji.confirmation.confirm` | 确认按钮（破坏性红色） | 执行操作 |
| `wuji.confirmation.cancel` | 取消按钮 | 关闭 |
| `wuji.toast` | 轻量提示胶囊 | 2.2s 自动消失 |

---

### 备注

- 所有新增文案走 `Wuji/Resources/{en,zh-Hans}.lproj/{Settings,Routing,Subscriptions}.strings`（`L10n.t(key, table:)`）；共用文案沿用 `Localizable.strings`。已用脚本核对 en/zh 两个表 key 完全对齐、代码引用的 key 全部存在。
- DEBUG 截图直达（不影响 Release）：`-WujiTab settings`（RootView）+ `-WujiScreenshotRoute <route>`（SettingsView / RoutingSettingsView / SubscriptionListView / SubscriptionDetailView）。
  可用 route：`subscriptions`、`subscriptions-delete-confirm`、`subscription-add`、`subscription-detail`、`subscription-edit`、`subscription-nodes`、`routing`、`regions`、`on-demand`、`test-url`、`timeout`、`about`、`licenses`、`terms`、`privacy`、`reset-confirm`、`clear-confirm`。
- 截图：`app_src/wuji/screenshots/impl-pagesB/`（EN 22 张 + 中文 4 张 + iPhone SE 7 张，含空/错误/二次确认状态）。

## 首页（Lead，2026-11-20 补充）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.home.connectPill` | 首页 | 连接控件（大号胶囊按钮：未连接蓝色 Connect / 已连接灰色 Disconnect；忙时禁用并显示进度） |
| `wuji.home.statusTitle` | 首页 | 连接状态标题（Connected / Not Connected / Connecting…） |
| `wuji.home.statusSubtitle` | 首页 | 状态副标题（节点 · 协议 · 延迟） |
| `wuji.home.currentNodeRow` | 首页 | 当前节点行（点击进节点列表） |
| `wuji.home.routingRow` | 首页 | 分流摘要行（点击打开分流设置） |
| `wuji.home.chooseNode` | 首页 | Choose a Node 按钮（无节点时） |
| `wuji.home.firstConnect.allow` | 首连弹窗 | Allow 按钮 |
| `wuji.home.firstConnect.notNow` | 首连弹窗 | Not Now 按钮 |

## 扫码预览（pages-a，2026-11-20 补充）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.scan.previewCard` | 扫码 | 识别结果预览卡容器（children: contain） |
| `wuji.nodes.scan.cancelSaveButton` | 扫码 | 预览卡 Cancel |
| `wuji.nodes.scan.saveButton` | 扫码 | 预览卡 Save Node |


## 设置 · GeoIP 数据（Lead，2026-11-20 补充）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.routing.globalModeToggle` | 分流设置 | 全局模式开关（替代原 Rule/Global 分段控件；开启后直连地区/局域网规则禁用） |
| `wuji.settings.geoipStatus` | 设置 | GeoIP 数据集状态（内置快照日期 / 上次更新时间） |
| `wuji.settings.geoipUpdate` | 设置 | 「立即更新」按钮（手动下载最新 GeoIP 数据，仅更新失败时提示） |

## 第三轮新增（SOCKS5 / DNS / 语言，2026-11-20 10:30）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.form.socksUsername` | 手动添加/编辑 | SOCKS5 用户名输入框（密码复用现有 password 字段；两者同时空或同时非空） |
| `wuji.nodes.form.error.socksCredentials` | 手动添加/编辑 | SOCKS5 用户名/密码不配对的行内错误 |
| `wuji.routing.dns.proxyDoH` | 分流设置 | DNS 处理：远程 DoH（经代理，默认） |
| `wuji.routing.dns.local` | 分流设置 | DNS 处理：本地 DNS（223.5.5.5 / 119.29.29.29 直连） |
| `wuji.settings.language.section` | 设置 | 语言区（跟随系统 / English / 简体中文） |
| `wuji.settings.language.option.system` | 设置 | 语言：跟随系统 |
| `wuji.settings.language.option.en` | 设置 | 语言：English |
| `wuji.settings.language.option.zh-Hans` | 设置 | 语言：简体中文 |


## 第四轮 UI 调整（2026-11-20 12:20）

| 变更 | 说明 |
|---|---|
| `wuji.home.connectSwitch` | 首页大圆形连接按钮改为系统开关（含状态标题/副标题卡片）；忙时显示 `wuji.home.connectingIndicator` |
| 首页导航栏 | 移除左上角大标题「连接」与右上角菜单（Settings / Reset VPN Configuration） |
| `wuji.settings.onDemand` / `wuji.settings.resetVPN` | 设置页「连接」区整体移除（按需连接、重置 VPN 配置入口） |
| `wuji.settings.geoipStatus` | GeoIP 行标题改为「数据库版本 / Database Version」，值为版本日期 |
| 全局模式 | 开启时系统级 LAN 直连排除也关闭（所有流量含局域网都走代理），仅规则模式才应用局域网直连 |


## 第五轮：11 语言支持 + 连接控件定稿（2026-11-20 12:45）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.home.connectPill` | 首页 | 胶囊连接按钮（Connect / Disconnect），替代旧开关与圆形按钮 |
| `wuji.settings.language.followSystem` | 设置 | 跟随系统（勾选表示当前模式） |
| `wuji.settings.language.chooseAnother` | 设置 | 当前语言行 → 打开二级语言选择 |
| `wuji.settings.language.picker` | 语言选择 | 二级语言列表（11 种语言，nativeName + englishName + 勾选） |
| `wuji.settings.language.option.<code>` | 语言选择 | 单个语言选项（en/zh-Hans/zh-Hant/es/fr/de/ja/ko/ru/th/vi） |


## 第六轮：文案/名称/关于页调整（2026-11-20）

| 变更 | 说明 |
|---|---|
| 直连 → 不代理 | 所有中文（zh-Hans / zh-Hant）用户可见文案中的「直连/直連」统一改为「不代理」 |
| About 页 | 仅保留「开源许可」入口；隐私政策、用户协议、联系支持从 About 移除（设置页已有） |
| App 名称 | zh-Hans「无极代理」、zh-Hant「無極代理」、其他 9 种语言「WProxy」；About 头部读 `L10n app.name`，InfoPlist 的 CFBundleDisplayName/CFBundleName 同步 |
