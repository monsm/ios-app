# 离线锁管家 for iOS (全原生 SwiftUI)

智能锁离线管理端 — 对厂商原版 APK 的协议级 iOS 全原生移植。
针对最新 iOS 26 SDK 编译，**最低部署版本 iOS 26.5**，通过 GitHub Actions 云编译，本地无需 Mac。

界面按 iOS 26 平台原生设计语言实现：液态玻璃（Liquid Glass）、声明式 `Tab` 导航、
系统 `ContentUnavailableView` 空态、系统触觉反馈与符号动效。设计令牌集中在
`App/Core/DesignSystem.swift`（间距 4/8 节奏、圆角、44pt 触达、图标尺寸、动效时长、
明暗自适应语义色），页面不各自写死颜色与尺寸。

## 架构

```
App/Core/     协议与业务核心 (Swift 重写, 与已验证的 JS 核心做差分测试)
  HexKit        十六进制/字节工具
  AESKit        AES-128-ECB + ZeroPadding (CommonCrypto)
  ZKProtocol    0x87 帧 / KLV / 0x88 EKey 包络 / 令牌注入 / 三头型解析 / 粘包重组 / 广播解析
  ZKCmdBuilder  全部 40 条命令构造器 (01..25/30/31/32/35/38/41/43/44)
  ZOTP          临时密码 (冻结时钟差分验证)
  KeyGen        配网密钥族 (SecRandomCopyBytes CSPRNG)
  StatusParser  03 状态 / 16 日志解析 + rc 文案表
  PidMap        型号矩阵与能力开关 (布防/尾随/清密码/升级)
  Store         本地存储 (kf_* 键与小程序互通)
App/Services
  BLEService    CoreBluetooth: 扫描/连接/服务发现/20B 分片写/notify
  LockService   会话令牌生命周期 / 命令执行 / rc=3 自愈 / 配网编排 (23→05→01→08×4→21→03)
  HardwareService 蓝牙钥匙串 (cmd 41/43/44) + 网关 (cmd 30/31/35/38)
  DFUKit        ZIP 解析 + 原生 inflate + Nordic DFU (Secure FE59 / Legacy 1530) + cmd22 编排
  Attribution   开门归属推断 (R1 临时码窗口 / R2 唯一凭证+实时背书)
  BackupKit     全量备份包 + PBKDF2/AES-CBC/HMAC 信封 + 坚果云 WebDAV
App/UI        SwiftUI: 设备 / 凭证 / 记录 / 设置 4 Tab + 13 个功能页
Tests         XCTest 差分回归 — 与 fixtures/golden.json 逐字节断言
tools         golden.js — 用已验证的 JS 核心生成差分金标
vendor/app    已验证的 JS 业务核心 (仅用于生成金标, 不参与 App 构建)
```

## 为什么可信 (不要BUG)

协议、密码学、解析的每个原语都有**字节级差分测试**：
`tools/golden.js` 用经过 25 套 Node 测试验证的 JS 核心生成 40 条命令帧、
AES 向量（含 NIST）、状态/日志解析、广播解析、ZOTP（冻结时钟）、网关/钥匙串应答解析、
真实固件包解析等金标；云端 CI 只做**金标漂移校验 + 静态闸门 + 编译测试目标**
（macOS runner 上没有 iOS 模拟器，`xcodebuild build-for-testing` 只编译不执行），
逐字节断言要在装有 iOS 模拟器的机器上手动跑 `xcodebuild test` 才生效 —— 别把"CI 绿"当成"差分回归通过"。

## 云编译 (GitHub Actions)

推送到 GitHub 后自动构建 (macOS runner + 最新 Xcode):

