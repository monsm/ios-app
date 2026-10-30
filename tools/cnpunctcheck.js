#!/usr/bin/env node
// cnpunctcheck —— 用户文案里的**中文标点**闸门。
//
// 为什么需要它：第 102 轮扫出 2 处中文句子用了半角句点：
//   "连接失败， 可能离门太远. \(reason)"              ← AccessibilityKit
//   "轻点两下直接开锁， 无需按住. 转子上下滑可切换…"   ← UnlockDial
// 两处都是 VoiceOver 朗读的文案 —— 半角句点会让朗读节奏错（读成"点"或不停顿）。
//
// 判据（保守，只报高置信度）：字符串字面量里「中文字符紧跟半角 `.` 或 `,`」，
// 且后面不是数字（排除 `版本 1.2` / `偏差 0.5` 这类小数）。
//
// 已知局限：
//   · 只扫 `"…"` 双引号字面量（本仓用户文案一律双引号）；
//   · 不判全角括号/冒号/感叹号（那些在本仓混用是**有意的**：
//     半角括号用于技术标识如 `(6 秒)` `(rc=25)`，全角用于叙述）；
//   · 不扫注释（注释里的半角标点是工程习惯，不是用户可见文案）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const hits = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    L.forEach((l, i) => {
      const code = l.replace(/\/\/.*$/, '');
      const strs = code.match(/"[^"]{4,}"/g) || [];
      for (const s of strs) {
        // 中文后紧跟半角句点/逗号，且后面不是数字
        if (/[\u4e00-\u9fa5][.,]/.test(s) && !/[\u4e00-\u9fa5][.,]\d/.test(s)) {
          hits.push({ loc: `${d}/${f}:${i + 1}`, text: s.slice(0, 90) });
        }
      }
    });
  }
}

if (hits.length) {
  console.log(`✗ 用户文案里中文后面用了半角标点 ${hits.length} 处：`);
  for (const h of hits) console.log(`  ${h.loc}\n      ${h.text}`);
  console.log('\n修法：中文句末用「。」、句中停顿用「，」。');
  process.exit(1);
}
console.log('✓ 用户文案的中文标点统一（中文后不用半角句点/逗号）');
