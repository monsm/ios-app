# PROGRESS · Door 子页域（task-5）

写作用域：`ios27/App/Features/Door/`（只新增文件，`DoorScreen.swift` 未改动）

## 文件清单

| 文件 | 行数 | 一句话 |
|---|---|---|
| `LockStatusScreen.swift` | ~305 | 把 cmd03 的读数摊成 2×2 仪器网格，安全模式 / 静音两枚开关即点即写，改动记「待下发」并可重试。 |
| `AddLockScreen.swift` | ~530 | 发现 → 校验 → 初始化 → 命名四步真序列，7 条写锁帧逐条留痕，可中止回滚并常驻原因。 |
| `GatewayScreen.swift` | ~450 | 网关五步配网（连 → 读名 → 写 WiFi → 写 IoT → 重启），配完只剩只读状态；5GHz 网段在写硬件前拦下。 |
| `SyncTimeScreen.swift` | ~255 | 锁内时间 / 手机时间 / 偏差三读数，偏差 > 2 秒才值得写；cmd0E 后回读复核，不归零就报失败。 |
| `DefendScreen.swift` | ~445 | cmd25 三档（撤防 / 不定期 / 每日时段）+ 15 分钟步进器，跨午夜与 start==end 都有明确裁决。 |

## 未接真数据（全部标了 `TODO(engine)`）

| 文件 | 字段 / 链路 |
|---|---|
| LockStatusScreen | cmd20 SETVALIDATIONMODE 回写；cmd18（vol 1B）静音回写；待下发队列的逐项补发 |
| AddLockScreen | `BLEService.startScan(allowDuplicates:timeoutMs:10000)` + 评分排序；cmd12 回声探测；cmd23 → cmd05 → cmd08×4 → cmd21 → cmd03 帧序列；回滚时的断链与半成品清理；op=addLock 落库 + Keychain/锁档案写入 |
| GatewayScreen | cmd30 读设备名 → op=checkDeviceBinding → cmd38 → cmd31 写 WiFi → op=addGateway → cmd32 写 IoT → cmd35 重启 → 落库；op=getDeviceStatus 刷新 |
| SyncTimeScreen | ensureConnected → cmd03 取 lockTime；cmd0E 下发与回读复核 |
| DefendScreen | op=getDeviceSetting（defenceControl / defenceStartTime / defenceEndTime）；cmd25 下发（半秒刻度）与三键回写 |

> 说明：以上位置的相位机 / 样本值只驱动界面状态，**不伪造锁端回执**；UI 文案也据此写成「命令已下发（锁端是否生效以现场为准）」。

## 自查

`node Gates/swiftcheck.js` / `tokens.js` / `contrast.js` 全绿。
Door 目录内：0 处 `Color(hex:`、0 处 `.padding(数字)`、0 处 `Text` 上直接 `.system(size: 数字)`、0 处 `.bold()`、0 处 `glassEffect`。
