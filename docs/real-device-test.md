# 真机测试指南（WProxy / 无极代理）

> 已检测到一台物理 iPhone：**Wanli 的 iPhone 16**（UDID `00008140-001934312102801C`，当前状态 unavailable = 未连接/未信任）。
> 模拟器不能测 NetworkExtension，真机测试是提审前唯一有效验证。

## 0. 前置条件（必须全部满足）
- [ ] Apple Developer 门户已为两个 App ID 开启 **App Groups** + **Network Extensions（Packet Tunnel Provider）**。
- [ ] Xcode 已登录你的 Apple ID（Settings → Accounts，密码/2FA 你自己输入）。
- [ ] Xcode 中 `Wuji` 与 `WujiTunnel` 两个 target 的 Signing 都选中 Team `R6748V42K5`，自动签名通过（无红色错误）。
- [ ] iPhone 已用数据线连接本 Mac、解锁、点「信任此电脑」。
- [ ] iPhone 开启开发者模式：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机 → 解锁确认。
- [ ] 手机系统版本 ≥ iOS 17.0。
- [ ] 准备一个**真实可用节点**（VMess / VLESS / Trojan / Shadowsocks / SOCKS5 任意），演示数据里的 203.0.113.x 是 TEST-NET，不能真正连接。

## 1. 连接手机并确认
```bash
xcrun devicectl list devices
# 期望看到：Wanli的iPhone 16 ... available ... physical
xcrun devicectl device info --device 00008140-001934312102801C
```
> 如果显示 unavailable：重新插拔数据线、解锁手机、点信任、确认开发者模式，再执行一次。

## 2. 运行 App（二选一）

### A. 用 Xcode 图形界面（推荐）
1. `open Wuji.xcodeproj`
2. 顶部 destination 选择 **Wanli 的 iPhone 16**
3. 选中 scheme `Wuji` → Run（⌘R）
4. 首次安装后如提示「不受信任的开发者」：手机 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书

### B. 用命令行（签名已配置好时）
```bash
# 构建并安装
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'platform=iOS,id=00008140-001934312102801C' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008140-001934312102801C \
  "$(ls -d ~/Library/Developer/Xcode/DerivedData/Wuji-*/Build/Products/Debug-iphoneos/Wuji.app | head -1)"
xcrun devicectl device process launch --device 00008140-001934312102801C com.juejin.ios.wuji
```

## 3. 首次启动流程（必须逐项确认）
1. Onboarding 3 页 → Get Started
2. **本地网络权限弹窗** → 允许
3. **VPN 配置权限弹窗**（“WProxy 想要添加 VPN 配置”）→ 允许
4. 协议同意 → 主页
5. 添加节点（手动 / 粘贴 / 扫码）→ 保存
6. 主页点击 **连接**：
   - 状态变「已连接」、状态栏出现 VPN 图标
   - 打开 Safari 访问 `https://ip.sb` 或 `https://ipinfo.io`，出口 IP 应为节点服务器 IP
7. 断开 → VPN 图标消失，Safari 恢复本机 IP

> 如果权限失败页出现：按提示「重新请求」或「打开系统设置」；系统设置路径：
> 本地网络：设置 → 隐私与安全性 → 本地网络
> VPN 配置：设置 → 通用 → VPN 与设备管理

## 4. 必测功能矩阵
| # | 场景 | 操作 | 期望 |
|---|---|---|---|
| 1 | 锁屏保持 | 连接后锁屏 2 分钟再解锁 | 仍显示已连接，VPN 图标还在 |
| 2 | Wi‑Fi → 蜂窝 | 连接 Wi‑Fi 后关 Wi‑Fi、开 5G | 5–20 秒内自动重连（Always On-Demand） |
| 3 | 蜂窝 → Wi‑Fi | 反向操作 | 自动重连 |
| 4 | 飞行模式 | 开飞行模式 10 秒再关 | 自动重连 |
| 5 | 杀 App 保持 | 连接后上滑杀掉 Wuji | VPN 图标保持；重开 App 显示已连接 |
| 6 | 切换节点 | 已连接时选另一个节点 | 自动断开再重连，状态恢复已连接 |
| 7 | 改分流/DNS/语言 | 已连接时修改 | 自动重连生效 |
| 8 | 删除当前节点 | 删除正在使用的节点 | 自动断开，不再显示已连接 |
| 9 | 全局模式 | 开全局模式 | 局域网/所选国家也走代理 |
| 10 | 分流验证 | 规则模式选 CN/局域网 | 国内网站直连、国外走节点；局域网设备可访问 |
| 11 | DNS 两模式 | 远程 DoH / 本地 DNS 各测一次 | 均可打开网页，无 DNS 泄漏 |
| 12 | 权限被拒 | 系统设置关本地网络/删 VPN 配置后重开 App | 出现失败页，指引去设置 |
| 13 | 11 种语言 | 设置→语言逐个切换 | 立即生效，重启保持 |
| 14 | 订阅 | 添加真实 HTTPS 订阅 | 拉取节点、更新、删除 |
| 15 | 扫码/相册/分享 | 扫真实二维码、从相册识别、分享二维码 | 权限弹窗、识别/保存正常 |
| 16 | 清空数据 | 设置→清空数据 | 隧道断开、回引导页 |
| 17 | 长稳 | 连接 2–4 小时 | 不掉线、内存无持续增长、耗电可接受 |

## 5. 看日志/定位问题
- Xcode → Window → Devices and Simulators → 选中 iPhone → **Open Console**
  - 过滤 `com.juejin.ios.wuji`（主 App）和 `com.juejin.ios.wuji.tunnel-ext`（扩展）
- 或命令行收集：
```bash
log collect --device-name "Wanli的iPhone 16" --output /tmp/wuji-device.logarchive
open /tmp/wuji-device.logarchive
```
- 关键关键字：`TunnelController`、`PacketTunnelProvider`、`runXray`、`stopTunnel`、`on-demand`、`GeoIP`、`active_tunnel.json`
- 常见问题：
  - `saveToPreferences` / NEVPNErrorDomain 失败 → 门户 App ID 缺 Network Extension 或签名/描述文件不对
  - 隧道启动后立即断开 → 扩展日志看 `runXray`、utun fd、active_tunnel.json 是否有效
  - 本地网络权限弹窗不出现 → 检查 App ID/Info.plist 的 NSLocalNetworkUsageDescription + Bonjour
  - 连接成功但无法上网 → 节点是否真实可用、服务端是否封 IP、Xray 配置协议参数

## 6. TestFlight / 提审前
- Xcode → Product → Archive → Distribute App → App Store Connect → Upload
- App Store Connect → TestFlight 添加内部测试员，先装 TestFlight 包再测试一轮
- App Review 备注中提供**提审期间可用**的测试节点/订阅或示例二维码
- 中国区销售需要相应资质说明，写在 Review Notes
