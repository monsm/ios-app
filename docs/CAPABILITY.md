# CAPABILITY — 锁端能力对照矩阵（离线锁管家 triage 依据）

来源缩写：REP=REVERSE_REPORT.md；cmds=vendor/app/utils/kernel/cmds.js；P=…/kernel/protocol.js；lbl=…/kernel/labels.js；lock=vendor/app/services/lock.js；attr=…/attribution.js；SP=App/Core/StatusParser.swift；PM=App/Core/PidMap.swift。只列来源确证项；？=来源提及但语义/参数未确证，不推测。

## 1. 命令全集（32 条确证，cmdId 十六进制）
命令号 06/07/09/0F-11/17/1A-1F/26-2F(除网关)/33/34/36/37/39/3A/42 协议未定义（REP:63 全表无）。密文面统一：body→EKey(0x88)包络→AES-128-ECB(skey)→KLV#xx；令牌经 KLV#0xEE 注入（P:12-12,151）。0C/0D 本代 App 无实现，禁止下发（cmds:5）。

| Cmd | 名称(官方) | 参数/响应要点 | 来源 |
|---|---|---|---|
| 01 | GETSESSIONTOKEN 会话令牌 | 无参；响应 #01=safety(bit1=1→Token) #02=token #03=有效期秒 u16 | REP:61 |
| 02 | GETBLEMAC | 读锁 BLE MAC；未入 cmds 实现面 | REP:63 |
| 03 | GETSTATUS 状态 | 密文版 #01=0x88EKey(cmd03)+#02=空，明文版无 KLV；响应字段见 §2；rc@#03 | cmds:53, lock:19 |
| 04 | OPEN 开锁 | #01=左补零32 #02=凭证=hex(AES(skey)(88 00 MAC反 TrackId VF VT 04 pinLE 00 00))；rc@#03；rc=22→双验继续 | cmds:65-82, lock:370-386 |
| 05 | EXSECURITYKEY 换钥 | 免令牌；#01=时间 #02=交换方式 1B #03=skey 16B；响应 #01=rc #02=skey 回显；执行即擦旧钥域 | cmds:42-47, P:17-19 |
| 08 | SYNCPINS PIN 池 | addCount+delCount(各1B)+addPins(4B LE×N, ≤20/批)+delPins；首批 delPins=FFFFFFFF 清哨兵；rc@#03 | cmds:84-92, lock:18 |
| 0A | SYNCPWD 密码 | delAlias(2B LE, 0xFFFF=清空全部)+addPwd(8B ASCII 右补零, ≤8位)+VF/VT(4B LE)；响应 #04=alias(2B LE) | cmds:98-106, lock:449 |
| 0B | SYNCPWDEXPIRE 密码改期 | alias(2B LE)+VF/VT(4B LE 协议秒) | cmds:107-111 |
| 0C | SYNCPWDFREEZEPOLICY 冻结策略 | 参数未确证 ？——不下发 | cmds:5 |
| 0D | SETZOTPPERIOD OTP 周期 | 参数未确证 ？——不下发 | cmds:5 |
| 0E | SYNCTIME 校时 | 协议秒 u32 LE（基准 2010-01-01） | cmds:112-116, P:14 |
| 12 | ECHO 回声 | #01=hex'123456'（3B 魔数）；连通探测 | cmds:50, P:172-174 |
| 13 | ADDNEWFP 录指纹 | times(1B 官方8)+timeout(1B 默认15s)；多帧响应 orderIdx@#04 featureNumber@#05 batchNumber@#06 nextTimeout@#07，orderIdx=0 收尾 | cmds:117-123, lock:498-514 |
| 14 | ADDNEWFPCONFIRM 指纹确认 | batchNumber(4B LE)+指纹 VF/VT(4B LE) | cmds:124-128 |
| 15 | DELETEFP 删指纹 | batchNumber(4B LE) | cmds:129-133 |
| 16 | GETLOG 日志 | orderType(1B)+startIdx(4B LE)+pageSize(1B 默认20)；响应 rc@#03 剩余条数@#04 每条@#05 | cmds:134-141, SP:4 |
| 18 | SETSOUNDVOLUMN 音量 | 1B；App setSilentMode 语义 0=有声 1=静音 | cmds:142-146, lock:409 |
| 19 | OPENZOTP 临时码开关 | 1B 0=关/1=开（码生成在手机端，见 §4） | cmds:147-151 |
| 20 | SETVALIDATIONMODE 单/双验 | 1B 0=A单验/1=B双验 | cmds:152-156 |
| 21 | SETBEACONKEY bkey | skeyLen(1B=0x10)+bkey(16B, 相邻字节约束) | cmds:93-97 |
| 22 | ENABLEDFU | param(1B)=0→重启进 bootloader（广播名 ZkDFU, MAC+1；断链属预期） | cmds:243-248, lock:426 |
| 23 | GETEXSECURITYKEYWAY 交换方式 | 免令牌；响应 #01=way 位（固件要求 bit1=1） | cmds:48, lock:544-547 |
| 24 | SETMOTOAUTOLOCKINTERVAL 自动上锁 | interval 1B 档位 1-6 | cmds:157-161 |
| 25 | SETDEFENCE 布防 | control(1B 0=关/1=不定期/2=时间段/3=readonly)+start/end(4B LE 日内秒) | cmds:162-166 |
| 30 | GWGETDEVICENAME 网关名称 | 无 KLV；响应 #01=deviceName | cmds:225-228 |
| 31 | GWSETWIFI 网关配网 | #01 SSID #02 密码(UTF8 hex) #03 authMode(App=8 WPA/WPA2-PSK) #04 encryptType(App=0) #05(1B)；响应 errCode@#01 | cmds:204-215 |
| 32 | GWSETIOT 网关 IoT | #05 iotpKey #06 iotdSec #07 devAccToken——云端档案，厂商云停服，构造器保留不下发 | cmds:216-220 |
| 35 | GWREBOOT 网关重启 | 无 KLV；响应 errCode@#01 | cmds:221-224 |
| 38 | GWGETSTATUS 网关状态 | 无 KLV；响应 #01 wifimac #02 romVer #03 eCtrlVer #04 ssid #05 wifiIP #06 netState | cmds:200-203 |
| 41 | WRITEEKEY 钥匙串写钥 | 明文帧免令牌；#01 锁MAC(6B反) #02 type(恒1) #03 pid(2B LE) #04 ekey 密文（空串=删除） | cmds:178-187 |
| 43 | GETSTATUS 钥匙串状态 | #01=各锁 MAC 逐个 6B 反转拼接 | cmds:193-198 |
| 44 | GETEKEYINFO 钥匙串查钥 | #01 锁MAC 6B 反转（空=全部钥匙） | cmds:188-192 |

