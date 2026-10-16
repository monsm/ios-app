// 核算 core-ui.html 的文字对比度, 并**反解极光场的亮度上限**。
// 结论要能落到一个具体的 CSS 数值上, 不能停在"应该再暗一点"。
function hx(h){return [parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];}
function over(fg,a,bg){return fg.map(function(c,i){return c*a+bg[i]*(1-a);});}
function toHex(c){return "#"+c.map(function(v){return ("0"+Math.round(v).toString(16)).slice(-2);}).join("");}
function L(c){var s=c.map(function(v){v/=255;return v<=0.03928?v/12.92:Math.pow((v+0.055)/1.055,2.4);});
  return 0.2126*s[0]+0.7152*s[1]+0.0722*s[2];}
function ratio(f,b){var l1=L(f),l2=L(b);return (Math.max(l1,l2)+0.05)/(Math.min(l1,l2)+0.05);}
function r2(x){return Math.round(x*100)/100;}

/* ---------- 文字三档 (与 CSS 里的 --ink/--sub/--faint 同源) ---------- */
var TIERS={
  dark :{ink:[hx("#F2F6FB"),1.00], sub:[[242,246,251],0.78], faint:[[242,246,251],0.56],
         tag:[hx("#F2F6FB"),0.82], graphic:[hx("#F2F6FB"),0.56]},
  light:{ink:[hx("#0D1626"),1.00], sub:[[13,22,38],0.80],    faint:[[13,22,38],0.68],
         tag:[hx("#0D1626"),0.82], graphic:[hx("#0D1626"),0.56]}
};

/* ---------- 背景模型 ---------- */
// 光团走 mix-blend-mode: screen, 且**三团会重叠** —— 最坏情况是两团圆心叠在一起,
// 只建单团会低估底色亮度 (第一版就是这么漏的)。
function screen(b,c){return b.map(function(v,i){return 255-(255-v)*(255-c[i])/255;});}
function blobLayer(base,blobHex,A,mode){
  // 浅色档光团走 multiply, 且浓度按 CSS 里的 .34 折
  var eff=mode==="dark"?A:A*0.34;
  var b=hx(blobHex);
  var mixed=mode==="dark"?screen(base,b):base.map(function(v,i){return v*b[i]/255;});
  return over(mixed,eff,base);
}
// veil 是 radial-gradient(120% 80% at 50% 62%, transparent 30%, rgba(2,4,10,.72) 100%)。
// 强度必须按**文字的真实落点**算, 不能按区域拍一个数 —— 第一版把顶部估成 0.72,
// 实际只有 0.48, 等于把最坏情况估轻了。
var VEIL_PEAK=0.72, VEIL_STOP=0.30;
function veilAt(x,y){
  var dx=(x-0.50)/1.20, dy=(y-0.62)/0.80, r=Math.sqrt(dx*dx+dy*dy);
  if(r<=VEIL_STOP)return 0;
  if(r>=1)return VEIL_PEAK;
  return VEIL_PEAK*(r-VEIL_STOP)/(1-VEIL_STOP);
}
// 四处文字落点 (归一化到 400×860 的机身坐标) + 该落点**实际存在**的文字档。
// "所有档 × 所有落点"是过保守的: faint 根本不出现在锁核带, 按全交叉解会把极光压得过暗。
// graphic = 图标描边 (SVG stroke), WCAG 非文字门槛 3:1, 不是 4.5:1。
var SPOTS={
  top  :{x:0.10,y:0.09,tiers:["ink","sub","faint"]},   // kicker / 锁名 / 电量 / 状态大字 / meta
  core :{x:0.82,y:0.56,tiers:["tag","graphic"]},       // 卫星标签 + 图标描边
  hint :{x:0.50,y:0.72,tiers:["sub"]},                 // 锁核下方提示 (原用 faint, 已提到 sub)
  sheet:{x:0.15,y:0.32,tiers:["ink","faint"]}          // 浮层标题 / 正文 / 大写小标签
};
var MINT={ink:4.5,sub:4.5,faint:4.5,tag:4.5,graphic:3.0};
function veilOf(s){return veilAt(SPOTS[s].x,SPOTS[s].y);}
console.log("== veil 在各文字落点的实际强度 (按 CSS 几何算, 非估值) ==");
Object.keys(SPOTS).forEach(function(s){
  console.log("  "+s+"  ("+SPOTS[s].x+", "+SPOTS[s].y+")  veil="+veilOf(s).toFixed(3)
    +"  档位["+SPOTS[s].tiers.join(",")+"]");});

