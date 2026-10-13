#!/usr/bin/env node
// tools/swiftshape.js — Swift 形状机检 (第一百三十七批新增, **判失败**)
//
// 为什么这道闸门存在：Actions 上 run 43 (2026-10-07) 之后连红四场 (44–47)，失败都落在
// 「编译校验测试目标」，而本地那 14 道 node 闸门没有一道能替代编译器 —— 括号平了、名字眼熟就一路绿。
// 这一道抓的是**不需要类型推导就能定形**的四类编译错误 (R1/R2/R4/R5)，外加一条只许减不许增的棘轮 (R3)：
//
// R1  声明为 `: some View` / `-> some View` 的成员，体内有**顶层 if 而没有 else、也没有 return**，
//     却缺 `@ViewBuilder` ⇒ "function declared as returning 'some View' … non-disclosure body"。
//     本仓真实命中 3 处：RecordsTimeline/credJumpSection、RecordsView/firstDayFooter、
//     SettingsView/autoOpenSection —— 最后那处正是 run 47 那次提交带进来的形状。
// R2  `@ViewBuilder` 归属的**那一条声明**带着显式类型，而类型落在一张"值类型"短名单里
//     (String / Int / Bool / Date / 数组 / 闭包…) ⇒ 结果构建器把 body 包成 buildBlock(...)，
//     与声明类型对不上。本仓真实命中 1 处：属性被插到一段 /// 文档注释**之前**，
//     于是挂到了返回 String? 的 timeWords 身上。
//
// R3  **棘轮** (只许减不许增): 持久化 struct 靠合成 Codable 解码, 却带着"非 Optional + 有默认值"
//     的字段 ⇒ 下一次给它加字段就会让旧 JSON keyNotFound。数量超过基线才判失败, 详见 r3() 上方。
//
// R4  调用点的**参数标签**与声明对不上 (第一百四十八批新增)：Swift 的标签是逐字匹配的，
//     少写、多写、写错一个都不过编译，而名字眼熟 + 括号平衡让它一路通过前面所有闸门。
//     落地当批即在现网抓到 **13 处**：只判首参那版抓到 10 处 —— RecordSearch.oid(mac:rowKey:) 被 6 处按位置调用、
//     StatsView.legendRow(_ labels:) 被 1 处写成 labels:、LinkSense.successRateText(mac:) 1 处、
//     RecordSearch.unhandledAlarmCount(macs:) 2 处；改成**逐位判**之后又抓到 3 处
//     (CredentialStudio 把 CredentialOrg.firstUse/usageCount/openCountInWindow 的第二参标签 `p:` 全省了)。
//     判据、两条豁免，以及"实例调用试过又撤掉"那条写在 r4() 上方。
//
// R5  实参**个数**与声明对不上 (第一百五十一批新增，与 R4 共用同一条流水)：`missing argument` /
//     `extra argument in call`。只判"参数表里既没有默认值、也没有闭包类型参数"的声明 ——
//     那种函数写不出尾随闭包、也省不掉任何一参，括号里的个数是定死的。
//     本批现网 0 命中 (那 13 处都是标签问题，没有个数问题)，但两条正控常驻 `fire/Arity.swift`
//     (少参、多参各一条)，反控 `ok/Arity.swift` 专放"尾随闭包"与"带默认值"两种看起来少一个的合法写法。
//     加它的过程反手打出自家判据的两个 bug (`->` 里那个 `>` 被当括号，把参数表在 `(Int` 处截断；
//     零参声明不登记，于是同名重载把**定义处**读成"少传一参"的调用点) —— 都记在 §10.23。
//     "没见过自己开火的尺子不算尺子"，本仓第二次被同一句话救回来。
//
// 三条刻意的豁免边界，写清楚而不是假装没有：
//  · `var body: some View` 与 ViewModifier 的 `func body(content:)` 不检 —— 协议自己带
//    @ViewBuilder，实现处不写也合法；算进来就是 8 条噪音。
//  · 判不了就不报：目标声明没写显式类型 (`@ViewBuilder private func trendSection(_ m:) {`) 时，
//    它靠 Swift 的隐式 opaque 返回类型推导，本机没编译器无从定论。StatsView 里这种形状有十几处，
//    既不动也不报，留给下一次真编译 (§10.11 记着这条)。
//  · R2 只认"值类型短名单"：想证明"这不是 View"要的是全知 —— `@ViewBuilder var content: Content`
//    (Content: View 的泛型内容槽) 完全合法，把它当误报会让闸门变成噪音机。
//
// 判据自己先过正控：`--selftest` 拿 fixtures/swiftshape/ 里"该响的"与"不该响的"两组样例各跑一遍，
// 三条判据都各有正控 (R3 的第一版看不见单行写完的小 struct —— 是注入探针 `App/_probe_r3.swift` 一测就不响才发现的)；
// 打不响或误响就退出 2 (本仓在 changelogcheck / keydead 上都验证过这条纪律)。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'Widget', 'Tests'];
const VIEW_DECL = /^(\s*)(?:private |public |fileprivate |internal )?(?:static )?(?:@\w+ )?(?:var|func)\s+[\w<>]+(?:\([^)]*\))?\s*(?::|->)\s*some\s+View\s*\{\s*$/;
const DECL_HEAD = /^(?:@\w+\s+)*(?:private |public |fileprivate |internal |static |final )*(var|func)\b/;
const VALUE_TYPE = /^(?:\s*\?)?(String|Int\d*|UInt\d*|Double|Float|CGFloat|Bool|Date|Data|URL|Error|[([{])/;

function swiftFiles(root) {
  const out = [];
  if (!fs.existsSync(root)) return out;
  (function w(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, e.name);
      if (e.isDirectory()) w(f);
      else if (e.name.endsWith('.swift')) out.push(f);
    }
  })(root);
  return out;
}

const isCommentOrBlank = (l) => /^\s*(\/\/|\/\*|\*)/.test(l) || /^\s*$/.test(l);
const stripLine = (l) => l.replace(/\/\/.*$/, '');

// 属性与声明之间的注释/其它属性不改变归属 ⇒ 往回跳着找
function hasBuilderBefore(L, i) {
  for (let j = i - 1; j >= 0; j--) {
    if (/@ViewBuilder/.test(L[j])) return true;
    if (isCommentOrBlank(L[j]) || /^\s*@[A-Za-z]/.test(L[j])) continue;
    return false;
  }
  return false;
}

function r1(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const m = VIEW_DECL.exec(L[i]);
      if (!m) continue;
      if (/\bvar\s+body\b|func\s+body\s*\(/.test(L[i])) continue;
      if (hasBuilderBefore(L, i)) continue;
      let depth = 0, hasReturn = false, topIf = false, hasElse = false;
      for (let j = i; j < L.length; j++) {
        const ln = stripLine(L[j]);
        const before = depth;                                 // 进这行**之前**的嵌套层
        for (const ch of ln) { if (ch === '{') depth++; else if (ch === '}') depth--; }
        if (j > i && before === 1) {
          if (/^\s*return\b/.test(ln)) hasReturn = true;
          if (/^\s*if\b/.test(ln)) topIf = true;
        }
        if (j > i && /^\s*\}\s*else\b|^\s*else\b/.test(ln)) hasElse = true;   // `} else` 那行 before 是 2
        if (j > i && depth <= 0) break;
      }
      if (topIf && !hasReturn && !hasElse) {
        bad.push(f + ':' + (i + 1) + '  R1 缺 @ViewBuilder —— ' + L[i].trim().slice(0, 60));
      }
    }
  }
  return bad;
}

