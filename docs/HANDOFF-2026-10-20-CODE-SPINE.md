# 交接报告 · 2026-10-20 代码主干预重构

> 状态：**已完成（静态闸门全绿）/ 未编译 / 未提交**
> 基线：`main` HEAD `21d92b5`；工作区 21 个修改 + 4 个代码/闸门新文件（另加本报告）。
> 本文写给下一个接手的 AI 或人：先读 §0 与 §5，再按 §6 复跑；不要凭“闸门绿”推断“编译过”。

---

## 0. 一句话结论

这一轮把四件“同一事实多份真相”收成了唯一判据口：**命令安全族**、**每锁键族所有权**、**411 备份二维码**、**Android 浅色/权限/解绑**；同时修掉三处“注释说谎 / 假绿”。所有可跑的 node 闸门 exit 0，两个新闸门都做过注入正控。**但本机没有 Swift/Xcode/Java/Kotlin 工具链，0 行 Swift、0 行 Kotlin 被编译，0 次真机/模拟器运行。**

---

## 1. 为什么做这一轮

上一轮 `analysis/09-code-verification.md` 已定性：

- **P0**：`credentialQRPayload()` 返回明文 canonical，内含 `skey/bkey/PIN 池/ekey` 与成员名册，而界面写“口令另行线下交接”——那张码根本没有口令。
- **P1**：`SecurityPolicy.allows` 全仓只有 7 个调用点，`writeCredential / provision / dfu` 三族没有守卫，只读安全模式形同虚设。
- **P1**：`AutoOpen` 的 `dwellMet` 仍在调 `MotionStillness.met()`，而注释写着“删掉静置判定”；加速度计不可用的机器上 `met()` 恒 false，自动开锁永久不触发。
- **P1**：Android 解绑只清 `lock` 键、不清 `proximity`；权限回调是空 lambda；浅色主题只接了一半。
- **P2**：`kotlinshadow` 把 `BASE=-38` 写死在断言里，而源码已是 -40；`autoopenshadow` 钉着旧的 `stillnessSeconds=1.0`。

用户口径：**四条主线全部重构，允许修 P0/P1**。

---

## 2. 变更清单

### 2.1 命令安全表（新增，核心）

**文件**：[`App/Core/LockCommand.swift`](../App/Core/LockCommand.swift)

- `enum LockCommand: UInt8, CaseIterable` 登记 **29 条**会上链的命令。
- 每条通过 `var policy: LockAction?` 声明动作族；`nil` = 只读。
- 统计：**写类 21 条 / 只读 8 条**。

| 动作族 | 命令 |
|---|---|
| 只读 | `01` 会话令牌、`03` 状态、`12` 回声、`16` 日志、`30` 网关名称、`38` 网关状态、`43` 钥匙串状态、`44` 钥匙串查钥 |
| `.unlock` | `04` 开锁 |
| `.provision` | `23` 交换方式、`05` 换钥、`08` PIN 池、`21` bkey、`31` 网关 WiFi、`32` 网关 IoT |
| `.writeCredential` | `0A` 同步密码、`0B` 密码有效期、`13` 录指纹、`14` 确认指纹、`15` 删指纹、`19` 临时密码、`41` 钥匙串写钥 |
| `.configure` | `0E` 校时、`18` 音量、`20` 单双验、`24` 自动上锁、`25` 布防、`35` 网关重启 |
| `.dfu` | `22` 进入升级 |

**87 帧的唯一判据**：`LockCommand.requireAllowed(_:)`（`LockCommand.swift:115`）。未登记命令 **fail-closed**；已登记写命令走 `SecurityPolicy.allows`。DFU 不走 87 帧，没有 cmd 字节可查表，因此在两处入口直接判 `SecurityPolicy.allows(.dfu)`（与 `requireAllowed` 最终落到同一个策略函数，不是第二套语义）。

**四个上链入口全部接闸：**

