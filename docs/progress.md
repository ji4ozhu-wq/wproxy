# 无极（Wuji）— 进度与验收记录

## 阶段 0：开场与前置自检

- 2026-11-20：用户选择 **共创模式 + iOS**。暂定名“无极”，目录 `app_src/wuji/`，Bundle ID `com.wuji.app`，UI 语言 `en`，联系邮箱 ji4ozhu@gmail.com。
- 通用工具自检（开工前）：
  - REA：`npx rea-agents --version` → 4.0.1 ✓（DSH 会话未挂载 REA MCP 工具，Android 逆向时用裸 adb 兜底；本项目 iOS）
  - codex-collab：`health` 通过 ✓
  - xteam：`~/.claude/skills/xteam/xteam.mjs` v1.5.0 ✓
  - draw-ui ✓、humanizer ✓、imagegen-frontend-mobile ✓、aso-appstore-screenshots ✓、Pillow 13.0.0 ✓
  - high-end-visual-design：缺失 → 已安装（`npx skills add payoss/uiux-high-taste-skill@high-end-visual-design`）✓
  - gpt-image-2 配置 `Public/docs/image-gen-env.txt` 存在（base_url / api_key / image-model=gpt-image-2）✓
- iOS 平台专属：
  - macOS 26.7.1 + Xcode 27.2 ✓
  - 已配对真机：`Wanli的iPhone 16`（UDID 00008140-001934312102801C，physical, available）
  - 模拟器多台可用（含 iPhone 17 Pro / iPhone SE 3rd）
  - 开发者团队沿用 C544N77LD9
- 选定的 Codex 模型（codex-collab models 里唯一可用）：`mimo-v2.6-pro`（reasoning: none / high；落盘用 high）
- 待办：iphone-use / iphone-mcp 检测放在阶段 3 开工前（本机真机测试需要）。
- Go 工具链：go1.26.0 darwin/arm64 ✓；gomobile 未安装（如选 v2ray-core 嵌入方案，需 `go install golang.org/x/mobile/cmd/gomobile@latest` + `gomobile init`）。

## 阶段 1：功能探讨（已完成）

- 2026-11-20：已记录用户思路原文（见 `docs/discussion.md`），提交复述理解与第 1 轮确认弹窗。
- 2026-11-20：启动两个外部调研子代理：① v2ray-core/Xray-core 嵌入 iOS NetworkExtension 的可行性与构建方式；② App Store VPN 应用政策与上架要求（5.4、NetworkExtension entitlement、中国大陆资质等）。结果待回收。

## 阶段 2：视觉方向（已完成，2026-11-20 gate 通过）

- 2026-11-20：用户确认功能清单（gate 通过）；`docs/app-spec.md` 已产出（七段式，§三画风待阶段 2 回填）。
- 2026-11-20：用户要求「先设计 UI，满意后再继续做其他」→ 当前专注阶段 2。
- 2026-11-20：出图通道验证通过（gpt-image-2 `/images/generations`，配置只从 `Public/docs/image-gen-env.txt` 运行时读取）。
- 2026-11-20：正在生成 3 个风格方向 × 2 张核心屏（`design-refs/style-directions/`）：A Signal Atlas（编辑感纸质）、B Studio Glass（iOS 原生玻璃）、C Traffic Control（工业仪表）。

## 阶段 3：实现

（未开始）

## 阶段 4：验收

（未开始）

## 阶段 5：商店信息

（未开始）

## 阶段 6：交付摘要

（未开始）

### 背景补充与调研

- 2026-11-20：用户说明已持有资质并成功上架旧 App「无极代理」（`com.juejin.ios.wuji`，绍兴天穹网络科技有限公司，中国区，免费+内购，最后更新 2020-04）；本次是**自有 App 重构**。
- 2026-11-20：用户提供 socks5 代理 `192.168.31.88:9966`（仅开发期访问 GitHub/下载依赖用），已实测可用。
- 2026-11-20：引擎调研（子代理）结论：优先 `XTLS/libXray`（Xray-core 官方 iOS 封装）；NE 必须真机、~50MB 内存上限、geoip 全量 23MB 不可行（用 `geoip-only-cn-private.dat` 236KB）；URI 解析用 libXray `convertShareLinksToXrayJson`（不含 legacy vmess base64）。
- 2026-11-20：自建 v2ray-core gomobile 封装试验（/tmp/v2test）：go mod tidy 成功；gomobile bind 报「requires golang.org/x/mobile in module graph」，需 `go get -tool golang.org/x/mobile/cmd/gobind` 后重试 —— 说明 v2fly 自封装可行但需额外适配，且无官方 iOS 支持。

### 2026-11-20 调研回收

- **NE ↔ Xray 桥接（子代理 C）**：首选方案 = 枚举扩展进程 fd 定位 utun（`getpeername` AF_SYSTEM + `ioctl(CTLIOCGINFO)` 比对 `com.apple.net.utun_control`，纯 POSIX）→ 写入 Xray 配置根 `env["xray.tun.fd"]` → Xray tun 入站原地读写（libXray 官方支持，apiVersion 3）。无需 tun2socks、无需改 xcframework。备选 = hev-socks5-tunnel / Tun2SocksKit（MIT）。参考实现：illiasab/VLESSKit（MIT，现成 NEPacketTunnelProvider）。DNS 需劫持 53 到 dns outbound 或 fakedns；路由用 includedRoutes 0/0 + excludedRoutes LAN + enforceRoutes；代理服务器 IP 必须排除否则回环。
- **App Store 政策（子代理 B）**：5.4 要求组织账号 ✓（公司账号）；内核必须编译进包，不能运行时下载；首启需数据声明页；中国区需 ICP/资质（用户自称资质齐全，已成功上架）；通用代理客户端中国区过审风险高 → 记录风险；加密出口申报需在阶段 5/6 处理；VPN 无法在模拟器测试，只能真机。
- **libXray 构建验证**：`/tmp/libXray/LibXray.xcframework` 构建成功（Xcode 27.2，Go 自动拉 1.27.3，经用户 socks5 代理下载依赖）。

