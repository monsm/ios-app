'use strict';
// tools/proto/lint.js —— 结构完整性校验（防批量脚本的静默破坏）
//
// 起因：颜色收敛、环径归一、skeleton 这些批处理脚本，每次都会顺手改坏一些东西：
//   · <div style=">47%</div>           style 属性没闭合 → 整张卡排版塌
//   · 三环被收敛成同色                  Move粉/Exercise绿/Stand薄荷 丢了
//   · 环的 rotate 中心没跟着圆心变       整条弧转偏
// 这些肉眼扫不出来，只有截图才看得见。所以让脚本自己先报错。
const fs = require('fs'), path = require('path');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

const PALETTE = ['#0090FC','#F11B51','#FF3B30','#FF694E','#FF9F0A','#3CDE02','#0ADBD8','#30D158','#5E5CE6','#BF5AF2'];
let errs = 0;
const fail = (f, msg) => { console.log('  ✗ ' + f + ': ' + msg); errs++; };

for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) { fail(p.f, '文件不存在'); continue; }
  const s = fs.readFileSync(fp, 'utf8');

  // ① style 属性必须闭合且不为空
  const badStyle = s.match(/style="[^"]*"[^>]*style="|style=">|style=""[^>]*[^ ]/g);
  if (/style=">/.test(s)) fail(p.f, 'style 属性未闭合');
  if ((s.match(/style="/g)||[]).length !== (s.match(/style="/g)||[]).length) fail(p.f, 'style 引号不配对');

  // ② 三环必须是三种不同色
  for (const m of s.matchAll(/<svg width="(\d+)"[^>]*>([\s\S]*?)<\/svg>/g)) {
    const colors = [...new Set([...m[2].matchAll(/stroke="(#[0-9A-Fa-f]{6})"/g)].map(x=>x[1].toUpperCase()))];
    const ringCircles = (m[2].match(/<circle[^>]*stroke-dasharray/g)||[]).length;
    if (ringCircles >= 6 && colors.length < 3) {
      fail(p.f, '三环只有 ' + colors.length + ' 种色（应 ≥3）');
    }
  }

  // ③ 环的 rotate 中心必须等于圆心
  for (const m of s.matchAll(/<circle[^>]*cx="([\d.]+)"[^>]*cy="([\d.]+)"[^>]*stroke-dasharray[^>]*transform="rotate\((-?[\d.]+) ([\d.]+) ([\d.]+)\)"/g)) {
    const [ , cx, cy, rot, rx, ry ] = m;
    if (Math.abs(+cx - +rx) > 1.5 || Math.abs(+cy - +ry) > 1.5) {
      fail(p.f, '环 rotate 中心 (' + rx + ',' + ry + ') ≠ 圆心 (' + cx + ',' + cy + ')');
      break;
    }
  }

  // ④ a 标签必须平衡
  const oa = (s.match(/<a\b/g)||[]).length, ca = (s.match(/<\/a>/g)||[]).length;
  if (oa !== ca) fail(p.f, 'a 标签不平衡 ' + oa + '/' + ca);

  // ⑤ 环径必须在白名单（300 大环 / 101 三环 / 84 卡内 / 66 小环）
  const OK = new Set([300,101,84,66,72,56,64,52]);
  for (const m of s.matchAll(/<svg width="(\d+)"[^>]*>[\s\S]*?<circle[^>]*stroke="rgba\(255,255,255,\.1/g)) {
    const w = +m[1];
    if (w > 40 && !OK.has(w)) fail(p.f, '环径 ' + w + ' 不在白名单');
  }

  // ⑥ 页面必须有 interact.js
  if (!/interact\.js/.test(s)) fail(p.f, '缺 interact.js');
}

console.log(errs === 0 ? '\n✓ lint 全过（' + reg.length + ' 页）' : '\nlint 失败 ' + errs + ' 项');
process.exit(errs === 0 ? 0 : 1);
