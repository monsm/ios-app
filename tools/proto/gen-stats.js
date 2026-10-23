'use strict';
// 52-stats —— 严格按 StatsPage.swift 重做
// 源码六张卡：
//   safetyCard   卡头「安全」→ 三个 MetricTile（告警率/有告警的天/总开门）
//   paretoCard   卡头「怎么开的门」→ 横条列表
//   daypartCard  「一天里什么时候最忙」→ 24h 柱
//   firstOpenCard「工作日出门」→ 首次开门时间
//   rhythmCard   「一天里的开门分布」→ 分布图
//   trendCard    「近 14 天」→ 折线
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 横条（paretoCard）
const hbar = (rows) => rows.map(([label, cnt, col, max]) => `
  <div style="display:flex;align-items:center;gap:10px;margin-top:10px">
    <span style="width:52px;font-size:11px;color:#FFF;flex:0 0 auto">${label}</span>
    <div style="flex:1;height:6px;border-radius:3px;background:#24242A">
      <div style="height:6px;border-radius:3px;background:${col};width:${Math.round(cnt/max*100)}%"></div>
    </div>
    <span style="width:28px;text-align:right;font-size:12px;color:#FFF;
      font-variant-numeric:tabular-nums;flex:0 0 auto">${cnt}</span>
  </div>`).join('');

// MetricTile
const tile = (v, label, tone, icon) => `
  <div style="flex:1;text-align:center">
    <div style="width:28px;height:28px;margin:0 auto;color:${tone};display:flex;
      align-items:center;justify-content:center">${sv(icon,'22px')}</div>
    <div style="font-size:20px;font-weight:700;color:${tone};margin-top:8px;
      font-variant-numeric:tabular-nums">${v}</div>
    <div style="font-size:11px;color:#8D8D93;margin-top:4px">${label}</div>
  </div>`;

// 24h 柱
const bars24 = (data, hi) => `<div class="mchart" style="height:52px;margin-top:12px">` +
  data.map(v => `<i${v/hi>0.6?' class="hi"':''} style="height:${Math.max(3,Math.round(v/hi*100))}%"></i>`).join('') +
  `</div><div class="maxis"><span>0</span><span>6</span><span>12</span><span>18</span><span>24</span></div>`;

fs.writeFileSync(D+'52-stats.html', L.page('统计', `
  <!-- 胶囊行：源码是 2 枚并排（总开门 / 告警），含图标 -->
  <div class="chiprow">
    <a class="chip" href="50-events.html" style="flex:1">
      <span style="color:#E8A05C;width:22px;height:22px">${sv('lockOpen')}</span>
      <div><div class="lbl">总开门</div><div class="val">127</div></div>
    </a>
    <a class="chip" href="44-audit.html" style="flex:1">
      <span style="color:#FF9F0A;width:22px;height:22px">${sv('warn')}</span>
      <div><div class="lbl">告警</div><div class="val">2</div></div>
    </a>
  </div>

  <div style="margin-top:26px">
    <div class="h1">统计</div>
    <div class="sub">近 30 天 · 1 把门锁 · 5 位成员</div>
  </div>

  <!-- ① 安全（源码 safetyCard：卡头是链接 + 三个 MetricTile）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">安全<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:12px;margin-top:14px">
      ${tile('1.6%','告警率','#30D158','warn')}
      ${tile('1','有告警的天','#FF9F0A','calendar')}
      ${tile('127','总开门','#FFF','lockOpen')}
    </div>
  </div>

  <!-- ② 怎么开的门（源码 paretoCard：卡头 + 横条）-->
  <div class="card">
    <div class="cardlink">怎么开的门<span class="ch">${sv('chevron')}</span></div>
    ${hbar([
      ['指纹', 52, '#3CDE02', 127],
      ['密码', 43, '#0090FC', 127],
      ['自动', 24, '#0ADBD8', 127],
      ['临时码', 8, '#FF694E', 127],
    ])}
    <div class="footer">指纹占比最高。自动开锁只在手机靠近时触发。</div>
  </div>

  <!-- ③ 一天里什么时候最忙（源码 daypartCard：24h 柱）-->
  <div class="card">
    <div class="ctitle" style="font-size:18px">一天里什么时候最忙</div>
    ${bars24([1,0,0,0,0,1,8,22,30,12,6,8,14,6,4,5,10,26,34,18,9,5,3,1], 34)}
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">高峰</div><div class="cvalue">18–19 点</div></div>
      <div><div class="clabel" style="margin-top:0">低谷</div><div class="cvalue">1–5 点</div></div>
    </div>
  </div>

  <!-- ④ 工作日出门（源码 firstOpenCard）-->
  <div class="card">
    <div class="ctitle" style="font-size:18px">工作日出门</div>
    <div style="display:flex;align-items:baseline;gap:8px;margin-top:14px">
      <span style="font-size:34px;font-weight:700;color:#0090FC;font-variant-numeric:tabular-nums">07:12</span>
      <span style="font-size:13px;color:#8D8D93">平均首次开门</span>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">最早</div><div class="cvalue">06:41</div></div>
      <div><div class="clabel" style="margin-top:0">最晚</div><div class="cvalue">09:28</div></div>
    </div>
  </div>

  <!-- ⑤ 一天里的开门分布（源码 rhythmCard）-->
  <div class="card">
    <div class="ctitle" style="font-size:18px">一天里的开门分布</div>
    <div style="margin-top:12px">
      ${hbar([
        ['早 6–9', 38, '#0090FC', 38],
        ['午 11–14', 22, '#0090FC', 38],
        ['晚 17–21', 47, '#0090FC', 47],
        ['夜 22–5', 20, '#0090FC', 47],
      ])}
    </div>
    <div class="footer">晚上出门最频繁。夜间的 20 次里有 4 次来自临时码。</div>
  </div>

  <!-- ⑥ 近 14 天（源码 trendCard：折线）-->
  <div class="card">
    <div class="ctitle" style="font-size:18px">近 14 天</div>
    <div style="position:relative;height:88px;margin-top:12px">
      <div class="dash"><i></i><i></i><i></i><i></i></div>
      <svg width="100%" height="88" viewBox="0 0 320 88" preserveAspectRatio="none" style="position:absolute;inset:0">
        <defs><linearGradient id="tr" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#00C6FF" stop-opacity=".40"/>
          <stop offset="1" stop-color="#0090FC" stop-opacity="0"/></linearGradient></defs>
        <path d="M0,64 L25,58 L49,44 L74,52 L98,30 L123,42 L147,36 L172,50 L196,46 L221,54 L245,42 L270,48 L294,40 L320,52 L320,88 L0,88 Z" fill="url(#tr)"/>
        <path d="M0,64 L25,58 L49,44 L74,52 L98,30 L123,42 L147,36 L172,50 L196,46 L221,54 L245,42 L270,48 L294,40 L320,52"
          fill="none" stroke="#00C6FF" stroke-width="2"/>
      </svg>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:11px;color:#6A6A6E;margin-top:8px">
      <span>10-10</span><span>10-14</span><span>10-18</span><span>10-23</span>
    </div>
  </div>
`, 0, {nav:true, back:'01-home'}));

console.log('✓ 52-stats 按 StatsPage.swift 六张卡重做');
