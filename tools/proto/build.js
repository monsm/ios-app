#!/usr/bin/env node
// tools/proto/build.js —— 一条命令重建全部原型
//
// **为什么要这个**：13 个生成器会写同一批页面（例如 41-applock 同时被
// gen-system1 与 gen-fill3 写过）。跑的顺序错了，旧版会覆盖新版，
// 而界面上看不出"这一页其实是上一版的" —— 我这轮就为此白查了两轮。
//
// 顺序规则：**越靠后的生成器，越了解那一页的最终形态。**
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');
const D = __dirname;
const ORDER = [
  'gen-archived.js',    // 33 归档页完整化
  'gen-home.js',        // 01 门厅（标杆页，最后跑覆盖手写）
  'gen-top2.js',       // 04-members
  'gen-top.js',         // 5 个一级页（手写页转生成器）
  'gen-keys.js',        // 钥匙域 4
  'gen-devices.js',     // 设备域 6
  'gen-members.js',     // 成员域 5 + 事件统计 3
  'gen-system1.js',     // 系统域前 7
  'gen-system2.js',     // 系统域后 4 + 维护 2
  'gen-templates.js',   // A/D/双列 三页
  'gen-themed.js',      // 44 图4 两层结构
  'gen-iconpicker.js',   // 70 真实图标画廊
  'gen-shell.js',       // 75 图5 展示壳
  'gen-templateD.js',   // 44/51 改 D
  'gen-metric.js',      // 20/11/25 改双列
  'gen-destroy.js',      // 45 销毁（8 区块）
  'gen-synctime.js',     // 25 同步时间（3 区块）
  'gen-export.js',       // 48 导出（源码 6 区块）
  'gen-fix4.js',         // 10/13/40/60 按源码区块
  'gen-lockprofile2.js', // 21 锁档案（6 区块）
  'gen-lockprofile.js',  // 21 真实锁渲染图
  'gen-gallery.js',     // 21/49/31 改 A
  'gen-fill.js',        // 12/30/33/47/60/43 补形态
  'gen-fill2.js',       // 13/22/23/24
  'gen-fill3.js',       // 34/46/40/41
  'gen-credential.js',   // 11/12/14 凭证三页（按源码）
  'gen-dongle-gw.js',    // 24/23 按源码
  'gen-locks.js',        // 20 门锁（按源码）
  'gen-stats.js',        // 52 统计（按源码六卡）
  'gen-peek.js',         // 42 防窥（按源码重做）
  'gen-members-list.js', // 30 成员列表（重做）
  'gen-hero3.js',       // 30/31/32 成员域主角
  'gen-hero2.js',       // 11/13/22 补主角
  'gen-hero.js',        // 52/12/25 补视觉主角
  'gen-fill4.js',       // 42/45/4a/61
];
for (const g of ORDER) {
  const p = path.join(D, g);
  if (!require('fs').existsSync(p)) { console.error('缺生成器 ' + g); continue; }
  execFileSync(process.execPath, [p], { stdio: 'inherit' });
}
execFileSync(process.execPath, [path.join(D,'statusbar.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(D,'deemoji.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(D,'skeleton.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(D,'converge-color.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(D,'inject-viz.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(D,'images.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(D,'normalize.js')], { stdio: 'inherit' });
// 结构校验：脚本改坏了立刻报错，不用等截图才发现
try {
  execFileSync(process.execPath, [path.join(D,'lint.js')], { stdio: 'inherit' });
} catch (e) {
  console.error('lint 失败 —— 先修结构再截图');
  process.exit(1);
}
console.log('--- 生成完毕，开始截图 ---');
execFileSync(process.execPath, [path.join(D,'shot.js')], { stdio: 'inherit' });
// 规格对照：和参考图的百分比逐项比
try {
  execFileSync(process.execPath, [path.join(D,'compare.js')], { stdio: 'inherit' });
} catch (e) { console.error('规格对照失败'); }
console.log('--- 生成总览 ---');
execFileSync(process.execPath, [path.join(D,'gen-overview.js')], { stdio: 'inherit' });
console.log('\n✓ 全部完成：' + path.join(D,'overview.html'));
