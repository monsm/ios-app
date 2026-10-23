'use strict';
// 补齐剩余 5 页
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 85 换电指引（BatterySwapGuideView）══
fs.writeFileSync(D+'85-battery.html', L.page('换电指引', `
  <div class="h1" style="margin-top:8px">换电指引</div>
  <div class="sub">上次换电：还没有换电记录</div>

  <div class="card" style="margin-top:24px;background:linear-gradient(160deg,#5E5CE6,#3C489C);padding:20px">
    <div style="text-align:center;padding:6px 0">
      <span style="color:#FFF;width:32px;height:32px;margin:0 auto;display:block">${sv('battery','32px')}</span>
      <div style="font-size:18px;font-weight:700;color:#FFF;margin-top:12px">电量偏低，建议尽快更换</div>
      <div style="font-size:13px;color:rgba(255,255,255,.78);margin-top:8px">当前 47% · 型号见锁信息名片-电池档案</div>
    </div>
  </div>

  <div class="card">
    <div class="cardlink">换电步骤<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:12px">
      ${[['1','拆下锁体面板','两颗螺丝，注意别掉地上'],
         ['2','取出旧电池','记下型号'],
         ['3','装上新电池','注意正负极'],
         ['4','装回面板','螺丝别拧太紧']].map(([n,t,d])=>
        `<div style="display:flex;gap:12px">
          <div style="width:24px;height:24px;border-radius:50%;background:rgba(94,92,230,.20);
            color:#8B88F0;display:flex;align-items:center;justify-content:center;
            font-size:12px;font-weight:600;flex:0 0 auto">${n}</div>
          <div style="flex:1"><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:2px">${d}</div></div>
        </div>`).join('')}
    </div>
    <div class="sep"></div>
    <div style="font-size:12px;color:#8D8D93;line-height:1.6">
      换好后点下面记录一次，之后会按周期提醒。
    </div>
    <button class="btn" style="margin-top:12px;background:#5E5CE6;color:#FFF">我换好了</button>
  </div>
`, 4, {nav:true, back:'60-care'}));

// ══ 86 锁体保养（CareChecklistView：五项清单）══
fs.writeFileSync(D+'86-checklist.html', L.page('锁体保养', `
  <div class="h1" style="margin-top:8px">锁体保养</div>
  <div class="sub">五项清单 · 还没保养过</div>

  <div class="card" style="margin-top:24px">
    <div class="cardlink">五项清单<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:12px">
      ${[['滑轨与把手顺滑',false],['锁舌伸缩顺畅',false],['电池触点无锈蚀',false],
         ['指纹头清洁',false],['应急钥匙位置确认',false]].map(([t,on])=>
        `<div style="display:flex;align-items:center;gap:12px">
          <div style="width:24px;height:24px;border-radius:7px;flex:0 0 auto;
            border:2px solid ${on?'#30D158':'rgba(255,255,255,.20)'};
            background:${on?'rgba(48,209,88,.16)':'transparent'};
            display:flex;align-items:center;justify-content:center;color:#30D158;font-size:13px">
            ${on?'✓':''}</div>
          <span style="flex:1;font-size:15px">${t}</span>
        </div>`).join('')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">保养周期</div><div class="cvalue">90 天</div></div>
      <div><div class="clabel" style="margin-top:0">下次</div><div class="cvalue">— 天后</div></div>
    </div>
    <button class="btn" style="margin-top:14px">完成保养</button>
  </div>
`, 4, {nav:true, back:'60-care'}));

// ══ 87 认领钥匙（UnclaimedClaimView）══
fs.writeFileSync(D+'87-claim.html', L.page('认领钥匙', `
  <div class="h1" style="margin-top:8px">认领还没分配的钥匙</div>
  <div class="sub">未归属记录 · 4 条待认领</div>

  <div class="card" style="margin-top:24px">
    <div class="cardlink">那天是谁在家<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:12px;color:#8D8D93;margin-top:6px">同一天有 4 条未归属</div>
    <div class="sep" style="margin-top:12px"></div>
    <div style="display:flex;flex-direction:column;gap:12px;margin-top:12px">
      ${[['10-21 18:22','指纹 未分配'],['10-21 07:12','密码 未分配'],
         ['10-20 21:40','临时码 未分配'],['10-19 08:03','指纹 未分配']].map(([t,w])=>
        `<div style="display:flex;justify-content:space-between;font-size:14px">
          <span>${t}</span><span style="color:#FF9F0A">${w}</span></div>`).join('')}
    </div>
  </div>

  <div class="card">
    <div class="cardlink">认领给<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:10px;margin-top:12px">
      ${[['朕','#7B7BE8','4'],['爱妃','#E8A05C','2'],['皇子','#30D158','5'],
         ['父上','#FF3B30','2'],['母上','#0ADBD8','2']].map(([n,c,k])=>
        `<div style="display:flex;align-items:center;gap:12px;padding:12px;
          background:rgba(255,255,255,.04);border-radius:12px">
          <div style="width:32px;height:32px;border-radius:50%;background:${c}22;color:${c};
            display:flex;align-items:center;justify-content:center;font-size:15px;
            font-weight:600;flex:0 0 auto">${n[0]}</div>
          <span style="flex:1;font-size:15px">${n}</span>
          <span style="font-size:12px;color:#6A6A6E">${k} 份</span>
          <div style="width:22px;height:22px;border-radius:50%;
            border:2px solid rgba(255,255,255,.20)"></div>
        </div>`).join('')}
    </div>
  </div>

  <button class="btn" style="margin-top:4px;background:rgba(255,255,255,.10);color:#5A5A5E">
    认领所选
  </button>
`, 3, {nav:true, back:'30-members-list'}));

