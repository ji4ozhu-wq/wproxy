# macOS App Store 上架 / 分发准备检查清单（WProxy · 无极代理）

> 目标：为现有 iOS App record `1448657437`（`com.juejin.ios.wuji`）**添加 macOS 平台**，用同一 bundle ID 做 **universal purchase** 的原生 macOS 26+ 版本，走 Mac App Store 分发。
> 文档基于 **2026-11-22** 的 App Store Connect 只读查询、Apple 官方帮助/文档、以及本机 Xcode 27.2 实测环境编写。
>
> **硬规则（本次全程遵守）**：不提交审核、不改价格、不改主语言、不改 Bundle ID / App Group / Team、不重建 App Store 记录、不 `git add/commit/push`、不把私钥/证书/服务器密码/审核测试节点写进仓库或文档、不对 App Store Connect 发起写请求。
>
> 配套文档：
> - [`docs/macos-asc-status.md`](macos-asc-status.md) —— ASC 只读核实详情（端点、状态、时间）
> - [`docs/macos-build-upload.md`](macos-build-upload.md) —— 构建/签名/导出/上传命令与待实测项

---

## 0. TL;DR（先看这 8 条）

1. **可行**：现有 iOS app record 可以直接 Add Platform 加 macOS（Apple 帮助明确支持），macOS 使用**相同 Apple ID / SKU / bundle ID**，iOS/OS 版本号可以不同；添加后在 App Store Connect 里得到 macOS 初始 **1.0** 版本。
2. **不需要新建 App ID / App 记录**：Apple 帮助明确「自 Xcode 11.4 起，单个 App ID 可用于 iOS、macOS、tvOS、watchOS」，主 App `com.juejin.ios.wuji`、扩展 `com.juejin.ios.wuji.tunnel-ext` 可直接复用到 macOS target。
3. **价格与既有用户**：价格是 App 级的，Mac 版同样 **$8.99**（当前 API 实测 `customerPrice=8.99`，手动价、基准美国）。至少两个平台版本通过审核后自动成为 **universal purchase**，**已购 iOS 用户可免费下载 Mac 版**（需 macOS 26+）。
4. **元数据继承有例外**：添加 macOS 平台时，**宣传文本、描述、截图不会继承**，必须单独填；名称/副标题/关键词/支持 URL/分类/年龄分级/隐私等 App 级或其它版本级信息会继承。
5. **不可逆点**：macOS 平台一旦上传过 build，就**不能删除该平台**；universal purchase 一旦生效也**无法撤销**。第一次上传前必须确认要上。
6. **阻塞状态**：
   - 构建侧（**已解除**）：`Frameworks/LibXray.xcframework` 已重建为含 `macos-arm64_x86_64`（arm64+x86_64）slice 的版本，`project.yml` 的 `Wuji-macOS`/`WujiTunnel-macOS` 已指向仓库内该 xcframework；仍待实际 macOS archive 验证链接；
   - 签名侧（**仍阻塞**）：本机没有 macOS provisioning profile，也没有 R6748V42K5 的 `Mac Installer Distribution` 证书；需要 Xcode 登录团队账号自动签名，或由用户在开发者门户创建（Account Holder/Admin）。
7. **Network Extension 走 app extension**：Mac App Store 只接受 **app extension** 形式的 packet tunnel（TN3134：macOS system extension 不能走 App Store）；当前工程的 `WujiTunnel-macOS` 类型正确，**不要**改成 system extension。
8. **文档产出边界**：本次只写 `docs/macos-*.md`；Add Platform、审核备注、真实 Mac 测试、上传/提交都要**用户执行/批准**（清单见 §7、§8）。

---

## 1. 当前状态（摘要，详见 `macos-asc-status.md`）

> 查询时间：**2026-11-22 03:44–03:53（Asia/Shanghai）**；只读 GET + `altool --list-apps`，无写操作。

| 项 | 现状 |
|---|---|
| App record | `1448657437`，bundle `com.juejin.ios.wuji`，SKU 同 bundle ID，主语言 `zh-Hans`，内容版权 `DOES_NOT_USE_THIRD_PARTY_CONTENT` |
| 团队 | `R6748V42K5`（绍兴天穹网络科技有限公司）；ASC 用户：1×Account Holder+Admin、1×Admin |
| iOS 版本 | **3.3.1（build 2）`PREPARE_FOR_SUBMISSION`，未提交审核**；在售 3.3.0（2022 年）；3.2.1 仍在售（旧设备兼容） |
| macOS 版本 | **0 个**（需 Add Platform） |
| 价格 | 手动价，基准 USA，**$8.99 USD**（proceeds $6.30） |
| 可用性 | 175 个国家/地区，`availableInNewTerritories=true` |
| App 信息 | 2 个 appInfo（在售 + 3.3.1 草稿）；主分类 **Utilities**；年龄 **4+**；11 种语言本地化 |
| App 隐私 | **API 不暴露**；项目记录为「不收集数据、不追踪」，需网页确认已 Publish |
| 出口合规 | 3.3.1 build 2：`usesNonExemptEncryption=false`；macOS Info.plist 也已写 `ITSAppUsesNonExemptEncryption=false` |
| 历史 IAP | 6 个旧非续期订阅（`APPROVED`）+ 1 个订阅组；本次不修改、不接入 |
| 工程（本机） | `project.yml` 已有 `Wuji-macOS` / `WujiTunnel-macOS`（macOS 26.0，bundle ID 与 iOS 相同，已链接含 macOS slice 的 `Frameworks/LibXray.xcframework`）；scheme `Wuji-macOS` 可用；尚未签名/真机验证 |