function r2(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (!/^\s*@ViewBuilder\b/.test(L[i])) continue;
      // 同一行就写完的 (`@ViewBuilder var content: Content`) 目标在本行；否则找下一个声明行
      let target = L[i].replace(/^\s*@ViewBuilder\s*/, '').trim();
      if (!DECL_HEAD.test(target)) {
        let j = i + 1;
        while (j < L.length && (isCommentOrBlank(L[j]) || /^\s*@[A-Za-z]/.test(L[j]))) j++;
        target = (L[j] || '').trim();
      }
      if (!DECL_HEAD.test(target)) continue;          // 表达式位置 / init 参数表里的属性
      if (/->\s*some\s+View\b/.test(target)) continue;
      const isVar = /\bvar\b/.test(target);
      const m = /->\s*([^{]+?)\s*\{/.exec(target) || (isVar ? /:\s*([^{]+?)\s*\{/.exec(target) : null);
      if (!m) continue;                               // 没写显式类型 ⇒ 判不了 (豁免边界)
      const t = m[1].trim();
      if (!VALUE_TYPE.test(t)) continue;
      bad.push(f + ':' + (i + 1) + '  R2 @ViewBuilder 落到「' + target.slice(0, 56) + '」—— 显式类型 ' + t + ' 不是 some View');
    }
  }
  return bad;
}

function run(root) { return [...r1(root), ...r2(root), ...r4(root)]; }

// ---------- R4: 调用点的参数标签与声明对不上 (第一百四十八批新增) ----------
// Swift 要求调用点的外部标签与声明**逐字一致**：少写、多写、写错一个都不过编译
// ("missing argument label 'mac:' in call" / "the argument list for 'legendRow' must end with ')'")。
// 这一类是 run 43 之后最贵的缺陷形态 —— 名字眼熟、括号平衡、类型也对，只有编译器看得穿。
// 现网抓到 13 处 (清单与两轮的差别写在文件头 R4 那一段)，全部已修。
//
// 判据故意只做两种没有歧义的调用形状 (其余一律不判，理由写在下面两条豁免里)：
//  (a) `类型.方法(` —— 类型必须是**本次扫描目录里声明过**的类型，方法名以小写字母开头；
//  (b) `方法(` 且前面没有 `.` —— 该方法在同一个文件里声明，或是本目录里的顶层函数。
// 两种都是**逐位比对** (第一百四十八批第二版)：从第 0 位起比到"第一个判不了的位"为止，
//  并且只比调用实际写了的那些参数 —— 尾随闭包不在括号里、多行调用只能看到本行那一段，两种都只是漏判。
// 豁免 1 同名的 Apple 成员：`.tag(date:)`/`Calendar.startOfDay(for:)`/`arr.remove(at:)` 这些
//   都撞得上本仓某个函数名，上一版无差别扫描 210 条里 200 条是这种噪音 ⇒ 判不了就不报。
// 豁免 2 判不了的位：带默认值 (调用可以整个不传，后面的位置会前移)、闭包/函数类型参数
//   (常写成尾随闭包，位置会空出来)、同名重载 (两份标签表无从选) —— 都从那一位置起停。
// 只认三种括号。**不把 < > 当括号**：Swift 的 `-> ` 里那个 `>` 会被当成闭括号，
// 于是 `func run(_ n: Int, body: (Int) -> Void)` 的参数表在 `(Int` 处就被"配平"截断，
// 那个函数的闭包参数就消失了 ⇒ R5 会拿"少一个实参"去判尾随闭包的正确写法。
// 代价：泛型里带逗号的声明 (`Dictionary<String, Int>`) 会被切坏 → 那位判不了 → 跳过 (漏判不误判)。
// 这条是 ok/Arity.swift 那枚反控打出来的：它本来"应该 0 条"，第一版却报了一条。
const OPEN_CH = '([{';
const CLOSE_CH = ')]}';
const TYPE_LINE = /^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate )?(?:final )?(?:struct|class|enum|actor|extension)\s+([A-Za-z_]\w*)/;
const FUNC_LINE = /(?:^|[^\w.])func\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(/;
const STOP_WORDS = new Set(['if', 'for', 'while', 'switch', 'case', 'guard', 'return', 'where', 'as', 'is', 'catch', 'throw', 'init', 'deinit', 'subscript', 'get', 'set', 'willSet', 'didSet', 'func', 'let', 'var', 'in', 'else', 'do', 'repeat', 'defer', 'associatedtype', 'typealias', 'some', 'any', 'each', 'await', 'try', 'sizeof', 'print', 'dump', 'assert', 'precondition', 'fatalError']);

// 注释与字符串去掉后剩下的才是代码：字符串里的 `foo(` 不是调用点
function codeLines(raw) {
  const out = [];
  let block = false;
  for (const l of raw) {
    let s = stripLine(l);
    if (/"""/.test(s)) { block = !block; out.push(''); continue; }
    if (block) { out.push(''); continue; }
    out.push(s.replace(/"(?:[^"\\\n]|\\.)*"/g, '""'));
  }
  return out;
}
// 每一行落在哪个类型体内 (最内层)；顶层为 ''
function enclosingTypes(code) {
  const stack = [];
  const enc = [];
  let depth = 0;
  for (const ln of code) {
    const t = TYPE_LINE.exec(ln);
    enc.push(stack.length ? stack[stack.length - 1].name : '');
    const opens = (ln.match(/\{/g) || []).length;
    const closes = (ln.match(/\}/g) || []).length;
    if (t && opens > 0) stack.push({ name: t[1], depth });
    depth += opens - closes;
    while (stack.length && depth <= stack[stack.length - 1].depth) stack.pop();
  }
  return enc;
}
function balancedClose(text, openIdx) {   // text[openIdx] === '(' ⇒ 返回配平 ')' 的下标
  let d = 0;
  for (let k = openIdx; k < text.length; k++) {
    const c = text[k];
    if (OPEN_CH.includes(c)) d++;
    else if (CLOSE_CH.includes(c)) { d--; if (d === 0) return k; }
  }
  return -1;
}
function splitParams(s) {
  const out = [];
  let d = 0, cur = '';
  for (const c of s) {
    if (OPEN_CH.includes(c)) d++;
    if (CLOSE_CH.includes(c)) d--;
    if (c === ',' && d === 0) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur);
  return out;
}
// 每个参数 => {label, stop, fixed}。stop = 从这一位起往后都判不了 (见下面两条注释)；
// fixed = 这一位**允许**参与"实参个数"判定 (带默认值或闭包类型的位都不允许)。
function paramInfo(p) {
  const t = p.trim();
  const m = /^(_\s+[A-Za-z_]\w*\s*:|_\s*:|[A-Za-z_]\w*\s*:)/.exec(t);
  if (!t || !m) return { label: '?', stop: true, fixed: false };   // 元组解构、运算符、属性下标之类: 整条作废
  const label = m[1].startsWith('_') ? '_' : m[1].split(':')[0].trim();
  const stop = /=/.test(t) || /->/.test(t);        // 默认值可整个不传 / 闭包常写成尾随闭包 ⇒ 位置会空出来
  return { label, stop, fixed: !stop };
}
// 调用括号里的实参列表 (按顶层逗号切; 多行调用只能看到本行那一段 —— 那是漏判, 不是误判)
function callArgs(ln, openIdx) {
  const out = [];
  let d = 0, cur = '';
  for (let k = openIdx + 1; k < ln.length; k++) {
    const c = ln[k];
    if (OPEN_CH.includes(c)) d++;
    else if (CLOSE_CH.includes(c)) { if (d === 0) break; d--; }
    if (c === ',' && d === 0) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur);
  return out;
}
function put(table, key, params, file, line) {
  const sig = params.map(p => p.label + (p.stop ? '=' : '')).join();
  const arityFixed = params.every(p => p.fixed);          // 全表没有默认值/闭包参数 ⇒ 实参个数是定死的
  const prev = table.get(key);
  if (prev) { if (prev.sig !== sig) prev.conflict = true; return; }
  table.set(key, { params, sig, arityFixed, file, line });
}

function r4(root) {
  const bad = [];
  const files = swiftFiles(root);
  const statics = new Map();   // "TypeName.method" -> {params, sig, conflict}
  const members = new Map();   // "文件::method"     -> 同上 (同文件内的隐式 self 调用)
  const globals = new Map();   // "method"          -> 同上 (顶层函数, 全模块可直接调用)
  const parsed = [];
  for (const f of files) {
    const raw = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    const code = codeLines(raw);
    const enc = enclosingTypes(code);
    const text = code.join('\n');
    const lineStart = [0];
    for (let k = 0; k < text.length; k++) if (text[k] === '\n') lineStart.push(k + 1);
    const declRanges = [];
    for (let i = 0; i < code.length; i++) {
      const m = FUNC_LINE.exec(code[i]);
      if (!m) continue;
      const name = m[1];
      const openIdx = text.indexOf('(', lineStart[i] + m.index + m[0].length - 1);
      if (openIdx < 0) continue;
      const close = balancedClose(text, openIdx);
      if (close < 0) continue;
      const params = splitParams(text.slice(openIdx + 1, close)).map(paramInfo);
      declRanges.push([lineStart[i] + m.index, close]);      // 声明自己的那张表: 判不判得动都要记下, 扫描时好跳过
      // 零参声明也登记 (params 为空)。之前这里是 `if (!params.length) continue`，于是同名的
      // `func run(mac:)` 会把下面那行 `static func run() -> …` 的**定义处**当成"少传一个实参"的调用点 ——
      // 第一百五十一批 ok/Arity.swift 那枚反控专门盯这一对形状，一测就露了。
      const owner = enc[i];
      if (owner) put(statics, owner + '.' + name, params, f, i + 1);
      else put(globals, name, params, f, i + 1);
      put(members, f + '::' + name, params, f, i + 1);
    }
    parsed.push({ f, raw, code, text, declRanges, lineStart });
  }
  // 逐位比对：从第 0 位起，遇到"判不了的那一位"就整段停住 (默认值/闭包会让后面的位置前移或空出来)。
  // 只比调用**实际写了**的那些参数 —— 多行调用只能看到本行那一段、尾随闭包根本不在括号里，两种都只是漏判。
  const judge = (d, name, args, f, lineNo, how) => {
    if (!d || d.conflict) return;
    // R5: 实参个数。只在"参数表里没有默认值、也没有闭包参数"的声明上判 ——
    //     那种函数写不出尾随闭包 (少写一个实参就是不合法)，所以个数对不上就是编译器必拒。
    //     空表 `f()` 也算 ( arityFixed 的函数没有零参版本)。
    if (d.arityFixed && args.length !== d.params.length) {
      bad.push(`${f}:${lineNo}  R5 ${how} 声明要 ${d.params.length} 个实参, 这里括号里给了 ${args.length} 个 —— ${name}(${args.join(', ').slice(0, 40)}`);
    }
    let limit = d.params.length;
    for (let i = 0; i < d.params.length; i++) {
      if (d.params[i].label === '?' || d.params[i].stop) { limit = i; break; }
    }
    const n = Math.min(args.length, limit);
    for (let i = 0; i < n; i++) {
      const want = d.params[i].label;
      const a = args[i].trim();
      if (!a) continue;
      const labeled = /^[A-Za-z_]\w*\s*:/.test(a);
      const got = labeled ? a.split(':')[0].trim() : null;
      const pos = `第 ${i + 1} 个参数`;
      if (want === '_') {
        if (labeled) bad.push(`${f}:${lineNo}  R4 ${how} ${pos}声明**没有**外部标签, 这里却写了 "${got}:" —— ${name}(${a.slice(0, 34)}`);
      } else if (!labeled) {
        bad.push(`${f}:${lineNo}  R4 ${how} ${pos}标签应是 "${want}:", 这里按位置传 —— ${name}(${a.slice(0, 34)}`);
      } else if (got !== want) {
        bad.push(`${f}:${lineNo}  R4 ${how} ${pos}标签应是 "${want}:", 这里写的是 "${got}:" —— ${name}(${a.slice(0, 34)}`);
      }
    }
  };
  // 形状 (c) 试过、当场撤掉 (第一百四十八批)：`小写接收者.小写方法(` 只判"方法名在全目录里只有一份声明"的那些。
  // 实测 58 条命中，**逐条开代码看全是假的**：`list.remove(at:)`(Array)、`path.move(to:)`(Path)、
  // `s.range(of:options:)`(String)、`cal.startOfDay(for:)`(Calendar)、`buf.range(of:)`(Data)…
  // 这些都撞得上本仓某份唯一声明 (`LockArchive.remove(_)`、`RangeTable.range(fromDay:toDay:)`、`StatsKit.startOfDay(_)`、
  // `DesignSystem.move(_)`)。加豁免名单能压一时，但下一个同名 Apple 成员就会再冒一条 ——
  // 那正是 §10.11 里 apisig.js 被删掉的原因 (132 条假线索)，也是本批第一版探针 200/210 假的原因。
  // ⇒ 实例调用整个不判。要判它需要类型推导，那就是编译器的活，别用一把天天误报的尺子换。
  //
  // 第一百五十一批：调用点扫描改成**按整份文本走** (参数表跨行也取全)。按行截时
  // `legendRow(labels: mp.complete` 那种换行写法只能看见第一段 —— 现在两段都看得见，
  // 顺带把 R5 (实参个数) 接在同一条流水上。R5 只判"参数表里没有默认值、也没有闭包参数"的声明，
  // 因为那种函数**不可能**用尾随闭包少写一个实参，个数对不上就是编译器必拒。
  const scan = (re, nameOf, look, howOf) => {
    for (const { f, text, declRanges, lineStart } of parsed) {
      const lineOf = (off) => {
        let lo = 0, hi = lineStart.length - 1;
        while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (lineStart[mid] <= off) lo = mid; else hi = mid - 1; }
        return lo + 1;
      };
      const inDecl = (off) => declRanges.some(([a, b]) => off >= a && off <= b);
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(text))) {
        const name = nameOf(m);
        if (STOP_WORDS.has(name)) continue;
        const d = look(f, m, name);
        if (!d || d.conflict) continue;
        const openIdx = m.index + m[0].length - 1;
        const closeIdx = balancedClose(text, openIdx);
        if (closeIdx < 0) continue;
        if (inDecl(openIdx)) continue;                       // 声明自己的那张参数表
        const inner = text.slice(openIdx + 1, closeIdx).trim();
        const args = inner ? splitParams(inner) : [];
        judge(d, name, args, f, lineOf(m.index), howOf(m, name));
      }
    }
  };
  scan(/(?:^|[^\w.])([A-Z][A-Za-z0-9_]*)\.([a-z]\w*)\s*\(/g,
    (m) => m[2], (f, m, name) => statics.get(m[1] + '.' + name), (m, name) => m[1] + '.' + name);
  scan(/(?:^|[^\w.])([a-z]\w*)\s*\(/g,
    (m) => m[1], (f, m, name) => members.get(f + '::' + name) || globals.get(name), (m, name) => name);
  return bad;
}

// ---------- R3: 合成 Codable + 非 Optional 带默认值 = 加字段就会炸的雷区 (棘轮, 只许减不许增) ----------
// 本仓自己在 Store.swift:119 记着这条事实：**合成 Codable 对有默认值的属性同样要求键存在**。
// 于是"给一个持久化 struct 新加一个字段"这个最普通的动作，会让**加字段之前**写下的所有旧 JSON
// keyNotFound ⇒ DB.get 返回 nil ⇒ 界面上一切回落默认值，没有任何报错 (第一百三十七批给 LockMeta
// 加 grp 时就是这样炸的，那一炸是"老用户整本锁档案凭空变空"的量级)。
// LockMeta 已补显式 init(from:)。剩下这 14 个 struct 现在都还没被加过字段，所以不是现行缺陷 ——
// 但下一次有人往里塞字段就会是。棘轮写法 (基线只许减) 而不是判"有就是错"：
// 因为"当前没错"是真的，而"以后会错"也是真的，两个都得留下记录。
const R3_BASELINE = 13;   // 第一百八十七批由 14 下调 (CredAlert 补了显式解码器, 见 r3Gate 上方注释)

function r3Hits(root) {
  const hits = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const m = /^\s*(?:public |final )?struct\s+(\w+)\s*:[^{]*Codable/.exec(L[i]);
      if (!m) continue;
      let depth = 0;
      const body = [];
      // 整行写完的小 struct (`struct P: Codable { var a: String = "" }`) 也要看到体内字段 ——
      // 第一版只逐行往下收，注入探针 (`App/_probe_r3.swift`) 一测就不响，
      // 那个"绿"是假的：判据看不见单行写法，等于对这类形状完全失明。
      const sameLine = /\{\s*(.+?)\s*\}\s*$/.exec(L[i]);
      if (sameLine) body.push(sameLine[1]);
      for (let j = i; j < L.length; j++) {
        const ln = stripLine(L[j]);
        depth += (ln.match(/\{/g) || []).length - (ln.match(/\}/g) || []).length;
        if (j > i && sameLine === null) body.push(L[j]);
        if (depth <= 0 && j > i) break;
      }
      const text = body.join('\n');
      if (/init\s*\(\s*from\s/.test(text)) continue;                 // 有显式解码器的不在名单里
      const risky = body.filter(l => /^\s*var\s+\w+\s*:\s*[^?{=\n]+=/.test(l) && !/\?\s*=/.test(l));
      if (risky.length) hits.push(`${f}:${i + 1}  R3 雷区 struct ${m[1]} —— ${risky.length} 个非 Optional 带默认值字段, 无显式 init(from:)`);
    }
  }
  return hits;
}

function selftest() {
  const dir = path.join(ROOT, 'fixtures', 'swiftshape');
  const shouldFire = run(path.join(dir, 'fire'));
  const shouldNot = run(path.join(dir, 'ok'));
  const n4 = shouldFire.filter(h => h.includes(' R4 ')).length;
  const n5 = shouldFire.filter(h => h.includes(' R5 ')).length;
  const n1 = shouldFire.filter(h => h.includes(' R1 ')).length;
  const n2 = shouldFire.filter(h => h.includes(' R2 ')).length;
  // fire/ 里 R4 有**四处**有问题的调用，报出 5 条：按位置传那一处第 1、第 2 个参数都少标签，逐位判就该各报一次。
  // R5 有两条：少一个实参、多一个实参。
  if (n1 !== 1 || n2 !== 1 || n4 !== 5 || n5 !== 2) {
    console.log(`✗ 正控失败: fire/ 里 R1/R2 各应 1 条、R4 应 5 条、R5 应 2 条，实得 R1=${n1} R2=${n2} R4=${n4} R5=${n5}`);
    console.log(shouldFire.join('\n'));
    return 2;
  }
  if (shouldNot.length !== 0) {
    console.log('✗ 正控失败: ok/ 里应 0 条，实得 ' + shouldNot.length);
    console.log(shouldNot.join('\n'));
    return 2;
  }
  const riskyFire = r3Hits(path.join(dir, 'fire'));
  const riskyOk = r3Hits(path.join(dir, 'ok'));
  const wantBoth = ['R3Risky', 'R3RiskyOneLine'];
  const missed = wantBoth.filter(n => !riskyFire.some(h => h.includes('struct ' + n + ' ')));
  if (riskyFire.length !== 2 || riskyOk.length !== 0 || missed.length) {
    console.log(`✗ 正控失败: R3 应数出 fire/ 的两个雷区 struct (多行 + 整行写完那种)，`
      + `实得 fire=${riskyFire.length} ok=${riskyOk.length} 漏=${missed.join(',') || '无'}`);
    console.log([...riskyFire, ...riskyOk].join('\n'));
    return 2;
  }
  console.log('正控 ✓ (R1/R2 各开火一次；R3 两种写法都数得出，且放过有显式解码器的那个；'
    + 'R4 四处有问题的调用报满 5 条 (含第二个标签写错那种只有逐位判才看得见的)；'
    + 'R5 少参与多参各一条；ok/ 里尾随闭包与带默认值这两种"括号里个数少"的合法写法一条不响)');
  return 0;
}

/// R3 棘轮: 只有**新增**才判失败。基线 13 个 —— 第一百八十七批从 14 下调:
/// `CredAlert` 早在 cc7a569 (926/930 那批) 就补上了显式 `init(from:)`，棘轮却拖了 20 个 commit 没落。
/// 为什么一直没人看见: 摘要行印的是**基线**而不是实数 ("停在基线 14 个")，与提示行算出的 13 自相矛盾，
/// 读的人自然信了那句"停在基线 14"。现在摘要改印实数 (r3Count)，这类"闸门用自己的常量替实况说话"的口子堵掉。
function r3Count() {
  let n = 0;
  for (const d of DIRS) n += r3Hits(path.join(ROOT, d)).length;
  return n;
}
function r3Gate() {
  const hits = [];
  for (const d of DIRS) hits.push(...r3Hits(path.join(ROOT, d)));
  if (hits.length === R3_BASELINE) return [];
  if (hits.length < R3_BASELINE) {
    console.log(`提示: R3 雷区比基线少 ${R3_BASELINE - hits.length} 个 —— 把 R3_BASELINE 改成 ${hits.length} (棘轮只许往下调)`);
    return [];
  }
  return [`${hits.length} 个合成 Codable 雷区 (基线 ${R3_BASELINE}) —— 新增的那几个必须先补显式 init(from:)，`
    + `否则加字段之前写下的旧 JSON 会 keyNotFound，DB.get 返回 nil，界面上只是静静地回落默认值:`]
    .concat(hits.slice(0, 20));
}

if (process.argv.includes('--selftest')) process.exit(selftest());
else {
  const st = selftest();
  if (st !== 0) process.exit(st);
  const bad = [];
  for (const d of DIRS) bad.push(...run(path.join(ROOT, d)));
  bad.push(...r3Gate());
  if (bad.length) {
    console.log('Swift 形状机检判失败 (' + bad.length + ' 条):');
    console.log(bad.join('\n'));
    process.exit(1);
  }
  console.log('Swift 形状机检 ✓ (R1 缺 @ViewBuilder / R2 属性挂到值类型 / R4 调用点参数标签对不上 / '
    + 'R5 实参个数对不上 — 零命中; R3 合成 Codable 雷区 ' + r3Count() + ' 个, 基线 ' + R3_BASELINE + ' 个)');
}
