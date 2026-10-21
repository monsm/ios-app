const boot=document.getElementById('boot');
function setBoot(m,e){if(!boot)return;boot.textContent=m||"";boot.style.display=m?"block":"none";if(e)boot.classList.add("err");else boot.classList.remove("err");}
function srcOf(id){const el=document.getElementById("vendor-"+id);return el?el.textContent:null;}
function blob(s){return URL.createObjectURL(new Blob([s],{type:"text/javascript"}));}
async function main(){
  const ts=srcOf("three"),os=srcOf("orbit"),rs=srcOf("room"),ss=srcOf("scene");
  if(!ts||!os||!rs){setBoot("内联资源缺失。",true);return;}
  const tU=blob(ts),oU=blob(os),rU=blob(rs);
  const im=document.createElement("script");im.type="importmap";
  im.textContent=JSON.stringify({imports:{three:tU}});document.head.appendChild(im);
  let THREE,OC,RE;
  try{THREE=await import(tU);OC=(await import(oU)).OrbitControls;RE=(await import(rU)).RoomEnvironment;}
  catch(e){setBoot("3D 引擎失败: "+(e&&e.message?e.message:String(e)),true);console.error(e);return;}

  // 场景脚本执行后会填充 window.__DESIGNS
  try{
    const sc=document.createElement("script");sc.type="module";sc.textContent=srcOf("scene");
    // 直接 eval 更快: 场景脚本里没有 import（已剥离），只依赖全局 THREE
    window.THREE = THREE;
    new Function("THREE", srcOf("scene"))(THREE);
  }catch(e){setBoot("设计代码执行失败: "+(e&&e.message?e.message:String(e)),true);console.error(e);return;}

  const DS = window.__DESIGNS || [];
  if(!DS.length){setBoot("没有读到任何设计。检查 docs/redesign/locks/*.js 是否导出 DESIGNS。",true);return;}
  setBoot("");
  run(THREE,OC,RE,DS);
}