```bash
git init && git add -A && git commit -m "feat: iOS native port"
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 三个作业, 一条依赖链 —— stamp 红了会"假装什么都没发生"

`stamp`(构建时刻) → `build`(iOS) 与 `android`(APK) 两个作业都 `needs: stamp`。
所以 **stamp 一红, 两端整个 skip**, 看上去"今天没编译", 其实是它先炸:

```bash
# 踩过的坑 (run 173/174): GNU date 的 -d 必须带 @ 前缀
date -d "@1792240940" +%Y%m%d.%H%M%S   # ✓ 20261017.204220
date -d "1792240940"   +%Y%m%d.%H%M%S  # ✗ invalid date —— 裸的 10 位秒数被当 YYYYMMDDHH 解析
```

回读校验那一步就是专门用来暴露这个的: 戳与 ts 换不回去 ⇒ 宁可红, 也不要产出
"包内号与文件名不是同一时刻"的两种 ipa 混在安装台上分不出来。

### CI 的判定为什么和行尾有关 (`core.autocrlf=true`)

CI 检出是 **LF**, Windows 工作区是 **CRLF**。闸门里有跨行正则 (`…[\s\S]*?\n    \}`) 与
`split("\n")` + `$` 剥行尾注释这类写法时, 同一份代码会在两边给出**不同结论**。
两次真实事故:

- `uicoverage` 在我本机报"1 处绕过漏斗的裸写换页", 指向 `RecordsTimeline.swift:450` ——
  实际那是**行尾注释里的历史说明**("(原写法置 tabSelection=3 无消费方)")。
  `split("\n")` 留着行尾 `\r`, 而 JS 的 `$` 不在 `\r` 前匹配 ⇒ 剥注释失效。CI 上是 LF, 不报。
- `kotlinshadow` 在 CI 报"A8 冷路径没先吃缓存句柄" (run 175), 本机全绿 —— 同一族行尾差异。

所以: **判断"这条红是不是我引入的", 要用与 CI 相同的 LF 树复现**, 别拿本机结论直接下:

```bash
git -c core.autocrlf=false archive HEAD | tar -x -C <空目录>   # 等价 CI 检出
# 再把未提交改动按 LF 覆盖进去 (改过的文件 readFileSync → replace(/\r\n/g,"\n") → 写回)
```

### 安卓的本地编译回路 (不必每轮等 CI)

`node tools/kotlinlocal.js` —— 用 gradle 缓存里的 `kotlin-compiler-embeddable` + SDK 的
`android.jar` 真编译**协议/链路那一层** (KfProtocol/AutoOpenKit/LockStore/BleUnlocker),
十几秒出结果。它编出 error 就退 1 (注入 run 169 那个真实错误验过开火), 缺工具链退 0 并说明。

- **覆盖不到 UI 层**: `MainActivity.kt` 要 Compose/androidx 的 aar, 本地 classpath 凑不齐,
  硬编只会刷一屏 Unresolved reference 噪音。UI 层与"真 APK 能不能装"仍只有 CI 判。
- 路径全走环境变量, 仓里不写死任何人的用户名或盘符:
  `KF_ANDROID_SDK` / `KF_GRADLE_CACHE` / `KF_JDK_HOME`。

```bash
# Windows 示例 (本机有 Android SDK 与跑过一次 gradle 才有这些)
set KF_ANDROID_SDK=<你的 SDK 根, 例如 %LOCALAPPDATA%\Android\Sdk>
set KF_GRADLE_CACHE=%USERPROFILE%\.gradle\caches\modules-2\files-2.1
set KF_JDK_HOME=<你的 JDK 21 根>
node tools/kotlinlocal.js
```

构建流水线 (`.github/workflows/ios.yml`):
1. `node tools/golden.js --check` — 已提交的 `fixtures/golden.json` 必须等于 JS 核心当前输出 (改了 vendor 却没重生成即失败)
2. `node tools/shadowdiff.js` — 影子对拍（第八道）。把 Swift 侧纯函数（`HexKit.bytes/reversePairs/asciiHex/u32leHex/fillZeroLeft`、`StatusParser.leHexToU32`、`ZKCmdBuilder.protoSecOrNil` 等）**手抄成语义等价的 JS 端口**，与 vendor JS 权威核心在 106 组输入上对拍；分四档：判失败 / 域外差异（非 hex、奇长、字节不够）/ 仅大小写（帧构造统一 `.uppercased()`，到不了字节面）/ 有意分歧（如纯数字字符串 JS 回落"现在"而 Swift 认下）。它**不替代** `xcodebuild test`：绿只说明"我读到的两边一致"
3. `for f in tools/*.js; do node --check "$f"; done` — 闸门脚本自己也是代码：先过语法检查（第七十批改 swiftlint 时就吃掉过一个右括号，那时无任何检查覆盖 tools/）
4. `node tools/swiftcheck.js && node tools/swiftlint.js && node tools/contrast.js && node tools/dynamictype.js` — Swift 括号/字符串平衡、结构粗检（十二项：同行合并语句 / 疑似臆造符号 / **Int64 与 Double 混比** / **存储层键值参数序** / **中文串里混进 ASCII 引号** / **写死纯白前景** / **UTC 日期当本地日用**——`.iso8601` 截前 10 位在 UTC+8 的早上会拿到昨天 / **机器面日期格式没钉 `en_US_POSIX`**——系统历法切成佛历或农历时 `yyyy-MM-dd` 会算出 2569 这类异 era 年份 / **直接对 `Calendar.current` 取年月日**——它本身就是用户历法那套日历，取分量一律走 `WeekCal.gregorian` / **手写 `protoSecondsToMs(…) / 1000`**——量纲藏在名字里，抄一次就漂出"秒比毫秒"，要 Unix 秒调 `protoSecondsToUnix` / **列表截断方向与增长方向相反**——`insert(at: 0)` 配 `suffix(N)`、`append` 配 `prefix(N)` 都会把刚存进去的最新一条挤掉（553 搜索历史就是这么丢词的）；确实不是"留最新 N 条"的截断（按序号夹长度之类），在截断行写 `方向口径：…` 销号。**界面把回收站天数写死**——文案里出现「回收站 …N 天 / 保留 N 天」判失败，因为 497 那个保留期是设置页 7~90 天的可调项，写死就在用户调小之后把安全网说大，而这句话恰好出现在按下就不可逆的那一刻；要闭嘴只有读 `CredentialOrg.reclaimDays()` 或写 `天数口径：<这是哪件事、出处在哪>`（364 的一键恢复窗口是另一件时间，代码里就写死 7 天）。后六条是第一百五十八→一百六十七批），对比度、动态字体/触达静态闸门。`swiftlint` 另有一档**顾问级、不进判决**：⑫ 秒与 `.at` 落在同一算式里相减就列线索（本仓 `.at` 有 epoch 毫秒与秒两套约定，静态判不出属于哪套），人读完在本行或紧邻上方写 `单位口径：秒`/`单位口径：毫秒` 销号，见 §10.34。扫描范围含 `App/`、`Tests/` 与 927 的 `Widget/`（第二个 target 不能裸奔）
5. `node tools/apisweep.js` — 需由框架提供的链式修饰符名清单（报线索不判失败，恒退出 0）。起因是第七十九批抓到 `.listItemSpacing` 这类臆造 API，而 swiftlint 检查② 只认大写类型名、对小写成员名整片失明。它**不进闸门判决**：判对错需要知道哪些小写名字是合法框架 API，那份名单离线拿不全，而误报的闸门比没有闸门更糟
6. `node tools/deadscan.js` — 零引用声明扫描（第六道）。它**报线索不判失败**（恒退出 0）：SwiftUI 协议成员、系统按名回调的入口都会天然"零调用"，需人工判定接线/删除/写清为什么留着，清单见 `docs/AUDIT-DEADCODE.md`
7. `node tools/citecheck.js` — 台账引用核查（第七道）。把 `docs/AUDIT-*.md` 里 `文件:行 + 摘录` 的引用拿去和源码比对，分开判"逐字摘录 / 符号级 / 行号漂 / 搜不到"。它同样**不判失败**：本仓 40+ 文件的行号在审计中漂移过，指针旧不等于结论错；但"搜不到/无此文件"必须逐条人读（防臆造引用）
8. `node tools/docpointers.js` — 台账**散文型**指针存活检查（第八十五批新增，顾问级、不判失败）：文档里提到的 Swift 文件名必须存在、
   抓"把文件名当类型名用"的形状（真实例子见 docs/AUDIT-CODE.md §96）、以及文件与类型都找不到的死指针候选。
   台账需要**引用**死指针原文时可以在行尾加 `指针检查:忽略` 注释标记 —— 一把天天在自己说明书上开火的尺子最后没人看。
   第一百七十批起，`Zprobe162.swift` / `_probe_tp.swift` 这一族**按名字形状豁免并单独报数**（注入探针按设计用完即删，
   文档里留的是"当时怎么验的"的历史，不是还该存在的文件）；形状很窄 (以 probe 为核心 + 可选 z 前缀/数字尾巴)，
   真·缺失文件照旧上报。同批读候选时抓到一处臆造类型名：文档写 `MemberActivityBoard.rows`，真名是 `MemberActiveTable` (§10.42)  <!-- 指针检查:忽略 (本行是在**引用**那个假名字本身, 不是指向本仓代码的指针) -->
9. `node tools/macpin.js` — 活读选中态检查（第八十七批新增，顾问级、不判失败）：同一个异步流程里跨 `await` 反复读
   `app.current?.mac ?? ""` 这种计算属性去写本机台账，会在当前锁被 AppIntent / `kf://` 深链改掉时"命令发向 A 锁、台账写进 B 锁"，
   而 `?? ""` 在锁为空时会静默写出没有锁的台账记录（最重的一条是清空整本密码台账）。修法统一是**入口钉住 + 非空才走**
10. `node tools/assetscheck.js` — 资源纪律检查（顾问级、不判失败）：219 位图只许待在 `appiconset`，界面图标一律走 `systemName`
11. `node tools/iconmap.js` — 图标一致性检查（顾问级、不判失败）：210 同一条标签文字必须配同一个图标基名
12. `node tools/keydead.js` — **假开关扫描**（第九十四批新增，顾问级、不判失败）：动词表从 `Store.swift` 现场解析，
    把每个 `kf_*` 键的读侧与写侧各数一遍，"只有写没有读"= 无人消费的备案，"只有读没有写"= 该键恒为默认值（设置页压根没有开关）。
    为了让报告不是噪音，判据认了四种"藏在水面下的存取"：键名常量别名（按宿主类型 + 所在作用域消歧，`HolidayFeed.autoKey`
    与 `SeasonIcon.autoKey` 是两个键）、**搬运函数**（`binding` / `setUnlockOption` / `setCodeRow→setCodeAlert`，按函数体认定并迭代到传递闭包）、
    单行 setter（`static func setElderMode(_ on: Bool) { DB.store.set(...) }` 只剥函数头不丢整行）、前缀族键单列一档。
    还认**「键口径：」销号标记**（第一百六十六批，与 swiftlint 的 `单位口径：`/`方向口径：`/`历法例外：` 同一族做法）：
    人读过并在写点写明理由（如 839 已判 PART 删档、只留清残留的写）的键进"已销号"一档，不再反复占名单。
    第一版判据漏掉这些时，53 条"只读不写"里有 47 条是假的——**包括应用锁安全族 389–398 全族**，那样一把尺子没人会信。
    定性完剩下的真缺口这一批已修：`kf_rssi_fence`(93 信号围栏) 与 `kf_trial_guard`(只读试验模式) 补上了真实开关入口，
    死键 `kf_sdest_trash`、零写入的 `kf_nfc_tags` 计数行改为如实标注
    **第一百五十六批加第四档**：同一个 `kf_*` 键被读出**多套字面量默认值** ⇒ 同一个值两套真相
    （设置页一档、别处另一档）。只认单行字面量 (数字 / 字符串 / true|false)：默认值写成 `BackupStudio.webdavRoot`
    这类属性的属于"走同一个口径"，第一版把它们也报出来时 2 条全是假的 (kf_webdav_root / kf_launch_line，逐条读代码排除)。
    现网 62 处带字面量默认值的读取点扫下来为 **0 冲突**；开火能力用两处注入探针证过 (`kf_probe_key` 5 vs 7 ⇒ 报 1 个)。
13. `node tools/featuremap.js` — **功能点覆盖台账**（第九十六批新增；分档结论顾问级、不判失败）：把 `IDEA-BANK` 的 1050 条
    与 `FEATURE-TRIAGE` 的判定、代码里的编号标注、`AUDIT-*/DEFERRED` 的逐条下落四处对齐。
    A 档之下现在分五格报：**A1**(标题词能搜到 ⇒ 多半是"做时没写编号") / **A0-x**(已划掉或**已合并到既有实现** ⇒ 不要重做) /
    **A0-w**(台账写明在等什么：等拍板·等一次真编译·等真机或 iPad ⇒ 条件不在本机) / **A0-d**(台账说已落、标注形式没被抓到) /
    **A0-t**(判 MISS/PART 且**没写下落** ⇒ 这一格才是真施工面) / **A0-u**(台账从未记过)。
    第一百六十三批改了四处判据 (下落词表、文档优先级、登记表行形状、"等编译"小节定性)：此前**历史审计的 MISS 行先被读到就定案**，
    DEFERRED 后来写的"已合并/挂起/等拍板"永远读不到 ⇒ 14 条施工面里 13 条其实早写下落，照着做就是把否决过的东西再做一遍。
    现在优先级是 **DEFERRED > VERIFY-CHECKLIST > ROADMAP-DRAFT > 历史审计，同文档内后写的行赢**，且每条 A0-x/A0-w 都带 `文件:行` 出处。
    判据自带**常驻分档自测**（14 条断言，含一条反控 #299 必须是"已落"）：默认就跑，不必加参数；
    台账或判据被改坏 ⇒ 打印 `✗ 分档回归` 并**退出 2**（第一百六十三批用"把 339 那行的编号改成 339x"证明它会开火，改回即恢复）。
    它自己先是被审出四处系统性错认（无界横杠区间 / 整行搜判定符号 / `:` 行号冒领编号 / `///` 吃掉强约定），
    修完才是能用的数：实现证据 924→828。**别把它当验收**：标注只是实现证据的一种形式，A 档里 35 条其实是"做时没写编号"
