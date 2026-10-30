#!/usr/bin/env node
// tools/autoopenshadow.js — AUTOOPEN 纯函数的**影子对拍** (第一百七十一批新增，判失败)
//
// 为什么要有它：本仓从未跑过 XCTest (无 Xcode/模拟器，CI 只 build-for-testing，见 §10.2)，
// 于是 `Tests/AUTOOPENTests.swift` 里 4 条断言与实现相反、整张 defendActive 表因 helper 少除一个 2 而全错，
// 挂了几个月没人看见 (§10.43)。这一支把同样的期望值用**另一门语言**再算一遍：
// 六个纯函数按 Swift 源码逐行复刻，期望表逐条誊自 Swift 测试 ——
// 两边任何一侧改了语义而另一侧没跟上，这里就红。
//
// ⚠ 它证明的边界要照实说：只有这六个纯函数的算术。
//   `AutoOpenController` 的时序、BLE 回调、LAContext 真弹窗、标定页交互 —— 一行都没执行过。
//   "影子对拍通过"永远不等于"测试跑过了"。
const assert = require('assert');
const log10 = Math.log10, round = Math.round, floor = Math.floor, ceil = Math.ceil;

// ---------- 复刻 AutoOpenKit 的六个纯函数 (逐行对照 Swift) ----------
// Swift: secOfDay = ((h*3600 + m*60 + s) * 2)；startSec/endSec 与它同尺 (半秒刻度)
function defendActive(control, startSec, endSec, secOfDayReal) {
  if (control !== 2) return false;
  if (startSec === endSec) return true;                    // 全天布防 (fail-closed)
  const secOfDay = secOfDayReal * 2;
  if (startSec < endSec) return secOfDay >= startSec && secOfDay < endSec;
  return secOfDay >= startSec || secOfDay < endSec;
}
// Swift: guard let v = tier; isStrict = tier != 0 —— 非 0 的任何档都按最严的解释
const isStrict = (tier) => tier !== 0;
// ages 单位: 距今年秒; lastFaceAge = -1 表示 nil；strictSinceAge = -1 表示 nil
function faceFresh(tier, lastFaceAge, pendingPrompt, strictSinceAge) {
  // 与 Swift 同语义 (2026-10-17 用户口径): 0 = 免额外验证 ⇒ 放行; 非 0 = 严格 ⇒ 必须本次进前台刷过脸。
  // 旧影子跑 "0 = 60 秒复用窗", 那是把 iOS 自己的死门当成正确行为 —— iOS 没有静默生物识别,
  // 没人主动刷脸就 lastFace 恒 nil ⇒ 恒拒 ⇒ "iOS 从来不会自动解锁"。影子跟着测它只会把谎测得自洽。
  if (!isStrict(tier)) return true;
  if (pendingPrompt) return true;
  if (lastFaceAge < 0 || strictSinceAge < 0) return false;
  return lastFaceAge <= strictSinceAge;                  // Swift: lf >= since
}
const armThreshold = (base) => base;
// Swift: Int((Double(base) + 10 * log10(0.5)).rounded())
const disarmThreshold = (base) => round(base + 10 * log10(0.5));
function rssiSample(prevArmed, rssi, base) {
  return prevArmed ? rssi > disarmThreshold(base) : rssi >= armThreshold(base);
}