| 入口 | 位置 | 说明 |
|---|---|---|
| `LockService.request` | `App/Services/LockService.swift:226` | 所有普通 87 帧命令 |
| `HardwareService.send` | `App/Services/HardwareService.swift:135` | 网关 / 钥匙串；先判再连 |
| `LockService.fpStart` | `App/Services/LockService.swift:641` | `13` 是多响应直写，不走 request，必须自己过两道闸（用户只读 + `kf_trial_guard`） |
| `DFURunner.runUpgradeQueue` | `App/Services/DFUKit.swift:643` | 连接第一把锁前就停手（`SecurityPolicy.allows(.dfu)`） |
| `DFURunner.runUpgrade` | `App/Services/DFUKit.swift:677` | DFU 不走 87 帧，必须单独挡（同一策略函数） |

**`LockAction` 新增 `.configure`**：[`App/Core/LockGuard.swift:149`](../App/Core/LockGuard.swift)，拒因文案在 `:163`。`.provision` 的文案从“网关配网”改为“配网/换钥（含网关配网）”，因为现在它真的会拦 `05/08/21/23`。

**行为变化（有意）：**

- 只读安全模式开启后，凭证写入、配网/换钥、锁端参数、DFU 全部被拦；此前只有开锁/销毁/导入导出被拦。
- 新命令如果忘了登记，会在发包前报“未在 LockCommand 安全表登记”，而不是静默绕过。
- `HardwareService.send` 被拦时不会先建立链路。

**新闸门**：[`tools/policygate.js`](../tools/policygate.js)

检查五件事：

1. `ZKCmdBuilder` 里每个 `cmd: 0xNN` 都在 `LockCommand` 表里；
2. `request` / `send` / `fpStart` / DFU 两处都接闸；
3. 每个 `LockAction` 都有拒因；每个命令策略都是已声明的 action；
4. 直写路径数量棘轮：`LockService` 只允许 2 处 `ble.writeFrameHex`（`request` + `fpStart`），`HardwareService` 只允许 1 处；
5. 411 二维码的函数必须收 `password`、走 `CryptoBox.encryptText`、容量按 UTF-8 字节、调用点必须传 `password:`。

CI 已接：[`.github/workflows/ios.yml:113`](../.github/workflows/ios.yml)。

**正控（已验会开火）：**

```text
抽掉 LockService.request 里的 requireAllowed(cmd)
→ ✗ policygate: 1 条 … 退出 1
恢复 → 退出 0
```

---

### 2.2 每锁键族所有权（新增）

**文件**：[`App/Core/LockKeySpace.swift`](../App/Core/LockKeySpace.swift)

旧 `Store.removeDevice` 内联了 35 条前缀 + `kf_chist_<mac>_` 特例 + “键名含 MAC”兜底。现在收成一张表三档：

| 档 | 数量 | 例子 |
|---|---:|---|
| `suffixPrefixes`（前缀 + mac） | 35 | `kf_ledger_`、`kf_snap_`、`kf_macorder_`、`kf_autocal_` |
| `segmentedPrefixes`（前缀 + mac + `_` + 尾段） | 1 | `kf_chist_` |
| `macInKeyFamilies`（仅文档 + 闸门核查） | 9 族 | `kf_calert_`、`kf_cotp_t_`、`kf_mig_lockact_` |

`owns(_:_:)` 保留大小写不敏感判据（兼容 DemoKit 大写 demoMac）；`purge(_:)` 依次做精确删、分段扫、MAC 兜底。`Store.removeDevice` 现在只调 `LockKeySpace.purge(m)`（[`Store.swift:450`](../App/Core/Store.swift)），随后只处理 `kf_default_mac` / `kf_current_mac` / `kf_last_device` / `kf_lock_order` 这些**全局指针**。

**行为**：与旧实现等价（顺序从“前缀→autocal→chist→兜底”变为“suffix→segmented→兜底”，集合相同）。

**新闸门**：[`tools/keyspace.js`](../tools/keyspace.js)

- `removeDevice` 必须调 `LockKeySpace.purge(m)`；
- 不许再出现 `"kf_ledger_..."` 等逐锁前缀字面量；
- 前缀不得重复/为空/不以 `_` 结尾；
- 前缀必须在 App/ 其他文件里真的出现过（防删键后留死表项）；
- 兜底族前缀也要有真实使用点。

