# 发布前自查清单

> 本文件写的不是"要做什么"，而是**每个检查能证明什么、不能证明什么**。
>
> 这个会话最大的教训不是发现了很多问题，而是我反复把工具输出当成事实：
> 工具说「7 个页面缺标题」→ 实际 0 个；说「122 处死引用」→ 实际 2 个孤立页；
> 说「可达 1 个」→ 是工具自己覆盖了 body。
>
> **工具的价值取决于它的判据，不取决于它能报多少条。**

## 一、当前状态（2026-10-22，HEAD 见 git log）

| 检查 | 当前输出 | 能否作为"没问题"的证据 |
|---|---|---|
| 23 道本地闸门 | ✅ LOCAL 23 PASS | 只能证明结构/命名/令牌合规，**不能证明能编译** |
| CI（真编译器）| ✅ SUCCESS | **能证明能编译**，不能证明行为正确 |
| `pagecraft` | 平均完成度 100%，未满分 0 | 启发式打分，见其判据说明 |
| `statewrites` | @State 322 个，从不写入 0 | 能证明没有"假状态"；不能证明状态变化时机对 |
| `deadfuncs` | 1115 个声明，零调用 161 | 零调用≠该删；其中有等 UI 的 API |
| `typerefs` | 476 个类型，31 处可疑 | **假阳性约一半**，见下 |
| `reach` | 89 个 View，88 可达 | 高估可达（故意的），只保留确凿孤立页 |
| `rendercontrast --scan` | 不达标 0 / 14 | 只算令牌叠透明度，**不算真实渲染层叠** |
| `cilog` | 按需 | **能给出 文件:行:列 + 编译器原话** |
| `regress` | **30 / 30 成立** | 能证明"已修复项没有回退"；不能证明"没修的东西是对的" |

## 二、哪些结论必须由人验证

这些**没有任何工具能替代**：

1. **视觉观感** —— 好不好看、留白是否舒服、层级是否清楚
2. **真机手势** —— 开锁环按住的手感、长按菜单的可发现性
3. **动画实际效果** —— 转场是否流畅、有没有掉帧
4. **设备协议行为** —— 日志同步的分页约定、静默命令的回读值
5. **文案是否说人话** —— 「去「设备」处理」对非技术用户是否清楚

## 三、每个工具的有效范围

### `pagecraft.js` —— 页面品质记分卡
- **查**：字号是否语义化、有无空态、有无无障碍、有无裸写颜色、有无状态表达
- **不查**：好不好看、布局是否合理、信息密度
- **已知偏差**：对"整页用原生带标签控件"的页面曾误判（已修）；配置类页面的"空态"记为 N/A
- `node tools/pagecraft.js`

### `statewrites.js` —— 假状态
- **查**：声明了但从不写入的 `@State`
- **不查**：写入了但时机不对（例如写了却没触发重绘）
- **踩过的坑**：漏集合变更（`.insert`/`.remove`）、漏 `&+=`
- `node tools/statewrites.js`

### `deadfuncs.js` —— 零调用函数 + 有读无写
- **查**：`App/Core` + `App/Services` 里零调用的函数；以及"读侧在用、写侧零调用"的成对函数
- **不查**：KeyPath / 协议 / 反射的间接使用
- **注意**：零调用**不等于**该删 —— `setArchived` 这类是等 UI 的 API
- 第二段「有读无写」是最高价值的输出：`setPasscode` 零调用就是这么找到的
- `node tools/deadfuncs.js`

### `typerefs.js` —— 类型归属
- **查**：`Type.member` 里 member 是否真在 Type 中
- **不查**：可见性、重载、泛型、协议合成成员
- **已知假阳性**：系统成员撞名（`Color.clear`、`UIApplication.shared`）、限定名 extension（`extension BackupStudio.Channel`）
- **速度**：能在我犯错的**当下**抓到 —— 本会话三次类型归属错误，它抓到了三次
- `node tools/typerefs.js`

