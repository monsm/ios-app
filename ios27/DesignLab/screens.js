// screens.js —— 每屏的 1:1 镜像。内容与 Swift 侧同源（同一份数据模型、同一套组件语法）。
// 加一屏 = 在 SCREENS 里加一项；run.js 会自动渲染并截图。
'use strict';
const P = require('./primitives.js');

// ---------- 与 AppModel.sample 同源的数据 ----------
const LOCK = { name: '前门', model: 'KX 系列', battery: 76, signal: 3, firmware: '1.4.2', keyCount: 9, connected: true, safeMode: false, muted: true };
const ENTRIES = [
  { t: '18:42', d: '今天', e: '指纹开锁', o: '妈妈', tone: 'ok' },
  { t: '17:05', d: '今天', e: '密码开锁', o: '我', tone: 'ok' },
  { t: '14:23', d: '今天', e: '密码错误 ×2', o: '未识别', tone: 'attention' },
  { t: '09:11', d: '今天', e: '临时码开锁', o: '保洁 周三', tone: 'ok' },
  { t: '22:47', d: '昨天', e: '门未关严', o: null, tone: 'critical' },
  { t: '20:30', d: '昨天', e: '手机钥匙开锁', o: '我', tone: 'ok' },
];
const KEYS = [
  { k: '密码', n: '主门密码', o: '我', code: '••••••', exp: null, off: false },
  { k: '指纹', n: '右手拇指', o: '我', code: null, exp: null, off: false },
  { k: '指纹', n: '左手食指', o: '妈妈', code: null, exp: null, off: false },
  { k: '临时码', n: '保洁 周三', o: '访客', code: '482913', exp: '2 天后', off: false },
  { k: '手机钥匙', n: '我的 iPhone', o: '我', code: null, exp: null, off: false },
];
const MEMBERS = [
  { n: '我', r: '管理员', keys: 3, last: '3 小时前', arch: false },
  { n: '妈妈', r: '成员', keys: 2, last: '26 小时前', arch: false },
  { n: '小姨', r: '成员', keys: 1, last: '未使用', arch: false },
  { n: '保洁', r: '访客', keys: 1, last: '5 天前', arch: false },
];

const statusConnected = P.statusLine('ok', '已连接 · ' + LOCK.model);

const doorHeader = P.pageHeader(LOCK.name, statusConnected);

const doorReadings = P.panel(
  P.sectionLabel('锁实况') +
  '<div class="gap-s"></div>' +
  P.readingGrid([
    { label: '电量', value: '76', unit: '%' },
    { label: '信号', value: '3', unit: '/ 4' },
    { label: '凭证', value: '9', unit: '枚' },
    { label: '固件', value: '1.4.2' },
  ]) +
  '<hr class="hair">' +
  '<div style="display:flex;gap:var(--sp-m)">' + P.statusLine('neutral', '安全模式 关') + P.statusLine('neutral', '静音 开') + '</div>'
);

const doorRecent = P.panel(
  P.sectionLabel('最近', '全部') + '<div class="gap-s"></div>' +
  P.ledgerRow('18:42', '指纹开锁', '妈妈', 'ok')
);

const doorShortcuts = P.panel(
  P.shortcut('锁实况', '&#9673;') + P.shortcut('新增凭证', '&#43;') +
  P.shortcut('成员', '&#9787;') + P.shortcut('校时', '&#8635;')
);

