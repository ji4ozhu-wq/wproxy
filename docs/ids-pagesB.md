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
| `wuji.subscriptions.update.<id>` | 卡片底部 Update 行 | 调用 `AppState.refresh` 拉取更新：更新中显示 spinner + 「更新中…」并禁用；成功 toast「Subscription updated」，失败 toast 显示原因（不离开列表） |
| `wuji.subscriptions.emptyState` | 空状态容器 | 主按钮打开添加订阅 |
| `wuji.subscriptions.list` 内 footer | “Auto-update runs while the app is open.” | 只读说明 |

## 添加 / 编辑订阅（AddSubscriptionView，自带 NavigationStack 的 sheet）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.subscriptions.add.cancel` | Cancel | 关闭表单（加载中禁用） |
| `wuji.subscriptions.add.save` | 右上 Save | 与底部主按钮同一提交逻辑 |
| `wuji.subscriptions.add.urlField` | 订阅地址输入框 | URL 键盘；仅接受 https://（非 loopback 的 http 直接给「仅支持 HTTPS 订阅地址」可读错误，不依赖 ATS） |
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
| `wuji.settings.onDemand` | On-Demand 行 | push 按需连接单选项 |
| `wuji.settings.resetVPN` | Reset VPN Configuration | 自定义二次确认 → `AppState.resetVPNConfiguration()`，成功/失败 toast |
| `wuji.settings.testURL` | 测速 URL 行 | push 编辑页 |
| `wuji.settings.timeout` | 超时时间行 | push 选项页 |
| `wuji.settings.autoUpdate` | 订阅自动更新开关 | 即时持久化 |
| `wuji.settings.subscriptions` | Subscriptions（计数）行 | push 订阅列表 |
| `wuji.settings.language.section` | 语言区容器 | — |
| `wuji.settings.language.option.system` | 跟随系统（默认） | 应用内语言=跟随设备语言，即时生效并持久化 |
| `wuji.settings.language.option.en` | English | 强制英文，即时生效并持久化 |
| `wuji.settings.language.option.zh-Hans` | 简体中文 | 强制简体中文，即时生效并持久化 |
| `wuji.settings.about` | About & Licenses | push 关于页 |
| `wuji.settings.contact` | Contact Support | 打开 `mailto:ji4ozhu@gmail.com` |
| `wuji.settings.terms` | Terms of Use | push 用户协议 |
| `wuji.settings.privacy` | Privacy Policy | push 隐私政策 |
| `wuji.settings.clearData` | Clear All Data（红） | 自定义二次确认 → 清 SQLite + App Group 配置，回首次启动状态 |

### 设置子页

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.settings.onDemand.option.off` / `.always` / `.wifi` / `.cellular` | 按需连接选项 | 即时持久化 |
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
| —（已移除） | ~~View all licenses~~ | 与上方 Open Source Licenses 重复的入口已删除（C3）；许可统一从 `wuji.settings.about.openSource` 进入 |
| `wuji.settings.licenses.xray-core` / `.libxray` / `.country-cidrs` | 许可 DisclosureGroup | 展开/收起完整许可文本 |

> About 顶部图标使用真实 AppIcon（`Assets.xcassets/AppIconPreview.imageset`，与 1024 AppIcon 母图一致），不再是字母 W 占位。

## 用户协议 / 隐私政策（LegalDocumentView）

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.settings.legal.scroll` | 文档滚动容器 | — |
| `wuji.settings.legal.email` | 联系邮箱链接 | 打开 mailto |
| `wuji.settings.legal.error` | 文档加载失败状态 | 提供 “Try Again” 重试 |

> 渲染口径（C4）：`##` 章节 → 原生卡片；`- ` 列表项 → 原生圆点行；`**bold**` 行内 Markdown 用 `AttributedString` 渲染为粗体，不再显示星号；`**Effective date:**`/Operator/Contact 等标题前 metadata 正常显示（生效日期进标题卡，其余作为标题卡内 footnote 段落），不再被丢弃。
>
> 语言跟随（task-10）：协议正文按应用内语言（设置 → 语言）选择 `*-en.md` / `*-zh.md`；切换语言时根视图重建，本页重新加载并渲染新语言。页面标题/生效日期/错误态文案均走 `L10n`。
>
> 应用内语言限制：InfoPlist 权限用途弹窗（相机/相册）与主屏幕 App 名称由系统语言决定，运行时切换应用内语言不改变它们（主 App 显示名已按系统语言本地化）。

## 共享弹层

| 标识 | 控件 | 行为 |
|---|---|---|
| `wuji.confirmation.title` | 自定义二次确认标题 | 只读 |
| `wuji.confirmation.confirm` | 确认按钮（破坏性红色） | 执行操作 |
| `wuji.confirmation.message` | 二次确认正文 | 只读（长文案可滚动） |
| `wuji.confirmation.cancel` | 取消按钮 | 关闭 |
| `wuji.toast` | 轻量提示胶囊 | 2.2s 自动消失；导入汇总、订阅更新结果、节点测速结果等复用 |

> 两个 sheet（FirstConnectSheet / ConfirmationSheet）已改为 `ScrollView` + `.presentationDetents([.medium, .large])`，小屏与大字号不再截断（B14）。

---

### 备注

- 所有新增文案走 `Wuji/Resources/{en,zh-Hans}.lproj/{Settings,Routing,Subscriptions}.strings`（`L10n.t(key, table:)`）；共用文案沿用 `Localizable.strings`。已用脚本核对 en/zh 两个表 key 完全对齐、代码引用的 key 全部存在。
- DEBUG 截图直达（不影响 Release）：`-WujiTab settings`（RootView）+ `-WujiScreenshotRoute <route>`（SettingsView / RoutingSettingsView / SubscriptionListView / SubscriptionDetailView）。
  可用 route：`subscriptions`、`subscriptions-delete-confirm`、`subscription-add`、`subscription-detail`、`subscription-edit`、`subscription-nodes`、`routing`、`regions`、`on-demand`、`test-url`、`timeout`、`about`、`licenses`、`terms`、`privacy`、`reset-confirm`、`clear-confirm`。
- 截图：`app_src/wuji/screenshots/impl-pagesB/`（EN 22 张 + 中文 4 张 + iPhone SE 7 张，含空/错误/二次确认状态）。


## 语言菜单（第五轮，11 语言）

| 标识 | 说明 |
|---|---|
| `wuji.settings.language.followSystem` | 设置页「跟随系统」行（勾选表示当前模式） |
| `wuji.settings.language.chooseAnother` | 设置页当前语言行 → 二级菜单 |
| `wuji.settings.language.picker` | 二级语言列表页 |
| `wuji.settings.language.option.<code>` | 语言选项：en/zh-Hans/zh-Hant/es/fr/de/ja/ko/ru/th/vi |
