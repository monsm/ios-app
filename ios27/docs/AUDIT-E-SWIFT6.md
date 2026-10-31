# AUDIT-E · Swift 6 并发迁移 / SwiftUI 正确性 / 索引与生命周期 深审

> 审计对象：**live working tree** `D:\aapk\ios-app\ios27`（148 个 Swift 文件，36.6k 行）
> 审计基线：HEAD 在审计期间从 `b6143d4` 一路推进到 `7e062b4`（Lead 并行修复 9 个提交）；本文件所有 `file:line` **在写入前逐条重读当前文件确认，并在写完后二次校验**（见 §6 复核方法）。
> 纪律：**未修改任何 Swift 源码**；只新增本文件。
> 闸门基线：`node Gates/allgates.js` → **15/15 通过**（本文件写作时实测，见 §1.3）。
> 前序状态：`docs/WARNINGS.md`（88 条源码告警 = 62 并发 + 19 未使用 + 2 deprecated）、`docs/VERIFY-FINAL.md`（P0=0 / P1=1 / P2=3 / P3=4，均已修）。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| 覆盖 | 148/148 个 Swift 文件通读或按主题全量扫描；52 个关键位置逐行取证 |
| 新发现 | **P0 = 0，P1 = 2，P2 = 7，P3 = 11**（合计 20） |
| 已在 working tree 修复（本轮 Lead 并行修） | 12 项（§4，标注「already fixed, verify」） |
| Swift 6 迁移剩余 | `docs/WARNINGS.md` 的 62 条并发告警中，**约 49 条已消**（Destinations 43 条 + Router 5 条 + ScreenAwake 2 条 + RecordsModels 2 条 + CaptureShield 4 条中的 3 条），**剩余约 9 条**集中在 `SettingsStore` 与 `SettingsParts`、`CredentialOrgState`（§5） |
| 判定 | 当前 `SWIFT_VERSION=5.0` + `STRICT_CONCURRENCY=complete` 下**无已知会崩的数据竞争路径**；但「切 Swift 6 就红」的债仍在 `SettingsStore` 一处集中，且本轮新发现的 2 个 P1 是**功能级**缺陷（不是并发债） |

**最重要的两件事**（若只修两处）：
1. `AddLockScreen` / `ProtocolTestScreen` 在 `startScan` **返回后立刻**读 `allDiscovered()` —— 扫描窗口还没开始收广播，列表基本恒为空（**配网入口事实上不可用**）。
2. `KeyCreateScreen` 的「改造密码值」走 `addPassword`，它只会 **append 一条新密码**，旧的那条留在锁里与台账里 —— 用户以为改了口令，实际是「多了一把」。

---

## 1. 方法与基线

### 1.1 审计口径

按 `swiftui-expert-skill`（Correctness Checklist / Topic Router）与 `swiftui-pro`（`references/data.md`、`swift.md`、`api.md`）的规则做**规则驱动**扫描，而不是"看一遍觉得还行"：

1. **全量机械扫描**：`@State` 非 private、`ForEach` 身份（`.indices` / `\.offset` / `id: \\.self`）、`@Observable` 是否 `@MainActor`、`ObservableObject`/`@Published` 残留、强解包 `!`、`try!`/`as!`、`Task.detached`、`Task.sleep(nanoseconds:)`、`DispatchQueue.main`、`Timer.scheduledTimer`、`NotificationCenter.addObserver`、`.animation` 缺 `value:`、`String(format:)`、`.toolbar(.hidden,for:)`、`UIScreen.main`、`@FocusState` 是否 private、`@Entry` 默认值是否稳定、`@Binding(get:set:)` 数量。
2. **人工通读**：Shell/AppModel/Router/Destinations/CaptureShield/ScreenAwake/SettingsModel/SettingsParts/RecordsModels/RecordsScreen/DoorScreen/AddLockScreen/KeyCreate*/KeyDetail/MobileKey/Zotp/DFUScreen/LockSettings/LockStatus/SafeMode/Tailgate/DeviceInfo/LinkSense/BLEService/BLEDelegates/DFUKit/Store/StoreState/CredentialOrg*/AutoOpenKit/BackgroundGuard/ToastCenter 等。
3. **每条结论都必须能"打开就看见"**：给出 `file:line` + 该行原文 + 为什么错 + 怎么改。凡"可能/也许"的一律不进 P0–P3 清单，只进 §7 的「观察项」。

### 1.2 部署与语言模式（决定这些告警的严重度）

- `ios27/project.yml:8` → `iOS: "27.0"`；`project.yml:21` → `SWIFT_VERSION: "5.0"`；`project.yml:22` → `SWIFT_STRICT_CONCURRENCY: complete`。
- 因此**当前**并发告警只是 warning；**切 Swift 6 语言模式**才变 error。本报告把这类问题标 `[Swift6-blocker]`，并按"会不会在 Swift 5 下就崩"另判级别。

### 1.3 闸门基线（本文件写作时实测）

```
swiftparse: OK — 148 个 Swift 文件无语法错误（已知语法盲区豁免 14 处）
types: 148 个文件，368 个顶层类型，SDK 白名单 333 项
swiftcheck: OK — 148 个文件括号/字符串/注释全部平衡
tokens / contrast / glass / motion / a11y / dynamictype / reducedmotion / crosprivate /
callsig2 / lineage / workflow / destmap: 全部 OK
allgates: 全部 15 道闸门通过
```

> 注意：**闸门全绿不代表本报告的 P1 不存在**。闸门查的是"语法/令牌/签名/目的地对账"，查不出「扫描窗口没等」「改造变成了新增」这类语义缺陷。

---

## 2. 发现清单（按严重度）

