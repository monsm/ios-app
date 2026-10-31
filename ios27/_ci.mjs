
const ua = { 'User-Agent': 'Mozilla/5.0' };
const runId = process.argv[2] || '41163081282';
const base = 'https://github.com/monsm/ios-app';

const html = await (await fetch(base + '/actions/runs/' + runId, { headers: ua })).text();
console.log('run page bytes:', html.length);

// 状态：找 "Status: Failure" 之类的文本
for (const k of ['Success', 'Failure', 'In progress', 'Queued', 'cancelled']) {
  const n = (html.match(new RegExp(k, 'g')) || []).length;
  if (n) console.log('  ' + k + ' x' + n);
}

// 抓 job 链接
const jobIds = [...new Set([...html.matchAll(new RegExp('/actions/runs/' + runId + '/job/(\\d+)', 'g'))].map(m => m[1]))];
console.log('job ids:', jobIds.join(', '));

for (const jid of jobIds) {
  const jh = await (await fetch(base + '/actions/runs/' + runId + '/job/' + jid, { headers: ua })).text();
  console.log('--- job ' + jid + ' bytes=' + jh.length + ' ---');
  // 注解区：GitHub 会渲染 "Annotations" 与 error 文本
  const errs = [...jh.matchAll(/error: [^<\n]{0,200}/g)].map(m => m[0].trim());
  const uniq = [...new Set(errs)];
  console.log('errors found:', uniq.length);
  for (const e of uniq.slice(0, 25)) console.log('  ' + e);
  const title = (jh.match(/<title>([^<]*)<\/title>/) || [])[1];
  console.log('title:', title);
}
