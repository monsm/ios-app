#!/usr/bin/env node
// privacy.js —— 隐私/安全回归闸门（第 16 道）。
//
// 为什么需要它：2026-10-31 的安全审计（docs/AUDIT-F-SECURITY.md）发现的问题，
// 都是"代码看着没事、但每一条都能被下一次改动悄悄改回去"的那类：
//   · 剪贴板直接写 UIPasteboard（绕过 90 秒过期）
//   · 备份允许明文落盘 / 落盘不加密
//   · 空壳（胁迫码）模式下数据层仍然可读
//   · 帧脱敏只处理第一个 hex=
//   · WebDAV 允许 http://
// 静态审计脚本是"报告型"（默认不判红），而这一道是**判红**的：改回去就构建失败。
//
// 用法：node Gates/privacy.js
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
// 注释换空格、字符串内容换 '~'，行号不漂
function mask(src) {
  const a = src.split('');
  const n = a.length;
  let i = 0;
  while (i < n) {
    const c = a[i], d = a[i + 1];
    if (c === '/' && d === '/') { while (i < n && a[i] !== '\n') { a[i] = ' '; i++; } continue; }
    if (c === '/' && d === '*') {
      let depth = 1; a[i] = ' '; a[i + 1] = ' '; i += 2;
      while (i < n && depth > 0) {
        if (a[i] === '/' && a[i + 1] === '*') { depth++; a[i] = ' '; a[i + 1] = ' '; i += 2; continue; }
        if (a[i] === '*' && a[i + 1] === '/') { depth--; a[i] = ' '; a[i + 1] = ' '; i += 2; continue; }
        if (a[i] !== '\n') a[i] = ' ';
        i++;
      }
      continue;
    }
    if (c === '"') {
      a[i] = '~'; i++;
      while (i < n) {
        const ch = a[i];
        if (ch === '\\') { a[i] = '~'; if (a[i + 1] && a[i + 1] !== '\n') a[i + 1] = '~'; i += 2; continue; }
        if (ch === '"') { a[i] = '~'; i++; break; }
        if (ch === '\n') break;
        a[i] = '~'; i++;
      }
      continue;
    }
    i++;
  }
  return a.join('');
}

const files = walk(APP).map((f) => {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  const raw = fs.readFileSync(f, 'utf8');
  return { rel, raw, masked: mask(raw).split(/\r?\n/), lines: raw.split(/\r?\n/) };
});

const fails = [];
const note = (rel, line, why, fix) => fails.push(rel + ':' + line + ' — ' + why + ' → ' + fix);

for (const f of files) {
  f.masked.forEach((line, i) => {
    // 1. 剪贴板：只有 Engine/Clip.swift 可以直接写 UIPasteboard。
    // 读取是允许的（"从剪贴板粘贴"），只禁**写入**。
    if (/UIPasteboard\.general\.(string|items|setItems)\s*=/.test(line) && f.rel !== 'Engine/Clip.swift') {
      note(f.rel, i + 1, '直接写剪贴板，绕过 90 秒过期', '改 Clip.set(...)');
    }
    // 2. 备份必须加密：明文分支不许出现（BackupScreen / BackupStudioScreen）。
    if (/password\.isEmpty \? plain/.test(line) && /backup|Backup/.test(f.rel)) {
      note(f.rel, i + 1, '备份存在明文分支（含 skey/pins）', '强制 CryptoBox.encryptText，没有口令就拒绝生成');
    }
    // 3. 空壳（胁迫码）模式必须在数据层生效，不能只清界面投影。
    if (/\bif decoyMode\b/.test(line) && f.rel.startsWith('Shell/') && !/setDecoy/.test(f.masked.slice(Math.max(0, i - 3), i + 12).join(' '))) {
      note(f.rel, i + 1, 'decoyMode 只改界面状态，未同步数据层', '同一处调 DB.setDecoy(...)');
    }
    // 4. 协议帧脱敏不许只处理第一个 hex=。
    if (f.rel === 'Engine/FrameRedact.swift' && /range\(of: "hex="\)/.test(line) && !/while/.test(f.raw)) {
      note(f.rel, i + 1, '帧脱敏只处理第一个 hex=（其余明文落盘）', '循环处理全部 hex=');
    }
    // 5. WebDAV 不许 http://（除本机回环）。
    if (/hasPrefix\("http:\/\/"\)/.test(line) && !/localhost|127\.0\.0\.1/.test(f.masked.slice(i, i + 6).join(' '))) {
      note(f.rel, i + 1, 'WebDAV 接受明文 http://（账号与备份走明文）', '只接受 https://，本机回环例外');
    }
    // 6. 含密钥的文件必须显式文件保护。
    if (/\.write\(to:/.test(line) && /\.atomic\b/.test(line) && !/completeFileProtection/.test(line)) {
      if (/Backup|roll|rollback/i.test(f.rel)) {
        note(f.rel, i + 1, '含密钥文件写入未指定 completeFileProtection', 'options: [.atomic, .completeFileProtection]');
      }
    }
    // 7. 备份目录必须排除系统备份。
    if (f.rel === 'Engine/BackupStudioKit.swift' && /appendingPathComponent\("lockkeeper-backups"/.test(line)) {
      const window = f.masked.slice(i, i + 8).join(' ');
      if (!/isExcludedFromBackup/.test(window)) {
        note(f.rel, i + 1, '备份目录未标记 isExcludedFromBackup', '设 URLResourceValues.isExcludedFromBackup = true');
      }
    }
    // 8. CSV 导出必须防公式注入。
    if (f.rel === 'Features/Records/RecordsModels.swift' && /static func field\(_ value: String\)/.test(line)) {
      const window = f.masked.slice(i, i + 10).join(' ');
      if (!/HYPERLINK|"'"|\+"'"\+/.test(window) && !/\+ "'"/.test(window)) {
        // 以源码实际内容判定：必须出现前置单引号的写法
        const srcWindow = f.lines.slice(i, i + 10).join('\n');
        if (!/v = "'" \+ v|"'" \+ v/.test(srcWindow)) {
          note(f.rel, i + 1, 'CSV 单元格未防公式注入', '首字符 = + - @ 时前置单引号');
        }
      }
    }
  });
}

console.log('privacy: 扫 ' + files.length + ' 个 Swift 文件');
if (fails.length === 0) {
  console.log('privacy: OK — 剪贴板/备份加密/空壳隔离/帧脱敏/WebDAV/文件保护/CSV 注入 7 类回归判据全部通过');
  process.exit(0);
}
console.log('privacy: FAIL — ' + fails.length + ' 处回归\n');
for (const x of fails) console.log('  ' + x);
process.exit(1);