CI 已接：[`.github/workflows/ios.yml:116`](../.github/workflows/ios.yml)。

**正控（已验会开火）：**

```text
把 LockKeySpace.purge(m) 换成 _ = m
→ ✗ keyspace: 1 条 … 退出 1
恢复 → 退出 0
```

> 操作教训：做注入正控时用 `cp` 备份**单个文件**再改；不要用 `git checkout -- 文件` 还原实验，它会把该文件上**本轮全部**改动一起回退。本次曾误回退 `Store.swift`，已按原 diff 重新应用并复核（见 §3.3）。

---

### 2.3 P0：411 二维码改为口令信封

**旧实现**（`BackupStudioKit.swift` 原 `credentialQRPayload()`）：

- 收集全量包 → 清 `meta/globals` → 保留 `members`（姓名/电话）→ 返回**明文 canonical**；
- UI 同屏写“口令另行线下交接”，但二维码本身没有口令；
- 谁拍到/截图就拿到 skey/bkey/PIN 池/ekey。

**新实现**：[`App/Services/BackupStudioKit.swift:459`](../App/Services/BackupStudioKit.swift)

```swift
static func credentialQRPayload(password: String) -> String? {
    guard !password.isEmpty else { return nil }
    // 清 meta / globals；成员保留但电话置空
    // 明文 t.utf8.count <= 900
    // CryptoBox.encryptText(t, password: password)
    // 信封 env.count <= 2200
}
```

- **算法**：`CryptoBox.encryptText` = PBKDF2-HMAC-SHA256（60,000）+ AES-128-CBC/PKCS7 + HMAC-SHA256（encrypt-then-MAC），与备份文件同一套。
- **容量口径**：按 UTF-8 **字节**，不是 `String.count`。中文 1 字符 3 字节，按字符卡会生成扫不出来的码。
- **实测（node 模拟同结构信封）**：900 字节明文 → **2124** 字符信封；1000 字节 → 2317（超 2200，故 900 是刻意上界）。QR 纠错档 M 上限约 2331 字节，2200 留了余量。
- **成员隐私**：保留 `id/name/relation` 供 owner 归属，`phone` 置空；`globals` 整个不带走。

**UI**：[`App/UI/BackupStudio.swift`](../App/UI/BackupStudio.swift)

- 新增 `qrPass` / `qrMsg` 状态（`:380`）。
- 导出完成时：只有 `pw` 非空才自动出码；否则留空，完成页显示“二维码口令”+“生成加密二维码”按钮（`:628` / `:632`），至少 6 位（`:645`）。
- 文案从“口令另行线下交接”改为“这张码本身是口令信封：截到码也打不开。但口令请当面或走另一条渠道，不要和码一起发。”
- 接收端文案改为“扫码包是加密信封……请在上方填旧机用的同一口令”（原 `:1688` 附近）。
- 分卷导出（`useVolumes`）不出二维码，与旧行为一致。

**接收链**：`MigrationWizardView` 的 `addSegment` 调 `BackupStudio.parsePreview(text:password:)`；`looksEncrypted` 命中后走 `decryptAny`，口令为空时明确报“此备份带口令 — 输入导出时设置的口令”。**没有新造格式**。

**已知取舍**：

- 自动出码复用了导出向导里的 `pw`；如果用户给备份设了 1 位口令，二维码也会接受这 1 位（独立生成路径会强制 6 位）。这是为了不在导出完成后突然要求第二套口令；若产品要求统一，改成 `credentialQRPayload` 内强制 ≥6 位即可。
- 明文 900 字节上限意味着“凭证很多”的包会返回 nil，UI 引导走文件通道；这是一条如实失败，不是静默降级。
- 成员姓名仍在二维码里（owner 归属需要）；只去掉电话。

---

### 2.4 Android 三个真缺口 + 主题收口

#### 2.4.1 解绑清 proximity

[`LockStore.kt:61`](../android-app/app/src/main/java/com/aapk/kfkey/LockStore.kt)

