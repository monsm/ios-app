#!/usr/bin/env node
// run.js —— 渲染 + 截图。用 Edge headless 把每个镜像屏拍成 PNG。
//
// 用法：node DesignLab/run.js          渲染全部屏（浅色 + 深色）
//       node DesignLab/run.js door     只渲染 id 含 door 的屏
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const lab = require('./lab.js');
const { SCREENS } = require('./screens.js');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'DesignLab', 'out');
const SHOTS = path.join(ROOT, 'DesignLab', 'shots');
for (const d of [OUT, SHOTS]) if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true });

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const GLYPH = ['&#9635;', '&#9919;', '&#9636;', '&#9787;', '&#9881;'];
const TABS = ['门', '钥匙', '台账', '家', '设置'];

function page(screen, mode) {
  const tabbar = '<nav class="tabbar">' + TABS.map((t, i) =>
    '<div class="t ' + (i === screen.tab ? 'on' : '') + '"><b>' + GLYPH[i] + '</b>' + t + '</div>').join('') + '</nav>';
  return '<!doctype html><html lang="zh"><head><meta charset="utf-8"><title>' + screen.name + '</title>' +
    '<style>:root{' + lab.rootVars(mode) + '}' + lab.cssBody + '</style></head><body>' +
    '<div class="phone" data-mode="' + mode + '">' +
    '<div class="statusbar"><span>9:41</span><span>&#9679;&#9679;&#9679; &#9650;</span></div>' +
    '<div class="scroll">' +
    '<div class="navbar">' + screen.nav + '<span class="tr">' + (screen.trailing || '&#43;') + '</span></div>' +
    '<div style="height:8px"></div>' +
    screen.body +
    '<div class="foot">' + screen.id + ' · ' + mode + '</div>' +
    '</div>' + tabbar + '</div></body></html>';
}

function index(screens, modes) {
  const blocks = [];
  for (const s of screens) for (const m of modes) {
    blocks.push('<div class="frame"><h2>' + s.name + ' <span>' + s.id + ' · ' + m + '</span></h2>' +
      '<iframe src="' + s.id + '.' + m + '.html" width="430" height="932" style="border:0;border-radius:44px"></iframe></div>');
  }
  return '<!doctype html><html lang="zh"><head><meta charset="utf-8"><title>DesignLab</title><style>' + lab.cssBody +
    '.wrap{padding:24px}.grid{display:flex;flex-wrap:wrap;gap:28px}</style></head><body><div class="wrap"><div class="grid">' +
    blocks.join('') + '</div></div></body></html>';
}

const args = process.argv.slice(2);
const htmlOnly = args.includes('--html-only');
const filter = args.find((a) => !a.startsWith('--'));
const targets = filter ? SCREENS.filter((s) => s.id.includes(filter)) : SCREENS;
const modes = ['light', 'dark'];

const htmls = [];
for (const s of targets) for (const m of modes) {
  const f = path.join(OUT, s.id + '.' + m + '.html');
  fs.writeFileSync(f, page(s, m), 'utf8');
  htmls.push({ file: f, shot: path.join(SHOTS, s.id + '.' + m + '.png') });
}
fs.writeFileSync(path.join(OUT, 'index.html'), index(targets, modes), 'utf8');

let ok = 0;
if (htmlOnly) {
  // CI 上没有 Edge：只生成 HTML，不截图。截图是本地验收用的。
  console.log('DesignLab: ' + htmls.length + ' 个页面已生成（--html-only，跳过截图）');
  process.exit(0);
}
for (const h of htmls) {
  try {
    execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars',
      '--window-size=430,932', '--screenshot=' + h.shot, 'file:///' + h.file.replace(/\\/g, '/')],
      { stdio: 'ignore', timeout: 30000 });
    ok++;
  } catch (e) {
    console.log('  截图失败: ' + path.basename(h.file));
  }
}
console.log('DesignLab: ' + ok + '/' + htmls.length + ' 屏已渲染并截图');
console.log('  预览台: DesignLab/out/index.html');
console.log('  截图:   DesignLab/shots/');