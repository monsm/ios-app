'use strict';
// ══ 84 诊断与自检 ══ 参考图5 Activity Details 的 MetricCard 语言
// 图5 特征：① 44px 大数字主角 + 单位小字
//          ② 三列细线分隔（1px rgba .09），label 12px 在上 value 在下
//          ③ 卡头 = 可点链接（chevron 在右）
//          ④ 卡内多组：主数字区 → sep → 三列 → footer 全句
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 图5 MetricCard：大数字 + 环 + 三列
const metricCard = (link, big, unit, sub, ringPct, ringColor, cols, footer) => {
  const R = 34, C = 40, W = 6, circ = 2*Math.PI*R;
  const ring = ringPct === null ? '' : `<svg width="80" height="80" viewBox="0 0 80 80" style="flex:0 0 auto">
    <circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="${W}"/>
    <circle cx="${C}" cy="${C}" r="${R}" fill="none" stroke="${ringColor}" stroke-width="${W}"
      stroke-linecap="round" stroke-dasharray="${(circ*ringPct).toFixed(1)} ${circ.toFixed(1)}"
      transform="rotate(-90 ${C} ${C})"/>
  </svg>`;
  return `<div class="card">
    <div class="cardlink">${link}<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:4px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:${ringColor}">${big}<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">${unit}</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">${sub}</div>
      </div>
      ${ring}
    </div>
    <div class="sep"></div>
    <div class="cols">
      ${cols.map(([l,v,c]) => `<div><div class="clabel">${l}</div><div class="cvalue" style="color:${c||'#FFF'}">${v}</div></div>`).join('')}
    </div>
    <div class="footer">${footer}</div>
  </div>`;
};

fs2.writeFileSync(D+'84-diagnostics.html', L.page('诊断与自检', `
  <div class="h1" style="margin-top:8px">诊断与自检</div>
  <div class="sub">进入时算一次，动作后重算</div>

  <!-- 图5 MetricCard 主角：数据健康 0 问题 -->
  ${metricCard('数据健康', '0', '项问题', '数据键都能解析，也没有孤立文件或日志断档', 1, '#2FD65C',
    [['孤儿数据','0','#FFF'],['日志断档','0','#FFF']],
    '每次进入这一页都会重算一次：解析所有数据键、比对事件链、检查文件完整性。')}

  <!-- 图5 MetricCard：稳定性和启动耗时 -->
  ${metricCard('稳定性', '0.8', '秒', '启动耗时 · 内存占用 42 MB', 0.92, '#4FC3FF',
    [['异常退出','最近一次','#FFA31A'],['内存占用','42 MB','#FFF'],['本次启动','0.8 秒','#2FD65C']],
    '异常退出的记录会保留 —— 最近有一次，已经归档到崩溃日志。')}

  <!-- 图2 卡解剖：本机自检逐项 -->
  <div class="card">
    <div class="cardlink">本机自检<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:10px">
      <div style="display:flex;align-items:center;gap:10px">
        <span style="width:7px;height:7px;border-radius:50%;background:#FFA31A;flex:0 0 auto"></span>
        <span style="font-size:15px;color:#FFF;flex:1">稳定性</span>
        <span style="font-size:13px;color:#FFA31A;font-weight:600">最近有一次异常退出</span>
      </div>
      <div style="display:flex;align-items:center;gap:10px">
        <span style="width:7px;height:7px;border-radius:50%;background:#2FD65C;flex:0 0 auto"></span>
        <span style="font-size:15px;color:#FFF;flex:1">钥匙解析</span>
        <span style="font-size:13px;color:#2FD65C;font-weight:600">13 项全部可读</span>
      </div>
      <div style="display:flex;align-items:center;gap:10px">
        <span style="width:7px;height:7px;border-radius:50%;background:#FFA31A;flex:0 0 auto"></span>
        <span style="font-size:15px;color:#FFF;flex:1">备份完整性</span>
        <span style="font-size:13px;color:#FFA31A;font-weight:600">从未备份</span>
      </div>
    </div>
    <div class="sep"></div>
    <div class="footer">自检只读本机数据，不上传任何内容。异常退出与断链会在这里标出来。</div>
  </div>

  <!-- 图2 卡解剖：蓝牙 -->
  <div class="card">
    <div class="cardlink">蓝牙<span class="ch">${sv('chevron')}</span></div>
    <div class="cols" style="margin-top:8px">
      <div><div class="clabel">连接状态</div><div class="cvalue" style="color:#2FD65C">已连接</div></div>
      <div><div class="clabel">握手耗时</div><div class="cvalue">1,033 ms</div></div>
    </div>
    <div class="sep"></div>
    <div class="footer">握手耗时偏高（正常 &lt; 800 ms）—— 靠近门锁再试一次通常更快。</div>
  </div>

  <!-- 图2 卡解剖：数据保留 -->
  <div class="card">
    <div class="cardlink">数据保留<span class="ch">${sv('chevron')}</span></div>
    <div class="cols" style="margin-top:8px">
      <div><div class="clabel">事件记录</div><div class="cvalue">保留 20 条</div></div>
      <div><div class="clabel">审计日志</div><div class="cvalue">永久</div></div>
    </div>
  </div>

  <button class="btn" style="margin-top:18px;background:rgba(255,255,255,.14);color:#FFF;font-weight:600">复制全部诊断信息</button>
`, 4, {nav:true, back:'05-system'}));
