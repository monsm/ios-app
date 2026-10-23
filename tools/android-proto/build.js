'use strict';
// tools/android-proto/build.js —— Android 端原型构建
const steps = ['gen-home.js', 'gen-scan.js', 'gen-settings.js'];
let fail = 0;
for (const s of steps) {
  try { require('child_process').execSync('node ' + s, { cwd: __dirname, stdio: 'inherit' }); }
  catch(e) { console.error('✗ ' + s); fail++; }
}
// 后处理
for (const s of ['statusbar.js', 'deemoji.js', 'normalize.js', 'converge-color.js']) {
  try { require('child_process').execSync('node ' + s, { cwd: __dirname, stdio: 'inherit' }); }
  catch(e) { console.error('✗ ' + s); fail++; }
}
console.log(fail ? '✗ ' + fail + ' 步失败' : '✓ Android 原型构建完成');
