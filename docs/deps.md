# 依赖清单 — 无极 Wuji

## 运行期依赖

| 依赖 | 版本 | 来源 | 用途 | 许可 |
|---|---|---|---|---|
| Xray-core | latest master（构建时锁定提交） | https://github.com/XTLS/Xray-core | 代理内核（VMess/VLESS/Trojan/Shadowsocks、TLS/REALITY、tun inbound） | MPL-2.0 |
| libXray | latest master | https://github.com/XTLS/libXray | Xray 的 iOS 静态封装（`Invoke` JSON API） | MIT |
| GeoIP 数据集（`geoip.dat`） | v2fly/geoip release 202611080027（2026-11-08） | https://github.com/v2fly/geoip（release 分支）；底层数据 DB-IP Lite | 国家/地区分流：App 只抽取选中国家的 list，交给 Xray 用 `ext:<file>:<cc>` 运行时匹配 | 编译产物 CC BY-SA 4.0；DB-IP Lite 数据 CC BY 4.0（署名见 `docs/licenses-geoip.md`） |
| SQLite | 系统自带 | libsqlite3（系统） | 本地存储 | Public Domain |
| CryptoKit / Compression / Network | 系统自带 | Apple SDK | sha256 校验、gzip 解压、网络状态 | 系统框架（无第三方代码） |

- `Frameworks/LibXray.xcframework`：iOS 设备 arm64 + 模拟器 arm64 两个 slice（构建脚本 `tools/build_libxray.sh`），只链接到 NE 扩展 target（主 App 不链接，控制体积）。
- 主 App 不引入任何第三方 Swift 包；UI 用 SwiftUI / Foundation / Network / AVFoundation / NetworkExtension / PhotosUI。

### GeoIP 数据资产与更新机制

- **不再把 CIDR 展开进 Xray 配置**。全量 DB-IP 派生数据有 1.41M 条前缀（JSON 约 26 MB），而 Xray-core
  原生支持读 `geoip.dat` 并通过路由规则 `ext:<file>:<code>` 运行时匹配；Xray 只看被规则引用的 list。
  因此 App 内置原始 `geoip.dat`，连接时把选中国家的 protobuf entry 原样拼成很小的 per-connection 资产。
- 内置资源（`Wuji/Resources/`，构建期由 `tools/prepare_geoip_assets.py` 生成）：
  - `geoip.dat.gz`：完整 v2ray GeoIPList protobuf（原始 23,876,117 B），gzip 后 4,614,749 B（4.40 MB）；
    sha256 `eedb24b3b9fcba27e06b92c0428dab90d9496083091ae4cf39e11387fd99d0e2`，`dataVersion=eedb24b3b9fc`。
  - `geoip_countries.json`：253 个 list 的元数据（`code → CIDR 数`，2,758 B），供国家选择与计数显示。
  - 数据规模：250 个国家/地区 + `PRIVATE` 18 / `TEST` 1 / `ZZ` 5，合计 1,410,686 条 CIDR；
    重点国家：CN 15,189 / JP 38,106 / US 271,874 / DE 55,789 / GB 63,134 / SG 62,692 / HK 18,572 / TW 10,823 / KR 4,996。
- App Group（`group.com.juejin.ios.wuji`）运行时文件：
  - `geoip.dat`（23.8 MB，首次启动由 bundle gz 解压）、`geoip_countries.json`（元数据）、
    `geoip_meta.json`（lastUpdatedAt / dataVersion / source / etag / lastError / isUpdating 等状态）、
    `wuji-geoip-<hash>.dat`（每次连接按选中国家的 entry 抽取，保留最近 3 个，CN ≈ 0.23 MB / US ≈ 3.97 MB）。
  - 扩展进程通过 `xray.location.asset` 指向该目录读取资产；文件名带数据版本 hash，避免同进程 Xray
    matcher 缓存旧数据。
- 更新：`GeoIPUpdater` 在 App 启动/回前台/隧道状态变化时检查；**距上次更新超过 7 天且 VPN 已连接**
  （此时系统流量经代理，GitHub/jsDelivr 可达）才下载 `geoip.dat` + `.sha256sum`（jsDelivr 优先、
  raw.githubusercontent 备用，HTTPS，60 s 超时），sha256 校验通过后原子替换；失败保留旧数据并记录
  `lastError`（设置页可见），之后每 1 小时重试一次（固定间隔）直到成功，断开 VPN 时暂停重试。
- 国内网络注意：jsDelivr / raw.githubusercontent 在中国大陆网络通常不可达，自动更新只在「已连接的
  代理网络」或海外网络下有效；失败时继续使用内置数据，不影响分流功能。后续若要国内可用需自建镜像。

### 许可与署名

GeoIP 数据的来源与许可（v2fly/geoip CC BY-SA 4.0 + DB-IP Lite CC BY 4.0）以及 App 内署名文案，
见 `docs/licenses-geoip.md`；App 内「关于 → 开源许可」需按该文档接线（Lead 负责），文案中不得出现
MaxMind / GeoLite2。

## 开发期工具

| 工具 | 用途 |
|---|---|
| XcodeGen | 从 `project.yml` 生成 `Wuji.xcodeproj`（新增 Swift 文件后需重跑一次） |
| go + gomobile/cgo | 构建 LibXray.xcframework（`tools/build_libxray.sh`） |
| Python3（标准库） | 生成/校验 GeoIP 资源（`tools/prepare_geoip_assets.py --from-dir /path/to/geoip.dat` / `--check`）、设计图与商店图脚本 |

- 开发机访问 GitHub 需 socks5 代理（仅开发期下载数据用，不写进代码/产物）：
  `export HTTPS_PROXY=socks5h://<host>:<port> ALL_PROXY=socks5h://<host>:<port>`；脚本用 curl，自动读取该环境变量。
- 离线复现：`python3 tools/prepare_geoip_assets.py --from-dir /tmp/geoip-src`（目录内放 `geoip.dat` 与
  可选 `geoip.dat.sha256sum`；若只有 `text/<cc>.txt` 会现场拼出 protobuf）。

## 构建环境

- Xcode 27.2 / macOS 26.7.1
- Go 1.26+（构建 libXray 时自动使用 go1.27.3 工具链）
- Development Team：C544N77LD9
