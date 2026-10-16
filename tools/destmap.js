#!/usr/bin/env node
// 目的地台账 (判失败) — node tools/destmap.js [--json] [--verbose]
//
// 起因 (2026-10-16): 要在一套 App 里并存**两套完整界面**并可切换。
// "完整"如果只是一句口号，两套里必然有一套缺一块而没人发现 —— 这是双 UI 的经典死法。
// 所以先把分母钉死：**一个目的地 = 被 sheet / fullScreenCover / NavigationLink / Tab
// 呈现出来的那一个 View 类型**。仅仅被另一个视图 compose 在 body 里 (MomentCardView、
// SettingsGroupChips 这类构件) **不算目的地**，否则分母虚高、两套都得为装饰买单。
//
// 口径:
//   · 只认**实例化** `XxxView(`，不认注释里的名字 —— 注释会写"原来这里是 BackupView"。
//   · 呈现作用域 = 从呈现调用后面那个 `{` 起、到与之配对的 `}` 止 (手写括号计数，
//     跳过字符串与行注释/块注释里的括号 —— 不跳就会在 `}` 上提前收口，漏掉整批目的地)。
//   · 排除声明文件自身里的 `struct XxxView` 行。
//   · 宁可多认也不要少认：多认一条只是给两套各加一站；少认一条就是某套真的少了页面而台账说"齐了"。
//     (与 featuremap.js 的"宁可少认"相反方向 —— 因为这里错的代价不对称。)
//
// 尺子自己必须被验: 见文件末尾的 fixtures —— 一个只被 compose 的视图必须**不进**台账，
// 一个被 sheet 呈现的必须进。任一条不符 ⇒ exit 1 并说明"台账不可信"。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.argv.includes('--json') ? process.cwd() : process.cwd();
const SRC = ['App', 'Widget'];
// 只匹配修饰符本身，**不在正则里试图吃掉参数表**。
// 旧写法 `(\([^)]*\))?\s*\{` 假设参数里不含括号，于是
//     .sheet(isPresented: Binding(get: { … }, set: { … })) { … }
// 整条匹配失败 —— 该 sheet 端出来的目的地凭空从台账消失 (2026-10-16 实测掉过 CredentialsView /
// RecordsView 两条，靠 tools/uicoverage.js 的漂移检查才发现)。参数表交给下面的解析器走。
const PRESENT = /\.(sheet|fullScreenCover|navigationDestination|popover)\b/g;
const LINK = /\bNavigationLink\b/g;
const LINK_INLINE = /NavigationLink\s*\((?:value|title):[^;]*?\)\s*\{?\s*([A-Z][A-Za-z0-9_]*View)\s*\(/g;
// Tab 的内容既可能是**直接实例化**（`Tab(...) { XxxView() }`），也可能是一个
// **内容属性**（`Tab(...) { deviceTabContent }`）—— 本仓四个 Tab 全是后者
// （内联进 TabView 会报 type-check 超时）。旧正则只吃前者，于是四个 Tab 的根页
// 一个都不进台账；`DeviceHomeView` 能出现在旧台账里纯粹是因为一句解释性注释（见 inLineComment）。
// 所以这里不再要求后面跟 `(`，把决定权交给使用处。
const TAB = /\bTab\s*\(([^;]*?)\)\s*\{?\s*([A-Za-z_][A-Za-z0-9_]*)/g;
const INSTANTIATION = /(?:^|[^A-Za-z0-9_])([A-Z][A-Za-z0-9_]*View)\s*\(/g;

function walk(dir, out) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) walk(f, out);
    else if (f.endsWith('.swift')) out.push(f);
  }
  return out;
}

/** 本仓自己声明的 View 类型名集合。
 *  目的地必须是**自己人** —— 否则 `.sheet { EmptyView() }`、`ProgressView()`、
 *  `QLPreviewView()` 这些系统/SDK 类型会被当成"一套界面少了一站"，分母虚高。
 *  (第一版就混进了 EmptyView / ProgressView / QLPreviewView 三条，
 *   applyseam.js 报"找不到 struct 声明"才暴露出来。) */
function declaredViews(files) {
  const s = new Set();
  const re = /^\s*(?:(?:public|internal|fileprivate|private)\s+)?struct\s+([A-Za-z0-9_]+)\s*:\s*[^{]*\bView\b/mg;
  for (const f of files) {
    let m; re.lastIndex = 0;
    while ((m = re.exec(fs.readFileSync(f, 'utf8')))) s.add(m[1]);
  }
  return s;
}

/** 从修饰符（`.sheet` / `NavigationLink`）之后找到它**尾随闭包**的 '{'。
 *  参数表里可以带括号、花括号、字符串、注释 —— 所以必须配对走完，不能交给正则。
 *  返回 -1 表示这个位置后面没有尾随闭包（例如 `NavigationLink(value: x)` 那种带 label 的写法，
 *  由另一条正则专门处理）。 */
function trailingClosureBrace(src, from) {
  let i = from, d = 0, inLine = false, inBlock = false, inStr = false;
  while (i < src.length && /\s/.test(src[i])) i++;
  if (src[i] === '(') {
    for (; i < src.length; i++) {
      const c = src[i], p = src[i - 1];
      if (inLine) { if (c === '\n') inLine = false; continue; }
      if (inBlock) { if (c === '/' && p === '*') inBlock = false; continue; }
      if (inStr) { if (c === '\\') { i++; continue; } if (c === '"') inStr = false; continue; }
      if (c === '/' && src[i + 1] === '/') { inLine = true; continue; }
      if (c === '/' && src[i + 1] === '*') { inBlock = true; continue; }
      if (c === '"') { inStr = true; continue; }
      if (c === '(' || c === '{' || c === '[') d++;
      else if (c === ')' || c === '}' || c === ']') { d--; if (d === 0) { i++; break; } }
    }
    if (d !== 0) return -1;
  }
  while (i < src.length && /\s/.test(src[i])) i++;
  return src[i] === '{' ? i : -1;
}

/** 解析一个"内容属性"（`Tab(...) { deviceTabContent }` 里那个名字）：返回它 body 的区间。
 *  只跟**一跳**，且只看**同一个文件** —— 跟第二跳就等于在这里写一个 Swift 编译器，
 *  那是另一个量级的事（且会引入"解析错了反而静默掉站"的新风险）。
 *  找不到就返回 null，使用处宁可不算也不猜。 */
function propertyBody(src, name) {
  const re = new RegExp('var\\s+' + name + '\\s*:[^{}]*\\{');
  const m = re.exec(src);
  if (!m) return null;
  const open = m.index + m[0].length - 1;
  const close = matchBrace(src, open);
  return close > open ? { start: open, end: close } : null;
}

/** 从 openIdx 处的 '{' 起，返回配对 '}' 的下标。跳过字符串插值以外的括号与注释。 */
function matchBrace(src, openIdx) {
  let depth = 0, i = openIdx, inLine = false, inBlock = false, inStr = 0;
  for (; i < src.length; i++) {
    const c = src[i], p = src[i - 1];
    if (inLine) { if (c === '\n') inLine = false; continue; }
    if (inBlock) { if (c === '/' && p === '*') inBlock = false; continue; }
    if (inStr) {
      if (c === '\\' ) { i++; continue; }
      if (c === '"') inStr = 0;
      continue;
    }
    if (c === '/' && src[i + 1] === '/') { inLine = true; continue; }
    if (c === '/' && src[i + 1] === '*') { inBlock = true; continue; }
    if (c === '"') { inStr = 1; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return i; }
  }
  return src.length;
}

const lineOf = (src, idx) => src.slice(0, idx).split('\n').length;

/** idx 是否落在**行注释**里（含行尾注释）。
 *  为什么必须逐处判而不是把整份源剥一遍注释：本仓有 `"""` 多行字符串，
 *  整份剥会把里面的内容一起当注释吃掉（那就是另一个方向的错：真目的地被静默丢掉，分母变小）。
 *  而且这本来就是本文件自己的口径 —— 开头写着"只认**实例化**，不认注释里的名字 —— 注释会写
 *  '原来这里是 BackupView'"，但旧实现只在声明行上做了这件事，扫作用域内的实例化时根本没剥。
 *  2026-10-16 实测翻车：`// …里面**不许**放 DeviceHomeView()` 这句**解释性注释**把一个
 *  并不存在的目的地塞进了台账（分母虚高）。
 *  ⚠ 仍然漏的：块注释（斜杠星号那一对）里的名字。本仓没有一例，宁漏不误报 —— 记在这里，不假装不存在。 */
function inLineComment(src, idx) {
  const ls = src.lastIndexOf('\n', idx - 1) + 1;
  let inStr = false;
  for (let i = ls; i < idx; i++) {
    const c = src[i];
    if (inStr) {
      if (c === '\\') { i++; continue; }
      if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === '/' && src[i + 1] === '/') return true;
  }
  return false;
}

function scan(files) {
  const DECLARED = declaredViews(files);
  const found = new Map();   // ViewName -> [{file,line,how}]
  const add = (name, file, line, how) => {
    if (!found.has(name)) found.set(name, []);
    const hits = found.get(name);
    if (!hits.some((h) => h.file === file && h.line === line)) hits.push({ file, line, how });
  };
  for (const file of files) {
    const src = fs.readFileSync(file, 'utf8');
    const lines = src.split('\n');
    // 声明行集合: 本文件里 `struct XxxView` 所在行不算实例化
    const declLines = new Set();
    lines.forEach((l, k) => { const m = /^\s*(?:private |fileprivate |public )?struct\s+([A-Z][A-Za-z0-9_]*View)\b/.exec(l); if (m) declLines.add(k + 1); });

    const scopes = [];
    for (const job of [[PRESENT, (m) => m[1]], [LINK, () => 'NavigationLink']]) {
      const re = job[0], howOf = job[1];
      re.lastIndex = 0; let m;
      while ((m = re.exec(src))) {
        if (inLineComment(src, m.index)) continue;      // 注释里的 `.sheet(...)` 不是呈现
        const open = trailingClosureBrace(src, m.index + m[0].length);
        if (open < 0) continue;
        scopes.push({ start: open, end: matchBrace(src, open), how: howOf(m) });
      }
    }
    // 作用域内的实例化
    for (const s of scopes) {
      const seg = src.slice(s.start, s.end);
      INSTANTIATION.lastIndex = 0; let m;
      while ((m = INSTANTIATION.exec(seg))) {
        const abs = s.start + m.index + m[0].indexOf(m[1]);
        if (inLineComment(src, abs)) continue;          // 注释里的实例化不算目的地
        add(m[1], file, lineOf(src, abs), s.how);
      }
    }
    // NavigationLink(value:) 的简写形式
    LINK_INLINE.lastIndex = 0;
    let lm;
    while ((lm = LINK_INLINE.exec(src))) {
      if (!lm[1]) continue;
      if (inLineComment(src, lm.index)) continue;
      add(lm[1], file, lineOf(src, lm.index), 'NavigationLink(value:)');
    }
    // Tab 的两种写法
    TAB.lastIndex = 0;
    let tm;
    while ((tm = TAB.exec(src))) {
      if (inLineComment(src, tm.index)) continue;
      const name = tm[2];
      if (!name) continue;
      if (src[tm.index + tm[0].length] === '(') {
        add(name, file, lineOf(src, tm.index), 'Tab');
        continue;
      }
      // 内容属性：真正的目的地在它 body 里。
      const body = propertyBody(src, name);
      if (!body) continue;
      const seg = src.slice(body.start, body.end);
      INSTANTIATION.lastIndex = 0;
      let im;
      while ((im = INSTANTIATION.exec(seg))) {
        const abs = body.start + im.index + im[0].indexOf(im[1]);
        if (inLineComment(src, abs)) continue;
        add(im[1], file, lineOf(src, abs), `Tab(${name})`);
      }
    }
    // 只留本仓自己声明的 View —— 系统/SDK 类型不是"某套界面少了一站"。
    for (const k of [...found.keys()]) if (!DECLARED.has(k)) found.delete(k);
    // 去掉声明行自身的命中
    for (const hits of found.values()) {
      for (let i = hits.length - 1; i >= 0; i--) {
        if (declLines.has(hits[i].line) && /\bstruct\b/.test(
          fs.readFileSync(hits[i].file, 'utf8').split('\n')[hits[i].line - 1] || '')) hits.splice(i, 1);
      }
    }
  }
  return found;
}

// ---------- 正控 / 反控: 台账自己必须被验 ----------
// 覆盖**全部 6 条呈现通道**：一条通道没被正控覆盖，就意味着走那条通道的目的地
// 可能整批漏抽而台账照样报"自检通过"。上一版只验了 sheet 与 NavigationLink 两条，
// 77 这个数因此是**下界**而不是定值。
function selfTest() {
  const dir = path.join('fixtures', 'destmap');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'A.swift'), [
    'import SwiftUI',
    'struct ComposedOnlyView: View { var body: some View { Text("x") } }',
    'struct SheetPresentedView: View { var body: some View { Text("y") } }',
    'struct LinkedView: View { var body: some View { Text("z") } }',
    'struct FullScreenView: View { var body: some View { Text("f") } }',
    'struct NavDestView: View { var body: some View { Text("n") } }',
    'struct PopoverView: View { var body: some View { Text("p") } }',
    'struct TabbedView: View { var body: some View { Text("t") } }',
    'struct BindingSheetView: View { var body: some View { Text("b") } }',
    'struct CommentOnlyView: View { var body: some View { Text("c") } }',
    'struct PropTabView: View { var body: some View { Text("pt") } }',
    'struct HostView: View {',
    '  @State private var on = false',
      '  @ViewBuilder private var tabContentProp: some View { PropTabView() }',
    '  var body: some View {',
    '    TabView {',
    '      Tab("一", value: 1) { TabbedView() }',
    // 正控 9：Tab 的内容是**内容属性**而不是直接实例化。本仓四个 Tab 全是这种写法
    // （内联进 TabView 报 type-check 超时），旧实现因此四个根页一个都不进台账。
    '      Tab("二", value: 2) { tabContentProp }',
    '    }',
    // 正控 7：参数表里带花括号的 Binding 写法。旧的正则在这条上整条匹配失败，
    // 于是这个 sheet 端出来的目的地会**凭空从台账消失** —— 必须有控件钉住它。
    '    .sheet(isPresented: Binding(get: { on }, set: { v in on = v })) {',
    '      BindingSheetView()          // 目的地 (参数含括号的 sheet)',
    '    }',
    '    .sheet(isPresented: $on) {',
    '      SheetPresentedView()        // 目的地 (sheet)',
    '    }',
    '    .fullScreenCover(isPresented: $on) { FullScreenView() }',
    '    .navigationDestination(for: String.self) { _ in NavDestView() }',
    '    .popover(isPresented: $on) { PopoverView() }',
    '    .background(',
    '      NavigationLink("l") { LinkedView() }   // 目的地 (NavigationLink trailing)',
    '    )',
    '    // 反控 4：注释里的实例化不算目的地（旧实现会把这一句当真的呈现）',
    '    // CommentOnlyView()',
    '    .overlay { ComposedOnlyView() }          // 只是构件, 不是目的地',
    '    .sheet(isPresented: $on) { SystemishNotDeclaredHereView() }  // 外部类型, 不算目的地',
    '  }',
    '}',
    ''].join('\n'));
  const got = scan([path.join(dir, 'A.swift')]);
  const names = new Set(got.keys());
  const problems = [];
  const MUST = {
    SheetPresentedView: 'sheet', FullScreenView: 'fullScreenCover',
    NavDestView: 'navigationDestination', PopoverView: 'popover',
    LinkedView: 'NavigationLink', TabbedView: 'Tab'
  };
  // 参数表里带花括号的那条 sheet 单独列一条正控：它曾经是**静默消失**的那一类。
  MUST.BindingSheetView = 'sheet(Binding 参数含括号)';
  // 第 7 条通道单独列一条正控：它替掉了一个 sheet，是"台账少三站"的最高危入口。
  // Tab 的"内容属性"写法单独列一条正控：四个 Tab 的根页全靠它才进得了台账。
  MUST.PropTabView = 'Tab(内容属性)';
  for (const v of Object.keys(MUST)) {
    if (!names.has(v)) problems.push(`正控失败: ${v} 走 ${MUST[v]} 通道却没进台账 —— 该通道的抽取是坏的`);
  }
  if (names.has('ComposedOnlyView')) problems.push('反控失败: ComposedOnlyView 只被 compose 却进了台账 (分母会虚高)');
  if (names.has('HostView')) problems.push('反控失败: 宿主自己进了台账 (它不是被呈现的目的地)');
  // 反控 4：只出现在**注释**里的名字不算目的地。
  // 2026-10-16 实测：`// …不许放 DeviceHomeView()` 这类解释性注释把不存在的目的地塞进了台账。
  if (names.has('CommentOnlyView')) problems.push('反控失败: 只在注释里出现的名字进了台账 (分母虚高)');
  // 反控 3：本仓没声明过的类型（系统 / SDK）不算目的地。
  // 第一版没有这条，EmptyView / ProgressView / QLPreviewView 混进台账，
  // 分母虚高 3 条，直到 applyseam.js 报"找不到 struct 声明"才暴露。
  if (names.has('SystemishNotDeclaredHereView')) {
    problems.push('反控失败: 未在本仓声明的外部类型进了台账 —— 分母会被系统类型撑高');
  }
  // 计数从上面两张表里读，不写死 —— 上一版底部印的"正控 2 条"是硬编码文案，
  // 通道加到 6 条之后它还在说 2 条：判据改了、口径没改，比没口径更坏。
  return { problems, nPos: Object.keys(MUST).length, nNeg: 4,
           channels: Object.keys(MUST).map((k) => MUST[k]) };
}

