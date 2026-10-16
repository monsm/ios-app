# 「一枚锁核」全项目 UI/UX 改造方案

> 本文取代 `MASTER.md` §10.1 那张旧→新表。**不要再从那张表读方向** —— 它还是在给现有容器搬家，
> 而这次要的是把容器整个扔掉。§10.2 的五条实证冲突、§10.3 的连带缺陷面、§10.4 的施工前置**仍然有效**，
> 本文把它们收编进 §9 与 §10。
>
> 原型：`core-ui.html`（会话取证目录，非仓库文件）。尺子：`contrast-check.js`（同目录）。
> 两者都已跑过两轮独立视觉评审（第一轮 5/10，第二轮 7/10），本文所有数字都来自改后的那一版。

---

## 0. 一句话与三条公理

**北极星：导航即画面。** 全 App 只有一枚会变形的玻璃锁核，和三个围绕它的光点；没有 Tab、没有卡片、没有列表页。
把锁核拖向某个光点 = 召唤那个域；直接点那个光点也行 —— 拖拽是给熟手的加速键，点击是给所有人的通路。

三条公理，后面每一处设计都必须能回答"它服务了哪一条"：

1. **零卡片定理**：界面里不许出现任何圆角矩形容器。层级只由三样东西承载 —— 字号对比（58pt/200 的超细 vs
   9.5px/650 加宽字距的大写标签）、两端淡出的发丝线、玻璃材质本身。盒子是模板感的来源；一旦开始堆盒子，
   就必然开始堆五种盒子（现状实证：`DeviceHomeView.swift` 2549 行里 ≥11 种 background+radius 组合）。
2. **一枚物体五种形态**：待机 / 按压 / 开门 / 浮层 / 平铺。是**同一个对象的五个状态**，不是五个页面。
   形态之间用同一组几何连续过渡，不许出现"另一个组件接管"的接缝。
3. **发光层预算 2**：锁核的 halo + rim 投影。它替代的那块屏幕（`UnlockDial.swift`，1019 行 / 10 个 struct /
   ~13 层 / ≥8 处渐变-发光-阴影）是 6 层以上 —— 那是"糊"不是"亮"。

---

## 1. 五形态规格

| 形态 | 进入 | 退出 | 视觉 | AX |
|---|---|---|---|---|
| **待机** | 默认；浮层关闭后回弹到位 | 按住 110ms → 按压；拖离home → 拖拽 | 极光场 + 门名 + 状态大字 + 锁核 + 三光点 + 一行提示 | 锁核是 `role=button`，标签「按住开启」；三光点各自 `role=button` + 域名 |
| **按压** | 按住锁核且未位移 110ms 内 | 松手未充满 → 从**呈现值**弹回并接管释放速率；充满 1100ms → 开门 | 进度环沿锁核自己的轮廓长出来（r=66 与 rim 共用一圈），光晕随力度 0→0.80，缩放 +0.075 | 无独立焦点；VoiceOver 播报充能完成 |
| **开门** | 充能到 1 | 3000ms 自动回锁 | 三层涟漪（0/160/320ms 错峰）+ 全屏泛光 + 读数改「已开启」+ 锁梁抬起 | 状态变更必须 `AXTools.announce`，且**字形与文字同时改**（不许只改一个） |
| **浮层** | 拖到光点并释放，或直接点光点 | 点浮层空白 / 抓握条；再点同一光点 | 玻璃浮层从该侧升起 640pt；锁核缩到 0.42 骑在标题右侧；其余两光点降到 0.18 | 见 §11 待拍板 P-1：**浮层态目前读不到锁状态** |
| **平铺** | 无障碍档（`AXFlags` 或系统减少动效+降低透明度组合触发） | 关掉该档 | 三光点摊成三行带字条目，直接排在画布上，行与行用同一根两端淡出的发丝线分开；拖拽退场，**按住开门保留** | 这一档是"同一套设计换个密度"，不是另一套 UI —— 降档时**不许换容器语法**（见 §6.3） |

**平铺档曾经是全案最坏的一处**：光点坐标写在 markup 的 `style="left:200px;top:345px"` 上，内联样式打败
`#cor[data-flat="on"] #s-act{top:640px}`，于是三行 340pt 宽的条目留在三角轨道位上 —— 右缘切字、被锁核压住，
而且那三行是带描边填充的圆角胶囊，**违反零卡片定理的唯一一处恰好落在无障碍层**。已修：坐标进 CSS，
胶囊删掉换成发丝线。iOS 侧的第一条硬约束由此得来：**可被降档重排的位置数据不许写成视图的内联样式。**

---

## 2. 几何与常数（全部机器推导，改一处必须重跑尺子）

