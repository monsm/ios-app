const fs=require('fs'),path=require('path');
const ROOT=__dirname;
const raw=fs.readFileSync(path.join(ROOT,'features.json'),'utf8');
const json=JSON.parse(raw);
const safe=raw.replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
const tpl=fs.readFileSync(path.join(ROOT,'template.html'),'utf8');
fs.writeFileSync(path.join(ROOT,'feature-web.html'), tpl.replace('__FEATURES_JSON__', safe),'utf8');
console.log('rebuilt via inline');
