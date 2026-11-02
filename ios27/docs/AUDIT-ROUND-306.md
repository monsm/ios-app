# AUDIT-ROUND-306 · 第 306 轮：注释里的「幽灵引用」全扫

> CI：`1897666` build 全绿（errors=0）。

## 1. 方法：把「注释里提到的自家类型」与「真实声明」求差

| 步骤 | 数量 |
|---|---|
| 注释中形如 `*Kit/*Store/*Service/*Screen/*Model/*Hub/…` 的名字 | 46 |
| 排除：Apple 框架名（`UIKit`/`CryptoKit`/`UIScreen`/`AnyLayout`…） | — |
| 排除：**同名文件**（注释指的是文件名，如 `BackupStudioKit.swift` 里类型其实叫 `BackupStudio`） | — |
| 排除：已注明「已删除」的（`DestroyKit`/`AlarmKindsScreen`） | — |
| 剩余 | **21** |
| 其中真问题 | **1** |

## 2. 真问题：`LockScreen` 不存在

`AppLock.swift:109` 写：

> **只在没设胁迫码时可用**（调用方 `LockScreen` 用 `!DB.hasDuressCode()` 把关）

而全仓**没有 `LockScreen` 这个类型**。真正的把关点是 `LockKeeperApp.swift:271`：

    bioAvailable = !DB.hasDuressCode() && DB.store.getBool("kf_bio_unlock", true) && canUseBiometric…

已把注释改成 `LockKeeperApp`，并注明「原写 `LockScreen`，全仓没有这个类型」。

## 3. 顺带修：`MembersDetailScreen` 多了一个 s

`MemberDetailParts.swift:3` 写「`MembersDetailScreen` 已过 400 行」，实际类型是 **`MemberDetailScreen`**（单数）。

## 4. 其余 20 条为什么不算问题

| 类别 | 例子 |
|---|---|
| Apple 框架/类型 | `UIScreen` `ViewBuilder` `AnyLayout` `UIKit` |
| **历史文件名**（注释在说「来源：原 X.swift」） | `LinkSenseKit` `AccessibilityKit` `DFUKit` |
| 已注明删除 | `DestroyKit` `AlarmKindsScreen` |
| 外部平台 | `LockStore`（Android 的 `LockStore.kt`） |

## 5. 方法论

**代码里的幽灵引用会让读者白找一趟 —— 而它的检测成本极低，只是「名字集合求差」。**

| 引用类型 | 检测方式 |
|---|---|
| 类型名（本轮） | 注释里的 CamelCase ↔ `struct/class/enum/protocol` 声明集 |
| 函数名 | 注释里的 `foo(` ↔ `func foo` |
| 行号 | 注释里的 `File.swift:123` ↔ 该文件是否真有 123 行 |

判据：**「注释提到的标识符」也应当被当成可校验的引用 —— 它和代码一样会过期，而且过期后误导性更强（读者会以为是自己没找到）。**