// 光团色 → 机身底色, 单团不透明度 A; 再叠该落点的 veil
function bg(mode,blobHex,A,veilA){
  var base=hx(mode==="dark"?"#05070C":"#F4F6FB");
  // 最坏: 主团 (#0891B2) 与紫团 (#6D28D9) 圆心重合
  var g=blobLayer(base,"#6D28D9",A,mode);
  g=blobLayer(g,blobHex,A,mode);
  var veil=mode==="dark"?hx("#02040A"):[255,255,255];
  return over(veil,veilA,g);
}

/* ---------- 1. 反解: 全部落点 × 全部文字档都过 4.5 的最大光团不透明度 ---------- */
function worstTier(mode,A){
  // 不同档门槛不同 (文字 4.5 / 图形 3.0), 所以比的是"实测值 ÷ 各自门槛", 不是原始比值。
  var wm=99,wv=0,arg="";
  Object.keys(SPOTS).forEach(function(s){
    var b=bg(mode,"#0891B2",A,veilOf(s));
    if(s==="sheet")b=mode==="dark"?over([18,24,38],0.62,b):over([255,255,255],0.86,b);
    SPOTS[s].tiers.forEach(function(k){
      var t=TIERS[mode][k], v=ratio(over(t[0],t[1],b),b), m=v/MINT[k];
      if(m<wm){wm=m;wv=v;arg=s+"/"+k;}
    });
  });
  return {v:wv,m:wm,at:arg};
}
console.log("\n== 反解: 各落点在其实际档位下全部达标的光团不透明度上限 ==");
var ceil=0;
for(var a=1.00;a>=0.001;a-=0.001){ if(worstTier("dark",a).m>=1){ceil=a;break;} }
// 不留余量的上限不可用: 刚好压线 = 零余量, 光团一动 (blur 半径 / 漂移关键帧) 就掉下去。
// 取上限的 86% 作为施工值。
var A=Math.floor(ceil*0.86*1000)/1000;
console.log(" 零余量上限 A_max = "+ceil.toFixed(3)+"   (当前 CSS 用的是 0.920)");
console.log(" 施工取值 A     = "+A.toFixed(3)+"  (上限的 86%, 留余量)");
var wc=worstTier("dark",A);
console.log(" 该值下最紧的点 = "+r2(wc.v)+":1 @ "+wc.at+"  (余量 ×"+wc.m.toFixed(3)+")");

/* ---------- 2. 用施工值重算全表 ---------- */
var bgs={};
["dark","light"].forEach(function(m){ bgs[m]={};
  Object.keys(SPOTS).forEach(function(s){ bgs[m][s]=bg(m,"#0891B2",A,veilOf(s)); }); });
// 浮层内文字还压在玻璃上: sheet 渐变浅端 rgba(18,24,38,.62) / rgba(255,255,255,.86)
bgs.dark.sheet =over([18,24,38],0.62,bgs.dark.sheet);
bgs.light.sheet=over([255,255,255],0.86,bgs.light.sheet);

console.log("\n== 采用 A="+A.toFixed(3)+" 后的最坏背景 ==");
["dark","light"].forEach(function(m){
  var o=[]; Object.keys(bgs[m]).forEach(function(s){o.push(s+"="+toHex(bgs[m][s]));});
  console.log(" "+m+": "+o.join("  "));
});

var N=0; Object.keys(SPOTS).forEach(function(s){N+=SPOTS[s].tiers.length;});
console.log("\n== 全表 (2 模式 × "+N+" 个「落点/档位」对 = "+(2*N)+" 组合) ==");
var pass=0,fail=0,rows=[],flist=[];
["dark","light"].forEach(function(m){
  Object.keys(bgs[m]).forEach(function(s){
    var b=bgs[m][s];
    SPOTS[s].tiers.forEach(function(k){
      var t=TIERS[m][k], v=ratio(over(t[0],t[1],b),b), ok=v>=MINT[k];
      ok?pass++:fail++;
      if(!ok)flist.push(m+"/"+s+"/"+k+"="+r2(v));
      rows.push((ok?" PASS":" FAIL")+"  "+m+"/"+s+"  "+k+"  "+r2(v)+":1  (门槛 "+MINT[k]+")");
    });
  });
});
rows.forEach(function(r){console.log(r);});
console.log("\npass="+pass+" fail="+fail+(fail?"   报出的: "+flist.join("  "):""));
console.log("判据形状: 覆盖点数 "+pass+"+"+fail+" = "+(2*N)+" = 2 模式 × Σ(各落点实际档位) [top3+core2+hint1+sheet2]×2;");
console.log("          文字门槛 4.5:1, 图形描边 3.0:1 (WCAG 非文字)。");
console.log("          正控 = 把 A 调回 0.920 必须报出 FAIL (见下节), 0 条 FAIL 即尺子坏了。");

