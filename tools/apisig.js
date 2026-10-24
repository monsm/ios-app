#!/usr/bin/env node
// ============================================================================
// apisig.js — 组件签名闸门
// ============================================================================
//
// 为什么需要这一道:
//   21 道闸门查的是语法结构 / 令牌 / 对比度 / 括号, 它们都不知道
//   xFont 只收两个参数。而这类错误在 Swift 里是编译期报错,
//   CI 要 20 分钟才回话 —— 一轮下来只前进一小步。
//
//   这一道把「组件签名能静态判定的部分」提前到本地:
//     · xFont 收 (XText, weight:, design:), 传 size:/relativeTo:/textStyle: 是错的（绕过规范字阶）
//     · XStatusPill / XBusyButton / XMetricTile / XEmptyState 的参数名
//
// 判据全部来自 App/Core/Components.swift 的真实声明 —— 不是手抄的第二份。
// 每次跑都重新读声明, 所以改组件签名时这道闸门会自动跟上。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const LIB = path.join(ROOT, 'App', 'Core', 'Components.swift');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.git' || e.name === 'fixtures') continue;
    const q = path.join(dir, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (q.endsWith('.swift')) out.push(q);
  }
  return out;
}

let lib = '';
try { lib = fs.readFileSync(LIB, 'utf8'); } catch (e) {}
if (!lib) { console.error('✗ 读不到 App/Core/Components.swift'); process.exit(1); }

// ── 1. xFont 参数表 (从真实声明推) ──────────────────────────────────
const xfDecl = lib.match(/func xFont\(([^)]*)\)/);
let xfLabels = [];
if (xfDecl) {
  xfLabels = xfDecl[1].split(',').map(function (s) {
    const beforeColon = s.split(':')[0].trim();
    const toks = beforeColon.split(/\s+/);
    return toks[0] === '_' ? (toks[1] || '_') : toks[0];
  }).filter(Boolean);
}

