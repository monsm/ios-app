// tools/proto/interact.js —— 让原型真的能操作
//
// 目标里写的是「可交互」。只做 href 跳转不算 ——
// 用户点一个开关，它应该真的翻过去；点一个分段，选中态应该真的移过去。
'use strict';
(function () {
  // §7.19：App 内屏（非样机）用**真实系统时间**，只有样机内才是固定 9:41
  function setRealTime(){
    var els = document.querySelectorAll('[data-real-time]');
    if (!els.length) return;
    var d = new Date();
    var t = d.getHours() + ':' + String(d.getMinutes()).padStart(2,'0');
    els.forEach(function(el){ el.textContent = t; });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setRealTime);
  else setRealTime();
  // ── 开关：点击切换 on/off ──
  document.addEventListener('click', function (e) {
    var sw = e.target.closest('.sw');
    if (sw) {
      e.preventDefault();
      sw.classList.toggle('on');
      // 触觉反馈的视觉替代：轻微缩放
      sw.style.transform = 'scale(.94)';
      setTimeout(function(){ sw.style.transform = ''; }, 110);
      return;
    }
    // ── 分段控件：点击移动选中态 ──
    var seg = e.target.closest('.segctl .o, .segctl2 .o, .dtabs .t');
    if (seg) {
      e.preventDefault();
      var box = seg.parentElement;
      Array.prototype.forEach.call(box.children, function (c) { c.classList.remove('on'); });
      seg.classList.add('on');
      return;
    }
    // ── 圆形单选（周起始日 / 隐私仪表盘）──
    var radio = e.target.closest('[data-radio]');
    if (radio) {
      e.preventDefault();
      var grp = radio.parentElement.parentElement;
      Array.prototype.forEach.call(grp.querySelectorAll('[data-radio]'), function (r) {
        r.style.borderColor = 'rgba(255,255,255,.24)';
        r.style.background = 'transparent';
        r.textContent = '';
      });
      radio.style.borderColor = '#D98B45';
      radio.style.background = 'rgba(217,139,69,.20)';
      radio.textContent = '✓';
      return;
    }
    // ── 危险动作：二次确认 ──
    var danger = e.target.closest('.btn.dgr');
    if (danger) {
      e.preventDefault();
      if (danger.dataset.confirmed === '1') {
        danger.dataset.confirmed = '0';
        danger.textContent = danger.dataset.orig || '已执行';
        danger.style.opacity = '.55';
        return;
      }
      danger.dataset.orig = danger.textContent;
      danger.dataset.confirmed = '1';
      // 不换文字（原文可能很长，换了会截断）—— 改用边框闪烁 + 加副标题
      danger.style.background = 'rgba(255,59,48,.28)';
      danger.style.boxShadow = 'inset 0 0 0 2px rgba(255,59,48,.7)';
      var tip = document.createElement('div');
      tip.className = 'dtip';
      tip.textContent = '再点一次确认';
      tip.style.cssText = 'font-size:11px;color:#FF3B30;margin-top:6px;text-align:center';
      danger.parentElement.insertBefore(tip, danger.nextSibling);
      setTimeout(function () {
        if (danger.dataset.confirmed === '1') {
          danger.dataset.confirmed = '0';
          danger.style.background = '';
          danger.style.boxShadow = '';
          var t = danger.parentElement.querySelector('.dtip');
          if (t) t.remove();
        }
      }, 3000);
      return;
    }
  });

  // ── 长按（清空回收站）──
  document.addEventListener('pointerdown', function (e) {
    var hold = e.target.closest('[data-hold]');
    if (!hold) return;
    var t0 = Date.now();
    hold.dataset.orig = hold.textContent;
    hold.textContent = '按住…';
    var timer = setTimeout(function () {
      hold.textContent = '已释放';
      hold.style.color = '#FF3B30';
      clearInterval(hold._iv);
    }, 2000);
    hold._iv = setInterval(function () {
      if (Date.now() - t0 > 2000) return;
      hold.textContent = '按住 ' + ((2000 - (Date.now() - t0)) / 1000).toFixed(1) + 's';
    }, 100);
    hold._timer = timer;
  });
  document.addEventListener('pointerup', function (e) {
    var hold = e.target.closest('[data-hold]');
    if (!hold) return;
    clearTimeout(hold._timer); clearInterval(hold._iv);
    if (hold.textContent.indexOf('已') !== 0) hold.textContent = hold.dataset.orig || '按住';
  });

  // ── 输入框：显示已输入长度（口令类）──
  document.addEventListener('input', function (e) {
    var inp = e.target.closest('.inp');
    if (!inp || !inp.dataset.count) return;
    var hint = inp.parentElement.querySelector('.inhint');
    if (!hint) {
      hint = document.createElement('div');
      hint.className = 'inhint';
      hint.style.cssText = 'font-size:11px;color:var(--text-tert);margin-top:6px';
      inp.parentElement.insertBefore(hint, inp.nextSibling);
    }
    hint.textContent = inp.value.length + ' / ' + inp.dataset.count + ' 位';
  });
})();
