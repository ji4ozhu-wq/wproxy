# 代码审计报告（2026-11-20，只读审查）

> 口径：对照 CLAUDE.md / app-spec / discussion / impl-plan / ui-test-report + 全部 50 个 Swift 文件（约 11.3k 行）。
> 状态说明：部分条目已由 Lead 在 09:06–09:12 修复（见条目内「已修」标注）。用户决策：自动重连生效、连接中删当前节点自动断开、改用 MaxMind 数据库（7 天自动更新）、测速 URL 经代理测 HTTP 延迟。

## A. 阻断级

- **A1 主 App 缺 NetworkExtension entitlement**：`Wuji/Wuji.entitlements` 只有 app groups；扩展有 NE。NETunnelProviderManager.saveToPreferences 会失败，真机核心功能不可用。修法：主 App entitlements 加 `com.apple.developer.networking.networkextension=[packet-tunnel-provider]`。（需门户开能力后真机验证）
- **A2 按需连接开启后无法真正断开**：`TunnelController.stop()` 直接 stopVPNTunnel，没有先把 isOnDemandEnabled=false 存档，系统会立即重连。修法：stop 前 applyOnDemandRules(.off)+saveToPreferences，再 stopVPNTunnel。
- **A3 缺 PrivacyInfo.xcprivacy**：使用 System Boot Time API（DispatchTime.uptimeNanoseconds），提交可能被 ITMS-91053 拦。加 manifest：NSPrivacyAccessedAPICategorySystemBootTime 35F9.1；NSPrivacyCollectedDataTypes 空；NSPrivacyTracking=false。App 与扩展两个 bundle 都要。
- **A4 「清空全部数据」不停隧道、不重置系统 VPN 配置、无成功反馈**：只删表+文件；应 await resetVPNConfiguration() → deleteAllData() → toast；使用已有 AppDatabase.deleteAllData()。
- **A5 订阅刷新会把当前节点静默换成另一条节点**：refresh 用 rawURI 匹配恢复 active；手工表单节点 rawURI=""，会匹配第一条空 rawURI 节点 → 连错服务器。修法：rawURI 为空不参与匹配；用 server+port+protocol+凭据 映射旧 id→新 id。

## B. 重要

- B1 局域网开关形同虚设：NE 层无条件排除 RFC1918；应跟随 settings.bypassLAN（TunnelLaunchConfig 传参）。
- B2 连接中改分流/节点不即时生效、无提示：按用户决策改为自动重连。
- B3 测速 URL 死设置：按用户决策实现「连接时经代理 HTTP 测速」。
- B4 连接中 TCP 测速语义（服务器 IP 已排除，基本直连；域名节点可能进隧道）——实现 HTTP 测速时一并处理。
- B5 接受 http:// 订阅但 ATS 会拦：校验时拒绝 http 并给可读提示。
- B6 连接键 busy 时点击执行断开、快速双击可并发 connect：busy 禁用按钮 + isConnecting 守卫。
- B7 删除当前节点/订阅/清空数据时不停隧道：按用户决策删除当前节点自动断开；订阅删除同样处理。
- B8 自动更新失败每次前台重试同一订阅且无并发去重：失败也写 lastUpdatedAt（recordFailure），加 refreshing 集合。
- B9 导入无重复检测、部分失败静默：按 server/port/protocol+凭据查重；汇总「N 条已存在 / M 条无法解析」。
- B10 错误文案大量硬编码英文（TunnelError/XrayBuildError/URIParseError/DatabaseError/stopReason、订阅页 "ms"）：内层 detail 保留，UI 映射 L10n。
- B11 隐私文案与实际不符：日志 `.public` 输出服务器地址；DNS 固定 1.1.1.1 DoH 属第三方数据流未披露；隐私政策需同步。
- B12 TLS/REALITY serverName 兜底用 server 而非 ws/xhttp Host：sni 为空时回落 wsHost → server。
- B13 订阅更新入口缺失：订阅列表卡片/节点分组头加刷新按钮。
- B14 大字号/小屏截断：引导页不可滚动、首连弹窗固定 340、确认弹窗固定 272 不可滚动；改 ScrollView/自适应高度。

## C. 细节