14. `node tools/changelogcheck.js` — **更新说明对账（43/44，判失败）**：设置页"新变化"的每一条都带一个功能编号，
    这条闸门拿它去问覆盖表"代码里有没有实现证据"，对不上就构建失败 —— 拍板口径是"内容锁死在真台账上"，
    所以这份清单在结构上说不出"没做出来的功能"。第九十八批已用注入探针证明它会开火
    （塞一条 `#15` 假条目 ⇒ 退出码 1）。它不证明界面长得对，那仍然只有真机能定论
15. `node tools/swiftshape.js` — **Swift 形状机检（第一百三十七批新增，判失败）**：四类不用编译器也能定形的编译错误 (R1/R2/R4/R5)，加一条只许减不许增的棘轮 (R3) ——
    R1 `: some View` 成员里有顶层 `if` 而没有 else/return 却缺 `@ViewBuilder`；R2 `@ViewBuilder` 挂到了返回 String/Int/Bool…
    的声明上。落地当批就在现网代码里抓到 **3 + 1 处**（`SettingsView/autoOpenSection` 那处正是 run 47 变红的形状）。
    **R4 (第一百四十八批)** 判"调用点的参数标签与声明对不上"——Swift 的标签是逐字匹配的，少写、多写、写错一个都不过编译，
    而这类代码名字眼熟、括号平衡，前面 14 道闸门一路放过。落地当批即在现网抓到 **13 处**：
    只判首参那版抓到 10 处
    （`RecordSearch.oid(mac:rowKey:)` 被 6 处按位置调用、`StatsView.legendRow(_ labels:)` 被 1 处写成 `labels:`、
    `LinkSense.successRateText(mac:)` 1 处、`RecordSearch.unhandledAlarmCount(macs:)` 2 处）；
    改成**逐位比对**之后又抓到 3 处 —— `CredentialStudio` 把 `CredentialOrg.firstUse/usageCount/openCountInWindow`
    的第二参标签 `p:` 全省了，那种只有看第二位才看得见。
    只判两种没有歧义的调用形状（`本仓类型.方法(` 与 同文件内不带点的 `方法(`），
    `.tag(date:)`/`Calendar.startOfDay(for:)`/`arr.remove(at:)` 这类 Apple 同名成员**不判** ——
    无差别扫描的上一版 210 条里 200 条是这种噪音；"实例调用 (`svc.read(from:)`)"也试过一轮，
    58 条命中逐条开代码看**全是假的** (`Array.remove(at:)`/`Path.move(to:)`/`String.range(of:)`/`Calendar.startOfDay(for:)`/
    `View.tag(_:)` 撞得上本仓某份唯一声明)，
    当场撤掉，理由写在 `r4()` 上方。这与 §10.11 里 `apisig.js` 被删是同族教训：天天误报的尺子最后没人信。
    判据自带正控 `fixtures/swiftshape/{fire,ok}`：该响的两条不响、或不该响的响了，`--selftest` 直接退 2。
    R4 的正控是四处有问题的调用报满 5 条 (少写 / 多写 / 第二个标签写错 / 同文件无标签声明被写成带标签)，
    反控包含 Apple 同名成员、带默认值的参数、闭包类型参数、两个标签都写对的调用与字符串里的假调用。
    **R5 (第一百五十一批)** 判"实参个数与声明对不上"(`missing argument` / `extra argument`)，与 R4 共用同一条流水：
    只判参数表里**既无默认值也无闭包类型参数**的声明 (那种函数写不出尾随闭包，个数是定死的)。
    本批现网 0 命中，正控在 `fixtures/swiftshape/fire/Arity.swift` (少参、多参各一条)，
    反控 `ok/Arity.swift` 放着"尾随闭包"与"带默认值"这两种看起来少一个、其实合法的写法。
    加它的过程反手打出自家判据两个 bug —— `->` 里的 `>` 被当括号把参数表在 `(Int` 处截断、
    零参声明不登记导致同名重载把**定义处**读成调用点 —— 两次都是反控先叫出来的 (§10.23)。
    三条豁免边界写在工具头注里 (`body` 协议自带 builder、没写显式类型的判不了、泛型内容槽 `Content: View` 合法)。
    **R3 (棘轮)** 数的是"持久化 struct 靠合成 Codable 解码 + 带着非 Optional 有默认值的字段 + 没有显式
    `init(from:)`"——给这种 struct 加字段会让旧 JSON `keyNotFound`、`DB.get` 返回 nil、界面上静静回落默认值
    (第一百三十七批在 `LockMeta.grp` 上真踩过一次，代价是"老用户整本锁档案看起来被清空"，见 §10.13)。
    基线 14 个，**只有新增才判失败**，往下调要改常量且工具会提示改成几。R3 第一版看不见单行写完的小 struct，
    是当场注入一个违规 struct 当探针打出来的 (常驻正控 = `fixtures/swiftshape/fire/CodableRisky.swift`)——
    没见过自己开火的尺子不算尺子。
