# FEATURE-LEDGER — 功能点总账 · 分组诊断 · 新信息架构方案

> 作者：feature-ledger（teammate，共享任务 **task-3**）· 唯一产出：本文件
> 覆盖面：`ios-app/App/` 109 个 .swift / 46,146 行 · `android-app/` 9 个 .kt · `docs/` 台账 6 份
> 规范面：`ios-glass-design-spec/references/design-spec.md` §0 / §1 / §8 / §12
> 未修改任何 `.swift` / `.kt` / `tools/*.js`；未运行会写文件的闸门（`destmap.js` 不带 `--emit`、`golden.js` 未跑）

## TL;DR（给 Lead 与下一轮的四条结论）

1. **现在不存在「一套分组」**，而是**四套并行口径**：`ManagerGroup` 5 组（21 条路由，组内可见 20）/ `MePage` 4 段（20 条链接）/ `SettingsGroup` 5 组（**零调用**）/ `Route` 4 Tab（已被压平成 5 组）。四者之间没有单一事实来源，任一处改动都不会通知其它三处。
2. **最贵的三个结构性洞**：① **9 个页面**在 ManagerFace 与 MePage 各有一个入口（`LocksPage`/`FirmwarePage`/`GatewayPage`/`DonglesPage`/`SyncTimeView`/`SafemodeIntroView`/`BackupPage`/`ExportCenterView`/`DiagnosticsPage`；`D3` 写的『不改』，其推翻条件『同一功能两处行为不一致』已经发生）；② 一批页面**写完了但零可达**（`AlarmCenterView` 898 行 / `BackupView` 272 行 / `StudioPage` 252 行 连带 `FpStudio`+`OtpStudio` 两个工坊 / `LockOverviewView` 与 `DeviceStripCard` 只剩注释），而 `reach.js` 因『按名字提及建边』看不见这个洞；④ 帮助 / 更新说明 / 版本号**三页全缺**，`changelogcheck` 闸门因此空转。
3. **推荐方案：5 个域，3 层深，域内 3–7 项。** 域名以本仓 `SettingsGroups.swift:9-13` 的既有用户语言为底（5 个里 2 个原样沿用、3 个改并逐条给理由，见 §3.2），**不是我凭空发明的**。迁移映射表 §3.3 共 **67 条**可勾项：合并 9 组 / 删入口 6 类 / 改归属 18 条 / 新增 4 项。Android 明确**不跟**——它是极简客户端，屏数上限由协议面（3 条命令）决定，不由 iOS 的 152 条功能点决定。
4. **自检与边界**：§5 的 8 条判据 **7 条过、1 条部分过（①）、0 条完全不过**；§6 写明了哪些是 E1/E2/E3、哪些**没有验证**（用户价值判断 / 真机可用性 / 映射表完整性 / G20 严重度），以及一句必须写死的话 —— **本轮没有改一行源码，§3 是方案不是既成事实**。
---

## §0 口径、证据分档与两条必须先说的免责

### 0.1 证据三档（每行都标）

| 标记 | 含义 |
|---|---|
| **E1** | 我实际跑了命令并读到输出（命令与关键数字写在该行/该节） |
| **E2** | 我读了源码，结论可由当行 `文件:行` 复现 |
| **E3** | 转述文档/别人的产出（写出处） |
| 未读到 | 我没读到对应源码，不猜 |

**本轮实际跑过（E1）的闸门**（全部只读，仓内 `git status` 未被它们改动）：

```
node tools/destmap.js        -> exit 0, 首次读 19 个目的地；并行改动落地后复跑 = 20（新增 SecurityPeekView，见 §2-G1）
node tools/destmap.js --json -> exit 0, 逐条 sites{file,line,how}
node tools/featuremap.js     -> exit 0, A245/A1 37/A0-x 25/A0-w 5/A0-d 110/A0-t 66/A0-u 2 · B44/C19/D1/E0/F6/G1/R6/W8 · 实现证据 730
node tools/reach.js          -> exit 0, View struct 90 个, 从 RootView 可达 89, 不可达 1 (XLockBlade)
node tools/deadscan.js       -> exit 0, A 档"确证零引用" 146 条
node tools/keydead.js        -> exit 0, 只写不读 10 个 / 只读不写 40 个 / 前缀族 3 个
node tools/deadfuncs.js      -> exit 0, 1119 个函数声明里零调用 148 个; "有读无写" 7 组
node tools/pagecraft.js      -> exit 0, 20 条路由平均 98.8%, 未满分 1 (StudioPage 3/4)
node tools/uicoverage.js     -> exit 0；首跑 台账 19 = 枚举 19、缝覆盖 18/19（缺 CredentialBinView）、自绘容器 31 < 基线 32；复跑 台账 20 = 枚举 20、缝覆盖 18/20（缺 CredentialBinView + SecurityPeekView）
node tools/changelogcheck.js -> exit 0, 但**空转**: "更新说明页不存在 (App/UI/ChangelogView.swift) ⇒ 本闸门无事可做"
```

> **写作期间发生的一次并行改动（E1 现场）**：`MePage.swift:145/154` 那两个同指 `SecurityPage()` 的链接，在我第一次读到之后被改成 `:161 → SecurityPeekView()`；`destmap` 于是从 19 变 20，`Destination.swift` 也跟着重新生成（多了 `securityPeek`）。
> 我**没有**跑过 `destmap --emit`，这些改动不是我做的（`git status` 里 `App/Core/Destination.swift` 的 diff 与我无关）。本文两处数字都保留（19 = 首读，20 = 复跑），并标明时刻。

### 0.2 免责一：行号会漂，请按名字 grep 而不是按行号定位

工作区当前**有并发未提交改动**（E1 `git status`）：

```
 M App/Core/Components.swift, App/Core/Theme.swift, App/UI/HomeConsole.swift, App/UI/ManagerFace.swift
 M App/UI/MePage.swift, App/UI/KeysPage.swift, App/UI/EventsPage.swift, App/UI/StatsPage.swift …（共 20 个 .swift）
?? docs/GLASS/, tools/glassaudit.js, App/Core/Theme.swift.pre-glass
```

其中 `HomeConsole.swift`(+26 行)、`ManagerFace.swift`(+3)、`Theme.swift`(+139)、`Components.swift`(+209) 正在被并行改动。
**本文件的行号是 2026-10-22 16:00 前后的工作区快照**；这四份文件改动前后的行号差见下表，读的时候宁可 grep 类型名/函数名：

| 文件 | 我引用时依据 | 备注 |
|---|---|---|
| HomeConsole.swift | 工作区（1117→1143 行） | `struct HomeConsole` 在 HEAD:47 / 工作区:53 |
| ManagerFace.swift | 工作区（299→302 行） | `enum ManagerRoute` HEAD:241 / 工作区:244 |
| Theme.swift | 工作区（412→551 行） | `enum XPalette` HEAD:32 / 工作区:48 |
| Components.swift | 工作区（1443→1652 行） | `struct XRow` 两边都是 395（巧合） |

### 0.2b 写作期间我**看到**的并行改动（不是我做的，但影响本文数字）

| 文件 | 改动 | 对本文的影响 |
|---|---|---|
| `App/UI/MePage.swift` | `:161` 的「隐私与伪装」从 `SecurityPage()` 改指 `SecurityPeekView()`，并留注释（`:156-160`） | 修掉了 §2-G1 的『两个链接同指一页』；`destmap` 19→20 |
| `App/Core/Destination.swift` | 新增 `case securityPeek`，头注释 19→20 | 是 `--emit` 的产物（**不是我跑的**） |
| `fixtures/uicoverage/budget.json` | `selfDrawnContainers` 32→31 + note 追加一行 | 我跑 `uicoverage` 时读到的是 31 = 基线 |
| `android-app/.../Tokens.kt` | 整份重写（见 §4.4） | §4.4 的结论从『注释是假的』改为『已修』 |
| `App/UI/KeysPage.swift` | +18 行（搜索 / 长按菜单区域重排） | §1.3 里 KeysPage 的行号已按 HEAD 标注 |
| `App/Core/Theme.swift` / `Components.swift` | 大幅重写（+139 / +209 行） | 令牌行号全部按 HEAD 标注 |

> 这条表存在的意义：**下一轮读本文的人不该被『为什么同一份文档里 19 和 20 都出现』绊住**。

### 0.3 免责二：`destmap` 的 19 不是页面总数，是"呈现通道"总数

这是一个**必须先纠正的读数**，否则后面所有"全不全"的讨论都建立在错的分母上。

`destmap.js` 只认 6 条呈现通道（sheet / fullScreenCover / navigationDestination / popover / NavigationLink / Tab）里的**实例化**（E2 `tools/destmap.js:40,168-176`）。
而 ManagerFace 的纵深页是走 `path.append(route)` + `switch` 落地的（E2 `App/UI/ManagerFace.swift:145` 的 `path.append(route)`、`:204-235` 的 `routeDestination`）
—— 这条通道**一条都数不到**。所以：

- `destmap` = **19**（首读，E1）→ 复跑 **20**（并行改动新增 `SecurityPeekView` 一个真实目的地，见 §2-G1）
- `ManagerRoute` 自己就有 **21** 个 case（E1 逐 case 数，工作区 `ManagerFace.swift:277-286` 与 HEAD 版同为 21；任务卡写的 20 是漏数），且每个 case 在 `routeDestination`（工作区 :204-235）都有落地页
- `App/UI` 下 53 个文件里有 **96 个 `struct X: View`**（E1 逐文件正则统计）

⇒ 19 是**下界**，不是总数。任何"目的地 = 19 / 77 / 76 条一条都不能少"的表述，都只是在说"某条测量管道看到了几条"。
`docs/redesign/PART2-NAV-IA.md:17-19` 的"77 = 4 根屏 + 51 一级 + 22 二级"是**另一套口径**（那时还按 4 Tab 算），与本轮单控制台结构不再对应。
本文件的做法是：**不引用任何"总数"作为完备性证明**，而是逐条列功能点、逐条给锚点。


---

## §1 功能点总表

### 1.1 覆盖口径（先定分母，否则"全不全"这句话没有意义）

三路来源与各自的分母：

| 来源 | 规模 | 我怎么用 | 不能拿它当什么 |
|---|---|---|---|
| **代码**（App/ 109 个 .swift / 46,146 行 / 96 个 `struct X: View`） | E1 逐文件统计 | **主口径**：每条功能点必须有 `文件:行` | 不能当"用户能用"——同一份代码里有 148 个零调用函数（E1 `deadfuncs`） |
| **台账**（IDEA-BANK 1050 条 / FEATURE-TRIAGE 1190 行 / CAPABILITY 100 / FUNCTION-MATRIX 147 / ROADMAP-DRAFT 310 / DEFERRED 481） | E2 通读 | 只用来**补漏与对状态**（尤其"判 ❌ 但代码里有"这类） | 不能当"实现了"——见下条 |
| **交叉验证**（`node tools/featuremap.js`） | E1：A 档 245 条（复跑同值） | 只在 §1.4 引用它的分档数字 | **不能当验收**。README:151 原话：「标注只是实现证据的一种形式，A 档里 35 条其实是"做时没写编号"」。分档是**标注形式的证据**，不等于功能存在 |

**未纳入 §1 的类别与规模**（诚实边界）：

| 未纳入 | 规模 | 理由 |
|---|---|---|
| IDEA-BANK 里判 ❌ 的 33 条 | 33 | 协议/平台硬缺口（CAPABILITY §5 / CONSTRAINTS:18-25），不是"没做"，是**做不了** |
| ROADMAP 18 个包里的纯视觉微创意（如 #13 周柱图、#214 噪点质感） | 约 900 条 | 它们的"落点"是同一批页面的内部表现，不构成独立功能点；本文件按**页面/能力**计数，不按创意条目计数 |
| ⚠ 类且当前无本地数据可算的（如 #45 电量趋势 sparkline、#50 年报告） | 84 条里的大部分 | 需要数月数据积累，现在只有代码骨架 |
| 纯协议字节层（32 条命令的 KLV 构造、AES、ZOTP 算法） | 约 36 个类型 | 已在 `docs/FUNCTION-MATRIX.md` 逐条对账，此处只把"有 UI 消费者的"列成功能点 |
| 测试与 fixtures（Tests/ 3 个文件、fixtures/golden.json） | — | 不是用户功能 |

**最终条目数：152 条**（下表 F-001…F-152）。按首列状态逐条数出（含"活（…）"这类带括注的）：

- **活 111**（含 4 条带"刚接上/四级深"括注）
- **半 10**（F-027 凭证工坊不可达 / F-028 OTP 工坊不可达 / F-034 版本历史有写无读页 / F-059 夜间时段不可配 / F-061 连续天数无独立页 / F-120 访客闸在单控制台失效 / F-124 救援码零调用 / F-142 主屏快捷动作未读到实现 / F-143 伪装态无开关 / F-144 试验模式无开关）
- **死 21**（含 2 条带括注）
- **缺 8**（F-016 F-063 F-135 F-136 F-137 F-139 F-140 F-141）
- **未读到 1**（F-145 演示锁）
- **引用行 1**（F-112 是 F-103 的重复入口记录，不单独计数）
- 安卓侧有对应物 **10 条**（F-001/003/005/006/007/013/014/016/095/148）

> 上述数字由脚本对本文档自身的表格逐行统计得出（E1），改表后请重算，不要照抄。

### 1.2 图的读法

- **状态**：`活` = 有真实入口且写侧通；`半` = 实现有但入口/写侧/展示缺一半；`死` = 有代码但零调用或不可达；`缺` = 应该有的能力，代码里没有。
- **触达频率**：每天 / 每周 / 每月 / 一次性 / 故障时。
- **风险等级**：改它会连累什么。高 = 动到安全闸/唯一主操作/数据写入；中 = 动到跨页共享口径；低 = 单页内观感。
- 行号标注：**无后缀** = 工作区当前行号；**`(H:)` / `HEAD x:`** = HEAD（已提交）版本行号 —— 该文件正在被并行改动时以 HEAD 为准，见 §0.2。
- 只给 `文件:行` 不给列名的地方，行号指**该符号的声明行**（不是使用行）。

### 1.3 总表