## 2. 状态/字段全集（03 响应 KLV，lbl:4-23）
- 01 sKeyStatus 密钥状态 — 取值语义 ？（01 会话响应同位参考：1=Clear/2=ECDH，REP:61）
- 03 resultCode 总 rc（0=成功；1..27 锁端码见 lbl:35-43 / SP:142-149）
- 04 lockTime 锁钟，协议秒 u32 LE（0 视为无效不上报，SP:56-59）
- 05 zotpPeriod u16 LE，单位分钟（zotp.js:21 按 60·period 取整），默认 30
- 06 keyboardFreeze 键盘冻结 / 07 keyboardErrCount 密码连续错误次数（取值仅标签名确证 ？）
- 08 securityLevel 位域：bit0=verify 单双验、bit1=broadcast 状态广播、bit2=tempPwd 临时码开通（lbl:8, SP:70-74）
- 11 powerLevel 电量（整数，App 按 % 展示，lbl:92-95）
- 14 soundVolumn 音量 1B（写入语义 0=有声/1=静音，lock:409-413）
- 21/22/23 pinInfo Capacity/Stock/Binding — PIN 池容量/剩余/绑定数
- 24/25/26 pwdInfo Capacity/Stock/MaxLen — 密码容量/剩余/最大长度
- 27/28/29 fpInfo Capacity/Stock/BatchNumber — 指纹容量/剩余/批号
- 31 verFirmware 3B→a.b.c；32 verDFU；33 verKeyboard u16 LE；34 pid u32 LE；35 eCtrlVer ASCII（SP:88-108）
- EE requestToken 回显（lbl:22）
- 关联响应字段：16 剩余日志数 surplus@#04（lock:528）；0A 返回 alias@#04（lock:449）；网关 38 六字段见 §1

## 3. 日志与告警类型全集（cmd16 每条 [type 1B][len 1B][idx 4B LE][lockTime 4B LE][body]，SP:4,117-123）
- 开门类：1 数字钥匙 / 2 密码 / 3 指纹 / 4 临时密码 / 5 NFC（attr:13-15 与 REP:102 一致）
- 告警类：6 电量低、7 撬锁（防撬）、10 多次密码失败锁定、13 指纹告警、224 键盘被锁定
- 事件类：8 重新上电、9 DFU 后版本、12 授时
- 操作类：14 同步PIN、15 同步密码、20 添加指纹、21 删除指纹、22 设置安全级别、23 状态广播开关、24 设置单双验、25 开通临时密码、26 设置音量、27 设置 beacon 密钥
- 11/16/17/19 为预研错枚举已勘误，非真实类型（attr:13-14）；胁迫/防尾随/门磁告警类型：协议未定义
- 日志条目无身份字段（无 alias/指纹批号）→「谁开的门」只能本地台账推断（attr:1-8）

