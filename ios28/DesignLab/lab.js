#!/usr/bin/env node
// lab.js —— DAYLIGHT 设计语言的 CSS 基线。
//
// 这个文件只做两件事：把 tokens.css 的变量接进来，以及提供与 SwiftUI 组件一一对应的
// HTML/CSS 原语。**它不是产品代码**，是视觉验收台的渲染层：让 Windows 上也能看见设计。
'use strict';
const fs = require('fs');
const path = require('path');

const cssFile = path.join(__dirname, 'tokens.css');
const tokens = fs.existsSync(cssFile) ? fs.readFileSync(cssFile, 'utf8') : '';

const base = `
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:#DAD6CE}
body{font-family:-apple-system,"SF Pro Display","Segoe UI","Microsoft YaHei",sans-serif;-webkit-font-smoothing:antialiased}
.phone{position:relative;width:430px;height:932px;overflow:hidden;background:var(--canvas);color:var(--ink);border-radius:44px}
.scroll{position:absolute;left:0;right:0;top:56px;bottom:0;overflow:hidden;padding:0 22px 118px}
.statusbar{position:relative;z-index:8;display:flex;justify-content:space-between;align-items:center;padding:16px 30px 4px;font-size:13px;font-weight:600;letter-spacing:.2px}
.nav{display:flex;align-items:center;justify-content:space-between;padding:10px 0 6px;min-height:44px}
.nav .ttl{font-size:28px;font-weight:600;letter-spacing:-.6px}
.nav .tr{display:flex;gap:10px;align-items:center;font-size:17px;color:var(--ink2)}
.avatar{width:38px;height:38px;border-radius:50%;display:grid;place-items:center;font-size:14px;font-weight:600;color:var(--brass);background:var(--glass);backdrop-filter:blur(18px);border:.5px solid var(--glassEdge);box-shadow:inset 0 1px 0 var(--glassEdge),0 6px 16px -12px var(--shadow)}
.kicker{font-family:ui-monospace,"SF Mono",Consolas,monospace;font-size:10.5px;font-weight:600;letter-spacing:1.6px;text-transform:uppercase;color:var(--ink3)}
.serif{font-family:"Songti SC","Noto Serif SC",SimSun,serif;font-weight:400;letter-spacing:-1px;line-height:1.08}
.mono{font-family:ui-monospace,"SF Mono",Consolas,monospace;font-variant-numeric:tabular-nums}
.hair{height:.5px;background:var(--hair);width:100%}
.hairStrong{height:.5px;background:var(--hairStrong);width:100%}

/* ===== 环境光：整页的日光场 ===== */
.field{position:absolute;inset:0;z-index:0;overflow:hidden;pointer-events:none;
  background:
    radial-gradient(120% 70% at 78% -8%, var(--atmoWarm) 0%, transparent 56%),
    radial-gradient(90% 60% at 8% 2%, var(--atmoCool) 0%, transparent 52%),
    linear-gradient(180deg, var(--canvasTop) 0%, var(--canvas) 46%, var(--canvas) 100%);
  opacity:.95}
.field:after{content:"";position:absolute;inset:-20%;background:
    radial-gradient(40% 30% at 70% 18%, var(--atmoCool) 0%, transparent 70%),
    radial-gradient(50% 36% at 18% 40%, var(--atmoCool) 0%, transparent 70%);
  filter:blur(10px)}
.grain{position:absolute;inset:0;z-index:1;pointer-events:none;opacity:.35;mix-blend-mode:multiply;
  background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/><feColorMatrix type='saturate' values='0'/></filter><rect width='120' height='120' filter='url(%23n)' opacity='.055'/></svg>")}

/* ===== 日光窗 ===== */
.pane{position:relative;border-radius:var(--r-pane);overflow:hidden;isolation:isolate;
  box-shadow:0 30px 60px -30px var(--shadow), 0 2px 6px -2px var(--shadow), inset 0 1px 0 var(--glassEdge)}
.pane .sky{position:absolute;inset:0;z-index:0;
  background:
    radial-gradient(80% 90% at 82% 0%, var(--paneWarm) 0%, transparent 60%),
    radial-gradient(90% 110% at 8% 6%, var(--paneCool) 0%, transparent 55%),
    linear-gradient(165deg, var(--paneTop) 0%, var(--paneMid) 52%, var(--paneBot) 100%)}
.pane .blob{position:absolute;border-radius:50%;filter:blur(26px);z-index:1;opacity:.85}
.pane .blob.a{width:280px;height:280px;right:-70px;top:-90px;background:var(--paneWarm)}
.pane .blob.b{width:240px;height:240px;left:-80px;top:90px;background:var(--paneCool)}
.pane .streak{position:absolute;z-index:2;left:-30%;top:-40%;width:70%;height:180%;
  transform:rotate(18deg);background:linear-gradient(90deg,transparent,var(--paneStreak) 45%,transparent);filter:blur(6px);opacity:.45}
.pane .edge{position:absolute;inset:0;z-index:8;border-radius:inherit;box-shadow:inset 0 0 0 .5px var(--glassEdge), inset 0 -1px 0 var(--glassEdge)}
.pane .inner{position:relative;z-index:6;padding:24px 26px}

/* ===== 玻璃 ===== */
.glass{background:var(--glass);backdrop-filter:blur(26px) saturate(1.6);-webkit-backdrop-filter:blur(26px) saturate(1.6);
  border:.5px solid var(--glassEdge);box-shadow:0 12px 30px -16px var(--shadow), inset 0 1px 0 #FFFFFF55}
.glassStrong{background:var(--glassStrong);backdrop-filter:blur(30px) saturate(1.7);-webkit-backdrop-filter:blur(30px) saturate(1.7);
  border:.5px solid var(--glassEdge);box-shadow:0 20px 50px -22px var(--shadow), inset 0 1px 0 #FFFFFF66}
.sheet{background:linear-gradient(180deg,var(--glassStrong),var(--canvas));border-radius:var(--r-sheet) var(--r-sheet) 0 0;
  border:.5px solid var(--glassEdge);box-shadow:0 -30px 60px -30px var(--shadow)}

/* ===== 解锁镜头 ===== */
.lens{position:relative;width:116px;height:116px;border-radius:50%;display:block;
  background:radial-gradient(130% 130% at 32% 16%, var(--glassStrong) 0%, var(--glass) 46%, var(--glass) 100%);
  backdrop-filter:blur(18px) saturate(1.5);-webkit-backdrop-filter:blur(18px) saturate(1.5);
  box-shadow:0 18px 36px -16px var(--shadow), inset 0 1px 0 var(--glassEdge), inset 0 -2px 6px var(--shadow);
  border:.5px solid var(--glassEdge)}
.lens .ring{position:absolute;inset:5px;border-radius:50%;border:1.5px solid var(--brassBright);opacity:.28;
  -webkit-mask:conic-gradient(#000 var(--p,0%), transparent 0);mask:conic-gradient(#000 var(--p,0%), transparent 0)}
.lens .core{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:44px;height:44px;border-radius:50%;
  background:radial-gradient(120% 120% at 34% 26%, var(--brassBright) 0%, var(--brass) 62%, var(--brass) 100%);
  box-shadow:0 0 26px 10px var(--brassWash), inset 0 1px 0 #FFF6E6AA}
.lens .glyph{position:absolute;inset:0;display:grid;place-items:center;z-index:2;font-size:20px;color:#FFF9EE}
.lens .word{position:absolute;top:calc(100% + 8px);left:50%;transform:translateX(-50%);white-space:nowrap;font-size:10.5px;letter-spacing:1.6px;color:var(--ink3);text-transform:uppercase}
.lensbusy .ring{border-color:var(--ink);opacity:.7}
.lensfail .ring{border-color:var(--danger);opacity:.9}

/* ===== 读数 ===== */
.readings{display:flex;align-items:stretch}
.readings .r{flex:1;padding:0 0 0 0;display:flex;flex-direction:column;gap:3px}
.readings .r + .r{padding-left:18px;border-left:.5px solid var(--hair)}
.readings .v{font-size:19px;font-weight:600;letter-spacing:-.3px;font-variant-numeric:tabular-nums}
.readings .u{font-size:11px;color:var(--ink3);margin-left:2px;font-weight:400}
.readings .k{font-family:ui-monospace,Consolas,monospace;font-size:9.5px;letter-spacing:1.2px;color:var(--ink3);text-transform:uppercase}

/* ===== 列表 ===== */
.row{display:flex;align-items:center;gap:14px;padding:14px 0;min-height:60px}
.row + .row{border-top:.5px solid var(--hair)}
.row .main{flex:1;min-width:0}
.row .t{font-size:16px;font-weight:500;letter-spacing:-.2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row .s{font-size:12.5px;color:var(--ink3);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row .trail{font-size:12.5px;color:var(--ink3);text-align:right;font-variant-numeric:tabular-nums}
.chev{color:var(--ink4);font-size:13px}
.tile{width:40px;height:40px;border-radius:var(--r-tile);display:grid;place-items:center;font-size:17px;
  background:var(--brassWash);color:var(--brass);border:.5px solid var(--hair)}
.tile.cool{background:#FFFFFF77;color:var(--ink2)}
.tile.red{background:var(--dangerWash);color:var(--danger)}

/* ===== 章节 ===== */
.sect{display:flex;align-items:baseline;gap:10px;margin:30px 0 10px}
.sect .n{font-family:ui-monospace,Consolas,monospace;font-size:10px;color:var(--brass);letter-spacing:1px}
.sect .t{font-size:13px;font-weight:600;letter-spacing:.4px}
.sect .rule{flex:1;height:.5px;background:var(--hair);transform:translateY(-3px)}

/* ===== 芯片 ===== */
.chips{display:flex;gap:8px;flex-wrap:nowrap;overflow:hidden}
.chip{flex:0 0 auto;display:flex;align-items:center;gap:7px;padding:11px 15px;border-radius:999px;
  background:var(--glass);border:.5px solid var(--glassEdge);font-size:13.5px;font-weight:500;
  box-shadow:0 8px 18px -14px var(--shadow), inset 0 1px 0 #FFFFFF66}
.chip .g{font-size:14px;color:var(--brass)}
.chip.on{background:var(--brass);color:#fff;border-color:transparent}
.chip.on .g{color:#fff}

/* ===== 工具托盘 ===== */
.tray{display:flex;padding:5px;border-radius:22px}
.tray .it{flex:1;display:flex;flex-direction:column;align-items:center;gap:5px;padding:10px 0 9px;font-size:11px;letter-spacing:.2px;color:var(--ink2)}
.tray .it + .it{border-left:.5px solid var(--hair)}
.tray .it .g{font-size:18px;color:var(--brass)}

/* ===== 日光带（一天的活动） ===== */
.strip{position:relative;height:82px;margin-top:6px}
.strip .base{position:absolute;left:0;right:0;bottom:22px;height:.5px;background:var(--hairStrong)}
.strip .tick{position:absolute;bottom:22px;width:2.5px;border-radius:2px;background:var(--brass);opacity:.9}
.strip .tick.bad{background:var(--danger)}
.strip .lab{position:absolute;bottom:0;font-family:ui-monospace,Consolas,monospace;font-size:9.5px;color:var(--ink3);letter-spacing:.8px}

/* ===== 时间线 ===== */
.rail{position:relative;padding-left:24px}
.rail:before{content:"";position:absolute;left:5px;top:8px;bottom:8px;width:1px;background:var(--hairStrong)}
.ev{position:relative;padding:11px 0}
.ev:before{content:"";position:absolute;left:-23px;top:18px;width:9px;height:9px;border-radius:50%;
  background:var(--canvas);border:1.5px solid var(--brass)}
.ev.calm:before{border-color:var(--ink4)}
.ev.bad:before{border-color:var(--danger);background:var(--danger)}
.ev .t{font-size:14.5px;font-weight:500}
.ev .s{font-size:12px;color:var(--ink3);margin-top:2px}
.ev .time{position:absolute;right:0;top:12px;font-family:ui-monospace,Consolas,monospace;font-size:11px;color:var(--ink3)}
.daylabel{font-family:ui-monospace,Consolas,monospace;font-size:10.5px;letter-spacing:1.4px;color:var(--ink3);
  text-transform:uppercase;margin:18px 0 4px;padding-left:2px}

/* ===== 底部玻璃搁板 ===== */
.tabbar{position:absolute;left:20px;right:20px;bottom:20px;height:60px;border-radius:30px;z-index:20;
  display:flex;align-items:center;justify-content:space-around;padding:0 8px}
.tabbar .t{display:flex;flex-direction:column;align-items:center;gap:4px;font-size:10px;color:var(--ink3);
  width:84px;letter-spacing:.2px;opacity:.72}
.tabbar .t .g{font-size:19px;line-height:1}
.tabbar .t.on{color:var(--ink);opacity:1}
.tabbar .t.on .g{color:var(--brass)}
.tabbar .t.on:after{content:"";position:absolute;bottom:7px;width:3px;height:3px;border-radius:50%;background:var(--brass)}

/* ===== 段落文字 ===== */
.lede{font-size:14.5px;line-height:1.55;color:var(--ink2)}
.note{font-size:12px;line-height:1.55;color:var(--ink3)}
.foot{font-size:10px;color:var(--ink4);text-align:center;margin:20px 0 0;font-family:ui-monospace,Consolas,monospace}

/* ===== 按钮 ===== */
.btn{display:flex;align-items:center;justify-content:center;gap:8px;height:52px;border-radius:16px;
  font-size:16px;font-weight:600;letter-spacing:.2px;background:var(--brass);color:#fff;
  box-shadow:0 16px 30px -18px #6B4A20, inset 0 1px 0 #FFFFFF33}
.btn.ghost{background:var(--glass);color:var(--ink);border:.5px solid var(--glassEdge);box-shadow:0 10px 24px -18px var(--shadow)}
.btn.danger{background:var(--dangerWash);color:var(--danger);box-shadow:none}
.btn.sm{height:40px;font-size:14px;border-radius:12px;padding:0 16px}

/* ===== 分段 ===== */
.seg{display:flex;padding:4px;border-radius:14px;background:var(--glass);border:.5px solid var(--glassEdge)}
.seg .s{flex:1;text-align:center;padding:8px 0;font-size:13.5px;font-weight:500;color:var(--ink3);border-radius:10px}
.seg .s.on{background:var(--canvas);color:var(--ink);box-shadow:0 1px 4px #00000014}

/* ===== 输入 ===== */
.fieldInput{display:flex;align-items:center;gap:10px;height:48px;padding:0 16px;border-radius:14px;
  background:var(--glass);border:.5px solid var(--glassEdge)}
.fieldInput .ph{color:var(--ink3);font-size:15px}

/* ===== 数值大字 ===== */
.bignum{font-size:52px;font-weight:600;letter-spacing:-2px;font-variant-numeric:tabular-nums;line-height:1}
.unit{font-size:13px;color:var(--ink3);font-weight:400;letter-spacing:0}

/* ===== 徽标 ===== */
.badge{display:inline-flex;align-items:center;gap:4px;padding:3px 8px;border-radius:999px;font-size:10.5px;font-weight:600;
  background:var(--brassWash);color:var(--brass)}
.badge.red{background:var(--dangerWash);color:var(--danger)}
.badge.calm{background:var(--hair);color:var(--ink2)}
.badge.ok{background:#3F725018;color:var(--ok)}
`;

function rootVars(_mode) { return tokens; }

module.exports = { cssBody: base, rootVars, tokensRaw: tokens };
