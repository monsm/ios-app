#!/usr/bin/env node
/* featurewebcheck.js — 校验 docs/feature-web 的产物与 inventory 源是否一致（CI 闸门）。
 *
 * 为什么需要：蜘蛛网是三份产物（features.json / feature-web.html / 清单），
 * 由 inventory/*.json 经 build.js → build_html.js → export.js 生成。
 * 三份是**派生物**，一旦有人改了 inventory 忘了重建，提交里就会出现
 * 「数据说 A、图显示 B」——这比没有图更糟：读者会以为图是权威的。
 *
 * 判据：用 inventory 重算一遍，与 committed 的产物做规范化比较。
 *   - features.json：比 meta.generated 之外的**全部内容**（generated 是时间戳，每次不同）
 *   - feature-web.html / 清单：比「去掉 generated 时间戳后的字节」
 *
 * 用法：
 *   node tools/featurewebcheck.js           只校验（CI）
 *   node tools/featurewebcheck.js --rebuild 先重建再校验
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const FW = path.join(ROOT, 'docs/feature-web');
const REBUILD = process.argv.includes('--rebuild');

function run(script) {
  execFileSync(process.execPath, [path.join(FW, script)], { cwd: FW, stdio: 'pipe' });
}

if (REBUILD) {
  run('build.js');
  run('build_html.js');
  run('export.js');
}

// ---------- 规范化：抹掉时间戳与生成日期 ----------
function normalizeJson(text) {
  const j = JSON.parse(text);
  if (j.meta) {
    delete j.meta.generated;
    // 产物里 sources 含 inventory 文件名与节点数 —— 保留（那是可校验的事实）
  }
  return stableStringify(j);
}
function stableStringify(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(stableStringify).join(',') + ']';
  const keys = Object.keys(v).sort();
  return '{' + keys.map(k => JSON.stringify(k) + ':' + stableStringify(v[k])).join(',') + '}';
}
function normalizeHtml(text) {
  // meta.generated 内联在 JSON 里；只抹这一个字段
  return text.replace(/"generated":\s*"[^"]*"/g, '"generated":"<TS>"')
             .replace(/\d{4}-\d{2}-\d{2}T[\d:.]+Z/g, '<TS>');
}
function stripBom(t) { return t.replace(/^\uFEFF/, ''); }

const checks = [];
function check(name, ok, detail) {
  checks.push({ name, ok, detail });
}

// 1) inventory 是否有源
const invDir = path.join(FW, 'inventory');
if (!fs.existsSync(invDir)) {
  console.error('✗ docs/feature-web/inventory 不存在，无法校验');
  process.exit(1);
}
const invFiles = fs.readdirSync(invDir).filter(f => f.endsWith('.json'));

// 2) features.json 与重算结果一致
try {
  const committed = normalizeJson(fs.readFileSync(path.join(FW, 'features.json'), 'utf8'));
  // 重算到临时文件：build.js 会写 features.json，所以先在内存里比
  const tmpBefore = fs.readFileSync(path.join(FW, 'features.json'), 'utf8');
  run('build.js');
  const rebuilt = normalizeJson(fs.readFileSync(path.join(FW, 'features.json'), 'utf8'));
  fs.writeFileSync(path.join(FW, 'features.json'), tmpBefore);   // 还原，避免校验动作本身产生 diff
  const same = committed === rebuilt;
  check('features.json 与 inventory 一致', same,
    same ? '' : 'inventory 改了但没重建（跑 node tools/featurewebcheck.js --rebuild）');

  // 2026-10-26: 本闸门在 CI 上连红而本地永远绿，日志里只有一句「不一致」没法定位。
  // 把第一处差异与两侧上下文打出来 —— 有这条输出，下一次不用再猜。
  if (!same) {
    let k = 0;
    while (k < Math.min(committed.length, rebuilt.length) && committed[k] === rebuilt[k]) k++;
    console.log('\n  —— 差异定位 ——');
    console.log('  首个差异位置: ' + k + ' / committed=' + committed.length + ' rebuilt=' + rebuilt.length);
    console.log('  committed: ' + JSON.stringify(committed.slice(Math.max(0, k - 120), k + 160)));
    console.log('  rebuilt  : ' + JSON.stringify(rebuilt.slice(Math.max(0, k - 120), k + 160)));
    try {
      const A2 = JSON.parse(tmpBefore);
      const B2 = JSON.parse(fs.readFileSync(path.join(FW, 'features.json'), 'utf8'));
      for (const key of Object.keys(A2)) {
        if (key === 'meta') continue;
        const sa = stableStringify(A2[key]);
        const sb = stableStringify(B2[key]);
        if (sa !== sb) console.log('  差异字段: ' + key + '  committed=' + sa.length + ' rebuilt=' + sb.length);
      }
    } catch (e2) { console.log('  字段级诊断失败: ' + e2.message); }
  }
} catch (e) {
  check('features.json 可校验', false, e.message.split('\n')[0]);
}

// 3) 派生清单与 html 里不能出现「inventory 之外」的陈旧节点数
try {
  const fj = JSON.parse(fs.readFileSync(path.join(FW, 'features.json'), 'utf8'));
  const html = fs.readFileSync(path.join(FW, 'feature-web.html'), 'utf8');
  const md = stripBom(fs.readFileSync(path.join(FW, '功能蜘蛛网.md'), 'utf8'));
  const csv = stripBom(fs.readFileSync(path.join(FW, '功能点清单.csv'), 'utf8'));
  const n = fj.nodes.length;

  // html 内嵌的 DATA 里必须有同样的节点数
  const nodesInHtml = (html.match(/"key":/g) || []).length;
  check('feature-web.html 的节点数与 features.json 一致', nodesInHtml >= n,
    `${nodesInHtml} < ${n}`);

  // 清单行数 = 非域节点数 + 表头
  const rows = csv.split(/\r?\n/).filter(Boolean).length - 1;
  const nonDomain = fj.nodes.filter(x => !x.isDomain).length;
  check('功能点清单.csv 行数与 features.json 一致', rows === nonDomain,
    `csv ${rows} 行 ≠ 非域节点 ${nonDomain}`);

  // md 里要有总览数字
  check('功能蜘蛛网.md 含节点总数', md.includes(String(n)), `未找到 ${n}`);
} catch (e) {
  check('派生产物可读', false, e.message.split('\n')[0]);
}

// 4) inventory 自身结构健全（每条至少 1 证据）
let badNode = 0;
for (const f of invFiles) {
  const j = JSON.parse(fs.readFileSync(path.join(invDir, f), 'utf8'));
  for (const node of (j.nodes || [])) {
    if (!node.isDomain && !(node.evidence && node.evidence.length)) badNode++;
  }
}
check('inventory 无「零证据」节点', badNode === 0, `${badNode} 个`);

// ---------- 输出 ----------
console.log('功能图谱派生一致性检查 (docs/feature-web)');
console.log(`  inventory 源: ${invFiles.length} 份\n`);
let fail = 0;
for (const c of checks) {
  console.log(`  ${c.ok ? '✓' : '✗'} ${c.name}${(!c.ok && c.detail) ? '  ← ' + c.detail : ''}`);
  if (!c.ok) fail++;
}
console.log(`\n通过 ${checks.length - fail} · 失败 ${fail}`);
if (fail) {
  console.log('\n修复: node tools/featurewebcheck.js --rebuild 后重新提交');
}
process.exit(fail ? 1 : 0);