### 阶段 2 进展

- 2026-11-20：出 3 个风格方向（A Signal Atlas / B Studio Glass / C Traffic Control，各 2 屏）→ 用户反馈"希望原生 UI 设计"→ 二次确认选"纯系统默认风"。
- 2026-11-20：按纯系统默认风（SF Pro、SF Symbols、inset grouped 列表、系统蓝、原生导航栏/标签栏）出全部 28 张设计图，落盘 `design-refs/native/`，索引 `design-refs/index.md`；评审拼图 `sheet-1..5`。修正了第一轮的 tab bar 漂移与 iPad 画布裁切问题。

### 阶段 2 确认记录（gate）

- 2026-11-20 用户确认：3 个风格方向后选「纯系统默认风」→ 28 张全量设计图评审「**全部通过，开始实现**」。
- 定稿图清单：`design-refs/index.md`（native/ 共 28 张，风格基准 `native/N-home-connected.png`）。
- 视觉规范已回填 `docs/app-spec.md` §三。

## 阶段 3：实现（进行中）

- 2026-11-20：工程骨架完成（XcodeGen 两 target + 单测 target），模拟器编译通过。
  - `project.yml`（Wuji / WujiTunnel / WujiTests）、Info.plist、entitlements（App Group + NE packet-tunnel-provider）、Assets、双语 Localizable.strings（主表 + Nodes/Settings/Routing/Subscriptions 分表避免并发冲突）。
  - 共享层：Models、AppGroup、AppDatabase（SQLite WAL）、ProfileStore/SettingsStore/SubscriptionStore、AppState、Theme/Components、TunnelControlling 协议、XrayConfigBuilder/URIParser/CountryDirectory/LatencyTester 骨架。
  - 裁剪版 `Frameworks/LibXray.xcframework`（iOS arm64 设备 + arm64 模拟器，77MB）就位；主 App 不链接，仅 NE 扩展链接。
  - App 图标：`design-refs/icon-1024.png`（原生系统蓝 + 白色 W 几何标记）已进 Assets。
- 2026-11-20：App 骨架在模拟器跑通（启动→协议同意页，中文系统语言环境截图 `screenshots/impl-lead/01-launch-consent.png`）。
- 2026-11-20：并行开工 4 个 teammate：data（task-1）、engine（task-2）、pages-a（task-3）、pages-b（task-4）；Lead 负责首页/自适应（iPad + Duo）/集成/真机/验收。共享任务板记录在 team task board。
- 2026-11-20：共享层接口补充：`AppState.autoUpdateSubscriptionsIfNeeded()`、`AppState.refresh(subscription:)`、`AppState.resetVPNConfiguration() async -> Bool`、`TunnelControlling.resetConfiguration()`；RootView didBecomeActive 触发订阅自动更新。
- 2026-11-20：自适应布局：宽度 ≥700pt（iPad / Duo 展开）用 `NavigationSplitView` 侧边栏+详情，窄屏用原生 TabView（已编译通过）。
- 2026-11-20：设计合理偏差记录：N-settings 设计图漏了「订阅列表」入口，为实现 D14 在设置页保留 Subscriptions（带计数）行。

## 阶段 3 完成记录（2026-11-20）

- 4 个并行 teammate（data / engine / pages-a / pages-b）+ Lead 集成，任务板 task-1~4 全部完成：
  - **data**：SQLite（WAL/迁移/事务/级联）、URI 四协议解析/编码（含 legacy vmess base64）、订阅服务（Userinfo/错误分类/URLProtocol 单测）、测速（可取消/批量）、国家 CIDR（249 国 / 249,596 条 / 4.22MB，脚本 `tools/gen_country_cidrs.py` 可复现）、DEBUG 演示数据（9 节点/2 组/1 订阅，幂等）。30 条单测全过。
  - **engine**：XrayConfigBuilder（4 协议、4 传输、TLS/REALITY、tun inbound、DoH 防泄漏、分流/防回环、stats、log none；9 份配置经真实 Xray testXray 校验通过）、TunnelController（NE 全生命周期/按需/状态监听/流量/重置）、PacketTunnelProvider + utun fd 探测（纯 POSIX）+ XrayRunner、libXray fork 增补 getTrafficStats 并重建 xcframework。22 条单测全过。
  - **pages-a**：引导 3 页、协议同意门控、节点列表（搜索/排序/测速/刷新/滑动操作/订阅分组状态）、节点操作菜单、四协议动态表单（校验/编辑/重复检测）、扫码（AVFoundation + PhotosUI + 权限降级）、剪贴板批量导入、二维码分享；35 张截图（EN/zh/SE/iPad + 两条运行时冒烟：保存入库、批量导入）。
  - **pages-b**：订阅列表/添加/详情/更新/删除（自定义二次确认）、分流（Rule/Global + 局域网 + 地区多选 + 即时保存）、设置全部子页（On-Demand/测速 URL/超时/重置 VPN/清空数据/关于/许可/协议/隐私）、双语 Markdown 渲染、74 个 accessibilityIdentifier；33 张截图 + 真实订阅失败链路实测。
  - **Lead**：工程骨架/共享层/首页（含 mock 连接态与演示会话数据）/自适应布局（≥700pt NavigationSplitView：iPad、Duo 展开）/调试截图钩子/集成构建/图标/国家名规范化。
