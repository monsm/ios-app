# AUDIT-F · Security / Privacy + Engine Correctness

> 审计对象：`D:\\aapk\\ios-app\\ios27`（SwiftUI iOS App，App/Engine 69 个纯逻辑文件 + App/Shell/AppModel + 备份/设置/硬件页面）
> 审计日期：2026-10-31
> 审计快照：初次审计 `35fe751`；复核快照 `f50e34f`（2026-10-31 修复轮，逐项复核见 §6）
> 本报告只写本文件，未修改任何 Swift 源码。
> 审计立场：默认「不安全」；只写有文件:行号、代码或 grep 证据支撑的项。P0 = 无需用户交互的远程/未授权全量失陷；P1 = 高影响凭据泄露或安全控制可绕过；P2 = 需本地/用户动作的纵深防御、完整性、隐私或数据破坏问题；P3 = 低风险加固项。

---

## 0. 结论摘要

**初次审计（`35fe751`）：P0 = 0 · P1 = 4 · P2 = 17 · P3 = 11 · 合计 32 项。**

**复核（`f50e34f`）：完全修复 10 项 · 部分修复 4 项 · 仍存在 18 项 ⇒ 原 32 项中未闭环 22 项**（P1 2、P2 11、P3 9）。
**另发现 4 项由修复引入的新问题（§4.1）：N-01 为 P1（空壳模式下"还原"会抹掉真实台账），N-02/N-03/N-04 为 P3。**
**⇒ 当前仍需处理合计 26 项（其中 P1 共 3 项：SEC-01、SEC-03 残余、N-01）。**

没有发现可从网络无认证直接控制门锁的 P0 路径：本 App 没有云端账号，门锁命令只经 BLE；真正的风险集中在**本机秘密的落盘方式、备份/导出通路，以及“本应保护数据”的模式是否真被执行**这四件事上。

**当前最重的三项（按 `f50e34f` 复核后）**：

1. **N-01（P1，本轮修复引入）**：空壳模式下 `ledger(mac)` 返回空台账，但 `saveLedger` 没有 decoy 守卫 —— 胁迫者在"凭证工作室 → 回收站 → 还原"点一下，就会用空台账整表覆盖真实 `kf_ledger_<mac>`，**全部凭证永久丢失**。
2. **SEC-01（P1）**：门锁密码、手机钥匙 pin/ekey、回收站/历史副本仍明文存在 `NSUserDefaults`。
3. **SEC-03（P1，部分修）**：数据层 decoy 门禁只覆盖了 `keychains/ledger/readLogs/members`，`keychain(mac)`、`dongles()`、`gateways()`、`MobileKeyService.list`、`CredBinStore.all`、`CredHistoryStore.all`、`RecordSearch.notes` 仍未判 decoy。

---

初次审计（`35fe751`）时最重的四项（保留原始结论，其中 SEC-02/SEC-04 已修）：

1. **SEC-01（P1）**：Keychain 只保护了 `skey/bkey/ekey/pins`，而**门锁密码明文、手机钥匙 pin/ekey、回收站与版本历史副本**仍在 `NSUserDefaults` plist 里；一份 iTunes/iCloud 备份或一次容器取证即可拿到可直接开门的凭据。
2. **SEC-02（P1）**：备份默认**不加密**，落到 `Documents/lockkeeper-backups`，该目录既没有 `isExcludedFromBackup` 也没有 `.completeFileProtection`；包内含 `skey/bkey/pins/ekey`，即一键生成“家门万能钥匙文件”。
3. **SEC-03（P1）**：胁迫码/空壳模式只清 `AppModel` 的界面投影；`CredentialStudioScreen` 和 `BackupStudioScreen` 直接读 `DB`，在空壳模式下仍能查看/批量导出全部真实凭证。
4. **SEC-04（P1）**：靠近自动开锁不检查 `AppLock.unlocked`，且“严格档”把**Face ID 提示仍在等待**当作已通过（`pendingPrompt => true`），能在未解锁/未完成生物识别时下发开锁命令。

---

## 1. 范围与方法

- 逐文件阅读：`App/Engine` 全部 **69** 个 `.swift`（含 `AESKit`、`SecretStore`、`StoreKeychain`、`BackupKit`、`BackupBundle`、`BackupCanonical`、`BackupStudioKit`、`LockService*`、`BLEService`/`BLEDelegates`、`HardwareService`、`AutoOpenKit`、`FrameRedact`、`DiagKit`/`DiagLogStore`、`ZKProtocol`/`ZKCmdBuilder`/`StatusParser`、`ZOTP` 等）。
- 重点页面：`App/Shell/AppModel.swift`、`App/LockKeeperApp.swift`、`Features/Settings/{BackupScreen,BackupStudioScreen,SecurityScreen,SettingsScreen,SettingsParts,SettingsModel,HardwareScreen}.swift`、`Features/Keys/{KeyDetailScreen,MobileKeyScreen,ShareToAndroidScreen,CredentialStudioScreen,CredentialStudioStores,ZotpScreen}.swift`、`Features/Records/{RecordExportScreen,RecordsModels,RecordsStudioScreen}.swift`。
- 配置/合规：`project.yml`（Info.plist 由 XcodeGen 生成）、`App/PrivacyInfo.xcprivacy`。
- 方法：grep 全仓对账（`UIPasteboard`、`URLSession`、`UserDefaults`、`SecItem`、`CCCrypt`、`kSecAttrAccessible`、`isCaptured`、`fileProtection`、`try!`/force unwrap）、逐条阅读关键实现、对备份/恢复与协议帧构建器做数据流走查。
- 边界：本机是 Windows，无 Xcode/iOS 真机，不能做 `xcodebuild` 或运行时 BLE 抓包；本报告是**静态代码级**审计，不把“能编译”或“看起来跑过”当证据。动态验证建议见每项 Fix。

### 1.1 审计开始前已在 HEAD 修复、因此不计入发现的问题

以下问题在本报告快照前的提交 `35fe751` 中已修复，复核代码确认已消失，故不计入 32 项：`BackupBundle.Appearance.CodingKeys` 漏列字段、`FrameRedact` 脱敏文案未插值、`RecordSearchParse` 日历 `!` 崩溃、`DFUKit` 先取 `bytes[0]` 后判长度的越界顺序。若后续 revert 这些提交，对应问题会重新成立。

---

## 2. 发现（按严重度）

### SEC-01 [P1] 门锁密码、手机钥匙 pin/ekey 与回收站/历史副本明文存在 UserDefaults

**位置**
- `App/Engine/StoreModels.swift:64`：`LedgerPwd.pwd: String?`（门锁密码明文）
- `App/Engine/StoreLedger.swift:38`：`set(l, "kf_ledger_" + mac)`，台账整表写入 `Store`
- `App/Engine/Store.swift:73-87`：`Store.set` 用 `JSONSerialization` + `UserDefaults.standard.set`，无加密、无 Keychain
- `App/Engine/MobileKeyService.swift:15-24,58-67`：`MobileKey.pin` / `MobileKey.ekey` 作为 `kf_mkey_<mac>` 存储
- `App/Features/Keys/CredentialStudioStores.swift:15-17,30-33,84-91`：`CredBinItem.pwd` 回收站、`CredSnapshot.pwds` 版本历史（最多 10 份）都保存完整 `LedgerPwd`（含 `pwd`）

**证据**
`SecretStore` 的迁移注释明确说明原问题：“密钥与普通偏好一起经 Store.set → JSONSerialization → UserDefaults(plist) 明文落盘”（`App/Engine/SecretStore.swift:1-7`）；迁移只覆盖 `Keychain.skey/bkey/ekey/pins`（`StoreKeychain.swift:94-132`、`StoreModels.swift:449-492`），没有覆盖 `LedgerPwd.pwd`、`MobileKey.pin/ekey`、`CredBinItem.pwd`、`CredSnapshot.pwds`。这些值最终都在 `UserDefaults` 的 `kf.*` plist 里，且 `Store` 没有文件保护属性（`Store.swift:73-87`）。

**影响**
skey 被 Keychain 保护这一点被高估了：拿到设备备份（iTunes/iCloud，未加密或弱加密备份）或能读取 App 容器的人，可以直接读出门锁密码、手机钥匙 ekey+pin、回收站和历史快照中的旧密码；这些凭据足以在锁端有效期内开门。回收站/历史还会让“已彻底删除”的密码继续以明文存在。

**Fix**
1. 用 Keychain 中的随机数据密钥做信封加密（AES-GCM）后再存 `Ledger`/`MobileKey`/`CredBin`/`CredHistory`；或把这些结构整体迁入 Keychain（单条尺寸允许时分片）。
2. `UserDefaults` 只保留非密元数据（alias、名称、时间）；启动时校验 schema 并迁移旧值后从 plist 抹掉明文。
3. 给 `Store` 写保护标记，禁止新增明文 secret 键；CI grep 拦截 `pwd:`、`pin:`、`ekey:` 出现在 `UserDefaults` Codable 路径。

---

### SEC-02 [P1] 默认生成明文全量备份，写入 Documents 且进入 iCloud/iTunes 备份

**位置**
- `App/Features/Settings/SettingsModel.swift:227-229`：`encryptBackup` 默认 `false`（`getBool("kf_encrypt_backup")` 无默认 true）
- `App/Features/Settings/BackupScreen.swift:249-253`：未开启加密时 `exportText = plain`
- `App/Features/Settings/BackupStudioScreen.swift:270-289`：`let text = password.isEmpty ? plain : ...`，然后 `Data(text.utf8).write(to: BackupStudio.dir...)`
- `App/Engine/BackupStudioKit.swift:31-36`：`dir` = `Documents/lockkeeper-backups`，只 `createDirectory`，**没有** `isExcludedFromBackup`
- `App/Engine/BackupCanonical.swift:99-102`：`kcValue` 写入 `skey`、`pins`、`ekey`（以及 `BackupBundle.Device.Meta.mobileKeys` 的 pin/ekey，`BackupCanonical.swift:155-169`）
- `App/Features/Settings/BackupScreen.swift:81`：UI 文案声称“文件只留在本机 Documents”，但 Documents 默认参与 iCloud/iTunes 备份

