# GeoIP 数据来源与许可署名（Wuji / 无极）

> 状态：2026-11-20。适用于 `Wuji/Resources/geoip.dat.gz`、`Wuji/Resources/geoip_countries.json`、
> App Group 内运行时下载/派生的 `geoip.dat`、`geoip_countries.json`、`wuji-geoip-<hash>.dat`，
> 以及生成脚本 `tools/prepare_geoip_assets.py`。

## 1. 数据链路

```
DB-IP Lite（db-ip.com，CC BY 4.0）
  └─ Project V / v2fly 每月编译 → https://github.com/v2fly/geoip（release 分支）
       ├─ geoip.dat              v2ray GeoIPList protobuf（253 个 list，23,876,117 B）
       ├─ geoip.dat.sha256sum    官方校验和
       └─ text/<cc>.txt          同数据的纯文本形式（离线兜底）
            ↓  Wuji 构建期（tools/prepare_geoip_assets.py，sha256 校验后）
       ├─ Wuji/Resources/geoip.dat.gz          gzip(geoip.dat) → 4,614,749 B
       └─ Wuji/Resources/geoip_countries.json  253 条 list 元数据（code → CIDR 数），2,758 B
            ↓  App 首次启动解压到 App Group
       geoip.dat + geoip_countries.json
            ↓  每次连接
       wuji-geoip-<hash>.dat    只抽取用户选中国家的原始 protobuf entry（Xray ext: 规则）
            ↓  每 7 天（VPN 已连接时）
       重新下载 geoip.dat + .sha256sum → 校验 → 原子替换
```

- 当前内置数据：`sha256 = eedb24b3b9fcba27e06b92c0428dab90d9496083091ae4cf39e11387fd99d0e2`
  （`dataVersion = eedb24b3b9fc`，生成日期 2026-11-20，上游 release tag 202611080027 / 2026-11-08）。
- 数据规模：253 个 list（250 个国家/地区 + `PRIVATE` 18 条 + `TEST` 1 条 + `ZZ` 5 条），
  合计 1,410,686 条 CIDR。
- 重要事实（2026-11-20 复核）：v2fly/geoip 的 release 构建**当前使用 DB-IP Lite 数据，已不再使用
  MaxMind GeoLite2**。证据：仓库 `master` 的 `.github/workflows/build.yml` 下载
  `dbip-country-lite-YYYY-MM.mmdb.gz`，`config.json` 的 input 只有 `dbipCountryMMDB` + `private` + `test`。
  README 的 License 一节同时写明 Project V 项目为 CC-BY-SA-4.0、DB-IP 数据为 CC-BY-4.0。
  因此本项目所有署名与文案**不得**再写 MaxMind/GeoLite2。

## 2. 许可与义务

| 对象 | 许可 | 说明 |
|---|---|---|
| DB-IP Lite 国家数据 | **CC BY 4.0** | 数据版权方 IP Geolocation data by DB-IP（https://db-ip.com） |
| v2fly/geoip 的编译产物（geoip.dat） | **CC BY-SA 4.0** | Project V 把 DB-IP 数据编译为 v2ray 格式 |
| Wuji 内置/运行时派生的数据文件（`geoip.dat.gz`、`geoip_countries.json`、`wuji-geoip-*.dat`、App Group 内的 `geoip.dat`） | **CC BY-SA 4.0** | 上述数据的改编/再分发，必须保留署名并以相同许可分发数据部分 |

义务：

1. **署名**：在 App 内「关于 → 开源许可」与本文档中标注 DB-IP（CC BY 4.0）与 Project V /
   v2fly/geoip（CC BY-SA 4.0），附许可证链接；保留 `geoip.dat.sha256sum` 作为版本凭据。
2. **相同方式共享**：数据文件（而非 App 源码）以 CC BY-SA 4.0 分发；App 代码本身不因此被要求采用
   CC BY-SA（数据与程序是独立作品，App 只是使用/再分发了数据）。
3. **不得暗示背书**：使用 DB-IP/v2fly 名称仅用于事实性署名，不得暗示其对本 App 的认可。
4. **修改声明**：Wuji 的修改 = 把 geoip.dat 打为 gzip、抽取元数据、按选择抽取 list 子集；
   这些派生文件同样以 CC BY-SA 4.0 提供。

## 3. App 内文案（由 Lead 接线到 About / 开源许可页）

英文（建议替换 `LicensesCatalog.regionDataAttribution`）：

```text
Country and region IP data bundled with Wuji comes from the GeoIP dataset
published by the v2fly project (Project V), which compiles the free DB-IP Lite
country database:

  - https://github.com/v2fly/geoip
  - https://db-ip.com

The v2fly compilation is distributed under the Creative Commons
Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0), and the
underlying IP geolocation data by DB-IP is distributed under the Creative
Commons Attribution 4.0 International License (CC BY 4.0):

  - https://creativecommons.org/licenses/by-sa/4.0/
  - https://creativecommons.org/licenses/by/4.0/

The GeoIP files bundled with this app and the per-connection extracts derived
from them are adaptations of that dataset and are made available under the same
CC BY-SA 4.0 license. The dataset is used only to decide, on the device, whether
a destination IP belongs to a region the user marked as direct.

Attribution: IP Geolocation data by DB-IP (https://db-ip.com), CC BY 4.0;
compiled and published by the v2fly project (https://github.com/v2fly/geoip),
CC BY-SA 4.0. No endorsement by DB-IP or Project V is implied.
```

中文（可选，跟随 UI 语言）：

```text
本 App 内置的国家/地区 IP 数据来自 v2fly 项目（Project V）发布的 GeoIP 数据集，
该数据集由免费的 DB-IP Lite 国家数据库编译而成：

  - https://github.com/v2fly/geoip
  - https://db-ip.com

v2fly 的编译产物以 CC BY-SA 4.0（知识共享 署名-相同方式共享 4.0 国际）分发，
底层 IP 归属地数据由 DB-IP 以 CC BY 4.0（知识共享 署名 4.0 国际）分发。
本 App 内置的 GeoIP 文件及运行时从中派生的数据文件同样以 CC BY-SA 4.0 提供。
该数据只在本机用于判断目的 IP 是否属于用户勾选为直连的地区。

署名：IP Geolocation data by DB-IP（https://db-ip.com），CC BY 4.0；
由 v2fly 项目编译发布（https://github.com/v2fly/geoip），CC BY-SA 4.0。
不代表 DB-IP 或 Project V 对本 App 的认可。
```

## 4. 合规检查清单

- [ ] App 内「关于 → 开源许可」出现 DB-IP + v2fly/geoip + CC BY-SA 4.0 与 CC BY 4.0 链接（Lead 接线）。
- [ ] 文案中不出现 MaxMind / GeoLite2（旧文案需替换）。
- [ ] 数据文件随 App 分发（geoip.dat.gz + geoip_countries.json），许可声明与文件同在。
- [ ] 运行时下载仅从 v2fly/geoip release 分支（HTTPS），下载内容经 sha256 校验后落盘。
- [ ] 不把数据作为独立商品售卖；App 为客户端工具。
- [ ] 若未来改用 MaxMind 官方数据，需重新评估许可（MaxMind GeoLite2 亦为 CC BY-SA 4.0，
      但需要 license key 下载，且本次已按用户指定的 v2fly 源实现）。
