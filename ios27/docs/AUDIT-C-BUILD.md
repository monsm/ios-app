# AUDIT-C-BUILD · ios27 编译与交付风险审计

> 审计立场：默认“有遗漏”，只报有证据的问题。  
> 审计快照：2026-10-31 20:40 +08:00，`HEAD = 1f87607`（工作树另有 14 个未提交修改；审计期间有并发修复），`App` 下 148 个 `.swift`。  
> 限制：本机是 Windows，没有 xcodebuild；真编译结论取自同一 commit 的 GitHub Actions run **41201710690** 的 job/annotation。未修改被审计源码，只新增本报告。

## 结论（先看这一段）

1. **当前 HEAD 真编译失败**：GitHub run 41201710690 的 `gates` job 绿，`build` job 在第 6 步 `编译（整模块单次调用…）` 红，Archive/Release 被跳过；annotation 给出 5 条编译错误（见 C-01）。这不是“可能”，是已经发生的事实。
2. **本地 `node Gates/allgates.js` 仍报 15/15 通过**；这 5 条错误没有一条被静态闸门挡住（见 C-02 / R-04）。
3. 旧工程已有的 **AppIcon / PrivacyInfo / kf:// URL scheme / bluetooth-central 后台模式** 没有搬进 `ios27/project.yml`；这些不阻止 CI 编译，但会让产物缺图标、App Store 隐私申报失败、深链失效、DFU 后台被挂起（见 C-03 ~ C-06）。
4. 当前 Release 里仍有 **3 个 IPA**，`docs/COMPLETION.md` 指向的是旧资产；当前 v7 代码没有成功产出新 IPA（见 C-08）。

---

## 一、一定失败（已由真编译或可复现命令证明）

### C-01 当前 HEAD 的 5 条编译错误（CI build job 已红）