- 集成构建：模拟器 `BUILD SUCCEEDED`；真机架构 `CODE_SIGNING_ALLOWED=NO` 编译通过（完整签名待开发者门户配置）。
- 单元测试：`WujiTests` **55/55 通过**（WujiTests + 数据 30 + 引擎 22 + 冒烟 3）。
- 阶段 4 交互覆盖：新增 `WujiUITests` target + scheme，teammate `ui-tests` 正在写全页面 XCUITest（详见 `docs/ui-test-report.md`）。

## 视觉/实现偏差记录（合理偏差）

1. 节点列表工具栏在「+」左侧增加排序、全部测速按钮；行内增加「⋯」菜单（spec 要求，设计图未画）。
2. 节点操作 sheet 增加「Share」一行（系统分享）；协议分段控件 Shadowsocks 显示为 "SS"（小屏不截断）。
3. 订阅分组头显示「节点数 · 更新时间」（spec 要求）。
4. 设置页保留「订阅列表」入口（设计图遗漏，功能必需）。
5. 国家名按系统 Locale 显示；对 iOS 26 的 "China mainland" 做了短名规范化（→ "China"）。

## 阶段 4 验收（进行中）

- 交互覆盖：XCUITest（teammate ui-tests 执行中）。
- 设备矩阵：iPhone 17 Pro（EN/zh）、iPhone SE 3、iPad Pro 13 已截图；6.9"（iPhone 17 Pro Max）已用于商店图。
- **真机跳过（用户 2026-11-20 决定「先跳过真机验证」）**：
  - 原因：Apple 开发者门户需为 `com.juejin.ios.wuji` / `com.juejin.ios.wuji.packettunnel` 开启 App Groups + Network Extensions 能力（需用户管理员操作）；未开启时真机签名失败。
  - 后果：NE 隧道真实建立/断开、utun fd 探测、真实节点连接（4 协议）、真实流量统计、按需连接、相机扫码、保存相册等**未在真机验证**；交付摘要如实标注。
  - 待用户配置门户后：`xcodebuild -allowProvisioningUpdates` 真机构建 + 安装到 Wanli的iPhone 16 + 按 `docs/ids-engine.md` §8 步骤联调。

## 阶段 5：应用商店信息（已产出）

- `应用商店信息/商店5图/`：5 张 1320×2868 JPEG（RGB，无 alpha）——01-home(CONNECT) / 02-nodes(MANAGE) / 03-routing(ROUTE) / 04-import(IMPORT) / 05-subscriptions(SYNC)；总览 `design-refs/store5-overview.jpg`；制作链：真实 6.9" 截图（iPhone 17 Pro Max，status bar 9:41）→ `tools/aso/compose.py` scaffold（1290×2796，SF Pro Display Black，浅蓝底深色字）→ gpt-image-2 `/images/edits` 8 张（首批 3 变体选风格模板；其余按模板生成，严格保留文字与 UI）→ 等比缩放到 1320×2868。
  - 风格模板：`tools/aso/scaffolds/s1-style-template2.png`；最终 AI 图：`/tmp/store-final/s1..s5`（临时候选，终稿已入 `应用商店信息/商店5图/`）。
  - 文字逐张核对与 scaffold 一致；App UI 未被重绘；无额外文字/logo；无 Gemini 参与（合规）。
  - 过程中出现过 AI 输出宽高比不稳导致裁掉标题的问题：已通过「输出必须匹配输入画布比例」重试至 852×1846，再按高度等比缩放到 1320×2868（不拉伸、不裁标题）。
- `APP图标-1024.png`：1024×1024 RGB 无 alpha，与 AppIcon 同源（`design-refs/icon-1024.png`）。
- `隐私政策.md` / `用户协议.md`：英文定稿（含运营主体/联系方式/数据实践/权限/删除），已同步回 App 内 `privacy-en.md` / `terms-en.md`，中文版 `privacy-zh.md` / `terms-zh.md` 同步更新并重新编译。
- `提交填写信息.md`：Title/Subtitle/Promotional Text/Keywords/Description（英文主版本，字符数在限内）+ 中文参考翻译 + App Review Notes（Guideline 5.4）+ App Privacy/Data safety 要点。

## 阶段 5 验收（自检）

- [x] 目录齐全（iOS 5 类产物）
- [x] 商店5图 5 张、1320×2868、RGB、无 alpha、5 张不同屏、英文
- [x] compose scaffold + gpt-image-2 edits；无 Gemini；回退与重试已记录
- [x] 文字与 scaffold 一致、UI 未重绘、无额外文字/logo/伪影
- [x] 图标 1024 无 alpha
- [x] 隐私政策/用户协议存在、双语内容一致、与 App 内文本同步并重编译核对
- [x] 提交填写信息字段齐全、字符数在限内、名称不含原 App 品牌、中文参考翻译
- [ ] 隐私政策/用户协议/支持 URL 线上发布（待办）
- [ ] 中国区资质材料附审核备注（待用户提供）
- [ ] 测试节点/示例二维码用于 App Review（待用户提供）

### 设备矩阵补充（2026-11-20）

- **iPhone Duo 模拟器不可用**：本机 Xcode 27.2 已有 `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo` 设备类型，但与已安装的 iOS 26.2 / 26.5 / 27.0 / 27.2 runtime 均报 "Incompatible device"，无法创建。Duo 展开布局以 ≥700pt 宽屏自适应（NavigationSplitView）实现，已用 iPad 13" 模拟器验证；Duo 真机/专用模拟器待有对应 runtime 后补测（设计图 `design-refs/native/N-duo-unfolded.png` 为目标形态）。

## 阶段 4 交互覆盖补充（2026-11-20 07:10）

- 新增 `WujiUITests` target（XCUITest，38 条用例），test 通过 `docs/ui-test-report.md` 记录（teammate ui-tests 产出）。
- ui-tests 报告的产品侧缺口已由 Lead 修复并编译通过：
  1. 扫码预览卡父容器吞掉子控件 identifier → 加 `.accessibilityElement(children: .contain)`。
  2. 首页/首连弹窗缺 identifier → 补 `wuji.home.statusTitle/statusSubtitle/currentNodeRow/routingRow/chooseNode`、`wuji.home.firstConnect.allow/notNow`。