**影响**
用户点一次“生成本机备份”，默认就生成含全部门锁母钥（skey）、PIN 池、手机钥匙和 App 密码摘要的明文文件；该文件会随 iCloud/iTunes 备份离开设备。任何人拿到该文件即可离线构造开锁帧。即使开加密，`password` 为空的分支仍是明文。

**Fix**
1. 备份接口默认强制加密：调用 `collectAll()` 检测到 `skey/pins/ekey` 非空时，没有密码就拒绝写文件；UI 不再提供“留空 = 明文”的一键路径。
2. 备份目录设置 `isExcludedFromBackup = true`，并对文件使用 `.completeFileProtection`（另见 SEC-10）。
3. 对“换机迁移”同样强制口令，或改用 `ShareLink`/本地临时文件 + 完成后删除，不走 Documents 持久目录。

---

### SEC-03 [P1] 胁迫码/空壳模式只清界面投影，数据层仍暴露全部真实凭证

**位置**
- `App/Shell/AppModel.swift:130-139`：`reload()` 在 `decoyMode` 只清 `keys/members/entries` 三个界面数组，注释明确“只清界面投影，不动任何真实存储”
- `App/Features/Keys/KeysScreen.swift:547-568`：无论是否空壳，都渲染“凭证工具 → 凭证工作室”入口
- `App/Features/Keys/CredentialStudioScreen.swift:42-66`：`pwdRows` / `fpRows` 直接 `DB.listPwds(studioMac)` / `DB.listFps(studioMac)`，完全绕过 `app.keys`
- `App/Features/Settings/BackupStudioScreen.swift:270-289`：`BackupKit.collectAll()` 直接读全库，空壳模式照样可生成/上传/复制含全部密钥的备份

**影响**
“被胁迫时输入胁迫码，门能开、数据看不见”是产品对用户的安全承诺。当前实现里，胁迫者只要在 App 内点“设置 → 备份工作室 → 生成一份本机备份”，或“钥匙 → 凭证工作室”，即可看到/导出真实凭证；空壳模式对数据读取没有任何强制力。

**Fix**
1. 在数据访问层（`DB`/`Store`）引入 `SecurityContext`（normal/decoy），所有 `listPwds/listFps/keychains/collectAll` 在 decoy 下返回空集或脱敏集；不要只靠页面 `@State`。
2. 在 decoy 下隐藏/禁用备份、导出、凭证工作室、成员档案、删除设备等所有会泄露或破坏数据的入口。
3. 增加 UI 测试：设置胁迫码 → 用胁迫码进入 → 遍历所有 Dest，断言不出现真实 alias、密码长度、ekey、锁名和备份文本。

---

### SEC-04 [P1] AutoOpen 绕过 App 锁，且严格档把“Face ID 提示进行中”当作已认证

**位置**
- `App/Engine/AutoOpenKit.swift:115-128`：`faceFresh(tier:lastFace:now:pendingPrompt:strictSince:)` 在 `pendingPrompt == true` 时直接 `return true`；`facePromptInFlight` 在提示开始 30 秒内返回 true
- `App/Engine/AutoOpenKit.swift:289-299`：`pollOnce()` 只判断 `AutoOpen.on` 和 `EngineHost`，不检查 `AppLock.shared.unlocked`
- `App/Engine/AutoOpenKit.swift:340-375`：`attempt()` 的门控上下文 `f0Foreground` 只判断 `UIApplication.applicationState == .active && !AppLock.shared.decoy`，没有 `unlocked`
- `App/LockKeeperApp.swift:50-56`：`RootView.onAppear` / `.task` 在冷启动（还在 LockGate）就注册并启动 `AutoOpenController`
- `App/Engine/AutoOpenKit.swift:202-218`：`rejectReason` 使用 `faceFresh(...)` 作为 F1 判据

**影响**
用户开启“靠近自动开锁”后：
- 手机在锁屏/冷启动 App 锁界面时，靠近门锁仍可由 `AutoOpenController` 下发 `cmd04`，完全绕过本机密码闸；
- 严格档（声称每次前台刷脸）在 Face ID 提示尚未成功、甚至失败后的 30 秒内被当作“已认证”，RSSI 达到武装线即开门。

**Fix**
1. `pollOnce/attempt` 增加 `AppLock.shared.unlocked == true` 与 `!AppLock.shared.decoy`；锁屏/后台立即 `armed=false`。
2. `faceFresh` 严格档必须 `lastFace != nil && lastFace >= strictSince && !facePromptInFlight(...)`；把“提示中”与“已验证”分开。
3. 把 F0/F1/F3/F4/F5/F6 的判定表写成单元测试（含 pendingPrompt、lastFace=nil、decoy、locked 四组）。

---

### SEC-05 [P2] 剪贴板 90 秒过期只覆盖 2 处，10 处敏感内容直接写 `UIPasteboard`

**位置**
- `App/Engine/Clip.swift:11-25`：`Clip.set` 统一设 `expirationDate = now + 90`；全仓只有 `App/Features/Keys/ZotpScreen.swift:125,214` 调用它
- 直接写 `UIPasteboard.general.string` 的敏感路径：
  - `App/Features/Settings/BackupScreen.swift:168-170`（完整备份文本，可能是全部 skey）
  - `App/Features/Settings/BackupStudioScreen.swift:368-371`（换机包完整备份）
  - `App/Features/Keys/KeyDetailScreen.swift:110-113,142-144`（凭证码值/分段）
  - `App/Features/Keys/MobileKeyScreen.swift:158-161`（手机钥匙 ekey）
  - `App/Features/Keys/ShareToAndroidScreen.swift:142-147`（含 ekey 的配对串）
  - `App/Features/Keys/CredentialStudioScreen.swift:362-364`（凭证包）
  - `App/Features/Records/RecordExportScreen.swift:447-450`（含成员姓名/记录的 CSV 摘要）
  - `App/Features/Records/RecordsStudioScreen.swift:267-269`（脱敏帧）

**影响**
`UIPasteboard.general.string = ...` 不设置过期时间，内容会一直留在系统剪贴板，并可能通过 Universal Clipboard 同步到其他设备；把完整备份/迁移包/ekey 复制后，任何前台 App 在用户粘贴提示允许时都可读取。项目自己在 `Clip.swift` 里承认“全仓 17 处 0 处设过期时间”，但迁移只完成了 2 处。

**Fix**
1. 全部改为 `Clip.set`；新增 grep 门禁：`UIPasteboard.general.string =` 只允许出现在 `Clip.swift`。
2. 备份/迁移包不要放剪贴板，改用 `ShareLink` 或 `fileExporter`；若必须复制，设置 30–90 秒过期并在 App 进后台时清空。
3. 增加测试：复制后模拟 `UIApplication.didEnterBackground`，断言 pasteboard 为空。

---

### SEC-06 [P2] 备份把 App 密码降级为 32 位 FNV 摘要，且 PBKDF2 仅 60k 轮

**位置**
- `App/Engine/BackupKit.swift:188-190`：收集 `kf_passcode` 时只取 `s` / `d`，丢弃 `d2`（PBKDF2 强摘要）
- `App/Engine/BackupBundle.swift:133`：`PasscodeRec { s, d }` 结构本身只有 s/d
- `App/Engine/BackupCanonical.swift:307-309`：canonical 只写 `s`/`d`
- `App/Engine/Store.swift:374-386`：`pcIter = 60_000`；`passcodeRecord` 同时存 `d = fnv1a32(salt+pw)` 与 `d2 = pcStrong(pw)`；备份只带弱 `d`
- `App/Engine/BackupStudioKit.swift:420-422`：恢复时把 `s/d` 写回 `kf_passcode`，无 `d2`

**影响**
明文备份（默认路径见 SEC-02）或加密备份被解密后，App 的 4 位数字密码只剩 32 位 FNV1a 摘要，离线穷举 10^4 个候选是毫秒级；恢复后系统还会用这份弱摘要验证，直到用户再次成功输入才升级。PBKDF2 60k 轮也低于当前密码存储实践（OWASP 对 PBKDF2-HMAC-SHA256 建议远高于此；应做设备基准）。

**Fix**
1. 备份 schema 增加 `d2`（可选字段，v6）并加入 canonical；恢复优先 `d2`，不再把弱 `d` 作为主验证路径。
2. 新设备/新备份使用至少 600k 轮或改用 Argon2id；把 `pcIter` 作为版本化参数存进摘要记录，验证时按记录轮数。
3. 备份口令至少强制 8 位混合字符（当前只长度 >=8）。

---

### SEC-07 [P2] 胁迫码 `duress` 从未写进 canonical/备份文本，换机后静默丢失

**位置**
- `App/Engine/BackupBundle.swift:49-53`：定义 `Globals.duress: PasscodeRec?`，注释称“2026-10-30 修复……从来没进过备份”
- `App/Engine/BackupKit.swift:191-194`：`collectAll` 确实把 `kf_duress` 映射进 `duress`
- `App/Engine/BackupCanonical.swift:236-321`：`canonical()` 的 globals 分支只写 `appearance/deviceOrg/gatewayList/keychainDongles/passcode/trace`，**没有 `duress` 分支**
- `App/Engine/BackupStudioKit.swift:424-429`：`restore` 的 `g.duress` 分支永远收不到值（因为导出文本没有它）

**影响**
用户设置的胁迫码在“生成备份 → 换机恢复”后丢失；而胁迫码是“被胁迫时输入它进入空壳模式”的安全承诺。换机后该承诺静默失效，用户可能在真正需要时被暴露。

