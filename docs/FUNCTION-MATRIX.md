# 功能全量核查矩阵 (2026-10-17 · 对抗式)

**基准**: `apk_raw/assets/www/build/main.js`(APK 反编译业务层, 逐字符抽取) + `vendor/apk/BleLockConnector.java`(原生层)。
**不采用** `vendor/app/**` 作为结论来源 —— 它本身是本仓的移植稿, 用它证明"一致"是循环论证; 只在
main.js 无法抽取 (如 JS 里没有的实现) 时才引它, 并单独标注。
**范围**: 本 App 能对**真实设备**发出的每一条命令 + 每条命令背后的时序/收尾判据。
纯本地功能(备份、成员、统计、徽章等)没有 APK 对应物, 列在 §4 说明其口径。

判定图例: ✅ 逐字段一致 · 🔧 本轮修 · ⚠️ 有差异待裁定 · ❌ 不可用

## 1. 命令面 (32 条, 从 main.js 抽 needToken 与 KLV 键, 逐条比对载荷)

| cmd | 名称 | APK needToken | APK 载荷 (main.js 原文) | 本机 | 判定 |
|---|---|---|---|---|---|
| 01 | 会话令牌 | false | 无 KLV | `cmd01Session` 空帧, needToken:false | ✅ |
| 03 | 状态(密) | **true** | `#01=EKey(03) #02=""` | `cmd03StatusWrap` 同 | ✅ |
| 04 | 开锁 | **true** | `#01=fillZero(t,32) #02=ekey`; `$t` 体 = pin+bind+times | `cmd04Open` + `buildEkeyOpen` 同 | ✅ |
| 05 | 换钥 | **true** | `#01=时间 #02=way #03=skey` | `cmd05Exchange` 同 | ✅ |
| 08 | PIN 池 | **true** | addCount+delCount+addPins+delPins | `cmd08SyncPinsBatch` 同, ≤20/批 | ✅ |
| 0A | 同步密码 | **true** | delAlias(2B)+pwdASCII(右补零16)+vf+vt | `cmd0ASyncPwd` 同 | ✅ |
| 0B | 改期 | **true** | alias(2B)+vf+vt | `cmd0BSyncPwdExpire` 同 | ✅ |
| 0C/0D | 冻结策略/OTP周期 | — | **APK 无构造类** (死枚举) | 不实现 | ✅ 对齐 |
| 0E | 校时 | **true** | `getProtocolTimeSecond(时间串)` 4B LE | `cmd0ESyncTime` 同 | ✅ |
| 12 | 回声 | **false** | `#01="123456"` | `cmd12Echo` 同 | ✅ |
| 13 | 录指纹 | **true** | times(1B)+timeout(1B); `keep=true` 多响应 | `cmd13AddFp` + collector | 🔧 见 §2.1 |
| 14 | 指纹确认 | **true** | batch(4B)+vf+vt | `cmd14FpConfirm` 同 | ✅ |
| 15 | 删指纹 | **true** | batch(4B) | `cmd15DeleteFp` 同 | ✅ |
| 16 | 日志 | **true** | orderType+startIdx(4B)+pageSize | `cmd16GetLog` 同 | ✅ |
| 18 | 音量 | **true** | 1B (0=有声/1=静音) | `cmd18Volume` 同 | ✅ |
| 19 | 临时码开关 | **true** | 1B | `cmd19OpenZotp` 同 | ✅ |
| 20 | 单双验 | **true** | 1B | `cmd20ValidationMode` 同 | ✅ |
| 21 | bkey | **true** | skeyLen(1B=10)+bkey(16B) | `cmd21SetBkey` 同 | ✅ |
| 22 | 进 DFU | **true** | 1B module | `cmd22EnableDfu` 同 | ✅ |
| 23 | 交换方式 | **false** | 无 KLV | `cmd23ExKeyWay` 同 | ✅ |
| 24 | 自动上锁 | **true** | 1B interval | `cmd24AutoLock` 同 | ✅ |
| 25 | 布防 | **true** | control+start(4B)+end(4B) | `cmd25Defence` 同 | ✅ |
| 30 | 网关名 | **false** | 无 KLV | `cmd30GWDeviceName` 同 | ✅ (无 UI 入口, 与 APK 同) |
| 31 | 网关配网 | **false** | #01 SSID #02 pwd #03 auth #04 enc #05 | `cmd31GWSetWifi` 同 (auth=8/enc=0/05=00) | ✅ |
| 32 | 网关 IoT | **false** | #05 #06 #07 | `cmd32GWSetIot` 同 (云停服, 不调用) | ✅ |
| 35 | 网关重启 | **false** | 无 KLV | `cmd35GWReboot` 同 | ✅ |
| 38 | 网关状态 | **false** | 无 KLV | `cmd38GWStatus` 同 | ✅ |
| 41 | 钥匙串写钥 | **false** | #01 MAC(6B反) #02 type #03 pid #04 ekey | `cmd41WriteEkey` 同 | ⚠️ 见 §3.2 |
| 43 | 钥匙串状态 | **false** | #01 多 MAC 拼接 | `cmd43KeychainStatus` 同 | ✅ |
| 44 | 钥匙串查钥 | **false** | #01 MAC(6B反) 或空 | `cmd44GetEkeyInfo` 同 | ⚠️ 见 §3.2 |
| 02 | BLE MAC | — | APK 全库零调用 | 不实现 | ✅ 对齐 |

