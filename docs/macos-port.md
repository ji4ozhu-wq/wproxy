# macOS 26+ 原生支持（移植说明）

> 2026-11-22 · 目标：macOS 26.0+ 原生 App（Mac App Store 分发，与 iOS 同一个 app record 的 macOS platform）
> 与 iOS 3.3.1 共用同一套 Swift 源码；iOS 行为保持不变（iOS 分支代码逐行保留）。
> 本文件是**实现/架构记录**；上架流程与素材见 `docs/macos-appstore-checklist.md`、`docs/macos-asc-status.md`、`docs/macos-build-upload.md`。

---

## 0. 一句话

新增 `Wuji-macOS`（macOS 26+ SwiftUI App，沙盒）与 `WujiTunnel-macOS`（Network Extension packet-tunnel **app extension**），
复用 `Wuji/`、`WujiTunnel/` 源码与 `LibXray.xcframework`（新增 macOS universal slice），
平台差异集中在 `Wuji/DesignSystem/PlatformCompat.swift` 与少量 `#if os(...)`。

当前状态（2026-11-22）：**本地构建 / 单测 / iOS 回归 / Release archive / App Store .pkg 导出全部跑通**；
**真实 Mac + 真实节点的 VPN 连接已实测通过**（Google HTTP 200、出口 IP = 代理服务器 IP、断开后网络恢复；见 §7.1）。
App Store Connect 还未 Add Platform（用户操作，见 §10）。
macOS 使用 iPad 布局；全部表单/弹窗已做 UI 自检修复（见 §8）。

---

## 1. 目标与产物

| Target | 类型 | 产物 / Bundle ID | 说明 |
|---|---|---|---|
| `Wuji-macOS` | macOS application | `Wuji.app` / `com.juejin.ios.wuji` | 与 iOS 同 Bundle ID；沙盒；嵌入扩展；3.3.1(2)，`LSMinimumSystemVersion 26.0` |
| `WujiTunnel-macOS` | macOS **app-extension** | `Contents/PlugIns/WujiTunnel.appex` / `com.juejin.ios.wuji.tunnel-ext` | `NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel`；3.3.1(2)（必须与宿主 build 号一致） |
| `WujiTests-macOS` | unit-test bundle | `com.juejin.ios.wuji.tests` | 复用 `WujiTests/`，TEST_HOST 指向 `Wuji.app` |

Scheme：`Wuji-macOS`（build → run/test）。`project.yml` 是唯一工程定义，改完必须 `xcodegen generate`。

---

## 2. 为什么用 app extension（不是 system extension）

Apple TN3134（Network Extension provider deployment）对 macOS packet tunnel 的打包方式：

| 平台 | 打包方式 | 最低 OS | 限制 |
|---|---|---|---|
| macOS | **app extension** | 10.11 | App Store only |
| macOS | system extension | 10.15 | App Store + Developer ID |

我们只走 **Mac App Store**，因此选择 app extension：

- 不需要系统扩展的安装/审批流程（`Contents/Library/SystemExtensions`、`OSSystemExtensionRequest` 等全部不需要）；
- 嵌入位置就是 `Wuji.app/Contents/PlugIns/WujiTunnel.appex`，与 iOS 的扩展结构一致；
- 少数 Mac App Store VPN 客户端（如 XConnect 等）也采用该方案。

> 将来若需要 Developer ID 直接分发，再新增一个 `system-extension` target：entitlement 用
> `com.apple.developer.networking.networkextension = packet-tunnel-provider-systemextension`，
> 并嵌入 `Contents/Library/SystemExtensions`；现有 app extension 路径无需改动。

参考：<https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment>

---

## 3. 源码组织

```
WujiMac/                        # 只属于 macOS 的平台文件（不参与 iOS target）
├── Info-Wuji-macOS.plist       # macOS App Info.plist（LSMinimumSystemVersion、NSPrincipalClass、分类、版权…）
├── Info-WujiTunnel-macOS.plist # 扩展 Info.plist（NSExtension packet-tunnel）
├── Wuji-macOS.entitlements     # sandbox、NE、app group、network.client、files.user-selected.read-write
├── WujiTunnel-macOS.entitlements
└── Assets.xcassets/            # macOS AppIcon（16–1024 全尺寸）+ AppIconPreview + AccentColor
```

共享源码（两个平台同时编译）：

- `Wuji/` 全部 SwiftUI 源码（新增 `Wuji/DesignSystem/PlatformCompat.swift`）；
- `WujiTunnel/`（PacketTunnelProvider、XrayRunner、TunFdResolver、TunnelNetworkSettings、RouteDiagnostics）；
- `Wuji/Core/Models`、`Wuji/Core/Routing`（扩展 target 共享）；
- `WujiTests/`（iOS 与 macOS 各一个 test target）。