| # | 严重度 | 位置 | 一句话 |
|---|---|---|---|
| E-01 | **P1** | `App/Features/Door/AddLockScreen.swift:429`、`App/Features/Settings/ProtocolTestScreen.swift:142` | `startScan` 是"启动扫描并挂定时器"就返回，调用方紧接着读 `allDiscovered()` ⇒ 列表几乎恒空 |
| E-02 | **P1** | `App/Features/Keys/KeyCreateScreen.swift:205` + `App/Shell/AppModel.swift:361` | 「改造密码值」走 `addPassword`，只会新增一条，旧凭证不删不改 |
| E-03 | P2 | `App/Shell/AppModel.swift:372` | `addPassword` 写死 `owner: nil`，工坊里选的归属成员被丢弃 |
| E-04 | P2 | `App/Features/Settings/SettingsModel.swift:153` `[Swift6-blocker]` | `SettingsStore` 缺 `@MainActor`（唯一还没修的 `@Observable` 单例） |
| E-05 | P2 | `App/Features/Settings/SettingsParts.swift:320`,`:328` `[Swift6-blocker]` | `settingsBinding` / `trialGuardBinding` 在 `@Sendable` 闭包里捕获非 Sendable 的 `keyPath` / `AppModel` |
| E-06 | P2 | `App/Engine/CredentialOrgState.swift:61` `[Swift6-blocker]` | `UNUserNotificationCenter` 回调里把非 Sendable 闭包交给 `DispatchQueue.main.async` |
| E-07 | P2 | `App/Features/Door/LockSettingsScreen.swift:26/319`、`ZotpScreen.swift:24/173`、`SafeModeScreen.swift:128`、`TailgateScreen.swift:108`、`DeviceInfoScreen.swift:22/369`、`AppModel.swift:501` | `await` 之后仍用**计算属性 `mac`** ⇒ 期间换锁会把结果写到新锁（与已修的 RecordsScreen 同一类） |
| E-08 | P2 | `App/Features/Door/AddLockScreen.swift:442` | `inReset: true` 写死 ⇒ 所有扫到的锁都显示「可配网」，`tap()` 里的重置态守卫成了死代码 |
| E-09 | P2 | `App/Features/Door/AddLockScreen.swift:43/324` | 「中止并回滚」按钮置位的 `abortRequested` 全仓**零读取** ⇒ 按钮是假的 |
| E-10 | P2 | `App/Features/Settings/SettingsModel.swift:393` | `lockClockSyncedAt` 只活在内存，却在设置页当"上次校时"展示 ⇒ 重启后恒「从未」 |
| E-11 | P3 | `HouseholdScreen.swift:256`、`MemberArchiveScreen.swift:51`、`MemberDetailParts.swift:28/96`、`RecordDetailScreen.swift:240`、`RecordsScreen.swift:578`、`DoorScreen.swift:232/913`、`LinkSense.swift:236` | `ForEach` 用 `.indices` / `\.offset` 身份（可变集合） |
| E-12 | P3 | `App/Features/Keys/KeysScreen.swift:13/91` | `now` 只在 `onAppear` 刷新 ⇒ 跨零点后到期角标/颜色不更新 |
| E-13 | P3 | `App/Features/Settings/AccessibilityScreen.swift:24`,`:25` 等 | `@State` 镜像 `SettingsStore` 值（双真相） |
| E-14 | P3 | `App/Features/Keys/ShareToAndroidScreen.swift:25`,`:61` | `deliverable` 死代码；「缺手机钥匙」闸门不生效（`build()` 不看它） |
| E-15 | P3 | `App/Engine/AutoOpenKit.swift:392`、`BLEDelegates.swift:75`、`ZipKit.swift:43` | 残留强解包（有隐式守卫但脆） |
| E-16 | P3 | `BLEService.swift:111`、`HardwareService.swift:137`、`LockServiceLink.swift:102`、`LockServiceCredentials.swift:175` | `Task.sleep(nanoseconds:)` 4 处未换成 `for:` |
| E-17 | P3 | `App/Features/Door/DoorScreen.swift:64` 等 4 处 | `.toolbar(.hidden, for: .navigationBar)` 是软废弃写法 |
| E-18 | P3 | `DoorScreen.swift:352`、`AppearanceScreen.swift:285` | 用户可见数字用 `String(format:)`，不走 `FormatStyle`/本地化 |
| E-19 | P3 | `App/Shell/Shell.swift:33` | 标签栏角标在 `body` 里直接读库（每次 body 求值都算一遍全锁到期） |
| E-20 | P3 | `App/Features/Door/UnlockGateScreen.swift:10` | 作为 `Dest` 打开时 `onPass == nil`，验证通过只 dismiss（无动作） |

---

## 3. P1 / P2 逐条取证

### E-01 · P1 · 扫描窗口没等就开始读结果（配网入口事实上不可用）

**位置**：`App/Features/Door/AddLockScreen.swift:429`–`:430`；`App/Features/Settings/ProtocolTestScreen.swift:142`–`:144`；对照实现 `App/Engine/BLEService.swift:165`–`:178`

```swift
// AddLockScreen.swift:429
try await BLEService.shared.startScan(allowDuplicates: true, timeoutMs: 6000)
let found = BLEService.shared.allDiscovered()      // :430 —— 立刻读
```

```swift
// BLEService.swift:165
@MainActor
func startScan(allowDuplicates: Bool = false, intervalMs: Int = 500, timeoutMs: Int = 10000) async throws {
    try await waitReady()
    scanRefLock.withLock { $0 += 1 }
    discovered.removeAll()                            // :169 清空
    scanning = true
    guard let manager else { throw BLEErrorX.code(.notReady) }
    manager.scanForPeripherals(...)                   // :172 只是"启动"
    scanTimer = Timer.scheduledTimer(...)             // :175 6 秒后才停扫
}                                                     // :178 立刻返回
```

**为什么是缺陷**：`startScan` 的 `async` 只 `await waitReady()`（等蓝牙上电），**不 await 扫描窗口**。函数返回时 `discovered` 刚被清空（`:169`），广播还没开始进来。于是 `allDiscovered()`（`:208` `Array(discovered.values)`）基本恒为空数组：
- `AddLockScreen.scan()` → `candidates` 恒空 → 恒走 `:447` 的「没搜到门锁」分支 ⇒ **"添加门锁"这个入口事实上不可用**；
- `ProtocolTestScreen.scan()` → `devices` 恒空 ⇒ 协议测试页也永远"扫不到设备"。

