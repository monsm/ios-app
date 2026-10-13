#!/usr/bin/env node
// tools/typepred.js — 「同一类日志类型被写了两遍」对账（第一百五十七批新增，**顾问级、不判失败**）
//
// 键面/锁面之外还有一族"同一个口径两处定义"：**日志类型分类**。
// 协议里告警只有 5 类 (CAPABILITY.md:61 —— 6 电量低 / 7 撬锁 / 10 试错锁定 / 13 指纹告警 / 224 键盘锁定)，
// 代码里canonical 的那份是 `StatsKit.alarmTypes` 与 `openTypes`。但"哪些算告警"这件事还会以别的形式再出现：
//   ① 手写 `type == 7 || type == 13 || …` 的或链 —— 第一百五十七批就是在设备页抓到一条只圈了 3/5 类的，
//      于是低电量与试错锁定的告警在设备页不标红，而同一条记录在告警中心、统计、导出里都算告警；
//   ② 同一个字面量集合在两个文件里各 `static let` 一份 (`openTypes`/`alarmTypes` 曾各抄一份，值相同) ——
//      值相同只说明**还没漂**，不说明会一起改；
//   ③ 定级表 (`AlarmMeta.urgent ∪ serious ∪ info`) 与 canonical 集合的并集是否还相等 ——
//      这条今天是成立的，但没有任何东西保证下一次加一类告警时有人两边都改。
// 三档都只**报线索**：这些都不是类型错误，编译器看不见，而人也只在"两处数字对不上"时才看得见。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
function swiftFiles(d, out = []) {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) swiftFiles(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}
const files = swiftFiles(path.join(ROOT, 'App'));
const strip = (l) => l.replace(/\/\/.*$/, '');

// ---------- canonical 集合：从 StatsKit.swift 现场读，不写死在工具里 ----------
let canon = { alarm: null, open: null };
for (const f of files) {
  if (!f.endsWith('StatsKit.swift')) continue;
  const s = fs.readFileSync(f, 'utf8');
  const a = /static let alarmTypes\s*:\s*Set<Int>\s*=\s*\[([0-9,\s]+)\]/.exec(s);
  const o = /static let openTypes\s*:\s*Set<Int>\s*=\s*\[([0-9,\s]+)\]/.exec(s);
  if (a) canon.alarm = new Set(a[1].split(',').map(x => parseInt(x.trim(), 10)).filter(x => !Number.isNaN(x)));
  if (o) canon.open = new Set(o[1].split(',').map(x => parseInt(x.trim(), 10)).filter(x => !Number.isNaN(x)));
}
if (!canon.alarm) { console.log('找不到 StatsKit.alarmTypes —— 本档判据失效，先看 canonical 声明有没有改名'); process.exit(0); }
const key = (s) => [...s].sort((a, b) => a - b).join(',');
const rows = { chain: [], dup: [], level: [] };

