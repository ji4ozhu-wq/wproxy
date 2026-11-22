# macOS 构建 / 签名 / 上传（本机可行命令与待实测项）

> 目标：把现有工程打成 **Mac App Store** 可上传的 `.pkg`，上传到 App Store Connect 的 `1448657437` 记录（macOS 平台）。
> 本文命令按 **2026-11-22 本机实测环境** 编写；标注「需实测」的步骤尚未实际执行（未生成签名、未上传、未提交审核）。
>
> 相关文档：[`docs/macos-appstore-checklist.md`](macos-appstore-checklist.md)（上架清单）、[`docs/macos-asc-status.md`](macos-asc-status.md)（ASC 现状核实）。

---

## 1. 本机环境（已核实）

| 项 | 值 | 核实方式 |
|---|---|---|
| macOS | 26.7.1（build 25G241） | `sw_vers` |
| Xcode | 27.2（build 27B52） | `xcodebuild -version` |
| macOS SDK | 27.2（`MacOSX27.2.sdk`） | `xcodebuild -showsdks` / `-showBuildSettings` |
| XcodeGen | 2.46.0（`/opt/homebrew/bin/xcodegen`） | `xcodegen --version` |
| `altool` | 27.10.4（Xcode 自带，`ContentDelivery.framework`） | `xcrun altool --version` |
| `notarytool` | 1.1.4（**不适用于 App Store 上架**，只用于 Developer ID 公证） | `xcrun notarytool --version` |
| Transporter.app | **未安装**（可从 Mac App Store 装） | `/Applications` 无该 App |
| Icon Composer | 已随 Xcode 安装（`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`，要求 macOS 26.4+） | 本机路径 |

---

## 2. 当前工程里与 macOS 有关的状态（已核实）

> 工程以 `project.yml` 为源；改完必须 `xcodegen generate`。**本文档不改工程**，以下只做记录。

| target / scheme | 类型 | bundle ID | deployment target | 版本（当前） |
|---|---|---|---|---|
| `Wuji` | iOS app | `com.juejin.ios.wuji` | iOS 17.0 | 3.3.1(2) |
| `WujiTunnel` | iOS app-extension | `com.juejin.ios.wuji.tunnel-ext` | iOS 17.0 | 3.3.1(1) |
| **`Wuji-macOS`** | macOS app | `com.juejin.ios.wuji` | **macOS 26.0** | 3.3.1(2) |
| **`WujiTunnel-macOS`** | macOS app-extension | `com.juejin.ios.wuji.tunnel-ext` | **macOS 26.0** | 3.3.1(2)（与宿主 app 一致） |
| `WujiTests-macOS` | macOS 单测 | `com.juejin.ios.wuji.tests` | 26.0 | — |
| scheme `Wuji-macOS` | 构建/测试入口 | — | — | — |

其他已核实事实：

- `xcodebuild -list` 已包含 `Wuji-macOS` / `WujiTunnel-macOS`；`Wuji-macOS` scheme 可被 `xcodebuild` 直接使用。
- `-showBuildSettings -destination 'generic/platform=macOS'`：`ARCHS = arm64 x86_64`、`ONLY_ACTIVE_ARCH = NO`（**归档默认 universal**，覆盖 Apple silicon + Intel Mac）。
- `-showBuildSettings -destination 'platform=macOS'`：本机本地运行只编 `arm64`。
- macOS Info.plist：`WujiMac/Info-Wuji-macOS.plist`（含 `LSMinimumSystemVersion=$(MACOSX_DEPLOYMENT_TARGET)`、`ITSAppUsesNonExemptEncryption=false`、`LSApplicationCategoryType=public.app-category.utilities`、`WujiAppGroupIdentifier=$(TeamIdentifierPrefix)group.com.youqu.wuji.appgroup`）。
- macOS 扩展 Info.plist：`WujiMac/Info-WujiTunnel-macOS.plist`（`NSExtensionPointIdentifier=com.apple.networkextension.packet-tunnel`、`NSExtensionPrincipalClass=$(PRODUCT_MODULE_NAME).PacketTunnelProvider`）。
- entitlements：`WujiMac/Wuji-macOS.entitlements`、`WujiMac/WujiTunnel-macOS.entitlements`，两者均含
  `com.apple.developer.networking.networkextension = [packet-tunnel-provider]`、`com.apple.security.app-sandbox = true`、
  `com.apple.security.application-groups = [$(TeamIdentifierPrefix)group.com.youqu.wuji.appgroup]`、`com.apple.security.network.client = true`。