证据：run [41201710690](https://github.com/monsm/ios-app/actions/runs/41201710690)，commit `1f87607`；job「编译（iOS 27 SDK）」第 6 步失败，第 7 步 Archive、第 9 步 Release 均 skipped。GitHub annotation 原文（节选；**表内行号均指 1f87607，本地快照已修复，见下方补充**）：

| # | 文件:行:列 | 编译器错误 | 本地核对 |
|---|---|---|---|
| 1 | `App/Features/Door/DoorScreen.swift:180:29` | `value of type 'StatusSnapshot' has no member 'sKeyStatus'` | 第 180 行确实是 `app.lastStatus?.sKeyStatus`；`StatusSnapshot` 只有 `at` / `status` 两个成员，`sKeyStatus` 在 `StatusSnapshotData` 上（`Engine/StoreModels.swift:191-207`、`:211-223`） |
| 2 | `App/Features/Door/DoorScreen.swift:555:68` | `value of type 'StatusSnapshot' has no member 'lockTime'` | 第 555 行 `$0.lockTime` 同样少了一层 `.status` |
| 3 | `App/Features/Settings/BackupStudioScreen.swift:430:73` | `call to main actor-isolated static method 'collectAll()' in a synchronous nonisolated context` | `SelfCheck.fingerprint()` 不是 `@MainActor`；`BackupKit` 是 `@MainActor enum`（`Engine/BackupKit.swift:166-168`） |
| 4 | `App/Engine/AutoOpenKit.swift:353:99` | `missing argument label 'mac:' in call` | 第 353 行 `Self.doorName(mac)`；声明是 `static func doorName(mac: String)`（同文件 `:426`） |
| 5 | `App/Shell/AppModel.swift:445:51` | `cannot convert value of type 'Int' to expected argument type 'UInt32'` | 第 445 行 `fpDelete(batch)`；签名是 `func fpDelete(_ batchNumber: UInt32)`（`Engine/LockServiceCredentials.swift:211`） |

**补充（审计快照的未提交工作树）**：上述 5 处已经在工作树中出现对应修复——`DoorScreen.swift:180/555` 改成 `.status.…`、`BackupStudioScreen.swift:429` 给 `fingerprint()` 加 `@MainActor`、`AutoOpenKit.swift:353` 改成 `doorName(mac: mac)`、`AppModel.swift:446` 改成 `fpDelete(UInt32(batch))`。但这些修改尚未提交，也没有新的 CI run；**不能把“本地已改”当成“已通过”**。

**后果**：1f87607 这个 commit 不可能产出新 IPA；任何依赖“CI 已通过”的交付声明都不成立。  
**最小修法**：
- 1/2：`app.lastStatus?.status.sKeyStatus`、`app.lastStatus?.status.lockTime`（或给 `StatusSnapshot` 加转发属性，但不要在 UI 里再写错一层）。
- 3：`SelfCheck.fingerprint()` 标 `@MainActor`，或把 `BackupKit.collectAll()` 调用移进 `Task { @MainActor in ... }` / 让 `SelfCheck` 整体 `@MainActor`。
- 4：`Self.doorName(mac: mac)`。
- 5：`fpDelete(UInt32(batch))`（并确认 batch 在 0...UInt32.max 内；或把 `fpDelete` 参数改成 Int 并做一次显式转换）。

### C-02 静态闸门 15/15 全绿，但没有挡住上面 5 条真编译错误

实测（当前快照）：

```text
$ node Gates/allgates.js
swiftparse: OK — 148 个 Swift 文件无语法错误（已知语法盲区豁免 14 处）
types: 148 个文件，364 个顶层类型，SDK 白名单 332 项
swiftcheck: OK — 148 个文件括号/字符串/注释全部平衡
tokens: OK — 148 个 Swift 文件，0 处硬编码样式字面量（含 V7 字号/色板）
contrast: 解析到 11 个旧色令牌 × 2 模式 + 57 个 V7 色令牌
glass: 扫 148 个文件，自定义玻璃面 0 处
motion: 扫 148 个文件，.animation 调用 13 处
a11y: 扫 148 个文件
dynamictype: 148 个文件，761 处走令牌字号（其中 V7 761 处经 VFont/@ScaledMetric）
reducedmotion: 21 处已守卫
crosprivate: 检查 7 组 Screen+Parts 拆分
callsig: 跟踪 14 个组件，检查 0 处具名调用
lineage: OK — 148 个文件，0 处上一版设计系统残留
workflow: 检查 1 个文件
destmap: Dest 44 项，映射 44 项，已声明 View 146 个

allgates: 全部 15 道闸门通过
```

为什么漏：
- `Gates/types.js:89-103` 的“未解析类型引用”只扫 `rel.startsWith('Engine/')`，UI 层的 `StatusSnapshot.sKeyStatus` 这类成员错误完全不在范围内；
- 没有 Swift 类型检查，`AutoOpenKit` 的参数标签、`AppModel` 的 Int/UInt32、`BackupStudio` 的 actor 隔离都不会被括号/语法闸门发现；
- `Gates/callsig.js` 本次输出 `检查 0 处具名调用`，与旧文档“201 处”差异巨大，至少说明该闸门对当前 V7 组件调用没有有效覆盖（见 R-04）。

---

## 二、可能失败（构建可过，但产物/功能/上架会出问题）

### C-03 没有 Assets.xcassets，AppIcon 配置指向不存在的目录

- `project.yml:38`：`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`
- 实测：`ios-app/ios27` 下 `**/*.xcassets/**` = **0 条**；`App/` 只有 `Design/ Engine/ Features/ Shell/` 和 `LockKeeperApp.swift`，没有资源目录。
- 对照旧工程：`ios-app/App/Assets.xcassets/AppIcon.appiconset` 存在（另有 8 个备选图标 set）。
- 影响：`xcodebuild archive` 可能只报 warning，但产物没有 AppIcon；App Store 会因缺主图标被拒。旧 CI 在 e45c804 也确实能在无 assets 的情况下 archive 成功，所以这不是“编译必红”，是“产物缺失/上架必红”。

### C-04 没有 PrivacyInfo.xcprivacy，而代码确实使用 Required Reason API

- 实测：`ios-app/ios27` 下 `**/PrivacyInfo.xcprivacy` = **0 条**。
- 旧工程有完整清单：`ios-app/App/PrivacyInfo.xcprivacy:32-50`，声明 `NSPrivacyAccessedAPICategoryUserDefaults`（CA92.1）和 `NSPrivacyAccessedAPICategoryFileTimestamp`（C617.1）。
- 新代码使用点：
  - `App/Engine/Store.swift:8`：`private let defaults = UserDefaults.standard`
  - `App/Features/Settings/BackupStudioScreen.swift:259-263`：`contentModificationDateKey` / `resourceValues`
- 影响：App Store Connect 的 Required Reason API 检查会要求清单；旧工程已写明“缺失会被 App Store 拒收”，新工程没有搬。

### C-05 没有 CFBundleURLTypes，但代码仍在处理 kf:// 深链

- `App/LockKeeperApp.swift:54-77`：`.onOpenURL` 中 `guard url.scheme == "kf"`，并按 `device/credentials/records/settings` 路由。
- `project.yml:42-60` 的 `info.properties` 没有 `CFBundleURLTypes`；旧工程 `ios-app/project.yml:56-59` 有 `CFBundleURLName: kf.lockkeeper.deeplink` / `CFBundleURLSchemes: [kf]`。
- 影响：系统不会把 `kf://` 交给这个 App，深链功能等于不存在（不影响编译，但功能“一定失败”）。

### C-06 没有 UIBackgroundModes(bluetooth-central)，DFU/配网在后台可能被挂起

- 新 `project.yml` 全文没有 `UIBackgroundModes`；旧工程 `ios-app/project.yml:53-54` 有 `bluetooth-central`，注释明确写“DFU 是几分钟的 BLE 传输”。
- 新代码 `App/Features/Door/DFUScreen.swift:251`：`BackgroundGuard.run("固件刷写") { try await session.run() }`；`BackgroundGuard` 只是 `beginBackgroundTask`（约 30 秒，`Engine/BackgroundGuard.swift:23`），不是无限后台。
- 影响：DFU 中途锁屏/切后台可能被系统挂起，锁停在半完成态；这是“变砖风险”，不是编译错误。

### C-07 CFBundleVersion 固定为 "1"，没有构建号注入

- `project.yml:47`：`CFBundleVersion: "1"`。
- 旧 `ios.yml` 有 stamp 作业并在 generate 后注入 `CFBundleVersion`；新的 `ios27.yml` 没有 stamp，项目里也没有版本号替换。
- 影响：所有 IPA 的 CFBundleVersion 都是 1；安装台/AltStore 无法靠版本号区分新旧，App Store 也不能重复上传同 build number。

### C-08 Release 产物与文档不一致：3 个 IPA，文档指向旧包

GitHub Release `ios27-latest` 实测（API）：

| 资产 | 大小 | 创建时间 (UTC) |
|---|---:|---|
| `LockKeeper-20261031.112404-unsigned.ipa` | 1,208,041 | 2026-10-31T03:24:07Z |
| `LockKeeper-20261031.112907-unsigned.ipa` | 1,208,041 | 2026-10-31T03:29:10Z |
| `LockKeeper-20261031.130056-unsigned.ipa` | 1,213,780 | 2026-10-31T05:00:58Z |

- `README.md:41` 仍写“每次构建只保留最新一个”，实际是 3 个；
- `docs/COMPLETION.md:124` 直链的是 `112404`（最旧的一个），不是最新的 `130056`；
- 最新资产 `130056` 是 e45c804（113 文件）时构建的；当前工作树（148 文件、v7）在 1f87607 的 CI build 已经红（C-01），没有新 IPA 上传。
- 影响：用户按文档下载到旧包；v7 的界面改动没有进入可安装产物。

### C-09 未提交文件 / Destinations 依赖（已修复，保留回归检查）

- 审计早期这 5 个文件确实是 untracked：`DeviceInfoScreen.swift`、`DoorLayout.swift`、`ModuleOrderSheet.swift`、`UnlockGateScreen.swift`、`AlarmKindsSheet.swift`；而 `App/Shell/Destinations.swift:29-31,44` 已引用它们。
- 1f87607 已把这 5 个文件纳入 tracked；审计快照的 `git status` 里没有 untracked Swift，只有 14 个未提交修改。
- 仍要防的回归：当前工作树有 14 个未提交修改；如果只提交部分文件，Destinations 会引用不存在的 View。提交前用 `git status` + `node Gates/destmap.js` 对账。

### C-10 Bundle ID 从旧工程默认值改成新值，升级/钥匙串数据不连续

- 旧 `ios-app/project.yml:4` 目标名 `OfflineLock`，`:6` `bundleIdPrefix: com.aapk`，没有显式 `PRODUCT_BUNDLE_IDENTIFIER`；按 XcodeGen 默认推导为 `com.aapk.OfflineLock`。
- 新 `ios27/project.yml:36` 显式 `PRODUCT_BUNDLE_IDENTIFIER: com.aapk.lockkeeper`。
- 代码里仍残留旧 bundle id：`Engine/CredentialOrg.swift:29`（Logger subsystem `com.aapk.OfflineLock`）、`Engine/SecretStore.swift:20`（Keychain service `com.aapk.OfflineLock.secrets`）。
- 影响：如果目标是覆盖升级旧 App，bundle id 不同 = 装成两个 App，旧数据/钥匙串不会自动继承；如果不是目标，应删掉旧 id 残留并明确“全新安装”。

### C-11 本地 Xcode 真机签名没有 DEVELOPMENT_TEAM

- `project.yml:24`：`CODE_SIGN_STYLE: Automatic`，全文件没有 `DEVELOPMENT_TEAM`。
- CI 的 build/archive 都传 `CODE_SIGNING_ALLOWED=NO`（`ios27.yml:107,119`），所以 CI 能绕过；但 `README.md:66-67` 让用户本地 `xcodebuild build ...`（虽然也带 `CODE_SIGNING_ALLOWED=NO`），真要装到设备仍需在 Xcode 里选 team。
- 影响：本地真机调试/签名安装会停在 “requires a development team”；不阻断 CI，但阻断 README 的“真机跑一遍”路径。

### C-12 显式 import 缺失（依赖隐式/wholemodule，环境一变就红）

静态扫描结果（只列“文件没有显式 import 但使用了该模块符号”）：

| 文件 | 使用 | 现有 import | 说明 |
|---|---|---|---|
| `App/Engine/AppLock.swift:20,24` | `ObservableObject` / `@Published` | 只有 `Foundation` + `CryptoKit`（`:16-17`） | `ObservableObject`/`@Published` 属 Combine；旧 CI 在 wholemodule 下碰巧通过，单文件/增量编译可能报 cannot find type |
| `App/Design/Tokens.swift:149` | `UIColor` | 只有 `SwiftUI`（`:7`） | 依赖 SwiftUI 对 UIKit 的隐式暴露；建议显式 `import UIKit` |
| `App/Engine/FrameRedact.swift:15` | `String.range(of:)` | 文件没有任何 import | `range(of:)` 是 Foundation 扩展；当前文件只有标准库类型，建议补 `import Foundation` |

这三处没有被当前 CI 的 5 条错误列出（说明当前 wholemodule 构建把它们带过了），但它们是**可移植性风险**：换 Xcode 版本、改增量编译、或把文件单独抽出去就会红。审计口径：**不是当前 5 条失败项，但应补显式 import**。

### C-13 权限/合规文案与实际能力不一致

- `project.yml:58` 有 `NSCameraUsageDescription`，但全仓没有 `AVCapture`/`UIImagePickerController`/相机扫码消费方（`camera` 仅作为 SF Symbol 字符串出现在 `CredentialStudioParts.swift:173,202`）；旧工程 `:70-73` 明确把相机键删掉，理由是“声明未使用能力会被 App Store 问询”。
- `project.yml:54` 的蓝牙文案写“App 不联网、不上传任何数据”，但 `App/Features/Settings/BackupStudioScreen.swift:443,459` 使用 `URLSession` 做 WebDAV PROPFIND/PUT；文案与实际能力不一致。
- `project.yml:60` `ITSAppUsesNonExemptEncryption: NO`，而 `Engine/AESKit.swift` 使用 CommonCrypto AES-128-ECB；出口合规问卷应人工确认，不能直接按 NO 交。

### C-14 WebDAV 的 HTTP/本地网络配置缺失

- `BackupStudioScreen.swift:468` 接受 `http://` 前缀；`project.yml` 没有 `NSAppTransportSecurity` 例外，iOS 默认 ATS 会拦截明文 HTTP。
- 若用户填局域网地址（如 `192.168.x.x`），还缺 `NSLocalNetworkUsageDescription`；WebDAV 功能会静默失败或弹不出本地网络授权。
- 影响：备份工作室的“WebDAV 同步”在真实网络环境下大概率不可用（不是编译失败）。

---

## 三、风险（当前可编译/可运行，但会反噬）

### R-01 Swift 6 并发迁移债（当前 5 条错误里已经有一条 actor 错误）

- `project.yml:21-22`：`SWIFT_VERSION: "5.0"` + `SWIFT_STRICT_CONCURRENCY: complete`；`:41` `SWIFT_TREAT_WARNINGS_AS_ERRORS: NO`。这意味着并发问题大多只是告警；一旦切 6.0 会成片变红。
- 4 个 `@Observable` 类没有 `@MainActor`：
  - `App/Shell/Router.swift:173`
  - `App/Features/Records/RecordsModels.swift:155`（`RecordsOverlay`）
  - `App/Features/Records/RecordsModels.swift:314`（`RecordsRoute`）
  - `App/Features/Settings/SettingsModel.swift:129`（`SettingsStore`）
- 3 个非 Sendable 的全局 `static let shared`：
  - `SettingsModel.swift:131`
  - `RecordsModels.swift:157`
  - `RecordsModels.swift:316`
- `App/Design/Components/CaptureShield.swift:9-20`：`CaptureWatcher: ObservableObject` 非 `@MainActor`，在 `NotificationCenter` 的 `@Sendable` 回调里捕获 `self` 并写 `@Published`；Swift 6 下是典型 non-Sendable capture。
- 正面：全仓 `Task.detached` = 0、`nonisolated(unsafe)` = 0，说明迁移没有用“关检查”换绿；但上述 4+3 个点是明确的待办。
- 影响：当前 5 条编译错误里的 `BackupStudioScreen:430` 已经是同类 actor 错误；不先修并发边界，切 Swift 6 时会出现一批同类错误。

### R-02 iOS 27 专有 API 名称扫描：未发现“假 API”，但部署目标抬高了兼容成本

实测：
- `.scrollEdgeEffectStyle` 25 处（iOS 26 引入，27 可用）；
- `@Entry` 1 处（`Dial.swift:183`，iOS 18+）；
- `@Observable` 8 处、`ShareLink` 9 处、`ImageRenderer` 2 处，均为 iOS 16/17 API；
- 未发现 `glassEffect` / `Tab(role:)` 等无法确认的 iOS 27 名字。

结论：没有证据表明存在“iOS 27 专有 API 名称写错”导致的编译错误；但 `deploymentTarget: 27.0` 会让所有 iOS 26.x 设备装不上，这是产品/分发决策，不是编译问题。

### R-03 #Preview 依赖

- 32 个 `#Preview`；抽查 `Shell`、`DeviceInfoScreen`、`BackupStudioScreen` 等预览都补了 `.environment(AppModel())` / `.environment(Router())`（如 `LockKeeperApp.swift` 的 `#Preview` 不涉及；`DeviceInfoScreen.swift:402-404` 有）。
- 未发现 `#Preview` 依赖缺失导致的编译错误；预览是 DEBUG 期工具，当前 build job 也不执行 UI，不能替代真机验证。

### R-04 闸门覆盖不足/可能假绿

- `Gates/types.js:89-103` 只检查 Engine 的类型引用；UI 层类型/成员错误不查。
- `Gates/swiftparse.js:13-19`：`tree-sitter` 未安装时直接 `SKIP` 并 `exit 0`；如果 CI 的 native 依赖装上了但加载失败，swiftparse 会假绿（当前 CI 安装步骤成功，但这是结构性风险）。
- `Gates/callsig.js` 当前输出 `检查 0 处具名调用`，与旧文档 `204 处` 差距过大；说明 V7 组件调用没有被有效覆盖（或该 gate 已退化为 no-op）。
- `Gates/workflow.js:35-49` 只检查 `run: |` 的缩进，不解析 YAML、不检查 `with:` 块；历史上 0df0ec3 的非法 workflow 就是这样通过本地 gate 的（见附录 R-05）。

### R-05 文档/交付证据与当前树不一致

实测当前：**148 个 Swift、34,417 行、1,633,320 字节**；`Gates/types` 364 个顶层类型、`destmap` 44 Dest / 146 View、allgates 15 道。  
文档仍写：`README.md:11` 113 文件 / 1.12 MB、`:55` 9 道、`:83` 11 道、`:103` 113 文件；`docs/COMPLETION.md:13-14` 113 文件 / 21,775 行、`:69` 26 Dest、`:146` run 41161655697。  
当前 run 41201710690 是 failure；最后一次成功的 ios27 build/archive 是 41170697979（commit e45c804，113 文件）。**“CI 已通过”只对旧树成立，对当前 148 文件树不成立。**

### R-06 发布/版本流程

- Release 清理逻辑在 `ios27.yml:155-162` 才刚修复；此前 `d71c6f9` 的 workflow 是非法 YAML，导致 41171707124 / 41199640021 两次 run 的 jobs=0；当前虽然修好，但 Release 里仍遗留 3 个 IPA（C-08）。
- `CFBundleVersion` 固定为 1（C-07），与“只保留最新一个”的资产策略叠加，用户无法从版本号确认安装的是哪一版。

---

## 四、实测记录（可复跑）

### 4.1 Gates

```text
$ cd D:\aapk\ios-app\ios27
$ node Gates/allgates.js
...（15 行输出，见 C-02）...
allgates: 全部 15 道闸门通过
```

- `node Gates/swiftparse.js`：`OK — 148 个 Swift 文件无语法错误（已知语法盲区豁免 14 处）`。
- 独立“未换源”的 tree-sitter 解析（同一 `tree-sitter-swift`，不执行 gate 的 3 类替换）会报 7 个文件有 ERROR/MISSING 节点：

```text
Shell\AppModel.swift                 ERROR=92 MISSING=5
Engine\LockServicePairing.swift      ERROR=20 MISSING=0
Features\Settings\HardwareScreen.swift ERROR=2 MISSING=1
Engine\LockServiceOps.swift          ERROR=2 MISSING=0
Features\Door\DeviceInfoScreen.swift ERROR=1 MISSING=1
Engine\BLEDelegates.swift            MISSING=1
Features\Keys\KeyDetailScreen.swift MISSING=1
```

逐一核对：这些是 `if let x = try? await ...`、`cb?(.success(()))`、`.success(())` 的 grammar 盲区，不是真实 Swift 语法错误；gate 的 `swiftparse.js:52-72` 用换源处理，处理后可解析。**没有发现真正的语法失败文件**；但这说明“raw parser 报错文件”不能直接当作编译失败清单。

### 4.2 工程/文件计数

```text
App/**/*.swift : 148 files, 34,417 lines, 1,633,320 bytes
project.yml    : 68 lines（无 Assets.xcassets / PrivacyInfo.xcprivacy / CFBundleURLTypes / UIBackgroundModes）
Gates          : allgates 15 道（README 写 9/11 道）
```

### 4.3 CI（GitHub Actions API）

| run | commit | 结果 | 关键事实 |
|---|---|---|---|
| 41201710690 | 1f87607 | failure | gates job success；build job step 6 failure；Archive/Release skipped；5 条 annotation 见 C-01 |
| 41170697979 | e45c804 | success | 最后一次 ios27 build + Archive + Release 成功；当时 113 个 Swift |
| 41171707124 | 9facd18 | failure | jobs=0（workflow YAML 解析阶段拒绝） |
| 41199640021 | 0df0ec33 | failure | jobs=0（同一非法 YAML） |
| 41161655697 | 762f54c | success | README/COMPLETION 引用的旧 run；仅 113 文件树，且 job 只有 build，不含 Archive/Release |

说明：0df0ec3 的 workflow 非法是**历史问题**；1f87607 已修复 YAML（当前 `PyYAML.safe_load` 通过），所以 C-01 现在是“修好 workflow 后暴露出的真编译错误”，不是 YAML 问题。

### 4.4 Release（GitHub API）

- 3 个 IPA（见 C-08），最新 `LockKeeper-20261031.130056-unsigned.ipa` 1,213,780 bytes；
- `docs/COMPLETION.md:124` 指向 `...112404...`，不是最新；
- 当前 1f87607 的 build 失败，没有新 IPA 覆盖。

---

## 五、建议修复顺序

1. **先修 C-01 的 5 条编译错误**，让 1f87607 的 build job 变绿；这是唯一能产出新 IPA 的前提。
2. 补 `Assets.xcassets`（至少 `AppIcon.appiconset`）、`PrivacyInfo.xcprivacy`、`CFBundleURLTypes`、`UIBackgroundModes(bluetooth-central)`（C-03 ~ C-06）。
3. 给 `CFBundleVersion` 注入构建号，清理 Release 旧 IPA，修正 `COMPLETION.md` 的资产链接（C-07/C-08）。
4. 把 5 个未跟踪文件纳入 commit，确认 Destinations 依赖（C-09）。
5. 补显式 `import Combine/UIKit/Foundation`，再按 R-01 的 4+3 个并发点做 Swift 6 迁移；否则下一次“切 6.0”会重复 C-01 的 actor 错误。
6. 把 `Gates/types.js` 的检查范围扩到 UI，或至少在 CI build 前保留“真编译”作为唯一硬门槛（C-02/R-04）。

---

## 附：审计边界

- 未修改被审计源码；本报告是唯一新增文件。
- 没有 xcodebuild，未在本机复现 5 条编译错误；它们来自同一 commit 的 GitHub Actions annotation（run 41201710690），并已逐行对照本地源码。
- 未验证真机安装/签名/DFU；相关结论按代码与工程配置推断，已标为“可能失败/风险”。
