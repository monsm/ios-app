// tools/sheetcover.js —— 常驻闸门：被 sheet 盖住时换 Tab，必须同时收摊（ dismiss() ）
//
// 起因（docs/HANDOFF-2026-10-15-UI-SWEEP.md §7.3 / 行 LII）：页面以 `.sheet` / `.fullScreenCover` 呈现时，
// 写 `app.tabSelection = N` 切的是**被盖住的那层 TabView** ⇒ 用户点了看着"没反应"，甩掉 sheet 才发现自己站在别的 Tab 上。
// 正解两条：跳转后紧跟 `dismiss()`，或让承载那一层的 sheet 自己收摊。
//
// ⚠ 这条尺子真正的分辨点（行 LII 当场抓出的 4 处都栽在这上面）：
//   `app.requestTab(N)` 只过**访客门禁**（377），**不收当前那层 sheet/push** ⇒ "改成走 requestTab 就算修好了"是错的。
//   所以本闸门对 `tabSelection =` 与 `requestTab(` 一视同仁：两者都算"换 Tab 动作"，都要求附近有 `dismiss()`。
//
// 判与不判（判不了就明写，宁漏不误报 —— 天天误报的尺子比没尺子更糟）：
//   ① 只判"这一页确实被某处 `.sheet/.fullScreenCover` 端出来过"的 struct 里的换 Tab 动作。
//      认不出结构的（struct 头行形状不匹配、大括号在字符串里不成对）⇒ 计入 `跳过`，不猜。
//   ② 窗口 = 动作行的**前一行的代码 + 后六行的代码**（先去掉整行注释）。
//      为什么含前一行的代码：`RecordsSampleGuideView` 的 `dismiss()` 就写在切换之前。
//      为什么要去整行注释：解释注释里会引述 `dismiss()` 这句被检查的原话，不去掉就把注释当成调用（行 LII 实测踩过）。
//   ③ 销号标记 `收摊口径：`（写在动作行或其窗口内的代码行上）⇒ 跳过并单独报数。
//      用途：那一处真的不该收摊（例如这页根本不会被 sheet 端出来，只是同 struct 名字被别处复用过）。
//   ④ **不判**：间接呈现（页面被一个计算属性 `some View` 包一层再进 sheet）、`NavigationLink` push 栈该不该退、
//      以及"dismiss() 到底退的是哪一层"——这三件要类型推断或真机，本机给不了。
//
// 用法：`node tools/sheetcover.js`（现网扫描，违规退 1）
//       `node tools/sheetcover.js --selftest`（fixtures/sheetcover/{fire,ok} 各跑一遍，不符退 2）
//       `node tools/sheetcover.js --json`（机器读）
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App'];
const STRUCT_HEAD = /^(\s*)(?:private |public |fileprivate |internal )?(?:@available\([^)]*\)\s*)?(?:@\w+\s+)*(?:private |public |fileprivate |internal )?struct\s+([A-Za-z_][\w]*)[^{]*\{\s*$/;
const SHEET_MOD = /\.(sheet|fullScreenCover)\s*\(/;
const TAB_ACT = /(?:\bapp\.tabSelection\s*=\s*\d)|(?:\.requestTab\s*\(\s*\d)/;
const DISMISS = /\bdismiss\s*\(\s*\)/;
const MARK = /收摊口径：/;
const VIEW_USE = /\b([A-Z][A-Za-z0-9_]*)\s*\(/g;

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

// 去掉整行注释与行尾注释（粗糙但一致：只按第一个不在括号字符串里的 `//` 切；字符串里的 `//` 极少且都在 URL，代价是可能少算一行）
function stripComment(line) {
  const i = line.indexOf('//');
  if (i < 0) return line;
  const before = line.slice(0, i);
  if ((before.match(/"/g) || []).length % 2 === 1) return line;   // 引号里的 // 不算注释起点
  return before;
}
const isCode = (l) => { const s = stripComment(l).trim(); return s.length > 0; };

// struct 边界：按大括号深度（去掉整行注释后数括号；字符串里的括号本仓极少，撞上就少算一个 struct —— 方向是"少判"不是"误判"）
function structs(file, lines) {
  const list = [];
  let skipped = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = STRUCT_HEAD.exec(stripComment(lines[i]));
    if (!m) continue;
    let depth = 0, end = -1, sawBrace = false;
    for (let j = i; j < lines.length; j++) {
      const code = stripComment(lines[j]);
      for (const ch of code) { if (ch === '{') { depth++; sawBrace = true; } else if (ch === '}') depth--; }
      if (sawBrace && depth === 0) { end = j; break; }
    }
    if (end < 0) { skipped++; continue; }
    list.push({ name: m[2], start: i, end });
  }
  return { list, skipped };
}

// 哪些 struct 被 sheet/fullScreenCover 端出来过：从修饰符行往后最多 10 行里找 `SomeView(`
function sheetPresented(all, fileStructs) {
  const names = new Set();
  const unknown = new Set();
  const known = new Set();
  for (const f of fileStructs) for (const s of f.structs) known.add(s.name);
  for (const f of all) {
    const lines = f.lines;
    for (let i = 0; i < lines.length; i++) {
      if (!SHEET_MOD.test(stripComment(lines[i]))) continue;
      for (let j = i; j <= Math.min(lines.length - 1, i + 10); j++) {
        for (const m of stripComment(lines[j]).matchAll(VIEW_USE)) {
          if (known.has(m[1])) names.add(m[1]);
          else unknown.add(m[1]);
        }
        if (j > i && /^\s*\}\s*$/.test(lines[j])) break;
      }
    }
  }
  return { names, unknown };
}

function scan(root) {
  const hits = [];
  const files = swiftFiles(root).sort();
  const parsed = files.map((f) => {
    const lines = fs.readFileSync(f, 'utf8').split('\n');
    const { list, skipped } = structs(f, lines);
    return { file: path.relative(ROOT, f).replace(/\\/g, '/'), lines, structs: list, skipped };
  });
  const presented = sheetPresented(parsed, parsed);
  let acts = 0, inSheet = 0, marked = 0, structSkipped = 0;
  for (const p of parsed) {
    structSkipped += p.skipped;
    for (let i = 0; i < p.lines.length; i++) {
      const code = stripComment(p.lines[i]);
      if (!TAB_ACT.test(code)) continue;
      acts++;
      const owner = p.structs.find((s) => i >= s.start && i <= s.end);
      if (!owner || !presented.names.has(owner.name)) continue;
      inSheet++;
      const from = Math.max(0, i - 1), to = Math.min(p.lines.length - 1, i + 6);
      const codeWin = [], rawWin = [];
      for (let j = from; j <= to; j++) { if (isCode(p.lines[j])) codeWin.push(p.lines[j]); rawWin.push(p.lines[j]); }
      // 判据的不对称是有意的：销号标记**住在注释里**（它就是对人说的一句话），所以按原始行找；
      // 而 dismiss() 必须按"去掉整行注释"的代码行找 —— 否则注释里引述的那句 `dismiss()` 会被当成真调用（行 LII 实测踩过）。
      if (rawWin.some((l) => MARK.test(l))) { marked++; continue; }
      if (codeWin.some((l) => DISMISS.test(l))) continue;
      hits.push(`${p.file}:${i + 1}  ${owner.name} 被 sheet 端出来过，而这里的换 Tab 动作附近没有 dismiss() | ${code.trim().slice(0, 70)}`);
    }
  }
  return { hits, acts, inSheet, marked, structSkipped, presented: [...presented.names].sort() };
}

function runDir(dir) {
  if (!fs.existsSync(dir)) return [];
  return scan(dir).hits;
}

function selftest() {
  const dir = path.join(ROOT, 'fixtures', 'sheetcover');
  const fire = runDir(path.join(dir, 'fire'));
  const ok = runDir(path.join(dir, 'ok'));
  const bad = [];
  if (fire.length !== 3) bad.push(`fire/ 期望 3 条，实得 ${fire.length}（三处各是一个形状：sheet 内裸写 tabSelection、requestTab 不收摊、动作在 dismiss() 之前但隔了 7 行）`);
  if (ok.length !== 0) bad.push(`ok/ 期望 0 条，实得 ${ok.length}: ${ok.join(' | ')}`);
  console.log(`[selftest] fire=${fire.length}/3  ok=${ok.length}/0`);
  for (const h of fire) console.log('  fire:', h);
  if (bad.length) { for (const b of bad) console.log('✗ ' + b); process.exit(2); }
  console.log('sheetcover 自测 ✓');
}

if (process.argv.includes('--selftest')) { selftest(); process.exit(0); }
const r = scan(path.join(ROOT, 'App'));
if (process.argv.includes('--json')) { console.log(JSON.stringify(r, null, 2)); process.exit(r.hits.length ? 1 : 0); }
console.log(`样本量: 换 Tab 动作 ${r.acts} 处 · 其中落在"被 sheet 端出来过"的页面 ${r.inSheet} 处 · 销号 ${r.marked} 处 · struct 边界认不出 ${r.structSkipped} 处`);
console.log(`sheet 呈现到的页面名: ${r.presented.join(', ')}`);
if (r.hits.length) {
  console.log(`✗ 被 sheet 盖住时换 Tab 而附近没有 dismiss(): ${r.hits.length} 处（改法：紧跟一句 dismiss()，或让承载那层的 sheet 自己收摊；见 docs/HANDOFF-2026-10-15-UI-SWEEP.md §7.3）`);
  for (const h of r.hits) console.log('  - ' + h);
  process.exit(1);
}
console.log('sheet 盖住切 Tab 收摊检查 ✓');