| 量 | 值 | 怎么来的 |
|---|---|---|
| 机身逻辑尺寸 | 400 × 860 | 原型取景基准，iOS 侧换成安全区相对 |
| HOME（锁核待机位） | (200, 521) | 拇指区中心 |
| RIDE（浮层骑乘位） | Δ(130, −263)，scale 0.42 | 标题右侧；**必须 z 序在浮层之上**，见 §2.1 |
| LIMIT（拖拽半径） | 196 | 越界后走橡皮筋 `over·dim·c/(dim+c·over)`，c=0.55，**不是硬停** |
| CHARGE（充满时长） | 1100 ms | `S.cv = 1000/CHARGE`，同一连续量驱动环、光晕、缩放 |
| 动量投影 | `d=0.99`，钳位 `LIMIT×1.4` | Apple `project()` 指数衰减式，不是 `v²/2a` |
| 三光点轨道位 | 动态 (200,345) / 钥匙 (74,425) / 门锁 (326,425) | 等腰三角，顶角指向拇指反方向 |
| 进度环半径 | 66，与 rim 同圆 | **一处几何兼两个语义**：待机时是物体轮廓，按压时是轨道 |

### 2.1 两条会静默失效的坑（都已在原型上真实踩过）

- **z 序**：`.sheet` 在 DOM 里排在 `.core` 之后且无 z-index → 浮层整个盖住锁核。表现是"浮层态里锁核不见了"，
  六张截图里那个形态**根本没交付**，退化成一条普通 iOS 抓取条。修法是 `.core{z-index:3}` / `.sheet{z-index:2}`。
  iOS 侧对应：`matchedGeometryEffect` 的宿主层级必须显式，不能靠声明顺序。
- **特异度**：`#cor[data-mode="light"] .sw` 是 (1,2,0)，`.sw.on` 只有 (0,2,0) → 浅色档把"开"的状态色整条压掉，
  四行开关渲染成同一种灰，**ON/OFF 实测 1.02:1，状态只剩滑块位置一条线索**。深色档因为基础规则是 (0,1,0)
  所以完全看不出来 —— 这类缺陷只在一种主题下发作，走查极易漏。

### 2.2 复算

```bash
node contrast-check.js        # 36 个覆盖点 + 18 个防漂移锚点；exit 0 才算过
```
判据形状（不许只写"违规 0"）：文字 16 点 = 2 模式 × Σ(各落点实际档位)[top3+core2+hint1+sheet2]；
非文字/有色文字/平铺档 20 点 = 2 模式 × 10 条。
**正控**：把 A 调回 0.920 必须报出 FAIL（文字表 10 pass / 6 fail）；把四个施工旋钮退回改前坏值必须报出
FAIL（非文字表 16 pass / 4 fail）。**反控**：按施工值必须 0 条 FAIL。
**防漂移**：尺子回读 `core-ui.html` 的 18 个锚点，任一条对不上 exit 2 并点名 —— 这条是本轮自己撞出来的
（CSS 从 .11 一路改到 .035，`CUR` 里还留着 .11，连着两轮"改了值、数字不动"）。

---

## 3. 色板与对比度：不新增色板，但浅色档必须**单独解一组**

`MASTER.md` §4 的"不新增色板"仍然成立。变的是：**浅色档不能沿用深色档解出来的旋钮值。**

| 旋钮 | 深色 | 浅色 | 门槛 | 说明 |
|---|---|---|---|---|
| 极光场不透明度 A | **0.414** | 0.414（浅色再乘 0.34 且走 multiply） | — | 深色零余量上限 0.482，取 86% 留余量；最紧点 top/faint 5.02:1 |
| 核轮廓 `.body` 描边 | **0.525** | **0.55** | 3.0（1.4.11 非文字） | 轮廓 = 锁核的边界，边界责任在这一条 |
| 核盘体 `.body` 高光 | **0.095** | **0.845** | 1.10（软） | 只负责"玻璃更厚"，不该和轮廓一个标准 |
| 进度空轨 `.rim .trk` | **0.035** | **0.10** | **不设门槛** | 见 §3.2 |
| 进度弧 `.rim .bar` | #22D3EE → **#C7D2FE** → #F0ABFC | **#0E7490 → #4338CA → #86198F** | 3.0（对盘体 & 对空轨） | 浅色档必须换一组同色相深一档的 stop |
| 开关 OFF 轨道 | **0.13** | 0.14（**开口**） | 1.30 | 见 §3.3 |
| 到期警示文字 | #FBBF24（8.81:1） | **#836313**（5.31:1） | 4.5 | 它是文字，走 4.5 不走 3.0 |

文字三档 + 一档标签不变：深色 `#F2F6FB` / .78 / .56 / .82；浅色 `#0D1626` / .80 / .68 / .82。

### 3.1 为什么浅色档原先是"一张空白页"

第一轮评审用渲染像素实测报出浅色六处跌破底线（核体对页面底 1.09:1、开关 ON/OFF 1.02:1、到期码 1.46:1…）。
回源确认：**不是评审夸张，是我的尺子问的题目太少** —— 那 16 个覆盖点全是文字加一根图标描边，
没有一问是关于"一个非文字对象能不能被看见"。补到 36 点后，浅色档的六个数全部重解。

### 3.2 一条自造的门槛被删掉了（理由留在代码里）

