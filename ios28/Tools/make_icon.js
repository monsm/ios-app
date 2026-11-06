#!/usr/bin/env node
// make_icon.js —— 生成 1024×1024 的 App 图标（Edge headless 渲染 HTML）。
//
// 图形：一块日光底、一条黄铜门槛线、一枚骑在门槛上的玻璃镜头。
// 这是整个 App 的唯一符号，不画门、不画锁、不画房子。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'App', 'Assets.xcassets', 'AppIcon.appiconset');
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const variants = {
  'icon-any.png': { bg: '#F3F0E9', warm: '#F0D6B0', ink: '#14161A', brass: '#9A7444', glass: '#FFFFFF', line: '#B99A6E' },
  'icon-dark.png': { bg: '#0D0F12', warm: '#6E5536', ink: '#F3F1EC', brass: '#D8B47F', glass: '#242A31', line: '#D8B47F' },
  'icon-tinted.png': { bg: '#F3F0E9', warm: '#E7E3DA', ink: '#3A3A3A', brass: '#6E6E6E', glass: '#FFFFFF', line: '#8A8A8A' },
};

function html(v) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{width:1024px;height:1024px;overflow:hidden}
  .icon{position:relative;width:1024px;height:1024px;background:${v.bg};overflow:hidden}
  .warm{position:absolute;width:1100px;height:1100px;border-radius:50%;
    background:${v.warm};opacity:.85;filter:blur(90px);right:-380px;top:-460px}
  .cool{position:absolute;width:760px;height:760px;border-radius:50%;
    background:#FFFFFF;opacity:.75;filter:blur(100px);left:-260px;top:-120px}
  .line{position:absolute;left:110px;right:110px;top:512px;height:3px;
    background:linear-gradient(90deg,transparent,${v.line},transparent);opacity:.55}
  .lens{position:absolute;left:50%;top:512px;width:470px;height:470px;margin-left:-235px;margin-top:-235px;
    border-radius:50%;
    background:radial-gradient(130% 130% at 32% 16%, ${v.glass}F2 0%, ${v.glass}B8 46%, ${v.glass}66 100%);
    box-shadow:0 40px 90px -30px rgba(30,24,16,.35), inset 0 3px 0 rgba(255,255,255,.8), inset 0 -6px 18px rgba(80,60,30,.10);
    border:2px solid rgba(255,255,255,.7);
    backdrop-filter:blur(20px)}
  .ring{position:absolute;inset:28px;border-radius:50%;border:3px solid ${v.brass};opacity:.34}
  .core{position:absolute;left:50%;top:50%;width:196px;height:196px;margin-left:-98px;margin-top:-98px;border-radius:50%;
    background:radial-gradient(120% 120% at 34% 26%, ${v.brass} 0%, ${v.brass} 60%);
    box-shadow:0 0 50px 14px ${v.brass}33, inset 0 3px 0 rgba(255,255,255,.35)}
  .kh{position:absolute;left:50%;top:50%;width:54px;height:54px;margin-left:-27px;margin-top:-46px;border-radius:50%;
    border:9px solid #FFF9EE}
  .ks{position:absolute;left:50%;top:50%;width:20px;height:46px;margin-left:-10px;margin-top:-6px;border-radius:10px;
    background:#FFF9EE}
  </style></head><body><div class="icon">
    <div class="warm"></div><div class="cool"></div>
    <div class="line"></div>
    <div class="lens"><div class="ring"></div><div class="core"><div class="kh"></div><div class="ks"></div></div></div>
  </div></body></html>`;
}

const tmp = path.join(ROOT, 'Tools', '.icon.html');
for (const [file, v] of Object.entries(variants)) {
  fs.writeFileSync(tmp, html(v), 'utf8');
  execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars',
    '--force-device-scale-factor=1', '--window-size=1024,1024',
    `--screenshot=${path.join(OUT, file)}`,
    'file:///' + tmp.replace(/\\/g, '/')], { stdio: 'ignore', timeout: 40000 });
  console.log('icon:', file);
}
fs.unlinkSync(tmp);
