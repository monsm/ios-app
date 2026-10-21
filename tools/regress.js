#!/usr/bin/env node
// tools/regress.js —— 回归检查：确认"已修复"的项现在仍然成立
//
// 为什么需要它：
//   会话里改了 20+ 项，后面的改动可能覆盖前面的修复。
//   例如改 HomeConsole 的失败态时，是否碰坏了它的重入闸门？
//   改 EventsPage 的空态时，是否碰坏了同步逻辑？
//   这些靠人回忆不可靠，靠 CI 也查不出来（CI 只保证能编译）。
//
// 做法：每条修复写成一个**可机械验证的断言**，跑一遍就知道有没有回退。
//
// ⚠ 判据必须**剔除注释**：第一版用 includes 直接搜，
//   结果把"注释里解释为什么不这么做"的那行当成了回退（DragGesture / refreshTick 各误报一次）。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
function allSwift() {
  const out = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (e.name[0] !== '.') walk(p); }
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  };
  walk(path.join(ROOT, 'App'));
  return out;
}

const FILES = allSwift();
const RAW = new Map(FILES.map(f => [path.basename(f), fs.readFileSync(f, 'utf8')]));
/** 剔除整行注释后的正文 */
const CODE = new Map(FILES.map((f, i) => {
  const base = path.basename(f);
  const body = RAW.get(base).split('\n').filter(l => !/^\s*\/\//.test(l)).join('\n');
  return [base, body];
}));

const inCode = (f, s) => (CODE.get(f) || '').includes(s);
const inRaw = (f, s) => (RAW.get(f) || '').includes(s);
const anyCode = s => FILES.some(f => (CODE.get(path.basename(f)) || '').includes(s));

const checks = [
  ['开锁改用 onLongPressGesture', () => inCode('HomeConsole.swift', 'onLongPressGesture(minimumDuration')],
  ['不再用 DragGesture 开锁', () => !inCode('HomeConsole.swift', 'DragGesture(minimumDistance')],
  ['开锁有重入闸门', () => inCode('HomeConsole.swift', 'guard !isUnlocking else { return }')],
  ['切后台会 abortCharge', () => inCode('HomeConsole.swift', 'private func abortCharge()')],
  ['成功反馈先于状态刷新', () => {
    const s = CODE.get('HomeConsole.swift') || '';
    const a = s.indexOf('XHaptics.success()');
    const b = s.indexOf('refreshStatusQuietly()');
    return a > 0 && b > 0 && a < b;
  }],
  ['主界面可下拉刷新', () => inCode('HomeConsole.swift', '.refreshable {')],
  ['主界面监听回前台', () => inCode('HomeConsole.swift', 'onChange(of: scenePhase)')],
  ['当日统计走缓存', () => inCode('HomeConsole.swift', 'private func recompute()')],
  ['今日成员用归因结果', () => inCode('HomeConsole.swift', 'todayMemberCounts()')],
  ['删除凭证两端一起撤', () => inCode('KeysPage.swift', 'CredentialOrg.batchDisable')],
  ['隐藏门锁可恢复', () => inCode('LocksPage.swift', '取消隐藏')],
  ['事件日志可同步', () => inCode('EventsPage.swift', 'app.lock.getLogs')],
  ['同步带步骤追踪', () => inCode('EventsPage.swift', 'syncDetail')],
  ['事件备注可写', () => inCode('EventsPage.swift', 'RecordOverlay.setNote')],
  ['筛选视图可存', () => inCode('EventsPage.swift', 'saveNamedView')],
  ['空态给同步按钮', () => inCode('EventsPage.swift', '从门锁同步日志')],
  ['应用锁页接线', () => inCode('SecurityPage.swift', 'AppLockSetupView()')],
  ['回收站页接线', () => inCode('SecurityCenterView.swift', 'CredentialBinView()')],
  ['外观路由指向外观页', () => inCode('ManagerFace.swift', 'AppearancePage()')],
  ['回收站有队列核对', () => inCode('CredentialBinView.swift', '等待门锁确认')],
  ['失败态带去处', () => inCode('HomeConsole.swift', 'struct UnlockFailure')],
  ['refreshTick 只在 LinkSenseKit（唯一合法处）', () =>
    !anyCode('refreshTick') || (inCode('LinkSenseKit.swift', 'refreshTick') &&
      !['KeysPage.swift','MembersPage.swift','GatewayPage.swift'].some(f => inCode(f, 'refreshTick')))],
  ['BackupView 死 busy 已删', () => !inCode('BackupView.swift', '@State private var busy')],
  ['ErrorText 已建', () => !!CODE.get('ErrorText.swift')],
  ['ErrorText 接入 >= 8 处', () => FILES.filter(f => (CODE.get(path.basename(f))||'').includes('ErrorText.human')).length >= 8],
  ['浅色三级文字已调深', () => inCode('Theme.swift', '0x666670')],
  ['分时柱对比度达标', () => inCode('HomeConsole.swift', 'textSub.opacity(0.6)')],
  ['空柱有可见基线', () => inCode('HomeConsole.swift', 'return XPalette.hairline')],
  ['录入成功环有降级', () => inCode('AddFingerPage.swift', 'reduceMotion ? .opacity')],
  ['外观页不是 StudioPage', () => !inCode('ManagerFace.swift', 'case .appearance:     StudioPage()')],
  ['配对中禁止下滑关闭', () => inCode('AddLockPage.swift', 'interactiveDismissDisabled(flow == .pairing || flow == .naming)')],
  ['关掉弹层也会回滚配对', () => /onDisappear \{[\s\S]{0,240}?rollback\(reason: ""\)/.test(CODE.get('AddLockPage.swift') || '')],
  ['写入中禁止下滑关闭（>=5 处）', () => {
    // ⚠ 按**出现次数**算，不是文件数：CredentialStudio / BackupStudio 各有两个视图，
    //   第一版按文件数比较，把 5 处误算成 3，导致这条断言自己误报。
    let n = 0;
    for (const f of FILES) {
      const s = CODE.get(path.basename(f)) || '';
      n += (s.match(/interactiveDismissDisabled\(busy\)/g) || []).length;
    }
    return n >= 5;
  }],
  ['可点行/按钮不低于 44pt', () => {
    // HIG accessibility.md: iOS 控件默认 44×44，最小 28×28。
    // 只查"按钮标签自己写死的高度"，装饰点与行内图标不算。
    let bad = 0;
    for (const f of FILES) {
      const lines = (RAW.get(path.basename(f)) || '').split('\n');
      lines.forEach((t, i) => {
        if (/^\s*\/\//.test(t)) return;
        const m = t.match(/\.frame\(height:\s*([0-9.]+)\)/);
        if (!m) return;
        const h = parseFloat(m[1]);
        if (h >= 44 || h < 30) return;
        const win = lines.slice(Math.max(0, i - 14), i + 3).join('\n');
        if (/Button\s*[\{\(]/.test(win)) bad++;
      });
    }
    return bad === 0;
  }],
  ['区分「蓝牙关着」与「没有权限」', () => {
    const a = CODE.get('LinkSenseKit.swift') || '';
    const r = CODE.get('LockKeeperApp.swift') || '';
    return a.includes('btDenied') && a.includes('var denied: Bool = false') && r.includes('BLEOffBanner(denied:');
  }],
  ['首启空态直达配对页（不经管理面板）', () => {
    const h = CODE.get('HomeConsole.swift') || '';
    return h.includes('showAddLock = true') && h.includes('.sheet(isPresented: $showAddLock)');
  }],
  ['二次开锁闸真的会弹验证', () => {
    const a = CODE.get('LockKeeperApp.swift') || '';
    const al = CODE.get('Alerts.swift') || '';
    return a.includes('onChange(of: app.showGate)') && al.includes('func promptPasscode') &&
           a.includes('func confirmGatePassed') && a.includes('DB.verifyPasscode(pw)');
  }],
  ['pendingSettingsFocus 有消费端', () => {
    const m = CODE.get('ManagerFace.swift') || '';
    return m.includes('consumePendingFocus') && m.includes('path = [.backup]');
  }],
  ['诊断页存在并被三处入口消费', () => {
    // 上一轮这条断言的写法是"不要承诺不存在的诊断页"（当时确实没有）。
    // 现在 DiagnosticsPage 补上了，断言反过来：必须存在、必须接线、三处入口都要通。
    const d = CODE.get('DiagnosticsPage.swift') || '';
    const m = CODE.get('ManagerFace.swift') || '';
    const me = CODE.get('MePage.swift') || '';
    const app = CODE.get('LockKeeperApp.swift') || '';
    return !!d && m.includes('case .diagnostics:    DiagnosticsPage()') &&
           m.includes('case "diag": path = [.diagnostics]') &&
           me.includes('DiagnosticsPage()') &&
           app.includes('pendingSettingsFocus = "diag"');
  }],
  ['routeDestination 保留 @ViewBuilder', () => {
    // 多分支返回不同 View 类型的函数必须带 @ViewBuilder。
    // 本轮插新函数时把它挤到了别的函数头上，CI 报
    // "branches have mismatching types 'KeysPage' and 'MembersPage'"。
    const m = RAW.get('ManagerFace.swift') || '';
    return /@ViewBuilder\s*\n\s*private func routeDestination/.test(m);
  }],
];

let pass = 0;
const failed = [];
for (const [name, fn] of checks) {
  let ok = false;
  try { ok = fn(); } catch (e) { ok = false; }
  console.log('  ' + (ok ? '✓' : '✗') + ' ' + name);
  if (ok) pass++; else failed.push(name);
}
console.log('');
console.log('回归通过 ' + pass + ' / ' + checks.length);
if (failed.length) { console.log('⚠ 回退: ' + failed.join(' | ')); process.exit(1); }
console.log('✓ 全部已修复项仍然成立');

