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


// 2026-11-01：按缩进找到函数体结束。
// 固定行数窗口（slice(i, i + N)）会因注释长短而失效 —— 注释一长，守卫就被推出窗口，
// 正确代码被判红（AUDIT-ROUND-68）。结构性划界不受注释影响。
function bodyEndOf(lines, i) {
  const base = lines[i].length - lines[i].trimStart().length;
  let j = i + 1;
  while (j < lines.length) {
    const l = lines[j];
    const ind = l.length - l.trimStart().length;
    if (l.trim() === '}' && ind === base) break;
    j++;
  }
  return j;
}

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
      const window = f.masked.slice(i, bodyEndOf(f.masked, i) + 1).join(' ');
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
      const window = f.lines.slice(i, bodyEndOf(f.lines, i) + 1).join('\n');
      if (!/isDecoy/.test(window)) {
        note(f.rel, i + 1, '空壳模式下仍返回真实数据（缺 isDecoy 守卫）', '函数体首行加 if isDecoy { return 空集 }');
      }
    }
    // 12. SEC-01：凭证/手机钥匙/回收站/快照的**明文口令不许进 plist**。
    //     判据：这些结构体的写入口必须经过 SecretStore（Keychain）。
    //     台账：saveLedger 必须走 ledgerForPlist；手机钥匙：save 必须写 Keychain；
    //     回收站/快照：写盘前必须过 safeForPlist / SecretStore.set。
    if (f.rel === 'Engine/StoreLedger.swift' && /static func saveLedger\(/.test(line)) {
      const window = f.lines.slice(i, bodyEndOf(f.lines, i) + 1).join('\n');
      if (!/ledgerForPlist\(/.test(window)) {
        note(f.rel, i + 1, 'saveLedger 直接把明文口令写进 plist', '先过 ledgerForPlist（Keychain）再落盘');
      }
    }
    if (f.rel === 'Engine/MobileKeyService.swift' && /static func save\(/.test(line)) {
      const window = f.lines.slice(i, bodyEndOf(f.lines, i) + 1).join('\n');
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
      const window = f.lines.slice(i, bodyEndOf(f.lines, i) + 1).join('\n');
      if (!/isDecoy/.test(window)) {
        note(f.rel, i + 1, 'saveLedger 缺空壳守卫（空表会覆盖真实台账）', '函数体首行加 if isDecoy { return }');
      }
    }
    // 8. CSV 导出必须防公式注入。
    if (f.rel === 'Features/Records/RecordsModels.swift' && /static func field\(_ value: String\)/.test(line)) {
      // 2026-11-01 修正：原来只看"函数签名后 10 行"—— 注释一写长，防护那行就被推出窗口，
      // 于是正确代码被判红（上一轮我只能靠缩短注释绕过）。现在扫到函数体结束。
      let end = i + 1;
      const baseIndent = line.length - line.trimStart().length;
      while (end < f.lines.length) {
        const l = f.lines[end];
        const ind = l.length - l.trimStart().length;
        if (l.trim() === '}' && ind === baseIndent) break;
        end++;
      }
      const srcBody = f.lines.slice(i, end + 1).join('\n');
      if (!/v = "'" \+ v|"'" \+ v/.test(srcBody)) {
        note(f.rel, i + 1, 'CSV 单元格未防公式注入', '首字符 = + - @ 时前置单引号');
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


// 12) 通知排程必须可 await（2026-11-01）。
// addCalendar 曾经是 sync + 内部 Task{ add }（分离异步），而外层串行队列
// 在 add 落地前就 done() 了 —— 所谓 删旧→排新 的顺序根本没生效。
// 现在它必须是 async 并被 await。这条防止它被改回去。
{
  const target = 'Engine/CredentialOrg.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    const m = f.raw.match(/static func addCalendar\s*\([^)]*\)\s*(async)?/);
    if (!m || !m[1]) {
      const line = m ? f.raw.slice(0, f.raw.indexOf(m[0])).split('\n').length : 1;
      note(f.rel, line, 'addCalendar 不是 async：通知排程会回到分离异步，串行队列失效', '改成 async 并由调用方 await');
    }
  }
}

// 13) 清掉通知就必须有重建路径（2026-11-01）。
// cancelAllForDecoy 会把整族通知清掉；本仓没有其它全量重排入口，
// 不重建就是静默功能丢失：界面显示已排程，实际一条都不响。
{
  const am = files.find(function (x) { return x.rel === 'Shell/AppModel.swift'; });
  if (am && am.raw.indexOf('cancelAllForDecoy') >= 0 && am.raw.indexOf('rescheduleAllAlerts') < 0) {
    note(am.rel, 1, '清空通知后没有重建路径', '退出空壳时调用 CredentialOrg.rescheduleAllAlerts()');
  }
}


// 14) 写路径不许走空壳过滤后的读（2026-11-01）。
// CredBinStore / CredHistoryStore 的 all() 在空壳模式返回 []，那是**展示层**语义。
// 写路径若用它，空壳里一次删除/快照就会把整段历史覆盖成只剩新条目（静默数据丢失）。
{
  const target = 'Features/Keys/CredentialStudioStores.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    const writers = ['addPwds', 'addFps', 'restore', 'purge', 'clear', 'capture'];
    for (let i = 0; i < f.lines.length; i++) {
      const line = f.lines[i];
      const w = writers.find(function (n) { return line.indexOf('func ' + n + '(') >= 0; });
      if (!w) continue;
      // 该函数体内（到下一个 func 或文件末，最多 40 行）不许出现 `all(mac)`
      let body = '';
      for (let j = i; j < Math.min(f.lines.length, i + 40); j++) {
        if (j > i && /^\s{4}(private )?(static )?func /.test(f.lines[j])) break;
        body += f.lines[j] + '\n';
      }
      if (/\ball\(mac\)/.test(body)) {
        note(f.rel, i + 1, w + ' 用 all(mac) 读存储：空壳下会返回空并把历史覆盖掉', '改用 stored(mac) 读原始存储');
      }
    }
  }
}


// 15) 删凭证必须清掉钥匙串里的口令副本（2026-11-01）。
// ledgerForPlist 只处理"仍在台账数组里的条目"；条目被移除后那份副本再没人碰过，
// 于是每删一条凭证就在钥匙串里永久多一份可读的开门口令。
{
  const target = 'Engine/StoreLedger.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    const i = f.lines.findIndex(function (l) { return l.indexOf('static func delPwd(') >= 0; });
    if (i >= 0) {
      let body = '';
      for (let j = i; j < Math.min(f.lines.length, i + 24); j++) {
        if (j > i && /^\s{4}(private )?(static )?func /.test(f.lines[j])) break;
        body += f.lines[j] + '\n';
      }
      if (body.indexOf('pwdSecretAccount') < 0) {
        note(f.rel, i + 1, 'delPwd 没有清理钥匙串里的口令副本', '加 SecretStore.remove(pwdSecretAccount(mac, alias))');
      }
    }
  }
}


// 16) RecordOverlay 的写路径同样不许走空壳过滤后的读（2026-11-01）。
// setNote / toggleFlag / setDisposition 若用 notes()/flags()/dispositions()，
// 空壳里改一条就会把整表覆盖成只剩这一条。
{
  const target = 'Engine/RecordSearch.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    const writers = ['setNote', 'toggleFlag', 'setDisposition'];
    const forbidden = /(notes|flags|dispositions)\(mac\)/;
    for (let i = 0; i < f.lines.length; i++) {
      const w = writers.find(function (n) { return f.lines[i].indexOf('func ' + n + '(') >= 0; });
      if (!w) continue;
      let body = '';
      for (let j = i; j < Math.min(f.lines.length, i + 20); j++) {
        if (j > i && /^\s{4}(private )?(static )?func /.test(f.lines[j])) break;
        body += f.lines[j] + '\n';
      }
      if (forbidden.test(body)) {
        note(f.rel, i + 1, w + ' 用展示层读取器（空壳下返回空会把整表覆盖）', '改用 rawNotes/rawFlags/rawDispositions');
      }
    }
  }
}


// 17) MobileKeyService 的写路径不许用 list()（2026-11-01，同一族第三处）。
// list() 在空壳返回 []；issue 会写成"只剩新的一条"、revoke 会写成空表 —— 整批手机钥匙被静默抹掉。
{
  const target = 'Engine/MobileKeyService.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    for (let i = 0; i < f.lines.length; i++) {
      const w = ['issue', 'revoke'].find(function (n) { return f.lines[i].indexOf('func ' + n + '(') >= 0; });
      if (!w) continue;
      let body = '';
      for (let j = i; j < Math.min(f.lines.length, i + 40); j++) {
        if (j > i && /^\s{4}(private )?(static )?func /.test(f.lines[j])) break;
        body += f.lines[j] + '\n';
      }
      if (/\blist\(kc\.mac\)|\blist\(mac\)/.test(body)) {
        note(f.rel, i + 1, w + ' 用 list() 读存储：空壳下返回空会把整批手机钥匙覆盖', '改用 rawList()');
      }
    }
  }
}


