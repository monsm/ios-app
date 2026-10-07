# 平台与账号约束（免费开发者账号 / Personal Team）

> 依据：用户当前使用未付费（$99）的 Apple 开发者账号，分发方式为侧载（AltStore/Sideloadly/爱思）。
> 本文是功能 triage 的平台侧权威；协议侧权威见 docs/CAPABILITY.md。

## ✅ 免费账号可用（无需特殊 capability）
| 能力 | 说明 |
|---|---|
| App Intents / 快捷指令 | 无需付费能力；App 内动作可注册给快捷指令/动作按钮/轻点背面 |
| WidgetKit（哑组件） | Widget target 本身可建；**但见下方 App Groups 限制** |
| Control Center 控件（ControlWidget, iOS 18+） | 基于 App Intent，可用 |
| 本地通知 UNUserNotificationCenter | 免费；全部离线场景的提醒都走这里 |
| BLE 后台模式 / CoreBluetooth | capability 可用；后台重连/扫描受系统调度约束 |
| BGTaskScheduler | 可用（后台刷新/清理，7 天签名下照常） |
| FaceID / Keychain / Secure Enclave / Biometry | 可用 |
| Swift Charts / App IntentsShortcutsLink 等 UI | 可用 |

## ❌ 免费账号不可用
| 能力 | 对本 App 的影响 |
|---|---|
| APNs 远程推送 | 无影响（全离线设计，本来就没有推送） |
| **App Groups** | **Widget 无法读取 App 的 SQLite/设置** → Widget 只能做"拉起 App 的哑按钮"，不能显示锁状态/电量 |
| CloudKit / iCloud | 无影响（无云依赖；WebDAV 走用户自己的账号） |
| TestFlight / App Store 上架 | 分发只能侧载 |
| 自定义通知扩展等系统能力 | 无影响 |

## ⚠ 受限（可用但有代价，设计时必须接受）
| 项 | 约束 |
|---|---|
| **签名 7 天过期** | 所有侧载 App 7 天后失效，需重签（AltStore 可自动）。影响：不能依赖"长期后台驻留"的体验设计 |
| 免费槽位 | 每台设备同时可侧载的 App 数量有限（AltStore 免费档约 3 个）；本 App 占一个槽位 |
| NFC Tag Reading | CoreNFC capability 在个人团队下不可确定，落地前需实测；不可用则放弃 NFC 类创意 |
| Watch 配套 App | 可建 watchOS target（无审核），但增加每周重签负担；WatchConnectivity 本身可用 |
| 后台 BLE 时长 | iOS 后台 BLE 有系统级限制（连接保持可行，主动扫描受限）——所有"后台自动完成"类创意都要降级预期 |

## Triage 判定规则（与 CAPABILITY.md 配合使用）
- ❌ = 协议不存在该能力（CAPABILITY.md 第 5 节）或平台明确不可用（上表 ❌）
- ⚠ = 需新本地数据积累 / 系统能力不确定（NFC/Watch）/ 体验受平台限制（后台时长、7 天签名）
- ✅ = 纯本地 UI/逻辑，现有协议字段已支撑
