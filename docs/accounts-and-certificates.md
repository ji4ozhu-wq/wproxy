# 旧开发者账号登录 + 证书导出/自动签名指南

> 背景：旧 App（无极代理，`id1448657437`）属于**另一个 Apple Developer 团队**（很可能是「绍兴天穹网络科技有限公司」组织团队），
> 这台 Mac 之前从未登录过该团队；本机工程当前 Team 是 `R6748V42K5`（Wanli Zhang 个人团队）。
> 更新旧 App 必须用**旧 App 所属团队**签名；证书不需要沿用旧 Mac 的，可以在这台 Mac 上重新生成。

## 一、在这台 Mac 登录旧账号（必须）

1. 打开 Xcode → Settings（⌘,）→ **Accounts**
2. 左下角 **+** → Apple ID → 输入旧账号邮箱/密码（2FA 由你本人输入）
3. 登录成功后左侧会出现多个 Team（如有），选中**组织团队**（绍兴天穹网络科技有限公司 / 对应 Team ID）
4. 选中团队 → 右侧 **Download Manual Profiles**（自动签名时也会拉取）
5. 验证：
   ```bash
   security find-identity -v -p codesigning
   xcodebuild -project Wuji.xcodeproj -scheme Wuji -showBuildSettings | grep DEVELOPMENT_TEAM
   ```
   - `security find-identity` 里应出现该团队的 `Apple Development` / `Apple Distribution`
   - 若 Team ID 不是 `R6748V42K5`，告诉我，我会改工程

## 二、登录后必须去门户开能力（否则装不上）

developer.apple.com（用同一账号）→ Certificates, Identifiers & Profiles：

1. **Identifiers → App IDs**
   - `com.juejin.ios.wuji` → Edit → 勾选 **App Groups** + **Network Extensions（Packet Tunnel Provider）**
   - `com.juejin.ios.wuji.tunnel-ext` → 同样
2. **Identifiers → App Groups**
   - 确认/创建 `group.com.youqu.wuji.appgroup`，并关联到上面两个 App ID
3. 回到 Xcode → Settings → Accounts → 选中团队 → **Download Manual Profiles**
4. 然后告诉我，我执行真机构建/安装

> 若你的账号角色不是 Account Holder/Admin，可能看不到能力开关或无法创建 App Group；
> 需要在 App Store Connect / 开发者门户把角色提升为 Admin，或让账号持有人操作。

## 三、证书要不要“从旧电脑导出”？

**不需要沿用旧证书也能更新旧 App。** 两种方案：

### 方案 A（推荐）：Xcode 自动签名，新证书在这台 Mac 生成
- 登录账号 + 选对 Team + 勾选 Automatic Signing
- Xcode 首次 Archive 时会自动创建/下载 `Apple Distribution` 证书和 App Store 描述文件
- 旧证书继续有效，不影响旧版本；一台机器多张证书是正常的

### 方案 B：确实要导出旧 Mac 的证书（备份/换机/CI）
在旧 Mac 上：
1. 打开 **Keychain Access → 登录 → My Certificates**
2. 找到 `Apple Distribution: ...` 或 `Apple Development: ...`，展开确认包含**私钥**
3. 右键 → **Export Items…** → 存为 `.p12`，设置导出密码
4. 同时把 provisioning profile 从 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` 或门户下载出来

在新 Mac（这台）上：
1. 双击 `.p12` → 输入密码导入「登录」钥匙串
2. 双击 `.mobileprovision` 安装（或放回 Xcode Profiles 目录）
3. Xcode → Settings → Accounts 登录账号 → Download Manual Profiles
4. 验证 `security find-identity -v -p codesigning` 能看到对应证书

### 用命令行导出（可选，需输入密码）
```bash
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 \
  -o ~/Desktop/Wuji-Signing.p12
```
> 注意：只导出证书（.cer）没有意义，必须带私钥；`.p12` 含私钥，妥善保管，不要发到聊天/仓库。

## 四、门户手动创建证书（如果自动签名不行）
1. Keychain Access → Certificate Assistant → **Request a Certificate From a Certificate Authority**
   - 邮箱填账号邮箱 → 选 **Saved to disk** → 存 `.certSigningRequest`
2. developer.apple.com → Certificates → **+** → Apple Distribution（或 Apple Development）
3. 上传 CSR → 下载 `.cer` → 双击安装到钥匙串
4. Certificates → Profiles → **+** 创建 App Store 描述文件，选择对应 App ID + 证书 + 设备（开发用）
5. 下载 profile 双击安装；或 `xcodebuild -allowProvisioningUpdates` 自动生成

## 五、验证签名是否可用
```bash
cd /Users/zhang/VC/app_src/wuji
xcodebuild -project Wuji.xcodeproj -scheme Wuji -configuration Debug \
  -destination 'platform=iOS,id=00008140-001934312102801C' \
  -allowProvisioningUpdates build
```
- 成功：`BUILD SUCCEEDED`，产物在 `Build/Products/Debug-iphoneos/Wuji.app`
- 失败：把 `error:` 行发我，通常是 Team 不对/能力没开/描述文件过期