### 3.1 平台差异层 `PlatformCompat.swift`

| Helper | iOS | macOS |
|---|---|---|
| `PlatformPasteboard` | `UIPasteboard` | `NSPasteboard` |
| `PlatformHaptics` | `UIImpact/NotificationFeedbackGenerator` | no-op |
| `PlatformSystem.open` / `appSettingsURL` | `UIApplication` | `NSWorkspace` / 系统设置深链 |
| `PlatformNotifications.appDidBecomeActive` | `UIApplication.didBecomeActiveNotification` | `NSApplication.didBecomeActiveNotification` |
| `PlatformImage` / `PlatformQRImageView` | `UIImage` | `NSImage` |
| `wujiKeyboardType` / `wujiNoAutocapitalization` | `.keyboardType` / `.textInputAutocapitalization` | no-op |
| `wujiListStyle` | `.insetGrouped` | `.inset` |
| `wujiInlineNavigationTitle` | `.navigationBarTitleDisplayMode(.inline)` | no-op |
| `.wujiTrailing` / `.wujiLeading`（ToolbarItemPlacement） | `.topBarTrailing/Leading` | `.primaryAction` / `.navigation` |
| `wujiHiddenTabBar` / `wujiHiddenNavigationBar` / `wujiSearchable` / `wujiNavigationLinkPickerStyle` | iOS API | macOS 等价（无 tab bar / `.menu` picker / 默认 search） |
| `wujiFullScreenCover` | `.fullScreenCover` | `.sheet` |
| `wujiImageFileImporter` | no-op | `fileImporter([.image])` |
| `wujiMacWindowSizing` | no-op | 最小 900×620，默认 1120×760 |

`Theme` 的颜色在 macOS 上映射到 AppKit 语义色（`windowBackgroundColor`、`labelColor`、`systemBlue` 等），
`fillTertiary/fillSecondary/gray3/gray4` 同样有平台分支；iOS 原值不变。

### 3.2 行为差异（有意的）

- **本地网络权限门控**：macOS 的 `NetworkPermissionRequester.requestAll()` 只请求 VPN 配置授权（保存 `NETunnelProviderManager` 时系统弹窗），不跑 Bonjour 探测（`#elseif os(macOS)` 分支）。
- **on-demand**：macOS 没有 cellular 接口。`OnDemandMode.wifi` 只保留“Wi-Fi 时连接”，`.cellular` 在 macOS 等价于 `.off`（`TunnelController.applyOnDemandRules` 的 `#if os(iOS)/#else`）。
- **扫码导入**：macOS 没有相机扫描。`ScanQRView` 在 macOS 上变为“从照片选择 / 从文件选择（`fileImporter`）+ 粘贴导入”，QR 检测走同一套 CoreImage 解码与预览保存流程。
- **保存二维码**：iOS 写照片库（`PHPhotoLibrary`）；macOS 用 `NSSavePanel` 导出 PNG（新增本地化 key `nodes.qr.saveToFile`，11 语言已同步）。
- **分享**：iOS `UIActivityViewController`；macOS 用 SwiftUI `ShareLink`（sheet 内展示）。
- **窗口/导航**：沿用 iPad 的 `NavigationSplitView` 布局（宽度 ≥700 时），macOS 窗口由 `wujiMacWindowSizing` 约束；light-only 外观保持现状。

---

## 4. 隧道与网络栈（复用 iOS 逻辑）

- 扩展启动流程完全复用：读 App Group `active_tunnel.json` → 解析服务器 IP →
  `NEPacketTunnelNetworkSettings`（IPv4-only：tun `198.18.0.1/16`、DNS `198.18.0.2`、MTU 1380、
  永远排除服务器 IP、可选 bypass LAN）→ 找 utun fd → `env["xray.tun.fd"]` → `LibXray.runXray`。
- **App 消息通道**：macOS SDK 的 `NETunnelProvider`/`NETunnelProviderSession` 同样提供
  `sendProviderMessage` / `handleAppMessage`（`macos(10.11)`），所以流量统计、版本查询逻辑无需分平台。
- **utun fd 解析**（`TunFdResolver`）：主路径仍是 `getpeername` → `AF_SYSTEM` → `CTLIOCGINFO`/`sc_id`；
  新增 macOS 兜底：若主路径找不到（部分 macOS 扩展不暴露 kernel-control peer），改为遍历 fd 用
  `getsockopt(SYSPROTO_CONTROL, UTUN_OPT_IFNAME)` 找 `utun*`，并与 `getifaddrs` 中拥有 `198.18.0.1`
  的接口名匹配。iOS 主路径行为不变，仅在没有 descriptor 时才走兜底。