// 18) 单条读取器也必须与列表读取器同口径判空壳（2026-11-01）。
// members()/dongles()/gateways() 都判了，而 member(id)/dongle(mac)/gateway(mac) 原本没判 ——
// 空壳里凡是用单条读取器取名字的界面都会显示真实数据。
{
  const target = 'Engine/Store.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    const singles = ['member', 'dongle', 'gateway'];
    for (let i = 0; i < f.lines.length; i++) {
      const n = singles.find(function (s) { return f.lines[i].indexOf('static func ' + s + '(') >= 0 && f.lines[i].indexOf('private') < 0; });
      if (!n) continue;
      let body = '';
      for (let j = i; j < Math.min(f.lines.length, i + 8); j++) body += f.lines[j] + '\n';
      if (body.indexOf('isDecoy') < 0) {
        note(f.rel, i + 1, n + '() 没有空壳过滤（列表读取器有，单条没有 → 不一致泄露）', '加 if isDecoy { return nil }，写路径改用 raw 版本');
      }
    }
  }
}


// 19) 生物识别解锁必须在**模型层**再判一次胁迫码（2026-11-01）。
// UI 的 bioAvailable 只是"入口隐藏"；模型层没有守卫时，任何新调用点都能绕开，
// 而有胁迫码时刷脸会直接暴露"这不是伪装模式"。
{
  const target = 'Engine/AppLock.swift';
  const f = files.find(function (x) { return x.rel === target; });
  if (f) {
    const i = f.lines.findIndex(function (l) { return l.indexOf('func unlockByBiometric(') >= 0; });
    if (i >= 0) {
      let body = '';
      for (let j = i; j < Math.min(f.lines.length, i + 14); j++) body += f.lines[j] + '\n';
      if (body.indexOf('hasDuressCode') < 0) {
        note(f.rel, i + 1, 'unlockByBiometric 没有在模型层判胁迫码', '加 guard !DB.hasDuressCode() else { return false }');
      }
    }
  }
}


