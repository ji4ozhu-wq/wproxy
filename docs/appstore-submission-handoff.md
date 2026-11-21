# 更新发布到 App Store：需要你提供的信息

> 代码侧状态：Debug 真机版本已跑通；单元测试 117/117；Team `R6748V42K5`；
> 主 App `com.juejin.ios.wuji`（沿用旧记录），扩展 `com.juejin.ios.wuji.tunnel-ext`，
> App Group `group.com.youqu.wuji.appgroup`。
> 旧 App Store 记录：`id1448657437`。

## 0. 最关键：先确认旧 App 属于哪个 Team
旧 App 可能是 `KM56KD59W4`（手机里旧版的签名团队），而当前开发签名是 `R6748V42K5`。
**上传的构建只有和 App Store 记录属于同一个 Team，才能更新旧 App。**

请确认：
- [ ] App Store Connect → App → 无极代理，所属 Team 名称/ID
- [ ] 该 Team 是否就是 `R6748V42K5`（绍兴天穹）；如果不是，提供该 Team 的登录方式

## 1. 账号/上传授权（不要发密码）
三选一：
- [ ] **方式 A（推荐）**：你本人在 Xcode → Settings → Accounts 登录旧 App 所属 Team，之后我负责 Archive/Upload
- [ ] **方式 B**：App Store Connect → Users and Access → Integrations → App Store Connect API Key
  - 提供：Issuer ID、Key ID、`.p8` 文件路径（文件放本机，不要贴到聊天）
  - 角色：App Manager 及以上
- [ ] **方式 C**：你提供一台已登录 Xcode 的 Mac / 或你自己用 Transporter 上传

## 2. App Store Connect 后台状态
- [ ] Agreements, Tax, and Banking 全部 Active（付费 App 必须）
- [ ] App Store Connect 能打开旧 App 记录 `id1448657437`
- [ ] 当前账号有 App Manager / Admin 权限

## 3. 商店元数据（可我来写，需你拍板）
- [ ] 最终定价（付费档位）
- [ ] 中文名称：无极代理 / 無極代理；其他语言：WProxy
- [ ] 副标题、描述、关键词、宣传文本
- [ ] 分类（建议 工具 / Utilities）
- [ ] 年龄分级
- [ ] 版权信息
- [ ] 版本号 / 构建号（建议 1.0.0 / 1，或按旧记录顺延）
- [ ] 本次更新说明（Release Notes）

## 4. 必须公网可访问的 URL（本地 md 不算）
- [ ] 隐私政策 URL
- [ ] 用户协议 URL
- [ ] 支持/客服 URL（或邮箱）
- [ ] 市场推广 URL（可选）

## 5. App 隐私与合规
- [ ] App 隐私问卷：不收集数据、不追踪（我会按实际行为填）
- [ ] 出口合规：标准加密（TLS/HTTPS/VPN）申报
- [ ] 中国区资质说明（旧 App 上架时用的资质/说明，Review Notes 用）
- [ ] 是否保留旧 IAP 产品：保留、但新版本不接入

## 6. 审核测试材料（必需）
- [ ] 一个审核期间可用的真实节点：协议 / 地址 / 端口 / 凭据（或订阅 URL）
- [ ] 示例二维码图片（如用扫码路径）
- [ ] Review Notes：说明这是 BYO 服务器工具、如何添加节点并连接、分流怎么验证
- [ ] 审核联系人：姓名 / 邮箱 / 电话（可选）

## 7. 商店图片/图标
当前已有：
- [x] 1024 图标（已更新为最终玻璃 W + D1 深蓝）
- [x] 6.9 英寸 5 张图（1320×2868）
- [ ] `03-routing` 需要按当前「国家/区域」术语与 UI 重新生成（我可以做）
- [ ] 如果你有新文案/卖点要求，告诉我

## 8. 我可以直接完成的部分
- Release Archive / 导出 App Store IPA（签名配置好的情况下）
- 上传前校验（签名、entitlement、版本号、Privacy Manifest）
- 商店截图/图标整理与规格检查
- 提交填写信息草稿、Review Notes
- 上传命令（Xcode Organizer 或 Transporter/altool，取决于你选的授权方式）

## 9. 下一步
你至少先提供：
1. 旧 App 所属 Team 的确认（或登录方式/API Key）
2. 隐私政策/用户协议/支持 URL
3. 审核测试节点
4. 最终定价
5. 中国区资质说明

拿到这些后我可以先跑 Release Archive，再做上传前检查，最后上传 TestFlight/提交审核。