- **Apple 支持面**：`NEPacketTunnelProvider.packetFlow`、`enforceRoutes`（macOS 11+）、`cancelTunnelWithError` 在 macOS 都存在（已核对 macOS 27.2 SDK headers）。
- **平台限制保持**：IPv4-only、无 on-demand（`onDemandEnabled=false`）、无 per-App 统计；这些与 iOS 一致。

### 4.1 沙盒与 entitlements

App（`Wuji-macOS.entitlements`）：

```
com.apple.developer.networking.networkextension = [packet-tunnel-provider]
com.apple.security.app-sandbox                  = true
com.apple.security.application-groups           = [$(TeamIdentifierPrefix)group.com.youqu.wuji.appgroup]
com.apple.security.network.client               = true
com.apple.security.files.user-selected.read-write = true   # NSSavePanel / fileImporter
```

扩展（`WujiTunnel-macOS.entitlements`）：同上，但去掉 user-selected 文件权限（扩展不弹面板），
并额外需要 **`com.apple.security.network.server = true`**。

> **macOS 实测踩坑（已修复）**：Xray 的 UDP/DNS 拨号器会 `bind(0.0.0.0:0)`，App Sandbox 下只有
> `network.client` 时内核返回 `bind: operation not permitted`，导致所有 DNS（含国内直连 DNS 与代理 DoH）失败、
> 整机断网。给扩展补上 `network.server` 后，同一个真实 VMess 节点立即正常（Google HTTP 200，出口 IP 为代理 IP）。

> `ENABLE_HARDENED_RUNTIME = YES`；`CODE_SIGN_STYLE = Automatic`、`DEVELOPMENT_TEAM = R6748V42K5`。

### 4.2 App Group（macOS 的 TeamID 前缀格式）

- iOS：`group.com.youqu.wuji.appgroup`（已注册）。
- macOS：Apple 允许 macOS app group 使用 `<TeamID>.<group name>` 格式，**无需在开发者网站注册**
  （`docs`：Configuring app groups / App Groups entitlement；profile 中以 `R6748V42K5.*` 通配授权）。
  实际值：`R6748V42K5.group.com.youqu.wuji.appgroup`。
- 两个 macOS Info.plist 都注入 `WujiAppGroupIdentifier = $(TeamIdentifierPrefix)group.com.youqu.wuji.appgroup`，
  `AppGroup.swift` 在 macOS 运行期读取该值（直接取 `Bundle.main`），未签名构建时回退到硬编码 team 前缀。
- SQLite / `active_tunnel.json` / `tunnel_status.json` / `tunnel_traffic.json` / GeoIP 资产路径全部不变（`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`）。

---

## 5. LibXray（macOS slice）

`tools/build_libxray.sh` 现在产出 **3 个 slice** 的 xcframework：

| LibraryIdentifier | 平台 | 架构 |
|---|---|---|
| `ios-arm64` | iOS device | arm64 |
| `ios-arm64-simulator` | iOS simulator | arm64 |
| `macos-arm64_x86_64` | macOS | arm64 + x86_64（universal） |

- 仍固定 upstream commit `5a0f7d8d…` + `tools/libxray-patch/wuji-traffic-stats.patch`（可复现；网络抖动时可用 cache 离线重建）。
- 导出的 iOS 符号集/header 与旧库一致（ABI 不变）；macOS 侧 `CGoInvoke/CGoFree` 在 arm64/x86_64 均导出。
- macOS 扩展 target 的链接参数：`-lresolv -framework CoreFoundation -framework Security`（`-lpthread` 不需要）。
- Validation：`tools/libxray-patch/validation/run_validation.sh` → 12 份配置 + 流量计数全部通过（macOS slice，testXray 接受性验证）。
- 体积：xcframework 151MB（iOS 两个 38MB + macOS universal 74MB）；App Store 包只含所需 slice，导出 pkg ≈ 37.6MB。

---

## 6. 构建 / 签名 / 测试命令