旧 `clear()` 只 `remove(KEY)`；`MainActivity` 解绑时只把内存 `proximity` 置 false，没有落盘。下次扫新锁 `loadProximity` 读回 true ⇒ 新锁一绑上就默认自动开。

现在 `clear()` 同一次 `edit()` 里 `.remove(KEY).remove(KEY_PROX).apply()`。`KEY_PROX` 定义在 `:19`。

#### 2.4.2 权限回调不再空

[`MainActivity.kt:150`](../android-app/app/src/main/java/com/aapk/kfkey/MainActivity.kt)

- `minSdk = 33`，三项权限（BLUETOOTH_SCAN / BLUETOOTH_CONNECT / CAMERA）都是运行时权限，删掉恒真的 `Build.VERSION.SDK_INT >= 33` 分支。
- 回调把被拒权限映射成人话：“缺少权限: 蓝牙扫描、相机 — 扫码与开锁会失败, 请到系统设置里允许”。
- 删除不再使用的 `Build` / `VibrationEffect` / `VibratorManager` import。

#### 2.4.3 浅色主题残点

- `KfColors` 新增 `onAccent`（[`KfTheme.kt:30`](../android-app/app/src/main/java/com/aapk/kfkey/KfTheme.kt)）：暗色暖金配深墨字，浅色深金配白字。
- `ProximityCard` 整块改读 `LocalKfColors`（`:685` 起），不再用固定 `Surface/Ink/InkSub/Accent`；圆角/间距开始用 `KfTokens`（`Tokens.kt` 此前零引用，现在至少有一个真实消费点）。
- `Header`、`UnlockDial`、`EmptyState`、`Status`、`GearButton`、`PillButton` 全部接到 `colors.*`。
- [`SignalArrow.kt`](../android-app/app/src/main/java/com/aapk/kfkey/SignalArrow.kt)：颜色改为**显式参数** `okColor` / `outlineColor`（DrawScope 不是 Composable，不能在里面读 `LocalKfColors`）；描边从写死白色改为 `outlineColor`，浅色模式不会再“白底白箭头”。删掉了未使用的 `accentColor` 参数。
- `Haptics.kt` 收敛：`minSdk 33` ⇒ 直接走 `VibratorManager`；删除零调用的 `tick/trigger/rememberKfHaptics/KfTick/KfConfirm`，只留 `ok/fail`，避免同一件事两套入口。
- `Theme.kt` 注释更新：固定 val 只保留给非 Composable 默认参数 / DrawScope 兜底，不再是页面取色入口。

**未做**：`AirTagLayer` 的全屏查找层仍是固定深色（它本身就是特殊覆盖层）；Canvas 里锁体金属色仍固定（材质语义，不随主题）。如果要求全量双模，需要单独走一遍 `AirTagLayer`。

---

### 2.5 注释漂移 / 假绿 / 死代码

#### 自动开锁静置闸（P1，行为变更）

[`App/Core/AutoOpen.swift`](../App/Core/AutoOpen.swift)

- 删除 `MotionStillness` 整族（20Hz 加速度计 + 1s 静置 + `feed/met/variance`），删除 `import CoreMotion`。
- `onForeground` 不再 `start()`；`onBackground` 不再 `stop()`。
- `makeContext` 的 `dwellMet: armed && MotionStillness.met()` 改为 `dwellMet: armed`（`:450`）。
- 原因：`start()` 在加速度计不可用时直接 return，`met()` 永远 false ⇒ 这类设备自动开锁永久拒开。注释本来就写着“删掉静置判定”，代码却没跟上。
- 语义现在是：**F3 武装位是唯一条件**，靠进入线/解除线的回差拦“站着反复开”。这是产品口径变更，需要真机确认“路过门口”是否仍被回差拦住。

#### 开发自检区移出 Release

[`App/UI/AccessibilityView.swift:27`](../App/UI/AccessibilityView.swift)

`DevFeatureAuditSection / DevGrayscaleSection / DevContrastSection` 只用 `#if DEBUG` 包住入口。灰度预览/200% 字号是开发自测，不该让普通用户一键把界面弄坏。结构体本身保留（DEBUG 构建仍可用）。

