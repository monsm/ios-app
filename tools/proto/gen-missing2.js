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

  <!-- 图5 MetricCard：电量（44px 大数字 + 环 + 三列）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">当前电量<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:#FFA31A">47<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:2px">%</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">电量偏低，建议尽快更换 —— 换完点下面的按钮记一次。</div>
      </div>
      <svg width="76" height="76" viewBox="0 0 76 76" style="flex:0 0 auto">
        <circle cx="38" cy="38" r="31" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="6"/>
        <circle cx="38" cy="38" r="31" fill="none" stroke="#FFA31A" stroke-width="6"
          stroke-linecap="round" stroke-dasharray="91.5 194.8" transform="rotate(-90 38 38)"/>
      </svg>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel">型号</div><div class="cvalue" style="font-size:14px">见锁信息名片</div></div>
      <div><div class="clabel">电池档案</div><div class="cvalue" style="font-size:14px">已记录</div></div>
    </div>
    <div class="footer">电量低于 20% 会开始提醒 —— 冬天气温低时建议留到 30% 以上再换。</div>
  </div>

  <!-- 图2 卡解剖：四步换电 -->
  <div class="card">
    <div class="cardlink">换电步骤<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:12px">
      <div style="display:flex;gap:13px">
          <span style="width:22px;height:22px;border-radius:50%;background:rgba(94,92,230,.20);
            color:#7B7BE8;display:inline-flex;align-items:center;justify-content:center;
            font-size:12px;font-weight:700;flex:0 0 auto">1</span>
          <div style="flex:1"><div style="font-size:15px;font-weight:600">拆下锁体面板</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">两颗螺丝，注意别掉地上</div></div>
        </div><div style="display:flex;gap:13px">
          <span style="width:22px;height:22px;border-radius:50%;background:rgba(94,92,230,.20);
            color:#7B7BE8;display:inline-flex;align-items:center;justify-content:center;
            font-size:12px;font-weight:700;flex:0 0 auto">2</span>
          <div style="flex:1"><div style="font-size:15px;font-weight:600">取出旧电池</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">记下型号</div></div>
        </div><div style="display:flex;gap:13px">
          <span style="width:22px;height:22px;border-radius:50%;background:rgba(94,92,230,.20);
            color:#7B7BE8;display:inline-flex;align-items:center;justify-content:center;
            font-size:12px;font-weight:700;flex:0 0 auto">3</span>
          <div style="flex:1"><div style="font-size:15px;font-weight:600">装上新电池</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">注意正负极</div></div>
        </div><div style="display:flex;gap:13px">
          <span style="width:22px;height:22px;border-radius:50%;background:rgba(94,92,230,.20);
            color:#7B7BE8;display:inline-flex;align-items:center;justify-content:center;
            font-size:12px;font-weight:700;flex:0 0 auto">4</span>
          <div style="flex:1"><div style="font-size:15px;font-weight:600">装回面板</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">确认能转开再关</div></div>
        </div>
    </div>
    <div class="sep"></div>
    <div class="footer">换好后点下面记一次，之后会按周期提醒 —— 记录只存本机。</div>
  </div>

  <button class="btn" style="margin-top:18px;background:#5E5CE6;color:#FFF;font-weight:600">我换好了</button>