**Fix**
1. 在 `BackupCanonical.canonical()` globals 段增加 `duress`（顺序放在 `deviceOrg` 与 `gatewayList` 之间，按字母序），并确保 canonical/checksum 包含它。
2. 增加 round-trip fixture：有 duress 的包导出→导入→`hasDuressCode()` 为 true，且 `verifyDuress` 通过。
3. 若因 schema 兼容不能升版本，可将 `duress` 放进现有 `passcode` 可选子树并加 migration 测试。

---

### SEC-08 [P2] 恢复无条件信任备份中的 passcode/duress 摘要，且只检查 skey 非空

**位置**
- `App/Engine/BackupStudioKit.swift:332-359`：`restore` 遍历 `c.devices`；第 350 行 `guard HexKit.bytes(d.mac).count == 6, !d.kc.skey.isEmpty else { continue }`，只判非空，不判 `skey` 是 32 位十六进制
- `App/Engine/BackupStudioKit.swift:420-429`：直接 `DB.store.set("kf_passcode", ["s": pc.s, "d": pc.d])` 和 `kf_duress`，没有当前密码验证、没有二次确认、没有“包内密码摘要来源”校验
- `App/Features/Settings/BackupScreen.swift:63-68`：只提示“若备份里带本机密码摘要，本机密码会被替换成它（可能回滚到旧值）”
- `App/Engine/StoreKeychain.swift:94-132`：`saveKeychain` 会无条件把传入的 `skey` 写进 Keychain

**影响**
1. 恶意/损坏的备份可设置一个攻击者已知的 App 登陆密码（PBKDF2/FNV 摘要），下次冷启动后攻击者可用该密码打开 App，形成持久后门。
2. 非 16 字节或非十六进制的 `skey` 会覆盖原有 Keychain 密钥；此后所有加密帧使用错误密钥，原锁可能无法再被本机打开（软砖），且恢复备份也不一定救回（原密钥已被覆盖）。
3. `duress` 可被注入/删除，破坏胁迫码承诺。

**Fix**
1. 恢复界面前置“输入当前本机密码”验证；用户未设置密码时要明确的二次确认并展示“将替换 App 密码”的风险。
2. 校验 `skey` 必须 `^[0-9a-fA-F]{32}$`、`pins` 必须 8 位十六进制、`ekey` 长度上限；先在内存/临时 Keychain 中构建，全部校验通过后再提交。
3. 如果备份包没有 `d2` 而本机有 `d2`，保留本机 `d2`（或要求用户重新设密码），不要把强摘要降级成弱摘要。

---

### SEC-09 [P2] 恢复前自动生成的 rollback 快照把完整 Keychain（skey/pins）明文写入磁盘

**位置**
- `App/Engine/BackupStudioKit.swift:37-40`：注释明确“回滚快照点的是整库 Keychain (skey/ivKey 明文)”
- `App/Engine/BackupStudioKit.swift:135-175`：`RollbackBundle.keychains: [String]` 是 `JSONEncoder().encode(Keychain)` 的字符串；`Keychain` 的 `skey/bkey/pins/ekey` 都在 `StoreModels.swift:15-18`；`makeRollbackPoint` 第 172 行只 `.atomic` 写文件
- `App/Engine/BackupStudioKit.swift:41-48`：rollbackDir 在 Application Support、`isExcludedFromBackup = true`（这点正确），但**没有文件保护/加密**
- `App/Engine/BackupStudioKit.swift:60-74`：快照只生成、无消费（无 `loadRollbackPoint` / UI 撤销入口），文件保留 4 份

**影响**
每次恢复（包括从恶意/错误包恢复）都会把当前所有锁的 skey/pins/ekey 以明文 JSON 写到磁盘，保留 4 份且无过期/删除入口。设备被取证、越狱或恶意文件读取时，这些快照等同于母钥备份；而功能本身“只能生成、无法使用”，收益为 0。

**Fix**
1. 用 Keychain 中的独立密钥对 rollback 做 AES-GCM 加密；或把快照存进 Keychain（分片）。
2. 写入时使用 `.completeFileProtection`（不是默认的 UntilFirstUserAuthentication）。
3. 明确保留策略（7 天/最多 4 份）并提供“删除本机还原点”入口；在功能未接 UI 前直接移除自动快照，避免无主明文密钥堆积。

---

### SEC-10 [P2] 除诊断日志外，所有备份/回滚/导出文件都没有 `.completeFileProtection`

**位置**
- 全仓唯一一处文件保护：`App/Engine/DiagLogStore.swift:41`：`.completeFileProtectionUntilFirstUserAuthentication`
- `App/Features/Settings/BackupStudioScreen.swift:279`：`Data(text.utf8).write(..., options: .atomic)`，无 `.completeFileProtection`
- `App/Engine/BackupStudioKit.swift:171-172`：rollback `data.write(to: rollURL, options: .atomic)`
- `App/Features/Settings/BackupScreen.swift:47-55`：`fileExporter` 写系统文件，未指定保护等级

**影响**
iOS 默认 App 数据文件是 `NSFileProtectionCompleteUntilFirstUserAuthentication`：设备第一次解锁后，锁屏状态仍可被读取。对含 skey 的备份/回滚来说，应使用 `NSFileProtectionComplete`（设备锁屏即不可读）。当前备份/回滚文件均未显式设置，且 at-rest 明文风险见 SEC-02/SEC-09。

**Fix**
1. 所有 secret-bearing 文件写入使用 `Data.WritingOptions.completeFileProtection`；目录创建后用 `URLResourceValues` 设保护属性。
2. 对 `BackupStudio.dir` 与 `rollbackDir` 增加 `isExcludedFromBackup = true`（rollback 已有，backup 没有）。
3. 用 XCTest 断言文件属性 `NSFileProtectionKey == NSFileProtectionComplete`。

---

### SEC-11 [P2] “截图保护”只覆盖两个视图，且 `isCaptured` 检测不到截图

**位置**
- `App/Design/Components/CaptureShield.swift:1-4,12-49`：判据是 `UIScreen.isCaptured`，只在**录屏/镜像**时为 true；普通截图不会触发；文案却写“屏幕正在被录制或截图”
- 使用点只有 `App/Features/Keys/KeyDetailScreen.swift:131`（码值卡）与 `App/Features/Keys/ShareToAndroidScreen.swift:50`（二维码）
- 未加保护：`App/Features/Keys/ZotpScreen.swift:94-106`（动态码文本）、`App/Features/Settings/BackupScreen.swift:161-166`（完整备份文本）、`App/Features/Keys/MobileKeyScreen.swift`（ekey 复制菜单）、`App/Features/Settings/BackupStudioScreen.swift`（迁移包文本）

**影响**
用户以为开启“防窥挡片/屏幕捕获遮罩”能防截图，实际普通截图照样把 OTP/动态码/备份文本/ekey 带走；录屏检测也只覆盖两个指定视图。对“给别人看 OTP”或“截图备份文本”场景是安全承诺失效。

**Fix**
1. 监听 `UIApplication.userDidTakeScreenshotNotification`，在敏感页面截图后立即隐藏码值并提示；录屏继续用 `isCaptured`。
2. 给所有展示 OTP/备份/ekey/密码的视图统一挂 `captureShield`；敏感输入用安全文本入口/系统截图禁用的 `UITextField` 包装。
3. 文案改成“录屏时遮挡；截图会被检测并自动隐藏”，不要承诺做不到的“防截图”。

---

### SEC-12 [P2] CSV / vCard 导出存在公式注入与换行注入

**位置**
- `App/Features/Records/RecordsModels.swift:368-386`：`RecordCSV.field` 只处理逗号、双引号、`\\n`，不处理 `=`、`+`、`-`、`@`、tab、`\\r`
- `App/Features/Records/RecordsModels.swift:398-401`：`MemberVCard.escape` 不转义 `\\r`，可伪造 vCard 行
- `App/Engine/StatsKit.swift:68-81`：`lastWeekDigest` 的 `esc` 同 CSV 规则，且表头用全角逗号（`时间，类型，成员`），列数可能错位
- 可注入内容来源：`Member.name` / `Member.phone`（`StoreModels.swift:160-188`），且成员名可来自导入的备份（`BackupStudioKit.swift:442-449`），成员/锁名/备注都可被构造为 `=HYPERLINK("...",...)`、`+cmd|...` 等

**影响**
用户导出 CSV 后用 Excel/Numbers 打开，恶意成员名/备注可触发公式/DDE 执行（取决于客户端），或至少造成钓鱼链接；vCard 的 `\\r` 可注入额外字段。虽非 App 内 RCE，但属于典型的“信任边界外的数据进入用户办公软件”风险。

**Fix**
1. 所有 CSV cell 统一函数：若首字符是 `= + - @ \\t \\r`，前置单引号 `'` 或空格；对 `\\r` 也按换行处理并加引号。
2. vCard 转义增加 `\\r` -> `\\\\r`（或直接拒绝 `\\r`）。
3. 导出前对成员名/备注做长度和字符白名单；给出“CSV 仅供查看，不要启用宏”的提示。

---

### SEC-13 [P2] BleTelemetry 把台账变更的备注/成员文本写进 UserDefaults，随系统备份出机

**位置**
- `App/Engine/StoreLedger.swift:39-47`：`ledgerDiff` 的 `desc` 包含 `o.note -> p.note`、`owner` 等，然后 `BleTelemetry.recordEvent("台账变更 " + name + ": " + desc)`
- `App/Engine/DiagKit.swift:227-265`：`BleTelemetry` 把 `kf_ble_events` 存进 `DB.store`（即 `UserDefaults`），上限 200 条
- `App/Engine/StoreKeychain.swift:203-221`：`removeDevice` 的键族列表不含全局 `kf_ble_events`/`kf_conn_attempts`