- 疑似崩溃已排除：CountryPicker 首次打开卡顿来自 4.4MB 国家 CIDR 在主线程同步解码；已在 AppState 启动时后台预解码（`Task.detached`），相关用例复跑通过。

## 阶段 4 最终结果（2026-11-20 07:30）

- 阶段 gate 判定（Lead 签字）：
  - impl-plan：A/B/C/D 组代码项全部 DONE；真机相关（A2 签名、C4/C7、D6、F2/F3）因用户选择跳过真机为 **BLOCKED（待开发者门户配置）**；E/F 交互项按 XCUITest 结果记录。
  - 每页 DoD：控件/文案/状态/持久化/视觉对照均有实现与截图证据（`screenshots/impl-pagesA|impl-pagesB|impl-lead/`）。
  - XCUITest：38 条，**34 通过 / 4 已知失败**（详见 `docs/ui-test-report.md`；2 条测试侧时序、2 条待真机复现，无崩溃/数据丢失）。
  - 收尾修复（报告后）：① 订阅编辑保存不再阻塞等待网络刷新（后台刷新，失败写 lastError）；② 首页/扫码 identifier 补齐；③ 国家数据启动后台预解码。
- 阶段 4 未通过项：真机 VPN 旅程（F2/F3）、Duo 实机、相机/相册/系统分享（环境限制）——在交付摘要「已知风险/待办」中单列，不冒充通过。
- 阶段 5 已产出并通过自检（见上）。
- 阶段 6：`交付摘要.md` 已写（只写实际结果）。

## 生命周期修复（task-6 / lifecycle-fix，2026-11-20 09:16–09:25）

> 范围：审计 A1/A2/A4/A5/B1/B6/B7/B8/B10（部分）/B11/C7/C9 + 用户决策 G3/G4。
> 写权限：AppState / TunnelController / AppGroup / TunnelNetworkSettings / Wuji.entitlements /
> SettingsView / Components / HomeView / docs/ids-lifecycle.md（另有一行 PacketTunnelProvider
> 接线为 B1 必需）。未改 project.yml、Resources、Features 下的其他文件。

- 已完成（编号 = 审计项；代码位置见 `docs/ids-lifecycle.md`）：
  1. **A1** `Wuji/Wuji.entitlements` 增加 `com.apple.developer.networking.networkextension = [packet-tunnel-provider]`（门户能力 + 真机仍待用户/Lead）。
  2. **A2** `TunnelController.stop()`：先 `applyOnDemandRules(.off)` + `saveToPreferences`（保存后 manager 失效 → reload + 重装状态监听），再 `stopVPNTunnel`；on-demand 模式下用户可从 App 内真正断开。`updateOnDemandMode` 保存后同样 reload，避免后续 stop 用失效 connection。
  3. **A4** 设置 → 清空数据：二次确认 → `await app.resetVPNConfiguration()`（停隧道 + 移除系统 VPN 配置 + 删 App Group 文件）→ `AppDatabase.deleteAllData()` 事务清库 → `settings.clearData.success` toast（900ms）→ 回引导态；VPN 重置失败时不清库、给错误 toast。
  4. **A5** `refresh(subscription:)` 的 active 恢复改为「proto + server + port + 凭据（VMess/VLESS=uuid，Trojan/SS=password）」映射，server/uuid 忽略大小写；rawURI 不参与；匹配不到清空 active；订阅刷新 remap 不触发自动重连。
  5. **B7/G4** `deleteProfile`：被删节点是当前节点且隧道未断开 → 先断开再删；新增 `disconnectIfActiveNodeDeleted(_:)`、`prepareForRemoval(of:)`、`prepareForRemoval(ofGroup:)`（删订阅调用点由 Lead 接线）。
  6. **B1** `TunnelLaunchConfig` 增加 `bypassLAN`（旧文件容错解码默认 true）；`AppState` 传入；`TunnelNetworkSettingsFactory.make(...bypassLAN:)` 按开关决定是否排除 RFC1918/RFC4193(ULA)；loopback/link-local/CGNAT/multicast 始终排除，代理服务器 IP 始终排除，tunnel 子网/DNS 不受影响（PacketTunnelProvider 一行接线）。
  7. **B6** `ConnectionButton` 在 `connecting`/`disconnecting` 时 `.disabled`；HomeView 忙时不再把点按转成断开；`connect()` 保留 isBusy guard，新增 isAutoReconnecting guard。
  8. **G3** 连接中切换节点 / 改 routingMode / bypassLAN / bypassCountryCodes：保存上次连接快照 `TunnelSetup`，不一致时 0.5s 防抖后 `disconnect + connect`；`autoReconnectEpoch` + `connectGeneration` 保证手动断开/删除/重置能取消在途自动重连，且被取消的启动若已完成会被 stop；失败沿用既有 error banner/状态（短暂 disconnected 不弹错误）。
  9. **B8** `refresh` 失败改 `SubscriptionStore.recordFailure`（lastError + lastUpdatedAt，前台自动更新不再每次激活重试同一订阅）；新增 `refreshingSubscriptionIDs` 与 `SubscriptionFetchGate` 双层去重（并发抛 `error.subscription.inFlight`）。
  10. **B10（部分）** `TunnelError.startupTimedOut` → `L10n.t("error.tunnel.timeout")`；`configurationFailed` 保留 detail、空 detail → `L10n.t("error.tunnel.failed")`（两个 key 已由 Lead 补齐 en/zh-Hans，Localizable.strings 137–138 行）。
  11. **B11** `TunnelController` 中带服务器地址/配置错误详情的日志全部改 `privacy: .private`（仅 on-demand rawValue 仍 public）。
  12. **C7** `SectionHeader` 中文环境不 `uppercased()`；HomeView 延迟文案改 `String(format: L10n.t("unit.ms"), ...)`。
  13. **C9** `active_tunnel.json` 写盘加 `.completeFileProtectionUntilFirstUserAuthentication`；`TunnelController.stop()`（显式断开）与 `resetConfiguration()` 删除该文件。
