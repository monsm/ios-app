# AUDIT-G-DELIVERY · ios27 构建 / 交付 / CI 审计

> 审计口径：只报有证据的问题；每条给 file:line、证据、严重度、修法。
> 审计快照：2026-11-01 00:38 +08:00。本地 HEAD `18b018c`；最后一次可读 CI 为 run `41219938500`（commit `a8416aa`，BUILD SUCCEEDED + ARCHIVE SUCCEEDED + errors=0）。
> 限制：本机 Windows，无 xcodebuild / 无 plutil / 无 gh。编译结论一律取自 `origin/ci-log` 与 GitHub REST API；IPA 结论取自**下载并解析真实 Release 资产**（sha256 与 GitHub digest 逐字节核对一致）。
> 未修改任何源码；本文件是唯一产物。
> 说明：审计期间远端 main 连续推进（b6143d4 → … → 18b018c，多次），`ci-log` 始终只保留**最近一次**。本报告以「本轮能读到的最强证据」为准：绿 run `41219938500`（`a8416aa`）的日志 + 最新 Release 资产的逐字节解析；审计期间还观测到 `65dc3ef`/`c2e0ec5` 两轮红（`SyncTimeScreen.swift:246` `cannot find 'mac' in scope`、`RecordsModels.swift:388` `@MainActor clock` 隔离），均已在后续提交修复 —— 这条轨迹本身也印证了 G-04/G-05 的「文档数字追不上树」。

---

## 0. 结论摘要

| 项 | 结论 |
|---|---|
| 当前构建 | **绿**。`a8416aa` / run `41219938500`：`** BUILD SUCCEEDED **`、`** ARCHIVE SUCCEEDED **`、`errors=0`、`build.log` 428 行、`: warning:` **0** 条。 |
| 静态闸门 | 本地 `node Gates/allgates.js` → **16 / 16 通过**（新增 `privacy.js`）。 |
| 真 IPA | 已下载 `LockKeeper-20261101.003442-unsigned.ipa`（2,629,100 B / sha256 `f5a068df…c7c14d`，与 Release API 的 digest 一致）并解析：`CFBundleVersion=48`、`MinimumOSVersion=27.0`、Mach-O `minos 27.0.0`、24 个依赖全是系统框架、`UILaunchScreen={}`、`kf://`、`bluetooth-central`、`UIRequiresFullScreen` 已不在。 |
| **阻断项** | **1 条 P0**：`App/PrivacyInfo.xcprivacy` 是**非法 XML**（第 50 行多一个 `</dict>`），且该文件被原样打进 IPA。上架时隐私清单无法解析 = Required Reason API 申报等于没交。 |
| 计数 | **P0 = 1 · P1 = 2 · P2 = 5 · P3 = 6（共 14 条）** |

---

## 1. 已核实为「正确」的交付项（不是凑数，逐条有证据）

