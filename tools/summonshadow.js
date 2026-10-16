#!/usr/bin/env node
// tools/summonshadow.js — 拖拽召唤的**纯几何影子对拍** (P5，判失败)
//   node tools/summonshadow.js            判失败，异常退 2
//   node tools/summonshadow.js --selftest  验尺子自己（正控/反控各一），不符退 2
//
// 为什么要有它：本仓从未跑过 XCTest（无 Xcode/模拟器），而拖拽召唤是第一批碰
// `matchedGeometryEffect` / `DragGesture(velocity:)` / 弹簧交接的代码 —— 这三个 API 全仓 0 先例，
// 错了只能等 CI 红，且红在哪一行都说不清。所以「哪里有光点 / 拖多远算越界 / 松手会落在哪 / 落在谁身上」
// 全部抽成不碰视图的纯算术（`App/Core/SummonGeometry.swift`），在这里用**另一门语言**再算一遍。
//
// ⚠ 它证明的边界要照实说：只有这几个纯函数的算术，以及"常数与设计文档 §2 一致"。
//   `matchedGeometryEffect` 的形变、手势的跟手感、弹簧的观感 —— 一行都没执行过。
//   "影子对拍通过"永远不等于"真机上是对的"。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SWIFT = path.join(ROOT, 'App', 'Core', 'SummonGeometry.swift');
const CORE = path.join(ROOT, 'design-system', 'aurora-lock', 'CORE.md');
const ROOTS = path.join(ROOT, 'App', 'UI', 'VariantRoots.swift');

// ---------- 复刻 SummonGeometry 的算术 (逐行对照 Swift) ----------
const CANVAS = { w: 400, h: 860 };
const HOME = { x: 200 / CANVAS.w, y: 521 / CANVAS.h };
const RIDE = { dx: 130 / CANVAS.w, dy: -263 / CANVAS.h };
const RIDE_SCALE = 0.42;
const DOTS = [
  { route: 'records', x: 200 / CANVAS.w, y: 345 / CANVAS.h },
  { route: 'credentials', x: 74 / CANVAS.w, y: 425 / CANVAS.h },
  { route: 'settings', x: 326 / CANVAS.w, y: 425 / CANVAS.h },
];
const LIMIT_RATIO = 196 / CANVAS.w;
const RUBBER_C = 0.55;
const PROJECT_D = 0.99;
const PROJECT_CLAMP = 1.4;
const HIT_RATIO = 34 / CANVAS.w;

// Swift: over * dim * c / (dim + c * over)
const rubberBand = (over, dim, c = RUBBER_C) => (over > 0 && dim > 0 ? (over * dim * c) / (dim + c * over) : Math.max(0, over));
// Swift: 界内 1:1；界外按半径方向拉到 limit + rubberBand(d-limit, limit)
function dragOffset(raw, limit) {
  const d = Math.hypot(raw.dx, raw.dy);
  if (!(limit > 0) || d <= limit) return { dx: raw.dx, dy: raw.dy };
  const k = (limit + rubberBand(d - limit, limit)) / d;
  return { dx: raw.dx * k, dy: raw.dy * k };
}
// Swift: (v / 1000) * d / (1 - d)   ← Apple project() 的指数衰减式，不是 v²/2a
const project = (v, d = PROJECT_D) => (d > 0 && d < 1 ? ((v / 1000) * d) / (1 - d) : 0);
function projectedOffset(offset, velocity, limit, clamp = PROJECT_CLAMP) {
  const raw = { dx: offset.dx + project(velocity.dx), dy: offset.dy + project(velocity.dy) };
  const cap = limit * clamp;
  const d = Math.hypot(raw.dx, raw.dy);
  if (!(cap > 0) || d <= cap) return raw;
  const k = cap / d;
  return { dx: raw.dx * k, dy: raw.dy * k };
}
function summon(projected, dots, radius) {
  let best = null;
  for (const dd of dots) {
    const r = Math.hypot(projected.x - dd.point.x, projected.y - dd.point.y);
    if (r <= radius && (best === null || r < best.distance)) best = { route: dd.route, distance: r };
  }
  return best && best.route;
}
const hasMomentum = (velocity, limit) => Math.hypot(velocity.dx, velocity.dy) > Math.max(limit * 1.2, 1);

