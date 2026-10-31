#!/usr/bin/env node
// parity-28.js —— 原 App 28 个 Destination 的可达性对账（报告型）。
//
// 判三件事：
//   ① 原 App 的页面文件/符号存在（审计口径的原文件:行）；
//   ② ios27 里承接它的 Swift 类型真实存在；
//   ③ 若走 Router，则 Dest 有 case、Destinations 有映射（Gates/destmap.js 已判整体，这里判"这 28 项"）。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');
const ORIG = path.resolve(ROOT, '..', 'App');

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}
const origText = walk(ORIG).map((f) => fs.readFileSync(f, 'utf8')).join('\n');
const newText = walk(APP).map((f) => fs.readFileSync(f, 'utf8')).join('\n');
const router = fs.readFileSync(path.join(APP, 'Shell', 'Router.swift'), 'utf8');
const dests = fs.readFileSync(path.join(APP, 'Shell', 'Destinations.swift'), 'utf8');

// 原 28 Destination（AUDIT-A-OMISSION §2 的表）→ ios27 承接类型 + Dest
const MAP = [
  ['AddDeviceView', 'AddDeviceView', 'AddLockScreen', 'addLock'],
  ['BackupView', 'BackupView', 'BackupScreen', 'backup'],
  ['CredentialCalendarView', 'CredentialCalendarView', 'KeyCalendarScreen', 'keyCalendar'],
  ['CredentialsView', 'CredentialsView', 'KeysScreen', 'keys'],
  ['CredExtendView', 'CredExtendView', 'CredentialStudioScreen', 'credentialStudio'],
  ['DefendView', 'DefendView', 'DefendScreen', 'defend'],
  ['DeviceHomeView', 'DeviceHomeView', 'DoorScreen', 'door'],
  ['DeviceInfoView', 'DeviceInfoView', 'DeviceInfoScreen', 'deviceInfo'],
  ['DFUView', 'DFUView', 'DFUScreen', 'dfu'],
  ['DongleView', 'DongleView', 'HardwareScreen', 'hardware'],
  ['GatewayView', 'GatewayView', 'GatewayScreen', 'gateway'],
  ['LockProfileView', 'LockProfileView', 'LockProfileScreen', 'lockProfile'],
  ['LockSettingsView', 'LockSettingsView', 'LockSettingsScreen', 'lockSettings'],
  ['MemberArchivedView', 'MemberArchivedView', 'MemberArchiveScreen', 'memberArchive'],
  ['MemberCenterView', 'MemberCenterView', 'HouseholdScreen', 'household'],
  ['MemberDetail360View', 'MemberDetail360View', 'MemberDetailScreen', 'memberDetail'],
  ['MembersView', 'MembersView', 'HouseholdScreen', 'household'],
  ['MemberWizardView', 'MemberWizardView', 'MemberCreateScreen', 'memberCreate'],
  ['MergeMembersView', 'MergeMembersView', 'MemberMergeSheet', null],
  ['MobileKeyView', 'MobileKeyView', 'MobileKeyScreen', 'mobileKey'],
  ['ProtocolTestView', 'ProtocolTestView', 'ProtocolTestScreen', 'protocolTest'],
  ['RecordsView', 'RecordsView', 'RecordsScreen', 'records'],
  ['SafemodeIntroView', 'SafemodeIntroView', 'SafeModeScreen', 'safeMode'],
  ['SettingsView', 'SettingsView', 'SettingsScreen', 'settings'],
  ['ShareToAndroidView', 'ShareToAndroidView', 'ShareToAndroidScreen', 'shareToAndroid'],
  ['SyncTimeView', 'SyncTimeView', 'SyncTimeScreen', 'syncTime'],
  ['TailgateView', 'TailgateView', 'TailgateScreen', 'tailgate'],
  ['UnlockGateView', 'UnlockGateView', 'UnlockGateScreen', 'unlockGate']
];

let ok = 0;
const bad = [];
for (const [dest, origType, newType, newDest] of MAP) {
  const problems = [];
  if (!new RegExp('\\b(?:struct|class|enum)\\s+' + origType + '\\b').test(origText)) problems.push('原 App 无 ' + origType);
  if (!new RegExp('\\b(?:struct|class|enum)\\s+' + newType + '\\b').test(newText)) problems.push('ios27 无 ' + newType);
  if (newDest) {
    if (!new RegExp('case\\s+' + newDest + '\\b').test(router)) problems.push('Dest 缺 ' + newDest);
    if (!new RegExp('case\\s+\\.' + newDest + '\\s*:').test(dests)) problems.push('Destinations 缺 .' + newDest);
  }
  if (problems.length) bad.push(dest + ' → ' + problems.join(' / '));
  else ok++;
}
console.log('parity-28: 原 App 28 个 Destination，可达 ' + ok + ' / ' + MAP.length);
for (const b of bad) console.log('  ✗ ' + b);
process.exit(bad.length ? 1 : 0);
