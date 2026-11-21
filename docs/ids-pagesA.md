# ids — pagesA（启动引导 / 协议同意 / 节点 / 添加 / 导入 / 二维码）

> owner：pages-a。命名规范 `wuji.<page>.<control>`；列表中带节点 id 的后缀保证索引无关的稳定标识。
> 文件：`docs/ids-pagesA.md`（与 Lead 汇总的 `docs/ids.md` 合并时以本表为准）。

## 1. 引导 OnboardingView（D2）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.onboarding.pager` | 引导 | 横向分页容器（可滑动，3 页） |
| `wuji.onboarding.skipButton` | 引导 | 右上角 Skip，标记 onboarding_done 并进入协议同意 |
| `wuji.onboarding.pageIndicator` | 引导 | 页码点（非交互，VoiceOver 播报「第 X 页，共 3 页」） |
| `wuji.onboarding.primaryButton` | 引导 | 底部主按钮：Continue（前两页）/ Get Started（末页） |

## 2. 协议同意 ConsentView（D3）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.consent.termsLink` | 协议同意 | 用户协议行，push App 内 LegalDocumentView(.terms) |
| `wuji.consent.privacyLink` | 协议同意 | 隐私政策行，push App 内 LegalDocumentView(.privacy) |
| `wuji.consent.checkbox` | 协议同意 | 勾选同意；VoiceOver value = 已同意/未同意；`isSelected` trait |
| `wuji.consent.continueButton` | 协议同意 | Agree & Continue；未勾选时 disabled + 50% 透明 |

## 3. 节点列表 NodeListView（D7/D8/D9）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.addButton` | 节点列表 | 导航栏 + → 添加方式弹层 |
| `wuji.nodes.sortMenu` | 节点列表 | 导航栏排序菜单：名称/延迟/添加时间 + 升/降序，写 settings.sortField / sortAscending |
| `wuji.nodes.testAllButton` | 节点列表 | 导航栏全部测速；测速中显示 ProgressView 且禁用 |
| `wuji.nodes.empty.addButton` | 节点空状态 | 主按钮 Add Node → 添加方式弹层 |
| `wuji.nodes.empty.addSubscriptionButton` | 节点空状态 | 次按钮 Add Subscription → 添加订阅页 |
| `wuji.nodes.empty.scanButton` | 节点空状态 | 第三入口 Scan QR Code → 扫码页 |
| `wuji.nodes.row.<profileID>` | 节点列表 | 节点行主体：点按 = 设为当前节点（行内出现 ✓，轻触觉反馈） |
| `wuji.nodes.rowMenu.<profileID>` | 节点列表 | 行内 ⋯ → 节点操作 sheet |
| `wuji.nodes.latency.<profileID>` | 节点列表 | 行尾延迟文本（`%d ms` / `--`） |
| `wuji.nodes.swipeDelete.<profileID>` | 节点列表 | 行左滑 Delete（二次确认后删除） |
| `wuji.nodes.swipeEdit.<profileID>` | 节点列表 | 行左滑 Edit Node |
| `wuji.nodes.swipeSetActive.<profileID>` | 节点列表 | 行右滑 Set as Active |
| `wuji.nodes.group.<groupID>.update` | 节点列表 | 订阅分组头右侧刷新按钮：调用 `AppState.refresh`，加载中显示 spinner，成功/失败 toast |
| —（系统搜索框） | 节点列表 | 搜索框由 SwiftUI `.searchable` 系统注入，无法设置自定义标识；搜索逻辑见 `nodes(in:)` |

## 4. 添加方式弹层 AddNodeMenuSheet（D7 子流程）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.addMenu.manual` | 添加方式 | Enter Manually → 手动添加表单 |
| `wuji.nodes.addMenu.scan` | 添加方式 | Scan QR Code → 扫码页 |
| `wuji.nodes.addMenu.paste` | 添加方式 | Paste from Clipboard → 剪贴板导入页 |
| `wuji.nodes.addMenu.subscription` | 添加方式 | Add Subscription → 添加订阅页 |
| `wuji.nodes.addMenu.cancel` | 添加方式 | Cancel，关闭弹层 |