/* ---------- 3. 正控: 证明这把尺子会响 ---------- */
console.log("\n== 正控 (A=0.920, 即改前) ==");
var pc=0,pf=0,plist=[];
["dark","light"].forEach(function(m){
  Object.keys(SPOTS).forEach(function(s){
    var b=bg(m,"#0891B2",0.920,veilOf(s));
    if(s==="sheet")b=m==="dark"?over([18,24,38],0.62,b):over([255,255,255],0.86,b);
    SPOTS[s].tiers.forEach(function(k){
      var t=TIERS[m][k],v=ratio(over(t[0],t[1],b),b);
      if(v>=MINT[k])pc++;else{pf++;plist.push(m+"/"+s+"/"+k+"="+r2(v));}
    });
  });
});
console.log(" pass="+pc+" fail="+pf+(pf>0?"   ← 尺子会响, 不是恒真":"   ← 尺子坏了 (0 条 FAIL)"));
console.log(" 报出的: "+plist.join("  "));

/* ---------- 4. 解卫星图标待机不透明度 (graphic 档唯一未达标项) ---------- */
console.log("\n== 解 .sat .g 待机不透明度 (A="+A.toFixed(3)+", 门槛 3.0:1) ==");
["dark","light"].forEach(function(m){
  var b=bgs[m].core, need=0;
  for(var al=0.01;al<=1.0001;al+=0.01){
    var c=m==="dark"?hx("#F2F6FB"):hx("#0D1626");
    if(ratio(over(c,al,b),b)>=MINT.graphic){need=al;break;}
  }
  var cur=0.56;   // 与 core-ui.html 里 .sat .g 的 opacity 同源, 改一处要改两处
  console.log("  "+m+": 最小可用 = "+need.toFixed(2)+(need>cur?"   ← 当前 "+cur.toFixed(2)+" 不够, 需提到 "+need.toFixed(2):"   ← 当前 "+cur.toFixed(2)+" 够"));
});
/* ================= 5. 尺子原先一问都没问的那五类 ================= */
/* 独立评审用渲染像素实测报出浅色模式六处跌破底线。回源后确认不是它夸张, 是我的覆盖点太少 ——
   上面 16 个「落点×档位」对**全是文字 + 一根图标描边**, 没有一问是关于「一个非文字对象
   能不能被看见」的。门槛按 WCAG 1.4.11 非文字 3.0:1; 有色警示**文字**仍走 4.5。 */
var GMIN=3.0;
function pageBg(mode,A){return bg(mode,"#0891B2",A,0);}          // 锁核带: veil=0, 极光最亮处
function sheetBg(mode,A){var b=bg(mode,"#0891B2",A,veilOf("sheet"));
  return mode==="dark"?over([18,24,38],0.62,b):over([255,255,255],0.86,b);}

// 当前 CSS 里的非文字取值。改一处 CSS 必须同步这里, 否则尺子在量一个不存在的界面。
// 2026-10-16 施工值 = 本脚本第 6 / 6b 节反解出来的结果, 已回填进 core-ui.html。
//   轮廓 edgeA 走 1.4.11 的 3.0; 盘体 bodyA 走 1.10 高光软门槛, 空轨 rimA 不设门槛;
//   浅色进度弧 bar 另配一组深色 stop (深色档维持 #cg)。目标一律 = 门槛 × HEAD。
//   见第 6 节末尾的开口 —— 它是"过门槛但没留够余量", 不是"已解决"。
var CUR={
  dark :{edgeC:[255,255,255], edgeA:0.525,  rimC:[255,255,255], rimA:0.035,  offA:0.13, offC:[255,255,255],
         warn:hx("#FBBF24"), bodyA:0.095,  bodyC:[255,255,255],
         bar:[hx("#22D3EE"),hx("#C7D2FE"),hx("#F0ABFC")]},
  light:{edgeC:[13,22,38],    edgeA:0.55,  rimC:[13,22,38],    rimA:0.10,  offA:0.14, offC:[13,22,38],
         warn:hx("#836313"), bodyA:0.845, bodyC:[255,255,255],
         bar:[hx("#0E7490"),hx("#4338CA"),hx("#86198F")]}   // 浅色档进度弧 = 第 6b 节候选 A, 已配 #cgl
  // edgeA = .body 描边 (物体轮廓, 走 3.0)   rimA = .rim .trk 空轨 (进度沟, **不设门槛**)
  // 上一轮把 3.0 挂在 rimA 上, 和进度弧撞车; 这一轮分开: 轮廓 0.525/0.55, 空轨退回 0.035/0.10。
};
var BEFORE={   // 改前的坏值, 正控退回这里
  dark :{edgeA:0.30, rimA:0.11, offA:0.12, bodyA:0.055, warn:hx("#FBBF24")},
  light:{edgeA:0.10, rimA:0.10, offA:0.14, bodyA:0.60,  warn:hx("#FBBF24")}
};
// 上一版这里把 --acc 写死成浅色的 #4338CA、把平铺档的字色写死成深色的 #F2F6FB ——
// 于是深色那组量的是浅色的按钮、浅色那组量的是深色的字, 两边一起报假 FAIL。
// 一个量算两次, 第二次必须和第一次同源: 色值按 mode 取, 和 CSS 的 [data-mode] 分支一一对应。
var INK ={dark:hx("#F2F6FB"), light:hx("#0D1626")};
// .sw.on 是 linear-gradient(90deg,--acc,--acc2), 两端都可能出现, 所以取**两端里更差的那个**
var ACCS={dark:[hx("#A5B4FC"),hx("#22D3EE")], light:[hx("#4338CA"),hx("#0E7490")]};

