#!/usr/bin/env node
// 用户可见文案里的内部规格编号检查 — node tools/copynum.js [目录…] [--selftest] [--fail] [--json]
//
// 为什么加这条: 本仓用"(N 说明)"给每处改动挂台账编号，**注释里**这么写是对的 (可追溯)，
// 但有些编号漏进了用户能看见的字符串 —— 截图里"成员别名显示 (919: 关系备注优先, 如「老妈」)"
// 就是一例：一行标签被撑成两行、右侧开关被挤到第二行，用户看到的还是一串跟自己无关的编号。
// 2026-10-14 地毯式扫出并清掉两批共 40 处，同时抓到 SecurityCenterView 一处**硬编码假总数**。
//
// 第十九批 (2026-10-15) 按 §7.4-21 加宽。原版只认"`分隔符 + 1~4 位数字 + 分隔符`"这一种包围，
// 而清编号那一轮实际删掉的句子有七种形状；原版作用域只有传进来的那一个目录，
// 界面文案还住在 `App/Intents/`（快捷指令画廊整页）、`App/LockKeeperApp.swift`（启动 toast）、
// `App/Services/BackupStudioKit.swift`（错误文案）里 ⇒ 现在默认扫 `App` + `Widget`。
//
// 七种形状（每条都各有反控，见 fixtures/copynum/ok）：
//   ① 原支：`[(（] 数字 [^)]*`，数字后紧跟 `[:：,，、)]` 或 空格 + 非量纲中文
//   ② 数字或数字对**紧跟冒号**：`123:` `123-456:` `123/456：`
//   ③ `包\d{1,3}`：头注释那种"包6 凭证列表"上屏了就是编号
//   ④ 介词挂编号：`与 501 同级` / `按 379/380 字段级 diff` / `走 353 那条`
//   ⑤ 句首或逗号后挂编号：`927 哑按钮`、` 896 又补了`
//   ⑥ 括号**末尾**挂编号：`(锁端仅告警级, 569)`、`(最近 30 天, 343)` 里的 343 那一半
//   ⑦ 数字对：`937/938 仍不提供`、`957-963:`（② 只管带冒号的，这条管带中文/右括号的）
//
// 排除（都是本轮实测撞出来的，不是猜的）：
//   · 注释行与行尾 `// …`；多行字符串 `"""` 块（整段跳，插值多易误报）
//   · 插值 `\(...)` 里的内容（先替换成占位符再判）
//   · 量纲单位（数字 + 单位 = 给人看的信息）：见 UNITS
//   · **标准名/算法名**：数字左边 6 字内出现 SHA/AES/RFC/GB/MD5/HMAC/UTF ⇒ 放行（`SHA256 摘要`、`SHA-256:`、`RFC 6238 常用档`）
//   · **结构性豁免**：数字左边直接贴字母或 `-`（`SHA256`、`iOS16`、`kf_2026`）⇒ 那不是编号是名字的一部分
//   · 整行出现「示例 / 例如 / 比如」⇒ 那是给人看的样例数字
//   · ⑥ 的前导词（最近/取/约/共/上限/末/前/后）后跟数字是真值，不算编号
//
// 默认**顾问级**（打印线索、退 0）；`--fail` 才在有命中时退 1。CI 现在跑的是
// `--selftest`（判据会开火 + 不乱叫，不符退 2）与顾问级全量 ⇒ 升判失败的时机记在 §7.4-21 末尾。
'use strict';
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('--')));
const dirs = argv.filter((a) => !a.startsWith('--'));
const ROOTS = dirs.length ? dirs : ['App', 'Widget'];

const UNITS = ['天', '条', '批', '秒', '分', '米', '次', '小', '时', '个', '位', '号', '款', '种', '项',
               '步', '页', '行', '层', '档', '版', '周', '月', '年', '人', '枚', '张', '台', '把',
               // 第十九批补 (标定记录 §7.2-XLVII): 这些在真句子里被误响过
               '字', '毫', '千', '万', '元', '组', '列', '栏', '窗', '屏', '格', '键', '轮', '圈', '段', '倍', '级'];
