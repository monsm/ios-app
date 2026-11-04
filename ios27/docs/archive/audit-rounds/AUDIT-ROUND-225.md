# AUDIT-ROUND-225 · 第 225 轮：累计开锁次数漏掉自动开锁 + 一个真死计数

> CI：`9977e77` 全绿，且 **`project=yes` / `swift_files=150` 已出现在回执里**（Round 222 的诊断改进生效）。

## 1. 缺陷 A：`recordUnlockSuccess()` 只数手动开锁

```swift
// 全仓唯一调用点：AppModel 手动开锁成功路径
Milestones.recordUnlockSuccess()
```

而自动开锁成功（`AutoOpenController` 的 `case 0`）**从不调用它**。

界面写的是：

```swift
.accessibilityLabel("累计开锁 \(store.unlockTotal) 次")
```

**没有任何限定词**。于是天天靠自动开锁进门的人会永远看到「累计开锁 0 次」。

### 修法

`case 0` 成功分支补 `Milestones.recordUnlockSuccess()` —— 两条开锁路径同一口径。

## 2. 缺陷 B：`organizeTotal` / `recordOrganize` 是**真死代码**

| 检查 | 结果 |
|---|---|
| `organizeTotal` 读取处 | **0**（只有定义） |
| `recordOrganize` 调用处 | **0** |
| 有 `【保留未接】` 标记？ | ❌ |
| 注释里写了接线点？ | ❌ |

按本仓纪律（无接线点 + 无标记 = 真死代码）删除，与 `quota` / `DiagFlags.silent` / `Advice` / `DiagOp` 同一处置。
原地留一段注记，说明**为什么删** —— 免得下一个人从 git 历史里翻出来又加回去。

## 3. 本轮另外 1 项「审过、正确」

| 检查 | 结论 |
|---|---|
| `recordBackup` 覆盖度 | ✅ 3 个调用点（备份页 + 备份工作室两处），三条导出路径都记 |

## 4. 方法论

**「计数器」最容易骗人，因为它看起来像个事实。**

| 检查 | 能发现什么 |
|---|---|
| 计数器有 UI | 只能说明「有人在显示它」 |
| **计数器的每个写入点是否覆盖了所有产生该事件的地方** | ✅ 才能发现漏计 |

判据：**给任何计数器做一次「反向枚举」——列出所有会产生该事件的地方，逐个对写入点。**
本轮就是对「开锁」做了反向枚举（手动 + 自动），一眼看出漏了一条。
