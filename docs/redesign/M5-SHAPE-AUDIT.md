# M5 形态评估：52 页到底该改哪些

> 2026-10-21。M5 执行到第 6 页时做的一次校准。
> 结论有代码与 git 基线双重依据，不是估算。

---

## 一、起因：我差点把「独立构思」做成「统一模板」

M5 前 5 页我全改成了同一种卡片流。自查数据：

| 页面 | XPanel | ScrollView | Divider |
|---|---|---|---|
| KeysPage | 3 | 1 | 1 |
| MembersPage | 3 | 1 | 3 |
| MePage | 5 | 1 | 0 |
| AlarmsPage | 3 | 2 | 2 |
| EventsPage | 1 | 2 | 2 |

结构高度雷同 —— 这正是用户明确禁止的「大锅饭」。

---

## 二、两个设计技能给出的校准

### apple-design（Apple HIG 原文）

`lists-and-tables.md`：

> **Consider using a table instead of a collection for text.** It's generally
> simpler and more efficient to view and digest textual information when it is
> displayed in a scrollable list.

→ 纯文本列表，HIG 推荐 `List` 而不是卡片流。

### anti-ui-slop

核心要求：**Work from the product** —— 先读产品现状再动手。

---

## 三、关键证据：既有模式不是我的模板

用 git 基线 `f7d8c57`（本次重构开始前）核对 4 个页面：

| 页面 | ScrollView | xScrollLift | XPanel |
|---|---|---|---|
| CareRemindersView | ✓ | ✓ | ✓ |
| CarePage | ✓ | ✓ | ✓ |
| SettingsView | ✓ | ✓ | ✓ |
| CareViews | ✓ | ✓ | ✓ |

**`ScrollView + XPanel + xScrollLift` 在重构前就存在。**

加上设计系统本身的规模：
- `App/Core/Theme.swift` 432 行
- `App/Core/Components.swift` 1375 行 / 23 个 X 组件

结论：**本仓已有成熟设计系统，我该扩展它，不该替换它。**

---

## 四、M5 的真实构成

| 类别 | 数量 | 处理 |
|---|---|---|
| **A. 形态雷同且该改** | 5 | ✅ 已重做 |
| **B. 形态本就合适** | 22 | ❌ 不动（见下） |
| **C. 畸形结构** | 3 | ✅ Form → ScrollView |
| **D. 新增页面** | 3 | ✅ M3/M4 已做 |

### A 类（已完成，五页五种形态）

| 页面 | 形态 | 为什么 |
|---|---|---|
| 凭证 | 密度优先，一屏 10 条，46pt 行高 | HIG: 扫读文本用列表 |
| 成员 | 横向 64pt 头像带 + 行头像 44pt | 认人靠脸 |
| 事件 | **时间轴**，竖线贯穿 + 节点圆点 | 时间关系是核心 |
| 告警 | 主告警卡 + 「已持续 X 小时 Y 分」 | 紧迫感来自时间压力 |
| 关于我 | 大数字（title2 加粗，去图标圆） | 概览优先 |

### B 类（不动，因为形态本来就对）

| 形态 | 页面 | 为什么不该动 |
|---|---|---|
| **Grid** | StudioPage / CredentialStudio / LockProfilePage | 四宫格选类型，本来就与卡片流不同 |
| **Canvas** | SecurityCenterView | 雷达图，绘图需求 |
| **LazyVStack** | EventsPage（本轮新建） | 时间轴 |
| **List + swipeActions** | LocksPage | `.swipeActions` + `.onMove` 是系统能力，换卡片流要自己实现手势，是退化 |
| **XPanel 卡片流** | 其余 ~18 页 | 本仓既有约定，且这些页面的内容确实是并列的卡片 |

### C 类（畸形结构，已修）

`MemberCenterView` 里三处 `Form { XPanel { ... } }`：

- `MergeMembersView`
- `MemberFamilySettingsView`
- `MemberExitWizard`

`Form` 自带 grouped 样式 + `XPanel` 又画一层卡片底 = **双层边框**。
全仓 `Form` 数量：3 → **0**。

---

## 五、这条判断的意义

**「52 个页面全部独立构思」不等于「52 个页面全部重写」。**

如果盲目重写 22 个本来就对的页面：
- 破坏既有的 `xScrollLift` 滚动动效
- 破坏 `XPanel` 的 `kind` / `tone` / `padding` 语义
- 破坏 21 道闸门对既有模式的检查

「独立构思」的正确执行方式是**逐页判断它该是什么形态**：
- 该用 Grid 的用 Grid
- 该用时间轴的用时间轴
- 该用 `List` 的（需要 swipe）用 `List`
- 形态本已合适的，不动

---

## 六、尚未覆盖的页面

### 流程型页面：**已核查，不该动**

我原以为这些是"卡片堆"，该改成步骤条。**核查后发现它们早就有流程结构，而且比我打算做的更完整。**

| 页面 | 已有的流程实现 |
|---|---|
| **AddLockPage** | `spine` 步骤条（51 行）：三步圆点 + 三态着色 + checkmark + 当前步脉冲呼吸 + reduceMotion 降级 |
| **GatewayPage** | `confirmed` 分支的两步流程（stepOneCard / stepTwoCard） |
| **FirmwarePage** | 三态分支（`running` 升级中 / `failed` 失败 / 正常版本卡） |

具体看 `AddLockPage.spine`：
- 三步圆点（scan / pairing / naming）
- 三态着色：已完成 `accent` / 当前 `accent.opacity(0.18)` + 2pt 描边 / 未到 `surface`
- 完成态打 `checkmark`
- 当前步 `scaleEffect(1.12)` + `repeatForever` 脉冲
- `reduceMotion` 降级（`reduceMotion ? nil : 动画`）

**这已经是一个完成度很高的步骤条。再改就是破坏。**

### 仍需逐页看的

| 页面 | 行数 | 待判断 |
|---|---|---|
| DonglesPage | 376 | 钥匙串，可能需要卡片式实体隐喻 |
| DevicePage | 351 | 设备首页，待看是否有大数字/状态强调 |
| BackupPage | 283 | 备份状态，可能需要"健康度"而非行列表 |
| StatsPage | 221 | 与 DashboardFace 有重叠，需确认关系 |

### 大页面（本次不动，风险高）

| 页面 | 行数 | 状态 |
|---|---|---|
| ExportCenter | 2470 | 已有 `xScrollLift` 动效 + 16 个 XPanel，形态成熟 |
| CredentialStudio | 1930 | 三套 Studio（TempCode/Fp/Otp），Grid 形态 |
| SecurityCenterView | 1499 | Canvas 雷达 + 22 个 XPanel |
| MemberCenterView | 1333 | 本轮只清 Form，内部仍是 XPanel |

---

## 七、下一步

流程型页面已排除（它们本来就对）。

剩下四个待看：
1. `StatsPage` vs `DashboardFace` —— **优先查**，两者可能重复
2. `BackupPage` —— 备份状态适合"健康度"而非行列表
3. `DevicePage` —— 看是否已有状态强调
4. `DonglesPage` —— 看是否需要实体隐喻

原则不变：**每一页先看它要表达什么，再决定形态。**
先核查再动手 —— 本会话已经两次因为"没查就改"而返工（refscheck / enumcase 两个闸门，以及差点重做 AddLockPage 的步骤条）。