## 5. 节点操作 NodeActionsSheet（D8）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.actions.header` | 节点操作 | 标题块（节点名 + 协议 · 地址），非交互 |
| `wuji.nodes.actions.setActive` | 节点操作 | Set as Active，写 settings.activeProfileID 后关闭 |
| `wuji.nodes.actions.edit` | 节点操作 | Edit Node，push 预填的编辑表单 |
| `wuji.nodes.actions.copyURI` | 节点操作 | Copy URI；成功后行标题变 Copied（1.6s 后还原） |
| `wuji.nodes.actions.shareQR` | 节点操作 | Share QR Code，push 二维码分享页 |
| `wuji.nodes.actions.share` | 节点操作 | Share，系统分享面板（分享 URI 文本） |
| `wuji.nodes.actions.delete` | 节点操作 | Delete Node（红色），二次确认后删除并关闭 |
| `wuji.nodes.actions.testLatency` | 节点操作 | Test Latency：统一走 `AppState.testLatencyResult(for:)`（连接中且为当前节点时经隧道 HTTP 测速，其余 TCP；HTTP 失败回落 TCP），行尾显示结果；测速中禁用 |
| `wuji.nodes.actions.testResult` | 节点操作 | 单节点测速结果（`%d ms` / `--`，条件显示） |
| `wuji.nodes.actions.cancel` | 节点操作 | Cancel |
| `wuji.nodes.actions.copyError` | 节点操作 | 无原始 URI 时的红字错误提示（条件显示） |

## 6. 添加 / 编辑节点 AddNodeFormView（D10）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.form.protocolPicker` | 添加/编辑节点 | 协议分段控件 VMess / VLESS / Trojan / Shadowsocks / SOCKS5，切换动态字段 |
| `wuji.nodes.form.name` | 添加/编辑节点 | 名称（可选，空则保存为 server:port） |
| `wuji.nodes.form.address` | 添加/编辑节点 | 服务器地址，URL 键盘；校验必填/非法字符 |
| `wuji.nodes.form.port` | 添加/编辑节点 | 端口，数字键盘；校验 1–65535 |
| `wuji.nodes.form.uuid` | 添加/编辑节点 | VMess / VLESS UUID，校验 UUID 格式 |
| `wuji.nodes.form.alterID` | 添加/编辑节点 | VMess Alter ID，数字键盘 |
| `wuji.nodes.form.encryption` | 添加/编辑节点 | VMess 加密方式（auto/aes-128-gcm/chacha20-poly1305/none） |
| `wuji.nodes.form.flow` | 添加/编辑节点 | VLESS 流控（None / xtls-rprx-vision） |
| `wuji.nodes.form.password` | 添加/编辑节点 | Trojan / Shadowsocks / SOCKS5 密码（SOCKS5 与用户名同时填写或同时留空） |
| `wuji.nodes.form.socksUsername` | 添加/编辑节点 | SOCKS5 用户名（可空；填写后密码必填） |
| `wuji.nodes.form.method` | 添加/编辑节点 | Shadowsocks 加密方法 |
| `wuji.nodes.form.network` | 添加/编辑节点 | 传输协议（TCP/WebSocket/gRPC/HTTP/2，按协议过滤） |
| `wuji.nodes.form.tls` | 添加/编辑节点 | VMess / Trojan TLS 开关 |
| `wuji.nodes.form.security` | 添加/编辑节点 | VLESS 安全层（None/TLS/REALITY） |
| `wuji.nodes.form.sni` | 添加/编辑节点 | SNI |
| `wuji.nodes.form.path` | 添加/编辑节点 | WebSocket Path（network = ws 时显示） |
| `wuji.nodes.form.host` | 添加/编辑节点 | WebSocket Host（network = ws 时显示） |
| `wuji.nodes.form.grpcService` | 添加/编辑节点 | gRPC Service Name（network = grpc 时显示） |
| `wuji.nodes.form.fingerprint` | 添加/编辑节点 | uTLS 指纹（None/Chrome/Firefox/Safari/iOS/Android/Edge/Randomized） |
| `wuji.nodes.form.allowInsecure` | 添加/编辑节点 | Allow Insecure（TLS/REALITY 时显示） |
| `wuji.nodes.form.realityPublicKey` | 添加/编辑节点 | REALITY 公钥（VLESS + REALITY 时显示，必填） |
| `wuji.nodes.form.realityShortID` | 添加/编辑节点 | REALITY Short ID（十六进制校验） |
| `wuji.nodes.form.cancelButton` | 添加节点 | Cancel（sheet 呈现时显示；push 编辑用系统返回） |
| `wuji.nodes.form.saveButton` | 添加/编辑节点 | Save：先校验，保存中显示 ProgressView |
| `wuji.nodes.form.keyboardDone` | 添加/编辑节点 | 键盘工具栏 Done（收起键盘） |
| `wuji.nodes.form.error.<field>` | 添加/编辑节点 | 行内红字校验错误（server/port/uuid/password/duplicate/realityPublicKey/realityShortID/socksCredentials） |
| `wuji.nodes.form.saveError` | 添加/编辑节点 | 保存失败红字（条件显示） |