`, 4, {nav:true, back:'60-care'}));

// ══ 86 锁体保养（CareChecklistView：五项清单）══
fs.writeFileSync(D+'86-checklist.html', L.page('锁体保养', `
  <div class="h1" style="margin-top:8px">锁体保养</div>
  <div class="sub">五项清单 · 还没保养过</div>

  <!-- 图4 三段分色环 + 图5 大数字：保养进度 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">保养进度<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:#FFF">0<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">/ 5 项</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">还没开始 —— 逐项打勾，做完点「完成保养」。</div>
      </div>
      <svg width="76" height="76" viewBox="0 0 76 76" style="flex:0 0 auto">
        <circle cx="38" cy="38" r="31" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="6"/>
        <circle cx="38" cy="38" r="31" fill="none" stroke="#5E5CE6" stroke-width="6"
          stroke-linecap="round" stroke-dasharray="4 194.8" transform="rotate(-90 38 38)"/>
        <text x="38" y="43" text-anchor="middle" font-size="15" font-weight="700" fill="#7B7BE8"
          font-family="system-ui">0/5</text>
      </svg>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel">保养周期</div><div class="cvalue">90 天</div></div>
      <div><div class="clabel">下次保养</div><div class="cvalue" style="color:#FFA31A">未记录</div></div>
    </div>
    <div class="footer">五项都过一遍大约 5 分钟 —— 主要是看顺滑、看锈蚀、清指纹头。</div>
  </div>

  <!-- 图2 卡解剖：五项清单（可勾选）-->
  <div class="card">
    <div class="cardlink">五项清单<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;flex-direction:column;gap:16px;margin-top:12px">
      <div style="display:flex;align-items:flex-start;gap:12px">
          <span style="width:22px;height:22px;border-radius:6px;flex:0 0 auto;margin-top:1px;
            background:rgba(255,255,255,.055);box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.14)"></span>
          <div style="flex:1"><div style="font-size:15px;font-weight:500">滑轨与把手顺滑</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">喷一点润滑剂，别用食用油</div></div>
        </div><div style="display:flex;align-items:flex-start;gap:12px">
          <span style="width:22px;height:22px;border-radius:6px;flex:0 0 auto;margin-top:1px;
            background:rgba(255,255,255,.055);box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.14)"></span>
          <div style="flex:1"><div style="font-size:15px;font-weight:500">锁舌伸缩顺畅</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">手动推拉几次感受阻力</div></div>
        </div><div style="display:flex;align-items:flex-start;gap:12px">
          <span style="width:22px;height:22px;border-radius:6px;flex:0 0 auto;margin-top:1px;
            background:rgba(255,255,255,.055);box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.14)"></span>
          <div style="flex:1"><div style="font-size:15px;font-weight:500">电池触点无锈蚀</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">发白或发绿就是锈了</div></div>
        </div><div style="display:flex;align-items:flex-start;gap:12px">
          <span style="width:22px;height:22px;border-radius:6px;flex:0 0 auto;margin-top:1px;
            background:rgba(255,255,255,.055);box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.14)"></span>
          <div style="flex:1"><div style="font-size:15px;font-weight:500">指纹头清洁</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">干布擦，别用酒精</div></div>
        </div><div style="display:flex;align-items:flex-start;gap:12px">
          <span style="width:22px;height:22px;border-radius:6px;flex:0 0 auto;margin-top:1px;
            background:rgba(255,255,255,.055);box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.14)"></span>
          <div style="flex:1"><div style="font-size:15px;font-weight:500">应急钥匙位置确认</div>
          <div style="font-size:12px;color:#8A8A90;margin-top:3px">确认钥匙还在老地方</div></div>
        </div>
    </div>
    <div class="sep"></div>
    <div class="footer">打勾只是本机记录 —— 门锁不知道你保养过。</div>
  </div>

  <button class="btn" style="margin-top:18px;background:#5E5CE6;color:#FFF;font-weight:600">完成保养</button>
