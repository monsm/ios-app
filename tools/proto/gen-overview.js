'use strict';
const fs = require('fs');
const D = __dirname + '/';
const reg = JSON.parse(fs.readFileSync(D+'registry.json','utf8'));
const groups = [...new Set(reg.map(p=>p.g))];

const grid = groups.map(g=>{
  const items = reg.filter(p=>p.g===g);
  return `<section>
  <h2>${g} <span class="cnt">${items.length} 页</span></h2>
  <div class="row">
    ${items.map(p=>{
      const n = reg.indexOf(p)+1;
      return `<figure>
        <a href="${p.f}.html" target="_blank"><img src="${p.f}.png" alt="${p.t}" loading="lazy"></a>
        <figcaption><b>${String(n).padStart(2,'0')} ${p.t}</b><span>${p.d}</span></figcaption>
      </figure>`;
    }).join('')}
  </div>
</section>`;
}).join('\n');

const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>KF Key · 全界面原型 ${reg.length} 页</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#070709;font-family:-apple-system,"SF Pro Text","PingFang SC",sans-serif;
  color:#E8E8EA;padding:40px 32px 80px}
header{max-width:1600px;margin:0 auto 40px}
h1{font-size:28px;font-weight:700;letter-spacing:-.5px}
.sub{font-size:14px;color:#8D8D93;margin-top:8px;line-height:1.6}
.sub b{color:#E8A05C}
section{max-width:1600px;margin:0 auto 44px}
h2{font-size:15px;font-weight:600;color:#A8A8AE;margin-bottom:16px;
  padding-bottom:10px;border-bottom:1px solid #1E1E22;display:flex;align-items:baseline;gap:10px}
h2 .cnt{font-size:11px;color:#5A5A5E;font-weight:400}
.row{display:flex;gap:20px;overflow-x:auto;padding-bottom:12px;scrollbar-width:thin}
.row::-webkit-scrollbar{height:8px}
.row::-webkit-scrollbar-thumb{background:#22222A;border-radius:4px}
figure{flex:0 0 auto;width:270px}
figure a{display:block}
figure img{width:270px;height:585px;object-fit:cover;object-position:top;
  border-radius:16px;background:#0A0A0C;border:1px solid #1E1E22;
  transition:border-color .15s,transform .15s}
figure a:hover img{border-color:#E8A05C;transform:translateY(-3px)}
figcaption{margin-top:10px;font-size:12px;line-height:1.5}
figcaption b{display:block;color:#E8E8EA;font-weight:600;margin-bottom:3px}
figcaption span{color:#6A6A6E;font-size:11px}
</style></head><body>
<header>
  <h1>KF Key · 全界面原型</h1>
  <div class="sub">
    <b>${reg.length} 页</b> · 依据 ios-glass-design-spec · 对照 6 张参考图<br>
    点任意缩略图在新标签打开那一页（页面内可交互：Tab、行、按钮都可点）
  </div>
</header>
${grid}
</body></html>`;
fs.writeFileSync(D+'overview.html', html, 'utf8');
console.log('overview.html 生成', html.length, '字节，', reg.length, '页');
