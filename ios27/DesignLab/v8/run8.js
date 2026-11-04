#!/usr/bin/env node
// run8.js —— V8 设计语言渲染器
//
// 用法：node DesignLab/v8/run8.js [target|components|all]
// 输出：
//   shots/target.png            三屏目标稿（门 / 凭证 / 记录）
//   shots/components-light.png  组件库状态矩阵（浅色）
//   shots/components-dark.png   组件库状态矩阵（深色）
//
// 说明：这些是**设计基准图**，不是 App 的运行时镜像。它们按 _plan/raw/E-ref-metrics.md
// 的实测坐标 1:1 摆放，用来做"实现后逐元素比对"的裁判。
// 与 DesignLab/run.js（V7 的 27 屏镜像）互不干扰。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const OUT = path.join(__dirname, 'shots');
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

function shot(html, out, w, h) {
  const src = path.join(__dirname, html);
  if (!fs.existsSync(src)) { console.log('  missing ' + html); return false; }
  try {
    execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars',
      '--window-size=' + w + ',' + h, '--screenshot=' + path.join(OUT, out),
      'file:///' + src.replace(/\\/g, '/')], { stdio: 'ignore', timeout: 30000 });
    console.log('  ' + out);
    return true;
  } catch (e) {
    console.log('  ' + out + ' 渲染失败（检查 Edge 路径）');
    return false;
  }
}

const which = process.argv[2] || 'all';
let ok = 0;
if (which === 'target' || which === 'all') ok += shot('target.html', 'target.png', 1800, 1250) ? 1 : 0;
if (which === 'components' || which === 'all') {
  ok += shot('components.html', 'components-light.png', 860, 1500) ? 1 : 0;
  ok += shot('components-dark.html', 'components-dark.png', 860, 1500) ? 1 : 0;
}
if (which === 'keys' || which === 'all') ok += shot('keys.html', 'keys.png', 1040, 1050) ? 1 : 0;
console.log('v8: ' + ok + ' 张已渲染 → DesignLab/v8/shots/');