```bash
# 工程重新生成（改 project.yml 或新增 Swift 文件后必须）
xcodegen generate

# macOS Debug 构建（自动签名 + 自动 provisioning）
xcodebuild -project Wuji.xcodeproj -scheme Wuji-macOS -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates build

# macOS 单测（117 条，其中 1 条在 macOS 跳过：沙盒内不能 bind loopback listener）
xcodebuild test -project Wuji.xcodeproj -scheme Wuji-macOS -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates

# iOS 回归（模拟器）
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Release Archive（macOS，universal）
xcodebuild archive -project Wuji.xcodeproj -scheme Wuji-macOS -configuration Release \
  -destination 'generic/platform=macOS' -archivePath /tmp/Wuji-mac.xcarchive \
  -allowProvisioningUpdates

# 导出 Mac App Store .pkg（method=app-store-connect，destination=export）
xcodebuild -exportArchive -archivePath /tmp/Wuji-mac.xcarchive \
  -exportPath /tmp/Wuji-mac-export \
  -exportOptionsPlist /tmp/ExportOptions-mac.plist -allowProvisioningUpdates
```

签名现状（本机实测）：

- 自动签名会为 macOS 生成 Team Provisioning Profile（开发）与 **Mac Installer Distribution / 3rd Party Mac Developer Installer** 证书（导出时自动创建，team `R6748V42K5`），无需手动去门户建 profile。
- 导出的 `WProxy.pkg`：app/扩展用 **Apple Distribution**（SHA1 `9DC357C5…`）签名，pkg 用
  `3rd Party Mac Developer Installer: Shaoxing Tianqiong Network Technology Co., Ltd. (R6748V42K5)` 签名，universal（x86_64+arm64）。
- 上传 build 前需要先在 App Store Connect 给 app record **Add Platform → macOS**（见 `docs/macos-appstore-checklist.md`）。

---

## 7. 本地验证记录（2026-11-22）

| 项目 | 命令/方式 | 结果 |
|---|---|---|
| macOS Debug 构建 | `scheme Wuji-macOS` | ✅ BUILD SUCCEEDED（app + appex 嵌入到 `Contents/PlugIns`，含 LibXray symbols） |
| macOS 单测 | `xcodebuild test -scheme Wuji-macOS` | ✅ 117 executed / 1 skipped / 0 failures |
| iOS 模拟器构建 | `scheme Wuji`（iPhone 17 Pro） | ✅ BUILD SUCCEEDED |
| iOS 真机架构编译 | `generic/platform=iOS` + `CODE_SIGNING_ALLOWED=NO` | ✅ BUILD SUCCEEDED |
| macOS Release Archive | `xcodebuild archive` | ✅ ARCHIVE SUCCEEDED（universal app/exe） |
| App Store 导出 | `-exportArchive`（app-store-connect） | ✅ EXPORT SUCCEEDED → `WProxy.pkg`（37.6MB，签名链见 §6） |
| App 启动 / UI | 本地运行 Debug `.app`（960×800） | ✅ iPad 布局；首页/节点/设置/订阅/关于等页面 + 全部分流/表单/操作 sheet 逐页截图自检，无裁切；列表可点行有 chevron；手填/编辑节点表单为 macOS grouped Form（见 §8 与 `docs/macos-screenshots/`） |
| 真实 VPN 隧道（真实节点，macOS 26.7.1） | `-WujiAutoConnect` → 真实 VMess 节点 | ✅ 已连接；`www.google.com` HTTP 200；`ipinfo.io/ip` = `150.109.58.245`（代理出口 IP）；断开后默认路由/IP 恢复（详见 §7.1） |
| App Store Connect | Add Platform | ❌ 未做（用户操作） |

### 7.1 真实节点实测记录（2026-11-22 04:30，本机 macOS 26.7.1 + 用户提供的 VMess 节点）

| 检查项 | 结果 |
|---|---|
| 扩展 / Xray 启动 | `route_diag`: `context=started fd=6 xray=26.11.9`；Xray VMess outbound 正常 `dialing TCP to 150.109.58.245:3389` |
| 系统隧道 | `scutil --nc status "Wuji"` = Connected；默认路由 `interface: utun4`；`inet 198.18.0.1/16` |
| 出网 | `curl https://www.google.com` → HTTP 200（0.20s）；`curl https://ipinfo.io/ip` → `150.109.58.245`（= 代理服务器） |
| 流量统计 | `tunnel_traffic.json`: uplink 44091 / downlink 45138 字节 |
| 断开 | killall + `scutil --nc stop "Wuji"` 后：路由回 `en1`，直连 IP 恢复 `59.50.80.222`，VPN 状态 Disconnected |
| 沙箱 bind | 修复后的运行日志中 `operation not permitted` 计数 = 0（历史日志里的 1839 条来自修复前） |

未验证：长稳/断线重连、分流规则（国内直连 vs 全局）、DNS 泄漏（`1.1.1.1/help`）、多协议节点、真实 App Store 分发后的行为。