// 2026-10-31（第 24 轮，**闸门测错对象**）：Swift 侧 `feedRssi` 自第 13 轮起已改调
// `AutoOpenKit.rssiArmedByMedian`（3 样本中值），而本影子仍在测旧的单样本 `rssiSample`
// —— 等于"验的不是线上那行代码"。这里补上中值复刻，并把 F3 用例改测它。
// 逐行对齐 Swift:
//   guard let cur = history.first else { return prevArmed }
//   if prevArmed, cur <= disarm { return false }
//   let med = history.prefix(3).sorted()[count/2]
//   return prevArmed ? med > disarm : med >= arm
function rssiArmedByMedian(prevArmed, history, base) {
  if (history.length === 0) return prevArmed;
  const arm = armThreshold(base);
  const disarm = disarmThreshold(base);
  const cur = history[0];                          // 最新在前
  if (prevArmed && cur <= disarm) return false;     // 解除走单样本（走开要快）
  const win = history.slice(0, 3).slice().sort((a, b) => a - b);
  const med = win[Math.floor(win.length / 2)];
  return prevArmed ? med > disarm : med >= arm;
}
function p95(samples) {
  if (samples.length < 5) return null;
  const a = [...samples].sort((x, y) => x - y);
  const rank = (a.length - 1) * 0.95;
  const lo = floor(rank), hi = ceil(rank), frac = rank - lo;
  if (lo === hi) return a[lo];
  return round(a[lo] + (a[hi] - a[lo]) * frac);
}
// 测试 helper: utc(dayTick) = 基准日 + tick/2 秒  (形参曾是 daySecond —— 那正是 §10.43 那个谎)
const tickToRealSec = (tick) => tick / 2;

// ---------- 期望表 (逐条对应 Tests/AUTOOPENTests.swift) ----------
const W = 44 * 3600, E = 12 * 3600;            // 22:00 → 06:00 (半秒刻度)
const CASES = [];
const push = (group, name, got, want) => CASES.push({ group, name, got, want });

// F4 defendActive 表
push('F4', 'control=0 不拒', defendActive(0, W, E, tickToRealSec(17 * 3600)), false);
push('F4', 'control=1 不拒', defendActive(1, W, E, tickToRealSec(17 * 3600)), false);
push('F4', 'control=3 不拒', defendActive(3, W, E, tickToRealSec(17 * 3600)), false);
push('F4', '22:00 起点含', defendActive(2, W, E, tickToRealSec(44 * 3600)), true);
push('F4', '23:00 中间点', defendActive(2, W, E, tickToRealSec(46 * 3600)), true);
push('F4', '00:00 下半段', defendActive(2, W, E, tickToRealSec(0)), true);
push('F4', '05:59:59 末秒含', defendActive(2, W, E, tickToRealSec(12 * 3600 - 1)), true);
push('F4', '06:00 终点不含', defendActive(2, W, E, tickToRealSec(12 * 3600)), false);
push('F4', '06:30 窗外', defendActive(2, W, E, tickToRealSec(13 * 3600)), false);
push('F4', '08-10 内 08:30', defendActive(2, 16 * 3600, 20 * 3600, tickToRealSec(17 * 3600)), true);
push('F4', '07:30 前', defendActive(2, 16 * 3600, 20 * 3600, tickToRealSec(15 * 3600)), false);
push('F4', '10:30 后', defendActive(2, 16 * 3600, 20 * 3600, tickToRealSec(21 * 3600)), false);
push('F4', 'start==end 全天布防', defendActive(2, 12 * 3600, 12 * 3600, tickToRealSec(12 * 3600)), true);
push('F4', 'start==end 换个时刻也布防', defendActive(2, 12 * 3600, 12 * 3600, tickToRealSec(2 * 3600)), true);
push('F4', '23:00→06:00 起点', defendActive(2, 46 * 3600, E, tickToRealSec(46 * 3600)), true);
push('F4', '23:00→06:00 终点', defendActive(2, 46 * 3600, E, tickToRealSec(12 * 3600)), false);

// F1 faceFresh: 标准档 60s / 严格档 0 窗口 / 档位漂移
  push('F1', '默认档 无面容记录 放行', faceFresh(0, -1, false, -1), true);
  push('F1', '默认档 脸2s 放行', faceFresh(0, 2, false, -1), true);
  push('F1', '默认档 脸60s 仍放行 (不吃时间窗)', faceFresh(0, 60, false, -1), true);
  push('F1', '默认档 弹窗在途也放行', faceFresh(0, -1, true, -1), true);
push('F1', '严格 t59 无 since 拒', faceFresh(1, 59, false, -1), false);
push('F1', '严格 t59 早于 since 拒', faceFresh(1, 59, false, 10), false);
push('F1', '严格 脸2s/since10s 过', faceFresh(1, 2, false, 10), true);
push('F1', '严格 nil+弹窗 放行', faceFresh(1, -1, true, -1), true);
push('F1', '严格 nil 无弹窗 拒', faceFresh(1, -1, false, -1), false);
push('F1', '未知档 7 不吃 60s 窗', faceFresh(7, 59, false, -1), false);
push('F1', '未知档 7 弹窗在途放行', faceFresh(7, -1, true, -1), true);

