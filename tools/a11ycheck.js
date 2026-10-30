#!/usr/bin/env node
// a11ycheck —— VoiceOver 可访问性闸门。
//
// 2026-10-30 新增（第 107 轮）：本轮修掉 5 处「有 .onTapGesture 但没有 accessibilityAction」——
// 那对读屏用户是**看得见、点不动**：VoiceOver 的双击走"默认动作"，而默认动作没定义。
// 更糟的是其中两处还写了 `accessibilityHint` 说"查看这位成员的记录"/"双击切大字号"，
// 提示成了空话 —— 比没提示更坏，因为它承诺了一个做不到的交互。
//
// 判据分两档：
//   A2（**硬闸门**）：`.onTapGesture` 所在段必须有 `accessibilityAction` / `accessibilityAddTraits` /
//                      或外层是 Button。→ 命中即 exit 1。
//   A1（**只报线索**）：`Image(systemName:)` 既没 accessibilityHidden 也没 accessibilityLabel。
//                      装饰性图标该隐藏、功能图标该给标签，但"这个图标是装饰还是功能"
//                      静态判断不了（同一个 systemName 在不同上下文角色不同），
//                      所以这一档只提示，不判失败。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];
const strip = (s) => s.replace(/\/\/[^\n]*/g, '');

const hard = [];   // A2
const soft = [];   // A1

for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = `${d}/${f}`;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);

    for (let i = 0; i < L.length; i++) {
      const code = strip(L[i]);

      if (/Image\s*\(\s*systemName:/.test(code)) {
        const win = strip(L.slice(i, i + 7).join('\n'));
        if (!/accessibilityHidden|accessibilityLabel|accessibilityElement/.test(win)) {
          soft.push(`${rel}:${i + 1}  ${code.trim().slice(0, 70)}`);
        }
      }

      if (/\.onTapGesture/.test(code)) {
        // 2026-10-30（第 107 轮，正控三次才定稿）：
        //   ① 只看后 6 行 → 漏报（修饰符可能写在前）；
        //   ② 前后各看 8 行 → 把相邻元素的修饰符算进来（正控注入时被上一个元素放过）；
        //   ③ 只走「以 . 开头的连续行」→ 遇到多行闭包就断（`{` 那行之后的 `guard …` 不以 . 开头）。
        // 正解：从手势行起**按括号深度**吞掉它的闭包，之后继续吃以 `.` 开头的修饰符行；
        //       向上同理，但要跳过注释与多行闭包内部的非 . 行 —— 向上只吃紧邻的 `.` 行即可
        //       （本仓 a11y 修饰符从不写在多行闭包"里面"）。
        const isMod = (s) => /^\s*\./.test(s);
        const isComment = (s) => /^\s*\/\//.test(s);
        const braces = (s) => {
          let d = 0;
          for (const ch of s.replace(/\/\/.*$/, '')) { if (ch === '{') d++; else if (ch === '}') d--; }
          return d;
        };

        let lo = i;
        for (let k = lo - 1; k >= 0; k--) {
          if (isComment(L[k])) { lo = k; continue; }
          if (isMod(L[k])) { lo = k; continue; }
          break;
        }

        let hi = i, depth = 0;
        for (let k = i; k < L.length; k++) {
          depth += braces(L[k]);
          hi = k;
          if (depth <= 0) {
            // 闭包结束 → 继续吃后续修饰符/注释行（每条也可能带闭包，同样按深度吞）
            let k2 = k + 1;
            while (k2 < L.length && (isMod(L[k2]) || isComment(L[k2]))) {
              hi = k2;
              if (isMod(L[k2])) {
                let d2 = braces(L[k2]);
                while (d2 > 0 && k2 + 1 < L.length) { k2++; hi = k2; d2 += braces(L[k2]); }
              }
              k2++;
            }
            break;
          }
        }

        const win = strip(L.slice(lo, hi + 1).join('\n'));
        if (!/accessibilityAction|accessibilityAddTraits|accessibilityElement|accessibilityHidden/.test(win)) {
          hard.push(`${rel}:${i + 1}  ${code.trim().slice(0, 70)}`);
        }
      }
    }
  }
}

// A3（硬闸门）：同一条修饰符链上出现 ≥2 个 `.accessibilityLabel` —— **后者覆盖前者**，
// 前一个是死代码。2026-10-30（第 113 轮）在 CredentialActions 的搜索框上实测到：
// 带「键盘 Cmd/Control+F」的那句被下面那句「凭证搜索」覆盖，快捷键提示从来没被读过。
const dupLabel = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = `${d}/${f}`;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    // 按「连续以 . 开头的行 + 夹在中间的注释」聚成一条链
    let chain = [], start = 0;
    const flush = () => {
      const labels = chain.filter(x => /^\s*\.accessibilityLabel\s*\(/.test(x));
      if (labels.length >= 2) {
        dupLabel.push(`${rel}:${start + 1}  同链 ${labels.length} 个 accessibilityLabel（后写的覆盖前面的）`);
      }
      chain = [];
    };
    for (let i = 0; i < L.length; i++) {
      const line = L[i];
      const isMod = /^\s*\./.test(line);
      const isComment = /^\s*\/\//.test(line) || line.trim() === '';
      if (isMod || (isComment && chain.length)) {
        if (!chain.length) start = i;
        chain.push(line);
      } else {
        flush();
      }
    }
    flush();
  }
}

if (dupLabel.length) {
  console.log(`✗ 同一条修饰符链上重复 accessibilityLabel ${dupLabel.length} 处：`);
  dupLabel.forEach(x => console.log('  ' + x));
  console.log('\n修法：合并成一条（后写的会覆盖前面的，前面那句是死代码）。');
  process.exit(1);
}

if (soft.length) {
  console.log(`【线索】Image(systemName:) 无 a11y 标注 ${soft.length} 处（装饰性应 hidden、功能性应 label）:`);
  soft.slice(0, 15).forEach(x => console.log('  ' + x));
  if (soft.length > 15) console.log(`  …还有 ${soft.length - 15} 处`);
  console.log('');
}

if (hard.length) {
  console.log(`✗ 可点区域对 VoiceOver 不可激活 ${hard.length} 处（有 .onTapGesture 但无 accessibilityAction）:`);
  hard.forEach(x => console.log('  ' + x));
  console.log('\n修法：补 `.accessibilityAddTraits(.isButton)` + `.accessibilityAction { …同一段逻辑… }`。');
  console.log('判据：手势能做到的事，读屏用户也必须能做到 —— 否则等于对这部分用户删掉了功能。');
  process.exit(1);
}

console.log(`✓ 可点区域全部对 VoiceOver 可激活（0 处）${soft.length ? `；另有 ${soft.length} 处装饰图标线索` : ''}`);