- C1 文档状态不一致（progress 旧占位、impl-plan 仍 DOING/TODO）。
- C2 未使用/重复：AppDatabase.deleteAllData、SubscriptionStore.dueForAutoUpdate/recordFailure/isDue、三份 privateCIDRs、TunnelLaunchConfig.onDemandEnabled 只写不读。
- C3 关于页两个「开源许可」入口重复；图标用字母 W 而非真实 AppIcon。
- C4 应用内协议页丢内容：`**Effective date:**` 行被跳过、正文 `**` 星号原样显示。
- C5 死文案（settings.clearData.success、consent.paragraph2）；数据声明页未提 VPN 权限。
- C6 节点行滑动按钮无 identifier（订阅有）→ 给 Delete/Edit/SetActive 加 id。
- C7 排序菜单 systemImage=""；中文 uppercased；HomeView 用 replacingOccurrences("%d") 代替 String(format:)。
- C8 iPad/宽屏切 tab 重建详情（状态丢失）。
- C9 active_tunnel.json 明文凭据且断开不删：加 file protection + 断开时删除。
- C10 订阅列表空态 Section 结构、minHeight 顶在 List。
- C11 SS plugin / VMess ALPN 静默丢弃：导入时给出「含不支持参数」警告。
- C12 project.yml 无 configs；build/design-refs/screenshots 体积大；CountryDirectory 编入扩展但数据不在扩展包（埋雷）。

## D. 4 条 XCUITest 失败判断

- D1 testScanPreviewCardCancelAndSave：测试问题（DEBUG 钩子复用已有节点 id，upsert 不新增）。
- D2 testNodesSwipeDeleteWithConfirmation：测试问题（helper 的 "Delete".firstMatch 同时命中滑动按钮与弹窗按钮；补 identifier 可修）。
- D3 testSubscriptionEditNameAndDelete：倾向测试/框架（保存路径无阻塞；编辑从详情进入，保存后回详情而非列表）。
- D4 testAddNodeVLESSSecurityAndRealityValidation：待定；可把 AddNodeFormView 的 @Environment(\.dismiss) 改成显式 onDismiss 闭包后单跑验证。

## E. 优先修复顺序（Lead 采用）

1) A1/A2/A4/B7/A5/G3/G4（生命周期与安全）→ 2) A3/B11（合规）→ 3) B1/B2/B12/B6/B5/B8/B9 → 4) B10/B13/B14/C*。

---

# 修复状态（2026-11-20 10:40 复核）

## A 阻断级
- **A1 已修（代码）**：主 App `Wuji.entitlements` 增加 `com.apple.developer.networking.networkextension=[packet-tunnel-provider]`。**仍待**开发者门户为主 App/扩展 App ID 开能力 + 真机验证。
- **A2 已修**：`TunnelController.stop()` 先 `applyOnDemandRules(.off)` + `saveToPreferences` + reload 再 `stopVPNTunnel`；`updateOnDemandMode` 同步 reload。
- **A3 已修**：新增 `PrivacyInfo.xcprivacy`（`NSPrivacyAccessedAPICategorySystemBootTime` 35F9.1，Tracking=false，CollectedDataTypes 空），通过 project.yml `buildPhase: resources` 分别打进 App 与 WujiTunnel.appex 两个 bundle（Release 产物已核实）。
- **A4 已修**：清空数据 = 二次确认 → `resetVPNConfiguration()` → 事务 `deleteAllData()` → success toast → 回引导态；VPN 重置失败不清库。
- **A5 已修**：订阅刷新恢复 active 改为 proto+server+port+凭据映射；rawURI 不参与；匹配不到清空。

## B 重要
- B1 已修：`TunnelLaunchConfig.bypassLAN` 传给扩展，NE 排除路由跟随开关（server IP/DNS 始终排除）。
- B2 已修：连接中改分流/节点自动重连（0.5s 防抖 + 代次取消）。
- B3 已修：测速 URL 接入 `LatencyTester.testHTTP`（经隧道测 HTTP 延迟）；`AppState.testLatencyResult` 统一规则（当前节点 HTTP、其他节点 TCP、失败回落 TCP）。
- B4 部分：HTTP 测速专门用于已连接当前节点；未连接节点仍是 TCP（语义在 UI/文档中说明）。
- B5 已修：非 loopback 的 http 订阅直接拒绝并本地化提示（loopback 保留给 UI 测试 fixture）。
- B6 已修：`ConnectionButton` busy 禁用 + `HomeView` 忙时不转断线 + `isAutoReconnecting` 守卫。
- B7 已修：删当前节点先断开；删订阅/组调用 `prepareForRemoval(ofGroup:)` 先断开。
- B8 已修：失败走 `SubscriptionStore.recordFailure`（写 lastUpdatedAt）+ AppState/服务层双层 in-flight 去重。
- B9 已修：导入按 proto+server+port+凭据去重、重复行禁用；结果 toast 汇总「导入/跳过/无法解析」，失败列表可展开；不支持参数警告。
- B10 大部分已修：TunnelError/XrayBuildError/URIParseError 用户可见文案本地化；订阅毫秒单位本地化。扩展 stopReason 仍为英文 detail（仅日志/状态文件，不直接展示）。
- B11 已修：日志 `privacy:.private`（App 与扩展）；DNS DoH（Cloudflare 1.1.1.1）与 GeoIP 数据下载在 App 内隐私政策、商店隐私政策、提交信息中披露；署名改为 DB-IP/v2fly（真实来源）。
- B12 已修：TLS/REALITY serverName 兜底 sni → wsHost/xhttp host → server；新增 3 条 EngineTests。
- B13 已修：订阅列表卡片 + 节点分组头新增更新按钮（spinner/错误提示）。
- B14 已修：引导页可滚动、首连 sheet 自适应 detent+ScrollView、确认弹窗 ScrollView+自适应。

