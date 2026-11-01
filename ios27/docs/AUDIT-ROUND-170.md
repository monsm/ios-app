# AUDIT-ROUND-170 · 第 170 轮：三条「布局卫生」判据全部干净；符合性报告补全

> CI：`c679d60`（对比度玻璃）已验证绿；`3db7532`（按压反馈）待回执。

## 1. 三条新判据，全部「审过无缺陷」

| 检查 | 方法 | 结果 |
|---|---|---|
| **裸数字 padding**（应走 `V.S` 令牌） | `grep ".padding("`，排除含 `V.S.`/`V.R.`/`V.Hit` 的行 | **0 处** ✅ |
| **`.offset()` 用于布局**（不参与布局计算，易造成重叠） | `grep ".offset("` | 9 处，**全在绘图组件**（`VMiniBars` 柱位 / `VGauge` 游标 / Tab 角标），属画布内定位 ✅ |
| **工具栏反模式**（`Spacer()` 分隔 / 图标无标题 / 自建省略号菜单） | 逐个读 9 处 `.toolbar {` | **0 / 0 / 0** ✅ |

第三条的出处是 `apple-design` 的 `code-audit.md`：

> Manual spacers between toolbar items (`Spacer()`, `.fixedSpace`, fixed `SizedBox` widths)
> → Use `ToolbarItemGroup`
> Toolbar items with a symbol and no title: `Image(systemName:)` alone → Give both, for example with `Label`
> An app-owned overflow menu behind an ellipsis → Move the actions into `ToolbarOverflowMenu`

本仓 9 处工具栏都写成 `ToolbarItem(placement:) { Button("文字") }` 或 `Label`，三条都不命中。

## 2. 又排除一条假线索：17 个滚动页没有 `scrollEdgeEffectStyle`

| 项 | 判定 |
|---|---|
| 17 个「有 `ScrollView` + `navigationTitle`、没写 `scrollEdgeEffectStyle`」的文件 | **不是缺陷** —— 该 API 默认值就是 `.automatic`，系统自带边缘效果；显式 `.soft` 只是风格偏好 |

**17 处全部不动。** 改了只会制造 17 处无收益的 diff，还会让"哪里真的需要自定义"这件事变模糊。

## 3. 符合性报告补两节

`docs/DESIGN-CONFORMANCE.md` 新增：

| 小节 | 内容 |
|---|---|
| **§5.1 审过无缺陷** | 上面六条（含 `scrollEdgeEffectStyle` 的判定），逐条留证，避免下一轮重复扫 |
| **§5.2 交互反馈** | `PressStyle` 的「有实现、没接上」：101 处 `.plain` vs 4 处 `PressStyle`，接入后覆盖约 176 处 |

把「审过无缺陷」也写进正式报告，是因为**它同样是需要维护的事实** ——
否则下一轮的我（或另一个人）会再扫一遍同样的东西。

## 4. 方法论

**「审过无缺陷」必须留证，否则等于没审。**

本段这类记录已经攒了 6 条（`scrollEdgeEffectStyle`、裸 padding、`.offset`、工具栏三条、`UIScreen.main` 假红、
`Conductor` 之外的死代码）。它们的共同价值是：

| 作用 | 说明 |
|---|---|
| 不重复劳动 | 下一轮不必再扫 |
| 可复核 | 写清"用什么方法查的、查到什么"，别人能重跑 |
| **防止为了有产出而硬改** | 有据可查地写着"这里没问题"，比"我再看一遍吧"更省事 |

第三种最容易被忽略：当一个人被迫"每轮都要有产出"时，
一份写着"审过、无缺陷"的记录，是唯一能让他停手的依据。
