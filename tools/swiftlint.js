// Swift 结构性粗检 (编译前闸门之二) — node tools/swiftlint.js
// 为什么单独有这一支: 本仓库至今没有真正跑过编译器 (见 docs/AUDIT-CODE.md §10.2)。
// 审计过程中我自己就犯过几类"编译器一秒就能抓到、人眼容易漏"的错:
//   ① 编辑时把函数体首条语句并到了 `func … {` 同一行 (Swift 需换行分隔语句);
//   ② 引用了一个仓库里根本不存在的类型 (DumpLineBinding);
//   ③ Int64 值拿去和 Double 时间戳比较 (本仓真实存在过 7 处);
//   ④ 存储层 Store.setCodable(键,值) 与 DB.setCodable(值,键) 参数序相反, 写反了 (抓到 5 处)。
//   ⑤ 中文串里混进 ASCII 双引号 —— 整行引号数仍偶数, swiftcheck 的平衡检查看不见, 编译器必拒。
//   ⑥ 写死的纯白前景 (hero/语义填充上的文字必须随主题与 863 反转换向, 第七十八→八十二批清了三轮仍有漏网)。
//   ⑦ 把 `.iso8601` (UTC) 截前 10 位当本地"今天"用 (第一百五十八批)。
//   ⑧ 机器面的日期格式没钉 `en_US_POSIX` —— 系统历法一换 (佛历/民国历/农历) 就算错年份 (第一百五十八批)。
//   ⑨ 直接对 `Calendar.current` 取年/月/日 —— 它本身就是用户历法那套日历，佛历下 `.year` 是 2569 (第一百五十九批)。
//   ⑩ 手写"协议秒绕回 Unix 秒" (`protoSecondsToMs(x) / 1000`) —— 量纲藏在函数名里，抄一次就漂出"秒比毫秒" (第一百六十批)。
//   ⑪ 列表"留最新 N 条"的截断方向与增长方向相反 (`insert(at: 0)` 配 `suffix`、`append` 配 `prefix`)
//      ⇒ 留下的全是最旧的 (第一百六十四批，553 搜索历史就是这么丢新词的)。
//   ⑫ (顾问级，见下一段) 秒与 `.at` 同式相减。
//   ⑬ 界面把回收站保留天数写死在文案里 —— 497 那枚 7~90 天可调项一旦被写成「30 天」，
//      用户调小之后安全网就被说大了，而那句话正出现在按下不可逆动作的时刻 (第一百六十七批)。
// 这十二条判失败的检查 (①—⑪ 与 ⑬) 就是为把这几类错变成机器可检的，不是装饰。
// 另有一档**顾问级、不进判决**：⑫ 把"秒与 .at 直接相减"的行列为线索 —— 本仓 `.at` 同时存在
//   epoch 毫秒 (`LedgerPwd`/`LedgerFp`/`MaintEvent`) 与秒 (`CredBinEntry`/`CredSnapshot`/`ClipboardCare`) 两套约定，
//   静态判不出某个 `at` 属于哪套 (要类型流)，所以只摆到人面前；与 ④ 的"两参都不像键"同一处理方式。
//   第一百六十二批的「智能列表·添加超一年」恒 0 条就是这一族 (见 §10.34)。
'use strict';
const fs = require('fs');

const files = [];
(function walkAll(dirs) {
  for (const d of dirs) {
    if (!fs.existsSync(d)) continue;
    (function walk(x) {
      for (const e of fs.readdirSync(x, { withFileTypes: true })) {
        const f = x + '/' + e.name;
        if (e.isDirectory()) walk(f);
        else if (f.endsWith('.swift')) files.push(f);
      }
    })(d);
  }
})(['App', 'Tests', 'Widget']);   // Widget = 927 扩展 target，必须同样受检

const readAll = files.map(f => ({ f, s: fs.readFileSync(f, 'utf8') }));
const strip = (line) => line
  .replace(/\/\/.*$/, '')                                   // 行尾注释
  .replace(/"(?:[^"\\]|\\.)*"/g, '""');                     // 字符串字面量整体摘掉 (含插值前缀)