| 编号 | 域 | 功能点 | 用户价值（一句话） | iOS 实现锚点 | 安卓 | 呈现位置（现状） | 状态 | 频率 | 风险 |
|---|---|---|---|---|---|---|---|---|---|
| F-001 | 开门 | 按住 1.05s 开锁环 | 站在门口按一下就进 | `HomeConsole.swift:400/480/96`（H:）；`LockService.swift:470` | **有**（单击即开 `MainActivity.kt:573`） | 控制台首屏（唯一主角） | 活 | 每天 | **高**：全 App 唯一开锁动线 |
| F-002 | 开门 | 开锁失败翻译成人话 + 给出下一步入口 | 失败时知道该干什么，而不是看报错 | `HomeConsole.swift:881/1108`（H:） | 部分（`KfProtocol.kt:170 rcText`） | 环下方一行 | 活 | 故障时 | 中：动到错误分类会同改 4 处文案 |
| F-003 | 开门 | 开锁重入闸（连点不会发两次 BLE） | 不会因为手抖开两次门 | `HomeConsole.swift:63/833`（H:） | 有（`busy` `MainActivity.kt:119`） | 无界面（内部） | 活 | — | **高**：去掉=并发开锁 |
| F-004 | 开门 | VoiceOver 直接开锁（不必长按） | 视障用户也能开门 | `HomeConsole.swift:489`（H:） | 无 | 环的 accessibilityAction | 活 | 每天（视障） | 中 |
| F-005 | 开门 | 切后台/视图消失即放弃蓄力 | 去回微信不会真把门开了 | `HomeConsole.swift:807/172`（H:） | 有（`ON_PAUSE` `MainActivity.kt:242`） | 无界面（内部） | 活 | — | **高**：安全语义 |
| F-006 | 开门 | 页眉：时间 + 连接状态胶囊 | 一眼知道"现在能不能开" | `HomeConsole.swift:219`（H:） | 有（`Header` `MainActivity.kt:518`） | 首屏顶部 | 活 | 每天 | 低 |
| F-007 | 开门 | 空态「还没有门锁 → 去配对门锁」 | 首启只有一条路，不用找 | `HomeConsole.swift:249/191`（H:） | 有（`EmptyState` `MainActivity.kt:653`） | 首屏（无锁时整屏） | 活 | 一次性 | 低 |
| F-008 | 开门 | 关键提示条（未处理告警 / 低电 / 近 7 日到期） | 有事的那天才出现，平时不占地方 | `HomeConsole.swift:318/340`（H:）；`CredentialOrg.swift:784 expiringSoonCount` | 无 | 开锁环正上方 | 活 | 每周 | 中：三条共用一行，优先级写死 |
| F-009 | 开门 | 三指标（今日开门 / 今日成员 / 最早开门） | 今天的情况一眼看完 | `HomeConsole.swift:563`（H:） | 无 | 首屏第二簇 | 活 | 每天 | 低 |
| F-010 | 开门 | 24 小时分时柱 + 点某小时下钻记录 | 看出今天几点有人来 | `HomeConsole.swift:602/609/635`（H:） | 无 | 首屏第二簇 | 活 | 每天 | 中：整块触达面按 x 换算小时 |
| F-011 | 开门 | 成员横向胶囊 → 成员详情（一步到位） | 看到某人的名字就能点进去 | `HomeConsole.swift:675/205`（H:） | 无 | 首屏第二簇 | 活 | 每天 | 中 |
| F-012 | 开门 | 下拉刷新（显式连锁读实时状态） | 想看实时电量就拉一下 | `HomeConsole.swift:142`（H:） | 无 | 首屏 | 活 | 每周 | 中：会真建 BLE 连接 |
| F-013 | 开门 | 回前台只重算本地，不唤醒硬件 | 切回 App 不费电 | `HomeConsole.swift:149-164`（H:） | 有（`ON_RESUME`） | 无界面 | 活 | — | 中 |
| F-014 | 开门 | 靠近自动开锁（六道门链 F0–F6） | 走到门口自动开 | `AutoOpen.swift:12/303`；入口 `MePage.swift:224` | **有**（`AutoOpenKit.kt:12` + `MainActivity.kt:271`） | 我页 → 靠近自动开锁 | 活 | 每周 | **高**：任一门失效=误开 |
| F-015 | 开门 | 连接与预握手偏好（信号围栏/成功率） | 调门槛前先看见当前信号 | `LinkSenseKit.swift:650`；入口 `MePage.swift:217` | 部分（预热 `MainActivity.kt:276`） | 我页 → 开锁偏好 | 活 | 每周 | 中 |
| F-016 | 开门 | 精确查找箭头（iOS 侧） | 找不到门时能定位 | 只有**半个开关**：`FindArrowLayer.swift:33-38` 的 `FindArrowPower`（`intensive` 被 `AutoOpen.swift:362` 读；`beginIntensive`/`endIntensive` 零调用，E1 `deadscan` 报两条），**全仓无箭头 View** | **有**（`SignalArrow.kt:128` + `MainActivity.kt:357` 的 208dp 箭头 + `:811` AirTag 全屏层） | 无界面 | **缺** | 故障时 | 中：iOS 缺一整页，安卓有 |
| F-017 | 开门 | 摇一摇迷你开锁面板 | 提着重物也能开 | `LockKeeperApp.swift:140/163` 只写 `shakePanel`，**零消费者** | 无 | — | **死** | — | 中：加回要有新的浮层 |
| F-018 | 开门 | 门厅 5 个管理瓦片 → 管理面板 | 从开门切到管理只要一次 | `HomeConsole.swift:729`（H:）；`ManagerFace.swift:25`（H:） | 无 | 首屏底部 | 活 | 每周 | **高**：§3 要改的就是它 |
| F-019 | 钥匙 | 钥匙列表（密码/指纹/临时码三段） | 谁能开门，一行一权 | `KeysPage.swift:31`(结构) `/347`(rows) `/147`(segmentBar, H:) — 工作区已漂到 :159 | 无 | 管理 → 钥匙 | 活 | 每周 | 中 |
| F-020 | 钥匙 | 钥匙搜索 | 钥匙多了直接搜 | `KeysPage.swift:73`(H:) — 工作区 :81 | 无 | 钥匙页 searchable | 活 | 每周 | 低 |
| F-021 | 钥匙 | 行级长按：置顶 / 归档 / 改名字 / 改备注 / 删除 | 不用进详情也能管 | `KeysPage.swift:494`(H:) 长按菜单（+510 归档 / 524 改名 / 531 备注）— 工作区 :512 | 无 | 钥匙行 contextMenu | 活（2026-10-22 刚接上） | 每周 | 中 |
| F-022 | 钥匙 | 删除前三件事（本机删/锁端撤/回收站 N 天） | 按下之前知道有没有退路 | `KeysPage.swift:91-106`(H:) — 工作区 :99-114 | 无 | 删除确认框 | 活 | 每月 | 低 |
| F-023 | 钥匙 | 到期预警卡 | 快过期的钥匙自己浮上来 | `KeysPage.swift:116`(H:) — 工作区 :128 | 无 | 钥匙页顶部 | 活 | 每周 | 低 |
| F-024 | 钥匙 | 添加密码（逐位大号回显） | 能核对自己设的码 | `AddKeyPage.swift:25`（回显 :114） | 无 | 钥匙页 + → sheet | 活 | 每月 | 中 |
| F-025 | 钥匙 | 录指纹（8 次按压 / 归属先行） | 录的时候不用记次数 | `AddFingerPage.swift:24`；`FpOwnerPicker.swift:9`（用点 :162） | 无 | 管理 → 指纹 | 活 | 每月 | 中 |
| F-026 | 钥匙 | 临时码工作室（五场景 / 重叠检测） | 给保洁/装修发一个只今天有效的码 | `CredentialStudio.swift:510`（重叠 :531） | 无 | 管理 → 临时密码 | 活 | 每周 | 中 |
| F-027 | 钥匙 | 指纹工坊（沉浸录入 / 删除双签） | 录指纹有个像样的过程 | `CredentialStudio.swift:1054`（双签 :1003） | 无 | **StudioPage 里，而 StudioPage 不可达** | **半** | 每月 | 中：只能从死页进 |
| F-028 | 钥匙 | OTP 工坊（otpauth 导入 / 时窗细条） | 门锁之外的口令也能管 | `CredentialStudio.swift:1469`（otpauth :60） | 无 | 同上 | **半** | 每月 | 中 |
| F-029 | 钥匙 | 凭证工坊 2×2 卡 | 四类凭证一处进 | `StudioPage.swift:24` | 无 | **零真实入口**（唯一引用的 `QuickPool.swift:149` 自身是死函数） | **死** | — | 中：F-027/028 的宿主 |
| F-030 | 钥匙 | 凭证回收站 | 删错了能捞回来 | `CredentialBinView.swift:23`；入口 `SecurityCenterView.swift:999` | 无 | 安全 → 销毁 → 回收站（**藏在销毁页里**） | 活 | 每月 | 中 |
| F-031 | 钥匙 | 下发队列（待下发 → 已下发 → 锁端确认） | 断网时的改动不会丢 | `CredentialOrg.swift:478/569`；展示 `CredentialBinView.swift:51/174` | 无 | 回收站页内 | 活 | 每月 | 中 |
| F-032 | 钥匙 | 星标与高频建议 | 常用的钥匙排前面 | `CredentialOrg.swift:672/675/689`；用点 `KeysPage.swift:496` | 无 | 钥匙行长按 | 活 | 每周 | 低 |
| F-033 | 钥匙 | 批量操作（统一延期 / 批量移交 / 批量停用） | 一次改一批 | `CredentialOrg.swift:583/597/638` | 无 | — | **死**（E1 `deadscan` 三条全零引用） | — | 中 |
| F-034 | 钥匙 | 凭证版本历史 / 自动快照 | 改坏了能回到上一版 | `CredentialOrg.swift:175 snapshot/229 diff` | 无 | — | **半**（写侧有、读侧无页面） | — | 中 |
| F-035 | 钥匙 | 成员名册 | 谁在这个家 | `MembersPage.swift:30`(H:)（头像条 :49，名册 :50） | 无 | 管理 → 成员 | 活 | 每月 | 中 |
| F-036 | 钥匙 | 成员详情 360（名下钥匙 / 最近开门 / 授权来源） | 点一个人看全部 | `MemberCenterView.swift:15`（区块 :60-65） | 无 | 名册行 → push | 活 | 每月 | 中 |
| F-037 | 钥匙 | 添加成员三步向导 | 建档案不用填表 | `MemberCenterView.swift:478` | 无 | 名册右上 + | 活 | 一次性 | 低 |
| F-038 | 钥匙 | 归档成员（可恢复） | 搬走的人不占名册 | `MemberCenterView.swift:837`；入口 `MembersPage.swift:170` | 无 | 名册底部 | 活 | 每月 | 低 |
| F-039 | 钥匙 | 匿名认领（未归属钥匙认给某人） | 谁开的门能对上号 | `MemberCenterView.swift:1087`；入口 `MembersPage.swift:180` | 无 | 名册底部 | 活 | 每月 | 中 |
| F-040 | 钥匙 | 家庭设置（长辈模式 / 隐私浏览） | 给老人用 / 不给孩子看 | `MemberCenterView.swift:956`；入口 `MembersPage.swift:190` | 无 | 名册底部 | 活 | 一次性 | 中 |
| F-041 | 钥匙 | 合并重复成员 | 同一人建了两次能并 | `MemberCenterView.swift:678`；**唯一入口** `MemberCenterView.swift:86`（成员详情右上菜单） | 无 | 成员详情 → 重复合并 | 活（**三级深**） | 一次性 | **高**：合并会迁钥匙 |
| F-042 | 钥匙 | 成员退出处置向导 | 有人搬走时的标准流程 | `MemberCenterView.swift:1353`；入口 :87 | 无 | 成员详情右上菜单 | 活（三级深） | 一次性 | 中 |
| F-043 | 钥匙 | 权限矩阵 | 一眼看出谁能干什么 | `MemberHub.swift:66 permRows/80 permAllows` | 无 | 成员详情 | 活 | 每月 | 低 |
| F-044 | 钥匙 | 成员活跃度（带"约"） | 谁最近在用 | `MemberHub.swift:125 activity` | 无 | 成员详情 | 活 | 每月 | 低 |
| F-045 | 钥匙 | 成员徽章与生日 | 给成员的仪式感 | `Milestones.swift:295/303` | 无 | **入口不存在**：`MemberCenterView.swift:105-106` 文案写「设置 → 成员管理 里长按成员行」，而 `MembersPage.swift` 没有任何 contextMenu（E1 grep 空） | **死** | — | 中：文案指路指向不存在的手势 |
| F-046 | 钥匙 | 关怀提醒（家庭公告板 / 纪念日 / 生日） | 记得家里的事 | `CareRemindersView.swift:6`；入口 `MePage.swift:335` | 无 | 我页 → 关怀提醒 | 活 | 每周 | 低 |
| F-047 | 今天 | 事件记录时间线（按天分组） | 谁什么时候来过 | `EventsPage.swift:32`(H:)；入口 `MePage.swift:272` | 无 | 我页 → 事件记录 | 活 | 每周 | 中 |
| F-048 | 今天 | 事件搜索（自然语言 / 加减号 / 时间短语） | 翻旧账直接问 | `EventsPage.swift:105`；引擎 `RecordSearch.swift:529/711` | 无 | 记录页 searchable | 活 | 每周 | 中 |
| F-049 | 今天 | 筛选菜单（只看告警 / 存为筛选视图 / 清空搜索） | 常用查询一键回来 | `EventsPage.swift:147/169/175` | 无 | 记录页 toolbar | 活 | 每周 | 低 |
| F-050 | 今天 | 命名筛选视图 + 最近搜索 | 不用每次重敲条件 | `EventsPage.swift:273`；`RecordSearch.swift:796` | 无 | 记录页顶部胶囊条 | 活 | 每周 | 低 |
| F-051 | 今天 | 事件备注（只存本机） | 给一条记录留个说明 | `EventsPage.swift:208`；`RecordSearch.swift:37` | 无 | 事件落点弹窗 | 活 | 每月 | 低 |
| F-052 | 今天 | 从门锁同步日志（分页 + 剩余条数） | 主动拉一次全量 | `EventsPage.swift:357`；`LockService.swift:761` | 无 | 记录页 toolbar → 刷新 | 活 | 每周 | **高**：写日志缓存 |
| F-053 | 今天 | 统计页（安全/节律/变化三问 + 帕累托/时段/首次/趋势） | 看出家里的作息 | `StatsPage.swift:31`(H:)；七张卡在 HEAD 集中在 :44-51（`degradedCard` 44 / `safetyCard` 46 / `paretoCard` 47 / `daypartCard` 48 / `firstOpenCard` 49 / `rhythmCard` 50 / `trendCard` 51）— 工作区已重排 | 无 | 记录页 toolbar 图表图标 | 活 | 每月 | 中 |
| F-054 | 今天 | 告警页（按紧迫度排序 + 就地处置） | 有事时马上看到 | `AlarmsPage.swift:27`（分级 :185，列表 :46） | 无 | 记录页 toolbar 三角图标 | 活 | 故障时 | 中 |
| F-055 | 今天 | 动态消息流（跨锁卡片流） | 最近发生了什么 | `FeedPage.swift:21`；入口 `MePage.swift:279` | 无 | 我页 → 动态消息 | 活 | 每周 | 低 |
| F-056 | 今天 | 告警中心（跨锁流 / 四级色标 / 处置留痕 / 24h 回放） | 报警有人处置、有闭环 | `AlarmCenterView.swift:12`（回放 :22，留痕 :457） | 无 | **零真实入口**（唯一引用 `QuickPool.swift:151` 是死函数） | **死** | — | 中：`AlarmsPage` 是它的简化替代 |
| F-057 | 今天 | 节假日表（内置 + 在线可选 + 调休补班） | "周末/假期"的判断不撒谎 | `HolidayFeed.swift:15`；自动刷新 `LockKeeperApp.swift:1298` | 无 | 无界面（后台） | 活 | 每月 | 低 |
| F-058 | 今天 | 归因引擎（可证明才署名） | 说"谁开的"不出错 | `Attribution.swift`（R1/R2 头注）；用点 `HomeConsole.swift:956`（H:） | 无 | 首屏成员统计 | 活 | 每天 | **高**：署名错=甩锅 |
| F-059 | 今天 | 夜间时段与"深夜开门"判定 | 半夜开门能被认出来 | `RecordSearch.swift:413/414/422` | 无 | 记录筛选 / 统计 | **半**：`setNightFrom/setNightTo` 零调用（E1 `deadfuncs`）→ 永远 22:00–06:00 | — | 中 |
| F-060 | 今天 | 里程/成就结算与时刻卡 | 用了半年有个纪念 | `Milestones.swift:533`；`Celebration.swift:18`；`MomentLayer.swift:10` | 无 | 全局覆盖层 | 活 | 每月 | 中 |
| F-061 | 今天 | 连续天数 / 安心夜打卡 | 养成习惯 | `Milestones.swift:145/164/169` | 无 | 无独立页（只进时刻卡） | **半** | 每周 | 低 |
| F-062 | 今天 | 本地朗读出口（统一一份 TTS） | 念密码 / 念记录 | `SpeechKit.swift` —— **文件只有注释 + import，没有任何实现**（E2 全文 9 行） | 无 | — | **死** | — | 低 |
| F-063 | 今天 | 症状向导 / 帮助中心 | 出问题自己查 | **文件不存在**：`App/UI/HelpCenter.swift` 缺失（`CJKSpacing.swift:4` 提到"从被删除的 HelpCenter.swift 中独立出来"） | 无 | — | **缺** | 故障时 | 中 |
| F-064 | 今天 | 通知横幅预算（同屏只挂一条闲时提醒） | 顶部不会堆四条指路条 | `LockKeeperApp.swift:955 topBanners/243 ambientRanked`；`NoticeBudget.swift:13/42` | 无 | 全局顶部 | 活 | 每天 | 中 |
| F-065 | 今天 | 剪贴板关怀（90s 自清 / 复制后快捷条） | 密码不会一直躺在剪贴板 | `ClipboardCare.swift`（唯一出口）；条 `LockKeeperApp.swift:1212` | 无 | 全局顶部 | 活 | 每周 | 中 |
| F-066 | 今天 | 诊断与自检页（体检/健康/稳定性/运维/蓝牙/保留） | 出问题自己查 | `DiagnosticsPage.swift:18`（六个卡 :51-57）；引擎 `DiagKit.swift:161/417/459/483/503` | 无 | **两入口**：`MePage.swift:166` 与 `ManagerFace.swift:232`（H:229） | 活 | 故障时 | 中 |
| F-067 | 今天 | 页面耗时 / 导航追踪 | 知道哪页慢 | `DiagKit.swift:590 markNav/600 shown` | 无 | 诊断页 | 活 | 故障时 | 低 |
| F-068 | 今天 | 异常退出档案 | 崩过一次能查到 | `DiagKit.swift:351 checkAbnormalExit`；接线 `LockKeeperApp.swift:1014` | 无 | 诊断页 | 活 | 故障时 | 低 |
| F-069 | 今天 | 日志保留期与归档 | 日志不无限涨 | `DiagKit.swift:189/503 archiveOldLogs` | 无 | 诊断页 | 活 | 每月 | 低 |
| F-070 | 这把锁 | 设备管理（排序 / 隐藏 / 设为当前 / 解绑 / 分享安卓） | 多把锁也能理清 | `LocksPage.swift:30`（排序 :61，工具栏 :123，滑动 :220，分享 :237，解绑 :250+） | 无 | **两入口**：`ManagerFace.swift:206` 与 `MePage.swift:196` | 活 | 每月 | **高**：解绑会删密钥 |
| F-071 | 这把锁 | 配对向导（发现 → 校验 → 初始化 → 命名） | 新锁四步加上 | `AddLockPage.swift:23`（脊梁 :52） | 部分（扫码 `LockStore.kt:72`） | 门厅空态 / 设备管理 + | 活 | 一次性 | **高**：写钥匙串 |
| F-072 | 这把锁 | 锁档案（昵称 / 符号 / 色标 / 场所） | 一眼认出是哪把锁 | `LockProfilePage.swift:22`（锁牌 :46）；入口 `MePage.swift:204` | 无 | 我页 → 锁档案 | 活 | 一次性 | 中 |
| F-073 | 这把锁 | 这台锁（身份 / 待办 / 容量 / 读数 / 明细 / 最近） | 一把锁的全部状态一页看完 | `DevicePage.swift:30`(H:)（七个区块 :41-53）；入口 `MePage.swift:189` | 无 | 我页 → 这台锁 | 活 | 每周 | 中 |
| F-074 | 这把锁 | 固件升级（体检三勾 / 三段进度 / 批量队列 / 历史） | 刷固件不心慌 | `FirmwarePage.swift:23`（卡 :84-90，升级 :534，DFU :551/591）；引擎 `DFUKit.swift:595/637/672` | 无 | **两入口**：`ManagerFace.swift:207` 与 `MePage.swift:322` | 活 | 每月 | **高**：刷坏=砖 |
| F-075 | 这把锁 | 网关配网（两步阶梯 / 网关卡） | 远程/联网能力 | `GatewayPage.swift:21`（步骤 :40-43）；入口 `ManagerFace.swift:208` / `MePage.swift:348` | 无 | 两入口 | 活 | 一次性 | 高 |
| F-076 | 这把锁 | 蓝牙钥匙串（硬件名片 / 读状态 / 写钥匙） | 带一个钥匙串出门 | `DonglesPage.swift:22`（卡 :35-45，查钥匙 :160） | 无 | 两入口 | 活 | 每月 | 高 |
| F-077 | 这把锁 | 校准门锁时间（偏差 + 回读校验） | 临时码能不能用全靠它 | `DeviceHomeView.swift:9 SyncTimeView`；`LockService.swift:499` | 无 | **三入口**：`ManagerFace.swift:213` / `MePage.swift:211` / `CareViews.swift:423` | 活 | 每周 | **高**：时间错=临时码全废 |
| F-078 | 这把锁 | 安全模式（单验→双验 cmd20 + 锁端开关实况 + 静音 cmd18） | 把锁调严 | `SettingsView.swift:12`（实况卡 :114，静音 :134/172，双验 :196） | 无 | `ManagerFace.swift:224` / `MePage.swift:233` | 活 | 一次性 | **高**：改锁端验证策略 |
| F-079 | 这把锁 | 布防（cmd 25） | 布防时段自动开锁被否决 | 服务层有 `LockService.swift:487`；**零调用** | 无 | — | **死** | — | 高 |
| F-080 | 这把锁 | 自动上锁档位（cmd 24） | 关门几秒后自动落锁 | `LockService.swift:535`；**零调用** | 无 | — | **死** | — | 高 |
| F-081 | 这把锁 | 临时码总开关（cmd 19） | 一键停用临时码 | `LockService.swift:539`；**零调用**（`SettingsView.swift:131-133` 注释解释为何不接） | 无 | — | **死** | — | 高 |
| F-082 | 这把锁 | 清空全部密码（cmd 0A delAlias=FFFF） | 换住户时的重手段 | `LockService.swift:605`；**零调用** | 无 | — | **死** | — | **高**：不可逆 |
| F-083 | 这把锁 | 回声探测（cmd 12 连通性） | 判断"是不是锁没响应" | `LockService.swift:440`；**零调用** | 无 | — | **死** | — | 低 |
| F-084 | 这把锁 | 容量水位（PIN/密码/指纹各剩多少） | 快满了提前知道 | `DevicePage.swift:243 capacityCard`；`StatusParser.swift:51` | 无 | 这台锁 | 活 | 每月 | 低 |
| F-085 | 这把锁 | 电量采样与五档显示（无电压/无健康度） | 知道什么时候该换电池 | `BatteryCare.swift:79/141/164` | 无 | 门厅 footnote / 这台锁 | 活 | 每周 | 中 |
| F-086 | 这把锁 | 保养清单与周期（90 天 / 年度换电） | 不用记什么时候该保养 | `CarePage.swift:27`（周期 :39，待办 :40，历史 :41）；`CareViews.swift:470 CareChecklistView` | 无 | `MePage.swift:329` | 活 | 每月 | 低 |
| F-087 | 这把锁 | 换电图文指引 + 「已换新」复位基线 | 换电池有步骤、换完有记录 | `CareViews.swift:313`（步骤 :299）；`BatteryCare.swift:233 recordBatterySwap` | 无 | **两入口**：`CareViews.swift:226` 与 `AlarmCenterView.swift:639`（后者在死页里） | 活 | 每月 | 中 |
| F-088 | 这把锁 | 保养历史 | 上次保养是什么时候 | `CareViews.swift:173 / BatteryCare.swift:250` | 无 | 维护与保养页 | 活 | 每月 | 低 |
| F-089 | 这把锁 | 关怀提醒（低电阈值 / 夜间免扰 / 仅白天送达 / 固件复提醒） | 半夜不被通知吵醒 | `BatteryCare.swift:344/346/351/353/360` | 无 | **无设置页**（原 SettingsView 已被 `SafemodeIntroView` 顶替） | **死** | — | 中：`keydead` 报 `kf_quiet_night` 只读不写 |
| F-090 | 这把锁 | 固件版本历史 / 固件库 / DFU 历史 | 刷过什么版本查得到 | `FirmwareHistory.swift:11`；`BatteryCare.swift:315/324` | 无 | 固件页 | 活 | 每月 | 低 |
| F-091 | 这把锁 | 多锁总览与对比（活跃度榜 / 告警率 / 成员×锁 / 固件对照） | 多把锁一眼比 | `LockOverviewView.swift` —— **文件只剩 6 行注释 + import，没有类型**（E2 全文） | 无 | — | **死** | — | 中 |
| F-092 | 这把锁 | 电量总览条带（每锁一格） | 哪把快没电一眼看 | `DeviceStripCard.swift` —— **13 行，只有注释 + import** | 无 | — | **死** | — | 中 |
| F-093 | 这把锁 | 型号识别与能力开关（哪些 pid 能布防/能升级） | 不对不支持的锁发命令 | `PidMap.swift:5-56` | 无 | 无界面（内部） | 活 | — | 高 |
| F-094 | 这把锁 | 锁端安全级别三开关实况（单双验/广播/临时码） | 看见锁现在是什么策略 | `SettingsView.swift:114-124`；`StatusParser.swift:70-74` | 无 | 安全模式页 | 活 | 每月 | 中 |
| F-095 | 这把锁 | 分享给安卓（二维码只带 mac/pid/ekey，不带 skey） | 换机不用重新配网 | `ShareToAndroidView.swift:8`；载荷 `AndroidPair.swift:24`；入口 `LocksPage.swift:237` | **有**（扫码 `MainActivity.kt:202`） | 设备管理行 → 分享给安卓 | 活 | 一次性 | **高**：码里是开锁凭证 |
| F-096 | 数据 | 备份页（状态卡 / 导出 / 导入 / 工作室入口） | 知道上次备份是什么时候 | `BackupPage.swift:28`（卡 :58-61） | 无 | **两入口**：`ManagerFace.swift:225` 与 `MePage.swift:249` | 活 | 每月 | **高**：导入=整表覆盖 |
| F-097 | 数据 | 备份工作室（五块：导出/恢复/WebDAV/换机/信任感） | 高级动作有专门的地方 | `BackupStudio.swift:10`（动作 :125，自检 :74） | 无 | 备份页 → 工作室（sheet） | 活 | 每月 | 高 |
| F-098 | 数据 | 导出向导四步（分区勾选 + 口令两遍 + 体检 + 完成分享） | 导出一份带口令的包 | `BackupStudio.swift:458`（步骤注释 :530/580/621/667） | 无 | 工作室 → 导出向导 | 活 | 每月 | 高 |
| F-099 | 数据 | 恢复向导（预演 / 三策略 / 冲突裁决 / 差异报告） | 恢复之前先看清会覆盖什么 | `BackupStudio.swift:918`（预演 :964，策略 :1017） | 无 | 工作室 → 恢复向导 | 活 | 一次性 | **高**：覆盖不可撤销 |
| F-100 | 数据 | 本地备份文件管理（列出 / 哈希 / 短码） | 本机有哪些备份 | `BackupStudio.swift:323 LocalBackupFilesSection` | 无 | 工作室 | 活 | 每月 | 中 |
| F-101 | 数据 | WebDAV 同步（自配端点 / 远端列表 / 滚动保留） | 两台机不见面也能换机 | `BackupStudio.swift:287`（Channel :975） | 无 | 工作室 | 活 | 一次性 | 高 |
| F-102 | 数据 | 换机迁移（三通道 / 中断续迁 / 旧机退役） | 换手机不丢数据 | `BackupStudio.swift:975 Channel`；`BackupStudioKit.swift:977 MigSession/1018` | 无 | 工作室 | 活 | 一次性 | 高 |
| F-103 | 数据 | 导出中心（范围 / 列选择 / 三组动作） | 要一份能发出去的材料 | `ExportCenter.swift:1475`（范围 :1546，动作 :1558，失败 :1684） | 无 | **两入口**：`ManagerFace.swift:223` 与 `MePage.swift:257` | 活 | 每月 | 中 |
| F-104 | 数据 | CSV 导出（BOM + 双语列头 + 预检 + 校验行） | 给 Excel 也能打开 | `ExportCenter.swift:493` | 无 | 导出中心 | 活 | 每月 | 中 |
| F-105 | 数据 | PDF 月度报告（矢量封面/图表/告警章置前） | 打印或存档用 | `ExportCenter.swift:614` | 无 | 导出中心 | 活 | 每月 | 中 |
| F-106 | 数据 | 分享卡（告警卡 / 单条记录卡） | 发给家人看 | `ExportCenter.swift:1414/1446`；入口 `ExportCenter.swift:916/925` | 无 | 导出中心 | 活 | 每月 | 低 |
| F-107 | 数据 | 打印（AirPrint） | 贴在门上的一页纸 | `ExportCenter.swift:1163` | 无 | 导出中心 | 活 | 每月 | 低 |
| F-108 | 数据 | 报告校验二维码（出码 + 扫码核对指纹） | 证明这份报告没被改 | `ExportCenter.swift:1213`；相机侧 `ReportVerifyView.swift:21` | 无 | 导出中心 | 活 | 一次性 | 中 |
| F-109 | 数据 | 备份自检黄条（库体哈希对不上就提示） | 数据坏了第一时间知道 | `BackupStudioKit.swift:1089 selfCheckWarning`；接线 `LockKeeperApp.swift:965` | 无 | 全局顶部 | 活 | 故障时 | 中 |
| F-110 | 数据 | 通知分派器（点通知能落到对的地方） | 通知不是死的 | `BackupStudioKit.swift:1358 UNDelegate` | 无 | 系统通知 | 活 | 每月 | 中 |
| F-111 | 数据 | 备份与恢复（旧页） | — | `BackupView.swift:7` | 无 | **零真实入口**（唯一引用 `QuickPool.swift:150` 是死函数） | **死** | — | 低：被 BackupPage 取代 |
| F-112 | 数据 | 旧导出中心入口（`ManagerFace` 与 `MePage` 双份） | — | 同 F-103 | — | — | 见 F-103 | — | — |
| F-113 | 安全 | 本机保护页（安全状态卡 + 三盏灯 + 四个动作） | 先回答"现在安全吗" | `SecurityPage.swift:28`（状态卡 :60，动作 :247） | 无 | `MePage.swift:147`（HEAD 版 :145 与 :154 两条同指它；工作区已修其中一条，见 §2-G1） | 活 | 每周 | 中 |
| F-114 | 安全 | 应用锁（设置/修改/关闭） | 借手机给别人时挡住 | `AppLockSetupView.swift:25`；入口 `SecurityPage.swift:254` | 无 | 本机保护 → 应用锁 | 活 | 一次性 | **高**：口令丢失=进不去 |
| F-115 | 安全 | 防窥与遮蔽（切后台即糊 / 限时可见 / 分享遮半 / 磨砂挡片） | 旁边有人也不怕 | `SecurityCenterView.swift:154`；入口 `SecurityPage.swift:260` | 无 | 本机保护 → 防窥 | 活 | 每月 | 中 |
| F-116 | 安全 | 隐私仪表盘（逐项状态，点行切换） | 一眼看清防窥开了几项 | `SecurityCenterView.swift:1390`；入口 `SecurityCenterView.swift:216` | 无 | 防窥页 → 隐私总览 | 活（**四级深**） | 每月 | 中 |
| F-117 | 安全 | 审计日志（双流水 + 防篡改哈希链） | 谁动过什么查得到 | `SecurityCenterView.swift:471`；链 `AuditChain.swift:132 verifyChain` | 无 | 本机保护 → 审计 | 活 | 故障时 | 中 |
| F-118 | 安全 | 彻底销毁（三级确认 + 覆写 + 残留检查） | 卖手机前清干净 | `SecurityCenterView.swift:881`；`AuditChain.swift:311 destroyAll/348 checkResidue` | 无 | 本机保护 → 销毁 | 活 | 一次性 | **高**：不可逆 |
| F-119 | 安全 | 销毁前备份闸 | 别把唯一一份数据删了 | `AuditChain.swift:462 backupGatePass`；UI `SecurityCenterView.swift:1271` | 无 | 销毁页 | 活 | 一次性 | **高** |
| F-120 | 安全 | 访客通道（受限区要复核才放行） | 别人拿手机看不到钥匙 | `LockGuard.swift:125 guestActive`；闸 `LockKeeperApp.swift:118-125 requestRoute`；判据 `Route.swift:47` | 无 | 防窥页里的开关（`SecurityCenterView.swift:262`） | **半** | — | **高**：闸判的是 `tabIndex`（`guestBlockedTabs` 由 `Route.guestBlockedTabs` 派生，`LockKeeperApp.swift:80`），而单控制台里**换页已不走 tab**：门厅 5 个瓦片直接 `managerGroup = g`（`HomeConsole.swift:976-979 openGroup`）、noticeRow 直接置组（`:384`）、成员胶囊直接开 sheet（`:205`）—— 这些都不经过 `requestRoute`，**访客闸在这四条路上不生效**。这正是 `Route.swift:12-15` 头注自己警告过的那件事（『两处同时失去指称对象 ⇒ 访客模式静默失去…不崩、不报错』） |
| F-121 | 安全 | 常驻水印（截图带溯源码） | 截图外传能追 | `SecurityCenterView.swift:120`；挂载 `LockKeeperApp.swift:1082` | 无 | 全局覆盖层 | 活 | 每月 | 低 |
| F-122 | 安全 | 录屏遮罩 / 截图警示 | 录屏时看不到明文 | `ScreenCare.swift` | 无 | 全局 | 活 | — | 中 |
| F-123 | 安全 | 只读安全模式（命令级 fail-closed） | 借人时连写命令都发不出去 | `LockGuard.swift:81/122/137`；表 `LockCommand.swift:115 requireAllowed` | 无 | 安全页 | 活 | 每月 | **高**：误开=什么都改不了 |
| F-124 | 安全 | 应用锁冷却 / 失败留痕 / 救援码 | 被猜到密码也不至于无解 | `LockGuard.swift`；`AuditChain.swift:45 rescueCode` | 无 | 应用锁页 | **半**（救援码零调用，E1 `deadscan`） | — | 高 |
| F-125 | 安全 | 毁灭操作 sudo 口令 | 最重的动作再验一次 | `SecurityCenterView.swift:646` | 无 | 销毁页 | 活 | 一次性 | **高** |
| F-126 | 安全 | 命令安全分类表（29 条 cmd → 动作族） | 新命令忘了登记就发不出去 | `LockCommand.swift` 全文；闸 `LockService.swift:226`、`HardwareService.swift:132`、`DFUKit.swift:643/677` | 无 | 无界面（内部） | 活 | — | **高**：安全主脉 |
| F-127 | 外观 | 外观工作室（明暗四档 / 七套强调色 / 高对比 / 周起始日） | 换成自己喜欢的样子 | `AppearancePage.swift:18`（三卡 :49-51）；入口 `ManagerFace.swift:231`（H:228） | 部分（深浅双模 `KfTheme.kt:22`） | 管理 → 数据与外观 | 活 | 一次性 | 中 |
| F-128 | 外观 | App 图标（9 款备选） | 主屏认得出来 | `IconPicker.swift:13`；入口 `MePage.swift:318` | 无 | 我页 → App 图标 | 活 | 一次性 | 低 |
| F-129 | 外观 | 密度 / 圆角 / 行高 / 动效档 | 字大一点、行松一点 | 键在 `LockKeeperApp.swift:690-706` **只有写，没有读**（E1 `keydead`：`kf_density/kf_radius/kf_row_h/kf_tl_gap/kf_motion` 全在"只写不读"） | 无 | **无界面** | **死** | — | 中 |
| F-130 | 外观 | 时间制式（12/24、要不要秒、第二行） | 按自己习惯读时间 | `TimeFormat.swift:22/25/31` 只读不写；`keydead` 报三键"只读不写" ⇒ 恒默认 | 无 | **无界面** | **死** | — | 低 |
| F-131 | 外观 | 系统无障碍旗标（增强对比 / 反转 / 加粗 / 减动效 / 降透明） | 跟着系统设置走 | `AccessibilityKit.swift:16 AXFlags`（五旗标 :22-39） | 部分 | 全局 | 活 | — | 中 |
| F-132 | 外观 | App 内无障碍开关（字号五档 / 灰度 / 大字预览 / 防连点 / 单手下沉） | 在 App 里调 | `AccessibilityKit.swift:99 AXPrefs` —— **2026-10-20 面板已删，全部冻结默认**（:100-103） | 无 | **无界面** | **死** | — | 中：`kf_font_scale` 有读无写入口 |
| F-133 | 外观 | 中西文间距 | 中文里夹英文不难看 | `CJKSpacing.swift` | 无 | 全局排版 | 活 | — | 低 |
| F-134 | 外观 | 窗口防熄屏 | 看指引时不黑屏 | `ScreenCare.swift:85 keepingScreenAwake` | 无 | — | **死**（E1 `deadscan` 零引用） | — | 低 |
| F-135 | 外观 | 设置页内搜索 | 找一个开关不用翻整页 | **不存在**；`SettingsGroups.swift:1-15` 的方案（五组筛选片）零调用（E1 `deadscan`） | 无 | — | **缺** | 每周 | 中 |
| F-136 | 外观 | 帮助 / 关于 / 致谢 / 版本号 | 知道这是什么 App、找作者 | **不存在**（`HelpCenter.swift` 已删；全仓 0 处读 `CFBundleShortVersionString`） | 无 | — | **缺** | 一次性 | 中 |
| F-137 | 外观 | 更新说明（"新变化"时间线） | 知道这版改了什么 | **不存在**（`App/UI/ChangelogView.swift` 缺失；E1 `changelogcheck` 原话"本闸门无事可做"） | 无 | — | **缺** | 每月 | 低 |
| F-138 | 系统 | 深链 `kf://`（白名单 host → 路由） | 快捷指令/通知能直达某页 | 注册 `project.yml:50-53`；表 `Route.swift:61`／`LockKeeperApp.swift:106`；**但全仓无 `onOpenURL`、无 `handleURL`**（E1 grep） | 无 | — | **死** | — | 中：URL 进来没人接 |
| F-139 | 系统 | App Intents / 快捷指令 / Siri | 用嘴开锁 | `App/Intents/` **目录不存在**；`SpeechKit.swift:3` 与 `SecurityCenterView.swift:765` 仍在引用它 | 无 | — | **缺** | — | 中：文档仍称已落地 |
| F-140 | 系统 | 桌面小组件 | 主屏一眼看状态 | `project.yml` **无 widget target**（E1 grep 只有 `NSSupportsLiveActivities`）；`README:257` 仍写"含 927 的 OfflineLockWidget 扩展 target" | 无 | — | **缺** | — | 低 |
| F-141 | 系统 | 实时活动（灵动岛/锁屏） | 开锁过程在岛上 | `project.yml:78 NSSupportsLiveActivities: true`，但**无任何 ActivityKit 代码** | 无 | — | **缺** | — | 低 |
| F-142 | 系统 | 主屏长按快速操作 | 长按图标直接开锁 | `LockKeeperApp.swift:10` 注释提到 `UIApplicationDelegate.performActionFor`；**未读到实现** | 无 | — | **半/未读到** | — | 低 |
| F-143 | 系统 | 伪装态（decoyMode） | 被逼开门时给个空壳 | `LockKeeperApp.swift:69` 及 9 处守卫 | 无 | 无界面开关 | **半** | — | 中 |
| F-144 | 系统 | 只读试验模式（`kf_trial_guard`） | 借人试玩不写锁 | `LockService.swift:218/642`（判断处） | 无 | 无界面开关 | **半** | — | 中 |
| F-145 | 系统 | 演示锁 / 示例数据 | 没锁也能看界面 | 引用散在 `PidMap.swift:54` 注释等；**未读到 DemoKit 实现** | 无 | — | **未读到** | — | 低 |
| F-146 | 系统 | 全局 Toast / 写入回执 | 动作有反馈 | `LockKeeperApp.swift:1346 ToastView` / `:1261 writeReceiptView` | 部分 | 全局 | 活 | 每天 | 低 |
| F-147 | 系统 | 防连点（300ms 闸） | 手抖不会连开两次 | `LockKeeperApp.swift:1383 PressableButtonStyle` | 无 | 全局按钮 | 活 | 每天 | 中 |
| F-148 | 系统 | 按压反馈样式 | 按下去有回应 | `HomeConsole.swift:1121`（H:1061）`PressableScaleStyle`；`LockKeeperApp.swift:1368 PressFeedback` | 有（`Modifier.scale`） | 全局 | 活 | 每天 | 低 |
| F-149 | 系统 | 设计令牌层（色/间距/圆角/触达/字阶/动效/触感） | 全 App 一个样子 | `Theme.swift:32/119/138/146/245/336`（H:）；组件 `Components.swift:63/395/152/221/337/183`（H:） | 部分（`Tokens.kt:16`，且注释所称"与 iOS 逐字相同"不成立，见 §4） | 全局 | 活 | — | **高**：改一处连累全仓 |
| F-150 | 系统 | 玻璃/无障碍降级通道（axGlass 三档） | 开了"降低透明度"也不崩 | `AccessibilityKit.swift:269 axGlass` + 400 附近三入口 | 无 | 全局浮层 | 活 | — | 中 |
| F-151 | 系统 | 导航到达性（destmap/reach 两条尺子） | 保证没有打不开的页 | `tools/destmap.js`、`tools/reach.js`；产出 `Destination.swift:8-28`（19 条） | 无 | CI 闸门 | 活 | — | 中 |
| F-152 | 系统 | 设置五组分区方案（`SettingsGroup`） | 一屏只给你看相关的那几节 | `SettingsGroups.swift:18` + `:49` | 无 | **零调用**（E1 `deadscan` 列 `settingsSectionShown` 零引用） | **死** | — | 低：但它是本文件 §3 的**口径来源** |