function run(THREE,OC,RE,DS){
  const STATE={mode:"locked",charge:0};
  const TINT={locked:0xD98B45,charge:0xE8A05C,open:0x3DD68C,deadbolt:0xF5A524,fail:0xFF6B6B};

  document.getElementById("count").textContent = DS.length + " 个设计";

  // 动态建卡片
  const grid=document.getElementById("grid");
  DS.forEach(function(d,i){
    const sec=document.createElement("section");sec.className="col";
    const head=document.createElement("div");head.className="col-head";
    const tag=document.createElement("span");tag.className="tag";tag.textContent="No."+(i+1);
    const h2=document.createElement("h2");h2.textContent=d.name||d.id;
    const pp=document.createElement("p");pp.textContent=d.note||"";
    head.appendChild(tag);head.appendChild(h2);head.appendChild(pp);
    const stage=document.createElement("div");stage.className="stage";
    const badge=document.createElement("div");badge.className="badge";badge.textContent="拖拽 360°";
    stage.appendChild(badge);
    sec.appendChild(head);sec.appendChild(stage);grid.appendChild(sec);
    d.__stage=stage;
  });

  function makeStage(host){
    const renderer=new THREE.WebGLRenderer({antialias:true,alpha:true});
    renderer.setPixelRatio(Math.min(window.devicePixelRatio||1,2));
    renderer.toneMapping=THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure=1.05;
    host.appendChild(renderer.domElement);
    const scene=new THREE.Scene();
    const pm=new THREE.PMREMGenerator(renderer);
    scene.environment=pm.fromScene(new RE(),0.04).texture;
    const cam=new THREE.PerspectiveCamera(32,1,0.02,60);
    const k=new THREE.DirectionalLight(0xfff4e8,3.0);k.position.set(-1.8,2.2,2.6);scene.add(k);
    const f=new THREE.DirectionalLight(0xb8c8dc,0.55);f.position.set(2.0,-1.2,1.8);scene.add(f);
    const rim=new THREE.DirectionalLight(0xe8a05c,1.1);rim.position.set(0.7,1.1,-2.2);scene.add(rim);
    const top=new THREE.DirectionalLight(0xffffff,0.6);top.position.set(0,2.8,0.5);scene.add(top);
    scene.add(new THREE.AmbientLight(0xffffff,0.18));
    const ctl=new OC(cam,renderer.domElement);
    ctl.enableDamping=true;ctl.dampingFactor=0.08;ctl.enablePan=false;
    ctl.autoRotate=true;ctl.autoRotateSpeed=0.5;
    ctl.addEventListener("start",function(){ctl.autoRotate=false;});
    return {renderer:renderer,scene:scene,camera:cam,controls:ctl,host:host};
  }

  const stages=[];
  DS.forEach(function(d){
    if(typeof d.build!=="function"){console.error("设计缺少 build(): "+d.id);return;}
    let obj;
    try{obj=d.build();}catch(e){console.error("build 失败: "+d.id,e);return;}
    if(!obj){console.error("build 返回空: "+d.id);return;}
    // 统一缩放到场景单位：设计若以 mm 建模（尺寸几十~几百），缩到 1/100
    const bb0=new THREE.Box3().setFromObject(obj);
    const sz0=new THREE.Vector3();bb0.getSize(sz0);
    const maxMM=Math.max(sz0.x,sz0.y,sz0.z);
    if(maxMM>10) obj.scale.setScalar(1/100);
    const s=makeStage(d.__stage);
    s.design=d;s.obj=obj;
    s.scene.add(obj);
    stages.push(s);
  });

  function fit(s){
    const w=s.host.clientWidth,h=s.host.clientHeight;
    if(!w||!h)return;
    s.renderer.setSize(w,h,false);
    s.camera.aspect=w/h;s.camera.updateProjectionMatrix();
    if(s.inited)return;
    s.inited=true;
    const bb=new THREE.Box3().setFromObject(s.obj);
    const size=new THREE.Vector3();bb.getSize(size);
    const c=new THREE.Vector3();bb.getCenter(c);
    const maxDim=Math.max(size.x,size.y,size.z,0.001);
    const fov=s.camera.fov*Math.PI/180;
    const dist=(maxDim*0.60)/Math.tan(fov/2);
    s.camera.position.set(c.x+dist*0.30,c.y+dist*0.14,c.z+dist);
    s.controls.target.copy(c);
    s.controls.minDistance=dist*0.5;
    s.controls.maxDistance=dist*2.2;
    s.controls.update();
  }

  function applyState(){
    const col=new THREE.Color(TINT[STATE.mode]||TINT.locked);
    stages.forEach(function(s){
      const h=s.design.highlight;if(!h)return;
      if(h.accent&&h.accent.material){
        const m=h.accent.material;
        if("emissive" in m){m.emissive=col.clone();m.emissiveIntensity=STATE.mode==="open"?0.32:(STATE.mode==="fail"?0.28:0.10);}
        else{m.color=col.clone();}
      }
      if(h.sensor&&h.sensor.material&&"emissive" in h.sensor.material){
        h.sensor.material.emissive=col.clone();
        h.sensor.material.emissiveIntensity=STATE.mode==="charge"?0.18+STATE.charge*0.9:0.10;
      }
      if(h.mover){h.mover.rotation.z=(STATE.mode==="deadbolt")?-0.22:0;}
    });
  }

  document.querySelectorAll(".states button").forEach(function(b){
    b.addEventListener("click",function(){
      document.querySelectorAll(".states button").forEach(function(x){x.setAttribute("aria-pressed","false");});
      b.setAttribute("aria-pressed","true");
      STATE.mode=b.dataset.mode;
      if(STATE.mode==="charge")STATE.charge=0;
      applyState();
    });
  });

  const clock=new THREE.Clock();let dir=1;
  function tick(){
    const dt=Math.min(clock.getDelta(),0.05);
    if(STATE.mode==="charge"){STATE.charge+=dir*dt*0.55;if(STATE.charge>=1){STATE.charge=1;dir=-1;}if(STATE.charge<=0){STATE.charge=0;dir=1;}applyState();}
    stages.forEach(function(s){fit(s);s.controls.update();s.renderer.render(s.scene,s.camera);});
    requestAnimationFrame(tick);
  }
  stages.forEach(fit);
  applyState();requestAnimationFrame(tick);
  window.addEventListener("resize",function(){stages.forEach(fit);});

  document.getElementById("foot").innerHTML=(
    "<b>共 " + DS.length + " 个设计</b>，来自 5 位设计师（A 包豪斯 / B 东方器物 / C 高级制表 / D 当代艺术 / E 材质对比）。<br>" +
    "每个都按真实门锁尺寸（mm）建模，只用 box/cylinder/sphere/cone —— 这些在 iOS 的 MeshResource 里都能做出来。<br>" +
    "<b>选一个编号，我就把它接进 iOS 首屏。</b>"
  );
}
main().catch(function(e){setBoot("启动失败: "+(e&&e.message?e.message:String(e)),true);console.error(e);});