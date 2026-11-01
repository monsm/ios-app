# AUDIT-ROUND-133 · 第一百三十三轮：四态枚举被写成二分支

> CI：`cab0218` 已验证绿；`78d2e0d` / `8335306` 待回执。本轮本地提交。

## 1. 缺陷：`HHMemberStatus` 有四个值，两处只判了两种

```swift
enum HHMemberStatus: Hashable { active, stale, never, archived }
```

而 `HHMemberRow` 里：

| 位置 | 原写法 | 后果 |
|---|---|---|
| 第 266 行 | `status == .stale ? "久未用" : "活跃"` | **`never`（还没用过）与 `archived`（已归档）都显示成「活跃」** |
| 第 259 行 | `status == .stale \|\| status == .archived ? 灰 : 主色` | **`never` 用了主色**（它其实不该是"活跃"色） |

第一条是**语义错误**：一个从没用过钥匙的成员、或一个已归档的成员，在名册里被标成「活跃」。

## 2. 为什么它容易被漏

因为**同一份语义在别处已经写全了**：

```swift
static func statusWord(_ status: HHMemberStatus) -> String {
    switch status {
    case .active: return "活跃约"
    case .stale: return "久未用"
    case .never: return "还没用过"
    case .archived: return "已归档"
    }
}
```

`HHDisplay.statusWord` 就在**同一个文件的下方 30 行**，四分支齐全 ——
而 `HHMemberRow` 自己写了个二分支，没复用它。

**"两处各写一套同一语义"正是这类缺陷的温床**：写的时候都是对的（各自看着都合理），
但枚举一扩，只有 `switch` 那份会被编译器强制更新（`switch` 穷尽检查），
而三元表达式**不会**报错。

## 3. 修法

| 位置 | 改为 |
|---|---|
| 第 266 行 | `Text(HHDisplay.statusWord(status))` —— 直接复用四分支 |
| 第 266 行颜色 | `status == .active ? V.C.rewardGreen : V.C.text3` |
| 第 259 行 | `status == .active ? V.C.text2 : V.C.text3`（四态里只有 `active` 是"活跃"） |

## 4. 方法论

**"用 `switch` 而不是三元表达式处理枚举" —— 因为 `switch` 有穷尽检查。**

| 写法 | 枚举新增一值时 |
|---|---|
| `switch` | **编译报错**（non-exhaustive switch） |
| 三元 / `if` | **静默走 else 分支** |

所以本仓的纪律应当是：**凡是枚举分支逻辑，优先 `switch`**；
确实要用三元的（如颜色这种"两个视觉档"），要**写明另外几档归到哪边**（本轮第 259 行就是这么修的）。

## 5. 顺带一个假阳性（记下来）

我一度以为 `HHPageHeader` 里 `VStateDot(tone:word: status)` + `Text(status)` 是**重复显示**。
读了 `VStateDot` 的定义才发现：它**只画形状**，`word` 仅用于 `accessibilityLabel`，
不进视觉 —— 所以「形状 + 文字」正是两通道的正确搭配，不是重复。

这是本段第 4 次"看起来是缺陷、读实现后不是"（前三次见 ROUND-121/130/132）。