const SCREENS = [
  {
    id: 'door',
    name: '门 · 就绪',
    nav: '门',
    tab: 0,
    body: doorHeader + '<div class="gap"></div>' + P.dial('就绪', '上次 3 小时前', '轻点开锁', 0, false, 260) + '<div class="gap"></div>' + doorReadings + '<div class="gap"></div>' + doorRecent + '<div class="gap"></div>' + doorShortcuts,
  },
  {
    id: 'door-busy',
    name: '门 · 下发中（真实进度 46%）',
    nav: '门',
    tab: 0,
    body: doorHeader + '<div class="gap"></div>' + P.dial('下发', '上次 3 小时前', '正在开锁，请不要离开', 0.46, false, 260) + '<div class="gap"></div>' + doorReadings,
  },
  {
    id: 'door-opened',
    name: '门 · 已开（弧走满）',
    nav: '门',
    tab: 0,
    body: doorHeader + '<div class="gap"></div>' + P.dial('已开', '刚刚', '轻点开锁', 1, false, 260) + '<div class="gap"></div>' + doorReadings,
  },
  {
    id: 'door-failed',
    name: '门 · 失败（弧停在断点）',
    nav: '门',
    tab: 0,
    body: doorHeader + '<div class="gap"></div>' + P.dial('失败', '上次 3 小时前', '轻点重试', 0.72, true, 260) +
      '<div class="gap-m"></div><div style="display:flex;gap:var(--sp-s);align-items:flex-start;margin:0 var(--sp-gutter);padding:var(--sp-m) var(--sp-l);border-radius:var(--r-control);background:color-mix(in srgb,var(--critical) 10%,transparent)"><span style="color:var(--critical)">&#9888;</span><span style="color:var(--ink);font-size:var(--f-caption)">门锁未响应，请靠近门锁后重试</span></div><div class="gap"></div>' + doorReadings,
  },
  {
    id: 'door-empty',
    name: '门 · 空态（必须给出路）',
    nav: '门',
    tab: 0,
    body: P.pageHeader('未添加门锁', null) + '<div class="gap"></div>' +
      P.panel(P.empty('还没有添加门锁', '把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。', '添加门锁', '&#9635;')) +
      '<div class="gap"></div>' + doorShortcuts,
  },
  {
    id: 'keys',
    name: '钥匙 · 台账',
    nav: '钥匙',
    trailing: '&#43;&nbsp;&nbsp;&#9638;',
    tab: 1,
    body: P.pageHeader('钥匙', P.statusLine('neutral', '9 枚有效 · 1 枚 2 天后到期')) + '<div class="gap"></div>' +
      P.chipRow(['全部', '密码', '指纹', '临时码', '手机钥匙'], '全部') + '<div class="gap-m"></div>' +
      P.panel(
        P.sectionLabel('有效凭证', '9') + '<div class="gap-s"></div>' +
        KEYS.map((k, i) => (i ? '<hr class="hair">' : '') +
          '<div style="display:flex;align-items:baseline;gap:var(--sp-m);min-height:44px">' +
          '<div style="flex:1"><div style="font-size:var(--f-body);color:var(--ink)">' + P.H(k.n) + '</div>' +
          '<div style="font-size:var(--f-unit);color:var(--ink-sub)">' + P.H(k.k + (k.o ? ' · ' + k.o : '')) + '</div></div>' +
          (k.code ? P.reading(k.code, null, 'var(--f-caption)', 'var(--ink-sub)') : '') +
          (k.exp ? P.badge(k.exp, 'warn') : '') + '</div>').join('')
      ) + '<div class="gap"></div>' +
      P.panel(P.shortcut('到期月历', '&#9638;') + P.shortcut('手机钥匙', '&#9741;') + P.shortcut('分享给安卓', '&#8594;')),
  },
  {
    id: 'keys-empty',
    name: '钥匙 · 空态',
    nav: '钥匙',
    tab: 1,
    body: P.pageHeader('钥匙', P.statusLine('neutral', '还没有凭证')) + '<div class="gap"></div>' +
      P.chipRow(['全部', '密码', '指纹', '临时码', '手机钥匙'], '全部') + '<div class="gap-m"></div>' +
      P.panel(P.empty('这把锁还没有凭证', '先加一枚密码，家人就能用密码开门了。', '新增凭证', '&#9919;')),
  },
  {
    id: 'records',
    name: '台账 · 时间轴',
    nav: '台账',
    tab: 2,
    body: P.pageHeader('台账', P.statusLine('neutral', '今天 4 条 · 昨天 2 条')) + '<div class="gap"></div>' +
      P.chipRow(['全部', '开锁', '告警', '异常'], '全部') + '<div class="gap-s"></div>' +
      P.panel(P.sectionLabel('检索', '命中 6 条') + '<div style="display:flex;align-items:center;gap:var(--sp-s);color:var(--ink-faint);font-size:var(--f-caption);min-height:44px">&#9906;&nbsp;成员 / 凭证 / +指纹 -临时码</div>' + '<hr class="hair" style="margin:0">') +
      P.dayHeader('今天', 4) + P.panel(ENTRIES.slice(0, 4).map((e, i) => (i ? '<hr class="hair">' : '') + P.ledgerRow(e.t, e.e, e.o, e.tone)).join('')) +
      P.dayHeader('昨天', 2) + P.panel(ENTRIES.slice(4).map((e, i) => (i ? '<hr class="hair">' : '') + P.ledgerRow(e.t, e.e, e.o, e.tone)).join('')),
  },
  {
    id: 'records-empty',
    name: '台账 · 空态',
    nav: '台账',
    tab: 2,
    body: P.pageHeader('台账', null) + '<div class="gap"></div>' +
      P.panel(P.empty('还没有开门记录', '记录存在门锁里。连上锁读取一次就能看到。', '读取记录', '&#9636;')),
  },
  {
    id: 'household',
    name: '家 · 成员',
    nav: '家',
    tab: 3,
    body: P.pageHeader('家', P.statusLine('neutral', '4 位成员 · 9 枚凭证')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('成员', '4') + '<div class="gap-s"></div>' +
        MEMBERS.map((m, i) => (i ? '<hr class="hair">' : '') +
          '<div style="display:flex;align-items:baseline;gap:var(--sp-m);min-height:52px">' +
          '<div style="flex:1"><div style="font-size:var(--f-body);color:var(--ink)">' + P.H(m.n) + '</div>' +
          '<div style="font-size:var(--f-unit);color:var(--ink-sub)">' + P.H(m.r + ' · 最近 ' + m.last) + '</div></div>' +
          P.reading(String(m.keys), '枚', 'var(--f-body)', 'var(--ink-sub)') + '</div>').join('')) +
      '<div class="gap"></div>' + P.panel(P.shortcut('成员档案与权限', '&#9673;') + P.shortcut('归档', '&#9635;') + P.shortcut('家庭设置', '&#9881;')) +
      '<div class="gap"></div>' + P.panel(P.primary('新建成员')),
  },
  {
    id: 'settings',
    name: '设置',
    nav: '设置',
    tab: 4,
    body: P.pageHeader('设置', null) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('门锁') + '<div class="gap-s"></div>' + P.fieldRow('名称', '前门', null) + P.fieldRow('固件', '1.4.2', null) + P.fieldRow('电量', '76', '%') + P.fieldRow('安全模式', '关', null) + P.fieldRow('静音', '开', null)) +
      '<div class="gap"></div>' + P.panel(P.sectionLabel('安全') + '<div class="gap-s"></div>' + P.fieldRow('本机数据保护', '已开', null) + P.fieldRow('30 秒二次开锁', '已开', null) + P.fieldRow('防尾随', '关', null)) +
      '<div class="gap"></div>' + P.panel(P.sectionLabel('外观') + '<div class="gap-s"></div>' + P.fieldRow('深浅', '跟随系统', null) + P.fieldRow('密度', '标准', null)) +
      '<div class="gap"></div>' + P.panel(P.sectionLabel('数据') + '<div class="gap-s"></div>' + P.fieldRow('备份', '上次 3 天前', null) + P.fieldRow('关于', '1.0 (27)', null)),
  },
];


