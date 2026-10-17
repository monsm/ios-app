# 全量对齐盘点: 本机 ↔ 原 APK 的**锁数据交互**逐项对照 (2026-10-17)

本文件是"地毯式逐行"盘点的结果与证据。方法: **不引用任何既有工具/报告作为结论** ——
直接从反编译产物重新抽取事实, 与 `ios-app/App/**` + `ios-app/vendor/app/**` + `miniprogram-app/**` 逐行对照。

抽取脚本 (一次性, 已删): `tools/_inv.py` `_inv2.py` `_dump.py` `_dump2.py` `_cls.py` `_cmp.py`,
产出 `tools/_apk_cmds.txt`(逐命令聚合) / `tools/_apk_cls.txt`(逐类 ctor+取值) / `tools/_parity_table.txt`(并排表)。

基准来源 (三处, 全部逐字读过):
- `apk_raw/assets/www/build/main.js` —— Angular 打包的 JS 层 (命令类/KLV/取值方法/调用点/状态机)
- `jzzns22561_v2/sources/cn/zelkova/ZKurlcsPlugin/lockprotocol/*.java` —— 原生层 (帧骨架/令牌/分片/超时/解析)
- 反编译入口 `cn.zelkova.ZKurlcsPlugin` 的 `LockCommResponseMapper` —— 响应类映射

## 0. 命令字典 (APK `Jn` 枚举, 逐字)

