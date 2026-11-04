# AUDIT-ROUND-6 · 第六轮：P3 清零（含一个"看着成功、其实没做"的功能缺陷）

> 执行日期：2026-11-01 05:20 → 06:00（+08:00）
> 起点 `c822ce8` → 终点 `0c430bc`
> CI：BUILD SUCCEEDED + ARCHIVE SUCCEEDED + errors=0（run `41243973740`）

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **4 项**（P3 × 3 + G-12 从"文档降级"升级成**真修**） |
| 闸门 | 17 / 17 |
| 静态扫描 | P0 0 · P1 0 · P2 23 · P3 9 |
| 测试 | 31 条（16 金标 + 15 安全回归） |

---

## 1. E-15 · `UnlockGate` 作为 Dest 时**验完密码什么都没做**（本轮最值得记的一条）

`UnlockGateScreen` 是"30 秒内二次开锁要先输本机密码"那道闸。它通过 `onPass` 回调执行真正的开锁：

```swift
UnlockGateScreen { Task { await app.runUnlockChain() } }   // 门页 sheet：正确
```

但它同时被登记成 `Dest`（`Router.swift:30` → `Destinations.swift:31` → `UnlockGateScreen()`），
**没有传回调** ⇒ `onPass == nil` ⇒ 用户输对密码后：

```swift
case .success:
    error = nil
    onPass?()      // ← nil，什么都不发生
    dismiss()      // ← 页面直接关掉
```

**门没开，也没有任何提示**。用户会以为"确认过了"，再点一次圆盘 —— 而那次又会因为 30 秒窗口再弹一次闸。
这是本 App 最该避免的一类错误：**界面说成功了，实际什么都没做**。

修法：缺省值不再是"什么都不做"，而是执行真正的开锁链。

```swift
if let onPass { onPass() } else { Task { await app.runUnlockChain() } }
```

同时给预览注入 `AppModel`/`Router`（否则 Preview 会崩在 "No Observable object of type AppModel found"）。

### E-16 · 标签栏角标在 `body` 里读库

`Shell.tabItems` 把 `CredentialOrg.expiringSoonCount(macs: DB.keychains()…)` 写在计算属性里，
而 `tabItems` **每次 body 求值都会算** —— 切 Tab、开任何 sheet、任何 `@Observable` 变化都触发。
等于"每次界面刷新都读一遍 UserDefaults 并遍历全部锁的台账"。

修法：数值移进 `@State keysBadge`，只在 `task` / 切 Tab / 换锁时重算。

### G-08 · README 的 ⌘R 路线缺"要选 Team"这一步

`project.yml` 是 `CODE_SIGN_STYLE: Automatic` 且**没有** `DEVELOPMENT_TEAM`（写死等于把某个人的 Team ID 强加给所有人）。
但 README 只写"打开工程后 ⌘R"，照着做会撞上
`Signing for "LockKeeper" requires a development team`，让人以为工程坏了。

现在 README 明写：⌘R 前要在 Signing & Capabilities 里选自己的 Team（一次，本地生效不进仓库），
并说明 CI 全程 `CODE_SIGNING_ALLOWED=NO` 所以不需要 Team。

---

## 2. G-12 · 从"文档降级"改成**真修**

前几轮的结论是"`CBCentralManager` 没有 restore identifier ⇒ DFU 抗进程回收做不到，
文档应降级为'后台尽力'"。这一轮把它真修了：

```swift
// BLEService.bootstrap()
CBCentralManagerOptionRestoreIdentifierKey: Self.restoreId   // "com.aapk.lockkeeper.central"
```

```swift
// BLEDelegates：系统在后台唤起 App 时把已连外设交回来
public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    guard let p = peripherals.first(where: { $0.state == .connected }) else { return }
    p.delegate = self
    device = p
    connectedPeripheralId = p.identifier.uuidString
    p.discoverServices(nil)     // 重新发现服务，notifyChar/writeChar 才能在回调里复位
}
```

**为什么必须两个都做**：只加 restore identifier 而不管 `willRestoreState`，系统把外设交回来时
没人接住 ⇒ `device` 仍是 `nil` ⇒ 后续 `writeFrameHex` 判"未连接" ⇒ 用户看到"升级莫名其妙中断"。
那比不加更糟：**看起来有恢复能力，实际没有**。

底层只负责"承认这条连接还在"，**不重放业务动作**（是否续传由上层决定）——
引擎层不该猜用户意图。

`Gates/sdk-types.txt` 白名单同步补了两个 CoreBluetooth 常量（`types` 闸门当场就抓到了，这就是它的价值）。

---

## 3. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过
tests: 2 个测试文件，176 条断言

$ node Tools/static-audit.js
P0=0 P1=0 P2=23 P3=9

$ git show origin/ci-log:meta.txt
commit=0c430bc… run=41243973740  errors=0  build_ok=1  archive_ok=1
```

---

## 4. 仍未闭环

### P2（6 项，全部需要设备或外部确认）
- **SEC-01 残余**：Swift `String` 无法可靠清零，进程内仍有一份明文口令副本（平台限制）。
- **SEC-18 残余**：手机钥匙撤销走 `cmd08`，锁端失败时本机记录如何处置**需真机确认**。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— **固件限制**，App 侧无法根治。
- **SEC-26**：`ITSAppUsesNonExemptEncryption: NO` 对自研 AES 的出口合规归类**需法律复核**。
- **G-14**：Release 资产名用上传时刻，无法从文件名反查 commit。
- **SEC-01 Keychain 单测**：未签名测试宿主没有权限 ⇒ CI 上 `skipped`，只在签名环境真跑。

### P3（9 项，均为只读快照或已软废弃）
`ForEach` 下标身份若干处、`.toolbar(.hidden, for:)` 软废弃、
`@unchecked Sendable` 三套手写同步协议缺并发单测。

### 需要真机/人工的（CI 替代不了，也是本轮之后的主要缺口）
SwiftUI 真实渲染与**浅色主题观感**、手势手感、进度弧节奏、触觉反馈、
BLE 回执、指纹录入、DFU 真实续传（G-12 改完之后**正好需要真机验证**）、WebDAV 真实链路。