// ---------- 其余域的镜像屏（与各域 Swift 实现同源的数据与语法） ----------
const D = P;

const MORE = [
  {
    id: 'addlock',
    name: '添加门锁 · 扫描中（真四步梯）',
    nav: '添加门锁',
    tab: 0,
    body: P.pageHeader('添加门锁', P.statusLine('attention', '正在搜索门锁')) + '<div class="gap"></div>' +
      P.ladder(['发现', '校验', '初始化', '命名'], 0) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('附近的门锁', '1 台') + '<div class="gap-s"></div>' +
        '<div style="display:flex;align-items:baseline;gap:var(--sp-m);min-height:52px">' +
        '<div style="flex:1"><div style="font-size:var(--f-body);color:var(--ink)">ZKL-KX-8A21</div>' +
        '<div style="font-size:var(--f-unit);color:var(--ink-sub)">信号 ' + P.reading('-62', 'dBm', 'var(--f-unit)', 'var(--ink-sub)') + ' · 未绑定</div></div>' +
        P.badge('可添加') + '</div>') + '<div class="gap"></div>' +
      P.panel('<div class="note">把后面板打开，长按 RESET 直到三声嘀，再点下面的按钮。</div><div class="gap-m"></div>' + P.primary('开始添加')),
  },
  {
    id: 'addlock-chain',
    name: '添加门锁 · 配网链推进',
    nav: '添加门锁',
    tab: 0,
    body: P.pageHeader('添加门锁', P.statusLine('live', '配网中 · 不要离开这一页')) + '<div class="gap"></div>' +
      P.ladder(['发现', '校验', '初始化', '命名'], 1) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('进度', '3 / 7') + '<div class="gap-s"></div>' +
        P.kv('探测交换方式', '完成', null, 'var(--base)') +
        P.kv('生成密钥族', '完成', null, 'var(--base)') +
        P.kv('交换密钥 cmd05', '进行中', null, 'var(--ink)') +
        P.kv('写入密钥槽', '待执行', null, 'var(--ink-faint)')),
  },
  {
    id: 'lockstatus',
    name: '锁实况 · 读数 + 两枚真开关',
    nav: '锁实况',
    tab: 0,
    body: P.pageHeader('锁实况', P.statusLine('ok', '前门 · KX 系列')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('运行状态', 'cmd03') + '<div class="gap-s"></div>' +
        P.readingGrid([
          { label: '电量', value: '76', unit: '%' }, { label: '信号', value: '3', unit: '/ 4' },
          { label: '凭证', value: '9', unit: '枚' }, { label: '固件', value: '1.4.2' },
        ]) + '<hr class="hair">' +
        P.kv('锁内时间', '18:44', null) + P.kv('时间偏差', '+2', '分', 'var(--attention)')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('锁端策略') + '<div class="gap-s"></div>' +
        '<div class="kv"><span>安全模式（A/B 双验）</span><span class="toggle on"><i></i></span></div>' +
        '<div class="kv"><span>静音（键盘与开锁不提示音）</span><span class="toggle on"><i></i></span></div>'),
  },
  {
    id: 'memberdetail',
    name: '成员 360',
    nav: '成员',
    tab: 3,
    body: P.pageHeader('妈妈', P.statusLine('ok', '成员 · 2 枚凭证')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('档案') + P.fieldRow('角色', '成员', null) + P.fieldRow('凭证', '2', '枚') + P.fieldRow('最近', '26 小时前', null)) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('她的凭证', '2') + '<div class="gap-s"></div>' +
        '<div class="lrow"><div class="stamp">指纹</div><div class="lev"><span>左手食指</span><em>长期有效</em></div></div>' +
        '<hr class="hair">' +
        '<div class="lrow"><div class="stamp">密码</div><div class="lev"><span>备用密码</span><em>长期有效</em></div></div>') + '<div class="gap"></div>' +
      P.panel(P.shortcut('最近动态', '&#9636;') + P.shortcut('权限矩阵', '&#9673;') + P.shortcut('移入归档', '&#9635;')),
  },
  {
    id: 'security',
    name: '安全 · 开关页',
    nav: '安全',
    tab: 4,
    body: P.pageHeader('安全', P.statusLine('ok', '3 项已开启')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('本机') + '<div class="gap-s"></div>' +
        '<div class="kv"><span>本机数据保护（冷启动要密码）</span><span class="toggle on"><i></i></span></div>' +
        '<div class="kv"><span>30 秒内二次开锁要密码</span><span class="toggle on"><i></i></span></div>' +
        '<div class="kv"><span>截屏遮罩</span><span class="toggle on"><i></i></span></div>') + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('门锁') + '<div class="gap-s"></div>' +
        '<div class="kv"><span>防尾随（开门后等待时长）</span>' + P.reading('15', '秒', 'var(--f-body)') + '</div>' +
        '<div class="kv"><span>失败次数上限</span>' + P.reading('5', '次', 'var(--f-body)') + '</div>'),
  },
];