---

## 8. macOS UI 适配（2026-11-22 UI 自检修复）

macOS 使用 **iPad 布局**（侧边栏 + 详情），这是产品决定：`RootView` 在 macOS 上忽略宽度分支，
始终使用 `NavigationSplitView`；`WujiApp` 通过 `PlatformCompat.wujiMacWindowScene()` 设置默认窗口
**1180×780**、最小 **960×640**。iOS 保持原规则（宽度 <700pt 用 iPhone TabView）。
这样 Mac 上的表单/列表都有足够的横向空间，不会再出现「显示不全」。

macOS 与 iOS 的表单/弹窗差异（本次修复）：

1. **macOS 的 `.sheet` 不会自适应尺寸**：iOS 风格的 `NavigationStack { List }` 根视图没有固有高度，
   弹出来只有一条缝，且内容超出部分会被裁掉。现在所有 macOS sheet 都用
   `PlatformCompat.wujiSheetSizing(width:height:)` 固定尺寸。
2. **macOS sheet 里不渲染 SwiftUI `.toolbar`**：iOS 靠工具栏的取消/保存按钮在 Mac 上不可见；
   现在 macOS sheet 统一增加底部操作栏 `wujiMacSheetActions(...)`（取消/完成/保存，支持 Esc/Return）。
3. **macOS sheet 里不能靠 push 返回**：`NodeActionsSheet` 的「编辑节点 / 分享二维码」在 macOS 改为独立 sheet
   （不再嵌套 push）；订阅的「自动更新间隔」改为原生 menu picker。
4. **macOS 的 segmented control 不会压缩**：添加节点表单的协议选择在 macOS 改为 menu picker。
5. **列表行看起来像普通文字**：iOS 的 `NavigationLink` 在列表里自带箭头/点击感，macOS 不画。
   现在 macOS 上可点行统一为「**蓝色标题 + 右侧 chevron + 悬浮高亮 + 手型光标**」：
   - `ValueRow(showsChevron: PlatformFlags.isMacOS)` 会自动用 `PlatformFlags.interactiveTitleColor`
     （macOS 蓝、iOS 保持原色）并加 `.wujiRowHover()`；
   - 纯文字链接用 `.wujiNavigationRow()`；
   - 数据展示行（本次会话流量、数据库版本等）保持普通文字颜色，不误导。
   首页的「当前节点 / 分流」行、设置页全部跳转行、关于页开源许可行都已是可识别的链接样式。
6. **添加/编辑节点表单布局乱、控件溢出 sheet**：macOS `Form` 默认是 `.columns` 两栏样式，和自定义
   label/field 行冲突（标签错位、输入框超出 sheet 被裁）。现已改为 `.formStyle(.grouped)`，并把
   `fieldRow` 在 macOS 上改成「固定标签列 + 受约束 TextField」；截图 `05-add-node-sheet.png` / `09-edit-node-sheet.png`。

固定 sheet 尺寸（macOS）：

| 弹窗 | 尺寸 |
|---|---|
| 添加/编辑节点 | 560×700 |
| 添加/编辑订阅 | 520×620 |
| 分流设置 | 520×640 |
| 国家/地区选择 | 560×680（在分流 sheet 上再弹） |
| 节点操作菜单 | 520×620 |
| 订阅节点列表 | 560×640 |
| 粘贴导入 | 560×700 |
| 扫码导入 | 620×720 |
| 确认弹窗 | 420×240 |
| 首次连接引导 | 420×300 |
| 分享 | 380×200 |

UI 自检覆盖（macOS 960×800 窗口实拍，截图在 `docs/macos-screenshots/`）：

- 首页（未连接 / 已连接+演示流量）、节点列表、设置、订阅列表/详情、关于/许可/语言/测速地址；
- Sheet：分流、添加节点、编辑节点、添加订阅、节点操作、分享二维码、地区选择、粘贴/扫码；
- 截图清单：`01-home-ipad-layout.png` … `12-subscription-detail.png`（含 `11-about.png`）。

> iOS 端布局与交互未改动：平台 helper 在 iOS 分支仍是原来的代码/行为。

---

### 8.1 macOS 原生观感（2026-11-22 第二轮优化）

在 iPad 布局基础上，macOS 端做了原生观感优化（**全部 macOS-only，iPhone/iPad 不变**）：