| 项 | 证据 |
|---|---|
| 构建号注入真的生效 | IPA `Info.plist` `CFBundleVersion = "48"`（不是写死的 1）；CI 日志 `CURRENT_PROJECT_VERSION = 42` / `= 48`（`ios27.yml:116,129` 传 `github.run_number`；`project.yml:52` `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`）。链路成立，自检步骤 `ios27.yml:97-103` 只是 warning 不阻断。 |
| 部署目标 iOS 27 | IPA `MinimumOSVersion=27.0`；Mach-O `LC_BUILD_VERSION platform=2 minos=27.0.0`；`actool --minimum-deployment-target 27.0`（build.log）；`project.yml:8`。 |
| 未签名 IPA 可复现且完整 | 三次下载分别 2,609,538 / 2,622,180 / 2,629,100 B，sha256 均与 Release API `digest` 逐字节一致；ZIP 9 个条目，EOCD 正常。 |
| 无缺失框架 | 可执行文件 24 个 `LC_LOAD_DYLIB`：Foundation / Combine / CoreBluetooth / CoreImage / CoreTransferable / CryptoKit / LocalAuthentication / Security / SwiftUI / UIKit / UserNotifications / libcompression / libswift*。代码里 `import` 的模块全部在内（`CommonCrypto` 走 libSystem，正常）。 |
| 权限文案与实际 API 一致 | 声明：Bluetooth ×2、FaceID、LocalNetwork。实际：`CBCentralManager` 35 处、`LAContext/evaluatePolicy` 4 处、`URLSession` WebDAV。相机/定位/相册/通讯录/健康/日历/追踪 API **全部 0 命中**，也没有对应声明 → 无「声明未使用能力」。 |
| 隐私清单申报类别选对了 | 代码用 `UserDefaults`（`Store.swift:8`）与文件时间戳（`BackupStudioScreen.swift:259,263`），清单恰好申报 `NSPrivacyAccessedAPICategoryUserDefaults`(CA92.1) + `NSPrivacyAccessedAPICategoryFileTimestamp`(C617.1)；磁盘空间/开机时间/键盘 API 0 命中。**类别正确，但文件本身解析不了（见 G-01）。** |
| 图标位图合规 | 9 个 appiconset × 3 张，全部 1024×1024 RGBA，alpha 全 255（无透明通道，符合 App Store）；`Contents.json` 10 个全部 JSON 合法；`Assets.car` 已生成并含 `AppIcon`/`icon-any`。 |
| 启动屏 | `UILaunchScreen: {}`（`project.yml:53`）→ IPA 内为 `{}`，系统默认启动屏，合法。 |
| URL scheme | `CFBundleURLTypes` 声明 `kf`（`project.yml:65-68`）→ IPA 内一致；`LockKeeperApp.swift:55-79` `onOpenURL` 白名单 4 个 host 且 `guard app.unlocked`（深链不绕过本机密码闸）。 |
| Release 只留一份 | API 实测 `ios27-latest` 只有 1 个 IPA 资产（`ios27.yml:166-173` 先删后传）。 |
| ci-log 可读 | `origin/ci-log` 四文件齐全（`build.log`/`archive.log`/`errors.txt`/`meta.txt`），失败轮也会推（`ios27.yml:208-230`，`if: always()`）。 |
| 闸门补强真实发生 | `swiftcheck.js:29-34` 现会判「源码含裸控制字符」——正是 run 41217531256 红的根因（`RecordsModels.swift:407` 一个裸 CR）；已由 `c6bc462` 修复，当前该文件 CR=0。 |

---

## 2. 发现（P0 → P3）

### G-01 · P0 · 隐私清单是非法 XML，且被原样打进 IPA

**位置**：`App/PrivacyInfo.xcprivacy:50`（`</dict>` 应为 `</array>`）

**证据**（三条独立复核）：

```text
# 1) 结构：32 <key>NSPrivacyAccessedAPITypes</key>  33 <array>  34 <dict> … 41 </dict>
#    42 <dict> … 49 </dict>   50 </dict>   ← 多余（此处应闭合 33 行的 <array>）
#    51 </dict>（根 dict）   52 </plist>
# 2) 解析：python plistlib → ExpatError: mismatched tag: line 50, column 3
#    .NET [xml] → "The 'array' start tag on line 33 … does not match the end tag of 'dict'. Line 50, position 4."
# 3) 打包：IPA 内 Payload/LockKeeper.app/PrivacyInfo.xcprivacy 1745 B，与仓库源文件**逐字节相同**（same sha256），
#    即没有经过任何 Xcode 规范化 —— 坏文件原样进包。
```

**影响**：App Store Connect 对 `PrivacyInfo.xcprivacy` 做 plist 解析；解析失败 = 隐私清单不生效，`CA92.1`/`C617.1` 的 Required Reason 申报视为未提交（自 2024 起会被拒收/警告），且`NSPrivacyTracking=false` 等声明也一并失效。Xcode 编译与本地闸门都**不会**发现它（`Gates/privacy.js` 只扫 Swift 源码，不校验 XML）。

