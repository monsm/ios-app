#!/usr/bin/env node
// run.js —— 渲染 + 截图（Edge headless）。Windows 上没有 iOS 模拟器，这是唯一的"看见"手段。
//
// 用法：node DesignLab/run.js           渲染全部屏（浅色 + 深色）
//       node DesignLab/run.js today     只渲染 id 含 today 的屏
//       node DesignLab/run.js --html-only
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const lab = require('./lab.js');
const { SCREENS, I } = require('./screens.js');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'DesignLab', 'out');
const SHOTS = path.join(ROOT, 'DesignLab', 'shots');
for (const d of [OUT, SHOTS]) if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true });

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const TABS = [
  { label: '今日', icon: I.today },
  { label: '通行', icon: I.access },
  { label: '记录', icon: I.log },
];

const args = process.argv.slice(2);
const htmlOnly = args.includes('--html-only');
const widthArg = args.find((a) => a.startsWith('--width='));
const PHONE_W = widthArg ? parseInt(widthArg.split('=')[1], 10) : 430;
const filter = args.find((a) => !a.startsWith('--'));
const targets = filter ? SCREENS.filter((s) => s.id.includes(filter)) : SCREENS;
const modes = ['light', 'dark'];

function tabbar(active) {
  return '<nav class="tabbar glassStrong">' + TABS.map((t, i) =>
    `<div class="t ${i === active ? 'on' : ''}"><span class="g">${t.icon}</span>${t.label}</div>`).join('') + '</nav>';
}

function backIcon() {
  return '<svg width="11" height="18" viewBox="0 0 11 18" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M9.5 1.5L1.5 9l8 7.5"/></svg>';
}

function page(screen, mode) {
  const root = screen.tab <= 2 ? tabbar(screen.tab) : '';
  const nav = screen.nav
    ? `<div class="navbar" style="display:flex;align-items:center;justify-content:space-between;gap:12px;padding:8px 0 4px;min-height:44px">` +
      `${screen.tab > 2 ? `<div style="color:var(--ink2);width:22px">${backIcon()}</div>` : ''}` +
      `<div style="flex:1;min-width:0">${screen.nav}</div>` +
      `<div class="tr" style="font-size:15px;color:var(--ink2)">${screen.trailing || ''}</div></div>`
    : '';
  return `<!doctype html><html lang="zh" data-mode="${mode}"><head><meta charset="utf-8"><title>${screen.name}</title>` +
    `<style>${lab.rootVars(mode)}${lab.cssBody}</style></head><body>` +
    `<div class="phone" data-mode="${mode}">` +
    `<div class="field"></div><div class="grain"></div>` +
    `<div class="statusbar"><span>9:41</span><span>&#9679;&#9679;&#9679; &#9650;</span></div>` +
    `<div class="scroll">${nav}${screen.body}</div>` +
    root + `</div></body></html>`;
}

function index(screens) {
  const blocks = [];
  for (const s of screens) for (const m of modes) {
    blocks.push(`<div class="frame"><h2>${s.name} <span>${s.id} · ${m}</span></h2>` +
      `<iframe src="${s.id}.${m}.html" width="430" height="932" style="border:0;border-radius:44px"></iframe></div>`);
  }
  return `<!doctype html><html lang="zh"><head><meta charset="utf-8"><title>DAYLIGHT · DesignLab</title><style>` +
    `body{background:#DAD6CE;font-family:-apple-system,"Segoe UI",sans-serif;margin:0;padding:28px}` +
    `.grid{display:flex;flex-wrap:wrap;gap:30px}.frame h2{font-size:12px;font-weight:600;color:#3B352C;margin:0 0 8px;letter-spacing:.4px}` +
    `.frame h2 span{color:#8A8378;font-weight:400}</style></head><body><div class="grid">${blocks.join('')}</div></body></html>`;
}

const htmls = [];
for (const s of targets) for (const m of modes) {
  const f = path.join(OUT, `${s.id}.${m}.html`);
  fs.writeFileSync(f, page(s, m), 'utf8');
  htmls.push({ file: f, shot: path.join(SHOTS, `${s.id}.${m}.png`) });
}
fs.writeFileSync(path.join(OUT, 'index.html'), index(targets), 'utf8');

if (htmlOnly) {
  console.log(`DesignLab: ${htmls.length} 个页面已生成（--html-only，跳过截图）`);
  process.exit(0);
}
let ok = 0;
for (const h of htmls) {
  try {
    execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2',
      `--window-size=${PHONE_W},932`, `--screenshot=${h.shot}`, 'file:///' + h.file.replace(/\\/g, '/')],
      { stdio: 'ignore', timeout: 40000 });
    ok++;
  } catch (e) {
    console.log('  截图失败: ' + path.basename(h.file));
  }
}
console.log(`DesignLab: ${ok}/${htmls.length} 屏已渲染并截图`);
console.log('  预览台: DesignLab/out/index.html');
console.log('  截图:   DesignLab/shots/');