**对照证据（说明这是"这一处写错了"而不是"设计如此"）**：`HardwareService.scanForPIDs`（`HardwareService.swift:126`–`:139`）与 `LockService.scanForMAC`（`LockServiceLink.swift:89`–`:106`）都是同一个 `startScan` 的调用方，它们**在 `startScan` 之后跑一个 `while Date() < deadline` 的轮询循环**再读 `allDiscovered()`。两个页面漏掉了这个循环。

**修法（二选一，推荐 A）**：
- A. 给 `BLEService` 加一个"扫满窗口并返回快照"的便捷方法，页面只调它：
```swift
@MainActor
func scanWindow(allowDuplicates: Bool = false, timeoutMs: Int = 6000) async throws -> [BLEAdvDevice] {
    try await startScan(allowDuplicates: allowDuplicates, timeoutMs: timeoutMs)
    defer { stopScan() }
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
    while Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
    return allDiscovered()
}
```
- B. 页面内照抄 `HardwareService` 的 `deadline` 循环（会多一份重复实现，不推荐）。

**回归验证**：真机/模拟器上点「重新扫描」，列表应在约 6 秒内出现设备（当前是立刻报"没搜到"）。

---

### E-02 · P1 · 「改造密码值」实际是「再新增一条」

**位置**：`App/Features/Keys/KeyCreateScreen.swift:205`（`submit()`）、`:260`（`addPassword` 调用）、`:30`（`@State var editingID`）、`:42`（`isEdit`）；被调方 `App/Shell/AppModel.swift:361`

```swift
// KeyCreateScreen.swift:42
var isEdit: Bool { editingID != nil }

// KeyCreateScreen.swift:205
func submit() {
    if kind != .fingerprint {
        guard codeValid else { ... }
        guard confirmCode == code else { ... }
    }
    ...
    // :260 —— 无论 isEdit 与否，都走"新增"
    let result = await app.addPassword(code, from: fromStr, to: toStr)
```

```swift
// AppModel.swift:361
func addPassword(_ pwd: String, from: String, to: String) async -> Result<Int, Error> {
    ...
    let alias = try await LockService.shared.pwdAdd(pwd: pwd, validFrom: from, validTo: to)  // 新 alias
    var l = DB.ledger(mac)
    l.pwds.append(LedgerPwd(alias: alias, ...))          // :369 只 append
    DB.saveLedger(mac, l)
```

**为什么是缺陷**：入口在 `KeyDetailScreen.swift:213`–`:216`：点「改造密码值」→ `router.request(.dest(.keyCreate))` + `router.pending = .key(id: key.id)`。`consumeRoute()`（`:108`）把 `editingID`/`kindIndex`/`owner`/`code`/`name` 都填好，页面标题也变成「改造凭证」—— 但**`submit()` 完全不看 `editingID`**，仍然走 `addPassword`：
- 锁端多一枚密码（`pwdAdd` 给新 alias）；
- 本机台账多一条 `LedgerPwd`；
- 旧 alias 既没 `pwdExpire` 也没 `pwdDelete`。

用户看到的是「改造成功」，实际后果是**门口多了一把能开门的旧口令**（旧码没作废），同时台账里出现两条同名凭证。这是凭证生命周期层面的错误，不只是 UI 不一致。

**修法**：`submit()` 分叉 —— `isEdit` 时走「改值」路径：`pwdDelete(oldAlias)` + `pwdAdd(newPwd)`（或先 add 成功再 delete，保证"不会把人关在门外"的顺序，与 `FingerprintReEnrollSheet` 的既有纪律一致：**先成功建新，再删旧**），并同步更新台账那一条的 `pwd`/`alias`；失败则整体回滚到旧值。若产品语义就是"改造 = 换一把新的、旧的留着"，那 UI 文案必须改成「新增一条并保留旧码」，且不能显示为「改造凭证」。

**回归验证**：改一次密码后，锁端密码条数应不变（`DB.listPwds(mac).count` 相同），旧码不能再开门。

---

### E-03 · P2 · 工坊里选的归属成员被丢弃（`owner: nil` 写死）

**位置**：`App/Shell/AppModel.swift:361`–`:380`，关键行 `:372`；调用方 `KeyCreateScreen.swift:103`（`ownerName`）

```swift
// AppModel.swift:369-373
l.pwds.append(LedgerPwd(
    alias: alias, from: from, to: to, temp: false,
    at: Date().timeIntervalSince1970 * 1000,
    pwd: pwd, owner: nil, note: "密码 \(alias)"      // ← owner 恒 nil
))
```

**为什么是缺陷**：`KeyCreateScreen` 第 1 步强制选归属（`:184`–`:187` 未选不许前进），`:103` `ownerName` 也算出来了，但**只有指纹那条路径传了 owner**（`:235` `enrollFingerprint(..., owner: ownerName, ...)`）；密码/临时码路径（`:260`）根本没有 owner 形参，`addPassword` 内部写死 `nil`。后果：
- 新建的密码凭证在 `KeysScreen.grouped`（`:33`–`:42`）里永远落进「未归属」组；
- `RecordsSource.owner()`（`RecordsModels.swift:293`–`:297`）按 `members.filter{!archived}` 单成员推断时用的是**成员名**，与凭证 owner 对不上；
- 成员 360 的「名下凭证」（`MemberDetailScreen.swift:42` `app.keys.filter { $0.owner == member.name }`）永远为空。

**修法**：`addPassword` 增加 `owner: String?` 与 `note: String` 形参（或干脆让 `KeyCreateScreen` 改调 `addTempCode` 的通用版本），`KeyCreateScreen.submit()` 传 `ownerName`。写完立刻 `reloadKeys` 已在做，无需额外刷新。

