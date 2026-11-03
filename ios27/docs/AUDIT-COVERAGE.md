# 审计覆盖图（AUDIT-COVERAGE）

> 这份文件回答一个问题：**这套 App 到底哪些地方被真正查过了，哪些没有。**
> 每一行都能点到具体的轮次报告；没有点到的，就是没查过 —— 不假装。
>
> 快照时间：2026-11-01（第二轮地毯审计结束时）。
> 轮次报告：`docs/AUDIT-{A..G}-*.md`（首轮四路并审）+ `docs/AUDIT-ROUND-1..85.md`（本段 55 轮增量）。
> 待接功能清单：`docs/RESERVED.md`。
> **怎么找缺陷**（方法论与判据）：`docs/AUDIT-METHOD.md`。
> **这次审计做完了吗、还剩什么**：`docs/AUDIT-CLOSING.md`。

## 1. 覆盖矩阵

| 子系统 | 主要文件 | 查了什么 | 证据（报告） | 状态 |
|---|---|---|---|---|
| **协议层** | `ZKProtocol` `ZKCmdBuilder` `StatusParser` `ZOTP` `PidMap` `AESKit` `HexKit` `ZipKit` `Attribution` | 40 条命令帧逐字节 · NIST AES · 状态/日志解析 · 三种帧头 · 广播解析 · ZOTP 冻结时钟 · PID 能力 · 网关/钥匙串应答 · 归属推断 · 时间基准 · rc 文案 · inflate · 严格 hex | ROUND-2/4/5（金标套件 16 条，**CI 真跑 0 失败**） | ✅ 已验证执行 |
| **存储与台账** | `Store` `StoreLedger` `StoreKeychain` `StoreState` `MobileKeyService` `CredentialStudioStores` `RecordSearch` | 明文口令进 Keychain 与回填 · 删除时清副本 · 空壳模式读/写隔离（列表 + 单条 + 写路径）· 回收站/历史保留上限 · 备注/旗标/处置覆盖层 | ROUND-23/27/28/29/30；SEC-01 系列（AUDIT-F） | ✅ 已查（含 5 轮补齐） |
| **备份与恢复** | `BackupCanonical` `BackupStudioKit` `BackupBundle` `CryptoBox` `BackupKit` | 规范化与校验和（新旧两套语义）· schema 升级 · skey/pin 形状校验 · 合并只增不删 · 冲突裁决 · 导出→解析→恢复往返 · 校验和二次确认 | ROUND-17/18（`BackupRoundTripTests` 8 条） | ✅ 已验证执行 |
| **通知** | `CredentialOrgState`（排期队列）`CredentialOrg.addCalendar` `BatteryCare` | 删旧/排新/取消串行化 · 排程必须可 await · 空壳清整族 · 退出空壳重建 | ROUND-3/18/20/21 | ✅ 已查 |
| **BLE 链路** | `BLEService` `BLEDelegates` `LockService*` `HardwareService` `DFUKit` | 帧归属路由（两服务共用连接）· 重连/恢复标识 · DFU 包校验与降级闸 · 写命令不重发 · 超时与陈旧定时器 | ROUND-3/6/16（SEC-15/G-12/D-23） | ✅ 静态已查；**真机未验** |
| **设计系统** | `V7Tokens` `V7Components` `V7Extras` + 130 余个界面文件 | 浅色/深色双取值 · 对比度 · Dynamic Type · 减少动态 · 触达 44pt · 装饰图标 · 假 chevron · 死令牌 24 个 · 密度三档 · 圆角三档 | ROUND-1（AUDIT-D）+ ROUND-7/12/13/14/15/16 | ✅ 已查（数值层）；**观感未验** |
| **安全与权限** | `SecretStore` `CryptoBox` `AppLock` `LockKeeperApp`（深链）`QuickActions` | Keychain 生命周期 · 空壳/胁迫码 · 失败计数持久化 · 深链切换确认 · 剪贴板 · 帧脱敏 · CSV/vCard 注入 · 备份明文 · 隐私清单 | AUDIT-F（SEC-01..32）+ ROUND-8/10/11/24/26 | ✅ 已查 |
| **交付与 CI** | `.github/workflows/ios27.yml` `Gates/*` `docs/*` | 22 道闸门 · 正控 · CI 逐步骤证据（`build_ok`/`archive_ok`/`test_ok`）· 金标在 CI 真跑 · 文档闸门数对账（4 个文件） | ROUND-2/4/19/25/26 | ✅ 已查 |


