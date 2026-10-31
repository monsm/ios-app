#!/usr/bin/env node
// feedback.js —— 第 18 道闸门：**命令失败必须说出来**。
//
// 依据 HIG `feedback` › Best practices：
//   "Show people when a command can't be carried out and help them understand why."
//
// 为什么需要自动检查：这一类缺陷**不崩、不报错、不影响编译**，只让用户"点了没反应"。
// 本轮实测两处（AutoOpenScreen.calibrate 的连不上、DeviceInfoScreen 的自动校时失败）：
// 都是 `try? await <会失败的调用>` —— 失败被静默吞掉，界面状态原地不动，
// 用户唯一的线索是"转圈停了，什么都没变"。
//
// 判什么：动作函数（名字像用户动作）里出现 `try? await`，
// 且同函数体**没有任何**错误通道（catch / errorText / outcome / toast …）⇒ 红。
//
// 判红。用法：node Gates/feedback.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const ACTION_RE = /func\s+(calibrate|connect|sync|submit|save|restore|import|export|start|stop|toggle|issue|revoke|delete|remove|add|write|send|apply|confirm|upload|download|pair|unpair|enable|disable|reset|clear|rename|edit|create|update|refresh|reload)\w*\s*\(/i;

const FEEDBACK_RE = /\bcatch\b|errorText|outcome|errorLine|calibrationError|restoreError|lastError|importError|saveError|AppToast|showToast|ToastCenter|VStatusLine\(tone: \.critical|presentingError|errorMessage|failMsg/i;

const fails = [];
const files = walk(APP);

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  for (let i = 0; i < lines.length; i++) {
    if (!ACTION_RE.test(lines[i])) continue;
    let depth = 0, started = false, body = '';
    for (let j = i; j < Math.min(lines.length, i + 90); j++) {
      const l = lines[j];
      body += l + '\n';
      for (const ch of l) {
        if (ch === '{') { depth++; started = true; }
        else if (ch === '}') depth--;
      }
      if (started && depth === 0) break;
    }
    // 只关心**会真的失败**的调用：`try? await Task.sleep(...)` 是取消语义，不是命令失败；
    // `func ... throws` 的函数本身就把错误抛给调用方了（错误通道在别处）。
    const failingCalls = (body.match(/try\?\s+await\s+[A-Za-z_.]+/g) || [])
      .filter((c) => !c.includes('Task.sleep'));
    if (failingCalls.length === 0) continue;
    if (/func\s+\w+\s*\([^)]*\)\s*(async\s+)?throws/.test(body.split('\n')[0])) continue;
    // 纯后台轮询 / 状态刷新：名字以 reload/refresh/poll/start/stop 开头且不返回任何值给用户
    if (/^\s*func\s+(reload|refresh|poll|start|stop|observe|prefetch)/.test(lines[i])) continue;
    if (FEEDBACK_RE.test(body)) continue;
    fails.push(rel + ':' + (i + 1) + '  ' + lines[i].trim().slice(0, 96));
  }
}

if (fails.length === 0) {
  console.log('feedback: OK — 用户动作里的 try? await 都有错误通道');
  process.exit(0);
}
console.log('feedback: FAIL — ' + fails.length + ' 处"命令失败但不说原因"（HIG feedback）\n');
for (const x of fails) console.log('  ' + x);
console.log('\n  处置：把 try? 改成 do/catch，并把失败原因写进用户可见的 errorText/outcome/toast。');
process.exit(1);