### 1.4 交叉验证的读数（`node tools/featuremap.js`，E1）

它给的六个 A 档与我对账后的用法：

| 分档 | 条数 | 工具的含义 | 我在 §1 里怎么处理 |
|---|---|---|---|
| A1 标题词撞上 | 37 | 疑似"做时没写编号" | **只当补漏线索**：如 #34 凭证卡 3D 厚度 → 我核到 `KeysPage.swift:200` 只是注释 |
| A0-x 已划掉/已合并 | 25 | 不要重做 | 未纳入 |
| A0-w 在等条件 | 5 | 条件不在本机（等拍板/等编译/等真机） | 未纳入，标"不属本轮" |
| A0-d 台账说已落 | 110 | 标注形式没被抓到 | 抽样复核：**多为真已实现**（如 #809 引导、#845 样例） |
| A0-t 真施工面 | 66 | 判 MISS 且没写下落 | **只当候选**：抽 10 条读代码，6 条其实已在别处实现（如 #806 分流卡在 `KeysPage.swift:292 emptyCard`） |
| A0-u 台账没记过 | 2 | 只能人读（#27 设置页内搜索 / #29 上下文工具栏） | #27 判**缺**（F-135）；#29 见 `KeysPage.swift:494` 长按菜单，判**活** |

**必须写清的一句**：A 档 245 条里，"实现证据"只有 730/1050（工具末行）。剩下 320 条**不是未实现**，而是"没写编号/没写下落/在等条件/已合并"四种的混合。
本文件的 152 条是按**代码可读到的能力**数的，与 1050 条创意不是同一把尺子，两个数不可相减。


