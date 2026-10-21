
'use strict';
const fs=require('fs'),path=require('path');
const {Canvas}=require('./prism-render.js');
const W=390,H=844,SS=2;
const C={canvas:[10,10,11],surface:[22,22,24],surfaceAlt:[31,31,34],sunken:[18,18,20],
 hair:[50,50,54],text:[245,245,247],textSub:[160,160,172],textTert:[136,136,146],
 accent:[217,139,69],accentText:[232,160,92],ok:[61,214,140],warn:[245,165,36],danger:[255,107,107],
 kindFp:[42,166,166],kindOtp:[128,96,200]};

function screen(){const cv=new Canvas(W*SS,H*SS);cv.clear(...C.canvas);return cv;}
const R=(cv,x,y,w,h,r,col,a=255)=>cv.fillRounded(x*SS,y*SS,w*SS,h*SS,r*SS,col,a);
const T=(cv,x,y,w,h,col)=>{R(cv,x,y,w,h,h/2,col);};  // 文字条
const RR=(cv,x,y,w,h,r,t,col)=>cv.strokeRounded(x*SS,y*SS,w*SS,h*SS,r*SS,t*SS,()=>col);
function groupBar(cv){
  const y=H-56;
  R(cv,14,y,362,44,22,[30,30,33]);
  RR(cv,14,y,362,44,22,0.8,C.hair);
  const names=[C.accent,C.textSub,C.textSub,C.textSub,C.textSub];
  for(let i=0;i<5;i++){ const cx=14+22+i*72; R(cv,cx,y+16,26,12,6,names[i],names[i]===C.accent?255:120); }
}
// ── A 门厅：门是主角 ──
function dirA(){
  const cv=screen();
  // 顶部：锁名 + 状态
  T(cv,20,20,96,15,C.text); T(cv,20,42,60,10,C.textSub);
  R(cv,300,20,70,24,12,C.surfaceAlt); T(cv,312,29,46,7,C.ok);
  // 门（真实比例 1050:2300，高约 470）
  const dh=470, dw=dh*1050/2300, dx=(W-dw)/2, dy=76;
  R(cv,dx,dy,dw,dh,10,[26,26,29]);
  for(let i=0;i<26;i++){ const sy=dy+8+i*(dh-16)/26; R(cv,dx+8,sy,dw-16,(dh-16)/26-3,2,[33,33,37]); }
  // 刃锁体 60×300 → 相对门
  const lh=dh*(300/2300), lw=dw*(60/1050);
  R(cv,dx+dw-lw-6,dy+dh*(1100/2300),lw,lh,3,[52,50,46]);
  R(cv,dx+dw-lw-4,dy+dh*(1180/2300),lw-4,lh*0.34,2,C.accent);
  // 按住提示
  T(cv,W/2-58,dy+dh+18,116,12,C.textSub);
  // 状态条
  const sy=dy+dh+44; R(cv,20,sy,350,44,14,C.surface);
  T(cv,34,sy+16,54,8,C.textTert); T(cv,100,sy+13,40,13,C.ok);
  T(cv,180,sy+16,48,8,C.textTert); T(cv,240,sy+13,52,13,C.text);
  T(cv,308,sy+16,48,8,C.textTert);
  // 今天三个数
  const ty=sy+58; R(cv,20,ty,350,70,16,C.surface);
  const tiles=[[72,'13 次'],[175,'3 人'],[278,'08:12']];
  for(const [tx] of [[72],[175],[278]]){
    T(cv,tx,ty+18,44,16,C.text); T(cv,tx,ty+42,38,8,C.textTert);
  }
  // 分组入口
  const gy=ty+86;
  for(let i=0;i<5;i++){
    const y=gy+i*54;
    R(cv,20,y,350,48,14,C.surface);
    R(cv,34,y+14,20,20,6,[40,40,44]);
    T(cv,64,y+15,88,11,C.text); T(cv,64,y+30,120,8,C.textTert);
    R(cv,336,y+20,8,8,4,C.textTert);
  }
  groupBar(cv);
  return cv;
}
// ── B 控制台：开锁是主角 ──
function dirB(){
  const cv=screen();
  T(cv,20,18,110,14,C.text); R(cv,300,14,70,22,11,C.surfaceAlt); T(cv,312,22,46,7,C.ok);
  // 大圆环开锁
  const cx=W/2, cy=210, rad=96;
  for(let a=0;a<360;a+=2){ /* 画弧 */ }
  for(let r=rad;r>rad-3;r--){
    for(let a=0;a<300;a++){ const th=a*Math.PI/180;
      cv.dot((cx+r*Math.cos(th))*SS,(cy+r*Math.sin(th))*SS,...[50,50,54]); }
  }
  for(let r=rad;r>rad-4;r--){
    for(let a=0;a<300;a++){ const th=a*Math.PI/180;
      cv.dot((cx+r*Math.cos(th))*SS,(cy+r*Math.sin(th))*SS,...C.accent); }
  }
  R(cv,cx-70,cy-70,140,140,70,C.surfaceAlt);
  T(cv,cx-30,cy-22,60,14,C.text);
  T(cv,cx-22,cy+2,44,9,C.textSub);
  T(cv,cx-42,cy+92,84,11,C.textSub);
  // 三个读数
  const ty=352; R(cv,20,ty,350,72,16,C.surface);
  const xs=[72,175,278];
  for(let i=0;i<3;i++){ T(cv,xs[i],ty+18,44,18,C.text); T(cv,xs[i],ty+44,40,8,C.textTert); }
  // 24h 环 + 成员
  const hy=ty+88; R(cv,20,hy,350,110,16,C.surface);
  T(cv,34,hy+16,80,9,C.textTert);
  for(let i=0;i<24;i++){
    const bh=8+((i*37)%40);
    R(cv,34+i*13,hy+92-bh,8,bh,3, i%7===0?C.accent:[46,46,52]);
  }
  T(cv,34,hy+16,0,0,C.text);
  // 成员活跃
  const my=hy+122; R(cv,20,my,350,88,16,C.surface);
  T(cv,34,my+14,72,9,C.textTert);
  for(let i=0;i<4;i++){ R(cv,34+i*80,my+36,64,32,10,[38,38,42]); T(cv,42+i*80,my+46,40,10,C.text); }
  // 分组入口（横向 5 个）
  const gy=my+100; R(cv,20,gy,350,56,16,C.surface);
  for(let i=0;i<5;i++){ R(cv,34+i*66,gy+18,40,20,10,[40,40,44]); }
  groupBar(cv);
  return cv;
}
// ── C 时间线：今天发生了什么 ──
function dirC(){
  const cv=screen();
  T(cv,20,16,76,11,C.textSub);
  T(cv,20,34,150,20,C.text);
  // 今日时间轴
  const ty=76; R(cv,20,ty,350,96,16,C.surface);
  T(cv,34,ty+14,60,9,C.textTert);
  R(cv,34,ty+40,322,6,3,[44,44,52]);
  const ev=[[0.28,C.ok],[0.42,C.ok],[0.55,C.accent],[0.63,C.ok],[0.78,C.warn]];
  for(const [p,col] of ev){ R(cv,34+322*p-2,ty+32,4,22,2,col); }
  for(let i=0;i<5;i++){ T(cv,34+322*(i/4)-8,ty+62,16,7,C.textTert); }
  // 现在卡：门状态 + 一键开锁
  const ny=ty+110; R(cv,20,ny,350,132,18,C.surface);
  R(cv,36,ny+18,44,44,22,[40,40,44]); T(cv,50,ny+30,16,16,C.ok);
  T(cv,92,ny+24,80,13,C.text); T(cv,92,ny+45,110,9,C.textSub);
  R(cv,36,ny+80,314,36,18,C.accent); T(cv,150,ny+92,80,12,[20,20,22]);
  // 成员
  const my=ny+146; R(cv,20,my,350,84,16,C.surface);
  T(cv,34,my+14,64,9,C.textTert);
  for(let i=0;i<4;i++){ const rr=14+((i*13)%10); R(cv,40+i*78,my+44-rr/2,rr*2,rr*2,rr,[44,44,50]); }
  // 分组
  const gy=my+96;
  for(let i=0;i<3;i++){ const y=gy+i*52; R(cv,20,y,350,46,14,C.surface); T(cv,36,y+16,90,11,C.text); T(cv,36,y+31,110,8,C.textTert); }
  groupBar(cv);
  return cv;
}
const out=path.join(__dirname,'..','docs/redesign/directions');
fs.mkdirSync(out,{recursive:true});
dirA().save(path.join(out,'A-door-first.png'));
dirB().save(path.join(out,'B-control-first.png'));
dirC().save(path.join(out,'C-day-first.png'));
console.log('已输出三个方向: docs/redesign/directions/{A-door-first,B-control-first,C-day-first}.png');