// ---------- 期望表 (手算 + 不变量，逐条写死；两边任一侧改了语义这里就红) ----------
const near = (a, b, eps = 0.01) => Math.abs(a - b) <= eps;
const LIMIT = LIMIT_RATIO * 400;          // = 196（画布 400pt 短边 ⇒ 与原型同值）
const layout = {
  home: { x: HOME.x * 400, y: HOME.y * 860 },                 // (200, 521)
  ride: { x: HOME.x * 400 + RIDE.dx * 400, y: HOME.y * 860 + RIDE.dy * 860 },  // (330, 258)
  dots: DOTS.map((d) => ({ route: d.route, point: { x: d.x * 400, y: d.y * 860 } })),
  limit: LIMIT,
  hit: HIT_RATIO * 400,                                        // 34
};
const CHECKS = [];
const check = (name, ok, detail) => CHECKS.push({ name, ok, detail });

// 1. 轨道位与 CORE.md §2 的四个坐标逐字相同
check('HOME = (200, 521)', near(layout.home.x, 200) && near(layout.home.y, 521), JSON.stringify(layout.home));
check('RIDE = (330, 258)  [Δ(130, −263)]', near(layout.ride.x, 330) && near(layout.ride.y, 258), JSON.stringify(layout.ride));
check('动态光点 = (200, 345)', near(layout.dots[0].point.x, 200) && near(layout.dots[0].point.y, 345));
check('钥匙光点 = (74, 425)', near(layout.dots[1].point.x, 74) && near(layout.dots[1].point.y, 425));
check('门锁光点 = (326, 425)', near(layout.dots[2].point.x, 326) && near(layout.dots[2].point.y, 425));
check('LIMIT = 196', near(layout.limit, 196));
check('RIDE scale = 0.42', RIDE_SCALE === 0.42);

// 2. 界内 1:1 跟手 (跟手感就是这一条：位移必须原样等于手指位移)
const inA = dragOffset({ dx: 60, dy: -40 }, LIMIT);
check('界内 1:1: dragOffset 原样返回', near(inA.dx, 60) && near(inA.dy, -40), JSON.stringify(inA));
const exactly = dragOffset({ dx: 196, dy: 0 }, LIMIT);
check('正好到 LIMIT 仍 1:1', near(exactly.dx, 196), String(exactly.dx));

// 3. 越界走橡皮筋，且**不是硬停**：先验公式原值，再验三条不变量
const over = rubberBand(196, LIMIT);
check('橡皮筋 over=196 → limit·(c/(1+c)) 之上', over > 60 && over < 70, String(over));
const out = dragOffset({ dx: 392, dy: 0 }, LIMIT);
check('越界: |位移| = limit + rubberBand(over)', near(Math.hypot(out.dx, out.dy), 265.548, 0.01), String(Math.hypot(out.dx, out.dy)));
check('越界: 模长 > limit (仍在动，不是硬停)', Math.hypot(out.dx, out.dy) > LIMIT);
check('越界: 模长 < limit·(1+c) (拉得动但拉不飞)', Math.hypot(out.dx, out.dy) < LIMIT * (1 + RUBBER_C));
const out2 = dragOffset({ dx: 800, dy: 0 }, LIMIT);
check('橡皮筋单调: 拖更远 ⇒ 走更远', Math.hypot(out2.dx, out2.dy) > Math.hypot(out.dx, out.dy));
const diag = dragOffset({ dx: 300, dy: 300 }, LIMIT);
check('越界保持方向: 45° 拖进来还是 45°', near(diag.dx, diag.dy, 1e-6), JSON.stringify(diag));

// 4. 动量投影：指数衰减 + 钳位
check('project(0) = 0', project(0) === 0);
check('project(1000, d=0.99) = 99  ⇒ v·0.099', near(project(1000), 99), String(project(1000)));
check('project 单调', project(3000) > project(1000));
const flung = projectedOffset({ dx: 0, dy: 0 }, { dx: 3000, dy: 0 }, LIMIT);
check('投影钳位 = LIMIT×1.4 = 274.4', near(Math.hypot(flung.dx, flung.dy), 274.4, 0.01), String(Math.hypot(flung.dx, flung.dy)));
const soft = projectedOffset({ dx: 0, dy: 0 }, { dx: 200, dy: 0 }, LIMIT);
check('轻甩不触发钳位: 200pt/s ⇒ 19.8pt', near(soft.dx, 19.8, 0.01), String(soft.dx));
check('d 非法时不猜: project(v,1) = 0', project(1000, 1) === 0);