---

## §2 现有分组的问题诊断（用户说的「现有的可能不合理」）

### 2.0 先把「现在的分组」画出来（**四条**并行路径 + 一批悬空页）

```
RootView (LockKeeperApp.swift:941)
└─ HomeConsole (唯一主界面, 1 个 NavigationStack)
   ├─ [路径 A] 5 个瓦片 → sheet(ManagerFace) → navigationDestination(push)
   │            21 个 ManagerRoute / 落到 20 个不同页面 (mergeMembers 也落 MembersPage)
   │            ManagerGroup: 钥匙 / 设备 / 成员 / 安全 / 数据与外观
   ├─ [路径 B] 瓦片「数据与外观」→ 本机设置(MePage) → 20 个内联 NavigationLink
   │            MePage 四段: 本机保护 / 这台锁 / 数据 / 关于与偏好
   ├─ [路径 C] SecurityPage 的 actionRow 泛型 NavigationLink → 4 条
   │            应用锁 / 防窥 / 审计 / 销毁  (SecurityPage.swift:256/262/267/272，定义在 :279)
   └─ [路径 D] 首屏直接 sheet：AddLockPage / EventsPage(×2) / MemberDetail360View
```

```
另有两套已写但接不上的顶层分组方案：
   · SettingsGroup 五组（SettingsGroups.swift:18）—— 零调用
   · Route 四 Tab（Route.swift:24）—— 只剩 tabSelection 的序号映射在用
```

> **与 teammate `ios-inventory` 的核对**：它把路径 C 单列（E3：`docs/GLASS/INVENTORY-IOS.md` 勘误 3 的 A/B/C 三通道表），我第一版只画了 A/B 两条 + D。**它的更完整，我采纳**；顺带它指出的「应用锁从管理面板永远开不了」是真的（`ManagerRoute` 无应用锁 case，只有 `SecurityPage.swift:256` 那条）。
> 两条产出的数量对得上：A 通道 21 route / 20 页（它数 21，我数 21，都注明 `mergeMembers` 落同一页）；B 通道 20 条（一致）。
**结论先行**：现在的"分组"其实**同时存在四套口径**——
① ManagerGroup 5 组（21 条路由，组内可见 20）② MePage 4 组（20 条链接）③ SettingsGroup 5 组（0 调用）④ Route 4 Tab（已被压平成 5 组）。
它们之间没有单一事实来源，也没有任何一处能回答"某个功能到底在哪个组"。

### 2.1 诊断表（G1–G20）

