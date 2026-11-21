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
