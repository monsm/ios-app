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
  ['诊断页用顶层类型名（DiagKit 不是类型）', () => {
    // CI 报过 "cannot find type 'DiagKit' in scope" —— 文件叫 DiagKit.swift，
    // 但里面全是顶层 enum（SelfCheck / DataHealth / BleTelemetry …），
    // 并没有一个叫 DiagKit 的命名空间类型。
    const d = RAW.get('DiagnosticsPage.swift') || '';
    return d.length > 0 && !d.includes('DiagKit.');
  }],
  ['体检不把合法空串算成残留', () => {
    // kf_theme / kf_accent / kf_week_start 的 "" 是合法值（跟随系统 / 默认色）。
    // 之前 integrity() 把所有空串都算"空键残留"，正常机器每次体检都报 3 条异常。
    const d = CODE.get('DiagKit.swift') || '';
    return d.includes('emptyMeansDefault') &&
           d.includes('!DataHealth.emptyMeansDefault.contains(k)');
  }],
  ['诊断页不重复列孤儿数据', () => {
    // integrity() 内部已调 scanOrphans() 并拼成一行，页面再列一次就是重复。
    const p = RAW.get('DiagnosticsPage.swift') || '';
    return !p.includes('scanOrphans()');
  }],
  ['异常退出提示会自动过期', () => {
    // kf_crash_arch_pending 原来只被设 true，全仓没有一处清回 false ——
    // 一次异常之后诊断页永远显示"上次是异常退出"，哪怕之后正常用了几个月。
    const d = CODE.get('DiagKit.swift') || '';
    return /set\("kf_crash_arch_pending", false\)/.test(d);
  }],
  ['蓝牙遥测有上限', () => {
    const d = CODE.get('DiagKit.swift') || '';
    return d.includes('list.count > 200') && d.includes('list.count > 300');
  }],
  ['诊断页可处置（不只读）', () => {
    // DiagKit 里的清理动作原来没有任何入口：archiveOldLogs 只在启动时跑，
    // 且要先开 kf_diag_autoarchive（默认关）—— 等于默认不存在。
    const p = RAW.get('DiagnosticsPage.swift') || '';
    return p.includes('archiveOldLogs()') && p.includes('PageTrace.clear()') &&
           p.includes('kf_diag_log_retention') && p.includes('kf_diag_ops_on');
  }],
  ['分组名不用行话', () => {
    // 「台账」「备份外观」是工程词，与页面标题（钥匙管理 / 数据与外观）不一致。
    const m = CODE.get('ManagerFace.swift') || '';
    return m.includes('case ledger = "钥匙"') && m.includes('case backupLook = "数据与外观"') &&
           !m.includes('"台账"') && !m.includes('"备份外观"');
  }],
  ['门厅间距有层级（不再一律 32pt）', () => {
    // 8 个区块等距 32pt = 没有层级：同一把锁的两件事和跨簇一样远。
    // 改为簇内 16、簇间 24。
    const h = CODE.get('HomeConsole.swift') || '';
    return !h.includes('VStack(spacing: XSpace.xxl) {') &&
           h.includes('VStack(spacing: XSpace.l) {');
  }],
  ['XRow 副标题不超过 16 字', () => {
    // XRow 的 subtitle 是 lineLimit(1)：超过单行容量就被截断，等于说明白写。
    // 26 个调用点里曾有 7 处超长（其中 3 处是我自己加的）。
    let bad = 0;
    for (const f of FILES) {
      const lines = (RAW.get(path.basename(f)) || '').split(/\r?\n/);
      lines.forEach((t, i) => {
        if (!/XRow\(/.test(t)) return;
        const win = lines.slice(i, i + 9).join('\n');
        const m = win.match(/subtitle:\s*"([^"]*)"/);
        if (m && [...m[1]].length > 16) bad++;
      });
    }
    return bad === 0;
  }],
  ['hero 卡比 group 卡更有呼吸感', () => {
    // 原先 hero 与 group 内边距都是 16，只差阴影和描边；
    // 而阴影在深色模式下几乎不可见，于是"主角卡"并不更像主角。
    // 另外 inset 零使用，已删（与早先删掉的 tile 同因）。
    const c = CODE.get('Components.swift') || '';
    return c.includes('case .hero:  return XSpace.card + 4') &&
           !/case inset/.test(c.split('enum XContainerKind')[1]?.split('}')[0] || 'case inset');
  }],
  ['按钮文字不小于 footnote', () => {
    // caption2 是 11pt，叠上 minimumScaleFactor 会到 8pt 左右；
    // 可点元素的文字太小，用户得凑近才看得清该点哪里。
    let bad = 0;
    for (const f of FILES) {
      const lines = (CODE.get(path.basename(f)) || '').split('\n');
      lines.forEach((t, i) => {
        if (!/\.xFont\(\.(?:system\()?\.?caption2/.test(t)) return;
        for (let k = i; k >= Math.max(0, i - 8); k--) {
          if (/Button\s*[\{\(]/.test(lines[k])) { bad++; break; }
          if (/^\s*(VStack|HStack|ZStack|var |func |struct )/.test(lines[k])) break;
        }
      });
    }
    return bad === 0;
  }],
  ['说明性长句不用小字号', () => {
    // 25 字以上的说明段落用 caption(12pt)/caption2(11pt) 排，读起来吃力。
    // 实测全仓曾有 95 处，已把 57 处 caption/caption2 提到 footnote。
    let bad = 0;
    for (const f of FILES) {
      const lines = (CODE.get(path.basename(f)) || '').split('\n');
      lines.forEach((t, i) => {
        if (!/\.xFont\(\.(?:system\()?\.?caption2?\b/.test(t)) return;
        for (let k = i - 1; k >= Math.max(0, i - 6); k--) {
          if (/\.xFont\(/.test(lines[k])) break;
          // 含 \(插值) 的模板串源码长、渲染短（如 "\\(n) 秒后刷新"），不算长句。
          const tm = lines[k].match(/Text\("([^"]{25,})"\)/);
          if (tm && !tm[1].includes('\\(')) { bad++; break; }
        }
      });
    }
    return bad === 0;
  }],
  ['入场曲线不是"为已删界面标定的时长"', () => {
    // doorReveal 原名"门后内容入场"，0.70s 是三棱柱时代整屏揭示的尺度。
    // 三棱柱删掉后它只剩小组件在用，收短到 0.45s。
    const t = CODE.get('Theme.swift') || '';
    return t.includes('duration: 0.45') && !t.includes('duration: 0.70');
  }],
  ['设计令牌没有零引用成员', () => {
    // XMetric.dial / tlGap / emptyMascot、XHit.dial / tlGap 都是三棱柱"锁面"时代的尺寸，
    // 界面删了但常量留着 —— 死常量比死函数更误导：它会让读 Theme.swift 的人
    // 以为那些设置还活着。
    const theme = RAW.get('Theme.swift') || '';
    const allCode = [...CODE.values()].join('\n');
    let dead = 0;
    for (const name of ['XIcon', 'XRadius', 'XOpacity', 'XHit', 'XSpace', 'XMotion', 'XMetric']) {
      const start = theme.indexOf('enum ' + name);
      if (start < 0) continue;
      const seg = theme.slice(start, start + 2600);
      for (const m of seg.matchAll(/static (?:var|func|let) (\w+)/g)) {
        const n = (allCode.match(new RegExp('\\b' + m[1] + '\\b', 'g')) || []).length;
        if (n <= 1) dead++;
      }
    }
    return dead === 0;
  }],
  ['同一颜色不表示两种含义', () => {
    // color.md: "Avoid using the same color to mean different things."
    // 原来临时码借用 warn（告警橙），而 EventsPage 里 care 和 temp 两类事件都返回 warn ——
    // 同一屏一个颜色两个含义。已新增 XPalette.kindTemp（金）并落地到工坊与事件页。
    const t = CODE.get('Theme.swift') || '';
    const s = CODE.get('StudioPage.swift') || '';
    const e = CODE.get('EventsPage.swift') || '';
    return t.includes('static var kindTemp') &&
           s.includes('case .temp: return XPalette.kindTemp') &&
           e.includes('case "temp": return XPalette.kindTemp');
  }],
  ['同一凭证类型跨页同色', () => {
    // 同一个概念在工坊 / 事件页 / 统计页必须是同一套颜色。
    // 曾经有三套：StatsPage 指纹用铜、密码用绿、临时码用橙。
    const pick = (file, pat) => {
      const s = CODE.get(file) || '';
      const out = {};
      for (const m of s.matchAll(pat)) out[m[1]] = m[2];
      return out;
    };
    const ev = pick('EventsPage.swift', /case "(fp|pwd|temp|key)":\s*return XPalette\.(\w+)/g);
    const st = pick('StatsPage.swift', /case "(fp|pwd|temp|key)":\s*return XPalette\.(\w+)/g);
    const keys = ['fp', 'pwd', 'temp'];
    return keys.every(k => ev[k] && st[k] && ev[k] === st[k]);
  }],
  ['回收站用垃圾桶图标', () => {
    // clock.arrow.circlepath 的语义是"时间同步 / 历史"，曾同时用于
    // "回收站是空的""立即清理到期条目" —— 语义冲突。
    // 注意：排队项"等待门锁确认"用时钟图标是**对的**（等待），所以这里只断言正向，
    // 不做"整个文件不许出现时钟"的否定 —— 第一版就是这么写宽的，自己误报了一次。
    const bin = CODE.get('CredentialBinView.swift') || '';
    const sec = CODE.get('SecurityCenterView.swift') || '';
    return bin.includes('systemName: "trash"') &&
           bin.includes('systemImage: "trash.slash"') &&
           sec.includes('Label("立即清理到期条目", systemImage: "trash.slash")');
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