## 6.1 SOCKS5（share link 兼容性）

- 解析：`socks://base64(user:pass)@host:port#name`、`socks://user:pass@host:port#name`、`socks://host:port#name`（无认证）、`socks5://` 同义；fragment 为空时名称回落 `host:port`；用户名/密码必须同时存在或同时为空（否则 `error.uri.malformed.socksCredentials`）。
- 分享/复制 URI：统一输出规范格式（无认证 `socks://host:port#name`；有认证 `socks://base64(user:pass)@host:port#name`），保证扫码/粘贴互转。
- 去重：proto+server+port+username+password；无认证节点也按空凭据判重。
- 不支持参数：socks 链接上的任意 query 参数会按 C11 警告提示（忽略，不阻断）。
- 表单：`wuji.nodes.form.protocolPicker` 选 SOCKS5 后只显示地址/端口/用户名/密码（无传输/TLS 段）；编辑已导入节点会回填 `socksUsername`。

## 7. 剪贴板导入 PasteImportView（D12）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.paste.editor` | 剪贴板导入 | 多行链接输入框，进入页面自动填充剪贴板；输入实时解析 |
| `wuji.nodes.paste.row.<profileID>` | 剪贴板导入 | 识别结果行：点按切换勾选（✓ 绿色）；已存在（同协议+地址+端口+凭据）的行显示「已存在」且不可勾选，导入时自动跳过 |
| `wuji.nodes.paste.warning.<profileID>` | 剪贴板导入 | 该节点含不支持参数（SS plugin / VMess ALPN 等）的橙色提示，不阻断导入 |
| `wuji.nodes.paste.failures` | 剪贴板导入 | 「无法解析 N 条」列表：逐行显示原始链接 + 失败原因（条件显示） |
| `wuji.nodes.paste.error` | 剪贴板导入 | 整段无法识别时的红字提示（条件显示） |
| `wuji.nodes.paste.cancelButton` | 剪贴板导入 | Cancel |
| `wuji.nodes.paste.importButton` | 剪贴板导入 | 导航栏 Import（与底部主按钮等效，未勾选/导入中 disabled） |
| `wuji.nodes.paste.primaryButton` | 剪贴板导入 | 底部主按钮 Import N Nodes，loading 态；导入后关闭、刷新列表，并在节点页 toast 汇总「已导入 N 条，跳过重复 M 条，无法解析 K 条」（含不支持参数计数） |

## 8. 扫码导入 ScanQRView（D11）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.scan.closeButton` | 扫码 | 左上角关闭（白圆底 ×） |
| `wuji.nodes.scan.choosePhotoButton` | 扫码 | 底部白圆相机按钮 + Choose from Photos（系统相册选择器，无需相册权限） |
| `wuji.nodes.scan.openSettingsButton` | 扫码·相机被拒 | 打开系统设置 |
| `wuji.nodes.scan.pasteButton` | 扫码·相机被拒 | 降级到剪贴板导入页 |
| `wuji.nodes.scan.unavailableMessage` | 扫码·相机不可用 | 取景框下方提示「当前设备没有可用相机」 |
| `wuji.nodes.scan.error` | 扫码 | 非法二维码/相册无可识别二维码的红底提示（2.5s 自动消失） |
| `wuji.nodes.scan.previewCard` | 扫码 | 识别成功预览卡片（节点名 / 协议 · 地址） |
| `wuji.nodes.scan.cancelSaveButton` | 扫码 | 预览卡片 Cancel（继续扫码） |
| `wuji.nodes.scan.warning` | 扫码 | 预览卡片内「该节点包含不支持的参数（…）」橙色提示（条件显示） |
| `wuji.nodes.scan.previewError` | 扫码 | 预览卡片内错误提示：节点已存在时显示「该节点已在列表中。」且不重复入库 |
| `wuji.nodes.scan.saveButton` | 扫码 | 预览卡片 Save Node：去重检查通过后入库、设为当前节点并关闭 |

