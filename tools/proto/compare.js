'use strict';
// tools/proto/compare.js —— 按 REFERENCE-SPEC.md 的百分比逐项对照
//
// 参考图的每个值都是「占屏宽百分比」，乘 390 得到 @390 屏的 pt。
// 这个脚本在真实浏览器里读 getComputedStyle / getBoundingClientRect，
// 和规格表逐项比，超出容差就报。
const { execFileSync } = require('child_process');
const fs = require('fs'), path = require('path');
const D = __dirname;
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

// 图 2/3 的规格（钥匙/系统页是 C 模板，最重要）
const SPEC = [
  ['chip',       'height', 56, 2,  '图2 胶囊高'],
  ['chip',       'radius', 18, 2,  '图2 胶囊圆角'],
  ['card',       'radius', 26, 1,  '图2 卡片圆角'],
  ['card',       'left',   14, 2,  '图2 卡左边距'],
  ['.cardlink',  'size',   14, 1,  '图2 卡头字号（§7.11）'],
  ['.ctitle',    'size',   19, 1,  '图2 卡标题字号'],
  ['.clabel',    'size',   12, 1,  '图2 label 字号'],
  ['.cvalue',    'size',   16, 1,  '图2 value 字号'],
  ['.footer',    'size',   12, 1,  '图2 页脚字号'],
  ['.h1',        'size',   30, 2,  '图3 大标题字号'],
  ['.sub',       'size',   16, 1,  '图3 正文字号'],
  ['.tabbar',    'height', 62, 2,  '图1 Tab Bar 高'],
];

const PAGES = ['01-home','02-keys','03-devices','04-members','05-system'];

const probe = (file, items) => {
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>body{margin:0}iframe{width:454px;height:908px;border:0}</style></head><body>
<iframe id="f" src="${file}"></iframe>
<script>
window.addEventListener('load',()=>setTimeout(()=>{
  var d=document.getElementById('f').contentDocument,w=document.getElementById('f').contentWindow;
  var out={};
  ${JSON.stringify(items.map(i=>i[0])).slice(1,-1).split(',').map(s=>s.trim()).filter(Boolean).map(sel=>{
    const s = sel.trim().replace(/^"|"$/g,'');
    return `try{var e=d.querySelector('${s}');if(e){var cs=w.getComputedStyle(e),r=e.getBoundingClientRect();out['${s}']={h:Math.round(r.height),w:Math.round(r.width),l:Math.round(r.left),fs:parseFloat(cs.fontSize),br:parseFloat(cs.borderTopLeftRadius)||0};}}catch(x){}`;
  }).join('')}
  document.title='R|'+JSON.stringify(out);
},700));
</script></body></html>`;
  const tmp = path.join(D, '_c.html');
  fs.writeFileSync(tmp, html, 'utf8');
  try {
    const o = execFileSync(EDGE, ['--headless=new','--disable-gpu','--use-angle=swiftshader',
      '--allow-file-access-from-files','--window-size=470,960','--dump-dom',
      '--virtual-time-budget=2500','file:///' + tmp.replace(/\\/g,'/')],
      { encoding:'utf8', stdio:['ignore','pipe','ignore'] });
    const m = o.match(/R\|(\{[^<]*\})/);
    return m ? JSON.parse(m[1]) : null;
  } catch(e) { return null; }
};

let pass=0, fail=0;
const fails=[];
for (const pg of PAGES) {
  const r = probe(pg + '.html', SPEC);
  if (!r) { fails.push(pg + ': 测量失败'); fail++; continue; }
  for (const [sel, prop, want, tol, label] of SPEC) {
    const v = r[sel];
    if (!v) continue;
    const got = prop==='height'?v.h : prop==='radius'?v.br : prop==='left'?v.l : v.fs;
    if (got===undefined||got===null) continue;
    if (Math.abs(got-want) > tol) {
      fails.push(pg + ' ' + label + ': ' + got + ' (应 ' + want + '±' + tol + ')');
      fail++;
    } else pass++;
  }
}
if (fails.length) console.log(fails.join('\n'));
console.log('\n对照: ✓' + pass + ' ✗' + fail);
