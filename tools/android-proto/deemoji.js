'use strict';
// tools/proto/deemoji.js —— 把已生成页面里的 emoji 换成 SVG 占位
const fs = require('fs');
const path = require('path');
const D = __dirname;
const MAP = {"🔒":"lock","🔓":"lockOpen","🔐":"lock","🔑":"key","⚿":"key","🛡":"shield","🛡️":"shield","✓":"check","✔":"check","👤":"person","👥":"people","👪":"people","📱":"phone","📲":"phone","📡":"wifi","📶":"signal","💾":"db","💿":"db","🕐":"clock","⏱":"timer","⏱️":"timer","📅":"calendar","🎂":"calendar","⬆":"arrowUp","⬇":"arrowDown","⬆️":"arrowUp","⬇️":"arrowDown","🔍":"search","📋":"copy","👁":"eye","👁️":"eye","🗑":"trash","🗑️":"trash","⚙":"gear","⚙️":"gear","📄":"doc","📂":"folder","🗄":"archive","🗄️":"archive","📊":"chart","📝":"list","⭐":"star","★":"star","❤️":"heart","❤":"heart","🔋":"battery","🏠":"house","🏢":"house","🏬":"house","🚪":"house","🚗":"house","⚠":"warn","⚠️":"warn","ℹ":"info","ⓘ":"info","✕":"xmark","✖":"xmark","📤":"export","🔄":"refresh","♻":"refresh","☝":"fingerprint","☝️":"fingerprint","🔔":"ring","🎨":"ring","🛠":"gear","🩺":"heart","✨":"star","🏷":"doc","🎯":"ring","🏆":"star","🔖":"doc","📎":"doc"};
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
let total = 0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  const orig = s;
  for (const [emo, name] of Object.entries(MAP)) {
    if (s.indexOf(emo) < 0) continue;
    s = s.split(emo).join('<span class="svgi" data-i="' + name + '"></span>');
    total++;
  }
  if (s !== orig) {
    if (s.indexOf('icons-render.js') < 0) {
      s = s.replace('<script src="interact.js"></script>',
        '<script src="icons-render.js"></script>\n<script src="interact.js"></script>');
    }
    fs.writeFileSync(fp, s, 'utf8');
  }
}
console.log('✓ emoji 替换 ' + total + ' 处');