第一轮为了把轮廓顶到 3.0，把门槛挂在了进度空轨 `.trk` 上。第二轮两个约束一撞就露馅：空轨要够深才撑得起
轮廓 → 进度弧得比空轨更抢眼 → 只能更深 → 两圈糊成一圈，反解直接报"四组候选都不过"。
真正该承担边界的是 `.body` 自己的描边。拆开后还剩一条「空轨对盘体 ≥1.15」—— 那是我自己发明的门槛，
没有任何外部依据，且和「弧对空轨 ≥3.0」夹出一个无解三明治（盘体、沟、弧要在同一圈 2.5px 上排开 4 倍亮度）。
**已删除，理由写在 `gchecks()` 原地**：空轨的可见性是构造保证的 —— 它就是同一条环上没被弧扫到的那部分。

### 3.3 一个诚实的开口

浅色档开关 OFF 轨道停在 0.14：过了 1.30 门槛（实测 1.34）但**没留够余量**。抬它会同时把 ON-vs-OFF 压到 3.0
以下，因为 ON 是渐变、其较淡的一端 #0E7490 才是约束。第二轮独立评审复算后确认这个耦合是真的，并建议按
"平台基线"记录而不是每轮重解（iOS 自家 OFF 轨道也在同一个带里，状态由位置+行标签双重编码）。
**要拿回边界，正确做法是给轨道加一圈 0.5px 描边（描边几乎不吃填充亮度），不是动品牌渐变。** 此条进 §11 待拍板。

---

## 4. 物理

| 场景 | response | damping | 出处 |
|---|---|---|---|
| 位移 / 缩放（默认） | 0.35 s | 1.0（临界阻尼，不过冲） | 屋式默认 |
| 带动量的释放（甩、松手回弹） | 0.35 s | 0.82 | 只有手势本身带动量时才给回弹 |
| 旋转 | 0.4 s | 0.8 | Apple 给的表 |
| 呼吸 | 0.13 Hz（周期 7.6 s） | — | 低于 ~0.2 Hz 前庭不适阈值；减弱动态档关掉 |

规则：X / Y / 缩放**各自一根弹簧**，不做二维合一起（两根速度不同时会脱节）；打断时从**呈现值**起，
绝不从目标值起；释放速率要交接给新弹簧（`dropHold()` 里 `cv=-1.6` 就是这个交接）；
`prefers-reduced-motion` 下所有位移/缩放换成交叉淡入，去掉过冲，保留透明度变化。

现状可复用的资产：`DS.Motion.tier` 已接 reduceMotion（`DesignSystem.swift:280`）与低电量双闸；
`DS.Hit.min = 44`（`:149`）。要新增的只有 `DS.Spring`（上面那张表），**零行为改动**。

---

## 5. 三域功能归属

三个光点 = 三个域。归属判据**沿用本仓自己写下的那一条**（`SettingsGroups.swift:8-15` 原文）：

> 「归属判据 (按"用户此刻想干的事", 不是按代码里的实现归属)… 一个 Section 只进一组:
> 允许它同时出现在两组就等于没收敛」

本仓给设置页写了这条却从没给 Tab 写过。新方案是把它推到顶层。

| 光点 | 域 | 作用对象 | 频率 |
|---|---|---|---|
| 动态 | 这一把锁发生过什么 | 事件流 | 天级，回看 |
| 钥匙 | 谁能开门 | 人 / 凭证 | 周级，代际 |
| 门锁 | 这一把锁怎么行为 | 硬件 | 月级，配置 |
| （门锁 → 本机与隐私） | 与任何一把锁无关 | App / 这台手机 | 极少 |

`SettingsGroups.swift:29-33` 那五组原样搬进来，成为「门锁」浮层内的分区，push 到「本机与隐私」：
`开门日常 / 凭证与成员 / 数据与安全 / 外观与辅助 / 帮助与关于`。
18 个 section 的现有归属（`SettingsView.swift:95-111`，已逐条核对，零死代码）：

- 开门日常 → `lockSection` `deviceManageSection` `unlockSection` `autoOpenSection` `reminderSection` `alertToneSection`
- 凭证与成员 → `familySection`（`credCareSection` 挂在它内部，`SettingsView.swift:715`）
- 数据与安全 → `securitySection` `toolsSection` `drillSection` `applockSection`
- 外观与辅助 → `timeSection` `a11ySection` `appearanceSection`
- 帮助与关于 → `memorySection` `helpSection` `aboutSection`

`SettingsGroupChips`（筛选 chip 行）在**新方案里删掉**：chip 是胶囊容器，违反公理 1；而且它存在的理由
是"18 节一页装不下"，域拆开后不需要了。

### 5.1 五条实证冲突（`MASTER.md` §10.2，仍然有效）

E1 备份两个入口 + `BackupView`/`BackupStudio` 两文件并存；E2 快捷 6 格里没有"开锁"这个秒级动作
（新方案整块废除快捷池）；E3「家人与钥匙」混了人/硬件/钥匙/事件四种对象；E4 固件升级、告警中心、
家政维保同时挂在设置和快捷池；E5「时间显示」与「校准时间」共用一个名字 → 改名 **时钟显示 / 校准锁钟**。

---

## 6. 逐文件改造清单

