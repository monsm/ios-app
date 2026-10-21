#!/usr/bin/env node
// ============================================================================
// cistat.js — 可靠的 CI 状态查询
// ============================================================================
//
// 为什么需要这一道:
//   之前用一个正则去数 run 页面里的 "completed successfully" / "completed with failure" ——
//   但那两个串在页面里是**其他 job 的状态标签**, 不是本次运行的结论。
//   真正的失败信号是 favicon-failure.svg 与 octicon-x 图标。
//   代价是: iOS 编译从 XScrollLift 那一轮起一直失败, 却连续多轮被报成"全绿"。
//
// 判据 (按可信度排序):
//   1. favicon-failure.svg     → run 结论 = failure
//   2. favicon-success.svg     → run 结论 = success
//   3. 页面文本里的 error: 行  → 直接给出编译错误
//
// 用法: node tools/cistat.js [runId]
//       不带参数 → 抓最新一次 run
'use strict';
const https = require('https');

const UA = { 'User-Agent': 'Mozilla/5.0' };

function get(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: UA }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return get(res.headers.location).then(resolve, reject);
      }
      let buf = '';
      res.on('data', (d) => (buf += d));
      res.on('end', () => resolve(buf));
    }).on('error', reject);
  });
}

function decode(html) {
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/[ \t]+/g, ' ');
}

async function latestRunId() {
  const html = await get('https://github.com/monsm/ios-app/actions?query=branch%3Amain');
  const m = html.match(/"runNumber":(\d+),"id":"(\d+)"/);
  if (!m) throw new Error('抓不到最新 run');
  return { number: m[1], id: m[2] };
}

async function runStatus(id) {
  const html = await get('https://github.com/monsm/ios-app/actions/runs/' + id);
  let conclusion = 'unknown';
  if (html.includes('favicon-failure.svg')) conclusion = 'failure';
  else if (html.includes('favicon-success.svg')) conclusion = 'success';
  else if (html.includes('In progress') || html.includes('Queued')) conclusion = 'running';

  // job id
  const jobs = [...new Set([...html.matchAll(/\/actions\/runs\/\d+\/job\/(\d+)/g)].map((x) => x[1]))];
  return { conclusion, jobs };
}

async function jobErrors(jobId) {
  const html = await get('https://github.com/monsm/ios-app/actions/runs/x/job/' + jobId);
  const text = decode(html);
  const out = [];
  const seen = new Set();
  for (const line of text.split('\n')) {
    const t = line.trim();
    if (!/error:/.test(t)) continue;
    const key = t.slice(0, 160);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(t.slice(0, 240));
  }
  return out;
}

(async () => {
  let id = process.argv[2];
  let number = '?';
  if (!id) {
    const l = await latestRunId();
    id = l.id;
    number = l.number;
  }
  const { conclusion, jobs } = await runStatus(id);
  console.log('run #' + number + ' (id ' + id + ')  =>  ' + conclusion.toUpperCase());
  if (jobs.length) console.log('jobs: ' + jobs.length + ' 个');

  if (conclusion === 'failure') {
    let total = 0;
    for (const j of jobs) {
      const errs = await jobErrors(j);
      if (!errs.length) continue;
      total += errs.length;
      console.log('\n── job ' + j + ' ──');
      errs.slice(0, 20).forEach((e) => console.log('  ' + e));
    }
    if (total === 0) console.log('\n(页面里没抓到 error: 行 —— 可能是 Xcode 换行截断, 需要点进 job 页面人工看)');
    process.exit(1);
  }
  process.exit(conclusion === 'success' ? 0 : 2);
})();