**修法**：把第 50 行 `\t</dict>` 改成 `\t</array>`；在 `Gates/privacy.js` 末尾加一条 plist 断言（Node 里可用 `plutil`-free 的极简配对检查，或直接比对 `<array>`/`</array>`、`<dict>`/`</dict>` 计数），让这类错误在本地就红。

---

### G-02 · P1 · `pull_request` 触发的构建会去改公开 Release

**位置**：`.github/workflows/ios27.yml:155`（发布步骤只有 `if: success()`）；触发条件见 `:20-23`。

**证据**：`on.pull_request.paths: [ios27/**, .github/workflows/ios27.yml]` 会真跑 build job；发布步骤

```yaml
- name: 发布到 Release（公开直链下载 IPA）
  if: success()          # ← 没有 github.event_name == 'push' 守卫
```

同仓库分支的 PR：`GITHUB_TOKEN` 有 `contents: write`（`:26-28`），于是 PR 会**删掉并替换** `ios27-latest` 的 IPA（`:168-172`）。fork PR：token 只读，`gh release upload` 失败 → 整条 build job 变红（假红）。

**影响**：任意外部贡献者/草稿 PR 都能改写对外发布物；或让本来编译成功的 PR 报红。

**修法**：发布与 ci-log 两个步骤都加 `if: github.event_name == 'push' && success()`（ci-log 步骤同理，避免 PR 去 force-push 分支）。

---

### G-03 · P1 · 文档直链的 IPA 文件名已经 404

**位置**：`docs/COMPLETION.md:123-124`、`README.md:41`

**证据**：

```text
$ curl -I -L https://github.com/monsm/ios-app/releases/download/ios27-latest/LockKeeper-20261031.223629-unsigned.ipa
404
$ curl -I -L …/LockKeeper-20261031.230756-unsigned.ipa   → 200（当时）
# 现在 Release 只剩 LockKeeper-20261101.003442-unsigned.ipa（1 个资产）
```

**影响**：文档把「带时间戳的文件名」写死，而 workflow 的策略是「每次删旧传新」（`:166-173`）——两者互斥，每次新构建后文档链接必失效。用户照 COMPLETION.md 点进去得到 404。

**修法**：文档只写 Release 页（`releases/tag/ios27-latest`）或直接用 API 的 `browser_download_url` 不带文件名的稳定重定向；若必须给文件名，改用「见 Release 页最新资产」的措辞。

---

### G-04 · P2 · 闸门数/文件数/行数在文档里全面过期

**证据（实测 vs 文档）**：

| 指标 | 实测（HEAD 18b018c） | 文档写的 |
|---|---|---|
| Swift 文件 | **148** | `README.md:11,103` 113；`COMPLETION.md:13` 113 |
| 代码行 | **36,874** | `COMPLETION.md:14` 21,775 |
| 静态闸门 | **16** | `README.md:55` 9 道、`:83` 十一道；`ARCHITECTURE.md:29` 9 道；`COMPLETION.md:17` 11；`ios27.yml:7` 11 道 |
| Engine 文件 | **69** | `COMPLETION.md:19` 66 |

同一份仓库里 `ios27.yml:37` 的 job 名已经写「16 道」，`:7` 的注释还写 11 道 —— 自相矛盾。

**修法**：把四处计数改成由脚本产出的数字，或至少在本轮统一到 148 / 36,874 / 16 / 69；`ios27.yml:7` 注释与 job 名对齐。

---

### G-05 · P2 · 「CI 已通过」引的是 11 道闸门时代的旧 run

**位置**：`README.md:159`、`docs/COMPLETION.md:147`（均引 run `41161655697`）

**证据**：API 实测该 run = commit `762f54c`，job 为「静态闸门（**11 道**）」+「编译」，即 113 文件旧树。当前绿的是 run `41219938500`（`a8416aa`，16 道闸门 + Archive + errors=0）。`COMPLETION.md:167` 还把「已完成」归到该 run。

**影响**：交付声明的证据链对不上当前树 —— 与 `docs/VERIFY-FINAL.md` 内部记录（run `41219938500`）不一致。