const STANDARD = /(?:SHA|AES|RFC|GB|MD5|HMAC|UTF|DES|UUID|APNS|BLE)/;
const EXAMPLE = /示例|例如|比如/;
const LEAD_TRUE = /(?:最近|取|约|共|上限|末|前|后|第)$/;      // ⑥ 的"这是真值不是编号"前导词
const CJK = /[一-鿿]/;
// 有意保留的带编号对外文案。⚠ 销号按 **文件 + 片段** 认，不按行号 —— 行号是消耗品（§7.5 那条"引用认符号不认行号"）。
// 唯一一条现网已知行 = 诊断页那句对 JS 侧行号的**证据引用**：它不是台账编号而是"去看哪两行代码"，删掉反而让那句话失去依据。
const ALLOW = [{ file: 'App/UI/DiagnosticsView.swift', has: 'status.js:100-101' }];

function listFiles(root) {
  const out = [];
  if (!fs.existsSync(root)) return out;
  (function w(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name).split(path.sep).join('/');
      if (e.isDirectory()) w(p); else if (e.name.endsWith('.swift')) out.push(p);
    }
  })(root);
  return out;
}

// 括号配对剥离插值（正则处理不了嵌套括号）
function stripInterpolations(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && s[i + 1] === '(') {
      let depth = 0, j = i + 1;
      for (; j < s.length; j++) {
        if (s[j] === '(') depth++;
        else if (s[j] === ')') { depth--; if (depth === 0) { j++; break; } }
      }
      out += '§'; i = j - 1;
    } else out += s[i];
  }
  return out;
}

// 通用豁免：贴字母/连字符、标准名、示例行
function exempt(line, idx) {
  if (EXAMPLE.test(line)) return '示例';
  const left = line[idx - 1];
  if (left && (/[A-Za-z0-9_\-]/.test(left))) return '左贴字母或数字';
  if (STANDARD.test(line.slice(Math.max(0, idx - 6), idx))) return '标准名';
  return null;
}

const num = String.raw`\d{1,3}`;                 // ③ 包\d{1,3} 用
const N34 = String.raw`\d{3,4}`;                  // ②④⑤⑥⑦ 一律 3~4 位：两位数字在界面文案里几乎都是真值（"22 点后"、"1-27 错误码"），第十九批第一版把 ⑤ 写成 \d{1,4} ⇒ 现网 128 行误响，就是这个宽度的差别
const NUM2 = String.raw`\d{3,4}(?:\s*[-/]\s*\d{3,4})?`;
const CJKc = '[\\u4e00-\\u9fff]';

