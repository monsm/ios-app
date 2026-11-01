# AUDIT-ROUND-243 · 第 243 轮：`owner` 口径的**另外两个写入点**（同族漏两处）

> CI：**`42e5134` build 全绿**（凭证计数对齐编译通过）。

## 1. 缺陷

Round 237 修了 `addPassword` 的 owner 口径，但全仓还有**两个**写 `owner` 的地方没修：

| 写入点 | 调用方传的是 | 后果 |
|---|---|---|
| `enrollFingerprint`（指纹录入） | `ownerName`（**名字**，工作室成员行） | 录完的指纹恒显示「未归属」 |
| `addTempCode`（成员向导第 4 步） | `memberName`（**名字**） | 向导生成的临时码恒显示「未归属」 |

两者与 `addPassword` 是**同一个坑**：台账 `owner` 在成员管理/合并/恢复路径里存的是 id，
而读侧 `ownerName` 按 id 查。

## 2. 修法

把换算抽成 `AppModel.memberID(for:)`，三个写入点共用：

| 写入点 | 现在 |
|---|---|
| `addPassword` | `memberID(for: owner)` ✅ |
| `enrollFingerprint` | `memberID(for: owner)` ✅ |
| `addTempCode` | `memberID(for: owner)` ✅ |

全仓 `LedgerPwd(` / `LedgerFp(` 构造点共 **3 处**，已全部覆盖。

## 3. 为什么这轮才抓到

Round 237 我是**从 `keyCount` 反查**发现 `addPassword` 的，修完就收工了 ——
**没有回头 grep 同类构造点**。

| 做法 | 结果 |
|---|---|
| 修发现的这一处 | 1/3 |
| **修完 grep 同类构造点** | **3/3** |

## 4. 方法论

**「修一处」和「修一类」的差别，就在于修完之后那一次 grep。**

判据：**任何一次「某函数把 X 写成了 Y」的修复，都要立刻 grep `X(` 的所有构造点，逐个确认。**
本仓这条纪律写成闸门不现实（口径是语义的），只能靠流程 —— 所以写进方法论文档。