### `reach.js` —— 页面可达性
- **查**：从 `RootView` BFS 后走不到的 View
- **不查**：菜单名与页面是否匹配（需人工，见下）
- **方向**：**宁可高估可达** —— 低估会让我去"修"本来正常的导航
- `node tools/reach.js`

### `rendercontrast.js` —— 实际对比度
- **查**：令牌 × 透明度 × 背景 合成后的对比度；`--scan` 反查代码里实际用到的组合
- **`--stack`**：算**两层背景** —— 同色相淡底板 + 同色文字（告警行、胶囊）。
  实测 0.10–0.12 的板安全（6.06–8.07:1），0.35 会掉到 3.26–4.34（那是描边档，上面不该压文字）
- **不查**：三层及以上叠加；渐变内部的局部对比度
- **判据**：文字 4.5:1、信息性图形 3:1、装饰/网格线约 1.4:1
- **豁免**：`// @contrast-allow <理由>`，**豁免必须写明理由**
- `node tools/rendercontrast.js`（矩阵）/ `--scan`（反查代码）/ `--stack`（两层叠加）

### `cilog.js` —— 从 CI 取真实报错
- **查**：失败 job 日志里的 `error:` 行（文件:行:列 + 编译器原话）
- **不查**：非编译失败（环境/签名/模拟器）
- **凭据**：走 `git credential fill`，不打印不落盘
- `node tools/cilog.js <runId>`

## 四、提交前一分钟清单

```
1. 跑 23 道闸门                     —— 结构层
2. 改了对比度相关 → rendercontrast --scan
3. 改了类型引用   → typerefs
4. 改了导航/新页面 → reach + destmap --emit
5. 改了状态变量   → statewrites
6. push
7. cistat 看状态；红了立刻 cilog <runId>
8. **拿到 error: 原文之前，不要说"通过"**
```

## 五、需要人工、工具做不到的三件事

1. **菜单名与落点是否一致** —— 本会话发现「外观工作室」指向了「钥匙工坊」。
   `reach` 只能证明"到得了"，证明不了"是同一件事"。做法：把路由标签和页面
   `navigationTitle` 并排列出来人工看（本会话做过一次）。

2. **装饰 vs 信息图形** —— 低对比度不等于要修。告警卡的淡红底衬、1.5pt 连接线、
   4pt 占位点都不承载信息，套 3:1 只会让界面变硬。

3. **承诺是否兑现** —— 文案写「可还原」就必须真有还原入口。这类问题
   `deadfuncs` 只能提供线索（`undoRemove` 零调用），判断"这算不算欺骗"要靠人。

---

# 追加：reduceMotion 覆盖审计（2026-10-22）

对前庭功能敏感的用户，这个比配色重要。全 App 112 处动画调用，按**运动幅度**分类的结果：

| 类别 | 数量 | 有 reduceMotion 判断 |
|---|---|---|
| **持续动画 `repeatForever`** | 5 | **5 / 5** ✅ |
| `.move(edge:)` 滑动转场 | 8 | 0（多为横幅，位移 14–20pt）|
| 大幅 `scale` 转场 | 3 | 1（本次补）|
| 纯 `.opacity` 转场 | 8 | 0（淡入淡出不算运动）|

## 结论：**关键的一类已经全覆盖**

`repeatForever` 是唯一会造成**持续**运动的形式，5 处全部有降级分支。
剩下的是一次性转场，且位移小（横幅下滑 14–20pt、小图标 0.9 缩放）。

**Apple 的 Reduce Motion 针对的是大幅位移、缩放、视差**，不是所有状态变化。
把按钮按压的 0.96 缩放也关掉，反而会让界面失去"按到了"的反馈。

## 本次补的一处

`AddFingerPage` 的录入成功圆环：180pt 元素从 80% 放大 —— 这是全 App 位移最大的单次动画。
已改为 `reduceMotion ? .opacity : .scale(0.8).combined(with: .opacity)`。

## 未处理的，与理由

