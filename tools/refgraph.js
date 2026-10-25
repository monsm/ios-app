#!/usr/bin/env node
// 引用图可达性分析 —— 找「叶子」: 只被死代码引用的整片区域
// 用法: node tools/refgraph.js [--json]
//
// 与 deadscan.js 的分工:
//   deadscan 数「这个名字全仓出现几次」, 只报一次都不被调用的。
//   refgraph 建 声明->引用 的有向图, 从入口做可达性传播; 不可达的整片区域就是叶子。
//   「一层层删」要的正是这个: 删掉第一轮叶子后, 原来引用它的代码变成新叶子, 再跑一次继续。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ARGS = process.argv.slice(2);
const AS_JSON = ARGS.includes('--json');

function swiftFiles(dir) {
  let out = [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(swiftFiles(f));
    else if (e.name.endsWith('.swift')) out.push(f);
  }
  return out;
}

const SRC_DIRS = ['App', 'Widget', 'Shared'];
const declFiles = SRC_DIRS.flatMap(d => swiftFiles(path.join(ROOT, d)));
const testFiles = swiftFiles(path.join(ROOT, 'Tests'));
const norm = f => path.relative(ROOT, f).split(path.sep).join('/');
const LF = String.fromCharCode(10);
const BSLASH = String.fromCharCode(92);

// 去注释, 保留字符串内容（字符串里可能有 selector / 通知名 / systemName 的真实引用）
function stripComments(text) {
  let out = '', i = 0, n = text.length, inBlock = false;
  while (i < n) {
    const c = text[i], d = text[i + 1];
    if (inBlock) {
      if (c === '*' && d === '/') { inBlock = false; i += 2; continue; }
      if (c === LF) out += c;
      i++; continue;
    }
    if (c === '/' && d === '/') { while (i < n && text[i] !== LF) i++; continue; }
    if (c === '/' && d === '*') { inBlock = true; i += 2; continue; }
    if (c === '"') {
      if (text.slice(i, i + 3) === '"""') {
        out += text.slice(i, i + 3); i += 3;
        while (i < n && text.slice(i, i + 3) !== '"""') { out += text[i]; i++; }
        out += '"""'; i += 3; continue;
      }
      out += c; i++;
      while (i < n && text[i] !== '"') {
        if (text[i] === BSLASH) { out += text[i]; i++; }
        if (i < n) { out += text[i]; i++; }
      }
      out += '"'; i++; continue;
    }
    out += c; i++;
  }
  return out;
}

function braceDelta(s) {
  let d = 0;
  for (const ch of s) { if (ch === '{') d++; else if (ch === '}') d--; }
  return d;
}

// ---- 1. 切声明 ----
const decls = [];
const seen = new Set();

const RE_TYPE = /^\s*(?:@[\w()]+\s+)*(?:public\s+|private\s+|fileprivate\s+|internal\s+|open\s+|final\s+)*(struct|class|enum|actor|protocol|extension)\s+([A-Za-z_][\w]*)/;
const RE_FUNC = /^\s*(?:@[\w()]+\s+)*(?:public\s+|private\s+|fileprivate\s+|internal\s+|open\s+|static\s+|class\s+|final\s+|mutating\s+|nonisolated\s+)*func\s+([A-Za-z_][\w]*)/;
const RE_VAR  = /^\s*(?:@[\w()]+\s+)*(?:public\s+|private\s+|fileprivate\s+|internal\s+|open\s+|static\s+|class\s+|final\s+|nonisolated\s+)*var\s+([A-Za-z_][\w]*)/;

