#!/usr/bin/env node
// docnumbercheck —— 验收清单里的**可机器算的数字**是否与实际一致（判失败）。
//
// 正控：把「**24/24 项在位**」改成「**23/24 项在位**」⇒ 报出「表格实际 24 个 ✅，文档写 23」。
// 负控：全仓零误报（只查验收清单里三个**能算**的数字：提速证据行数、真问题合计、界面维度行数）。
//
// 2026-10-31（第 78 轮）：`docs/最终验收清单.md` 是我自己维护的，而它里面全是**手写数字**：
//   · 第 73 轮我把构建链写成「6 连 success」—— 实际 3 个是 failure（第 76 轮修正）
//   · 第 73 轮我把闸门数写成「78 道」—— 实际调度 74（第 77 轮修正，已加动态断言）
//   · 提速证据「24/24」、真问题「30」、维度「13」—— 这些**都能从文档自身算出来**，不该靠人记
//
// 为什么不做成通用 Markdown 校验：那会误报一片。这里只查三个**结构固定**的表格。
//
// 正控：把「**24/24 项在位**」改成「**23/24 项在位**」⇒
//       报出「提速证据：文档写 23/24，表格实际 24 个 ✅ / 24 行」，退出码 1。
// 负控：三项数字（24/24、30、13）全 ok，零误报。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DOC = path.join(ROOT, 'docs', '最终验收清单.md');

if (!fs.existsSync(DOC)) {
  console.log('✓ 验收清单不存在，跳过');
  process.exit(0);
}

const doc = fs.readFileSync(DOC, 'utf8');
const L = doc.split(/\r?\n/);
const bad = [];
const okList = [];

// ① 提速证据表：`| N | iOS/Android | 项 | ✅/❌ |`
let rows = 0, okRows = 0;
for (const line of L) {
  const c = line.trim();
  if (!/^\| \d+ \|/.test(c)) continue;
  if (!/ \| (iOS|Android) \| /.test(c)) continue;
  rows++;
  if (c.endsWith('| ✅ |')) okRows++;
}
const claim1 = doc.match(/\*\*(\d+)\/(\d+) 项在位\*\*/);
if (claim1) {
  if (okRows !== +claim1[1] || rows !== +claim1[2]) {
    bad.push(`提速证据：文档写 ${claim1[1]}/${claim1[2]}，表格实际 ${okRows} 个 ✅ / ${rows} 行`);
  } else {
    okList.push(`提速证据 ${okRows}/${rows} 与表格一致`);
  }
}

// ② 真问题合计
const fixM = doc.match(/\| iOS \| \d+ 轮 \| (\d+) \|/);
const fixA = doc.match(/\| Android \| \d+ 轮 \| \*\*(\d+)\*\* \|/);
const claim2 = doc.match(/(\d+) 个真问题全修/);
if (fixM && fixA && claim2) {
  const sum = +fixM[1] + +fixA[1];
  if (sum !== +claim2[1]) bad.push(`真问题数：文档写 ${claim2[1]}，iOS ${fixM[1]} + Android ${fixA[1]} = ${sum}`);
  else okList.push(`真问题数 ${sum} 与分项一致`);
}

// ③ 界面维度行数（必须 13）
const DIMS = /^\| (触达尺寸|图形\/图标无障碍|最小图标无障碍|最小字号|硬编码颜色|深色对比度|空态|弹窗出口|孤儿页|导航层级|错误文案|RTL|横屏|动态字体) \|/;
let dimRows = 0;
for (const line of L) if (DIMS.test(line.trim())) dimRows++;
if (dimRows) {
  const claim3 = doc.match(/(\d+) 维度 × 2 平台/);
  if (claim3 && +claim3[1] !== dimRows) bad.push(`界面维度：文档写 ${claim3[1]}，表格实际 ${dimRows} 行`);
  else okList.push(`界面维度 ${dimRows} 行`);
}

if (bad.length) {
  console.log(`✗ 验收清单数字与实际不符 ${bad.length} 处：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：这些数字**能从文档自身算出来**，手写必然出错（第 73/77 轮各错过一次）。');
  console.log('修法：改正文档里的数字；若表格结构改了，同步更新本闸门的正则。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log('\n✓ 验收清单里可机器算的数字均与实际一致');