| 编号 | 问题类型 | 证据（双侧） | 用户会怎么踩到 | 影响面 |
|---|---|---|---|---|
| **G1** | **重复入口且行为不一致** | **HEAD 版**：`MePage.swift:145` 与 `:154` 两个相邻的 NavigationLink **都指向 `SecurityPage()`**，一个叫「本机数据保护·应用锁/审计/销毁」，一个叫「隐私与伪装·偷窥模式/伪装/访客」（E1 `git show HEAD:App/UI/MePage.swift`）。**本条在我写作期间被并行改动修掉了**：工作区 `MePage.swift:161` 已改指 `SecurityPeekView()`，并留了注释说明原委（`:156-160`） | 修之前：点「隐私与伪装」进去看到的是同一页「本机保护」，页内没有防窥入口（防窥在 `SecurityPage.swift:260` 的下一层）。修之后两条各到各页，但**它们仍是两个平行的入口体系**（一个在 MePage、一个在 ManagerFace 的「安全」组，G11） | 这条不是「已解决」，而是**证明了 D3 的推翻条件真的会发生**：两个入口指向同一页这种事，只要有两套并行入口就会复发 |
| **G2** | **路由扇出到同一页** | 工作区 `ManagerFace.swift:214` `case .members: MembersPage()` 与 `:219` `case .mergeMembers: MembersPage()`（HEAD 版分别 :211 / :216） | 「合并成员」点开 = 成员名册，得自己再找到那个人点进去 → 右上菜单 → 重复合并（**实际要 4 步**） | 1 条路由形同虚设；原注释已承认『路由层拿不到 Member』。**写作期间已被修（E1 现场）**：菜单名改成「成员列表 / 合并从这里选人发起」（工作区 `ManagerFace.swift:143`），文案不再承诺一个不存在的落点 —— 但**结构没变**（仍是 `case .mergeMembers: MembersPage()`，`:252`），本方案 §3.3-A 仍建议**删掉这一行**，让「合并」只从成员详情进 |
| **G3** | **菜单名 ≠ 页面内容** | 现在已修：`ManagerFace.swift:231`（H:228）指向 `AppearancePage`，注释 :228-230 留着前科——"原来指向 StudioPage，而 StudioPage 是钥匙工坊" | 历史前科本身说明这套路由**没有类型约束**，任何 case 都能指向任何页面 | 整个 ManagerRoute 枚举 20 条都没有编译期保证 |
| **G4** | **同一功能三入口**（SyncTime） | `ManagerFace.swift:213` / `MePage.swift:211` / `CareViews.swift:423`（E1 destmap 报 2 处 + 我另找到 CareViews 1 处 = 3 处） | 三条路都到同一页，但**用户不知道哪条是"官方"的**；`QuickPool.swift:147` 还有第 4 条（在死函数里） | 校时错了临时码全废（F-077），入口越多越难说"去某处校时" |
| **G5** | **同一功能两入口**（**9 个页面**，E1 正则复核） | ManagerFace 与 MePage 重复的页（HEAD 行号）：`LocksPage`(`MF:206`/`Me:196`)、`FirmwarePage`(`MF:207`/`Me:322`)、`GatewayPage`(`MF:208`/`Me:348`)、`DonglesPage`(`MF:209`/`Me:342`)、`SyncTimeView`(`MF:213`/`Me:211`)、`SafemodeIntroView`(`MF:224`/`Me:233`)、`BackupPage`(`MF:225`/`Me:249`)、`ExportCenterView`(`MF:226`/`Me:257`)、`DiagnosticsPage`(`MF:229`/`Me:166`) | 同一个页面在两处，用户会怀疑『这两个是不是不一样』 | 9 页 × 2 入口 = 18 个触点；`docs/redesign/DESIGN-DECISIONS.md:27-29` 的 D3 写『**不改**』 |
| **G6** | **层级错位**（危险操作在叶子层） | 回收站藏在「销毁」页底部：`MePage.swift:145` → `SecurityPage.swift:270`「彻底销毁」→ `SecurityCenterView.swift:881 SecurityDestroyView` → `:993-999` 的「回收站」面板 | 想**找回**误删的钥匙，路径是：管理面板 → 安全组 → 销毁数据 → **滚到页面最底** → 回收站（3 次点击 + 必须滚到底，而入口叫「销毁数据」）。另一条路：门厅 → 管理 → 数据与外观 → 本机设置 → 本机数据保护 → 彻底销毁 → 滚到底（5 次点击） | 唯一能挽回误删的地方，挂在语义相反的名字下面。**写作期间已被修一半（E1 现场）**：`KeysPage` 删除确认框现在把整条路指全 —— 「管理 → 安全 → 销毁数据 → 回收站」（工作区 `KeysPage.swift:114-117`）。**入口本身没动**，本方案 §3.3-C 仍建议把它升到域④页级 |
| **G7** | **层级错位**（低频深、高频更深） | 成员详情在 `MembersPage.swift:92/142`（2 层），但"合并/退出处置"在 `MemberCenterView.swift:86/87`（4 层）；而首屏成员胶囊直达详情（1 层，`HomeConsole.swift:209`） | 同一张"成员详情"页有两条深度不同的路径，用户找不到第二次 | 合并成员是**不可逆**操作，却藏在最深的地方 |
| **G8** | **无入口 / 极深路径**（destmap「入口数=1」清单逐条核） | E1 `destmap` 报 13 条只有 1 个入口。逐条核：其中 **6 条只在 MePage**（AutoCal / CareReminders / ExportCenter / LinkPrefs / SafemodeIntro / EventsPage 之外的 5 条）、**4 条在某个叶子页里**（CredentialBin 在销毁页、Maintenance 在 CarePage、ExportWizard/RestoreWizard 在工作室、ShareToAndroid 在 LocksPage 行菜单） | 想用「靠近自动开锁」只能从"我页"进；而它对应的开关是**每天都会用**的能力 | 13 条单入口页里，有 5 条其实应该是高频 |
| **G9** | **死入口 / 整页够不着** | ① `StudioPage` 只有 `QuickPool.swift:149` 引用，而 `quickDestination` 本身零调用（E1 `deadscan`）= 整条"钥匙工坊"不可达，连带 F-027 FpStudio / F-028 OtpStudio 也不可达；② `AlarmCenterView`（898 行）同上，只被 `QuickPool.swift:151` 引用；③ `BackupView` 同上（`QuickPool.swift:150`）；④ `LockOverviewView`／`DeviceStripCard`／`DevModules`／`SpeechKit` 四个文件**只剩注释 + import，没有一个类型** | 四类功能**写完了但用户永远看不到**：钥匙工坊、告警中心（含 24h 回放）、旧备份页、多锁总览 | 898 + 252 + 272 行界面对用户等于 0；`reach.js` 因为按"名字提及"建边而把它们判成"可达"（E2 `tools/reach.js:89-94` 自述"宁可高估可达"），所以**闸门看不见这个洞** |
| **G10** | **死入口 / 枚举里有、界面没有** | `ManagerRoute` 有 **21** 个 case（E1 逐 case 数），`groupContent` 五组只列出 **20** 行（3+5+4+4+4=20，E1 正则统计）。差的那一条是 **`diagnostics`** —— 它只能由 `consumePendingFocus()` 的 `"diag"` 落点带进来（`ManagerFace.swift:196-199`），**在管理面板里没有任何一行能主动点到它** | 想主动找"诊断与自检"：管理面板里没有这一行，只能从**我页**进（`MePage.swift:166`），或从自检黄条（`LockKeeperApp.swift:1199`）被动进来 | 一个 426 行的页面只有一个主动入口，且不在它本该属于的"安全"组里 |
| **G11** | **设置项被拆成两套** | 外观：`AppearancePage` 在 ManagerFace（`MF:231`），`IconPicker` 在 MePage（`Me:318`）—— 两个都是"外观"；安全：`PrivacyDashboard` 在 ManagerFace（`MF:221`），`SecurityPage`/`AppLockSetupView`/`SecurityPeekView` 在 MePage（`Me:145`） | 用户问"我在哪换图标/开应用锁"，答案是**两个不同的地方** | 设计系统里"外观"和"安全"各自被劈成两半 |
| **G12** | **空有实现但零调用**（E1 `deadscan` 146 条里挑与本主题相关的） | `QuickPool` 全族（`all/selected/ordered/recordTap/clearCounts/repeatTarget/quickDestination` 七项，全部零调用）⇒ 905 快捷格十选六 + 1047 常用排前 + 921 再开一次 **三项功能整块不存在**；`settingsSectionShown`（`SettingsGroups.swift:49`）零调用 ⇒ 五组筛选片方案作废；`CustomizedAppearance` 五键只写不读（`keydead`） | 无入口可踩，但"文档说有的功能"会误导后续改造 | 三个已立项的功能实际为 0；一个已写好的分组方案闲置 |
| **G13** | **两端命名分叉** | iOS「钥匙」（`Route.swift:52-56`、`DESIGN-DECISIONS.md:64-68` 的 D8 明令统一为"钥匙"）vs 安卓「离线锁钥匙」+「门锁设置」vs 文档「凭证」vs `ManagerRoute` 里叫 `keys` 而页面标题是「钥匙管理」(`KeysPage.swift:71`)、`TempCodeStudio` 在组里叫「临时密码」但没有页面标题 | 同一个东西四处叫法：钥匙/凭证/密码/临时密码 | 5 处文案要一起改才不出洋相 |
| **G14** | **指路文案指向不存在的路径** | `MemberCenterView.swift:105-106`：「设置 → 成员管理」里长按成员行→「授予徽章」；但 `MembersPage.swift` **没有 contextMenu**（E1 grep 空），且"设置"页已不存在（`SettingsView.swift` 现在只装 `SafemodeIntroView`）。`CareRemindersView.swift:158` 同样写「设置-成员管理-补全信息」。`SecurityCenterView.swift:1040` 写「设置 → 家人与钥匙」 | 用户按提示去找，找不到 | 至少 4 处**硬编码的旧路径**（E1 grep "设置 →"/"设置-"） |
| **G15** | **无入口 / 完全缺失的"基础设施页"** | 帮助/关于/版本/致谢/更新说明全部不存在（F-136/F-137）；`App/UI/HelpCenter.swift`、`App/UI/ChangelogView.swift` 均已被删（前者在 `CJKSpacing.swift:4` 留痕，后者 E1 `changelogcheck` 报"不存在"） | 用户想知道版本号、想反馈问题、想看这版改了什么 —— **全都没有** | 4 个"必备页"缺失；`changelogcheck` 闸门因缺页而空转 |
| **G16** | **不可达但仍在维护的并行实现** | `AlarmCenterView`(898 行) vs `AlarmsPage`(417 行)：两套告警 UI；`BackupView`(272) vs `BackupPage`(511)：两套备份 UI；`DeviceHomeView`(2525→230 行，现只剩 `SyncTimeView`) vs `DevicePage`(503) vs `HomeConsole`(1116)：三种"设备总控" | 维护者要改告警样式时，改哪一套？改错的那套没人看得见 | 约 1700 行等价界面双份维护 |
| **G17** | **"面板里的面板"** | `ManagerFace` 里的瓦片「本机设置」(`MF:233`) → `MePage`，而 MePage 本身就是一个完整设置页（358 行、20 个入口） | 用户在"管理面板"里又进了一个"设置页"，两级导航都叫"设置" | 三级深度：门厅 → 管理面板 → 本机设置 → 具体页 |
| **G18** | **分组名字不是用户语言** | `ManagerGroup`：钥匙 / 设备 / 成员 / 安全 / **数据与外观**（`MF:262-267`）。"数据与外观"把两件无关的事塞一起，正是 `SettingsGroups.swift:14-15` 注释里批评过的"一个小节进两组就等于没收敛"的反面 | 用户要备份，在"数据与外观"里找；要换主题，也在"数据与外观"里找 | 一组 4 项跨两个心智模型 |

| **G19** | **功能只在一条路径上可达，另一条没有**（**E3 采纳自 `INVENTORY-IOS.md` 勘误 3，我用 E2 复核**） | 应用锁：`ManagerRoute` **没有**对应 case（E2 逐 case 读 21 条，无 appLock），唯一入口是 `SecurityPage.swift:256` 的 actionRow；外观：`MePage` 无入口（20 条链逐条读，无 `AppearancePage`），唯一入口是 `ManagerFace.swift:231` | 从管理面板永远开不了应用锁；从我页永远换不了主题 —— 两条路径各有各的洞 | 两条通道「看似都全」的错觉，实际各缺一块 |
| **G20** | **分组改造带来的安全回归**（结构性） | 访客通道的判据是 `Route.guestBlocked` → `guestBlockedTabs`（`Route.swift:47/69-71`、`LockKeeperApp.swift:80`），只在 `requestRoute()`（`LockKeeperApp.swift:118-125`）里判一次。但工作区已经是单控制台：门厅 5 个瓦片直接置 `managerGroup`（`HomeConsole.swift:976-979`）、关键提示条直接置组（`:384`）、成员胶囊直接开 sheet（`:205`）、摇一摇直接切 `tabSelection`（`LockKeeperApp.swift:148-167`） | 开了访客通道后，**从门厅点「安全」或「数据与外观」瓦片仍然能直接进管理面板** —— 闸拦的是「切 Tab」，而管理面板根本不是 Tab | 这是 `Route.swift:12-15` 头注预言过的同一类事故（『不崩、不报错、走查看不出来』）在**分组层**的复现；也是本文件 §3 方案必须重新定义「谁能进哪些域」的原因：旧判据（`guestBlocked` = credentials/settings）在新 IA 下没有指称对象 |

### 2.2 三条最贵的结构性问题（其余都是它们的症状）

1. **没有单一分组事实来源**（G1/G4/G5/G11/G18）。
   `SettingsGroups.swift` 已经写了正确判据（"按用户此刻想干的事，不是按代码归属"，:8-15），但**零调用**；实际在跑的是 ManagerGroup 的代码归属（"钥匙"=KeysPage，"设备"=LocksPage）。
2. **纵深页靠"路由枚举 + switch"落地，闸门看不见**（G2/G3/G9/G10）。
   `destmap` 只数 6 条呈现通道（§0.3），`reach` 又按"名字提及"建边（`tools/reach.js:89-94`）。两个尺子各有各的盲区，合起来仍然抓不到"StudioPage 唯一引用在死函数里"。
3. **并行实现没有下线机制**（G16）。
   新页写好后旧页没删，旧页又被 `QuickPool` 这种"零调用但引用一切"的死枢纽挂着，于是 `reach`/`deadscan` 都判它"活着"。

### 2.3 与三份既有裁决的关系（不要以为我在推翻它们）

| 既有裁决 | 原文 | 我这次的处置 |
|---|---|---|
| `DESIGN-DECISIONS.md` **D3** | 「门厅与 MePage 保持两套并行入口 —— **不改**」 | **不推翻，但推翻条件已满足**：D3 自己写「如果出现同一功能在两处行为不一致 —— 那时必须合并」。G1（两个链接指向同一页）与 G4（SyncTime 三入口）就是"行为不一致"的实证 |
| `DECISIONS.md` **D10-6** | 「不把 76 个目的地重排分组（分组沿用 `uiux-v3.data.js`）」 | 本轮用户明确要求"重新分组"，且那 76 条口径已随 4 Tab 一起失效（§0.3） |
| `DECISIONS.md` **D7** | 「App Index 必须列出全部 76 项，一个都不能少」 | 现在**没有 App Index**（`AppIndexView` 不存在）。§3 的方案用"域 → 页"两级替代，且给出比 76 更可靠的完备性判据 |


---

## §3 新的信息架构分组方案

### 3.1 设计约束（先定死，再画图）

| # | 约束 | 来源 |
|---|---|---|
| C1 | 深度 **≤3**：控制台 → 域 → 页 | 本任务要求 |
| C2 | 每个域 **3–7 项** | 本任务要求；`DESIGN-DECISIONS.md:19-23` 的 D2「每组 3–5 项是人一眼能扫完的数量」 |
| C3 | 域名是**用户此刻想干的事**，不是代码归属 | **本仓既有口径**：`SettingsGroups.swift:8-13`「按'用户此刻想干的事', 不是按代码里的实现归属」 |
| C4 | 域名的**来源可追溯**：沿用、改造、或新起，每条都要写明 | 同上（`SettingsGroups.swift:9-13` 是既有那套；实际沿用 2 个、改 3 个，见 §3.2 末两条） |
| C5 | 高频（每天）路径 ≤2 次点击 | 本任务要求 |
| C6 | 不可回退动作不在高频路径上 | 本任务要求；`DESIGN-DECISIONS.md:157-173` D21 的四档递进 |
| C7 | 每个页面必须能指名套用 §8 的模板之一 | 规范 §8「只允许这四种骨架」（实际给了五种） |

### 3.2 推荐方案：门厅 + 5 域 + 一页 = 一站

```
L0  门厅 HomeConsole                —— 只回答「现在能不能进 / 今天发生了什么」
     │
     ├── L1 域（sheet，5 个，每个 3–7 项）
     │     ├─ ① 开门日常   (5 项)
     │     ├─ ② 钥匙与成员 (7 项)
     │     ├─ ③ 记录与告警 (5 项)
     │     ├─ ④ 数据与安全 (7 项)
     │     └─ ⑤ 这台手机   (6 项)
     │
     └── L2 页（push 一层，不再有第三层）
```

**为什么是 5 个域而不是 4 个或 6 个**：

- 4 个会把「记录与告警」和「数据与安全」合成一组 = 12 项，违反 C2；
- 6 个会把「这台手机」再劈成「外观」+「帮助」，而「帮助」现在**一条活功能点都没有**（F-136 / F-137 都是缺），劈出来是空组；
- 5 个刚好接住 §1 里 111 条活功能。**域名的来源要如实说**：5 个名字里 **2 个原样沿用** `SettingsGroups.swift:9-13`（「开门日常」「数据与安全」），**3 个改了**：「凭证与成员」→「钥匙与成员」（D8 已定『用户可见文案统一说钥匙』，`DESIGN-DECISIONS.md:64-68`）、「外观与辅助」→「这台手机」（旧的「无障碍面板」已于 2026-10-20 删除，`AccessibilityKit.swift:100-103`，留着『辅助』二字会让用户去找一个不存在的面板）、**「帮助与关于」整条换成「记录与告警」**（前者对应的帮助/关于页当前**一页都不存在**：F-136 / F-137 全是缺；而记录与告警是真有 5 条活功能的一域）。
- **原来的「帮助与关于」不是被删掉，是被改成「待新建的域」**：等 F-136 / F-137 那三页真做出来，它们按 §3.3-D 的『新增 4 项』进 ⑤ 这台手机的末尾，或届时独立成第 6 个域。

#### 域定义表

| 域 | 名字（用户语言） | 判据（用户此刻想干的事） | 项数 | 图标 |
|---|---|---|---|---|
| ① | **开门日常** | 「我要开一次门 / 调这个门怎么开」 | 5 | `lock.open` |
| ② | **钥匙与成员** | 「谁能开这个门」 | 7 | `key.horizontal` |
| ③ | **记录与告警** | 「今天 / 上周发生过什么」 | 5 | `list.bullet.rectangle` |
| ④ | **数据与安全** | 「数据别丢 / 别被人看见」 | 7 | `lock.shield` |
| ⑤ | **这台手机** | 「这台设备本身长什么样、怎么用」 | 6 | `iphone.gen3` |