SCREENS.push(...MORE);


const MORE2 = [
  {
    id: 'keycreate',
    name: '新增凭证 · 四步真序列',
    nav: '新增凭证',
    tab: 1,
    body: P.pageHeader('新增凭证', P.statusLine('live', '第 2 步 · 填内容')) + '<div class="gap"></div>' +
      P.ladder(['选类型', '填内容', '定归属', '下发'], 1) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('密码', '6 位数字') + '<div class="gap-s"></div>' +
        P.inset('<div style="font-family:ui-monospace,Consolas,monospace;font-size:28px;letter-spacing:12px;color:var(--ink);text-align:center;padding:var(--sp-s) 0">4 8 2 9 1 3</div>') +
        '<div class="note">这枚密码会写进门锁的密码槽。下发前锁端不生效。</div>') + '<div class="gap"></div>' +
      P.panel(P.primary('下一步：定归属') + '<div class="gap-m"></div>' + P.secondary('改用随机码')),
  },
  {
    id: 'keycalendar',
    name: '到期月历',
    nav: '到期月历',
    tab: 1,
    body: P.pageHeader('到期月历', P.statusLine('attention', '本月 1 枚到期')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('2026 年 10 月') + '<div class="gap-s"></div>' +
        '<div class="cal">' + ['日','一','二','三','四','五','六'].map(d => '<b>' + d + '</b>').join('') +
        Array.from({length: 31}, (_, i) => '<span class="' + ([2, 9, 16, 23, 30].includes(i+1) ? 'on' : '') + '">' + (i+1) + '</span>').join('') + '</div>') + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('本月到期', '1') + '<div class="gap-s"></div>' +
        P.ledgerRow('11-02', '保洁 周三', '访客 · 临时码', 'attention')),
  },
  {
    id: 'recorddetail',
    name: '记录详情',
    nav: '记录详情',
    tab: 2,
    body: P.pageHeader('指纹开锁', P.statusLine('ok', '今天 18:42 · 已成功')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('事件') + P.fieldRow('时刻', '18:42', null) + P.fieldRow('方式', '指纹', null) + P.fieldRow('归属', '妈妈', null, 'var(--ink)')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('门锁读数', '当时') + '<div class="gap-s"></div>' +
        P.readingGrid([{ label: '电量', value: '76', unit: '%' }, { label: '信号', value: '3', unit: '/ 4' }])) + '<div class="gap"></div>' +
      P.panel(P.shortcut('这枚凭证', '&#9919;') + P.shortcut('这位成员', '&#9787;') + P.shortcut('前后各 3 条', '&#9636;')),
  },
  {
    id: 'sync',
    name: '校时 · 三读数',
    nav: '校时',
    tab: 0,
    body: P.pageHeader('校时', P.statusLine('attention', '锁钟比手机慢 2 分')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('读数') + '<div class="gap-s"></div>' +
        P.readingGrid([
          { label: '锁内时间', value: '18:42' }, { label: '手机时间', value: '18:44' },
          { label: '偏差', value: '-2', unit: '分', tint: 'var(--attention)' },
        ])) + '<div class="gap"></div>' +
      P.panel('<div class="note">偏差大于 2 秒才值得写。写会下发 cmd0E，写完回读核对，没归零就报失败。</div><div class="gap-m"></div>' + P.primary('写入手机时间')),
  },
  {
    id: 'defend',
    name: '布防 · 三档',
    nav: '布防',
    tab: 0,
    body: P.pageHeader('布防', P.statusLine('neutral', '当前：撤防')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('模式') + '<div class="gap-s"></div>' +
        '<div class="kv"><span>' + P.dot('neutral','已选') + ' 撤防</span><span class="sub">不布防</span></div><hr class="hair">' +
        '<div class="kv"><span>' + P.dot('neutral','') + ' 不定期</span><span class="sub">全天布防</span></div><hr class="hair">' +
        '<div class="kv"><span>' + P.dot('neutral','') + ' 每日时段</span>' + P.reading('22:00', '- 07:00', 'var(--f-body)') + '</div>') + '<div class="gap"></div>' +
      P.panel('<div class="note">布防否决的是「靠近自动开锁」，不是手动开锁 —— 站在门口点刻度盘仍然能开。</div><div class="gap-m"></div>' + P.primary('下发布防')),
  },
];