// 七条形状各返回 [{shape, idx, text}]
function findShapes(body) {
  const hits = [];
  // 所有形状共用一道闸：**最后一段数字之后（跳掉空格）的第一个字符若是量纲单位，那就是真值不是编号**。
  // 这道闸原本只写在 ① 里 ⇒ 第十九批加宽时忘了给 ④⑤ 也加，"365 天" / "按 30 秒" 这类句子会被误响。
  const push = (shape, index, text) => {
    if (index < 0 || !text) return;
    const runs = [...text.matchAll(/\d+/g)];
    if (!runs.length) return;
    const last = runs[runs.length - 1];
    const after = text.slice(last.index + last[0].length).replace(/^\s+/, '');
    const c = after[0];
    if (c && UNITS.includes(c)) return;
    hits.push({ shape, idx: index, text });
  };
  let mm;
  // ① 原支
  const re1 = /[(（](\d{1,4}[^)]*)/g;
  while ((mm = re1.exec(body)) !== null) {
    const t = /^(\d{1,4})(.*)$/.exec(mm[1]);
    if (!t) continue;
    const tail = t[2];
    const leadSpace = /^\s+(\S)/.exec(tail);
    const spec = /^[:：,，、]/.test(tail) || /^[)）]/.test(tail) || (leadSpace && CJK.test(leadSpace[1]));
    if (spec) push('①', mm.index + 1, mm[1]);
  }
  // ② 数字/数字对紧跟冒号
  const re2 = new RegExp('(?:^|[^0-9A-Za-z_.\\(-])(' + NUM2 + ')\\s*[:：]', 'g');
  while ((mm = re2.exec(body)) !== null) push('②', mm.index + mm[0].indexOf(mm[1]), mm[1]);
  // ③ 包NNN (排除 压缩包 / 包内 / 打包 / 装包 这一类)
  const re3 = new RegExp('(^|[^压内打成括装])包(' + num + ')', 'g');
  while ((mm = re3.exec(body)) !== null) {
    const at = mm[0].indexOf('包');
    if (LEAD_TRUE.test(body.slice(0, mm.index + at + 1))) continue;
    push('③', mm.index + at, mm[0].slice(at));
  }
  // ④ 介词挂编号
  const re4 = new RegExp('[与含按走如同照]\\s*(' + NUM2 + ')\\s+' + CJKc, 'g');
  while ((mm = re4.exec(body)) !== null) push('④', mm.index + mm[0].search(/\d/), mm[0]);
  // ⑤ 句首 / 逗号后挂编号
  const re5 = new RegExp('(?:^|[，,、;；。:：]\\s*)(' + N34 + ')\\s+' + CJKc, 'g');
  while ((mm = re5.exec(body)) !== null) push('⑤', mm.index + mm[0].search(/\d{3,4}/), mm[0]);
  // ⑥ 括号末尾挂编号
  const re6 = new RegExp('[(（][^)]{2,40}[，,、\\s](' + N34 + ')\\s*[)）]', 'g');
  while ((mm = re6.exec(body)) !== null) {
    const before = mm[0].slice(0, mm[0].indexOf(mm[1])).replace(/[，,、\s]+$/, '');
    if (LEAD_TRUE.test(before)) continue;                 // "(最近 30 天, 343)" 里"最近/上限"这类前导词 = 真值
    // 「脱敏样例」豁免：括号里在数字之前**只有掩码字符**（`· … ・ * -` 与空格）时，那串数字是被遮住的样本值
    // (现网唯一一例: 安全中心那句「保留末 4 位 (· · · 4821)」)，不是台账编号。
    // 这条写得**比形状⑥更窄**：要求左括号到数字之间除掩码与空格外不许有任何字 —— 加反控 fixtures/copynum/ok/U6Mask.swift。
    if (/^[（(][\s·…・.\*\-]+$/.test(mm[0].slice(0, mm[0].search(/\d{3,4}/)))) continue;
    push('⑥', mm.index + mm[0].search(/\d{3,4}/), mm[0]);
  }
  // ⑦ 数字对后接中文或右括号（② 已管带冒号的那一半）
  const re7 = new RegExp('(^|[^0-9A-Za-z_.\\(-])(' + N34 + '\\s*[-/]\\s*' + N34 + ')(?:\\s*' + CJKc + '|[)）])', 'g');
  while ((mm = re7.exec(body)) !== null) push('⑦', mm.index + mm[0].indexOf(mm[2]), mm[2]);
  return hits;
}