`, 4, {nav:true, back:'60-care'}));

// ══ 87 认领钥匙（UnclaimedClaimView）══
fs.writeFileSync(D+'87-claim.html', L.page('认领钥匙', `
  <div class="h1" style="margin-top:8px">认领还没分配的钥匙</div>
  <div class="sub">未归属记录 · 4 条待认领</div>

  <!-- 图5 MetricCard：待认领（44px 大数字 + 橙环 + 三列）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">那天是谁在家<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:#FFA31A">4<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">条未归属</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">都集中在 10-21 那天 —— 认领之后记录就归到人名下。</div>
      </div>
      <svg width="76" height="76" viewBox="0 0 76 76" style="flex:0 0 auto">
        <circle cx="38" cy="38" r="31" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="6"/>
        <circle cx="38" cy="38" r="31" fill="none" stroke="#FFA31A" stroke-width="6"
          stroke-linecap="round" stroke-dasharray="194.8 194.8" transform="rotate(-90 38 38)"/>
      </svg>
    </div>
    <div class="sep"></div>
    <div style="display:flex;flex-direction:column;gap:12px">
      <div style="display:flex;align-items:center;gap:10px">
          <span style="width:7px;height:7px;border-radius:50%;background:#FFA31A;flex:0 0 auto"></span>
          <span style="font-size:13px;color:#8A8A90;font-variant-numeric:tabular-nums;flex:0 0 auto;width:88px">10-21 18:22</span>
          <span style="font-size:13px;color:#FFF;flex:1">指纹</span>
          <span style="font-size:12px;color:#FFA31A">未分配</span>
        </div><div style="display:flex;align-items:center;gap:10px">
          <span style="width:7px;height:7px;border-radius:50%;background:#FFA31A;flex:0 0 auto"></span>
          <span style="font-size:13px;color:#8A8A90;font-variant-numeric:tabular-nums;flex:0 0 auto;width:88px">10-21 07:12</span>
          <span style="font-size:13px;color:#FFF;flex:1">密码</span>
          <span style="font-size:12px;color:#FFA31A">未分配</span>
        </div><div style="display:flex;align-items:center;gap:10px">
          <span style="width:7px;height:7px;border-radius:50%;background:#FFA31A;flex:0 0 auto"></span>
          <span style="font-size:13px;color:#8A8A90;font-variant-numeric:tabular-nums;flex:0 0 auto;width:88px">10-20 21:40</span>
          <span style="font-size:13px;color:#FFF;flex:1">临时码</span>
          <span style="font-size:12px;color:#FFA31A">未分配</span>
        </div><div style="display:flex;align-items:center;gap:10px">
          <span style="width:7px;height:7px;border-radius:50%;background:#FFA31A;flex:0 0 auto"></span>
          <span style="font-size:13px;color:#8A8A90;font-variant-numeric:tabular-nums;flex:0 0 auto;width:88px">10-19 08:03</span>
          <span style="font-size:13px;color:#FFF;flex:1">指纹</span>
          <span style="font-size:12px;color:#FFA31A">未分配</span>
        </div>
    </div>
    <div class="footer">未归属的记录不占名额，也不会丢 —— 认领完这条就归到具体成员名下。</div>
  </div>

  <!-- 图2 卡解剖：认领给（单选行）-->
  <div class="card">
    <div class="cardlink">认领给<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;flex-direction:column;gap:2px;margin-top:8px">
      <div style="display:flex;align-items:center;gap:12px;padding:11px 0;
          border-bottom:.5px solid rgba(255,255,255,.07)">
          <span style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,.07);
            color:#FFF;display:inline-flex;align-items:center;justify-content:center;
            font-size:13px;font-weight:600;flex:0 0 auto">朕</span>
          <span style="font-size:15px;color:#FFF;flex:1">朕</span>
          <span style="font-size:13px;color:#8A8A90;margin-right:4px">4 份</span>
          <span style="width:20px;height:20px;border-radius:50%;flex:0 0 auto;
            background:transparent;box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.20)"></span>
        </div><div style="display:flex;align-items:center;gap:12px;padding:11px 0;
          border-bottom:.5px solid rgba(255,255,255,.07)">
          <span style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,.07);
            color:#FFF;display:inline-flex;align-items:center;justify-content:center;
            font-size:13px;font-weight:600;flex:0 0 auto">爱</span>
          <span style="font-size:15px;color:#FFF;flex:1">爱妃</span>
          <span style="font-size:13px;color:#8A8A90;margin-right:4px">2 份</span>
          <span style="width:20px;height:20px;border-radius:50%;flex:0 0 auto;
            background:transparent;box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.20)"></span>
        </div><div style="display:flex;align-items:center;gap:12px;padding:11px 0;
          border-bottom:.5px solid rgba(255,255,255,.07)">
          <span style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,.07);
            color:#FFF;display:inline-flex;align-items:center;justify-content:center;
            font-size:13px;font-weight:600;flex:0 0 auto">皇</span>
          <span style="font-size:15px;color:#FFF;flex:1">皇子</span>
          <span style="font-size:13px;color:#8A8A90;margin-right:4px">5 份</span>
          <span style="width:20px;height:20px;border-radius:50%;flex:0 0 auto;
            background:transparent;box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.20)"></span>
        </div><div style="display:flex;align-items:center;gap:12px;padding:11px 0;
          border-bottom:.5px solid rgba(255,255,255,.07)">
          <span style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,.07);
            color:#FFF;display:inline-flex;align-items:center;justify-content:center;
            font-size:13px;font-weight:600;flex:0 0 auto">父</span>
          <span style="font-size:15px;color:#FFF;flex:1">父上</span>
          <span style="font-size:13px;color:#8A8A90;margin-right:4px">2 份</span>
          <span style="width:20px;height:20px;border-radius:50%;flex:0 0 auto;
            background:transparent;box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.20)"></span>
        </div><div style="display:flex;align-items:center;gap:12px;padding:11px 0;
          ">
          <span style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,.07);
            color:#FFF;display:inline-flex;align-items:center;justify-content:center;
            font-size:13px;font-weight:600;flex:0 0 auto">母</span>
          <span style="font-size:15px;color:#FFF;flex:1">母上</span>
          <span style="font-size:13px;color:#8A8A90;margin-right:4px">2 份</span>
          <span style="width:20px;height:20px;border-radius:50%;flex:0 0 auto;
            background:transparent;box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.20)"></span>
        </div>
    </div>
    <div class="sep"></div>
    <div class="footer">选一个人，4 条记录一起归到他名下 —— 反悔可以再改。</div>
  </div>

  <button class="btn" style="margin-top:18px;background:#FFF;color:#0A0A0C;font-weight:700">认领 4 条</button>
