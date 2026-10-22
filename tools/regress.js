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
// ── 关于「盲区」───────────────────────────────────────────────
// 每条断言都会在最后打印它**担保什么**与**不担保什么**。
// 理由：这个会话里我立的规则，自己违反过两次（第 93 轮自查发现），
// 而闸门对此一声不响。规则如果不说清自己的边界，
// 「回归全过」就会被误读成「这里没问题」。
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
  ['删除确认告知可找回', () => {
    // 删除凭证是可恢复的（进回收站 N 天），但确认框原来只讲"会删、会撤销"，
    // 没讲"可以找回" —— 用户在最有顾虑的那一刻不知道自己还有退路。
    // 反过来：真正不可恢复的（删本锁钥匙 / 删记录）不该假称能找回。
    const k = CODE.get('KeysPage.swift') || '';
    const d = CODE.get('DonglesPage.swift') || '';
    return k.includes('回收站 \\(CredentialOrg.reclaimDays())') &&
           !d.includes('留在回收站');
  }],
  ['用户可见文案不再出现「凭证」', () => {
    // 同一个核心名词两个叫法：页面标题是「钥匙管理」，里面按钮写「添加凭证」。
    // 第 30 轮只改了 17 处，实际有 125 处 —— 现在清零。
    let bad = 0;
    for (const f of FILES) {
      const body = CODE.get(path.basename(f)) || '';
      for (const m of body.matchAll(/"((?:[^"\\]|\\.)*)"/g)) {
        if (m[1].includes('凭证')) bad++;
      }
    }
    return bad === 0;
  }],
  ['失败提示要给出原因或下一步', () => {
    // "保存失败" 四个字，用户没法据此做任何事。
    // 逐字检查：含 失败/错误/无法 的 toast 里，必须有冒号/破折号/逗号带出的原因，
    // 或者"下一步"（可改用…）。纯粹的状态词不算。
    const allowed = ['不能为空', '不能为', '拒绝执行'];
    let bad = 0;
    for (const f of FILES) {
      const body = CODE.get(path.basename(f)) || '';
      for (const m of body.matchAll(/showToast\("((?:[^"\\]|\\.){2,60})"\)/g)) {
        const s = m[1];
        if (!/失败|错误|无法|不可/.test(s)) continue;
        // 半角逗号也要算：本仓文案里 , 与 ，混用（例如「没有 MAC, 无法配对」）。
        // 第一版只认全角，把三条本来合规的提示报成了问题。
        if (/[:：—,，]/.test(s)) continue;
        if (/或/.test(s)) continue;                    // "读取失败或格式不对" —— 或已给出原因
        if (/稍后|可改用|请|到「/.test(s)) continue;    // 已给出下一步
        if (allowed.some(a => s.includes(a))) continue;
        if (s.includes('失败记录')) continue;   // "已清除失败记录"是成功提示
        bad++;
      }
    }
    return bad === 0;
  }],
  ['异步列表页保留三态（骨架/空/内容）', () => {
    // 全仓只有三页异步加载列表：告警、事件、统计。
    // 它们必须同时有"加载中骨架"与"空态"，否则加载期间会显示一片空白
    // （或更糟：显示"还没有…"，那是一句不真实的话）。
    // 其余 8 个有空态的页面都读本地同步数据（DB.keychains / members / bin…），
    // 不存在加载窗口，因此不需要骨架 —— 这是有意的区分，不是遗漏。
    const need = ['AlarmsPage.swift', 'EventsPage.swift', 'StatsPage.swift'];
    return need.every(f => (CODE.get(f) || '').includes('XSkeleton'));
  }],
  ['长操作有可见的进行中指示', () => {
    // 菜单里的按钮点完菜单就关了，"同步中…"这句文案用户永远看不到。
    // 首启路径上的长等待各自都有反馈：
    //   配对 = 步骤脊梁 / 录指纹 = 进度环 / 开门 = 相位 / 固件 = 圆环+三段
    // 只有事件页同步原来是静默的，已补常驻指示。
    const e = CODE.get('EventsPage.swift') || '';
    return e.includes('正在从门锁同步') && e.includes('ProgressView().controlSize(.small)');
  }],
  ['忙碌标志用 defer 复位', () => {
    // 手工在每个出口写一遍 flag = false，经不起将来的一次提前 return ——
    // 漏一次，按钮就永久不可点，用户只能杀进程。
    // defer 让"离开作用域一定复位"成为结构保证。
    // 例外：ExportCenter 的状态在 Task + MainActor.run 里复位，
    // 且 self 已释放时标志无处可卡，属于合理写法。
    const allow = ['ExportCenter.swift'];
    let bad = 0;
    for (const f of FILES) {
      const base = path.basename(f);
      // 只查 UI 层：服务层的 scanning 由超时定时器与委托回调驱动
      // （BLEService.stopScanInternal 由 scanTimer 调），不是手动复位。
      if (!/(^|\/)UI\/[^/]+\.swift$/.test(f)) continue;
      if (allow.includes(base)) continue;
      const lines = (CODE.get(base) || '').split('\n');
      lines.forEach((t, i) => {
        const m = t.match(/^\s*(\w*(?:busy|syncing|running|loading|working|saving|exporting|scanning)\w*)\s*=\s*true/);
        if (!m) return;
        const win = lines.slice(i, i + 40).join('\n');
        if (!new RegExp('defer\\s*\\{[^}]*' + m[1] + '\\s*=\\s*false').test(win)) bad++;
      });
    }
    return bad === 0;
  }],
  ['新增凭证后提示去验证', () => {
    // 门锁 App 里"没试过的密码等于不存在的密码"。
    // 录指纹流程早就说了「请用新指纹开一次锁, 确认可用」，
    // 而加密码这条更常做的路径只报一句"添加成功"就关掉了。
    const k = CODE.get('AddKeyPage.swift') || '';
    const f = CODE.get('CredentialStudio.swift') || '';
    return k.includes('请用这串密码开一次锁，确认可用') &&
           k.includes('请用它在门锁上开一次，确认可用') &&
           f.includes('请用新指纹开一次锁');
  }],
  ['队列下发成功会告诉用户', () => {
    // 撤销链可能从早上排到晚上：下令 → 入队 → 等连上锁 → 真正下发。
    // 而"下发成功"这个信号（lastReceipt）原来写了没人读 —— 最长的一条链，
    // 最后一个环节是静默的。现在两处消费：回收站回执卡 + 主动播报。
    const ls = CODE.get('LinkSenseKit.swift') || '';
    const bin = CODE.get('CredentialBinView.swift') || '';
    return ls.includes('lastReceipt = done') &&
           ls.includes('self.app?.showToast') &&
           bin.includes('sense.lastReceipt');
  }],
  ['门厅成员卡可直达成员详情', () => {
    // 成员卡原来只展示：想看某人权限要 管理→成员→选人 三步。
    // 而卡上已经写着他的名字和今天的次数 —— 点它是最自然的意图。
    const h = CODE.get('HomeConsole.swift') || '';
    return h.includes('memberSheetID') && h.includes('MemberDetail360View(memberID: id)');
  }],
  ['分时图可点到对应小时的记录', () => {
    // 用户看到"14 点有 3 次"，自然会想知道是谁。24 根柱子各自做按钮远低于 44pt，
    // 所以整块图作触达面、按 x 换算小时，落到事件页并按该小时筛。
    const e = CODE.get('EventsPage.swift') || '';
    const h = CODE.get('HomeConsole.swift') || '';
    return e.includes('var initialHour: Int? = nil') &&
           e.includes('ZKProtocol.protoSecondsToUnix(r.lockTime)') &&
           h.includes('EventsPage(initialHour: h)') && h.includes('SpatialTapGesture()');
  }],
  ['过滤组合会被记住', () => {
    // RecordSearch 里 QueryFilters 的存取写得很完整（含三种开场策略，注释标到 560/908），
    // 但全仓 UI 一次都没调过 load/save —— 用户设了"只看告警"，离开再回来就回到全部。
    const e = CODE.get('EventsPage.swift') || '';
    return e.includes('QueryFilters.load(mac: mac)') && e.includes('filters.save(mac: mac)');
  }],
  ['即将到期的钥匙在门厅可见', () => {
    // expiringSoonCount 的注释写着"凭证 Tab 角标"，而 Tab 栏在单控制台重构时删了 ——
    // 函数还在（零调用），数就没了去处。门厅关键提示是它的新家。
    const h = CODE.get('HomeConsole.swift') || '';
    return h.includes('CredentialOrg.expiringSoonCount') && h.includes('case expiring(Int)');
  }],
  ['零调用的分析函数已接到展示位', () => {
    // 这两个函数实现都在（gapDays 17 行 / bigDropDays 25 行），但从来没有调用方。
    // 它们的展示位本来就有：诊断页的"数据健康"、设备页的"明细"。
    const d = CODE.get('DiagnosticsPage.swift') || '';
    const v = CODE.get('DevicePage.swift') || '';
    return d.includes('DataHealth.gapDays') && v.includes('BatteryCare.bigDropDays');
  }],
  ['明文密钥迁移会在启动时跑', () => {
    // migrateSecretsToKeychain 把旧 plist 里明文的 skey/bkey/ekey 搬进系统 Keychain
    // 并抹掉明文，注释写着"启动时调一次" —— 而它全仓零调用。
    // 后果：旧格式的明文密钥会一直躺在 UserDefaults 里（可被备份提取）。
    const app = CODE.get('LockKeeperApp.swift') || '';
    const store = CODE.get('Store.swift') || '';
    return store.includes('static func migrateSecretsToKeychain') &&
           app.includes('DB.migrateSecretsToKeychain()');
  }],
  ['凭证备注创建后可以改', () => {
    // 创建时能写备注，创建之后改不了 —— setPwdNote / setFpNote 写好了零调用，
    // 打错一个字只能删了重建。
    const k = CODE.get('KeysPage.swift') || '';
    const a = CODE.get('Alerts.swift') || '';
    // promptText 定义在 Alerts.swift，调用点在 KeysPage —— 第一版把两者写在同一个文件里查了。
    return k.includes('DB.setPwdNote(') && k.includes('DB.setFpNote(') && a.includes('func promptText');
  }],
  ['启动时预热 MAC 字节序', () => {
    // 协议层字节序在内存里，冷启动回到默认 .display。已配对的锁要等第一条命令失败、
    // exec() 里的探针才换序重试并记住 —— 正确性有保障，但每次冷启动第一条命令
    //（往往就是开锁）多一个来回。hydrateMacOrders 把它提前灌进去，原先零调用。
    const app = CODE.get('LockKeeperApp.swift') || '';
    return app.includes('DB.hydrateMacOrders()');
  }],
  ['设密码时提示它够不够难猜', () => {
    // StudioTools.pwdStrength 实现完整零调用。全同数字(111111)与顺子(123456)
    // 正是家里设门锁密码最常见的两种错误，也是试错者最先试的两种。
    // 挂在 AddKeyPage 的提示行上：密码一变成"可用"，就说它是弱是强。
    const k = CODE.get('AddKeyPage.swift') || '';
    return k.includes('StudioTools.pwdStrength(pwd)') && k.includes('private var pwdWeak');
  }],
  ['指纹可以改名，密码不能只改本地', () => {
    // 指纹在锁端没有名称字段，名字是本机展示字段 —— 改名安全。
    // 而 rePwd 只改本地台账的 pwd、不写锁，接了会造出"本地新、锁里旧"的骗人记录。
    const k = CODE.get('KeysPage.swift') || '';
    return k.includes('DB.renameFp(mac, row.key, text)') && !k.includes('DB.rePwd(');
  }],
  ['成员可以改名', () => {
    // 编辑表单有 10 个字段却唯独没有名字，DB.renameMember 零调用；
    // 而两处文案承诺「请在成员页重命名其一」「可重命名」。
    const m = CODE.get('MemberCenterView.swift') || '';
    return m.includes('DB.renameMember(') && m.includes('field("称呼 (必填)"');
  }],
  ['固件落后会在设备页提示', () => {
    // LockStats.fwLag 写好了零调用。新固件通常修的是开锁成功率与防拆逻辑，
    // "这把锁落后于本机最新那把"是用户该知道的信息。
    const v = CODE.get('DevicePage.swift') || '';
    return v.includes('LockStats.fwLag') && v.includes('fwLagNote');
  }],
  ['固件行同时说清落后与服役时长', () => {
    // fwLag 是跨锁对照，fwSince 是本机首次读到该版本的时刻（不冒充出厂时间）。
    // 两条都是本机算得出来的事实，合在固件行下面一行。
    const v = CODE.get('DevicePage.swift') || '';
    return v.includes('BatteryCare.fwSince(') && v.includes('fwNotes');
  }],
  ['设密码时提示前缀撞车', () => {
    // prefixConflict 零调用。它不是安全检查，是口头沟通检查：
    // 家里说"1234 开头那个"，两条都 1234 开头时谁都会拿错。
    const k = CODE.get('AddKeyPage.swift') || '';
    return k.includes('CredentialOrg.prefixConflict(') && k.includes('prefixClash');
  }],
  ['切换日志保留期会当场生效', () => {
    // 注释写着"确认后立即应用保留策略，返回实际删掉的条数"，
    // 但它错位挂在一个叫 today() 的函数上 —— 那个"立即应用"的函数早就不在了。
    // 结果：用户切完保留期看不到任何变化，要等下次写日志才裁剪。
    const d = CODE.get('DiagKit.swift') || '';
    const p = CODE.get('DiagnosticsPage.swift') || '';
    return d.includes('static func applyRetentionNow()') && p.includes('DiagLogs.applyRetentionNow()');
  }],
  ['视觉改动可被人工定位', () => {
    // 改了几十个界面文件，人工验收无从下手。工具把碰了字体/间距/颜色的行按界面列出来，
    // 并标出本次新建的文件（从没人看过，优先验）。
    return fs.existsSync(path.join(__dirname, '..', 'tools', 'visualreview.js'));
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
// ── 已知盲区 ────────────────────────────────────────────────
// 只列**真正会让人误判**的边界，不列"理论上可能"的。
const BLIND_SPOTS = {
  '按钮文字不小于 footnote': '只查 caption2，不查 caption(12pt) —— 后者是允许的紧凑动作',
  '说明性长句不用小字号': '只看 Text("字面量")；文字是变量时（Text(clash)）抓不到 —— 第 93 轮就是这样漏的两处',
  '可点行/按钮不低于 44pt': '只查按钮标签自己写死的高度；系统托管控件（Picker/Toggle）不查',
  '忙碌标志用 defer 复位': '只查 UI 层；服务层由定时器/委托驱动的状态不在内',
  '设计令牌没有零引用成员': '只看 Theme.swift 里 7 个令牌命名空间，其它常量不查',
  '体检不把合法空串算成残留': '只覆盖已知的 3 个键；新增"空串即默认"的键要手动加进白名单',
  '开锁改用 onLongPressGesture': '只验用的是长按；**手感、触发时机是否合适完全没验**',
  '分时图可点到对应小时的记录': '只验有一块可点区域；按 x 坐标换算成小时的准确性**没在真机验过**',
  '队列下发成功会告诉用户': '只验代码路径存在；真正连上锁时的下发与播报**没在真机走过**',
  '配对中禁止下滑关闭': '只验修饰符在；被系统手势抢先时会不会漏**未验**',
  '明文密钥迁移会在启动时跑': '只验调用点在；Keychain 写入失败时的回退路径**未在真机验**',
  '长句不用小字号（第93轮补）': 'N/A',
};
console.log('');
if (Object.keys(BLIND_SPOTS).length) {
  console.log('已知盲区（"全过"不等于"没问题"）:');
  for (const [k, v] of Object.entries(BLIND_SPOTS)) {
    if (checks.some(([n]) => n === k)) console.log('  · ' + k + ' —— ' + v);
  }
  console.log('');
}
console.log('回归通过 ' + pass + ' / ' + checks.length);
if (failed.length) { console.log('⚠ 回退: ' + failed.join(' | ')); process.exit(1); }
console.log('✓ 全部已修复项仍然成立');