- **侧边栏**：顶部显示 App 图标 + 名称 + 版本（`RootView.splitLayout`）。
- **系统分组卡片**：新增 `WujiSettingsList` 容器——iOS 仍是 `List(.insetGrouped)`，
  macOS 用 `Form` + `.formStyle(.grouped)`；设置、关于、许可、语言、测速地址/超时、分流、
  国家选择、订阅列表/详情/节点、节点列表、添加/编辑节点表单全部改用它。
- **页面底色**：macOS 页面背景改为 `underPageBackgroundColor`（浅灰），卡片用 `controlBackgroundColor`（白），
  与 macOS 系统设置一致；`wujiListBackground()` 让 iOS 继续用原来的自定义背景。
- **内容限宽居中**：首页/条款/协议/引导页用 `wujiMacContentWidth(...)` 限制阅读宽度并居中，
  不再把手机布局横向拉满整个窗口。
- **可点行**：`PlatformFlags.interactiveTitleColor`（macOS 蓝 / iOS 原色）+ 右侧 chevron +
  `.wujiRowHover()`（悬浮淡蓝高亮 + 手型光标）；数据展示行保持普通文字。
- **表单布局**：`AddNodeFormView` 用 `.formStyle(.grouped)` + macOS 专用 `fieldRow`
  （固定标签列 + 受约束输入框），不再溢出 sheet；`AddSubscriptionView` 的间隔选择在 macOS 用原生 menu picker。
- 首页连接按钮/状态、会话统计仍保持 iOS 视觉，但被收在居中的 760pt 内容列里。

截图：`docs/macos-screenshots/01-home-ipad-layout.png` … `15-licenses.png`。

---

### 8.2 扁平 → iOS 26 Liquid Glass（用户选定风格，2026-11-22）

用户在若干设计稿中选定了 **iOS 26 Liquid Glass 风格**，macOS 端按此实现（iOS/iPad 外观与逻辑不变）：

- 设计 token 集中在 `PlatformCompat.swift` 的 `MacGlass`：页面浅蓝渐变背景、半透明白色卡片
  （`.ultraThinMaterial` + 白色叠层 + 白色描边 + 轻阴影）、20pt 圆角、同色系浅底彩色 SF Symbol 图标、
  蓝色渐变胶囊主按钮；字号：标题 28、正文 16、说明 13、指标 22。
- 组件：`MacGlassCard`、`MacGlassRow`、`MacGlassIcon`、`MacGlassMetric`、`MacGlassDivider`、
  `MacGlassSectionHeader`、`MacGlassFootnote`、`MacGlassPrimaryButton`、`MacGlassPageBackground`。
- 已应用页面：连接页（状态卡 / 当前节点·分流 / 本次会话 2×2 指标 / 连接详情）、
  设置页（测速 / 订阅 / GEOIP / 语言 / 支持 / 数据 全部分组）、节点列表（按分组卡片 + 协议彩色图标 +
  延迟 + 选中标记 + ⋯ 菜单）。
- 新增本地化 key（11 语言）：`home.details.section/exit/protocol/routing/dns`（连接详情区块）。
- 窗口改为单 `Window` scene（非 `WindowGroup`），并加 macOS `NSApplicationDelegate` 在激活/重开时兜底新建窗口；
  正常安装后首次启动或从 Dock 重新打开都能看到窗口。
- 其余页面（订阅/关于/许可/协议/sheet 表单）仍沿用系统 Form 样式，后续可按同一 token 继续套用。

#### 8.2.1 细节打磨（按用户反馈）

- **去掉右侧渐变背景**：`MacGlassPageBackground` 改为纯色平铺（`MacGlass.flatPage` ≈ #F2F3F6），
  window 根视图也设置同色背景，避免标题栏/工具栏露出白色断层。
- **窗口整体宽度 -30%**：默认窗口 1180×780 → **826×780**，最小宽 960 → 680；
  侧边栏列宽限制 180–220（理想 196）；内容列相应收窄（连接页 620、设置页 900、节点页 700）。
- **连接页无右侧滚动条**：macOS 用 `ViewThatFits` 优先选择不滚动布局，只有窗口极小时才回退到
  隐藏指示条的 `ScrollView`。
- **本次会话更紧凑**：2×2 大指标格改为单行 4 个紧凑指标（图标+标签+数值），高度约 60pt，
  减少空白且信息密度更高。
- **设置页紧凑两栏 + 无滚动条**：左栏 测速/订阅/GEOIP，右栏 语言/支持/数据；行高 44，
  卡片与脚注更紧，`ViewThatFits` 保证当前窗口下完整显示。
- 按用户要求移除了 macOS 设置页的 3 段脚注（语言说明、订阅自动更新说明、GeoIP 自动更新说明），
  以及订阅列表页底部的「App 打开时会自动更新订阅」；iOS 仍保留这些说明。
