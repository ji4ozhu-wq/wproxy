# macOS 上架准备 · App Store Connect 现状核实（只读）

> 核实时间：**2026-11-22 03:44–03:53（Asia/Shanghai，UTC+8）**
> 核实方式：`tools/appstore/asc_api.py`（App Store Connect API，**全部为 GET**）+ `xcrun altool --list-apps`（只读）。
> 本文所有结论来自只读查询；**没有**发起任何写请求、没有提交审核、没有改价格/主语言/Bundle ID/App Group/Team。
> 密钥与签名材料：API Key 的 `.p8` 在仓库外 `~/.appstoreconnect/private_keys/`，本文不记录私钥内容，也不记录审核测试节点/联系人等敏感信息。

---

## 1. 结论摘要（供上架决策）

| # | 结论 | 影响 |
|---|---|---|
| 1 | App record `1448657437`（`com.juejin.ios.wuji`，`无极代理`，Team `R6748V42K5`）存在且可读；当前**只有 iOS 平台**，`MAC_OS` 版本数为 **0**。 | 需要通过 Add Platform 新建 macOS 版本，不能上传 macOS build 先占位（上传前无对应平台版本）。 |
| 2 | iOS 版本 **3.3.1（build 2）** 状态 `PREPARE_FOR_SUBMISSION`，未提交审核；在售版本 **3.3.0**（`READY_FOR_SALE`，2022 年），另有一个 `3.2.1` 仍为 `READY_FOR_SALE`（应为旧设备兼容版本）。 | 加 macOS 平台后会出现独立的 macOS 版本（初始 1.0），与 iOS 3.3.1 互不影响；**不要误提交 iOS 版本**。 |
| 3 | 价格：**手动价格**，基准地区 **USA**，单一手动价，API 返回 `customerPrice = 8.99 USD`、`proceeds = 6.30 USD`；自动价格为空。 | 价格是 **App 级**的，添加 macOS 平台不会产生独立 Mac 价格；Mac 同样按 $8.99 售卖。 |
| 4 | 可用性：`availableInNewTerritories = true`，`territoryAvailabilities` 共 **175** 个地区（首发日期 2019-02-22）。 | 可用性也是 App 级；macOS 平台继承现有地区设置，不需要重新选地区。 |
| 5 | App 信息（名称/副标题/分类/年龄分级/隐私政策 URL）是 **跨平台共享**的：主分类 `UTILITIES`，年龄分级 `FOUR_PLUS`；当前有 2 个 appInfo（在售 + 3.3.1 草稿）。 | 添加 macOS 平台无需重填 App 信息；版本级元数据才需要为 macOS 补填（见主清单）。 |
| 6 | App 隐私问卷 **ASC API 不提供**（候选端点全部 404）；当前项目记录为「不收集数据、不追踪」，需在网页端确认已 `Publish`。 | macOS 平台沿用同一份 App 级隐私回答；提交前必须网页核实，API 无法代替。 |
| 7 | 出口合规：已上传 build 2 的 `usesNonExemptEncryption = false`；macOS 的 `Info.plist` 也已写 `ITSAppUsesNonExemptEncryption = false`。 | macOS build 上传后可跳过加密问卷（仍以 ASC 显示为准）。 |
| 8 | Bundle ID：主 App `com.juejin.ios.wuji`（portal 侧 platform=`IOS`），扩展 `com.juejin.ios.wuji.tunnel-ext`（`UNIVERSAL`）。Apple 帮助明确「自 Xcode 11.4 起单个 App ID 可用于 iOS/macOS/tvOS/watchOS」。 | **不需要新建 App ID**；同一 App ID + 同一 bundle ID 即可作为 macOS 平台上传。 |
| 9 | app record 上仍挂着 **6 个历史 IAP**（非续期订阅，状态 `APPROVED`）和 **1 个订阅组**；当前 App 代码不接入 IAP。 | 本次硬规则禁止改 IAP；但 universal purchase 会覆盖 IAP，提交 macOS 前需用户知晓/决定是否处理（见主清单风险）。 |
| 10 | `altool`（Xcode 27.2 自带，27.10.4）可用仓库外 API Key 成功只读列出该 App；说明后续上传可用同一 Key 的 `--upload-package`（上传权限需 App Manager 及以上，待实测）。 | 上传路径可行；正式上传仍属写操作，需用户批准后执行。 |

---

## 2. 查询端点与返回状态

> 基础地址：`https://api.appstoreconnect.apple.com`；以下均通过 `asc_api.request("GET", path)` 调用，返回码为 HTTP 状态。

### 2.1 App / 版本 / App 信息

