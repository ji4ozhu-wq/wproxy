# 教训记录 — 无极 Wuji

## 引擎与平台

- **v2fly/v2ray-core 没有 iOS 官方封装**：一开始按用户原话选 v2fly 会卡在自建 gomobile 封装上；改为 XTLS/Xray-core + 官方 `XTLS/libXray` 后一次构建成功（`python3 build/main.py apple go`）。Xray 是 v2ray 的超集、配置同源，用户也认可改名。
- **NE 不允许模拟器**：Packet Tunnel 只能在真机验证，UI 层必须能在模拟器用 mock 状态跑通，否则无法做视觉验收。开发顺序：先 UI + 数据（模拟器），最后接真隧道。
- **utun fd 获取**：枚举 fd + `getpeername(AF_SYSTEM)` + `ioctl(CTLIOCGINFO)` 比对 `com.apple.net.utun_control` 是纯 POSIX 方案，不要用 KVC（审核风险）；拿到 fd 后不能再调 `packetFlow.readPackets`。
- **geoip 体积**：v2fly `geoip.dat` 约 23MB，塞不进 50MB 的 NE 扩展内存预算；改用 RIR 派生的国家 CIDR（按需生成 Xray routing 规则）。
- **libXray 体积**：全平台 xcframework 300MB；只保留 iOS 设备 arm64 + 模拟器 arm64 两个 slice 后 77MB。只把它链接进 NE 扩展，主 App 自己解析 URI/生成 JSON 以控制体积。

## 设计

- 用户先要“原生 UI”，进一步明确“纯系统默认风”。概念稿式设计（发光球、玻璃拟态、自定义字体）会被否决；直接用 SwiftUI 系统组件 + 系统语义色最稳。
- AI 生图做多屏 UI 时 tab bar / 导航栏容易漂移：提示词里必须显式写死“底部 tab 恰好三项：Connect / Nodes / Settings”，否则每张图都可能出现不同的 tab 组合。
- 竖版画布生成 iPad/Duo 横屏布局会裁切：宽屏设计必须用 landscape 画布（1536x1024）单独生成。

## 工程

- XcodeGen 生成的工程不自动收录新文件：teammate 新增文件后必须 `xcodegen generate`；并发时可能撞车，重试即可。
- NE 扩展 Info.plist 必须显式写 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，否则出现 appex CFBundleVersion=null 的校验 warning。
- 多 teammate 并行时按目录/文件切分写权限；共享层接口（AppState / 协议）由 Lead 先定义，避免互相改同一文件。
