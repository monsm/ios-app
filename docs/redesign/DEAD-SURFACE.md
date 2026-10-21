# 不可达的 API 面 —— 「假机制」清单

> 工具：[tools/deadfuncs.js](tools/deadfuncs.js)、[tools/statewrites.js](tools/statewrites.js)
> 记录时间：2026-10-22。这是**已知未完成**，不是待办清单里的猜测。

## 为什么要专门记这个

这几轮发现的最难缠的一类问题不是崩溃、不是报错，而是**代码看起来很努力但从不执行**：

- 它不违反任何闸门
- 它读起来完全正常
- 它甚至会互相引用，形成"看起来有功能"的闭环
- 唯一的症状是：**某个功能在界面上无法使用**

读代码很难发现，因为"它看起来对"。所以做了两个机器检查：

| 工具 | 查什么 |
|---|---|
| `tools/statewrites.js` | 声明了但从不被写入的 `@State` |
| `tools/deadfuncs.js` | 声明了但从不被调用的函数 |

## 当前结果

- `@State` 从不写入：**0 个**（已清零）
- `App/Core` + `App/Services` 里零调用函数：**183 个 / 1112 个声明**

## 已确认的几个「完整但够不着」的功能簇

### 1. 凭证星标（整块不可达）

```
toggleStar ─┬─> setStar
            └─> isStarred
```

三者互相引用，**外部零调用**。所以界面上没有任何地方能打星。
这不是"星标做得简陋"，是**星标根本没有入口**。

### 2. 凭证归档（读侧铺满、写侧缺失）

| | 状态 |
|---|---|
| `isArchived` 过滤 | **15 处**，散落在 CredentialOrg 与 QuickPool |
| `setArchived` 写入 | **零调用** |

归档集合恒为空 → 那 15 处过滤全部是空操作。
（已在 `CredentialOrg.setArchived` 上写明，避免后来者以为功能可用。）

### 3. 停用便签（内部自循环）

`markDisabled` / `DisableMark` / `disReasonKey` 只在 `CredentialOrg` 内部互相引用。
界面上「停用」的实际实现是**删除并入回收站**（`MemberCenterView:1402` → `DB.delPwd`），
与这套"停用便签"不是同一条路径。

## 堆积最多的文件

| 文件 | 零调用函数 |
|---|---|
| `App/Core/CredentialOrg.swift` | **42** |
| `App/Core/RecordSearch.swift` | 19 |
| `App/Core/StatsKit.swift` | 14 |
| `App/Core/Store.swift` | 13 |
| `App/Services/BackupStudioKit.swift` | 12 |

## 处理原则

**不批量删除。** 理由：

1. 本机没有 Swift 编译器，删错一处就是一次 CI 红
2. 其中有真实但尚未接 UI 的 API（如归档），删掉会丢失意图
3. 有些可能通过 KeyPath / 协议 / 反射间接使用，静态扫描看不到

所以采取**标注而非删除**：在关键处写清"这个功能目前够不着"，
并在这里集中记录。要接通时按记录补 UI，要清理时按记录删，两边都有依据。