#### 逐域页面清单 + 规范 §8 模板
**① 开门日常（5 项）**
| # | 页 | 现状锚点 | 模板 | 理由 |
| 1 | 这台锁 | `DevicePage.swift:30` | **C 详情** | 一屏讲一把锁：身份 → 待办 → 明细（`DevicePage` 已是这个形状，区块见 `:41/47/48/49/52/53`） |
| 2 | 开锁方式（按住确认 / 靠近自动开锁 / 信号围栏） | `LinkPrefsView`（`LinkSenseKit.swift:650`）+ `AutoCalView`（`AutoOpen.swift:523`）**合并** | **C 详情** | 两页都是「门怎么开」，各自一屏都太薄（LinkPrefs 3 卡、AutoCal 2 区） |
| 3 | 门锁安全模式 | `SafemodeIntroView`（`SettingsView.swift:12`） | **C 详情** | 单页单事（单双验 / 静音 / 三个只读位，见 `SettingsView.swift:114-139`） |
| 4 | 校准门锁时间 | `SyncTimeView`（`DeviceHomeView.swift:9`） | **C 详情** | 一页一个数字（偏差秒数）+ 一个动作 |
| 5 | 设备管理（多锁排序 / 隐藏 / 解绑 / 分享安卓） | `LocksPage.swift:30` | **D 主题化列表** | 「按分组排列同构行」正是 D 的适用面（规范 §8 模板 D 的适用句） |

**② 钥匙与成员（7 项）**
| # | 页 | 现状锚点 | 模板 | 理由 |
| 1 | 钥匙列表（密码/指纹/临时码三段 + 搜索 + 行长按） | `KeysPage.swift:31` | **D 主题化列表** | 同构行 + 分段（`:155` 分段条） |
| 2 | 添加密码 | `AddKeyPage.swift:25` | **C 详情** | 单任务表单，不走画廊 |
| 3 | 录指纹 | `AddFingerPage.swift:24` | **C 详情** | 单任务 + 进度 |
| 4 | 临时码 | `CredentialStudio.swift:510` | **C 详情** | 生成 + 有效期 |
| 5 | 成员名册 | `MembersPage.swift:30` | **A 画廊** | 头像 + 名字 + 角色 → 图/名/说明的卡片流，正是 A 的形状 |
| 6 | 成员详情 360 | `MemberCenterView.swift:15` | **C 详情** | 多区块同属一人（六区块见 `:60-65`） |
| 7 | 钥匙工坊（四类凭证入口） | `StudioPage.swift:24` —— **本次恢复可达** | **A 画廊** | 2×2 能力卡（`:56-61`）就是画廊的最小形态 |

**③ 记录与告警（5 项）**
| # | 页 | 现状锚点 | 模板 | 理由 |
| 1 | 事件记录（按天时间线 + 搜索 + 筛选视图 + 备注 + 同步） | `EventsPage.swift:32` | **D 主题化列表** | 按天分组、同构行 |
| 2 | 告警 | `AlarmsPage.swift:27` | **D 主题化列表** | 按紧迫度分组同构行（`:185` 分级概览） |
| 3 | 统计 | `StatsPage.swift:31` | **B 仪表盘** | 三个问题 + 大数字 + 图（`:81/148/197/229/263/324`） |
| 4 | 动态消息 | `FeedPage.swift:21` | **D 主题化列表** | 跨锁事件流（`:51` 日组头） |
| 5 | 导出中心 | `ExportCenter.swift:1475` | **C 详情** | 一个目的地 + 多组动作（`:1546` 范围卡 / `:1558` 三组动作卡） |

**④ 数据与安全（7 项）**
| # | 页 | 现状锚点 | 模板 | 理由 |
| 1 | 备份与恢复 | `BackupPage.swift:28` | **C 详情** | 状态卡 + 两个方向（`:58-61`） |
| 2 | 备份工作室（导出向导 / 恢复向导 / WebDAV / 换机迁移 / 本地文件） | `BackupStudio.swift:10`（子页 `:458` / `:918` / `:323`） | **C 详情**（工作室作 hub） | 五个入口一个 hub，深度不再涨 |
| 3 | 回收站（含下发队列） | `CredentialBinView.swift:23` | **D 主题化列表** | 同构行 + 保留期（`:49` 保留卡、`:51/174` 队列） |
| 4 | 本机保护 | `SecurityPage.swift:28` | **B 仪表盘** | 一屏一个结论（「现在安全吗」三盏灯，`:80-85`） |
| 5 | 防窥与隐私 | `SecurityPeekView`（`SecurityCenterView.swift:154`）+ `PrivacyDashboard`（`:1390`）**合并** | **D 主题化列表** | 逐项开关 = 同构行（`:1430` 逐项状态） |
| 6 | 审计与销毁 | `SecurityAuditView`（`:471`）+ `SecurityDestroyView`（`:881`）**合并** | **C 详情** | 都是「留痕 vs 抹掉」，且销毁必须在审计之后读懂 |
| 7 | 应用锁与访客 | `AppLockSetupView.swift:25` + 访客开关（`SecurityCenterView.swift:262`）**合并** | **C 详情** | 两个都是「谁能进这台手机」 |

**⑤ 这台手机（6 项）**
| # | 页 | 现状锚点 | 模板 | 理由 |
| 1 | 外观（明暗 / 强调色 / 高对比 / 周起始日 / 图标） | `AppearancePage.swift:18`（三卡 `:49-51`）+ `IconPicker.swift:13` **合并** | **A 画廊** | 七个色板 + 九款图标 = 可看的选项墙 |
| 2 | 维护与保养 | `CarePage.swift:27`（含 `MaintenanceView` `CareViews.swift:9` / `CareChecklistView` `:470`） | **C 详情** | 待办清单 + 历史 |
| 3 | 关怀提醒 | `CareRemindersView.swift:6` | **C 详情** | 三张卡（`:79/104/123`） |
| 4 | 固件升级 | `FirmwarePage.swift:23` | **C 详情** | 三段进度 + 体检单（`:80-90`） |
| 5 | 网关与钥匙串 | `GatewayPage.swift:21` + `DonglesPage.swift:22` **合并** | **C 详情** | 两个都是「附属硬件」，各自一页都太薄 |
| 6 | 诊断与自检 | `DiagnosticsPage.swift:18` | **B 仪表盘** | 六个体检卡（`:51-57`）= 仪表盘 |

> **模板分布**：A0（展示壳轮播）**本方案一页都不用**。理由：A0 是「功能引导卡 + 设备样机」的营销层（规范 §8），而这个 App 里没有任何一页在向用户推销功能 —— 用户已经装了；且仓内**零位图资产**（`tools/assetscheck.js` 的纪律：位图只许待在 `appiconset`），做不出规范 §6.4 要求的真 3D 样机。
>
> 这条与 teammate 的 `docs/GLASS/DEVIATIONS.md` §5（『没有展示壳这一层』）是同一结论，两边独立得出（E3 对照）。

### 3.3 迁移映射表（旧位置 → 新位置，一行一条，可勾）

**A. ManagerFace 的 21 条路由**

| 旧（ManagerGroup › 行） | 新（域 › 页） | 处置 | ☐ |
|---|---|---|---|
| 钥匙 › 钥匙管理 | 钥匙与成员 › 钥匙列表 | 改归属 | ☐ |
| 钥匙 › 指纹 | 钥匙与成员 › 录指纹 | 改归属 | ☐ |
| 钥匙 › 临时密码 | 钥匙与成员 › 临时码 | 改归属 | ☐ |
| 设备 › 我的门锁 | 开门日常 › 设备管理 | 改归属 | ☐ |
| 设备 › 固件升级 | 这台手机 › 固件升级 | 改归属（讲的是机身硬件，不是「怎么开门」） | ☐ |
| 设备 › 网关配网 | 这台手机 › 网关与钥匙串 | 改归属 + **合并** | ☐ |
| 设备 › 钥匙串 | 这台手机 › 网关与钥匙串 | 改归属 + **合并** | ☐ |
| 设备 › 校准时间 | 开门日常 › 校准门锁时间 | 改归属 | ☐ |
| 成员 › 成员 | 钥匙与成员 › 成员名册 | 改归属 | ☐ |
| 成员 › 添加成员 | 钥匙与成员 › 成员名册（右上 +） | **删除行**（页内已有入口，二入口必删其一） | ☐ |
| 成员 › 合并成员 | 钥匙与成员 › 成员详情（右上菜单） | **删除行**（现在落到 MembersPage，等于假入口，G2） | ☐ |
| 成员 › 已归档 | 钥匙与成员 › 成员名册（底部） | **删除行**（页内已有） | ☐ |
| 安全 › 隐私看板 | 数据与安全 › 防窥与隐私 | 改归属（页名从「隐私看板」改为「防窥与隐私」，与内容一致） | ☐ |
| 安全 › 安全审计 | 数据与安全 › 审计与销毁 | **合并** | ☐ |
| 安全 › 销毁数据 | 数据与安全 › 审计与销毁 | **合并** | ☐ |
| 安全 › 安全模式 | 开门日常 › 门锁安全模式 | 改归属（它改的是**锁**的行为） | ☐ |
| 数据与外观 › 备份恢复 | 数据与安全 › 备份与恢复 | 改归属 | ☐ |
| 数据与外观 › 导出中心 | 记录与告警 › 导出中心 | 改归属（导出物是**记录**） | ☐ |
| 数据与外观 › 外观工作室 | 这台手机 › 外观 | 改归属 | ☐ |
| 数据与外观 › 本机设置 | —— | **删除**（它是第二个设置页，G17；内容全部按 B 表分流） | ☐ |
| （组内不可见）诊断与自检 | 这台手机 › 诊断与自检 | 改归属（修 G10） | ☐ |

**B. MePage 的 20 条 NavigationLink（+ 路径 C 的 4 条 actionRow）**

| 旧（MePage › 段） | 新（域 › 页） | 处置 | ☐ |
|---|---|---|---|
| 本机保护 › 本机数据保护 | 数据与安全 › 本机保护 | 改归属 | ☐ |
| 本机保护 › 隐私与伪装 | 数据与安全 › 防窥与隐私 | 改归属（并行改动已把它改指 SecurityPeekView，G1 的『同页』已修；本条只剩搬归属） | ☐ |
| 本机保护 › 诊断与自检 | 这台手机 › 诊断与自检 | 改归属 | ☐ |
| 这台锁 › 这台锁（DevicePage） | 开门日常 › 这台锁 | 改归属 | ☐ |
| 这台锁 › 设备管理 | 开门日常 › 设备管理 | **删除行**（与 ManagerFace 重复，G5） | ☐ |
| 这台锁 › 锁档案 | 开门日常 › 这台锁（页内「改档案」） | **合并进页**（锁档案 = 这台锁的编辑形态） | ☐ |
| 这台锁 › 校准门锁时间 | 开门日常 › 校准门锁时间 | **删除行**（三入口收敛为一，G4） | ☐ |
| 这台锁 › 开锁偏好 | 开门日常 › 开锁方式 | **合并** | ☐ |
| 这台锁 › 靠近自动开锁 | 开门日常 › 开锁方式 | **合并** | ☐ |
| 这台锁 › 门锁安全模式 | 开门日常 › 门锁安全模式 | **删除行**（重复） | ☐ |
| 数据 › 备份与恢复 | 数据与安全 › 备份与恢复 | **删除行**（重复） | ☐ |
| 数据 › 导出中心 | 记录与告警 › 导出中心 | **删除行**（重复） | ☐ |
| 数据 › 事件记录 | 记录与告警 › 事件记录 | 改归属 | ☐ |
| 数据 › 动态消息 | 记录与告警 › 动态消息 | 改归属 | ☐ |
| 关于与偏好 › App 图标 | 这台手机 › 外观 | **合并** | ☐ |
| 关于与偏好 › 检查固件更新 | 这台手机 › 固件升级 | **删除行**（重复） | ☐ |
| 关于与偏好 › 维护与保养 | 这台手机 › 维护与保养 | 改归属 | ☐ |
| 关于与偏好 › 关怀提醒 | 这台手机 › 关怀提醒 | 改归属 | ☐ |
| 关于与偏好 › 蓝牙钥匙串 | 这台手机 › 网关与钥匙串 | **合并** | ☐ |
| 关于与偏好 › 智能网关 | 这台手机 › 网关与钥匙串 | **合并** | ☐ |
| （SecurityPage 路径 C 的 4 条）应用锁 → | 数据与安全 › 应用锁与访客 | 改归属（**升到域级**：现在只有 `SecurityPage.swift:256` 一条路能到，G19） | ☐ |
| （路径 C）防窥与遮蔽 → | 数据与安全 › 防窥与隐私 | 改归属 | ☐ |
| （路径 C）审计日志 → | 数据与安全 › 审计与销毁 | 改归属 | ☐ |
| （路径 C）彻底销毁 → | 数据与安全 › 审计与销毁 | 改归属（**并把回收站从这一页里提出来**，G6） | ☐ |

**C. destmap 的 19 条「呈现目的地」**

| 旧入口（destmap 报的） | 新位置 | 处置 | ☐ |
|---|---|---|---|
| AutoCalView（`MePage.swift:224`） | 开门日常 › 开锁方式（页内一节） | 合并 | ☐ |
| BackupStudioView（`BackupPage.swift:107`、`BackupView.swift:63`） | 数据与安全 › 备份工作室 | 保留；`BackupView` 那条随死页一起下线 | ☐ |
| BatterySwapGuideView（`AlarmCenterView.swift:639`、`CareViews.swift:226`） | 这台手机 › 维护与保养（页内 push） | 保留 1 处，删告警中心那处 | ☐ |
| CareRemindersView（`MePage.swift:335`） | 这台手机 › 关怀提醒 | 改归属 | ☐ |
| CredentialBinView（`SecurityCenterView.swift:999`） | 数据与安全 › 回收站（**升到域级**） | 改归属（修 G6） | ☐ |
| ExportCenterView（`MePage.swift:257`） | 记录与告警 › 导出中心 | 改归属 | ☐ |
| ExportWizardView（`BackupStudio.swift:33`） | 数据与安全 › 备份工作室 › 导出向导 | 保留 | ☐ |
| LinkPrefsView（`MePage.swift:217`） | 开门日常 › 开锁方式 | 合并 | ☐ |
| MaintenanceView（`CarePage.swift:252`） | 这台手机 › 维护与保养 | 保留 | ☐ |
| MemberArchivedView（`MembersPage.swift:170`） | 钥匙与成员 › 成员名册（底部） | 保留 | ☐ |
| MemberDetail360View（`HomeConsole.swift:209`、`MembersPage.swift:92/142`） | 钥匙与成员 › 成员详情 + 门厅胶囊直达 | 保留两条（门厅直达是高频路径） | ☐ |
| MemberFamilySettingsView（`MembersPage.swift:190`） | 钥匙与成员 › 成员名册（底部） | 保留 | ☐ |
| MemberWizardView（`MembersPage.swift:75`） | 钥匙与成员 › 成员名册（右上 +） | 保留 | ☐ |
| MergeMembersView（`MemberCenterView.swift:86`） | 钥匙与成员 › 成员详情（右上菜单） | 保留（**唯一**入口，删 ManagerFace 那条假的） | ☐ |
| RestoreWizardView（`BackupStudio.swift:34`） | 数据与安全 › 备份工作室 › 恢复向导 | 保留 | ☐ |
| SafemodeIntroView（`MePage.swift:233`） | 开门日常 › 门锁安全模式 | 改归属 | ☐ |
| ShareToAndroidView（`LocksPage.swift:136`） | 开门日常 › 设备管理（行菜单） | 保留 | ☐ |
| SyncTimeView（`CareViews.swift:423` + `MePage.swift:211`） | 开门日常 › 校准门锁时间 | **收敛为 1 处**（CareViews 那处改为指向新位置） | ☐ |
| UnclaimedClaimView（`MembersPage.swift:180`） | 钥匙与成员 › 成员名册（底部） | 保留 | ☐ |

**D. 合并 / 删除 / 改归属 / 新增 四类汇总**