---

## 2. 添加 macOS 平台的准确步骤

> 依据：Apple 帮助「Add platforms」（英文 / 中文「添加平台」）：<https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/> · <https://developer.apple.com/cn/help/app-store-connect/create-an-app-record/add-platforms/>

### 2.1 前提与权限

- **职能要求**：Account Holder（账户持有人）、Admin（管理）或 App Manager（App 管理）。当前 App record 的用户里已有 Account Holder 和 Admin 各一，满足。
- **建议在网页端操作**：Add Platform 是 App Store Connect 网页动作；本机 API Key 只读核实过，**本次没有发起写请求**。
- **不需要**新建 App record / App ID；不要动 bundle ID、SKU、Team、主语言。
- 先在开发者门户确认该 App ID 已启用 **App Groups** 和 **Network Extensions**（Packet Tunnel Provider）capability（portal → Certificates, Identifiers & Profiles → Identifiers）。

### 2.2 网页操作步骤（中文界面）

1. 打开 <https://appstoreconnect.apple.com> → **Apps / App** → 选中「无极代理」（Apple ID `1448657437`）。
2. 左侧平台列表上方的 **「+ / Add Platform / 添加平台」**（Add Platform 按钮）→ 弹窗中勾选 **macOS** → **Add / 添加**。
3. 侧边栏会出现 macOS 平台版本，默认版本号 **1.0**；可在右侧 **App Information → Version** 区改成别的版本号。
4. 进入 macOS 版本页，逐项核对/补填版本级元数据（见 §3）；**描述、宣传文本、截图需要全新填写**。
5. 保存后，等待 Xcode 侧签好名的 **macOS build** 上传；上传处理完成后再把 build 关联到这个 macOS 版本。
6. 先不要提交审核；等真机测试（真实 Mac）和素材齐备、用户明确批准再走审核流程。

### 2.3 添加后需要重新填 / 确认的信息

| 类别 | 是否继承 | macOS 需要做什么 |
|---|---|---|
| App 信息（名称、副标题、主/次分类、年龄分级、Bundle ID、SKU、内容版权、隐私政策 URL、许可证协议） | **继承**（App 级，跨平台共享） | 核对即可；其中**隐私政策 URL 对 macOS 也是必需** |
| 版本级：关键词、支持 URL、营销 URL、版权、版本号、发布设置 | **继承** | 核对；版权当前为「绍兴天穹网络科技有限公司」 |
| 版本级：**宣传文本、描述、截图** | **不继承** | **必须为 macOS 重新填/上传** |
| App 预览 | 可选 | 需要就单独上传（Mac 规格见 §3.2） |
| App Review Information（联系人、备注、测试账号/节点） | 版本级单独填写 | 为 macOS 写 **Mac 专用审核备注 + 测试节点**；测试节点只放 ASC |
| 出口合规 / App 隐私 | App 级；按 build 属性/问卷 | 确认 `ITSAppUsesNonExemptEncryption=false` 与隐私问卷已发布 |
| 发布方式 | 新版本默认 `AFTER_APPROVAL` | 建议改为手动发布，避免审核通过即自动上线 |

### 2.4 版本号策略（建议 1.0）

Apple 明确允许 macOS 与 iOS 使用**不同版本号/构建号**（Add Platform 帮助）。两个方案：

| 方案 | 版本号 | 优点 | 缺点 |
|---|---|---|---|
| **A. 独立 1.0（推荐）** | macOS `1.0(1)` | 首个原生 Mac 版本，语义正确；首版不需要「本次新增」；与 iOS 3.3.1 的 build 组合不冲突；以后 Mac 独立演进 | Mac 与 iOS 商店显示版本不同（正常现象） |
| B. 与 iOS 对齐 | macOS `3.3.1(3 或更大)` | 宣传上「同版本」 | 给人「Mac 已有 3.3.1 历史版本」的错觉；build 不能用 2（与 iOS 3.3.1(2) 的「bundle ID+版本+build」组合冲突风险）；首版就要写「本次新增内容」 |

**推荐 A**。当前 `project.yml` 里 macOS 两个 target 都是 `3.3.1(2)`（App 与扩展的 build 号已按宿主一致处理，见工程注释）；改成 `1.0(1)` 属于代码/配置改动，需用户/Lead 拍板后另改（本文档未改工程）。

### 2.5 不可逆风险（必须让用户知道）

- **上传过 macOS build 后，Account Holder/Admin 也无法删除 macOS 平台**。删除平台的条件是：该平台**从未上传过 build**，且至少存在一个可编辑状态的平台版本。
- **至少两个平台版本通过审核后，App 自动成为 universal purchase**（当前 iOS 已通过 + macOS 通过即触发）；此后**不能撤销 universal purchase**，也**不能从 App 记录中移除单个平台版本**。
- **不同 app record 不能合并**；如果将来想拆成两个独立记录（独立定价），现有记录也无法合并。
- 所以：**第一次上传 macOS build 前，确认版本号、签名、截图、审核备注都已定稿；第一次提交审核前，确认用户明确同意。**

