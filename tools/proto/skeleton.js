'use strict';
// tools/proto/skeleton.js —— 标题→首卡 74
//
// 关键教训：之前用「.page > .sub + *」做清零，但 .sub 大多**不在 .page 直接子级**
// ——它被包在一个 div 里。所以永远匹配不到，改了 5 次都没生效。
// 现在：找到含 .sub 的那个容器，在它之后插 .sp74。
const fs = require('fs'), path = require('path');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));

let n = 0, skip = 0;
for (const p of reg) {
  const fp = path.join(D, p.f + '.html');
  if (!fs.existsSync(fp)) continue;
  let s = fs.readFileSync(fp, 'utf8');
  if (s.indexOf('class="sub"') < 0) { skip++; continue; }
  const before = s;

  // 幂等：先移除旧的 sp74
  s = s.replace(/\s*<div class="sp74"><\/div>/g, '');
  // 在「含 .sub 的那层容器」结束之后插
  // 容器形如：<div ...>  <div class="sub">…</div>  </div>
  s = s.replace(
    /(<div class="sub"[\s\S]*?<\/div>)(\s*<\/div>)?/,
    function(m, sub, closeTag){
      if (!closeTag) {
        // .sub 直接是 .page 子级
        return sub + '\n\n  <div class="sp74"></div>';
      }
      return sub + closeTag + '\n\n  <div class="sp74"></div>';
    });
  // sp74 之后那块清零 margin-top —— style 属性在 class 之后，[^>]* 会跨过它
  s = s.replace(/(<div class="sp74"><\/div>\s*<div\b[^>]*?)\s*margin-top:\s*\d+px;?/g, '$1');
  // 再兜一层：sp74 后紧跟的 div 若含 margin-top，从 style 里剥掉
  s = s.replace(/(<div class="sp74"><\/div>\s*<div\b[^>]*style=")([^"]*)"/g,
    function(m, pre, style){
      const cleaned = style.split(';').map(function(x){return x.trim();})
        .filter(function(x){return x && x.indexOf('margin-top') !== 0;}).join(';');
      return pre + cleaned + '"';
    });
  // 清掉残留的裸 spacer（旧版 skeleton 留的）
  s = s.replace(/\s*<div style="height:calc\(var\(--title-to-card\)[^<]*<\/div>/g, '');
  if (s !== before) { fs.writeFileSync(fp, s, 'utf8'); n++; }
}
console.log('✓ 插 sp74：' + n + ' 页（' + skip + ' 页无标题）');