16. `node tools/delsweep.js` — **删除点对账（第一百五十三批新增，顾问级、不判失败）**：台账里"本机删掉一条凭证"有 15 条路径，
    锁端那一半只有三种正当交代 —— 直发命令 (`pwdDelete`/`fpDelete`)、排一条待下发 (`enqueue "del_*"`)、换槽 (`pwdModify`)；
    第四种是**只动本机**，那必须在代码与界面上都写出来（声明写法：附近注释带 `撤权口径：`）。
    这一条不是判据而是**阅读清单**：±25 行的窗口是启发式，配对可能属于隔壁函数，所以"找到配对"那一档也要人读。
    落地当批把 2 处只动本机的路径（501 成员级联）写明，另外修掉一处真缺陷：撤销/还原**不收回待发的锁端删除**，
    于是刚恢复的凭证仍排在"下次连锁就删掉它"的队列里（§10.24/§10.25）。
    **第一百六十七批加第二张清单**：同一批汇点里只挑**界面上按下去就不可逆**的那些（`App/UI`、`App/Intents`，
    Core 层被谁调都不算），问的是另一件事 —— **有没有先问一句**。附近的 `confirmDestructive`/`.confirmationDialog`/
    `.alert(` 算一档，其余要就近写 `确认口径：<为什么这一刀不必问>`；两样都没有的逐条开代码。
    落地当批 15 处摊开：9 处正当（换槽 / 确认写在外层函数 / 319 那枚勾选项 / 归档向导的逐项决策 / 只清 `demo_` 前缀的样例），
    1 处真漏 —— 同一个「彻底删除」按钮，删最后一枚指纹要密码前缀双签，删**不止最后一枚**时直接 `action()`，
    双签的门槛分叉把"要不要问"整个问漏了（§10.39）。
    **第一百六十八批加第三张清单**：全仓每一个 `httpMethod = "DELETE"` 的远端删除点都必须就近写
    `删除面：<它只动哪一族对象>`，否则进名单交人读。起因是 `pruneRemote` 把 PROPFIND 列表里"超出 N 份"的条目
    一律删掉，而它读的 `webdavRoot` 默认值是整个坚果云根目录（§10.40）—— 这张表替不了"跨文件读默认值"这件事，
    但它保证任何一个新增的远程删除点都会被人当成一次必须交代删除面的机会。