**影响**
用户备注常含“给谁、哪扇门、备用密码提示”等敏感文本；这些内容以明文进入 `kf_ble_events`，随 iCloud/iTunes 备份出机，且删设备后仍保留。日志/遥测与“凭证内容不进日志”的纪律冲突。

**Fix**
1. `ledgerDiff` 只记录字段名与哈希指纹（已有 `HashKit.fingerprint`），不要记录 note/owner 原文。
2. 遥测改存 `Caches` + `isExcludedFromBackup`（同 `DiagLogStore`），并加入保留期/清空入口。
3. 删设备时按前缀清理全局遥测中该锁名的条目，或重新设计全局事件为匿名。

---

### SEC-14 [P2] 备份校验和是 32 位 FNV，且 mismatch 只警告不拦截；明文备份无认证

**位置**
- `App/Engine/BackupCanonical.swift:53-85`：checksum = `fnv1a32Hex`；注释明确“FNV 无密钥，只用于意外损坏检测，不是防篡改”
- `App/Engine/BackupStudioKit.swift:218-229`：`checksumState` 只比较 FNV/legacy FNV
- `App/Engine/BackupStudioKit.swift:252-258`：下载/导入时 `checksumState` 为 mismatch **不 throw**，仅 Preview 显示；`parsePreview` 随后返回 bundle
- `App/Engine/BackupKit.swift:227`：自身注释“真要防篡改得换带密钥的 MAC（另立项）”

**影响**
明文备份没有 HMAC；FNV 可被任意重算。恶意/损坏的备份包（例如导入他人分享的“备份”）可修改成员、锁名、备注、设备记录而不被硬拦截；用户在预览显示“校验失败”后仍可能继续恢复。加密信封有 HMAC，但 schema 兼容的明文包没有。

**Fix**
1. 给所有备份（含明文包）增加 HMAC-SHA256（密钥来自用户口令派生）或签名；v6 schema 强制验证。
2. mismatch 改为默认 fail-closed，提供明确的“我已核对来源，仍要导入”二次确认；仅对明确的 legacy 包保留 warning。
3. 保留 FNV 作为兼容读取，不作为安全判据。

---

### SEC-15 [P2] BLE 单连接上 LockService/HardwareService 各有一套 waiter，响应可被错误消费者拿走

**位置**
- `App/Engine/BLEService.swift:124-126`：`emit(_:)` 把每一帧广播给所有 `frameSubscribers`
- `App/Engine/LockServiceLink.swift:108-115`：只按 `frame.cmd` 匹配自己的 `waiter`，没有 peripheral/连接代次
- `App/Engine/HardwareService.swift:32-45`：同样只按 `cmd` 匹配自己的 `waiter`
- `App/Engine/BLEService.swift:209-278`：`connect/disconnect` 可直接被 `HardwareService.connectTarget` 调用；`LockService` 的挂起 `waiter` 不会收到 `BLEService.disconnect` 的取消（只有 `LockService.disconnect` 会 `rejectWaiter`）
- `App/Engine/LockServiceLink.swift:203-288`：`request` 的超时/重试与 waiter 只覆盖单帧

**影响**
同一时间从“门”页做开锁、从“设置 → 硬件”读钥匙串/网关时，两个服务共用 `BLEService`：`cmd03`/其它相同 cmd 的响应可能被另一个服务当成自己的结果，导致错误状态写库、错误的 rc 判定、甚至把 dongle 的状态当作锁状态参与 F6 判据；一方 `connectTarget` 断链会让另一方等 8 秒超时。正确性/可用性问题，亦可能让安全门控使用错误锁态。

**Fix**
1. 建立单一 `BLECommandArbiter`：所有服务通过同一队列提交命令，按“命令+peripheral UUID+连接 generation”匹配响应；不能有两个独立 waiter。
2. `BLEService.disconnect` 通知所有 waiter（或所有服务统一经 `LockService.disconnect`）；写前检查连接代次。
3. 加并发测试：同时发两条 `cmd03` 到不同目标，断言不会交叉消费。

---

### SEC-16 [P2] `FrameAssembler` 无缓冲上限，且协议解析用宽松 `HexKit.bytes` 接受畸形帧

**位置**
- `App/Engine/ZKProtocol.swift:241-266`：`push` 只 `buf += chunkHex`，找不到完整帧就 `break`，从不限制 `buf` 长度；攻击者可连续发送“87 + 声明一个很大 len”的残帧让内存持续增长
- `App/Engine/ZKProtocol.swift:72-86`：`parseKLV` 使用 `HexKit.bytes`（非严格）
- `App/Engine/HexKit.swift:11-12`：`strictBytes` 注释明确“协议解析路径本该用它（现在用宽容版 bytes()），留作后续收紧”
- `App/Engine/ZKProtocol.swift:200-238`：`parseResponse` 多种 header 都尝试，第一个解析成功即采用；畸形回包可被误认成合法帧

**影响**
靠近的恶意 BLE 设备可对 App 造成内存压力/DoS（连接后持续发残帧），或构造“结构合法但语义错位”的回包让 App 解析出错误状态/rc；配合 SEC-15 的 waiter 混用，影响面扩大。

**Fix**
1. `FrameAssembler` 设置最大缓冲（如 64 KiB/最多 4 帧），超限丢弃并记遥测；`len` 上限按协议最大帧校验。
2. 解析路径切换 `HexKit.strictBytes`；任何非 hex/奇数长度直接判失败；解析多解时保留所有候选并拒绝语义不确定的帧。
3. 对 `parseKLV` 做 fuzz 测试（随机/超长/截断输入）。

---

### SEC-17 [P2] `restore` 无条件 `clearAllLedgerCorrupt()`，会把无关锁的损坏台账标记清掉并允许后续覆盖

**位置**
- `App/Engine/BackupStudioKit.swift:341`：恢复开始即 `DB.clearAllLedgerCorrupt()`
- `App/Engine/StoreLedger.swift:10-12`：清除所有锁的损坏标记
- `App/Engine/StoreLedger.swift:14-20,29-36`：`ledger()` 发现键存在但解码失败会 `markLedgerCorrupt`；`saveLedger` 对 corrupt 锁拒绝写入，保护原数据

**影响**
用户只为 A 锁导入一份备份，却把 B 锁原本“解不出但可人工恢复”的台账标记清掉；B 锁下一次 `saveLedger` 会读到 nil 并按空表/新表覆盖，原始数据永久丢失。这是数据破坏，不是保密问题，但对“离线锁管家”是高风险。

**Fix**
1. 只对本次恢复 `bundle.devices` 中实际成功恢复的 mac 清标记；在恢复结束后逐锁 `clearLedgerCorrupt(mac)`。
2. restore 前把当前 corrupt 键族写入 rollback（已有快照机制）并验证可读；或者拒绝恢复并要求用户先处理损坏锁。
3. 加测试：B 锁 corrupt + A 锁备份导入 → B 仍保持 corrupt，后续写入仍被拒。

---

### SEC-18 [P2] 凭证详情“彻底删除”手机钥匙只删内存投影，不撤销锁端 PIN 也不删 `kf_mkey`

**位置**
- `App/Features/Keys/KeyDetailScreen.swift:369-389`：`deleteKey()` 分支中，手机钥匙走 `app.keys.removeAll { $0.id == key.id }`，**只改内存**
- `App/Engine/MobileKeyService.swift:130-134`：真正的撤销路径 `MobileKeyService.revoke(host:kc:key:)` 会 `deletePins([key.pin])` 并 `save(mac, list.filter...)`
- `App/Shell/AppModel.swift:170-180`：`app.keys` 只是 `MobileKeyService.list(mac)` 的投影，重启后会重建

**影响**
用户在详情页点“彻底删除”看到成功，重启后手机钥匙仍在 `kf_mkey_<mac>`，且锁端 PIN 仍有效——旧的 ekey 仍能开门；与“撤销/删除”语义完全相反。属于安全撤销失效。

**Fix**
1. 手机钥匙分支调用 `MobileKeyService.revoke(host: app, kc: kc, key: mk)`；锁端 `cmd08` 失败时不要删本地记录，并提示“锁端未撤销”。
2. 若只是本机隐藏，改文案为“仅从本机列表移除（锁端仍有效）”，不要放在“彻底删除/不可逆”区。
3. 加测试：撤销后重启 `MobileKeyService.list` 为空，且 `deletePins` 被调用一次。

---

### SEC-19 [P2] 删除设备不清理备份、回滚快照与全局遥测；`SecretStore.remove` 忽略失败

**位置**
- `App/Engine/StoreKeychain.swift:194-236`：`removeDevice` 清理 `kf_*` 与 Keychain 账户，但不触碰 `BackupStudio.dir` 的备份文件与 `rollbackDir` 快照
- `App/Engine/BackupStudioKit.swift:31-36,147-175`：备份文件与 rollback 快照都保留含该锁 skey/pins 的完整包
- `App/Engine/DiagKit.swift:227-265`：`kf_ble_events`/`kf_conn_attempts` 是全局键，不在 `removeDevice` 列表
- `App/Engine/SecretStore.swift:57-59`：`remove` 忽略 `SecItemDelete` 的返回状态，删除失败无提示

**影响**
用户“删除这把锁的本机数据”后，旧备份/还原点仍能恢复出该锁的母钥；系统备份/取证可拿到。数据删除不完整，违反“删设备即删该锁数据”的预期。

**Fix**
1. `removeDevice` 删除/重加密所有包含该 MAC 的备份文件与 rollback 快照；至少提供“删除本机所有备份/还原点”入口并默认勾选。
2. `SecretStore.remove` 返回 `Bool/OSStatus`，删除失败时 UI 明确告知，并重试/报告。
3. 增加删除后审计：枚举 `kf.*`、本地 Documents/Application Support、Keychain 服务，断言无 MAC/skey 残留。

---

### SEC-20 [P2] WebDAV 接受 `http://` 且 Basic Auth 明文发送；局域网 ATS 例外放行