- 纯 `.opacity` 转场：淡入淡出不属于运动，HIG 允许保留
- `scaleEffect(configuration.isPressed ? 0.96 : 1)`：按压反馈，幅度 4%，是"按到了"的唯一视觉证据
- 横幅 `.move(edge:)`：位移 14–20pt，且同时带 `.opacity`，视觉上主要是淡入

**判断依据**：关掉一个 4% 的按压缩放，用户会以为按钮没响应；关掉一个 20% 的全屏缩放，才是真正照顾到敏感用户。

---

# 追加：回归检查（`tools/regress.js`）

会话里改了 30 项，**后面的改动可能覆盖前面的修复**。例如改 `HomeConsole` 的失败态时，
是否碰坏了它的重入闸门？改 `EventsPage` 的空态时，是否碰坏了同步逻辑？

`node tools/regress.js` —— 把每条修复写成一个可机械验证的断言，跑一遍就知道有没有退回去。

当前：**30 / 30 成立**。

## 这个工具第一版也误报了两条

用 `includes` 直接搜，把**注释里解释"为什么不这么做"的那行**当成了回退：

| 误报 | 真相 |
|---|---|
| 「不再用 DragGesture 开锁」✗ | `HomeConsole` 里那行是注释：`// 之前是 DragGesture(...) + sleep` |
| 「refreshTick 已删净」✗ | `LinkSenseKit` 里保留着（它有 `+= 1`，是唯一合法处）|

第二版**剔除整行注释**再匹配，两条都通过了。

**又一次同一个教训**：断言写错方向，会让我去"修"正确的东西。

---

# 追加：对照 Apple HIG 的条款审计（2026-10-22）

用 `apple-design` 技能里的 124 页 HIG 原文，逐条对照本 App，找出**属于明确条款**的问题。

## 查了三条可机械验证的

### 1. `color.md › Best practices`
> "Avoid relying **solely on color** to differentiate between objects, indicate interactivity, or communicate essential information."

扫了全 App 所有 `XPalette.ok/warn/danger/accentText` 的填充与外框，找「前后 6 行内既无文字也无图标」的纯色块：15 处。
逐个看上下文，**全部合规**：

| 位置 | 实际用途 |
|---|---|
| `FeedPage:120` 堆叠条 | 装饰条，已 `.accessibilityHidden(true)`，条数另有文字统计 |
| `GatewayPage:181` 步骤点 | 同色点，颜色不承担区分职责；步骤文字在旁边 |
| `SecurityCenterView:1069` | 是**文字按钮**，文字本身承载语义，颜色只是强调 |
| 其余 `accentText` | 都是链接/图标，语义由文字或形状承担 |

### 2. `feedback.md › Best practices`
> "Make sure all feedback is accessible. When you use multiple ways to provide feedback... color, text, sound, and haptics"

本 App 的 `XHaptics` 覆盖：开锁成功/失败、录入每按一次、保存、删除、长按释放……关键动作都有触觉通道，且都配了 toast 或状态文字。

### 3. `accessibility.md`（装饰图标应隐藏，功能性图标应有标签）
全 App **154 个 `Image(systemName:)`**，其中在按钮内、且 16 行内既无 `accessibilityLabel` 也无 `accessibilityHidden` 也无 `Text` 的：**1 处**。

核实那 1 处（`CredentialStudio:1128` 铃铛）→ 它其实是 `Label { Text(...) } icon: { Image(...) }`，
**Label 会自动合并图标与文字朗读**，图标是装饰。**实际缺口 0 处。**

## 结论

这三条 HIG 明确条款，本 App **已经合规**。

这一轮没有产出代码改动 —— 但这是**有价值的负结果**：
它说明前面几轮在无障碍、对比度、反馈通道上做的功课是有效的，
而不是"改了 40 轮但无一处对得上标准"。

## 下次审计该查别的条款

这三条已覆盖，重复查是浪费。还没对照过的：`motion.md`（转场时长与曲线）、
`lists-and-tables.md`（行高与可点区域）、`modals.md`/`sheets.md`（何时用弹层还是推入）、
`onboarding.md`（首次使用）。

