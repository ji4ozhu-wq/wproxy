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