### 1.1 第二轮地毯审计新增的**缺陷类别**（ROUND-31..85）

前面那张表按"子系统"组织；这里按**缺陷形态**再列一遍 —— 因为同一形态会在多个子系统里重复出现，
按形态扫比按子系统扫更容易抓全。

| 形态 | 典型例子 | 轮次 |
|---|---|---|
| **写路径误用展示层过滤器** | 空壳模式下写回收站/历史/备注 → 整表被清空 | 23 / 28 / 29 |
| **单条读取器缺过滤**（列表有、单条没有） | `member(id)` / `dongle(mac)` / `gateway(mac)` | 30 |
| **清理不彻底**（键删了、副本还在） | `delPwd` 不清钥匙串口令 · 删设备不清回收站/快照密钥 | 27 / 47 |
| **清了不重建** | 空壳清通知后，退出空壳提醒永久消失 | 20 / 21 |
| **旁挂表不进备份** | `kf_member_ext` / `kf_calert_` / `kf_cstar_ui_` / `kf_cseq_` | 44 / 48 / 65 / 66 |
| **字段存在但 canonical 不 emit** | 同上四族：只改结构体 = 功能静默不生效 | 52 |
| **成对调用缺异常路径复位** | `keepingAwake(true)` 末尾复位，抛错则屏幕常亮 | 81 |
| **「停止」没有 cancel** | 自动开锁轮询「彻底停止」其实每 2 秒醒一次 | 82 |
| **`Task.isCancelled` 无人 cancel** | 配网链的「已中止」分支永不触发 | 83 |
| **空态掩盖失败态** | 读不到备份目录 → 显示「还没有备份」 | 84 |
| **只有时间上限没有条数上限** | 电池采样 90 天无条数封顶 | 85 |
| **未来时间戳钉死判断** | 冷却永久生效 · 连接时间永不更新 | 76 / 77 |
| **文案承诺 ≠ 实现** | 「最近一条」按别名排 ·「2 小时内到期」含已过期 ·「再开一次」只跳转 | 31 / 78 |
| **安全披露未展示** | 自动开门风险文案注释写「强制展示」，实际零引用 | 80 |
| **注释里的承诺没有实现**（元类） | 死声明 6 处 · 幽灵开关 2 处 · 幽灵警告 1 处 · 假队列 · 假索引 | 32/35/42/45/49/61/72 |

**这张表本身是这次审计最有复用价值的产出。** 每一条都可以被翻译成一条闸门判据
（其中 8 条已经落成 `privacy` / `a11y` 的具体规则）。

## 2. 自动化保证（当前）

```
本地：node Gates/allgates.js  -> 29 道闸门全部通过
      其中 privacy 已扩到 21 条判据（第 13–21 条是本段新增）
      a11y 新增第 ⑥ 条（下限令牌不得当固定尺寸）
测试：8 个测试文件 / 317 条断言（金标 + 安全回归 + 并发 + 时基 + 备份往返 + 格式化一致性）
CI  ：build（xcode-27，BUILD + ARCHIVE + errors=0）· golden（iOS 27 模拟器真跑，72+ tests / 0 失败）
```

注意：闸门数现为 **22**（第 21 道 `reserved` 是新增的闸门文件）；`privacy` / `a11y` 则是在已有闸门里加判据。
闸门数对账由 `Gates/workflow.js` 盯着 6 个文档。

## 2.5 逐文件审计状态（2026-11-01 地毯审计后）

判据：**一个文件算"已审"，当且仅当它的文件名出现在某轮 `AUDIT-*.md` 里**。
这条判据可以机械计算（`App/` 下 147 个 `.swift` 的文件名 vs 全部报告正文的差集）。

### 本轮已专门审过、且**未发现缺陷**的文件（结论如实记录，不假装有产出）

