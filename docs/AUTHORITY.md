# 权威顺序（2026-10-24 用户裁定）

> 「**规范有时候可能是错的，以 html 的视觉审美为标准！**」

## 一句话判据

| 维度 | 权威来源 |
|---|---|
| 视觉审美 / 令牌数值 | **tools/proto/tokens.css（HTML 原型）** |
| 功能与业务逻辑 | iOS / Android 实际 App |
| 仓库规范文档 | 仅参考；与 HTML 冲突时**以 HTML 为准** |

## 已按此口径改判据的四处

| 令牌/项 | 仓库规范 | HTML | 采纳 | 影响 |
|---|---|---|---|---|
| `surfaceAlt` | `#24242A` | `#202022` | **HTML** | iOS `XPalette` + Android `KfColors` + `tools/contrast.js` 规范值表三处同步 |
| `XRadius.chip` | 14（§7.2 实测 13.3）| **22** | **HTML** | 全站顶部胶囊从「圆角矩形」变成「胶囊」 |
| 卡片面材质 | 平色 `#1C1C1E`（§6.3）| 平色 `#1C1C1E` | 一致 | App 此前用渐变（与两边都冲突），已回退 |
| 二级页标题 | `.inline`（标题只在导航栏）| **页内 `.h1` + `.sub`** | **HTML** | 31 页补回页内大标题 |

## 31 道闸门分类（各管哪一层）

| 层 | 闸门 | 测的对象 |
|---|---|---|
| 协议正确性 | golden / shadowdiff | BLE 核心 JS↔Swift 字节级差分（**与 UI 无关**，UI 改动不影响它们）|
| 编译形状 | swiftcheck / swiftshape / swiftsyn / apicheck / apisig / declcheck | 括号/参数标签/成员存在/重复声明 |
| 风格令牌 | tokendrift / contrast / glassaudit / dynamictype / uicoverage | 三端同源/对比度/自绘预算/AX 字号/缝覆盖 |
| 内容基线 | subtitlesync / reviewsync / protosweep / copynum / changelogcheck / keyspace | 副标题/验收页/原型完整性/文案数/变更记录 |
| 导航 | destmap / entrygate / sheetcover | 路由表/入口动作/sheet 收摊 |
| Android | kotlinbalance / kotlinshadow | 字面量/字阶 |

## 「HTML 为准」的精确含义（第 80 轮补充）

HTML **内部**也会矛盾。chip 圆角的三层冲突实例：

| 层 | 值 | 来源 |
|---|---|---|
| `.chip` CSS 规则 | 高 56 / **r18**，注释"不是全圆胶囊" | 渲染事实（用户看到的）|
| `--r-chip` 变量 | 22 | 变量声明（可能没被 .chip 引用/已过期）|
| 仓库规范 §7.2 | 13.3 | 更早的实测 |

**裁决规则：渲染规则 > 变量声明 > 规范文档。**

⚠ 补充实证：`--r-chip: 22` 在两个原型的 CSS 里**零使用者**（死变量）——
HTML 的 chip 实际写死 `border-radius: 18px`。第 59 轮按这个死变量把 iOS 改成 22 是误读。
死变量不能当"HTML 的意愿"引用；这也是"渲染规则 > 变量"的又一实证。 理由：渲染规则连同它的实测注释
才是"用户在屏幕上看到的东西"；变量可能改了值没改引用。据此 iOS `XRadius.chip`
定为 **18**（Android 等比 13dp）——第 59 轮按变量改成 22 是误读，本轮纠正。

## 字号层终核（第 83 轮）

与圆角层同法检查 `--f-*` 变量的实际引用：

| 检查 | 结果 |
|---|---|
| 死变量 | `--f-display`/`--f-display-num` 零引用——**但值与 App 一致**（36/56），无需动作 |
| 硬写 15px ×7 | 第 59 轮裁定保留 App 16（等真机反馈），维持 |
| 硬写 13px ×8 | = App `small` 13 档 ✓ |
| 其余硬写 | 原型页内微调，App 有对应档 |

**字号层无漂移。** 圆角层的死变量教训（`--r-chip`）在字号层复核时同样适用——
但这次先查了值是否一致再下结论，没有误改。

## 闸门盲区（原理性，2026-10-24 清点）

97 轮里 CI 抓到 **18 处**本地闸门放过的错误。共同点：全部在**局部作用域 / 类型系统 / 跨文件**层面——

| 错误类 | 本地闸门为何查不到 |
|---|---|
| 局部变量遮蔽（Double health.count）| apicheck 只匹配 Type.member 模式 |
| 属性/函数形态（daysSinceLastExport 无括号）| 成员名存在≠形态正确 |
| 可选性（row.owner.isEmpty）| 同上 |
| 容器外插入（卡头/页脚插到属性体外）| swiftcheck 只查大括号平衡；swiftshape R1 被 @ViewBuilder 覆盖 |
| 嵌套类型作用域（PeekItem）| 类型名存在于别处，作用域错 |
| Kotlin @Composable 错位/递归 | Kotlin 无形状闸（kotlinbalance 只查字面量）|

**纪律结论**：本地闸门是**快筛**，不是保险箱。本仓无本地编译器，
**改完即推、CI 为准**是唯一可靠的验证闭环——本地全绿 ≠ 没问题。

## 闸门有效性实证（2026-10-24）