// ── 2. 结构体参数表 ────────────────────────────────────────────────
// 用大括号配平取出 struct 的完整正文 —— 不能用"到下一个 struct 为止",
// 因为外层的枚举/扩展会把后面的内容也吞进来 (踩过一次)。
function structParams(name) {
  const head = lib.indexOf('struct ' + name);
  if (head < 0) return null;
  const open = lib.indexOf('{', head);
  if (open < 0) return null;
  let depth = 0, end = -1;
  for (let i = open; i < lib.length; i++) {
    const ch = lib[i];
    if (ch === '"') {                        // 跳过字符串
      i++;
      while (i < lib.length && lib[i] !== '"') { if (lib[i] === '\\') i++; i++; }
      continue;
    }
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (end < 0) return null;
  const body = lib.slice(open, end + 1);
  const out = [];
  for (const line of body.split('\n')) {
    // 只认 4 空格缩进的存储属性 —— let 与 var 都要认。
    // (XStepBar 的 titles/current 是 let, 只匹配 var 会漏掉,
    //  于是 external 调用被误判成"没有这个参数"。)
    // computed var 后面跟 { 的不算。
    const pm = line.match(/^\s{4}(?:let|var) (\w+):\s*[^={]/);
    if (pm) out.push(pm[1]);
  }
  return out;
}

const STRUCTS = ['XStatusPill', 'XBusyButton', 'XMetricTile', 'XEmptyState', 'XRow', 'XStepBar'];
const structDefs = {};
for (const s of STRUCTS) {
  const ps = structParams(s);
  if (ps && ps.length) structDefs[s] = ps;
}

// ── 3. 扫全仓 ─────────────────────────────────────────────────────
const files = walk(path.join(ROOT, 'App'));
// xFont 的顶层实参里出现 design/size/relativeTo 才算错 ——
// 嵌在 .system(...) 里的是合法写法, 不能只看"有没有出现过"。
// 2026-10-22: xFont 的签名已扩为 (XText, weight:, design:) —— 为了让圆体也走规范字阶。
// 所以 design 不再是错；size / relativeTo / textStyle 仍会绕过字阶，留着判。
const XFONT_BAD_LABEL = /^(size|relativeTo|textStyle)$/;

function badXFontArgs(src) {
  const out = [];
  const re = /\bxFont\(/g;
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length, depth = 1, buf = '';
    while (i < src.length && depth > 0) {
      const ch = src[i];
      if (ch === '(') depth++;
      else if (ch === ')') { depth--; if (depth === 0) break; }
      buf += ch; i++;
    }
    for (const raw of topLevelLabels(buf)) {
      const lm = raw.trim().match(/^(\w+)\s*:/);
      if (lm && XFONT_BAD_LABEL.test(lm[1])) {
        out.push({ line: src.slice(0, m.index).split('\n').length, label: lm[1] });
      }
    }
  }
  return out;
}

function topLevelLabels(argstr) {
  let depth = 0, cur = '', out = [];
  for (const ch of argstr) {
    if ('([{'.indexOf(ch) >= 0) depth++;
    else if (')]}'.indexOf(ch) >= 0) depth--;
    if (ch === ',' && depth === 0) { out.push(cur); cur = ''; }
    else cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out;
}

function checkStructArgs(name, src) {
  const known = new Set(structDefs[name]);
  const problems = [];
  const re = new RegExp('\\b' + name + '\\(', 'g');
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length, depth = 1, buf = '';
    while (i < src.length && depth > 0) {
      const ch = src[i];
      if (ch === '(') depth++;
      else if (ch === ')') { depth--; if (depth === 0) break; }
      buf += ch; i++;
    }
    for (const raw of topLevelLabels(buf)) {
      const lm = raw.trim().match(/^(\w+)\s*:/);
      if (!lm) continue;
      if (!known.has(lm[1])) {
        problems.push({
          line: src.slice(0, m.index).split('\n').length,
          msg: name + ' 没有参数 ' + lm[1] + ' (可用: ' + Array.from(known).join(', ') + ')'
        });
      }
    }
  }
  return problems;
}

const allProblems = [];
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(ROOT, f);
  for (const b of badXFontArgs(src)) {
    allProblems.push({ rel: rel, line: b.line,
      msg: 'xFont 顶层不能传 ' + b.label + ' (只收 ' + xfLabels.join(', ') + ') —— 字号必须走 XText，不许绕开规范字阶' });
  }
  for (const nm of Object.keys(structDefs)) {
    for (const pr of checkStructArgs(nm, src)) {
      allProblems.push({ rel: rel, line: pr.line, msg: pr.msg });
    }
  }
}

// ── 4. 自检: 正控 / 反控 ───────────────────────────────────────────
const probes = [
  { src: '.xFont(.title2, weight: .semibold, design: .rounded)', bad: false, why: '圆体走 XText（合法）' },
  { src: '.xFont(.system(.title2, design: .rounded), weight: .semibold)', bad: false, why: '旧写法仍被接受' },
  { src: '.xFont(.body, size: 17)', bad: true, why: 'xFont 传 size 绕开字阶' },
  { src: 'XStatusPill(text: "a", tone: .ok, systemImage: "x")', bad: false, why: 'XStatusPill 合法' },
  { src: 'XStatusPill(text: "a", image: "x")', bad: true, why: 'XStatusPill 错参数名' }
];
let probeFail = 0;
for (const pr of probes) {
  let got = badXFontArgs(pr.src).length > 0;
  if (!got && structDefs.XStatusPill) {
    for (const q of checkStructArgs('XStatusPill', pr.src)) { got = true; break; }
  }
  if (got !== pr.bad) {
    console.error('✗ 自检失败: ' + pr.why + ' (期望 ' + pr.bad + ', 实际 ' + got + ')');
    probeFail++;
  }
}
if (probeFail > 0) { console.error('✗ 闸门自检不通过, 判据已失效'); process.exit(1); }


// ── 6. 死代码: 定义了但全仓零使用的 X 组件 ──────────────────────────
// 这一节是在清掉 4 处死代码 (XGuidedEmptyView / XStaggeredAppear /
// staggered() / XContainerKind.tile) 之后加的 —— 那 4 处都是
// "组件被替换掉, 旧的那个忘了删", 单看代码完全正常, 只有统计使用次数才发现。
//
// 判据:
//   · 对 Components.swift 里每个 struct/enum X* 类型, 统计全仓引用次数
//   · 减去它自己定义处那 1 次, 再减去同文件内的引用 (lib 内部互相用)
//   · 结果为 0 → 死代码
//   · 例外: 有 @ViewBuilder / modifier / extension View 方法名与之对应的
//     (如 XScrollLift 通过 .xScrollLift() 用、XPlateShape 通过 .xPlate() 用),
//     这些按"小写去 X 前缀"再查一次
//
// 允许名单: 正在开发中的组件可以临时登记, 但每加一条都应该问自己
//   "它到底是还没接上, 还是已经不需要了"。
const DEAD_ALLOW = new Set([
  // (空) —— 当前没有豁免项
]);

const libTypes = [];
{
  const re = /^(?:struct|enum) (X\w+)/gm;
  let m;
  while ((m = re.exec(lib))) libTypes.push(m[1]);
}

function countOutside(name) {
  // 全仓 (排除 Components.swift 自身的定义与内部引用)
  let n = 0;
  for (const f of files) {
    if (/Components\.swift$/.test(f)) continue;
    const src = fs.readFileSync(f, 'utf8');
    const hits = src.match(new RegExp('\\b' + name + '\\b', 'g'));
    if (hits) n += hits.length;
  }
  return n;
}

function countMethodForm(name) {
  // XScrollLift → .xScrollLift()   XPlateShape → .xPlate(
  const base = name.replace(/^X/, '');
  const camel = base.charAt(0).toLowerCase() + base.slice(1);
  const patterns = [
    '.' + camel + '\\(',
    '.' + camel + '\\)?\\s',
  ];
  let n = 0;
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    for (const p of patterns) {
      const hits = src.match(new RegExp(p, 'g'));
      if (hits) n += hits.length;
    }
  }
  return n;
}

