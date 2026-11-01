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
    // 9. 空壳（decoy）模式必须在**数据读取口**生效（N-01/SEC-03 残余）。
    //    这些函数都是"把真实凭证/密钥交给界面"的出口，缺守卫就等于胁迫者仍能看见。
    const DECOY_READERS = [
      'static func keychain(', 'static func dongles(', 'static func gateways(',
      'static func list(_ mac: String) -> [MobileKey]',
      'static func all(_ mac: String) -> [CredBinItem]',
      'static func all(_ mac: String) -> [CredSnapshot]',
      'static func notes(_ mac: String) -> [String: String]',
      'static func ledger(_ mac: String) -> Ledger'
    ];
    if (DECOY_READERS.some((sig) => line.includes(sig))) {
      const window = f.lines.slice(i, i + 12).join('\n');
      if (!/isDecoy/.test(window)) {
        note(f.rel, i + 1, '空壳模式下仍返回真实数据（缺 isDecoy 守卫）', '函数体首行加 if isDecoy { return 空集 }');
      }
    }
    // 12. SEC-01：凭证/手机钥匙/回收站/快照的**明文口令不许进 plist**。
    //     判据：这些结构体的写入口必须经过 SecretStore（Keychain）。
    //     台账：saveLedger 必须走 ledgerForPlist；手机钥匙：save 必须写 Keychain；
    //     回收站/快照：写盘前必须过 safeForPlist / SecretStore.set。
    if (f.rel === 'Engine/StoreLedger.swift' && /static func saveLedger\(/.test(line)) {
      const window = f.lines.slice(i, i + 20).join('\n');
      if (!/ledgerForPlist\(/.test(window)) {
        note(f.rel, i + 1, 'saveLedger 直接把明文口令写进 plist', '先过 ledgerForPlist（Keychain）再落盘');
      }
    }
    if (f.rel === 'Engine/MobileKeyService.swift' && /static func save\(/.test(line)) {
      const window = f.lines.slice(i, i + 18).join('\n');
      if (!/SecretStore\.set/.test(window)) {
        note(f.rel, i + 1, '手机钥匙 pin/ekey 直接写进 plist', '先 SecretStore.set 再落盘');
      }
    }
    if (f.rel === 'Features/Keys/CredentialStudioStores.swift' && /DB\.store\.setCodable\(key\(mac\)/.test(line)) {
      const window = f.lines.slice(Math.max(0, i - 8), i + 2).join('\n');
      if (!/safeForPlist|SecretStore\.set|SecretStore\.remove/.test(window)) {
        note(f.rel, i + 1, '回收站/版本历史把明文口令写进 plist', '写盘前过 safeForPlist / SecretStore');
      }
    }

    // 10. 空壳模式下**禁止写台账**（N-01：空台账会覆盖真实台账，凭证全丢）。
    if (f.rel === 'Engine/StoreLedger.swift' && /static func saveLedger\(/.test(line)) {
      const window = f.lines.slice(i, i + 6).join('\n');
      if (!/isDecoy/.test(window)) {
        note(f.rel, i + 1, 'saveLedger 缺空壳守卫（空表会覆盖真实台账）', '函数体首行加 if isDecoy { return }');
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

// ---------- 11. 隐私清单必须是合法 plist（G-01：非法 XML 会被原样打进 IPA，清单等于没交）----------
// 不用第三方库：只做标签配对（<key>/<string>/<array>/<dict>/<true|false>），
// 足以抓住"多一个 </dict> / 少一个 </array>"这类错误，而且不依赖 plutil。
(function checkPrivacyManifest() {
  const p = path.join(APP, 'PrivacyInfo.xcprivacy');
  if (!fs.existsSync(p)) {
    fails.push('App/PrivacyInfo.xcprivacy 缺失（App Store 要求 Required Reason API 申报）');
    return;
  }
  const src = fs.readFileSync(p, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const stack = [];
  const VOID = new Set(['true', 'false']);
  // 属性（如 <plist version="1.0">）与自闭合（<true/>）都要认。
  const re = /<\/([a-zA-Z]+)>|<([a-zA-Z]+)[^>]*>/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    if (m[1]) {
      const want = stack.pop();
      if (want !== m[1]) {
        fails.push('App/PrivacyInfo.xcprivacy — 标签不配对：期望 </' + want + '> 实得 </' + m[1] + '>（会被原样打进 IPA，隐私清单失效）');
        return;
      }
    } else if (!VOID.has(m[2]) && !m[0].endsWith('/>') && !m[2].toLowerCase().includes('xml') && m[2] !== 'DOCTYPE') {
      stack.push(m[2]);
    }
  }
  if (stack.length !== 0) {
    fails.push('App/PrivacyInfo.xcprivacy — 未闭合标签：' + stack.join(' > '));
    return;
  }
  const must = ['NSPrivacyTracking', 'NSPrivacyAccessedAPITypes', 'NSPrivacyCollectedDataTypes'];
  for (const k of must) {
    if (!src.includes('<key>' + k + '</key>')) fails.push('App/PrivacyInfo.xcprivacy — 缺少必需键 ' + k);
  }
})();

console.log('privacy: 扫 ' + files.length + ' 个 Swift 文件 + PrivacyInfo.xcprivacy');

// 11) 校验和不一致禁止硬拒绝恢复（2026-11-01，我第 8 轮的过度收紧回归）。
// 本仓早期版本导出的包用旧键序 canonical，FNV 必然对不上；
// 硬拒绝会把用户自己的合法备份挡在门外——"恢复不了"比"被截断包覆盖"更糙。
{
  const re = /guard\s+parsed\.preview\.checksum\s*!=\s*\.mismatch\s+else/;
  for (const f of files) {
    const idx = f.raw.search(re);
    if (idx < 0) continue;
    const line = f.raw.slice(0, idx).split('\n').length;
    note(f.rel, line, '硬拒绝校验和不一致的备份', '改用 BackupStudio.checksumNeedsAck 做二次确认');
  }
}

if (fails.length === 0) {
  console.log('privacy: OK — 剪贴板/备份加密/空壳隔离(读+写)/明文口令不进 plist/帧脱敏/WebDAV/文件保护/CSV 注入/隐私清单 XML 10 类回归判据全部通过');
  process.exit(0);
}
console.log('privacy: FAIL — ' + fails.length + ' 处回归\n');
for (const x of fails) console.log('  ' + x);
process.exit(1);