17. `node tools/lockpair.js` — **改锁命令对账（第一百五十四批新增，顾问级、不判失败）**：与上一条同族、方向相反 ——
    每发一条会改锁状态的命令 (`pwdAdd`/`pwdDelete`/`setDefence`/`syncTime`…)，本机这一半要么跟着写
    (`DB.save*`/`DB.add*`/快照/队列/审计/敏感流水)，要么当场写 `留存口径：` 说明为什么不落本机 (例如"以锁端为准，本机只回读校验")。
    落地当批把 12 处待读摊开逐条读，读出一个真缺陷并收拢：**365 队列的执行代码曾被抄成三份**，
    而"缺载荷就中止、别发 0 号槽"那条修正只落在其中一份 —— 另外两份 (队列页 + **到场自动补发**)
    会把 `pwdDelete(别名 0)` 发出去，删掉的是别人的密码，回来还被标成"锁端确认" (§10.26)。
    第一百五十五批把它接成**双向**：反过来查"每一行 `DB.addPwd`/`DB.addFp` 的锁端来源在哪"
    (`pwdAdd`/`fpConfirm`/`pwdModify`/504 `queueRestore`/待下发队列，或代码里写明 `来源口径：`)，
    又读出同族的两处缺口：**496 版本恢复**与 **504 的批量还原/还原为副本** ——
    都是"界面报已还原、锁里却没这条"，现在排队与措辞都收进 `restoreBin`/`restore` 一处 (§10.27)。
    现网两向各 0 处待读 (改锁 26 处、台账写入 17 处，全部要么有配对要么写明口径)。