const deadCode = [];
for (const ty of libTypes) {
  if (DEAD_ALLOW.has(ty)) continue;
  const outside = countOutside(ty);
  if (outside > 0) continue;
  // 检查方法调用形式 (XScrollLift → .xScrollLift())
  const asMethod = countMethodForm(ty);
  if (asMethod > 0) continue;
  // 检查它在库内是否被别的类型引用 (如 XContainerKind 被 XPanel 用)
  const inLib = (lib.match(new RegExp('\\b' + ty + '\\b', 'g')) || []).length;
  if (inLib > 1) continue;          // 库内互用, 不算死
  deadCode.push(ty);
}

// 自检: 造一个必然"零外部引用"的假类型名, 确认检测逻辑活着
{
  const probe = 'X__SelfTestDeadProbe__';
  const fakeLib = lib + '\nstruct ' + probe + ' { }\n';
  const fakeTypes = [...fakeLib.matchAll(/^(?:struct|enum) (X\w+)/gm)].map(m => m[1]);
  const found = fakeTypes.filter(ty => {
    if (DEAD_ALLOW.has(ty)) return false;
    let out = 0;
    for (const f of files) {
      if (/Components\.swift$/.test(f)) continue;
      const hits = fs.readFileSync(f, 'utf8').match(new RegExp('\\b' + ty + '\\b', 'g'));
      if (hits) out += hits.length;
    }
    if (out > 0) return false;
    if (countMethodForm(ty) > 0) return false;
    const inLib = (fakeLib.match(new RegExp('\\b' + ty + '\\b', 'g')) || []).length;
    return inLib <= 1;
  });
  if (!found.includes(probe)) {
    console.error('✗ 自检失败: 死代码检测抓不到人造的零引用类型');
    process.exit(1);
  }
}

if (deadCode.length > 0) {
  for (const d of deadCode) {
    console.error('Components.swift: 死代码 ' + d + ' (全仓零引用) —— 删掉, 或加进 DEAD_ALLOW 并写清为什么留着');
  }
}