function gchecks(mode,A){
  var pb=pageBg(mode,A), sb=sheetBg(mode,A), c=CUR[mode], out=[];
  var disc=over(c.bodyC,c.bodyA,pb);   // 盘体压在页面上
  var edge=over(c.edgeC,c.edgeA,pb);   // .body 的描边 = 物体的轮廓
  var rim =over(c.rimC,c.rimA,disc);   // .rim .trk 空轨压在盘体上
  // 上一轮把 1.4.11 的 3.0 边界门槛挂在 `.rim .trk`(进度空轨)上, 这一轮两个约束一撞就露馅:
  // 空轨要够深才撑得起轮廓 → 进度弧得比空轨更抢眼 → 只能更深 → 两圈糊成一圈, 反解报"四组都不过"。
  // 真正该承担「锁核是个物体」这条边界的是**盘体自己的描边** .body border; 空轨只是轨道。
  // 门槛因此拆成三条: 轮廓 3.0 / 盘体 1.3 / 空轨 1.3, 进度弧再单独和这两圈比。
  out.push({k:"核轮廓对页面底", v:ratio(edge,pb), min:GMIN,
            note:".body 描边 = 锁核的边界, 1.4.11 讲的「理解界面所必需的视觉信息」落在它身上"});
  out.push({k:"核盘体对页面底", v:ratio(disc,pb), min:1.10,
            note:"软门槛: 盘体只负责「玻璃更厚」的高光。边界已由 .body 描边走 3.0, 这里再要 1.30 就是逼盘体变亮、反过来压掉压在它上面的进度弧 (实测 2.66) —— 降到 1.10"});
  // 「空轨对盘体 ≥1.15」这一行**删掉了**, 理由要留在原地: 它是我自己发明的门槛, 没有任何外部依据,
  // 而它和「进度弧对空轨 ≥3.0」夹出一个无解的三明治 —— 沟要比盘体看得见, 弧又要比沟强 3.45 倍,
  // 于是盘体、沟、弧三档亮度被要求排开 4 倍, 而它们本来就在同一圈 2.5px 上。
  // 空轨的可见性是**构造保证**的: 它就是同一条环上没被弧扫到的那部分, 弧已经比盘体强 3.18 倍,
  // 沟按定义就是较弱的另一半。真正要判的只有「弧对盘体」和「弧对空轨」两条。
  var off=over(c.offC,c.offA,sb);
  var onWorst=Math.min.apply(null,ACCS[mode].map(function(a){return ratio(over(a,1.0,sb),sb);}));
  var onVsOff=Math.min.apply(null,ACCS[mode].map(function(a){return ratio(over(a,1.0,sb),off);}));
  // 门槛的**形状**在这里改过一次, 理由要留在原地, 不然下一个人只会看到两个奇怪的数:
  // 原先给 OFF 轨道也定了 3.0, 于是反解报「单拧这一个拧不出来」—— 因为 ON 是深色实底,
  // 把 OFF 也拧深会同时把「ON 对 OFF」压下去, 两条互相回滚。这不是配色无解, 是我把
  // 1.4.11 用错了地方: 开关里"理解界面所必需的视觉信息"是**状态**, 不是轨道的边缘;
  // 轨道边缘另有滑块位置和胶囊轮廓两条线索。所以状态那条保持 3.0, 轨道存在感降到 1.3。
  out.push({k:"开关OFF对浮层底", v:ratio(off,sb), min:1.30, note:"轨道存在感 (状态线索不止这一条)"});
  out.push({k:"开关ON对浮层底",  v:onWorst,      min:GMIN, note:"--acc/--acc2 两端里更差的那个"});
  out.push({k:"开关ON对OFF",     v:onVsOff,      min:GMIN,
            note:"**这条才是 1.4.11 真正管的东西**: 状态不能只靠滑块位置; 浅色下 .sw.on 被 #cor[data-mode=light] .sw 的特异度压掉, 实测 1.02"});
  out.push({k:"到期警示文字",     v:ratio(over(c.warn,1.0,sb),sb), min:4.5,
            note:"它是文字, 走 4.5 不走 3.0"});
  // —— 进度弧两行是**第二轮评审逼出来的覆盖点**, 不是原表漏抄:
  // 上一轮为了把 rim 顶到 3.0, 把空轨 .trk 在浅色档抬到 rgba(13,22,38,.55),
  // 而 .bar 用的还是深色档那组亮青/亮紫 —— 于是"已充能"比"还没充"更淡, 主操作的反馈层级反了。
  // 尺子当时不会响, 因为表里没有"进度弧"这一项。修一个量, 必须把被它压到的那个量一起量。
  var arcVsDisc=Math.min.apply(null,c.bar.map(function(a){return ratio(over(a,1.0,disc),disc);}));
  var arcVsTrk =Math.min.apply(null,c.bar.map(function(a){return ratio(over(a,1.0,disc),rim);}));
  out.push({k:"进度弧对盘体", v:arcVsDisc, min:GMIN, note:".rim .bar 三段渐变里最淡的那端, 门槛取整圈最小值不是端点"});
  out.push({k:"进度弧对空轨", v:arcVsTrk, min:GMIN, note:"**这条是层级**: 已充能必须比没充的那段抢眼, 上一轮就是栽在这里"});
  // 平铺档: 三行落在机身下部, 那里 veil 强、极光被压暗 —— 原先整个形态一个覆盖点都没有
  var fb=bg(mode,"#0891B2",A,veilAt(0.50,0.85));
  out.push({k:"平铺档标签", v:ratio(over(INK[mode],0.95,fb),fb), min:4.5, note:"data-flat 三行的标签"});
  out.push({k:"平铺档图标", v:ratio(over(INK[mode],0.85,fb),fb), min:GMIN, note:"data-flat 三行的图标"});
  return out;
}
var gfail=0,gpass=0,grows=[];
console.log("\n== 新增五类覆盖点 (非文字 3.0 / 有色文字 4.5), 用**当前** CSS 取值 ==");
["dark","light"].forEach(function(m){
  console.log(" ["+m+"]");
  gchecks(m,0.414).forEach(function(c){
    var ok=c.v>=c.min; ok?gpass++:gfail++;
    grows.push(m+" | "+c.k+" | "+r2(c.v)+":"+c.min+(ok?" PASS":" FAIL"));
    console.log("   "+(ok?"PASS":"FAIL")+"  "+c.k+"  "+r2(c.v)+":1 (门槛 "+c.min+")   "+c.note);
  });
});
console.log(" 新增覆盖点 pass="+gpass+" fail="+gfail+"  →  全表覆盖点数 = 16 + "+(gpass+gfail)+" = "+(16+gpass+gfail));