## 9. 二维码分享 QRShareView（D13）

| 标识 | 页面 | 控件说明 |
|---|---|---|
| `wuji.nodes.qr.image` | 二维码分享 | CIFilter 生成的白底黑码（voiceover: 「<节点名> 的二维码」） |
| `wuji.nodes.qr.emptyState` | 二维码分享 | 无原始 URI 时的空状态（条件显示） |
| `wuji.nodes.qr.saveButton` | 二维码分享 | Save to Photos：PHPhotoLibrary 加相册权限、保存中 loading、失败红字 |
| `wuji.nodes.qr.copyButton` | 二维码分享 | Copy URI，写剪贴板并显示「URI Copied」 |
| `wuji.nodes.qr.shareButton` | 二维码分享 | 导航栏 Share，系统分享面板（URI 文本） |
| `wuji.nodes.qr.status` | 二维码分享 | 成功/失败状态行（绿色/红色，2.5s 自动消失） |

## 10. 导入结果与去重（B9 / C11）

- 去重口径：`proto` + `server` + `port` + 凭据（VMess/VLESS 用 uuid，Trojan 用 password，SS 用 password+method）相同即视为重复；同时比对库内全部节点与本次粘贴内的重复行。
- 不支持参数：SS `plugin` / `uot`、VMess `alpn` / 头混淆 `type`、VLESS/Trojan `alpn` / `headerType` 会被忽略并逐节点提示，不阻断导入。
- 汇总文案 `nodes.import.summary`，en/zh 双语；扫码单节点导入在预览卡内提示（不入库重复节点）。

## 11. DEBUG 截图钩子（不进 Release）

`#if DEBUG` 生效，供 headless 模拟器截图核对设计图：

| 启动参数 | 作用 |
|---|---|
| `-WujiScreenshotPage onboarding2` / `onboarding3` | 引导直接显示第 2/3 页 |
| `-WujiScreenshotPage consent-agreed` / `consent-terms` | 协议同意页勾选态 / push 用户协议页 |
| `-WujiScreenshotPage nodes-menu` / `nodes-add` / `nodes-add-vless` / `nodes-add-trojan` / `nodes-add-ss` / `nodes-add-socks` / `nodes-add-invalid` | 节点页打开添加方式 / 对应协议表单（含 SOCKS5）/ 空表单校验态 |
| `-WujiScreenshotPage nodes-add-subscription` | 节点页打开添加订阅页（pagesB） |
| `-WujiScreenshotPage nodes-scan` / `nodes-scan-preview` | 扫码页 / 识别成功预览卡 |
| `-WujiScreenshotPage nodes-paste` / `nodes-paste-data` / `nodes-paste-socks` | 剪贴板导入空态 / 预填四协议链接 / 预填 SOCKS5 三种用户信息格式（base64、明文、无认证） |
| `-WujiScreenshotPage nodes-actions`（配 `-WujiScreenshotDetail qr|edit`） | 节点操作 sheet / push 二维码分享 / push 编辑表单 |
| `-WujiScreenshotSearch <text>` | 节点列表预置搜索词（搜索无结果状态） |
| `-WujiScreenshotAction test` | 节点页启动即触发全部测速（行内 loading 状态） |
| `-WujiScreenshotAction sort-name` / `sort-latency-desc` | 预置排序（名称升序 / 延迟降序）并截图 |
| `-WujiScreenshotAction invalid`（配 add 表单） | 空表单点保存的校验失败红字状态 |
| `-WujiScreenshotAction autosave`（配 add 表单） | 自动填有效值并保存，验证表单→入库→列表刷新链路 |
| `-WujiScreenshotAction import`（配 paste 页） | 自动导入已识别节点，验证批量导入链路 |