---

# 追加：`motion.md` 审计（2026-10-22）

HIG 的 motion 页给的是原则而非数值。挑了两条能机械验证的：

## 「高频交互上不要加动画」

> *"In apps, generally avoid adding motion to UI interactions that occur frequently."*

扫 `.animation(..., value: X)` 里 X 属于输入/搜索/滚动/焦点类状态的：**仅 1 处**
（`BackupStudio:687`，且那是**完成态**，不是高频）。

## 「让人能取消动效，别让人等动画放完」

- 开锁环 1.05s 是**蓄力手势**（按住才充能，松手即 `abortCharge` 归零），不是装饰动画
- 所有 `XMotion` 令牌时长 0.08–0.70s，无阻塞式等待

## 顺带发现的死代码：`lively` 档

`XMotion.tier` 只返回 `"calm"` 或 `"standard"` —— **`"lively"` 四个分支永远走不到**，
没有任何开关能切过去。而那一档的 `dampingFraction: 0.68` 会**过冲/回弹**，
与本 App「金属刚性、无回弹」的设定冲突。

**已删除该档**，注释改为两档。理由写在了代码里：
> 需要"更有活力"的观感时，改 standard 的时长，而不是加回弹。

现在 7 个令牌（quick / standard / soft / exit / summon / doorReveal / chargeReset）
**全部有调用**，`dampingFraction` 全在 0.85–1.0 —— 整组动效没有一处过冲。

---

# 追加：modality 审计（2026-10-22）

## 结构上没有「App 里的 App」

HIG：
> *"Avoid creating a modal experience that feels like an app within your app. Presenting a hierarchy of views within a modal task can make people forget how to retrace their steps."*

扫了 23 处 `.sheet` / `.fullScreenCover`：**0 处**在弹层里装多级跳转。
（其中 5 处有 `NavigationStack`，但那只是为了让弹层有标题栏与工具栏，里面没有 NavigationLink。）

## 但发现一个真问题：配对中下滑关闭不回滚

`AddLockPage` 是一个**会真的改设备状态**的多步任务：
`pair()` 之后门锁端已经换过密钥，本机这边只有 `@State` 里的 `pairedKC`。

而 `interactiveDismissDisabled` **全仓 0 处**，`onDisappear` 只取消了扫描任务。
后果：**用户在配对进行中下滑关闭 → 锁被配上了、App 里没有记录**，
既控制不了它，重新配对还可能被「已经添加过」挡住。

修复：
- `.interactiveDismissDisabled(flow == .pairing || flow == .naming)` —— 这两个阶段会改设备状态
- `onDisappear` 兜底：只要还在这两个阶段就 `rollback`

## 顺带把同类风险也堵了

另外 5 个**写入类弹层**（AddKeyPage / ExportWizardView / RestoreWizardView /
TempCodeStudio / FpStudio）在 `busy` 期间禁止下滑关闭 ——
否则操作可能已经发到设备，用户却拿不到结果、也看不到失败原因。

`OtpStudio` **没有 busy 状态**，所以没加（加了会编译失败）。

## 这次改动中我自己犯的错

第一版用**文件级**匹配插 `.interactiveDismissDisabled`，插到了文件里**第一个**
`navigationTitle` 上——而那个属于另一个视图，该视图没有 `busy`。
**三处会编译失败。**

用一个「插入后回查所在 struct 是否真的声明了 busy」的脚本抓出来，撤掉重插。
现在 6 处全部作用域正确。

**教训**：批量改代码时，"改到了"和"改对地方了"是两件事。
写完立刻回查作用域，比等 CI 报错便宜得多。

---

# 追加：结构盘点（2026-10-22）

## 管理面板不是"一个抽屉放 23 个东西"

我之前担心的事没有发生。实际是 **5 个分组 × 3–5 项**：