**取证状态必须先说清**：下表 32 个 UI 文件里，只有 17 个是**读过源码**的（`AppIntents.swift`、
`SettingsGroups.swift` 与 15 个 ≤663 行的文件，第二轮已逐文件核对类型、容器、`kf_` 键、可达性并带行号）。
另外 **14 个大文件只有文件名与行数** —— 一次并行取证被中断，它们的归属是**推断，未核**，
施工前必须先读源（见 §11 P-4）。

### 6.1 已核（17 个）

| 文件 | 行数 | 去向 | 依据 |
|---|---|---|---|
| `App/LockKeeperApp.swift` | 2112 | **重写** `RootView`：`mainTabView`(:1132-1158) 整块换成锁核宿主 | 已读 |
| `App/UI/UnlockDial.swift` | 1019 | **删除**，物理层并入锁核；~13 层压到 2 层 | 已读 |
| `App/Core/DesignSystem.swift` | — | **删** `HeroCard`(:925-987) `HeroFlairBorder`(:990-1006)；**改** `DS.Metric.dial`(:153-156)；**增** `DS.Spring` | 已读 |
| `App/Core/AccessibilityKit.swift` | — | `axGlass*`(:348/:353/:360) 保留；**增** `axGlassSheet`；`AXFlags`(:12-74) 增平铺档 | 已读 |
| `App/Core/SettingsGroups.swift` | 96 | 五组枚举保留；**删** `SettingsGroupChips`(:54-96) | 已读 |
| `App/Intents/AppIntents.swift` | — | 六个 intent 保留；`:466` 那句 kf:// 说明文案必须同步改 | 已读，原文见 §7 |
| `MemberCenterView.swift` | 2401 | → 钥匙（按人分组） | 已读 |
| `CredentialCenterView.swift` | 1377 | → 钥匙 | 已读 |
| `SecurityCenterView.swift` | 1999 | → 本机与隐私 | 已读 |
| `AccessibilityView.swift` | 500 | → 外观与辅助（21 个 `kf_` 字面量 / 15 个去重） | 已读 |
| `AchievementsView.swift` | 663 | → 动态（纪念按强调级分层）；`CareRemindersView` 拆出 → 门锁 | 已读 |
| `RecordsTimeline.swift` | 653 | → 动态的详情层；`:425` 有 `kf://records?k=` 深链 | 已读 |
| `CareViews.swift` | 558 | → 门锁（维保 / 换电指南） | 已读 |
| `ChangelogView.swift` | 535 | → 帮助与关于；`:25` 有 kf://device 文案 | 已读 |
| `AlarmCenterView.swift` | 806 | → 动态（与记录同一条时间轴） | 已读 |
| `HelpCenter.swift` | 819 | → 帮助与关于 | 已读 |
| `LockOverviewView.swift` / `DeviceManageView.swift` / `LockCompareView.swift` / `BackupView.swift` / `BackupStudio.swift` / `DiagnosticsView.swift` / `DiagReferenceView.swift` / `ExportCenter.swift` / `StatsView.swift` / `Sheets.swift` / `Onboarding.swift` / `Celebration.swift` / `DeviceStripCard.swift` / `DataScannerView.swift` / `DecoyShellView.swift` / `ReportVerifyView.swift` | — | 见下条 | **部分已读**：`Celebration`（`MomentCardView` 挂在 `LockKeeperApp.swift:1274`，属"开门"形态的一部分）、`DeviceStripCard`（名字里就带 Card，公理 1 直接命中 → **删容器留数据**）、`DecoyShellView`（伪装，属本机与隐私）、`DataScannerView`（无界面，相机封装，保留）、`ReportVerifyView`（→ 门锁）已读；其余 11 个**未读源** |

### 6.2 未核，施工前必须先读（14 个大文件）

`RecordsView`(3653) `CredentialStudio`(3310) `Sheets`(2850) `BackupStudio`(2759) `CredentialsView`(2723)
`DeviceHomeView`(2549) `StatsView`(2471) `MemberCenterView`(2401，已读) `ExportCenter`(2248)
`SecurityCenterView`(1999，已读) `DiagnosticsView`(1423) `CredentialCenterView`(1377，已读)
`HelpCenter`(819，已读) `AlarmCenterView`(806，已读) `Onboarding`(704)

真正未核的是：**`RecordsView` `CredentialStudio` `Sheets` `BackupStudio` `CredentialsView`
`DeviceHomeView` `StatsView` `ExportCenter` `DiagnosticsView` `Onboarding`** 十个，共 23,722 行。
其中 `Sheets.swift`(2850) 最关键 —— 它是全仓 91 处 `.sheet(` 的主要宿主，新方案里"浮层"是唯一的
呈现容器，这个文件要么成为锁核宿主的实现、要么被拆掉，必须先看它现在装了什么。

### 6.3 一条必须带进 iOS 实现的纪律

**降档不许换容器语法。** 平铺档那次翻车的根因不是坐标写错，是我在"无障碍版"里偷偷允许了胶囊。
iOS 侧每一条降档路径（`AXFlags` / `reduceMotion` / `reduceTransparency` / `highContrast` / 低电量）
都只能改**密度、材质、动效**，不能改**有没有盒子**。这条要写进 §10 的闸门。

---

## 7. 连带缺陷面（Tab 彻底消失后的悬空引用）

