'use strict';
// ══ 80 三种状态 ══ 参考图2 卡解剖 + 图5 大数字
// 图2 特征：卡头（可点）→ 主体 → sep → footer 全句
// 图5 特征：空态/错误态也用大字号主角，不做小字说明
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}`:''}></span>`;

fs2.writeFileSync(D+'80-states.html', L.page('三种状态', `
  <div class="h1" style="margin-top:8px">三种状态</div>
  <div class="sub">骨架屏 · 空态 · 错误态</div>

  <!-- ① 图2 卡解剖：骨架屏（shimmer 占位，真实布局骨架）-->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">① 骨架屏<span class="ch">${sv('chevron')}</span></div>
    <div style="font-size:11px;color:#6A6A72;margin-top:2px">数据还在读，先把版式占住 —— 不闪白、不跳动</div>
    <div style="margin-top:16px">
      <!-- 骨架行：与真实卡同高度，灰色块 -->
      <div style="display:flex;align-items:center;gap:12px">
        <div style="width:44px;height:44px;border-radius:12px;background:rgba(255,255,255,.07);flex:0 0 auto"></div>
        <div style="flex:1">
          <div style="height:11px;border-radius:6px;background:rgba(255,255,255,.075);width:38%"></div>
          <div style="height:9px;border-radius:5px;background:rgba(255,255,255,.05);width:62%;margin-top:9px"></div>
        </div>
      </div>
      <div style="height:1px;background:rgba(255,255,255,.06);margin:14px 0"></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="width:44px;height:44px;border-radius:12px;background:rgba(255,255,255,.07);flex:0 0 auto"></div>
        <div style="flex:1">
          <div style="height:11px;border-radius:6px;background:rgba(255,255,255,.075);width:52%"></div>
          <div style="height:9px;border-radius:5px;background:rgba(255,255,255,.05);width:44%;margin-top:9px"></div>
        </div>
      </div>
      <div style="height:1px;background:rgba(255,255,255,.06);margin:14px 0"></div>
      <div style="display:flex;align-items:center;gap:12px">
        <div style="width:44px;height:44px;border-radius:12px;background:rgba(255,255,255,.07);flex:0 0 auto"></div>
        <div style="flex:1">
          <div style="height:11px;border-radius:6px;background:rgba(255,255,255,.075);width:29%"></div>
          <div style="height:9px;border-radius:5px;background:rgba(255,255,255,.05);width:56%;margin-top:9px"></div>
        </div>
      </div>
    </div>
    <div class="sep"></div>
    <div class="footer">骨架块用 rgba(255,255,255,.05–.075) —— 比正文暗一档，看起来是「还没到」而不是「坏了」。</div>
  </div>

  <!-- ② 图2 卡解剖：空态（居中图标 + 主文 + 副文）-->
  <div class="card">
    <div class="cardlink">② 空态<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:34px 0 30px">
      <div style="width:54px;height:54px;border-radius:50%;background:rgba(255,255,255,.055);
        color:#8A8A90;display:inline-flex;align-items:center;justify-content:center">${sv('clock','24px')}</div>
      <div style="font-size:17px;font-weight:600;color:#FFF;margin-top:16px">昨晚没有开门记录</div>
      <div style="font-size:13px;color:#8A8A90;margin-top:8px;line-height:1.55">门锁正常在线，只是没人经过</div>
    </div>
    <div class="sep"></div>
    <div class="footer">空态要说清楚「是真的没有」还是「读取失败」—— 这里属于前者，所以语气是平的。</div>
  </div>

  <!-- ③ 图2 卡解剖：错误态（警示图标 + 主文 + 副文 + 重试）-->
  <div class="card">
    <div class="cardlink">③ 错误态<span class="ch">${sv('chevron')}</span></div>
    <div style="text-align:center;padding:30px 0 22px">
      <div style="width:54px;height:54px;border-radius:50%;background:rgba(255,163,26,.14);
        color:#FFA31A;display:inline-flex;align-items:center;justify-content:center">${sv('warn','24px')}</div>
      <div style="font-size:17px;font-weight:600;color:#FFF;margin-top:16px">连接超时</div>
      <div style="font-size:13px;color:#8A8A90;margin-top:8px;line-height:1.55">门锁在休眠，唤醒后重试</div>
      <button class="btn" style="margin-top:18px;height:40px;width:auto;padding:0 26px;
        background:rgba(255,255,255,.12);color:#FFF;font-size:14px;font-weight:600;border-radius:999px">重试</button>
    </div>
    <div class="sep"></div>
    <div class="footer">错误态必须给出「下一步做什么」—— 这里写的是「唤醒后重试」，不是「出错了」。</div>
  </div>
`, 4, {nav:true, back:'05-system'}));