---

### E-04 · P2 · `SettingsStore` 仍缺 `@MainActor`（`[Swift6-blocker]`）

**位置**：`App/Features/Settings/SettingsModel.swift:152`–`:154`

```swift
@Observable
final class SettingsStore {
    static let shared = SettingsStore()
```

**为什么是缺陷**：全仓 8 个 `@Observable` 类里，`AppModel`(`:15`)、`Router`(`:182`)、`RecordsOverlay`(`:168`)、`RecordsRoute`(`:329`)、`LinkSenseModel`(`:11`)、`HouseholdRoster`(`:29`)、`AppToast`(`:20`) 都已标 `@MainActor`；**只剩 `SettingsStore`**。它被 20+ 个视图从主线程读写，但从编译期看没有保证：
- `docs/WARNINGS.md:126` 记录的告警（`static property 'shared' is not concurrency-safe ... 'SettingsStore'`）在当前树里**依然成立**；
- 切 Swift 6 语言模式即 error（`static let shared` + 非 Sendable 可变状态）。

**修法**：`@MainActor @Observable final class SettingsStore`。连带检查 3 个非视图调用点：
- `AccessibilityScreen.swift:11` `static var bigText: Bool { SettingsStore.shared.axBigText }`（`enum AXSettings` 需要一起标 `@MainActor`，或改为 `nonisolated static func` 里直接读 `DB.store`）；
- `TimeDisplay.swift:9` `static var store: SettingsStore { SettingsStore.shared }`（同上）；
- `AppModel.swift:238` `SettingsStore.shared.autoRetry`（`AppModel` 已是 `@MainActor`，无需改）。

**验收**：`xcodebuild` 的 `-strict-concurrency=complete` 告警数应从 9 降到 5 左右；再用 `SWIFT_VERSION=6.0` 试编译一次（CI 单独一轮，不要与功能改动混在一起）。

---

### E-05 · P2 · `settingsBinding` / `trialGuardBinding` 的 `@Sendable` 捕获（`[Swift6-blocker]`）

**位置**：`App/Features/Settings/SettingsParts.swift:320`–`:325`、`:328`–`:336`

```swift
func settingsBinding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
    Binding(
        get: { SettingsStore.shared[keyPath: keyPath] },      // :322
        set: { SettingsStore.shared[keyPath: keyPath] = $0 }   // :323
    )
}
func trialGuardBinding(_ app: AppModel) -> Binding<Bool> {
    Binding(
        get: { app.trialGuard },                               // :330
        set: { v in app.trialGuard = v; TrialGuard.set(v) }    // :332
    )
}
```

**为什么是缺陷**：`docs/WARNINGS.md:127`–`:130` 的四条告警（`keyPath` ×2、`trialGuard` ×2）在当前树里仍然成立。Swift 6 下 `Binding` 的 `get/set` 闭包被当作 `@Sendable`，捕获非 Sendable 的 `ReferenceWritableKeyPath<SettingsStore, Value>` 与 `AppModel` 直接报错。

**修法**（推荐，且顺带修掉 `Binding(get:set:)` 的既有规则问题，见 `references/data.md`「Prefer bindings projected from …」）：
1. `SettingsStore` 标 `@MainActor`（E-04）；
2. 把两个函数标 `@MainActor`（闭包即在主 actor 隔离内，捕获合法）；
3. 更好的写法：让页面用 `@Bindable`。目前页面里的 `store` 是**计算属性**（`private var store: SettingsStore { SettingsStore.shared }`），`@Bindable` 要求局部变量，所以需要每页写 `@Bindable var store = SettingsStore.shared` —— 21 个 `settingsBinding(...)` 调用点可以一次性删掉。这一步是重构，建议与 E-04 同一轮做，但**单独提交**。

---

### E-06 · P2 · 通知回调里把非 Sendable 闭包交给 `DispatchQueue.main.async`（`[Swift6-blocker]`）

**位置**：`App/Engine/CredentialOrgState.swift:52`–`:63`，关键行 `:56`、`:61`

```swift
c.getPendingNotificationRequests { reqs in                 // :54 系统回调，@Sendable
    let stale = ...
    let afterRemove: () -> Void = { scheduleAlertsNow(id: id, p: p, a: a, mac: mac) }   // :56
    if stale.isEmpty { afterRemove(); return }
    c.removePendingNotificationRequests(withIdentifiers: stale)
    DispatchQueue.main.async(execute: afterRemove)          // :61 传非 Sendable 闭包
}
```

**为什么是缺陷**：`docs/WARNINGS.md:73` 记录的就是这一条（`converting non-Sendable function value to '@MainActor @Sendable @convention(block) () -> Void' may introduce data races`）。`afterRemove` 捕获了 `LedgerPwd`/`CredAlert`/`String`（值类型没问题），但它**是闭包本身**在跨隔离域传递；Swift 6 直接拒。

**修法**：不要传闭包，改成"先算参数，再跳主 actor 重建动作"：
```swift
c.getPendingNotificationRequests { reqs in
    let stale = reqs.map(\.identifier).filter { $0 == id || $0.hasPrefix(id + ".") }
    if !stale.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stale) }
    Task { @MainActor in scheduleAlertsNow(id: id, p: p, a: a, mac: mac) }   // 只捕获值
}
```
（`Task { @MainActor in … }` 捕获的是 `id/p/a/mac` 这些 Sendable 值，不捕获闭包。）
顺带：`:61` 的 `DispatchQueue.main.async` 也是 `references/swift.md` 明令避免的 GCD 用法。

---

### E-07 · P2 · `await` 之后仍用计算属性 `mac`（换锁时结果写错锁）

**位置与证据**（全部是同一模式：`private var mac: String { app.lock?.id ?? "" }` 或 `app.currentMac`，在 `await` 前后各读一次）：