/* ---------- 6. 反解各模式的旋钮 (浅色和深色的病都不是「场太亮」, 是「东西太浅」) ---------- */
function bad(mode,prefixes,head){
  var h=head||1;
  return gchecks(mode,0.414).some(function(c){
    return c.v<c.min*h && prefixes.some(function(p){return c.k.indexOf(p)>=0;});});
}
// 一次只拧一个旋钮、且把**已经拧过的**旋钮带进约束里一起判 —— 否则 rim 拧完再去拧轨道,
// 会把 rim 那一条又判回 FAIL, 两个旋钮互相回滚。
// HEAD=1.15: 反解找的是"带余量的施工值", 不是"刚好踩线的值"。踩线值不能交出去 ——
// 光团一动 (blur 半径 / 漂移关键帧 / 骑乘位缩放) 就掉回门槛以下, 和上面 A 取上限 86% 是同一条纪律。
var HEAD=1.15;
function solve(mode,plan){
  var log=[];
  plan.forEach(function(step){
    var start=CUR[mode][step.key];
    if(!bad(mode,step.watch,HEAD)){log.push("  "+mode+" | "+step.name+": 当前 "+start+" 已带余量, 不动");return;}
    var hit=null;
    for(var a=start;a<=0.95;a+=0.005){
      CUR[mode][step.key]=a;
      if(!bad(mode,step.watch,HEAD)){hit=Math.round(a*1000)/1000;break;}
    }
    if(hit===null){CUR[mode][step.key]=start;log.push("  "+mode+" | "+step.name+": **单拧这一个拧不出来** (从 "+start+" 到 0.95 都不能让 ["+step.watch.join()+"] 同时带余量通过)");}
    else{CUR[mode][step.key]=hit;log.push("  "+mode+" | "+step.name+": "+start+"  →  施工值 "+hit+"  (下限之上再留 "+((HEAD-1)*100).toFixed(0)+"%)");}
  });
  return log;
}
console.log("\n== 反解: 每个模式要拧哪些旋钮 (watch 里带上前面已拧的, 一起判; 目标 = 门槛 × "+HEAD+") ==");
var PLAN=[
  {key:"bodyA",name:"核盘体不透明度",watch:["核盘体"]},
  {key:"edgeA",name:"核轮廓描边 alpha",watch:["核盘体","核轮廓"]}
];
// rimA(空轨) 与 offA(开关 OFF 轨道) **不在 PLAN 里**, 两个都是刻意的:
//   空轨 —— 给它存在感门槛会把沟拧成实心圈, 反过来压掉进度弧, 强弱交给「弧对空轨」那条判;
//   OFF 轨道 —— 浅色档抬 alpha 会同时把 ON-vs-OFF 压到 3.0 以下, 两头不能都赢,
//     第二轮独立评审复算后确认这个耦合是真的, 并建议按"平台基线"记录而不是每轮重解。
var KNOWN=[
  "light 开关 OFF 轨道: 停在 0.14, 过 1.30 门槛但没留够余量 —— 抬它会撞 ON-vs-OFF, 记为平台基线",
  "rimA 空轨: 不设存在感门槛, 只由「进度弧对空轨 ≥3.0」管强弱"
];
var solved={};
["dark","light"].forEach(function(m){
  var before=JSON.parse(JSON.stringify(CUR[m]));
  solve(m,PLAN).forEach(function(l){console.log(l);});
  solved[m]={bodyA:CUR[m].bodyA,edgeA:CUR[m].edgeA,rimA:CUR[m].rimA,offA:CUR[m].offA};
  CUR[m]=before;
});
console.log(" 已知开口 (不每轮重解; 要动这两条, 先在上面那段注释里写明理由):");
KNOWN.forEach(function(x){console.log("   · "+x);});
var wcol=null,sbL=sheetBg("light",0.414);
for(var k=1.0;k>=0.05;k-=0.01){
  var cand=CUR.light.warn.map(function(v){return v*k;});
  if(ratio(over(cand,1.0,sbL),sbL)>=4.5*HEAD){wcol=cand;break;}   // 同样留余量, 不踩线
}
console.log("  light | 到期警示色: "+toHex(CUR.light.warn)+"  →  乘 "+r2(k)+" = "+toHex(wcol)+"  (浅色档专用, 深色 #FBBF24 实测已过)");
console.log("  注: 上面都是**下限**, 施工值各留一档余量。浅色的极光上限 A 不该沿用深色解出来的 0.414 ——");
console.log("      浅色是 multiply 折 .34, 场再暗也不会让白盘浮起来, 病根在描边/轨道/警示色本身。");