18. `node tools/typepred.js` — **日志类型分类对账（第一百五十七批新增，顾问级、不判失败）**：
    协议里告警只有 5 类、开门只有 5 类 (`docs/CAPABILITY.md:61`)，canonical 那份是 `StatsKit.alarmTypes` / `openTypes`。
    这一道数三种"同一分类被写了两遍"：① 手写 `type == 7 || type == 13 || …` 的或链 (与 canonical 同值 ⇒ 该引用集合；
    **是子集 ⇒ 这几类在这条路径上不当告警处理**，那就是真缺陷)；② 同一个字面量集合在两个文件各 `static let` 一份；
    ③ 定级表 `AlarmMeta.urgent∪serious∪info` 的并集与 `alarmTypes` 是否还相等。
    落地当批读出**两处真缺陷**：设备页"最近开门"与一个跨锁日志列表都自己写着 `7||13||224`，
    5 类告警只圈 3 类 ⇒ 低电量(6) 与试错锁定(10) 在这些屏上不变色、VoiceOver 也不念"告警："前缀，
    而同一条记录在告警中心 / 统计 / 导出里都算告警 (§10.29)。canonical 集合也从两份收成一份 (`LockStats` 改为别名)。
19. `node tools/autoopenshadow.js` — **AUTOOPEN 纯函数影子对拍（第一百七十一批新增，判失败）**：
    把 `defendActive / faceFresh / isStrict / armThreshold / disarmThreshold / rssiSample / p95`
    按 Swift 源码逐行复刻成 node，期望表逐条誊自 `Tests/AUTOOPENTests.swift` ⇒ 两侧语义漂开就红。
    为什么要有它：本仓 XCTest 从未执行 (§10.2)，结果是一份"可执行规格"里 **4 条断言与实现相反**、
    整张布防表又因测试 helper 的形参名说谎 (`utc(_ daySecond:)` 实际收的是半秒刻度) 而全错，挂了几个月没人看见 (§10.43)。
    ⚠ **它证明的边界**：只有这六个纯函数的算术。控制器时序、BLE 回调、`LAContext` 真弹窗、标定页交互
    仍然一行都没执行过 —— "影子对拍通过"不等于"测试跑过了"，报状态时两句话不许合并。
20. `node tools/zotpshadow.js` — **ZOTP 跨语言差分（第一百七十二批新增，判失败）**：
    `ZOTP.generate` 是临时密码那 6 位数字的算术，它唯一的验证本来是 `GoldenDiffTests.testZOTP`，而 XCTest 从未执行 (§10.2)。
    这一道把 Swift 侧 (`ZOTP` + `AESKit.encryptHex` + `HexKit.reversePairs/bytes`) 逐行复刻进 node (AES 用 node 自带 crypto)，
    再拿 vendor 基线生成的 `fixtures/golden.json` 四格对拍，另加三条不变式：冒号形 MAC 与无冒号形同码、
    畸形 MAC 返回空串、periodSec=0 落回 30 分钟。**改 Swift 侧任何一个字符级细节，这里要同步改**，否则差分在验旧代码。
    ⚠ 只证明算术一致 (含 MAC 一位不同 ⇒ 码就不同)，不证明真机上锁端认这个码；那要拿真锁试。