### 2.6 API 方式（仅记录，本次未执行）

Apple 帮助页在「添加平台」里链接了 App Store Connect API 的 *Create an App Store Version* 文档：即 `POST /v1/appStoreVersions` 带 `platform=MAC_OS`（以及 versionString 等）。理论上可以脚本化添加平台，但：

- 这是**写操作**，违反本次「只读」限制；
- 需要 API Key 具备足够角色（App Manager 及以上）；
- 建议等用户手动完成 Add Platform 后，再决定是否把后续「新建版本」脚本化。

---

## 3. macOS App Store 资产 / 元数据清单

> 依据：Apple 帮助「Screenshot specifications」「App preview specifications」「Add an app icon」「Platform version information」「App 信息」「Manage app privacy」「Overview of export compliance」。

### 3.1 截图（必需）

| 项 | 要求（Apple 官方，2026-11 抓取） |
|---|---|
| 数量 | 每个设备尺寸 **1–10 张**；Mac 至少 1 张 |
| 格式 | `.jpeg` / `.jpg` / `.png`，**不能有 alpha/透明** |
| Mac 尺寸 | **16:10**，四选一：`1280×800`、`1440×900`、`2560×1600`、`2880×1800` |
| 必填性 | 「Required for Mac apps」 |
| 内容 | 必须真实展示 App 使用状态；符合 App Review 2.3.3（截图要与 App 一致） |

**本项目的落地建议**：

- 先做 **zh-Hans 5 张**（与 iOS 商店图主题一致：首页/节点/分流/导入/订阅），尺寸用 **2560×1600**（16:10，足够清晰，Mac App Store 会自动缩小）。
- 其他 10 种语言可暂不单独做：缺失语言会用「下一优先语言」的截图展示（Apple 帮助），后续按需补。
- 截图里**不要出现任何真实服务器地址/节点凭据/二维码**（用演示数据/占位地址，参考 iOS 截图用 `-WujiBypassOnboarding` 等 DEBUG 钩子的做法）。
- 现有 `应用商店信息/` 里都是 iOS 尺寸（1320×2868 等）和 iPad 图，**不能用于 Mac**；需要新拍/新合成。

### 3.2 App 预览（可选）

- 最多 **3 个 / 设备尺寸 / 语言**；Mac **仅横屏**。
- 格式 `.mov`/`.m4v`/`.mp4`（H.264）；Mac 分辨率 **1920×1080（16:9）**，15–30 秒，≤500MB。
- 可选，首版建议不做。

### 3.3 App 图标

**要求（App Store Connect 帮助「Add an app icon」）**：图标在 Xcode 的 asset catalog 或 **Icon Composer** 中提供，随 build 上传；**不需要在 App Store Connect 单独上传 Mac 图标**。改图标必须发新版本。

**macOS 26（Liquid Glass）与设计规范**：

- HIG「App icons」：iOS/iPadOS/macOS 图标布局尺寸 **1024×1024**，系统做圆角遮罩；图标支持两种格式：**位图（PNG）**或 **Icon Composer 分层文件**。推荐 Icon Composer（可控 Liquid Glass 高光/折射/半透明，含 Default/Dark/Mono 外观）。
- Icon Composer 是 Xcode 自带工具（本机 `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`，要求 macOS 26.4+）。
- Xcode 文档「Configuring your app's icon」：iOS 可从单张 1024 自动生成；**macOS 需要每个尺寸单独提供**（除非用 Icon Composer 分层图标）。

**本项目现状**：

- `WujiMac/Assets.xcassets/AppIcon.appiconset` 已有 macOS 全尺寸 PNG（16/32/128/256/512 + @2x，1024 为 512@2x），`sips` 检查均无 alpha、正方形 → **可先用它上架**（不阻塞）。
- 建议（非阻塞）：用 Icon Composer 基于现有 1024 图标（`应用商店信息/APP图标-1024.png`）生成 `.icon`，获得 macOS 26 原生 Liquid Glass 外观；这是设计任务，可与上架并行。

### 3.4 名称 / 副标题 / 关键词 / 描述 / 宣传文本 / URL / 版权

- **名称、副标题、关键词、支持 URL、版权**：会从 iOS 版本继承（App 级或版本级）；核对即可。
- **描述、宣传文本**：必须为 macOS 单独写（不继承）。内容必须与 Mac 版实际功能一致（尤其：BYO 服务器、无节点提供、无账号、无内购、无广告、无追踪）。
- 版权：`绍兴天穹网络科技有限公司`（当前值）。
- 隐私政策 URL / 支持 URL：`https://www.54nb.com/privacy.html` / `https://www.54nb.com/support.html`（现有可用）。
- 字数限制：描述 ≤4000、关键词 ≤100 字节、宣传文本 ≤170 字符（Apple 帮助）。

### 3.5 分类

- App 级主分类当前是 **Utilities（工具）**；Info.plist `LSApplicationCategoryType=public.app-category.utilities` 一致。
- macOS 平台沿用 Utilities，无需改动；次分类可保持为空。

### 3.6 年龄分级