// 5. 命中判据用**投影落点** —— 这就是"朝光点甩一下就过去"
// 从 HOME (200,521) 朝左下甩 1100pt/s（方向指向「钥匙」光点）：
// 投影位移 = (−108.9, −82.97) ⇒ 落点 (91.1, 438.03)，距 (74,425) 21.5pt < 34 ⇒ 命中
const flungPts = projectedOffset({ dx: 0, dy: 0 }, { dx: -1100, dy: -838.1 }, LIMIT);
const landing = { x: layout.home.x + flungPts.dx, y: layout.home.y + flungPts.dy };
check('斜甩落点 = HOME + 投影位移', near(landing.x, 91.1, 0.05) && near(landing.y, 438.03, 0.05), JSON.stringify(landing));
check('朝「钥匙」斜甩 ⇒ 召唤 credentials', summon(landing, layout.dots, layout.hit) === 'credentials', String(summon(landing, layout.dots, layout.hit)));
// 拿**抬手位置**判就会漏掉这一条：抬手时手指还在 (200,521)，投影落点才是 (91.1,438.0)
check('判据必须用投影落点：拿抬手位置判會 miss', summon({ x: 200, y: 521 }, layout.dots, layout.hit) === null);
check('落在动态光点旁 ⇒ records', summon({ x: 210, y: 350 }, layout.dots, layout.hit) === 'records');
// 半径边界：正好 34 = 命中，35 = 不命中（"≤" 而不是 "<"，调一次就会看起来像手势忽灵忽不灵）
check('距光点正好 34pt ⇒ 命中', summon({ x: 200, y: 345 - 34 }, layout.dots, layout.hit) === 'records');
check('距光点 35pt ⇒ 不命中', summon({ x: 200, y: 345 - 35 }, layout.dots, layout.hit) === null);
check('离三光点都远 ⇒ 不召唤 (回位)', summon({ x: 90, y: 600 }, layout.dots, layout.hit) === null);

// 6. 只有手势本身带动量才给回弹
check('hasMomentum(300pt/s, limit 196) = true (阈 235.2)', hasMomentum({ dx: 300, dy: 0 }, LIMIT) === true);
check('hasMomentum(100pt/s) = false', hasMomentum({ dx: 100, dy: 0 }, LIMIT) === false);

// ---------- 防漂移：常数必须与设计文档 §2 逐字一致 ----------
// 这是本仓"手抄的常数必然漂移"那条教训（HANDOFF §5-6：CSS 从 .11 改到 .035，尺子里还留着 .11）的机器版。
function anchors(md) {
  const need = [
    ['196', 'LIMIT 拖拽半径'], ['c=0.55', '橡皮筋 c'], ['d=0.99', '动量投影衰减率'],
    ['1.4', '投影钳位 LIMIT×1.4'], ['(200, 521)', 'HOME'], ['(130, −263)', 'RIDE Δ'],
    ['0.42', 'RIDE scale'], ['(200,345)', '动态光点'], ['(74,425)', '钥匙光点'], ['(326,425)', '门锁光点'],
    ['1100', 'CHARGE 满充时长'],
  ];
  return need.filter(([tok]) => !md.includes(tok)).map(([, why]) => why);
}
function swiftProblems(src) {
  const need = [
    ['over * dim * c / (dim + c * over)', '橡皮筋公式'],
    ['(v / 1000) * d / (1 - d)', 'project 指数衰减式'],
    ['196.0 / canvas.width', 'LIMIT 比例'],
    ['34.0 / canvas.width', '命中半径比例'],
    ['static let rubberC: CGFloat = 0.55', 'rubberC'],
    ['static let projectD: CGFloat = 0.99', 'projectD'],
    ['static let projectClamp: CGFloat = 1.4', 'projectClamp'],
    ['static let rideScale: CGFloat = 0.42', 'rideScale'],
  ];
  return need.filter(([tok]) => !src.includes(tok)).map(([, why]) => why);
}
// 接线控制：纯函数没人调用就不是实现，是死代码（本仓 deadscan 的同一条口径）
function wiredProblems(src) {
  const used = ['SummonGeometry.layout', 'SummonGeometry.dragOffset', 'SummonGeometry.projectedOffset',
                'SummonGeometry.summon', 'SummonGeometry.hasMomentum'];
  return used.filter((u) => !src.includes(u));
}