## 4. 凭证语义
- 密码：≤8 位 ASCII（cmds:102）；时间窗 VF/VT（协议秒；App 永久=2010-01-01~2118-01-01，cmds:169-170）；添加 0A→别名→0B 改期两步链（lock:444-467）；原位改写=0A 带 delAlias+新密码（lock:468-484）；删除=0A delAlias；清空=delAlias 0xFFFF（lock:489-492）；改期随时可改（0B）→ 支持：时间窗/删除/改期/清空；一次性、周期重复、暂停：协议未定义（0C 冻结策略 ？）
- PIN 池：64 个 4B LE 随机（<2^31、池内去重），≤20/批，首批清哨兵（keys.js:93-116, lock:564-572）；PIN 不直接开门，用于本端自签发凭证
- 开锁凭证 ekey：AES-ECB(skey)($t 包络 88 00 MAC反 TrackId VF VT 04 pinLE bind times)（cmds:78-82）；钥匙串分享版窗口本地时区 2010~2118+随机 TrackId（cmds:171-177）；钥匙串分享权限 0 关/1 不定期/2 周期/3 只读属 App 云端模型（REP:103），锁命令无此字段
- ZOTP 临时码：6 位 = AES-ECB(skey,ZeroPadding)( u(8hex)+MAC反序(12hex)+idx(2B BE)+"00000000" ) 密文前 24hex 每 4hex (b1^b2)%10；u=floor(协议秒/(60·period))，period 单位分钟、默认 30；idx App 走云端自增，离线端本地持久自增且锁不独立验证 idx；前提锁钟已校（0E）（zotp.js:1-6,19-37）；cmd 19 仅开关功能，生成不经锁
- 容量上限：全部实时读 21/24/27（协议不硬编码）；App 侧 PIN 池恒 64、密码 ≤8 位
- 远程性：一切凭证操作均 BLE 近场；临时码可离线生成但开通（19）需在场

## 5. 明确不支持 / 协议中不存在（triage ❌ 依据）
- 门磁状态：无字段无命令（rc=21「反锁状态」仅是开锁失败错误码，非状态查询，lbl:40）
- 反锁/上锁状态位：03 状态无此字段
- 在线状态：无（纯 BLE 近场协议；网关 netState 只是网关自身联网位，gateway.js:213）
- 推送/远程操作：App 依赖厂商云推送与网关 IoT（cmd 32）——云停服即失效；网关命令面(30-38)不含锁指令透传（REP:63）
- 电量历史/趋势：无，仅实时 0x11 + 本地快照（snapshot.js:1-5）
- 胁迫指纹/胁迫告警：日志类型表无此项（SP:117-123）
- NFC 卡管理：日志有 type5、产品有 Z3NFC，但命令面无发卡/删卡命令（？）
- 防尾随：App 走云端 settings key tailgate（REP:104；V1_Pro 需 ROM≥1.0.3）——锁命令面无对应命令，离线不可设（？）
- 凭证命名：锁端无名称字段，App 台账本地命名（REP:95 Modifypwd/fpname 页）
- 日志清空/上传：无清空命令，仅 16 翻页读（cmds:134-141）；身份归属锁端不含（attr:1-3）

## 6. DFU / 网关 / 校时能力
- DFU：cmd 22 进 bootloader → 扫描（pid 一致 + dfuState 位=1 + MAC=原或+1，15s 超时）→ Nordic zip（manifest.json+bin+dat init packet）Secure(FE59) 优先、Legacy(1530) 回退 → 进度 0-7（6=完成）；包需本机导入（云停服）；zip CRC 必须通过，bin 512B~8MB、dat/manifest ≤4KB（dfu.js:19,5-9）；版本对比=03#31 vs 文件名版本（dfu.js:64-77）
- 网关：FE90 服务/FE92 写/FE91 通知，明文 87 帧免令牌（gateway.js:1-8）；能力=读状态(38)/配网 WiFi(31)/重启(35)/读名称(30)；配网需广播 resetStatus=1（gateway.js:41-43）；不能透传锁操作；App 侧锁与网关会话不能并存（静态 UUID 缺陷，REP:145）
- 校时：先 03 读锁钟(#04) 算偏差再 0E 下发（lock:398-408）；rc=3 命令过期 / rc=9 时间误差过大均为时钟类失败（lbl:37-38）；ZOTP 与全部凭证时间窗依赖锁钟正确（zotp.js:6）

## 7. PidMap 型号差异（PM.swift:6-54）
- pid 表：K1=8097 KX=8098 V1=7857 V1_Pro=7858 JZ=7873 Z3=7891 Z3NFC=7892 Z3AL=7893 ZKBBV1=16289（钥匙串硬件）GW=12193 GW_commercial=12209 GW2_commercial=12194（REP:101 同）
- 设备列表锁族 locks：KX/V1/V1_Pro/JZ（PM:20）
- 布防(25)：仅 KX/V1_Pro；未知 pid（如实测 49408）按 KX 家族放行（PM:32-35）
- 防尾随：布防家族且 V1_Pro 固件 <1.0.3 拒绝（PM:46-51, REP:104）
- 清空密码/设备信息/固件升级：锁族 + 未知 pid 放行；GW 族及 K1/Z3/Z3NFC/Z3AL/ZKBBV1 等已知 pid 不放行（PM:52-54）
- ZKBBV1 走 41/43/44 钥匙串命令面（明文免令牌），不进锁族（cmds:167-198）