function collectFromFile(file) {
  const rel = norm(file);
  const lines = stripComments(fs.readFileSync(file, 'utf8').replace(/\r\n/g, LF)).split(LF);
  const stack = [];
  let depth = 0;
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i];
    const tm = t.match(RE_TYPE);
    const fm = t.match(RE_FUNC);
    const vm = t.match(RE_VAR);
    const fullOwner = stack.join('.');
    // 成员只允许出现在「恰好一层」的类型体里: depth === stack.length 表示正处于当前 type 的直接子层。
    // 之前的写法没收这个约束, 于是函数体里的局部 var 被当成成员报了出来 (RecordsView 一次误报 30 条)。
    const atMemberLevel = depth === stack.length;
    if (tm) {
      const isExt = tm[1] === 'extension';
      if (!isExt) {
        const key = (fullOwner ? fullOwner + '.' : '') + tm[2];
        // 往上看几行抓属性 (@main / @Observable …)。属性行在声明行**之前**,
        // 只扫声明行会漏掉 @main —— LockKeeperApp 那次就是这样被误判成不可达的。
        let attrs = '';
        for (let k = i - 1; k >= 0 && k >= i - 4; k--) {
          const prev = lines[k].trim();
          if (prev === '' || prev.startsWith('@') || prev.startsWith('//')) { attrs = lines[k] + LF + attrs; continue; }
          break;
        }
        if (!seen.has(key)) { seen.add(key); decls.push({ key, kind: 'type', name: tm[2], owner: fullOwner || null, file: rel, line: i + 1, attrs }); }
      }
      stack.push(tm[2]);
    } else if (fm && stack.length && atMemberLevel) {
      // 重载必须各自成条: peripheral(_:didUpdateNotificationStateFor:) / didUpdateValueFor / didWriteValueFor
      // 同名不同参, 只保留第一个会让后面几个的**函数体**根本不进分析 —— 它们调用的 emit/finishConnect
      // 因此被误判成零引用 (实测两条)。
      const key = fullOwner + '.' + fm[1] + '@' + (i + 1);
      if (!seen.has(key)) { seen.add(key); decls.push({ key, kind: 'func', name: fm[1], owner: fullOwner, file: rel, line: i + 1 }); }
    } else if (fm && !stack.length) {
      const key = fm[1] + '@' + (i + 1);
      if (!seen.has(key)) { seen.add(key); decls.push({ key, kind: 'func', name: fm[1], owner: null, file: rel, line: i + 1 }); }
    } else if (vm && stack.length && atMemberLevel) {
      const key = fullOwner + '.' + vm[1] + '@' + (i + 1);
      if (!seen.has(key)) { seen.add(key); decls.push({ key, kind: 'var', name: vm[1], owner: fullOwner, file: rel, line: i + 1 }); }
    }
    depth += braceDelta(t);
    while (stack.length && depth < stack.length) stack.pop();
  }
}

for (const f of declFiles) collectFromFile(f);

// ---- 2. 按文件切块（声明行 -> 下一条声明行）----
const fileLines = new Map();
for (const f of declFiles) {
  const rel = norm(f);
  fileLines.set(rel, stripComments(fs.readFileSync(f, 'utf8').replace(/\r\n/g, LF)).split(LF));
}
const byFile = new Map();
for (const d of decls) { if (!byFile.has(d.file)) byFile.set(d.file, []); byFile.get(d.file).push(d); }
for (const entry of byFile) {
  const f = entry[0], list = entry[1];
  list.sort((a, b) => a.line - b.line);
  const lines = fileLines.get(f);
  for (let k = 0; k < list.length; k++) {
    const start = list[k].line - 1;
    const end = (k + 1 < list.length) ? list[k + 1].line - 1 : lines.length;
    list[k].chunk = lines.slice(start, end).join(LF);
  }
}

// ---- 3. 引用边 ----
const byName = new Map();
for (const d of decls) { if (!byName.has(d.name)) byName.set(d.name, []); byName.get(d.name).push(d); }
const EDGES = new Map();
for (const d of decls) {
  const set = new Set();
  const tokens = (d.chunk || '').match(/\b[A-Za-z_][\w]*\b/g) || [];
  for (const tok of tokens) { if (tok !== d.name && byName.has(tok)) set.add(tok); }
  EDGES.set(d.key, set);
}

// ---- 4. 根 ----
const PROTOCOL_NAMES = new Set([
  'body','makeBody','perform','makeCoordinator','makeUIViewController','updateUIViewController','dismantleUIViewController','placeSubviews',
  'transferRepresentation','encode','decode','application','scene','run','init','deinit',
  'numberOfPreviewItems','previewController','itemsForBeginning','urandom',
  'userNotificationCenter','peripheralIsReady','centralManager','centralManagerDidUpdateState','appShortcuts','main',
  'fileWrapper','readableContentTypes','readConfiguration',
  // WidgetKit: TimelineProvider 的三个方法都由系统按名回调, 源码里不会有调用点
  'getSnapshot','getTimeline','placeholder','snapshot','timeline',
  // WidgetKit: AppIntentTimelineProvider / Widget 的 configurationDisplayName 等
  'configurationDisplayName','supportedFamilies','relevance',
  // ActivityKit: ActivityAttributes 要求的嵌套 ContentState 由系统按名编码
  'ContentState','Attributes','makeConfiguration',
  // AppIntents
  'openAppWhenRun','staticParameterSummary','parameterSummary',
  // CoreBluetooth / 通知 其余回调
  'didReceive','willPresent','didRegisterForRemoteNotificationsWithDeviceToken',
  // MessageUI / VisionKit / QuickLook 的 delegate 回调 —— 全部由系统按名调, 源码里没有调用点。
  // 这三条是被本工具误判后逐条人工核出来的: 删掉任何一个都会让"发邮件 / 扫码 / 预览"当场失效。
  'mailComposeController','dataScanner','previewController','documentPicker',
  // Error/ErrorDescription 协议
  'errorDescription','failureReason','recoverySuggestion','helpAnchor',
]);
const ROOT_ATTR = /@main|WidgetBundle|AppIntent|AppShortcutsProvider|UIApplicationDelegate|UNUserNotificationCenterDelegate|CBCentralManagerDelegate|CBPeripheralDelegate|FileDocument|Transferable|ButtonStyle|ViewModifier|PreviewProvider|#Preview/;
const roots = new Set();
for (const d of decls) {
  if (PROTOCOL_NAMES.has(d.name)) roots.add(d.key);
  if (ROOT_ATTR.test((d.attrs || '') + LF + (d.chunk || ''))) roots.add(d.key);
}


