#!/usr/bin/env node
// workflow.js —— GitHub Actions 工作流结构闸门。
//
// 为什么需要它：2026-10-31 连着两次 run 秒红，报「Invalid workflow file」。
// 根因是 `--notes "..."` 字符串里有一个**未缩进的换行** —— YAML 把下一行当成新的键，
// 整份文档判为非法。这类错 CI 只会告诉你 invalid，不告诉你在哪，且本地无感知。
//
// 判什么：
//   ① 文件里不许有 TAB（YAML 禁止）
//   ② `run: |` 块内每一行的缩进必须**大于**该 run 键的缩进（裸换行会掉到 0）
//   ③ 顶层必须只有 name / on / permissions / defaults / jobs 这些已知键
//   ④ README / 工作流 / 架构 / 完成度 / 覆盖表里声称的**闸门数**必须等于 allgates.js 的真实数量
//   ⑤ 界面「数字承诺」与它的**代码锚点**必须同时存在（任一侧被改就红，逼人重新核对）
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FILES = [
  path.join(ROOT, '..', '.github', 'workflows', 'ios27.yml'),
];

const findings = [];
let checked = 0;

for (const f of FILES) {
  if (!fs.existsSync(f)) continue;
  checked++;
  const rel = path.basename(f);
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);

  lines.forEach((line, i) => {
    if (line.includes('\t')) findings.push(rel + ':' + (i + 1) + ' 含 TAB（YAML 禁止）');
  });

  // ② run: | 块缩进
  for (let i = 0; i < lines.length; i++) {
    const m = /^(\s*)(- )?run:\s*\|\s*$/.exec(lines[i]);
    if (!m) continue;
    const baseIndent = m[1].length + (m[2] ? 2 : 0);
    for (let j = i + 1; j < lines.length; j++) {
      const line = lines[j];
      if (line.trim() === '') continue;
      const indent = line.length - line.trimStart().length;
      // 回到同级或更浅 = run 块结束
      if (indent <= baseIndent - (m[2] ? 2 : 0)) break;
      if (indent <= baseIndent) {
        findings.push(rel + ':' + (j + 1) + ' run 块里的行缩进不足（疑似裸换行截断文档）: ' + line.trim().slice(0, 60));
        break;
      }
    }
  }

  // ③ 顶层键白名单
  const ALLOW = new Set(['name', 'on', 'permissions', 'defaults', 'jobs', 'env', 'concurrency', 'run-name']);
  lines.forEach((line, i) => {
    const m = /^([A-Za-z_][\w-]*):/.exec(line);
    if (m && !ALLOW.has(m[1])) findings.push(rel + ':' + (i + 1) + ' 未知顶层键 ' + m[1]);
  });
}


// ④ README / 工作流里声称的闸门数，必须等于 allgates.js 真实的 GATES 数量。
// 这条是被真实事故逼出来的：README 曾写「9 道」「16 道」而实际已经 20 道；
// 另有一处把钉死的 run 号当成当前状态（见 AUDIT-G 的 G-05）。
{
  const ag = fs.readFileSync(path.join(__dirname, 'allgates.js'), 'utf8');
  const gm = ag.match(/const GATES = \[([^\]]*)\]/);
  if (gm) {
    const real = gm[1].split(",").filter(function (x) { return x.trim(); }).length;
    const CN = { "九": 9, "十一": 11, "十二": 12, "十三": 13, "十四": 14, "十五": 15, "十六": 16, "十七": 17, "十八": 18, "十九": 19, "二十": 20, "二十一": 21, "二十二": 22 };
    const targets = [
      [path.join(ROOT, 'README.md'), /## ([一-鿿0-9]+)\s*道机器闸门/],
      [path.join(ROOT, '..', '.github', 'workflows', 'ios27.yml'), /静态闸门（([一-鿿0-9]+)\s*道）/],
      [path.join(ROOT, 'docs', 'ARCHITECTURE.md'), /当前共 ([一-鿿0-9]+)\s*道/],
      [path.join(ROOT, 'docs', 'COMPLETION.md'), /3\.1 ([一-鿿0-9]+)\s*道机器闸门/],
      // 2026-11-01 补：AUDIT-COVERAGE 也声称闸门数，此前不在对账名单里 —— 它就是这样过期的。
      [path.join(ROOT, 'docs', 'AUDIT-COVERAGE.md'), /-> ([一-鿿0-9]+)\s*道闸门全部通过/],
    ];
    // 2026-11-01 再补：**示例输出块里的 `allgates: 全部 N 道闸门通过`** 同样会过期 ——
    // README 与 COMPLETION 的标题已改成 21，而块里仍写 20，上面那组正则只盯标题所以漏了。
    const outputBlocks = [
      path.join(ROOT, 'README.md'),
      path.join(ROOT, 'docs', 'COMPLETION.md'),
    ];
    for (const file of outputBlocks) {
      if (!fs.existsSync(file)) continue;
      const txt = fs.readFileSync(file, 'utf8');
      const m = txt.match(/allgates: 全部 ([一-鿿0-9]+)\s*道闸门通过/);
      if (!m) { findings.push(path.relative(ROOT, file) + ' 找不到示例输出里的闸门数'); continue; }
      const claimed = /^[0-9]+$/.test(m[1]) ? parseInt(m[1], 10) : (CN[m[1]] || -1);
      if (claimed !== real) {
        findings.push(path.relative(ROOT, file) + ' 示例输出声称 ' + m[1] + ' 道，实际 ' + real + ' 道');
      }
    }
    for (const t of targets) {
      const file = t[0];
      if (!fs.existsSync(file)) continue;
      const txt = fs.readFileSync(file, 'utf8');
      const hit = txt.match(t[1]);
      if (!hit) { findings.push(path.relative(ROOT, file) + ' 找不到闸门数声明'); continue; }
      const raw = hit[1];
      const claimed = /^[0-9]+$/.test(raw) ? parseInt(raw, 10) : (CN[raw] || -1);
      if (claimed !== real) {
        findings.push(path.relative(ROOT, file) + ' 声称 ' + raw + ' 道，实际 ' + real + ' 道（与 allgates.js 的 GATES 不一致）');
      }
    }
  }
}