| 文件:行 | 计算属性定义 | `await` 后仍读 `mac` 的行 |
|---|---|---|
| `LockSettingsScreen.swift:26` | `private var mac: String { app.lock?.id ?? "" }` | `:322` `ensureConnected(mac: mac)` → `:324` `DB.saveOtpStatus(mac, …)`；`:342`/`:344`；`:360`/`:362` |
| `ZotpScreen.swift:24` | 同上 | `:179` → `:181` `DB.saveOtpStatus(mac, …)` |
| `SafeModeScreen.swift:128` | 同上 | `:128` → `:130` `getStatus(mac: mac)`、`:132` `DB.writeStatus(mac, st)` |
| `TailgateScreen.swift:108` | 同上 | `:108` → `:110` `DB.saveTailgate(mac, …)` |
| `DeviceInfoScreen.swift:22` | 同上 | `:376` → `:378` `DB.writeStatus(mac, st)`、`:380` `BatteryCare.samples(mac)` |
| `AppModel.swift:501` | `currentMac`（计算属性，`:75`–`:81`） | `:504` → `:506` `DB.store.set("kf_muted_" + currentMac, on)`；`syncTime()` `:491`/`:494`；`setSafeMode()` `:512`/`:515` |

**为什么是缺陷**：`await` 是挂起点。期间用户可以从「全部锁 / 换锁」切到另一把锁（`LockPortfolioScreen.swift:148`、`DoorScreen.swift:182` 都会改 `app.overrideMac` + `app.lock = nil` 再 reload），`app.lock` 变 nil 后 `mac` 变成 `""` 或新锁的 id。于是：
- `DB.writeStatus("", st)` 把快照写进空键（`StoreState.swift:25` `"kf_snap_" + mac`）；
- 或把 A 锁的读数写进 B 锁的快照键 ⇒ 门页显示"B 锁电量 82%"而实际是 A 锁的；
- `kf_muted_` 同理：静音位写到新锁上，**用户以为给 A 锁静音了，实际是 B 锁静音、A 锁照响**。

这与 `docs/VERIFY-FINAL.md` §3 已修的 P3「`RecordsScreen.read()` 的 `markSynced(mac:)` 用了计算属性」是**同一类缺陷**，那次修在 `RecordsScreen.swift:837`（`let readMac = mac`）；上面 6 处还没修。

**修法**（每处 3 行）：
```swift
private func writeOtp(_ on: Bool) {
    let mac = self.mac                       // ① 进函数先固定
    guard !mac.isEmpty, !busy else { return }
    ...
    Task {
        ...
        try await LockService.shared.ensureConnected(mac: mac)   // ② 全程用局部常量
        DB.saveOtpStatus(mac, ...)                              // ③
    }
}
```
`AppModel` 三处同理（`let mac = currentMac` 放在 `guard` 之前，函数体只用 `mac`）。

---

### E-08 · P2 · `inReset: true` 写死 ⇒ 重置态守卫是死代码

**位置**：`App/Features/Door/AddLockScreen.swift:442`（构造）、`:475`–`:478`（守卫）

```swift
list.append(Candidate(
    ...
    rssi: d.rssi,
    inReset: true,                                  // :442 —— 恒真
    alreadyAdded: DB.keychain(mac) != nil
))
```

```swift
// :475
guard c.inReset else {
    banner = "「\(c.name)」不在重置态。先在键盘上做物理重置…"
    return
}
```

**为什么是缺陷**：`ZKProtocol.parseAdv` 已经把重置位解析出来了（`ZKProtocol.swift:323` `resetStatus: (frameCtrl & 0x01) != 0 ? 1 : 0`），`Candidate.inReset` 的注释（`:28`）也写着"只有重置态的锁才能换钥"，但构造时**没用**它。后果：
- 列表把每一把扫到的锁都标成「重置态 · 可以换钥」（`:256`），而真机上一把没重置的锁点下去会进 `askConfirm` → `runChain` → `cmd23` 被拒（rc≠0），用户看到的是"配网失败"而不是"这锁还没重置"；
- `:475` 的守卫永远不会命中，是死分支。

**修法**：`inReset: adv.resetStatus != 0`（`adv` 已在 `:433` 拿到）。

---

### E-09 · P2 · 「中止并回滚」是假按钮（`abortRequested` 零读取）

**位置**：`App/Features/Door/AddLockScreen.swift:43`（声明）、`:324`（唯一写入）、`:485`（`startPairing` 未重置它）

全仓检索 `abortRequested` 只有 3 处：声明、按钮置位、`runChain` 里的 `= false`。**没有任何读取**。

```swift
// :42-43
/// 中止请求：链在两帧之间检查它，命中就走回滚，而不是假装跑完。
@State private var abortRequested = false
```
注释承诺了「链在两帧之间检查它」，但 `runChain`（`:489`–`:508`）与 `LockService.pair` 里都没有检查点。

**为什么是缺陷**：这是 `docs/VERIFY-FINAL.md` §7 反复强调要杜绝的那一类「有按钮无效果」的伪入口 —— 用户点「中止并回滚」，界面没有任何变化，配网继续跑（最多在 `pair` 失败时进 `rollback`）。更糟的是它给了"我能停"的错觉：配网写钥阶段用户最需要的就是能停。

**修法（二选一）**：
- A. 真做：把 `abortRequested` 作为 `Task` 取消的桥梁 —— 在 `:485` 把 `Task { await runChain(c) }` 的 `Task` 存进 `@State private var pairTask: Task<Void, Never>?`，按钮调 `pairTask?.cancel()`，`runChain` 每个 `try await` 之后查 `Task.isCancelled` 并走 `rollback("已中止")`；`LockService.pair` 内部也要有 `Task.isCancelled` 检查点（现在 `fpStart` 有，`pair` 没有）。
- B. 删按钮（连同 `abortRequested` 与那段注释），把「中途不要离开这一页」的说明留着。宁可少一个按钮，也不要一个假的。

---

