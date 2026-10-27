# AUDIT-B — 创意 301–550 对抗式代码审计


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> 方法: 以 ROADMAP-DRAFT 包5/6/7/8「收录/舍弃/⚠」+ FEATURE-TRIAGE Part2 + DECISION-NEEDED + DEFERRED 为基准, 逐编号在 App/ 内 grep 实现证据 (创意号写在代码注释里), 三态判定: DONE / PART(未接线或有备案降级) / MISS(无代码无备案)。
> 审计日 2026-10-07。只信代码, 不信文档声称。

## 一、统计 (共 250 编号: 301–550)

| 分类 | 数量 | 说明 |
|---|---|---|
| 应做 (✅收录) | 239 | 301–550 段 ✅ 收录 240 项, 扣除 ❌541 |
| DONE | 190 | 有实现且接线 (含本次审计新接线项, 见 P0) |
| ⚠DONE (合规降级) | 20 | 按 DEFERRED 备案口径降级/占位/并入落地 |
| PART (未接线/备案暂缓) | 14 | 开关或文案在, 主功能未接或未备案 |
| MISS | 20 | 无代码无备案 = 漏项 |
| ❌ 排除 | 1 | 541 (DECISION-NEEDED 建议替代, 未做=合规) |
| 舍弃 | 5 | 302/318/321 (包5) + 384 (包7) + 540 (包2) |

**MISS 20 项**: 312/313/336/338/339/342/344/354/361/362/367/368/387/397/404/415/416/432/433/437。
**PART 14 项**: 310/334/370/372/374/377/396/405/426/435/447/455/471/537 (其中 370/372/374 已有 DEFERRED 包7 暂缓备案; 334/447/455⚠/471/537/426/435/405/396/377/310 无备案)。

## 二、P0 已修清单 (当场修复, 闸门已绿)

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| P0-1 | SecurityCenterView:403 | 403 按住2秒清空回收站: startHoldTask 跑满后无人调用 clearTrash (形同虚设), 且 clearTrash 只清从未被填充的演示键 kf_sdest_trash, 真回收站 CredentialOrg.kf_cbin_ 未动 | 任务跑满 2s 自动 clearTrash(); clearTrash 真清各锁 kf_cbin_; trashCount 改为各锁回收站条数和 |
| P0-2 | AuditChain:386 | 哈希链可被本地绕过: ① id=毫秒时间戳, 两条同毫秒即重放/注入; ② 头部截断后重封 GENESIS 链 verifyChain 不检出; ③ purgeExpired(385) 截断保留段后保留段哈希指向被删条目, 链永久"断链"误报 | id 改 last+1 单调; verifyChain 增 id 单调校验 (brokenAt=-2 序号异常); purgeExpired 截断后整段重封重锚 GENESIS 并留痕 |
| P0-3 | LockKeeperApp 390/391 | 安全级: 胁迫码/伪装码只有配置入口, AppLockView 完全不识别 — "进空壳/打标"零实现, "视觉无破绽"无从谈起 | unlockAttempt 先比胁迫码 (放行+会话打标 kf_sses_duress/kf_sduress_at + AuditLog 橙边记录) 再比伪装码 (进 DecoyShellView 天气空壳, 真密码逃生), 无破绽只留痕; 顺带补 395 救援码重置入口/392 失败留痕/389 递增冷却/393·394 后台锁定时机+免验窗口/398 会话写入 |
| P0-4 | CredentialStudio 521 | 521 二次输入确认缺失: 保存密码不重输码值 | 确认步加 confirmPwd 重输核对, 不一致禁提交; 开关 kf_scred_2nd (安全页可关, SecurityCenterView 新 Section) |
| P0-5 | BackupStudioKit WebDAV | 对抗重点: ① 远端列表 XML 解析对恶意响应无护栏 (resourcename 实体/超长/二进制静默当空); ② 远端条目名直接拼 URL, 恶意 <resourcename>../.. 或外链可被 delete/download 利用 | listRemote 拒绝非 UTF-8 响应 + xmlUnescape + 256 长度护栏; 新增 safeRemoteURL (禁 / 前缀/外链/../), pruneRemote/dryRunRemote/下载全走该护栏 |
| P0-6 | BackupStudio 408/549 | 408 口令两遍已有, 但 549 "备份口令与应用锁密码相同" 提示缺失 | 口令步 DB.verifyPasscode(pw) 命中即 warn 提示"建议分开设置" |

未修 (P1/P2, 见下): 未做 386 链外的跨设备重放防护 (本地轻量口径, 文档已声明)。

## 三、P1 清单 (只列不修)

| 编号 | 问题 |
|---|---|
| 377 | 访客通道只有安全中心开关+敏感成员隐藏键; "访客进入"入口与 Tab 过滤逻辑未落地 (代码自注"待接线") |
| 396 | 随机键位开关 (kf_slock_randkey) 有, 应用锁仍为单 TextField, 随机布局未消费 |
| 447 | 分阶段迁移 (先迁凭证+成员, 记录次日补 + 阶段记录) 未做, 只有 445 中断续迁 |
| 310 | 别名字段未做: 记录 Tab 展项无独立"别名", 沿 note/归属 |
| 426 | 扫码恢复: 恢复页仅粘贴文本, 文案承诺"相机扫码" (BackupStudio:473/1280) 但无相机扫码 UI; NSCameraUsageDescription 仅 522 侧 |