// ⑤ 界面「数字承诺」与它的**代码锚点**必须同时存在。
//
// 这条被 ROUND-188 的事故逼出来：密码闸的说明写着「输对一次后 30 秒内不再重复询问」，
// 而 `needsGate` 只判 `lastUnlockSuccessAt` —— 文案与判据各写各的，
// 谁也不知道对方改了，于是承诺静默失效了一整段时间。
//
// 本闸门**不判断对错**（那需要人读代码）。它只判断"两边都还在"：
// 任一侧被改或被删就红，逼人回来把这一对重新对一遍。
// 加新条目时：把文案里的原句、和真正实现它的那行代码，各截一个**稳定子串**。
{
  const PAIRS = [
    { copy: 'App/Features/Door/TailgateScreen.swift', text: '2–6 秒',
      code: 'App/Features/Door/TailgateScreen.swift', anchor: 'ForEach(2 ... 6' },
    { copy: 'App/Features/Door/LinkSense.swift', text: '5 / 15 / 30 / 60 / 90',
      code: 'App/Features/Door/LinkSense.swift', anchor: '[5, 15, 30, 60, 90]' },
    { copy: 'App/Features/Door/DeviceInfoScreen.swift', text: '偏差超过 2 秒',
      code: 'App/Features/Door/DeviceInfoScreen.swift', anchor: 'abs(drift) > 2' },
    { copy: 'App/Features/Settings/AboutScreen.swift', text: '连点 10 次',
      code: 'App/Features/Settings/AboutScreen.swift', anchor: 'versionTaps >= 10' },
    { copy: 'App/Features/Door/UnlockGateScreen.swift', text: '30 秒内不再重复询问',
      code: 'App/Features/Door/DoorScreen.swift', anchor: 'app.gatePassedAt' },
  ];
  for (const p of PAIRS) {
    for (const side of ['copy', 'code']) {
      const relPath = p[side];
      const needle = side === 'copy' ? p.text : p.anchor;
      const abs = path.join(ROOT, relPath);
      if (!fs.existsSync(abs)) { findings.push(relPath + " 不存在（承诺对账）"); continue; }
      if (fs.readFileSync(abs, "utf8").indexOf(needle) < 0) {
        findings.push(relPath + " 里找不到「" + needle + "」—— 承诺或判据被改过，请重新核对这一对");
      }
    }
  }
}

if (checked === 0) {
  console.log('workflow: SKIP — 没找到 .github/workflows/ios27.yml');
  process.exit(0);
}
console.log('workflow: 检查 ' + checked + ' 个文件');
if (findings.length === 0) {
  console.log('workflow: OK — 无 TAB，run 块缩进正确，顶层键合法');
  process.exit(0);
}
console.log('workflow: FAIL — ' + findings.length + ' 处\n');
for (const f of findings) console.log('  ' + f);
process.exit(1);