SCREENS.push(...MORE2);


const MORE3 = [
  { id: 'household-empty', name: '家 · 空态（给出路）', nav: '家', tab: 3,
    body: P.pageHeader('家', P.statusLine('neutral', '还没有成员')) + '<div class="gap"></div>' +
      P.panel(P.empty('还没有建立成员档案', '建档后可以给每个人分配凭证、看各自的开门记录。', '新建成员', '&#9787;')), },
  { id: 'keydetail', name: '凭证详情', nav: '凭证详情', tab: 1,
    body: P.pageHeader('主门密码', P.statusLine('ok', '有效 · 我')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('码值', '逐位可点开') + '<div class="gap-s"></div>' +
        '<div style="font-family:ui-monospace,Consolas,monospace;font-size:26px;letter-spacing:10px;text-align:center;color:var(--ink);padding:var(--sp-m) 0">••••••</div>') + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('读数') + P.fieldRow('类型', '密码', null) + P.fieldRow('归属', '我', null, 'var(--ink)') + P.fieldRow('有效期', '长期', null) + P.fieldRow('最近使用', '3 小时前', null)) + '<div class="gap"></div>' +
      P.panel(P.secondary('改到期日') + '<div class="gap-m"></div>' + P.secondary('停用')) + '<div class="gap-m"></div>' +
      P.panel('<div class="note" style="color:var(--critical)">彻底删除会同时从门锁里删掉这枚密码 —— 删完就开不了门了。</div>'), },
  { id: 'appearance', name: '外观 · 跟着档位变的样例', nav: '外观', tab: 4,
    body: P.pageHeader('外观', P.statusLine('neutral', '标准密度 · 跟随系统')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('深浅') + '<div class="gap-s"></div>' + P.chipRow(['跟随系统', '浅色', '深色'], '跟随系统')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('密度') + '<div class="gap-s"></div>' + P.chipRow(['紧凑', '标准', '宽松'], '标准')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('样例', '会跟着变') + P.fieldRow('电量', '76', '%') + P.fieldRow('固件', '1.4.2', null)), },
  { id: 'about', name: '关于 · 机械计数器', nav: '关于', tab: 4,
    body: P.pageHeader('关于', P.statusLine('neutral', '锁管家 1.0 (27)')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('累计开锁', '自配网起') + '<div style="display:flex;gap:6px;justify-content:center;padding:var(--sp-m) 0">' +
        ['0','0','4','2','8','7'].map(d => '<span style="font-family:ui-monospace,Consolas,monospace;font-size:30px;padding:8px 10px;border-radius:8px;background:var(--plate-alt);color:var(--ink)">' + d + '</span>').join('') + '</div>') + '<div class="gap"></div>' +
      P.panel(P.kv('版本', '1.0 (27)') + P.kv('构建', '2026.10') + P.kv('数据', '全部在本机')), },
  { id: 'backup', name: '备份 · 密钥按档提示', nav: '备份与恢复', tab: 4,
    body: P.pageHeader('备份与恢复', P.statusLine('attention', '上次 3 天前')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('导出') + '<div class="gap-s"></div>' +
        '<div class="kv"><span>加密（口令保护）</span><span class="toggle on"><i></i></span></div>' +
        '<div class="note" style="padding:0">开启后备份包需要口令才能恢复，口令丢了就解不开。</div><div class="gap-m"></div>' + P.primary('导出备份')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('恢复') + '<div class="gap-s"></div>' + P.inset('<div class="note" style="padding:0;color:var(--ink-faint)">粘贴备份文本</div>')), },
  { id: 'hardware', name: '硬件 · 钥匙串台账', nav: '硬件', tab: 4,
    body: P.pageHeader('硬件', P.statusLine('neutral', '1 把钥匙串 · 1 个网关')) + '<div class="gap"></div>' +
      P.panel(P.sectionLabel('蓝牙钥匙串', '1') + '<div class="gap-s"></div>' +
        P.readingGrid([{ label: '电量', value: '62', unit: '%' }, { label: '钥匙', value: '3', unit: '枚' }, { label: '固件', value: '2.0.1' }]) + '<hr class="hair">' +
        '<div class="kv"><span>ZKBB-7C31</span>' + P.badge('已绑定') + '</div>') + '<div class="gap"></div>' +
      P.panel(P.primary('扫描钥匙串')), },
];

SCREENS.push(...MORE3);

module.exports = { SCREENS, LOCK, ENTRIES, KEYS, MEMBERS };