- 左侧栏应用名下方不再显示版本号；连接页/设置页内容改为**顶部对齐**（此前 `MacGlassPage` 的 ZStack
  默认居中，导致大标题不在顶部）。

截图：`docs/macos-screenshots/01-home-ipad-layout.png`、`02-home-connected.png`、`03-nodes.png`、`04-settings.png`。

---

### 8.3 菜单栏图标 + 快捷操作菜单（2026-11-22）

按用户选定的 **原生 NSMenu 方案（设计稿 A）** 实现 macOS 菜单栏常驻图标与快捷菜单：

- `WujiMac/MenuBarController.swift`（`NSStatusItem` + `NSMenu`）：
  - 图标使用 **App 自己的图标**（`NSApp.applicationIconImage` 缩放到 18pt，非模板）；已连接时右下角显示绿色状态点（连接中橙色）。
  - 菜单内容：状态头（已连接/未连接 · 节点 · 协议）；连接/断开（⌘D）；「当前节点」子菜单
    （所有节点，当前节点打勾，点击切换并自动重连）；「分流」子菜单（规则/全局，切换后自动重连）；
    实时下载/上传/时长（菜单打开时每秒刷新，自定义两列 NSView 右对齐数值）；
    显示主窗口；设置…（⌘,）；关于无极代理；退出无极代理（⌘Q）。
  - 窗口跳转通过 `Notification.Name.wujiSelectTab` 通知 `RootView` 切换侧边栏选中项。
  - 菜单栏在 App 启动时由 `MacWindowDelegate.applicationDidFinishLaunching` 启动。
- 截图：`docs/macos-screenshots/16-menubar-menu.png`。
- 仅 macOS：iOS 构建不包含该文件。

---

### 8.4 实时连接日志（日志页 · 代理 / 直连）

- **左侧栏「日志」页**（设置下方，macOS 独有）：实时显示每条连接的路由结论：
  `代理` / `直连` / `DNS` / `其他`，带时间、域名、目标 IP:端口。
- **不落盘、内存上限 1 MB**：
  - Xray 在 extension 临时目录写 access log（含 `dnsLog`），`WujiTunnel/AccessLogRelay` 每 0.8s 增量解析；
  - 解析结果只存在 extension 内存 ring buffer（≤1 MB），连接停止时删除临时文件并清空；
  - App 通过 `sendProviderMessage` 的 `logs` / `logsClear` 拉取增量，页面自己再保留 ≤1 MB（最新在前，
    超出时从最旧开始丢弃），连续跑几天也不会增长。
- **域名显示**：extension 同时开启 Xray DNS log，把 `域名 -> IP` 映射回访问日志的目标 IP，
  因此日志里能显示 `www.apple.com` 这类域名；没有 DNS 记录的目标显示 IP。
- **排序**：最新的一条在最上面，越往下越旧（按 seq 倒序）。
- 顶部一行：日志标题 + 过滤（全部/代理/直连/DNS/其他）+ 实时状态 + 保存/暂停/清空；
  菜单栏「连接日志…」（⌘L）也会跳到这个页面。
- **保存**：把当前过滤后显示的日志另存为 `.txt`（时间 / 路由 / 域名 / 目标 / 路由标签，最新在前）。
- **可选中复制**：日志行文字启用 `textSelection(.enabled)`，可用鼠标选中并 ⌘C 复制。
- iOS 不启用 access log，不包含日志页。
- 截图：`docs/macos-screenshots/17-connection-log.png`。

---

## 9. 已知限制 / 风险

1. **真实隧道已验证基础连通**（见 §7.1），但长稳、分流规则、DNS 泄漏、多协议/多节点仍需继续手测。
2. **App Store Connect 还未有 macOS platform**：必须先 Add Platform，才能上传 build/配置截图；同一 record 加平台后是 **universal purchase**（$8.99 既有用户可免费下载 Mac 版），且上传过 build 后不能删平台。
3. **macOS 26+ only**：`LSMinimumSystemVersion 26.0`；如需支持更旧 macOS 要下降部署目标并回归 SwiftUI API。
4. **无相机扫码**：macOS 只支持照片/文件导入 + 粘贴；如需实时相机扫码要另写 `AVCaptureSession` + 权限/entitlement。
5. **IPv4-only / 无 on-demand / 无 per-App 统计**：与 iOS 相同的产品限制。
6. **图标仍是 iOS 风格**：macOS 26 的 Liquid Glass 图标建议后续用 Icon Composer 重新出（非阻塞，商店可先用 1024 PNG）。
7. **UDP/DNS 行为**：Xray 侧不变；真机验证时重点看 DNS 是否走代理（`1.1.1.1/help`）与分流规则。
8. **utun fd 兜底**：主路径在 macOS 上是否总是失败未实测；兜底逻辑已加，真机连不上时先看扩展日志（subsystem `com.juejin.ios.wuji.tunnel-ext`）。