#### 统计页死属性

[`App/UI/StatsView.swift:2459`](../App/UI/StatsView.swift)

删除 `private var rows: [StatsKit.CachedLogRow] { [] }` 与配套 `StatsKit.CachedLogRow` 扩展。它们恒空且零读点；真正的时段下钻是 `drillRows`（638），未动。

#### 两个影子闸门的修正（不是放宽，是纠正）

| 闸门 | 旧问题 | 现在 |
|---|---|---|
| [`tools/kotlinshadow.js`](../tools/kotlinshadow.js) | `BASE=-38` 写死在断言里，源码 `AutoOpenKit.BASE=-40`，闸门验的是不存在的代码（假绿） | 从 `AutoOpenKit.kt` 读 `BASE`，回差带/样本全部由它推导；输出 `BASE=-40 武装线=-40 解除线=-43` |
| [`tools/autoopenshadow.js`](../tools/autoopenshadow.js) | 钉 `stillnessSeconds=1.0`，与“删掉静置判定”的行为变更冲突 | 改钉 `dwellMet: armed`；新增反向围栏“非注释行不许出现 `MotionStillness.met(`” |

> 这两处改动是**因为行为/事实变了**才改闸门；没有跳过、没有弱化断言。`kotlinshadow` 的覆盖面反而变强（不再依赖手写常量）。

---

## 3. 验证记录

### 3.1 实际跑过、退出码 0

在 `D:\aapk\ios-app`：

| 命令 | 结果 |
|---|---|
| `for f in tools/*.js; do node --check "$f"; done` | 全部通过 |
| `node tools/golden.js --check` | 金标漂移校验通过 |
| `node tools/contrast.js` | 439 条断言，0 不达标 |
| `node tools/dynamictype.js` | 通过 |
| `node tools/swiftcheck.js` | 110 个 Swift 文件括号平衡 |
| `node tools/swiftshape.js` | R1–R12 零命中；R3 基线 13 |
| `node tools/swiftlint.js` | 全部检查通过 |
| `node tools/logicparity.js` | 21 条对上 APK + 4 条已裁定分歧 |
| `node tools/autoopenshadow.js` | **42/42** |
| `node tools/zotpshadow.js` | 7/7 |
| `node tools/cmdsshadow.js` | 通过（覆盖 32/40，未覆盖项由工具打印） |
| `node tools/parseshadow.js` | 通过（35/35 组） |
| `node tools/bundleshadow.js` | 18/18 |
| `node tools/kotlinshadow.js` | 全部通过；`BASE=-40` |
| `node tools/keyspace.js` | 36 条前缀 + 9 族兜底；removeDevice 单一入口 |
| `node tools/policygate.js` | 29 条命令 / 写 21 / 读 8；四路接闸；二维码只走信封 |
| `node tools/destmap.js` | 通过 |
| `node tools/uicoverage.js` | 通过（75/77，迁移期） |
| `node tools/changelogcheck.js` | 82 条 / 认账 82 / 重号 0 |
| `node tools/sheetcover.js --selftest && node tools/sheetcover.js` | 通过 |
| `git diff --check` | 干净 |

### 3.2 注入正控

| 探针 | 结果 |
|---|---|
| 抽掉 `LockService.request` 的 `requireAllowed(cmd)` | `policygate` 退出 **1**，点名该行 |
| 抽掉 `Store.removeDevice` 的 `LockKeySpace.purge(m)` | `keyspace` 退出 **1**，点名该行 |
| 两处恢复后 | 均退出 **0** |

### 3.3 一次操作事故（已修复）

做 `keyspace` 正控时用了：

```bash
sed -i 's/LockKeySpace.purge(m)/_ = m/' App/Core/Store.swift
# 还原时：
git checkout -- App/Core/Store.swift
```