**修法**：改为「run 41219938500 / a8416aa（16 道闸门 + BUILD + ARCHIVE + errors=0）」，并注明「后续提交需重新核对 ci-log」。

---

### G-06 · P2 · 8 套备选 App 图标是死资产（功能相对旧版回退）

**位置**：`App/Assets.xcassets/AppIcon-{Bell,Guard,Heart,Home,Key,Pin,Ring,Shield}.appiconset`（24 张 PNG，共约 8×3 张）

**证据**：
- 代码 `setAlternateIconName` / `alternateIcon` / `iconOptions` → **0 命中**（全 `App/`）；
- `project.yml` 无 `CFBundleIcons` / `CFBundleAlternateIcons`（对比旧 `ios-app/project.yml:89-114` 是有的）；
- 真实 IPA 的 `Assets.car` 里只有 `AppIcon`/`icon-any` 两个名字，8 个 `AppIcon-*` 名字**一个都不在**；`Info.plist` 只有 `CFBundlePrimaryIcon`。

**影响**：旧 App 有「换图标」功能，新版静默丢失；同时 24 张 1024×1024 PNG 白占仓库与编译期 actool 时间。

**修法**：二选一 —— ① 在 `project.yml` 补 `CFBundleIcons.CFBundleAlternateIcons` 并在设置页接 `setAlternateIconName`；② 删掉 8 个 appiconset（保留 `AppIcon`）。

---

### G-07 · P2 · 新工程没有任何测试目标，金标向量不再被执行

**位置**：`project.yml:26-85`（`targets` 只有 `LockKeeper`）；`README.md:174-175` 的承诺

**证据**：`yaml.safe_load(project.yml)["targets"]` = `['LockKeeper']`；仓库无 `ios27/Tests`；`App/` 内 `import XCTest` / `@Test` → 0 命中；旧工程 `ios-app/project.yml:120-142` 曾有 `OfflineLockTests` + `fixtures/golden.json` + 固件 fixture。README:174-175 仍称「有字节级差分金标（40 条命令帧、NIST AES 向量…）已验证」。

**影响**：引擎层（69 文件，含密码学与协议帧）的回归保护只剩「CI 能不能编译」，语义错误不会被任何环节拦住。

**修法**：加 `LockKeeperTests` target（`project.yml` 里 `type: bundle.unit-test`）+ 把 `fixtures/golden.json` 搬过来，CI 加一步 `xcodebuild test`；或在 README 把「金标已验证」降级为「金标在旧仓，本仓未接入」。

---

### G-08 · P2 · 本地真机签名没有 DEVELOPMENT_TEAM，但 README 让人本地跑

**位置**：`project.yml:24`（`CODE_SIGN_STYLE: Automatic`，全文件无 `DEVELOPMENT_TEAM`）；`README.md:46,66-67`；CI 侧 `ios27.yml:117,130`

**证据**：`Select-String project.yml -Pattern DEVELOPMENT_TEAM` → 0 行。CI 能过是因为 build 与 archive 都传 `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`；IPA 里 `LC_CODE_SIGNATURE` 计数 = 0（确认未签名）。README:46 给的 `xcodebuild` 路线也带 `CODE_SIGNING_ALLOWED=NO`，但要在真机上跑仍必须在 Xcode 里选 team。

**影响**：用户按 README 走「Xcode ⌘R」会停在 “requires a development team”；交付文档没有把「只有 CI 出未签名包」这条边界写清。

**修法**：要么加 `DEVELOPMENT_TEAM: ""` 并在 README 明写「真机安装需自选 Team / 走 AltStore 自签」，要么把 README:46 那行改成「仅生成工程，签名自备」。

---

### G-09 · P3 · ATS 注释与「强制 HTTPS」的新代码互相矛盾

**位置**：`project.yml:72`（注释「允许用户连自建 HTTP 服务器」）vs `BackupStudioScreen.swift:487-493`（`normalized()` 只放行 `https://`，`http://` 仅 localhost/127.0.0.1）