**位置**
- `App/Features/Settings/BackupStudioScreen.swift:466-470`：`normalized` 只去空白，保留 `http://` 或补 `https://`
- `App/Features/Settings/BackupStudioScreen.swift:451-459`：`upload` 设置 `Authorization: Basic base64(user:password)`，`URLSession.shared` 默认跟随重定向
- `project.yml:73-75`：`NSLocalNetworkUsageDescription` + `NSAllowsLocalNetworking: true`，允许本地网络 HTTP
- `App/Features/Settings/BackupStudioScreen.swift:153`：文案称“账号密码只存本机 Keychain / 偏好，不上传第三方”

**影响**
用户在局域网使用 `http://192.168.x.x/...` 时，WebDAV 用户名/App 密码和完整备份（可能含 skey）以明文经过 Wi-Fi；同一网络攻击者可直接读取。公共 HTTP 远程主机虽然通常被 ATS 拦，但本地网络例外实际放行，且错误提示不说明协议不安全。

**Fix**
1. `normalized` 拒绝 `http://`（除非 `localhost`/`127.0.0.1` 且显式“我了解明文风险”二次确认）；UI 默认只接受 `https://`。
2. 用自定义 `URLSessionConfiguration.ephemeral` + `URLSessionTaskDelegate` 处理重定向，跨 host 丢弃 Authorization；设置合理超时。
3. 上传前强制加密备份（SEC-02）；对 WebDAV 错误不回显含 userinfo 的 URL。

---

### SEC-21 [P2] 本机密码闸首次解锁后永不重新上锁，`AppLock.lock()` 是死代码

**位置**
- `App/Engine/AppLock.swift:121-139`：注释称“手动上锁（设置页「立即锁定」、或回前台超时）”，但 `lock()` 在全仓无调用点（grep `\\.lock()` 只命中 `Locked.swift:32` 的 NSLock）
- `App/LockKeeperApp.swift:82-91`：`scenePhase` 进入 `.background` 只调 `AutoOpenController.onBackground()`，不调 `AppLock.lock()`；进入 `.active` 直接 `app.unlocked = AppLock.shared.unlocked`（仍为 true）
- `App/Features/Door/DoorScreen.swift:585-588`：只有“30 秒内第二次开锁”要求密码；超过 30 秒或回前台不再要求
- `App/Engine/AppLock.swift:135-139`：`lock()` 只清 `unlocked/decoy`，但无人调用

**影响**
手机被拿走后，只要 App 进程未被杀（用户切到后台/接电话/锁屏但未 force quit），再次打开 App 无需本机密码即可查看凭证、导出备份、开锁；与“冷启动才要求”的设计相比，手机丢失场景实际保护时间被缩短到“一次冷启动”。

**Fix**
1. `scenePhase == .background` 记录时间，超过可配置超时（如 30 秒/5 分钟）调用 `AppLock.lock()`；设置页增加“立即锁定”。
2. 每次进入 `BackupScreen/BackupStudioScreen/KeyDetail/CredentialStudio` 前校验 `AppLock.unlocked`（或统一 `RequireUnlockModifier`）。
3. 若产品坚持“冷启动才要求”，在安全页明确写“切后台不会重新上锁”，不要用“本机密码是查看/导出的前置屏障”这样的绝对表述。

---

### SEC-22 [P3] 协议层 AES-128-ECB + ZeroPadding 无 IV、无认证，静态 ekey 可重放

**位置**
- `App/Engine/AESKit.swift:1-24`：AES-128-ECB + ZeroPadding，注释“与 JS utils/crypto.js 字节级一致”
- `App/Engine/ZKProtocol.swift:170-178`：`wrapEnc` 用 `AESKit.encryptHex(env, keyHex: skeyHex)`，没有随机 IV/MAC
- `App/Engine/ZKCmdBuilder.swift:140-147`：`buildEkeyOpen` 把同一 skey/PIN/有效期加密成静态 ekey，cmd04 可重复使用到 2118

**影响**
协议既定限制：ECB 会泄露相同明文块模式，密文无完整性；更重要的是 ekey 是静态 bearer token，附近攻击者若抓到一次 cmd04 帧，可在有效期内重放（外层会话令牌只保护外层帧，不改变 ekey）。这是锁固件/协议层面的残余风险，App 无法单独根治。

**Fix**
1. 在文档/隐私说明中明确“协议为 AES-128-ECB，App 不把 ECB 当认证加密”；不要把 skey 之外的 ekey 当短期凭据。
2. 固件升级时改为 AES-GCM/CMAC + 随机 nonce/序号；在此之前限制 ekey 有效期、把 cmd04 与会话令牌/时间绑定。
3. App 侧继续保持每次 cmd04 走新的会话令牌；对重放检测只能记录异常。

---

### SEC-23 [P3] `FrameRedact` 只处理第一个 `hex=` 且 4096 字符后剩余 hex 不脱敏

**位置**
- `App/Engine/FrameRedact.swift:17-32`
  - `msg.range(of: "hex=")` 只取第一次出现；若一条日志含两个 `hex=`，第二个原样保留
  - 循环条件 `hexPart.count < 4096, rest.isEmpty`：超过 4096 个 hex 字符后，后续 hex 字符进入 `rest`，会原样输出（约 2048 字节以上帧）
  - `guard hexPart.count >= 16 else { return msg }`：短 hex 载荷完全不脱敏

**影响**
当前调用点帧都较短（BLE 20B 分片拼出的命令帧 < 2K），但这是“防御只对当前长度成立”的定时炸弹；将来加长帧（固件/日志）会把后半段密钥/PIN 写进 `DiagLogs`、导出和剪贴板。

**Fix**
1. 改为“第一个 `hex=` 到下一个非 hex 字符的全部 hex”并统一截断；超过上限时整段替换为 `…(redacted N bytes)`，绝不把剩余 hex 放回。
2. 多个 `hex=` 全部处理；`hex` 太短也按敏感处理（至少输出 `<redacted>`）。
3. 加单测：2K/4K/8K hex、两个 hex=、含空格/中文尾。

---

### SEC-24 [P3] `kf://device?mac=` 可由任意 App/网页切换当前锁，且无来源确认

**位置**
- `App/LockKeeperApp.swift:57-81`：`onOpenURL` 对 `host == "device"` 直接 `DB.currentMac = mac`（只要求 `DB.keychain(mac) != nil`）
- `project.yml:64-68`：公开注册 `kf` URL scheme
- `App/LockKeeperApp.swift:58`：只检查 `app.unlocked`，不检查 URL 来源/是否用户主动点击

**影响**
恶意网页/二维码/其他 App 可打开 `kf://device?mac=<已知MAC>` 把 App 当前锁切到指定锁，诱导用户对错误的门执行开锁/改设置；虽然不能直接开门（仍需用户点），但会造成误操作和社工。`kf://records?k=` 还可构造任意记录 id 的导航上下文。

**Fix**
1. 对 `device` 深链增加显式确认（“是否切换到 XXX 锁？”）；URL 中只接受当前已配对 MAC，显示锁名与来源提示。
2. 对 `records/k=` 做格式校验（必须匹配 `<mac>#<idx>` 且 mac 已配对）。
3. 若深链只用于通知，可改用 Universal Link 或内部通知 userInfo，减少公开 scheme 攻击面。

---

### SEC-25 [P3] `ZOTP` 的 `assert` 在 Release 被编译掉，`periodMin` 来自锁状态未做 guard

**位置**
- `App/Engine/ZOTP.swift:23-31`：注释说“原先 assert 已删除，若恢复要写 guard”，但第 29 行仍有 `assert(periodMin <= 0 || (1...120).contains(periodMin), ...)`
- `App/Features/Keys/ZotpScreen.swift:204-206`：`rawPeriod = DB.readStatus(mac)?.zotpPeriod ?? 0`，`period = rawPeriod > 0 ? rawPeriod : 30`；没有上限/异常值处理
- `project.yml` Release 默认 `-O`，`assert` 不执行

**影响**
Release 真机上异常固件返回 `zotpPeriod = 0xFFFF` 或负值（Int 来自 u16），不会崩但生成错误窗口的 6 位码（用户反复试也开不了）；Debug 下反而崩。注释与实际代码不一致，后续维护者会误以为已有校验。

**Fix**
1. 用 `guard (1...120).contains(periodMin) else { return "" }`（或 clamp 到 1...120 并记遥测），删除 assert。
2. `ZotpScreen` 对 `rawPeriod` 做同一 guard；显示“锁端周期异常，暂不生成”。
3. 把 `ZOTP.generate` 加入异常值单元测试。

---

### SEC-26 [P3] 隐私清单“数据全部留本机、不上传服务器”与 WebDAV 上传/导出能力不一致；加密出口申报需复核

**位置**
- `App/PrivacyInfo.xcprivacy:19-25`：`NSPrivacyCollectedDataTypes` 为空，注释“本 App 全部数据留在本机，不上传服务器”
- `App/Features/Settings/BackupStudioScreen.swift:151-159,348-362`：WebDAV 上传完整备份到用户配置的远端
- `App/Engine/BackupCanonical.swift:209-214`：成员值包含 `phone`，备份包含姓名/电话/凭证
- `project.yml:77`：`ITSAppUsesNonExemptEncryption: NO`，但 App 实现 `AES-128-CBC + HMAC-SHA256`（`BackupKit.swift:1-4`）

**影响**
若 WebDAV 上传被 Apple 或用户理解为“数据传输到第三方”，空的 CollectedDataTypes 与“全部留本机”字样会导致隐私标签/隐私政策不一致；`ITSAppUsesNonExemptEncryption: NO` 对自定义 AES 也需要出口合规复核（是否属于豁免类别由法律/构建审计确认）。

