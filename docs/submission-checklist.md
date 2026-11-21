# 提交 App Store 检查清单（WProxy / 无极代理）

> 当前工程状态：bundle id `com.juejin.ios.wuji`（扩展 `com.juejin.ios.wuji.tunnel-ext`）、Team `R6748V42K5`、
> 版本 `1.0.0 (1)`、自动签名、主 App + 扩展均已声明 App Groups + Network Extension entitlement。
> Debug/Release（模拟器 + 设备架构）构建通过，单测 117/117，商店 5 图/1024 图标已就绪。
> 旧 App Store 记录：`id1448657437`（无极代理，Bundle ID 相同）→ 提交时选择更新该记录，不要新建 App。

## 0. 安全（必须）
- [ ] 立即修改开发者账号密码（密码已在聊天中出现过），开启双重认证（Apple Developer 强制）。
- [ ] 不要把密码/验证码发给任何人；如需自动化上传，用 App Store Connect API Key（App Manager 权限）或由你本人在 Xcode 登录。

## 1. Apple Developer 门户（developer.apple.com）
- [ ] 确认账号为 Organization（公司账号），Team ID `R6748V42K5`。
- [ ] App ID `com.juejin.ios.wuji`：勾选 **App Groups**（group.com.youqu.wuji.appgroup）与 **Network Extensions**（Packet Tunnel Provider）。
- [ ] App ID `com.juejin.ios.wuji.tunnel-ext`：勾选 **App Groups**（同上）与 **Network Extensions**（Packet Tunnel Provider）。
- [ ] 创建/更新 App Group `group.com.youqu.wuji.appgroup`，两个 App ID 都关联它。
- [ ] 生成 App Store 发布证书（Apple Distribution）+ App Store 描述文件（或使用 Xcode 自动签名）。
- [ ] 记录 Team ID 与两个 Bundle ID 的 provisioning 状态。

## 2. App Store Connect
- [ ] 协议、税务、银行：Agreements, Tax, and Banking 全部 Active（付费 App 必需）。
- [ ] My Apps → 无极代理（旧记录）→ App 信息：名称本地化（zh-Hans 无极代理 / en WProxy）、副标题、分类（工具/网络）。
- [ ] 价格：付费下载（Tier 按你定价），无 IAP；旧 IAP 产品保留但不关联版本。
- [ ] App 隐私：不收集数据（No, we do not collect data）；不使用追踪。
- [ ] 出口合规：使用标准加密（TLS/HTTPS/VPN）→ App Encryption Documentation 按标准加密豁免申报；Info.plist 不写 `ITSAppUsesNonExemptEncryption=false`（已移除）。
- [ ] 年龄分级、版权、隐私政策 URL、用户协议 URL、支持 URL、联系邮箱（需公网可访问；本地 md 不能直接当 URL）。
- [ ] 6.9 英寸截图 5 张（1320×2868）、App 图标 1024（无 alpha）、宣传文本/描述/关键词。
- [ ] App Review 备注：写清这是 BYO 服务器客户端、如何添加测试节点（提供可用节点/示例二维码）、如何测试连接/分流、中国区资质说明；提供测试节点与订阅 URL。
- [ ] 如需 USA 等地区销售：出口合规/加密说明按 ASC 指引回答。

## 3. 本机签名与打包（你登录 Xcode 账号后）
- [ ] Xcode → Settings → Accounts 登录你的 Apple ID（你自己输入密码/2FA，我不需要也不应接触）。
- [ ] 打开 `Wuji.xcodeproj`，两个 target 的 Signing & Capabilities 确认 Team = R6748V42K5、自动签名勾选。
- [ ] 真机连接/信任，先跑通 tunnel（本地网络 + VPN 配置权限弹窗、连接/断开、锁屏、Wi‑Fi↔5G 切换）。
- [ ] Archive（Release / Any iOS Device）→ Organizer → Distribute App → App Store Connect → Upload。
- [ ] 上传成功后 App Store Connect → TestFlight 内部测试，确认构建可用。
- [ ] 选中构建、提交审核。

## 4. 命令（签名配置完成后可用于校验/上传）
```bash
# 1) 归档（需已登录 Xcode 账号且有自动签名权限）
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Wuji.xcarchive archive

# 2) 导出 App Store ipa（ExportOptions.plist 由 Xcode 生成或手写 method=app-store-connect）
xcodebuild -exportArchive -archivePath /tmp/Wuji.xcarchive \
  -exportPath /tmp/Wuji-export -exportOptionsPlist ExportOptions.plist

# 3) 上传（三选一）：Xcode Organizer / Transporter.app / altool（App Store Connect API Key）
xcrun altool --upload-app -f /tmp/Wuji-export/Wuji.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

## 5. 提交前技术验收（真机，必做）
- [ ] 首次启动：引导 3 页 → 本地网络权限 → VPN 配置权限 → 协议 → 主页。
- [ ] 添加节点：手动/粘贴/扫码；SOCKS5 认证/无认证；订阅添加与更新。
- [ ] 连接/断开；切换节点/分流/DNS/语言后自动重连；删除当前节点自动断开。
- [ ] 锁屏保持；Wi‑Fi ↔ 5G 自动重连；长时间（至少数小时）运行看内存/掉线。
- [ ] 分流验证：选中地区/局域网不代理、全局模式全部走代理；DNS 两种模式。
- [ ] 11 种语言切换 + 重启保持；清空数据/重置 VPN 配置。
- [ ] 权限被拒时的失败页：重新请求 / 打开系统设置。
- [ ] App Review 测试节点在审核期间可用（至少覆盖 VMess/VLESS/Trojan/SS/SOCKS5 之一）。

## 6. 用户需要提供给我的东西（合规/审核相关）
- [ ] 隐私政策公网 URL、用户协议公网 URL、支持 URL。
- [ ] App Review 测试节点（服务器/端口/协议/凭据）+ 示例订阅 URL / 二维码。
- [ ] 最终定价（付费档位）。
- [ ] 中国区相关资质说明文案（Review Notes 用）。
- [ ] 确认是否沿用旧 App Store 记录与旧 IAP 产品（仅保留、不集成）。