`git checkout` 把 `Store.swift` 上**本轮全部**改动一起回退（不只是探针那一行）。随后按原 diff 重新应用 `LockKeySpace.purge(m)`，并复跑 `keyspace` / `policygate` / `swiftcheck` / `swiftshape` / `swiftlint`，全绿；`git diff --stat App/Core/Store.swift` = `27 +------`（3 insertions / 24 deletions），与预期一致。

**交给下一位的纪律**：注入探针前 `cp 文件 /tmp/x.bak`，还原用 `cp`，不要用 `git checkout -- 文件`。

### 3.4 没跑 / 跑不了

| 项 | 状态 |
|---|---|
| `xcodebuild build-for-testing` / `xcodebuild test` | **未跑**（本机无 macOS/Xcode） |
| Swift/XCTest 执行 | **0 行** |
| `gradle assembleDebug` / Kotlin 编译 | **未跑**（无 java/gradle/kotlinc；`kotlinlocal.js` 报缺工具链并退 0） |
| 真机/模拟器 | **0 次** |
| 二维码真机扫描 | **未做**；容量是 node 模拟，不是 Swift 执行 |
| `copynum` 顾问项 | 有 1 处既有日志串含 `§`（`LockService.swift:967` 附近），不是本轮引入 |

> `swiftcheck` 只数括号；`swiftshape` 只认结构性形状；`swiftlint` 是正则级代理。它们**都不能替代编译器**。CI 的 `build-for-testing` 是第一次真编译。

---

## 4. 变更文件清单

### 新增

| 文件 | 作用 |
|---|---|
| `App/Core/LockCommand.swift` | 29 条命令的动作族表 + 唯一 `requireAllowed` |
| `App/Core/LockKeySpace.swift` | 每锁键族所有权表 + `purge` |
| `tools/policygate.js` | 命令安全表/闸门/二维码静态对账（判失败） |
| `tools/keyspace.js` | 键族所有权表静态对账（判失败） |

### 修改（21 个）

| 文件 | 改动 |
|---|---|
| `App/Services/LockService.swift` | `request` 接闸；`fpStart` 接双闸 |
| `App/Services/HardwareService.swift` | `send` 接闸 |
| `App/Services/DFUKit.swift` | 队列/单锁两处 `.dfu` 闸 |
| `App/Core/LockGuard.swift` | 新增 `.configure` + 拒因；`.provision` 文案修正 |
| `App/Core/Store.swift` | `removeDevice` 委托 `LockKeySpace.purge` |
| `App/Core/AutoOpen.swift` | 删 `MotionStillness`；`dwellMet: armed` |
| `App/Services/BackupStudioKit.swift` | 二维码口令信封 + UTF-8 容量 |
| `App/UI/BackupStudio.swift` | 二维码口令 UI、文案、接收端文案 |
| `App/UI/AccessibilityView.swift` | 开发自检区 `#if DEBUG` |
| `App/UI/StatsView.swift` | 删死 `rows` + 扩展 |
| `android-.../LockStore.kt` | 解绑同事务清 proximity |
| `android-.../MainActivity.kt` | 权限回调、主题取色、SignalArrow 参数、import 清理 |
| `android-.../KfTheme.kt` | 新增 `onAccent` |
| `android-.../SignalArrow.kt` | 颜色显式参数、描边跟主题 |
| `android-.../Haptics.kt` | 收敛到 `ok/fail`，minSdk 33 简化 |
| `android-.../AutoOpenKit.kt` | 注释旧值 -38 → -40 |
| `android-.../Theme.kt` | 注释更新（固定 val 的定位） |
| `.github/workflows/ios.yml` | 新增 `policygate` / `keyspace` 两步 |
| `tools/kotlinshadow.js` | BASE 从源码读，去掉 -38 假绿 |
| `tools/autoopenshadow.js` | 钉 `dwellMet: armed`，加静置反向围栏 |
| `docs/redesign/REFACTOR-STATUS.md` | 新增 §五/§六 交接摘要 |

`fixtures/*` 在 `git status` 里显示 `M`，但 `git diff` 内容为空——是既有行尾标记差异，本轮未改内容。

---

## 5. 剩余风险 / 需要拍板