| 处置 | 条目 | 说明 |
|---|---|---|
| **合并（9 组）** | 开锁方式（LinkPrefs+AutoCal）· 网关与钥匙串 · 防窥与隐私 · 审计与销毁 · 应用锁与访客 · 外观（Appearance+IconPicker）· 锁档案→这台锁 · 备份工作室 hub · 回收站升域级 | 每组两页各自都太薄；合并后每页仍能指名套用 §8 模板之一 |
| **删除（6 类）** | ① MePage「隐私与伪装」重复链接 ② ManagerFace「本机设置」整行 ③ ManagerFace「添加成员 / 合并成员 / 已归档」三行 ④ MePage 的 8 条重复链接 ⑤ 死页 3 个（`AlarmCenterView` / `BackupView` / `LockOverviewView`+`DeviceStripCard`） ⑥ `SettingsGroup` 死方案（改造成 §3.2 的域枚举） | 删的是**入口与死实现**，不是功能 |
| **改归属（18 条）** | 见 A/B/C 三表 | 只搬入口，不改页面内部 |
| **新增（5 项）** | ① **帮助与关于**（F-136：版本号 / 致谢 / 数据流向） ② **更新说明**（F-137，同时恢复 `changelogcheck` 闸门） ③ **精确查找 iOS 版**（F-016，对着安卓 `SignalArrow.kt:128` 做） ④ **诊断与自检升域级**（F-066，修 G10） ⑤ **访客域的准入闸**（G20）：域面板改为**唯一入口**后，访客闸的判据必须从「Tab 序号」改成「域枚举」——建议 `HomeDomain.guestBlocked: Set<HomeDomain>`（域④数据与安全 + 域⑤这台手机），并在域面板的 5 个瓦片与 `openGroup` 上各判一次 | 前两项是「必备页缺失」，第三项是「安卓有 iOS 没有」，第四项是「有页没入口」，第五项是**分组改造必须同时补的安全闸**（不补就是 §2-G20 那条静默回归） |

### 3.4 备选方案（只给一个，且我不推荐）

**备选 B：保留 ManagerFace 5 组，只做「去重 + 补入口」**

- 做法：删掉 MePage（20 条全部并进 5 组），`diagnostics` 加进「安全」组，SyncTime 收敛为 1 条。
- 代价：域名字仍是代码归属（「数据与外观」跨两个心智模型，G18），且「本机保护 vs 隐私看板」这类分叉仍在（G11）、应用锁与外观各只有一条通道能到（G19）。
- 本方案对 G19 的处置：应用锁 → 域④『应用锁与访客』、外观 → 域⑤『外观』，**两条通道的洞同时补上**（因为域面板是唯一入口）。
- 只在「本轮不许动 `ManagerFace.swift`」这条约束成立时才选它。

### 3.5 落地顺序（把风险摊开）

| 步 | 动作 | 风险 | 不可回退？ |
|---|---|---|---|
| 1 | 删 MePage 两条重复链接（G1）与 8 条重复导航（G5） | 低（纯入口删除） | 否 |
| 2 | `diagnostics` 进组（G10） | 低 | 否 |
| 3 | 新增域枚举 `HomeDomain`（5 域），**只做映射表，不删旧路由** | 低 | 否 |
| 4 | 合并 9 组页面（§3.3-D） | 中（页内布局改动） | 否（旧页留在 git） |
| 5 | 删 `ManagerFace` 的 4 行冗余 + `MePage` 退役 | 中 | 是（git 可回） |
| 6 | 新增 4 页（帮助 / 更新说明 / 精确查找 / 诊断升域）+ **访客闸改判据**（G20） | 中 | 否 |
| 6b | **G20 必须在第 5 步之前做完**：删 MePage 那一刻，`guestBlocked` 的 credentials/settings 两个 host 里有一个就没指称对象了 | **高**（安全） | 是（上线后已出事就晚了） |
| 7 | **最后**才删死页（`AlarmCenterView` / `BackupView` / `LockOverviewView` / `DeviceStripCard`） | 高（可能有人还想复用） | 是 |


---

## §4 两端分组对齐

### 4.1 先看清 Android 到底是什么（E2 逐文件读）

| 项 | Android 现状 | 证据 |
|---|---|---|
| 界面层 | **1 个 Activity + 1 个 Composable 根**，无 NavHost、无 Navigation 库 | `MainActivity.kt:108 KfApp`；`app/build.gradle.kts` 依赖表无 navigation |
| 可见层 | 2 屏 + 2 覆盖层 + 1 个系统扫码页 = **5 层**；任务卡说的「S3 设置抽屉」其实是**全屏遮罩 + 底部卡片**，不是 BottomSheet | `MainActivity.kt:417-458`（`AnimatedVisibility` + `fillMaxSize` + `Arrangement.Bottom`） |
| 协议面 | 只实现 **3 条命令**（01 会话 / 03 状态 / 04 开锁） | `KfProtocol.kt:180 unlockFrame`、`:185 tokenFrame`、`:192 statusFrame` |
| 存储 | SharedPreferences 单键 `kf_key_v1`，存 `lock` + `proximity` 两项 | `LockStore.kt:17-19` |
| 自动开锁 | 有，且是真判据（回差 + 一次性闩锁 + 6s 冷却） | `AutoOpenKit.kt:32/50`；`MainActivity.kt:271 maybeAutoUnlock` |
| 查找层 | **有**，AirTag 式箭头 + 距离档 + 提示音（iOS 没有） | `SignalArrow.kt:128`；`MainActivity.kt:811 AirTagLayer` |
| 设置抽屉 | 只有 4 项：靠近开关 / 重新扫码 / 解绑 / 完成 | `MainActivity.kt:683-760 ProximityCard` |
| 返回键 | **已处理**（AirTag 层 → 抽屉 → 退出） | `MainActivity.kt:150 BackHandler` |

### 4.2 映射表：iOS 的 5 个域在 Android 上怎么办

| iOS 域 | Android 保留哪些 | 落在哪一屏 | 需要补屏吗 |
|---|---|---|---|
| **① 开门日常** | 只保留**手动开锁** + **靠近自动开锁**开关 | 手动开锁 = **S2**；开关 = **S3**（已存在，`ProximityCard`） | **不需要**。S2 已经是「开门日常」的全部：圆盘 + 状态 + 齿轮 |
| **② 钥匙与成员** | **不保留**。安卓只有 `ekey`（`AndroidPair.swift:15` 签出来的那一把），没有凭证表、没有成员 | —— | **不需要，而且不该补**：补它就得补 cmd 0A/13/16 一族 + 成员数据模型，等于把 iOS 的一半搬过来（`PART6-ANDROID.md:150` 原话「没有 P0 的协议层对齐，后面每个功能页都是在沙上盖楼」） |
| **③ 记录与告警** | **不保留**（无 cmd16 日志读取） | —— | **不需要**；`PART6-ANDROID.md:144` 把它排在 P1 |
| **④ 数据与安全** | 只保留**解绑**与**换绑二次确认** | **S3** + `MainActivity.kt:461 AlertDialog` | **不需要** |
| **⑤ 这台手机** | 只保留**深浅双模跟随系统**与**权限提示** | 系统级，无屏 | **不需要**；`PART6-ANDROID.md:118` 明确「不升 targetSdk、不引入 Navigation / DataStore / Room」 |

### 4.3 一句话立场（写死，防止下一轮有人来「对齐」）

> **Android 是极简客户端，不许因为 iOS 有 96 个 View / 152 条功能点就给它加导航树。**
>
> 安卓的定位由它自己那行注释钉死：`LockStore.kt:13` 原话「本机存储: 只存一把锁 (极简版的定位就是『一个人、一把门』)」。
> 它的屏数上限**由协议面决定**，不是由 iOS 的功能数决定：3 条命令只能支撑 5 个可见层。
> 任何「iOS 有 X，安卓也该有」的提案，先过这一条：**安卓有没有那条命令？** 没有就先做协议（P0），不要先做界面。

### 4.4 安卓唯一值得补的一件事（不是屏，是注释）—— 已在写作期间被修

`Tokens.kt` 的自述与现状曾经分家。**HEAD 版**（E1 `git show HEAD:…Tokens.kt`）：

| 项 | HEAD 版声称 | 实际（E2） | 结论 |
|---|---|---|---|
| 引用的 iOS 文件 | 「与 iOS 的 `App/Core/DesignSystem.swift` 数值逐字相同」（HEAD `Tokens.kt:6`） | 该文件**已不存在**；现存令牌在 `App/Core/Theme.swift` | 死指针 |
| 圆角值 | 「与 iOS DS.Radius 同值（card 22 / control 16 / tile 18）」（HEAD `Tokens.kt:31`） | iOS 侧 `XRadius` 是**按主题求值**的（`Theme.swift` 里 `enum XRadius`），不是三个常量 | 无法逐值核对 ⇒ 自述不可证 |
| 消费点行号 | `MainActivity.kt:687 / :685`（HEAD `Tokens.kt:10-11`） | 并行改动已让行号漂 | 注释过期 |

**工作区已被并行改动重写**（E1 读工作区全文）：新头部直接点名三处不成立并给理由（`Tokens.kt:8-16`），
并把 `gutter` 从 16 改成 14、`card` 从 22 改成 24、新增 `Space.section/pageTop/card` 与 `Hit.min = 48.dp`，
每条都写明对应的 iOS 出处行号。**我复核了它引用的 `Theme.swift` 行号方向正确**（iOS 侧确有 `XSpace`/`XRadius`/`XHit`/`XIcon` 四族，
`Theme.swift` 工作区 :162 / :201 / :221 / :227），但**没有逐值比对**（因为 iOS 侧是按主题求值，静态读不出唯一值）。

> 与 teammate `android-inventory` 的结论一致（E3：`docs/GLASS/INVENTORY-ANDROID.md:32` 判旧注释为假）；我按 E2 独立复核了『文件已删』这一条。
> 它不构成『补屏』理由，只说明**两端一致性判据曾经是空的**：`PART6-ANDROID.md:167-172` 定的「两端同名令牌数值逐字相同」在 HEAD 版代码里无法验证；工作区这一版开始可验证了。

### 4.5 两端在分组上的唯一交集：S3 = 域 ① 的最后一节

安卓 S3 抽屉里的 4 项，在 iOS 新方案里分属同一个域 ① 的两页：

- 靠近开关 → 域 ① 开门日常 › 开锁方式
- 重新扫码 / 解绑 → 域 ① 开门日常 › 设备管理

⇒ 两端在**语义**上对齐（都是『这一把锁怎么开、怎么解绑』），在**结构**上不追平（安卓只有 4 项，不分局）。这是**有意的不对称**，写在这里免得下一轮被当成遗漏。


---

## §5 分组自检清单

判据来自任务卡 8 条。**逐条给结论 + 证据 + 不合规的处置**，不写『基本满足』。

### 5.0 一行一条：八条判据的过 / 不过

| # | 判据 | 结论 |
|---|---|---|
| ① | 每个功能点都有归属 | **部分过**（144 条用户可见的全有归属；8 条全域底座故意不给域位） |
| ② | 没有功能点属于两个域 | **过** |
| ③ | 每个域 3–7 项 | **过**（5/7/5/7/6） |
| ④ | 深度 ≤3 | **过**（附一条护栏：第 2 层之后只许 modal） |
| ⑤ | 没有『其他/杂项』兜底域 | **过** |
| ⑥ | 名字是用户语言 | **过**（2 沿用 + 3 改，改的逐条给理由） |
| ⑦ | 高频功能 ≤2 次点击 | **过** |
| ⑧ | 不可回退动作在高频路径外 | **过**（另挂一条安全前置 G20，不属违例） |

**统计：8 条里 0 条完全不过、1 条部分过（①）。** 部分过的那条不是方案缺陷，是刻意设计（内部底座不该有域位），处置见下表 ① 行。

---

### 5.0b 逐条依据（下表即证据）

| # | 判据 | 结论 | 证据 / 说明 |
|---|---|---|---|
| ① | 每个功能点都有归属 | **⚠ 部分满足** | **用户可见的 144 条**全部落到 5 域（§3.2 逐域清单可对）；**8 条内部支撑功能点没有域位**：F-126 命令安全表 / F-149 设计令牌层 / F-150 降级通道 / F-151 到达性闸门 / F-058 归因引擎 / F-093 型号能力表 / F-084 容量解析 / F-147 防连点。它们不是『某一页』，而是**全域共享的底座**——给它们安一个域反而是错的（会让用户以为那是个能点的地方）。**处置**：在域枚举里加一个 `internal` 标记位，这 8 条只在本台账出现，不进任何域面板。 |
| ② | 没有功能点属于两个域 | **✅ 满足** | 逐条核对 152 行，无一条在两个域里出现。三个曾经的『双属』嫌疑已按判据定死：**校时**（原 ManagerFace 设备组 + MePage 这台锁组 + CareViews）→ 只归域①（它改的是锁的时钟）；**诊断**（原 ManagerFace 安全组 + MePage 本机保护组）→ 只归域⑤（它看的是这台手机的健康）；**导出中心**（原 ManagerFace 数据与外观 + MePage 数据）→ 只归域③（导出物是记录）。 |
| ③ | 每个域 3–7 项 | **✅ 满足** | ①5 · ②7 · ③5 · ④7 · ⑤6（§3.2 域定义表逐行可数）。上限 7 的两处理由：②里 7 项是三类钥匙（密码/指纹/临时码）+ 工坊 + 名册 + 详情 + 开锁方式入口，再减就要把『添加密码/录指纹/临时码』塞回列表页，那会让列表页变回『管理器』（`KeysPage.swift:11-13` 头注批评过的旧版形状）；④里 7 项含合并后的三对（防窥 / 审计销毁 / 应用锁访客），拆开就是 10 项。 |
| ④ | 深度 ≤3 | **✅ 满足（带一条附加规则）** | L0 门厅 → L1 域面板(sheet) → L2 页(push) = 3 层。**附加规则**（必须写进护栏）：第 2 层之后的呈现只允许 modal（sheet / fullScreenCover），**不许再 push**。当前有两处是『第 3 层再开 sheet』：`备份工作室 → 导出向导`（`BackupStudio.swift:33`）与 `成员详情 → 合并`（`MemberCenterView.swift:86`）。modal 不占导航树层级，所以仍算 ≤3；但**一旦有人把它们改成 push，深度立刻变 4** ⇒ 建议进 `tools/uicoverage.js` 加一条：域面板内不得出现第 3 个 `NavigationStack`。 |
| ⑤ | 没有『其他/杂项』兜底域 | **✅ 满足** | 5 个域全部有明确判据句（§3.2 表第 3 列），没有『其它』『更多』『工具』这类名字。特别检查了旧的『数据与外观』（`ManagerFace.swift:267`）——它正是兜底域的形状（备份+导出+外观+本机设置四件无关的事），本次拆散进 ④ 与 ⑤。 |
| ⑥ | 名字是用户语言 | **✅ 满足（来源已如实标注）** | 5 个名字里 **2 个原样沿用** `SettingsGroups.swift:9-13`（开门日常 / 数据与安全），**3 个改过**并给了理由（见 §3.2 末两条 li）：凭证与成员→钥匙与成员（D8 统一『钥匙』口径）、外观与辅助→这台手机（无障碍面板已删）、帮助与关于→记录与告警（前者对应的页一页都不存在）。**没有一个名字是代码归属词**（不是 `ledger`/`devices`/`backupLook` 那种）。 |
| ⑦ | 高频（每天）功能在 ≤2 次点击内 | **✅ 满足** | 每天用的四条逐条数：**开锁** = 0 次（首屏就是环，`HomeConsole.swift:400`（H:））；**分时图/三指标** = 0 次（首屏）；**成员胶囊→详情** = 1 次（`HomeConsole.swift:205`（H:））；**靠近自动开锁开关** = 域瓦片(1) + 行(2) = 2 次。反例自检：`导出向导` 要 3 次，但它不是每天用的（§1.3 记『每月』）。 |
| ⑧ | 不可回退动作在所属域的高频路径之外 | **✅ 满足（但另有一条安全前置）** | 四个不可回退动作的位置：**彻底销毁** 在 域④ ›『审计与销毁』页（域内第 6 项，且页内还要三级确认 + sudo，`SecurityCenterView.swift:646/966`）；**清空回收站** 在 域④ ›『回收站』页（长按 2 秒，`SecurityCenterView.swift:1023-1026`）；**解除绑定门锁** 在 域① ›『设备管理』行的滑动菜单（`LocksPage.swift:250`，且二次确认 `:142`）；**合并成员** 在 域② ›『成员详情』右上菜单（`MemberCenterView.swift:86`）。四条都不在域面板的第一屏、也不在每天用的路径上。<br>**安全前置（G20）**：本方案的域面板是**唯一**入口，因此访客准入闸必须跟着搬 —— 旧闸判 `Route.guestBlocked`（`Route.swift:47`），而新 IA 里没有 Tab 序号，不搬就是静默失去覆盖。这一条不是自检 ⑧ 的违例，但属于改造时必须同时补的，写在 §3.3-D 新增第 ⑤ 项与 §3.5 第 6b 步。 |