- **已知 entitlement 缺口（代码侧需修）**：Mac 版「扫码 → 从文件导入图片」走 SwiftUI `fileImporter`，「保存二维码到文件」走 `NSSavePanel` + 写入；App Sandbox 下需要
  `com.apple.security.files.user-selected.read-only`（导入）与 `com.apple.security.files.user-selected.read-write`（保存），当前两个 macOS entitlements 都**没有**这两个键 → 沙箱签名后这两个功能会失败。属代码/配置任务（Lead/实现任务），本文档不改工程。
- 构建 setting：`CODE_SIGN_STYLE=Automatic`、`DEVELOPMENT_TEAM=R6748V42K5`、`ENABLE_HARDENED_RUNTIME=YES`；
  注意 `ENABLE_APP_SANDBOX=NO` 只是关闭 Xcode 自动生成 sandbox entitlement，真正的 sandbox 由上面的 entitlements 文件声明。
- **LibXray 依赖（已就绪）**：`Wuji-macOS` / `WujiTunnel-macOS` 已链接仓库内 `Frameworks/LibXray.xcframework`；该 xcframework 的 `Info.plist` 含 3 个 library：`ios-arm64`、`ios-arm64-simulator`、**`macos-arm64_x86_64`**（arm64 + x86_64），mac slice 路径为 `libXray.a`。仍需 `xcodegen generate` 后用实际 macOS archive 验证链接/运行时。

---

## 3. 签名 / 描述文件现状（已核实，属于阻塞项）

| 资产 | 现状 | 需要做什么 |
|---|---|---|
| 签名证书 | 钥匙串有 `Apple Distribution: Shaoxing Tianqiong Network Technology Co., Ltd. (R6748V42K5)`（可用） | 已有可用的 App 签名证书 |
| Mac Installer 证书 | **没有** `Mac Installer Distribution` / `3rd Party Mac Developer Installer`（属 R6748V42K5 的没有；`3rd Party Mac Developer Application` 是另一个团队 C544N77LD9，不可用于本 App） | 导出 `.pkg` 需要安装包签名证书；由 Xcode 自动签名创建，或门户手动创建 |
| macOS provisioning profile | **没有**（`~/Library/Developer/Xcode/UserData/Provisioning Profiles` 里 20 个全是 iOS） | 自动签名时由 Xcode 生成 **Mac App Store Connect** 描述文件 |
| 交互前提 | 需要 Xcode 登录 R6748V42K5 团队且角色足够（Account Holder/Admin），或给 `xcodebuild` 传 ASC 认证 key | 用户操作（见主清单「需要用户执行」） |

**建议做法（自动签名）**

```bash
# 首次归档/导出时允许 xcodebuild 访问开发者网站，自动创建 Mac App Store 描述文件和（如需）托管证书。
# 认证二选一：
#  A) 本机 Xcode → Settings → Accounts 已登录 R6748V42K5 团队（最简单）
#  B) 用 App Store Connect API Key（需该 Key 有足够权限；本机 Key 仅验证过只读）
xcodebuild ... -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8" \
  -authenticationKeyID "<KEY_ID>" \
  -authenticationKeyIssuerID "<ISSUER_ID>"
```

> `.p8` 路径不要写进仓库；KEY_ID / ISSUER_ID 可从 `tools/appstore/asc_api.py` 读出（私钥内容绝不入库/入文档）。
> 若自动签名无法创建 Installer 证书，让用户在 developer.apple.com → Certificates 手动创建 **Mac Installer Distribution** 证书并安装（Account Holder/Admin 才能创建分发证书）。

---

## 4. Archive（归档）

