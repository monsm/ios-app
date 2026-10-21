#!/usr/bin/env node
// tools/cilog.js —— 从 CI 取**真实编译报错**
//
// 为什么需要它：
//   tools/cistat.js 是从 Actions 页面 HTML 里正则抓状态的，
//   页面结构一变它就抓不到 error 行，只会告诉你 FAILURE ——
//   于是我只能猜是哪个文件错了。本会话因此在 CI 已经红了好几轮的情况下
//   一直报「本地 23 道闸门全绿」，直到手动用 API 下载了 730KB 日志才看见：
//     EventsPage.swift:179: error: type 'RecordSearch.Query' has no member 'parse'
//
// 做法：
//   1. git credential fill 取本机已存的 GitHub 凭证（不落盘、不打印密码本身）
//   2. 走 Actions API 列出该 run 的 jobs，找 conclusion=failure 的那些
//   3. 下载失败 job 的日志（纯文本），抽 error: 行
//
// 用法：
//   node tools/cilog.js <runId>
//
'use strict';
const { spawnSync } = require('child_process');
const https = require('https');

const runId = process.argv[2];
if (!runId) {
  console.error('用法: node tools/cilog.js <runId>');
  process.exit(2);
}

function token() {
  // 只取 password 字段；不打印、不落盘。
  // 不能用 shell 管道：Windows 上没有 bash，会直接 ENOENT。
  // 直接 spawnSync 给 git 喂 stdin，跨平台都成立。
  const r = spawnSync('git', ['credential', 'fill'], {
    input: 'protocol=https\nhost=github.com\n\n',
    encoding: 'utf8',
  });
  const m = ((r.stdout) || '').match(/^password=(.*)$/m);
  return m ? m[1].trim() : '';
}

function api(pathname, asJson = true) {
  const tk = token();
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.github.com',
        path: pathname,
        method: 'GET',
        headers: {
          'User-Agent': 'cilog',
          // ⚠ 日志端点也必须是 vnd.github+json —— 送 text/plain 会得到 415。
          // asJson 只决定要不要 JSON.parse，不决定 Accept。
          Accept: 'application/vnd.github+json',
          ...(tk ? { Authorization: 'Bearer ' + tk } : {}),
        },
      },
      res => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          https.get(res.headers.location, r2 => {
            let b = '';
            r2.on('data', d => (b += d));
            r2.on('end', () => resolve(b));
          });
          return;
        }
        if (res.statusCode !== 200) { reject(new Error('HTTP ' + res.statusCode + ' ' + pathname)); return; }
        let body = '';
        res.on('data', d => (body += d));
        res.on('end', () => resolve(asJson ? JSON.parse(body) : body));
      }
    );
    req.on('error', reject);
    req.end();
  });
}

(async () => {
  const jobs = await api('/repos/monsm/ios-app/actions/runs/' + runId + '/jobs');
  const failed = (jobs.jobs || []).filter(j => j.conclusion === 'failure');
  console.log('run ' + runId + '  共 ' + (jobs.jobs || []).length + ' 个 job，失败 ' + failed.length + ' 个');
  if (!failed.length) { console.log('没有失败的 job（可能是排队/取消，不是源码问题）'); return; }
  const seen = new Set();
  for (const j of failed) {
    console.log('');
    console.log('══ ' + j.name + ' ══');
    let log = '';
    try { log = await api('/repos/monsm/ios-app/actions/jobs/' + j.id + '/logs', false); }
    catch (e) { console.log('  取日志失败: ' + e.message); continue; }
    const lines = String(log).split('\n');
    let n = 0;
    for (const raw of lines) {
      const l = raw.replace(/^\d{4}-\d\d-\d\dT[\d:.]+Z\s?/, '');
      if (!/error: /.test(l)) continue;
      const key = l.trim();
      if (seen.has(key)) continue;   // 同一错误在多份日志里重复出现
      seen.add(key);
      console.log('  ' + key.slice(0, 250));
      if (++n >= 20) { console.log('  …（更多省略）'); break; }
    }
    if (n === 0) {
      console.log('  这份日志里没有 error: 行 —— 多半是环境/签名/模拟器问题，不是源码');
      const tail = lines.map(l => l.replace(/^\d{4}-\d\d-\d\dT[\d:.]+Z\s?/, '')).filter(Boolean).slice(-12);
      for (const t of tail) console.log('    ' + t.slice(0, 200));
    }
  }
})().catch(e => { console.error('失败: ' + e.message); process.exit(1); });