// F3 回差 (基准 -60 ⇒ 武装线 -60, 解除线 -63)
push('F3', 'arm(-60)', armThreshold(-60), -60);
push('F3', 'disarm(-60) ≈ -63', disarmThreshold(-60), -63);
push('F3', '未武装 恰在武装线', rssiArmedByMedian(false, [-60], -60), true);
push('F3', '未武装 差一格', rssiArmedByMedian(false, [-61], -60), false);
push('F3', '已武装 回差带内保持', rssiArmedByMedian(true, [-62], -60), true);
push('F3', '已武装 恰在解除线解除', rssiArmedByMedian(true, [-63], -60), false);
push('F3', '已武装 更低解除', rssiArmedByMedian(true, [-64], -60), false);
push('F3', '解除后带内需重新越过武装线', rssiArmedByMedian(false, [-62], -60), false);
push('F3', '远处 -80 不武装', rssiArmedByMedian(false, [-80], -60), false);
push('F3', '比标定近 -55 武装', rssiArmedByMedian(false, [-55], -60), true);
push('F3', '近处 -40 武装', rssiArmedByMedian(false, [-40], -60), true);
push('F3', '已武装微抖 -41 保持', rssiArmedByMedian(true, [-41], -60), true);

// 2026-10-31（第 24 轮）：**中值专属用例** —— 单样本等价于 1 元素窗（上面已覆盖），
// 这几条测的是「3 样本窗如何吃掉尖峰」，那正是第 13 轮改中值的理由。
// 基准 -60 ⇒ 武装线 -60，解除线 -63。
push('F3', '尖峰打断不武装 (样本 -80,-59,-58 → 中值 -59 达线 ⇒ 武装)', rssiArmedByMedian(false, [-80, -59, -58], -60), true);
push('F3', '两个尖峰才拦住 (样本 -80,-80,-58 → 中值 -80 ⇒ 不武装)', rssiArmedByMedian(false, [-80, -80, -58], -60), false);
push('F3', '已武装 中值在带内维持 (样本 -58,-62,-70 → 中值 -62 > -63 ⇒ 保持)', rssiArmedByMedian(true, [-58, -62, -70], -60), true);
push('F3', '已武装 cur 跌破解除线立刻解除 (不看中值)', rssiArmedByMedian(true, [-64, -40, -40], -60), false);
push('F3', '空窗返回原态 (不发明数据)', rssiArmedByMedian(false, [], -60), false);
push('F3', '单样本 -60 恰在武装线 ⇒ 武装', rssiArmedByMedian(false, [-60], -60), true);

// F3 P95
push('P95', '样本不足 = nil', p95([-60, -58, -55, -62]), null);
push('P95', '全同 -60', p95(Array(100).fill(-60)), -60);
push('P95', '95 个 -60 + 5 个 -50', p95([...Array(95).fill(-60), ...Array(5).fill(-50)]), -60);

// 反向不变式: 这套影子必须真的会响 —— 若复刻与 Swift 漂开，期望表要红
assert.notStrictEqual(defendActive(2, 12 * 3600, 12 * 3600, 21600), false, '影子自检: start==end 已改成全天布防');
assert.notStrictEqual(faceFresh(1, 59, false, -1), true, '影子自检: 严格档不再吃 60s 窗');
assert.strictEqual(faceFresh(0, -1, false, -1), true, '影子自检: 默认档无面容也必须放行 (否则 iOS 自动开锁还是死的)');