/* ---------- 6b. 进度弧: 浅色档换一组深色 stop ---------- */
// .bar 的 stroke 是 SVG 里的 <linearGradient id="cg">, **两档共用一份** —— 这就是浅色档
// "已充能比没充还淡"的根因。解法不是调 alpha, 是给浅色档另配一组同色相的深色 stop。
// 搜索空间是"同一族色相的深一档", 不是任意 RGB: 品牌那三个色相 (青/靛/品红) 不能换。
console.log("\n== 进度弧 .rim .bar: 浅色档候选三组 (同色相、深一档), 门槛 3.0 × "+HEAD+" ==");
var CANDS={
  "维持现状 (两档共用 #cg)":[hx("#22D3EE"),hx("#C7D2FE"),hx("#F0ABFC")],
  "候选 A cyan700/ind700/fuc700":[hx("#0E7490"),hx("#4338CA"),hx("#86198F")],
  "候选 B cyan800/ind700/fuc800":[hx("#155E75"),hx("#4338CA"),hx("#701A75")],
  "候选 C cyan700/ind800/fuc800":[hx("#0E7490"),hx("#312E81"),hx("#701A75")]
};
var barPick=null;
Object.keys(CANDS).forEach(function(nm){
  CUR.light.bar=CANDS[nm];
  var g=gchecks("light",0.414), a=g.filter(function(c){return c.k.indexOf("进度弧")>=0;});
  var ok=a.every(function(c){return c.v>=c.min*HEAD;});
  console.log("  "+(ok?"PASS":"FAIL")+"  "+nm+"  →  弧对盘体 "+r2(a[0].v)+":1  弧对空轨 "+r2(a[1].v)+":1");
  if(ok&&!barPick)barPick={nm:nm,hex:CANDS[nm].map(toHex)};
});
CUR.light.bar=barPick?CANDS[barPick.nm]:CANDS["维持现状 (两档共用 #cg)"];
console.log(barPick?(" → 施工值: "+barPick.nm+"  =  "+barPick.hex.join(" → ")+"  (浅色档另配一组深色 stop, 深色档维持 #cg)")
                 :" → 四组都不带余量通过: 需要动色相或加描边, 交回人定, 不在这里硬凑");