| 端点 | 状态 | 关键内容 |
|---|---|---|
| `/v1/apps/1448657437` | 200 | bundleId `com.juejin.ios.wuji`；name `无极代理`；sku `com.juejin.ios.wuji`；primaryLocale `zh-Hans`；contentRights `DOES_NOT_USE_THIRD_PARTY_CONTENT`；`streamlinedPurchasingEnabled=true` |
| `/v1/apps/1448657437/appStoreVersions?limit=50` | 200 | 18 个版本，全部 `IOS` |
| `/v1/apps/1448657437/appStoreVersions?filter[platform]=IOS` | 200 | 同上（18） |
| `/v1/apps/1448657437/appStoreVersions?filter[platform]=MAC_OS` | 200 | **0 个** |
| `/v1/apps/1448657437/appInfos?include=appInfoLocalizations,ageRatingDeclaration,primaryCategory,secondaryCategory` | 200 | 2 个 appInfo（在售 / 3.3.1 草稿）；主分类 `UTILITIES`；年龄 `FOUR_PLUS` |
| `/v1/appInfos/{inSaleId}/appInfoLocalizations` | 200 | 11 种语言（zh-Hans/en-US/zh-Hant/es-ES/fr-FR/de-DE/ja/ko/ru/th/vi），name/subtitle/privacyPolicyUrl 已填 |
| `/v1/appInfos/{draftId}/appInfoLocalizations` | 200 | 同上；为 3.3.1 草稿版本的信息 |
| `/v1/appInfos/{draftId}/ageRatingDeclaration` | 200 | 全部内容描述为 NONE / false（无广告、无赌博、无成人内容等） |
| `/v1/apps/1448657437/appStoreVersionExperimentsV2` | 200 | 无进行中实验（不影响） |

**版本状态（关键版本）**

| 平台 | 版本 | 状态 | 创建日期 | 说明 |
|---|---|---|---|---|
| IOS | 3.3.1 | `PREPARE_FOR_SUBMISSION` | 2026-11-20 | 已关联 build 2；**未提交审核** |
| IOS | 3.3.0 | `READY_FOR_SALE` | 2022-01-27 | 当前在售版本 |
| IOS | 3.2.1 | `READY_FOR_SALE` | 2020-04-20 | 旧设备兼容版本（Last-Compatible Version） |
| MAC_OS | — | — | — | 尚无任何 macOS 版本（需 Add Platform） |

`3.3.1` 版本已关联 build：`e18c4aa9-5e04-479e-814e-9e897e9d230f`（build `2`，`VALID`）。

### 2.2 价格 / 可用性

| 端点 | 状态 | 关键内容 |
|---|---|---|
| `/v1/apps/1448657437/appPriceSchedule` | 200 | 价格表 id `1448657437`；基准地区 **USA** |
| `/v1/appPriceSchedules/1448657437/baseTerritory` | 200 | `USA`，USD |
| `/v1/appPriceSchedules/1448657437/manualPrices?include=appPricePoint` | 200 | 1 条手动价格；包含 `appPricePoint.customerPrice = "8.99"`、`proceeds = "6.30"` |
| `/v1/appPriceSchedules/1448657437/automaticPrices` | 200 | 空（未使用自动价格） |
| `/v1/apps/1448657437/appPricePoints?filter[territory]=USA` | 200 | 价格点列表（分页）；用于人工核价，8.99 已由上面的 include 证实 |
| `/v1/apps/1448657437/appAvailabilityV2` | 200 | `availableInNewTerritories = true` |
| `/v2/appAvailabilities/1448657437/territoryAvailabilities` | 200 | 175 个地区全部 `available=true` |

> 注意：`/v1/apps/{id}/appAvailability`、`/v1/apps/{id}/availableTerritories` 等旧路径返回 **404**；正确路径是 `/v1/apps/{id}/appAvailabilityV2` 与 `/v2/appAvailabilities/{id}/territoryAvailabilities`。

### 2.3 Build / 出口合规

| 端点 | 状态 | 关键内容 |
|---|---|---|
| `/v1/apps/1448657437/builds?limit=20` | 200 | 共 20 个（含 2019–2020 老 build）；新 build：`2`（2026-11-20，`VALID`，`usesNonExemptEncryption=false`）、`1`（2026-11-20，`VALID`，false） |
| `/v1/appStoreVersions/{3.3.1}/build` | 200 | build `2`（`VALID`，未过期） |
| `/v1/appStoreVersions/{3.3.1}/appStoreVersionLocalizations` | 200 | 11 种语言，description/promotionalText/keywords/supportUrl/whatsNew 均已填 |
| `/v1/appStoreVersions/{3.3.1}/appStoreReviewDetail` | 200 | 已填联系人、电话、邮箱、审核备注（含测试节点；**本文档不转录**），`demoAccountRequired=false` |

### 2.4 App 隐私 / 加密文档 / 其他（API 不可用项）

| 端点 | 状态 | 说明 |
|---|---|---|
| `/v1/apps/1448657437/appPrivacyDetails` | 404 | API 未提供 App Privacy 资源 |
| `/v1/apps/1448657437/appDataUsages` | 404 | 同上 |
| `/v1/apps/1448657437/appEncryptionDeclarations` | 404 | App 级加密文档接口不存在；出口合规按 build 的 `usesNonExemptEncryption` 与 ASC 问卷处理 |
| `/v1/apps/1448657437/appReviewAttachments` | 404 | 审阅附件没有该集合端点 |
| `/ageRatingDeclarations?filter[app]=...` | 403 | 只允许 UPDATE；通过 `appInfos/{id}/ageRatingDeclaration` 只读获取 |