- 年龄分级是 **App 级、跨平台一致**（Apple 帮助明确「applied across all platforms」）。
- 当前 `appStoreAgeRating = FOUR_PLUS`，问卷内容描述全部为 NONE/false（无广告、无赌博、无成人内容等）。
- macOS 平台无需重新评级；提交 macOS 版本时沿用即可。

### 3.7 App 隐私

- 隐私回答是 **App 级、应覆盖所有平台**（Apple 帮助：「Responses are provided at the app level… across all platforms」）。
- 现有填写为 **「No, we do not collect data from this app」+ 不追踪**（项目记录）；`PrivacyInfo.xcprivacy` 也随 macOS 包一起打包（`project.yml` 已把 `Wuji/Resources/PrivacyInfo.xcprivacy` 加入 macOS target resources）。
- **API 不提供 App 隐私读取**（`/v1/apps/{id}/appPrivacyDetails` 等均 404），必须由用户/管理员在 ASC 网页确认状态是 **已发布（Publish）**；如果问卷里新增了 macOS 独有的数据类型，需要同步更新（当前 App 无收集，无变化）。
- 隐私政策 URL 对 macOS 是必需项，已继承。

### 3.8 出口合规

- 当前 iOS build 属性 `usesNonExemptEncryption=false`；macOS Info.plist 已写 `ITSAppUsesNonExemptEncryption=false`。
- 含义：App 使用标准加密（TLS/HTTPS/VPN 场景）但属于豁免情形，**无需上传 App Encryption Documentation**；这样可跳过逐 build 的加密问卷（Apple 帮助「Determine and upload app encryption documentation」）。
- 仍以 ASC 上传后显示为准：如果 ASC 仍要求回答，选择「不使用非豁免加密/豁免」；VPN/TLS 属于标准加密，不是自研算法。
- 注意：**不要**在 macOS Info.plist 里加 `ITSAppUsesNonExemptEncryption=true`；也不要删这个键。

### 3.9 审核备注（macOS 版模板）

> 规则：**测试节点/订阅 URL/账号只写在 App Store Connect 的 Review Notes 字段**，绝不写进仓库、文档、截图、App 内。
> 现有 iOS 3.3.1 审核备注里已有一个测试节点——**不要复制进任何文件**，macOS 版本重新写。

模板（占位符替换，中文或英文均可，英文更稳妥）：

```text
WProxy (无极代理) is a BYO-server (bring-your-own-server) proxy client.
The developer does not provide proxy nodes, accounts, in-app purchases, ads, or tracking.
The app has no sign-in; users add their own server by manual form, link, QR code, or subscription.

WHY NETWORK EXTENSION:
The macOS app uses a NetworkExtension packet-tunnel app extension to route the user's
traffic to the proxy server that the user configured. The extension is required for VPN
functionality. The macOS build is packaged as an app extension (App Store requirement);
it is not a system extension.

HOW TO TEST ON macOS:
1. Launch WProxy, complete onboarding and the consent screen.
2. Approve the system prompt allowing WProxy to add VPN configurations.
3. Add the test node below (or paste its share link).
4. Tap Connect, wait for "Connected".
5. Open a browser and verify the proxy works; then disconnect.

TEST NODE (valid during review):
<PUT TEST NODE / SUBSCRIPTION URL HERE ONLY IN APP STORE CONNECT>

Notes:
- The app works without any developer account; all data stays on the device.
- macOS version is 1.0, first release of the macOS platform (universal purchase with iOS).
- Nothing is collected or tracked; App Privacy answer is "No data collected".
```

补充建议：

- 若 Mac 版首启有「本地网络」相关声明（Info.plist 里有 `NSLocalNetworkUsageDescription` / `NSBonjourServices`，但 macOS 版代码只走 VPN 配置授权），审核如果问起，按实际行为说明。
- 兼容性说明里明确：**仅支持 macOS 26+**（真实限制，不是审核障碍）。
- 若审核问「为什么不能直接在 Mac 上用 iOS 版」：说明这是原生 macOS 版本，性能/体验/系统集成更好；iOS 版本仍独立存在。

### 3.10 价格、Universal Purchase 与现有 $8.99 用户

**事实（Apple 帮助 + ASC 只读核实）**：

- 价格是 **App 级**的（Pricing and Availability），不是按平台；当前手动价 **$8.99 USD**、基准美国。添加 macOS 平台**不会**产生独立的 Mac 价格。
- 同一 app record + 同一 bundle ID 添加 macOS 平台 → 只要 **至少两个平台版本通过审核**，App 自动成为 **universal purchase**：用户一次购买，可在 iOS/macOS 等多个平台下载，**含 App 内购买项目**。
- universal purchase 一旦生效**不能撤销**，也不能从 record 移除单个平台。

**对现有用户的影响**：