判断"一把尺子还有没有用"的方法不是看它绿不绿，而是**注入坏值看它响不响**：

| 闸门 | 注入测试 | 结果 |
|---|---|---|
| `tokendrift`（色板/字阶两端同源）| 临时把 Android `surfaceAlt` 改回 `0x24242A` | ✅ 立即报 MISMATCH，还原后恢复 |
| `SecFmt.__bogus`（apicheck 自检）| 注入不存在的成员符号 | ✅ 报出（仓内既有自检）|
| `subtitlesync`（S1-S4 基线对账）| 基线表漏一行/副标题含数字 | ✅ 两个方向都报 |
| `swiftmember.js`（成员精确边界）| 三次 CI 失败的沉淀：'下一个 private var' 边界法在 func 成员处漏判（c6c802a/6270b60 两次失败）→ 深度归 0 法 + 计数验证 + 读回，一次成功 | ✅ 自测三成员边界全对 |
| `swiftshape` 正控 | 12 种坏形状 | ✅ 各开火一次 |

## 原有闸门仍然有效

`contrast.js` 里 `danger` / `textTertiary` 那两次历史事故的教训**不变**：
把令牌往「偏离规范且**没有 HTML 依据**」的方向改，仍然要拦。
本条只把权威来源从规范文档换成 HTML —— **不是取消锁定**。

## 全量 token 对账（HTML ↔ iOS ↔ Android）

| 类别 | 项数 | 一致 |
|---|---|---|
| 画布/表面/文字/语义色 | 12 | 12 |
| 间距（gutter/pageTop/section/titleToCard/align/rowGap/cardPad/xs..xl）| 12 | 12 |
| 圆角（card/cardLg/inner/chip/min）| 5 | 5 |
| 字号（display..caption + hero）| 11 | 11 |

**结论：设计令牌层已与 HTML 逐值同源。剩余差异只在「页面结构内容」，不在令牌。**

## 三端字号档对账（2026-10-24 复核）

| HTML --f-* | iOS XText / DSFont | Android Type | 值 |
|---|---|---|---|
| display / display-num | display / displayNumber | display / displayNumber | 36 / 56 |
| large | largeTitle | largeTitle | 30 |
| title2 / title3 | title2 / title3 | title2 / title3 | 19 / 18 |
| headline / body | headline / body | headline / body | 16 / 16 |
| subhead | subheadline | subhead | 14 |
| footnote / caption | footnote / caption(+caption2) | footnote / caption | 12 / 11 |
| （无）| hero / small | hero / small | 44 / 13 |

**三端 12 档逐值相同**（含六图补档 hero=44 与 small=13 —— 它们是 HTML 里 44px 大数字与
13px 卡内副文的档位化，Android/iOS 的 tokendrift 闸门守着不许漂移）。
另有页面级排版逐值核对：XScreen 大标题 = .h1（30 Bold / -0.4 / 1.15）✓，
副标题 = .sub（16 / textSub）✓。


---

# 审美优先级裁决表（2026-10-24 用户裁定）

**优先级：参考图 > html预览 > 规范 > app**

上级与下级冲突时，**无条件取上级**。以下逐条记录了按此优先级做过的裁定：

| # | 冲突点 | 规范/app 说 | 参考图/html 显示 | 裁决 |
|---|---|---|---|---|
| 1 | **内容卡材质** | 规范 §14-#6「毛玻璃只许功能层」| 参考图 2 卡片实测 R35G34B39，比画布亮 25-30 色阶且**保留背景色相** —— 只有真模糊透光能产生 | **取参考图**：内容卡改 `.ultraThinMaterial` |
| 2 | **卡片边距** | App 原 14pt | 参考图 2 实测卡片左边界 x=80/1206 = **6.6% ≈ 26pt** | **取参考图**：改 22pt（兼顾问小屏可读宽度）|
| 3 | **底部 Tab 栏** | 规范：不透明 surface + 发丝线 | 参考图 2 实测 x=44~1160 = **92.5% 宽（浮动）**、R70G66B65（半透明玻璃）| **取参考图**：改浮动胶囊玻璃 |
| 4 | 环尺寸 | App 322pt | 参考图 1 实测 x=185~1019 = 834px = **69% 屏宽 ≈ 278pt** | **两者一致，无需改**（印证"不是所有差异都要改"）|
| 5 | 系统开关 | 无冲突 | 参考图**没有任何开关**；HTML 的 `.sw` 是 51×31px 圆角 999 白钮 —— 就是系统 Switch | **下探到 HTML**：App 用系统 Switch 正确，无需改 |

## 两条方法论

**① 多高度重复测量。** 环尺寸我第一次只扫 y=700 得到 116px（只有一小段弧），差点把正确的 322pt 改小。在 y=500/700/800/900 四点重测才得到 834px 的真值。

**② 上级缺失时下探，不是跳过。** 参考图里没有开关控件，不代表"随便做" —— 要下探到 HTML 看它怎么规定的，结果 HTML 就是系统 Switch 形态。

## 冲突时的处置流程

```
① 量参考图（多位置重复测量，避免单点误判）
② 若参考图有明确规定 → 取参考图，并记录规范在哪一条落后
③ 若参考图无此项 → 下探到 HTML 原型
④ 若 HTML 也无 → 才轮到规范
⑤ 每一层裁决都写进本文档，供后续复核
```