function scanFile(f) {
  const src = fs.readFileSync(f, 'utf8');
  const linesAll = src.split(/\r?\n/);
  const blockLines = new Set();
  let inBlock = false;
  linesAll.forEach((l, i) => {
    const n = (l.match(/"""/g) || []).length;
    if (inBlock) { blockLines.add(i + 1); if (n % 2 === 1) inBlock = false; return; }
    if (n % 2 === 1) inBlock = true;
  });
  const out = [];
  linesAll.forEach((raw, i) => {
    const ln = i + 1, t = raw.trim();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
    if (blockLines.has(ln)) return;
    let code = stripInterpolations(raw);
    const cut = code.search(/\s\/\//);
    if (cut >= 0) code = code.slice(0, cut);
    const litRe = /"(?:[^"\\]|\\.)*"/g;
    let m;
    while ((m = litRe.exec(code)) !== null) {
      const body = m[0].slice(1, -1);
      if (!CJK.test(body)) continue;
      const shapes = findShapes(body).filter((h) => !exempt(body, h.idx));
      if (!shapes.length) continue;
      if (ALLOW.some((a) => a.file === f && raw.includes(a.has))) return;
      out.push({ file: f, line: ln, shapes: shapes.map((s) => s.shape), sample: m[0].slice(0, 96) });
      return;                                             // 一行只报一次，跟原版行为一致
    }
  });
  return out;
}

function run(dirs) {
  const files = [];
  for (const d of dirs) for (const f of listFiles(d)) files.push(f);
  const hits = [];
  for (const f of files.sort()) hits.push(...scanFile(f));
  return { filesScanned: files.length, hits };
}

function selftest() {
  const dir = path.join('fixtures', 'copynum');
  const fire = run([path.join(dir, 'fire')]);
  const ok = run([path.join(dir, 'ok')]);
  const wantFire = 8;                                      // 七条形状各一条 + 一条"掩码豁免不许吃下带汉字的括号"的近失正控
  const got = new Set();
  for (const h of fire.hits) for (const s of h.shapes) got.add(s);
  const bad = [];
  if (fire.hits.length !== wantFire) bad.push(`fire/ 期望 ${wantFire} 行命中，实得 ${fire.hits.length}`);
  for (const s of ['①', '②', '③', '④', '⑤', '⑥', '⑦']) if (!got.has(s)) bad.push(`形状 ${s} 没有正控开火`);
  if (ok.hits.length !== 0) bad.push(`ok/ 期望 0 条，实得 ${ok.hits.length}: ` + ok.hits.map((h) => h.file + ':' + h.line).join(', '));
  console.log(`[selftest] fire=${fire.hits.length}/${wantFire} (开火的形状: ${[...got].sort().join('')})  ok=${ok.hits.length}/0  扫描文件数 fire=${fire.filesScanned} ok=${ok.filesScanned}`);
  for (const h of fire.hits) console.log('  fire:', path.basename(h.file) + ':' + h.line, h.shapes.join('+'), h.sample.slice(0, 60));
  if (!fire.filesScanned || !ok.filesScanned) bad.push('夹具目录里一个 .swift 都没有 ⇒ 本轮比较无意义');
  if (bad.length) { for (const b of bad) console.log('✗ ' + b); process.exit(2); }
  console.log('copynum 自测 ✓');
}

if (flags.has('--selftest')) { selftest(); process.exit(0); }
const r = run(ROOTS);
if (flags.has('--json')) { console.log(JSON.stringify(r, null, 2)); process.exit(r.hits.length && flags.has('--fail') ? 1 : 0); }
console.log(`样本量: 扫了 ${r.filesScanned} 个文件 · 疑似含内部规格编号 ${r.hits.length} 行 · ALLOW 销号 ${ALLOW.length} 条 (按 文件+片段 认，不按行号)`);
for (const h of r.hits) console.log(`内部规格编号疑似进界面 [${h.shapes.join('+')}] ${h.file}:${h.line}  ${h.sample}`);
console.log(r.hits.length === 0
  ? '✓ 用户可见文案无内部规格编号'
  : `⚠ 用户可见文案疑似含内部规格编号 ${r.hits.length} 处 (${flags.has('--fail') ? '判失败' : '顾问级, 不判失败'}) — 保留说明、删掉编号`);
process.exit(r.hits.length && flags.has('--fail') ? 1 : 0);