1. **已经花 $8.99 买过 iOS 版的用户**：macOS 版本通过审核并发布后，App Store 会把它视为已购买，**可免费下载 Mac 版**（在 macOS 26+ 的 Mac 上；这是 universal purchase 的定义）。
2. **尚未购买的用户**：在 Mac App Store 看到的价格也是 **$8.99**（与 iOS 同价）；不存在「Mac 版单独定价」。
3. **当前 iOS 版在 Apple silicon Mac 上以「Designed for iPad」形式可下载**：Apple 帮助明确——当 App 有 macOS 平台且成为 universal purchase 后，这个选项会消失；**macOS 版本发布后会替换 Mac App Store 上的 iOS 版，现有「iOS app on Mac」用户会被更新到 macOS 版**。无需（也不应）手动去关这个开关。
4. **购买共享 ≠ 数据共享**：Mac 版是独立设备上的本地数据（App Group 是本机容器），**不会自动同步 iOS 的节点/订阅/设置**；用户需在 Mac 上重新添加或导入。这是产品预期，写进发布说明/客服口径，避免用户误解。
5. **历史 IAP**：record 上仍有 6 个旧 IAP（APPROVED）。universal purchase 的定义包含 IAP，但当前 App 不接入 IAP。本次**不改 IAP**；是否下架旧 IAP 由用户决定（不属于本任务）。

### 3.11 可用性 / iPad-on-Mac / 中国区

- 可用性 175 地区、`availableInNewTerritories=true`；**App 级设置，macOS 继承**，Add Platform 不需要重选地区。
- iPad-on-Mac：见 §3.10 第 3 点，会自动被 macOS 版本替换；无需操作。
- 中国区：现有 iOS 版本已在中国大陆上架；macOS 平台继承可用性。**但 Mac App Store 中国区对带网络功能的应用也要求相应资质（ICP 备案等）**，本次不改可用性；发布前由用户确认现有资质覆盖 macOS 版本，避免中国区被下架/审核卡住（待用户确认）。

### 3.12 其他元数据注意

- **发布方式**：新版本默认 `AFTER_APPROVAL`（审核通过即发布）。建议 macOS 首版改为**手动发布**，留出上线前检查时间（版本级设置，随版本保存）。
- **iOS 3.3.1 草稿**：Add Platform 不会动它；**不要误提交 iOS 3.3.1**（两个平台版本独立提交）。另外 App 信息草稿（3.3.1 的 appInfo）与 macOS 平台共享，修改 App 级信息会同时影响 iOS/macOS。
- **审核备注/联系人**：macOS 版本是独立的 App Review Information，需重填（联系人可沿用，备注要重写）。

---

## 4. 构建与上传（摘要，命令见 `docs/macos-build-upload.md`）

| 步 | 做什么 | 关键命令/产物 |
|---|---|---|
| 1 | 重新生成工程 | `xcodegen generate` |
| 2 | 归档（universal，arm64+x86_64） | `xcodebuild archive -project Wuji.xcodeproj -scheme Wuji-macOS -configuration Release -destination 'generic/platform=macOS' -archivePath build/macos/Wuji-macOS.xcarchive -allowProvisioningUpdates` |
| 3 | 导出 Mac App Store 包 | `xcodebuild -exportArchive … -exportOptionsPlist tools/appstore/ExportOptions-macOS.plist`，`method=app-store-connect` → **`.pkg`**（不是 ipa） |
| 4 | 校验 | `pkgutil --check-signature`；`xcrun altool --validate-app -f Wuji.pkg -t macos --api-key … --api-issuer …` |
| 5 | 上传 | `xcrun altool --upload-package Wuji.pkg --api-key … --api-issuer … --wait`（或 Xcode Organizer / Transporter） |
| 6 | 关联 | App Store Connect → macOS 1.0 版本 → 选择该 build |
| 7 | 测试 | 真实 Mac（本机 macOS 26.7.1）安装 TestFlight/开发版，实测 VPN（模拟器不能测 NetworkExtension） |

版本/构建号：建议 macOS **1.0(1)**；若坚持 3.3.1，build 用 **≥3**（不要与 iOS 3.3.1(2) 相同）。扩展的版本字符串与 build 号都必须与宿主 App 一致（工程注释确认 App Store 校验会拒绝 build 不一致）。

---

## 5. 风险 / 阻塞清单