### E-10 · P2 · `lockClockSyncedAt` 只在内存，却被当持久事实展示

**位置**：`App/Features/Settings/SettingsModel.swift:393`（`var lockClockSyncedAt: Int64? = nil`）、写入 `SyncTimeScreen.swift:244`、读取 `SettingsScreen.swift:375`

```swift
// SettingsModel.swift:392-393
/// 上次校准门锁时间的时刻。nil = 从未校准。
var lockClockSyncedAt: Int64? = nil        // 普通存储属性，不落盘
```

```swift
// SettingsScreen.swift:370-376
VListRow(title: "校准门锁时间", …,
         value: store.lockClockSyncedAt.map { TimeFormat.ago($0) } ?? "从未")
```

**为什么是缺陷**：这是 `@Observable` 类的**非 `@ObservationIgnored` 存储属性**，进程重启即回到 `nil`。用户在「校时」页同步成功（`SyncTimeScreen.swift:244` 写它），回到设置页看到「刚刚」，**杀进程再开就变「从未」** —— 而「超过 30 天未校时」正是门页异常提醒卡（`DoorScreen.swift:257`–`:261`）的判据之一，它读的是 `DB.syncTime(mac)`（持久），两个口径互相矛盾：设置页说「从未」，门页的提醒卡却不出现。

同类：`calibrationAt`（`:250`）、`lastSkipReason`（`:251`）、`lastScanAt`（`:269`）也是内存态，但它们的**真值**在 `AutoOpen.autocal` / `AutoOpen.lastReject` / `store.lastScanAt` 里有落盘版本，页面在 `syncAutoOpenState()`（`AutoOpenScreen.swift:214`–`:219`）里会重新同步 —— 只有 `lockClockSyncedAt` 没有任何回读点。

**修法**：删掉这个内存属性，设置页直接读持久真值：
```swift
value: DB.syncTime(app.currentMac) > 0
    ? TimeFormat.ago(Int64(DB.syncTime(app.currentMac)))
    : "从未"
```
`SyncTimeScreen.swift:244` 改成 `DB.saveSyncTime(mac, now)`（该函数已存在，`StoreState.swift:88`）。

---

## 4. 已在 working tree 修复的项（标 already fixed, verify）

> Lead 在本轮并行修了下列项。**我逐条重读当前文件确认代码已变**，因此不作为"未修缺陷"计入 §2；但都需要 CI/真机回归验证（尤其前 3 条属于并发与安全语义）。

| # | 原问题（`docs/WARNINGS.md` / `VERIFY-FINAL.md` 记录） | 当前证据 | 验证要点 |
|---|---|---|---|
| A-01 | `Destinations.view(for:)` 非隔离里构造 `@MainActor` View（43 条告警） | `App/Shell/Destinations.swift:7` `@MainActor` | 切 Swift 6 后这 43 条应清零 |
| A-02 | `Router` 未 `@MainActor`（5 条 `@Sendable` 捕获告警） | `App/Shell/Router.swift:182` `@MainActor` | `Shell.swift:44` 等 5 处 `router.path(for:)` 仍返回 `Binding(get:set:)`（`:231`–`:239`）—— 若切 Swift 6 后仍有告警，改 `@Bindable` + 分路径属性 |
| A-03 | `RecordsOverlay` / `RecordsRoute` 的 `static let shared` 非并发安全 | `App/Features/Records/RecordsModels.swift:168`、`:329` 均 `@MainActor` | 同上 |
| A-04 | `CaptureShield` 用 `UIScreen.main`（iOS 26 deprecated ×2 + 3 条并发告警） | `App/Design/Components/CaptureShield.swift:38` `onReceive(NotificationCenter.default.publisher(...))`；`:44`–`:50` 从 `UIWindowScene.screen` 取；全文已无 `UIScreen.main`、无 `ObservableObject` | 真机录屏时遮罩要真的出现/消失；分屏/外接屏场景确认只跟当前 scene |
| A-05 | `ScreenCare` 非隔离改 `isIdleTimerDisabled`（2 条） | `App/Design/Components/ScreenAwake.swift:8` `@MainActor` | DFU / 录指纹期间屏幕不自动锁 |
| A-06 | 13 处 `execOk` 返回值未使用（`WARNINGS.md` 19 条 NoUsage 的大头） | `LockServiceCredentials.swift:56/69/87/95/207/213`、`LockServiceOps.swift:104/127/134/139/144/155/167` 均已 `_ = try await execOk(...)` | 确认这些调用点**确实不需要** rc（`execOk` 内部已 fail-closed 抛错，见 `LockServiceLink.swift:348`–`:358`），不是"漏判回执" |
| A-07 | `RecordSearchParse` 5 处 `Calendar` 强解包（用户输入"13月1日"可崩） | `App/Engine/RecordSearchParse.swift:73` `addDays(_:_:)` 兜底；`:89`/`:93`/`:97`/`:101` 已 `if let` | 搜索框敲 "2月30日" / "13月1日" / "上周" / "上月" 不崩 |
| A-08 | `DFUKit` 下标在 `count` 判断之后（`bytes[0]` 先于 `bytes.count >= 3`） | `App/Engine/DFUKit.swift:461` `if bytes.count >= 3 && bytes[0] == 0x60`；`:470` `bytes.count >= 2 && bytes[0] == 0x10` | 短回包（1 字节）不越界 |
| A-09 | `BLEService.manager` 隐式解包 `CBCentralManager!` | `App/Engine/BLEService.swift:51` `private(set) var manager: CBCentralManager?`；`:171`/`:218` `guard let manager else` | 冷启动第一时间点扫描不崩 |
| A-10 | `FrameRedact` 只脱敏第一段 hex（旧实现：4096 字符后剩余 hex 明文输出） | `App/Engine/FrameRedact.swift:17`–`:43` 已改为**逐段循环**处理每一个 `hex=`（`:23`），短 hex 也遮成 `<redacted>`（`:37`） | 打一条含两个 `hex=` 的日志，两段载荷都必须被遮 |
| A-11 | `RootView` 无条件 `.dynamicTypeSize(.large)` 压掉系统字号 | `App/LockKeeperApp.swift` 改为 `AXTextSizeModifier(enabled:)`（未启用时**不覆写**） | 系统「更大字号」+ App 大字档四种组合各看一次 |
| A-12 | `LockSettingsScreen` 的 `st!` / `kc!` 三元副作用求值 | `App/Features/Door/LockSettingsScreen.swift:100`–`:106` 改成 `let firmware/bootText/keyboardText` 局部常量 | 无锁/未读快照时显示「未知」「该固件未上报」 |