// ---- 5. 传播 ----
const reachable = new Set();
const queue = [];
function push(k) { if (!reachable.has(k)) { reachable.add(k); queue.push(k); } }
for (const k of roots) push(k);
const testText = testFiles.map(f => stripComments(fs.readFileSync(f, 'utf8'))).join(LF);
for (const d of decls) {
  if (!reachable.has(d.key) && new RegExp('\\b' + d.name + '\\b').test(testText)) push(d.key);
}
while (queue.length) {
  const k = queue.pop();
  const refs = EDGES.get(k);
  if (!refs) continue;
  for (const nm of refs) { for (const t of (byName.get(nm) || [])) push(t.key); }
}

// 嵌套类型: **只**把协议要求的嵌套类型当根。
// 不能笼统地"外层可达 ⇒ 内层可达": 那会把 LockGuard 里 11 个从未接线的安全成员、
// DesignSystem 的 summon/fling 等真正零引用的成员一起洗白 (实测一次误救 42 条)。
// 系统按名取的只有这些: ActivityAttributes.ContentState / TimelineProvider 的 Entry 等。
const REQUIRED_NESTED = new Set(['ContentState', 'Attributes', 'Entry', 'Configuration', 'Intent']);
for (const d of decls) {
  if (REQUIRED_NESTED.has(d.name)) reachable.add(d.key);
}

// 嵌套类型的补充判定: 外层可达 + 内层名出现在**类型位置** (而非仅声明处) ⇒ 算可达。
// 例: AXTools.calcTokens[i].name —— CalcToken 这个名字在调用点根本没出现, 但
//     calcTokens 的类型是 [CalcToken], 声明行里有 "[CalcToken]"。只看"名字被引用几次"
//     会把它误判成死码 (实测 AXTools.CalcToken / DiagLogs.EntityRef.Kind 两处)。
{
  const typePos = new Map();   // name -> true
  for (const d of decls) {
    const chunk = d.chunk || '';
    for (const m of chunk.matchAll(/[:<(\[,]\s*([A-Z][A-Za-z0-9_]*)\b/g)) typePos.set(m[1], true);
    for (const m of chunk.matchAll(/->\s*([A-Z][A-Za-z0-9_]*)\b/g)) typePos.set(m[1], true);
  }
  for (const d of decls) {
    if (reachable.has(d.key) || !d.owner) continue;
    if (!reachable.has(d.owner)) continue;
    if (typePos.get(d.name)) reachable.add(d.key);
  }
}


// debug: dump chunk for a given key
if (process.argv.includes('--dump')) {
  const want = process.argv[process.argv.indexOf('--dump') + 1];
  const d = decls.find(x => x.key === want || x.name === want);
  if (d) { console.log('KEY', d.key, 'file', d.file, 'line', d.line); console.log('CHUNK:'); console.log(d.chunk); }
  else console.log('not found');
  process.exit(0);
}

// ---- 6. 输出 ----
const dead = decls.filter(d => !reachable.has(d.key));
if (AS_JSON) {
  console.log(JSON.stringify({ total: decls.length, reachable: reachable.size, dead: dead.map(d => ({ key: d.key, kind: d.kind, file: d.file, line: d.line })) }, null, 1));
} else {
  console.log('声明总数 ' + decls.length + ' · 可达 ' + reachable.size + ' · 不可达 ' + dead.length);
  const byF = new Map();
  for (const d of dead) { if (!byF.has(d.file)) byF.set(d.file, []); byF.get(d.file).push(d); }
  const sorted = [...byF.entries()].sort((a, b) => b[1].length - a[1].length);
  for (const e of sorted) {
    console.log('');
    console.log('  ' + e[0] + '  (' + e[1].length + ')');
    for (const d of e[1].slice(0, 50)) console.log('    ' + String(d.line).padStart(5) + '  ' + d.kind.padEnd(5) + '  ' + d.key);
    if (e[1].length > 50) console.log('    ... 还有 ' + (e[1].length - 50) + ' 条');
  }
}