| # | 级别 | 风险/阻塞 | 影响 | 处置 |
|---|---|---|---|---|
| 1 | **已解除（待实测）** | `LibXray.xcframework` 缺 macOS slice | ~~macOS target 链接失败~~ | 已完成：`Frameworks/LibXray.xcframework` 含 `macos-arm64_x86_64`（arm64+x86_64），`project.yml` 已指向仓库内路径；剩：`xcodegen generate` + 实际 macOS archive 验证 |
| 2 | **阻塞** | 本机无 macOS provisioning profile；无 R6748V42K5 的 `Mac Installer Distribution` 证书 | 无法签名 archive / 无法导出 pkg | 用 Xcode 自动签名（登录 R6748V42K5 团队，Account Holder/Admin）自动建 **Mac App Store Connect** profile 和 Installer 证书；失败则门户手动创建 |
| 3 | **高** | Add Platform 后若上传 build，macOS 平台不可删除 | 无法回退平台 | 上传前确认版本/签名/素材定稿；先本机存档验证，再上传 |
| 4 | **高** | universal purchase 在 ≥2 个平台版本通过审核后自动生效且不可撤销 | 不能拆平台/独立定价 | 用户确认接受 $8.99 跨平台共享后再提交 macOS 审核 |
| 5 | **中** | 描述/宣传文本/截图不继承 | macOS 商店页空白或不全，无法提交 | 按 §3 单独准备（截图 16:10） |
| 6 | **中** | Mac App Store 只接受 **app extension** 形式的 NE provider（TN3134），system extension 只能非商店分发 | 如果误用 system extension 会被拒 | 保持 `WujiTunnel-macOS` 为 `app-extension` + `NSExtensionPointIdentifier=com.apple.networkextension.packet-tunnel`；不要改成 system extension |
| 7 | **中** | App Sandbox 要求 | 主 App/扩展缺 sandbox/网络权限会被审核或签名拒绝 | 已声明：`com.apple.security.app-sandbox`、`network.client`、app group；构建后用 `codesign -d --entitlements` 断言 |
| 8 | **中** | macOS App Group 标识格式 | 用错格式会导致容器为 nil / 扩展读不到文件 | 现状用 macOS 专用格式 `R6748V42K5.group.com.youqu.wuji.appgroup`（`$(TeamIdentifierPrefix)group.com…`，Apple 明确该格式无需门户注册）；iOS 继续 `group.com.youqu.wuji.appgroup`；真机验证容器共享 |
| 9 | **中** | 最低 macOS 26 | 旧 macOS 用户无法安装；对销量有影响 | 产品决策（已定 macOS 26+）；描述/兼容性写清楚；universal purchase 只对 macOS 26+ Mac 生效 |
| 10 | **中** | 历史 IAP 6 个仍 APPROVED | 商店页可能展示旧 IAP；universal purchase 覆盖 IAP | 不修改（硬规则）；由用户决定是否下架；不要接入 IAP |
| 11 | **中** | iOS 3.3.1 草稿与 macOS 版本并存 | 误提交 iOS 版本 / App 信息互相影响 | 提交前确认选中的平台版本；App 级信息改动需同时考虑两端 |
| 12 | **中** | 审核风险（代理/VPN/NE 权限） | 可能被问节点/测试账号/为什么需要 NE | 审核备注按 §3.9 写；测试节点只在 ASC；说明 BYO 服务器、无节点提供、无收集；真实可用节点覆盖至少一种协议 |
| 13 | **中** | 已知功能限制（IPv4-only、无 on-demand、无 per-App 统计） | 审核/用户预期 | 描述里不要承诺 IPv6/自动重连；Mac 版行为与 iOS 一致；写入发布说明 |
| 14 | **中** | 模拟器不能测 NE | 无法在 Xcode 模拟器验证 VPN | 必须真实 Mac（本机 macOS 26.7.1 可测）；测试项见 §8 |
| 15 | **低** | 导出 pkg / altool 上传路径未实测 | 首次可能踩签名/格式问题 | 按 `docs/macos-build-upload.md` §9 逐项验证；首次导出后检查 `pkgutil --check-signature` |
| 16 | **低** | Liquid Glass 图标未适配 | macOS 26 上图标可能不是最优外观 | 非阻塞；建议用 Icon Composer 迭代（`应用商店信息/APP图标-1024.png` 为基础） |
| 17 | **低** | `NSLocalNetworkUsageDescription` / Bonjour 声明在 macOS 版可能未实际使用 | 审核若问需解释 | macOS 版实际只请求 VPN 配置授权（代码已处理）；按实际行为解释，必要时后续版本清理 |
| 18 | **高（代码缺口）** | **macOS 沙箱文件访问 entitlement 缺失**：Mac 版「扫码 → 从文件导入图片」用的是 `fileImporter`（`PlatformCompat.wujiImageFileImporter`），「保存二维码到文件」用的是 `NSSavePanel`（`QRShareView.saveToFile`）；App Sandbox 下分别需要 `com.apple.security.files.user-selected.read-only` / `read-write`，但当前 `WujiMac/*.entitlements` 未声明 | 沙箱签名后这两个功能会失败（导入读不到文件/保存写不进去），Mac 版功能不完整，审核/用户都会碰到 | 属代码/配置任务（Lead/实现任务）：在两个 macOS entitlements 中补 `com.apple.security.files.user-selected.read-only`（至少）与 `read-write`（保存用）；或用 XcodeGen 的 `ENABLE_USER_SELECTED_FILES: readwrite` 生成；重新签名后真机验证导入/保存 |
| 19 | **低** | 所有 ASC 写操作/提交审核需用户执行或批准 | 越权风险 | 严格按 §7 清单，用户操作/授权后再做 |

---

## 6. 需要用户执行的操作清单

### A. App Store Connect 网页（用户本人或具 Account Holder/Admin 权限）

- [ ] 在 App record `1448657437` 上 **Add Platform → macOS**（本任务已给出步骤；API 未写）。
- [ ] 确认 macOS 版本号（建议 1.0）、发布方式（建议手动发布）。
- [ ] 核对 App 级信息：名称/副标题/分类/年龄分级/隐私政策 URL/版权。
- [ ] 为 macOS 补填：**描述、宣传文本、关键词（如需）、支持 URL、截图（至少 1 张，建议 5 张 2560×1600）**。
- [ ] 填写 macOS 版本的 **App Review Information**（联系人 + 备注 + 测试节点；测试节点只放这里）。
- [ ] 确认 **App 隐私** 状态为已发布（「不收集数据/不追踪」）。
- [ ] 确认出口合规（`usesNonExemptEncryption=false`；如 ASC 仍提问，按实际回答）。
- [ ] 确认中国区可用性/资质覆盖 macOS（如需要）。
- [ ] 决定历史 IAP 处理方式（保留 / 下架；本次不改）。
- [ ] **不要提交审核**，直到用户明确同意。

