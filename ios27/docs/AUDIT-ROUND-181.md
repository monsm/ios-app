# AUDIT-ROUND-181 · 第 181 轮：共用错误槽 `lastError` 的「串味」与「永远看不到的警告」

> CI：**`3ccfc9a`（12/24 制式，12 文件）已验证绿** —— build_ok=1 errors=0 warnings=0。
> `a2d143d` 待回执。

## 1. 缺陷 A：`lastError` 只在失败时写、成功时不清

`AppModel.lastError` 是一个**跨功能共用的单一错误槽**，而三个页面都靠「它非 nil」判断本次操作失败：

```swift
DoorScreen:1102       if let err = app.lastError { ... }
LockStatusScreen:351  outcome = app.lastError == nil ? "已重新读取锁实况" : app.lastError
RecordsScreen:871     if let err = app.lastError { readNote = "读取失败 · " + err }
```

但 `refreshStatus()` 与 `readLogs()` **只在 catch 里写它、成功时不清**：

```swift
func refreshStatus() async {
    do { ... } catch { lastError = ... }     // 成功路径：lastError 原封不动
}
```

### 症状（可复现的时序）

| 步骤 | `lastError` |
|---|---|
| 1. 用户「改造密码值」，旧码删失败 | `"新码已写入，但旧码（#3）没能删除…"` |
| 2. 用户去记录页点「读取」 | 读取**成功**，槽没清 |
| 3. `RecordsScreen:871` 读到非 nil | 界面显示 **"读取失败 · 新码已写入，但旧码（#3）没能删除…"** |

**一次成功的读取，弹出了上一件事的错误。** 三个页面都有这个毛病。

### 修法

与 `runUnlockChain` 已有的写法对齐 —— **开工先清槽，失败再写**：

```swift
lastError = nil
do { ... } catch { lastError = ... }
```

加在 `refreshStatus()` 与 `readLogs()` 开头（`runUnlockChain:250` 本来就这么写，是这两处漏了）。

## 2. 缺陷 B：`addPassword` 的「部分成功」警告**永远看不到**

```swift
// AppModel.addPassword
} catch {
    lastError = "新码已写入，但旧码（#\(old)）没能删除 —— 请到凭证详情再删一次。"
}
```

而唯一的调用方成功分支直接跳走，**从不读 `lastError`**：

```swift
// KeyCreateScreen（旧）
switch result {
case .success:   router.keysPath = []      // ← 警告被丢在这里
case .failure:   errorText = ...
}
```

于是这条精心写好的提醒只有两个结局：**要么永远没人看到，要么被别的页面误当成它自己的失败**（缺陷 A）。

### 修法

```swift
case .success:
    if let warn = app.lastError { AppToast.shared.show(warn, tone: .warn); app.lastError = nil }
    router.keysPath = []
```

**缺陷 A 与 B 是同一条链的两端**：清槽修好了"串味"，但如果不补这一步，警告就变成"静默丢弃"。
只修 A 等于把"显示错地方"换成"不显示"。

## 3. 本轮另外 1 项「审过、判定合理」

| 疑点 | 结论 |
|---|---|
| `try?` 吞掉写操作失败（13 处） | ✅ 全是 best-effort：文件属性、诊断日志写盘、删除多余备份；唯一关键的 `data.write` 那处写的是 `(try? ...) != nil else { return false }`，**失败有返回值** |

## 4. 方法论

**共享可变状态的两个反面：串味（别人写的被当成你的）与丢失（你写的没人读）。**

| 形态 | 表现 |
|---|---|
| **串味** | 成功操作弹出上一次的错误 |
| **丢失** | 精心写的警告只活在内存里 |

两者常常同时存在于同一个槽上 —— 因为它们都是"没有明确的所有者"：
**谁写、谁读、谁清，三件事没有写在一处。**

判据：**给一个共享槽（错误、提示、加载态）加新的写入方之前，先问"谁负责清"**。
本轮之前 `lastError` 的答案其实是"没人"——只有 `runUnlockChain` 自己记得清。