```bash
cd /Users/zhang/VC/app_src/wuji
xcodegen generate   # 改了 project.yml 之后必须；工程已生成时也建议先跑一次确认

xcodebuild archive \
  -project Wuji.xcodeproj \
  -scheme Wuji-macOS \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/macos/Wuji-macOS.xcarchive \
  -allowProvisioningUpdates
```

说明/待验证：

- `-destination 'generic/platform=macOS'` 得到 **universal（arm64 + x86_64）** archive；如只想出 Apple silicon，可加 `ARCHS=arm64`（不建议：Intel Mac 上 macOS 26 仍可安装，universal 覆盖面更大；libXray mac slice 也必须对应）。
- 也可用 `-destination 'platform=macOS,arch=arm64'`，但它用于本机运行更合适，**不建议**作为上架 archive。
- 归档前确认 `Frameworks/LibXray.xcframework` 含 `macos-arm64_x86_64`（已确认：`Info.plist` 3 个 library）；仍建议每次干净 archive 验证。
- 归档成功后检查 `build/macos/Wuji-macOS.xcarchive/Products/Applications/Wuji.app`，确认 `Contents/PlugIns/WujiTunnel.appex` 存在。

---

## 5. Export（导出 Mac App Store `.pkg`）

### 5.1 ExportOptions.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>

    <!-- export：只导出 pkg（本文推荐，随后用 altool 上传）
         upload：让 Xcode 直接上传（需要 Xcode 已登录团队账号；见 man xcodebuild） -->
    <key>destination</key>
    <string>export</string>

    <key>signingStyle</key>
    <string>automatic</string>

    <key>teamID</key>
    <string>R6748V42K5</string>

    <!-- 建议 false：构建号由 project.yml 明确控制，避免上传时被 Xcode 自动改号 -->
    <key>manageAppVersionAndBuildNumber</key>
    <false/>

    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

`xcodebuild -help` 中该 plist 的官方说明（本机 Xcode 27.2 实测输出）：

- `method` 可用值：`app-store-connect`、`release-testing`、`enterprise`、`debugging`、`developer-id`、`mac-application`、`validation`（旧值 `app-store`/`ad-hoc`/`development` 已弃用）。
- `destination`：`export` 或 `upload`。
- `installerSigningCertificate`：自动选择器可用 `Mac Installer Distribution`（macOS 包签名证书）。
- `signingCertificate`：自动选择器可用 `Apple Distribution`、`Mac App Distribution` 等。
- `manageAppVersionAndBuildNumber`：是否由 Xcode 管理 build 号（上传时可能自动+1）。

### 5.2 导出命令

```bash
xcodebuild -exportArchive \
  -archivePath build/macos/Wuji-macOS.xcarchive \
  -exportPath build/macos/export \
  -exportOptionsPlist tools/appstore/ExportOptions-macOS.plist \
  -allowProvisioningUpdates
```

预期产物：`build/macos/export/Wuji.pkg`（macOS App Store 安装包；`.app` 被封装为 pkg，**不是 ipa**）。

验证：

```bash
pkgutil --check-signature build/macos/export/Wuji.pkg
# 期望：签名方为 Mac Installer Distribution / Apple Distribution 相关证书（首次实测确认）
pkgutil --payload-files build/macos/export/Wuji.pkg | head
```

> 注意：`build/` 已被 `.gitignore` 忽略；pkg/xcarchive 不要入库。

---

## 6. Upload（上传到 App Store Connect）

三种方式，任选其一（**上传属于写操作，必须先得到用户批准**）：

### 6.1 altool（本机可用，推荐脚本化）

```bash
# 先校验（不会真正上传）
xcrun altool --validate-app -f build/macos/export/Wuji.pkg -t macos \
  --api-key "<KEY_ID>" --api-issuer "<ISSUER_ID>" \
  --output-format json --verbose

# 上传
xcrun altool --upload-package build/macos/export/Wuji.pkg \
  --api-key "<KEY_ID>" --api-issuer "<ISSUER_ID>" \
  --output-format json --wait
```

