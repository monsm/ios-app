# AUDIT-ROUND-167 · 第 167 轮：`confirmationDialog` 挂到触发它的按钮上（液态玻璃从正确位置展开）

> CI：`ad34f48` 已验证绿；`6743235`（reorderable）与 `b5bf30b` 待回执。

## 1. 规则原文

`swiftui-pro` 的 `references/navigation.md`：

> Attach `confirmationDialog()` to its **triggering control** so Liquid Glass animates from the
> right source. An action inside `ToolbarOverflowMenu` is the exception: the system owns that menu,
> so a dialog attached to a button inside it **never appears**, even though the button's action runs.

这条直接对应 objective 的「保持液态玻璃原生化」：对话框的展开位置由**它在视图树里挂在哪**决定。
挂在根视图上，iPad / Liquid Glass 会从屏幕中部弹出，用户看不出是哪颗按钮要做什么。

## 2. 改了 2 处

| 文件 | 旧挂载点 | 新挂载点 |
|---|---|---|
| `ModuleOrderSheet` | 根 `VStack` | `VOutlineButton("恢复默认版面")` |
| `AppearanceScreen` | 根 `ScrollView`（`.navigationBarTitleDisplayMode` 之后） | `VOutlineButton("恢复默认外观")` |

两处都是「一颗按钮 → 一个确认框」的干净形状，移动后对话框从按钮位置展开。

## 3. 8 处里其余 6 处**故意不动**（每条都有理由）

| 位置 | 为什么不动 |
|---|---|
| `SafeModeScreen:85`（`confirmRelax`） | 标志被 **两个页面共用**（`LockStatusScreen:135` 也置它），挂到任一按钮都会让另一处弹错位置 |
| `SecurityScreen:61` / `:70` | 与后面的 `.onChange(of: showDisableConfirm)` **串联**：对话框真正关闭后才弹验证框。这条链要求两者挂在同一个视图上，拆开会让"点了继续验证却没反应"的老问题复发 |
| `MemberDetailScreen:96` | 触发点在一个承载多个动作的自定义卡片 `HHMemberClosingCard` 里 |
| `KeyDetailScreen:57` | 同上（`KeysActionRow`） |
| `BackupScreen:75` | 对话框带一长段「校验和是否匹配」分支文案，且与 `fileImporter` 同在一条呈现链上；迁移 churn 大、收益小 |

**「能改的都改，不能改的写清为什么」** —— 比"全部机械上移"安全得多。
尤其 `SecurityScreen` 那条：本轮如果机械上移，会重新踩回仓库里已经记录过的
「对话框退场时置 sheet 布尔会被丢掉」的坑。

## 4. 顺带核对（全部通过）

| 规则 | 本仓 |
|---|---|
| 不用已废弃的 `NavigationView` | **0** ✅ |
| 不用旧的 `NavigationLink(destination:)` | **0** ✅ |
| 同一栈内只注册一次 `navigationDestination(for:)` | **1 处**（`Shell.swift:96`） ✅ |
| 不混用两种导航写法 | 没有旧写法，自然不混 ✅ |
| `sheet(item:)` 优先于 `sheet(isPresented:)`（当呈现的是可选数据时） | `sheet(item:)` 1 处、`isPresented` 14 处 —— 但后者多是"打开一个固定面板"，没有可选数据可承载，用布尔是对的 |

## 5. 方法论

**「把修饰符挂到正确的位置」是一种常被忽略的正确性，不只是审美。**

`confirmationDialog` 挂错位置：

| 挂在哪 | 行为 |
|---|---|
| 触发它的按钮 | 从按钮展开（正确） |
| 根视图 | 从屏幕中部展开（iPad / 玻璃下明显错位） |
| **`ToolbarOverflowMenu` 内部的按钮** | **完全不出现**（系统拥有那个菜单） |

第三行不是"位置不好看"，是**功能失效**。所以这条规则必须读全，不能只记前半句。
