# 功能蜘蛛网 · 侦察兵共同约定（v1）

## 0. 铁律
1. **只信代码**。`README.md` / `docs/**` / `.github/**` / 任何 md 都**不是证据**，禁止引用、禁止据此下结论。它们只可能在找路时当索引，结论必须回到 `.swift` / `.kt` / `.java` / `.js` / `.xml` / `.gradle.kts` 源码。
2. 每条功能点必须有**可核对证据**：仓库相对路径 + 行号 + 符号名。行号必须是你亲自 `read` 到的（允许 ±3 行误差，但摘录要能对上）。
3. **不臆造**。代码里没有的不要写；不确定的写进 `unresolved`，不要写成功能点。
4. **不修改应用源码**，只写自己的 JSON 文件。
5. 用中文命名功能点；技术标识（命令号、KVC key、方法名）保留原文。
6. 深度要求：不是只列页面，而是列到**用户能做的动作、可调开关、状态/空态/错误态、自动化时序、后台行为、数据落盘键、协议命令**这一层。

## 1. 输出文件
每个侦察兵只写自己的文件：`D:\aapk\feature-web\inventory\<scout>.json`
UTF-8、无 BOM、合法 JSON、2 空格缩进。结构：

```json
{
  "scout": "ios-ui-cred",
  "platform": "ios",              // ios | android | apk
  "scope": ["App/UI/CredentialsView.swift", "..."],
  "nodes": [
    {
      "key": "credential.list",                  // 语义键：<domain>.<module>.<feature>，全小写 kebab
      "parentKey": "credential",                  // 语义父键；顶层模块填 domain
      "domain": "credential",                     // 12 域之一，见 §2
      "level": 3,                                 // 2=模块/屏 3=功能点 4=细节/状态/边界
      "name": "凭证总览",
      "kind": "screen",                           // screen|sheet|flow|action|setting|state|service|protocol|data|automation|diagnostic|edge
      "summary": "一句话：用户能做什么 / 系统做什么。",
      "details": ["细节 1", "细节 2"],             // level 4 必填；level 3 可选
      "evidence": [
        {"file": "App/UI/CredentialsView.swift", "line": 16, "symbol": "CredentialsView", "note": "可选摘录"}
      ],
      "tags": ["锁端读写", "核心"],
      "status": "implemented"                     // implemented|partial|edge|deprecated
    }
  ],
  "unresolved": ["读到了但定不了性的：文件:行 — 原因"],
  "notes": ["覆盖范围/刻意没展开的部分"]
}
```