### 5.1 自检发现的两个**不合格候选**（我不打算糊过去）

| 候选 | 为什么可能不合格 | 我的裁决 |
|---|---|---|
| ② | 域② 里的『钥匙列表』与『钥匙工坊』都通向同一批凭证（列表是读、工坊是建） | **保留两者**：判据是『用户此刻想干的事』——想**看**谁能开门 vs 想**加**一把钥匙。动词不同，不是同一功能两个入口。但**必须在域面板里把行副标题写成动词**（『看看谁能进』/『加一把新钥匙』），否则会退化成 G5 那一类重复。 |
| ④ | 『备份工作室』作 hub 后，域④ → 工作室 → 导出向导 = 3 次点击（不是层级，是点击） | **接受**，因为它每月一次。但**如果将来备份变成每周动作**，就必须把『导出向导 / 恢复向导』拆成域④的两个独立行（那样域④会变 9 项 ⇒ 必须同时把『网关与钥匙串』搬去域①或域⑤）。这条写在这里，作为推翻条件。 |

### 5.2 这个方案没有解决的三件事（诚实边界）

1. **`destmap` 量不到 ManagerFace 那一支**（§0.3）。本方案把深度页从『路由枚举』搬进域面板后，**如果仍然用 `path.append`**，`destmap` 依然看不见。要让闸门真正覆盖，得把域面板改成 `NavigationLink`，或给 `destmap` 加第七条通道（扫 `path.append(.` → `case .x:` 的映射）。**这是工具侧改动，不在本文件范围内**。
2. **`reach.js` 按『名字提及』建边**（`tools/reach.js:89-94` 自述『宁可高估可达』），所以它永远发现不了『唯一引用在死函数里』这类洞（§2-G9 的四个页面就是这么活的）。要抓住它们，需要一条**双向**判据：被引用次数 ≥1 **且** 引用方的入度 ≥1。同样不在本文件范围。
3. **帮助 / 更新说明 / 版本号三页缺失**（F-136/F-137）本方案只是『标出来』，没写内容。这三页的内容需要产品决定（比如版本号从 `CFBundleShortVersionString` 读，而 `project.yml:42` 写的是 `1.0.0`，且 `App/Info.plist` 文件当前不存在 —— E1 `Test-Path` false，而 `project.yml:39` 指向它）。**这是编译期隐患，不是分组问题**，单独记一笔。

### 5.3 一句话总结

> 这次不是『把 5 组换成 5 个域』，而是把**四套并行的分组口径收成一套**，并顺手把 §2 里 **20 条**问题中的 **14 条**在方案里给了处置（G1/G2/G4/G5/G6/G8/G10/G11/G14/G16/G17/G18/G19/G20）；剩下 6 条（G3/G7/G9/G12/G13/G15）中，G9 的四页下线与 G15 的三页新增是**独立工程**，不该混在『重新分组』这一刀里做。


---

## 附录 A · 本文引用的闸门命令与关键输出（E1 原始行）

```
$ node tools/destmap.js
目的地总数 = 19   (扫 109 个 .swift，呈现通道 = sheet/fullScreenCover/navigationDestination/popover/NavigationLink/Tab)

$ node tools/featuremap.js
编号权威 IDEA-BANK 1050 条 · 判定权威 FEATURE-TRIAGE 覆盖 1050 条 · 扫了 112 个 Swift 文件
【A · 判 ✅ 可行却零编号标注 ⇒ 未实现候选】245 条  (A1 37 / A0-x 25 / A0-w 5 / A0-d 110 / A0-t 66 / A0-u 2)
【实现证据合计】代码标注 722 条 + 仅台账 file:line 8 条 = 730 条 (顾问级, 不判失败)

$ node tools/reach.js
View struct 共 90 个 / 从 RootView 可达: 89 / 不可达: 1  (XLockBlade)

$ node tools/deadscan.js
A 档 · 确证零引用 146 条

$ node tools/keydead.js
只写不读 10 个 / 已销号 0 个 / 前缀族 2 个 / 只读不写 40 个 / 同一键多套默认值 0 个
键面统计: 216 个 kf_/别名键 · 别名表 69 条 · 搬运函数 14 个

$ node tools/deadfuncs.js
扫描 1119 个函数声明   零调用 148 个（有读无写 7 组）

$ node tools/pagecraft.js
平均完成度 98.8%   未满分页面: 1 个 —— 待改: StudioPage（3/4，缺空态）

$ node tools/uicoverage.js
目的地台账 = 19 条   枚举 = 19 条 · 检查一 通过
检查二 · 缝覆盖率 = 18/19 (95%)，未挂缝 1 条: CredentialBinView
检查四/六/七/八 全部零命中 · 检查五 自绘容器 31 < 基线 32
结论: 通过 (覆盖 18/19，迁移期不判失败)

$ node tools/changelogcheck.js
更新说明页不存在 (App/UI/ChangelogView.swift) ⇒ 本闸门无事可做
```

> 另有两条**我自己写的一次性脚本**（不落盘、只在内存里跑）：① 按 `struct X: View` 正则统计出 96 个 View、109 个 .swift、46,146 行；② 对本文档 §1.3 表格逐行统计状态分布（活 111 / 半 10 / 死 21 / 缺 8 / 未读到 1 / 引用行 1）。这两个数是我算的，不是仓里的闸门给的。

## 附录 B · 我没读到 / 读不到的东西（不猜）

| 项 | 状态 |
|---|---|
| `App/Info.plist` 内容 | **文件不存在**（E1 `Test-Path` false），而 `project.yml:39` 的 `info.path` 指向它 ⇒ 版本号 / URL scheme 实际值**未读到** |
| `App/Intents/` 目录 | **不存在**（E1），但 `SpeechKit.swift:3`、`SecurityCenterView.swift:765`、`LockKeeperApp.swift:429` 三处仍在引用它 ⇒ 这些引用**当前是死指针** |
| `Widget/` 目录 | **不存在**（E1），`README.md:257` 仍写『含 927 的 OfflineLockWidget 扩展 target』 ⇒ 文档与仓不一致 |
| 真机 / 模拟器行为 | 本机无 Xcode / swiftc（E3：与 teammate 的 `INVENTORY-ANDROID.md:17-18` 同一结论） ⇒ 所有『看起来能用』的判断都只到代码层 |
| 安卓 UI 渲染 | 同上，无 gradle / emulator ⇒ 只能读 Compose 源码 |
| IDEA-BANK 1050 条逐条下落 | 只抽读，未逐条核（`featuremap` 已给分档，见 §1.4） |
| `HomeConsole` / `ManagerFace` / `Theme` / `Components` 的行号稳定性 | 这四份正在被并行改动（§0.2） ⇒ 引用时优先 grep 名字，行号只作辅助 |

## 附录 C · 与其它 teammate 产出的接口（如果他们先写完）

| 对方的文件 | 我这边依赖它什么 | 冲突风险 |
|---|---|---|
| `docs/GLASS/INVENTORY-IOS.md`（ios-inventory） | 逐页清点的行号可用来校正我 §1.3 的锚点 | 低：我只引用少量锚点 |
| `docs/GLASS/INVENTORY-ANDROID.md`（android-inventory） | §4 的安卓现状我已独立读过一遍，并与它 :32 的结论交叉验证一致 | 低 |
| `docs/GLASS/TOKENS.md`（已存在，13.5KB） | 它定色值/间距/圆角；我 §3.2 的模板选择**不依赖具体数值** | **无**：本文件一个数值令牌都不定义 |
| `docs/GLASS/DEVIATIONS.md`（已存在，12.6KB） | 它 §2 记的是 `ManagerFace` **玻璃 Tab 条 5 项** vs 规范 §7.10『3–4 项』的偏离；它 §5 记的是**没有展示壳层（A0 模板）** | **不冲突，且互相印证**：① 我 §3.2 的 5 是**域数**（sheet 面板里的 5 个分组），不是 Tab 项数 —— 面板不受 §7.10 的 3–4 项约束，但**如果将来把 5 个域做成底部 Tab 条，就会同时撞上它的 §2 偏离**，届时两条要合并成一条；② 我 §3.2 末『A0 一页都不用』与它 §5『本仓没有展示壳层』是同一结论，我这边是独立从规范 §8 + 仓内零位图资产推出的（E2 `tools/assetscheck.js` 的位图纪律） |


---

## §6 本文的边界

> 这一节回答一个问题：**读这份文件的人，凭什么信它，以及哪里不该信。**

### 6.1 证据分层：每条结论的来源

| 层 | 本文里有多少 | 具体是哪些 |
|---|---|---|
| **E1 · 我跑过命令并读到输出** | 12 条闸门 + 2 条自写脚本 | §0.1 与附录 A 全表：`destmap`（19→20）/ `destmap --json` / `featuremap`（A245·实现证据 730）/ `reach`（90 View·可达 89）/ `deadscan`（146）/ `keydead`（10 写不读 · 40 读不写）/ `deadfuncs`（148 零调用）/ `pagecraft`（98.8%）/ `uicoverage`（19=19 → 20=20，缝 18/19 → 18/20）/ `changelogcheck`（空转）。自写脚本两条：逐文件统计 **109 .swift / 46,146 行 / 96 个 View**；对本文 §1.3 表格逐行统计状态分布。 |
| **E2 · 我读了源码** | 152 条功能点的锚点、20 条诊断、5 个域的页面清单、迁移映射表全部 67 行 | 每条都给了 `文件:行`。**行号精度见 §0.2**：并行改动的文件按 HEAD 标注，其余按工作区。 |
| **E3 · 转述** | 3 处，全部写出处 | ① 安卓注释真实性 → `docs/GLASS/INVENTORY-ANDROID.md:32`（我只独立复核了『DesignSystem.swift 已删』这一点）；② 路径 C（`SecurityPage` 4 条 actionRow）→ `docs/GLASS/INVENTORY-IOS.md` 勘误 3（我随后用 E2 复核了 4 个调用点）；③ 无工具 / 无模拟器 → 与该 teammate 同一结论。 |
| **未读到** | 附录 B 七项 | `App/Info.plist` 内容（文件不存在）、`App/Intents/` 内容（目录不存在）、`Widget/` 内容（目录不存在）、真机行为、安卓 UI 渲染、IDEA-BANK 1050 条逐条下落、四份并行改动文件的行号稳定性。 |

### 6.2 我没有验证的（读的时候必须打折扣）

| 项 | 为什么没验证 | 影响哪些结论 |
|---|---|---|
| **152 条功能点的『用户价值一句话』** | 那是我按代码语义写的**判断**，不是用户访谈、不是埋点数据。仓里没有任何使用频次统计（`QuickPool.recordTap` 那套记录机制**零调用**，见 F-033 / G12）。 | §1.3 第 4 列全部 152 行；§3.2 里高频/低频的排序；§5 判据 ⑦ 的点击次数推算 |
| **分组方案在真机上的可用性** | 本机无 Xcode / swiftc / 模拟器 / 真机（附录 B）。5 个域的面板在 393pt 宽屏上是否挤、域内 7 项是否需要滚动、`XGlassTabBar` 5 项标签是否截断 —— **全部未验**。 | §3.2 域定义表；§5 判据 ③④⑦ |
| **迁移映射表会不会漏掉某个入口** | 我逐条读了 `ManagerFace`（21 路由）、`MePage`（20 链接）、`SecurityPage`（4 条 actionRow）、`destmap` 20 条目的地 —— 但这**只覆盖 4 条通道**。`HomeConsole` 自己的 4 个 `.sheet`、`LocksPage` 的行菜单、`MembersPage` 的 4 个底部入口、`ExportCenter` 的 12 个动作，我是按『它们属于哪一页』归的，**没有逐条列成映射行**。 | §3.3 的 67 条勾选项是**入口级**清单，不是**功能级**清单；少一条入口不会让功能消失，但会让『点几次能到』算错 |
| **死页下线会不会有人还在用** | `AlarmCenterView` / `BackupView` / `LockOverviewView` / `DeviceStripCard` 我判『零真实入口』，依据是 `deadscan` + 手查 `QuickPool` 是死函数。**我没有跑运行时验证**（没有模拟器）。 | §3.3-D 的『删除 6 类』里的第 ⑤ 项；§3.5 第 7 步 |
| **G20（访客闸失效）的严重度** | 我是从代码路径推的（5 个瓦片直接置 `managerGroup`，不过 `requestRoute`）。**没有在设备上开访客通道实测**。它也可能被别处的守卫拦住 —— 我查到 `guestBlockedTabs` 只在 `requestRoute` / `revokeSessionGrants` / `restoreLastTab` 三处读，**没有找到第四处兜底**，但这只是静态搜索。 | §2-G20；F-120；§3.3-D 新增第 ⑤ 项；§3.5 第 6b 步 |
| **域名字的最终取舍** | 我给了 2 沿用 + 3 改造，每条带理由。但『这台手机』这个名字是否比『外观与辅助』更好，**是产品口味问题，不是我能证伪的**。 | §3.2 域定义表；§5 判据 ⑥ |

### 6.3 一句必须写死的话：这是一份方案，不是既成事实

> **本轮我没有改一行源码。**
>
> 我唯一的产出就是这份 Markdown。`git status` 里那 20 个 `M` 的文件、`docs/GLASS/` 下的其它 6 个文件、`Destination.swift` 的 19→20，**没有一处是我写的**。
> 所以：**§3 的新 IA 方案目前是纸上的东西。** `App/UI` 里现在跑的仍然是 §2 诊断的那套（ManagerGroup 5 组 + MePage 20 条 + SecurityPage 4 条）。
>
> 这一轮 Lead 已经修掉的（E1 现场，均在 §2 对应行里标注了）：
>
> | 已修 | 在哪 | 本文对应行 |
> |---|---|---|
> | `MePage` 两条 `NavigationLink` 同指 `SecurityPage` | 第二条改指 `SecurityPeekView`（`MePage.swift:161`） | §2-G1 |
> | `.mergeMembers` 菜单名承诺一个不存在的落点 | 菜单名改『成员列表 / 合并从这里选人发起』（`ManagerFace.swift:143`） | §2-G2 |
> | `KeysPage` 回收站路径文案少一跳 | 补全为『管理 → 安全 → 销毁数据 → 回收站』（`KeysPage.swift:114-117`） | §2-G6 |
> | 卡片 / 圆环投影 → 辉光、页边距 16→14、卡片圆角 16→24、画布 `#0A0A0B`→`#000000` | `Theme.swift` / `Components.swift` | 不在本文范围（视觉层，见 `docs/GLASS/README.md` §1） |
>
> **未修结构**（等 §3 的方案拍板）：5 域重排、9 条重复入口收敛、回收站升域级、死页下线、G20 访客闸改判据。

### 6.4 如果要验证这份方案，最小的一步是什么

不要先做视觉，也不要先删页面。**先做这一步**：

```
给 HomeConsole 加一个隐藏的调试入口，用 5 个域枚举 + 一张「域 → 现有页面」映射表
把 ManagerFace 的 5 组换掉（不删任何旧路由，只换入口层）
然后在真机/模拟器上走一遍：每个域的每一项能不能到、要几步、回来顺不顺
```

理由：这样**零功能消失**（旧路由全留着），但 §5 判据 ③④⑦ 全部变成可观测的。等走通了再执行 §3.5 的第 5–7 步（删冗余、删死页）。

