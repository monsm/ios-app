#!/usr/bin/env node
// tests.js —— 第 17 道闸门：测试套件的**静态可验证性**（G-07 的本地代理）。
//
// 为什么需要它：CI 的两个镜像（xcode-27 / macos-latest）都常常没有 iOS 27 模拟器 runtime，
// 于是 `xcodebuild test` 在那边**一条断言都跑不了**。那种情况下"CI 绿"不能证明金标测试存在、
// 也不能证明它覆盖了协议层。这道闸门在本地（不需要 Mac）就能证明三件事：
//
//   ① 测试目标真的存在，且 scheme 的 test 段引用了它（不是"写了文件没人跑"）；
//   ② 金标夹具真的被当作**资源**打进测试 bundle（否则所有断言会在空集合上静默通过）；
//   ③ 测试覆盖了协议层的关键面：AES / 命令帧 / 状态解析 / 日志解析 / ZOTP / 归属 / 广播解析。
//
// 判红。用法：node Gates/tests.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const fails = [];
const ok = [];

function read(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return ''; }
}

// ---------- ① 测试目标 + scheme 接线 ----------
const proj = read(path.join(ROOT, 'project.yml'));
if (!/CoreProtocolTests:\s*\n\s*type:\s*bundle\.unit-test/.test(proj)) {
  fails.push('project.yml — 没有 macOS 原生测试目标 CoreProtocolTests（CI 上金标永远跑不了）');
} else ok.push('测试目标 CoreProtocolTests 存在（macOS 原生，不需要 iOS 模拟器）');

// macOS 原生测试是 CI 上唯一能真跑金标的路径 —— 必须有自己的 scheme
if (!/CoreGolden:/.test(proj)) {
  fails.push('project.yml — 缺 CoreGolden scheme（CI 无法只跑协议层测试）');
} else ok.push('CoreGolden scheme 存在');

// 协议层源文件必须真的被编进 macOS 测试目标（不是"建了目标但没编源文件"）
for (const must of ['App/Engine/ZKCmdBuilder.swift', 'App/Engine/StatusParser.swift', 'App/Engine/AESKit.swift', 'App/Engine/ZOTP.swift']) {
  if (!new RegExp(must.replace(/[/.]/g, (c) => '\\' + c)).test(proj)) {
    fails.push('project.yml — CoreProtocolTests 没有编 ' + must + '（金标会测不到该模块）');
  }
}

if (!/test:\s*\n\s*config:\s*Debug\s*\n\s*targets:\s*\n\s*-\s*CoreProtocolTests/.test(proj)) {
  fails.push('project.yml — scheme 的 test 段没有引用 CoreProtocolTests（写了目标但从不执行）');
} else ok.push('scheme test 段引用了 CoreProtocolTests');

// ---------- ② 夹具作为资源 ----------
if (!/golden\.json/.test(proj)) {
  fails.push('project.yml — 金标夹具 golden.json 没有作为资源打进测试 bundle（断言会在空集合上静默通过）');
} else ok.push('golden.json 作为测试资源接线');

// ---------- ③ 测试文件与覆盖面 ----------
let testFiles = [];
for (const dir of ['TestsCore', 'Tests']) {
  try {
    testFiles = testFiles.concat(
      fs.readdirSync(path.join(ROOT, dir)).filter((f) => f.endsWith('.swift')).map((f) => path.join(dir, f)));
  } catch { /* 目录不存在 */ }
}
if (testFiles.length === 0) {
  fails.push('Tests/ 下没有任何 .swift 测试文件');
} else ok.push('测试文件 ' + testFiles.length + ' 个');

const allTestSrc = testFiles.map((f) => read(path.join(ROOT, f))).join('\n');

// 夹具加载必须自带"没加载到就红"的前置断言
if (!/testGoldenFixtureLoaded/.test(allTestSrc) || !/XCTAssertFalse\(.*golden\.isEmpty/.test(allTestSrc)) {
  fails.push('测试缺少「夹具必须真加载到」的前置断言（资源缺失时全套会静默通过）');
} else ok.push('有夹具加载前置断言（资源缺失即红）');

// 覆盖关键面：每条都要在测试源码里真实出现
const COVERAGE = [
  ['AES / NIST 向量', /AESKit\.encryptHex/],
  ['命令帧字节级对拍', /ZKCmdBuilder\.cmd0ASyncPwd/],
  ['状态解析', /StatusParser\.parseStatus/],
  ['日志解析', /StatusParser\.parseLogs/],
  ['ZOTP 冻结时钟', /ZOTP\.generate/],
  ['归属推断', /Attribution\.classify/],
  ['广播解析', /ZKProtocol\.parseAdv/],
  ['rc 文案表', /StatusParser\.rcMessage/],
  ['时间基准', /ZKProtocol\.epochMs/],
];
for (const [name, re] of COVERAGE) {
  if (re.test(allTestSrc)) ok.push('覆盖：' + name);
  else fails.push('测试未覆盖「' + name + '」（协议层回归面缺一块）');
}

// 断言数量下限：太少说明测试是摆设
const asserts = (allTestSrc.match(/XCTAssert|XCTUnwrap/g) || []).length;
if (asserts < 40) {
  fails.push('断言数量只有 ' + asserts + ' 条（<40）—— 金标差分至少需要几十条逐字节断言');
} else ok.push('断言 ' + asserts + ' 条');

// ---------- 输出 ----------
console.log('tests: ' + testFiles.length + ' 个测试文件，' + asserts + ' 条断言');
if (fails.length === 0) {
  console.log('tests: OK — ' + ok.length + ' 条判据全部通过');
  console.log('tests: 注意 —— 这是**静态**证明（目标存在 + 夹具接线 + 覆盖关键面）。');
  console.log('        真跑：协议层走 macOS 原生 scheme（CI 的 golden job 会真执行）：');
  console.log('        xcodebuild test -project LockKeeper.xcodeproj -scheme CoreGolden -destination "platform=macOS"');
  console.log('        界面层仍需带 iOS 27 模拟器 runtime 的机器（CI 镜像没有）。');
  process.exit(0);
}
console.log('tests: FAIL — ' + fails.length + ' 处问题\n');
for (const f of fails) console.log('  ' + f);
process.exit(1);
