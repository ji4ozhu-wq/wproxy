# 生命周期与隧道一致性 — 交互标识与验证口径（lifecycle-fix / task-6）

> 归属：`lifecycle-fix`（task-6，审计 A1/A2/A4/A5/B1/B6/B7/B8/C7/C9 + 用户决策 G3/G4）。
> 本任务**没有新增 accessibilityIdentifier**：所有涉及控件沿用 `docs/ids-pagesA.md` /
> `docs/ids-pagesB.md` / `docs/ids.md` 已登记的标识，这里只记录它们在本任务后**改变的行为契约**
> 与验证路径，供交互覆盖与合并核对使用。
> 代码：`Wuji/Core/AppState.swift`、`Wuji/Core/Tunnel/TunnelController.swift`、
> `Wuji/Core/Models/AppGroup.swift`、`WujiTunnel/TunnelNetworkSettings.swift`、
> `Wuji/Wuji.entitlements`、`Wuji/Features/Settings/SettingsView.swift`、
> `Wuji/DesignSystem/Components.swift`、`Wuji/Features/Home/HomeView.swift`。

## 1. 首页连接（B6 / A2 / G3）

| 标识 | 归属文件 | 本任务后的行为 |
|---|---|---|
| `wuji.home.connectButton` | ids.md（Lead） | `connecting` / `disconnecting` 时 `disabled`（B6）：点按不再触发任何动作；`connected` 点按 = 主动断开（先关按需规则再 stop，A2）；`disconnected` / `error` 点按 = 连接（首次连接仍先弹说明）。 |
| `wuji.home.statusTitle` | ids.md（Lead） | 自动重连期间显示 `Connecting…` → `Connected`（复用现有状态文案，无新增字符串）。 |
| `wuji.home.statusSubtitle` | ids.md（Lead） | 延迟文案改为 `String(format: unit.ms)`（C7）；自动重连后节点名随 `settings.activeProfileID` 更新。 |
| `wuji.home.currentNodeRow` | ids.md（Lead） | 仍进入节点列表；连接中切换节点 → 0.5s 防抖后自动重连（G3）。 |
| `wuji.home.routingRow` | ids.md（Lead） | 进入分流设置；连接中改分流 → 自动重连（G3）。 |

**自动重连（G3）**：`AppState` 保存上一次连接使用的设置快照
`TunnelSetup(activeProfileID, routingMode, bypassLAN, bypassCountryCodes)`。
`setActive` / `saveSettings` 在 `tunnelState == .connected` 且快照不一致时，经 0.5s 防抖
调用 `disconnect + connect`；失败沿用现有错误横幅（`ErrorBanner`，`wuji.home` 错误态）。
订阅刷新把 active 节点映射到新 id 时**不**触发重连（同服务器同凭据，写入快照）。

## 2. 删除节点 / 删除订阅（B7 / G4）

| 标识 | 归属文件 | 本任务后的行为 |
|---|---|---|
| `wuji.nodes.row.<profileID>` | ids-pagesA | 点按 = 设为当前节点（连接中 → 自动重连）。 |
| `wuji.nodes.actions.setActive` | ids-pagesA | 同上（经 `AppState.setActive`）。 |
| `wuji.nodes.actions.delete` / 列表左滑删除 | ids-pagesA | 二次确认后调 `AppState.deleteProfile`：**被删节点是当前节点且隧道未断开时先断开、再删除**；删除在后台完成，列表在 `reload()` 后刷新（无 UI 卡顿）。 |
| `wuji.subscriptions.swipeDelete.<id>` / 详情页删除 | ids-pagesB | 订阅代码删除前调用 `AppState.prepareForRemoval(ofGroup:)`（或对 active 节点 `prepareForRemoval(of:)`）：active 节点属于该订阅组时先断开。**调用点由 Lead 接线**，本任务只提供 AppState API。 |

非当前节点删除、或隧道已断开时删除：行为与之前一致（立即删除，若删的是 active 则清空选择）。

## 3. 设置页清空数据 / 重置 VPN（A4 / C9）

| 标识 | 归属文件 | 本任务后的行为 |
|---|---|---|
| `wuji.settings.clearData` | ids-pagesB | 弹自定义二次确认（`wuji.confirmation.title/confirm/cancel`）→ `await AppState.resetVPNConfiguration()`（停隧道 + 移除系统 VPN 配置 + 删除 App Group 文件）→ `AppDatabase.deleteAllData()` 事务清库 → 显示 `settings.clearData.success` toast（`wuji.toast`，900ms）→ `settings` 回到默认值，RootView 切回引导态。**VPN 配置重置失败时不销毁数据**，错误 toast 显示失败原因。 |
| `wuji.settings.resetVPN` | ids-pagesB | 仍走 `resetVPNConfiguration()`：移除系统配置、清理 `active_tunnel.json` / 状态文件，并取消排队中的自动重连。 |
| `wuji.confirmation.confirm` / `wuji.confirmation.cancel` | ids-pagesB | 清空数据确认执行上面的完整流程；取消不做任何修改。 |
| `wuji.toast` | ids-pagesB | 清空数据成功 = `All data cleared` / `数据已清空`（已有 key，无新增）。 |