// 20) 风险披露文案不许只定义不显示（2026-11-01）。
// `AutoOpen.riskDisclosure` 的注释写着「强制展示，不弱化」，但它曾经全仓零引用 ——
// 也就是说"别人拿你已解锁的手机仍可能自动开门"这句风险，从未出现在任何界面上。
// 这是安全承诺级的前置说明，不是可选文案。
{
  const decl = 'Engine/AutoOpenKit.swift';
  const user = 'Features/Settings/AutoOpenScreen.swift';
  const d = files.find(function (x) { return x.rel === decl; });
  if (d && /static let riskDisclosure/.test(d.raw)) {
    const u = files.find(function (x) { return x.rel === user; });
    // 必须排除注释：文案名会出现在注释里（本条规则自己的注释就写了它），
    // 只数 raw.indexOf 会把注释当成展示。
    const usedInCode = u ? u.lines.some(function (l) {
      return l.indexOf('riskDisclosure') >= 0 && !/^\s*\/\//.test(l);
    }) : false;
    if (!usedInCode) {
      note(user, 1, '风险披露文案定义了却没有任何界面显示', '在自动开门设置页展示 AutoOpen.riskDisclosure');
    }
  }
}


// 21) `keepingAwake(true)` 必须配 `defer` 复位（2026-11-01）。
// 「末尾调一次 false」在抛错/取消路径上不会执行 —— 屏幕会一直亮着（耗电 + 绕过熄屏）。
// 允许两种形态：紧跟 `defer { ... }`，或同函数内稍后出现 `defer`。
{
  for (const f of files) {
    f.lines.forEach(function (line, i) {
      if (line.indexOf('keepingAwake(true)') < 0) return;
      if (/^\s*\/\//.test(line)) return;
      // 同函数体内找 defer（向后 30 行内）
      let hasDefer = false;
      for (let j = i + 1; j < Math.min(f.lines.length, i + 30); j++) {
        if (/defer\s*\{/.test(f.lines[j])) { hasDefer = true; break; }
        if (/^\s2,4}(private )?(static )?func /.test(f.lines[j])) break;   // 出函数了
      }
      if (!hasDefer) {
        note(f.rel, i + 1, 'keepingAwake(true) 没有 defer 复位', '异常路径不会执行末尾复位 → 屏幕常亮');
      }
    });
  }
}

if (fails.length === 0) {
  console.log('privacy: OK — 剪贴板/备份加密/空壳隔离(读+写)/明文口令不进 plist/帧脱敏/WebDAV/文件保护/CSV 注入/隐私清单 XML 10 类回归判据全部通过');
  process.exit(0);
}
console.log('privacy: FAIL — ' + fails.length + ' 处回归\n');
for (const x of fails) console.log('  ' + x);
process.exit(1);
