'use strict';
const L = require('./lib.js');
const fs = require('fs');
const D = __dirname + '/';
const sv = (n, sz) => `<span class="svgi" data-i="${n}"${sz?` data-sz="${sz}"`:''}></span>`;

fs.writeFileSync(D+'48-export.html', L.page('导出与分享', `
  <div class="h1" style="margin-top:8px">导出与分享</div>
  <div class="sub">生成过程纯本地，不经过任何网络</div>

  <!-- scopeCard：范围 -->
  <div class="card" style="margin-top:24px">
    <div class="cardlink">范围<span class="ch">${sv('chevron')}</span></div>
    <div class="segctl2" style="margin-top:12px">
      <div class="o on">当月</div><div class="o">全部</div><div class="o">仅告警</div><div class="o">单日</div>
    </div>
    <div class="sep"></div>
    <div style="display:flex;justify-content:space-between">
      <span style="font-size:14px;color:#8D8D93">导出哪一天</span>
      <span style="font-size:14px;color:#E8A05C">最新一天 ›</span>
    </div>
    <div class="sep"></div>
    <div style="font-size:12px;color:#8D8D93;line-height:1.6">
      最新一天可直接用。导出与分享会让文件离开本机。
    </div>
  </div>

  <!-- fileActionsCard：文件类导出 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">文件<span class="ch">${sv('chevron')}</span></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('chart')}</div>
      <div class="tx"><div class="tt">CSV 标准导出</div><div class="sb">表格软件可直接打开</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('doc')}</div>
      <div class="tx"><div class="tt">原始 JSON + hex</div><div class="sb">含锁端原始报文，供开发核对</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('doc')}</div>
      <div class="tx"><div class="tt">月度 PDF 报告</div><div class="sb">打印月度记录</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('list')}</div>
      <div class="tx"><div class="tt">列选择</div><div class="sb">时间 / 类型 / 成员 / 告警 / 钥匙 / 原始 hex</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('eye')}</div>
      <div class="tx"><div class="tt">脱敏导出</div><div class="sb">关时 JSON 含原始 hex；开时 hex 列留空</div></div>
      <span class="sw"></span>
    </div>
  </div>

  <!-- imageActionsCard：图片类 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">图片<span class="ch">${sv('chevron')}</span></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('chart')}</div>
      <div class="tx"><div class="tt">单日长图</div><div class="sb">一天的全部记录拼成长图</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#FF9F0A">${sv('warn')}</div>
      <div class="tx"><div class="tt">告警分享卡</div><div class="sb">9:16 卡片，只含这一条告警</div></div>
    </div>
  </div>

  <!-- printActionsCard：打印 -->
  <div class="card" style="padding:6px 0">
    <div class="cardlink" style="padding:8px 20px 8px">打印<span class="ch">${sv('chevron')}</span></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('doc')}</div>
      <div class="tx"><div class="tt">告警事实单页</div><div class="sb">与物业沟通用的 PDF</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('export')}</div>
      <div class="tx"><div class="tt">用系统邮件发送</div><div class="sb">附件与 CSV 同源</div></div>
    </div>
    <div class="sep"></div>
    <div class="rw" style="cursor:default">
      <div class="ic" style="background:transparent;color:#8D8D93">${sv('export')}</div>
      <div class="tx"><div class="tt">邮件模板 .eml</div><div class="sb">复制到邮件客户端</div></div>
    </div>
  </div>

  <!-- doneSection：完成态 -->
  <div class="card">
    <div class="cardlink">文件位置<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;justify-content:space-between;margin-top:10px">
      <span style="font-size:14px;color:#8D8D93">最近导出</span>
      <span style="font-size:14px;color:#6A6A6E">还没有导出过</span>
    </div>
    <div class="footer">处理中… 完成后会显示在这里。</div>
  </div>

  <!-- verifySection：报告校验二维码 -->
  <div class="card">
    <div class="cardlink">报告校验二维码<span class="ch">${sv('chevron')}</span></div>
    <div style="display:flex;align-items:center;gap:16px;margin-top:12px">
      <div style="width:84px;height:84px;background:#1C1C1E;border-radius:12px;
        display:flex;align-items:center;justify-content:center;flex:0 0 auto">
        <span style="color:#6A6A6E;width:40px;height:40px">${sv('qrcode','40px')}</span>
      </div>
      <div style="flex:1;font-size:12px;color:#8D8D93;line-height:1.6">
        导出的报告带一枚校验二维码。<br>扫它可核对报告是否被改动。
      </div>
    </div>
  </div>

  <div class="card">
    <input class="inp" placeholder="加密口令（至少 6 位）" type="password">
    <button class="btn ghost" style="margin-top:12px">加密压缩导出</button>
  </div>
`, 4, {nav:true, back:'05-system'}));

console.log('✓ 48-export 按源码 6 区块重做');
