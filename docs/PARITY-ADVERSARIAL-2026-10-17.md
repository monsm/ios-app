# 对抗式逐行对拍: 本机 ↔ 原版 APK (2026-10-17 第三轮)

范围: 只看**锁数据交互与功能链路**, 小程序不作为参照。基准 = `apk_raw/assets/www/build/main.js`(反编译 JS 业务层)
+ `vendor/apk/BleLockConnector.java`(原生 BLE 层) + `vendor/app/**`(APK JS 层的可读移植)。
本机 = `App/**`。方法: 逐文件逐行读, 不以既有审计文档的结论为依据 (上一轮 `PARITY-FULL-AUDIT.md` 只覆盖
"字节/解析/时序", 本轮补**调用链、状态机、能力面**)。

## 0. 结论摘要

| # | 问题 | 影响的功能 | 状态 |
|---|---|---|---|
| 1 | 临时码页把周期写死 30 分钟, 不读锁端 `zotpPeriod` | 临时码 (页面生成) | **已修** |
| 2 | 网关记录从不落 `pid`, 且配网只认 12193 | 网关 (重启 App 后全部操作) | **已修** |
| 3 | 包络默认 VT 多一个时区偏移 (+28800) | 08/0A/0B/0E/13/14/15/16/18/19/20/21/24/25 的包络字节 | **已修** |
| 4 | DFU 数据点固定 `withResponse` 写, 不读特征属性 | 固件升级 (若 packet 只支持无响应写) | 待裁定 |
| 5 | 钥匙串 41/43/44 的 MAC 会随"锁的字节序裁定"翻转 | 蓝牙钥匙串写钥/查钥 | 待裁定 |
| 6 | 网关回连扫描不按 MAC 过滤 | 网关 (多台同型号时会连错设备) | 待修 |

## 1. 临时码周期写死 30 (已修)

