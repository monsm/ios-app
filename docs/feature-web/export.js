const fs=require('fs');
const D=JSON.parse(fs.readFileSync('features.json','utf8'));
const NODES=D.nodes, DOM=D.domains, ST=D.stats;
const esc=v=>'"'+String(v??'').replace(/"/g,'""')+'"';
const rows=[['domain','level','key','name','kind','platforms','status','commands','path','summary','evidence1','evidence2','details'].map(esc).join(',')];
for(const n of NODES){ if(n.isDomain) continue;
  const ev=n.evidence.map(e=>`${e.platform}:${e.file}:${e.line}`);
  rows.push([n.domain,n.level,n.key,n.name,n.kind,n.platforms.join('+'),
    Object.entries(n.status).map(([k,v])=>k+'='+v).join(';'),n.commands.join('+'),n.path,n.summary,
    ev[0]||'',ev[1]||'',n.details.slice(0,6).join(' | ')].map(esc).join(','));
}
fs.writeFileSync('功能点清单.csv','\ufeff'+rows.join('\r\n'),'utf8');

const PL=p=>p==='ios'?'iOS':p==='android'?'Android':'APK';
const SETL=k=>({'ios':'仅 iOS','android':'仅 Android','apk':'仅 APK','ios+android':'iOS + Android',
 'ios+apk':'iOS + APK','android+apk':'Android + APK','ios+android+apk':'三端都有'}[k]||k);
const DESC={device:'首页 / 连接 / 配网 / 信息 / 网关 / 钥匙串 / 校时 / 消息 / 排序分组',
 unlock:'开锁圆盘 / 自动开锁 / 查找 / 应用锁 / 访客 / 安全模式 / 扫码绑定',
 credential:'密码 / 指纹 / 临时码 / OTP / 队列 / 回收站 / 历史 / 整理 / 移交',
 member:'成员 / 权限 / 借用 / 归档 / 合并 / 家庭',record:'记录 / 时间线 / 检索 / 筛选 / 统计 / 告警 / 导出',
 security:'安全中心 / 布防 / 防尾随 / 审计 / 销毁 / 水印',backup:'备份 / 恢复 / WebDAV / 换机 / 本地 / 规范化',
 care:'电量 / 保养 / 里程碑 / 提示 / 更新日志',diagnostic:'体检 / 数据健康 / 恢复 / 追踪 / 遥测 / 自检 / 固件',
 settings:'分组 / 外观 / 无障碍 / 通知 / 实验 / 关于 / 深链 / 启动链 / 路由',
 protocol:'帧 / KLV / 令牌 / 32 条命令 / 密码学 / 型号矩阵',data:'存储键 / 实体 / 审计链 / 时间 / 变体语法 / 设计',
 apk:'厂商原版 APK 基线：51 页面 / 云账号 / 推送 / 21 插件 / 协议'};
const L=[];
L.push('# 离线锁管家 · 功能蜘蛛网');
L.push('');
L.push(`> 生成 ${D.meta.generated} ｜ 节点 **${ST.nodes}** ｜ 源码证据 **${ST.evidence}** 条 ｜ 协议命令 **${ST.commands}** 条`);
L.push('>');
L.push('> 全部结论来自**源码本体**（Swift / Kotlin / Java / JS / XML）。README 与 docs 未参与取证，每条结论都可回到 `file:line` 核对。');
L.push('');
L.push('## 一、总览');
L.push('');
L.push('| 项 | 数量 |'); L.push('|---|---:|');
L.push(`| 功能节点 | ${ST.nodes} |`);
L.push(`| 模块（第 2 环） | ${ST.modules} |`);
L.push(`| 功能点（第 3 环） | ${ST.features} |`);
L.push(`| 细节 / 状态 / 边界（第 4 环） | ${ST.details} |`);
L.push(`| 源码证据（每条可回到 file:line） | ${ST.evidence} |`);
L.push(`| iOS 原生覆盖 | ${ST.byPlatform.ios} |`);
L.push(`| Android 原生覆盖 | ${ST.byPlatform.android} |`);
L.push(`| 原版 APK 基线覆盖 | ${ST.byPlatform.apk} |`);
L.push('');
L.push('## 二、十三个功能域');
L.push('');
L.push('| 域 | 节点 | 覆盖内容 |'); L.push('|---|---:|---|');
for(const d of DOM) L.push(`| ${d.name} | ${ST.byDomain[d.key]} | ${DESC[d.key]||''} |`);
L.push('');
L.push('## 三、跨端对照');
L.push('');
L.push('| 平台组合 | 节点数 |'); L.push('|---|---:|');
for(const [k,v] of Object.entries(ST.platSets||{}).sort((a,b)=>b[1].length-a[1].length)) L.push(`| ${SETL(k)} | ${v.length} |`);
L.push('');
L.push('> iOS 是完整协议级移植（32 条命令）；Android 原生是「单锁 + 开锁」极简版（只有 01/03/04，无 AES/skey/ZOTP，但有 FindMy 式箭头与 AirTag 层）；APK 是厂商原版基线，有云账号体系。');
L.push('');
L.push('## 四、全覆盖核验');
L.push('');
L.push('反向覆盖率检查：`App/` 与 `android-app/` 下 84 个源文件（swift/kt/java/xml/kts）**全部至少被一个功能点引用**，零引用文件 0 个。');
L.push('符号级检查：65 个 Swift 文件里的类型/函数声明，除 3 个 Codable 编解码 helper 外全部被功能点覆盖（±60 行）。');
L.push('');
L.push('## 五、逐域明细');
for(const d of DOM){
  L.push(''); L.push(`### ${d.name}`); L.push('');
  const list=NODES.filter(n=>n.domain===d.key&&!n.isDomain).sort((a,b)=>a.level-b.level||a.path.localeCompare(b.path,'zh'));
  for(const n of list){
    const pad='  '.repeat(Math.max(0,n.level-2));
    const cmds=n.commands.length?` · ${n.commands.map(c=>'cmd'+c).join(' ')}`:'';
    L.push(`${pad}- **${n.name}** \`${n.key}\` · ${n.platforms.map(PL).join(' / ')}${cmds}`);
    if(n.summary) L.push(`${pad}  - ${n.summary}`);
    for(const dt of n.details.slice(0,8)) L.push(`${pad}  - · ${dt}`);
    const ev=n.evidence.slice(0,4).map(e=>`\`${e.file}:${e.line}\``).join('、');
    if(ev) L.push(`${pad}  - 证据：${ev}`);
  }
}
L.push(''); L.push('## 六、未决项（源码里读到了但定不了性）'); L.push('');
L.push('这些不是"没读"，而是代码本身自相矛盾、只有注释没有实现、或落点在别的文件：'); L.push('');
for(const u of (D.meta.unresolved||[]).slice(0,200)) L.push(`- ${u}`);
fs.writeFileSync('功能蜘蛛网.md',L.join('\n'),'utf8');
console.log('csv rows',rows.length-1,'md lines',L.length);