21. `node tools/cmdsshadow.js` — **ZK 命令帧跨语言差分（第一百七十三批新增，判失败）**：
    把 Swift 侧 `ZKProtocol` + `ZKCmdBuilder` 逐行复刻进 node，与 vendor JS 基线烘焙的 `fixtures/golden.json` **整帧逐字节**比对。
    覆盖 32/40 条；未纳入的 8 条由工具自己打印出来（`withToken`/`buildEkeyShare`/网关 5 条），不许让它看起来像全验过了。
    复刻过程中真正抓到的东西不是错字节，而是**极性核对**：`cmd18` 在 vendor 里参数叫 `vol`、在 Swift 里叫 `silent`、
    调用点又叫 `on` —— 三个名字一份语义，只有回读 `vendor/app/services/lock.js:412` 才确认三者同义（详见 §10.45）。
    时区：与 `golden.js` 一样无条件钉 `Asia/Shanghai`（夹具是按它烘焙的，日期串两侧都按设备本地解释）；
    不钉就会在 UTC runner 上出现 `from=-28800 → 0` 的**假红**。

22. `node tools/parseshadow.js` — **锁回字节的解析侧差分（第一百七十四批新增，判失败；第一百七十六批扩到钥匙串/网关）**：
    锁端状态那几组的输入与期望都取自 `fixtures/golden.json`（vendor 基线生成），算法逐行复刻自 Swift 的
    `ZKProtocol.parseResponse`/`parseKLV`/`parseAdv` + `StatusParser.parseStatus`/`parseLogEntry`/`truncatedLogCount`；
    另外 rc 词表 (27 条) 与 PidMap 型号表 (12 条) 是**直接解析 Swift 源文件**比出来的，不靠手抄。
    钥匙串 (cmd 43) 与网关 (cmd 38) 两种帧不在 golden.json 里 ⇒ 这两条**直接 `require` vendor 的
    `parseKCStatus`/`parseGWStatus` 当权威侧**，输入由工具构造、两边吃同一个对象（构造错只会让某条分支没被走到，
    凑不出假一致）。**35/35 组一致**（第一百七十六批加网关/钥匙串状态 14 组，第一百七十七批加 cmd 44 钥匙列表 6 组）；
    这一支新增时就抓到 Swift 与基线不一致并已修：
    `dotted(...)` 在长度不是 3 字节时把十六进制原样当版本号（基线一个留空、一个按 ASCII 解），
    以及网关 `0x02` 少了基线那半 ASCII 回退。口径差由工具自己打印：基线 kc 侧另有 `rc` 与 `applyPids`
    （`rc` 在 Swift 由调用方 `rcOf` 判，`applyPids` 基线自己也没有消费点）。未覆盖：手机侧失败行、缓存合并与分页游标。
    时区与 `golden.js` 同一颗钉子（`PARSE_SHADOW_TZ` 可覆盖）；放掉它会看到 `lockTimeStr` 差 8 小时的假红。

23. `xcodegen generate` 生成 Xcode 工程（含 927 的 `OfflineLockWidget` 扩展 target）
24. **编译校验测试目标** — 云端无模拟器，只 `build-for-testing` 不执行 XCTest（主 App 与 Widget 扩展都会在这一条真编译）
    > ⚠ **这一条现在是红的**：Actions 上 run 43 (2026-10-07) 之后连红四场 (run 44–47)，失败都在这一步。
    > 也就是说第 1–22 道本地检查**没有一道替代编译器**（swiftcheck 只数括号，swiftlint 的符号检查只认大写类型名，
    > swiftshape 到第一百四十八批才添了 R4 管"本仓函数的调用点标签"，实例调用与 Apple API 的名字仍然管不着），
    > 而 run 43 之后的改动从未被编译器看过。
    > 已定性的臆造 API 与修法见 `docs/AUDIT-CODE.md §10.11`；
    > 失败步骤现在会把 `error:` 行转成 annotations + job summary，下一场红自带诊断。
    > **读这份 README 的人请注意**：任何一批写"闸门全绿"，绿的是那 22 道，不含编译。
25. 注入编译号 (`注入编译号` 步骤; 由 `stamp` 作业那一个构建时刻派生, 见下) — 排在 `xcodegen generate` **之后**, 因为 Info.plist 是生成物
26. 真机未签名 IPA (`xcodebuild archive -sdk iphoneos CODE_SIGNING_ALLOWED=NO`)
27. 上传构建产物 (Actions → Artifacts → `OfflineLock-build`；`OfflineLock-build` 那份含日志与带时刻的 IPA)

## 编译号 = 构建时刻 (东八区, 一次 push 一个号)

`.github/workflows/ios.yml` 里 `stamp` 作业取一次 `date +%s`, 两个构建作业 `needs` 它 ——
**同一次 push 的 ipa 与 apk 共享同一个时刻**, 出问题能确定"这台手机上装的是哪一次 push"。
两个并行作业各自取 now 会差出几十秒 (archive 排在 build-for-testing 之后), 所以要单独算。

| 端 | 字段 | 取值 |
|---|---|---|
| iOS | `CFBundleVersion` (App **与 Widget 两份**) | `yyyyMMdd.HHmmss` (例 `20261017.184500`) |
| iOS | `CFBundleShortVersionString` | 保持 `1.0.0` (人认的产品版本; 变的是"构建"那一行) |
| 安卓 | `versionCode` | 距 `2026-01-01 00:00` (东八区) 的**秒数** |
| 安卓 | `versionName` | `1.0.yyyyMMdd.HHmmss` (与 iOS 的 CFBundleVersion 同一个串) |
| 产物名 | IPA / APK | `OfflineLock-<时刻>-unsigned.ipa` / `KfKey-<时刻>.apk` |