// ══ 88 退出处置（MemberExitWizard）══
fs.writeFileSync(D+'88-exit.html', L.page('退出处置', `
  <div class="h1" style="margin-top:8px">退出处置向导</div>
  <div class="sub">逐条处置：保留 / 移交 / 停用</div>

  <div class="card" style="margin-top:24px">
    <div class="cardlink">逐条处置<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:12px;color:#8D8D93;margin-top:6px">先把每把钥匙选一种处置方式</div>
    <div class="sep" style="margin-top:12px"></div>
    ${[['指纹 10','2026-08-20'],['密码-爱妃-长期','2026-03-12']].map(([t,d],i)=>
      `<div style="padding:14px 0">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div><div style="font-size:15px">${t}</div>
          <div style="font-size:12px;color:#8D8D93;margin-top:2px">${d}</div></div>
          <span style="font-size:12px;color:#FF9F0A">待选择</span>
        </div>
        <div style="display:flex;gap:8px;margin-top:10px">
          <span style="flex:1;text-align:center;font-size:12px;padding:8px;border-radius:9px;
            background:rgba(255,255,255,.06);color:#8D8D93">保留原样</span>
          <span style="flex:1;text-align:center;font-size:12px;padding:8px;border-radius:9px;
            background:rgba(0,144,252,.14);color:#0090FC">移交他人</span>
          <span style="flex:1;text-align:center;font-size:12px;padding:8px;border-radius:9px;
            background:rgba(255,59,48,.14);color:#FF3B30">停用</span>
        </div>
      </div>${i===0?'<div class="sep"></div>':''}`).join('')}
    <div style="font-size:12px;color:#8D8D93;line-height:1.6;margin-top:8px">
      停用的钥匙会进回收站，可以恢复。移交后归属改成另一个人。
    </div>
  </div>

  <div class="card">
    <div class="cardlink">归档<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:13px;color:#8D8D93;margin-top:6px;line-height:1.6">
      已归档，历史记录保留。归档后这个人不再出现在成员列表，但开门记录仍然算他的。
    </div>
    <button class="btn dgr" style="margin-top:14px">归档并执行</button>
  </div>
`, 3, {nav:true, back:'30-members-list'}));

// ══ 89 分享给安卓（ShareToAndroidView）══
fs.writeFileSync(D+'89-share-android.html', L.page('分享给安卓', `
  <div class="h1" style="margin-top:8px">分享给安卓</div>
  <div class="sub">这把锁的开锁二维码</div>

  <div class="card" style="margin-top:24px;background:#FFF;padding:28px 20px">
    <div style="text-align:center">
      <div class="qr-real" style="width:180px;height:180px;margin:0 auto"><svg width="156" height="156" viewBox="0 0 156 156" shape-rendering="crispEdges" style="background:#FFF;border-radius:8px"><rect x="0" y="0" width="43.68" height="43.68" fill="#1C1C1E"/><rect x="6.24" y="6.24" width="31.200000000000003" height="31.200000000000003" fill="#FFF"/><rect x="12.48" y="12.48" width="18.72" height="18.72" fill="#1C1C1E"/><rect x="112.32000000000001" y="0" width="43.68" height="43.68" fill="#1C1C1E"/><rect x="118.56" y="6.24" width="31.200000000000003" height="31.200000000000003" fill="#FFF"/><rect x="124.80000000000001" y="12.48" width="18.72" height="18.72" fill="#1C1C1E"/><rect x="0" y="112.32000000000001" width="43.68" height="43.68" fill="#1C1C1E"/><rect x="6.24" y="118.56" width="31.200000000000003" height="31.200000000000003" fill="#FFF"/><rect x="12.48" y="124.80000000000001" width="18.72" height="18.72" fill="#1C1C1E"/><rect x="49.92" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="68.64" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="81.12" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="87.36" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="99.84" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="6.24" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="6.24" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="62.400000000000006" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="68.64" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="74.88" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="56.160000000000004" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="6.24" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="81.12" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="56.160000000000004" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="43.68" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="93.60000000000001" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="99.84" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="56.160000000000004" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/></svg></div>
      <div style="font-size:15px;font-weight:600;color:#1C1C1E;margin-top:18px">然然家</div>
      <div style="font-size:12px;color:#6E6E73;margin-top:6px">安卓用相机扫这个码即可配对</div>
    </div>
  </div>

  <div class="card">
    <div style="font-size:13px;color:#8D8D93;line-height:1.6">
      二维码里是这把锁的配对信息。扫一次就失效，重新生成会作废旧码。
    </div>
    <div class="sep"></div>
    <div class="footer" style="margin-top:0">正在生成… 生成后可保存到相册或直接分享。</div>
  </div>

  <button class="btn" style="margin-top:4px">分享二维码</button>
`, 2, {nav:true, back:'03-devices'}));

console.log('✓ 补了 5 页：换电指引 / 锁体保养 / 认领钥匙 / 退出处置 / 分享给安卓');
