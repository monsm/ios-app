#!/usr/bin/env node
// tools/glassaudit.js — Black Canvas / Glass Instrument 范式符合度审计 (顾问级, 不判失败)
//
// 为什么需要它: 令牌层改对(14/24/#000000)不等于每个页面都照做了。
// 一个页面可以有正确的 XSpace.gutter, 却仍然用 VStack(spacing: XSpace.l) 把所有块等距排开 ——
// 那样分组层级读不出来, 而这项**没有任何现有闸门在看**。
//
// 判据全部来自 C:\\Users\\imons\\.agents\\skills\\ios-glass-design-spec\\references\\design-spec.md,
// 只取能被静态代码形状判定的那些。判不了的不假装能判, 逐条列在文末。
//
// 用法: node tools/glassaudit.js            (报线索, 恒退出 0)
//       node tools/glassaudit.js --strict   (有 FAIL 则 exit 1; 仅供人工蹲点用)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}
const files = walk(APP);

// ---- 规则表 ----
const RULES = [
  {
    id: 'G1',
    name: '页面底必须是 canvas',
    why: '规范总则一: 黑色是画布。用 .background(Color(...)) 或 .background(.black) 直接写底 = 绕过令牌, 亮色档会变成纯黑。',
    test: (line) => /\.background\(\s*(?:Color\.)?(?:black|white)\s*\)/.test(line),
  },
  {
    id: 'G2',
    name: '卡片不许有投影',
    why: '规范 6.3 / 14-4: 应用体卡片零投影。黑底上的投影只会把边缘糊成脏灰。',
    test: (line, ctx) => /\.shadow\(/.test(line) && /XPanel|XRadius\.card/.test(ctx),
  },
  {
    id: 'G3',
    name: '页面根 VStack 不该一律 16',
    why: '规范 5.1 / 验收 L4: 区块之间 28 (XSpace.section)。全页等距 = 没有分组。' +
         ' 判据: 一个 VStack(spacing: XSpace.l) 的**紧邻上下文**里既出现了 ScrollView 又出现了' +
         ' padding(.horizontal, XSpace.gutter) —— 那就是"页面根容器"的形状，而不是卡内分组。',
    test: (line, ctx) => /VStack\(spacing: XSpace\.l\)/.test(line) && /ScrollView/.test(ctx) && /padding\(\.horizontal, XSpace\.gutter\)/.test(ctx),
  },
  {
    id: 'G4',
    name: '卡片圆角落在 10–19 (低于规范下限)',
    why: '规范 5.2 / 14-5: 卡片圆角 < 20pt 即返工。10–19 这一段最像"卡片但不是卡片"—— 通用后台风就是这么来的。' +
         ' (cornerRadius 1–6 的多是进度条/图表刻度/分割块, 属于数据可视化, 不在本规则内。)',
    test: (line) => /RoundedRectangle\(cornerRadius:\s*1[0-9]\b/.test(line),
  },
  {
    id: 'G5',
    name: '环不许有投影, 只许辉光',
    why: '规范 7.8 通用自检: 环不得有投影。',
    test: (line, ctx) => /\.shadow\(/.test(line) && /Circle\(\)|trim\(from:/.test(ctx),
  },
  {
    id: 'G9',
    name: '长按菜单没有告诉用户「能长按」',
    why: '可发现性: 藏进 contextMenu 的动作在视觉上等于不存在。' +
         ' 规范要求「看着就想点的东西必须真的能点，而且要看得出能点」。' +
         ' 视觉侧可以权衡（有时加省略号反而更挤），但**读屏侧不能也不说** ——' +
         ' 所以判据只强制一件事: 有 contextMenu 的元素必须带 accessibilityHint。' +
         ' 已有 hint 的（比如「长按可置顶…」）就满足。',
    test: (line, ctx) => {
      if (!/\.contextMenu\s*\{/.test(line)) return false;
      // 第二参在 G9 上是「从本行往后 42 行」的窗口（见主循环）。
      const seg = ctx || line;
      return !/accessibilityHint\(/.test(seg);
    },
  },
  {
    id: 'G8',
    name: '成功/失败提示缺对应触感 (规范 §11.4)',
    why: '规范 §11.4 的触感表: 目标达成 → .success, 失败 → .error。' +
         ' 而 showToast 此前**不带触感**, 于是全仓 30 处「报了成功、手上没动静」——' +
         ' 不是谁忘了, 是接口没给形状。现在 showToast 有 tone 参数, 这条闸门防它退回去。' +
         ' 判据: 文案是"已…/成功…/失败…"却写成 tone: .plain(或没写)。' +
         ' 「已复制」这类**纯告知**本来就该是 plain, 不在本规则内。',
    test: (line, ctx) => {
      if (!/showToast\(/.test(line)) return false;
      // 多行调用很常见（三元表达式 / 长文案折行）—— 只看这一行会把正确的判成缺 tone。
      // 判据要用**调用所在的那一小段**：ctx 由主循环提供（前后各若干行）。
      const seg = ctx || line;
      // 纯告知白名单: 复制/切换/选中 这类不需要触感
      if (/已复制|已切换|已选中|已展开|已收起/.test(line)) return false;
      const isDone = /"(?:已(?:删除|生成|导入|保存|解除绑定|清除|标记|打卡|按|移)|设置成功|成功)/.test(line);
      const isFail = /"(?:失败|错误)/.test(line);
      if (!isDone && !isFail) return false;
      // 这一**段**里必须带 tone
      return !/tone:\s*\.(done|failed|caution)/.test(seg);
    },
  },
  {
    id: 'G14',
    name: '纯色描边画环（规范 §14-9 命中即返工）',
    why: '规范 §14-9 把「纯色（非渐变）描边画环」列进**命中即返工**，§7.8 的通用自检也写着' +
         ' 「所有环必须渐变或分色，纯色单环 = 不合格」。理由：环的质感全靠渐变/分色，' +
         ' 纯色描边读起来是一条粗线，不是一只环。' +
         ' 本仓 FirmwarePage 的升级进度底环原来就是 .stroke(XPalette.hairline, lineWidth: 14) —— 纯色。' +
         ' 判据：Circle() 用 .stroke/.strokeBorder 且 lineWidth >= 6（细描边是边框不是环），' +
         ' 而颜色不是 Gradient 的，判线索。',
    test: (line, ctx) => {
      const seg = ctx || line;
      if (!/Circle\(\)/.test(seg)) return false;
      const m = /\.stroke(?:Border)?\([\s\S]{0,120}?lineWidth:\s*([0-9]+(?:\.[0-9]+)?)/.exec(seg);
      if (!m) return false;
      if (parseFloat(m[1]) < 6) return false;
      // 这一段里出现任意 Gradient 就算渐变环
      return !/LinearGradient|AngularGradient|RadialGradient|Gradient\(/.test(seg);
    },
  },
  {
    id: 'G13',
    name: '出现投影（规范 §6.3 只允许两处）',
    why: '规范 §6.3 的注脚写得很死：**黑底上唯一允许的阴影**是「设备样机底部 0 24px 48px」与' +
         ' 「全屏 Sheet 边缘 0 -8px 32px」，并且「**卡片永远没有**」。' +
         ' §14-4 把「给应用体卡片加投影」列进明令禁止。' +
         ' 本仓曾用 .shadow 画过三处浮层投影 + 两处彩色辉光 —— 浮层那条直接违规（浮层是「玻璃 + 0.5pt 描边」），' +
         ' 彩色辉光也改成径向渐变了（§7.8：发光用辉光不用投影）。现在全仓 .shadow() 归零。' +
         ' 判据：出现 .shadow( 即判线索。若真需要设备样机/Sheet 边缘那两处，先在这里登记。',
    test: (line) => /\.shadow\(/.test(line),
  },
  {
    id: 'G12',
    name: '图标垫了规范之外的圆形底',
    why: '规范 §10「圆形底」写得很死：**StatChip 图标允许 34pt；列表图标允许 20pt；其余不加底**。' +
         ' 本仓曾在 hero 卡里给图标垫 56pt / 96pt 的洗染圆底 —— 既不是 34 也不是 20。' +
         ' 判法用**结构**而不是尺寸去认：`Circle()` 作为 ZStack 里的独立视图、紧跟着又一个 Image(systemName:)，' +
         ' 才是「图标底」；写在 `.background(… in: Circle())` 里的那种是**序号徽章**（圆里是 Text 数字），不判。',
    test: (line, ctx) => {
      const m = /\.frame\(width:\s*([0-9]+),\s*height:\s*([0-9]+)\)/.exec(line);
      if (!m) return false;
      const w = +m[1];
      if (w === 34 || w === 20) return false;   // 规范允许的两档
      const seg = ctx || '';
      const ls = seg.split('\n');
      const at = ls.findIndex((l) => l.includes(line.trim()));
      if (at < 0) return false;
      // 往回 5 行内要有**独立的** Circle() 行（不是嵌在 background/in: 里）
      const back = ls.slice(Math.max(0, at - 5), at);
      const standalone = back.some((l) => /^\s*Circle\(\)\s*$/.test(l));
      if (!standalone) return false;
      // 往前 6 行内要有 Image(systemName:) —— ZStack 的另一个孩子
      const fwd = ls.slice(at + 1, at + 7);
      if (!fwd.some((l) => /Image\(systemName:/.test(l))) return false;
      // 步骤节点：图标是圆的**状态标记**（完成的打勾），写在 .overlay 里，不是垫在下面的底。
      if (ls.slice(at, at + 6).some((l) => /\.overlay\(/.test(l))) return false;
      // 辉光不是底（§7.8 要求环/圆盘只用辉光）
      if (ls.slice(at, at + 6).some((l) => /\.blur\(radius:/.test(l))) return false;
      // moment 级（>=96pt）是整屏成功/庆祝大图，不是卡片内的图标底
      if (w >= 96) return false;
      return true;
    },
  },
  {
    id: 'G11',
    name: '图标尺寸不在规范 §10 的七档上',
    why: '规范 §10 给的图标尺寸是**固定七档**：12 / 13 / 17 / 20 / 22 / 28 / 34。' +
         ' 本仓原来写的是 12/16/20/26/44/72 —— 其中 16 / 26 / 44 / 72 都不在档位上；' +
         ' 另有 12 处调用点直接写死 14/19/24/40/42/44。' +
         ' 中间值说明有人在按感觉调，而不是按系统。' +
         ' 判据只认 XIcon.* 令牌或这七个数字。',
    test: (line, ctx) => {
      // 图标尺寸: Image(systemName:) 之后 .font(.system(size: N))
      const seg = ctx || line;
      if (!/Image\(systemName:|\bicon\b|glyph/.test(seg)) return false;
      const m = /\.font\(\.system\(size:\s*([0-9.]+)/.exec(line);
      if (!m) return false;
      const v = parseFloat(m[1]);
      const LADDER = [12, 13, 17, 20, 22, 28, 34];
      return !LADDER.includes(v);
    },
  },
  {
    id: 'G10',
    name: '排版绕过了规范字阶 (用了裸 .font 或 .xFont(.system(size:)))',
    why: '规范 §4.2 的字阶全线下修过一档 (caption 12→11 / footnote 13→12 / subheadline 15→14 /' +
         ' body 17→16 / title2 22→19 / largeTitle 34→30), 并明确写「原值直接套用了 HIG 默认值,' +
         ' 从未对参考图测过」。本仓曾经 766 处排版全跑在 HIG 默认值上 —— 那正是规范点名批评的做法。' +
         ' 现在字号唯一入口是 XText (see Theme.swift), 这条闸门防它退回去。' +
         ' 例外: 图标尺寸 Image(systemName:).font(.system(size:)) 是刻意写死的, 不放行这里。',
    test: (line, ctx) => {
      // .xFontExact 是显式字号的逃生门 —— 数量由 tools/apisig.js 的预算看着，这里不判。
      if (/\.xFontExact\(/.test(line)) return false;
      const isSizeFont = /\.font\(\.system\(size:/.test(line) || /\.xFont\(\.system\(size:/.test(line);
      if (!isSizeFont) return false;
      // 图标尺寸是**刻意写死**的（规范 §10 七档），不算绕过字阶。
      // 判据看上下文：这一段里有没有 Image(systemName:) 或 XIcon/XMetric 尺寸令牌。
      const seg = ctx || line;
      if (/Image\(systemName:|XIcon\.|XMetric\./.test(seg)) return false;
      // 只有作用在文本上才判：上下文里得出现 Text(
      return /Text\(/.test(seg);
    },
  },
  {
    id: 'G7',
    name: '图标尺寸低于 12pt (规范 §10 的档位下限)',
    why: '规范 §10 给的图标档位是 12 / 13 / 17 / 20 / 22 / 28 / 34，最小 12pt。' +
         ' 写 8pt/9pt/11pt 在 3x 屏上只有 24–33 物理像素，符号会糊成一团 ——' +
         ' 而这条没有任何其它闸门在看（dynamictype 只管文字字号与触达尺寸）。' +
         ' 修法是换成 XIcon.xs(12) 或更大的档位，不是随手调个数字。',
    test: (line) => {
      // 只判 Image(systemName:) 后面紧跟的 .font(.system(size: N))，且 N < 12。
      // 用 XMetric.dataText/decorIcon 包的属于刻度器皿，放行。
      const m = line.match(/\.font\(\.system\(size:\s*([0-9.]+)/);
      if (!m) return false;
      const v = parseFloat(m[1]);
      return v > 0 && v < 12;
    },
  },
  {
    id: 'G6',
    name: '玻璃只许出现在功能层',
    why: '规范总则二: 卡片/列表/内容容器永远不许用玻璃。xGlass 出现在 XPanel 内部 = 层搞错了。',
    test: (line, ctx) => /\.xGlass\(|\.axGlass/.test(line) && /XPanel\s*\{/.test(ctx) && !/overlay|Toast|savedChips|segmentBar/.test(ctx),
  },
];

// ── 工程级断言（不是逐行扫，是整个 App 有没有做这件事）──
const projectProblems = [];
// ── 流程维度：破坏性动作必须在确认框里，确认词不许含糊 ──
//
// 规范反复强调「说清要删什么」，本仓也有一批写得很好的确认（KeysPage 那条把
// ① 本机会删 ② 锁端也会撤销 ③ 断网不丢 ④ 在哪恢复 四件事都在 message 里说全了）。
// 判据只守住两条底线，不要求每处都写四句。
{
  const VAGUE_TITLE = /confirmTitle:\s*"(确定|确认|好的|好|OK|Ok|ok|是|Yes)"/;
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach(function (raw, i) {
      const code = raw.replace(/\/\/.*$/, '');
      if (VAGUE_TITLE.test(code)) {
        projectProblems.push('确认词含糊（应说清删的是什么，不是「确定」）：' +
                             path.relative(ROOT, f) + ':' + (i + 1));
      }
      // destructive 按钮必须在 confirmationDialog / alert 里。
      // 不能用固定行数回看 —— 有的对话框 message 很长，按钮在 40 行以外。
      // 改成**向上找块起点**：遇到 confirmationDialog/alert 就算在框内；
      // 遇到顶格的 struct/extension 或文件开头还没找到，就算不在。
      if (!/role:\s*\.destructive/.test(code)) return;
      let inConfirm = false;
      for (let k = i - 1; k >= 0; k--) {
        const up = lines[k].replace(/\/\/.*$/, '');
        if (/confirmationDialog\(|\.alert\(/.test(up)) { inConfirm = true; break; }
        // contextMenu 豁免：长按 + 选删除是**两步有意动作**，本仓 EventsPage 的注释也按这个口径论证过。
        // `Menu` 不豁免 —— 点开菜单即到，接近普通按钮（DonglesPage / GatewayPage 都是这个形态，已补确认）。
        if (/\.contextMenu\s*\{/.test(up)) { inConfirm = true; break; }
        // swipeActions 且 `allowsFullSwipe: false` 也是两步（划开 → 再点）。
        // 全滑即执行的那种（true）不豁免 —— 一划就没了。
        if (/\.swipeActions\([^)]*allowsFullSwipe:\s*false/.test(up)) { inConfirm = true; break; }
        if (/^(struct|extension|enum|final class|class) /.test(up)) break;
        if (/^    (?:private )?(?:var|func) /.test(up)) break;
      }
      if (inConfirm) return;
      // 第二种合法形态：按钮只是**触发**一个确认函数（按钮本身是红色调的入口）。
      // 判据看同一行或紧随 3 行里有没有 confirm* 调用。
      const win = lines.slice(i, i + 4).join('\n');
      if (/\bconfirm[A-Z]\w*\(/.test(win)) return;
      projectProblems.push('破坏性按钮不在确认框内（检查是否会误触即执行）：' +
                           path.relative(ROOT, f) + ':' + (i + 1) + '  ' + raw.trim().slice(0, 50));
    });
  }
}

{
  // 逻辑维度（通用探测器）：**同名私有成员跨文件必报**。
  //
  // 这一族错本会话抓到五处，全是同一形状：
  //   保养周期 / 备份时间戳 / 距今几天 / 电量图标 / 锁态文案 / 上次备份文案。
  // 一处一处找太慢，所以做成判据。
  //
  // 只判「缩进 4 的 private func/var 且名字 >= 8 字符」——短名多半是局部变量。
  // 白名单放「同名但确实不同语义」的视图构建器；往里加之前必须证明它们不是同一个量。
  const VIEW_BUILDER_OK = new Set([
    'emptyState', 'sectionTitle', 'groupHeader', 'detailSection', 'actionRow',
    'actionsCard', 'statusCard', 'capacityCard', 'metricsRow', 'retentionCard',
    'alarmRow', 'dayHeader', 'dayLabel', 'emptyCard', 'actionCard', 'subtitle',
    'header', 'signalCard', 'listContent', 'studioRow', 'lockStateText', 'shortTime',
    'lastBackupText', 'batteryIcon', 'batteryTone', 'periodDays', 'atLabel',
    'memberColor', 'ownerChip', 'errorBanner', 'progressText', 'importSheet',
    'armMigrateWizard', 'prefillOwner', 'readPair', 'timestampRow', 'submit',
    'alarmList', 'makeBody', 'makeCoordinator', 'makeUIViewController',
    'updateUIViewController', 'reload', 'refresh', 'systemImage', 'action',
    'onDone', 'vkBody', 'secLabel', 'embedded', 'accessibilityText', 'content',
    'devices', 'members', 'stream', 'waiter', 'debugRaw', 'connect', 'disconnect',
    'version', 'typeName', 'message', 'lockTime', 'lockName', 'idxRaw', 'member',
    'firmware', 'attempt', 'lastDispatch', 'pairedAt', 'archived', 'segment',
    'guestBlocked', 'sKeyStatus', 'powerLevel', 'pidName', 'securityLevel',
    'verifyMode', 'broadcastMode', 'tempPwdMode', 'zotpPeriod', 'eCtrlVer',
    'lockTimeStr', 'isAlarm', 'remaining', 'weight', 'active', 'sourceName',
    'errorDescription', 'writeAckCont', 'rows', 'parts', 'list', 'day', 'now',
  ]);
  const seen = new Map();
  for (const f of files) {
    const rel = path.relative(ROOT, f);
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      const m = /^    (?:private |fileprivate )(?:func|var) (\w{8,})\b/.exec(code);
      if (!m) return;
      const name = m[1];
      if (VIEW_BUILDER_OK.has(name)) return;
      if (!seen.has(name)) seen.set(name, []);
      seen.get(name).push(rel + ':' + (i + 1));
    });
  }
  for (const entry of seen) {
    const name = entry[0];
    const hits = entry[1];
    const filesWith = new Set(hits.map(function (h) { return h.split(':')[0]; }));
    if (filesWith.size < 2) continue;
    projectProblems.push('同名私有成员跨 ' + filesWith.size + ' 个文件出现（疑似重复实现：' + name + '）：' + hits.join(', '));
  }
}
{
  // 逻辑维度（第三类）：**同一个量只允许一处映射**。
  //
  // 实证：电量图标与配色在本仓曾有三套 —— `BatteryCare.tier()` 一套，
  // DonglesPage / LocksPage 各自一套，阈值与图标都不同。
  // p=5 时三处分别给 battery.0percent / battery.25 / battery.0；
  // p=85 时 DonglesPage 还停在 75% 图标；
  // LocksPage 的配色没处理「未知(-1)」，读不到电量反而显示成告警色。
  //
  // 判据：`battery.N` / `battery.Npercent` 字面量只许出现在 BatteryCare.swift。
  for (const f of files) {
    const rel = path.relative(ROOT, f);
    if (/BatteryCare\.swift$/.test(rel)) continue;
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      // 只判「按电量返回图标」的**映射**，不判静态装饰图标（Label(systemImage: "battery.100") 是文案配图）。
      if (!/return\s+"battery\./.test(code)) return;
      if (/BatteryCare\.icon|BatteryCare\.tier/.test(code)) return;
      projectProblems.push('电量图标映射只许在 BatteryCare（tier/icon）里定义：' +
                           rel + ':' + (i + 1) + '  ' + raw.trim().slice(0, 50));
    });
  }
}
{
  // 逻辑维度：**同一个量只允许一个算法 / 一个写点**。
  //
  // 实证两类（都是本会话真抓到的）：
  //  ① 备份时间戳有两个 key —— `kf_backup_hist` 与 `kf_bk_last_export`，
  //     两条导出路径各写各的，于是「上次导出」在不同屏幕给出不同答案；
  //  ② 「距今几天」有两种算法 —— ms 除法 vs 纪元日号相减，跨零点差一天。
  //
  // 判据：① `kf_bk_last_export` 只许在 Milestones.recordBackup 里写；
  //      ② 不许再用 `Int(... / 86400) - Int(... / 86400)` 那种日号相减写法。
  for (const f of files) {
    const rel = path.relative(ROOT, f);
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      if (/DB\.store\.set\("kf_bk_last_export"/.test(code) && !/Milestones\.swift$/.test(rel)) {
        projectProblems.push('同一个量两个写点：`kf_bk_last_export` 只许由 Milestones.recordBackup 写' +
                             '（这样时间线与该 key 才不会漂）：' + rel + ':' + (i + 1));
      }
      // 纪元日号相减的特征：两个 "/ 86400" 出现在同一个减式里。
      // 不能用带 [^)]* 的正则 —— 那个类会被 Date( 的首个 ) 截断。
      if ((code.match(/\/\s*86400\b/g) || []).length >= 2) {
        projectProblems.push('「距今几天」有第二套算法（纪元日号相减）—— 请用 TimeFormat.daysSince(ms:)：' +
                             rel + ':' + (i + 1));
      }
    });
  }
}
{
  // 逻辑维度：**同一个量只能有一个算法**。
  //
  // 实证：保养周期档（近 30 天开门 ≥60 次的锁 60 天、否则 90 天）在本仓有**三条读法**：
  //   · CarePage.daysUntilCare  写死 `opens30d: 0` → 永远 90 天（与同页卡片矛盾）
  //   · CareViews 自己数 `HotCache.recent` → 不含测试标记过滤与协议时间窗
  //   · BatteryCare(mac:) / 通知侧走 `LockStats.usage()` → 正确口径
  // 已全部收敛到 `carePeriodDays(mac:)`。判据：`carePeriodDays(opens30d:` 只许出现在
  // BatteryCare.swift 自身（定义 + 通知路径），其它文件用带 mac 的那个重载。
  for (const f of files) {
    const rel = path.relative(ROOT, f);
    if (/BatteryCare\.swift$/.test(rel)) continue;
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      if (!/carePeriodDays\(opens30d:/.test(code)) return;
      projectProblems.push('同一个量两处算法：`carePeriodDays(opens30d:)` 只许在 BatteryCare.swift 内用，' +
                           '其它地方请用 `carePeriodDays(mac:)`：' + rel + ':' + (i + 1));
    });
  }
}
{
  // 规范 §13.1：「支持到 AX3」。
  //
  // 实证：本仓有 11 处 `Text(...).frame(width: 52)` 这类**写死的列宽** ——
  // 普通字号下正好，AX3 时字号翻倍而列宽不动，标签就换行或截断，整张表一起垮。
  // 已全部换成 `xScaledWidth(_:)`（列宽随 Dynamic Type 缩放，对齐与可读性都保住）。
  //
  // 判据（三条件同时成立才报，否则误报太多）：
  //   ① `.frame(width: N` 且**没有 height**（有 height 的多半是图标/头像方框）；
  //   ② N < 200（≥200 的是画布/预览面，不是文字列宽）；
  //   ③ 紧邻前 5 行里有 `Text(` 且**没有** `Image(systemName`。
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const code = lines[i].replace(/\/\/.*$/, '');
      const m = /\.frame\(width:\s*([0-9]+)\s*(,|\b)/.exec(code);
      if (!m) continue;
      if (/height:/.test(code)) continue;                       // ① 方框
      if (Number(m[1]) >= 200) continue;                        // ② 画布
      const back = lines.slice(Math.max(0, i - 5), i).join('\n');
      if (!/Text\(/.test(back)) continue;                       // ③ 不是文字
      if (/Image\(systemName/.test(back)) continue;
      projectProblems.push('§13.1 文字上的固定列宽应走 xScaledWidth（AX3 会破版）：' +
                           path.relative(ROOT, f) + ':' + (i + 1) + '  ' + code.trim().slice(0, 46));
    }
  }
}
{
  // 规范 §14-#6：**内容层不许用毛玻璃** —— 违反 HIG 两层模型（内容不透明 / 功能层玻璃）。
  //
  // 本仓唯一合法的玻璃是 `XGlassTabBar`（功能层）。实证有一处越界：
  // SecurityCenterView 的挡片用 .ultraThinMaterial 盖 OTP —— 既违反分层，
  // 又没达成目的（那种材质故意透背景，秘密可能被部分读出）。
  const MATERIAL = /\.(ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)\b/;
  for (const f of files) {
    const rel = path.relative(ROOT, f);
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      if (!MATERIAL.test(code)) return;
      if (/XGlassTabBar/.test(code)) return;   // 功能层，允许
      // 允许的例外：XGlassTabBar 自身实现（同一个 struct 体内）
      const around = lines.slice(Math.max(0, i - 24), i + 2).join('\n');
      // 两处合法：功能层 Tab Bar 自身，以及**玻璃配方的唯一实现** XGlassSurface。
      // 后者不是「内容层用玻璃」，而是玻璃这个材质本身的定义 —— 内容层若直接用它会另报。
      if (/struct XGlassTabBar|struct XGlassSurface/.test(around)) return;
      projectProblems.push('§14-#6 内容层用了毛玻璃（只许在功能层 / XGlassTabBar）：' +
                           rel + ':' + (i + 1) + '  ' + raw.trim().slice(0, 50));
    });
  }
}
{
  // 规范 §14-#11：**11pt 以下字号命中即返工**（低于 iOS 最小可读字号）。
  //
  // 实证：环内文字的下限原为 max(8,…) / max(9,…)，在 104pt 的环里实际渲染出 8–9pt。
  // 这类错在源码里看不出来 —— 那一行写的是 max(9, size * 0.072)，看着像个合理的下限，
  // 但它随环直径收缩，小环就破了可读下限。
  //
  // 判法两条：① `.system(size: <字面量>)` 里的字面量不得 < 11；
  //          ② `max(<字面量>, …)` 用作字号下限时，字面量不得 < 11。
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      if (code.trim().startsWith('///')) return;
      let bad = null;
      const lit = /\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)/.exec(code);
      if (lit && Number(lit[1]) < 11) bad = '字号字面量 ' + lit[1];
      if (!bad) {
        const fl = /XMetric\.(?:dataText|decorIcon)\(max\(([0-9.]+),/.exec(code);
        if (fl && Number(fl[1]) < 11) bad = '字号下限 ' + fl[1];
      }
      if (!bad) return;
      projectProblems.push('§14-#11 ' + bad + ' 低于 11pt 可读下限：' +
                           path.relative(ROOT, f) + ':' + (i + 1));
    });
  }
}
{
  // 规范 J5 / §7.20.3：错误态要说清「什么坏了 + 怎么办」。
  // 系统给的 localizedDescription 是工程术语（"write failed" / "response timeout" / CBError 6），
  // 两条都不满足。本仓有 `ErrorText.human` 专门做这件事（19 处在用）——
  // 实证有三处漏了，直接抛原文。
  //
  // 只判**送到界面**的那些（赋给 error / 进 showToast / 进 Text）；
  // 写日志与审计的不判 —— 日志里要的是原文。
  const FACING = /(?:showToast\(|Text\(|self\.error\s*=|\berror\s*=|\berr\s*=)/;
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      if (code.trim().startsWith('///')) return;
      if (!/localizedDescription/.test(code)) return;
      if (!FACING.test(code)) return;
      if (/ErrorText\.human|log\(|audit\(|recordAttempt|recordFailure/.test(code)) return;
      projectProblems.push('J5 错误面直抛系统原文（应过 ErrorText.human）：' +
                           path.relative(ROOT, f) + ':' + (i + 1) + '  ' + raw.trim().slice(0, 60));
    });
  }
}
{
  // 规范 J6：部分数据时**保留卡片结构**，缺失项显示占位，而不是把整行藏掉。
  //
  // 判法：`if <cond> { ... XRow(...) }` 这种「条件成立才出行、没有 else 兜底」的形态；
  // 行一消失，用户就分不清「没有这项数据」和「这一项不存在」。
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const code = lines[i].replace(/\/\/.*$/, '');
      if (!/^\s*if\b.*\{\s*$/.test(code)) continue;
      const body = lines.slice(i + 1, i + 4).join('\n');
      if (!/XRow\(|XLabeledRow\(/.test(body)) continue;
      const indent = (code.match(/^\s*/) || [''])[0];
      let hasElse = false;
      for (let k = i + 2; k < Math.min(i + 18, lines.length); k++) {
        if (new RegExp('^' + indent + '\\}\\s*else').test(lines[k])) { hasElse = true; break; }
        if (new RegExp('^' + indent + '\\}').test(lines[k])) break;
      }
      if (!hasElse) {
        projectProblems.push('J6 整行被条件隐藏且无占位兜底：' +
                             path.relative(ROOT, f) + ':' + (i + 1) + '  ' + code.trim().slice(0, 50));
      }
    }
  }
}
{
  // 规范 I8：负号用 **U+2212 −**，不是连字符 `-`。
  //
  // 只判**界面文案里紧跟数字的负号**（`Text("... -60")` / 字符串插值里的负数）。
  // 日期 `2026-01-01`、`SHA-256`、`AES-128-CBC`、`A-Z`、`2-7` 这些连字符不是负号，不能一锅端 ——
  // 所以判法是「连字符 + 数字，且**前面不是数字**」（日期中间那种前面是数字，排除）。
  const NEG_IN_TEXT = /"[^"]*(?:^|[^0-9\w])-(\d)/;
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      // 只看界面文案：含 Text( 或 accessibilityLabel( 的字面量
      if (!/Text\(|accessibilityLabel\(|accessibilityValue\(/.test(code)) return;
      const lit = /"([^"]*)"/.exec(code);
      if (!lit) return;
      if (!NEG_IN_TEXT.test(lit[0])) return;
      // 排除看起来像日期/版本号的（YYYY-MM-DD 或 X-Y 且两侧都是数字）
      if (/\d-\d/.test(lit[1])) return;
      projectProblems.push('I8 负号应为 U+2212 −，这里用了连字符：' +
                           path.relative(ROOT, f) + ':' + (i + 1) + '  ' + lit[1].slice(0, 30));
    });
  }
}
{
  // 规范 §7.6 的「内部纵向节奏」六个数：卡头→标题 6 / 标题→标签 12 / 标签→值 2 /
  // 值→分隔线 14 / 分隔线→下一组 12 / 页脚上方 12。
  //
  // 实证错误：分隔线传 `verticalPadding: 14` —— 那是**线上下各补 14**，再叠容器 12，
  // 净距成了 26；而规范给的 14 是**净距**。这类错肉眼只觉得「有点松」，量不出来。
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      const m = /XHairline\(verticalPadding:\s*([0-9.]+)\)/.exec(code);
      if (!m) return;
      const v = Number(m[1]);
      if (v === 0) return;
      projectProblems.push('§7.6 分隔线间距写成了 verticalPadding: ' + v +
                           '（那是线上下各补 ' + v + '，会与容器间距叠加）；净距请用 .padding(.top, 2)：' +
                           path.relative(ROOT, f) + ':' + (i + 1));
    });
  }
}

// §5.3 的「页边距 14」**没有做成断言** —— 判不了。
//
// 原因：`.padding(.horizontal, XSpace.x)` 在同一棵视图树里既可能是**页面页边距**，
// 也可能是**卡片自己的内边距**（规范只约束前者）。要分开就必须知道「哪一个是页面的最外层容器」，
// 而那是 AST 信息，靠行扫描只能猜。试过一版按 navigationTitle 圈定页面 body —— 依然误报，
// 因为页面 body 里还有嵌套的卡片。
//
// 留了两条人读的实证修正（都改在源码里，注释写明理由）：
//   · FpStudio：`.padding(XSpace.l)` 四边 16 → 横向 XSpace.gutter(14)
//   · ShareToAndroidView：原来没有横向页边距，内容贴边 → 补 XSpace.gutter
{
  // 规范 §5.3：页边距 14 / **区块之间 28** / 簇内 16 / 卡片行距 8。
  // 四个数各自有语义。只靠「比簇内多 8pt」拉簇间是无效的 —— 16 与 24 的差别眼睛读不出分组，
  // 规范给的差是 16 与 28。本仓实证：27 个页面的根 VStack 用了 l(16) 或 xl(24)。
  //
  // 判据：`ScrollView` 紧跟的 `VStack(spacing:)` 是页面内容的区块容器，只许 section。
  // 不判 LazyVStack / VStack(spacing: 0)：那两种是「行容器」，行距另有规定。
  const BAD_ROOT = /ScrollView(?:\([^)]*\))?\s*\{\s*\n\s*VStack\(spacing: XSpace\.(?!section)\w+\)/;
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    for (let i = 0; i < lines.length - 2; i++) {
      if (!/ScrollView(?:\([^)]*\))?\s*\{\s*$/.test(lines[i].replace(/\/\/.*$/, ''))) continue;
      const next = (lines[i + 1] || '').replace(/\/\/.*$/, '');
      const m = /VStack\(spacing: XSpace\.(\w+)\)/.exec(next);
      if (!m) continue;
      if (m[1] === 'section') continue;
      projectProblems.push('§5.3 页面根 VStack 的区块间距应为 XSpace.section(28)，实为 ' + m[1] +
                           '：' + path.relative(ROOT, f) + ':' + (i + 2));
    }
  }
}
{
  // 规范 §7.16：单位与数值**同色但小一档**。
  // 最典型的反例就是把单位拼进同一个字符串 —— 那样单位必然拿到数值的字号。
  // 只在**指标级**字号上判（title2 及以上）：句子里的「3 天」是正文，不归这条管。
  const METRIC = /xFont(Exact|Scaled)?\(\s*\.(title2|title3|largeTitle|display|displayNumber|headline)/;
  // 只判「整条文本基本就是 数值+单位」的情形。
  // 「发现 3 把锁」是**句子**（单位是句子成分），不是指标排版 —— 不能一锅端。
  // 判法：取第一段字面量，把插值整段挖掉；剩下的若正好是一个单位，才是「拼接单位」。
  const UNITS = ['天','次','把','个','条','分钟','小时','秒','份','枚','位','%','cal','min','hrs'];
  const gluedLiteral = (code) => {
    const q = /"([^"]*)"/.exec(code);
    if (!q) return null;
    if (!q[1].includes('\(')) return null;          // 没有插值 → 不是拼接
    const rest = q[1].replace(/\\\([^)]*\)/g, '').trim();
    return UNITS.includes(rest) ? rest : null;
  };
  for (const f of files) {
    const srcLines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    srcLines.forEach((raw, i) => {
      const code = raw.replace(/\/\/.*$/, '');
      if (code.trim().startsWith('///')) return;
      const unit = gluedLiteral(code);
      if (unit === null) return;
      const win = srcLines.slice(i, i + 4).join('\n');
      if (!METRIC.test(win)) return;
      projectProblems.push('§7.16 指标级单位被拼进数值字符串（应走 XValueUnit）：' +
                           path.relative(ROOT, f) + ':' + (i + 1) + '  ' + raw.trim().slice(0, 60));
    });
  }
}
{
  // 规范 §7.18 数字溢出的四个档位是**确定值**（按位数，不按字符数）。
  // 这类比例错了肉眼读不出来 —— 只有把数字放到 8 位以上才看得见，而界面里极少出现。
  const th = fs.readFileSync(path.join(ROOT, 'App/Core/Theme.swift'), 'utf8');
  const oc = /static func overflowScale\(digits: Int\) -> CGFloat \{([\s\S]*?)\n    \}/.exec(th);
  if (!oc) projectProblems.push('XMetric.overflowScale 不见了 —— 规范 §7.18 要求按位数降档');
  else {
    const body = oc[1];
    if (!/if digits <= 7 \{ return 1\.0 \}/.test(body)) projectProblems.push('§7.18：≤7 位应为 1.0');
    if (!/if digits <= 9 \{ return 0\.82 \}/.test(body)) projectProblems.push('§7.18：8–9 位应为 0.82');
    if (!/if digits <= 11 \{ return 0\.65 \}/.test(body)) projectProblems.push('§7.18：10–11 位应为 0.65');
  }
  if (!/static func abbreviate\(_ n: Int\) -> String/.test(th)) projectProblems.push('§7.18：>11 位必须有 M/B 缩写');
}
{
  // 规范 §7.3 自检：「同一产品内**只用一种**，不得混用」。
  // 本仓此前三种并存：系统 .pickerStyle(.segmented)（4 处）、KeysPage 手搓的
  // glass+accent 洗底、以及别处各自写的。已统一为 XSegmented（形态 B）。
  const files = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const q = path.join(d, e.name);
      if (e.isDirectory()) walk(q);
      else if (q.endsWith('.swift')) files.push(q);
    }
  })(path.join(ROOT, 'App'));
  const offenders = [];
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((l, i) => {
      if (l.trim().startsWith('//') || l.trim().startsWith('///')) return;
      if (/\.pickerStyle\(\.segmented\)/.test(l)) offenders.push(path.relative(ROOT, f) + ':' + (i + 1));
    });
  }
  if (offenders.length) {
    projectProblems.push('仍有 ' + offenders.length + ' 处系统分段控件没换成 XSegmented（§7.3 同一产品只用一种）：' + offenders.join(', '));
  }
}
{
  // 规范 §7.20.1 骨架屏的四个数：周期 1.4s / ease-in-out / 高光宽 30% / 底色 #24242A。
  // 「参数差一点看不出来」正是这种地方 —— 而 1.4s 还是规范内部打架的那条（§11.2 说 ≤1.2s）。
  const compSrc = fs.readFileSync(path.join(ROOT, 'App/Core/Components.swift'), 'utf8');
  // 取整个 struct（到下一个顶层 }），不是只取 body —— 流光在 private func block() 里，
  // 第一版切到 @ViewBuilder 就停了，于是把「明明写对的值」判成错。
  const skStart = compSrc.indexOf('struct XSkeleton');
  const skRest = compSrc.slice(skStart);
  const body = skRest.slice(0, skRest.indexOf('\n}\n') + 2);
  if (!/\.easeInOut\(duration: 1\.4\)/.test(body)) {
    projectProblems.push('XSkeleton 的微光不是 easeInOut(1.4) —— 规范 §7.20.1 要求 ease-in-out / 周期 1.4s');
  }
  if (!/geo\.size\.width \* 0\.30/.test(body)) {
    projectProblems.push('XSkeleton 的高光宽度不是 30% —— 规范 §7.20.1');
  }
  if (!/Color\.white\.opacity\(0\.06\)/.test(body)) {
    projectProblems.push('XSkeleton 的高光不是 rgba(255,255,255,0.06) —— 规范 §7.20.1');
  }
}

{
  // 规范 §13.1：「环不随字号缩放」「AX3：displayNumber 允许降至 44pt」。
  // displayNumber 装在固定尺寸的环里 —— 跟着 Dynamic Type 放大会把数字顶出环外。
  const compSrc2 = fs.readFileSync(path.join(ROOT, 'App/Core/Components.swift'), 'utf8');
  const mod = compSrc2.slice(compSrc2.indexOf('struct XTextModifier'));
  const modBody = mod.slice(0, mod.indexOf('\n}\n') + 2);
  if (!/typeSize\.isAccessibilitySize \? 44/.test(modBody)) {
    projectProblems.push('XTextModifier 没有把 displayNumber 在 AX 档降到 44 —— 规范 §13.1');
  }
  if (!/min\(scaled, DSFont\.displayNumber\)/.test(modBody)) {
    projectProblems.push('displayNumber 没有被封顶在 56 —— 固定尺寸的环里放大会顶出环外');
  }
  // 单一来源：56 只应在 DSFont 出现一次
  const themeSrc2 = fs.readFileSync(path.join(ROOT, 'App/Core/Theme.swift'), 'utf8');
  const literals = (themeSrc2.match(/= 56\b/g) || []).length;
  if (literals > 1) projectProblems.push('56 这个数在 Theme.swift 出现了 ' + literals + ' 次 —— 应当只有 DSFont.displayNumber 一处');
}

{
  // 规范里「辉光」是**两个不同的量**：
  //   §3.5 glowBlue       —— 环后辉光，透明度 **0.35**，半径 ≤160，用小元素
  //   §7.12 AmbientGlow   —— 环境光溢出，透明度 **0.12–0.20**，半径 200–320，一屏 ≤2 处
  // 混用会出两种错：环不够亮，或整页发灰。本仓门厅曾把两者叠加（0.35×0.12=4%）。
  const th = fs.readFileSync(path.join(ROOT, 'App/Core/Theme.swift'), 'utf8');
  const glowFn = /static func glow\(_ color: Color\) -> RadialGradient \{([\s\S]*?)\n    \}/.exec(th);
  const ambFn = /static func ambient\(_ color: Color\) -> RadialGradient \{([\s\S]*?)\n    \}/.exec(th);
  if (!glowFn) projectProblems.push('XGradient.glow 不见了 —— 规范 §3.5 需要一个 0.35 的环后辉光');
  else if (!/color\.opacity\(0\.35\)/.test(glowFn[1])) projectProblems.push('XGradient.glow 不是 0.35 —— 规范 §3.5 glowBlue 就是这个值');
  if (!ambFn) projectProblems.push('XGradient.ambient 不见了 —— 规范 §7.12 需要一个 0.12–0.20 的环境光');
  else if (!/color\.opacity\(0\.(1[2-9]|20)\)/.test(ambFn[1])) projectProblems.push('XGradient.ambient 不在 0.12–0.20 —— 规范 §7.12 给的就是这个区间');}
{
  const appSrc = fs.readFileSync(path.join(ROOT, 'App/LockKeeperApp.swift'), 'utf8');
  // 规范 §10：图标渲染用 .hierarchical。缺了就是全仓图标跑在 .monochrome 上（单层平涂）。
  if (!appSrc.includes('.symbolRenderingMode(.hierarchical)')) {
    projectProblems.push('根视图没有设 .symbolRenderingMode(.hierarchical) —— 规范 §10 要求图标按层次渲染');
  }
}

const findings = [];
for (const f of files) {
  const rel = f.replace(/\\/g, '/').split('/App/').pop();
  const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
  lines.forEach((raw, i) => {
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    const code = raw.replace(/\/\/.*$/, '');
    // 上下文窗口前后各看 14 行: 页面根容器的 ScrollView 在前、gutter 内边距在后,
    // 只往前看会漏掉一半形状 —— 第一版就是这么漏的。
    const ctx = lines.slice(Math.max(0, i - 14), Math.min(lines.length, i + 15)).join('\n');
    // 前后各 6 行足够覆盖一个折行的调用（G8 用），又不至于把隔壁调用也卷进来。
    const callCtx = lines.slice(Math.max(0, i - 2), Math.min(lines.length, i + 7)).join('\n');
    // G9：hint 写在 contextMenu 之后，而菜单本身可能很长（KeysPage 那份列了六个动作
    // + 大段注释，hint 落在 70 行开外）。固定窗口不管调到多少都会误伤 ——
    // 改成**按函数边界**取：从 contextMenu 这一行扫到所在函数的收尾 `}`。
    // 注意：hint 在**修饰符链**上、位于菜单闭合的 `}` **之后**，
    // 所以不能用括号配平找终点（那样会停在菜单自己的 `}`，正好漏掉 hint）。
    // 正确边界是「修饰符链结束处」= 遇到下一个声明（func/var/struct/…）就停。
    let menuEnd = Math.min(lines.length - 1, i + 120);
    for (let k = i + 1; k < lines.length; k++) {
      if (/^\s{0,8}(?:private |public |internal |fileprivate )?(?:func|var|let|struct|enum|extension)\s/.test(lines[k])) {
        menuEnd = k - 1;
        break;
      }
    }
    const menuCtx = lines.slice(i, menuEnd + 1).join('\n');
    // G12 要往回看：判断这个 .frame 属于 Text 还是 Image（序号徽章 vs 图标底）
    const discCtx = lines.slice(Math.max(0, i - 9), Math.min(lines.length, i + 5)).join('\n');
    for (const r of RULES) {
      if (r.test(code, r.id === 'G9' ? menuCtx : (r.id === 'G12' ? discCtx : callCtx))) findings.push({ rule: r.id, name: r.name, why: r.why, file: rel, line: i + 1, text: t.slice(0, 78) });
    }
  });
}

// ---- 汇总 ----
const byRule = {};
for (const f of findings) (byRule[f.rule] ||= []).push(f);

console.log('Black Canvas / Glass Instrument 符合度审计 — 扫 ' + files.length + ' 个 .swift');
console.log('');
if (projectProblems.length) {
  for (const q of projectProblems) console.error('  ✗ ' + q);
  console.error('✗ 工程级断言不通过 ' + projectProblems.length + ' 处');
  process.exit(1);
}

if (findings.length === 0) {
  console.log('✓ 静态可判的六类全部通过');
} else {
  for (const r of RULES) {
    const list = byRule[r.id];
    if (!list || !list.length) continue;
    console.log('── ' + r.id + ' ' + r.name + ' (' + list.length + ') ──');
    console.log('   ' + r.why);
    for (const f of list.slice(0, 12)) console.log('   ' + f.file + ':' + f.line + '  ' + f.text);
    if (list.length > 12) console.log('   … 另 ' + (list.length - 12) + ' 处');
    console.log('');
  }
}

console.log('总计 ' + findings.length + ' 条线索。');
console.log('');
console.log('本工具**判不了**的 (不假装能判):');
console.log('  · §5.3 的页边距 14 是「页面最外层容器」的内边距，同行扫描分不清它与卡片内边距');
console.log('  · 玻璃在亮背景/黑背景下明度是否都合理 (需要真机截图)');
console.log('  · 字号在 Dynamic Type 各档下是否破版 (需要模拟器)');
console.log('  · 间距在屏幕上读起来是否有层级 (需要眼睛)');

if (process.argv.includes('--strict') && findings.length > 0) process.exit(1);