`, 3, {nav:true, back:'30-members-list'}));

// ══ 88 退出处置（MemberExitWizard）══
fs.writeFileSync(D+'88-exit.html', L.page('退出处置', `
  <div class="h1" style="margin-top:8px">退出处置向导</div>
  <div class="sub">逐条处置：保留 / 移交 / 停用</div>

  <!-- 图5 MetricCard：待处置概览 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">待处置<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="display:flex;align-items:flex-start;gap:16px;margin-top:2px">
      <div style="flex:1;min-width:0">
        <div style="font-size:44px;font-weight:700;line-height:1;letter-spacing:-1.4px;
          font-variant-numeric:tabular-nums;color:#FFF">2<span style="font-size:14px;font-weight:500;color:#8A8A90;margin-left:4px">把钥匙</span></div>
        <div style="font-size:13px;color:#8A8A90;margin-top:9px;line-height:1.5">每把都要选一种处置方式，选完才能归档。</div>
      </div>
      <svg width="76" height="76" viewBox="0 0 76 76" style="flex:0 0 auto">
        <circle cx="38" cy="38" r="31" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="6"/>
        <circle cx="38" cy="38" r="31" fill="none" stroke="#FFA31A" stroke-width="6"
          stroke-linecap="round" stroke-dasharray="97.4 194.8" transform="rotate(-90 38 38)"/>
      </svg>
    </div>
    <div class="sep"></div>
    <div class="cols">
      <div><div class="clabel">保留</div><div class="cvalue">0</div></div>
      <div><div class="clabel">移交</div><div class="cvalue">0</div></div>
      <div><div class="clabel">停用</div><div class="cvalue">0</div></div>
    </div>
    <div class="footer">保留 = 留着继续用；移交 = 换个人；停用 = 进回收站，可以恢复。</div>
  </div>

  <!-- 图2 卡解剖：逐条处置（三色按钮）-->
  <div class="card">
    <div class="cardlink">逐条处置<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="padding:14px 0;border-bottom:.5px solid rgba(255,255,255,.07)">
        <div style="display:flex;align-items:center;gap:10px">
          <span style="font-size:15px;font-weight:600;color:#FFF;flex:1">指纹 10</span>
          <span style="font-size:12px;color:#FFA31A;font-weight:600">待选择</span>
        </div>
        <div style="font-size:12px;color:#8A8A90;margin-top:4px">2026-08-20</div>
        <div style="display:flex;gap:8px;margin-top:12px">
          <button style="flex:1;height:34px;border-radius:9px;border:0;font-size:13px;font-weight:600;
            background:rgba(47,214,92,.14);color:#2FD65C">保留原样</button>
          <button style="flex:1;height:34px;border-radius:9px;border:0;font-size:13px;font-weight:600;
            background:rgba(79,195,255,.14);color:#4FC3FF">移交他人</button>
          <button style="flex:1;height:34px;border-radius:9px;border:0;font-size:13px;font-weight:600;
            background:rgba(255,69,58,.14);color:#FF453A">停用</button>
        </div>
      </div><div style="padding:14px 0;">
        <div style="display:flex;align-items:center;gap:10px">
          <span style="font-size:15px;font-weight:600;color:#FFF;flex:1">密码-爱妃-长期</span>
          <span style="font-size:12px;color:#FFA31A;font-weight:600">待选择</span>
        </div>
        <div style="font-size:12px;color:#8A8A90;margin-top:4px">2026-03-12</div>
        <div style="display:flex;gap:8px;margin-top:12px">
          <button style="flex:1;height:34px;border-radius:9px;border:0;font-size:13px;font-weight:600;
            background:rgba(47,214,92,.14);color:#2FD65C">保留原样</button>
          <button style="flex:1;height:34px;border-radius:9px;border:0;font-size:13px;font-weight:600;
            background:rgba(79,195,255,.14);color:#4FC3FF">移交他人</button>
          <button style="flex:1;height:34px;border-radius:9px;border:0;font-size:13px;font-weight:600;
            background:rgba(255,69,58,.14);color:#FF453A">停用</button>
        </div>
      </div>
    <div class="sep"></div>
    <div class="footer">停用的钥匙会进回收站，30 天内可以恢复 —— 移交后归属就改成另一个人。</div>
  </div>

  <!-- 图2 红色警告卡：归档执行 -->
  <div class="card" style="border-radius:16px;background:linear-gradient(180deg,#2A1517,#1F1012);
    box-shadow:inset 0 0 0 .5px rgba(255,69,58,.22)">
    <div class="cardlink" style="color:#FF453A">归档<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div style="font-size:14px;line-height:1.65;color:#E8B0AE;margin-top:8px">
      已归档：历史记录保留，归档后这个人不再出现在成员列表，但开门记录仍然算他的。</div>
    <button class="btn" style="margin-top:14px;background:rgba(255,69,58,.16);color:#FF453A;font-weight:600">归档并执行</button>
  </div>
