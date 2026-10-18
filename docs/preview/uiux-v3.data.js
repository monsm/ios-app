// UIUX v3 · 76 个目的地（与 App/Core/Destination.swift 一一对应）
// 数据只描述"这一屏有什么、主动作是什么"，渲染交给 uiux-v3.html。
window.SCREENS = [
/* ---------------- 锁 ---------------- */
{id:'deviceHome', t:'锁', g:'锁', tab:'锁', sub:'前门 · 已连接 · 电量 86%',
 path:'锁（主 Tab）', why:'能不能开：这一屏只回答这一件事。',
 act:'轻点黄铜圆盘开锁（或说“开锁”）。',
 states:['已连接','未连接','开锁在途','开锁失败','低电','近场（自动弹查找层）'],
 blocks:[
  {type:'hero',dot:1,k:'已连接 · 蓝牙直连',title:'前门',meta:'电量 86% · 信号 −52 dBm · 自动开锁已开',action:'轻点开锁'},
  {type:'sec',title:'找锁',rows:[{i:'⌖',t:'精确查找',s:'走近自动弹出 · 箭头随信号变绿',tone:'t-ok'}]},
  {type:'sec',title:'这把锁',rows:[
    {i:'▤',t:'概况',s:'信息 · 成员 · 电池 · 固件',tone:'t-info'},
    {i:'⚿',t:'凭证与钥匙',s:'密码 3 · 指纹 2 · 临时码 1',tone:'t-brass',badge:'6'},
    {i:'◈',t:'家人与访客',s:'3 人 · 1 个临时访客',tone:'t-info'},
    {i:'◷',t:'最近发生',s:'今天 08:12 指纹开锁',tone:'t-gray'}]},
  {type:'note',text:'<b>渐进披露：</b>设备管理、固件、网关、诊断不再常驻首页，收进“更多”。低频不等于消失，只是一步之遥。'}
]},

{id:'focusUnlock', t:'专注开锁', g:'锁', parent:'锁', sub:'全屏 · 只留圆盘',
 path:'锁 › 专注开锁', why:'在走廊、夜里、单手时，减少一切干扰。',
 act:'按住圆盘确认；超时可取消。', states:['按住中','握手','鉴权','执行','成功','失败抖动'],
 blocks:[{type:'hero',dot:1,k:'前门',title:'按住开锁',meta:'松手取消 · 8 秒自动退出',action:'按住'},
  {type:'note',text:'失败时不播放长文案，只在圆盘下方给一行原因（超时 / rc=13 / 未连接），并可一键重试。'}]},

{id:'unlockGate', t:'开锁前置检查', g:'锁', parent:'锁', sub:'权限 · 蓝牙 · 距离',
 path:'锁 › 开锁前置检查', why:'开不了时，先告诉用户缺什么，而不是转圈。',
 act:'按缺项逐条修复（开蓝牙 / 给权限 / 靠近）。', states:['全部就绪','蓝牙关闭','无权限','距离过远'],
 blocks:[{type:'sec',title:'检查项',rows:[
   {i:'◉',t:'蓝牙',s:'已开启',val:'就绪',tone:'t-ok'},
   {i:'◎',t:'附近设备权限',s:'已允许',val:'就绪',tone:'t-ok'},
   {i:'⌁',t:'距离',s:'信号 −52 dBm，约 1 米',val:'就绪',tone:'t-ok'},
   {i:'⚿',t:'凭证',s:'指纹 2 枚可用',val:'就绪',tone:'t-ok'}]},
  {type:'ctx',items:[{t:'重新检查'},{t:'去设置'}]}]},

{id:'lockOverview', t:'多锁总览', g:'锁', parent:'锁', sub:'3 把锁 · 按组',
 path:'锁 › 全部锁', why:'有多把锁时，一屏看清谁在线、谁该处理。',
 act:'点任意一把切为当前锁。', states:['全部在线','部分离线','低电','沉睡'],
 blocks:[{type:'stats',title:'状态',items:[{v:'2',l:'在线'},{v:'1',l:'需处理'}]},
  {type:'sec',title:'按组',rows:[
   {i:'⌂',t:'前门',s:'在线 · 86% · 刚刚开锁',val:'当前',tone:'t-ok'},
   {i:'⌂',t:'后门',s:'在线 · 64% · 2 小时前',tone:'t-ok'},
   {i:'⌂',t:'车库',s:'离线 · 上次 3 天前',val:'低电',tone:'t-warn'}]}]},

{id:'lockProfile', t:'这把锁', g:'锁', parent:'锁', sub:'资料 · 位置 · 备注',
 path:'锁 › 这把锁', why:'它是谁、装在哪、叫什么名字。',
 act:'改名、换位置、看序列号。', states:['已绑定','未命名','已归档'],
 blocks:[{type:'form',title:'基本',fields:[{l:'名称',v:'前门'},{l:'位置',v:'玄关'},{l:'型号',v:'ZK-Lock 3'},{l:'序列号',v:'•••• 8F2A'}]},
  {type:'sec',title:'操作',rows:[{i:'✎',t:'重命名',tone:'t-gray'},{i:'⌫',t:'解绑这把锁',s:'需要再次确认',tone:'t-danger'}]}]},

{id:'deviceInfo', t:'设备信息', g:'锁', parent:'锁', sub:'固件 · 电量 · 信号',
 path:'锁 › 设备信息', why:'排查时第一眼要看的事实。',
 act:'查看或复制诊断信息。', states:['正常','低电','信号弱'],
 blocks:[{type:'stats',title:'读数',items:[{v:'86%',l:'电量'},{v:'−52',l:'信号 dBm'},{v:'1.2m',l:'估算距离'},{v:'4.2.1',l:'固件'}]},
  {type:'sec',title:'复制',rows:[{i:'⧉',t:'复制诊断摘要',s:'型号 / 固件 / 电量 / 最近错误',tone:'t-gray'}]}]},

{id:'deviceManage', t:'设备管理', g:'锁', parent:'锁', sub:'排序 · 分组 · 批量',
 path:'锁 › 设备管理', why:'锁多了以后，顺序与分组决定找得快不快。',
 act:'拖动排序、批量改分组。', states:['默认顺序','手动顺序','按组筛选'],
 blocks:[{type:'sec',title:'顺序',rows:[
   {i:'⇅',t:'手动排序',s:'拖动调整',tone:'t-gray',chev:true},
   {i:'⌗',t:'按组显示',s:'前门 / 后门 / 车库',tone:'t-gray'}]},
  {type:'sec',title:'批量',rows:[{i:'☑',t:'选择多把锁',tone:'t-gray'},{i:'⌫',t:'批量解绑',tone:'t-danger'}]}]},

{id:'addDevice', t:'添加门锁', g:'锁', parent:'锁', sub:'扫码或靠近发现',
 path:'锁 › 添加门锁', why:'第一次用，或者添第二把锁。',
 act:'扫 iOS 生成的钥匙码，或靠近自动发现。', states:['扫码','搜索中','已发现','配对中','失败'],
 blocks:[{type:'sec',title:'方式',rows:[
   {i:'▣',t:'扫描钥匙二维码',s:'由另一台手机生成',tone:'t-brass'},
   {i:'⌁',t:'靠近自动发现',s:'需开启蓝牙',tone:'t-info'}]},
  {type:'note',text:'第一次绑定会要求给这把锁起名与选位置——这两个字段之后会出现在每一屏的标题下。'}]},

{id:'keychainHW', t:'钥匙硬件', g:'锁', parent:'锁', sub:'钥匙扣 / 卡片',
 path:'锁 › 钥匙硬件', why:'实体钥匙也要能被管理、挂失、补配。',
 act:'登记或挂失一把实体钥匙。', states:['已登记','已挂失','低电'],
 blocks:[{type:'sec',title:'已登记',rows:[
   {i:'⚿',t:'黄铜钥匙扣',s:'主钥匙 · 电量 74%',tone:'t-brass'},
   {i:'▭',t:'门禁卡',s:'备用 · 未使用 30 天',tone:'t-gray'}]}]},

{id:'linkPrefs', t:'连接偏好', g:'锁', parent:'锁', sub:'自动重连 · 超时',
 path:'锁 › 连接偏好', why:'连接行为要可预期，也要可关闭。',
 act:'开关自动重连、调整超时。', states:['默认','省电','激进'],
 blocks:[{type:'sec',title:'连接',rows:[
   {i:'↻',t:'自动重连',s:'回前台时尝试',sw:1,tone:'t-ok'},
   {i:'◷',t:'连接超时',val:'3 秒',tone:'t-gray'},
   {i:'⌁',t:'信号刷新',s:'连上后用 200ms 轮询',sw:1,tone:'t-ok'}]}]},

{id:'autoCal', t:'自动开锁校准', g:'锁', parent:'锁', sub:'武装线 · 回差',
 path:'锁 › 自动开锁校准', why:'每个人家门口的信号都不同，阈值必须能调。',
 act:'走一遍校准，或手动改阈值。', states:['校准中','已校准','信号不稳'],
 blocks:[{type:'form',title:'阈值',fields:[{l:'武装线',v:'−40 dBm'},{l:'解除线',v:'−43 dBm'},{l:'冷却',v:'6 秒'}]},
  {type:'note',text:'校准只改本机判定，不改锁端。写入前会显示“按当前信号，预计在 1–2 米触发”。'}]},

{id:'firmware', t:'固件', g:'锁', parent:'锁', sub:'4.2.1 · 已是最新',
 path:'锁 › 固件', why:'有没有更新、更新会改什么。',
 act:'检查更新；有更新时查看变更再执行。', states:['已最新','可更新','升级中','升级失败'],
 blocks:[{type:'sec',title:'版本',rows:[{i:'◈',t:'当前固件',val:'4.2.1',tone:'t-ok'},{i:'↧',t:'检查更新',tone:'t-gray'}]},
  {type:'note',text:'升级期间锁会重启，界面明确写“约 90 秒，期间不能开锁”。'}]},

{id:'gateway', t:'网关', g:'锁', parent:'锁', sub:'远程访问 · 在线',
 path:'锁 › 网关', why:'要远程开门时，网关是前提。',
 act:'绑定网关、查看在线状态。', states:['在线','离线','未绑定'],
 blocks:[{type:'sec',title:'网关',rows:[
   {i:'◫',t:'客厅网关',s:'在线 · 延迟 42ms',val:'已连接',tone:'t-ok'},
   {i:'＋',t:'添加网关',tone:'t-gray'}]}]},

{id:'syncTime', t:'时间同步', g:'锁', parent:'锁', sub:'锁端时钟 · 偏差 2 秒',
 path:'锁 › 时间同步', why:'日志时间对不上时，先校准时钟。',
 act:'把手机时间写入锁端。', states:['一致','有偏差','同步中'],
 blocks:[{type:'stats',title:'偏差',items:[{v:'+2s',l:'锁端 vs 手机'},{v:'刚刚',l:'上次同步'}]},
  {type:'ctx',items:[{t:'重新同步'}]}]},

{id:'lockCompare', t:'锁对比', g:'锁', parent:'锁', sub:'两台锁的读数并排',
 path:'锁 › 对比', why:'排查“为什么这台更慢”时，需要并排看。',
 act:'选两台锁，比较信号、电量、固件。', states:['选择中','已对比'],
 blocks:[{type:'stats',title:'前门 vs 后门',items:[{v:'−52 / −61',l:'信号 dBm'},{v:'86% / 64%',l:'电量'},{v:'1.4s / 2.1s',l:'开锁耗时'},{v:'4.2.1 / 4.1.9',l:'固件'}]}]},

/* ---------------- 凭证 ---------------- */
{id:'credentials', t:'凭证与钥匙', g:'凭证', parent:'锁', sub:'前门 · 谁能开门',
 path:'锁 › 凭证与钥匙（原第 2 个 Tab，降为二级）', why:'谁能开这把门：这是锁的属性，不是独立世界。',
 act:'搜索，或进入某一类凭证。', states:['为空','有到期','有队列','访客受限'],
 blocks:[{type:'pills',items:['全部','指纹','密码','临时码']},
  {type:'sec',title:'常用',rows:[
   {i:'☝',t:'指纹',s:'2 枚 · 你和家人',badge:'2',tone:'t-ok'},
   {i:'⚿',t:'密码',s:'3 条 · 1 条本周未用',badge:'3',tone:'t-brass'},
   {i:'◷',t:'临时码',s:'1 条 · 今天 18:00 失效',badge:'1',tone:'t-warn'}]},
  {type:'sec',title:'需要处理',rows:[
   {i:'△',t:'过期与整理建议',s:'2 条密码超过 180 天',tone:'t-warn'},
   {i:'⌫',t:'回收站',s:'已删除 3 条 · 30 天后清理',tone:'t-gray'}]}]},

{id:'credCenter', t:'凭证中心', g:'凭证', parent:'凭证与钥匙', sub:'全部凭证 · 按类型',
 path:'锁 › 凭证 › 中心', why:'所有凭证的单一入口。',
 act:'按类型或状态筛选。', states:['全部','已归档','到期'],
 blocks:[{type:'pills',items:['全部','指纹','密码','临时码','卡片']},
  {type:'sec',title:'清单',rows:[
   {i:'☝',t:'你的右手拇指',s:'指纹 · 最近 08:12',tone:'t-ok'},
   {i:'⚿',t:'家门密码',s:'密码 · 未使用 12 天',tone:'t-brass'},
   {i:'◷',t:'王阿姨',s:'临时码 · 今天 18:00–20:00',tone:'t-warn'}]}]},

{id:'addPwd', t:'添加密码', g:'凭证', parent:'凭证与钥匙', sub:'6–12 位 · 两次确认',
 path:'锁 › 凭证 › 添加密码', why:'新增一条能开门的密码。',
 act:'输入两遍并写入锁端。', states:['输入中','不一致','写入中','成功','失败'],
 blocks:[{type:'form',title:'新密码',fields:[{l:'密码',v:'••••••'},{l:'再输一次',v:'••••••'},{l:'名称',v:'家人通用'}]},
  {type:'ctx',items:[{t:'取消'},{t:'写入锁端'}]}]},

{id:'startAddFp', t:'添加指纹', g:'凭证', parent:'凭证与钥匙', sub:'按 3 次 · 抬起 · 再按',
 path:'锁 › 凭证 › 添加指纹', why:'把一个人的手指变成一把钥匙。',
 act:'按提示完成 3 次采集。', states:['等待','第 1/3','第 2/3','第 3/3','成功','失败'],
 blocks:[{type:'note',text:'<b>采集节奏：</b>每次按下保持 1 秒，听到提示再抬起。中途失败只重来当前这一次，不用从头。'},
  {type:'ctx',items:[{t:'取消'},{t:'开始采集'}]}]},

{id:'credBin', t:'回收站', g:'凭证', parent:'凭证与钥匙', sub:'3 条 · 30 天后清理',
 path:'锁 › 凭证 › 回收站', why:'删错了还能救回来。',
 act:'恢复，或彻底删除。', states:['有内容','空'],
 blocks:[{type:'sec',title:'已删除',rows:[
   {i:'⌫',t:'旧密码 2024',s:'删除于 3 天前 · 27 天后清理',tone:'t-gray'},
   {i:'⌫',t:'临时码 · 装修工',s:'删除于 9 天前',tone:'t-gray'}]},
  {type:'ctx',items:[{t:'清空回收站',danger:1},{t:'恢复所选'}]}]},

{id:'credHistory', t:'凭证历史', g:'凭证', parent:'凭证与钥匙', sub:'一条凭证的变更',
 path:'锁 › 凭证 › 历史', why:'这条密码什么时候改过、谁改的。',
 act:'查看变更记录；可回滚到上一版。', states:['无历史','有历史'],
 blocks:[{type:'timeline',title:'变更',days:[{d:'今天',rows:[
   {time:'09:02',i:'✎',t:'重命名',s:'“大门” → “家门密码”',tone:'t-gray'},
   {time:'08:40',i:'⚿',t:'修改密码',s:'你 · 本机',tone:'t-brass'}]}]}]},

{id:'credHistoryList', t:'凭证变更总表', g:'凭证', parent:'凭证与钥匙', sub:'全部凭证的变更',
 path:'锁 › 凭证 › 变更总表', why:'一次看完全部改动，而不是逐条翻。',
 act:'按凭证或时间筛选。', states:['全部','仅密码','仅指纹'],
 blocks:[{type:'timeline',title:'最近',days:[{d:'昨天',rows:[
   {time:'19:03',i:'＋',t:'新增临时码',s:'王阿姨 · 18:00–20:00',tone:'t-warn'},
   {time:'09:15',i:'☝',t:'新增指纹',s:'家人的左手食指',tone:'t-ok'}]}]}]},

{id:'credQueue', t:'待补拉队列', g:'凭证', parent:'凭证与钥匙', sub:'2 条待写回锁端',
 path:'锁 › 凭证 › 待补拉', why:'网络/链路失败时，改动不能悄悄丢。',
 act:'重试写回，或放弃并说明后果。', states:['有队列','重试中','已清空'],
 blocks:[{type:'sec',title:'等待写回',rows:[
   {i:'↻',t:'家门密码',s:'上次失败：回执超时',val:'重试',tone:'t-warn'},
   {i:'↻',t:'临时码 · 保洁',s:'上次失败：链路断开',val:'重试',tone:'t-warn'}]},
  {type:'note',text:'这一页只说事实：哪条没写进去、为什么、重试会做什么。不假装成功。'}]},

{id:'credOrganize', t:'整理建议', g:'凭证', parent:'凭证与钥匙', sub:'过期 · 重复 · 未使用',
 path:'锁 › 凭证 › 整理', why:'凭证会自己长出来，需要定期收。',
 act:'按建议合并、停用或删除。', states:['无建议','有建议'],
 blocks:[{type:'sec',title:'建议',rows:[
   {i:'△',t:'2 条密码超过 180 天',s:'建议轮换',tone:'t-warn'},
   {i:'⧉',t:'1 组疑似重复',s:'“家门密码”与“大门密码”',tone:'t-info'}]}]},

{id:'credTransfer', t:'凭证迁移', g:'凭证', parent:'凭证与钥匙', sub:'导出到新手机',
 path:'锁 › 凭证 › 迁移', why:'换机时把钥匙带走，而不是重新配。',
 act:'生成一次性迁移码。', states:['生成中','10 分钟内有效','已使用'],
 blocks:[{type:'note',text:'迁移码只在本机解密后生成，10 分钟内一次性有效；过期需重新生成。'},
  {type:'ctx',items:[{t:'生成迁移码'}]}]},

{id:'credExtend', t:'延长临时码', g:'凭证', parent:'凭证与钥匙', sub:'王阿姨 · 今天 20:00 到期',
 path:'锁 › 凭证 › 延长', why:'访客还没走，权限要能顺延。',
 act:'选新的失效时间并写回。', states:['未到期','已延长','已失效'],
 blocks:[{type:'form',title:'有效期',fields:[{l:'到期',v:'今天 22:00'},{l:'可开门次数',v:'不限'}]},
  {type:'ctx',items:[{t:'取消'},{t:'延长'}]}]},

{id:'shareToAndroid', t:'分享给安卓', g:'凭证', parent:'凭证与钥匙', sub:'生成二维码',
 path:'锁 › 凭证 › 分享给安卓', why:'家里另一台手机不该被系统排除在外。',
 act:'生成二维码，让对方扫码导入。', states:['生成中','可扫描','已过期'],
 blocks:[{type:'note',text:'二维码里是这把锁的钥匙，不是账号。只给对方看，用完关闭。'},
  {type:'ctx',items:[{t:'关闭'},{t:'生成二维码'}]}]},

/* ---------------- 成员 ---------------- */
{id:'members', t:'家人与访客', g:'成员', parent:'锁', sub:'3 人 · 1 个临时访客',
 path:'锁 › 家人与访客', why:'谁能进这个家，各自有什么权限。',
 act:'添加成员，或调整某人的权限。', states:['仅自己','有成员','有访客','有未认领'],
 blocks:[{type:'sec',title:'成员',rows:[
   {i:'☺',t:'你',s:'管理员 · 全部权限',val:'本机',tone:'t-brass'},
   {i:'☺',t:'家人 A',s:'密码 + 指纹',tone:'t-info'},
   {i:'☺',t:'王阿姨',s:'临时码 · 今天 18:00–20:00',val:'访客',tone:'t-warn'}]},
  {type:'sec',title:'待处理',rows:[{i:'？',t:'1 个未认领的指纹',s:'最近 2 天使用过',tone:'t-warn'}]}]},

{id:'memberCenter', t:'成员中心', g:'成员', parent:'家人与访客', sub:'档案 · 权限 · 借还',
 path:'锁 › 成员 › 中心', why:'把“人”和“钥匙”放在一起看。',
 act:'进入某人，或管理借还。', states:['正常','已归档','借用中'],
 blocks:[{type:'pills',items:['全部','管理员','家人','访客']},
  {type:'sec',title:'档案',rows:[
   {i:'☺',t:'家人 A',s:'2 枚凭证 · 最近 08:12',tone:'t-info'},
   {i:'☺',t:'王阿姨',s:'1 条临时码 · 借用中',tone:'t-warn'}]}]},

{id:'memberDetail360', t:'成员 360', g:'成员', parent:'成员中心', sub:'一人一页',
 path:'锁 › 成员 › 详情', why:'关于这个人，所有相关事实在一页。',
 act:'调整权限、撤销凭证、看记录。', states:['活跃','借出中','已归档'],
 blocks:[{type:'stats',title:'家人 A',items:[{v:'2',l:'凭证'},{v:'36',l:'本月开锁'},{v:'3',l:'最近告警'},{v:'—',l:'借出'}]},
  {type:'sec',title:'权限',rows:[
   {i:'⚿',t:'密码开门',sw:1,tone:'t-ok'},
   {i:'☝',t:'指纹开门',sw:1,tone:'t-ok'},
   {i:'◷',t:'临时码',sw:0,tone:'t-gray'}]}]},

{id:'memberWizard', t:'添加成员', g:'成员', parent:'成员中心', sub:'三步',
 path:'锁 › 成员 › 添加', why:'不要在添加时就要求一串技术决定。',
 act:'填名字 → 选凭证 → 设有效期。', states:['第 1 步','第 2 步','第 3 步','完成'],
 blocks:[{type:'form',title:'第 1 步 · 是谁',fields:[{l:'称呼',v:'妈妈'},{l:'关系',v:'家人'}]},
  {type:'ctx',items:[{t:'上一步'},{t:'下一步'}]}]},

{id:'mergeMembers', t:'合并成员', g:'成员', parent:'成员中心', sub:'两条档案 → 一条',
 path:'锁 › 成员 › 合并', why:'同一个人被录了两次，要能收拢。',
 act:'选主档案，把凭证并过去。', states:['选择中','预览','已合并'],
 blocks:[{type:'sec',title:'将合并',rows:[
   {i:'☺',t:'妈妈',s:'主档案 · 2 枚凭证',tone:'t-brass'},
   {i:'☺',t:'Mother',s:'并入 · 1 枚凭证',tone:'t-gray'}]},
  {type:'ctx',items:[{t:'取消'},{t:'合并'}]}]},

{id:'memberArchived', t:'已归档成员', g:'成员', parent:'成员中心', sub:'2 人',
 path:'锁 › 成员 › 已归档', why:'离开的人不该还在列表里，但记录要留。',
 act:'恢复或彻底移除。', states:['有归档','空'],
 blocks:[{type:'sec',title:'归档',rows:[
   {i:'☺',t:'前租客',s:'归档于 2026-08 · 凭证已撤销',tone:'t-gray'}]}]},

{id:'memberFamilySettings', t:'家庭设置', g:'成员', parent:'成员中心', sub:'家庭名 · 公告 · 关怀',
 path:'锁 › 成员 › 家庭设置', why:'这个家作为一个整体，怎么被称呼与提醒。',
 act:'改家庭名、开关怀提醒。', states:['默认','已改名'],
 blocks:[{type:'form',title:'家庭',fields:[{l:'家庭名',v:'林家'},{l:'公告',v:'出门记得反锁'}]},
  {type:'sec',title:'关怀',rows:[{i:'◷',t:'生日提醒',sw:1,tone:'t-ok'},{i:'◷',t:'回家报平安',sw:0,tone:'t-gray'}]}]},

{id:'borrowSheet', t:'借用钥匙', g:'成员', parent:'成员中心', sub:'临时借出 · 自动收回',
 path:'锁 › 成员 › 借用', why:'借一次，而不是送一把。',
 act:'设归还时间，生成临时凭证。', states:['借出中','已归还','已过期'],
 blocks:[{type:'form',title:'借用',fields:[{l:'借给',v:'王阿姨'},{l:'归还',v:'今天 20:00'},{l:'次数',v:'3 次'}]},
  {type:'note',text:'到期自动失效，无需再操作；提前收回会立即生效。'}]},

{id:'memberStacked', t:'成员叠放视图', g:'成员', parent:'成员中心', sub:'按权限层叠',
 path:'锁 › 成员 › 叠放', why:'权限多起来后，用层叠看清谁能做什么。',
 act:'点某一层看这组人。', states:['2 层','3 层'],
 blocks:[{type:'sec',title:'层',rows:[
   {i:'▤',t:'管理员',s:'2 人 · 全部权限',tone:'t-brass'},
   {i:'▤',t:'家人',s:'4 人 · 密码 + 指纹',tone:'t-info'},
   {i:'▤',t:'访客',s:'1 人 · 临时码',tone:'t-warn'}]}]},

{id:'unclaimedClaim', t:'认领指纹', g:'成员', parent:'家人与访客', sub:'1 个未认领',
 path:'锁 › 家人与访客 › 认领', why:'有人录了指纹但没说是谁，需要认领。',
 act:'指定归属，或删除。', states:['未认领','已认领'],
 blocks:[{type:'sec',title:'未知指纹',rows:[
   {i:'？',t:'指纹 #3',s:'最近使用：今天 07:58',tone:'t-warn'}]},
  {type:'ctx',items:[{t:'删除'},{t:'指定给成员'}]}]},

/* ---------------- 记录 ---------------- */
{id:'records', t:'记录', g:'记录', tab:'记录', sub:'前门 · 最近 30 天',
 path:'记录（主 Tab）', why:'发生过什么：时间、谁、结果。',
 act:'筛选类型，或点开一条看详情。', states:['全部','仅有告警','空','加载失败'],
 blocks:[{type:'pills',items:['全部','开锁','告警','成员']},
  {type:'timeline',days:[
   {d:'今天',rows:[
    {time:'08:12',i:'⚿',t:'开锁',s:'指纹 · 你 · 1.4 秒',tone:'t-ok'},
    {time:'07:58',i:'↥',t:'自动上锁',s:'关门后 6 秒',tone:'t-gray'}]},
   {d:'昨天',rows:[
    {time:'22:40',i:'△',t:'低电提醒',s:'电量 18% · 建议本周更换',tone:'t-warn'},
    {time:'19:03',i:'☺',t:'临时访客开锁',s:'王阿姨 · 18:00–20:00',tone:'t-info'}]}]},
  {type:'sec',title:'',rows:[{i:'⌫',t:'清理旧记录',s:'保留 30 天',tone:'t-gray'}]}]},

{id:'recordsSampleGuide', t:'记录样例说明', g:'记录', parent:'记录', sub:'第一次打开时',
 path:'记录 › 样例说明', why:'没有记录时，解释记录会长什么样。',
 act:'看完即关闭，不再打扰。', states:['首次','已读'],
 blocks:[{type:'note',text:'一条记录只包含四件事：时间、谁、做了什么、结果。没有日志时这里会是空的，不会拿假数据填。'}]},

{id:'alarmCenter', t:'告警中心', g:'记录', parent:'记录', sub:'2 条待处理',
 path:'记录 › 告警', why:'真正需要注意的事，不该混在流水里。',
 act:'逐条确认、跳转到对应锁或成员。', states:['有告警','已清空'],
 blocks:[{type:'sec',title:'待处理',rows:[
   {i:'△',t:'后门低电',s:'18% · 昨天 22:40',val:'查看',tone:'t-warn'},
   {i:'△',t:'连续 3 次密码错误',s:'今天 06:12 · 前门',val:'查看',tone:'t-danger'}]}]},

{id:'stats', t:'统计', g:'记录', parent:'记录', sub:'本月 · 全部锁',
 path:'记录 › 统计', why:'用趋势回答“这个月正常吗”。',
 act:'切时间范围；点柱子看当天。', states:['本月','上月','自定义'],
 blocks:[{type:'stats',title:'本月',items:[{v:'128',l:'开锁次数'},{v:'96%',l:'一次成功'},{v:'1.4s',l:'平均耗时'},{v:'3',l:'告警'}]},
  {type:'note',text:'只统计真实发生过的记录；没有数据的日期留空，不用 0 冒充。'}]},

{id:'yearReport', t:'年度报告', g:'记录', parent:'记录', sub:'2026 · 可分享',
 path:'记录 › 年度', why:'一年结束，给自己看的一页总结。',
 act:'生成并保存/分享。', states:['生成中','已生成'],
 blocks:[{type:'stats',title:'2026',items:[{v:'1,482',l:'开锁'},{v:'0',l:'忘带钥匙'},{v:'最快的月份',l:'3 月'}]}]},

{id:'exportCenter', t:'导出中心', g:'记录', parent:'记录', sub:'CSV · JSON · 图片',
 path:'记录 › 导出', why:'把记录带走，用于报修或留档。',
 act:'选格式与范围，导出到文件。', states:['选择中','导出中','完成','失败'],
 blocks:[{type:'sec',title:'格式',rows:[
   {i:'▤',t:'CSV',s:'表格软件可读',tone:'t-info'},
   {i:'{ }',t:'JSON',s:'完整字段',tone:'t-gray'},
   {i:'▧',t:'图片摘要',s:'一页长图',tone:'t-brass'}]},
  {type:'ctx',items:[{t:'取消'},{t:'导出'}]}]},

{id:'gratitude', t:'感谢与致谢', g:'记录', parent:'记录', sub:'帮助过这个项目的人',
 path:'记录 › 致谢', why:'把人和事的来处写清楚。',
 act:'阅读即可。', states:['静态'],
 blocks:[{type:'note',text:'这一页只放真实致谢：开源库、测试设备提供者、提出过关键问题的用户。'}]},

/* ---------------- 安全 ---------------- */
{id:'securityCenter', t:'安全中心', g:'安全', parent:'设置', sub:'评分 86 · 3 项建议',
 path:'设置 › 安全', why:'这个家现在的安全状态，以及下一步做什么。',
 act:'按建议逐项加固。', states:['良好','有风险','高风险'],
 blocks:[{type:'stats',title:'安全评分',items:[{v:'86',l:'/ 100'},{v:'3',l:'建议'}]},
  {type:'sec',title:'建议',rows:[
   {i:'⚿',t:'轮换 2 条旧密码',s:'超过 180 天',tone:'t-warn'},
   {i:'☝',t:'补录家人指纹',s:'1 人没有指纹',tone:'t-info'},
   {i:'◫',t:'开启尾随防护',s:'当前关闭',tone:'t-warn'}]}]},

{id:'securityAudit', t:'安全审计', g:'安全', parent:'安全中心', sub:'逐项核查',
 path:'设置 › 安全 › 审计', why:'把“感觉安全”换成可核对的事实。',
 act:'运行审计；每项给出证据。', states:['未运行','运行中','通过','有项未过'],
 blocks:[{type:'sec',title:'检查项',rows:[
   {i:'✓',t:'凭证未过期',val:'通过',tone:'t-ok'},
   {i:'✓',t:'固件为最新',val:'通过',tone:'t-ok'},
   {i:'!',t:'访客权限范围',val:'偏大',tone:'t-warn'}]}]},

{id:'securityPeek', t:'防偷窥', g:'安全', parent:'安全中心', sub:'输入时遮挡',
 path:'设置 › 安全 › 防偷窥', why:'在公共场合输入密码时，别让旁人看到。',
 act:'开关遮挡与自动模糊。', states:['开','关'],
 blocks:[{type:'sec',title:'遮挡',rows:[
   {i:'◉',t:'密码输入遮挡',sw:1,tone:'t-ok'},
   {i:'◉',t:'切后台自动模糊',sw:1,tone:'t-ok'}]}]},

{id:'securityDestroy', t:'远程销毁', g:'安全', parent:'安全中心', sub:'手机丢失时',
 path:'设置 › 安全 › 销毁', why:'最坏情况下，把本机凭证清干净。',
 act:'二次确认后销毁；不可撤销。', states:['未启用','已启用','执行中'],
 blocks:[{type:'note',text:'<b>这会删除本机所有钥匙与记录，且不能恢复。</b>锁端的凭证需要另外撤销，界面会列出没做的那一半，避免“以为清了”。'},
  {type:'ctx',items:[{t:'取消'},{t:'销毁本机数据',danger:1}]}]},

{id:'defend', t:'尾随防护', g:'安全', parent:'安全中心', sub:'关门后提醒未反锁',
 path:'设置 › 安全 › 尾随防护', why:'有人跟着进门时，给自己一个提醒。',
 act:'开关与延迟。', states:['关','开','仅夜间'],
 blocks:[{type:'sec',title:'行为',rows:[
   {i:'◷',t:'关门后提醒',s:'6 秒内未反锁',sw:1,tone:'t-ok'},
   {i:'◷',t:'仅夜间生效',s:'22:00–06:00',sw:1,tone:'t-ok'}]}]},

{id:'butlerCertificate', t:'管家证书', g:'安全', parent:'安全中心', sub:'长期访客的授权凭证',
 path:'设置 › 安全 › 管家证书', why:'长期帮忙的人需要稳定授权，也要能随时收回。',
 act:'签发、查看、撤销。', states:['有效','即将到期','已撤销'],
 blocks:[{type:'sec',title:'证书',rows:[
   {i:'▣',t:'保洁 · 每周三',s:'有效至 2026-12-31',val:'有效',tone:'t-ok'}]}]},

{id:'safemodeIntro', t:'安全模式说明', g:'安全', parent:'安全中心', sub:'异常时的降级',
 path:'设置 › 安全 › 安全模式', why:'出了问题时，App 会怎么保护你。',
 act:'了解并开启。', states:['未开启','已开启'],
 blocks:[{type:'note',text:'安全模式只做三件事：停用自动开锁、要求每次手动确认、把可疑记录置顶。它不会锁死你的门。'}]},

{id:'tailgate', t:'门未关提醒', g:'安全', parent:'安全中心', sub:'虚掩检测',
 path:'设置 › 安全 › 门未关', why:'门没关严，是这个家最常见的风险。',
 act:'开关提醒与重复间隔。', states:['关','开'],
 blocks:[{type:'sec',title:'提醒',rows:[
   {i:'△',t:'门未关提醒',sw:1,tone:'t-ok'},
   {i:'◷',t:'重复间隔',val:'10 分钟',tone:'t-gray'}]}]},

{id:'houseCleaningPreset', t:'保洁预设', g:'安全', parent:'安全中心', sub:'一次性授权',
 path:'设置 › 安全 › 保洁预设', why:'给保洁开门，不该给一把长期钥匙。',
 act:'选时段与范围，一次生成。', states:['未生成','生成中','已生效'],
 blocks:[{type:'form',title:'预设',fields:[{l:'时段',v:'周三 09:00–11:00'},{l:'范围',v:'仅大门'},{l:'次数',v:'1 次'}]}]},

{id:'accessibility', t:'无障碍', g:'安全', parent:'设置', sub:'字号 · 对比度 · 动效',
 path:'设置 › 无障碍', why:'每个人都能开门，包括看不清、听不见、手不稳的人。',
 act:'调字号、对比度、减弱动效。', states:['默认','大字号','高对比','减弱动效'],
 blocks:[{type:'sec',title:'显示',rows:[
   {i:'A',t:'更大字号',s:'跟随系统',val:'开',tone:'t-gray'},
   {i:'◐',t:'增强对比',sw:0,tone:'t-gray'},
   {i:'◷',t:'减弱动态效果',sw:0,tone:'t-gray'}]},
  {type:'note',text:'所有可点区域 ≥ 44pt；状态不只靠颜色表达（同时有图标与文字）。'}]},

/* ---------------- 数据 ---------------- */
{id:'backup', t:'备份与恢复', g:'数据', parent:'设置', sub:'上次备份 今天 07:30',
 path:'设置 › 备份与恢复', why:'换手机、丢手机时，钥匙不能丢。',
 act:'立即备份，或从备份恢复。', states:['从未备份','已备份','备份中','失败'],
 blocks:[{type:'sec',title:'本机',rows:[
   {i:'↧',t:'立即备份',s:'加密后写入文件',tone:'t-brass'},
   {i:'↥',t:'从备份恢复',s:'会覆盖当前数据',tone:'t-info'},
   {i:'◫',t:'备份位置',val:'本机文件',tone:'t-gray'}]},
  {type:'note',text:'备份含凭证，必须加密；界面明确写清密码丢失后无法恢复。'}]},

{id:'backupStudio', t:'备份工作台', g:'数据', parent:'备份与恢复', sub:'建包 · 校验 · 历史',
 path:'设置 › 备份 › 工作台', why:'备份不是一次按钮，是一份可验证的包。',
 act:'生成包、核对校验和、查看历史。', states:['无包','已生成','校验通过','校验失败'],
 blocks:[{type:'sec',title:'包',rows:[
   {i:'▣',t:'2026-10-18 备份',s:'12.4 MB · 校验和通过',tone:'t-ok'},
   {i:'＋',t:'新建备份',tone:'t-gray'}]}]},

{id:'exportWizard', t:'导出向导', g:'数据', parent:'备份与恢复', sub:'三步',
 path:'设置 › 备份 › 导出', why:'把数据交出去时，范围要说清楚。',
 act:'选范围 → 选格式 → 确认。', states:['第 1 步','第 2 步','完成'],
 blocks:[{type:'form',title:'范围',fields:[{l:'包含',v:'记录 + 凭证'},{l:'时间',v:'最近 90 天'}]},
  {type:'ctx',items:[{t:'上一步'},{t:'下一步'}]}]},

{id:'restoreWizard', t:'恢复向导', g:'数据', parent:'备份与恢复', sub:'覆盖前先对比',
 path:'设置 › 备份 › 恢复', why:'恢复是破坏性动作，必须先看清会覆盖什么。',
 act:'选文件 → 对比差异 → 确认恢复。', states:['选文件','对比中','恢复中','完成'],
 blocks:[{type:'sec',title:'将覆盖',rows:[
   {i:'△',t:'本机 2 把锁',s:'备份里 3 把',tone:'t-warn'},
   {i:'△',t:'记录 1,204 条',s:'备份里 1,186 条',tone:'t-warn'}]},
  {type:'ctx',items:[{t:'取消'},{t:'恢复',danger:1}]}]},

{id:'migrationWizard', t:'换机向导', g:'数据', parent:'备份与恢复', sub:'旧机 → 新机',
 path:'设置 › 备份 › 换机', why:'换手机时，按步骤走不会漏。',
 act:'在旧机导出 → 在新机导入 → 逐锁验证。', states:['第 1 步','第 2 步','验证中','完成'],
 blocks:[{type:'note',text:'每一步都告诉用户“现在该在哪台手机上做什么”，不要求同时操作两台。'}]},

{id:'localFiles', t:'本机文件', g:'数据', parent:'备份与恢复', sub:'备份 · 导出 · 日志',
 path:'设置 › 备份 › 文件', why:'文件都在哪，占了多少空间。',
 act:'查看、分享、删除。', states:['空','有文件'],
 blocks:[{type:'sec',title:'文件',rows:[
   {i:'▣',t:'OfflineLock-20261018.bak',s:'12.4 MB · 今天 07:30',tone:'t-brass'},
   {i:'▤',t:'records-2026-10.csv',s:'420 KB · 昨天',tone:'t-gray'}]}]},

{id:'webDAVStudio', t:'WebDAV 备份', g:'数据', parent:'备份与恢复', sub:'自建网盘',
 path:'设置 › 备份 › WebDAV', why:'不想用第三方云，就把包放到自己的盘。',
 act:'填地址与账号，测试连接并上传。', states:['未配置','连接成功','连接失败'],
 blocks:[{type:'form',title:'连接',fields:[{l:'地址',v:'https://…'},{l:'账号',v:'••••'},{l:'路径',v:'/lock/backup'}]},
  {type:'ctx',items:[{t:'测试连接'},{t:'保存'}]}]},

{id:'messages', t:'消息', g:'数据', parent:'设置', sub:'2 条未读',
 path:'设置 › 消息', why:'App 想告诉你的非紧急事项。',
 act:'读，或全部标为已读。', states:['有未读','全部已读'],
 blocks:[{type:'sec',title:'未读',rows:[
   {i:'✉',t:'本月安全报告已生成',s:'昨天 09:00',tone:'t-info'},
   {i:'✉',t:'备份成功',s:'今天 07:30',tone:'t-ok'}]}]},

/* ---------------- 关怀 ---------------- */
{id:'careReminders', t:'关怀提醒', g:'关怀', parent:'设置', sub:'生日 · 报平安',
 path:'设置 › 关怀', why:'技术之外，家人之间的小事。',
 act:'开关各类提醒与时间。', states:['默认','已开启','全部关闭'],
 blocks:[{type:'sec',title:'提醒',rows:[
   {i:'◷',t:'家人生日',sw:1,tone:'t-ok'},
   {i:'◷',t:'回家报平安',sw:0,tone:'t-gray'},
   {i:'◷',t:'久未开锁',s:'7 天无人进出',sw:1,tone:'t-ok'}]}]},

{id:'maintenance', t:'保养', g:'关怀', parent:'设置', sub:'下次保养 11 月',
 path:'设置 › 保养', why:'锁也需要被照顾，尤其是电池与锁芯。',
 act:'查看保养项，标记完成。', states:['未到期','即将到期','已逾期'],
 blocks:[{type:'sec',title:'保养项',rows:[
   {i:'◫',t:'更换电池',s:'预计 11 月 · 电量 86%',tone:'t-info'},
   {i:'⌗',t:'锁芯润滑',s:'上次 6 个月前',tone:'t-warn'}]}]},

{id:'maintSettings', t:'保养设置', g:'关怀', parent:'保养', sub:'周期 · 提醒方式',
 path:'设置 › 保养 › 设置', why:'不同家庭的节奏不同。',
 act:'调周期与提醒。', states:['默认','自定义'],
 blocks:[{type:'form',title:'周期',fields:[{l:'电池提醒',v:'低于 20%'},{l:'润滑',v:'每 12 个月'}]}]},

{id:'batterySwapGuide', t:'换电池指南', g:'关怀', parent:'保养', sub:'图文 · 3 步',
 path:'设置 › 保养 › 换电池', why:'用户第一次换电池时，不该靠猜。',
 act:'按步骤操作；每步可放大。', states:['第 1 步','第 2 步','第 3 步'],
 blocks:[{type:'note',text:'只写这把锁的真实结构：电池仓在下沿，向上推，不需要工具。配图按下真机拍摄，不用示意图冒充。'}]},

{id:'achievements', t:'成就', g:'关怀', parent:'设置', sub:'12 / 30',
 path:'设置 › 成就', why:'长期使用需要一点正反馈，但不喧宾夺主。',
 act:'查看已达成与进行中。', states:['有进展','全部达成'],
 blocks:[{type:'stats',title:'进度',items:[{v:'12',l:'已达成'},{v:'18',l:'进行中'}]},
  {type:'sec',title:'最近',rows:[{i:'★',t:'连续 30 天安全',s:'还差 4 天',tone:'t-brass'}]}]},

{id:'capsuleCompose', t:'胶囊编辑', g:'关怀', parent:'成就', sub:'写一条给未来的自己',
 path:'设置 › 成就 › 胶囊', why:'把此刻的心情留在 App 里。',
 act:'写、封存、到期打开。', states:['草稿','已封存','已打开'],
 blocks:[{type:'form',title:'内容',fields:[{l:'标题',v:'搬家第一天'},{l:'打开时间',v:'2027-10-18'}]},
  {type:'ctx',items:[{t:'存草稿'},{t:'封存'}]}]},

{id:'changeBatch', t:'更新批次', g:'关怀', parent:'设置', sub:'这一版改了什么',
 path:'设置 › 更新说明', why:'用户要知道升级带来了什么，而不是看提交记录。',
 act:'阅读；可回看历史版本。', states:['最新','历史'],
 blocks:[{type:'sec',title:'本版',rows:[
   {i:'✦',t:'新增：精确查找层',s:'走近自动弹出',tone:'t-brass'},
   {i:'✦',t:'改进：开锁提速',s:'热链路复用',tone:'t-info'}]}]},

{id:'changelog', t:'更新日志', g:'关怀', parent:'设置', sub:'按版本',
 path:'设置 › 更新日志', why:'完整的历史，供排查与回溯。',
 act:'展开某一版。', states:['折叠','展开'],
 blocks:[{type:'sec',title:'版本',rows:[
   {i:'▸',t:'1.0.20261018',s:'UIUX v3 · 设计层重建',tone:'t-brass'},
   {i:'▸',t:'1.0.20261017',s:'AirTag 双层 · 提速',tone:'t-gray'}]}]},

{id:'demoLabs', t:'实验室', g:'关怀', parent:'设置', sub:'未上线的能力',
 path:'设置 › 实验室', why:'把试验功能收在一处，默认关闭。',
 act:'逐项开启，随时可关。', states:['全关','部分开启'],
 blocks:[{type:'sec',title:'实验',rows:[
   {i:'⚗',t:'语音开锁',s:'实验 · 可能误触发',sw:0,tone:'t-gray'},
   {i:'⚗',t:'桌面小组件 2.0',sw:0,tone:'t-gray'}]}]},

{id:'integrationCenter', t:'集成', g:'关怀', parent:'设置', sub:'快捷指令 · 日历',
 path:'设置 › 集成', why:'把开锁接进系统能力，而不是再造一个入口。',
 act:'开关集成，查看权限。', states:['未连接','已连接'],
 blocks:[{type:'sec',title:'系统',rows:[
   {i:'◈',t:'快捷指令',s:'“开锁”动作',sw:1,tone:'t-ok'},
   {i:'◈',t:'日历',s:'访客到访写入',sw:0,tone:'t-gray'}]}]},

/* ---------------- 诊断 ---------------- */
{id:'diagnostics', t:'诊断', g:'诊断', parent:'设置', sub:'协议 · 链路 · 最近错误',
 path:'设置 › 诊断', why:'出问题时，先看事实，不看猜测。',
 act:'跑自检、复制摘要、查协议。', states:['正常','有错误','自检中'],
 blocks:[{type:'sec',title:'自检',rows:[
   {i:'✓',t:'BLE 链路',s:'RSSI −52 · MTU 247',val:'通过',tone:'t-ok'},
   {i:'✓',t:'凭证写入',s:'最近 08:12',val:'通过',tone:'t-ok'},
   {i:'!',t:'回执时延',s:'最近 1 次 3.2 秒',val:'偏高',tone:'t-warn'}]},
  {type:'ctx',items:[{t:'复制摘要'},{t:'跑完整自检'}]}]},

{id:'diagReference', t:'协议参考', g:'诊断', parent:'诊断', sub:'命令 · 返回码',
 path:'设置 › 诊断 › 协议', why:'排查时要能对照协议，而不是背。',
 act:'搜索命令或返回码。', states:['浏览','搜索'],
 blocks:[{type:'form',title:'查返回码',fields:[{l:'rc=13',v:'令牌无效 / 长度读偏'},{l:'rc=3',v:'鉴权失败'}]},
  {type:'note',text:'这一页是只读参考，不允许在这里发命令——避免把排障变成误操作。'}]},

{id:'symptomGuide', t:'症状指南', g:'诊断', parent:'诊断', sub:'按现象找原因',
 path:'设置 › 诊断 › 症状', why:'用户描述的是现象，不是错误码。',
 act:'选症状，得到可执行的下一步。', states:['选择症状','给出步骤'],
 blocks:[{type:'sec',title:'常见现象',rows:[
   {i:'?',t:'点了没反应',s:'先看链路与权限',tone:'t-warn'},
   {i:'?',t:'开锁要等很久',s:'热链路 / 信号',tone:'t-info'},
   {i:'?',t:'偶尔开两次',s:'回执超时重发',tone:'t-danger'}]}]},

/* ---------------- 设置 ---------------- */
{id:'settings', t:'设置', g:'设置', tab:'设置', sub:'前门 · 它怎么行为',
 path:'设置（主 Tab）', why:'这把锁怎么行为：连接、数据、安全、关于。',
 act:'进入某一组；危险动作都要二次确认。', states:['默认','访客受限','有未读消息'],
 blocks:[{type:'sec',title:'连接与开锁',rows:[
   {i:'⌁',t:'蓝牙与连接',s:'已连接 · 自动重连开',tone:'t-info'},
   {i:'⌖',t:'靠近自动开锁',s:'仅 App 前台扫描',val:'开',tone:'t-ok'},
   {i:'◷',t:'连接偏好',s:'超时 · 信号刷新',tone:'t-gray'}]},
  {type:'sec',title:'安全',rows:[
   {i:'◈',t:'安全中心',s:'评分 86 · 3 项建议',val:'3',tone:'t-warn'},
   {i:'◉',t:'防偷窥',tone:'t-gray'},
   {i:'◫',t:'尾随防护',s:'关门后提醒',sw:1,tone:'t-ok'}]},
  {type:'sec',title:'数据与关怀',rows:[
   {i:'↧',t:'备份与恢复',s:'今天 07:30',tone:'t-brass'},
   {i:'✉',t:'消息',s:'2 条未读',badge:'2',tone:'t-info'},
   {i:'◷',t:'关怀提醒',tone:'t-gray'},
   {i:'◫',t:'保养',s:'下次 11 月',tone:'t-gray'}]},
  {type:'sec',title:'诊断与关于',rows:[
   {i:'⌁',t:'诊断',s:'协议 · 链路 · 错误',tone:'t-gray'},
   {i:'⚗',t:'实验室',s:'默认全关',tone:'t-gray'},
   {i:'▸',t:'更新日志',val:'1.0.261018',tone:'t-gray'}]}]}
];