// ---------- 自检：尺子自己必须被验 ----------
function selfTest() {
  const p = [];
  const md = fs.readFileSync(CORE, 'utf8');
  const swift = fs.readFileSync(SWIFT, 'utf8');
  // 正控：把文档里的 LIMIT 改掉，锚点检查必须报出来
  if (anchors(md.replace('| 196 |', '| 190 |')).length === 0) p.push('自检失败: 文档里 LIMIT 被改掉却没被锚点检查抓到 (正控失效)');
  if (anchors(md).length !== 0) p.push('自检失败: 未改的文档报了锚点缺失 (反控失效)');
  // 正控 2：把 Swift 里的橡皮筋公式改掉，公式检查必须报出来
  if (swiftProblems(swift.replace('over * dim * c / (dim + c * over)', 'over * 0.5')).length === 0) {
    p.push('自检失败: 橡皮筋公式被改掉却没被抓到 (正控 2 失效)');
  }
  if (swiftProblems(swift).length !== 0) p.push('自检失败: 未改的 Swift 报了公式缺失 (反控 2 失效)');
  // 正控 3：算术表本身必须能判负 —— 故意歪一个数
  if (near(project(1000), 98, 0.01)) p.push('自检失败: 期望表判不出偏差 (正控 3 失效)');
  return p;
}

// ---------- 跑 ----------
function main() {
  const selftest = process.argv.includes('--selftest');
  const swift = fs.readFileSync(SWIFT, 'utf8');
  const roots = fs.readFileSync(ROOTS, 'utf8');
  const md = fs.readFileSync(CORE, 'utf8');

  const bad = CHECKS.filter((c) => !c.ok);
  console.log(`拖拽召唤 · 纯几何影子对拍 (${CHECKS.length} 条)`);
  bad.forEach((c) => console.log(`  FAIL  ${c.name}${c.detail ? '   ← ' + c.detail : ''}`));
  if (!bad.length) console.log('  · 轨道位 / 1:1 跟手 / 橡皮筋 / 动量投影 / 命中判据 / 动量交接 / 三光点坐标 全部与期望一致');

  const a = anchors(md);
  console.log('');
  if (a.length) a.forEach((x) => console.log(`  FAIL  设计文档 CORE.md §2 里找不到: ${x} —— 常数与文档脱钩了`));
  else console.log(`  · 防漂移: CORE.md §2 的 11 个锚点 (LIMIT / c / d / 钳位 / HOME / RIDE / scale / 三光点 / CHARGE) 全部在场`);

  const s = swiftProblems(swift);
  if (s.length) s.forEach((x) => console.log(`  FAIL  SummonGeometry.swift 里的${x}不是文档那把式子 —— 改了一侧没改另一侧`));
  else console.log('  · 公式: 橡皮筋 / project / LIMIT 比例 / 命中半径 四条式子逐字在场');

  const w = wiredProblems(roots);
  console.log('');
  if (w.length) w.forEach((x) => console.log(`  FAIL  ${x} 没有调用点 —— 纯函数没人用就是死代码，不是实现`));
  else console.log('  · 接线: 5 个几何入口在 VariantRoots.swift 里都有调用点');

  const st = selfTest();
  console.log('');
  if (st.length) st.forEach((x) => console.log('!! ' + x));
  else console.log('尺子自检: 正控 3 (改文档 LIMIT / 改 Swift 公式 / 歪一个期望值) 全部报出，反控 2 全部不报 → 通过');

  const fail = bad.length > 0 || a.length > 0 || s.length > 0 || w.length > 0 || st.length > 0;
  console.log('');
  console.log(fail ? '结论: 判失败' : '结论: 通过 (纯几何；形变/跟手感/弹簧观感未被执行过)');
  // 退出码三档：0 通过 / 1 判失败 / 2 尺子坏了（与 uicoverage 同一口径）
  process.exit(selftest ? (st.length ? 2 : 0) : fail ? 1 : 0);
}
try {
  main();
} catch (e) {
  console.log('!! 闸门自身异常: ' + ((e && e.stack) ? String(e.stack).split('\n')[0] : String(e)));
  console.log('→ 这是**尺子坏了**，不是代码不合格。上面所有结论作废。');
  process.exit(2);
}
