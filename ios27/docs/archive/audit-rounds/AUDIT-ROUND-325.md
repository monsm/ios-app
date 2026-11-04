# AUDIT-ROUND-325 · 第 325 轮：把「全换系统」改坏的地方全部退回去，并把真修复留在原地

> 用户原话：「上几轮修改界面修改原生液态玻璃控件，没改几个液态玻璃效果，却把界面改的七扭八歪、丑爆了！」
>
> 这句话是对的，而且是可以用数值证明的。本轮做的是**撤销**，不是再加一层。

## 1. 先承认：方向错了

第 324 轮把 40 个页面的容器从 `ScrollView + VStack + VCard` 换成 `List + Section + GroupBox`，
理由是「内容层的系统对应物就是 GroupBox / List」。这条理由**只对了一半**：

| 说法 | 实际 |
|---|---|
| GroupBox 是「系统卡片」 | 对。但它是**不透明**的系统卡片，不是液态玻璃 —— 换它**换不来任何玻璃** |
| List 是「系统列表」 | 对。但 List 有自己的一套内边距/段间距，和本设计的两族常量**全部冲突** |

HIG 的原话（`hig/liquid-glass.md › The two layers`）：
> **Don't use Liquid Glass in the content layer.** ... The one exception is a control in the content layer
> with a transient interactive element, such as a slider or toggle.

⇒ 内容层本来就不该有玻璃。所以「全换系统」这件事，**收益是 0，代价是整套布局**。

## 2. 数值证据：到底歪在哪

原设计有**两族页面**，常量不同：

| 族 | 顶部留白 | 块间距 | 左右 gutter |
|---|---|---|---|
| 仪表盘族（12 页） | `V.Page.topSpace = 8` | `gapM = 14.3` | `cardGutter = 14.67` |
| 表单族（15 页） | `gapXS = 4` / `gapS = 7.7` | `gap16 = 16` | `pageGutter = 16` |

List 化把两族**压成同一套数字**：

| 项 | 改前 | 改后 | 偏差 |
|---|---|---|---|
| 卡片左右 | 14.67 | 16（`cardRow()` 默认） | **+1.33pt**，68 处 |
| 页面顶部 | 8 | 16（`contentMargins(.top, gap16)`） | **+8pt（翻倍）**，20 页 |
| 页头缩进 | 29.67（`pageGutterB`） | 16 | **−13.67pt** |
| 卡间垂直 | 14.3（`VStack(spacing:)`） | **0**（`listRowInsets` 上下都是 0） | 卡片**贴在一起** |

最后一条是最致命的：同段内相邻卡片**没有任何垂直间距**，几张卡连成一整块。

## 3. 本轮处置

| 动作 | 范围 |
|---|---|
| 整页回退到改前快照 | 27 个混合页 + 13 个纯容器页 |
| 恢复被合并掉的三个页面 | `SafeModeScreen` / `TailgateScreen` / `SyncTimeScreen` |
| 恢复 `Destinations` 路由 | 回到「六页各归各位」 |
| 恢复 5 个被当「零消费」删掉的令牌 | `heroGlyph56` / `titleC` / `chipLabelStrong` / `gapXL` / `Metric.medal` |
| `LockMode` 挪进 `Engine/Reading.swift` | 它原本住在页面文件里 —— 引擎依赖页面是倒挂 |
| 门禁承诺对重新指回原页面 | `workflow.js` 的防尾随 / 校时两对 |

## 4. 真修复是**移植**回来的，不是跟着 List 一起留下的

回退会丢掉第 324 轮里那些真 bug 修复，所以逐条搬回原设计版：

| 修复 | 为什么不能丢 |
|---|---|
| `DefendScreen` 的 `outcomeOK` | 改前 `VStatusLine(tone: .ok, text: outcome)` 是**常量** —— 布防失败也画成绿色（P0） |
| `RecordsScreen` 的 `todayAlarmCount` | 改前写死「无异常」—— 一个永远说"没事"的假读数 |
| `KeysScreen` 的 `CredentialOrg.ownerName` | 改前直接把 `key.owner` 当显示名，而该字段历史上有「成员 id」和「成员名字」两种口径 ⇒ 界面上会露出内部 id |
| `DiagStreamScreen` 的行数上限 / 清空 / 双侧快照 | 用户明确要的三个功能 |

## 5. 顺手抓到的系统性观感缺陷：**25 个页面把标题印了两遍**

设计稿在内容区顶部画了 34pt 大标题（常带 overline 或状态行），而每一页**又**设了同名的
`.navigationTitle`（inline）。于是同一屏里同一个词出现两次：导航栏一次（小、居中）、页面里一次（大）。

本次按**精确同名 + 标题字号**匹配，清空 23 页的导航栏标题文字（导航栏本身保留 —— 它承载返回按钮，
也是滚动时那层系统玻璃的来源）。

## 6. 方法论

| 判据 | 出处 |
|---|---|
| **「换成系统控件」不等于「得到系统材质」。** GroupBox/List 是不透明的；玻璃只在功能层 | 本轮 §1 |
| **容器替换必须先对齐两族常量。** 布局系统一旦有两套 gutter，任何"统一成一套"的改动都是全局回归 | 本轮 §2 |
| **改组件内部一次 = 影响 500 处；改错了也是 500 处** | 第 324 轮 §3 的反面 |
| **同一个词在一屏出现两次，读者会认为没做完** —— 页面自带大标题时，导航栏标题必须清空 | 本轮 §5 |
| **`git commit -a` 不带未跟踪文件。** 恢复一个被删的页面 = 新建文件，必须 `git add` | 本轮事故 |