- 本机 `altool` 27.10.4 已实测支持 `--upload-package`（`.ipa` / `.pkg`）与 API Key；本仓库 API Key 已用 `--list-apps` 只读验证可用。
- `--validate-app`/`--upload-app -f` 也是等价入口（旧帮助把 `.pkg` 列为可上传类型）；`-t macos` 用于平台识别。
- 上传成功后 ASC 需要处理（几分钟到几十分钟），处理完状态才是 `VALID`。

### 6.2 Xcode Organizer（图形界面）

1. Xcode → Window → Organizer → Archives → 选中 `Wuji-macOS` archive。
2. Distribute App → **App Store Connect** → Upload。
3. 需要 Xcode 已登录 R6748V42K5 团队账号（命令行 `-destination upload` 也要求同样账号）。

### 6.3 Transporter.app

未安装；如安装，可拖入 `.pkg` 上传（App Store Connect 支持）。

> `xcrun notarytool` **不用于 App Store 上架**（只用于 Developer ID 公证），不要用；`stapler` 也不需要。

---

## 7. 版本号 / build 号规则与建议

Apple 规则（App 信息帮助文档）：

- **build 由「bundle ID + version + build string」唯一标识**；
- macOS / iOS 的版本号和 build 字符串**可以不同**（Add Platform 帮助明确允许）；
- 扩展的 `CFBundleShortVersionString` 必须与宿主 App 一致；build 号建议保持一致，避免校验噪音。

**建议方案（推荐）**

| 平台 | MARKETING_VERSION | CURRENT_PROJECT_VERSION | 理由 |
|---|---|---|---|
| iOS | 3.3.1 | 2 | 保持现状，勿动 |
| **macOS 首发** | **1.0** | **1** | macOS 是全新平台，1.0 语义正确；首版无需「本次新增内容」；避免暗示 Mac 已有 3.3.1 历史版本；也避免与 iOS 3.3.1(2) 的 build 组合冲突 |
| 之后 | 按 macOS 自身节奏递增（1.0 → 1.1 → …） | 每平台独立递增 | Apple 允许各平台版本/构建号不同 |

**备选方案**：macOS 也用 3.3.1，则 build 号**不要**用 2（与 iOS 3.3.1(2) 相同），建议用 **3** 或更大；但 Mac 商店首版显示 3.3.1 会让人误以为 Mac 版此前已存在，故仍推荐 1.0。

> **宿主与扩展 build 号必须一致**：工程 `project.yml` 注释（来自 macOS 构建验证）指出 App Store 校验会拒绝 macOS app extension 与宿主 build 号不一致；当前 macOS App/扩展都设为 3.3.1(2)。若改成 1.0(1)，两个 target 要一起改。
> 当前 `project.yml` 里 macOS target 仍是 3.3.1(2)；改成 1.0(1) 属于代码/配置改动，**需由用户/Lead 拍板后另行修改**（本文档只给建议，未改工程）。

---

## 8. 上传前/后验证命令

```bash
# 1) 检查签名与 entitlements（app 与 appex）
APP=build/macos/Wuji-macOS.xcarchive/Products/Applications/Wuji.app
codesign -dvvv "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p -
codesign -d --entitlements :- "$APP/Contents/PlugIns/WujiTunnel.appex" 2>/dev/null | plutil -p -

# 2) 检查 Info.plist 关键字段（确认 $(...) 已展开、App Group 标识正确）
plutil -p "$APP/Contents/Info.plist" | grep -E "CFBundle|LSMinimum|ITSApp|WujiAppGroupIdentifier"
plutil -p "$APP/Contents/PlugIns/WujiTunnel.appex/Contents/Info.plist" | grep -E "CFBundle|NSExtension"

# 2b) 补文件访问 entitlement 后确认已进签名（macOS 沙箱 QR 导入/保存依赖）
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - | grep -E "user-selected"

# 3) 检查架构（universal）
lipo -info "$APP/Contents/MacOS/Wuji"
lipo -info "$APP/Contents/Frameworks/LibXray.framework/LibXray" 2>/dev/null || true

# 4) 上传前校验 pkg
xcrun altool --validate-app -f build/macos/export/Wuji.pkg -t macos \
  --api-key "<KEY_ID>" --api-issuer "<ISSUER_ID>" --output-format json
```