| 分组 | 项数 | 内容 |
|---|---|---|
| 钥匙（原「台账」）| 3 | 钥匙管理 / 指纹 / 临时密码 |
| 设备 | 5 | 门锁 / 固件 / 网关 / 钥匙串 / 校准时间 |
| 成员 | 4 | 成员 / 添加 / 合并 / 已归档 |
| 安全 | 4 | 隐私看板 / 审计 / 销毁 / 安全模式 |
| 数据与外观（原「备份外观」）| 4 | 备份恢复 / 导出中心 / 外观工作室 / 本机设置 |

**每个分组 3–5 项，是合理的**。分组名原先是行话（台账 / 备份外观），已统一为
与页面标题一致的词。

## 仍然存在的结构问题（记下来，暂不动）

**两套并行的导航面**：

- `ManagerFace`（管理面板）：20 个入口
- `MePage`（本机设置）：4 个分区、约 15 行

两者有重叠：`backup` / `export` 在两个面都能到，而 `ManagerFace → me → MePage`
意味着"设置页里嵌着另一个设置页"。

iOS 上这种重复不算错误（系统「设置」也这样），但它带来两个代价：
用户不知道该去哪个面找；同一个目的地有两条路径，行为可能不一致。

**要真正解决需要合并成一个面** —— 那是结构级改动，风险远大于收益。
本轮只把命名统一，不动结构。

---

# 追加：门厅结构 versus 外部基准（2026-10-22）

## 外部基准在本会话不可用

- **UIZZE**（`ui-radar` 技能的数据源）：`uizze.com` 解析到非公网地址，被网络策略拦下
- **web_search**：无 API key

按 `ui-radar` 自己的原则 —— *"If nothing useful appears, say so and stop"* ——
**不编造参考物**。所以本轮改用**手头可引用的权威来源**：Apple HIG 原文。

## HIG 依据

> `layout.md › Best practices`
> **Order content by relative importance.** ... place the most important items [first]
>
> **Use progressive disclosure.** An interface with too much content and too many
> choices makes it harder to find information quickly.

## 逐个核对，三项结论

### 1. 顺序：站得住，不改

门厅顺序 = 页眉 → 身份（锁名）→ 今日摘要 → 开锁环 → 三指标 → 分时图 → 成员 → 管理。

「先知道是哪把锁、它今天什么状态，再开门」是合理的。**HIG 要求按重要性排序，
并没有要求"动作必须在第一位"。**

### 2. 今日摘要不是重复，不改

`digest`（"今天 N 人开过 M 次"）与下方 `todaySection` 一度被我怀疑重复。
核实：`todaySection` 只有分时图表，**没有文字摘要**。所以 digest 是那句"一眼看到多少次"
的文字版，不重复。

### 3. 时钟保留，但纠正了一处层级

页眉里"装饰性的时钟 15pt"比"能不能开门的连接状态 12pt"更醒目 —— **重要性倒置**。
已把连接状态提到 `footnote`(13pt) + semibold。

时钟本身保留：它是这次重写刻意做的「仪表气质」锚点，不是冗余错误。

## 顺带排除的性能疑虑

`recompute()` 由 `SecTickCenter` 驱动，而它是 **事件驱动**（`bump()`），
不是定时轮询 —— 不会每秒扫一遍日志。

**本轮结论：门厅结构不需要改。** 这是"查了、没问题"，不是"没查"。

---

# 追加：动效代入审计（2026-10-22）

把全仓 71 处 `XMotion` 使用按交互类型归类：

| 类型 | 用到的曲线 |
|---|---|
| 按压反馈 | quick × 8（✓ 全部是同一条，没有各按各的）|
| 状态变化 | standard × 23 / soft × 18 / quick × 10 / 其余 × 8 |
| 进出场 | soft × 2 / exit × 2 |
| 持续动画 | 5 处 `repeatForever`，**全部有 reduceMotion 降级** |

## 找到一处：曲线还在为已删的界面服务

`doorReveal`（原来的 `/// 门后内容入场`）：

```swift
default: return .timingCurve(0.22, 0.76, 0.03, 1, duration: 0.70)
```