### B. 开发者门户 / 签名（Account Holder/Admin）

- [ ] 确认 App ID `com.juejin.ios.wuji` / `com.juejin.ios.wuji.tunnel-ext` 的 capabilities：**App Groups + Network Extensions (Packet Tunnel Provider)**。
- [ ] 允许 Xcode 自动签名生成 **Mac App Store Connect** 描述文件（首次 archive/export 时）。
- [ ] 若自动创建失败：手动创建 **Mac Installer Distribution** 证书 + **Mac App Store Connect** 描述文件（Account Holder/Admin 才能建分发证书）。
- [ ] 确认签名团队为 `R6748V42K5`（不是 C544N77LD9）。

### C. 本机 Xcode / 构建

- [ ] Xcode → Settings → Accounts 登录 R6748V42K5 团队（或提供可用的 ASC API Key 供 `-authenticationKey*`；只读 Key 已验证，写权限待确认）。
- [ ] 运行 `xcodegen generate` 并用仓库内 `Frameworks/LibXray.xcframework`（已含 macOS slice）验证 `Wuji-macOS` archive 真正链接通过。
- [ ] 代码侧补 macOS 沙箱文件 entitlement：`com.apple.security.files.user-selected.read-only`（QR 图片导入）与 `read-write`（保存二维码图片到文件）；当前缺失，沙箱下这两个功能会失败（属代码任务，见 §5 风险 18）。
- [ ] 首次 `archive`/`export` 时在弹窗/命令行确认自动签名。
- [ ] 执行并在真实 Mac 上安装验证（见 §8）。

### D. 素材 / 测试 / 决策

- [ ] macOS 截图：由用户确认设计风格后生成（或授权按现有 iOS 主题生成）；不得含真实节点信息。
- [ ] 图标：决定是否用 Icon Composer 做 Liquid Glass 版（非阻塞）。
- [ ] 提供审核可用的测试节点（协议/地址/端口/凭据或订阅 URL），**只放 ASC**，不要发到仓库/文档/聊天记录之外的地方。
- [ ] 真实 Mac 测试（本机 macOS 26.7.1）：安装→授权→连接→分流→DNS→语言→休眠唤醒。
- [ ] 决策：macOS 版本号 1.0 vs 3.3.1；是否保留旧 IAP；是否接受 universal purchase 不可逆。
- [ ] 最终批准：上传 build、提交审核。

---

## 7. 提交前检查清单

### 构建 / 签名

- [ ] `xcodegen generate` 成功，`Wuji-macOS` scheme 能构建。
- [ ] `Frameworks/LibXray.xcframework` 含 `macos-arm64_x86_64`，macOS target/扩展链接通过。
- [ ] Release archive 成功（universal：`ARCHS=arm64 x86_64`），`Contents/PlugIns/WujiTunnel.appex` 存在。
- [ ] `codesign -d --entitlements` 检查：app & appex 均 sandbox + app group（`R6748V42K5.group.com.youqu.wuji.appgroup`）+ `network.client`；appex 有 `packet-tunnel-provider`。
- [ ] Info.plist 的 `$(TeamIdentifierPrefix)` 已展开；`ITSAppUsesNonExemptEncryption=false`；`LSMinimumSystemVersion=26.0`。
- [ ] 扩展 `CFBundleShortVersionString` 与宿主一致；版本号/build 号按 §2.4 定稿（若 3.3.1，则 build ≥3）。
- [ ] 导出 `.pkg` 并由 `pkgutil --check-signature` 验证；`altool --validate-app` 通过。
- [ ] 上传成功，ASC 处理为 `VALID`，并已关联 macOS 版本。

### App Store 元数据（macOS 平台）

- [ ] 描述已写（BYO、无节点、无账号、无内购、无广告、无追踪；不夸大功能）。
- [ ] 宣传文本已写（≤170 字符，首版可空）。
- [ ] 至少 1 张（建议 5 张）**16:10、无 alpha** 截图，2560×1600 / 2880×1800 等。
- [ ] 关键词已核对（≤100 字节）。
- [ ] 支持 URL、隐私政策 URL 可访问；版权正确。
- [ ] 分类 Utilities、年龄分级 4+ 核对无误。
- [ ] App 隐私已发布（不收集/不追踪）；出口合规已确认。
- [ ] macOS 版本 App Review Information 已填：联系人、Mac 测试步骤、测试节点（只在 ASC）。
- [ ] 发布方式已设为手动（建议）；没有误改价格/主语言/Bundle ID/App Group/Team。
- [ ] 没有把测试节点/私钥/证书/服务器密码写进仓库或文档。

### 真实 Mac 功能测试（不可用模拟器替代）