**Fix**
1. 隐私清单/隐私政策明确“用户可自行配置 WebDAV；启用时备份（含成员联系信息与凭证）会离开设备到用户指定服务器”，在 WebDAV 设置页显示同等提示并做开启前确认。
2. 复核 `ITSAppUsesNonExemptEncryption`：若自定义 AES 不属于豁免，改 `YES` 并提交出口合规信息；同时保留 HTTPS/TLS 说明。
3. 在 `PrivacyInfo` 若确实不收集（开发者不接收），保留空数组但在注释/隐私政策里区分“开发者收集”与“用户主动传输”。

---

### SEC-27 [P3] 没有 secret 清零；`keychainCache` 在进程生命周期内保留全部 skey/pins

**位置**
- `App/Engine/StoreKeychain.swift:8`：`private let keychainCache = Locked<[String: Keychain]>([:])`
- `App/Engine/StoreKeychain.swift:22-29,94-132`：`keychain(_:)/saveKeychain` 把含 skey/bkey/ekey/pins 的 `Keychain` 长期缓存在内存
- `App/Engine/AppLock.swift:135-139`：`lock()` 只改 `unlocked/decoy`，不清 `keychainCache`、`sessionTokenHex` 等
- 全仓 grep `memset|zeroize|wipe|resetBytes|withUnsafeMutableBytes` 无任何清零实现；`SecretStore.get` 返回不可控的 Swift `String`

**影响**
App 上锁/退后台后，所有锁的母钥仍常驻进程内存；被调试器、内存转储、崩溃日志（若含堆）获取即可绕过 Keychain 的“锁屏不可读”保护。Swift String 不可可靠清零是平台限制，但至少可以缩短生命周期、用 `[UInt8]` + `memset_s` 处理。

**Fix**
1. `AppLock.lock()` 清空 `keychainCache`、`sessionTokenHex`、`tokenExpiryMs` 等；`SecretStore` 用 `[UInt8]` 并在使用后 `memset_s`。
2. 将 `Keychain` 的 secret 字段改为按需读取、不缓存整个结构（或缓存只有非密字段）。
3. 崩溃/日志捕获 SDK 不采集内存；开启 `NSFileProtectionComplete`。

---

### SEC-28 [P3] `VerifyPasscodeSheet` 与 `UnlockGateScreen` 的失败计数不持久/可重置，`AppLock.recordFailure` 无调用点

**位置**
- `App/Engine/AppLock.swift:121-133`：`recordFailure()` 设计给“第二次开锁口令验证”用，但全仓 grep 无调用点（只有 `Store` 同名不同函数）
- `App/Features/Settings/SettingsParts.swift:340-391`：`VerifyPasscodeSheet.verify()` 只 `guard DB.verifyPasscode(code)`，无失败计数/冷却
- `App/Features/Door/UnlockGateScreen.swift:97-113`：`failures` 是 `@State`，关闭 sheet 即重置；3 次后仅 30 秒本地冷却

**影响**
拿到已解锁手机的人可在“关闭本机密码/关闭胁迫码/再次开锁”等对话框无限次重试 4 位数字密码；关闭 sheet 即清零，绕过 `AppLock` 的持久冷却设计。虽然前提是已解锁，但用户短暂离开手机的场景仍可利用。

**Fix**
1. `VerifyPasscodeSheet` 和 `UnlockGateScreen` 统一调用 `AppLock.recordFailure()`/`failStreak`，冷却写入 `kf_lock_fail/kf_lock_cool`；关闭 sheet 不重置。
2. 失败达到阈值时要求生物识别/延迟输入；把 `AppLock.lock()` 绑定到背景超时（SEC-21）。
3. 单测：关闭 sheet 重开、杀进程重启，冷却仍有效。

---

### SEC-29 [P3] `SecretStore.remove` 与 WebDAV `saveDav` 忽略 Keychain 写入结果

**位置**
- `App/Engine/SecretStore.swift:57-59`：`static func remove(_ account: String) { SecItemDelete(...) }`，无返回值/错误处理
- `App/Features/Settings/BackupStudioScreen.swift:328-334`：`_ = SecretStore.set(davPassword, for: "backup.webdav.password")`，失败仍提示“成功：WebDAV 配置已保存”

**影响**
删除设备时 Keychain 条目可能残留（之后同 MAC 重新配对可能复用旧密钥）；WebDAV 密码写失败时用户以为已保存，下次启动丢失，或继续用内存中的旧密码。属于错误处理/数据完整性问题。

**Fix**
1. `SecretStore.remove` 返回 `OSStatus`/`Bool`，调用方记录失败并提示；`removeDevice` 失败时不假装删除完成。
2. `saveDav` 检查返回值，失败显示“无法写入 Keychain，配置未保存”；清空密码时调用 `remove` 而不是存空串。

---

### SEC-30 [P3] 备份导入无大小/类型上限，`String(contentsOf:)` 可被超大文件拖垮

**位置**
- `App/Engine/BackupStudioKit.swift:237-276`：`parsePreview` 直接 `JSONDecoder().decode(BackupBundle.self...)`，没有 `body.count` 上限，也没有校验 `bundle.type == "kf-bundle"`
- `App/Features/Settings/BackupScreen.swift:269-284`：`String(contentsOf: url, encoding: .utf8)` 整个文件读入内存
- `App/Features/Settings/BackupStudioScreen.swift:193-198`：迁移文本无长度限制

**影响**
用户从“文件”选择一个几 GB 的 JSON/文本或恶意构造的巨大备份，App 在 `String(contentsOf:)`/JSONDecoder 阶段内存暴涨，可能被系统杀死（可用性）；无 `type` 校验还允许导入任意“看起来像 BackupBundle”的 JSON，扩大攻击面。

**Fix**
1. 读取前用 `FileManager` 的 `fileSize` 限制（如 32 MB）；超出直接报错。
2. `parsePreview` 校验 `bundle.type == "kf-bundle"`、`bundleVer` 范围、`devices.count` 上限（如 64）、每个 ledger 条目数上限。
3. 对大文本使用流式解析或分块读取。

---

### SEC-31 [P3] `ZKProtocol.buildKLV` 对 >255 字节载荷静默截断

**位置**
- `App/Engine/ZKProtocol.swift:52-71`：`rawLen > 0xFF` 时 `v = String(v.prefix(0xFF*2))`，只记一条遥测，仍返回截断 KLV
- `App/Engine/ZKCmdBuilder.swift:292-299`：`cmd31GWSetWifi` 把 SSID/密码放进 KLV；若 WiFi 密码过长（或含多字节 UTF-8）会被截断后下发
- 其他长参数：未来固件/日志分片同路径

**影响**
用户输入超长 WiFi 密码时，App 会把截断后的密码发给网关，导致网关无法联网；用户看到“写入成功/失败”无法知道是截断。协议 KLV 长度本来只有 1 字节，超长应在构造层拒绝而不是静默截断。

**Fix**
1. `buildKLV` 超长时返回 `nil`/抛错，由 `cmd31GWSetWifi` 提示“SSID/密码过长”，不要截断后继续发送。
2. 对 `KLV` 值长度建立类型级约束（例如 `KLVValue` 保证 <=255）。
3. 加测试：256/300 字节输入断言构帧失败且 UI 不显示成功。

---

### SEC-32 [P3] 凭证到期通知的“删旧+排新”存在跨队列竞态，删除凭证可能仍收到旧提醒

**位置**
- `App/Engine/CredentialOrgState.swift:24-33`：`scheduleAlerts` 调异步 `scheduleAlertsOrdered`
- `App/Engine/CredentialOrgState.swift:42-62`：`cancelAlerts` 与 `scheduleAlertsOrdered` 各自 `getPendingNotificationRequests` 异步回调，没有统一串行队列
- 场景：删凭证的 `cancelAlerts` 先执行完（pending 为空）→ 之前已排队的 `scheduleAlertsOrdered` 再执行并重新添加 6 条通知

**影响**
已删除/停用凭证仍会在到期前弹“密码临期”，泄露凭证存在性并误导用户；属于隐私/可用性缺陷，非权限提升。

**Fix**
1. 所有 `UNUserNotificationCenter` 调度收敛到单一串行 `NotificationScheduler` actor/队列，`cancelAlerts` 与 `scheduleAlerts` 使用同一队列顺序执行。
2. 为每条凭证维护代次（generation），删除后递增；异步回调里校验代次，过期结果丢弃。
3. 测试：快速“改提醒→删凭证”与“删凭证→改提醒”两种顺序均无 pending 通知。

---

## 3. 已核实的正面控制（不是发现）

以下控制经代码核实，可作为“已做对”的基线，避免后续修复破坏：

1. **Keychain 访问级别**：`App/Engine/SecretStore.swift:38-44` 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，更新时显式迁移旧条目；没有 `AfterFirstUnlock`。
2. **加密备份信封**：`App/Engine/BackupKit.swift:102-114` 每次随机 16B salt + IV；`135-160` 先验 IV/HMAC/salt/ciphertext 形状，再 HMAC（`152-158`）后解密；`122-128` 常量时间 MAC 比较。AES-CBC + HMAC-SHA256 encrypt-then-MAC 的组装正确。
3. **随机源**：`App/Engine/KeyGen.swift:12-21` 使用 `SecRandomCopyBytes`，失败回退 `UInt8.random`（SystemRandomNumberGenerator），且 `LockServicePairing.swift:72-75` 对全零 skey/bkey/pins fail-closed。
4. **日志脱敏主路径**：`App/Engine/LockService.swift:41-60` 对 `hex=` 帧统一走 `FrameRedact`；`HardwareService.swift:49-57` 同口径；完整帧只留在内存 `recentFrames`，诊断页导出前再次 `FrameRedact.apply`（`RecordsStudioScreen.swift:288`）。
5. **诊断日志落盘**：`App/Engine/DiagLogStore.swift:14-46` 从 UserDefaults 移到 `Caches`，`isExcludedFromBackup = true`，且使用 `.completeFileProtectionUntilFirstUserAuthentication`。
6. **BLE 连接后身份复核**：`LockServiceLink.swift:56-80` 与 `HardwareService.swift:76-98` 连接后读 `cmd03` 对照登记 pid，不匹配即断开且不写缓存，能防伪造广播。
7. **Keychain 明文迁移**：`StoreKeychain.swift:67-92` 只有 Keychain 确认有值才从旧 plist 删除明文，避免写失败导致丢钥。
8. **隐私清单的 Required Reason**：`App/PrivacyInfo.xcprivacy:27-50` 已声明 `NSPrivacyAccessedAPICategoryUserDefaults (CA92.1)` 与 `NSPrivacyAccessedAPICategoryFileTimestamp (C617.1)`，覆盖当前实际 API 使用。