/* ---------- 7. 新尺子的正控与反控 ---------- */
// 正控 = 把四个旋钮退回**改前**的值, 必须报出 FAIL; 反控 = 用解出的值, 必须 0 条 FAIL。
// 两头都过, 才说明这 16 个新覆盖点既不是恒真也不是摆设。
var pc2=0,pf2=0;
["dark","light"].forEach(function(m){
  CUR[m].bodyA=solved[m].bodyA; CUR[m].edgeA=solved[m].edgeA; CUR[m].rimA=solved[m].rimA; CUR[m].offA=solved[m].offA;
});
CUR.light.warn=wcol;
["dark","light"].forEach(function(m){gchecks(m,0.414).forEach(function(c){c.v>=c.min?pc2++:pf2++;});});
["dark","light"].forEach(function(m){
  CUR[m].bodyA=BEFORE[m].bodyA; CUR[m].edgeA=BEFORE[m].edgeA; CUR[m].rimA=BEFORE[m].rimA; CUR[m].offA=BEFORE[m].offA;
});
CUR.light.warn=BEFORE.light.warn;
var qc2=0,qf2=0;
["dark","light"].forEach(function(m){gchecks(m,0.414).forEach(function(c){c.v>=c.min?qc2++:qf2++;});});
["dark","light"].forEach(function(m){
  CUR[m].bodyA=solved[m].bodyA; CUR[m].edgeA=solved[m].edgeA; CUR[m].rimA=solved[m].rimA; CUR[m].offA=solved[m].offA;
});
CUR.light.warn=wcol;
console.log("\n== 新尺子的正控与反控 ==");
console.log(" 施工值 (盘体/轮廓/空轨/OFF 按模式解出 + 浅色警示色 "+toHex(wcol)+" + 浅色进度弧):");
["dark","light"].forEach(function(m){
  console.log("   "+m+"  bodyA="+solved[m].bodyA+"  edgeA="+solved[m].edgeA+"  rimA="+solved[m].rimA+"  offA="+solved[m].offA
    +"  warn="+toHex(CUR[m].warn));
});
console.log(" 反控 (按上面施工值改完): pass="+pc2+" fail="+pf2+"   ← 必须 0 条 FAIL");
console.log(" 正控 (退回改前坏值):      pass="+qc2+" fail="+qf2+"   ← 必须 >0, 为 0 说明这五类覆盖点是空的");
console.log(" 判据形状: 文字 16 点 + 非文字/有色文字/平铺档 "+(gpass+gfail)+" 点 = "+(16+gpass+gfail)+" 点;");
console.log("          每模式三个旋钮 (盘体 / rim / OFF 轨道) + 浅色一个警示色。");
grows.forEach(function(x){console.log("   · "+x);});
// 退出码: 文字表有 FAIL / 文字正控一条不报 / 新覆盖点有 FAIL / 新表反控有 FAIL / 新表正控一条不报
//   —— 注意 pf2 是**反控**的失败数, 必须为 0 才算过; qf2 是**正控**的失败数, 必须 >0 才说明尺子会响。
/* ---------- 8. 防漂移: 上面那批数**从 core-ui.html 里读**, 不靠我手抄 ---------- */
/* 这一节是本轮自己撞出来的教训换来的: 我把 CSS 的 .rim .trk 从 .11 一路改到 .035,
   而 CUR 里还留着 .11 —— 于是连着两轮"改了值、数字不动", 我差点以为是模型错。
   同一个量算两次必已不一致; 唯一的根治是让尺子去读那个唯一的真源。
   判据形状: 12 条 CSS 锚点, 任一条对不上就 exit 2 并点名是哪条 —— 不许静默量一个不存在的界面。 */
