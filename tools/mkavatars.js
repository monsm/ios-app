'use strict';
// tools/mkavatars.js —— 按成员配色批量生成头像
const fs = require('fs'), path = require('path');
const { execFileSync } = require('child_process');
const K = require('./imgkit.js');
const PRISM = path.join(__dirname, 'prism');
const OUT = path.join(__dirname, 'proto/img');
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

// 成员的语义色（与页面一致）
const MEMBERS = [
  { id: 'wo',   color: '0x7B7BE8' },   // 朕 靛蓝
  { id: 'fei',  color: '0xE8A05C' },   // 爱妃 铜
  { id: 'huang',color: '0x30D158' },   // 皇子 绿
  { id: 'fu',   color: '0xFF3B30' },   // 父上 红
  { id: 'mu',   color: '0x0ADBD8' },   // 母上 薄荷
];

const base = fs.readFileSync(path.join(PRISM,'member-avatar.html'),'utf8');
for (const m of MEMBERS) {
  const html = base.replace(/color: 0x[0-9A-Fa-f]{6}, roughness: 0\.42/, 'color: ' + m.color + ', roughness: 0.42');
  const f = path.join(PRISM, 'av-' + m.id + '.html');
  fs.writeFileSync(f, html, 'utf8');
  const raw = path.join(PRISM, 'av-' + m.id + '-raw.png');
  try { fs.unlinkSync(raw); } catch {}
  execFileSync(EDGE, ['--headless=new','--disable-gpu','--use-angle=swiftshader',
    '--allow-file-access-from-files','--window-size=256,256',
    '--screenshot=' + raw, '--virtual-time-budget=8000',
    'file:///' + f.replace(/\\/g,'/')], { stdio: 'ignore' });
  const img = K.decodePNG(fs.readFileSync(raw));
  K.keyOut(img, { threshold: 14, feather: 24 });
  fs.writeFileSync(path.join(OUT, 'avatar-' + m.id + '.png'), K.encodePNG(img.w, img.h, img.data));
  const r = K.resize(img, 128, 128);
  fs.writeFileSync(path.join(OUT, 'avatar-' + m.id + '-128.png'), K.encodePNG(128, 128, r.data));
  console.log('✓ avatar-' + m.id);
}