- 构建/单测（2026-11-20 09:23，独立 derivedData `/tmp/wuji-dd-life`）：
  - `xcodebuild ... -destination 'platform=iOS Simulator,id=7EFFAD4E-…' build` → **BUILD SUCCEEDED**（含主 App entitlements 签名/嵌入校验）。
  - `xcodebuild ... -only-testing:WujiTests test` → **58/58 passed, 0 failures**（TEST SUCCEEDED；09:23 首轮为 55/55，09:26 终轮含其他 teammate 新增的 3 条测试，全绿）。
- 未完成/风险：
  - 真机验证全部未做（用户已决定先跳过真机）：A1 主 App NE 能力需门户开启后 `-allowProvisioningUpdates` 真机构建；A2/B1/G3/G4/C9 的真机验证路径见 `docs/ids-lifecycle.md` §6。未声称真机通过。
  - `routing.reconnectFootnote`（“下次连接生效”）与新的自动重连行为不一致；该串在 `Resources/Routing.strings`（非本任务写权限），待 pagesB/Lead 更新。
  - `error.tunnel.timeout` / `error.tunnel.failed` 两个本地化 key：Lead 已于 09:23 补齐 en/zh-Hans。
  - 本任务未新增 `accessibilityIdentifier`：新增契约说明在 `docs/ids-lifecycle.md`。

## 第二轮：审计修复 + GeoIP 架构改造（2026-11-20 09:10 起）

- 只读审计（全部 50 个 Swift 文件）结论落盘 `docs/audit-report.md`（A 阻断级 5 条 / B 重要 14 条 / C 细节 12 条 / D 对 4 条 UI 测试失败的判断）。
- 用户决策（详见 `docs/discussion.md` §5/§6）：自动重连、删当前节点自动断开、改 MaxMind 系数据源（实际 v2fly/DB-IP）、GeoIP 运行时按 IP 判断（单条全局规则）、仅连接 VPN 后更新、固定 1 小时重试、测速 URL 经代理测 HTTP。
- 并行修复线：
  - lifecycle-fix（task-6）：A1 主 App NE entitlement、A2 on-demand 可断开、A4 清空数据先重置 VPN+事务清库+toast、A5 订阅刷新 active 按凭据映射、B7/G4 删当前节点先断开、B1 局域网开关真实生效、B6 连接键 busy 禁用、G3 连接中修改自动重连（0.5s 防抖+代次取消）、C9 配置文件 file protection、B8 recordFailure + 去重、B11 日志隐私、B10 部分错误本地化、C7 中文不 uppercase。构建绿、单测 58/58。
  - import-ui-fix（task-7）：SNI 兜底、http 订阅拒绝（loopback 放行）、订阅失败记录与去重、导入去重与汇总、订阅更新入口、协议页 Markdown 渲染、About 许可去重与真实图标、权限说明、小屏/大字号适配、滑动操作 identifier、错误文案本地化（进行中）。
  - geoip（task-8，架构已调整）：bundle `geoip.dat.gz` + 国家元数据；运行期解压/抽取选中国家的 protobuf entry 生成小型 `wuji-geoip-<hash>.dat`；Xray 配置只加 **1 条** `ip:[ext:...:cn, ...]` direct 规则 + `xray.location.asset` env；更新仅 VPN 连接后、失败固定 1 小时重试。
- Lead 已完成：主 App/扩展 PrivacyInfo.xcprivacy（SystemBootTime 35F9.1，已确认打进两个 bundle）、中英文 DisplayName（zh-Hans「无极代理」）、移除错误的 ITSAppUsesNonExemptEncryption=false、License 数据署名改为 DB-IP/v2fly（CC BY-SA 4.0）、商店隐私政策/提交信息补 DNS(DoH 1.1.1.1) 与 GeoIP 数据披露、LatencyTester 新增 `testHTTP(urlString:timeout:)`、AppState 新增 `testLatencyResult(for:)`、Release 模拟器 x86_64 排除修复、Extension 日志隐私。

### task-8 GeoIP 数据链路（geoip，2026-11-20 09:55 终验）

- 用户决策后的架构：分流不再把 CIDR 展开进 Xray 配置，改为内置 `geoip.dat` + Xray `ext:<file>:<cc>`
  运行时匹配（配置文件只加 1 条 direct 规则 + `xray.location.asset`）；App 每 7 天自动更新、仅 VPN
  已连接时下载、失败固定 1 小时重试；手动「立即更新」无视门槛。
- **数据源事实修正**：v2fly/geoip release 当前由 **DB-IP Lite（CC BY 4.0）** 编译（`build.yml` 下载
  dbip-country-lite mmdb、`config.json` 用 dbipCountryMMDB），已不再使用 MaxMind GeoLite2。署名按
  「v2fly/geoip 编译产物 CC BY-SA 4.0 + DB-IP Lite 数据 CC BY 4.0」写入 `docs/licenses-geoip.md`、
  资源元数据 `license` 字段与 `docs/deps.md`；App 内 About/许可文案（`LicensesCatalog` 旧 MaxMind 表述）
  待 Lead 接线替换。