| 文件 | 行数 | 轮次 | 结论 |
|---|---:|---|---|
| `RecordSearchQuery.swift` | 74 | 116 | 时基/偏移/stride 边界均正确 |
| `StatusParser.swift` | 217 | 116 | 字节偏移、`intHex`/`leHexToU32` 语义正确 |
| `Attribution.swift` | 80 | 116 | 与 `StatsKit.openTypes` 一致 |
| `Reading.swift` | 104 | 117 | `FieldRow` 是纯展示行，不受 44pt 约束 |
| `DefendService.swift` | 50 | 123 | 半秒单位、枚举 rawValue、失败不落盘三项均正确 |
| `BackgroundGuard.swift` | 35 | 124 | `expirationHandler` 在 main 线程，无竞态 |
| `AuditChain.swift` | 43 | 124 | 头注已自我更正 DestroyKit 的不实声明 |
| `HeroStats.swift` | 23 | 128 | 空集合回退全开 + 白名单过滤正确 |
| `RecordModels.swift` | 32 | 128 | 仅 `Rec` 结构定义 |
| `LockGuard.swift` | 31 | 122 | 五枚开关的处置已在头注写明理由 |
| `HouseholdParts.swift` | 355 | 133 | **发现缺陷**（四态枚举被写成二分支） |
| `KeysBits.swift` | 299 | 131/132 | **发现缺陷**（命中区 32pt、重复修饰符） |
| `ToastCenter.swift` | 78 | 118 | **发现缺陷**（`transition` 无减弱动态守卫） |
| `PidMap.swift` | 55 | 122 | **发现缺陷**（未知 pid 兜底文案撒谎） |
| `TimeFormat.swift` | 75 | 117 | **发现缺陷**（跨年组头只显示月日） |
| `DateFormats.swift` | 84 | 125/126 | **发现缺陷**（4 处未钉公历） |
| `WeekCal.swift` | 66 | 120 | **发现**：`kf_week_start` 无 UI 写入点（已登记 RESERVED） |
| `BatteryCare.swift` | 226 | 136 | **发现缺陷**（低电缓存从不作废） |
| `HouseholdRoster.swift` | 294 | 135 | **发现缺陷**（「23–24 点」不存在的小时） |
| `RecordSearchBuild.swift` | 135 | 139 | **发现缺陷**（跨锁时间线静默吞掉无时刻的行） |
| `EngineHost.swift` | 35 | 140 | **发现缺陷**（冷启动点通知动作丢失） |
| `DoorLayout.swift` | 83 | 141 | **发现缺陷**（`move(by:)` 只对 ±1 正确） |
| `LockStats.swift` | 332 | 137 | **发现缺陷**（`isSleeping` 缺未来时间戳保护） |
| `AndroidPair.swift` | 66 | 142 | 无代码缺陷；**更正了一处误导性注释**（指向一条不存在的待办） |
| `BLETypes.swift` | 67 | 142 | 无缺陷（UUID / 错误码 / 错误包装均正确） |

### 尚未专门审过的文件（差集，13 个）

```
AndroidPair.swift  BLETypes.swift  BatteryCare.swift  DoorLayout.swift
EngineHost.swift   HouseholdRoster.swift  LockStats.swift
RecordSearchBuild.swift
```

> 注：`HouseholdParts` / `KeysBits` / `DoorLayout` / `ToastCenter` / `HeroStats` / `RecordModels`
> 在本轮已审并记录（见上表），但它们的文件名只出现在**这一节**，所以机械差集仍会列它们 ——
> 这正是"报告里没写文件名"导致指标失真的例子。**上表是本轮之后的事实来源。**

## 3. 明确**没有**覆盖的部分（不要当成已验证）

| 项 | 为什么没覆盖 | 谁能验 |
|---|---|---|
| 真实渲染与浅色主题观感 | 本机 Windows 无 SwiftUI 渲染；DesignLab 只是近似 | 真机/模拟器人眼 |
| 手势手感、触觉反馈 | 需要真实触屏与 Taptic Engine | 真机 |
| BLE 回执、指纹录入、DFU 实刷 | 需要真实门锁与固件 | 真机 + 锁 |
| WebDAV 真实链路 | 需要真实服务器 | 真机 + 服务器 |
| 出口合规（`ITSAppUsesNonExemptEncryption`） | 需法律/合规判断 | 人 |
| iPad / 横屏 | 产品决定锁竖屏 | 产品 |
| 钥匙串单测 | 未签名测试宿主无 entitlement，CI 上 skipped | 签名环境 |

## 4. 怎么用这份图

- 想改某个子系统 → 先看它那一行的报告，那里写着**为什么这么做**（很多决定与反例都在注释里）；
- 想判断"能不能发" → 看 §3；那里列的是**没验的**，不是"应该没问题"；
- 想加新闸门 → 看 `docs/ARCHITECTURE.md` §5 的 29 道判据与正控清单，新闸门必须自己先做正控。
