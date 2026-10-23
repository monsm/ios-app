'use strict';
// 21-lock-profile —— 严格按 LockProfilePage.swift 的 6 个区块
// 源码：plaque / identitySection / symbolSection / colorSection / moreSection / saveButton
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

// 七个符号（源码：家/楼栋/车库/办公/钥匙/布防/侧门）
const SYMBOLS = [['house','家'],['building','楼栋'],['car','车库'],['office','办公'],
                 ['key','钥匙'],['shield','布防'],['door','侧门']];

fs.writeFileSync(D+'21-lock-profile.html', L.page('锁档案', `
  <!-- ① 锁牌（源码 plaque：3D 锁图 150 + 辉光 + 名称 + 场所 + 三个状态读数）-->
  <div class="card" style="margin-top:8px;padding:28px 20px 20px;text-align:center">
    <div style="position:relative;display:inline-block">
      <div style="position:absolute;inset:-24px;background:radial-gradient(circle,rgba(123,123,232,.30) 0%,transparent 70%);
        border-radius:50%;filter:blur(14px)"></div>
      <img src="img/lock-hero@3x.png" alt=""
        style="width:168px;height:auto;position:relative;
        filter:drop-shadow(0 14px 28px rgba(0,0,0,.6));transform:translateY(-4px)">
    </div>
    <div style="font-size:30px;font-weight:600;color:#FFF;margin-top:10px;
      letter-spacing:-.4px;line-height:1.15">然然家</div>
    <div style="font-size:14px;color:#8D8D93;margin-top:4px">婆婆家·入户门</div>
    <div class="sep" style="margin-top:20px"></div>
    <div class="cols">
      <div><div class="clabel" style="margin-top:0">电量</div><div class="cvalue">47%</div></div>
      <div><div class="clabel" style="margin-top:0">锁态</div><div class="cvalue">已上锁</div></div>
      <div><div class="clabel" style="margin-top:0">固件</div><div class="cvalue">1.0.2</div></div>
    </div>
  </div>

  <!-- ② 身份（源码 identitySection：名字 / 场所 / 分组 / 备注）-->
  <div class="card">
    <div class="cardlink">身份<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;flex-direction:column;gap:14px;margin-top:12px">
      <div>
        <div class="clabel" style="margin-top:0">名字</div>
        <input class="inp" style="margin-top:6px" placeholder="给这把锁起个名字" value="然然家">
      </div>
      <div>
        <div class="clabel" style="margin-top:0">场所</div>
        <input class="inp" style="margin-top:6px" placeholder="如 婆婆家·入户门" value="婆婆家·入户门">
      </div>
      <div>
        <div class="clabel" style="margin-top:0">分组</div>
        <input class="inp" style="margin-top:6px" placeholder="如 住宅 / 办公">
      </div>
      <div>
        <div class="clabel" style="margin-top:0">备注</div>
        <input class="inp" style="margin-top:6px" placeholder="随手记">
      </div>
    </div>
  </div>

  <!-- ③ 符号（源码 symbolSection：七个符号可选）-->
  <div class="card">
    <div class="cardlink">符号<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:12px;overflow-x:auto;scrollbar-width:none;margin-top:14px;padding-bottom:2px">
      ${SYMBOLS.map(([ic,n],i)=>`
        <div style="flex:0 0 auto;text-align:center">
          <div style="width:56px;height:56px;border-radius:50%;
            background:${i===0?'rgba(123,123,232,.24)':'rgba(255,255,255,.06)'};
            border:2px solid ${i===0?'#7B7BE8':'transparent'};
            display:flex;align-items:center;justify-content:center;
            color:${i===0?'#FFF':'#8D8D93'}">${sv(ic,'24px')}</div>
          <div style="font-size:11px;color:${i===0?'#FFF':'#6A6A6E'};margin-top:8px">${n}</div>
        </div>`).join('')}
    </div>
    <div class="footer">默认符号用 3D 锁具渲染图。选了别的符号就换成那个符号。</div>
  </div>

  <!-- ④ 配色（源码 colorSection）-->
  <div class="card">
    <div class="cardlink">配色<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;gap:14px;margin-top:14px;flex-wrap:wrap">
      ${[['#7B7BE8','靛蓝'],['#0090FC','蓝'],['#30D158','绿'],['#FF9F0A','橙'],
         ['#FF694E','珊瑚'],['#0ADBD8','薄荷'],['#8D8D93','石墨']].map(([c,n],i)=>`
        <div style="width:calc(25% - 11px);text-align:center">
          <div style="width:44px;height:44px;border-radius:50%;margin:0 auto;background:${c};
            border:3px solid ${i===0?'#FFF':'transparent'}"></div>
          <div style="font-size:11px;color:${i===0?'#FFF':'#6A6A6E'};margin-top:7px">${n}</div>
        </div>`).join('')}
    </div>
    <div class="footer">配色只影响锁牌的辉光与描边，不改正文颜色。</div>
  </div>

  <!-- ⑤ 更多（源码 moreSection）-->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">更多<span class="ch">${sv('chevron')}</span></div>
    <a class="rw" href="22-firmware.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('arrowDown')}</div>
      <div class="tx"><div class="tt">固件升级</div><div class="sb">1.0.2 · 已是最新</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="25-synctime.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('clock')}</div>
      <div class="tx"><div class="tt">锁内时钟</div><div class="sb">偏差 −3 秒</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <a class="rw" href="85-battery.html">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('battery')}</div>
      <div class="tx"><div class="tt">电池档案</div><div class="sb">型号与换电记录</div></div>
      <div class="ch">${sv('chevron')}</div></a>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('eyeOff')}</div>
      <div class="tx"><div class="tt">在翻页里隐藏这把锁</div><div class="sb">隐藏后可在门锁管理的「已隐藏」找回</div></div>
      <span class="sw"></span>
    </div>
  </div>

  <!-- ⑥ 保存（源码 saveButton）-->
  <button class="btn" style="margin-top:4px">保存</button>
  <button class="btn dgr" style="margin-top:10px">解除绑定</button>
`, 2, {nav:true, back:'20-locks', right:'保存'}));

console.log('✓ 21-lock-profile 按源码 6 区块重做');