- APK: `to.generateZOTPPwd` 的周期来自锁端 `zotpPeriod` (03 状态 KLV#05, 单位**分钟**); `zotp.js:24`
  只在调用方没给值时才 `|| 30`。
- 本机修前: `App/UI/CredentialsView.swift:2132` `ZOTP.generate(..., periodSec: 30, ...)` —— **写死**。
  而同一仓的 `App/Intents/AppIntents.swift:177` 是读 `DB.readStatus(kc.mac)?.zotpPeriod` 的。
- 后果: 锁端窗口不是 30 分钟时, 页面算出的 `u = now/(60*30)` 与锁端时窗错位 ⇒ **页面给的六位码开不了门,
  而 Siri 给的同一条能开**。这类"一半能用一半不能用"最难自查。
- 修法: 页面改读快照, 缺省才回落 30 (`CredentialsView.swift` genOtp)。
- 遗留: 同页"于 HH:MM 失效"文案走 `ZOTP.nextWindow()`, 该函数按 30 分钟半点计算 —— period≠30 时
  **文案时刻会错**, 码本身已正确。属显示项, 未动 (改它要先把窗口语义参数化)。

## 2. 网关 pid 从不落库 + 只认一个型号 (已修)

- APK: `gateway.js` 扫描用 `GW_PIDS = [12193, 12209, 12194]` 全族匹配, 且按 `macFilter` 过滤。
- 本机修前:
  - `HardwareService.provisionGateway` 建记录时只写 `bleId/boundAt`, **`rec.pid` 从未赋值**
    (`Gateway.pid` 默认 0, Store.swift:274);
  - `pidFor(mac)` 直接返回 `g.pid` (=0) ⇒ `scanForPID(pid: 0)` 永远匹配不到任何广播;
  - 配网入口写死 `PidMap.GW` (12193) ⇒ 商用网关 12209/12194 搜不到。
- 后果: 网关**当次**能配完 (deviceId 还在手上), 但**重启 App / 缓存 deviceId 失效后**, 刷新状态、重启、
  重新配网全部 20 秒超时 —— 表现就是"网关功能不能用"。
- 修法: 新增 `scanForPIDs(pids:)` 按族扫描, `provisionGateway` 从广播回填 `rec.pid`,
  `pidFor` 对老记录 (`pid<=0`) 回落 `PidMap.GW`。

## 3. 包络默认 VT 的时区偏移 (已修, 字节面)

- `ZKProtocol.validTo2118` 旧值 = `protoSecondsFromMs(4_670_438_400_000)`。
  4_670_438_400 是 **2118-01-01T00:00:00Z** 的 Unix 秒; 减"本地 2010"基准 ⇒ 东八区得 **3_408_163_200**。
- JS `buildEkey` 默认 VT = `protoTime('2118-01-01T00:00:00')` = **3_408_134_400** (本地两端相减, 108 年整)。
- 差 28800s。对 2118 这个上界**无害**, 但包络字节与金标不一致。为什么闸门没红: `tools/cmdsshadow.js:67`
  用的是 JS 的本地解析值, 没有忠实复刻 Swift 这一行 —— 这是**假绿**, 已在注释里写明。
- 修法: 常量直接钉 3_408_134_400。

## 4. DFU 数据点写类型 (待裁定, 有崩溃风险)

- APK: `utils/dfu/nordic.js:81` 读 `packet.properties`, `:182` 数据点用 **noRsp=true** 流式写;
  `ble.js:229` 选特征时也按 `write || writeNoResponse`。
- 本机: `App/Services/DFUKit.swift:345-368` 的 `writeRaw` 对控制点与数据点**一律** `.withResponse`,
  全文件没有一处读 `characteristics.properties`。
- 后果: 若固件 DFU 的 packet 特征只声明 `writeWithoutResponse`, CoreBluetooth 对 `.withResponse` 写
  **抛 NSException** (不是可捕获的 error) ⇒ 第一片就中断/崩溃。若两种都支持则只是慢。
- 需要: 真机看 `8EC90002-…` 的 properties (或直接按属性选型)。这条不改代码是因为**猜错方向更贵**。

## 5. 钥匙串 41/43/44 的 MAC 字节序 (待裁定)

- JS: 41/43/44 一律 `reversePairs(mac)` (显示序 → 线上序)。
- 本机: `ZKCmdBuilder.cmd41/43/44` 走 `ZKProtocol.targetMac(...)`, 而该函数会按**这把锁**学到的
  `macOrder` 决定要不要先翻一次。若某把锁在配网时被裁定成 `.raw`, 钥匙串命令就会**翻两次** = 送反。
- 判据: 钥匙串 dongle (ZKBBV1) 与门锁是两种设备, 字节序不该共用一份裁定。建议 41/43/44 强制 `.display`。

## 6. 网关回连不按 MAC 过滤 (待修)

- APK: `gateway.js:115` 扫描同时比对 pid 与 `macFilter`。
- 本机: `scanForPIDs` 只比 pid。附近有两台同型号网关时可能连到别人的 ⇒ 31 把家里 SSID/口令发给陌生网关。
- 建议: `scanForPIDs` 增加 `macFilter` 参数, 网关/钥匙串回连时传台账 MAC。

## 7. 逐层核对结果 (无差异项, 逐条读过)

| 层 | 对照 | 结论 |
|---|---|---|
| 帧/KLV/包络 | `ZKProtocol.swift` ↔ `kernel/protocol.js` | 一致 (8B 头、KLV、0x88 包络、KLV#EE 令牌、三头型解析、粘包重组) |
| 32 条命令构造 | `ZKCmdBuilder.swift` ↔ `kernel/cmds.js` | 逐字段一致 (端序/补零/MAC 反转/KLV 键); 例外见 §5 |
| 状态与日志解析 | `StatusParser.swift` ↔ `utils/status.js` + `labels.js` | 23 键 + 27 条 rc + 23 种日志类型逐条一致 |
| 加密 | `AESKit.swift` ↔ `utils/crypto.js` | AES-128-ECB + ZeroPadding 一致; 差异仅在错误路径 (JS throw / Swift 空串, 由 wrapFrame 拦) |
| 临时码算法 | `ZOTP.swift` ↔ `utils/zotp.js` | 逐字节一致 (u 8hex + MAC 反序 + idx 2B + 零填充, 每 4hex `(b1^b2)%10`) |
| 型号能力 | `PidMap.swift` ↔ `utils/pidmap.js` | pid 表与 `canDefend/canClearPwd/canTailgate` 表达式一致 |
| 密钥族生成 | `KeyGen.swift` ↔ `utils/keys.js` | skey/bkey 相邻字节约束/PIN 顶字节 &0x7F/去重预算/哨兵 ffffffff 一致 |
| BLE 传输 | `BLEService.swift` ↔ `services/ble.js` + `BleLockConnector.java` | 20B 分片、with-response 流控、8s 写确认、8s 响应超时、单 waiter 一致 |
| 命令执行 | `LockService.swift` ↔ `services/lock.js` | 令牌无条件刷新、rc=3 自愈、rc=12 换序自愈、写命令不重发、13 多帧采集一致 |
| 配网链 | 同上 | 23 → 01 → 05(带令牌) → 08×4(20/20/20/4, 首批 del=ffffffff) → 21 → 03 一致 |

## 8. 已知的"有意分歧" (不是缺陷, 但会改变行为)

- `execOk` 对 **rc=-1**(回包缺 rc KLV) 按 fail-closed 抛错; JS 视为成功 (G5)。若某固件对 21/24/25 这类
  命令不回 rc, 该功能在本机会报"无法确认锁端结果"。目前没有真机证据, 保留。
- 写类命令超时/写失败**不重发** (防电机连触发), JS 只是降 retries。
- 建链 20s 单次 (CoreBluetooth), Java 是 8s×3。

## 9. 验证

- `node tools/swiftcheck.js` / `swiftlint.js` / `swiftshape.js` / `swiftsyn.js` 全 EXIT=0
- `node tools/golden.js --check` 通过; `cmdsshadow.js` 32/32
- 三处改动后需真机复验: ① 临时码 (锁端 period≠30 的锁) ② 网关重启 App 后刷新/重启 ③ 08/0A/14 包络 VT
