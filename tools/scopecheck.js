const fs = require('fs');
const path = require('path');
// 2026-10-31（第 35 轮，**闸门自身导致 CI 红**）：硬编码 `D:/aapk/ios-app` 在 CI 上不存在
// （runner 路径是 /home/runner/work/...）。所有闸门必须用 __dirname 推根目录。
const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

// 精确判据：**计算属性** `var xxx: T {` 出现在函数/初始化器体内 ⇒ 编译必红。
// 局部变量 `var x: Int = 0` 合法（有初值），不算。
function strip(line) {
  let inStr = false;
  for (let i = 0; i < line.length - 1; i++) {
    const ch = line[i], prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') inStr = !inStr;
    if (!inStr && ch === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}

const bad = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = `${d}/${f}`;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    const stack = [];   // 'func' | 'block'
    for (let i = 0; i < L.length; i++) {
      const code = strip(L[i]);
      const t = code.trim();

      const inFunc = stack.length > 0 && stack[stack.length - 1] === 'func';

      // 计算属性：`var name: Type {`（行尾是 { 且没有 = 初值）
      // 计算属性两种形态：多行（行尾 `{`）与单行（`{ … }` 都在本行）。
      // 二者都不能出现在函数/初始化器体内 —— 属性只能声明在类型体或文件作用域。
      const isComputedPropMulti = /^(?:private|fileprivate|internal|public|static|override)?\s*(?:private|fileprivate|internal|public)?\s*var\s+\w+\s*:\s*[\w<>\[\]?.]+\s*\{\s*$/.test(t);
      const isComputedPropSingle = /^(?:private|fileprivate|internal|public|static|override)?\s*(?:private|fileprivate|internal|public)?\s*var\s+\w+\s*:\s*[\w<>\[\]?.]+\s*\{.*\}\s*$/.test(t);
      const isComputedProp = isComputedPropMulti || isComputedPropSingle;
      if (inFunc && isComputedProp) {
        bad.push(`${rel}:${i + 1}  函数体内出现**计算属性**声明: ${t.slice(0, 64)}`);
      }

      // 注意 `init(` 后面紧跟 `(` 而不是空格 —— 早先的正则要求 `\s` 所以漏掉了初始化器体。
      const isFuncOpen = /^(?:@[\w()]+\s+)*(?:private|fileprivate|internal|public|static|override|mutating|nonisolated)?\s*(?:func\s|init\s*\(|subscript\s*\()/.test(t) && t.includes('{');
      for (const ch of code) {
        if (ch === '{') stack.push(isFuncOpen ? 'func' : 'block');
        else if (ch === '}') stack.pop();
      }
    }
  }
}

if (bad.length) {
  console.log(`✗ 函数体内出现计算属性 ${bad.length} 处（编译必红）：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n修法：把该声明移到类型体层级（`init`/`func` 的闭合括号之后）。');
  process.exit(1);
}
console.log('✓ 未发现「计算属性被放进函数体」');