当前节点被删除后 `active_tunnel.json` 已在断开时删除（C9），清空数据再兜底删一次。

## 4. 分流设置（B1 / G3）

| 标识 | 归属文件 | 本任务后的行为 |
|---|---|---|
| `wuji.routing.modePicker` | ids-pagesB | 保存后：连接中 → 自动重连（G3）；局域网开关同时影响 NE 路由（B1）。 |
| `wuji.routing.bypassLanToggle` | ids-pagesB | 真生效：开 → NE 排除 RFC1918 + IPv6 ULA（局域网直连）；关 → LAN 目标进入隧道走 Xray 路由（B1）。代理服务器 IP 始终排除，防回环；tunnel 子网/DNS 地址不受影响。 |
| `wuji.routing.regionsRow` / `wuji.routing.region.<code>` | ids-pagesB | 国家多选 Done 保存一次 → 0.5s 防抖后单次自动重连（避免每选一个国家重连一次）。 |

注：`routing.reconnectFootnote` 现文案为“下次连接生效”，与自动重连行为不完全一致；
该字符串在 `Resources/Routing.strings`（非本任务写权限），已在汇报中提请 pagesB/Lead 处理。
本任务未改该文案。

## 5. 安全与存储（A1 / A5 / B8 / C9）

- **A1**：`Wuji/Wuji.entitlements` 增加
  `com.apple.developer.networking.networkextension = [packet-tunnel-provider]`；
  需 Apple Developer Portal 为 `com.juejin.ios.wuji` 开启能力后**真机**验证
  `NETunnelProviderManager.saveToPreferences`（模拟器无法验证）。
- **A5**：订阅刷新恢复当前节点改为 `proto + server + port + 凭据`（VMess/VLESS → uuid，
  Trojan/SS → password，server/uuid 忽略大小写）匹配；无 rawURI 参与；匹配不到清空 active。
- **B8**：`refresh` 失败写 `SubscriptionStore.recordFailure(subscription, error:)`
  （lastError + lastUpdatedAt，避免前台每次激活重试同一订阅）；`AppState` 增加
  `refreshingSubscriptionIDs`，与 `SubscriptionFetchGate` 双层去重；并发刷新抛
  `SubscriptionError.refreshInProgress`（已有文案 `error.subscription.inFlight`）。
- **C9**：`active_tunnel.json` 写盘带
  `.completeFileProtectionUntilFirstUserAuthentication`；显式断开（`TunnelController.stop()`）
  与重置（`resetConfiguration()`）时删除；只有隧道启动读取它，删除时机安全。

## 6. 验证路径

### 模拟器可验证（本任务已跑）
1. 编译：`xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug -destination 'platform=iOS Simulator,id=7EFFAD4E-84B0-4786-8B4D-87B70D6BC452' -derivedDataPath /tmp/wuji-dd-life build`。
2. 单测：`-only-testing:WujiTests test`（09:26 终轮 58/58 全绿；09:23 基线 55/55；改动均为
   主 App 生命周期代码，测试 target 未变）。
3. UI 行为（`-WujiBypassOnboarding`、`-WujiConnectedState`、`-WujiDemoSession` DEBUG 钩子）：
   - 连接键在 `connecting/disconnecting` 时不可点（可读 `disabled` 状态；模拟器无真实 NE，
     用 DEBUG 状态钩子核对按钮/状态文案）。
   - 清空数据：二次确认 → toast → 引导页；数据清空后节点/订阅/设置回到默认。
   - 中文环境：首页 “THIS SESSION” 区块头不再被 `uppercased()` 处理（`SectionHeader`）。
4. 单测/逻辑核验（无模拟器 NE 依赖）：A5 匹配函数、G3 快照比较、B8 失败记录均为纯主线程
   逻辑，可在 Xcode 断点/日志确认；`active_tunnel.json` 的文件保护属性需真机验证。

### 需真机验证（本任务未声称已验证）
1. 主 App NE entitlement 生效后 `saveToPreferences` 成功（A1）。
2. 按需连接（总是 / 仅 Wi-Fi / 仅蜂窝）连接后，从 App 内断开能真正断开且不被系统立刻重连（A2）。
3. 局域网开关：开 → 局域网设备直连；关 → 局域网目标走代理（B1，配合分流规则观察）。
4. 连接中切换节点/改分流 → 自动重连成功且流量统计重新开始（G3）。
5. 连接中删除当前节点 / 删除当前订阅 → 先断开再删除（B7/G4）。
6. 锁屏后扩展仍能读到 `active_tunnel.json`（`untilFirstUserAuthentication` 语义），
   断开后文件已删除（C9）。
