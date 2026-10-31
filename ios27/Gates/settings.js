#!/usr/bin/env node
// settings.js -- gate 20: every user-facing switch must have a real consumer.
//
// HIG settings > Best practices: 'Minimize the number of settings you offer.'
// More basic: a switch that is stored, backed up and shown in UI, but read by nothing,
// is worse than no switch - the user changes it and nothing happens.
//
// KEY POINT: judge by STORAGE KEY, not property name. Consumers often read
// UserDefaults directly (DB.store.getString('kf_tl_gap')), bypassing SettingsStore.
// v1 judged by property name and false-positived timelineGap / recordPolicy,
// which both do have consumers.
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out) {
  out = out || [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const NON_CONSUMER = new Set([
  'AppearanceScreen.swift', 'AccessibilityScreen.swift',
  'BackupKit.swift', 'BackupCanonical.swift', 'BackupStudioKit.swift', 'BackupBundle.swift',
  'SettingsScreen.swift',
  'SettingsParts.swift',
]);

const model = fs.readFileSync(path.join(APP, 'Features', 'Settings', 'SettingsModel.swift'), 'utf8');

const propRe = /var\s+([a-zA-Z][A-Za-z0-9_]*)\s*:\s*[A-Za-z0-9_<>\[\].]+\s*\{/g;
const keyRe = /DB\.store\.(?:getString|getBool|getInt|getDouble)\("([^"]+)"/;

const entries = [];
let m;
while ((m = propRe.exec(model)) !== null) {
  const name = m[1];
  const block = model.slice(m.index, m.index + 500);
  if (!/set\s*\{/.test(block)) continue;
  const keyM = block.match(keyRe);
  if (!keyM) continue;
  entries.push({ name: name, key: keyM[1] });
}

const EXEMPT_KEYS = new Set(['kf_revision']);
const files = walk(APP);
const fails = [];

for (const e of entries) {
  if (EXEMPT_KEYS.has(e.key)) continue;
  let consumed = false;
  for (const f of files) {
    if (NON_CONSUMER.has(path.basename(f))) continue;
    const src = fs.readFileSync(f, 'utf8');
    // Consumed EITHER by reading the raw key, OR by reading the SettingsStore property
    // (both are legitimate: tokens read DB directly, views read the @Observable property).
    const byKey = new RegExp("get(?:String|Bool|Int|Double)\\(\\s*\"" + e.key + "\"");
    const byProp = new RegExp("\\." + e.name + "\\b");
    const byDerived = new RegExp("[=:]\\s*" + e.name + "\\b");
    if (byKey.test(src) || byProp.test(src) || byDerived.test(src)) { consumed = true; break; }
  }
  if (!consumed) fails.push(e.name + '  (storage key ' + e.key + ')');
}

if (fails.length === 0) {
  console.log('settings: OK - ' + entries.length + ' settings all have a direct consumer');
  process.exit(0);
}
// WARN-ONLY by design: this check follows DIRECT consumption only (raw key read,
// property read, or one level of derivation). Consumption through a helper
// (e.g. QueryFilters.load -> QueryFilters.policy) is NOT traced, so a hit here
// means "verify by hand", not "provably dead". Making it fail would produce false reds.
console.log('settings: WARN - ' + fails.length + ' setting(s) with no DIRECT consumer - verify by hand:');
for (const x of fails) console.log('  ' + x);
console.log('  (indirect consumption through a helper is not traced by this gate)');
process.exit(0);