- 内置资源（`tools/prepare_geoip_assets.py` 可复现，`--check` 校验）：
  - `Wuji/Resources/geoip.dat.gz`：**4,614,749 B（4.40 MB）**，解压 23,876,117 B，
    sha256 `eedb24b3b9fcba27e06b92c0428dab90d9496083091ae4cf39e11387fd99d0e2`（dataVersion `eedb24b3b9fc`，
    上游 release 202611080027 / 2026-11-08）。
  - `Wuji/Resources/geoip_countries.json`：2,758 B，253 个 list（250 国家/地区 + PRIVATE/TEST/ZZ），
    CIDR 合计 1,410,686；CN 15,189 / JP 38,106 / US 271,874 / DE 55,789 / GB 63,134 / SG 62,692 /
    HK 18,572 / TW 10,823 / KR 4,996。
- 新增/重写代码：`GeoIPProtoParser`（只扫描 entry + 原样复制 entry 字节，不解码 CIDR，防御截断/未知字段）、
  `GeoIPCodec`（系统 Compression + CRC32/ISIZE 的 gzip 封装）、`GeoIPMetadata`（geoip_countries.json 读写）、
  `GeoIPAssetManager`（首次启动解压安装、`makeAsset(codes:includePrivate:dataVersion:)` 抽取
  `wuji-geoip-<12hex>.dat`、文件名 hash 稳定、清理保留最近 3 个）、`GeoIPUpdater`（7 天/1 小时/仅连接后/
  jsDelivr→raw GitHub/sha256 校验/原子替换/meta+status/manualUpdate）、`CountryDirectory`（仅元数据：
  countries/localizedName/reload + 搜索/计数/来源；App Group 覆盖优先、损坏回退 bundle）。
  删除旧 RIR 脚本 `tools/gen_country_cidrs.py` 与 JSON-CIDR 方案资源 `country_cidrs.json`。
- 单测：`WujiTests/GeoIPTests.swift` 33 条（protobuf 扫描/装配、gzip、元数据、资产抽取、更新策略与
  持久化、bundle 资产完整性）+ `DataTests` 国家数据断言同步更新。
- 终验（独立 derivedData `/tmp/wuji-dd-geo`）：
  - `xcodebuild ... -destination 'platform=iOS Simulator,id=7EFFAD4E-…' build` → **BUILD SUCCEEDED**。
  - `xcodebuild ... -only-testing:WujiTests test` → **90/90 passed, 0 failures**（TEST SUCCEEDED）。
  - 模拟器集成（免联网）：App 首次启动后 App Group 生成 `geoip.dat` 23,876,117 B、
    `geoip_countries.json`、`geoip_meta.json`（dataVersion `eedb24b3b9fc`、countryCount 250、cidrCount 1,410,686）。
- 未验证/风险（如实标注）：真实联网下载与 sha256 校验链路、真机 7 天/1 小时调度、VPN 连接后更新与
  `ext:` 分流效果（模拟器不能建 NE 隧道，需真机 + 用户节点）；中国大陆网络下 jsDelivr/raw GitHub
  通常不可达，自动更新只在「已连接代理网络/海外网络」生效，失败保留内置数据；首次启动解压 23.8MB
  在后台执行（模拟器实测完成）。
- 待 Lead 接线：Settings「数据」状态行（`GeoIPUpdater.shared.status` + `manualUpdate()`）、About/开源许可
  文案按 `docs/licenses-geoip.md` 替换（DB-IP + v2fly，删除 MaxMind 表述）。

## 第二轮修复完成记录（2026-11-20 10:00）

- **lifecycle-fix（task-6）完成**：A1/A2/A4/A5/B1/B6/B7/C9/G3/G4 + B8/C7/B10/B11 部分；构建绿、单测 58→90 全绿（含他人新增）。
- **import-ui-fix（task-7）完成**：B5/B8/B9/B12/B13/B14/C3/C4/C5/C6/C7/C11 + 追加 B10/latency 接线/删订阅断开/footnote；90/90 单测全绿；定向 UI 测试 6/8（2 条 paste 为模拟器系统粘贴弹窗环境问题）。
- **geoip（task-8）完成**：新架构落地（`geoip.dat.gz` 4.4MB + 元数据 250 国家/1,410,686 CIDR；`GeoIPProtoParser/Codec/Metadata/AssetManager/Updater`；`tools/prepare_geoip_assets.py`）。模拟器启动后 App Group 实测生成 `geoip.dat`+元数据+基线 meta。
- **Lead 接线与验证**：
  - `XrayConfigBuilder` 改为单条 GeoIP direct 规则 + `xray.location.asset` env；`AppState.connectInternal` 调 `makeAsset`；连接后触发更新 + 1 小时重试 Task；AppState 新增 `testLatencyResult`；Settings 新增 GeoIP 数据区（状态/立即更新/错误/说明）；Routing 「全局模式」改为单开关。
  - **真实 Xray 校验（关键）**：`tools/libxray-patch/validation/run_validation.sh` 9 份配置全部被 libXray `testXray` 接受，含 `geoip-asset-rule.json`；另做负向验证：把 `xray.location.asset` 改成不存在目录后 testXray 立即报 `failed to open wuji-geoip-validate.dat`，证明资产/env 链路真实生效。
  - 单测：`WujiTests` **90/90 通过**（DataTests 29 / EngineTests 25 / GeoIPTests 33 / SmokeTests 3）。
  - PrivacyInfo.xcprivacy 已确认打进 App 与扩展两个 bundle；zh-Hans DisplayName = 无极代理；移除 Info.plist 的错误加密预声明。
  - 商店图 03-routing 按新 UI（Global Mode 开关）重拍/重制；`应用商店信息/商店5图/03-routing.jpg` 已替换。
  - Release 模拟器 + 设备架构构建通过；模拟器 Debug 构建通过。
- **待真机**：NE 隧道、GeoIP `ext:` 实际分流效果、真实联网更新（jsDelivr/GitHub）、相机/相册/系统分享等；中国大陆网络下自动更新源不可达（保留内置快照，风险已知）。


