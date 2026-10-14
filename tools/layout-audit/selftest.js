#!/usr/bin/env node
// R6 材质判据的正/负控。
//   node tools/layout-audit/selftest.js
// 为什么要有这个文件: R6 曾经把"玻璃"只在 `background(...)` 的参数文本里找, 于是
// `.axGlass(DS.Radius.card)` 这种链式修饰符永远数不进玻璃列 —— 全 App 改完玻璃之后
// 它仍报"玻璃 0 处", 一条看起来在跑、实际永远为假的指标。下面五组 fixtures 分别钉住
// 玻璃列 / 盘子列 / 面板实底列 / 混用严重度, 少认任何一列就当场失败。
'use strict';
const fs = require('fs'), path = require('path');
const A = require('./ast.js');
const R = require('./rules.js');
const ROOT = path.resolve(__dirname, '../..');
const DIR = path.join(__dirname, 'fixtures', 'r6');

const tk = A.loadTokens(path.join(ROOT, 'App/Core/DesignSystem.swift'));
if (!Object.keys(tk.SPACE).length) { console.error('DesignSystem 令牌没解析到，停'); process.exit(1); }

function r6Of(file, rule) {
  const want = rule || 'R6 材质混用';
  const pre = R.parseAll([file], tk, 1.0, {});
  const out = R.runAll(pre, { tk, scale: 1.0, deviceW: 390, dens: 1.0 }).filter((f) => f.rule === want);
  if (out.length > 1) throw new Error(path.basename(file) + ': ' + want + ' 应当每文件至多一条, 实得 ' + out.length);
  return out[0] || null;
}
function counts(f) {
  if (!f) return null;
  const m = /面板级实底 (\d+) 处 \/ 玻璃 (\d+) 处 \/ 盘中 plate (\d+) 处/.exec(f.msg);
  if (!m) throw new Error('R6 文案形状变了, 断言读不出计数: ' + f.msg);
  return { solid: +m[1], glass: +m[2], plate: +m[3] };
}

// [文件, 期望(或断言函数), 说明]
const CASES = [
  ['glass.swift', (f) => f === null, '纯玻璃(axGlass+axGlassCapsule)不该被报成层感不统一'],
  ['plate.swift', (f) => f === null, '玻璃面上的 surfaceAlt 盘子不是面板, 不该单独开火'],
  ['solid.swift', (f) => { const c = counts(f); return c && c.solid === 1 && c.glass === 0 && c.plate === 0 && f.sev === 'lo'; }, '一处面板实底 ⇒ 开火, 且严重度 lo (这一页还没有玻璃)'],
  ['mixed.swift', (f) => { const c = counts(f); return c && c.solid === 1 && c.glass === 1 && c.plate === 1 && f.sev === 'md'; }, '玻璃+实底同文件 ⇒ 开火且升 md; 盘子单列不混进前两列'],
  ['capsule.swift', (f) => { const c = counts(f); return c && c.glass === 1 && c.solid === 1; }, 'axGlassCapsule 必须与 axGlass 同列 (少认它 glass 就归 0)'],
  ['allowed.swift', (f) => f === null, '带 @layout-allow 标记的实底面板不该再算混用缺陷'],
];

let bad = 0;
for (const [name, judge, why] of CASES) {
  const p = path.join(DIR, name);
  if (!fs.existsSync(p)) { console.error(`  ✗ ${name} 不存在 (fixtures/r6/)  ${why}`); bad++; continue; }
  let ok = false, got = '';
  try { const f = r6Of(p); ok = judge(f); got = f ? f.msg : '无命中'; }
  catch (e) { got = '抛错: ' + e.message; ok = false; }
  if (!ok) bad++;
  console.log(`  ${ok ? '✓' : '✗'} ${name.padEnd(15)} ${why}${ok ? '' : ' ⇒ 实得 ' + got}`);
}
if (bad) { console.error(`R6 材质判据自检失败 ${bad} 项`); process.exit(1); }

// 豁免必须是"能被机器撤掉的豁免": 把标记行删掉重扫, 同一段代码要立刻重新开火。
// 只验"有标记时不开火"是半个断言 —— 那也可能因为规则压根没看见这颗节点。
const os = require('os');
const srcTxt = fs.readFileSync(path.join(DIR, 'allowed.swift'), 'utf8');
if (!/@layout-allow 面板实底/.test(srcTxt)) { console.error('  ✗ allowed.swift 里的标记本身不见了'); process.exit(1); }
const stripped = srcTxt.replace(/\s*\/\/ @layout-allow 面板实底/, '');
const tmp = path.join(os.tmpdir(), 'r6_allow_off.swift');
fs.writeFileSync(tmp, stripped, 'utf8');
const back = r6Of(tmp);
const bc = counts(back);
const offOk = !!back && bc && bc.solid === 1 && back.sev === 'md';
console.log(`  ${offOk ? '✓' : '✗'} allowed-off   抹掉标记后同一段代码必须重新开火 (实得 ${back ? back.msg : '无命中'})`);
fs.unlinkSync(tmp);
if (!offOk) { console.error('R6 材质判据自检失败 (豁免不可撤销)'); process.exit(1); }

// 已定性那一侧也要留痕: 有标记 ⇒ 出一条"已定性"，不能悄悄消失
const al = r6Of(path.join(DIR, 'allowed.swift'), 'R6 材质已定性');
const alOk = !!al && /已定性保留的面板实底 1 处/.test(al.msg);
console.log(`  ${alOk ? '✓' : '✗'} allowed-trace 已定性必须单独报一条 (实得 ${al ? al.msg : '无命中'})`);
if (!alOk) { console.error('R6 材质判据自检失败 (已定性无痕)'); process.exit(1); }

console.log('R6 材质判据自检 ✓ (玻璃列/盘子列/面板实底列/混用严重度/豁免可撤销 六组正负控全过)');

// ---------- R5 触达: 菜单内容项托管 / 菜单触发器照判 ----------
function r5Of(file) {
  const pre = R.parseAll([file], tk, 1.0, {});
  return R.runAll(pre, { tk, scale: 1.0, deviceW: 390, dens: 1.0 }).filter((f) => f.rule.startsWith('R5'));
}
const MENU = path.join(__dirname, 'fixtures', 'r5', 'menu.swift');
if (!fs.existsSync(MENU)) { console.error('  ✗ fixtures/r5/menu.swift 不存在'); process.exit(1); }
// 固定条件 (标准密度/390pt/字号 1.0) 下的行号: Menu 触发器 7, 内容项 Button 8/9/11
const menuHits = r5Of(MENU).map((f) => f.line);
const trigOk = menuHits.includes(7);
const itemOk = ![8, 9, 11].some((l) => menuHits.includes(l));
console.log(`  ${trigOk ? '✓' : '✗'} menu-trigger   Menu 触发器自身无 minHeight 必须开火 (实得命中行 ${JSON.stringify(menuHits)})`);
console.log(`  ${itemOk ? '✓' : '✗'} menu-items    Menu 内容项由系统给行高, 不该判成触达不足 (实得命中行 ${JSON.stringify(menuHits)})`);
if (!trigOk || !itemOk) { console.error('R5 菜单托管判据自检失败'); process.exit(1); }