// ---------- 检查 1: 声明头与函数体首条语句挤在同一行 ----------
let lineFail = 0;
const DECL_HEAD = /^(\s*)(?:@\w+(\([^)]*\))?\s+)*(?:public |private |internal |fileprivate |static |final |class |open |mutating |nonisolated )*func\s+[\w`]+\s*\(/;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    if (!DECL_HEAD.test(raw)) return;
    const brace = raw.indexOf('{');
    if (brace < 0) return;                      // 多行签名, 本行无 {
    const after = raw.slice(brace + 1).trim();
    if (!after || after.includes('}')) return;  // 空体或本行已闭合 → 合法
    if (/^(let|var|guard|if|for|while|repeat|do|switch|return|try|await|defer|throw|self\.|_\s*=)/.test(after)) {
      console.log(`同行合并语句 (Swift 需换行分隔): ${f}:${idx + 1}  ${raw.trim().slice(0, 100)}`);
      lineFail++;
    }
  });
}

// ---------- 检查 2: 引用了仓库内不存在、又不像系统类型名的标识符 ----------
const declared = new Set();
for (const { s } of readAll) {
  for (const m of s.matchAll(/\b(?:enum|struct|class|protocol|actor|extension|typealias)\s+([A-Z][\w]*)/g)) declared.add(m[1]);
  // 局部函数名一并收集 (仓库里有首字母大写的 private func, 命名不规范但不等于臆造符号)
  for (const m of s.matchAll(/\bfunc\s+([A-Za-z_][\w]*)/g)) declared.add(m[1]);
}
// 系统/框架类型前缀白名单 (粗粒度: 只认前缀, 宁可放过不误报)
const SYS_PREFIX = /^(NS|UI|CG|CA|MK|SK|AV|CB|CL|SE|PH|WK|MT|MF|SC|IN|CK|CN|EK|SF|BE|PK|MC|WC|KS|LS|GC|GK|RPS|CX|XE|MTK|CF|CT|CI|VN|CN|OS|AX|PK|SK|MK)/;
const SYS_NAMES = new Set(['AreaMark','LineMark','PointMark','RuleMark','BarMark','SectorMark','AxisMarks','Chart','UTType','DataRepresentation','Slider','AngularGradient','AxisGridLine','AxisMarks','AxisValueLabel','BGAppRefreshTaskRequest','BGTaskScheduler','BGTaskType','ByteCountFormatter','CCKeyDerivationPBKDF','CCPBKDFAlgorithm','CCPseudoRandomAlgorithm','CMMotionManager','DispatchSource','DispatchTime','EdgeInsets','EmptyView','GlassEffectContainer','PDFDocument','PointMark','RadialGradient','Substring','SymmetricKey','TapGesture','TextEditor','TimelineView','URLResourceValues','UnicodeScalar','XCTAssertGreaterThan','XCTAssertLessThanOrEqual','XCTAssertNil','XCTAssertNotNil','XCTFail','XCTAssertEqual','XCTUnwrap','BarMark','LineMark','RuleMark','RectangleMark','Platter','VStack','HStack','LazyHStack','ContentUnavailableView','ToggleStyle','ButtonStyle','String', 'Int', 'Int64', 'Int32', 'UInt8', 'UInt16', 'UInt32', 'Double', 'Float', 'Bool', 'Array', 'Set', 'Dictionary', 'Optional', 'Result', 'Error', 'URL', 'Data', 'Date', 'Timer', 'Calendar', 'Locale', 'TimeZone', 'UUID', 'Any', 'AnyView', 'View', 'Text', 'Font', 'Color', 'Image', 'CGFloat', 'CGRect', 'CGPoint', 'CGSize', 'IndexPath', 'IndexSet', 'Character', 'Unicode', 'Comparable', 'Equatable', 'Codable', 'Decodable', 'Encodable', 'Identifiable', 'Hashable', 'Sendable', 'MainActor', 'Task', 'SwiftUI', 'Combine', 'Foundation', 'Security', 'CryptoKit', 'CommonCrypto', 'CoreBluetooth', 'Charts', 'UniformTypeIdentifiers', 'UserNotifications', 'ObjectiveC', 'Dispatch', 'UserDefaults', 'NotificationCenter', 'JSONEncoder', 'JSONDecoder', 'SHA256', 'Logger', 'Mirror', 'Swift',
// WidgetKit (927 哑按钮扩展 target): 这些系统 API 在仓库里各只出现 1–2 次, 正好落进本检查的误报形态。
// 加白名单**不等于**证明我写的 WidgetKit 用法正确 —— 那只有编译器能定论, 见 docs/VERIFY-CHECKLIST.md 的 927 条。
'Timeline', 'TimelineEntry', 'TimelineProvider', 'StaticConfiguration', 'WidgetConfiguration', 'WidgetBundle', 'WidgetFamily',
// 585 记录引用深链要读 `kf://records?k=<行键>` 的查询参数。URLComponents 是 Foundation 自带的 URL 解析器
// (iOS 7 起)，加白的理由是**替代方案更差**: 自己 split("?"/"&") 就等于手写一个不处理 % 转义、
// 不处理重复键、不处理 `#fragment` 的解析器 —— 而这条路径是深链入口，写错的代价是"链接能开门却定位错行"。
// 与 WidgetKit 那批同理: 加白不等于证明用法正确，深链落地的真机验证在 docs/VERIFY-CHECKLIST.md 的 585 条。
'URLComponents',
// 14 月度热力格用 LazyHGrid 画 7 行 × 周列。它是 SwiftUI 自带网格 (iOS 14 起, 与名单里已有的
// LazyHStack 同类)，全仓只此一处所以撞上本检查的误报形态；加白不等于证明布局正确，
// 格距与密度看真机 (14 的验收项)。
'LazyHGrid',
// 392 伪装空壳的长按逃生口 (2026-10-15 走查·行 LIII): 从 `DragGesture(minimumDistance: 0)` + 比时间戳
// 换成 `LongPressGesture(minimumDuration:)` —— 后者才是"按住够久即 onEnded"的那个契约。
// Apple 文档: SwiftUI.LongPressGesture, iOS 13 起, 初值签名就是 `init(minimumDuration: Double)`,
// 且文档自己的示例正是 `LongPressGesture(minimumDuration: 3)`。全仓只出现 2 次 (一次代码一次注释)
// ⇒ 撞上本检查的误报形态。加白**不等于**证明逃生口按 3 秒真的落锁 —— 那仍要真机核对 (交接书 §7.9 卡 9)。
'LongPressGesture',
// 77/939/941 开锁实时活动 (ActivityKit, iOS 16.1 起) 与 826 聚光教练用到的 SwiftUI 布局/绘制类型。
// 全仓各只出现 1 次, 正好落进本检查的误报形态; 与上面几批同理: **加白不等于证明用法正确** ——
// 真机验证在 docs/VERIFY-CHECKLIST.md (实时活动那条与聚光教练那条)。
'ActivityAuthorizationInfo', 'ActivityConfiguration',   // ActivityKit: 权限查询 + 活动配置
'VStackLayout', 'HStackLayout',                          // SwiftUI Layout: AnyLayout 的两种容器 (859)
'FillStyle',                                             // SwiftUI Canvas 填充规则 (eoFill 挖洞, 826)
// LazyVGrid 的列描述符。SwiftUI 自带 (iOS 14 起, 与名单里已有的 LazyHGrid 同类)。
// 2026-10-27 四轮删掉临时码工坊的五场景预设后，全仓用量从 4 处掉到 2 处，
// 于是撞上本检查「只出现 1–2 次且未声明」的误报形态。
'GridItem',
// 编译修复批 (1170/1255/150): 三个真实 Apple 符号, 全仓各只出现 1 次, 正好落进本检查的误报形态。
//   · DispatchSemaphore — Foundation 自带的并发原语。DiagKit 1170 用它把 async 的
//     `notificationSettings()` 拉回同步体检闭包 (体检项 run 是同步闭包, 不改成 async 是为了不动视图层)。
//   · CHHapticEngine — CoreHaptics 的引擎入口。DiagKit 1255: 系统没有任何"触感开关"的公开读取口,
//     `UIImpactFeedbackGenerator` 也没有 isEnabled (原写法编译不过), 能问的只有硬件是否支持触感。
//   · Insecure — CryptoKit 里 SHA1 的命名空间。CredentialStudio 150: HMAC-SHA1 是 TOTP 的默认档,
//     原写法 `HMAC<SHA1>` 里 `SHA1` 这个顶层名并不存在。
// 与上面几批同理: **加白不等于证明用法正确** —— 编译器才是判定方。
'DispatchSemaphore', 'CHHapticEngine', 'Insecure',
// SymbolEffectOptions — SwiftUI 的 symbolEffect 选项类型 (iOS 17 起)。run 63 修 UnlockDial 的
// "unable to type-check this expression in reasonable time" 时, 把 `.repeating` 写成显式
// `SymbolEffectOptions.repeating` 帮编译器消歧, 于是全仓出现 2 次, 正好落进本检查的误报形态。
// 2026-10-14: Security 框架的 Keychain 读写四个入口 (App/Core/SecretStore.swift)。全仓各只出现 1–3 次
// (单文件封装、经 set/get/remove/removeAll 收口, 不会在别处反复出现), 正好落进本检查的误报形态。
// 加白**不等于**证明 Keychain 用法正确 —— SecItemUpdate 的返回码分支、kSecAttrAccessible 访问级别、
// 以及"写失败不抹 plist 明文"那条, 都只有真机能验 (见 docs/VERIFY-CHECKLIST.md 的密钥迁 Keychain 条目)。
// SymbolEffectOptions — SwiftUI 的 symbolEffect 选项类型 (iOS 17 起), 上面已有注释, 这里补回名字。
// UnevenRoundedRectangle — SwiftUI 的"四角不同圆角"矩形 (iOS 16.4 起)。域浮层只用它两处
// (顶角圆、底角方), 正好落进本检查"全仓 1–2 次"的误报形态。
// 依据: Apple 文档 `swiftui/unevenroundedrectangle/init(topleadingradius:bottomleadingradius:
//   bottomtrailingradius:toptrailingradius:style:)` —— 参数名与顺序照抄, 不是凭记忆拼的。
// ⚠ 加白不等于它编得过: 本机无 Xcode, 只能靠 CI 编译定案 (与 SymbolEffectOptions 那条同口径)。
'SecItemAdd', 'SecItemUpdate', 'SecItemCopyMatching', 'SecItemDelete', 'SymbolEffectOptions',
'UnevenRoundedRectangle',
// FileWrapper — Foundation 的「把一段数据包成文件」类型, 配合 SwiftUI 的 FileDocument 做
// fileExporter (App/UI/BackupView.swift 的 iCloud 文件备份)。全仓只此一处 ⇒ 落进本检查的误报形态。
// 用法依据: Apple 文档 Foundation/FileWrapper/init(regularFileWithContents:) 与
// FileDocument/fileWrapper(configuration:) —— 都是必须实现的协议方法, 不是凭记忆拼的。
// 加白不等于它编得过: 本机无 Xcode, 只能靠 CI 编译定案。
'FileWrapper',
// Thread — Foundation 的"现在是不是主线程"判据 (`Thread.isMainThread`)。用得少是因为全仓只该有
// 一处需要它: BLEService.publishOnMain —— 2026-10-17 真机崩溃 (Thread stack size exceeded,
// 栈里 Published.setter ← 一个 Task 续体, body ← NavigationStack.init(root:)) 的修复点。
// 为什么非要问这一句: Combine 在哪个线程 emit, SwiftUI 就在哪个线程**同步**重算 body ——
// 非隔离 async 函数 (connect()) 的续体落在 cooperative 线程 (栈 ≈512KB), 直接写 @Published
// 就会把整棵根视图的 body 拉到那条小栈上算。已在主线程时不跳队列是刻意的 (少一次异步,
// 免得 `scanning = false` 这类状态在下一帧才可见)。
// 与上面几批同理: **加白不等于用法正确** —— 编译器才是判定方。
'Thread',
// 2026-10-26: UserNotifications 框架的两个类。功能精简删掉了 BackupStudio 里的
// UNDelegate（通知分派）之后，这两个类型在全仓正好降到「只出现 2 次」，
// 于是被上面那条"1–2 次且未声明 ⇒ 疑似臆造"的规则误判。
// 它们是真的系统 API（BatteryCare 排低电提醒、CredentialOrg 排临期提醒都在用）。
'UNMutableNotificationContent', 'UNCalendarNotificationTrigger']);