**证据**：`f50e34f` 已把 WebDAV 强制 HTTPS（`if t.hasPrefix("https://") { return t }` / `http://` 只有回环例外）；`project.yml:72-75` 仍保留「HTTP 服务器」措辞 + `NSAllowsLocalNetworking: true`。

**影响**：读工程配置的人会以为明文 HTTP 仍被支持；`NSAllowsLocalNetworking` 现在的正当理由只剩「localhost 调试」这一条，注释没更新。

**修法**：`project.yml:72` 改成「仅 https；localhost 调试例外」，并把 `NSAllowsLocalNetworking` 的注释写明只服务于回环调试。

---

### G-10 · P3 · Bundle ID 换代没有迁移策略，旧 id 残留两处

**位置**：`project.yml:36`（`com.aapk.lockkeeper`）；`Engine/SecretStore.swift:20`（`"com.aapk.OfflineLock.secrets"`）；`Engine/CredentialOrg.swift:29`（`Logger(subsystem: "com.aapk.OfflineLock")`）

**证据**：`git grep com.aapk.OfflineLock HEAD -- ios27` → 上述两处（+ 文档）。旧工程推导 id 为 `com.aapk.OfflineLock`（`ios-app/project.yml:4,6` 无显式 `PRODUCT_BUNDLE_IDENTIFIER`）。

**影响**：bundle id 不同 = 装成两个 App；Keychain service 名仍是旧串 —— 若这是**刻意**为迁移保留，需要写进文档（否则下一个人会「顺手改对」而把老用户的密钥读丢）；Logger subsystem 用旧 id 则是纯 mislabel（日志归错子系统）。

**修法**：在 `SecretStore.swift:20` 上方加一行「service 名是历史值，改它 = 老用户密钥丢失，禁止改动」；`CredentialOrg.swift:29` 的 subsystem 改成 `com.aapk.lockkeeper`（日志不参与迁移，可安全改）。

---

### G-11 · P3 · 两个 job 都没有 `timeout-minutes`

**位置**：`.github/workflows/ios27.yml:36-74`（gates）、`:70-230`（build）

**证据**：全文 `Select-String timeout-minutes` → 0 命中；`runs-on: xcode-27`（`:72`）是 preview 镜像，历史上有抽风记录（`:4` 注释自己写了）。

**影响**：镜像卡住时按默认 6 小时占着跑；失败反馈延迟到次日。

**修法**：`gates: timeout-minutes: 15`、`build: timeout-minutes: 45`。

---

### G-12 · P3 · 后台能力只声明不落地：`import BackgroundTasks` 是死引用，蓝牙链路没有状态恢复

**位置**：`Engine/BackupStudioKit.swift:8`（`import BackgroundTasks`，全仓 `BGTaskScheduler` 只在注释里出现 2 次）；`project.yml:70-71`（`UIBackgroundModes: bluetooth-central`）；`Engine/BLEService.swift:96`（`CBCentralManager(delegate:queue:.main, options:…)` 无 `CBCentralManagerOptionRestoreIdentifierKey`）

**证据**：`BGTaskScheduler`/`BGAppRefreshTask`/`BGProcessingTask` 在 `.swift` 里 0 处真调用；`willRestoreState` / `CBCentralManagerOptionRestoreIdentifierKey` 0 命中；`Info.plist` 无 `BGTaskSchedulerPermittedIdentifiers`。

**影响**：`bluetooth-central` 只能让 App 在后台继续处理事件，**进程被系统回收后无法恢复**（DFU 这种分钟级传输仍是「尽量不被打断」，不是「保证续上」）；`import BackgroundTasks` 是纯噪音。

**修法**：删掉 `BackupStudioKit.swift:8` 的无用 import；若 DFU 真要抗回收，给 `CBCentralManager` 加 restore identifier + `centralManager(_:willRestoreState:)`，并在文档把「后台保证」降级为「后台尽力」。

---

### G-13 · P3 · `WARNINGS.md` 的数据锚点已过期（当前 0 warning）

**位置**：`docs/WARNINGS.md:3,5`

