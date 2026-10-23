'use strict';
// 11-fingerprint / 12-tempcode / 14-otp —— 严格按 CredentialStudio.swift 的三个 struct
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// ══ 11 指纹（FpStudio：录入向导 + 库存 + 命名）══
fs.writeFileSync(D+'11-fingerprint.html', L.page('指纹', `
  <div class="h1" style="margin-top:8px">指纹</div>
  <div class="sub">锁内 38 / 50 · 本机登记 3 枚</div>

  <!-- 图 2 卡解剖：指纹库存（细三环 + 彩色数据行）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">指纹库存<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:18px;margin-top:2px">
      <div style="flex:1">
        <div class="ctitle">还可录 12 枚</div>
        <div style="margin-top:14px">
          <div class="drow"><span class="dot" style="background:#0ADBD8"></span>
            <span class="dv">38<span class="du"> 锁内已用</span></span></div>
          <div class="drow"><span class="dot" style="background:#3CDE02"></span>
            <span class="dv">12<span class="du"> 锁内余量</span></span></div>
          <div class="drow"><span class="dot" style="background:#FF9F0A"></span>
            <span class="dv">3<span class="du"> 本机登记</span></span></div>
        </div>
      </div>
      ${L.tripleRing(100, .76, .24, .06, '38')}
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">上次录入</div><div class="cvalue">09-01</div></div>
      <div><div class="clabel" style="margin-top:0">建议补录</div><div class="cvalue">1 枚</div></div>
    </div>
    <div class="footer">这把锁只剩 12 枚可用指纹，建议补一枚备用。</div>
  </div>

  <!-- 录入向导（源码原文）-->
  <div class="card">
    <div class="cardlink">录入指纹<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:6px;justify-content:center;margin:18px 0 14px">
      ${[1,2,3,4,5,6,7,8].map(i => `<span style="width:26px;height:4px;border-radius:2px;
        background:${i<=3?'#0ADBD8':'rgba(255,255,255,.13)'}"></span>`).join('')}
    </div>
    <div style="text-align:center;font-size:15px;color:#FFF;line-height:1.62">
      请选好的手指按在门锁指纹头上，<br>抬起，重复 8 次
    </div>
    <div style="text-align:center;font-size:13px;color:#0ADBD8;margin-top:10px;
      font-variant-numeric:tabular-nums">录入中… 3 / 8</div>
    <div style="display:flex;gap:10px;margin-top:18px">
      <button class="btn sec" style="flex:1">重置进度</button>
      <button class="btn" style="flex:1;background:#0ADBD8;color:#062A2A">开始录入</button>
    </div>
  </div>

  <!-- 命名 -->
  <div class="card">
    <div class="cardlink">命名<span class="ch">${sv('chevron')}</span></div>
    <div class="clabel" style="margin-top:0">建议名（点按填入）</div>
    <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px">
      ${['妈妈·左手食指','妈妈·右手拇指','备用'].map(n=>
        `<span style="font-size:12px;padding:7px 13px;border-radius:999px;
          background:rgba(10,219,216,.13);color:#0ADBD8;font-weight:500">${n}</span>`).join('')}
    </div>
    <input class="inp" style="margin-top:12px" placeholder="自定义名称，如: 妈妈·左手食指">
    <div class="footer">仅本机留存。重录会替代原来那枚。</div>
  </div>

  <!-- 已登记 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">已登记<span class="ch">${sv('chevron')}</span></div>
    ${[['指纹 12','母上 · 09-01 录入'],['指纹 11','母上 · 09-01 录入'],['指纹 10','爱妃 · 08-20 录入']].map(([t,s2],i)=>
      `${i>0?'<div class="sep"></div>':''}
      <a class="rw" href="13-key-detail.html">
        <div class="ic" style="color:#8D8D93">${sv('fingerprint')}</div>
        <div class="tx"><div class="tt">${t}</div><div class="sb">${s2}</div></div>
        <span class="badge ok">有效</span>
        <div class="ch">${sv('chevron')}</div></a>`).join('')}
  </div>
`, 1, {nav:true, back:'02-keys', right:'编辑'}));

fs.writeFileSync(D+'12-tempcode.html', L.page('临时码', `
  <div class="h1" style="margin-top:8px">临时码</div>
  <div class="sub">6~8 位数字 · 会占用密码库存</div>

  <!-- 场景预设（源码：场景预设 (选中即套默认时长与备注)）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">场景预设<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:12px;color:#8D8D93;margin-top:6px">选中即套默认时长与备注</div>
    <div style="display:flex;gap:12px;overflow-x:auto;scrollbar-width:none;margin-top:16px;padding-bottom:2px">
      ${[['快递员','10 分钟','#FF694E','package'],['保洁','2 小时','#0ADBD8','broom'],
         ['访客','半天','#5E5CE6','person'],['维修','1 天','#FF9F0A','wrench']].map(([n,t,c,ic])=>
        `<div style="flex:0 0 auto;width:104px;background:linear-gradient(180deg,#202022 0%,#191919 100%);
          border-radius:20px;padding:18px 12px;text-align:center;
          box-shadow:inset 0 .5px 0 rgba(255,255,255,.055),inset 0 0 0 .5px rgba(255,255,255,.03)">
          <div style="width:52px;height:52px;border-radius:50%;margin:0 auto;
            background:${c}1F;display:flex;align-items:center;justify-content:center;color:${c}">${sv(ic,'24px')}</div>
          <div style="font-size:14px;font-weight:600;color:#FFF;margin-top:12px">${n}</div>
          <div style="font-size:11px;color:#8A8A90;margin-top:3px">${t}</div>
        </div>`).join('')}
    </div></div>
  </div>

  <!-- 码值（源码：码值 (6~8 位数字) / 输入码值, 或点「生成」/ 本地生成 6 位随机码）-->
  <div class="card">
    <div class="cardlink">码值<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:18px 0 6px">
      <div style="display:flex;gap:8px;justify-content:center">
        ${[1,2,3,4,5,6].map(i => `<div style="width:38px;height:50px;border-radius:10px;
          background:rgba(255,105,78,.10);border:1px solid rgba(255,105,78,.28);
          display:flex;align-items:center;justify-content:center;
          font-size:22px;font-weight:700;color:rgba(255,105,78,.45);
          font-variant-numeric:tabular-nums">·</div>`).join('')}
      </div>
      <div style="font-size:12px;color:#8D8D93;margin-top:14px">输入码值，或点「生成」</div>
    </div>
    <div style="display:flex;gap:10px;margin-top:6px">
      <button class="btn sec" style="flex:1">扫一扫</button>
      <button class="btn" style="flex:1;background:#FF694E;color:#1A0805">本地生成</button>
    </div>
    <div class="footer">输入 6~8 位数字。生成时会检查其它锁上是否有同值。</div>
  </div>

  <!-- 生效时段（源码：生效时段 / 今天内 / 生效）-->
  <div class="card">
    <div class="cardlink">生效时段<span class="ch">${sv('chevron')}</span></div>
    <div class="segctl2" style="margin-top:12px">
      <div class="o on">今天内</div><div class="o">2 小时</div><div class="o">自定义</div>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">开始</div><div class="cvalue">现在</div></div>
      <div><div class="clabel" style="margin-top:0">结束</div><div class="cvalue">今天 23:59</div></div>
    </div>
    <div class="footer">临时码也占同一个密码池子。库存满了要先删一条。</div>
  </div>

  <button class="btn" style="margin-top:4px;background:#FF694E;color:#1A0805">一次生成</button>
  <button class="btn ghost" style="margin-top:10px">批量生成</button>
`, 1, {nav:true, back:'02-keys'}));

// ══ 14 OTP 与口令（OtpStudio：锁端 ZOTP + 独立口令 + 静态备份码 + 导入）══
fs.writeFileSync(D+'14-otp.html', L.page('OTP 与口令', `
  <div class="h1" style="margin-top:8px">OTP 与口令</div>
  <div class="sub">锁端 ZOTP · 独立 TOTP · 静态备份码</div>

  <!-- 用于哪把锁 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">用于哪把锁<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <img src="img/lock-45-128.png" alt="" style="width:52px;height:52px;object-fit:contain">
      <div><div style="font-size:16px">然然家</div>
        <div style="font-size:12px;color:#8D8D93;margin-top:2px">JZ · 固件 1.0.2</div></div>
    </div>
  </div>

  <!-- 锁端 ZOTP（源码：锁端 ZOTP (30 分钟时窗)）-->
  <div class="card">
    <div class="cardlink">锁端 ZOTP<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:16px 0 8px">
      <div style="font-size:40px;font-weight:700;letter-spacing:8px;line-height:1;
        font-variant-numeric:tabular-nums;color:#0090FC">482 913</div>
      <div style="font-size:12px;color:#8D8D93;margin-top:12px">30 分钟时窗 · 轻点复制当前码</div>
    </div>
    <div style="height:4px;border-radius:2px;background:rgba(255,255,255,.10);overflow:hidden">
      <div style="height:4px;background:#0090FC;width:62%"></div>
    </div>
    <div class="footer">锁端 ZOTP 走分钟级时窗，和手机上的独立 TOTP 不是同一套。</div>
  </div>

  <!-- 独立口令（源码：独立口令 / 还没有独立口令）-->
  <div class="card">
    <div class="cardlink">独立口令<span class="ch">${sv('chevron')}</span></div>
    <div class="empty-state" style="padding:20px 0">
      <div class="es-icon">${sv('key','26px')}</div>
      <div class="es-title">还没有独立口令</div>
      <div class="es-desc">独立 TOTP 走标准 HMAC-SHA1/256/512<br>可以同时绑多个</div>
    </div>
  </div>

  <!-- 导入与添加（源码：导入 otpauth:// 文本 / 手工添加 / 收起手工添加）-->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">导入与添加<span class="ch">${sv('chevron')}</span></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('doc')}</div>
      <div class="tx"><div class="tt">导入 otpauth:// 文本</div><div class="sb">粘贴标准 otpauth URI</div></div>
      <div class="ch">${sv('chevron')}</div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('plus')}</div>
      <div class="tx"><div class="tt">手工添加</div><div class="sb">直接填 secret 与周期</div></div>
      <div class="ch">${sv('chevron')}</div>
    </div>
  </div>

  <!-- 静态备份码（源码：静态备份码 / 生成 8 位静态码）-->
  <div class="card">
    <div class="cardlink">静态备份码<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:14px 0 8px">
      <div style="font-size:32px;font-weight:700;letter-spacing:6px;
        font-variant-numeric:tabular-nums;color:#FFF">— — — — — — — —</div>
      <div style="font-size:12px;color:#8D8D93;margin-top:12px">还没生成</div>
    </div>
    <button class="btn sec" style="margin-top:6px">生成 8 位静态码</button>
    <div class="footer">静态码不过期，用一次就应该换。<strong style="color:#FF9F0A">仅本机留存</strong>。</div>
  </div>
`, 1, {nav:true, back:'02-keys'}));

console.log('✓ 11 指纹 / 12 临时码 / 14 OTP 按源码重做');