- `key` 是**跨平台合并键**：同一能力在 iOS / Android / APK 上都用同一个 key（例如 `unlock.dial`、`credential.pwd.add`）。平台独有就自造，但必须带域前缀。
- `parentKey` 必须指向同一文件里出现过的节点，或 §2 的 domain 根。
- 同一 key 可在多个侦察兵文件出现（合并时证据会合并），不要为了避免重复而丢掉证据。
- 每个节点至少 1 条证据；模块/页面节点也要证据（struct/class 声明行）。
- 证据路径：iOS 用 `App/...`；Android 用 `android-app/app/src/main/...`；APK 用 `apk_raw/...` 或 `jzzns22561_out/...`（相对 `D:\aapk\`）。
- APK 的 `main.js` 是单行压缩文件：行号恒为 1，改用 `"note": "page-xxx @offset 123456"` 记录字符偏移（用 grep/Select-String 找到的 Index）。

## 2. 12 个域（domain）与建议 module
| domain key | 中文 | 典型 module |
|---|---|---|
| device | 设备与连接 | home / add / list / profile / info / link / autoopen / battery / synctime / gateway / keychain-hw / messages / quick |
| unlock | 开锁与鉴权 | dial / focus / gate / applock / guest / safemode / proximity / feedback / finder |
| credential | 凭证 | list / studio / pwd / fp / tempcode / otp / pinpool / keychain / queue / bin / history / calendar / organize / transfer / extend / disable / share / owner |
| member | 成员与家庭 | center / detail / add / edit / merge / borrow / archive / group / family / unclaimed / messages / permission |
| record | 记录与统计 | list / timeline / detail / search / filter / stats / alarm / active / outwin / export / share |
| security | 安全与防御 | center / defense / tailgate / audit / ledger / destroy / watermark / policy / applock |
| backup | 备份与迁移 | center / export / restore / webdav / migrate / local / canonical / cloud / android-share / zip |
| care | 关怀与维护 | battery / schedule / maintenance / milestone / mascot / hints / changelog / moments |
| diagnostic | 诊断与工具 | center / reference / health / data-health / recovery / crash / trace / telemetry / scan / cache / prewarm / reconcile / qr / dict / hex / fields / selfcheck / logs / startup / firmware |
| settings | 设置与偏好 | home / groups / appearance / a11y / unlock-prefs / link-prefs / notify / lab / about / deeplink / speech / haptics / language |
| protocol | 协议与命令 | frame / klv / token / aes / otp / keygen / pidmap / status / log / keychain / gateway / dfu / cmd01..cmd44 |
| data | 数据与存储 | store / schema / ledger / snapshot / logs-cache / member / dongle / gateway / audit / secret / time / variant / design / search-index |

## 3. 跨平台共用 key 速查（能对上就用，别另造）
- 设备：`device.home` `device.add` `device.list` `device.detail` `device.info` `device.rename` `device.reset` `device.manage` `device.synctime` `device.gateway.status` `device.gateway.wifi` `device.gateway.reboot` `device.gateway.name` `device.keychain.write` `device.keychain.status` `device.keychain.query`
- 开锁：`unlock.dial` `unlock.bind.qr` `unlock.proximity` `unlock.autoopen` `unlock.finder` `unlock.applock` `unlock.guest` `unlock.safemode` `unlock.gate` `unlock.feedback`
- 凭证：`credential.list` `credential.pwd.add` `credential.pwd.edit` `credential.pwd.delete` `credential.pwd.clear` `credential.pwd.extend` `credential.pwd.disable` `credential.fp.add` `credential.fp.delete` `credential.fp.rename` `credential.tempcode` `credential.otp` `credential.pinpool` `credential.queue` `credential.bin` `credential.history` `credential.calendar` `credential.organize` `credential.transfer` `credential.share` `credential.owner`
- 成员：`member.list` `member.add` `member.edit` `member.remove` `member.detail` `member.merge` `member.borrow` `member.archive` `member.group` `member.family` `member.unclaimed` `member.messages` `member.permission`
- 记录：`record.list` `record.timeline` `record.detail` `record.search` `record.filter` `record.stats` `record.alarm` `record.active` `record.outwin` `record.export`
- 安全：`security.center` `security.defense` `security.tailgate` `security.audit` `security.ledger` `security.destroy` `security.watermark` `security.policy`
- 备份：`backup.center` `backup.export` `backup.restore` `backup.webdav` `backup.migrate` `backup.local` `backup.canonical` `backup.cloud` `backup.android-share`
- 关怀：`care.battery` `care.schedule` `care.maintenance` `care.milestone` `care.mascot` `care.hints` `care.changelog` `care.moments`
- 诊断：`diagnostic.center` `diagnostic.reference` `diagnostic.health` `diagnostic.data-health` `diagnostic.recovery` `diagnostic.crash` `diagnostic.trace` `diagnostic.telemetry` `diagnostic.scan` `diagnostic.cache` `diagnostic.prewarm` `diagnostic.reconcile` `diagnostic.qr` `diagnostic.dict` `diagnostic.hex` `diagnostic.fields` `diagnostic.selfcheck` `diagnostic.logs` `diagnostic.startup` `diagnostic.firmware`
- 设置：`settings.home` `settings.groups` `settings.appearance` `settings.a11y` `settings.unlock-prefs` `settings.link-prefs` `settings.notify` `settings.lab` `settings.about` `settings.deeplink` `settings.speech` `settings.haptics` `settings.language`
- 协议：`protocol.frame` `protocol.klv` `protocol.token` `protocol.aes` `protocol.otp` `protocol.keygen` `protocol.pidmap` `protocol.status` `protocol.log` `protocol.keychain` `protocol.gateway` `protocol.dfu` `protocol.cmd01` … `protocol.cmd44`（命令号两位）
- 数据：`data.store` `data.schema` `data.ledger` `data.snapshot` `data.logs-cache` `data.member` `data.dongle` `data.gateway` `data.audit` `data.secret` `data.time` `data.variant` `data.design` `data.search-index`
- Android 原生独有：`android.scan` `android.bind` `android.unlock`(→`unlock.dial`) `android.proximity`(→`unlock.proximity`) `android.finder`(→`unlock.finder`) `android.airtag` `android.settings-sheet`(→`device.manage`) `android.store`(→`data.store`) `android.permissions` `android.theme`
- APK 独有：`apk.page.<page名去 page- 前缀>`、`apk.cloud.*`、`apk.login`、`apk.ota` 等。

## 4. 深度自检（交卷前逐条过）
- [ ] 我覆盖了自己 scope 里的**每一个**文件？
- [ ] 每个用户可见的按钮 / 开关 / 菜单项 / 破坏性操作 / 确认弹窗都有节点或写进 details？
- [ ] 每个页面的空态、加载态、错误态、只读/访客限制写了吗？
- [ ] 每条写锁命令/读锁命令都对应到 `protocol.cmdXX` 了吗？
- [ ] 每个 `kf_*`/SharedPreferences/UserDefaults 键都归到 `data.*` 了吗？
- [ ] 证据行号我亲自看过吗？
- [ ] JSON 能被 `node -e "JSON.parse(...)"` 解析吗？
- [ ] 有没有把文档说法混进来？（有就删掉）