## 第三轮：SOCKS5 / DNS 处理方式 / 语言选项（2026-11-20 10:20 起）

- 共享层：`ProxyProtocol.socks`、`NodeProfile.socksUsername`（DB 列 `socks_username` 迁移）、`AppSettings.dnsMode`、`AppSettings.appLanguage`、AppSettings 手写容错 decode（旧 settings JSON 不丢字段）、TunnelSetup 纳入 dnsMode 触发自动重连。
- Xray：socks outbound（用户名/密码可选，含校验）；DNS 两模式（proxyDoH 保持原 DoH 经代理；local 用 223.5.5.5/119.29.29.29 并加直连路由规则）。真实 libXray 校验 12 份配置全部通过（新增 socks5-auth / socks5-open / dns-local）。
- UI：手动添加 SOCKS5、粘贴/扫码 socks URI（并行修复线）；分流页 DNS 单选（Lead）；设置页语言选项（并行修复线）。
- 持久化：AppSettings JSON + DB 列持久化；新增 AppSettingsTests（round-trip / 旧 blob 兼容 / SettingsStore 重新打开后保持）。


## 第三轮收尾（2026-11-20 11:05）

- SOCKS5（task-9）完成：URI 5 种格式解析/规范编码、手动表单 5 协议、粘贴/扫码/分享/去重、DB 列迁移、5 条 DataTests；构建绿。
- 应用内语言（task-10）完成：L10n 强制语言、设置页语言区、RootView 重建 + locale、隐私政策跟随、LocalizationTests 9 条；持久化与冷启动/即时切换均模拟器实测。
- Lead：DNS 处理方式（远程 DoH / 本地 DNS）配置生成 + 分流页 UI + Routing.strings；AppSettings 容错 decode + dnsMode/appLanguage；SOCKS5 Xray outbound 与校验；EngineTests +4（SOCKS5×3、DNS×2）；AppSettingsTests 3 条（round-trip、旧 blob 兼容、SettingsStore 重开持久化）；真实 Xray 校验扩到 12 配置全过。
- 全量单测 112/112；Debug/Release 构建绿；PrivacyInfo 双 bundle 仍生效；商店 03-routing 已按新 DNS 区更新。
- 已知 UI 测试残留 3 条（测试侧定位/时序）+ 2 条模拟器粘贴权限环境问题，详见交付摘要。


## 第四轮 UI/文案调整（2026-11-20 12:20，按用户要求）

- 首页：移除左上角大标题「连接」与右上角菜单（设置 / 重置 VPN 配置）；中间大圆形连接按钮改为系统 Toggle 开关卡片（状态标题/副标题 + 连接中进度），导航栏整体隐藏。
- 全局模式：开启后系统级 LAN 直连排除也关闭，所有流量（含局域网）走代理；只有规则模式应用局域网直连/选中国家分流（`TunnelLaunchConfig.bypassLAN = rule && settings.bypassLAN`）。
- 设置页：移除「连接」区（按需连接选项、重置 VPN 配置入口）；`Route.onDemand` 与调试路由同步移除。
- GeoIP 数据：行标题由「数据集」改为「数据库版本」，值显示版本日期（不再出现「内置快照」文案）。
- 验证：构建绿、单测 112/112；定向 XCUITest（首页连接/断开/节点与分流行、设置测速、tab 切换、清空数据）全部通过；商店 01-home 已按新首页重制。

- 收尾：删除已下线的 `OnDemandSettingsView.swift`（xcodegen 重生成）；商店图 01-home/03-routing 因 gpt-image-2 输出比例漂移导致标题被裁，改用本地确定性合成脚本 `tools/aso/compose_pastel.py`（同一 1290×2796 排版 + PIL 渐变/光斑背景 + 真机截图/设备框），文本与 UI 均完整；两图已导出 1320×2868。
- 最终：Debug/Release 构建绿，单测 112/112；定向 XCUITest（首页开关连接/断开、节点与分流行、设置测速、tab 切换、清空数据）7/7 通过。


## 第五轮：连接控件定稿 + 11 语言支持（2026-11-20 12:40 起）

- 连接控件：4 个真实 SwiftUI 方案截图对比（`screenshots/round5/connect-styles-montage.png`），用户选择胶囊按钮；Home 已移除全部预览分支，仅保留 `wuji.home.connectPill`（Connected 灰断开 / 未连接蓝连接，忙时禁用+进度）。
- 语言扩展：`AppLanguage` 增至 11 种（+zh-Hant/es/fr/de/ja/ko/ru/th/vi），`L10n.supportedLanguageCodes` 同步；新增语言菜单（跟随系统 + 当前语言 → 二级「选择其他语言」）、`LanguagePickerView`、`-WujiLanguage` DEBUG 钩子；法律文档仅英/简中（其他回退英文）。
- 翻译：9 个新语言 × 6 张 `.strings` 表由并行子代理完成，`tools/check_localizations.py` 校验 key/占位符一致性；en/zh-Hans 重复 key 修复。
- 验证：DEBUG 模拟器实测首页胶囊控件与语言菜单（en/zh）截图；商店 01-home 已按胶囊首页重制；单测 114/114。
- 完成：`xcodegen generate` 后 11 个 `.lproj` 全部进 bundle；`tools/check_localizations.py` → 10/10 语言 OK；9 种新语言 Settings 页模拟器截图抽检通过（`screenshots/round7/`）。
- 语言菜单 XCUITest 修复：Section 级 accessibilityIdentifier 会遮挡子行，移除后 `testSettingsLanguageMenuSelectionAndPersistence`（含选日语→重启保持→切回英文）通过。
- 最终验证：单测 **115/115**；定向 XCUITest（Home 胶囊连接/断开/节点分流行、tab、设置测速、语言菜单选择+持久化）6/6 通过；Release 模拟器 + 设备架构构建绿；InfoPlist 本地化名核实（zh-Hans 无极代理 / zh-Hant 無極代理 / 其他 Wuji）；PrivacyInfo 双 bundle。