## 四、P2 清单

| 位置 | 问题 |
|---|---|
| AuditChain DestroyKit.checkResidue | 残留检索面只有键名 (snap=keys()), 未遍历值; 报告"零残留"口径偏乐观 (plist 值残留不可见), 建议后续加值采样 |
| WebDAV 凭据 | kf_cloudcfg_acct/kf_cloudcfg_app (应用专属密码) 落 UserDefaults 明文; "口令不出本机内存"纪律仅覆盖备份加密口令, 文档口径需在 DEFERRED 补一句 |
| BackupStudioKit.rotateKey | 仅轮换固定文件名 zklock-backup.enc, 自定义命名备份不在轮换范围 |
| DestroyKit.destroyAll | 宣称"覆写 3 轮随机字节"实际是 plist 层逻辑等价 (注释已声明非密码学级), UI 文案与注释一致, 无误导但需知情 |
| BackupStudioKit.volumes | 记录卷 chars 估算 lines*60, 展示口径可接受 |

## 五、逐编号明细 (301–550, 250 行)

| 编号 | 创意名 | 状态 | 证据 (文件:行) |
|---|---|---|---|
| 301 | 剪贴板即建 | DONE | App/UI/CredentialStudio.swift:694 剪贴板来源条 clipSource |
| 302 | 摇一摇生成 | 舍弃 |  |
| 303 | 大号回显行 | DONE | App/UI/CredentialStudio.swift:164 MaskedDigits 逐位回显 |
| 304 | 重复值拦截 | DONE | App/UI/CredentialStudio.swift:749 + CredentialOrg:779 duplicatePwdValuesAnyLock |
| 305 | 老旧巡检 | DONE | CredentialOrg isStalePwd + CredentialStudio:1520 |
| 306 | 改造分屏 | DONE | App/UI/CredentialStudio.swift step3 新旧对照分屏 |
| 307 | 保存前 diff | DONE | CredentialOrg digitDiff + CredentialStudio step3 |
| 308 | 分段转述 | DONE | App/UI/CredentialStudio.swift:1578 4位分段复制 |
| 309 | 语音读码 | DONE | CredentialStudio StudioTTS.speakDigits 语音读码 |
| 310 | 别名字段 | PART | 无独立"别名"字段; 记录 Tab 展项沿台账 note/归属推断 |
| 311 | 同码引用卡 | ⚠DONE(占位约) | CredentialOrg:842 openCountInWindow 时间窗推断(约) |
| 312 | 常用短语条 | DONE | 第四十五批落: CredentialStudio step2 备注框上方横滑短语条 (仅白天/勿外传/长期有效), 点按**追加**不替换 |
| 313 | 停用必填原因 | DONE | 第四十五批落: CredDisableSheet 四选一 (疑似泄露/换码/人员变动/其他), 未选不可确认; 原因写运行日志 + SensitiveLedger, 只记条数不记口令明文 |
| 314 | 前缀混淆提醒 | DONE | CredentialOrg prefixConflict 前缀混淆行 |
| 315 | 命名建议轮播 | DONE | CredentialOrg 命名建议轮播 + FpStudio |
| 316 | 档案三行统计 | ⚠DONE(占位约) | CredentialOrg fpUseCount30d(约) + FpDetail 316 |
| 317 | 归属先行 | DONE | CredentialStudio navBar 归属先行拦截(317) |
| 318 | ? | 舍弃 |  |
| 319 | 重录继承 | DONE | CredentialStudio:2074 重录替代入回收站(319) |
| 320 | ? | ⚠DONE(占位约) | CredentialOrg fpAlarmLogCount(约) + FpDetail |
| 321 | ? | 舍弃 |  |
| 322 | 缺失提醒行 | DONE | CredentialsView 缺失提醒行(322) |
| 323 | 删除双签 | DONE | CredentialStudio:1780 fpDoubleSignCheck 双签 |
| 324 | 冗余横条 | DONE | CredentialsView:895 冗余横条(324) |
| 325 | 场景预设 | DONE | CredentialStudio:136 SceneDef 五场景 |
| 326 | ? | ⚠DONE(本地计次) | CredentialStudio:1649 用量刻度(326/335 约) |
| 327 | 租期重叠检测 | DONE | CredentialStudio:430 327 重叠检测 CredentialOrg |
| 328 | 口述卡 | DONE | CredentialStudio 大字口述卡(328) |
| 329 | 一句话文本 | DONE | CredentialStudio 一句话口令文本(329) |
| 330 | 装修黄条 | DONE | CredentialStudio:136 装修黄条(330) |
| 331 | 提前失效滑杆 | DONE | CredentialOrg:911 提前失效滑杆(331) |
| 332 | ? | ⚠DONE(约) | CredentialStudio 原码续期(332 约) |
| 333 | 首用回执 | ⚠DONE(约) | CredentialStudio/CredentialOrg firstUse 首用回执(333 约) |
| 334 | 过期打包清理 | DONE | 第四十六批落: 已过期组尾加"清理本组已过期 (N 条)", 不新造本机静默删除 —— 选中后交给现有停用流 (摘要 353 + 必填原因 313 + 回收站 364 + 锁端删除记待下发), 免得台账与锁端分叉 |
| 335 | 线性用量刻度 | ⚠DONE(约) | CredentialStudio:1649 线性用量刻度(335 约) |
| 336 | 截图警示 | MISS |  |
| 337 | 秒刻度细条 | ⚠DONE(锁端分钟级) | CredentialStudio:232 WindowBar + :2293(锁端1800s约)/:2412 秒级 |
| 338 | 单击即复制 | 不新增 | 第五十一批判定: 行内已有"复制当前码"按钮 (405 之后还带自清)。再加"整行单击即复制"要与既有的行点开详情抢手势, 收益是省一次点按、代价是误复制 —— 判不值得, 不做 |
| 339 | 绑定锁选择器 | MISS |  |
| 340 | 双码并排 | DONE | CredentialStudio:2412 双码并排(340) |
| 341 | otpauth 导入 | DONE | CredentialStudio:2349 otpauth 导入 + CredentialOrg 解析(341) |
| 342 | 换码微动效 | MISS |  |
| 343 | 独立口令组 | DONE | CredentialStudio:2301 独立口令组 + CredentialOrg.addTotp(343) |
| 344 | 粘贴建议条 | DONE | 第五十三批落: 回前台在四 Tab 顶部安全区出快捷条 (LockKeeperApp:605), 数据源 ClipboardCare:49 `suggestion`。状态**只在内存**且用 `changeCount` 判"还在不在" —— 不读剪贴板明文 (读会顶出系统"粘贴自…"隐私横幅), 也不落盘 (重启后那条自清任务已不存在, 再说"N 秒后清除"就是假话)。两态两按钮: 还在 → "再复制一次" (recopy, 重起窗口); 已被自清抹掉 → "回凭证页"。**口径偏离原案**: 创意写"点击直接进入粘贴", iOS 无跨 App 注入剪贴板焦点的能力 (要第三方键盘扩展, 本仓不做扩展 target), 故按钮只做"补复制/带回凭证页", 不写"已为你粘贴" |
| 345 | 参数小字标注 | DONE | CredentialOrg.totpParams 参数小字(345) |
| 346 | 静态备份码 | DONE | CredentialStudio:2323 静态备份码(346) |
| 347 | 编辑模式 | DONE | CredentialsView:1264 批量操作栏(347) |
| 348 | 统一延期 | DONE | CredentialsView extendAliases 统一延期(348) + CredentialOrg:379 |
| 349 | 批量移交 | DONE | CredentialsView 批量移交(349) CredentialOrg |
| 350 | 智能选取 | DONE | CredentialsView 智能选取(350) CredentialOrg.smartSet |
| 351 | 合包导出 | DONE | CredentialsView:1340 合包导出(351) + CredentialOrg:712 |
| 352 | 拖拽排序 | DONE | CredentialsView:734 拖拽排序(352) kf_cseq_ |
| 353 | 批量停用摘要页 | DONE | CredentialsView:1353 停用摘要确认(353) + CredentialOrg:419 |
| 354 | 归档区 | MISS |  |
| 355 | 双视图分组 | DONE | CredentialsView:29 双视图(355) CredentialOrg.groupMode |
| 356 | 循环全选 | DONE | CredentialsView 循环全选(356) |
| 357 | 前缀批量备注 | DONE | CredentialsView 批量备注(357) |
| 358 | 整理建议中心 | DONE | CredentialCenterView:605 整理建议中心(358) + CredentialOrg.advice |
| 359 | 三档预警 | DONE | CredentialOrg:506 三档预警通知(359) |
| 360 | 过期即归档 | DONE | CredentialsView:793 过期即归档(360) |
| 361 | 停用原因回溯 | DONE | 第四十八批落: CredentialOrg.markDisabled/disableMarkText 逐条便签 (kf_cdisrea_<mac>, 只留最近 200 条), 回显在回收站行 —— 台账停用后已无此条, 详情卡打不开, 便签是唯一留存; 非本 App 停用则不显示, 不编原因 |
| 362 | 复活检测 | MISS |  |
| 363 | 月历到期视图 | DONE | CredentialsView 月历(363) + CredentialOrg |
| 364 | 恢复窗口期 | DONE | CredentialsView:1696 恢复窗口(364) + CredentialOrg.withinRecoverWindow |
| 365 | ? | ⚠DONE(本地容错) | CredentialCenterView CredQueueView 三步步条(365 本地容错) |
| 366 | 月度清理任务 | DONE | LockKeeperApp onLaunch CredentialOrg.launchTick 月度任务(366) |
| 367 | 成员动态同步 | MISS |  |
| 368 | 延期催办文本 | DONE | 第四十六批落: 凭证行菜单对"7 天内到期"的条目出"生成延期提醒文本 (368)", 称呼取备注或成员名、无称呼则"您好"不编造姓名; 复制到剪贴板且**文本不含口令** |
| 369 | 遮蔽样式自选 | DONE | SecurityCenterView:595 遮蔽样式自选(369) |
| 370 | 贴近复蔽 | PART | 备案(DEFERRED 包7): 距离传感器无 App 级 API, 无法本地实现 |
| 371 | 切后台即糊 | DONE | SecurityCenterView:708 切后台即糊(371) |
| 372 | 摇一摇遁走 | PART | 备案(DEFERRED 包7): 摇一摇全局手势待接线, 冲突面待实测 |
| 373 | 限时可见 | DONE | SecurityCenterView:629 限时可见(373) |
| 374 | 录屏遮罩 | DONE | 第五十一批落: ScreenCaptureWatch (UIScreen.isCaptured + capturedDidChangeNotification, 用 screens.first 不用已废弃的 main), AppState.init() 装监听。遮在三处明文出口: 密码详情卡 (MaskedDigits 整格换提示)、ZOTP 内联卡、独立 TOTP 的当前码与下一码。**只换明文那一格, 不整页遮黑** —— 整页黑会让人以为 App 坏了 |
| 375 | 磨砂挡片 | DONE | SecurityCenterView:773 磨砂挡片(375) |
| 376 | 分享遮半 | DONE | SecurityCenterView:644 分享遮半(376) |
| 377 | 访客通道 | PART | 访客通道仅有 SecurityCenterView 开关+敏感成员隐藏键, 应用锁页"访客进入"入口未接(代码自注"待接线"), 过滤逻辑未在 Tab 视图落地 |
| 378 | ? | ⚠DONE(水印层降级) | SecurityCenterView:60 SecurityWatermark 常驻水印层(378 降级) |
| 379 | 双流水分段 | DONE | SecurityCenterView:906 双流水分段 + AuditLog(379) |
| 380 | 字段级 diff | DONE | SecurityCenterView:1138 字段级 diff(380) |
| 381 | 操作者头像 | DONE | AuditChain operator_ 字段 + SecurityCenterView(381) |
| 382 | 脱敏导出 | DONE | AuditChain exportJSON + SecurityAuditView 脱敏导出(382) |
| 383 | sudo 口令 | DONE | SecurityCenterView:1252 sudo 口令(383) |
| 384 | 三档计数过滤 | 舍弃 |  |
| 385 | 保留期策略 | DONE | AuditChain.purgeExpired(保留期, 本次修截断重封) + SecurityCenterView 385 区 |
| 386 | ? | DONE | AuditChain.verifyChain(哈希链, 本次补 id 单调防截断重放) |
| 387 | 维护回执 | DONE | 第五十二批落: MaintenanceLog (kf_maint_acts 滚动 8 条 + kf_maint_seen_at 水位)。记真空清理/归档/自动补发三类本机维护, 下次启动在设备页 Hero 卡下回一行, 点"知道了"按水位隐藏且**不删历史**。**口径偏离原案**: 创意写"上次退出期间", 本 App 无后台执行面 (包17: 免费账号无 BGTask/Widget target), 退出期间不会有动作 → 按"上次会话"实现并在注释与 UI 都这么写 |
| 388 | 敏感操作视图 | DONE | AuditChain SensitiveLedger + 消费点(AppIntents/ExportCenter/SecurityCenter)(388) |
| 389 | 递增冷却 | DONE | LockKeeperApp unlockAttempt 递增冷却(389, 本次接线) + SecurityCenterView 区 |
| 390 | 伪装密码 | DONE | LockKeeperApp inDecoy + DecoyShellView 伪装壳(390, 本次接线) |
| 391 | 胁迫码 | DONE | LockKeeperApp 胁迫码识别打标(391, 本次接线) + SecurityCenterView + AuditEvent.duress |
| 392 | 失败留痕 | DONE | LockKeeperApp kf_strace_* 失败留痕(392, 本次接线) + SecurityCenterView |
| 393 | 锁定时机档位 | DONE | LockKeeperApp scheduleBgLock 四档锁定时机(393, 本次接线) |
| 394 | 短时免验 | DONE | LockKeeperApp scheduleBgLock 免验窗口(394, 本次接线) |
| 395 | 救援码 | DONE | LockKeeperApp 救援码重置入口(395, 本次接线) + SecurityCenterView 生成/手抄 |
| 396 | 随机键位 | PART | SecurityCenterView:295 随机键位开关键(kf_slock_randkey)已设, 但应用锁键盘仍为单 TextField, 随机布局未消费该键 |
| 397 | 静默自检 | DONE(等价改挂) | 第六十四批落。**前提修正**: 创意写"跑 SQLite quick_check", 而本 App 库体在 Keychain + UserDefaults, 根本没有 SQLite → 不存在 quick_check 可跑。按拍板改挂三件等价的本地只读核对 (`SelfCheck.run`, DiagKit 末): ① 库体哈希比对 ② 审计链逐条重算 (386/402) ③ JSON 回环 + 台账计数 (750)。解锁后自动跑一次 (`LockKeeperApp` 的 appUnlocked onChange), 异常才出声; 诊断页有「本机库体自检 (397)」栏 + 立即自检按钮, 栏底明写"这不是 quick_check, 也不重建索引" |
| 398 | 会话信息页 | DONE | LockKeeperApp kf_sses_* 会话写入(398, 本次接线) + SecurityCenterView 会话区 |
| 399 | 三级销毁 | DONE | SecurityCenterView:1238 三级销毁(399) |
| 400 | 销毁备份闸 | DONE | SecurityCenterView runDestroy 备份闸(400) + DestroyKit.backupGatePass |
| 401 | 覆写收尾 | DONE | AuditChain DestroyKit.destroyAll 覆写(401) |
| 402 | 离职清除 | DONE | AuditChain Offboard.markDeparted + SecurityDestroyView(402) |
| 403 | 按住清空 | DONE | SecurityCenterView holdClearControl 按住2秒(403, 本次修: 真清各锁回收站) |
| 404 | 销毁日期入名 | MISS |  |
| 405 | 剪贴板自清 | DONE | 第四十九批落: ClipboardCare 单一出口 (口令/OTP 复制后延时清, 默认 60s, 安全中心"防窥"区可选 关/30/60/300 秒)。只清"仍是当时那一串"(代数计数 + 内容比对), 加密凭证包与交接包刻意不清 (界面 footer 写明原因)。323 双签后的立即清空是另一码事, 保留 |
| 406 | 残留检查 | DONE | AuditChain checkResidue + SecurityDestroyView 残留复核(406) |
| 407 | 分区勾选导出 | DONE | BackupStudio zoneStep 分区勾选(407) + zoneCounts |
| 408 | 独立口令两遍 | DONE | BackupStudio:390 口令两遍 + 本次 549 同值提示 |
| 409 | 自描述文件名 | DONE | BackupStudioKit:31 fileName 自描述(409) |
| 410 | 按年分卷 | DONE | BackupStudioKit volumes 按年分卷(410) |
| 411 | 二维码搬运 | DONE | BackupStudio:470 QR 搬运 + qrImage(411) |
| 412 | 导出前体检 | DONE | BackupStudioKit preExportHealth(412) |
| 413 | 完成即分享 | DONE | BackupStudio:468 完成即分享(413) |
| 414 | 版本头标注 | DONE | BackupBundle.schema 文件头(414) + 预演页"备份 v(p.schema) → 当前 v5"(BackupStudio:623) |
| 415 | 名册单独导出 | DONE | 第五十九批落: `ExportKit.memberRoster()` 出 vCard 3.0 (FN / NICKNAME(备注名) / TEL;TYPE=CELL / CATEGORIES(分组) / NOTE(关系·主管理员·归档·代管·紧急联系·便签·关怀)), 空字段**不写空行**; 入口在成员中心右上角菜单"导出成员名册 (415)" → 面板里 ShareLink 一个 `Caches/exports/锁管家_成员名册_日期.vcf`。**名册刻意不含**: 锁 MAC、凭证 alias/批次、口令、`MemberExt.commonLocks` —— 搬整套数据是备份的职责, 名册只回答"家里有谁", 也正因为它少才适合发给家人线下核对。转义按 vCard 顺序 (反斜杠先转, 再 ; , 换行) —— 顺序颠倒会把 `\;` 二次转义成 `\\;` |
| 416 | 后台续写 | MISS |  |
| 417 | 恢复预演 | DONE | BackupStudioKit:420 preview + RestoreWizard 预演(417) |
| 418 | 三合并策略 | DONE | BackupStudio:648 三策略(418) |
| 419 | 冲突裁决列表 | DONE | BackupStudio:716 冲突裁决 + BackupStudio.conflicts(419) |
| 420 | 口令即馈 | DONE | BackupStudioKit decryptAny 口令即时反馈(420/453) |
| 421 | 恢复回滚点 | DONE | BackupStudioKit makeRollbackPoint/undoLastRestore + BackupStudio:84 撤销行(421)。第五十七批补洞: 快照旧实现只收六个分区,   **按 mac+记录行 oid / mac+凭证 alias 或批次 / 成员 id / 备份文件名 挂钩的用户内容** (186 备注、188 标旗、361 停用原因、352 排序、回收站 kf_cbin_、433 备注、437 复核钉、MemberHub 的档案/生日/徽章/移交/借用/认领/家务窗/离任键) 恢复后被顶掉、撤销也回不来 → 加 `rollbackFamilies` 前缀族清单 + `extras`(原样字节 base64, 可选字段所以旧快照仍解得开)。撤销**只回写快照里有的键、不删快照之后新攒的键** (删除它们就是把回滚变成抹掉更新的数据), 确认框文案同步写明这条边界 |
| 422 | WebDAV 恢复列表 | DONE | BackupStudioKit listRemote 哈希先行(422, 本次硬化) |
| 423 | 哈希先行 | DONE | BackupStudioKit:498 static func verifyChecksum 定义 + BackupStudio:983 导入前校验调用 (行号经 tools/citecheck.js 复核) |
| 424 | 升级链 | DONE | BackupStudioKit:461 upgradeChain(424) |
| 425 | 差异报告 | DONE | BackupStudioKit compare + BackupStudio:782 差异报告(425) |
| 426 | 扫码恢复 | PART | 文案挂 411: 恢复页/迁移页提示"相机扫码"(BackupStudio:473/1280)但相机扫码 UI 未实现, NSCameraUsageDescription 仅 522 侧 |
| 427 | 分区选择性恢复 | DONE | BackupStudio:641 分区反选 + prune(427) |
| 428 | ? | ⚠DONE(BGTask择机) | BackupStudio:206 充电备份开关 + registerChargeBackup(428 ⚠择机) |
| 429 | 新鲜度提醒行 | DONE | BackupStudioKit:53 新鲜度 + BackupStudio:71 黄条(429) |
| 430 | 滚动保留 | DONE | BackupStudio:191 滚动保留 + pruneRemote(430) |
| 431 | 导出前清理联动 | DONE | BackupStudio:435 清理联动 + cleanExpired(431) |
| 432 | 体积与覆盖列 | PART | 第四十九→五十批: 体积 + 文件时间已出 (文件属性), 内容概览出"备份于…·N 台锁·M 条凭证"。**"记录起止覆盖列"做不到** —— BackupBundle 只有 devices/ledger/members/globals, 本机备份根本不含记录日志, 出这一列就是编。密文包标"需口令"不猜 |
| 433 | 重命名备注 | DONE | 第四十九→五十批落: 行长按/右键菜单"加备注 / 改名显示", 存 kf_bk_note (键=文件名); **只改显示**, 文件名/内容/哈希短码都不动, 列表仍按文件名排 |
| 434 | 哈希短码 | DONE | BackupStudioKit:495 shortHash + LocalFilesView(434) |
| 435 | 算法参数标注 | DONE | 第五十八批落: `BackupStudio.algoNote(url)` 只读**文件头 4KB** 的信封 JSON (不解密、不要口令), 逐文件标出 `alg · kdf alg · iter 轮`；三档分开: 认得出信封 / **明文包 (没有信封, 含 `"devices":` 所以另说一档, 不混进"未能识别")** / 未能识别 (橙色)。工作室首页那枚徽章的文案本来就写着"换算法后旧文件各自标注 (37)" —— 此前全仓没有逐文件标注, 那句话是空头承诺, 现在真了, 并在徽章文案里指明去哪儿看 (435)。解析逻辑按 JSONEncoder 的实际键序 (`v,alg,kdf{alg,iter,saltHex},…`) 用 Node 复算过三种输入 |
| 436 | 演练恢复 | DONE | BackupStudio dryRunSel/dryRun(e) 演练(436) |
| 437 | 备份复核钉 | DONE | 第五十五批落: `BackupStudioKit` 437 段 —— `kf_bk_pin`(键=**真实文件名**，433 的别名会被改所以不能当身份) / `kf_bk_pin_seen`(记的是**那一个复核日**，挪到新一天会重新催)。入口在"本地备份文件"行菜单"设复核日期 (437)"(DatePicker)，未到日只在行内小字存档，**到日才**在设备页 Hero 卡下催一行 (含已过天数)。两条自限: ① 只列目录里真存在的文件，文件删了键残留也不催；② 日期串解不出来就不催，不猜。**口径偏离**: 创意写"提醒行"即可，这里把"知道了"做成按日水位而不删钉 —— 删了就把用户自己钉的日期弄丢了 |
| 438 | 三通道向导 | DONE | BackupStudio:1039 三通道向导(438) |
| 439 | 并排进度对看 | DONE | BackupStudio:1091 双机并排进度(439) |
| 440 | 差异补传 | DONE | BackupStudio:1117 差异补传 + diffHint(440) |
| 441 | 多锁逐把确认 | DONE | BackupStudio:1096 逐把确认 + restore meta 随锁(441) |
| 442 | 首验清单 | DONE | BackupStudio:1138 首验清单(442) |
| 443 | 直连重激 | DONE | BackupStudio:1175 首验含 443 直连重激活项 |
| 444 | 迁移后核对表 | DONE | BackupStudio:782 迁移后核对表(444) |
| 445 | 中断续迁 | DONE | BackupStudio:1232 中断续迁 resumeCard(445) |
| 446 | 旧机退役横幅 | DONE | BackupStudio:232 旧机退役横幅(446) |
| 447 | 分阶段迁移 | PART | 迁移向导只做 445 中断续迁; "先迁凭证+成员, 记录分区次日再补"的阶段化/向导阶段记录未做 |
| 448 | 启动自检黄条 | DONE | BackupStudioKit:634 runStartupSelfCheck + RootView 黄条(448) |
| 449 | 魔数先行 | DONE | BackupStudioKit:419 魔数先行(449) + 449 注释 |
| 450 | 抽样解密 | DONE | BackupStudioKit preview 抽样 5 条(450) |
| 451 | 空洞日期检测 | DONE | App/Core/DiagKit.swift 数据健康 451 |
| 452 | 孤儿扫描 | DONE | App/Core/DiagKit.swift 748/452 孤儿扫描段 |
| 453 | 失败分层定位 | DONE | BackupStudioKit 失败分层注释 + 下载 453(453) |
| 454 | 双备份对比 | DONE | BackupStudio:1332 双备份对比(454) |
| 455 | 指令重放摘要 | DONE | 第四十七批落: DiagnosticsView cmdTrace 取内存日志中 `命令名 -> rc=N` 行的前 20 条; 行内只有命令名与结果码, 不含帧/密钥/口令 |
| 456 | 只读副本浏览 | DONE | BackupStudio:672 只读副本(456) |
| 457 | 首字符号头像 | DONE | MemberCenterView 首字符号头像(457) |
| 458 | 角色三档 | DONE | MemberHub:44 角色三档(458) |
| 459 | 成员 360 卡 | ⚠DONE(并入台账推断) | MemberHub activity(459 ⚠并入台账推断) |
| 460 | 归档不蒸发 | DONE | MemberHub archived 归档不蒸发(460) |
| 461 | 备注名 | DONE | MemberCenterView 备注名(461) + MemberHub.remark |
| 462 | 重复合并 | DONE | MemberCenterView 重复合并(462) |
| 463 | 建档向导 | DONE | MemberCenterView 建档向导(463) |
| 464 | 常用锁字段 | DONE | MemberHub commonLocks(464) |
| 465 | 紧急联系行 | DONE | MemberHub emergency(465) |
| 466 | 活跃度排序 | ⚠DONE(并入台账推断) | MemberHub 活跃度排序(466 ⚠并入) |
| 467 | 所有权移交 | 改判(撤区) | 2026-10-09 拍板撤掉「待接受区」: 队列读侧与接受/拒绝 UI 一直在, 但**没有任何发起方** (凭证页移交走 `CredentialOrg.batchTransfer` 直接改本机台账), 那个区永远显示"暂无" → 属假开关族, 删。已移除 `MemberHub.MemberTransfer`/`pendingTransfers`/`addTransfer`/`acceptTransfer`/`rejectTransfer` + `MemberCenterView.pendingSection` + 回滚族里的 `kf_mtransfer`; deadscan 零引用由 7 降到 6。**移交语义不变**: 仍是本机台账直接改归属 (锁端本无归属字段)。顺带补了一条真缺陷: `batchTransfer` 的注释写着"各写一条本地记录"而代码只改 owner **没有任何快照** (撤掉待接受区后它就是唯一移交入口) → 现在每条移交都 `snapshot(note:"移交 → X")` 落历史, 注释与实现重新对上 |
| 468 | 代管标记 | DONE | MemberHub proxy 代管(468) |
| 469 | 紧急管理员 | DONE | MemberHub emergencyAdmin(469) |
| 470 | 权限矩阵 | DONE | MemberCenterView 权限矩阵(470) |
| 471 | 到期收回建议 | DONE | 第四十八批落: CredentialOrg.advice 新增成员级规则 —— 某成员名下临时码"**全部**过期"才催 (部分过期不催), 最多列 3 位; 指引走按成员视图 (355) + 多选停用 |
| 472 | 借用登记 | DONE | MemberHub MemberBorrow 借用(472) |
| 473 | 授权来源统计 | DONE | MemberHub 授权来源统计(473) |
| 474 | 退出处置向导 | DONE | MemberHub 退出处置(474) |
| 475 | 家庭便签 | DONE | MemberHub note 便签(475) |
| 476 | 归属图谱 | DONE | MemberHub 归属图谱(476) |
| 477 | 往返上下文 | DONE | BackupStudioKit:409 来源信息(477) |
| 478 | 打印口述卡 | DONE | ExportCenter 478 口述卡打印 |
| 479 | 长辈模式 | DONE | MemberHub 长辈模式 + CredentialsView:401 + SettingsView(479) |
| 480 | 孩子码关怀行 | DONE | MemberCenterView 孩子码关怀行(480) + MemberHub.careText |
| 481 | 本周轮值 | DONE | MemberHub 本周轮值 + DeviceHomeView(481) |
| 482 | 家庭会议摘要 | DONE | MemberCenterView 家庭会议摘要(482) |
| 483 | 家政周期预设 | ⚠DONE(整段窗降级) | MemberCenterView 家政窗(483 ⚠整段窗降级) + HouseWin |
| 484 | 访客欢迎语 | ⚠DONE(归属推断) | MemberHub welcome 欢迎语(484 ⚠归属推断) |
| 485 | 生日提醒行 | DONE | MemberCenterView 生日提醒行(485) + DeviceHomeView |
| 486 | 代际完成页切换 | DONE | MemberHub/MemberCenterView 完成页切换(486) |
| 487 | ? | DONE | CredentialOrg:133 kf_chist_ 快照 + CredentialStudio 落档(487) |
| 488 | ? | ⚠DONE(自动点2席) | CredentialOrg:384 批量前 auto 快照 2席(488); 备份还原前打点已随 421 rollback 覆盖 |
| 489 | 修订着色 | DONE | CredentialCenterView:417 逐字段 diff 着色(489) |
| 490 | 摘要句流 | DONE | CredentialCenterView 人话摘要句流(490) |
| 491 | 版本配额 | DONE | CredentialOrg quota 配额滚动(491) + SettingsView |
| 492 | 同库同密 | DONE | CredentialOrg 注释 492 同库同密不进备份 schema |
| 493 | 只读回看 | DONE | CredentialCenterView 只读回看(493) |
| 494 | 删除前快照 | DONE | CredentialOrg snapshotBeforeDelete(494) |
| 495 | 星标版本 | DONE | CredentialOrg 星标豁免(495) |
| 496 | 恢复即新版本 | DONE | CredentialCenterView:444 恢复即新版本(496) CredentialOrg.restore |
| 497 | 30 天自动清 | DONE | CredentialOrg sweepReclaim + onLaunch + CredentialCenterView(497) |
| 498 | 来源过滤 | DONE | CredentialCenterView:99 来源过滤(498) |
| 499 | 还原冲突副本 | DONE | CredentialCenterView:210 副本还原(499) |
| 500 | 容量头行 | DONE | CredentialCenterView:82 容量头行(500) |
| 501 | 级联预告 | DONE | CredentialCenterView:134 级联预告整组还原(501) |
| 502 | 彻底删除双验 | DONE | CredentialCenterView:148/267 彻底删除双验(502) |
| 503 | 回收站搜索 | DONE | CredentialCenterView:120 回收站搜索(503) |
| 504 | 还原即下发 | DONE | CredentialCenterView:245 还原即重新下发(504) |
| 505 | 清空计入整理 | DONE | CredentialCenterView:281 清空计入整理(505) |
| 506 | 误删撤销条 | DONE | CredentialsView armUndo 撤销条(506) |
| 507 | 备份状态角标 | DONE | DeviceHomeView:453 备份角标(507) + badgeState |
| 508 | 写入回执动效 | DONE | LockKeeperApp writeReceipt 回执(508) + CredentialStudio flashReceipt |
| 509 | 双向天数行 | DONE | BackupStudio trustHeader 双向天数行(509) |
| 510 | 待下发横条 | DONE | CredentialsView:227 待下发横条(510) + LinkSense |
| 511 | 数据里程碑 | DONE | BackupStudioKit:818 数据事件(511) |
| 512 | 主权声明 | DONE | BackupStudio:50 数据主权声明(512) |
| 513 | 固件本地清单 | DONE | Sheets/BatteryCare 本地固件包导入(513, 包4) |
| 514 | 离线帮助 | DONE | HelpCenter:96 本地手册(514) |
| 515 | 分步表单 | DONE |  |
| 516 | 纯数字键盘 | DONE |  |
| 517 | 粘贴来源条 | DONE(并入 301 来源条: 清除机制) |  |
| 518 | 草稿续填 | DONE |  |
| 519 | 错误字段定位 | DONE |  |
| 520 | 时长快捷项 | DONE |  |
| 521 | 二次输入确认 | DONE |  |
| 522 | 相机取号 | DONE |  |
| 523 | 听写备注 | DONE |  |
| 524 | 类型分段计数 | DONE | CredentialsView:144 分段计数(524) |
| 525 | 首字索引条 | DONE | CredentialsView 首字索引条(525) |
| 526 | 置顶凭证 | DONE | CredentialsView:730 置顶(526) + CredentialOrg.isStarred |
| 527 | 智能列表 | DONE | CredentialsView:364 命名智能列表(527) |
| 528 | 三态分组头 | DONE | CredentialsView:775 三态分组头(528) |
| 529 | 组尾统计行 | ⚠DONE(台账推断约) | CredentialsView:783 组尾统计"约"(529 台账推断) |
| 530 | iPad 键盘快捷键 | DONE | AccessibilityView:188 键盘快捷键(530) |
| 531 | 最近搜索词 | DONE | CredentialsView:540 最近搜索词(531) |
| 532 | 搜索兜底动作 | DONE | CredentialsView 搜索兜底动作(532) |
| 533 | 待下发清单页 | DONE | CredentialsView 待下发清单(533) + LinkSense |
| 534 | ? | ⚠DONE(前台检测降级, LinkSense.autoReconnectTick/onPreconnectDone) |  |
| 535 | 同步回执条 | DONE | CredentialsView:229 同步回执(535) + LinkSense.lastReceipt |
| 536 | 失败三分类 | DONE | DiagnosticsView:167 三分类(536) + LinkSense.classifyFailure |
| 537 | 下拉重扫 | DONE | 第五十六批落: 设备页 ScrollView `.refreshable` → `rescanPull()` (DeviceHomeView), 走现有 `LinkSense.scan` (startScan/stopScan 成对, **不连接、不下发**)。三种结果说实话: 蓝牙没开 / 扫到 (报 dBm 数值 + `noteScannedRssi` 推给信号格) / 4 秒超时没扫到 ("走近一点再下拉", 不假装刷新成功)。`noteScannedRssi` **只动 lastRssi 不动 linkState** —— 扫到广播 ≠ 已连接。127 静默模式关的是"自动"回连/预握手, 用户主动下拉属手动动作 (与"手动圆盘照常"同一口径), 故不看 DiagFlags.silent |
| 538 | 按锁排队 | DONE | CredentialsView 按锁排队(538) kf_cqueue_ |
| 539 | ? | ⚠DONE(占位) | LinkSenseKit:363 高成功率时段占位(539 ⚠) |
| 540 | RSSI 三格 | 舍弃 |  |
| 541 | ? | ❌ |  |
| 542 | 时间窗刷选 | DONE | DiagKit 时间窗刷选(542) |
| 543 | 实体跳转 | DONE | DiagKit:167 实体跳转(543) |
| 544 | 一键诊断报告 | DONE | DiagKit 一键诊断报告(544) |
| 545 | 能力自检清单 | DONE | DiagKit 能力自检(545) |
| 546 | 表级体积 | DONE | DiagKit:355 表级体积(546) |
| 547 | 异常退出档案 | DONE | DiagKit:311 异常退出档案(547) |
| 548 | 导出格式三选 | DONE | ExportCenter:367 三格式导出 + 脱敏开关(548) |
| 549 | 口令复用检测 | DONE | AuditChain PwReuse + SecurityCenterView 胁迫码冲突 + BackupStudio:396 应用锁同值提示(549, 本次补提示) |
| 550 | 首启承诺页 | DONE | Onboarding:211 首启承诺页(550) |