- [ ] 首次启动：引导 → 数据/协议同意 → VPN 配置授权弹窗 → 主页。
- [ ] 添加节点：手动表单 / 粘贴链接 / 扫码 / 订阅导入；至少一种真实可用节点。
- [ ] 连接/断开；切换节点自动重连；退出 App 后 VPN 状态正确。
- [ ] 分流：全局 / 规则；选择国家/区域直连；局域网直连；DNS 两种模式。
- [ ] 语言切换（11 种）+ 重启保持；清空数据/重置 VPN 配置。
- [ ] 休眠/唤醒、Wi‑Fi 切换、网络变化后连接状态。
- [ ] App 与扩展共享 App Group 文件（active_tunnel/status/traffic/sqlite）读写正常。
- [ ] 沙箱下「扫码 → 从文件导入图片」可读取所选图片；「保存二维码到文件」可写入所选位置（需要 `files.user-selected` entitlement，见风险 18）。
- [ ] 无崩溃、无高 CPU/内存异常（扩展内存上限注意）。
- [ ] 截图/演示不包含真实节点或服务器信息。

### 发布

- [ ] 用户确认可以「上传 build → 提交审核」；**未提交审核前保持 `PREPARE_FOR_SUBMISSION`**。
- [ ] 不做 git commit/push（本任务约束）。

---

## 8. 可脚本化事项（后续实现建议）

> 原则：先只读、后写；写操作必须显式开关 + 用户批准；任何脚本都不得读取/打印 `.p8` 私钥内容。

| 脚本 | 作用 |
|---|---|
| `tools/appstore/asc_status.py` | 把 `macos-asc-status.md` 的只读查询固化为命令：app/versions/appInfos/pricing/availability/builds → 生成当前状态表；对 macOS 版本是否存在、价格、可用性做断言 |
| `tools/appstore/macos_build.sh` | `xcodegen generate` → archive（generic/platform=macOS）→ export（app-store-connect）→ 产 pkg；`--upload` 才上传 |
| `tools/appstore/ExportOptions-macOS.plist` | 固定 `method=app-store-connect` / `destination=export` / `teamID` / `manageAppVersionAndBuildNumber=false` |
| `tools/appstore/macos_verify.sh` | codesign entitlements 断言、Info.plist 展开检查、lipo 架构检查、pkg 签名检查、appex 嵌入检查 |
| `tools/appstore/macos_upload.sh` | `altool --validate-app` → `--upload-package`，日志脱敏 |
| `tools/appstore/macos_screenshots.py` | 截图校验（16:10、尺寸白名单、无 alpha、命名/顺序）→ 可选调用 ASC API 上传（`screenshotDisplayType=APP_DESKTOP`）；上传是写操作，默认 dry-run |
| `tools/check_macos_entitlements.py` | 在真实 Mac 上检查 App Group 容器路径与 app↔appex 共享文件可读写 |
| 版本号脚本 | 读写 `project.yml` 的 macOS `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（只改 `Wuji-macOS`/`WujiTunnel-macOS`），避免手改漏改 |
| 元数据备份脚本 | 只读拉取 iOS 版本 localizations/appInfo 到本地 JSON，作为 macOS 文案翻译/校对底稿（不写 ASC） |

> 备注：ASC API 里 Mac 截图的 `screenshotDisplayType` 是 **`APP_DESKTOP`**（已从 API 文档确认；当前 iOS 用的是 `APP_IPHONE_67`、`APP_IPAD_PRO_3GEN_129`）。

---

## 9. 参考链接（Apple 官方，均为 2026-11-22 抓取）

- 添加平台：<https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/> · 中文：<https://developer.apple.com/cn/help/app-store-connect/create-an-app-record/add-platforms/>
- 截图规格：<https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/>
- App 预览规格：<https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/>
- 添加 App 图标：<https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/>
- 平台版本信息：<https://developer.apple.com/help/app-store-connect/reference/platform-version-information/>
- App 与合规信息：<https://developer.apple.com/help/app-store-connect/reference/app-information/>
- 必需/可本地化/可编辑属性：<https://developer.apple.com/help/app-store-connect/reference/required-localizable-and-editable-properties/>
- 管理 App 隐私：<https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- 出口合规概览：<https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/>
- 上传构建版本：<https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- 年龄分级：<https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/>
- iPhone/iPad App 在 Apple silicon Mac 上的可用性（Mac 版替换 iOS 版）：<https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon/>
- 注册 App ID（单个 App ID 可用于 iOS/macOS 等）：<https://developer.apple.com/help/account/identifiers/register-an-app-id>
- 创建 App Store Connect 描述文件（含 Mac App Store Connect）：<https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile>
- 证书概览（Apple Distribution / Mac Installer Distribution）：<https://developer.apple.com/help/account/certificates/certificates-overview>
- TN3134 Network Extension provider deployment（macOS：app extension = App Store only；system extension 为非商店分发）：<https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment>
- Network Extensions entitlement：<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension>
- App Groups entitlement（macOS 可用 `<TeamID>.<group name>`，无需注册）：<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups>
- Xcode 配置 App 图标：<https://developer.apple.com/documentation/xcode/configuring-your-app-icon>
- HIG App icons：<https://developer.apple.com/design/human-interface-guidelines/app-icons>
- Icon Composer：<https://developer.apple.com/icon-composer/>
- 本地 `xcodebuild -help`（exportOptionsPlist 可用 key / method 列表）、`xcrun altool --help`（`--upload-package`、`--platform macos`）

---

*文档状态：初版，2026-11-22。ASC 现状、Apple 文档与工程配置可能变化；执行前请重新核实（尤其是签名、截图规格、版本号）。本任务只写 `docs/macos-*.md`，未改代码/工程/App Store Connect，未提交审核。*
