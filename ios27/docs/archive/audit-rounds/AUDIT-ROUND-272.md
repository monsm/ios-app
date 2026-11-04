# AUDIT-ROUND-272 · 第 272 轮：`restore` 改 `throws` 后，**金标测试的 6 处调用没加 `try`**

> CI：`6c20d1c` build 全绿，但**队列积压**，`77b60ca`（改签名那轮）还没构建。
> 于是本轮改为**静态自证**：全仓搜 `BackupStudio.restore` 的每一个调用点。

## 1. 发现的隐患（我上一轮引入的）

上一轮给 `BackupStudioKit.restore` 加了 `throws`，只补了 **3 处 UI 调用点**的 `try`。
而全仓还有 **6 处**在测试里：

| 文件 | 行 |
|---|---|
| `BackupRoundTripTests.swift` | 110 / 128 / 143 / 162 / 166 / 202 |

**这些没加 `try` ⇒ 金标 job 编译失败 ⇒ 82 个用例全不跑。**
而 `allgates` / `swiftparse` 都**查不出**这类错误（它们不做类型检查）。

## 2. 修法

6 处补 `try`。先确认承载它们的测试函数已是 `throws`：

| 测试函数 | 签名 |
|---|---|
| `testRestoreBringsBackCredentials` | `throws` ✅ |
| `testOwnershipIsDroppedWhenMemberAbsentLocally` | `throws` ✅ |
| `testMergeNeverDeletesLocalCredentials` | `throws` ✅ |
| `testInvalidSkeyIsSkipped` | `throws` ✅ |

所以只需补 `try`，不必改函数签名。全仓现在 9 处调用点**全部带 `try`**。

## 3. 方法论

**改函数签名时，调用点清单必须来自「全仓 grep」，不能来自「我改过的那个文件」。**

| 找调用点的方式 | 会不会漏 |
|---|---|
| 顺着报错找 | 漏（还没编译就不知道） |
| **全仓 grep 函数名** | ✅ 本轮靠它抓到测试里的 6 处 |

判据：**任何 `throws` / 返回值 / 参数变化，先 grep 全仓调用点（含 Tests/），再改。**
另：`allgates` 与 `swiftparse` 是**文本级**闸门，类型错误只能靠 CI —— 所以 CI 积压时要自己做静态核对。