**结论**：App 隐私回答、App Encryption Documentation、审核附件等需要在 **网页 App Store Connect** 核实；API 只读核实的边界已记录，不能凭 API 断言这些项已发布。

### 2.5 团队 / 角色（只读）

- `/v1/users?limit=10` 返回 2 个用户：1 个 `ACCOUNT_HOLDER + ADMIN`，1 个 `ADMIN`。
- Add Platform 所需职能（Apple 帮助）：**Account Holder、Admin 或 App Manager**；网页操作需要其中之一的账号。
- 本机 `asc_api.py` 的 API Key 只读查询正常；`altool --list-apps --api-key ... --api-issuer ...` 也成功返回版本列表（含 3.3.1 `PREPARE_FOR_SUBMISSION`）。

### 2.6 历史 IAP / 订阅（只读，仅记录，不修改）

| 资源 | 状态 | 说明 |
|---|---|---|
| `/v1/apps/{id}/inAppPurchasesV2` | 200（6 个） | 全部 `APPROVED`、类型 `NON_RENEWING_SUBSCRIPTION`（历史代理套餐产品） |
| `/v1/apps/{id}/subscriptionGroups` | 200（1 个） | 组名「自动订阅」；未列出有效订阅 |

> 硬规则：**不修改** IAP、订阅、价格、可用性；这里仅作为「加 macOS 平台会共享 App 级资源」的风险提示。

---

## 3. 端口（bundle ID）核实：不需要新建 App ID

| 项 | 值/结论 |
|---|---|
| 主 App bundle ID | `com.juejin.ios.wuji`（ASC `bundleIds` 资源 platform 显示 `IOS`） |
| 扩展 bundle ID | `com.juejin.ios.wuji.tunnel-ext`（ASC platform 显示 `UNIVERSAL`） |
| App Group | `group.com.youqu.wuji.appgroup` |
| 关键依据 | Apple 帮助「Register an App ID」：*Beginning with Xcode 11.4, a single App ID can be used to build iOS, macOS, tvOS, and watchOS apps.* |

**含义**：macOS target 使用与 iOS 相同的 bundle ID（主 App + 扩展），无需在开发者网站注册新的 App ID；但 macOS 的 provisioning profile / 证书需要另行生成（见 `docs/macos-build-upload.md`）。

**待网页核实**：App ID 的 capabilities 是否已同时包含 App Groups + Network Extensions（Packet Tunnel Provider）；这些 capability 对多平台 App ID 生效，但首次 macOS 签名/描述文件生成时可能需要在门户确认。

---

## 4. 对「添加 macOS 平台」的具体影响（基于以上现状）

1. **iOS 3.3.1 草稿继续保留**：Add Platform 会新增 macOS 1.0 版本，不动 iOS 3.3.1；两个平台版本分别提交。
2. **价格/可用性/App 隐私/年龄分级/App 信息**：不用重填，都是 App 级共享；macOS 版本只需填版本级元数据（描述、宣传文本、截图、关键词、支持 URL、版权、审核信息）。
3. **描述/宣传文本/截图不会继承**：这是 Apple 帮助写明的例外；macOS 必须单独准备（截图规格见主清单）。
4. **审核备注**：现有 3.3.1 审核备注含测试节点；macOS 版本需要自己的 App Review Information，建议重写为「macOS 测试步骤 + 测试节点（只放 ASC）」，不要直接复制 iOS 备注。
5. **通用购买（Universal Purchase）**：macOS 版本与 iOS 版本在**同一 App record、同一 bundle ID**，且至少两个平台版本通过审核后，自动成为 universal purchase；此后 $8.99 已购用户可免费下载 Mac 版（详见主清单 §4.7）。
6. **旧 IAP**：仍挂在 App record 上，本次不改；若这些 IAP 仍可购买，universal purchase 的定义也覆盖 IAP（跨平台），但当前 App 不接入 IAP。

---

## 5. 复现方式（只读）

```bash
cd /Users/zhang/VC/app_src/wuji
python3 - <<'PY'
import sys
sys.path.insert(0, "tools/appstore")
import asc_api as api
for path in [
    "/apps/1448657437",
    "/apps/1448657437/appStoreVersions?filter[platform]=MAC_OS",
    "/apps/1448657437/appInfos?include=appInfoLocalizations,ageRatingDeclaration,primaryCategory",
    "/appPriceSchedules/1448657437/manualPrices?include=appPricePoint",
    "/apps/1448657437/appAvailabilityV2",
    "/v2/appAvailabilities/1448657437/territoryAvailabilities?limit=5",
    "/apps/1448657437/builds?limit=5",
]:
    status, body = api.request("GET", path)
    print(status, path)
PY
```

> 该脚本与上面的查询**只做 GET**。任何 `POST/PATCH/DELETE`（包括 Add Platform 的 API 方式）都属于写操作，必须由用户明确批准后另行执行。

---

*相关文档：[`docs/macos-appstore-checklist.md`](macos-appstore-checklist.md)（上架清单主文档）、[`docs/macos-build-upload.md`](macos-build-upload.md)（构建/签名/上传）。*