## C 细节
- C1 已修：spec/discussion/progress/impl-plan/交付摘要与审计报告已同步第二轮架构与结果。
- C2 部分：删除 `AppDatabase.deleteAllData` 重复实现、清理 AppState.privateCIDRs、`TunnelLaunchConfig.onDemandEnabled` 仍只写不读（保留给扩展容错）；SubscriptionStore.dueForAutoUpdate/isDue 仍为未调用（低风险）。
- C3 已修：About 删除重复许可入口；使用真实 AppIcon（AppIconPreview image set）。
- C4 已修：`**bold**`/`**生效日期:**`/列表/ Operator/Contact preamble 正常渲染。
- C5 已修：consent 权限说明补 VPN/相机/相册；清空数据使用 success toast；删除死文案 key。
- C6 已修：节点行滑动按钮与延迟文本加 identifier；UI 测试 helper 仍用 "Delete" 文案，但可用新 id。
- C7 已修：排序未选中图标改 `circle`；中文不 uppercase；延迟统一 `String(format: L10n unit.ms)`。
- C8 未修（iPad 宽屏切 tab 重建详情）——记为已知交互缺口，优先级低于真机核心链路。
- C9 已修：`active_tunnel.json` 写盘 `.completeFileProtectionUntilFirstUserAuthentication`；显式断开/reset 时删除。
- C10 未修（订阅列表空态 Section 结构/高度，纯视觉小瑕）。
- C11 已修：导入时提示不支持参数（SS plugin/uot、VMess alpn/type、VLESS/Trojan alpn/headerType），不阻断。
- C12 部分：project.yml 无 configs（用默认 Release 优化）；未创建 git 仓库/.gitignore（按规则不擅自改）。

## D 已知 4 条 UI 测试
- D1 已修：扫码 DEBUG 钩子改为生成全新节点；`testScanPreviewCardCancelAndSave` 已通过。
- D2 已修测试：滑动按钮加 identifier；本轮回归重跑验证。
- D3/D4 本轮回归重跑验证（订阅编辑删除、VLESS REALITY 保存）。

## 验证口径
- Debug/Release（模拟器 + 设备架构）构建均通过；`WujiTests` 90/90。
- 真实 Xray 校验：9 份配置（含 GeoIP 资产单规则）通过 `testXray`；负向测试证明 `xray.location.asset` 生效。
- 定向 XCUITest 复跑：路由/关于/引导/首页 + 节点删除/扫码/订阅/设置清空/重置等（结果见 `/tmp/ui-regression2.log` 与交付摘要）。


---

# 第三轮新增需求（2026-11-20 10:20）与验证

- SOCKS5：手动表单/粘贴/扫码/分享、可选用户名密码、Xray socks outbound、DB `socks_username` 迁移；真实 Xray `testXray` 接受 socks5-auth / socks5-open 配置；112/112 单测含 SOCKS5 解析/编码/DB 回读。
- DNS 处理方式：分流页单选 远程 DoH（默认）/ 本地 DNS（223.5.5.5 / 119.29.29.29 直连，含直连路由规则）；真实 Xray 接受 dns-local 配置；分流页修改触发自动重连。
- 应用内语言：设置页语言区（跟随系统 / English / 简体中文），L10n 即时切换、RootView 重建、隐私政策/用户协议跟随、持久化（AppSettings JSON）；已知限制：InfoPlist 权限弹窗与桌面 App 名仍随系统语言。
- 持久化：所有设置项与节点新字段均持久化（AppSettings JSON 容错 decode + SQLite 迁移 + SettingsStore 重开测试）；用户明确要求「设置后下次启动保持并生效」已覆盖单测与模拟器冷启动验证。
