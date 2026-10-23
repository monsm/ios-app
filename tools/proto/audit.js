'use strict';
// tools/proto/audit.js —— 像素级规范校验
//
// 为什么需要它：我靠肉眼看截图判断"像不像"，误判过两次
// （以为字号小、以为布局溢出，实际都是窗口尺寸或压缩的问题）。
// 这个脚本在真实浏览器里读 getComputedStyle，只有数字说话。
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const D = __dirname;
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

// 规范硬约束（§4.2 / §5.1 / §5.4 / §15）
const SPEC = {
  h1Size: 30,        // largeTitle
  subSize: 16,       // body
  clabelSize: 12,    // footnote
  cvalueSize: 16,    // headline
  footerSize: 12,    // footnote
  cardGap: 12,       // 卡间距
  titleToCard: 74,   // 标题→首卡
  gutter: 14,        // 页边距
};

const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
const only = process.argv.slice(2);
const list = only.length ? reg.filter(p=>only.includes(p.f)) : reg;

const probe = (file) => {
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>body{margin:0}iframe{width:454px;height:908px;border:0}</style></head><body>
<iframe id="f" src="${file}"></iframe>
<script>
window.addEventListener('load',function(){setTimeout(function(){
  var fr=document.getElementById('f'),d=fr.contentDocument,w=fr.contentWindow;
  var o={};
  function g(sel,key,prop){
    var el=d.querySelector(sel); if(!el)return;
    var cs=w.getComputedStyle(el),r=el.getBoundingClientRect();
    o[key]={fs:parseFloat(cs.fontSize),x:Math.round(r.left),w:Math.round(r.width)};
  }
  g('.page','page'); g('.h1','h1'); g('.sub','sub');
  g('.card','card'); g('.card .clabel','clabel');
  g('.card .cvalue','cvalue'); g('.footer','footer');
  var h1=d.querySelector('.h1');
  if(h1){
    // 标题块底部 = max(h1 底, sub 底)。之前取了 h1.parentElement，
    // 但 h1 的父级就是 .page，等于把整页当标题块 → 量出 610 之类的假数字。
    var hy=h1.getBoundingClientRect().bottom;
    var sub=d.querySelector('.sub');
    if(sub){
      var sb=sub.getBoundingClientRect().bottom;
      if(sb>hy) hy=sb;
    }
    // 取「在标题下方、且离标题最近」的卡/duo/hero
    var cands=Array.prototype.slice.call(d.querySelectorAll('.card,.duo,.gallery-hero,.dpanel,.chiprow,.segctl,.segctl2'));
    var best=null,bestD=1e9;
    cands.forEach(function(el){
      var t=el.getBoundingClientRect().top;
      if(t>hy+1&&t-hy<bestD){bestD=t-hy;best=el;}
    });
    if(best)o.titleToCard=Math.round(bestD);
  }
  // 只量**真正相邻**的两张卡（中间不能隔着别的块）
  var pg=d.querySelector('.page');
  if(pg){
    var kids=Array.prototype.slice.call(pg.children);
    for(var i=0;i<kids.length-1;i++){
      var isA=kids[i].classList&&kids[i].classList.contains('card');
      var nxt=kids[i+1];
      var isB=nxt.classList&&nxt.classList.contains('card');
      if(isA&&isB){
        o.cardGap=Math.round(nxt.getBoundingClientRect().top-kids[i].getBoundingClientRect().bottom);
        break;
      }
    }
  }
  document.title='R|'+JSON.stringify(o);
},700)});
</script></body></html>`;
  const tmp = path.join(D, '_a.html');
  fs.writeFileSync(tmp, html, 'utf8');
  try {
    const out = execFileSync(EDGE, ['--headless=new','--disable-gpu','--use-angle=swiftshader',
      '--allow-file-access-from-files','--window-size=470,960','--dump-dom',
      '--virtual-time-budget=3000','file:///' + tmp.replace(/\\/g,'/')],
      { encoding: 'utf8', stdio: ['ignore','pipe','ignore'] });
    const m = out.match(/R\|(\{[^<]*\})/);
    return m ? JSON.parse(m[1]) : null;
  } catch (e) { return null; }
};

let pass = 0, fail = 0;
const fails = [];
for (const p of list) {
  const r = probe(p.f + '.html');
  if (!r) { fails.push(p.f + ': 测量失败'); fail++; continue; }
  const errs = [];
  if (r.h1 && Math.abs(r.h1.fs - SPEC.h1Size) > 0.5) errs.push('h1字号 ' + r.h1.fs + '≠' + SPEC.h1Size);
  if (r.sub && Math.abs(r.sub.fs - SPEC.subSize) > 0.5) errs.push('sub字号 ' + r.sub.fs + '≠' + SPEC.subSize);
  if (r.clabel && Math.abs(r.clabel.fs - SPEC.clabelSize) > 0.5) errs.push('clabel ' + r.clabel.fs + '≠' + SPEC.clabelSize);
  if (r.cvalue && Math.abs(r.cvalue.fs - SPEC.cvalueSize) > 0.5) errs.push('cvalue ' + r.cvalue.fs + '≠' + SPEC.cvalueSize);
  if (r.footer && Math.abs(r.footer.fs - SPEC.footerSize) > 0.5) errs.push('footer ' + r.footer.fs + '≠' + SPEC.footerSize);
  if (r.cardGap !== undefined && r.cardGap !== SPEC.cardGap) errs.push('卡间距 ' + r.cardGap + '≠' + SPEC.cardGap);
  if (r.titleToCard !== undefined && Math.abs(r.titleToCard - SPEC.titleToCard) > 2) errs.push('标题→卡 ' + r.titleToCard + '≠' + SPEC.titleToCard);
  if (errs.length) { fails.push('✗ ' + p.f + ' ' + p.t + ': ' + errs.join(' / ')); fail++; }
  else pass++;
}
if (fails.length) { console.log(fails.join('\n')); }
console.log('\n像素级校验: ✓' + pass + ' ✗' + fail + ' / ' + list.length);