`, 3, {nav:true, back:'30-members-list'}));

// ══ 89 分享给安卓（ShareToAndroidView）══
fs.writeFileSync(D+'89-share-android.html', L.page('分享给安卓', `
  <div class="h1" style="margin-top:8px">分享给安卓</div>
  <div class="sub">这把锁的开锁二维码</div>

  <!-- 图6 hero：白底卡 + 真实二维码（图像即内容）-->
  <div class="card" style="margin-top:24px;background:#FFF;padding:28px 20px;border-radius:22px">
    <div style="text-align:center">
      <div style="width:180px;height:180px;margin:0 auto;
        box-shadow:0 4px 20px rgba(0,0,0,.10);border-radius:12px;overflow:hidden">
        <svg width="156" height="156" viewBox="0 0 156 156" shape-rendering="crispEdges" style="background:#FFF;border-radius:8px"><rect x="0" y="0" width="43.68" height="43.68" fill="#1C1C1E"/><rect x="6.24" y="6.24" width="31.200000000000003" height="31.200000000000003" fill="#FFF"/><rect x="12.48" y="12.48" width="18.72" height="18.72" fill="#1C1C1E"/><rect x="112.32000000000001" y="0" width="43.68" height="43.68" fill="#1C1C1E"/><rect x="118.56" y="6.24" width="31.200000000000003" height="31.200000000000003" fill="#FFF"/><rect x="124.80000000000001" y="12.48" width="18.72" height="18.72" fill="#1C1C1E"/><rect x="0" y="112.32000000000001" width="43.68" height="43.68" fill="#1C1C1E"/><rect x="6.24" y="118.56" width="31.200000000000003" height="31.200000000000003" fill="#FFF"/><rect x="12.48" y="124.80000000000001" width="18.72" height="18.72" fill="#1C1C1E"/><rect x="49.92" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="0" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="6.24" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="12.48" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="18.72" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="24.96" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="31.200000000000003" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="68.64" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="81.12" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="87.36" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="99.84" y="37.44" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="43.68" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="6.24" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="49.92" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="6.24" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="56.160000000000004" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="62.400000000000006" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="62.400000000000006" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="68.64" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="68.64" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="74.88" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="56.160000000000004" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="74.88" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="6.24" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="81.12" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="56.160000000000004" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="81.12" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="18.72" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="43.68" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="87.36" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="93.60000000000001" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="49.92" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="93.60000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="0" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="12.48" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="24.96" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="31.200000000000003" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="37.44" y="99.84" width="2.4960000000000004" height="2.4960000000000004" fill="#1C1C1E"/><rect x="56.160000000000004" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="99.84" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="106.08" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="112.32000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="118.56" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="124.80000000000001" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="131.04" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="68.64" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="93.60000000000001" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="149.76" y="137.28" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="56.160000000000004" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="62.400000000000006" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="74.88" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="87.36" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="99.84" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="124.80000000000001" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="143.52" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="49.92" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="81.12" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="106.08" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="112.32000000000001" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="118.56" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="131.04" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="137.28" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/><rect x="143.52" y="149.76" width="6.24" height="6.24" fill="#1C1C1E"/></svg>
      </div>
      <div style="font-size:16px;font-weight:700;color:#0A0A0C;margin-top:20px">然然家</div>
      <div style="font-size:12px;color:#6E6E73;margin-top:6px">安卓用相机扫这个码即可配对</div>
    </div>
  </div>

  <!-- 图2 卡解剖：二维码说明（三列 + footer）-->
  <div class="card" style="margin-top:16px">
    <div class="cardlink">关于这个码<span class="ch"><span class="svgi" data-i="chevron"></span></span></div>
    <div class="cols" style="margin-top:8px">
      <div><div class="clabel">有效期</div><div class="cvalue" style="color:#2FD65C">一次性</div></div>
      <div><div class="clabel">作用</div><div class="cvalue">导入钥匙</div></div>
    </div>
    <div class="sep"></div>
    <div style="font-size:14px;line-height:1.7;color:#8A8A90">
      二维码里是这把锁的配对信息，扫一次就失效，重新生成会作废旧码。</div>
    <div class="sep"></div>
    <div class="footer">扫完之后安卓那边会显示「已绑定」—— iOS 这边的钥匙不受影响，两个平台可以同时开锁。</div>
  </div>
`, 2, {nav:true, back:'03-devices'}));

console.log('✓ 补了 5 页：换电指引 / 锁体保养 / 认领钥匙 / 退出处置 / 分享给安卓');