let symFail = 0;
// 判定口径: 只报"全仓库只出现 1–2 次、又不是本仓库声明的类型"的驼峰名 ——
// 臆造符号的特征就是**只在这一处出现过** (DumpLineBinding 正是如此);
// 系统 API (HStack/XCTAssert*/Bundle…) 会反复出现或被前缀白名单挡掉, 不用维护长名单。
const freq = new Map();
for (const { s } of readAll) {
  for (const m of s.matchAll(/\b([A-Z][A-Za-z0-9_]{5,})\b/g)) freq.set(m[1], (freq.get(m[1]) ?? 0) + 1);
}
const reported = new Set();
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const t = strip(raw);
    for (const m of t.matchAll(/(?<![\w.])([A-Z][A-Za-z0-9_]{5,})(?=[.([])/g)) {
      const nm = m[1];
      if (declared.has(nm) || SYS_NAMES.has(nm) || SYS_PREFIX.test(nm)) continue;
      if ((freq.get(nm) ?? 0) > 2) continue;      // 反复出现 → 大概率是框架 API
      const key = nm + '@' + f;
      if (reported.has(key)) continue;
      reported.add(key);
      console.log(`疑似臆造符号 (全仓仅出现 ${freq.get(nm) ?? 1} 次且未声明): ${f}:${idx + 1}  ${nm}   | ${raw.trim().slice(0, 80)}`);
      symFail++;
    }
  });
}