## 2. 时序面 (逐条对 Java 原文, 不是对 JS 移植稿)

### 2.1 🔧 13 录指纹的采集窗口 (本轮修)

| 环节 | APK 事实 | 修前本机 | 现在 |
|---|---|---|---|
| 发帧后计时 | `post()` → `startReceiveTimer()` 起**一个** 8s 计时器 (:371/:692) | 8s 首帧窗口 | 同 |
| 收到第一帧 | `onCharacteristicChanged` 里 **cancelReceiveTimer()**, 且**不重启** (:196) | 无 | 同 |
| 之后 | **没有任何 App 计时器**; 8 次按压节拍由锁按 13 的 timeout=15s 裁定 | 自创「两次按压 16s 空闲即收尾」 | **已删** |
| 整体兜底 | 无 (会一直等) | 150s | 150s (保留, 只为防挂死) |
| 收尾判据 | 每帧回调一次; `orderIdx==0` → "启动成功"; 1..8 → 记 featureNumber; **8 帧后**用该帧 batchNumber 发 14 | 收过按压后的 0 / 满 8 次 | 同 |
| 字段解析 | `orderIdx`=#04 **大端** parseInt; `featureNumber`/`batchNumber`/`nextTimeout` = #05/#06/#07 **反转字节** | 四个都用 leHexToU32 | 1 字节字段下等价 (orderIdx 恒 1B) |

> 旧的自创窗口正是"按了 3 下就不动了"的来源: 用户看屏幕/换姿势超过 16s, 本机就提前收尾并抛
> "只收到 3/8 次按压", 而 APK 会继续等。

### 2.2 其余时序 (逐条对 Java, 均已一致)

| 环节 | APK | 本机 |
|---|---|---|
| 命令等待 | `send()` 写完后 `wait(BLE_TIMEOUT=8000)` | waiter 先挂后写, 8s 超时 |
| 令牌 | 每条 needToken 命令**无条件**先取 01 (不查 TTL) | `ensureToken()` 同 |
| 令牌 TTL 判定 | `isExpire`: now+2s > expire | 同 (仅用于 UI/自愈, 不跳过刷新) |
| 分片 | 20B/片, 每片等 `onCharacteristicWrite` (8s) | 20B/片, `.withResponse` 等 `didWriteValueFor` (8s) |
| 分片间隔 | **无** (ack 即流控) | 无 |
| 响应超时 | 8s | 8s |
| 命令串行 | 单线程 executor | 单 waiter, 忙即拒绝 |
| 写失败 | 清 waiter, 下轮重试 | 同 (写类命令另加"不重发") |
| 未请求帧 | 无 waiter 时直接回调 | collector → 订阅者 |
| 连接 | 扫 8s / 重试 3 | 扫 8s + 20s 连接超时 |

## 3. 流程面 (每条链的调用序列)