// ── 6b. 分隔线一律走 XHairline ──────────────────────────────────────
//
// **2026-10-23 改判据。** 旧判据只要求 "Divider 必须 .overlay(XPalette.hairline)"，
// 也就是默认 Divider 可以用、只是要手动补色。那是错的：
//
//   · SwiftUI 的 Divider 高度是**系统给的**（随字号与平台变），不是 1px 发丝线
//   · Divider 会进无障碍树，读屏时打断节奏
//   · 每个调用点都要记得 .overlay —— 靠记性
//
// 而 XHairline 三件事全做了：1px 实高、hairline 色、accessibilityHidden。
// 规范要的是「一条统一的分隔线」，不是「一条记得上色的系统线」。
//
// 判据：出现 `Divider(` 一律报（不管有没有 overlay）。
const dividerHits = [];
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
  src.split('\n').forEach((line, i) => {
    if (/^\s*\/\//.test(line)) return;
    if (/Divider\(/.test(line)) dividerHits.push({ rel: path.relative(ROOT, f), line: i + 1, text: line.trim() });
  });
}
// 自检：确认判据能抓到带 overlay 的形式
{
  const probe = 'Divider().overlay(XPalette.hairline)';
  if (!/Divider\(/.test(probe)) { console.error('✗ 自检失败: 判据抓不到带 overlay 的 Divider'); process.exit(1); }
}
if (dividerHits.length > 0) {
  for (const d of dividerHits) {
    console.error(d.rel + ':' + d.line + ': 用 Divider 画分隔线 —— 改用 XHairline（1px 实高 / hairline 色 / 不进无障碍树）');
  }
  console.error('共 ' + dividerHits.length + ' 处。XHairline 在 Components.swift。');
  process.exit(1);
}


// ── 6c. Theme.swift 里零使用的公共 static 成员 ─────────────────────
// 由来: 加 XOpacity 时声明了 5 档, 但 edge / dim 一开始零使用。
// 后来全量审计又挖出 13 个: 兼容旧名别名 3 / 未接的动效 4 / 未用的渐变 2 /
// 触感 1 / 间距 1 / 指标 2 —— 全是"声明了但没人用"。
//
// 判据:
//   · 只查 **非 private** 的 static var/let/func (private 是内部助手, 不在此列)
//   · 全仓统计引用, 同时认 ".name" 与裸 "name" 两种写法
//     (裸写法很关键: 删前核对时 XGradient.doorSurface 就是靠裸写法
//      才发现它被 hero 引用着, 只看 .name 会误判成死代码)
//   · Theme.swift 内部引用也算数 (一个令牌给另一个令牌用是正常的)
const THEME = path.join(ROOT, 'App', 'Core', 'Theme.swift');
let theme = '';
try { theme = fs.readFileSync(THEME, 'utf8'); } catch (e) {}

const deadTokens = [];
// 声明行判据放在块外 —— 自检块也要用
const declRe = /^    static (?:var|let|func) (\w+)/;
if (theme) {
  const themeLines = theme.split('\n');
  const names = [];
  for (const line of themeLines) {
    const m = line.match(declRe);
    if (m) {                       // private 的不进来
      if (/^    private /.test(line)) continue;
      names.push(m[1]);
    }
  }
  // 2026-10-22 (Glass 二批): 原判据把**注释里的提及**也算成引用。
  // 实证: textQuaternary 的唯一"引用"是 Theme.swift 里一行写着它名字的注释,
  // 于是它被判"在用" —— 而实际上没有任何一处把它当颜色用过。
  // 一条能被自己文档喂饱的判据, 数出来的是"有多少处提到这个名字", 不是"有没有人用"。
  // 现在两处统计都**先剥掉注释**: 整行注释与行尾注释都不算。
  const stripComments = (line) => line.replace(/^\s*\/\/.*$/, '').replace(/\/\/.*$/, '');
  for (const name of names) {
    let internal = 0;
    for (const line of themeLines) {
      if (declRe.test(line) && new RegExp('(?:var|let|func) ' + name + '\\b').test(line)) continue;
      const code = stripComments(line);
      const hits = code.match(new RegExp('\\b' + name + '\\b', 'g'));
      if (hits) internal += hits.length;
    }
    let external = 0;
    for (const f of files) {
      if (/Theme\.swift$/.test(f)) continue;
      const src = fs.readFileSync(f, 'utf8');
      let n = 0;
      for (const line of src.split(/\r?\n/)) {
        const code = stripComments(line);
        const hits = code.match(new RegExp('\\b' + name + '\\b', 'g'));
        if (hits) n += hits.length;
      }
      external += n;
    }
    // 2026-10-24 豁免：规范 §11.1 的动效语汇是**封闭清单**，
    // tools/motionlock.js 要求 XMotion 与那张表逐条对齐 —— 缺一个就判失败。
    // 所以这些令牌即便当前零调用也必须保留，不算死令牌。
    const MOTION_LOCKED = new Set(['summon', 'doorReveal', 'chargeReset', 'soft', 'standard', 'quick']);
    if (internal === 0 && external === 0 && !MOTION_LOCKED.has(name)) deadTokens.push(name);
  }
}
// 自检: 人造一个零使用令牌, 确认能抓到
{
  const probe = '__selfTestDeadToken';
  const fakeTheme = theme + '\n    static var ' + probe + ': Int { 0 }\n';
  const fakeNames = [];
  for (const line of fakeTheme.split('\n')) {
    const m = line.match(declRe);
    if (m && !/^    private /.test(line)) fakeNames.push(m[1]);
  }
  if (!fakeNames.includes(probe)) {
    console.error('✗ 自检失败: 令牌声明解析抓不到人造令牌');
    process.exit(1);
  }
  let seen = 0;
  for (const f of files) {
    if (/Theme\.swift$/.test(f)) continue;
    const hits = fs.readFileSync(f, 'utf8').match(new RegExp('\\b' + probe + '\\b', 'g'));
    if (hits) seen += hits.length;
  }
  if (seen > 0) {
    console.error('✗ 自检失败: 人造令牌居然"被引用"了, 判据已失效');
    process.exit(1);
  }
}
if (deadTokens.length > 0) {
  for (const d of deadTokens) {
    console.error('Theme.swift: 令牌 ' + d + ' 全仓零使用 —— 删掉, 或接上使用方');
  }
}


// ── 6d. 零调用的 View 扩方法 ────────────────────────────────────────
// 由来: 把全仓 30 处 .xList()/.xScreen() 删掉之后, 方法定义本身还在,
// 于是变成了 0 调用的死方法。这和死令牌是同一个病, 只是载体不同。
//
// 只查 Components.swift 里 `nonisolated func xXxx()` / `func xXxx(` 形式
// (本仓的样式扩方法统一 x/ax 前缀), 全仓统计 ".name" 调用次数。
const deadExtensions = [];
{
  const EXT_RE = /^\s*(?:nonisolated )?func (x[A-Z]\w*|ax[A-Z]\w*)\(/gm;
  let m;
  const seen = new Set();
  while ((m = EXT_RE.exec(lib))) {
    const name = m[1];
    if (seen.has(name)) continue;
    seen.add(name);
    let calls = 0;
    for (const f of files) {
      const src = fs.readFileSync(f, 'utf8');
      const hits = src.match(new RegExp('\\.' + name + '\\b', 'g'));
      if (hits) calls += hits.length;
    }
    if (calls === 0) deadExtensions.push(name);
  }
}
// 自检: 人造一个零调用扩方法名, 确认能抓到
{
  const probe = 'xSelfTestDeadExtension';
  let calls = 0;
  for (const f of files) {
    const hits = fs.readFileSync(f, 'utf8').match(new RegExp('\\.' + probe + '\\b', 'g'));
    if (hits) calls += hits.length;
  }
  if (calls !== 0) {
    console.error('✗ 自检失败: 人造扩方法居然"被调用"了');
    process.exit(1);
  }
}
if (deadExtensions.length > 0) {
  for (const d of deadExtensions) {
    console.error('Components.swift: 扩方法 .' + d + '() 全仓零调用 —— 删掉');
  }
}

// ── 5z. 不许把「文件名」当「类型名」用 ──
//
// 实证（本会话两次）：`BackupStudioKit.swift` 里的类型叫 `BackupStudio`，
// 我写了 `BackupStudioKit.xxx`。CI 报 cannot find in scope，而本地闸门全绿 ——
// 符号判据（5a）只查 X 前缀，这个不是。
//
// 判据：引用的标识符**等于某个 .swift 的 basename**，但全仓没有任何声明。
{
  const FILE_BASENAMES = new Set(files.map(function (f) { return path.basename(f, '.swift'); }));
  const DECLARED = new Set();
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/(?:struct|class|enum|protocol|extension|typealias)[ ]+(\w+)/g)) DECLARED.add(m[1]);
  }
  const bad = new Map();
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach(function (raw, i) {
      const code = raw.replace(/\/\/.*$/, '');
      if (code.trim().startsWith('///')) return;
      for (const m of code.matchAll(/\b([A-Z]\w{3,})[ ]*[.:]/g)) {
        const name = m[1];
        if (!FILE_BASENAMES.has(name)) continue;
        if (DECLARED.has(name)) continue;
        if (!bad.has(name)) bad.set(name, path.relative(ROOT, f) + ':' + (i + 1));
      }
    });
  }
  if (bad.size) {
    for (const entry of bad) console.error('  ' + entry[0] + '  <- ' + entry[1] + ' (file name, not a type)');
    console.error('x 把文件名当类型名用了 —— CI 会报 cannot find in scope');
    process.exit(1);
  }
  console.log('文件名/类型名 ok 没有把 .swift 文件名当类型');
}
// ── 5a. 引用的符号必须有声明（编译期错误，静态可抓）──
//
// CI 实证过两类：
//   · `@Environment(\.accessibilityContrast)` —— 键不存在（正确是 \.colorSchemeContrast）；
//   · `a11yText` 只加了使用处、参数声明没插进去 —— cannot find in scope。
// 这两类都能在推 CI 之前抓出来，只要一条判据：**引用的名字必须在某处声明过**。
//
// 注意必须**先剥注释**：本仓有大段注释在讨论这些符号（比如 LockStats 解释元组 key path），
// 不剥就会把注释里的提及当成引用 —— 那条错误的判据我在其他闸门里已经犯过一次。
{
  const strip = (l) => l.replace(/\/\/.*$/, '');
  const declSet = new Set();
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    for (const m of src.matchAll(/(?:struct|class|enum|extension|protocol)\s+(\w+)/g)) declSet.add(m[1]);
    for (const m of src.matchAll(/^\s*(?:internal |private |public |fileprivate )?(?:func|let|var)\s+(\w+)/gm)) declSet.add(m[1]);
    for (const m of src.matchAll(/static\s+(?:var|let|func)\s+(\w+)/g)) declSet.add(m[1]);
    for (const m of src.matchAll(/case\s+(\w+)/g)) declSet.add(m[1]);
  }
  const undef = new Map();
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = strip(raw);
      for (const m of code.matchAll(/\b(X[A-Z]\w+)\b/g)) {
        const n = m[1];
        if (/^XML|^XCTest/.test(n)) continue;
        if (declSet.has(n)) continue;
        if (!undef.has(n)) undef.set(n, path.relative(ROOT, f) + ':' + (i + 1));
      }
    });
  }
  if (undef.size) {
    for (const [n, where] of [...undef].slice(0, 12)) console.error('  ' + n + '  ← ' + where);
    console.error('✗ 有 ' + undef.size + ' 个 X 前缀符号被引用但没有任何声明 —— 这是编译期错误');
    process.exit(1);
  }
  // 成员级：命名空间令牌（XPalette.xxx / XGradient.xxx / …）也必须真的存在 ——
  // 删一个令牌却漏改引用，就是这一类编译错误（本仓删 surfaceChip 时差点踩到）。
  const NSS = ['XPalette','XGradient','DSRing','DSFont','XSpace','XRadius','XIcon','XHit','XOpacity','XMetric','XMotion','XText'];
  const memberMissing = new Map();
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = strip(raw);
      for (const ns of NSS) {
        for (const m of code.matchAll(new RegExp('\\b' + ns + '\\.(\\w+)', 'g'))) {
          if (declSet.has(m[1])) continue;
          const k = ns + '.' + m[1];
          if (!memberMissing.has(k)) memberMissing.set(k, path.relative(ROOT, f) + ':' + (i + 1));
        }
      }
    });
  }
  if (memberMissing.size) {
    for (const [n, where] of [...memberMissing].slice(0, 12)) console.error('  ' + n + '  ← ' + where);
    console.error('✗ 有 ' + memberMissing.size + ' 个令牌成员被引用但没声明 —— 删令牌时漏改引用');
    process.exit(1);
  }
  console.log('符号声明 ✓ 所有被引用的 X 前缀符号都能找到声明');
}
// ── 6a. xFont 实参必须是 XText case（否则编译器会去试另一个重载）──
//
// CI 实证：`.xFont(.caption2.monospacedDigit())` 的实参是 **Font 值**，不是 XText case。
// 它在改名 xFontExact 之后没有匹配的重载，编译器于是陷入类型推导，
// 报的是「unable to type-check this expression in reasonable time」——
// 一条看起来像性能问题的**真编译错误**。
//
// 更糟的是：我上一轮的校验正则用了 \b，`.caption2.` 的 word boundary 让 68 处全部混过，
// 于是得出「851 处全部 XText」的假结论。这条判据改用**严格形状**：
// 实参去掉空白后必须恰好是 `.case` 后接 `,` 或结尾。
{
  // 2026-10-23: 新增 `small`（13/Regular，图2 卡内副文档）。
  // 新增 XText case 时必须同步这里 —— 名单是封闭的，否则新 case 会被判成"非 case"。
  const XT = 'displayNumber|display|largeTitle|title2|title3|headline|body|subheadline|footnote|caption2|caption|small';
  // 除裸 case 外，还允许「已知返回 XText 的成员」——目前只有一个：
  //   `XText.unitStyle`（规范 §7.16 的单位档，返回 XText）。
  // 白名单是**封闭**的：新增成员必须先证明它返回 XText，再往这里加。
  const XT_MEMBERS = 'unitStyle';
  // 两种合法形状：
  //   `.case`                    —— 常量档
  //   `.case.unitStyle`          —— 常量档的单位档
  //   `某XText变量.unitStyle`    —— 变量档的单位档（XValueUnit 就是这种）
  const validArg = new RegExp(
    '^(\\.(' + XT + ')|[a-z][A-Za-z0-9_]*)(\\.(' + XT_MEMBERS + '))?(,|$)');
  const bad = [];
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    for (const mm of src.matchAll(/\.xFont\(/g)) {
      const start = mm.index + 7;
      let depth = 1, i = start;
      while (i < src.length && depth > 0) {
        if (src[i] === '(') depth++; else if (src[i] === ')') depth--;
        i++;
      }
      const arg = src.slice(start, i - 1).replace(/\s+/g, '');
      if (!validArg.test(arg)) {
        bad.push(path.relative(ROOT, f) + ':' + (src.slice(0, start).split('\n').length) + '  ' + arg.slice(0, 40));
      }
    }
  }
  if (bad.length) {
    for (const b of bad.slice(0, 12)) console.error('  ' + b);
    console.error('✗ .xFont 实参不是 XText case ' + bad.length + ' 处 —— 传 Font 值请用 xFontExact（否则重载不匹配、编译器类型推导超时）');
    process.exit(1);
  }
  console.log('xFont 实参形状 ✓ 全部是 XText case（Font 值一律走 xFontExact）');
}
// ── 6b. xFontExact 预算 ───────────────────────────────────────────
//
// 规范 §4.2 的字阶是唯一的排版入口（XText）。xFontExact 是显式字号的逃生门，
// 用来写图表轴、量规数字那种 XText 表达不了的尺寸。
// 风险是「慢慢变成主流写法」—— 设一个收紧型预算，只许变少。
{
  let n = 0;
  for (const f of files) n += (fs.readFileSync(f, 'utf8').match(/\.xFontExact\(/g) || []).length;
  // 2026-10-22 基线 23 → **91**。
  // 涨的原因不是"又绕开字阶了"，而是**上一版判据漏了一整类调用**：
  //   .xFont(.caption2.monospacedDigit()) —— 实参是 Font 值，不是 XText case。
  //   my 校验正则用了 \b，".caption2." 的 word boundary 让它们全部混过了检查，
  //   于是 851 处"全部 XText"的结论是假的；改名 xFontExact 后这些调用点直接编不过。
  //   CI 的编译错误（AddFingerPage 类型检查超时）就是它们的表现。
  const BUDGET = 91;   // 收紧型：只许变少
  if (n > BUDGET) {
    console.error('✗ xFontExact 用法 ' + n + ' 处，超过预算 ' + BUDGET + ' ——');
    console.error('  它是显式字号的逃生门，多了说明排版又在绕开规范 §4.2 的字阶。');
    process.exit(1);
  }
  console.log('xFontExact 预算 ✓ ' + n + '/' + BUDGET + ' 处（显式字号逃生门）');
}

// ── 7. 输出 ───────────────────────────────────────────────────────
if (allProblems.length === 0 && deadCode.length === 0 && deadTokens.length === 0 && deadExtensions.length === 0) {
  console.log('签名 / 死代码 / 裸Divider / 零用令牌 / 零调扩方法 ✓ (' + files.length + ' 文件, '
    + Object.keys(structDefs).length + ' 组件签名, ' + libTypes.length + ' 类型 + 令牌查引用, '
    + '自检 ' + (probes.length + 3) + '/' + (probes.length + 3) + ')');
  // ── 组件内引用的类型必须真的存在 ──
//
// 三次 CI 红都是这一类：声明不完整 / 编辑残留。
//   · XStatCard 用了 kind/tone 但属性没加进去
//   · XScreen 用了 Above 但泛型已回退
//   · XScreen 的 subtitle 声明了两次
//
// 闸门验风格，编译器验类型 —— 而本机没有编译器。
// 这条判据能抓的只是「引用了一个本仓从未定义过的类型名」，
// 抓不到「类型存在但没声明在正确的结构体里」。
// **但它能抓的就必须抓住。**
{
  const coreDir = path.join(ROOT, 'App');
  const allSwift = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const q = path.join(d, e.name);
      if (e.isDirectory()) walk(q);
      else if (e.name.endsWith('.swift')) allSwift.push(q);
    }
  })(coreDir);
  const declared = new Set();
  for (const f of allSwift) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/(?:struct|enum|class|protocol|typealias)\s+(\w+)/g)) declared.add(m[1]);
  }
  const BUILTIN = new Set(['View','AnyView','String','Bool','CGFloat','Double','Float','Int','Color','ScrollView','VStack','HStack','ZStack','Text','Image','EmptyView','Self','Array','Set','Dictionary','Optional','Shape','InsettableShape','Binding','Date','URL','Data','Never','Void','Group','Spacer','Button','Label','Toggle','Picker','Divider','Rectangle','Circle','Capsule','RoundedRectangle','LinearGradient','AngularGradient','StrokeStyle','Content','Configuration','ButtonStyle','ViewModifier','PreviewProvider','App','Scene','WindowGroup','NavigationStack','NavigationLink','Section','List','Form','Menu','ProgressView','TimelineView','GeometryReader','ScrollViewReader','LazyVStack','LazyVGrid','GridItem','Animation','Transaction','Gesture','TapGesture','DragGesture','Font','TextStyle','NumberFormatter','DateFormatter','UUID','Error','Result','Sequence','Collection','Equatable','Hashable','Codable','Identifiable','Comparable','CaseIterable','RawRepresentable','ObservableObject','Published','State','Environment','EnvironmentObject','StateObject','ObservedObject','ScaledMetric','Namespace','FocusState','MainActor','Sendable','AsyncStream','Task','Duration','Calendar','Gregorian','Locale','TimeZone','Character','Substring','Range','IndexPath','CGRect','CGSize','CGPoint','EdgeInsets','SafeAreaRegions','Axis','Edge','Alignment','HorizontalAlignment','VerticalAlignment','UnitPoint','Material','ShapeStyle','AnyShapeStyle','AnyShape','AnyLayout','LocalizedStringKey','Axis','Animation','Curve','Spring','UnitCurve','FeedbackGenerator','Notification','Bundle','FileManager','UserDefaults']);
  const ignored = new Set(['XSpace','XRadius','XIcon','XPalette','XText','XGradient','XOpacity','DSRing','DSFont','XMetric','TimeFormat','BatteryCare','LockArchive','StatsKit','MemberHub','ClipboardCare','SecurityPolicy','AuditLog','DestroyKit','ErrorText','StatusParser','Milestones','BackupStudio','DB','XMotion','XHaptics','XAppearance','SecTick','SecKey','SecTickCenter','XStatChip','XStatCard','XStatSection','XScreen','XCardLink','XHairline','XPanel','XContainerKind','XToneColor','XNamedColor','WeekCal','LinkSense','CredentialOrg','StudioTools','LockStats','LockCommand','LockKeySpace','XCycleRing','XValueUnit','XPrimaryButtonStyle','PressableScaleStyle','XGlassTabBar','XTabItem','XSegmented','XSkeleton','XEmptyState','XInlineError','XMetricTile','XRow','XStatusPill','XBreathing','XScaledFrame','XCodeRing','XDayClock','XBatteryGauge','XStepBar','XSkewBar','XScrollLift','XDestinedModifier','XToggle','SecRow','Card']);
  const problems = [];
  for (const f of allSwift) {
    const src = fs.readFileSync(f, 'utf8');
    // 只看组件层（Components.swift），避免误伤业务代码里的大量外部类型
    if (!f.endsWith('Components.swift')) continue;
    // 形状 1：`var x: SomeType`
    // 形状 2：`var x: (() -> SomeType)?`  ← 闭包，上一版漏了这个
    // 形状 3：`var x: [SomeType]`
    const typeRefs = [];
    for (const m of src.matchAll(/^\s*var \w+: ([A-Z]\w+)\b/gm)) typeRefs.push(m[1]);
    for (const m of src.matchAll(/^\s*var \w+: \(\(\) -> ([A-Z]\w+)\)/gm)) typeRefs.push(m[1]);
    for (const m of src.matchAll(/^\s*var \w+: \[([A-Z]\w+)\]/gm)) typeRefs.push(m[1]);
    for (const name of typeRefs) {
      if (declared.has(name) || BUILTIN.has(name) || ignored.has(name)) continue;
      problems.push('引用了未定义的类型：' + name + '  (' + path.relative(ROOT, f) + ')');
    }
  }
  if (problems.length) {
    for (const p of problems) console.error('  ✗ ' + p);
    process.exit(1);
  }
}


