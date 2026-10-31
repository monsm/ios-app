#!/usr/bin/env node
// sheet.js —— 把所有镜像屏拼成一张总览图（用于一眼看完整套设计）。
'use strict';
const fs=require('fs'),path=require('path');
const { execFileSync } = require('child_process');
const { SCREENS } = require('./screens.js');

const ROOT=path.resolve(__dirname,'..');
const OUT=path.join(ROOT,'DesignLab','out');
const SHOTS=path.join(ROOT,'DesignLab','shots');

const groups = [
  { title:'门 · 刻度盘四态 + 空态', ids:['door','door-busy','door-opened','door-failed','door-empty'] },
  { title:'钥匙 · 台账 / 空态 / 详情 / 工坊 / 月历', ids:['keys','keys-empty','keydetail','keycreate','keycalendar'] },
  { title:'台账 · 时间轴 / 空态 / 详情', ids:['records','records-empty','recorddetail'] },
  { title:'家 · 成员 / 详情 / 空态', ids:['household','memberdetail','household-empty'] },
  { title:'设置 · 分组读数 / 安全 / 外观 / 备份 / 硬件 / 关于', ids:['settings','security','appearance','backup','hardware','about'] },
  { title:'门 · 子页：配网 / 锁实况 / 校时 / 布防', ids:['addlock','addlock-chain','lockstatus','sync','defend'] },
];
const mode='light';
const cards=[];
for(const g of groups){
  const imgs=g.ids.filter(id=>fs.existsSync(path.join(SHOTS,id+'.'+mode+'.png')))
    .map(id=>'<figure><img src="'+path.join('..','shots',id+'.'+mode+'.png').replace(/\\/g,'/')+'"><figcaption>'+id+'</figcaption></figure>').join('');
  cards.push('<section><h2>'+g.title+'</h2><div class="row">'+imgs+'</div></section>');
}
const html='<!doctype html><html lang="zh"><head><meta charset="utf-8"><title>ios27 · 设计总览</title><style>'
 +'body{margin:0;background:#0d0f12;color:#e8eaee;font:13px/1.5 "Segoe UI","Microsoft YaHei",sans-serif;padding:32px}'
 +'h1{font-size:22px;font-weight:600;margin:0 0 4px}h1 span{color:#8b95a1;font-weight:400;font-size:14px}'
 +'h2{font-size:13px;font-weight:600;color:#9aa5b1;margin:28px 0 10px;letter-spacing:.4px}'
 +'.row{display:flex;gap:14px;flex-wrap:wrap}'
 +'figure{margin:0}img{width:212px;border-radius:20px;display:block;box-shadow:0 8px 24px rgba(0,0,0,.45)}'
 +'figcaption{font-size:10.5px;color:#69737f;margin-top:6px;text-align:center;font-family:ui-monospace,Consolas,monospace}'
 +'</style></head><body><h1>离线锁管家 · iOS 27 <span>设计总览 · 27 屏 · 浅色</span></h1>'+cards.join('')+'</body></html>';
fs.writeFileSync(path.join(OUT,'sheet.html'),html,'utf8');
const EDGE='C:\\\\Program Files (x86)\\\\Microsoft\\\\Edge\\\\Application\\\\msedge.exe';
execFileSync(EDGE,['--headless=new','--disable-gpu','--hide-scrollbars','--window-size=1420,3350','--screenshot='+path.join(SHOTS,'_sheet.png'),'file:///'+path.join(OUT,'sheet.html').replace(/\\/g,'/')],{stdio:'ignore',timeout:60000});
console.log('sheet: DesignLab/shots/_sheet.png');