---

## 5. Swift 6 迁移账（`docs/WARNINGS.md` 62 条并发告警的现状）

| 告警簇 | 原条数 | 现状 | 证据 |
|---|---:|---|---|
| `Destinations.view(for:)` `#ActorIsolatedCall` | 43 | **已消** | `Destinations.swift:7` |
| `Router` `#SendableClosureCaptures` | 5 | **已消**（`Router` 已 `@MainActor`） | `Router.swift:182` |
| `RecordsOverlay`/`RecordsRoute` `#MutableGlobalVariable` | 2 | **已消** | `RecordsModels.swift:168/329` |
| `ScreenAwake` `isIdleTimerDisabled`/`shared` | 2 | **已消** | `ScreenAwake.swift:8` |
| `CaptureShield`（`main actor-isolated default value` / `self` 捕获 / `isCaptured` / `main`） | 4 | **已消**（改为 `@State` + `onReceive`） | `CaptureShield.swift:14`,`:38` |
| `SettingsStore` `#MutableGlobalVariable` | 1 | **仍在** | `SettingsModel.swift:153`（E-04） |
| `SettingsParts` `keyPath` ×2 + `trialGuard` ×2 | 4 | **仍在** | `SettingsParts.swift:322/323/330/332`（E-05） |
| `CredentialOrgState` 非 Sendable 函数值 | 1 | **仍在** | `CredentialOrgState.swift:56/61`（E-06） |
| 合计 | 62 | **约 53 已消 / 9 仍在** | — |

**结论**：切 Swift 6 的阻塞面从「43 条集中在 Destinations」缩到「9 条集中在 Settings 域 + 1 处通知回调」。E-04/E-05/E-06 三项做完，理论上可清零；但**清零≠无数据竞争**：`BLEService`/`LockService`/`DFUSession` 用 `@unchecked Sendable` 承担了大量手写同步（`Locked`、写槽 FIFO、continuation 单槽），这些不在编译器检查范围内（详见 §7 观察项 O-01/O-02）。

---

## 6. 复核方法（可重跑）

1. **锚点式取证**：本文件每条 `file:line` 都是"在写入前对当前文件按唯一子串定位"得到的，而不是沿用旧报告的旧行号（旧报告的行号在 Lead 并行改动后普遍位移 2–15 行，例如 `RecordsScreen.read()` 从 833 变 837、`LockSettingsScreen.overviewCard` 从 96 变 100 并新增 4 行局部常量）。
2. **反向检索**：每个"零读取/零调用"结论都用全仓 grep 复核（`abortRequested` 3 处、`deliverable` 1 处、`copy(_:safeMode:muted:)` 1 处、`passphrase` 1 处、`lockClockSyncedAt` 3 处）。
3. **对照实现**：凡"这个调用点写错了"的结论，都给同一 API 的**正确调用点**作为反证（E-01 的 `HardwareService.scanForPIDs` / `LockService.scanForMAC`；E-07 的 `RecordsScreen.swift:837`）。
4. **不猜**：`try?` 吞错、`@unchecked Sendable`、`DispatchQueue.main` 这类"风格问题"不升级为缺陷，只进 §7。

复现命令：
```powershell
cd D:\aapk\ios-app\ios27
node Gates/allgates.js        # 15/15
node Tools/static-audit.js    # 六类高危模式（报告型）
```

---

## 7. 观察项（不进 P0–P3，但值得记一笔）

