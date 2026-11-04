# AUDIT-ROUND-244 · 第 244 轮：加完凭证，「名下 N 枚」不跟着变

> CI：**`d08ae9d` build 全绿**（rcHint 指路修复编译通过）。

## 1. 缺陷

`MemberCard.keyCount` 是**从 `keys` 派生**的：

```swift
keyCount: keys.filter { $0.owner == m.id || $0.owner == m.name }.count
```

而 `reloadMembers()` 只在 `reload()` 里被调用（`reloadKeys(mac)` → `reloadMembers()` → `reloadEntries`）。

**六个单独写入点只调了 `reloadKeys(mac)`**：

| 写入点 | 后果 |
|---|---|
| `addPassword` | 加完密码，「家」页「名下 N 枚」不变 |
| `enrollFingerprint` | 录完指纹，同上 |
| `addTempCode` | 向导临时码，同上 |
| 删密码 / 换钥 / 手机钥匙签发 | 同上（数字只会滞后，不会错） |

用户看到的是「我刚给他加了凭证，成员卡片还写着 3 枚」—— 要等下一次整页 reload 才对。

## 2. 修法

把 `reloadMembers()` 放进 `reloadKeys()` 末尾（`keyCount` 本来就依赖 `keys`，重建 keys 就必须重建成员），
并把 `reload()` 里那句显式调用去掉（避免重复，且注释说明为什么）。

这样**六个写入点 + 五个 UI 调用点一次性全部覆盖**，不用逐个补。

## 3. 方法论

**「派生数据」的正确刷新点，是它**依赖源**被重建的地方，不是每个调用者。**

| 修法 | 覆盖 |
|---|---|
| 在每个写入点后面补一句 `reloadMembers()` | 6 处，且以后新增写入点还会漏 |
| **放在 `reloadKeys()` 里** | **1 处，自动覆盖所有现在与将来的调用** |

判据：**当一个值是"从 X 算出来的"，就让它在 X 重建时自动跟着重建 —— 别指望每个调用者都记得。**
（这与 Round 227/229 那条「派生数据要随删」是同一族纪律的两个方向：删的时候要清，算的时候要跟。）