- ⚠ 安卓 `versionCode` **不能**用 `yyyyMMddHHmm`: 它是 32 位 Int (上界 2147483647),
  `202610171833` 已溢出 —— 不是"看着别扭"而是装不上。所以走"距基准秒数", 人读的那份放 versionName。
- 秒数口径同时解决**覆盖安装**: 号单调递增 ⇒ 新包总能盖旧包 (配合 `android-app/keystore/` 随仓库走的
  固定签名; CI 每次都是全新 runner, 默认 debug.keystore 每台不一样, 于是"装一次就不让升级")。
- 时区/格式只在 `stamp` 那一支算 (ubuntu = GNU `date -d`); macOS 没有 GNU 版 `date -d`,
  所以 iOS 那支直接用算好的字符串, 不再自己转换 —— 否则 BSD `date` 当场报错。
- `stamp` 作业最后一步把 stamp 反算回 ts 比对: 两端一致才放行 (不一致宁可红,
  也不要"包内号与文件名不是同一时刻", 那正是安装台上分不清版本的成因)。
- 本地手编 (无 `KF_BUILD_TS`) 回落"构建当刻" —— 单人开发时这就是最合理的号。

## 证据分三层，各管一件事 (缺哪一层都会出现"绿着绿着就红了")
| 层 | 载体 | 能判 | 判不了 |
|---|---|---|---|
| 形状 | `tools/*.js` 那 22 道 (含 `swiftshape.js` R1/R2/R3/R4/R5) | 括号/引号/参数序、缺 `@ViewBuilder`、属性挂到值类型、合成 Codable 雷区数量、**本仓函数的调用点参数标签与实参个数**、对比度与触达、编号是否有实现证据 | 类型不匹配、Apple API 名字不存在、实例调用 (`svc.read(from:)`) 的标签与个数 |
| 名字 | `docs/API-VERIFY.md` (撞 Apple 官方文档 JSON：撞页面 + 列父页成员) | 某个成员在当前 SDK 是否存在、是否被废弃 | 语义对不对、真机好不好看 |
| 眼睛 + 编译器 | `docs/VERIFY-CHECKLIST.md` (逐批列出只能真机验的项) 与 CI 的 `build-for-testing` | 一切 | —— |
> 当前状态：第三层的**编译器那一半是红的** (run 44–47 连红，最后一次绿 = run 43 / 2026-10-07)，
> 所以 run 43 之后写的每一行 Swift 都还欠一次真编译；`§10.11` 记着这件事的完整来龙去脉与已经抓到的四例。

## 安装到手机

未签名 IPA 需要自签 (免费 Apple ID 即可):
- **AltStore / SideStore**: 手机与电脑装 AltServer, 用 Apple ID 侧载 `OfflineLock-<时刻>-unsigned.ipa`
  (文件名里那个时刻 = 包内 `CFBundleVersion` = 安卓 `versionName` 后半段, 三份堆在桌面上时分得清)
- **Sideloadly**: 拖入 IPA + Apple ID 自动签名安装
- **Xcode** (如有 Mac): 打开 `xcodegen generate` 生成的工程直接跑真机

首次使用: 设置 → 蓝牙权限允许 → 添加设备 (先在门锁上做键盘重置)。

## 同步小程序侧业务改动

`vendor/app/` 是已验证 JS 核心的**冻结快照**（只保留 golden.js 依赖闭包内的 21 个文件）。
小程序侧 (`../miniprogram-app`) 协议/业务有改动时：把对应 .js 覆盖进 vendor/app 同路径，
然后 `node tools/golden.js` 重新生成金标——若 Swift 与 JS 行为出现分歧，差分测试会当场失败，
此时以 JS（真机验证过）为准修正 Swift。

## 2026-10-24 审美对齐专项（索引）

以 `tools/proto/`（iOS 51 页 + Android 6 页原型）为审美标准做过一轮全量对齐：
令牌三端同源、41 页页内大标题、卡解剖四层、16 张补卡、8 个入口 Bug、
2 个补原型（53-alarms / 06-airtag）。详细台账：

| 文档 | 内容 |
|---|---|
| `docs/AUTHORITY.md` | 权威顺序（HTML>规范）+ 31 道闸门分类 + 实证表 |
| `docs/GOAL-LEDGER.md` | 三大问题处理总账（60+ 轮）|
| `docs/PAGE-AUDIT.md` | iOS 50 页逐页审美台账 |
| `docs/ANDROID-AUDIT.md` | Android 6 屏逐屏台账 |
| `docs/NO-HTML-SCREENS.md` | 无原型界面处置清单（13/13 清零）|
| `docs/SUBTITLES.md` | 40 页副标题基线 |
| `docs/DEVIATIONS.md` | 30 条刻意偏离 HTML 的裁定 |
| `docs/ACCEPTANCE-GUIDE.md` | 真机验收三步指引 |
| `tools/REVIEW.html` | 56 项双端对照验收页 |

新增闸门：`entrygate`（入口可点性）/ `subtitlesync`（副标题基线）/
`reviewsync`（验收页一致性）/ `protosweep`（原型完整性）。
