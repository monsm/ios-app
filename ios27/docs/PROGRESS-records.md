# PROGRESS — Records 域（台账）

任务卡 task-2。写作用域：`ios27/App/Features/Records/`（未触碰 Design/、Shell/、他人 Features/）。

## 文件清单

| 文件 | 行数 | 是什么 |
|---|---|---|
| `RecordsModels.swift` | 372 | 纯逻辑层：检索词解析 / 筛选 / 日分组 / 近 7 日计数 / CSV / vCard / 上周小结 / 本机覆盖层 / 跨屏上下文 / 锁内日志装载 |
| `RecordsScreen.swift` | 463 | 台账 Tab 根：页头 + 检索面板 + 筛选 chip + 近 7 日刻度 + 按自然日分组的时间线 |
| `RecordDetailScreen.swift` | 332 | 一条记录的全字段面：时刻 / 归属 / 告警处置 / 备注标旗 / 同一天上下文 / 三个回到时间线的出口 |
| `RecordExportScreen.swift` | 401 | 导出：单条记录分享卡（ImageRenderer 出 PNG）/ 按天勾选 CSV / 成员名册 vCard / 上周小结复制 |

## 每屏一句话

- **RecordsScreen** —— 把锁内日志读成一本可检索的仪器台账：检索 + 筛选 + 近 7 日刻度 + 日分组时间线，点行带上下文进详情。
- **RecordDetailScreen** —— 一条记录的全部可核对字段，加上告警处置留痕与备注标旗，底部三个出口真的回到时间线。
- **RecordExportScreen** —— 三件真导出：360×640 记录卡出 PNG 走 ShareLink、按天勾选出 CSV、成员名册出 vCard。

## 数据来源

- `RecordsSource.load(mac:lockName:members:)` → `DB.readLogs(mac)`（`kf_logcache_<mac>`，≤300 条、按 `idxRaw` 去重）
- 时刻：`log.lockTime` 是协议秒（基准 2010-01-01），经 `ZKProtocol.protoSecondsToUnix` 转本地毫秒；`lockTime == 0` = 锁端没读到时钟，**不进时间线**，单独计数并如实播报
- 行身份：`mac#idxRaw`（与备注 / 标旗 / 处置 / 导出共用同一份）
- 读取时间戳：`kf_logsync_<mac>`（毫秒），读写都经 `DB.normalizeMac`

## 已接真数据

- 台账条目、告警分级（7/10/13/224）、开门类型（11/16/17/19）
- 上次读取时刻、读取后写回时间戳
- 备注 / 标旗 / 处置（进程内 `RecordsOverlay`，跨屏共用）
- CSV / vCard / 上周小结文本生成
- 分享卡 PNG（`ImageRenderer`，scale 2）

## TODO(engine)

| 字段 / 能力 | 现状 | 需要什么 |
|---|---|---|
| `read()` 的 cmd16 翻页 | 只装载缓存 + 写时间戳，未真的连 BLE 拉取 | `ensureConnected` → `getLogs(orderType:0, startIdx:, pageSize:5)`，最多 20 页 100 条，每页落 `kf_logcache_`；失败回退缓存并播报 |
| `LedgerEntry.owner`（归属人） | 只在「单成员家庭」时给出，多成员一律留空 | 需重写 `Attribution` 的「日志 × 密码/指纹/临时码台账」交叉推断；锁端日志只有类型与序号，没有凭证槽位 |
| `RecordExportRow.hex`（协议帧） | 恒空串 | 缓存层需存原始帧 hex |
| `MemberVCard` 的 TEL / NOTE | 只写 FN / ROLE / NOTE(凭证数) | 电话与备注在 `kf_member_ext`，接上后补 |
| `RecordsOverlay` 落盘 | 进程内存储，重启即失 | `kf_roverlay_`（备注/旗标）+ `kf_rdispo`（处置结论 + 时刻），删设备时按族清除 |
| 深夜时段 / 工作日周末 / 告警类型多选 | 未做 | 需锁端日志补「时刻小时」以外的日型与告警细分判据；现有 `LedgerEntry` 只有 `tone` 三档 |
| 锁内未回时刻的行 | 只计数并报数，不上时间线 | 若要展示，需一个「时间未知」独立组（旧版用 `__none` 键） |

## 闸门

`swiftparse` / `tokens` / `a11y` / `motion` / `glass` / `lineage` / `destmap` 全绿（103 个 Swift 文件）。
