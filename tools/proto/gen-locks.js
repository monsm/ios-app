'use strict';
// 20-locks —— 严格按 LocksPage.swift
// 源码结构：
//   空态：XEmptyState("还没有门锁", "配对之后…", "去配对")
//   列表 Section: header "N 把锁" / footer "顺序就是启动时默认选中的顺序。左滑可隐藏, 长按可拖动排序。"
//   已隐藏 Section（如果有）
//   lockRow: 名称 + 电量 12% + 当前标记
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs.writeFileSync(D+'20-locks.html', L.page('门锁管理', `
  <div class="h1" style="margin-top:8px">门锁管理</div>
  <div class="sub">1 把已配对 · 顺序即启动默认</div>

  <div class="card" style="margin-top:24px;padding:6px 0">
    <div style="padding:10px 20px 6px;font-size:12px;color:#6A6A6E">1 把锁</div>
    <a class="rw" href="21-lock-profile.html" style="min-height:72px">
      <img src="img/lock-45-128.png" alt="" style="width:52px;height:52px;object-fit:contain;flex:0 0 auto">
      <div class="tx">
        <div style="display:flex;align-items:center;gap:8px">
          <span class="tt">然然家</span>
          <span style="font-size:11px;color:#30D158;background:rgba(48,209,88,.14);
            padding:1px 6px;border-radius:999px">当前</span>
        </div>
        <div class="sb">JZ · 电量 47% · 信号 −76 dBm</div>
      </div>
      <div class="ch">${sv('chevron')}</div>
    </a>
    <div class="footer" style="padding:12px 20px 10px;margin:0">
      顺序就是启动时默认选中的顺序。左滑可隐藏，长按可拖动排序。
    </div>
  </div>

  <!-- 已隐藏（源码里有这一段，因为"把一把锁弄没了"是严重问题）-->
  <div class="card" style="padding:6px 0">
    <a class="rw" href="20-locks.html">
      <div class="ic" style="background:transparent;color:#6A6A6E">${sv('eye')}</div>
      <div class="tx"><div class="tt">已隐藏</div><div class="sb">0 把 · 左滑隐藏的锁会出现在这里</div></div>
      <div class="ch">${sv('chevron')}</div></a>
  </div>

  <button class="btn ghost" style="margin-top:16px">配对新门锁</button>
  <div style="text-align:center;font-size:12px;color:#6A6A6E;margin-top:12px">
    配对后这里会列出所有门锁
  </div>
`, 2, {nav:true, back:'03-devices', right:'排序'}));

console.log('✓ 20-locks 按 LocksPage.swift 重做');