「门后内容」是**三棱柱时代**的整屏揭示，那个界面已经删了。
0.70s 是按整屏尺度标定的，现在它只给 40pt 头像、仪表、进度环用 ——
iOS 标准过渡是 0.25–0.35s，0.70s 是它的两倍多（`motion.md`: "aim for brevity"）。

**已收短到 0.45s**：仍是"落定"而不是"弹出"，但不用等。

## 核对过、没问题的

- **进出场比例**：进场 standard 0.4s、退场 exit 0.15s = **2.7 : 1**（进场慢、退场快）✓
- 16 处 `.transition` 里只有 2 处显式指定退场曲线，其余跟随环境动画 ——
  SwiftUI 对 transition 用同一段动画，属于可接受做法
- `repeatForever` 5 处全部有降级 ✓（上一轮已核）

**这是一次"曲线有没有为已经不存在的界面服务"的检查** ——
删掉一个界面之后，为它调校过的时长、间距、颜色不会自己回来。

---

# 追加：图标语义冲突审计（2026-10-22）

按「图标 → 概念」建清单，找同一个图标被用于不同语义的情况。
29 个图标服务 2 个以上概念，但**多数是同一语义、不同文案**（`checkmark.seal` 出现在 8 处，
全都是"成功"，只是成功的事不同）—— 那些不是问题。

## 真问题：`clock.arrow.circlepath` 兼职四种含义

| 用途 | 是否贴合图标语义 |
|---|---|
| 校准门锁时间 / 将手机时间同步到锁内 | ✓ 这正是它的意思 |
| 保养历史 | ✓ 回溯/历史 |
| **回收站是空的** | ✗ 垃圾桶不是时钟 |
| **立即清理到期条目** | ✗ 那是"删"，不是"改时间" |

同一个图标在设置里表示"校准时间"，在回收站里表示"什么都没有" ——
用户靠图标扫读时会点错。

已改：
- 回收站面板头图 → `trash`
- 两处空态 → `trash.slash`
- 清理到期条目 → `trash.slash`

## 核对过、没问题的

`chevron.right` 出现 10 次，**全部是尾部展开指示符**（trailing disclosure），
只有一处作为 CTA 的 Label 图标 —— 没有"行首也放箭头"的双箭头问题。

## 方法

不是逐页读，而是**先建清单再对照**：
颜色、图标、字号这类跨页一致性问题，单页审查永远发现不了 ——
每一页单独看都合理，问题只在并排比较时出现。

---

# 追加：toast 词汇规则（2026-10-22）

扫了全仓 **138 处 `showToast`**，结论是**这套词汇本来就有规则**，只是没人写下来：

| 场景 | 句式 | 例 |
|---|---|---|
| 状态变化 | **已 + 动词** | 已删除 / 已复制 / 已保存 / 标定已清除 |
| 操作失败 | **动词 + 失败 + 原因** | 保存失败：<原因> |
| 批量操作 | **动词 + 完成 + 计数** | 导入完成: 新增 12, 覆盖 3 |
| 一次事件 | **动词 + 成功** | 开锁成功 / 重启成功 |

## 我一开始判错了三次

| 我以为是漂移 | 实际 |
|---|---|
| 「已保存」vs「保存失败」 | 成功与失败的不同句式 ✓ |
| 「导入完成: 新增 N」vs「已导入「名」」 | **批量 vs 单条**的有意区分 ✓ |
| 「已清除失败记录」 | 不是失败提示，是成功提示 ✓ |

## 真正的问题只有一处：失败不带原因

三处纯状态词，已补：

- `BackupPage`「保存失败」→ 带上 `ErrorText.human(e)`（错误对象本来就在手边）
- `BackupPage`「备份生成失败」→ 把 `try?` 拆成 `do/catch`，区分"编码失败"与"不是有效文本"
- `ExportCenter`「无法生成预览文件」→ `writeLocal()` 只返回 nil、拿不到原因，
  那就**给下一步**：「可改用「导出」直接保存到文件」

**"说不出原因时，至少说清下一步"** —— 这也是失败提示的底线。
