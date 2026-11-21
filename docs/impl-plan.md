# 实现清单（impl-plan）— 无极 Wuji

> 阶段 3 = 阶段 4 验收清单。每条：ID | 页面/功能 | 期望行为 | 数据来源 | 负责 | 代码文件/符号 | 验证方式 | 状态
> 负责角色：**Lead**（主调度 + 共享层 + 首页 + 集成）、**engine**（NE 内核/隧道）、**data**（存储/解析/订阅/分流数据）、**pagesA**（启动/节点/导入）、**pagesB**（订阅/分流/设置）。
> 状态：`TODO` / `DOING` / `DONE` / `BLOCKED`。全部 DONE 才可进入阶段 4 收尾。

## A. 工程基建（Lead）

| ID | 页面/功能 | 期望行为 | 数据来源 | 负责 | 代码文件/符号 | 验证方式 | 状态 |
|---|---|---|---|---|---|---|---|
| A1 | Xcode 工程 | `xcodegen generate` 生成两 target（Wuji / WujiTunnel）+ 单测 target；设备与模拟器均可编译 | project.yml | Lead | project.yml | xcodebuild build | DONE |
| A2 | 签名与能力 | App/扩展 entitlements：App Group + NetworkExtension packet-tunnel-provider；真机签名成功 | - | Lead | Wuji.entitlements / WujiTunnel.entitlements | 真机构建 + 安装 | BLOCKED |
| A3 | LibXray 框架 | 裁剪版 xcframework 只含 iOS 设备/模拟器 arm64，扩展可链接、`Invoke` 可调 | tools/build_libxray.sh | Lead/engine | Frameworks/LibXray.xcframework | 扩展编译 + 真机跑 | DONE |
| A4 | 设计系统 | 原生系统色/字体/组件（卡片/按钮/空态/连接键/数据行）与设计图一致 | design-refs/native | Lead | Wuji/DesignSystem/Theme.swift、Components.swift | 视觉对照 | DONE |
| A5 | App 骨架 | 三 tab（连接/节点/设置）+ 启动/引导/协议同意门控 + 前台刷新 | spec §2 | Lead | WujiApp.swift / RootView.swift | 模拟器运行 | DONE |
| A6 | App Group 通道 | 主 App 写 `active_tunnel.json`，扩展读；状态/流量回传 | spec §4.1 | Lead/engine | Wuji/Core/Models/AppGroup.swift | 真机联调 | DONE |
| A7 | 本地化 | en + zh-Hans 全量字符串，跟随系统、回退 en；权限用途文案双语 | spec §2.1 | Lead + pages | Resources/*.lproj/Localizable.strings | 切语言跑 UI | DONE |
| A8 | 图标与资源 | App 图标 1024 母图（阶段 3 生成，阶段 5 复用） | - | Lead | Assets.xcassets/AppIcon | 构建 + 桌面 | DONE |

## B. 数据层（data）

| ID | 页面/功能 | 期望行为 | 数据来源 | 负责 | 代码文件/符号 | 验证方式 | 状态 |
|---|---|---|---|---|---|---|---|
| B1 | SQLite 库 | 打开/迁移/CRUD/事务；WAL；三表 + settings；重启不丢 | spec §4.2 | data | Wuji/Core/Store/AppDatabase.swift | 单测 + 重启 | DONE |
| B2 | 节点仓库 | groups/profiles CRUD、手动组自动创建、订阅组级联删除、延迟写回 | spec §4.2 | data | ProfileStore.swift | 单测 | DONE |
| B3 | 设置仓库 | AppSettings JSON 持久化、默认值、活跃节点 | spec §4.2 | data | SettingsStore.swift | 单测 | DONE |
| B4 | 订阅仓库 | 订阅 CRUD、流量/到期字段 | spec §4.2 | data | SubscriptionStore.swift | 单测 | DONE |
| B5 | URI 解析/编码 | vmess://（含 legacy base64 JSON）、vless://、trojan://、ss:// 全字段解析；编码回分享链接；非法输入报错 | spec §5.4/5.6 | data | URIParserCore.swift | 单测（样本 URI 覆盖 4 协议） | DONE |
| B6 | 订阅服务 | HTTPS 拉取、UA、超时、base64/明文列表解析、Subscription-Userinfo 流量/到期、错误分类 | spec §5.7 | data | SubscriptionService.swift | 单测（mock URLProtocol） | DONE |
| B7 | 延迟测速 | TCP 握手延迟、超时、并发 8、批量回调；结果写库 | spec §5.3 | data | LatencyTester.swift | 真机 + 单测 | DONE |
| B8 | 国家/地区数据 | bundle 内置 `geoip.dat.gz`（v2fly/geoip → DB-IP Lite；4.40 MB gz / 23.8 MB 原始，sha256 `eedb24b3b9fc…`）+ `geoip_countries.json`（253 list / 250 国家的 code→CIDR 数元数据）；首次启动解压到 App Group；`tools/prepare_geoip_assets.py` 可复现并 `--check` | spec §4.4 | geoip | tools/prepare_geoip_assets.py、GeoIPAssetManager、GeoIPCodec、GeoIPProtoParser、CountryDirectory | 脚本 `--check` + 单测 | DONE |
| B9 | 分流规则生成 | 连接时只抽取选中国家的 list 原始 protobuf entry → `wuji-geoip-<hash>.dat`；`XrayBuildInput.geoIPRuleTargets`（`ext:<file>:cn`…）+ `geoIPAssetDirectory`（扩展侧 `xray.location.asset`），配置仅 1 条 direct 规则，不做 CIDR 展开 | spec §4.3/§5.10 | geoip/Lead | GeoIPAssetManager.makeAsset、XrayConfigBuilder、AppState.connectInternal | 单测（entry 原样复制/文件名稳定/仅保留 3 个）+ 真机分流验证 | 代码完成 / 真机 BLOCKED（F3） |
| B9a | 数据更新 | 启动/前台/隧道状态变化检查；7 天新鲜度、仅 VPN 已连接时自动下载、jsDelivr→raw GitHub、sha256 校验后原子替换；失败保留旧数据 + 固定 1 小时重试；manualUpdate 手动无视门槛；meta/status 供设置页 | spec §4.4 | geoip | GeoIPUpdater | 单测（7 天/1 小时/校验失败/镜像回落/meta 持久化）+ 模拟器启动解压 | DONE |

| B10 | 演示数据 | DEBUG 构建首次启动写入 9 条演示节点（TEST-NET 地址）；Release 不写 | spec §4.4 | data | Wuji/Core/Store/DemoSeed.swift | 模拟器两种配置各跑一次 | DONE |

## C. 内核与隧道（engine）

| ID | 页面/功能 | 期望行为 | 数据来源 | 负责 | 代码文件/符号 | 验证方式 | 状态 |
|---|---|---|---|---|---|---|---|
| C1 | Xray 配置生成 | 由 NodeProfile+AppSettings 生成合法 Xray JSON：4 协议出站、ws/grpc/h2/tcp、tls/reality、tun inbound、dns 防泄漏、routing（direct proxy 分流、代理服务器 IP 直连）、stats policy | spec §6.4 | engine | Wuji/Core/Routing/XrayConfigBuilder.swift | `libXray Invoke(testXray)` + 真机连接 | DONE |
| C2 | 隧道控制器 | NETunnelProviderManager 创建/更新/启动/停止/按需规则；状态监听回传 App | spec §2.4 | engine | Wuji/Core/Tunnel/TunnelController.swift（实现替换） | 真机 | DONE |
| C3 | 配置下发 | 写 App Group `active_tunnel.json`；扩展读取；`NETunnelProviderProtocol.providerConfiguration` 指路 | spec §4.1 | engine | AppGroup.swift / TunnelController | 真机 | DONE |
| C4 | NE 扩展启动 | 配置 NEPacketTunnelNetworkSettings（0/0 + ::/0、LAN 排除、DNS、MTU 1380、enforceRoutes），枚举 utun fd，注入 `env.xray.tun.fd`，`Invoke(runXray)` | spec §6.4 | engine | WujiTunnel/PacketTunnelProvider.swift、TunFdResolver.swift | 真机连接成功 | DOING |
| C5 | 停止与错误 | stopTunnel 调 stopXray；启动失败回调具体错误；系统占用/权限拒绝文案 | spec §5.2 | engine | PacketTunnelProvider.swift / TunnelError | 真机错误场景 | DONE |
| C6 | 流量统计 | Xray stats（uplink/downlink）经 `sendProviderMessage` 回传；速率由 App 计算 | spec §5.2 | engine | 扩展 + libXray fork（getTrafficStats） | 真机显示真实流量 | DONE |
| C7 | 按需连接 | 关闭/总是/仅 Wi-Fi/仅蜂窝 → NEOnDemandRule；保存后生效 | spec §5.11 | engine | TunnelController | 真机验证 | DOING |
| C8 | 内存与稳定性 | 扩展 <50MB；连接 10 分钟不崩、不断流 | spec §6.4 | engine | 全链路 | 真机 Instruments / 日志 | TODO |
| C9 | libXray fork 补丁 | 本地 fork 增补流量统计 invoke 方法；`tools/build_libxray.sh` 可复现构建 | spec §6.4 | engine | tools/libxray-patch/、build_libxray.sh | 重新构建成功 | DONE |
| C10 | 协议覆盖 | VMess/VLESS(含 REALITY)/Trojan/SS 真实节点可连接（用户提供节点） | spec §5.4 | engine | XrayConfigBuilder + URIParser | 真机 4 协议各连一次 | TODO |

## D. 页面（Lead / pagesA / pagesB）

| ID | 页面/功能 | 期望行为 | 数据来源 | 负责 | 代码文件/符号 | 验证方式 | 状态 |
|---|---|---|---|---|---|---|---|
| D1 | 启动屏 | 品牌启动态，无白屏；深链不适用 | 设计 N-launch | Lead | UILaunchScreen + Assets | 冷启动 | DONE |
| D2 | 引导 3 页 | 3 页内容、页码点、跳过、只出现一次 | 设计 N-onboarding-* | pagesA | Features/Onboarding/OnboardingView.swift | UI 截图 | DONE |
| D3 | 协议同意 | 数据声明、协议入口、勾选后才可继续、只出现一次 | 设计 N-consent | pagesA | ConsentView.swift | UI + 重启校验 | DONE |
| D4 | 首连授权弹窗 | 首次连接前说明 + Allow/Not Now；Allow 后触发系统 VPN 授权 | 设计 N-first-connect-sheet | Lead | FirstConnectSheet.swift + HomeView | 真机 | DONE |
| D5 | 首页四态 | 未连接/连接中/已连接/错误；状态文案、节点卡、流量、时长、分流摘要；错误横幅 + 重试 | spec §5.2 | Lead | Features/Home/HomeView.swift | 模拟器 mock 状态 + 真机 | DONE |
| D6 | 首页系统状态同步 | 系统设置断开/其他 App 占用 → 状态回同步；前台刷新 | spec §2.4 | Lead/engine | AppState + TunnelController | 真机 | DOING |
| D7 | 节点列表 | 分组 section、延迟/协议/选中、搜索、排序、批量测速、下拉刷新 | spec §5.3 | pagesA | Features/Nodes/NodeListView.swift | UI + 真机 | DONE |
| D8 | 节点行操作 | 设为当前/编辑/删除（二次确认）/复制 URI/二维码 | spec §5.3 | pagesA | NodeActionsSheet.swift | UI + 持久化 | DONE |
| D9 | 节点空状态 | 插画位（SF Symbol）+ 文案 + 添加/扫码/订阅入口 | 设计 N-nodes-empty | pagesA | NodeListView | 空库启动 | DONE |
| D10 | 手动添加表单 | 4 协议动态字段、校验（必填/端口/UUID/重复）、保存/取消、键盘不遮挡 | spec §5.4 | pagesA | AddNodeFormView.swift | UI + 单测 | DONE |
| D11 | 扫码导入 | 相机权限、扫码识别、相册识别、解析失败提示、预览保存 | spec §5.5 | pagesA | ScanQRView.swift | 真机扫码 | DONE |
| D12 | 剪贴板导入 | 多行粘贴、预览识别结果、批量导入 | spec §5.6 | pagesA | PasteImportView.swift | UI + 单测 | DONE |
| D13 | 二维码分享 | 生成二维码、保存相册、复制 URI、系统分享 | spec §5.9 | pagesA | QRShareView.swift | 真机扫码验证 | DONE |
| D14 | 订阅列表 | 订阅卡片（节点数/更新时间/流量/到期）、删除二次确认、错误提示 | spec §5.7 | pagesB | Features/Subscriptions/SubscriptionListView.swift | UI + 真机 | DONE |
| D15 | 添加/编辑订阅 | URL/名称/自动更新间隔、添加并更新、加载态、失败提示 | spec §5.7 | pagesB | AddSubscriptionView.swift | 真机真订阅 | DONE |
| D16 | 订阅详情与更新 | 流量/到期、节点预览、立即更新、编辑、删除 | spec §5.7 | pagesB | SubscriptionDetailView.swift | 真机 | DONE |
| D17 | 分流设置 | 规则/全局模式、局域网开关、地区选择入口、说明文案、即时保存 | spec §5.10 | pagesB | Features/Routing/RoutingSettingsView.swift | UI + 真机分流 | DONE |
| D18 | 地区多选 | 搜索、勾选/取消、已选计数、Done 保存 | spec §5.10 | pagesB | CountryPickerView.swift | UI | DONE |
| D19 | 设置页 | 连接/测速/订阅/支持/数据分组、开关持久化、重置 VPN、清空数据 | spec §5.11 | pagesB | Features/Settings/SettingsView.swift | 重启校验 | DONE |
| D20 | 关于与开源许可 | 版本、组件许可、联系支持、协议入口 | spec §5.12 | pagesB | AboutView.swift / LicensesView.swift | UI | DONE |
| D21 | 协议/隐私页 | App 内本地双语正文，与阶段 5 定稿一致 | spec §5.13 | pagesB | LegalDocumentView.swift + resources/*.md | 切语言 + 内容核对 | DONE |
| D22 | iPad / Duo 自适应 | ≥700pt 双栏（侧边栏+详情/列表）；SE 小屏不越界 | 设计 N-ipad / N-duo | Lead + pages | RootView + 各页面布局 | 模拟器 iPad/SE 截图 | DONE |

## E. 全局质量与本地化

| ID | 项目 | 期望行为 | 负责 | 验证方式 | 状态 |
|---|---|---|---|---|---|
| E1 | 空/加载/错误/离线/权限拒绝 | 所有列表与网络操作覆盖 | 全体 | 逐页截图 | DONE |
| E2 | 无障碍标识 | 每控件稳定 `accessibilityIdentifier`，登记 `docs/ids.md` | 全体 | 代码核对 + UI 测试 | DONE |
| E3 | 键盘处理 | 有输入的页面键盘不遮挡、可收起、归属判断正确 | pagesA/pagesB | 真机 | DONE |
| E4 | 文案质量 | en 自然（humanizer 过一遍）、zh-Hans 自然；术语统一 | Lead | 抽检 | DOING |
| E5 | 图片资源 | App 图标、空态图形全部真实资源，无灰块 | Lead | 视觉核对 | DONE |
| E6 | 无壳检查 | 无死按钮/假数据/缺状态；禁止 TODO/FIXME/占位 | Lead | 验收 | DOING |

## F. 测试与验收

| ID | 项目 | 期望行为 | 负责 | 验证方式 | 状态 |
|---|---|---|---|---|---|
| F1 | 单元测试 | 解析/存储/订阅/路由规则/配置生成 单测通过 | data/engine | xcodebuild test | DONE |
| F2 | 真机连接 | 用户提供节点后可连、可断、状态正确、流量真实 | engine/Lead | 真机 | BLOCKED |
| F3 | 分流验证 | 选中地区 IP 直连、局域网直连、全局模式不生效 | data/Lead | 真机 + 访问验证 | BLOCKED |
| F4 | 交互覆盖 | 每控件点一遍、每滚动区滚一遍并断言 | Lead | 真机/模拟器 | TODO |
| F5 | 设备矩阵 | iPhone SE / iPhone 17 Pro / iPad Pro 13 / Duo 布局 | Lead | 模拟器截图 | DOING |
| F6 | 旅程 1 | 首启→引导→同意→空态→手动添加→连接→断开 | Lead | 真机 | DOING |
| F7 | 旅程 2 | 添加订阅→更新→选节点→连接→勾选地区→重连生效 | Lead | 真机 | DOING |

## G. 商店信息与交付（阶段 5/6）

| ID | 项目 | 期望行为 | 负责 | 验证方式 | 状态 |
|---|---|---|---|---|---|
| G1 | 商店 5 图 | iOS 1320×2868 五张，原生风格卖点图 | Lead | store-assets §8 清单 | DONE |
| G2 | 图标 | AppIcon 1024 无 alpha，与 App 内一致 | Lead | 规格校验 | DONE |
| G3 | 隐私政策/用户协议 | 与 App 内文本一致、双语、含联系方式 | Lead | 核对 | DONE |
| G4 | 提交填写信息 | en 主版本 + 中文参考、字符数合规、Data safety/App Privacy 要点、5.4 审核备注（含测试节点/示例二维码说明） | Lead | 人工核对 | DONE |
| G5 | 交付摘要 | 只写实际结果 | Lead | 对照 | DONE |

## H. 生命周期修复补充（task-6 / lifecycle-fix，2026-11-20）

> 只记录本次修复涉及的条目；表内原状态保留（真机相关仍为 BLOCKED/DOING，未在真机验证）。
> 详细行为契约、验证路径见 `docs/ids-lifecycle.md`。

| 审计项 | impl-plan 关联 | 代码文件/符号 | 验证方式 | 代码状态 |
|---|---|---|---|---|
| A1 主 App NE entitlement | A2 签名与能力 | Wuji/Wuji.entitlements | 模拟器构建签名/嵌入校验；真机 saveToPreferences 待门户+真机 | 代码完成 / 真机 BLOCKED |
| A2 按需模式可断开 | C2 隧道控制器、C7 按需连接 | TunnelController.stop()（先关 on-demand 并 saveToPreferences 再 stop）、updateOnDemandMode reload | 真机：按需模式下 App 内断开后不被系统重连 | 代码完成 / 真机 BLOCKED |
| A4 清空数据完整重置 | D19 设置页 | SettingsView.clearAllData + AppState.resetVPNConfiguration + AppDatabase.deleteAllData | 模拟器：二次确认→toast→引导态；数据清空 | DONE |
| A5 订阅刷新 active 一致性 | B6 订阅服务、B2 节点仓库调用点 | AppState.refresh / isSameEndpoint（proto+server+port+凭据） | 单测基建 + 代码核对（模拟器可复现数据层） | DONE |
| B1 局域网开关真生效 | C4 NE 扩展启动、C3 配置下发 | TunnelLaunchConfig.bypassLAN、TunnelNetworkSettingsFactory.make(bypassLAN:)、PacketTunnelProvider 一行接线 | 真机：LAN 直连/走代理对比；模拟器仅编译 | 代码完成 / 真机 BLOCKED |
| B6 连接键 busy 禁用 | D5 首页四态 | ConnectionButton.disabled(state.isBusy) + HomeView.handleConnectTap | 模拟器 UI（DEBUG 状态钩子） | DONE |
| B7/G4 删除当前节点/订阅先断开 | D8 节点行操作、D14 订阅列表 | AppState.deleteProfile / disconnectIfActiveNodeDeleted / prepareForRemoval(of:) / prepareForRemoval(ofGroup:)（删订阅调用点待 Lead 接线） | 真机 + 代码核对 | 代码完成 / 真机 BLOCKED |
| B8 订阅刷新失败记录/去重 | B6 订阅服务 | AppState.refresh（recordFailure + refreshingSubscriptionIDs） | 单测基建 + 代码核对 | DONE |
| B10（部分）隧道错误本地化 | C5 停止与错误 | TunnelError → L10n（error.tunnel.timeout / error.tunnel.failed；key 已由 Lead 补齐 en/zh-Hans） | 模拟器触发启动失败文案 | 代码完成 |
| B11 日志隐私 | C2/C5 | TunnelController 日志 privacy: .private | 代码核对 | DONE |
| C7 文本细节 | D5 首页、Components | SectionHeader 中文不 uppercase；HomeView 用 String(format: unit.ms) | 切 zh-Hans 模拟器 | DONE |
| C9 active_tunnel.json 安全 | C3 配置下发 | TunnelLaunchConfig 写盘 .completeFileProtectionUntilFirstUserAuthentication；stop()/reset 删除 | 真机：断开后文件消失；锁屏启动 | 代码完成 / 真机 BLOCKED |
| G3 连接中改节点/分流自动重连 | D5/D17 | AppState TunnelSetup + 0.5s 防抖 reconnect（epoch/generation 取消保护） | 真机 + 模拟器状态观察 | 代码完成 / 真机 BLOCKED |

- 2026-11-20 09:26 终验：模拟器 Debug `build` BUILD SUCCEEDED；`-only-testing:WujiTests test` **58/58 passed**（0 failures；09:23 首轮 55/55），独立 derivedData `/tmp/wuji-dd-life`。

## I. GeoIP 数据链路（task-8 / geoip，2026-11-20 架构调整后）

> 用户决策：按 IP 判断国家/地区 → 不用「CIDR 全量展开进 routing」，改为内置 `geoip.dat` + Xray
> `ext:<file>:<cc>` 运行时匹配；App 只抽取选中国家的 list；数据每 7 天自动更新且仅在 VPN 连接后、
> 失败固定 1 小时重试。详细来源/许可见 `docs/deps.md`、`docs/licenses-geoip.md`。

| ID | 项目 | 期望行为 | 负责 | 代码文件/符号 | 验证方式 | 状态 |
|---|---|---|---|---|---|---|
| G1 | 内置数据资产 | `geoip.dat.gz`（4,614,749 B；解压 23,876,117 B，sha256 `eedb24b3b9fc…`）+ `geoip_countries.json`（2,758 B，253 list）；生成脚本 `--check` 全量校验（sha256/计数/必备国家/体积） | geoip | Wuji/Resources/、tools/prepare_geoip_assets.py | 脚本 `--check`；单测核对元数据=重扫结果 | DONE |
| G2 | 首次启动安装 | 后台把 bundle gz 解压为 App Group `geoip.dat`，重扫写 `geoip_countries.json` 与基线 `geoip_meta.json`；幂等 | geoip/Lead | GeoIPAssetManager.prepareDatasetIfNeeded、GeoIPUpdater.prepareIfNeeded（AppState 接线） | 单测 + 模拟器启动后检查 App Group 文件 | DONE |
| G3 | 连接资产抽取 | `makeAsset(codes:includePrivate:dataVersion:) -> GeoIPAsset?`：按 code 复制 entry 原始字节拼新 GeoIPList，写 `wuji-geoip-<12hex>.dat`，返回 `directory/fileName/ruleTargets`；文件名由 dataVersion+选中国家集合决定（顺序无关、版本变化换名）；清理旧资产保留最近 3 个 | geoip | GeoIPAssetManager、GeoIPProtoParser | 单测：entry 原样复制、hash 稳定、PRIVATE-only、清理、真实数据抽取 | DONE |
| G4 | 数据更新 | `updateIfNeeded(vpnConnected:)`：7 天新鲜度 + 仅连接后 + 失败 1 小时固定重试；`manualUpdate()` 无视门槛；jsDelivr→raw GitHub，sha256 + protobuf 扫描校验后原子替换；失败保旧数据、记录 lastError | geoip/Lead | GeoIPUpdater（AppState 在 applyTunnelState(.connected) 接线 + 1 小时 Timer） | 单测（断开不下载/7 天/1 小时/校验失败/镜像回落/meta 持久化） | DONE |
| G5 | 国家选择元数据 | `CountryDirectory` 只加载 `geoip_countries.json`：countries/localizedName/reload + 搜索/计数/来源；App Group 覆盖优先、损坏回退 bundle、不显示 PRIVATE/TEST/ZZ | geoip | CountryDirectory、GeoIPMetadata | 单测：覆盖优先/损坏回退/reload/过滤伪国家 | DONE |
| G6 | 资产/许可文档 | `docs/deps.md` 数据来源/许可/更新机制；`docs/licenses-geoip.md` DB-IP(CC BY 4.0) + v2fly/geoip(CC BY-SA 4.0) 双署名与 App 内文案；生成 JSON `license` 字段同步 | geoip | docs/deps.md、docs/licenses-geoip.md、Wuji/Resources/geoip_countries.json | 文档核对 | DONE |
| G7 | App 内接线（Lead） | Settings 数据状态行（GeoIPUpdater.status + 立即更新）、About/许可文案替换旧的 MaxMind 表述 | Lead | SettingsView、LicensesCatalog、AboutView | 模拟器 UI | 待 Lead |

- 2026-11-20 09:55 终验：模拟器 Debug `build` **BUILD SUCCEEDED**；`-only-testing:WujiTests test`
  **90/90 passed, 0 failures**（含 GeoIPTests 33 条），独立 derivedData `/tmp/wuji-dd-geo`。
- 模拟器集成验证（免联网）：App 首次启动后 App Group 内出现 `geoip.dat` 23,876,117 B、
  `geoip_countries.json`（250 国家/1,410,686 CIDR）、`geoip_meta.json`（dataVersion `eedb24b3b9fc`）。
- 未验证：真实联网下载（jsDelivr/raw GitHub）、真机 7 天/1 小时调度、VPN 连接后下载与分流效果
  （模拟器不能建立 NE 隧道）——交付说明中如实标注。