命中本仓高发族「删/改名留悬空引用」。全部数字为本轮机器实测：

| 量 | 实测 | 复算 |
|---|---|---|
| `requestTab(<字面量>)` | **40** 处 / **12** 文件（0:5 1:16 2:2 3:17） | `grep -rnoE 'requestTab\([0-9]\)' --include=*.swift App \| wc -l` |
| `tabSelection` | **74** 处 | `grep -rn tabSelection --include=*.swift App \| wc -l` |
| `TabView` | 30 处 / 11 文件 | 同上 |
| `.sheet(` | **91** 处 | `grep -rnF '.sheet(' --include=*.swift App \| wc -l` |
| `kf_` 去重字面量 | **299** | `grep -rhoE '"kf_[A-Za-z0-9_.]+"' --include=*.swift App \| sort -u \| wc -l` |
| `axGlass*` 调用点 | **24** 处 / 9 文件（19+2+3，排除定义文件） | 见 `MASTER.md` §2 更正行 |
| `matchedGeometryEffect` / `navigationTransition` / `glassEffectID` | **0 / 0 / 0** | 形变转场从零开始 |

### 7.1 最高危：访客门禁会**静默**失去覆盖

`guestBlockedTabs: Set<Int> = [1, 3]`（`LockKeeperApp.swift:92`）是**同一个量的双实现**之一 ——
另一处是层级摘除（`:1141`/`:1154`）+ `requestTab` 闸门（`:161`/`:235`），两边都硬编码字面量 `[1,3]`。
新容器里没有 Tab 序号，两处同时失去指称对象，而「本机与隐私」（应用锁 / 访客 / 伪装 / 销毁）
正是被它保护的东西。**不会崩、不会报错、走查看不出来。** 必须改成"封页面身份"而不是"封 Tab 序号"，
同一批内完成。

### 7.2 `kf://` 的四个 host 名散在四处，其中两处是**用户可见文案**

已取到原文：
- `AppIntents.swift:466`：「kf:// 路由: 支持 device / credentials / records / settings 四个入口, 其余地址一律
  忽略; 锁屏状态下先挂起, 解锁后才跳转。小组件走的也是 device 这一条」
- `ChangelogView.swift:25`：「走的还是原来那条 kf://device 深链, 所以应用锁没解开时它只会挂起, 不会给绕过门禁的第二条路。」
- `QuickActions.swift:19-21`：主屏长按三条 —— `records`/查看记录/`kf://records`、`tempcode`/生成临时码/`kf://credentials`、
  `battery`/查电量/`kf://device`（**没有 settings**）
- `SpotlightKit.swift:38`：`URL(string: "kf://device?mac=" + …)`

改路由不改这两句说明文案 = 命中「说明句多写必漏」。host 名建议**保留旧值做别名**，
新值另加，避免主屏快捷方式与 Spotlight 索引在升级后失效。

### 7.3 偏好键存活

299 个 `kf_` 去重键（另有约 30 个 MAC 前缀族）。`SettingsView` 读 31 个、`SecurityCenterView` 读 36 个、
`AccessibilityView` 读 15 个（去重）。**容器重写不许静默丢用户偏好** —— §10 每批都要带一份
"本批涉及的 `kf_` 键 + 保留/迁移/删除"清单，删除的必须给出迁移写入。

---

## 8. 降级矩阵

| 信号 | 来源 | 影响 |
|---|---|---|
| `reduceMotion` | `AXFlags` + `DS.Motion.tier`(`DesignSystem.swift:280`) | 极光漂移停、呼吸关、位移换交叉淡入、去过冲 |
| `reduceTransparency` | `axGlass`(`AccessibilityKit.swift:348`) | 玻璃 → `Palette.surface` + `hairlineStrong` 描边；**浮层与锁核都要有实底档** |
| `highContrast` | `DesignSystem.swift:339` | 发丝线 → 实线；**此时允许出现边界，但不允许出现圆角矩形容器** |
| `appLowBattery` | `BatteryCare` | 并入 calm 档 |
| 平铺档 | 新增 `AXFlags` 位 | 三光点 → 三行；拖拽退场、按住保留 |

**平铺档与 reduceTransparency 会同时开**，那一格现在没人验过：实底 + 三行 + 无动效。列为 §11 P-3。

---

## 9. 施工批次

每批独立可编译、独立可回退。本机无 Xcode/模拟器，**唯一验证途径是 CI**
（`.github/workflows/ios.yml`，36 步 / 18 判失败 / 10 报线索）。