// ---------- ① 手写 `type == N || …` 或链 ----------
const CHAIN = /(?:\w*\.?type|l\.type|e\.type|rec\.type)\s*==\s*(\d+)((?:\s*\|\|\s*(?:[\w.]*\.)?type\s*==\s*\d+)+)?/g;
for (const f of files) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((raw, i) => {
    const ln = strip(raw);
    let m;
    CHAIN.lastIndex = 0;
    while ((m = CHAIN.exec(ln))) {
      if (!m[2]) continue;                                   // 单一类型判断是正当的 (1023 连续三条 type 13 那种)
      const nums = (m[1] + m[2]).match(/\d+/g).map(Number);
      const set = new Set(nums);
      const rel = path.relative(ROOT, f).replace(/\\/g, '/') + ':' + (i + 1);
      // 先分族：这条或链整体落在告警类里，还是落在开门类里？两族各有 canonical。
      const allAlarm = [...set].every(x => canon.alarm.has(x));
      const allOpen = canon.open ? [...set].every(x => canon.open.has(x)) : false;
      let verdict;
      if (allAlarm && key(set) === key(canon.alarm)) verdict = '与 alarmTypes 同值 ⇒ 该写 StatsKit.alarmTypes (抄两份迟早漂)';
      else if (allAlarm) verdict = `**alarmTypes 的子集 (少 ${[...canon.alarm].filter(x => !set.has(x)).join('/')}) ⇒ 这几类在这条路径上不当告警处理**`;
      else if (allOpen && key(set) === key(canon.open)) verdict = '与 openTypes 同值 ⇒ 该写 StatsKit.openTypes';
      else if (allOpen) verdict = `开门类的子集 (只圈 ${key(set)} / ${key(canon.open)}) ⇒ 人读：这条是否本就该只看这几类 (如 2 指纹 / 4 密码)`;
      else verdict = `跨族或含未知类型 {${key(set)}} —— 对照 CAPABILITY.md:61 的日志类型表逐条读`;
      rows.chain.push(`  ${rel}  {${key(set)}}  ${verdict}`);
    }
  });
}

// ---------- ② 同一个字面量集合被抄在多份 ----------
const defs = new Map();
for (const f of files) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((raw, i) => {
    const one = /static let (openTypes|alarmTypes)\s*:\s*Set<Int>\s*=\s*\[([0-9,\s]+)\]/.exec(strip(raw));
    if (!one) return;
    const set = new Set(one[2].split(',').map(x => parseInt(x, 10)).filter(x => !Number.isNaN(x)));
    const k = one[1] + '{' + key(set) + '}';
    if (!defs.has(k)) defs.set(k, []);
    defs.get(k).push(path.relative(ROOT, f).replace(/\\/g, '/') + ':' + (i + 1));
  });
}
for (const [k, v] of defs) if (v.length > 1) rows.dup.push(`  ${k} 被 ${v.length} 份各自 static let: ${v.join(' , ')}`);

// ---------- ③ 定级表并集 vs canonical ----------
const lv = { urgent: null, serious: null, info: null };
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8');
  for (const n of ['urgent', 'serious', 'info']) {
    const m = new RegExp('static let ' + n + '\\s*:\\s*Set<Int>\\s*=\\s*\\[([0-9,\\s]+)\\]').exec(s);
    if (m) lv[n] = new Set(m[1].split(',').map(x => parseInt(x, 10)).filter(x => !Number.isNaN(x)));
  }
}
if (lv.urgent && lv.serious && lv.info) {
  const union = new Set([...lv.urgent, ...lv.serious, ...lv.info]);
  if (key(union) !== key(canon.alarm)) {
    rows.level.push(`  AlarmMeta 三级并集 {${key(union)}} ≠ StatsKit.alarmTypes {${key(canon.alarm)}} ⇒ `
      + `少 ${[...canon.alarm].filter(x => !union.has(x)).join('/') || '无'} / 多 ${[...union].filter(x => !canon.alarm.has(x)).join('/') || '无'} —— 定级与"算不算告警"从此两样`);
  }
}

const n = rows.chain.length + rows.dup.length + rows.level.length;
console.log(`日志类型分类对账 (顾问级, 不判失败) · canonical: alarmTypes={${key(canon.alarm)}} openTypes={${key(canon.open || new Set())}} · 线索 ${n} 条`);
if (rows.chain.length) { console.log('【① 手写类型或链 ⇒ 该引用集合而非再抄一遍】'); console.log(rows.chain.join('\n')); }
if (rows.dup.length) { console.log('【② 同一个集合多份 static let】'); console.log(rows.dup.join('\n')); }
if (rows.level.length) { console.log('【③ 定级表并集 ≠ canonical】'); console.log(rows.level.join('\n')); }
if (!n) console.log('三档都干净 —— 但这只证明"此刻两处一致"，加一类告警时这一道会先响。');
