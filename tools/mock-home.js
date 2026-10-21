
'use strict';
// 渲染 HomeConsole 的真实布局（不是线框，尽量还原最终观感）
const fs=require('fs'),path=require('path');
const {Canvas}=require('./prism-render.js');
const W=390,H=844,SS=2;
const C={canvas:[10,10,11],surface:[22,22,24],surfaceAlt:[31,31,34],
 hair:[50,50,54],text:[245,245,247],textSub:[160,160,172],textTert:[136,136,146],
 accent:[217,139,69],accentText:[232,160,92],ok:[61,214,140],warn:[245,165,36],danger:[255,107,107]};
const cv=new Canvas(W*SS,H*SS); cv.clear(...C.canvas);
const R=(x,y,w,h,r,c)=>{ if(w<=0||h<=0)return; cv.fillRounded(x*SS,y*SS,w*SS,h*SS,Math.max(0,r)*SS,c); };
const RR=(x,y,w,h,r,t,c)=>cv.strokeRounded(x*SS,y*SS,w*SS,h*SS,r*SS,t*SS,()=>c);
// 画一段文字（用条形近似字高，宽度=字符数*0.55*size）
const T=(x,y,text,size,col,weight)=>{
  const cw=size*0.56;
  for(let i=0;i<text.length;i++){
    const ch=text[i];
    if(ch===' '||ch==='.'||ch===',') continue;
    R(x+i*cw, y+size*0.18, cw*0.72, size*0.72, size*0.12, col);
  }
};
let y=8;
// ① masthead: 09:41 ... ● 已连接
T(16,y+2,'09:41',15,C.textSub);
R(W-16-9-46-8-6,y+9,6,6,3,C.ok);
T(W-16-46,y+2,'已连接',12,C.ok);
y+=20+24;
// ② identity
T(16,y,'大门',26,C.text);
y+=26+4;
T(16,y,'今天 3 人开过 13 次',13,C.textTert);
y+=18+28;
// ③ 开锁环 220
const cx=W/2, cy=y+110, rad=110;
for(let a=0;a<360;a+=1){ const th=a*Math.PI/180;
  for(let r=rad-3.5;r<=rad;r+=0.5) cv.dot((cx+r*Math.cos(th))*SS,(cy+r*Math.sin(th))*SS,...C.surfaceAlt); }
R(cx-30,cy-34,60,10,5,C.textSub);           // 锁图标示意
T(cx-26,cy+10,'按住开锁',13,C.textTert);
y=cy+110+16;
// footnote
T(cx-62,y,'电量 82% · 上次 08:12',13,C.textTert);
y+=18+28;
// ④ 三指标
const colW=(W-32)/3;
const metrics=[['13','今日开门'],['3','在家成员'],['08:12','最早开门']];
for(let i=0;i<3;i++){
  const mx=16+i*colW;
  T(mx+colW/2-metrics[i][0].length*14*0.28, y, metrics[i][0], 28, C.text);
  T(mx+colW/2-44*0.28, y+34, metrics[i][1], 11, C.textTert);
  if(i<2) R(mx+colW-0.5,y+4,1,34,0.5,C.hair);
}
y+=34+24+28;
// ⑤ 今天
T(16,y,'今天',11,C.textTert);
y+=11+12;
const bars=[1,2,4,7,9,6,3,2,1,2,3,5,8,9,6,3,2,1,2,4,6,8,5,3];
const peak=Math.max(...bars);
const bw=(W-32-23*3)/24;
for(let i=0;i<24;i++){
  const h=Math.max(3,46*bars[i]/peak);
  const col = i===9 ? C.accent : (bars[i]===peak? [Math.round(C.accent[0]*0.55+22*0.45),Math.round(C.accent[1]*0.55+22*0.45),Math.round(C.accent[2]*0.55+22*0.45)] : C.textSub);
  R(16+i*(bw+3), y+46-h, bw, h, bw/2, col);
}
y+=46+4;
T(16,y,'0',10,C.textTert); T(16+70,y,'6',10,C.textTert); T(16+150,y,'12',10,C.textTert);
T(16+230,y,'18',10,C.textTert); T(W-26,y,'24',10,C.textTert);
y+=10+24+28;
// ⑥ 成员
T(16,y,'成员',11,C.textTert);
y+=11+12;
const mem=[['妈','妈妈','8'],['爸','爸爸','3'],['我','我','2']];
let mx=16;
for(const [ch,nm,n] of mem){
  const cwid=5+28+8+Math.max(nm.length*13*0.56, n.length*11*0.56)+12;
  R(mx,y,cwid,38,19,C.surface);
  R(mx+5,y+5,28,28,14,C.surfaceAlt);
  T(mx+5+9,y+9,ch,14,C.text);
  T(mx+5+28+8,y+4,nm,13,C.text);
  T(mx+5+28+8,y+20,n+' 次',11,C.textTert);
  mx+=cwid+8;
}
y+=38+24+28;
// ⑦ 管理
T(16,y,'管理',11,C.textTert);
y+=11+12;
const groups=['台账','设备','成员','安全','备份外观'];
const tw=(W-32-8*4)/5;
for(let i=0;i<5;i++){
  const tx=16+i*(tw+8);
  R(tx,y,tw,62,14,C.surface);
  R(tx+tw/2-9,y+12,18,18,5,C.accentText);
  const lab=groups[i];
  T(tx+tw/2-lab.length*10*0.28, y+38, lab, 10, C.textSub);
}
const out=path.join(__dirname,'..','docs/redesign/directions/home-console.png');
cv.save(out);
console.log('已渲染 home-console.png  (末端 y='+Math.round(y+62)+' / 844)');