| 批 | 内容 | 行为改动 | 为什么先做 |
|---|---|---|---|
| **C1** | `requestTab(Int)` → `requestTab(Route)` 枚举，40 处裸整数变编译期可查 | **零** | `MASTER.md` §10.4。不做这步就改 IA = 在 12 个文件里手改 40 个数字靠人眼 |
| **C2** | `DS.Spring` 新增 + `axGlassSheet` 新增 + `AXFlags` 平铺档位 | 零 | 纯加法，先把地基铺好 |
| **C3** | 访客门禁从"封 Tab 序号"改成"封页面身份"，双实现合一 | 有，可测 | §7.1，最高危，必须在动容器**之前** |
| **C4** | 锁核宿主 `CoreRootView` 上线，与旧 TabView **并存**，用灰度开关切 | 有 | 可回退；旧路径整批留到 C9 才删 |
| **C5** | 三域浮层：动态 / 钥匙 / 门锁。`Sheets.swift` 拆解（先读源，§6.2） | 有 | 主体量 |
| **C6** | 本机与隐私 push；`SettingsView` 18 节按五组归位 | 有 | §5 |
| **C7** | 删 `UnlockDial` / `HeroCard` / `HeroFlairBorder` / `Card` / `DeviceStripCard` / `SettingsGroupChips` | 有 | 悬空引用高发，配 §10 闸门 |
| **C8** | `kf://` 别名 + 主屏快捷 + Spotlight + 两处说明文案同步 | 有 | §7.2 |
| **C9** | 删旧 TabView 与 `mainTabView`；`kf_` 键存活表收口 | 有 | 最后才拆旧桥 |

---

## 10. 验收尺子（要新建的）

`tools/` 现有 28 个 `.js`，`contrast.js` 36 条断言。本方案要新增/增补：

1. **`tools/uibudget.js`**（`MASTER.md` §6 已立项）—— 判零卡片定理与发光层预算。
   正控：fixture 里放"玻璃套玻璃"与"Hero 多行条件提示"必须检出；
   反控：现有 **24** 个 `axGlass*` 调用点中合规的必须不报（`MASTER.md` §6 已把 35 更正为 24）；
   真树：报数必须声明范围与形状，不许只写"违规 0"。
   **额外一条**（§6.3）：扫 `data-flat`/降档分支里新出现的容器类型，降档换容器语法要报错。
2. **`tools/tabref.js`** —— 扫裸整数 `requestTab([0-9])`、`guestBlockedTabs` 字面量、`deepLinkHosts`
   字面量，C1 之后必须恒为 0。这是 §7.1 的静态闸门。
3. **`tools/cssdrift.js`** —— 把 `contrast-check.js` 第 8 节那个"回读真源"的做法搬进仓库：
   任何判据里出现的常数，必须能从被检文件里读回同一个值。**本轮真实教训**：CSS 改了、`CUR` 没改，
   连着两轮"改了值、数字不动"，我差点判成模型错。
4. **`tools/contrast.js` 增补** —— 现 36 条按纯色面与渐变端点算；补玻璃面按"最坏背景"算
   （极光双团 screen 重合 + 该落点 veil 实际强度，按 CSS 几何算不是按区域拍数）。
   已知风险：第八十三批"白字压洗白底"实测 3.74:1 —— 玻璃化后同一形状会再来一次，
   **先写断言再改代码**。

---

## 11. 待拍板（不回话即按括注默认施工）

- **P-1 浮层态读不到锁状态。** 第二轮评审的问题 4：`openSheet` 把状态大字整块淡出，浮层头部左标题、
  右锁核、中间空场；锁状态唯一的载体是那枚缩到 63px 的圆盘上的锁形。一个门锁 App，在「门锁」浮层里
  拨"自动上锁"的时候不告诉你现在锁着还是开着。（默认：浮层态保留一行小号状态读数，占用顶部空场，
  不新增元素。）
- **P-2 浮层态没有横向通路。** 评审问题 3：`openSheet` 把另外两个光点降到 0.18 且被浮层整个盖住，
  平铺档三行同样在浮层底下 —— 实测平铺档的 act/key/lock 三帧与常规档**逐像素相同**。
  北极星是"导航即画面"，现在去程成立、回程没有画面，三域之间零横向通路。
  （默认：浮层顶部留一条域切换带，平铺档在浮层态仍提供带字条目。）
- **P-3 平铺 + 降透明同时开**，那一格无人验过（实底 + 三行 + 无动效）。
  （默认：C2 里出一张真机卡，进 §7.9 台账。）
- **P-4 十个未读源的大文件（23,722 行）** 的归属目前是推断。
  （默认：C5 开工前先做一轮逐文件取证，归属表按证据重排，不拿推断施工。）
- **P-5 浅色开关 OFF 轨道的余量**（§3.3）。
  （默认：按平台基线记录，加 0.5px 描边而不是动品牌渐变。）

---

## 12. 未验证 / 已知边界

- 本机无 Xcode 与模拟器，**全部编译验证只能靠 CI**；runs/jobs/annotations 匿名可读，整包日志要 token。
- iOS 27 SDK 两条二手信息（`UIDesignRequiresCompatibility` 是否失效、系统级玻璃透明度滑块）
  **仍未从 Apple 一手页面核实**，见 `MASTER.md` §9，不当既成事实。
- 原型是 HTML，SwiftUI 侧的 `matchedGeometryEffect` / `navigationTransition(.zoom)` / `glassEffectID`
  **全仓 0 使用** —— 三个 API 都还没在这个仓库里跑过一次，C4 是它们的第一次。
- 两轮独立评审的分数（5、7）不互相可比也不与任何外部标准可比，只用作"这一版比上一版少了什么"。
  动效始终**没有被独立评审确认过**：取证工具没有"按下并保持"动作，ffmpeg 构建读不了 PNG，
  1100ms 充能全过程与涟漪/泛光过渡只有终态静图。