---

## 10. 待用户/后续动作

1. **App Store Connect（Account Holder/Admin）**：Add Platform → macOS；补 macOS 描述/宣传文本/截图/版本号/审核信息；见 `docs/macos-appstore-checklist.md`。
2. **真实 Mac 测试**（有真实节点后，约 10 分钟）：
   - 用 Xcode 登录 team `R6748V42K5` 后运行 `Wuji.app`；首次会弹“WProxy 想添加 VPN 配置”→ Allow；
   - 同意协议/权限 → 添加真实节点（手动/订阅）→ 连接 → 检查：
     1) 首页状态“已连接”，流量/时长增长；
     2) Safari 打开 `https://ipinfo.io` 显示代理 IP；
     3) `1.1.1.1/help` 确认 DNS 无泄漏；
     4) 规则模式选“中国”直连，国内站点可访问；全局模式全部走代理；
     5) 断开后系统设置 VPN 状态同步消失；`ipconfig getifaddr utunX` 路由恢复；
     6) 若失败：`log show --last 5m --predicate 'subsystem == "com.juejin.ios.wuji.tunnel-ext"'` 收扩展日志。
3. **商店截图**：macOS 16:10（2560×1600 等），至少 1 张/尺寸，不能含真实节点信息。
4. **版本号决策**：当前 macOS targets 与 iOS 对齐 `3.3.1(2)`；也可改成 macOS 首发 `1.0(1)`（appex build 号必须与宿主一致；ASC 里 macOS 版本号需与 build 的 `CFBundleShortVersionString` 一致）。改版本只动 `project.yml` 里两个 macOS target。
5. 可选：Icon Composer 图标；Developer ID 分发（需要另加 system extension target）。

---

## 11. 文件改动清单（本次移植）

新增：

- `WujiMac/`（Info plists、entitlements、Assets.xcassets）
- `Wuji/DesignSystem/PlatformCompat.swift`
- `docs/macos-port.md`、`docs/macos-appstore-checklist.md`、`docs/macos-asc-status.md`、`docs/macos-build-upload.md`

修改：

- `project.yml`（新增 `Wuji-macOS` / `WujiTunnel-macOS` / `WujiTests-macOS` + scheme；LibXray 注释与 macOS 链接参数）
- `Wuji/DesignSystem/Theme.swift`（macOS 语义色）
- `Wuji/App/RootView.swift`（平台激活通知 + macOS 固定 iPad 布局 + 窗口尺寸）
- `Wuji/App/WujiApp.swift`（macOS 默认窗口 1180×780 / 最小 960×640）
- `Wuji/DesignSystem/PlatformCompat.swift`（平台 shims + macOS sheet 固定尺寸 + sheet 底部操作栏）
- `Wuji/Core/Models/AppGroup.swift`（macOS TeamID app group）
- `Wuji/Core/Tunnel/TunnelController.swift`（on-demand cellular 平台分支）
- `Wuji/Core/Tunnel/NetworkPermissionRequester.swift`（macOS 跳过 Bonjour 授权）
- `WujiTunnel/TunFdResolver.swift`（macOS utun fd 兜底）
- `Wuji/Features/**`（平台 shim + macOS sheet 适配：list style、toolbar placement、nav title、pasteboard、haptics、open URL、QR 图片/分享/保存、扫码页、onboarding pager、picker style；分流/添加订阅/添加节点/节点操作/地区选择/分享等 sheet 的尺寸与底部操作栏；节点操作里的编辑/二维码在 macOS 改为独立 sheet；协议/订阅间隔在 macOS 改为 menu picker）
- `WujiTests/DataTests.swift`（macOS 沙盒下跳过 loopback listener 测试）
- `Wuji/Resources/*.lproj/Nodes.strings` ×11（新增 `nodes.qr.saveToFile`）
- `tools/build_libxray.sh`、`tools/libxray-patch/validation/*`（3-slice 构建与验证）
- `Frameworks/LibXray.xcframework`（新增 macOS universal slice）

未做：git add/commit（按项目规则）；App Store Connect 任何写操作。

---

*最后更新：2026-11-22 · 与 `project.yml`/源码冲突时以源码为准。*
