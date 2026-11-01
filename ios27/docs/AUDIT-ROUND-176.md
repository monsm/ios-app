# AUDIT-ROUND-176 · 第 176 轮：再扫 4 类模式，删掉 1 个死函数

> CI：**`a58a24b`（开锁修复）已验证绿** —— `build_ok=1`、`errors=0`、`warnings=0`。
> `42e1cd6` 待回执。

## 1. 本轮扫的模式与结果

| # | 模式 | 命中 | 结论 |
|---|---|---|---|
| A | 存储键「只写不读 / 只读不写」 | 3 + 8 | 见 §2，全部有解释 |
| B | `private func` 定义但零调用 | 4 | 3 个是 `.map(fn)` 传引用；**1 个真死** → 已删 |
| C | `@State` 用会变化的外部值初始化（只取一次快照） | 6 | 全是 `@Observable` 引用或表单初值，合理 |
| D | `.sorted` 比较器用 `>=`/`<=`（非严格弱序） | 9 | 全是无参 `.sorted()` 或严格 `<`，✅ |
| E | 浮点数用 `==` 比较 | **0** | ✅ |

## 2. 存储键审计（这是本轮最值钱的一张表）

### 只写不读（3）

| 键 | 判定 |
|---|---|
| `kf_duress` | ✅ 通过 `duressKey` / `decoyRecordKey` 常量读取，扫描没识别 |
| `kf_logcache_` | ✅ 通过拼接读取 |
| `kf_passcode_weak` | ✅ 只是**清理旧版本遗留键**（两处 `remove`），从没写过也没读过 —— 防御性清理，正确 |

### 只读不写（8）

| 键 | 判定 |
|---|---|
| `kf_calias_display` | ✅ 仓库已明确记录："有读、全仓没有 setter —— 这个开关目前改不了"（`CredentialOrg.swift:18`）|
| `kf_speek_sharehalf` | ✅ 同为已记录项（`LockGuard.swift:10`：默认值就决定它一直在起作用）|
| `kf_trial_guard` | ✅ **有 setter**（`TrialGuard.set`），只是键名走常量，扫描没识别 |
| `kf_mkey_` / `kf_snap_` | ✅ 键名由函数拼接（`storeKey(mac)` / `"kf_snap_"`），扫描只看到读端 |
| `kf_rdispo` | ✅ `TODO(engine)` 明确写着"真实现落 kf_rdispo"，是**未接线的已知项** |
| `kf_week_start` | ✅ 已标「保留未接」 |
| **`kf_debug_raw`** | ⚠ 只读、无 setter。它只控制 4 条 hex 日志，所以那 4 行永不执行。**但不是 bug**：这是开发者键，可在模拟器上 `defaults write` 打开，只是没有 App 内开关 |

## 3. 删掉的死函数

```swift
// LockStatusScreen.swift:356（已删）
private func copy(_ lock: LockSummary, safeMode: Bool, muted: Bool) -> LockSummary {
    LockSummary(id: lock.id, name: lock.name, ..., safeMode: safeMode, muted: muted)
}
```

它构造一个"覆写了 safeMode/muted"的 `LockSummary` 副本 —— 是本段之前**乐观本地投影**留下的工具。
前几轮把静音/安全模式改成走 `AppModel.refreshStatus()` 之后，它就没有调用者了。

**留着它的害处**：下次有人想"本地改一下状态"时会先找到它，从而**绕过刷新**——
那正是 ROUND-147/149/150 三次修的同一类 bug 的入口。删掉等于把那个入口关死。

## 4. 方法论

**死代码的害处不只是"占地方"，它会成为"错误做法的示范"。**

| 死代码类型 | 害处 |
|---|---|
| 死常量 / 死类型 | 让人以为有这个能力 |
| **死辅助函数（本例）** | **提供一个"看起来能用"的捷径，把后来者引向已被修掉的旧做法** |

所以删除优先级应当是：**先删"封装了错误做法"的死代码**，再删纯占位的。

另一条：**键名审计要连同"键是怎么拼出来的"一起看。**
本轮 8 个只读键里有 4 个是假红（键名由函数/常量构造），
如果只看字面量就会误报一半。
