# PROGRESS · Keys 域（凭证 Tab）

## 页面清单（9 个文件 / 6 个屏幕类型）

| 文件 | 行数 | 是什么 |
|---|---|---|
| `Features/Keys/KeysScreen.swift` | 238 | **KeysScreen** —— Tab 2 根。凭证台账（状态点 + 名称 + 类型/归属/打码 + 剩余天数读数）+ 5 枚类型分段 + 唯一主动作「新增凭证」+ 3 条次级入口（月历/手机钥匙/分享给安卓）。 |
| `Features/Keys/KeyDetailScreen.swift` | 307 | **KeyDetailScreen** —— 单枚凭证档案。逐位打码可点开、4 位分段复制、读数区、改到期日（5 档真写台账）、停用/恢复、改造密码值、彻底删除（危险动作走 State.critical）。含「凭证已不在」空态。 |
| `Features/Keys/KeyCreateScreen.swift` | 226 | **KeyCreateScreen** —— 四步工坊主文件（导航 + 步间硬拦 + 提交）。 |
| `Features/Keys/KeyCreateParts.swift` | 297 | 上者的四步视图（类型归属 / 码值 / 有效期 / 确认二次输入）。 |
| `Features/Keys/KeyCalendarScreen.swift` | 234 | **KeyCalendarScreen** —— 到期月历。每月格子只有到期条数，点某天出当天清单 → 详情。 |
| `Features/Keys/MobileKeyScreen.swift` | 234 | **MobileKeyScreen** —— 手机钥匙签发/撤销。签发只写本机台账，交付靠行内「⋯」复制。 |
| `Features/Keys/ShareToAndroidScreen.swift` | 238 | **ShareToAndroidScreen** —— 配对二维码（CoreImage，无三方依赖）。有可交付钥匙才出码；没有就指路去签一把。 |
| `Features/Keys/KeysParts.swift` | 166 | 域内共享：`KeysFilter` / `KeysState`（到期推断）/ `KeysRoute` / `KeysRow` / `KeysDivider`。 |
| `Features/Keys/KeysBits.swift` | 297 | 域内控件：`KeysMaskedCode` / `KeysOwnerRow` / `KeysChips` / `KeysShortcutRow` / `KeysActionRow` / `KeysStepDots` / `KeysInlineNote` / `KeysCode`。 |

## 闸门

`node Gates/allgates.js`：Keys 域 **0 处** `Color(hex:` / `.padding(数字)` / `Text` 上直接 `.system(size:` / `.bold()` / `glassEffect`。
（当次全量跑出唯一一条失败在 `Features/Settings/SettingsParts.swift:166`，属 Settings 域，未越界修改。）

## 未接真数据的部分（`TODO(engine)` 清单）

| 位置 | 缺什么 |
|---|---|
| KeyDetail `setExpiry` | 改期要重发 **0B**（写新起止时间到锁）。现在只写本机台账。 |
| KeyDetail `toggleDisabled` | 停用 = 本地移除 + 回收站 + 排锁端删除。现在只翻本机 `disabled`。 |
| KeyDetail `deleteKey` | 彻底删除要先下发锁端删除命令，成功才摘台账。现在只摘本机。 |
| KeyDetail 读数区 | 用量 / 近 30 天开门次数要读 **cmd16** 日志与锁内计数 —— 页面上如实写了「还没有这条链路」。 |
| KeyCreate `submit` | 密码下发 **cmd0A/0B**；指纹录入 **cmd13 启动 / cmd14 确认**（含 batchNumber 校验）。现在只写本机台账。 |
| MobileKey `issue` | `getAvailablePin` → `ekey = AES(skey)(0x04 包络 + PIN LE4 + 00 00)` → `op=updateShareDevice action=add`。现在本机生成占位凭证串。 |
| MobileKey `revoke` | 撤销要同时 `cmd08 delPins` 把 pin 从锁里删；只删本地记录的话旧 pin 仍能开门。 |
| MobileKey 页头 | 真实 PIN 池占用要读锁 `deviceData.pins` 并按 ekey=1 的成员去重 —— 页头因此只说「本机签了几把」。 |
| ShareToAndroid `build` | 真实信封是 `CredPackage{v,mac,lockName,pwds,fps,at}` 经 AES 口令加密后的密文。现在拼的是**明文配对串**，页面上如实标注「还没加密」。 |
| ShareToAndroid 就绪度 | `KeysShareReadiness` 改为按本机是否有可交付的手机钥匙判定；真实现还要问 Engine 要 ekey/PIN。 |

## 设计自查

- 每屏一个主角：Keys = 台账 Panel；Detail = 码值 Panel；Create = 当前步骤 Panel；Calendar = 月历 Panel；MobileKey = 签发表单 Panel；Share = 二维码 Panel。
- 同屏只有一个 `PrimaryAction` / 一处 `Signal.base` 填充。
- 所有数字走 `Reading`（等宽右对齐 + 单位小字）；所有时刻走 `TimeFormat`（`clock` / `dayShort` / `dayKey` / `dayTitle`）。
- 空态都给出路：无锁 → 添加门锁；无凭证 → 新增凭证；分段空 → 说该去哪一步；月历空 → 发一张临时码；无成员 → 去新建成员；分享未就绪 → 去签手机钥匙；凭证已删 → 回列表。
- 中文标题全部 semibold（`T.F.display()`），无 `.bold()`。