- **O-01 `@unchecked Sendable` 的同步靠人肉**：`BLEService`(`:21`)、`DFUSession`(`DFUKit.swift:89`)、`Store`(`Store.swift:6`)、`NotificationDelegate`(`QuickActions.swift:39`) 都声明 `@unchecked Sendable`。它们的正确性依赖 `Locked`(`Locked.swift:23`)、写槽 FIFO(`BLEService.swift:81`)、continuation 单槽（`writeAckLock` `:67`）三套手写协议。**建议**：给 `Locked` 与写槽加一组并发单测（多 Task 同时 `writeFrameHex`，断言无 continuation 泄漏），这是切 Swift 6 前唯一能证伪的路径。
- **O-02 `publishOnMain` 的语义**：`BLEService.swift:44`–`:46` `if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }` —— 类头注释（`:23`–`:32`）记录过真机 SIGBUS（cooperative 线程 512KB 栈上重算 body）。这个补丁是对的，但它依赖"所有 `@Published` 写入都走它"这一纪律；新增写入点必须遵守（当前 3 处都在守）。
- **O-03 `Task.sleep(nanoseconds:)` 4 处**（E-16）：`BLEService.swift:111`、`HardwareService.swift:137/172`、`LockServiceLink.swift:102`、`LockServiceCredentials.swift:175`。功能上没问题，只是与 `references/swift.md`「Never use `Task.sleep(nanoseconds:)`」不符；顺手改成 `Task.sleep(for: .milliseconds(100))`。
- **O-04 `Binding(get:set:)` 仍 9 处**（`Router.swift:233`–`:237`、`SettingsParts.swift:322/323/330/332`、`LockStatusScreen.swift:169`、`AppearanceScreen.swift:441`、`AutoOpenScreen.swift:190/198`）。其中 `LockStatusScreen.swift:169` 的 `Toggle(title, isOn: Binding(get: { isOn }, set: { write($0) }))` 是**经典 bug 形态**：`isOn` 是函数参数（值快照），Toggle 拨动后界面不会回弹也不会前进，直到父视图重算。当前因为 `write` 会走网络并最终刷新 `app.lock` 才"看起来能动"；弱信号下会卡住。建议改为 `@State` 本地 + `onChange` 触发写入。
- **O-05 `ForEach` 身份**（E-11）的实际风险：这些列表元素都是**只读快照**（成员名册、归档名单、同日邻居、最近开门、RSSI 历史），不会在展示期间插入/删除，所以不会立刻出 bug；但 `RecordsScreen.swift:578` 的 `Array(group.items.enumerated()), id: \\.offset` 在**过滤/搜索变化时**会导致整段行状态重建（`:585` 的 `.id(pair.element.id)` 只是给 `scrollTo` 用的锚点，不参与 `ForEach` 身份）。改成 `ForEach(group.items) { entry in … .id(entry.id) }` 即可，同时 `:913` 的 `recentEntries` 已经在用 `id: \\.element.id`（正确写法就在同文件里，可对照）。
- **O-06 `UnlockGateScreen` 作为 Dest**（E-20）：`Destinations.swift` 有 `case .unlockGate: UnlockGateScreen()`，而 `onPass` 默认 nil ⇒ 验证通过只 `dismiss()`。当前唯一真实入口是 `DoorScreen.swift:75`–`:81` 的 sheet（带回调），Dest 是"已登记但无入口"。`docs/VERIFY-FINAL.md` §3 已记过同一条，仍未处理。
- **O-07 `Destinations` 与 `Gates/destmap.js`**：44 个 Dest ↔ 44 条映射（闸门绿）。新增页面时 `Destinations.swift` 的 `@MainActor`（`:7`）意味着**所有 `Dest` → View 的构造都在主 actor 上**，这与 SwiftUI 的约定一致，无需再改。
- **O-08 `AppModel.reload` 的 `refreshStatus` 门槛**（`:105` `if refreshStatus, LockService.shared.connectedMAC == mac`）：只有"当前已连上"才联网读 cmd03。未连上时 `refreshStatus: true` 静默退化成缓存读。这是**刻意的**（避免每次进页面都触发连接），但调用点 `DoorScreen.swift:66`、`SettingsScreen.swift:71` 都传 `true` 并期待"刷新"，实际在未连上时什么也没发生。建议把"未连上"作为可见状态透出（现在门页只显示"未连接"，没有"读数来自缓存"的提示）。

---

## 8. 建议修复顺序（含回归口径）

| 轮次 | 内容 | 为什么这个顺序 | 回归 |
|---|---|---|---|
| 1 | **E-01**（扫描窗口） | 唯一"核心入口不可用"级缺陷；改动局限在 2 个页面或 1 个 `BLEService` 方法 | 真机点「重新扫描」，6 秒内出现设备；协议测试页同 |
| 2 | **E-02 + E-03**（改造=新增、owner 丢弃） | 凭证正确性；两处同文件族，一次改完 | 改一次密码后锁端条数不变、旧码失效；新建密码落在所选成员名下 |
| 3 | **E-07**（6 处 `mac` 快照） | 数据写错锁，隐蔽且影响"静音/临时码/快照"三类事实 | 在「全部锁」页快速切锁，同时点静音/开通临时码，确认写进正确锁 |
| 4 | **E-04 + E-05 + E-06**（Swift 6 三件套） | 独立于功能，单独提交、单独 CI 轮 | `SWIFT_VERSION=6.0` 试编译；`-strict-concurrency=complete` 告警清零 |
| 5 | **E-08 + E-09 + E-10**（假按钮/写死标志/内存态） | 都是"界面说了假话"类，风险低但影响信任 | 逐条按 §3 的"回归验证" |
| 6 | **E-11…E-20**（P3 清尾） | 可与任意功能轮次合并 | 闸门 + 目视 |

---

## 9. 边界（没验的就是没验）

1. **无真机**：本轮全部是静态代码级审计 + 本机闸门；E-01/E-02/E-07 的"实际表现"需要真机或至少模拟器复现（模拟器没有 BLE，E-01 只能在真机验）。
2. **BLE 回执时序**：`LockService`/`HardwareService` 的 waiter/continuation 协议（`LockServiceLink.swift:203`–`:289`、`HardwareService.swift:177`–`:200`）读起来自洽（含"写命令失败不重发"的防双开逻辑 `:264`–`:272`），但"弱信号下是否真的不悬空"只能靠真机 + `O-01` 建议的单测。
3. **并行会话**：审计期间 HEAD 从 `b6143d4` 推进到 `7e062b4`（9 个提交，含 BLE manager 可选化、WebDAV 强制 HTTPS、CSV/vCard 注入防护、privacy 闸门、FrameRedact 重写）。本文件的行号在**写完后**又做了一次全量校验（36 个关键锚点逐行比对，仅 `FrameRedact` 因重写漂移并已就地更正），以 `7e062b4` 时点的 working tree 为准；若后续提交再动这些文件，行号会漂移，**锚点字符串（每条给出的代码原文）比行号更可靠**。
4. **未覆盖**：SwiftUI 渲染性能（Instruments）、无障碍（由 `docs/AUDIT-D-HIG.md` 负责）、安全与加密（由 `docs/AUDIT-F-SECURITY.md` 负责）、交付与 CI（由 `docs/AUDIT-G-DELIVERY.md` 负责）。本文件只在它们交界处做了最小取证（例如 `CaptureShield` 的录屏遮罩、`lockClockSyncedAt` 的事实性）。
5. **"P0 = 0"的含义**：指"没有发现会导致启动即崩、静默丢密钥、无用户操作即丢数据"的路径。E-01 虽阻断配网入口，但它是"功能不可用"而非"数据损坏"，故判 P1；若产品口径把"无法添加门锁"视为发布阻断，则应升级为 P0。
