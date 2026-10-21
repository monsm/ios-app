// 一次性代码转换器 (不是闸门): 把 List/Form { Section {...} } 结构
// 改成 ZStack + ScrollView + VStack + XPanel 卡片。
//
// 三条踩过的坑 (都是真失败过才写进来的):
// 1. Section 边界必须**线性扫描**, 不能用括号配平 —— Picker 里的
//    Binding(get:set:)、ForEach 闭包、if 语句的内层 {} 会让配平提前收口。
// 2. List/Form 的缩进不固定 (NavigationStack 里就是 12 格, 顶层是 8 格),
//    所以 baseIndent 要现算, 不能写死。
// 3. Section("标题") { ... } 与 Section { ... } header: { } 两种写法都要支持。
'use strict';
const fs = require('fs');
const path = require('path');

function findBlockEnd(lines, startIdx) {
  let depth = 0, started = false;
  for (let i = startIdx; i < lines.length; i++) {
    const code = lines[i].replace(/\/\/.*$/, '').replace(/"(?:[^"\\]|\\.)*"/g, '""');
    for (const c of code) {
      if (c === '{') { depth++; started = true; } else if (c === '}') depth--;
    }
    if (started && depth === 0) return i;
  }
  return -1;
}

function transformStruct(file, structName) {
  const abs = path.join(__dirname, '..', file);
  const L = fs.readFileSync(abs, 'utf8').split('\n').map(l => l.replace(/\r$/, ''));
  const sStart = L.findIndex(l => new RegExp('^struct ' + structName + '\\b').test(l));
  if (sStart < 0) { console.log(structName + ': struct not found'); return false; }

  let vs = L.findIndex((l, k) => k > sStart && /^    (?:@ViewBuilder )?var vkBody: some View \{/.test(l));
  const isVk = vs >= 0;
  if (!isVk) vs = L.findIndex((l, k) => k > sStart && /^    (?:@ViewBuilder )?var body: some View \{/.test(l));
  if (vs < 0) { console.log(structName + ': no body'); return false; }
  const e = findBlockEnd(L, vs);
  if (e < 0) { console.log(structName + ': body end not found'); return false; }
  const body = L.slice(vs, e + 1);

  const listIdx = body.findIndex(l => /^\s*(List|Form) \{/.test(l));
  if (listIdx < 0) { console.log(structName + ': no List/Form'); return false; }
  const container = body[listIdx].match(/(List|Form) \{/)[1];
  const baseIndent = (body[listIdx].match(/^(\s*)/) || ['', ''])[1].length;
  const secIndent = baseIndent + 4;

  const sp = n => ' '.repeat(n);
  const closeRe = new RegExp('^' + sp(secIndent) + '\\}\\s*(header|footer):\\s*\\{');
  const bareRe = new RegExp('^' + sp(secIndent) + '\\}$');
  const openRe = new RegExp('^' + sp(secIndent) + 'Section');

  function sectionEnd(i) {
    for (let k = i + 1; k < body.length; k++) {
      const t = body[k];
      if (closeRe.test(t)) return { closeIdx: k, kind: t.match(/header|footer/)[0] };
      if (bareRe.test(t)) return { closeIdx: k, kind: null };
    }
    return null;
  }

  const sections = [];
  for (let i = listIdx + 1; i < body.length; i++) {
    if (!openRe.test(body[i])) continue;
    let headerLabel = null;
    const tm = body[i].match(/Section\("([^"]*)"/);
    if (tm) headerLabel = tm[1];
    const se = sectionEnd(i);
    if (!se) continue;
    let endIdx = se.closeIdx;
    const inner = body.slice(i + 1, se.closeIdx);
    if (se.kind) {
      let hd = 1, k2 = se.closeIdx;
      for (let x = se.closeIdx + 1; x < body.length; x++) {
        const clean = body[x].replace(/\/\/.*$/, '').replace(/"(?:[^"\\]|\\.)*"/g, '""');
        for (const c of clean) { if (c === '{') hd++; else if (c === '}') hd--; }
        if (hd <= 0) { k2 = x; break; }
      }
      const blk = body.slice(se.closeIdx, k2 + 1).join('\n');
      const lbl = blk.match(/Text\("([^"]+)"/);
      if (lbl) headerLabel = lbl[1];
      endIdx = k2;
      const nx = (body[endIdx + 1] || '').trim();
      if (/^\}\s*footer:\s*\{$/.test(nx)) {
        let fd = 1, k3 = endIdx + 1;
        for (let x = endIdx + 2; x < body.length; x++) {
          const clean = body[x].replace(/\/\/.*$/, '').replace(/"(?:[^"\\]|\\.)*"/g, '""');
          for (const c of clean) { if (c === '{') fd++; else if (c === '}') fd--; }
          if (fd <= 0) { k3 = x; break; }
        }
        endIdx = k3;
      }
    }
    sections.push({ startIdx: i, endIdx, headerLabel, inner });
    i = endIdx;
  }

  if (!sections.length) { console.log(structName + ': 0 sections parsed — 跳过'); return false; }

  const listEnd = findBlockEnd(body, listIdx);
  const tailMods = body.slice(listEnd + 1, body.length - 1)
    .filter(l => !/^\s*\.xList\(\)\s*$/.test(l) && !/^\s*\.xScreen\(\)\s*$/.test(l));

  const stripRe = new RegExp('^' + sp(secIndent));
  const out = [];
  const headLine = L[vs].replace(/^\s+/, '    ');
  out.push(headLine);
  out.push('        ZStack {');
  out.push('            XPalette.canvas.ignoresSafeArea()');
  out.push('');
  out.push('            ScrollView {');
  out.push('                VStack(spacing: XSpace.l) {');
  for (const s of sections) {
    out.push('                    XPanel(kind: .group) {');
    out.push('                        VStack(alignment: .leading, spacing: XSpace.m) {');
    if (s.headerLabel) out.push('                            secLabel("' + s.headerLabel.replace(/"/g, '\\"') + '")');
    for (const il of s.inner) {
      const stripped = il.replace(stripRe, '');
      out.push(stripped.trim() === '' ? '' : ' '.repeat(28) + stripped);
    }
    out.push('                        }');
    out.push('                    }');
    out.push('');
  }
  out.push('                }');
  out.push('                .padding(.horizontal, XSpace.gutter)');
  out.push('                .padding(.vertical, XSpace.l)');
  out.push('            }');
  out.push('            .scrollIndicators(.hidden)');
  out.push('        }');
  out.push(...tailMods);
  out.push('    }');
  out.push('');
  out.push('    private func secLabel(_ text: String) -> some View {');
  out.push('        Text(text)');
  out.push('            .xFont(.caption, weight: .semibold)');
  out.push('            .foregroundStyle(XPalette.textTertiary)');
  out.push('            .textCase(.uppercase)');
  out.push('            .frame(maxWidth: .infinity, alignment: .leading)');
  out.push('    }');

  const rebuilt = L.slice(0, vs).concat(out, L.slice(e + 1));
  fs.writeFileSync(abs, rebuilt.join('\n'), 'utf8');
  console.log(structName + ' (' + container + ', baseIndent=' + baseIndent + '): ' + (e - vs + 1) + ' → ' + out.length + ' lines, ' + sections.length + ' sections');
  return true;
}

const targets = process.argv.slice(2);
if (!targets.length || targets.length % 2 !== 0) {
  console.error('用法: node tools/structrewrite.js <File.swift> <StructName> [...]');
  process.exit(1);
}
for (let i = 0; i < targets.length; i += 2) transformStruct(targets[i], targets[i + 1]);