---

## 13. 两套并存的实际落地（2026-10-16 追加，取代本文"只做一套"的隐含前提）

需求变更为：**一套 App 里并存两套完整 UIUX（本文的「一枚锁核」+ 同日另一套「近场仪表」），App 内可切换**。
本节记已落地的架构，§9 的 C1–C9 批次表仍然有效，但 C1 已经做完并且比原计划收得更紧。

### 13.1 为什么不是"77 个页面各抄一遍"

抄两遍之后，任何字段、文案、开关行为都要改两次 —— 就是本仓反复踩的"同一个量算两次"，
两套必然漂移，漂到最后就是"切到某版少一个功能"。**内容必须单一来源。**

也不采用中央路由表：77 个目的地绝大多数由宿主本地 `@State` 呈现
（`.sheet(item: $x) { LockProfileView(mac: $0) }`），搬到中央路由要先提升全部本地状态；
而 `@ViewBuilder` 装不下 77 个分支（本仓已两次因巨型 body 报 type-check 超时）。

采用：**每套变体定义一份完整视觉语法，所有目的地经过同一个缝。**

| 一致性 | 完整性 |
|---|---|
| 语法只有一个实现处（`VariantGrammar.swift` 的 `VK`），页面拿不到"自己随便画容器"的余地 | 每个方法内部是穷尽 `switch`，少给某变体定义就编译不过；空壳分支由 `tools/uicoverage.js` 检查三抓 |

### 13.2 新增文件

| 文件 | 作用 |
|---|---|
| `App/Core/UIVariant.swift` | `legacy / core / gauge` 三态，默认 legacy（零行为改动） |
| `App/Core/Route.swift` | 目的地身份。**顺序、深链 host、访客受限集三样都从它一处派生**，不再各写一张表 |
| `App/Core/Destination.swift` | 77 个 case，由 `node tools/destmap.js --emit` 生成，**不许手改** |
| `App/Core/VariantGrammar.swift` | `VK` 语法层 + `.destined(_:)` 缝 + `PlateShape` / `View.variantPlate`（2026-10-16 批一，装饰性中性底衬的接手件）+ `VisitLedger` 到达台账 + `VariantCoverageRow` |
| `App/UI/VariantRoots.swift` | 两套首屏 + 共用的诚实读数层 `LockReadout` + 域浮层（两版共用一张） |
| `tools/destmap.js` | 目的地台账；正控 7（逐呈现通道）+ 反控 3 |
| `tools/uicoverage.js` | 四道检查：枚举漂移 / 缝覆盖率 / 语法穷尽性 / 裸写换页 |
| `tools/applyseam.js` | 挂缝（重命名 `body`→`vkBody` 再插一行，与 body 内部结构无关） |
| `tools/migrateroute.js` | 一次性迁移 23 处裸写 `tabSelection = <序号>` 到 `requestRoute` |

### 13.3 本轮被闸门抓出来的真缺陷（不是理论风险）

- **`sheetcover` 抓到我自己写的**：`CoreHomeView` 用 sheet 端出 `RecordsView`，
  而它内部有 `requestTab(1)` —— 新变体没有 Tab，切不动而 sheet 还盖着。
  修法是让域浮层**挂在两版共用的 `VariantRootView` 上、内容跟着 `variantDomain` 换**：
  切域是换人不是叠层，这一族缺陷在两套里都不成立。
- **`destmap` 的旧正则一直在漏计**：`\([^)]*\)` 吃不下 `.sheet(isPresented: Binding(get:{},set:{}))`，
  参数里带括号的 sheet 整段作用域被跳过。修好后台账从 74 涨到 **77** —— 之前少报 3 条。
- **`uicoverage` 的漂移检查抓到 gauge 变体没有域浮层**：域浮层原先只挂在 `CoreHomeView` 里，
  仪表版点"全部页面"会设上状态却没有任何东西呈现。
- **`dynamictype` 抓到新界面 38 处写死 pt 字号**：`.system(size:)` 不参与 Dynamic Type，
  等于把无障碍字号档静默关掉。已全部换成语义字号（图标尺寸除外，那是该写死的）。
- **`device` 不该被端成 sheet**：两套新界面里"设备"就是首屏本身，
  `requestRoute(.device)` 在非 legacy 下的语义是收起域浮层。

### 13.4 进度（2026-10-16 第二接手轮更新；批五~批七 + P5 + P7 见交接文档 §8.9）

- ~~裸写 `requestTab(<字面量>)`~~ → **已完成**（36 处全换 `requestRoute`，`pendingRoute` 亦收成 `Route?`），
  现由 `uicoverage` **检查六** 守着不回潮。详细复算见 `docs/HANDOFF-2026-10-16-UI-VARIANTS.md` §4 P3 / §8。
- ~~两套首屏仍自带排版~~ → **gauge 首屏两块面板已走 `VK.container`**；`VK.metric` / `VK.primaryButton`
  刻意不用（会把"不在场 = 读数不可信"的琥珀/灰双色档、以及主按钮渐变拉平），理由见交接文档 §4 P2。
  `CoreHomeView` 的形状语法件（dot / core）并进拖拽那一批。