| cmd | APK 名 | 明文体 (`getCmdBody`) | 密文 KLV | needToken | 本机 |
|---|---|---|---|---|---|
| 0x01 | GETSESSIONTOKEN | (无体, 仅 8B 头) | — | 由 Java `LockCommSessionToken.needSessionToken()=false` | ✓ 一致 |
| 0x02 | GETBLEMAC | — | — | — | ⚠ APK 的 JS **没有任何类**使用它 (死枚举), 本机同样不实现 |
| 0x03 | GETSTATUS | `Ct`: 空体; KLV#01=AES(skey)($t), #02="" | 01,02 | true | ✓ 一致 |
| 0x04 | OPEN | (无 $t) KLV#01=fillZero("0000",32), KLV#02=ekey hex | 01,02 | true | ✓ 一致 |
| 0x05 | EXSECURITYKEY | KLV#01=`getProtocolTime(时间串)`(4B LE), #02=keyType(1B), #03=skey | 01,02,03 | true | ✓ 结构一致; **值已修** (见 §2.1) |
| 0x08 | SYNCPINS | addCount(1B)+delCount(1B)+add(4B LE×N)+del(4B LE×M) | 01 | true | ✓ 一致 (分批 20/20/20/4) |
| 0x0A | SYNCPWD | delAlias(2B LE)+pwd(8B ASCII 右补零)+vf(4B LE)+vt(4B LE) | 01 | true | ✓ 结构一致; **窗口值已修** (§2.1) |
| 0x0B | SYNCPWDEXPIRE | alias(2B LE)+vf+vt | 01 | true | ✓ 一致 (**值已修**) |
| 0x0C | SYNCPWDFREEZEPOLICY | — | — | — | ⚠ APK 无实现 (与 0x0C ECHO 撞号, 死枚举) |
| 0x0D | SETZOTPPERIOD | — | — | — | ⚠ APK 无实现 (与 0x0D ADDNEWFP 撞号, 死枚举) |
| 0x0E | SYNCTIME | `St`: 4B LE 协议秒 | 02 | true | ✓ 一致; **值已修** (§2.1); 另见 §2.4 (APK 进页自动校时) |
| 0x0F | DELETEFP | batchNumber(4B LE) | 02 | true | ✓ 一致 |
| 0x10 | GETLOG | orderType(1B)+startIdx(4B LE)+pageSize(1B) | 01 | true | ✓ 一致 |
| 0x12 | ECHO | val (KLV#01) | — | **false** | ✓ 一致 (KLV#01="123456") |
| 0x13 | ADDNEWFP | times(1B)+timeout(1B, ≤0→15) | 02 | true | ✓ 一致; 采集窗口已修 (§2.2) |
| 0x14 | ADDNEWFPCONFIRM | batch(4B LE)+vf+vt | 02 | true | ✓ 一致 (**值已修**) |
| 0x15 | DELETEFP(15) | batchNumber(4B LE) | 02 | true | ✓ 一致 |
| 0x16 | GETLOG(16) | 见 0x10 同布局 | 01 | true | ✓ 一致 |
| 0x17 | GetExSecurityKeyWay | 无 KLV/无体 | — | **false** | ✓ 一致 (本机 `cmd23ExKeyWay(wrap:false)`) |
| 0x18 | SetSoundVolumn | vol(1B) | 02 | true | ✓ 一致 |
| 0x19 | OPENZOTP | status(1B) | 02 | true | ✓ 一致 |
| 0x1A | SETVALIDATIONMODE | mode(1B) | 02 | true | ✓ 一致 |
| 0x1B | setBeacomKey | skeyLen(1B=0x10)+skey(16B) | 02 | true | ✓ 一致 (`cmd21SetBkey`) |
| 0x1C | enableDFUstate | module(1B) | 02 | true | ✓ 一致 |
| 0x1D | setMotoAutoLockInterval | interval(1B) | 01 | true | ✓ 一致 |
| 0x1E | setDefence | **control(1B)+start(4B LE)+end(4B LE)** | 01 | true | ✓ 一致 (本机早已是 3 字段) |
| 0x1F | GWGetDeviceName | 无 KLV/无体 | — | **false** | ✓ 一致 |
| 0x20 | GWSetWifi | #01 ssid(utf8) #02 pwd(utf8) #03/#04/#05 (1B each) | KLV 明文 | **false** | ✓ 一致 |
| 0x21 | GWSetIot | #05 iotpKey #06 iotdSec #07 devAccToken | KLV 明文 | **false** | ✓ 一致 (不调用, 云端停服) |
| 0x23 | GWReboot | 无 KLV | — | **false** | ✓ 一致 |
| 0x26 | GWGetStatus | 无 KLV | — | **false** | ✓ 一致 |
| 0x29 | Key_Chain_WriteEKey | #01 mac(6B 反转) #02 keyType(1B) #03 pid(2B LE) #04 ekey | KLV 明文 | **false** | ✓ 一致 |
| 0x2B | Key_Chain_GetStatus | #01 逐项 1B | KLV 明文 | **false** | ✓ 一致 (本机传空列表=查全部) |
| 0x2C | Key_Chain_GetEKeyInfo | #01 mac(6B 反转) 或空 | KLV 明文 | **false** | ✓ 一致 |

> 命名注: cmd 号以 **`Jn` 枚举** 为准 (`ZKCCOMM_ADDNEWFP="0D"` 即 13)。`ot` 枚举里 0x0C/0x0D 的
> `SyncPwdFreezePolicy`/`SetZotpPeriod` 与 ECHO/ADDNEWFP 撞号且**没有实现类** ⇒ 死枚举, 不予实现。

## 1. 传输层逐行对照 (Java ↔ Swift)

| 项 | APK (Java) | 本机 | 判定 |
|---|---|---|---|
| 帧骨架 | `87 00 len(LE 2B) cmd 00 00 00` + KLV | `buildFrame(header:8)` 同 | ✓ |
| KLV 编码 | `key(1B)+len(1B)+val`, len≤255 | 同 | ✓ |
| 令牌 KLV | **0xEE**, `getBytes(token)` 里 **追加在 KLV 列表末尾** | `injectToken` 同 (0xEE 追加尾部) | ✓ |
| 令牌刷新 | 每条 `needSessionToken` 命令前**同步**取一次 01 (8s 超时) | `ensureToken()` 同 | ✓ |
| 分片 | **20B/片**, 每片 `writeCharacteristic` 后等 `onCharacteristicWrite` | 20B/片 + `.withResponse` + 等 `didWriteValueFor` | ✓ (超时已改为 8s, §2.3) |
| 分片间隔 | **无 sleep** (ack 即流控) | 原多 30ms/片 → 已删 | ✓ 已修 |
| 响应等待 | 8s (`BLE_TIMEOUT`) | 8s | ✓ |
| 重试 | 连接 3 次; 命令层重试在 JS (3 次) | 连接重试 + `request(retries:3)` | ✓ |
| 未请求帧 | 无命令在飞时直接回调客户端 (指纹按压/令牌) | `handle()` → collector/订阅者 | ✓ |
| 命令串行 | 每连接一个单线程 executor | 单 `waiter` + "已有命令在等待响应" 闸 | ✓ |
| 通知 | TX(6e400003) + CCCD 2902 描述符 | 同 UUID + `setNotifyValue` | ✓ |
| 解析 | 累积队列, 头字节非 0x87 抛 `LockFormatException`; len+8 才成帧 | `ZKProtocol.parseResponse` (8B 优先 → 7B/10B 兼容) | ✓ (本机更宽容, 不放松任何校验) |
| 连接 | 扫描 8s/次, 失败重试 3; 断链清缓冲 | `scanForMAC` + 重连自愈 | ✓ |
| 响应对象 | `LockCommResponseMapper`: 仅 cmd 1 特化, 其余 → 通用 KLV 列表 | 同 (KLV 列表模型) | ✓ |

## 2. 本次修复 (9 项, 全部有可复算证据)

### 2.1 协议时间基准 = **本地** 2010-01-01 (差 28800s 的系统性偏差)

- APK: `En.getProtocolTimeSecond(x) = An.getDate(x) − An.getDate('2010-01-01 00:00:00')`,
  而 `An.getDate` 是 `new Date(y,m-1,d,h,mi,s)` ⇒ **被减数与减数都在本地墙钟**上, 时区自己消掉。
  东八区里同一时刻的协议秒 = (UTC 基准) **+28800**。
- 本机 (修前): `epochMs = 1_262_304_000_000` (2010-01-01T00:00:00**Z**) ⇒ 0E/05/0A/0B/14 全部少 28800s。
- 影响面 (全部已改): `ZKProtocol.epochMs` (Swift) / `utils/time.js EPOCH_MS` + `kernel/protocol.js EPOCH`
  (vendor 与小程序两份) / `buildEkey` 默认 VT 字面量改本地串 / `protoSecondsToDateStr` 改本地渲染。
- 证据 (解密 0A 帧逐字段): 修前 body_vf `4294938496`(2146) → 修后 **0**; body_vt 修前 3408105600 →
  修后 **3408134400** = APK `getProtocolTimeSecond('2118-01-01 00:00:00')` 逐字节相同;
  包络 vf/vt 与 APK `kt` 默认值一致 (本地两端相减 ⇒ 与机器时区无关, 恒 4670438400)。
- 配套: `fixtures/golden.json` 重生成 (12 处), `tools/golden.js` 本就钉死 `TZ=Asia/Shanghai`。

### 2.2 13 录指纹采集窗口 = 每帧后 8s 空闲 (Java 接收计时器)

- APK: `post()` 发帧后起**一个** 8s 计时器 (`BLE_TIMEOUT`), 收到第一帧即 `cancelReceiveTimer()`;
  之后由锁自己按 13 帧里的 `timeout=15s` 决定还接不接受下一次按压。
- 本机 (修前): 单个 30s 整体窗口。修后: **首帧 8s**, 已收按压后 **16s/次** (锁端 15s + 1s 余量),
  总兜底 150s; Swift 与两份 JS 同一口径; 上一次会话已修的"首帧应答不提前收尾"保留。

### 2.3 每片写确认超时 3s → 8s; 去掉分片间 30ms sleep (BLEService)

- APK 同一处 = `BLE_TIMEOUT` (8000ms) 且**无**固定间隔。修后与之一致 (ack 即流控)。

### 2.4 设备信息页进页自动校时 (APK `RominfoPage.ionViewDidLoad → syncTime()`)

- 本机此前只有手动入口; 现进 `DeviceInfoView` 读状态后, 偏差 >2s 即自动 0E 校时并回读验证
  (APK 无条件写; 我们只在真漂移时写, 终态一致)。

### 2.5 永久窗口下界 (0A/0B/14 与 41) 不再回绕

- 上一批已修 (`protoSecU32` / `protoSec` 以 0 为下界); 本次随 2.1 复核: 本地基准下
  `'2010-01-01 00:00:00'` **自然等于 0**, 护栏仍保留。

### 2.6 指纹"只有应答帧"不再当一次按压

- 上一批已修 (JS `fpStart` 增加 `some(orderIdx>0)` 判据 + 新回归套件 `tests/fpflow.test.js`)。

### 2.7 小程序整帧 3s 写超时 → 逐片 8s (逻辑面差分新抓到的同族缺陷)

- 上一批只修了 iOS (`BLEService` 3s/片 → 8s/片, §2.3), **小程序 `services/ble.js` 的孪生缺陷没动**:
  `writeFrame` 是"整帧 3s 总超时"(`Date.now() - t0 > 3000`)。08 PIN 池是 13 分片的长帧,
  弱信号下每片 100ms+ 就会在 3s 内被判"写入超时 6001", 而 APK 同一处是**每片重新计时 8s**。
- 修法: 计时器改为 `chunkAt`, 每发一片重置, 窗口 8000ms; 分片间 30ms 节流保留 (wx 栈节流, 非确认超时, 见 D4)。
- 证据: `node tools/logicparity.js` 的 `L02-chunk-ack-8s` 在修前红 (impl 未命中), 修后绿;
  反向围栏禁止 `> 3000` 回来。

### 2.8 金标生成器把 UTC 解析与本地基准混用 (夹具多出一个时区偏移)

- 起因: 新增逻辑面闸门时顺手跑全量闸门, `cmdsshadow` 25/32、`parseshadow` 32/35 **本来就是红的**
  (上一批只跑了 `golden --check` 与小程序单测, 没跑这两支)。
- 根因两处, 同源: 2.1 那一批把"协议时间基准"从 UTC 改成**本地** 2010-01-01, 但
  ① `tools/golden.js` 里 `buildEkeyOpen` 的 2118 窗口仍用 `Date.parse('2118-01-01T00:00:00Z')`
  (**UTC 解析 + 本地基准** ⇒ 凭空多一个偏移, 东八区 +28800s);
  ② `tools/cmdsshadow.js` / `tools/parseshadow.js` 的 `EP_MS` 还是旧的 UTC 常量。
- 修法: 三处都用本地解析/本地常量 (`new Date(2010,0,1,…).getTime()`); `fixtures/golden.json` 重生成。
  变更面: `cmds.buildEkeyOpen` / `cmds.cmd41WriteEkey` 两个向量 + `time.epochMs` + `time.protoFromMs_zero`。
- 结果: `golden --check` 绿; `cmdsshadow` 25/32 → **32/32**; `parseshadow` 32/35 → **35/35**。
  这个才是本轮最有价值的发现: 夹具本身差一个时区, 而两道差分闸门因此一直红着没人看。

### 2.9 逻辑面机检入场 (新闸门, 非修复但改变结论面)

- `tools/logicparity.js` + `fixtures/logic-parity.json` 已接 CI (见 §3.1): 17 条时序不变量 + 4 条已裁定分歧 + 3 条反向围栏。
- 首次运行就抓到 2.7 (小程序写确认窗口) —— 这正是上一批只靠"字节面"核对看不见的一类。

## 3. 逻辑面逐条核对 (调用点/条件/时序)

| 流程 | APK 事实 | 本机 |
|---|---|---|
| 配网 | 23(免令牌) → 01 → 05(带令牌) → 01 → 08×4(20/20/20/4, 首批 del=[FFFFFFFF]) → 21 → 回读 03 | ✓ 同 |
| 指纹 | 13(keep=true) → 应答帧(orderIdx 缺/0) → 每次按压 orderIdx 1..8(带 feature/batch) → 收满 8 → 14(批号+窗口) | ✓ 同 (2026-10-17 两处修复后) |
| 密码 | 0A(delAlias=0 加 / =alias 改 / =0xFFFF 清) → 响应 KLV#04=alias(LE 2B) → 0B(同 alias 设窗口) | ✓ 同 |
| 开锁 | ekey=Base64 解出 → `ae(ekey,"0000")` ⇒ #01="0000"左补零32, #02=ekey; `keep=false`; 响应 `pe` 读 rc + 剩余次数 | ✓ 同 |
| 校时 | 进设备信息页自动 0E; 云侧 `syncTime` 距今 ≥30 天 → 顶栏提醒 | ✓ 0E 已加 (§2.4); 提醒走本机 `DB.syncTime` |
| 布防 25 | control: 0=关 / 1=不定期 / 2=时间段(带 start/end 日内秒) / 3=readonly | ✓ 同 |
| 音量 18 | 0=有声 1=静音 | ✓ 同 |
| 安全模式 20 | securityLevel bit0 = A/B 验证 | ✓ 同 (仅 A→B 变严) |
| 钥匙串 41/43/44 | 免令牌; 41 KLV#04=ekey(AES(skey)($t cmd=04)), 空 ekey=删除; 44 传 mac=查单锁/空=查全部 | ✓ 同 |
| 网关 30/31/32/35/38 | 免令牌; FE90 服务 FE91 收/FE92 发; 31 authMode=8/encrypt=0 | ✓ 同 (构建器齐备, UI 只暴露在用入口) |
| 重发保护 | 写类命令超时/写失败**不重发** (可能已生效) | ✓ 同 (macBearingCmds + writeCmdsBlocked) |
| 只读试验模式 | JS `assertReadOnly` | ✓ 同 |

### 3.1 逻辑面机检 (不再是散文, 可跑)

`tools/logicparity.js` + `fixtures/logic-parity.json` (CI 判失败)。为什么另起一支: `golden.js` 管"发出去的字节",
`cmdsshadow/parseshadow` 管"同一输入两边同结果" —— 全是**数据面**; 而"**该等多久、该不该重发、该不该刷令牌、
多帧什么时候收尾**"没有任何机器证据。规则表每条都带 APK 证据 (`file` + 正则), **引用腐烂也判失败**。

| 规则 | 面 | 内容 | 本机证据 |
|---|---|---|---|
| `L01-chunk-20` | 一致 | 20B 分片上限 | BLEService.swift:294 |
| `L02-chunk-ack-8s` | 一致 | 写确认按片计时 8s (不是整帧 3s) | BLEService.swift:370 |
| `L03-rx-timeout-8s` | 一致 | 响应超时 8s | LockService.swift:196 |
| `L04-retries-3` | 一致 | 命令重试 3 次 | LockService.swift:301 |
| `L05-single-waiter` | 一致 | 单 waiter 串行: 有命令在飞时拒绝第二条 | LockService.swift:222 |
| `L06-writefail-clears-waiter` | 一致 | 写失败即刻清自己那格 waiter (按 cmd 匹配) | LockService.swift:240 |
| `L07-link-heal` | 一致 | 断链识别 → 丢旧连接 → 自愈重连 | LockService.swift:269 |
| `L08-token-every-needing-cmd` | 一致 | 每条 needToken 命令**无条件**先取一次 01 | LockService.swift:204 |
| `L09-token-ttl-margin-2s` | 一致 | TTL 剩 2s 视为过期 (Java `isExpire`) | LockService.swift:189 |
| `L10-rc3-refresh-once` | 一致 | rc=3 → 刷令牌重试一次, 不无限重试 | LockService.swift:306 |
| `L11-rc-klv-map` | 一致 | rc 所在 KLV 键逐键相同 (08=#03, 05=#01 …) | LockService.swift:290 |
| `L12-fp-window` | 一致 | 13 采集: 首帧 8s / 按压间 16s / 整体 150s | LockService.swift:610 |
| `L13-open-retries-2` | 一致 | 开锁只重试 2 次 (防电机连触发) | LockService.swift:459 |
| `L14-error-codes` | 一致 | 1006/1007/2003/6001/6005 同号 | BLEService.swift:40 |
| `L15-scan-timeout-8s` | 一致 | 扫描找锁 8s | LockService.swift:94 |
| `L16-token-not-truncated` | 一致 | 令牌整串透传 (不截 2B) | LockService.swift:185 |
| `L17-serial-exec` | 一致 | 命令串行 (单线程/单 waiter) | LockService.swift:6 |
| `D1-rc-minus1-failclosed` | **有意分歧** | 缺 rc KLV: APK 视为成功; 本机写命令面 fail-closed | LockService.swift:345 |
| `D2-write-cmd-no-resend` | **有意分歧** | 写类命令超时/写失败不重发 (APK 只降 retries) | LockService.swift:257 |
| `D3-connect-timeout` | **有意分歧** | 建链 20s 单次 (CoreBluetooth) vs Java scan+connect 8s×3 | BLEService.swift:216 |
| `D4-mini-chunk-pacing` | **有意分歧** | 小程序分片间 30ms 节流 (wx 栈; 非确认超时) | miniprogram services/ble.js:287 |

三条反向围栏 (出现即红): 写路径禁 `Thread.sleep/usleep`; 禁 `tokenExpiryMs > Date` 式 TTL 跳过令牌; 小程序禁整帧 3s 写超时。

**这条闸门的边界**: 正则是"逻辑还在、数字没被改小"的回归护栏, 不是语义证明 —— 它抓不到"条件写反了"这类错误
(Swift 无本地编译器, 语义只能靠 golden/cmdsshadow/parseshadow + 小程序单测 + 真机)。

## 4. 仍未覆盖 / 存疑 (如实列出)

1. **APK 内部两套 0E**: `RominfoPage` 发的是**明文包络**, `SynctimePage` 发的是 **AES 密文** (我们用后者)。
   APK 自身不一致, 本机取"生产加密版" — 如需实测明文版可加开关。
2. **0x02 GETBLEMAC / 0x0C / 0x0D**: APK 的 JS 里没有实现类 (死枚举), 本机同样不实现。
3. **cmd 04 的凭证语义**: APK 用 `deviceData.ekey` (云端下发/本地生成), 本机离线自签发 (`$t` 包络+AES(skey)),
   字节布局已逐字一致, 但**锁端是否接受离线自签发的 ekey** 属真机裁决项 (既有 U3 开放点)。
4. **Xcode 编译 / 真机行为**: 本机无 Swift 工具链、无锁 ⇒ 本次只做静态与字节级验证 (见 §5)。
5. **CI TZ**: `tools/golden.js` 自带钉死; CI 的 Swift↔JS 影子差分在同机同 TZ 下运行, 不受影响。

## 5. 本地验证 (真命令 + 真退出码)

- iOS 侧 **全部 32 道** `tools/*.js` 逐支跑过, 退出码均 0 (含新入场的 `logicparity`; 另跑
  `iconmap --strict` 与 `sheetcover --selftest` 也 0)。此前红着的 `cmdsshadow` / `parseshadow` 已修根因 (§2.8)。
- 字节/解析/逻辑三面各自的证据链: `golden --check` (夹具↔JS 核心) → `cmdsshadow` 32/32 (Swift 帧构造↔夹具)
  → `parseshadow` 35/35 (回包解析) → `logicparity` 17+4+3 (时序/重试/令牌/窗口)。
- 小程序 `node tests/run.js` 全部通过 (含新增 `fpflow.test.js` 与改写后的 `utils.test.js` 时间口径断言)。
- 金标: `node tools/golden.js` 重生成 → `--check` 绿; 夹具按 `Asia/Shanghai` 烘焙 (与工具钉死一致)。