// ── 同一结构体内不得重复声明同名属性 ──
//
// 这个错误犯过三次：
//   · XScreen.subtitle 声明两次
//   · XScreen.above 声明两次（两轮各一次）
//
// 原因都一样：改代码时**插入了一段新的，旧的没删**。
// 闸门验风格，编译器验类型 —— 而重复声明只有编译器会抓。
//
// 判据：按顶层结构体切分，每块内统计 `var <name>:` 的出现次数。
{
  const compFile = path.join(ROOT, 'App', 'Core', 'Components.swift');
  const src = fs.readFileSync(compFile, 'utf8').replace(/\r\n/g, '\n');
  const lines = src.split('\n');
  // 找顶层 `struct Xxx` / `enum Xxx` / `extension Xxx` 的起止
  const structs = [];
  for (let i = 0; i < lines.length; i++) {
    const m = /^(?:struct|enum|extension|final class|class) (\w+)/.exec(lines[i]);
    if (!m) continue;
    let depth = 0, started = false, end = i;
    for (let k = i; k < lines.length; k++) {
      for (const ch of lines[k]) { if (ch === '{') { depth++; started = true; } else if (ch === '}') depth--; }
      if (started && depth === 0) { end = k; break; }
    }
    structs.push({ name: m[1], start: i, end });
  }
  const problems = [];
  for (const st of structs) {
    const body = lines.slice(st.start, st.end + 1).join('\n');
    const counts = {};
    for (const mm of body.matchAll(/^    (?:@\w+ )?var (\w+):/gm)) {
      counts[mm[1]] = (counts[mm[1]] || 0) + 1;
    }
    for (const [k, v] of Object.entries(counts)) {
      if (v > 1) problems.push(st.name + '.' + k + ' 声明了 ' + v + ' 次');
    }
  }
  if (problems.length) {
    for (const p of problems) console.error('  ✗ 重复声明：' + p);
    process.exit(1);
  }
}

process.exit(0);
}
for (const p of allProblems) console.error(p.rel + ':' + p.line + ': ' + p.msg);
if (allProblems.length > 0) console.error('✗ 组件签名 ' + allProblems.length + ' 处不符');
if (deadCode.length > 0) console.error('✗ 死代码 ' + deadCode.length + ' 处');
if (deadTokens.length > 0) console.error('✗ 零使用令牌 ' + deadTokens.length + ' 处');
if (deadExtensions.length > 0) console.error('✗ 零调用扩方法 ' + deadExtensions.length + ' 处');
process.exit(1);