let bad = 0;   // 也供下面的"与 Swift 源码对钉"累加
for (const c of CASES) {
  let ok = true;
  try { assert.deepStrictEqual(c.got, c.want); } catch (e) { ok = false; }
  if (!ok) { bad++; console.log(`✗ ${c.group} ${c.name}  期望=${c.want} 影子算出=${c.got}`); }
}
// ---------- 与 Swift 源码对钉 ----------
// 上面测的是 JS 复刻。JS 与 Swift 各自改了才红, 一起改错就一路绿 ——
// 本轮真实踩过 (JS 改了阈值/Swift 没改, 影子全绿而功能仍是死的)。
// 所以把"最要命的几个口径"直接钉在 AutoOpen.swift 的文本上: 漂移当场红灯。
{
  const fs2 = require("fs"), path2 = require("path");
  const swiftPath = path2.join(__dirname, "..", "App", "Core", "AutoOpen.swift");
  const swift = fs2.readFileSync(swiftPath, "utf8").replace(/\r\n/g, "\n");
  const must = [
    [/if !isStrict\(tier\) \{ return true \}/, "F1 默认档直接放行 (iOS 无静默生物识别, 旧写法恒拒=自动开锁死门)"],
    [/static let fallbackBase = -40/, "F3 未标定退回 -40 (与安卓 AutoOpenKit.BASE 同值)"],
    [/static let cooldownSeconds: TimeInterval = 6/, "F5 冷却 6s (用户口径: 开完锁等 6 秒恢复)"],
    [/d\?\.control \?\? 0/, "F4 无布防记忆读成不布防 (旧 ?? 2 会永久否决没配过的人)"],
  ];
  for (const [re, why] of must) {
    if (!re.test(swift)) { bad++; console.log("✗ Swift 源码漂移: " + why); }
  }
  if (/guard calibrated else \{ return \.f3nocal \}/.test(swift)) {
    bad++; console.log("✗ Swift 源码漂移: F3 仍把「未标定」当硬门 → fallbackBase 白改, 新用户永远开不了");
  }
  if (!/func readLinkRSSI/.test(fs2.readFileSync(path2.join(__dirname, "..", "App", "Services", "BLEService.swift"), "utf8"))) {
    bad++; console.log("✗ Swift 源码漂移: BLEService 没有连接层测距 → 连上锁之后没有 RSSI 样本, armed 回不来");
  }
}
// REPLICA_GUARD —— 2026-10-31（第 26 轮，结构性改进）：
//
// 本文件是 Swift `AutoOpenKit` 的 **JS 复刻**。复刻与实现是两个真相来源，会漂：
// 第 13 轮把 Swift 的 `feedRssi` 改成调 `rssiArmedByMedian`，而这里仍在测旧的
// `rssiSample` —— 闸门输出 ✓，验的却是历史代码。那种"假安心"比没有闸门更危险。
//
// 存在性自检：凡断言里测的函数名，必须在 Swift 源码里找得到。
// 实现改名/删除时立刻红，而不是静默继续测旧代码。
{
  const REPLICATED = ["faceFresh", "defendActive", "armThreshold", "disarmThreshold",
                      "rssiSample", "rssiArmedByMedian", "p95"];
  const _fs = require("fs");
  const _path = require("path");
  const SWIFT_SRC = _fs.readFileSync(_path.join(__dirname, "..", "App", "Core", "AutoOpen.swift"), "utf8");
  const missing = REPLICATED.filter(fn => !new RegExp("func\\s+" + fn + "\\s*\\(").test(SWIFT_SRC));
  if (missing.length) {
    bad++;
    console.log("✗ REPLICA_GUARD: 以下函数在 App/Core/AutoOpen.swift 里已不存在 — " + missing.join(", "));
    console.log("  本影子的复刻与实现已漂开，先更新复刻再谈对拍。");
  } else {
    console.log("ok    REPLICA_GUARD 复刻的 " + REPLICATED.length + " 个函数在 Swift 源码里都存在");
  }
}

const total = CASES.length;
console.log(`AUTOOPEN 影子对拍: ${total - bad}/${total} 条与 Swift 期望表一致`
  + (bad ? ` ⇒ ✗ ${bad} 条漂开 (改一侧时另一侧要跟上；或复刻本身与 Swift 源码不符)` : ' ✓'));
console.log('边界: 只覆盖六个纯函数的算术。XCTest 仍未执行过，控制器/BLE/LAContext 一行都没跑。');
process.exit(bad ? 1 : 0);
