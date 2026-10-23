'use strict';
const L = require('./lib.js');
const fs2 = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs2.writeFileSync(D+'02-scan.html', L.page('扫码添加门锁', `
  <!-- 图6 hero：蓝渐变 + 主体视觉 + 引导语（扫码绑定=本页灵魂） -->
  <div style="margin-top:16px;border-radius:24px;overflow:hidden;
    background:linear-gradient(180deg,#4B5AE8 0%,#3D49C8 42%,#232B7A 100%);
    padding:26px 22px 24px;text-align:center;
    box-shadow:0 18px 48px rgba(59,72,200,.34),inset 0 .5px 0 rgba(255,255,255,.22)">
    <div style="font-size:17px;font-weight:700;color:#FFF">对准 iOS 上的钥匙二维码</div>
    <div style="margin:22px auto 0;width:210px;height:210px;border-radius:20px;position:relative;
      background:rgba(0,0,0,.24);box-shadow:inset 0 0 0 1px rgba(255,255,255,.14)">
      <!-- 取景四角（图6 表盘堆叠的圆角语言） -->
      ${['0 0 0','100% 0 0','0 100% 0','0 0 100%'].map((_,i)=>{
        const pos=[['top:14px;left:14px;border-top:3px solid #FFF;border-left:3px solid #FFF'],
                   ['top:14px;right:14px;border-top:3px solid #FFF;border-right:3px solid #FFF'],
                   ['bottom:14px;left:14px;border-bottom:3px solid #FFF;border-left:3px solid #FFF'],
                   ['bottom:14px;right:14px;border-bottom:3px solid #FFF;border-right:3px solid #FFF']][i];
        return `<span style="position:absolute;width:26px;height:26px;${pos};border-radius:4px"></span>`;
      }).join('')}
      <div style="position:absolute;left:18px;right:18px;top:50%;height:2px;border-radius:1px;
        background:linear-gradient(90deg,transparent,#0A84FF 30%,#4FC3FF 70%,transparent);
        box-shadow:0 0 12px rgba(10,132,255,.8);top:calc(50% - 1px)"></div>
    </div>
    <div style="font-size:13px;color:rgba(255,255,255,.72);margin-top:18px;line-height:1.55">
      在 iOS 端「设置 → 门锁 → 分享给安卓」生成二维码<br>扫一次即可导入</div>
  </div>

  <!-- 图2 卡解剖：相机权限说明（源码真实文案） -->
  <div class="card" style="margin-top:22px">
    <div class="cardlink">相机权限<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:10px">
      <span style="color:#FFA31A;width:22px;height:22px">${sv('lock')}</span>
      <div style="flex:1"><div style="font-size:16px;font-weight:600">缺少权限: 相机</div>
      <div style="font-size:12px;color:#8A8A90;margin-top:2px">— 扫码与开锁会失败</div></div>
    </div>
    <div class="sep"></div>
    <div class="footer">请到系统设置里允许相机权限，返回后对准 iOS 端生成的二维码即可完成绑定。</div>
  </div>

  <!-- 源码规范：主按钮白底黑字胶囊 -->
  <button class="btn" style="margin-top:20px;background:#FFF;color:#0A0A0C;font-weight:700;height:54px;border-radius:999px;font-size:17px">去开启相机权限</button>
`, 0, {nav:true, back:'01-home', tabbar:false}));
