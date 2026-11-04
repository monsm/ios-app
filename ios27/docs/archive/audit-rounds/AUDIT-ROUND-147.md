# AUDIT-ROUND-147 · 第一百四十七轮：切了静音，另一个页面还显示旧状态

> CI：`1414f20` 已验证绿；`0ecd405` / `305f87c` 待回执。本轮本地提交。

## 1. 怎么找到的：用「判据字面量」入口扫 `kf_` 键的散布

按方法论 §1.1 的三种入口，这轮用**字面量**（`"kf_..."`）扫全仓，找出跨多文件出现的键：

```
跨多文件出现的键: 75
```

75 个里绝大多数是**合理分工**（备份白名单 / 实际读写 / 清理列表）。逐个排除后，
`kf_muted_<mac>` 显得可疑：两个**页面**各有一套读写。

## 2. 逐层核对（差点判错）

| 层 | 结论 |
|---|---|
| `AppModel:126` 读镜像键 | ✅ 是状态投影，不是 accessor |
| `LockSettingsScreen:294` 读本地态 | ✅ 页面本地状态，合理 |
| `LockStatusScreen:134` 读 `app.lock.muted` | ✅ 读投影 |
| **`AppModel.setMuted`** | ✅ **有 `await refreshStatus()`**，投影会刷新 |
| **`LockSettingsScreen:349`** | ❌ **自己写 `DB.store.set`，绕过 `AppModel.setMuted`** |

## 3. 缺陷

```swift
// LockSettingsScreen（旧）
try await LockService.shared.ensureConnected(mac: mac)
try await LockService.shared.setSilent(on)
DB.store.set("kf_muted_" + mac, on)      // ← 绕过了 AppModel
muted = on
```

而 `AppModel.setMuted` 做的是**同一件事 + `await refreshStatus()`**：

```swift
// AppModel.setMuted
try await LockService.shared.setSilent(on)
DB.store.set("kf_muted_" + mac, on)
await refreshStatus()                    // ← 这一句被绕过了
```

后果：在「锁设置」页切了静音，**「锁状态」页（读 `app.lock.muted`）仍显示旧状态**，
直到下次有人手动重读。

## 4. 修法

改走唯一路径：

```swift
let r = await app.setMuted(on)
if case .failure(let e) = r { throw e }
```

## 5. 方法论

**"绕过了封装"往往表现为"少了最后一步"** —— 而不是"写错了"。

| 形态 | 例 |
|---|---|
| 绕过封装 | 本轮：少一句 `refreshStatus()` |
| 绕过校验 | ROUND-139：少一个 `guard lockTime != 0` |
| 绕过清理 | ROUND-47：少一族钥匙串 purge |

判据：**看到一个页面直接操作 `DB`/`LockService` 时，去问"有没有一个引擎函数做同样的事"。**
有，就应该调它 —— 因为那个函数里通常还有你没看到的必要步骤。

## 6. 顺带核对（无缺陷）

`AppModel.setSafeMode` 同样带 `await refreshStatus()` ✅，
而 `LockStatusScreen.writeSafeMode` 走的是 `app.setSafeMode` —— **正确的那一侧**。
（也就是说：`LockStatusScreen` 两处都走 AppModel，`LockSettingsScreen` 只有静音那处绕过。）