期望：

- app 与 appex 都有 `com.apple.security.app-sandbox=true`、`com.apple.security.application-groups` 含 `R6748V42K5.group.com.youqu.wuji.appgroup`、`com.apple.security.network.client=true`；appex 另有 `com.apple.developer.networking.networkextension=["packet-tunnel-provider"]`。
- `WujiAppGroupIdentifier` 的 `$(TeamIdentifierPrefix)` 已展开为 `R6748V42K5.`（若仍含 `$(` 说明签名/团队未生效，需要排查）。
- 扩展版本字符串与宿主一致。

---

## 9. 待实测验证清单（按优先级）

| # | 待验证点 | 说明 |
|---|---|---|
| 1 | macOS archive 链接成功 | LibXray 已含 `macos-arm64_x86_64` 且 project.yml 已指向仓库路径；仍需实际 `xcodebuild archive` 验证（含 -lresolv / CoreFoundation / Security 链接） |
| 2 | 自动签名生成 Mac App Store 描述文件 | 首次 archive/export 时观察是否自动创建；失败则门户手动创建 |
| 3 | `Mac Installer Distribution` 证书 | 本机钥匙串目前没有；导出 pkg 时 Xcode 能否自动创建（需 Xcode 账号/许可证） |
| 4 | export 确实产出 `.pkg` 且签名正确 | 目前基于 Xcode 帮助推断；首次导出后跑 `pkgutil --check-signature` |
| 5 | `altool --upload-package` 上传 pkg 成功 | API Key 需要 App Manager 及以上；只用只读验证过，上传未执行 |
| 6 | universal archive（arm64+x86_64）可运行 | 若本机只有 Apple silicon，只能在 Intel 真机/虚拟机验证 x86_64（可接受先上线 arm64+Intel 由 CI/用户验证） |
| 7 | App Store 校验通过 | `--validate-app` 是否报 entitlement/profile/版本/图标问题 |
| 8 | pkg 上传后 ASC 处理为 `VALID` | 检查 App Store Connect → macOS 版本是否可关联 build |
| 9 | 真 Mac 上 VPN 连接 | 模拟器不能测 NetworkExtension；需 macOS 26 真机（本机 26.7.1 可以） |
| 10 | App Group 共享 | app ↔ appex 读写同一个 `~/Library/Group Containers/R6748V42K5.group.com.youqu.wuji.appgroup`（路径待实测） |
| 11 | 沙箱文件访问 | 补 `files.user-selected.read-only/read-write` 后，真机验证 QR 图片导入可读、保存二维码可写（见 §2 已知缺口） |

---

## 10. 可脚本化（后续实现建议）

建议新增（**本次不实现**，避免与其它任务冲突）：

1. `tools/appstore/macos_build.sh`：`xcodegen generate` → archive → export → 校验 → 输出 pkg 路径；支持 `--upload`（显式开关，默认只导出）。
2. `tools/appstore/ExportOptions-macOS.plist`：固定 `method=app-store-connect` / `destination=export` / `teamID=R6748V42K5` / `manageAppVersionAndBuildNumber=false`。
3. `tools/appstore/macos_verify.sh`：codesign entitlements 断言（sandbox/app group/NE/network client）、Info.plist 展开检查、lipo 架构检查、pkg 签名检查。
4. `tools/appstore/macos_upload.sh`：读取 `~/.appstoreconnect/private_keys/` 的 key，`altool --validate-app` → `--upload-package`；日志脱敏，不打印 p8 内容。
5. `tools/appstore/asc_status.py`：把 `docs/macos-asc-status.md` 的只读检查固化为脚本（输出表格 + 变更提醒）。
6. 版本号脚本：从 `project.yml` 读/写 macOS `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`（只改 macOS target），避免手改漏改。

> 所有脚本在实现前都要确认：不打印私钥/证书、不把测试节点写进仓库、上传动作必须显式参数触发。