---

## 4. 复核表（对照 HEAD `f50e34f`，2026-10-31）

> 复核方式：逐条在 `f50e34f` 上重读代码 + grep 全仓；每行给出**复核后的行号**（旧报告行号可能因修复提交位移）。
> 判定口径：**已修** = 该条描述的可利用路径已不存在；**部分修** = 主路径已收紧但仍存在可触发的残余路径；**仍存在** = 代码未变或只改了文案。
> 汇总：已修 **10** · 部分修 **4** · 仍存在 **18** ⇒ **原 32 项未闭环 22 项**；另有 §4.1 的 4 项新问题（N-01 P1 + N-02~N-04 P3）⇒ **当前待处理合计 26 项**。

| 编号 | 严重度 | 复核结论 | 修复提交 | 复核证据（当前行号） |
|---|---|---|---|---|
| SEC-01 | P1 | **仍存在** | — | `StoreModels.swift:64` `var pwd: String?` 仍在；`StoreLedger.swift:45` `set(l,"kf_ledger_"+mac)` → `Store.swift:79` `defaults.set(d,forKey:)`；`MobileKeyService.swift:17` `var pin`；`CredentialStudioStores.swift:15` `var pwd: LedgerPwd?`。全仓 `Store.swift` 无 CryptoKit/加密。 |
| SEC-02 | P1 | **已修** | fd3e73a | `BackupScreen.swift:253` 空口令即拒绝生成；`BackupStudioScreen.swift:279/364/381` 本机文件、WebDAV 上传、换机包三路均强制口令；`BackupStudioKit.swift:37` `isExcludedFromBackup=true`；`BackupStudioScreen.swift:288` `.completeFileProtection`。**残余（P3 级）**：`BackupScreen.swift:98/107-109/128-130` 仍显示「加密/明文」档与「默认关闭」，UI 文案与「强制加密」不一致。 |
| SEC-03 | P1 | **部分修** | a1c7df5 | 已加数据层门禁：`StoreKeychain.swift:20`、`StoreLedger.swift:21`、`StoreState.swift:61`、`Store.swift:209`；`AppModel.swift:142` 广播。**残余漏洞**：①`StoreKeychain.swift:30` `keychain(mac)` **未判 decoy** ⇒ `AppModel.currentKeychain` 仍返回真钥匙串，ZotpScreen/ShareToAndroid/MobileKey 可用；②`Store.swift:294/326` `dongles()/gateways()` 未判 decoy；③`MobileKeyService.swift:60`、`CredentialStudioStores.swift:22/80`、`RecordSearch.swift:31`（备注）未判 decoy；④`AppLock.swift:153` `lock()` 只置 `decoy=false`，**不回写 `DB.setDecoy(false)`**，胁迫码后上锁再正常解锁会停在空壳数据层；⑤ 与 decoy 早退叠加出 **N-01 数据销毁路径**（见 §4.1）。 |
| SEC-04 | P1 | **已修** | fd3e73a / a1c7df5 | `AutoOpenKit.swift:128` `pendingPrompt → return false`；`:294` `guard AppLock.shared.unlocked, !decoy`；`:371` `f0Foreground` 增加 unlocked。**残余**：`:395` dispatch 下发前复查仍只判 `AutoOpen.on + applicationState`，attempt→dispatch 之间若上锁仍有窄竞态（`lock()` 会 `disconnect()`，实际多被链路断开拦住）。 |
| SEC-05 | P2 | **已修** | fd3e73a | 10 处写入全部改 `Clip.set`：`KeyDetailScreen.swift`(2 处)、`MobileKeyScreen.swift`、`ShareToAndroidScreen.swift`、`CredentialStudioScreen.swift`、`RecordExportScreen.swift`、`RecordsStudioScreen.swift`、`BackupScreen.swift`、`BackupStudioScreen.swift`；grep `UIPasteboard` 只剩 `Clip.swift` 自身 + 两处**读取**（`KeyCreateScreen.swift:124`、`BackupScreen.swift:222`）。 |
| SEC-06 | P2 | **仍存在** | — | `BackupKit.swift:189/193` 仍只取 `s/d`；`BackupBundle.swift:133` `PasscodeRec {s,d}`；`BackupCanonical.swift:307-315` 只写 `passcode`（无 `d2`）；`Store.swift:383` `pcIter = 60_000`；`BackupStudioKit.swift:432` 恢复只写 s/d。grep `d2` 在备份链路 0 命中。 |
| SEC-07 | P2 | **已修** | fd3e73a | `BackupCanonical.swift:305` 新增 `gp.append(("duress", …))`，字母序落在 `deviceOrg` 与 `gatewayList` 之间；`BackupStudioKit.swift:436` 恢复分支因此可收到值。 |
| SEC-08 | P2 | **仍存在** | — | `BackupStudioKit.swift:360` 仍为 `guard HexKit.bytes(d.mac).count == 6, !d.kc.skey.isEmpty`（只判非空，无 32 hex 校验）；`:432` 仍无条件 `DB.store.set("kf_passcode", …)`；恢复前无本机密码验证。 |
| SEC-09 | P2 | **部分修** | fd3e73a | `BackupStudioKit.swift:178` 已加 `.completeFileProtection`；但 `makeRollbackPoint`（:152）仍把 `Keychain` 明文 JSON 直接编码（`RollbackBundle.keychains` 未加密），无密钥保护，仍是"明文母钥文件"。 |
| SEC-10 | P2 | **部分修** | fd3e73a | 备份文件（`BackupStudioScreen.swift:288`）与 rollback（`BackupStudioKit.swift:178`）已用 `.completeFileProtection`；`BackupStudioKit.swift:37` 备份目录已 `isExcludedFromBackup`。**残余**：`BackupScreen.swift:47` `fileExporter` 导出的文件仍无保护等级；目录级保护未设（仅文件级）。 |
| SEC-11 | P2 | **仍存在** | — | `CaptureShield.swift:3/38` 仍只监听 `UIScreen.capturedDidChangeNotification`；grep `userDidTakeScreenshotNotification` 全仓 0 命中；挂载点仍只有 `KeyDetailScreen.swift:131` 与 `ShareToAndroidScreen.swift:50`；`ZotpScreen`/`BackupScreen`/`BackupStudioScreen` 未挂。 |
| SEC-12 | P2 | **已修** | b0368f8 | `RecordsModels.swift:373` 首字符 `= + - @ \t \r` 前置单引号；`:376` `\r` 归一；`MemberVCard.escape`（:406-413）已转义 `\r`。**残余（P3）**：`StatsKit.swift:68` `lastWeekDigest` 的 `esc` 仍是旧规则（仅处理逗号/引号），该函数输出的 CSV 会被 `RecordExportScreen.swift:448` 拼进"上周小结"并复制到剪贴板。 |
| SEC-13 | P2 | **仍存在** | — | `StoreLedger.swift:66/74` 仍写 `[o.note, p.note]`；`:67` 仍写 owner 原文；`:53` 仍 `BleTelemetry.recordEvent("台账变更 …")` → `DiagKit` `kf_ble_events`（UserDefaults）。 |
| SEC-14 | P2 | **仍存在** | — | `BackupCanonical.swift:61/78` 仍是 FNV1a32 / legacy；`BackupStudioKit.swift:258` `let ck = checksumState(body)` 仅用于预览，:281 `checksum: ck`；无 `throw`，仍不硬拦；明文包仍无 HMAC。 |
| SEC-15 | P2 | **仍存在** | — | `LockServiceLink.swift:111` 仍 `frame.cmd == w.cmd`；`HardwareService.swift:35` 仍同款；`BLEService.swift:124-126` 仍广播给全部订阅者；无连接代次/仲裁器（grep `generation` 在该路径 0 命中）。 |
| SEC-16 | P2 | **仍存在** | — | `ZKProtocol.swift:245` 仍 `buf += chunkHex`，:244-265 无长度上限；`:72-73` `parseKLV` 仍用宽容 `HexKit.bytes`；`HexKit.swift:12` `strictBytes` 仍"保留未接"。 |
| SEC-17 | P2 | **已修** | b0368f8 | `StoreLedger.swift:15` 新增 `clearLedgerCorrupt(mac)`；`BackupStudioKit.swift:348-351` 改为只清本次 `devices` 且非 `skip` 的锁；`clearAllLedgerCorrupt` 仅剩定义（grep 无调用点）。 |
| SEC-18 | P2 | **仍存在** | — | `KeyDetailScreen.swift:380` 仍 `app.keys.removeAll { $0.id == key.id }`，分支未调 `MobileKeyService.revoke`（grep 该文件 0 命中）。 |
| SEC-19 | P2 | **仍存在** | — | `StoreKeychain.swift:202-241` `removeDevice` 仍不清 `BackupStudio.dir`/`rollbackDir`；`SecretStore.swift:57-59` `remove` 仍无返回值；grep `BackupStudio` 在 StoreKeychain 0 命中。 |
| SEC-20 | P2 | **已修** | f50e34f | `BackupStudioScreen.swift:485-493` `normalized` 拒绝非回环 `http://`（`:490` 仅 `localhost`/`127.0.0.1` 例外），其余强制升级 `https://`。**残余（P3）**：`URLSession.shared` 仍跟随重定向且未剥离 `Authorization`（跨 host 时 Basic 头可能被带走）。 |
| SEC-21 | P2 | **已修** | a1c7df5 | `AppLock.swift:139` `didEnterBackground`、`:147` `willEnterForeground(lockAfter:30)`；`LockKeeperApp.swift:88-91` scenePhase 已接线；`AppLock.swift:153-160` `lock()` 现在会被调用（并 `dropKeychainCache`+`disconnect`）。 |
| SEC-22 | P3 | **仍存在** | — | `AESKit.swift:6-23` 仍 AES-128-ECB + ZeroPadding；`ZKProtocol.swift:170-178` 仍无 IV/MAC；`ZKCmdBuilder.swift:140-147` ekey 仍静态。协议层未变（属固件侧待改）。 |
| SEC-23 | P3 | **已修** | 140f8b1 | `FrameRedact.swift:23-24` 改为 `while let r = msg.range(of:"hex=", range:)` 逐段处理；:27-34 每段 hex 全部吞掉并按长度脱敏，短 hex → `<redacted>`，不再把剩余 hex 放回。 |
| SEC-24 | P3 | **仍存在** | — | `LockKeeperApp.swift:62-67` 仍 `case "device":` 直接 `DB.currentMac = mac`，无来源确认/无二次确认弹窗。 |
| SEC-25 | P3 | **已修** | 140f8b1 | `ZOTP.swift:31` `let period = (1...120).contains(periodMin) ? periodMin : 30`，:32-34 异常值记遥测；`assert` 已删除。 |
| SEC-26 | P3 | **仍存在** | — | `PrivacyInfo.xcprivacy:20` 仍写「全部数据留在本机，不上传服务器」，`NSPrivacyCollectedDataTypes` 仍为空；`project.yml:77` 仍 `ITSAppUsesNonExemptEncryption: NO`。（WebDAV 已强制 HTTPS，但隐私声明文字未更新） |
| SEC-27 | P3 | **部分修** | a1c7df5 | `StoreKeychain.swift:13` 新增 `dropKeychainCache()`，`AppLock.swift:158` 在 `lock()` 时调用并 `LockService.shared.disconnect()`。**残余**：仍无 `memset_s`/`resetBytes`（grep 0 命中）；`SecretStore.get` 仍返回不可清零的 `String`；`sessionTokenHex` 仅在 `disconnect` 清，进程内其余拷贝（`Keychain` 值类型副本、SwiftUI `@State`）未处理。 |
| SEC-28 | P3 | **仍存在** | — | `AppLock.swift:126` `recordFailure` 仍零调用（grep 仅定义处）；`SettingsParts.swift` `VerifyPasscodeSheet` 与 `UnlockGateScreen.swift:15` `@State failures` 仍各自为政。 |
| SEC-29 | P3 | **仍存在** | — | `SecretStore.swift:57` `remove` 仍返回 Void；`BackupStudioScreen.swift:341` 仍 `_ = SecretStore.set(davPassword, …)` 且下一行无条件提示"成功"。 |
| SEC-30 | P3 | **仍存在** | — | `BackupStudioKit.swift:243-257` `parsePreview` 仍无 `body.count` 上限、无 `bundle.type == "kf-bundle"` 校验（grep 0 命中）；`BackupScreen.swift:277` 仍 `String(contentsOf:)` 整读。 |
| SEC-31 | P3 | **仍存在** | — | `ZKProtocol.swift:52-71` `buildKLV` 仍返回 `String` 并在 `rawLen > 0xFF` 时 `prefix(0xFF*2)` 截断（:65-68）。 |
| SEC-32 | P3 | **仍存在** | — | `CredentialOrgState.swift:24/42/52` 仍是两个独立 `getPendingNotificationRequests` 异步回调，无串行调度器（grep `NotificationScheduler` 0 命中）。 |

