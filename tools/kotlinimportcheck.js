const fs = require('fs');
const path = require('path');
const KT = 'D:/aapk/ios-app/android-app/app/src/main/java/com/aapk/kfkey/';

// 检查：用到的符号是否有对应 import（只查常见 Compose / kotlin 标准库符号）
const NEED = {
  'mutableStateListOf': 'androidx.compose.runtime.mutableStateListOf',
  'mutableStateOf': 'androidx.compose.runtime.mutableStateOf',
  'remember': 'androidx.compose.runtime.remember',
  'getValue': 'androidx.compose.runtime.getValue',
  'setValue': 'androidx.compose.runtime.setValue',
  'roundToInt': 'kotlin.math.roundToInt',
  'floor': 'kotlin.math.floor',
  'ceil': 'kotlin.math.ceil',
  'log10': 'kotlin.math.log10',
  'cos': 'kotlin.math.cos',
  'sin': 'kotlin.math.sin',
  'sqrt': 'kotlin.math.sqrt',
  'abs': 'kotlin.math.abs',
  'delay': 'kotlinx.coroutines.delay',
  'launch': 'kotlinx.coroutines.launch',
  'JSONObject': 'org.json.JSONObject',
};

const files = fs.readdirSync(KT).filter(f => f.endsWith('.kt'));
const problems = [];

for (const f of files) {
  const src = fs.readFileSync(path.join(KT, f), 'utf8');
  const imports = new Set();
  src.split(/\r?\n/).forEach(l => {
    const m = l.match(/^import\s+(?:[\w.]+\s+as\s+\w+|([\w.]+))\s*$/);
    if (m && m[1]) imports.add(m[1]);
  });
  // 同包内的类不需要 import
  const samePackage = new Set(['AutoOpenKit', 'LockStore', 'LockInfo', 'BleUnlocker', 'KfProtocol',
    'KfHaptics', 'KfTheme', 'KfTokens', 'Tokens', 'SignalArrow', 'Outcome', 'Session', 'Attempt', 'Frame']);

  for (const [sym, imp] of Object.entries(NEED)) {
    // 源码里是否用到该符号（排除 import 行与注释）
    const used = src.split(/\r?\n/).some(l => {
      if (/^import /.test(l)) return false;
      if (/^\s*(\*|\/\/)/.test(l)) return false;
      return new RegExp('\\b' + sym + '\\b').test(l);
    });
    if (!used) continue;
    // 是否已 import（或用了全限定名 kotlin.math.xxx）
    const hasImport = imports.has(imp);
    const fullyQualified = new RegExp('kotlin\\.math\\.' + sym + '\\s*\\(').test(src) ||
                           new RegExp('kotlinx\\.coroutines\\.' + sym).test(src);
    if (!hasImport && !fullyQualified) {
      problems.push(`${f}  用到 ${sym} 但缺 import ${imp}`);
    }
  }
}

if (problems.length) {
  console.log(`✗ 缺失 import ${problems.length} 处（编译必拒：unresolved reference）：`);
  problems.forEach(p => console.log('  ' + p));
  process.exit(1);
}
console.log('✓ 未发现缺失 import');