## 第六轮：文案/名称/关于页/图标候选（2026-11-20 13:10 起）

- 中文文案：「直连/直連」全部改为「不代理」（zh-Hans / zh-Hant 的全部 strings，含 onboarding、分流、DNS、错误提示）。
- About 页：移除隐私政策/用户协议/联系支持入口与 mailto 代码，只保留开源许可；UI 测试同步调整。
- App 名称：非中文 9 种语言改为 **WProxy**，中文保持 无极代理/無極代理；base Info.plist、各语言 InfoPlist（CFBundleDisplayName + CFBundleName）、About 头部（`L10n app.name`）、版权、隐私政策/用户协议、商店提交文档同步。
- 图标：生成 10 个「手写体液体 W + 纯色背景」候选（`design-refs/icon-options/01..10.png`）等待用户挑选；选定后替换 AppIcon 全尺寸槽位与商店 1024 图标。
- 验证：单测 115/115 通过；About（WProxy/仅许可）与中文分流页（不代理）模拟器截图核对通过。


## 第七轮：国家/区域措辞 + 港澳台命名 + 首次权限门（2026-11-20 13:25 起）

- 中文文案：「地区/不代理地区」→「国家/区域/不代理国家/区域」，覆盖 Localizable + Routing 的全部中文串；繁体同名同步（國家/區域）。
- 国家名称：`CountryDirectory.localizedName` 改为跟随应用内语言；中文下 TW/HK/MO 显示 中国台湾/中国香港/中国澳门（繁體 中國台灣/中國香港/中國澳門）；切换语言时 reload 国家列表。
- 首次启动权限门：`NetworkPermissionView` + `NetworkPermissionRequester`（本地网络 NWBrowser + VPN 配置 NETunnelProviderManager），RootView 顺序 Onboarding → 权限 → 协议 → 主页；失败页阻止继续，提供重新请求/打开系统设置；`AppSettings.networkPermissionPassed` 持久化；DEBUG 钩子 `-WujiForcePermissionGate` / `-WujiForcePermissionFailure`。
- 验证：构建绿；单测 117/117；新增权限 UI 测试（失败页阻止 + 重试仍失败；模拟器授予后进入协议）与既有 onboarding 测试全部通过。
- 图标：液体方案被否，改为「当前蓝底 + 手写体白 W」6 个候选（`design-refs/icon-options2/01..06.png`），待用户选择。

- 图标定稿：用户选择 01 干笔刷风格并放大到溢出画面；最终图标为「#0072FE 纯蓝背景 + 超大干笔刷手写 W（左右笔锋被画布裁切）」，已替换 AppIcon.appiconset / AppIconPreview / design-refs/icon-1024.png / 商店 APP图标-1024.png，About 页与系统图标渲染核对通过。
- 权限页补充：Info.plist 增加 NSLocalNetworkUsageDescription + NSBonjourServices（`_wuji-permission._tcp`），11 种语言本地化说明；DEBUG 强制失败钩子与 UI 测试覆盖。

- 图标再调整：用户要求「钢笔字效果」；生成 4 个钢笔/蘸水笔笔尖变体（`design-refs/icon-options4/`），选定 classic-fountain（经典钢笔、笔锋收尖、干净利落、超大溢出构图）作为最终图标，已替换 AppIcon / AppIconPreview / design-refs/icon-1024(-final).png / 商店 APP图标-1024.png，About 页渲染核对通过。

- 图标最终定稿：按用户要求参考旧版 App Store 图标（绿色飘带 W）重设计，方向选择 **D 玻璃质感 + D1 深海军蓝渐变背景**（1024 源：`design-refs/icon-options-d/D1-navy.png`）；已替换 AppIcon.appiconset / AppIconPreview / design-refs/icon-1024(-final).png / 商店 APP图标-1024.png，About 页与系统图标渲染核对通过。旧图标原图与全部候选留档 `design-refs/icon-old*`。

- 用户三问收尾：① 权限页（8 keys + InfoPlist 本地网络说明）已覆盖 11 种语言，ja/de/zh-Hant 截图核对；② 「国家/区域」术语已多语言化：en = Countries/Regions，ja = 国/地域，ko = 국가/지역，es = Países/Regiones，fr = Pays/Régions，de = Länder/Regionen，ru = Страны/регионы，th = ประเทศ/ภูมิภาค，vi = Quốc gia/khu vực（17 keys × 9 语言由并行翻译完成，checker 10/10）；「直连→不代理」为中文专属，zh-Hans / zh-Hant 均已替换；③ About 页移除底部 Built with 段落（开源许可页已含全部内容），UI/截图核对通过。

## 长连接稳定性（2026-11-20 14:10）

- 用户询问锁屏 / Wi-Fi↔5G 切换 / 连续运行数天是否保持连接。现状：NE 系统隧道在锁屏下由系统持有，扩展已实现 `sleep/wake`（暂停/恢复流量定时器）；但 UI 移除按需连接设置后默认 `onDemandMode=.off`，网络切换时系统可能停止隧道。
- 改动：连接期间自动启用 **Always On-Demand**（`onDemandEnabled=true`, `onDemandMode=.always` → `NEOnDemandRuleConnect` 全接口），系统在网络变化/扩展被回收后自动拉起；手动断开仍先关闭 on-demand 再 stop。
- 预期：锁屏保持连接；Wi-Fi↔5G 切换后自动重连（切换瞬间的活动 TCP 连接会断，重连后恢复）；iPhone 被系统回收时由 on-demand 恢复。连续多天无中断无法由 App 保证（iOS 内存/电量策略），需真机多日 soak 测试。