| 流程 | APK 序列 | 本机 | 判定 |
|---|---|---|---|
| 配网 | 23 → 01 → 05(带令牌) → 08×4(20/20/20/4, 首批 del=FFFFFFFF) → 21 → 03 | 同 (含断点续配) | ✅ |
| 开锁 | ekey → 04(#01="0000"左补零32, #02=ekey), retries=2 | 同 | ✅ |
| 加密码 | 0A(add) → 响应 #04=alias → 0B(设窗口) | 同 | ✅ |
| 改密码 | 0A(delAlias=原alias + 新密码) 单帧 | 同 | ✅ |
| 删/清密码 | 0A(delAlias=N) / 0A(delAlias=FFFF) | 同 | ✅ |
| 指纹 | 13(多帧) → 8 帧后 14(batch+窗口) | 同 (窗口已修) | 🔧 |
| 删指纹 | 15(batch) | 同 | ✅ |
| 读日志 | 16(orderType,startIdx,pageSize) → #04=剩余, #05=条目 | 同 | ✅ |
| 校时 | 读 03#04 → 0E(手机当前时间) | 同 (且回读校验) | ✅ |
| 布防 | 25(control,start,end) | 同 | ✅ |
| 音量/单双验/自动锁/临时码开关 | 18/20/24/19 各 1B | 同 | ✅ |
| 临时码生成 | 6 位 = AES(skey)(u+MAC反+idx+0) 前 24hex 每 4hex (b1^b2)%10; 周期取锁端 zotpPeriod | 算法同; **周期本轮改读快照** | 🔧 |
| 钥匙串 | 41 写/删 ekey, 43 状态, 44 查钥 | 同 | ⚠️ §3.2 |
| 网关 | 38 → 31(5 KLV) → 35; 扫描 GW 全族 | 同 (pid 落库/全族本轮修) | 🔧 |
| DFU | 22 → 扫 (pid+dfuState / MAC 或 +1) → Secure FE59 / Legacy 1530 → 上传 | 同 | ⚠️ §3.1 |

### 3.1 ⚠️ DFU 数据点写类型 (未改, 需真机)

APK `nordic.js:81,182` 读 `packet.properties`, 数据点用 **noRsp** 写; 本机 `DFUKit.writeRaw` 一律
`.withResponse`, 全文件不读 properties。若固件 packet 特征只声明 writeWithoutResponse,
CoreBluetooth 会**抛异常** (不可捕获) ⇒ 第一片即中断。

### 3.2 ⚠️ 钥匙串 41/43/44 的 MAC 字节序 (未改)

APK 三处都恒 `reversePairs(显示序)`; 本机走 `ZKProtocol.targetMac()`, 会随**这把锁**学到的
`macOrder` 再翻一次。若某锁被裁定成 `.raw`, 钥匙串命令就会翻两次 = 送反。

## 4. 纯本地功能 (无 APK 对应物, 不计入"一致性", 只列口径)

备份/恢复 · 成员与权限 · 告警中心 · 统计与年报表 · 徽章与里程碑 · 分享卡 · 诊断与体检 ·
搜索 · 快捷指令/Siri · 桌面小组件 · 回收站 · 台账导入导出 · 自动开锁 · 连接看护。
这些的"对不对"只能按本仓自己的规格 (docs/DESIGN-SPEC.md 等) 判, 不存在与 APK 对齐的问题;
其中涉及锁端读写的部分已收敛到上面 §1/§2/§3 的 32 条命令里。

## 5. 本轮改动汇总

1. `LockService.fpStart` 删除自创的按压间隔计时器 (只留首帧 8s + 150s 兜底)
2. `CredentialsView.genOtp` 周期改读锁端 `zotpPeriod`
3. `HardwareService` 网关落 pid + 按 GW 全族扫描
4. `ZKProtocol.validTo2118` 3_408_163_200 → 3_408_134_400
5. `fixtures/logic-parity.json` L12 改成拿 Java 原文当证据, 并加反向围栏禁 `perPressMs` 回潮

## 6. 仍需真机裁决的三项

1. DFU 数据点特征属性 (决定 §3.1 是否要改)
2. 钥匙串 dongle 的 MAC 字节序是否与门锁共用一份裁定 (§3.2)
3. `execOk` 对 rc=-1 fail-closed: 若某固件对 21/24/25 不回 rc, 本机会报"无法确认锁端结果"

## 7. 核查完成度自证 (逐层, 每层写清"怎么核的")

| 层 | 覆盖对象 | 核对方式 | 状态 |
|---|---|---|---|
| 命令构造 | 32 条 | 从 main.js 抽 `call(this,Jn.ZKCCOMM_*,needToken)` + 各载荷类 `getCmdBody` 原文, 与 `ZKCmdBuilder.swift` 逐字段比 | 完成 |
| 回包解析 | 9 个解析类 (pt/Jt/_e/Ki/ku/Su/Nu/io/Oo) + 03 状态 23 键 | 抽 `setKlvs` 里 `"xx"==klvs[i].key` 分支, 与 `StatusParser`/各调用点比 | 完成 |
| 时序 | 连接/分片/写确认/响应超时/令牌/重试/多帧 | 对 `BleLockConnector.java` 原文 (非 JS 移植稿) | 完成 |
| 流程 | 15 条链 | 对 main.js 页面调用序列 | 完成 |
| 加密/临时码/密钥族/型号 | AESKit/ZOTP/KeyGen/PidMap | 对 crypto.js/zotp.js/keys.js/pidmap.js 逐行 | 完成 |
| 钥匙串/网关/DFU | 41/43/44, 30/31/32/35/38, DFU 全链 | 对 keychain.js/gateway.js/dfu.js/nordic.js | 完成 (3 项待真机, 见 §6) |
| 纯本地功能 | 备份/成员/告警/统计/徽章/分享/Siri/小组件等 | 无 APK 对应物, 不参与"一致性"; 其锁端读写部分已并入上面 32 条 | 不适用 |

**尚未完成 / 无法在本地完成**:
1. DFU 数据点特征属性 (§3.1) —— 需真机读 `8EC90002` 的 properties
2. 钥匙串 dongle 的 MAC 字节序 (§3.2) —— 需真机
3. rc=-1 fail-closed 是否会误伤某固件 (§6.3) —— 需真机
4. 任何"真机行为"结论 —— 本机无 Swift 工具链、无锁, 只能靠云端编译 + 真机