- ~~77 个页面内部只从缝里拿到"底色 + 记账"~~ → 现已是**整页级**下发：页面底色 100 +
  清单骨架 `variantList()` **85**（分组内缩/行分隔线/节距/Section 标题渲染，全仓 255 个 `Section` 的外观在这里）
  + 缝里一行 `.tint` ⇒ 全仓 **120 处 `Toggle`** 与所有滑杆/选择器 + 共享按钮 **61** 处
  + 三个语法件（`variantPlate` / `variantList` / 三个 `ActionChrome`）。
  自绘容器 176 → 151 → 131 → **113**（批五再收 18 处纯装饰，见下一条）。
  **113 这个数不是一个进度条，是三类不同的问题加在一起**：
  ① 带状态语义的底衬（开关轨道/进度空槽/选中态）、② 控件可识别性底衬（输入框底/实底进度/面板实底）、
  ③ 条/刻度/点（根本不是容器）。
  **①②③永久豁免，且要留痕**：每处就地写 `// @layout-allow VK豁免 <类名>`（判据与清单见交接文档 §8.9）。
  这不是"先不做"——接进去会把功能改坏（状态信息消失、输入框消失），而闸门**看不见**这种坏。
  分类、覆盖度表与下一步见交接文档 §4 P1 与 §8.5 / §8.9。
- ~~带 tone 的提示条~~ → **已接完**：新设 `VK` 语法件 `variantCallout(_:_:wash:)`（`VariantGrammar.swift`），
  16 处语义洗底块全部改走它（`LinkSenseKit` 1 / `BackupStudio` 6 / `CredentialStudio` 6 / `CredentialsView` 3）。
  **它不是 `variantPlate` 的一个参数**：`variantPlate` 收的是装饰性底衬，core 里整块去掉是对的；
  而提示条那层洗色是**信息**("这一段是告警")，core 去掉它就等于把信息去掉 —— 所以 callout 的 core 分支
  换的是**载体**：洗底 → 左侧一根 2pt 的染色线（与 `VK.card` 的 core 分支同一条纪律：
  盒子没了、语义色还在且更显式）。gauge 分支 = 凹槽窗格 + 同一根 tone 侧线。legacy 分支逐字复刻原句 ⇒ 外观零变化。
- ~~4 处 `surfaceAlt + Capsule + strokeBorder` 胶囊~~ → `variantPlate(_:_:edge:)` 新增 `edge` 参数收掉
  （`AccessibilityView` 1 / `StatsView` 3）。描边**不复用** `legacy`：`strokeBorder` 只长在 `InsettableShape` 上，
  而 `AnyShape` 把它擦掉了（`AccessibilityKit` 里记过这条），所以单开 `legacyEdge(_:_:)`。
- ~~行里面那点内容怎么排~~ → **字号/字重/字族已接管**（批七）：全仓 1,775 处文本 `.font(...)` 改为
  `.vkFont(_, weight:)`，变体差在语法层一处定：core 字重整体降一档（层级从字重挪到字号，公理 1）、
  gauge 字重升一档 + 整族等宽化（机加工读数），legacy 逐字原样。由 `uicoverage` **检查八** 守着不回潮。
  **字距仍未接管**：那 28 处 `.tracking(...)` 是显式写在调用点的，语法层再加一份会叠成两倍（下一批）。
- `VisitLedger` 的 N/77 需要真机点一轮才有数；本机无 Xcode，这是唯一能拿到"完整"证据的路。
  本轮把两处会**静默**污染这个分母的缺陷修了（交接文档 §8.9 第 3 条）：注释里的实例化被当成了目的地、
  四个 Tab 的根页因为写的是"内容属性"而一个都没进台账。修完仍是 77/77，但**每一条都有据可查**了。
- ~~拖拽召唤锁核（1:1 跟手 + 橡皮筋 + 动量投影）与 `matchedGeometryEffect`~~ → **已实现**（P5）：纯几何抽成
  `App/Core/SummonGeometry.swift`，由 `tools/summonshadow.js` 用另一门语言对拍 30 条（含 11 个文档锚点的防漂移）。
  未验的照实说：形变的观感、1:1 跟手的手感、弹簧曲线 —— 一条都没被执行过，只有算术被验过。
  按压充能（1100ms）与开门三层涟漪**未做**（不在这批）。
- ~~`DS.VariantPalette` 那 12 档变体色不在 `tools/contrast.js` 的断言覆盖里~~ → **已解决**：
  10 档已搬进 `DS.Palette`（`DesignSystem.swift` 的 `enum Palette`），`contrast.js` 新增 F 节 12 条
  （421 条 0 不达标）。**当场抓到并修掉一处 AA 级缺陷**：仪表深档主按钮文字压琥珀渐变暗端 4.47:1 → 纯黑 4.90:1。
  详细复算：交接文档 §7 与 §8.1-3b。
- 但 `core-ui.html` 那套 **HTML 原型 token** 的尺子仍未覆盖 gauge（另一把尺，见 §3 / §12）。
