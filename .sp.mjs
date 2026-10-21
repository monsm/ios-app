const boot=document.getElementById('boot');
function setBoot(m,e){if(!boot)return;boot.textContent=m||'';boot.style.display=m?'block':'none';if(e)boot.classList.add('err');else boot.classList.remove('err');}
function srcOf(id){const el=document.getElementById('vendor-'+id);return el?el.textContent:null;}
function blob(s){return URL.createObjectURL(new Blob([s],{type:'text/javascript'}));}
async function main(){
  const ts=srcOf('three'),os=srcOf('orbit'),rs=srcOf('room'),ss=srcOf('scene');
  if(!ts||!os||!rs||!ss){setBoot('内联资源缺失。',true);return;}
  const tU=blob(ts),oU=blob(os),rU=blob(rs),sU=blob(ss);
  const im=document.createElement('script');im.type='importmap';
  im.textContent=JSON.stringify({imports:{three:tU}});document.head.appendChild(im);
  let THREE,OC,RE,S;
  try{THREE=await import(tU);OC=(await import(oU)).OrbitControls;RE=(await import(rU)).RoomEnvironment;S=await import(sU);}
  catch(e){setBoot('3D 引擎失败: '+(e&&e.message?e.message:String(e)),true);console.error(e);return;}
  setBoot('');run(THREE,OC,RE,S);
}
function run(THREE,OC,RE,S){
  const {ANIMS,buildPrism,FACES}=S;
  const keys=Object.keys(ANIMS);

  function makeStage(host){
    const renderer=new THREE.WebGLRenderer({antialias:true,alpha:true});
    renderer.setPixelRatio(Math.min(window.devicePixelRatio||1,2));
    renderer.toneMapping=THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure=1.05;
    host.appendChild(renderer.domElement);
    const scene=new THREE.Scene();
    const pm=new THREE.PMREMGenerator(renderer);
    scene.environment=pm.fromScene(new RE(),0.04).texture;
    const cam=new THREE.PerspectiveCamera(32,1,0.1,60);
    cam.position.set(0,0,5.2);
    const k=new THREE.DirectionalLight(0xfff4e8,3.0);k.position.set(-3,4,5);scene.add(k);
    const f=new THREE.DirectionalLight(0xb8c8dc,0.6);f.position.set(3,-2,3);scene.add(f);
    const rim=new THREE.DirectionalLight(0xe8a05c,1.0);rim.position.set(1,2,-4);scene.add(rim);
    scene.add(new THREE.AmbientLight(0xffffff,0.22));
    const ctl=new OC(cam,renderer.domElement);
    ctl.enableDamping=true;ctl.dampingFactor=0.08;ctl.enablePan=false;
    ctl.minDistance=3.2;ctl.maxDistance=8.5;
    ctl.enableRotate=false;
    return {renderer,scene,camera:cam,controls:ctl,host};
  }

  const stages=[];
  const hosts=document.querySelectorAll('.stage');
  for(let i=0;i<hosts.length;i++){
    const host=hosts[i];
    const key=host.dataset.anim;
    const s=makeStage(host);
    const p=buildPrism();
    s.prism=p.group;s.faces=p.faces;s.key=key;s.anim=ANIMS[key];
    s.scene.add(p.group);
    // 起始面 = 1 (就近 D)，最能看出换面
    s.from=1;s.to=2;s.t=0;s.hold=0;
    stages.push(s);
  }

  function fit(s){
    const w=s.host.clientWidth,h=s.host.clientHeight;
    if(!w||!h)return;
    s.renderer.setSize(w,h,false);
    s.camera.aspect=w/h;s.camera.updateProjectionMatrix();
  }

  // 每个格子自己跑循环: 停 0.9s → 播 1.1s → 换下一面
  let SPEED=window.__SPEED||1.8;
  const BASE_DUR=620, BASE_HOLD=220;
  const getDUR=()=>BASE_DUR/SPEED, getHOLD=()=>BASE_HOLD/SPEED;
  function step(s,dt){
    if(s.hold>0){ s.hold-=dt; return; }
    s.t += dt/getDUR();
    if(s.t>=1){
      s.t=0;s.hold=getHOLD();
      s.from=s.to;s.to=(s.to+1)%3;
      s.anim.fn(s.prism,s.from,s.from,0);
      return;
    }
    s.anim.fn(s.prism,s.from,s.to,s.t);
  }

  window.__setSpeed = function(v){ SPEED = v; };
  let last=performance.now();
  function tick(now){
    const dt=Math.min((now-last)/1000,0.05);last=now;
    for(let i=0;i<stages.length;i++){
      const s=stages[i];
      fit(s);
      step(s,dt);
      s.controls.update();
      s.renderer.render(s.scene,s.camera);
    }
    requestAnimationFrame(tick);
  }
  for(let i=0;i<stages.length;i++)fit(stages[i]);
  requestAnimationFrame(tick);
  window.addEventListener('resize',function(){for(let i=0;i<stages.length;i++)fit(stages[i]);});
}
// 速度切换
document.querySelectorAll('.speed button').forEach(function(b){
  b.addEventListener('click', function(){
    document.querySelectorAll('.speed button').forEach(function(x){x.setAttribute('aria-pressed','false');});
    b.setAttribute('aria-pressed','true');
    window.__SPEED = parseFloat(b.dataset.speed) || 1.8;
    // 通知所有 stage
    if (window.__setSpeed) window.__setSpeed(window.__SPEED);
  });
});
main().catch(function(e){setBoot('启动失败: '+(e&&e.message?e.message:String(e)),true);console.error(e);});