# AUDIT-ROUND-191 · 第 191 轮：搜索标签的重复 ID（SwiftUI 视图身份 bug）

> CI：`c79c84c` 已验证绿；`ea66e90` / `82f65a3` 待回执。

## 1. 缺陷

`RecordSearchParse` 按输入 token **逐个 append**：

```swift
q.parsedTags.append(String(tok))     // 每个 +xxx / -xxx / 时间短语各一条
```

而记录工作室用 `id: \.self` 渲染它们：

```swift
ForEach(parsed.parsedTags, id: \.self) { tag in   // ← ID 必须唯一
```

用户写 `+指纹 +指纹`（或重复一个时间范围）就会产生**两个相同的字符串** ⇒ 两个相同 ID。

SwiftUI 对重复 ID 的行为：

| 后果 | 说明 |
|---|---|
| 控制台警告 | "ID occurs multiple times within the collection, this will give undefined results" |
| 视图身份错乱 | 标签可能错位、复用错误视图、动画时闪烁 |
| 不崩 | 所以**不会有人发现**，直到某次列表变化看起来"怪怪的" |

## 2. 修法

显示前按首次出现去重（解析结果本身不动）：

```swift
private var uniqueTags: [String] {
    var seen = Set<String>()
    return parsed.parsedTags.filter { seen.insert($0).inserted }
}
```

## 3. 同族排查：46 处 `ForEach(id: \.self)`

全部过了一遍，按"元素是否可能重复"分类：

| 类别 | 结论 |
|---|---|
| 字面量数组（`[10,15,20,25]` / `["一","二",…]`） | ✅ 天然唯一 |
| 区间/索引（`0..<n` / `x.indices`） | ✅ 唯一 |
| `Set` 派生（`LockPortfolio.groups` = `Array(Set(...)).sorted()`） | ✅ 已去重 |
| 搜索历史（`CredentialOrg.searchHistory()`） | ✅ `pushSearchHistory` 里 `filter { $0 != t }` 去重 |
| 成员名（`memberOptions` / `members`） | ✅ `addMember` 拒绝同名 |
| **`parsedTags`** | ❌ **可能重复** → 本轮修 |

## 4. 本轮另外 2 项「审过、判定正确」

| 疑点 | 结论 |
|---|---|
| `Task` 句柄是否有取消点 | 6 个句柄（`flashTask` / `pollTask` / `pairTask` / `holdTask` / `hideTask` / `autoLockTask`）**全都有 `.cancel()`** ✅ |
| `.onChange` / `.task(id:)` 里的长循环 | 有 `while`/`Task.sleep` 的块都带 `Task.isCancelled` 或 `try? await Task.sleep` ✅ |

## 5. 方法论

**"ID 必须唯一"是 SwiftUI 的硬约束，而它不会崩 —— 只会悄悄错。**

| 写法 | 什么时候炸 |
|---|---|
| `ForEach(array, id: \.self)` | 数组里出现**相等元素**时 |
| `ForEach(array)`（Identifiable） | id 重复时（同上，但更显式） |

判据：**用 `id: \.self` 前问一句"这个集合保证元素唯一吗"**；
答不上来就去重（`seen.insert(...).inserted` 是本仓已有的写法）。

这类缺陷尤其阴险：它**不报错、不崩、多数时候看起来正常** ——
所以只能靠"逐个 `id: \.self` 检查元素唯一性"这种笨办法。