### 4.1 复核中发现的**新增**问题（修复引入，不计入原 32 项）

| 编号 | 严重度 | 位置 | 说明 |
|---|---|---|---|
| N-01 | **P1** | `StoreLedger.swift:20-27`（decoy 早退）+ `:36-45`（saveLedger 无 decoy 守卫）+ `StoreLedger.swift:89-93/96-99/143-147` + `CredentialStudioStores.swift:22/46-53` + `CredentialStudioParts.swift:149` | **空壳模式下"还原"会抹掉真实台账（数据销毁）。** `ledger(mac)` 在 decoy 时提前 `return Ledger()`（:21），但 `saveLedger` **没有 decoy 守卫**（:36-45 只判 `isLedgerCorrupt`），而 decoy 下又从不 `markLedgerCorrupt` ⇒ 任何"读-改-写"都会用空台账整表覆盖 `kf_ledger_<mac>`。可达路径（已核实）：`KeysScreen.swift:83` 常驻渲染 `shortcutsBlock` → 凭证工作室 → `CredentialStudioScreen.swift:80` `binCard` 常驻 → `:423` 打开回收站 → `CredBinStore.all` **未判 decoy**（`CredentialStudioStores.swift:22`）⇒ 列出真实条目 → 点"还原"（`CredentialStudioParts.swift:109`）→ `DB.addPwd`（`StoreLedger.swift:89`）→ `saveLedger` 用"只有这 1 条"的空台账覆盖 ⇒ **其余凭证全部丢失**。版本历史 `restore`（`CredentialStudioStores.swift:46-53`/`:93-98`）同理。 |
| N-02 | P3 | `AppLock.swift:153-160` + `Store.swift:206` | `lock()` 只置 `decoy=false`，**不调用 `DB.setDecoy(false)`**：在胁迫码（空壳）会话里被 30 秒后台超时上锁，再以正常密码解锁，数据层 `isDecoy` 仍为 true（直到下一次 `AppModel.reload()`），界面继续显示空数据。fail-closed 的可用性缺陷，但"解锁后看不到自己的凭证"极易被误报成丢数据。建议 `lock()` 内同步 `DB.setDecoy(false)`。 |
| N-03 | P3 | `BackupScreen.swift:98/107-130` | 强制加密已生效，但 UI 仍显示「加密 / 明文」档位标签、仍可关闭「加密备份」开关、说明文字仍写「所以默认关闭」。用户以为还能生成明文备份，点下去却报错。建议删除该开关或改成不可关闭的"必须设置口令"说明。 |
| N-04 | P3 | `StatsKit.swift:68` | CSV 注入修复只覆盖 `RecordsModels.RecordCSV`/`MemberVCard`；`lastWeekDigest` 内联的 `esc` 未同步，仍把成员名/锁名原样拼进 CSV，该文本经 `RecordExportScreen.swift:448` 进剪贴板。建议复用 `RecordCSV.field`。 |

## 5. 修复优先级建议（按复核后的剩余项重排）

1. **立即（发布阻断，仍未闭环的 P1）**：**N-01**（空壳下还原抹台账）、**SEC-01**（门锁密码明文、手机钥匙 pin/ekey、回收站/历史副本落 UserDefaults）、**SEC-03**（空壳残余：`keychain(mac)`/`dongles()`/`gateways()`/`MobileKeyService.list`/`CredBinStore.all`/`CredHistoryStore.all`/`RecordSearch.notes` 未判 decoy + `lock()` 不回写 `setDecoy(false)`）。
   - **N-01（P1，新引入）必须与 SEC-03 同一批修**：给 `saveLedger` 加 `if isDecoy { return }` 守卫（或让 decoy 走独立只读副本），否则"空壳下点还原 = 抹掉全部凭证"。
   - SEC-02 / SEC-04 主路径已修（fd3e73a / a1c7df5），但 SEC-02 的 UI 文案不一致（N-03）建议一并收尾。
2. **本次迭代（P2 剩余 11 项）**：SEC-06（`d2` 进备份）、SEC-08（恢复校验 skey/密码）、SEC-09（rollback 加密）、SEC-10（fileExporter 保护）、SEC-11（截图检测）、SEC-13（遥测脱敏）、SEC-14（校验和 fail-closed/HMAC）、SEC-15（BLE 单仲裁器）、SEC-16（FrameAssembler 上限 + strictBytes）、SEC-18（手机钥匙撤销）、SEC-19（删设备清备份 + `SecretStore.remove` 返回值）。
3. **随后（P3 剩余 8 项 + 新增 N-02/N-03/N-04）**：SEC-22、SEC-24、SEC-26、SEC-28、SEC-29、SEC-30、SEC-31、SEC-32；其中 SEC-15/SEC-16 是 Engine 正确性核心，建议优先于纯 UI 加固。

**已闭环、不需要再动的**：SEC-02、SEC-04、SEC-05、SEC-07、SEC-12、SEC-17、SEC-20、SEC-21、SEC-23、SEC-25（10 项，证据见 §4）。

## 6. 附：审计覆盖与限制

- 已读 Engine 69/69 个 `App/Engine/*.swift`；重点页面见 §1。未修改任何源码；本文件是唯一输出。
- 未做动态验证：无 macOS/Xcode/iOS 真机，无法运行 BLE 抓包、Keychain 取证、文件保护属性实测；建议在真机/模拟器上补：
  - 备份文件 `NSFileProtectionKey` 与 iCloud 备份包含测试；
  - 空壳模式遍历全部 Dest 的 UI 测试；
  - AutoOpen 的门控矩阵测试（locked/decoy/pendingPrompt/lastFace）；
  - 恶意备份（超大/非 hex skey/篡改 passcode/duress）导入测试；
  - BLE 双服务并发测试。
- §2 的行号基于初次审计快照 `35fe751`（保留原始证据）；§4 复核表已按 `f50e34f` 重取行号。如后续提交再移动代码，请按符号名/代码片段复核。