1. **未编译**：最大风险。新增 `LockCommand` / `LockKeySpace`、`#if DEBUG`、二维码 UI 都还没有被 Swift 编译器看过。首轮 CI 若有红，优先看 `LockCommand.swift` 的 `String(format:)`/`UInt8`、`BackupStudioKit` 的 `if var ms = b.members`、`BackupStudio` 的 ViewBuilder 分支。
2. **自动开锁行为变了**：删除静置闸后，“骑车路过门口”只靠 RSSI 回差拦。需要真机确认误开率；如果不可接受，正确做法是恢复一个**可用性降级明确**的静置实现（加速度计不可用时 fail-open 并记审计），而不是回到 `met()` 恒 false。
3. **二维码口令强度**：自动出码复用备份口令；独立出码强制 6 位。若产品要求统一最小长度，在 `credentialQRPayload` 内加 `password.count >= 6`。
4. **二维码容量**：900 字节明文是实测上界；大台账会得到 nil，UI 应继续明确引导“用文件通道”，不要偷偷截断。
5. **键族语义**：`keyspace.js` 只保证“删除点唯一 + 表不自相矛盾”，**不判断**某个键到底该不该随锁删除。新增每锁键时仍要人读 `LockKeySpace` 三档。
6. **只读模式覆盖面**：现在所有 87 帧与 DFU 都被拦；但“本机只写台账、不发锁”的路径（如某些本地编辑）不在命令闸内。若产品定义只读连本机写入也要停，需要另做数据层闸。
7. **Android 双模**：`AirTagLayer` 仍是固定深色；Canvas 金属色刻意固定。全量双模未做。
8. **伪装/胁迫整族**：仍是“删了 UI 没删逻辑”的状态（09 §5 P2-9），本轮未动，需产品拍板删或补。

---

## 6. 复跑命令

```bash
cd D:/aapk/ios-app

# 新增闸门
node tools/policygate.js
node tools/keyspace.js

# 全量静态闸门（按 CI 顺序）
node tools/golden.js --check
node tools/swiftcheck.js
node tools/swiftshape.js
node tools/swiftlint.js
node tools/contrast.js
node tools/dynamictype.js
node tools/logicparity.js
node tools/autoopenshadow.js
node tools/zotpshadow.js
node tools/cmdsshadow.js
node tools/parseshadow.js
node tools/bundleshadow.js
node tools/kotlinshadow.js
node tools/destmap.js
node tools/uicoverage.js
node tools/changelogcheck.js
node tools/sheetcover.js --selftest && node tools/sheetcover.js

# 脚本自身语法
for f in tools/*.js; do node --check "$f"; done

# 工作区检查
git diff --check
git status --short
```

**注入正控的安全做法：**

```bash
cp App/Services/LockService.swift /tmp/LockService.bak
sed -i 's/try LockCommand.requireAllowed(cmd)/_ = cmd/' App/Services/LockService.swift
node tools/policygate.js   # 期望退出 1
cp /tmp/LockService.bak App/Services/LockService.swift
node tools/policygate.js   # 期望退出 0
```

---

## 7. 下一刀建议

按“收益 / 风险”排序：

1. **统一备份恢复管线**（覆盖 vs 合并两套成员 remap / owner 修正 / meta 写入）。这是当前最像“同一件事两份实现”的地方，且换机场景不可逆。
2. **共享契约**：`rc` 表、PID 表、命令号仍由 Swift/Kotlin 各写一份；做一份 `Shared/Contract` 并让两端校验，能根除 `-38` 那类漂移。
3. **UI 巨文件拆分**：`RecordsView` 3792 / `CredentialStudio` 3268 / `Sheets` 2972 行，需要编译器在场再动。
4. **只读模式负向测试**：CI 编译通过后，加一组逐族命令的“只读必须被拒”测试；目前只有静态闸门证明“每条命令有策略”，没有运行时证明“策略真的执行”。

---

## 8. 当前工作区状态

- 分支：`main`
- HEAD：`21d92b5`
- **未 commit、未 push**
- 新文件未 `git add`
- `fixtures/*` 的 `M` 仅为行尾标记（内容 diff 为空）