// ---------- 检查 3: Int64 与 Double 混比 (本仓真实存在过 7 处, 全是编译器会当场拒绝的) ----------
// 起因: ZKProtocol.protoSecondsToMs 返回 Int64, 而 epoch 比较的另一侧几乎都是 Double
// (timeIntervalSince1970 / nowSec)。Swift 不做隐式数值转换, `let t = protoSecondsToMs(x)/1000`
// 再拿去和 Double 比就是硬错误 —— 第三十九批在 CredentialOrg 里一次抓到 6 处 (含一处把 Int64 传给
// 形参 Double 的 `inWindow(p, at: t)`)。正确写法仓库里已有先例: Double(protoSecondsToMs(x)) / 1000。
const DBL_TOKEN = /timeIntervalSince1970|nowSec|epochSecs/;
let numFail = 0;
for (const { f, s } of readAll) {
  const lines = s.split(/\r?\n/);
  // 以 func 为界切块 (按花括号深度), 只在同一函数体内判断"Int64 变量被当 Double 用"
  let start = -1, depth = 0;
  const blocks = [];
  lines.forEach((raw, i) => {
    if (start < 0 && /^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate |static |final |class |open |mutating |nonisolated )*func\s+/.test(raw)) start = i;
    if (start < 0) return;
    const t = strip(raw);
    depth += (t.match(/{/g) || []).length - (t.match(/}/g) || []).length;
    if (depth <= 0) { blocks.push([start, i]); start = -1; depth = 0; }
  });
  for (const [a, b] of blocks) {
    const intVars = new Set();
    for (let i = a; i <= b; i++) {
      const t = strip(lines[i]);
      const m = t.match(/\blet\s+([a-z]\w*)\s*=\s*(?:ZKProtocol\.protoSecondsToMs\(|ZKProtocol\.protoSecondsFromMs\()/);
      if (m && !t.includes('Double(') && !t.includes('TimeInterval(')) intVars.add(m[1]);
    }
    if (!intVars.size) continue;
    for (let i = a; i <= b; i++) {
      const t = strip(lines[i]);
      if (/\blet\s+[a-z]\w*\s*=\s*(?:ZKProtocol\.protoSecondsToMs\(|ZKProtocol\.protoSecondsFromMs\()/.test(t)) continue;
      for (const v of intVars) {
        // 已显式包好的 Double(ms) / TimeInterval(ms) 不算混用, 别误伤正确写法 (StatsKit:16 就是对的)
        const t2 = t.replace(new RegExp(`(?:Double|TimeInterval|Float|Decimal)\\(\\s*${v}\\s*\\)`, 'g'), 'WRAPPED');
        const used = new RegExp(`(?<![\\w.])${v}(?![\\w(])`).test(t2)
          || new RegExp(`,\\s*\\w+:\\s*${v}\\b`).test(t2);   // 形参传递 (inWindow(p, at: t))
        if (!used || !DBL_TOKEN.test(t2)) continue;
        console.log(`Int64 当 Double 用 (protoSecondsToMs 返回 Int64, 需 Double(...) 包一层): ${f}:${i + 1}  ${lines[i].trim().slice(0, 90)}`);
        numFail++;
        intVars.delete(v);
        break;
      }
    }
  }
}

// ---------- 检查 4: 存储层键/值参数序颠倒 ----------
// 两套入口的顺序是**相反**的: Store 实例 = set(键, 值) / setCodable(键, 值), DB 静态 = setCodable(值, 键)。
// 混用的后果分两种, 第二种更贵: 值不是 String 时编译器当场拒 (第五十四批一次抓到 5 处, 其中两处是我自己
// 上一批写的 186/188 备注与标旗写入); 值恰好是 String 时**静默存成错误的键**, 开关看着能拨、数据永远读不回来。
// 判定口径按 keycheck 的教训收紧 —— 只在"首参不像键、次参像键"时判失败:
//   像键 = 以字符串字面量起头 ("kf_x" 或 "kf_x" + mac) / 名字含 key|Key / 形如 kXxx 的键常量。
// 两参都不像键 (如 set(marker, true)，marker 恰好是键名) 静态判不了, 不判失败, 只报总数交人读。
const keyish = a => /^"/.test(a) || /key|Key/.test(a) || /^k[A-Z]/.test(a);
function topLevelArgs(inner) {
  const out = []; let d = 0, q = false, cur = '';
  for (const c of inner) {
    if (c === '"') { q = !q; cur += c; continue }
    if (!q && '([{'.includes(c)) d++;
    if (!q && ')]}'.includes(c)) d--;
    if (!q && c === ',' && d === 0) { out.push(cur.trim()); cur = ''; continue }
    cur += c;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}
let orderFail = 0, orderBlur = 0;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const line = raw.replace(/\/\/.*$/, '');      // 去掉行尾注释, 保留字符串
    for (const m of line.matchAll(/\b(?:DB\.store|Store\.shared)\.(setCodable|set)\(/g)) {
      // 截到本次调用的配对右括号为止, 不把外层 ) 混进第二个实参
      let inner = '', d = 1;
      for (const c of line.slice(m.index + m[0].length)) {
        if (c === '(') d++;
        if (c === ')') { d--; if (d === 0) break }
        inner += c;
      }
      const args = topLevelArgs(inner);
      if (args.length !== 2) continue;
      if (!keyish(args[0]) && keyish(args[1])) {
        console.log(`存储层键/值参数序颠倒 (Store 层是 (键, 值)): ${f}:${idx + 1}  ${m[1]}(${inner.trim().slice(0, 70)})`);
        orderFail++;
      } else if (!keyish(args[0]) && !keyish(args[1])) orderBlur++;
    }
  });
}

// ---------- 检查 1b: 类型声明头的 `{` 后紧跟首条成员 ----------
// 同一类错误的另一半: 检查① 原来只盯 `func`, 而我实际犯的第二次是把 `let item: ExportItem`
// 并进了 `struct ExportTextFile: Transferable {` 同一行 (Edit 吃掉换行)。类型体同样需要换行分隔。
let typeFail = 0;
const TYPE_HEAD = /^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |internal |fileprivate |final |indirect )*(?:struct|class|enum|actor|extension)\s+[\w`][^{]*\{(.+)$/;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const m = TYPE_HEAD.exec(raw);
    if (!m) return;
    const after = m[2].trim();
    if (!after || after.includes('}')) return;               // 空体或本行已闭合 → 合法
    if (/^(let|var|func|init|deinit|typealias|case|static|class\s+func|enum)\b/.test(after)) {
      console.log(`类型体首条语句与声明头挤在同一行: ${f}:${idx + 1}  ${raw.trim().slice(0, 100)}`);
      typeFail++;
    }
  });
}

// ---------- 检查 5: 中文串里混进 ASCII 双引号 (swiftcheck 看不见的那一半) ----------
// 起因: 第七十一批我自己写出 `detail: "…退回"积累中"。…"` —— ASCII 引号把字面量关掉又开回来,
// **整行引号数仍是偶数**, 所以 swiftcheck 的平衡检查完全无感, 而 Swift 编译器当场拒。
// 判据 (刻意收窄到几乎不可能误报): 一个**未被转义**的 ASCII 双引号, 左右紧邻的都是中日韩字符。
// 合法 Swift 里这种形状只能来自"字符串已经结束后紧跟汉字"= 本就是语法错误; 中文正文里的引用一律写「」。
// 注释里的中文引号是合法的, 所以先按字符串状态切掉行尾注释, 并跳过整行注释。
const isCJK = (p) => (p >= 0x3000 && p <= 0x303F) || (p >= 0x3040 && p <= 0x30FF) ||
                     (p >= 0x4E00 && p <= 0x9FFF) || (p >= 0xFF00 && p <= 0xFFEF);
// 返回本行"代码部分" (丢掉顶层 // 之后的注释; 字符串里的 // 不算注释起始)
function codePart(line) {
  let inStr = false, esc = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (esc) { esc = false; continue; }
      if (c === '\\') { esc = true; continue; }
      if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}
let quoteFail = 0;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const code = codePart(raw);
    for (let i = 1; i < code.length - 1; i++) {
      if (code[i] !== '"' || code[i - 1] === '\\') continue;
      if (isCJK(code.charCodeAt(i - 1)) && isCJK(code.charCodeAt(i + 1))) {
        console.log(`中文串里混进 ASCII 引号 (字面量被截断, 编译器必拒): ${f}:${idx + 1}  ${t.slice(0, 100)}`);
        quoteFail++;
        break;
      }
    }
  });
}

// ---------- 检查 6: 写死的纯白前景 (第八十三批把这一类扫到只剩两个有据可查的例外) ----------
// 起因: hero 面与语义填充上的文字必须**随主题/明暗/863 反转**换向 (DS.heroFg / DS.Palette.onSem),
// 而写死的 .white 在深色档语义填充上实测只有 1.67~2.77:1、在反转降级后的浅 hero 上是 1.07:1。
// 这一类第七十八→八十二批清了三轮才清完 (每轮都有漏网), 所以留一条静态守卫而不是靠人记住。
// 口径: 只认"直接以纯白作前景/填充"的四种写法; `.white.opacity(x)` 的纹理与柔光不在本检范围
//       (它们压的是装饰层, 且都在 heroScrim 之下, 由 tools/contrast.js E4 的叠层算式核)。
// 允许名单是**上限**而不是清单: 只能减不能加, 每个名额都要写明为什么白在这里是对的。
const WHITE_CEIL = {
  'App/Core/AccessibilityKit.swift': 1, // heroFg 的定义本身 (唯一的合法纯白出处)
  'App/UI/SettingsView.swift': 1,       // 图标预览块的白符号: 底是写死的深色渐变, 机检 E6 ≥5.00:1
  // PDF / 分享长图的封面文字: 输出面压的是 heroA/heroB 渐变, 比值由 contrast.js B/C 节按
  // "每主题 × 明暗 × 两端" 机检 (≥4.5:1)。位图一旦生成就不再随系统反转/主题变化, 所以这里的
  // 纯白是**正确的**, 不是漏网 —— 但名单只允许往下减: 新增名额必须先证明底色仍是那批被检的深渐变。
  'App/UI/ExportCenter.swift': 7,
};
const RE_WHITE_FG = [
  /\.foregroundStyle\((?:Color)?\.white\b/,
  /\.foregroundColor\((?:Color)?\.white\b/,
  /\.tint\((?:Color)?\.white\b/,
  /\.fill\((?:Color)?\.white\b/,
  /color:\s*(?:UIColor)?\.white\b/,
  /\?\s*(?:Color)?\.white\s*:/,
  /:\s*(?:Color)?\.white\s*(?=[,)\s}])/,
];
const whiteSeen = {};
let whiteFail = 0;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const code = codePart(raw);
    if (!/\.white\b/.test(code)) return;
    if (!RE_WHITE_FG.some((re) => re.test(code))) return;
    whiteSeen[f] = (whiteSeen[f] || 0) + 1;
    const ceil = WHITE_CEIL[f] === undefined ? 0 : WHITE_CEIL[f];
    if (whiteSeen[f] > ceil) {
      console.log(`写死纯白前景 (应走 DS.heroFg / DS.Palette.onSem / onAccent): ${f}:${idx + 1}  ${t.slice(0, 100)}` +
                  (ceil ? `  [本文件上限 ${ceil} 已用尽]` : ''));
      whiteFail++;
    }
  });
}

// ---------- 检查 7: 用 `.iso8601` 取"日期" (第一百五十八批) ----------
// 起因: `Date().formatted(.iso8601)` 走的是 **UTC**。本仓有两处把它当本地日 key 用:
//   · `DiagKit.gapDays` 一边取日志的锁端墙上日期 (`lockTimeStr.prefix(10)`)、一边取 UTC 日期比 ——
//     UTC+8 的用户每天 00:00–08:00 会拿到"昨天"，于是 451 空洞检测既报假洞又漏真洞;
//   · 诊断日志的"今天"与保留期 cutoff 同样按 UTC 分日。
// 判据收窄到一种几乎不可能误报的形状: `formatted(.iso8601)` 之后接 `.prefix(10)` (取日期那一段)。
// 真正的 ISO 时间戳 (带 Z、用于跨端交换) 不会去截前 10 位当本地日用，所以这一条不判"用了 .iso8601"，只判"截它当日期"。
let utcFail = 0;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const code = codePart(raw);
    if (!/\.iso8601\)/.test(code) || !/\.prefix\(\s*10\s*\)/.test(code)) return;
    console.log(`UTC 日期当本地日用 (.iso8601 是 UTC，.prefix(10) 取的是它的日期段): ${f}:${idx + 1}  ${t.slice(0, 100)}`
                + '  → 用 StatsKit.dayKey / DiagLogs.localDay');
    utcFail++;
  });
}

// ---------- 检查 8: 纯数字日期格式没钉 en_US_POSIX (第一百五十八批) ----------
// 起因: iOS「设置 → 语言与地区 → 历法」可以选佛历/民国历/农历等非公历。`DateFormatter` 不钉
// locale 时跟随系统历法 ⇒ 同一个 `yyyy-MM-dd` 在佛历用户手机上输出 "2569-10-10"。
// 本仓有 3 处因此算错 (节日限定色、春节底带、连续开门天数)，见 §10.30。
// 判据只圈**机器面**的形状: 格式串全 ASCII 且含 y/M/d 字段 (给人看的会写 "yyyy年M月d日"、"M月d日")。
// 给这种格式补 `en_US_POSIX` 对公历用户是逐字节同值的，所以不存在"为了过闸门把显示改坏"的代价。
// 组 = 从 `dateFormat` 行往前找到 `= DateFormatter()` (最多 3 行)、往后到 `return`/`}`/下一处 dateFormat。
let calFail = 0;
const DATE_RUN = /^[yMd]+$/;                       // yyyy / yy / MM / M / dd / d
for (const { f, s } of readAll) {
  const L = s.split(/\r?\n/);
  L.forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const m = raw.match(/dateFormat\s*=\s*"([^"]*)"/);
    if (!m) return;
    const pat = m[1];
    if (/[^\x20-\x7e]/.test(pat)) return;                     // 带中文装饰 = 给人看, 归用户 locale
    const runs = (pat.match(/[A-Za-z]+/g) || []).filter(r => !/^M{3,}$/.test(r));
    if (!runs.some(r => DATE_RUN.test(r))) return;            // 纯时间格式 (HH:mm) 与本判据无关
    let a = idx;
    while (a > 0 && !/=\s*(?:Date)?Formatter\(\)/.test(L[a]) && idx - a < 3) a--;
    let b = idx;
    while (b + 1 <= Math.min(L.length - 1, idx + 4)) {
      b++;
      if (/^\s*(?:return|[}\]])/.test(L[b]) || /dateFormat\s*=/.test(L[b])) { b--; break; }
    }
    const grp = L.slice(a, b + 1).join('\n');
    // 组内所有 locale 赋值逐个看: 后写的覆盖先写的 ⇒ 只要有一个不是 POSIX 就判，
    // 免得"补了一行 POSIX、上面那行 zh_CN 又把它盖回去"这种改法蒙过闸门 (第一百五十八批写脚本时真踩到)。
    const locs = [...grp.matchAll(/\.locale\s*=\s*Locale\(identifier:\s*"([^"]*)"\)/g)].map(x => x[1]);
    if (locs.length && locs.every(x => x === 'en_US_POSIX')) return;
    const why = locs.length ? `组内 locale 被设成 ${locs.join(' + ')} (后写覆盖先写)` : '组内没有 locale 赋值';
    console.log(`日期格式没钉历法 (非公历历法下 ${pat} 会算出异 era 年份): ${f}:${idx + 1}  ${t.slice(0, 100)}  [${why}]`
                + '  → 加 f.locale = Locale(identifier: "en_US_POSIX")，或复用 StatsKit.dayKey / RecordSearch.dateFromKey');
    calFail++;
  });
}

// ---------- 检查 9: 代码里直接写 `Calendar.current` (第一百五十九批) ----------
// 检查⑧ 钉的是"格式串跟着历法走"，这一条钉另一半：`Calendar.current` **本身就是用户历法的那套日历**。
// 佛历 ⇒ `.year` 取回 2569；农历 ⇒ `.month`/`.day` 整月错位。本仓的日期串、节假日表、锁端日志全是公历，
// 所以取分量必须走 `WeekCal.gregorian` (只把 identifier 钉成公历，时区/Locale/周序原样照抄)。
// 判据是一个字面 token，没有歧义；但**UI 文案里写这个词是合法的** (反控 `Text("Calendar.current 是用户历法")`)，
// 所以先按串/插值状态机把纯字面量内容摘掉，`\(...)` 里的代码仍留在判定面上 (插值里真取分量照样是缺陷)。
// 确要跟随用户历法的 (如 681 农历小字) 必须写 `Calendar(identifier: .chinese)` 这种**具名历法**，
// 或在该行留 `历法例外：` 说明为什么。
// 返回"去掉纯字符串字面内容、保留插值"的代码部分 (串外的注释已由 codePart 摘掉)
// 已知保守处：插值里出现未闭合/嵌套括号时会提前退出插值，后续内容按字面量丢掉 ⇒ 只会漏判，不会误判。
// 不吹全覆盖：这条判据的全部价值在于它不误报。
// 串与插值的**边界**用 \u0001 标出 (不是空格)：检查 12 要靠它认出"`\(x.at)` 后面那个 +"其实跨了字符串边界。
function codeNoStrings(line) {
  const src = codePart(line);
  let out = '';
  const stack = [];   // 'str' = 纯字面量, 'interp' = 插值内, 'istr' = 插值里再套的字符串
  let esc = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const top = stack[stack.length - 1];
    if (!top) {
      if (c === '"') { stack.push('str'); out += '\u0001'; }
      else out += c;
      continue;
    }
    if (top === 'str') {
      if (esc) { esc = false; continue; }
      if (c === '\\') { if (src[i + 1] === '(') { stack.push('interp'); i++; out += '\u0001('; } else esc = true; continue; }
      if (c === '"') { stack.pop(); out += '\u0001'; }
      continue;                                  // 字面内容丢掉
    }
    if (top === 'istr') {
      if (esc) { esc = false; continue; }
      if (c === '\\') { esc = true; continue; }
      if (c === '"') { stack.pop(); out += '\u0001'; }
      continue;
    }
    // interp: 内容留在判定面上
    if (c === '"') { stack.push('istr'); out += '\u0001'; continue; }
    if (c === '(') out += c;
    else if (c === ')') { stack.pop(); out += '\u0001'; continue; }
    out += c;
  }
  return out;
}
let sysCalFail = 0;
// 第一百七十一批补第二种形状：`cal: Calendar = .current` —— 默认参数里写的是**缩写** `.current`，
// 上面那句 `Calendar.current` 的字面 token 看不见它 (AutoOpenKit.defendActive 就这么躲过了 ⑨ 三轮)。
// 只认"`Calendar` 类型标注紧跟 `= .current`"这一种没有歧义的形状；
// 已声明过的变量再赋值 (`myCal = .current`) 行内没有类型信息 ⇒ 判不了，宁漏不误报。
const CAL_DEFAULT = /:\s*Calendar\s*=\s*\.current/;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const code = codeNoStrings(raw);
    if (!code.includes('Calendar.current') && !CAL_DEFAULT.test(code)) return;
    if (raw.includes('历法例外：')) return;
    console.log(`直接用系统历法的 Calendar (用户把历法设成佛历/农历时 .year/.month/.day 会整套换掉): ${f}:${idx + 1}  ${t.slice(0, 100)}`
                + '  → 用 WeekCal.gregorian；真要跟随用户历法就写具名历法或标 历法例外：');
    sysCalFail++;
  });
}

// ---------- 检查 10: 手写"协议秒 → Unix 秒"的绕路 (第一百六十批) ----------
// 这条绕路此前全仓 15 处各写一遍：`Double(protoSecondsToMs(x)) / 1000`。它本身没错 (epochMs 是整千毫秒)，
// 但**名字会骗人**：`StatsKit.msOf2` 走的就是这条路、返回的是秒，三个调用方按名字拿它去和
// `timeIntervalSince1970 * 1000` (毫秒) 比 ⇒ 626 逐密码用量恒 0、628 越界开门=全部密码开门、
// 609/629 临时码甘特刻度与核销天数恒 0。收成 `ZKProtocol.protoSecondsToUnix` 一份，
// 并判"同一行把 protoSecondsToMs 再除回 1000" —— 要 Unix 秒就直接调那个出口。
let protoRoundFail = 0;
for (const { f, s } of readAll) {
  s.split(/\r?\n/).forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const code = codeNoStrings(raw);
    const at = code.indexOf('protoSecondsToMs(');
    if (at < 0) return;
    if (!/\/\s*1000\b/.test(code.slice(at))) return;
    console.log(`协议秒绕回 Unix 秒的手写式 (量纲藏在名字里，抄一次就漂): ${f}:${idx + 1}  ${t.slice(0, 100)}`
                + '  → 用 ZKProtocol.protoSecondsToUnix(…)；真的要毫秒就别除这 1000');
    protoRoundFail++;
  });
}

// ---------- 检查 12 (报线索不判失败): `nowSec` 与 `.at` 同行相减 ----------
// 本仓的 `at` 字段**两套单位并存**：`LedgerPwd.at` / `LedgerFp.at` / `MaintEvent.t` 是 epoch 毫秒，
// `CredBinEntry.at` / `CredSnapshot.at` / `ClipboardCare.Pending.at` 是秒。第一百六十二批的
// 「智能列表·添加超一年」恒 0 条就是这么来的 (秒减毫秒 ⇒ 差一千倍 ⇒ 条件永不成立)。
// 静态判不出那个 `at` 属于哪一套 (要类型流)，所以这一条**只列线索、不进判决** —— 与"存储层参数序"
// 那一档同一处理方式：机器把可疑行摆到人面前，人写完结论才算数。
let unitBlur = 0;
for (const { f, s } of readAll) {
  const L = s.split(/\r?\n/);
  L.forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*') || t.startsWith('/*')) return;
    const code = codeNoStrings(raw);
    // 只判"秒的那一侧与 .at 的那个值真的在同一个加减算式里"：两个 token 之间必须有 +/−，
    // 且不许跨字符串边界 (\u0001) —— 反控 `"\(e.at)" + String(nowSec)` 就是靠这一条不响的。
    const secs = [...code.matchAll(/nowSec|timeIntervalSince1970/g)].map(m => [m.index, m.index + m[0].length]);
    const ats = [...code.matchAll(/\.(?:at|t)\b/g)].map(m => [m.index, m.index + m[0].length]);
    let arithmetic = false;
    for (const a of ats) {
      for (const s of secs) {
        const first = a[0] < s[0] ? a : s, second = a[0] < s[0] ? s : a;
        const between = code.slice(first[1], second[0]);
        if (between.includes('\u0001') || !/[+\-]/.test(between)) continue;
        arithmetic = true;
      }
    }
    if (!arithmetic) return;
    if (/\/\s*1000\b|\*\s*1000\b|86_400_000|86400000/.test(code)) return;  // 已经换算过
    for (let k = Math.max(0, idx - 3); k <= idx; k++) if (L[k].includes('单位口径：')) return;   // 人读过并写了结论
    console.log(`单位待读: 秒与 .at 直接相减 (这个 at 是 epoch 毫秒还是秒? 两套约定都在用): ${f}:${idx + 1}  ${t.slice(0, 110)}`
                + '  → 读完后在本行或紧邻上方写「单位口径：秒」或「单位口径：毫秒」');
    unitBlur++;
  });
}

// ---------- 检查 11: 保留"最新 N 条"的截断方向与增长方向反了 (第一百六十四批) ----------
// 列表有两种长大方式：`x.insert(…, at: 0)` = 最新在前，`x.append(…)` = 最新在后。
// 截断留头还是留尾必须与它同侧，否则留下的正好是**最旧**的那批：
// 553 搜索历史原本 `insert(at: 0)` 之后 `Array(h.suffix(5))` ⇒ 第 6 个新词一进去就被挤掉，
// 留下的全是旧词 (界面上还写着"再次选用要把这条提到最前")。
// 判据要变量名同侧、6 行内成对出现，所以不会碰 `removeFirst(h.count - 60)` 这种另写法的截断。
let capFail = 0;
for (const { f, s } of readAll) {
  const L = s.split(/\r?\n/);
  L.forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    const grow = raw.match(/(\w+)\.(insert)\([^)]*\bat:\s*0\s*\)/) || raw.match(/(\w+)\.(append)\(/);
    if (!grow) return;
    const v = grow[1], newestFirst = grow[2] === 'insert';
    for (let k = idx + 1; k <= Math.min(L.length - 1, idx + 6); k++) {
      const c = codeNoStrings(L[k]);
      // 例外标记: 写在截断那一行、或它上面三行内 (与 ⑫ 的 `单位口径：`、⑨ 的 `历法例外：` 同一族做法)。
      let marked = false;
      for (let m = Math.max(0, k - 3); m <= k; m++) if (L[m].includes('方向口径：')) marked = true;
      if (marked) break;
      const wrong = newestFirst
        ? new RegExp('Array\\(\\s*' + v + '\\.suffix\\(|\\b' + v + '\\s*=\\s*Array\\(.*\\.suffix\\(')
        : new RegExp('Array\\(\\s*' + v + '\\.prefix\\(|\\b' + v + '\\s*=\\s*Array\\(.*\\.prefix\\(');
      const same = newestFirst
        ? new RegExp('Array\\(\\s*' + v + '\\.prefix\\(|\\b' + v + '\\s*=\\s*Array\\(.*\\.prefix\\(')
        : new RegExp('Array\\(\\s*' + v + '\\.suffix\\(|\\b' + v + '\\s*=\\s*Array\\(.*\\.suffix\\(');
      if (wrong.test(c)) {
        console.log(`截断方向与增长方向相反 (${v} 是${newestFirst ? '最新在前，该用 prefix' : '最新在后，该用 suffix'}): ${f}:${k + 1}  ${L[k].trim().slice(0, 100)}`
                    + '  → 换成同侧截断；若这不是"留最新 N 条"(按序号截长度之类)，写「方向口径：…」销号');
        capFail++;
        break;
      }
      if (same.test(c)) break;                                   // 同侧的合法截断，这段已定案
    }
  });
}

// ---------- 检查 13: 界面把「回收站保留天数」写死 ----------
// 起因 (第一百六十七批)：回收站保留期是 497 的可调项 (设置页那枚 7~90 天的 Stepper，键 `kf_cbin_reclaim_days`)，
// 而两枚「彻底删除」的确认框把文案写成「回收站 30 天内可找回」—— 用户把它调到 7 天之后，
// 这句就把安全网说大了整整四倍，而它恰恰出现在**按下就不可逆**的那一刻。
// 这一族的可怕之处在于它不是算错，是**说错**：数字与设置各行其是，没有任何一处会报错。
// 判据只看纯字面量段 (插值 `\(…)` 里的代码不算文案)，所以正确写法 `回收站 \(reclaimDays()) 天` 天然不响。
// 不吹全覆盖：静态分不出「这个 N 天」到底是不是 497 那个保留期 —— 364 的一键恢复窗口就是**另一件**事
// (代码里写死 7 天，`CredentialOrg.withinRecoverWindow`)，那两句 UI 文案是属实的。
// 所以给这一族留一个专用销号标记 `天数口径：`：写明这个天数是什么、出处在哪，工具就闭嘴。
function litSegs(line) {
  const out = [];
  let cur = null;            // 非 null = 正在收集字面量段
  let esc = false, interp = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (interp > 0) {                                    // 插值内的一切 (含嵌套引号) 都不进文案
      if (c === '\\') { i++; continue; }
      if (c === '(') interp++;
      else if (c === ')') { interp--; if (interp === 0) cur = ''; }   // 插值结束: 同一条串继续
      continue;
    }
    if (cur === null) { if (c === '"') cur = ''; continue; }
    if (esc) { cur += c; esc = false; continue; }
    if (c === '\\') {
      if (line[i + 1] === '(') { interp = 1; i++; out.push(cur); cur = null; }   // 进插值: 当前段结束
      else esc = true;
      continue;
    }
    if (c === '"') { out.push(cur); cur = null; continue; }
    cur += c;
  }
  return out;
}
let dayFail = 0;
const DAY_CLAIM = /回收站[^。\n]{0,12}?\d+\s*天|保留\s*\d+\s*天/;
for (const { f, s } of readAll) {
  const L = s.split(/\r?\n/);
  L.forEach((raw, idx) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    const hit = litSegs(codePart(raw)).find(seg => DAY_CLAIM.test(seg));
    if (!hit) return;
    for (let m = Math.max(0, idx - 2); m <= idx; m++) if (L[m].includes('天数口径：')) return;
    console.log(`界面把天数写死在文案里: ${f}:${idx + 1}  ${t.slice(0, 96)}`
                + '  → 497 的回收站保留期是可调项 (7~90 天)，要读 `CredentialOrg.reclaimDays()`；'
                + '若这个 N 天不是保留期，写「天数口径：它是哪件事、出处在哪」销号');
    dayFail++;
  });
}

console.log(lineFail + typeFail ? `✗ 同行合并语句 ${lineFail + typeFail} 处 (含类型体)` : '同行合并语句检查 ✓');console.log(symFail ? `✗ 疑似未声明符号 ${symFail} 处 (逐条人工判定, 允许名单外的系统类型会误报)` : '符号引用检查 ✓');console.log(numFail ? `✗ Int64/Double 混比 ${numFail} 处` : 'Int64/Double 混比检查 ✓');
console.log(orderFail ? `✗ 存储层键/值参数序颠倒 ${orderFail} 处 (另有 ${orderBlur} 处两参都不像键, 静态判不了, 交人读)`
                      : `存储层参数序检查 ✓ (${orderBlur} 处两参都不像键, 未判定)`);
console.log(quoteFail ? `✗ 中文串里的 ASCII 引号 ${quoteFail} 处` : '中文串引号检查 ✓');
console.log(whiteFail ? `✗ 写死纯白前景 ${whiteFail} 处 (名单是上限, 只能减不能加)`
                      : `写死纯白前景检查 ✓ (${Object.values(whiteSeen).reduce((a, b) => a + b, 0)} 处已核实并在名单内)`);
console.log(utcFail ? `✗ UTC 日期当本地日用 ${utcFail} 处` : '本地日 key 检查 ✓ (.iso8601 不再被截成日期)');
console.log(calFail ? `✗ 日期格式没钉历法 ${calFail} 处` : '日期格式历法检查 ✓ (机器面日期格式全部钉 en_US_POSIX)');
console.log(sysCalFail ? `✗ 直接用系统历法的 Calendar ${sysCalFail} 处` : 'Calendar 历法检查 ✓ (取分量一律走 WeekCal.gregorian)');
console.log(protoRoundFail ? `✗ 手写协议秒绕回 Unix 秒 ${protoRoundFail} 处` : '协议秒换算检查 ✓ (要 Unix 秒就调 protoSecondsToUnix)');
console.log(`时间单位对账 (顾问级, 不判失败): ${unitBlur} 处秒与 .at 直接相减待人读 —— 本仓 .at 有毫秒与秒两套约定`);
console.log(capFail ? `✗ 保留"最新 N 条"截反 ${capFail} 处` : '截断方向检查 ✓ (prefix/suffix 与 insert(at:0)/append 同侧)');
console.log(dayFail ? `✗ 界面写死回收站/保留天数 ${dayFail} 处` : '回收站天数检查 ✓ (保留期一律读 reclaimDays，其余带 天数口径 销号)');
process.exit(lineFail + typeFail + symFail + numFail + orderFail + quoteFail + whiteFail + utcFail + calFail + sysCalFail + protoRoundFail + capFail + dayFail ? 1 : 0);