**证据**：文档写「`origin/ci-log:build.log`（commit `a24bcac`，run `41209905485`）… **88 条源码 warning（去重 83 个唯一位置）**」。当前绿 run `41219938500` 的 `build.log` 428 行、`: warning:` **0** 条（并发迁移已完成，`@MainActor` 已加）。文档把「88 条」当作当前事实来引用（`:134`「当前构建 0 error，warning 不阻断发布」）。

**影响**：读者会以为还有 88 条待办；实际已经清零，剩下的价值是历史记录。

**修法**：标题下改成「历史快照（a24bcac）；当前 run 41219938500 已 0 warning」，保留明细作为迁移台账。

---

### G-14 · P3 · Release 资产名用「上传时刻」而非「构建时刻」，无法反查 commit

**位置**：`.github/workflows/ios27.yml:134-135`

**证据**：`STAMP=$(TZ=Asia/Shanghai date +%Y%m%d.%H%M%S)` 在 archive 步骤里取的是**打包上传瞬间**；Release notes 里有 commit sha（`:162`），但文件名里没有。同一 commit 重跑会生成不同文件名（`223629` vs `230756` 就是同一 `a24bcac` 的两份），文档一旦按名字引用就会漂移（见 G-03）。

**修法**：文件名改成 `LockKeeper-${GITHUB_RUN_NUMBER}-${GITHUB_SHA:0:8}-unsigned.ipa`（run number 唯一且可反查），时间戳只进 notes。

---

## 3. 证据与复现

```text
# 1) CI 结果（无需出网）
git -C D:\aapk\ios-app fetch origin --quiet
git -C D:\aapk\ios-app show origin/ci-log:meta.txt     # commit / run / errors
git -C D:\aapk\ios-app show origin/ci-log:errors.txt   # 空 = 0 error
git -C D:\aapk\ios-app show origin/ci-log:build.log | tail -1   # ** BUILD SUCCEEDED **
git -C D:\aapk\ios-app show origin/ci-log:archive.log | tail -1 # ** ARCHIVE SUCCEEDED **

# 2) 闸门
cd ios27 && node Gates/allgates.js        # allgates: 全部 16 道闸门通过

# 3) 真 IPA（用 GitHub API 拿 digest，再下载核对）
curl -sS https://api.github.com/repos/monsm/ios-app/releases/tags/ios27-latest
#   assets[].digest = sha256:…
#   → 下载后 Get-FileHash -Algorithm SHA256 必须一致（本轮三次均一致）

# 4) 隐私清单（P0 复现，两种解析器各一次）
python -c "import plistlib;plistlib.loads(open('ios27/App/PrivacyInfo.xcprivacy','rb').read())"
#   ExpatError: mismatched tag: line 50, column 3
#   .NET: [xml] 同文件 → "array start tag on line 33 … does not match end tag of dict. Line 50, position 4."
```

### 3.1 审计边界（未验的就是未验）

1. **无 xcodebuild / 无真机 / 无模拟器**：编译结论来自 CI 日志；安装、签名、DFU、BLE 回执、WebDAV 真实链路均未在本机跑过。
2. **REA 未能解析 IPA**：`mcp__rea__open_binary` 能打开（`format=ipa, kind=archive, sha256=91181c…`），但 `inspect_artifact`/`extract_artifact` 报 `artifact_operation_failed (reason: io)`。定位：`D:\aapk\.tmp-audit-c\ipa\LockKeeper.ipa` 是**截断文件**（1,029,868 B，无 EOCD，`.NET ZipFile` 报 “End of Central Directory record could not be found”）。改用「Release API 取 digest → 下载 → Python zipfile 解析」替代，结论未降级。
3. **App Store 侧行为**：G-01 的「解析失败 → 清单不生效」依据 Apple 对 `PrivacyInfo.xcprivacy` 的 plist 要求与解析器实测，未在 App Store Connect 实机提交验证。
4. **PR 触发发布（G-02）**：依据 workflow 结构与 GitHub token 权限模型，未真的开一个 PR 去观测。