(function(){
  var src;
  try{ src=require('fs').readFileSync(__dirname+'/core-ui.html','utf8'); }
  catch(e){ console.log("\n!! 读不到 core-ui.html, 防漂移检查没跑 —— 这次的结果不可信"); process.exit(2); }
  function re1(rx,what){ var m=rx.exec(src); if(!m){DRIFT.push("锚点找不到: "+what);return null;} return m[1]; }
  var DRIFT=[];
  function chk(label,got,want){
    if(got===null)return;
    var g=String(got).toLowerCase(), w=String(want).toLowerCase();
    var ng=parseFloat(g), nw=parseFloat(w);
    if(!isNaN(ng)&&!isNaN(nw)){ if(Math.abs(ng-nw)>1e-9) DRIFT.push(label+": CSS 里是 "+g+", 尺子里是 "+w); return; }
    var mg=/#[0-9a-f]{6}/.exec(g), mw=/#[0-9a-f]{6}/.exec(w);            // hex: 只比那六个字符, 别把 stop-color= 比进去
    if(mg&&mw){ if(mg[0]!==mw[0]) DRIFT.push(label+": CSS 里是 "+mg[0]+", 尺子里是 "+mw[0]); return; }
    if(g!==w)DRIFT.push(label+": CSS 里是 "+g+", 尺子里是 "+w);
  }
  chk("dark.rimA",  re1(/\.rim \.trk\{[^}]*?rgba\(255,255,255,([\d.]+)\)/,".rim .trk 深色"), CUR.dark.rimA);
  chk("light.rimA", re1(/light"\] \.rim \.trk\{stroke:rgba\(13,22,38,([\d.]+)\)/,".trk 浅色"), CUR.light.rimA);
  chk("dark.edgeA", re1(/\.body\{[^}]*?border:\.5px solid rgba\(255,255,255,([\d.]+)\)/,".body 深色描边"), CUR.dark.edgeA);
  chk("light.edgeA",re1(/light"\] \.body\{[^}]*?border-color:rgba\(13,22,38,([\d.]+)\)/,".body 浅色描边"), CUR.light.edgeA);
  chk("dark.offA",  re1(/\.sw\{[^}]*?background:rgba\(255,255,255,([\d.]+)\)/,".sw 深色轨道"), CUR.dark.offA);
  chk("light.offA", re1(/light"\] \.sw\{background:rgba\(13,22,38,([\d.]+)\)/,".sw 浅色轨道"), CUR.light.offA);
  chk("dark.bodyA", re1(/\.body\{[^}]*?rgba\(255,255,255,([\d.]+)\) 42%/,".body 深色 42% 档"), CUR.dark.bodyA);
  chk("light.bodyA",re1(/light"\] \.body\{[^}]*?rgba\(255,255,255,([\d.]+)\) 50%/,".body 浅色 50% 档"), CUR.light.bodyA);
  chk("dark.warn",  re1(/\.row \.val\.warn\{color:(#[0-9a-f]{6})\}/i,".val.warn 深色"), toHex(CUR.dark.warn));
  chk("light.warn", re1(/light"\] \.row \.val\.warn\{color:(#[0-9a-f]{6})\}/i,".val.warn 浅色"), toHex(CUR.light.warn));
  var cg=(src.match(/<linearGradient id="cg"[\s\S]*?<\/linearGradient>/)||[""])[0];
  var cgl=(src.match(/<linearGradient id="cgl"[\s\S]*?<\/linearGradient>/)||[""])[0];
  CUR.dark.bar.forEach(function(c,i){ chk("dark.bar["+i+"]",  (cg.match(/stop-color=\"(#[0-9a-f]{6})\"/gi)||[])[i], toHex(c)); });
  CUR.light.bar.forEach(function(c,i){chk("light.bar["+i+"]", (cgl.match(/stop-color=\"(#[0-9a-f]{6})\"/gi)||[])[i], toHex(c)); });
  console.log("\n== 防漂移: 12 组锚点回读 core-ui.html ==");
  if(DRIFT.length){ DRIFT.forEach(function(d){console.log("   MISMATCH  "+d);});
    console.log(" → 尺子在量一个不存在的界面, 上面所有数字作废。把 CUR 改成 CSS 的实际值再跑。");
    process.exit(2); }
  console.log("   全部一致 (rimA / edgeA / offA / bodyA / warn / bar×3 × 两模式 = "+(12+6)+" 个锚点)");
})();
process.exit(fail>0||pf===0||gfail>0||pf2>0||qf2===0?1:0);