const files = [];
for (const r of SRC) walk(r, files);
const found = scan(files);
const list = [...found.entries()].sort((a, b) => a[0].localeCompare(b[0]));

if (process.argv.includes('--json')) {
  process.stdout.write(JSON.stringify(list.map(([n, h]) => ({ view: n, sites: h })), null, 1) + '\n');
  // 机器可读输出必须独占 stdout。上一版没做这条：--json 之后又把人类汇总 console.log
  // 到同一个流里，调用方 (tools/uicoverage.js) JSON.parse 直接炸在尾巴上。
  // 把后续所有普通输出改道 stderr —— 信息一条不少，但 stdout 是干净的 JSON。
  console.log = (...a) => console.error(...a);
} else {
  for (const [n, h] of list) {
    console.log(`${n.padEnd(34)} ${String(h.length).padStart(2)} 处  ${h.map((x) => `${x.file}:${x.line}(${x.how})`).join(' ')}`);
  }
}

// ---------- --emit: 把台账直接生成 Swift 枚举 ----------
// 为什么由工具生成而不是手写：两套完整界面各自要一张 77 条的路由表，
// 手写清单与代码里的真实目的地**必然漂移**（本仓"同一个量算两次"那一族）。
// rawValue 用 View 类型名本身 ⇒ 闸门可以直接拿 `Destination.allCases.map(\.rawValue)`
// 与本台账的键集做集合差，差一个就报错，不需要人维护对照表。
if (process.argv.includes('--emit')) {
  const camel = (n) => n.charAt(0).toLowerCase() + n.slice(1).replace(/View$/, '');
  const rows = list.map(([n]) => `    case ${camel(n)} = "${n}"`);
  const out = [
    '// 本文件由 `node tools/destmap.js --emit` 生成，**不要手改**。',
    `// 生成时的目的地总数 = ${list.length}。改了界面呈现方式之后重新生成，`,
    '// 并核对 diff —— 少一条就是某套界面会缺一个页面而没人发现。',
    'import SwiftUI',
    '',
    '/// 一个目的地 = 界面里的一站（供闸门与台账对账）。',
    '/// rawValue 是 View 类型名，供 tools/uicoverage.js 与本台账对账。',
    'enum Destination: String, CaseIterable, Identifiable {',
    rows.join('\n'),
    '    var id: String { rawValue }',
    '}',
    ''
  ].join('\n');
  fs.writeFileSync(path.join('App', 'Core', 'Destination.swift'), out);
  console.log(`已写 App/Core/Destination.swift —— ${list.length} 个 case`);
}

const st = selfTest();
const problems = st.problems;
console.log('');
console.log(`目的地总数 = ${list.size || list.length}   (扫 ${files.length} 个 .swift，呈现通道 = sheet/fullScreenCover/navigationDestination/popover/NavigationLink/Tab)`);
console.log(`判据形状: 每条命中带 文件:行 + 走的是哪条呈现通道；只被 compose 在 body 里的视图不计入。`);
if (problems.length) {
  problems.forEach((p) => console.log('!! ' + p));
  console.log('→ 台账自身没通过自检，上面这个数**不可信**，两套界面的覆盖判定作废。');
  process.exit(1);
}
console.log(`尺子自检: 正控 ${st.nPos} 条 (逐通道: ${st.channels.join(' / ')}) 全部入表, `
          + `反控 ${st.nNeg} 条 (仅 compose 的构件 / 宿主自身 / 未声明的外部类型) 全部未入表 → 通过`);
