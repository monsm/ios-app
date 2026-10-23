# 逐页审美审核台账

> 目标（用户 2026-10-24）：**app 每一页都亲自过一遍**，核对是否做到 HTML 对应页的审美 / 视觉 / 布局。
> 口径：审美以 tools/proto/*.html 为准；功能以真实 App 为准。
> 方法：逐页读 HTML 卡结构与 Swift 实现，对照 ①卡序 ②卡内解剖（卡头→标题→标签/值→分隔线→页脚）③视觉词汇（环/大数字/胶囊/彩点行），不一致就改 Swift。

图例：✅ 已逐页审完并修　🟨 审过但仍有差距　⬜ 未审


### 60-care ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 还剩多少（44px 天数 + 三色环 + 三列：上次/下次/周期 + 页脚）| periodCard | ✅ **整卡按 HTML 重写**（原 XStatCard 内的 19pt 标题 → 44px 主角 + 三列）|
| 该做的（彩点行 + 页脚）| todoCard | ✅ 上一轮已补卡头 |
| 入口卡 | historyRow | ✅ 已对齐 |

### 46-safemode ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 验证强度（A/B 两条进度条 + 页脚）| — | ✅ **新增整卡** |
| 两种模式的差别（双角色卡 + 彩点行）| modeCard ×2 + XDataRow | ✅ 前一轮已改 |
| 怎么设置（+页脚）| 已有 | ✅ 已对齐 |


### 88-exit ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 待处置（44px + 三列：保留/移交/停用 + 页脚）| exitStatsCard | ✅ 补三列（用真实 decisions 取值 keep/move/delete）|
| 逐条处置 | 已有 | ✅ 已对齐 |
| 归档 | **已有「归档并执行」按钮且逻辑完整** | ✅ 判定无需新增（我一度误加红卡，已撤回）|

### 42-peek ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 防窥项（环）| 已有 | ✅ |
| 遮蔽样式（圆点/星号/末4位 + 页脚）| — | ✅ **新增整卡** |
| 隐私总览 | — | ✅ **新增整卡** |
| 遮蔽与通道（+页脚）| 已有 SecRow 组 | ✅ |


### 01-home ✅（主屏）
| HTML 元素 | Swift 对位 | 处理 |
|---|---|---|
| 顶部 3 玻璃胶囊 | masthead 的 4 个 chip（link/battery/today/alerts）| ✅ 已有，判定对齐 |
| 巨型渐变环 + 环心数字 | unlockStage（220pt 按住开锁环）| ✅ 保留（功能是"按住开锁"，非数据环）|
| **44px 大数字** | metricsRow 三个等重 XDataRow | ✅ **把「今日开门」提为 44px 主角** + 两条数据行 |
| 「本周」卡（两列 + 页脚）| todaySection（XStatCard + 页脚 + 最早一次/最后一次）| ✅ 已对齐 |

### 10-keys-manage ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 库存分布（环 + 两列：本周新增/即将到期 + 页脚）| overviewCard（44px + 三环 + 页脚）| ✅ **补两列 + weekAdded** |
| 即将到期（+页脚）| expiringCard | ✅ 已对齐 |
| 密码 / 指纹（+页脚）| credentialCard | ✅ 已对齐 |


### 13-key-detail ✅ **（本轮最重要：补出缺失的详情页）**
**发现的真 Bug**：`KeysPage.keyRow` **没有任何点击**，只有 contextMenu（长按）。
代码注释自己写着「这一页原来完全没有行交互 —— 没有详情页、没有点击」。
→ 用户点凭证行毫无反应。**这正是"入口不能点击"**。

**修复**：新增 `CredentialDetailView`（对齐 HTML 13-key-detail 四卡）+ 整行包 NavigationLink。

| HTML 卡 | 实现 |
|---|---|
| 码值（44px + 锁内编号/指纹位 两列）| ✅ XHeroNumber + 两列 |
| 归属与授权 | ✅ XDataRow（归属/类型）|
| 使用记录（本月使用/最后使用 两列 + 页脚）| ✅ |
| 操作 | ✅ 星标 + 停用（走确认框）|


### 11-fingerprint ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 锁内容量 | capacityCard | ✅ |
| 指纹库存（**上次录入 / 建议补录** 两列 + 页脚）| capacityCard | ✅ **补两列 + lastEnrollText** |
| 录入指纹 / 命名 / 已登记 | fingerprintStage / ownerPicker | ✅ 已有 |

**顺带修的单位坑**：`LedgerFp.at` 是 epoch **毫秒**，我一开始按秒算（会显示 1970 年）。已按 Store.swift 的注释 ÷1000。

---

## 专题：虚假可点暗示（问题②的根因之一）

**发现**：我前几轮为了对齐 HTML 的「卡头 + chevron」解剖，在 12 张卡的卡头画了装饰性 chevron，
**但没有接任何动作** —— 用户看到箭头会去点，点了没反应。

**处理**：全部删除（HTML 的 cardlink 有目标才带箭头；这些卡没有详情页，画箭头就是撒谎）：
AppLockSetupView / BackupPage / CarePage / CareRemindersView / DiagnosticsPage×2 / ExportCenter / FeedPage / KeysPage / MembersPage / SecurityPage / StatsPage 共 **12 处**。

**判据留存**：`entrygate.js` 的 E1 已在「带 chevron ⇒ 必须有动作」，但只查 `XRow(showsChevron:)`，
查不到手绘 Image(chevron)。已在本轮人工清理干净。


### 24-dongles ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 已配对（44px 读数 + 环）| headerCard | ✅ 上一轮已加 |
| 每把钥匙串 | dongleCard | ✅ **手绘 RoundedRectangle 背景 → XPanel**（拿到图2 顶光材质）|
| 操作（+页脚）| 已有操作按钮 | ✅ |

### 25-synctime ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| **偏差范围**（允许区间/当前）| — | ✅ **新增整卡** |
| 锁钟偏差（96px + 页脚）| skewCard（44px 主角 + 同色光晕）| ✅ 标签改回「锁钟偏差」|
| 对照 | clockCard | ✅ |
| 写入 | actionCard | ✅ |

### 33-archived ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 归档（44px 读数 + 环）| archivedStatsCard | ✅ |
| 归档记录（+页脚）| 裸 ForEach | ✅ 加小节标题 + 组容器 + **补页脚** |
| 归档规则 | — | ⬜ 待补（下轮）|


### 33-archived ✅ 补齐
| HTML 卡 | 处理 |
|---|---|
| 归档规则（三条彩点行：钥匙不删/记录保留/不占名额）| ✅ **新增整卡** |

### 40-security ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 现在安全吗（44px + 环）| 已有 | ✅ |
| 有没有事 | 缺卡头 | ✅ 补「有没有事」|
| 有哪些功能（+页脚）| 缺卡头与页脚 | ✅ 补「有哪些功能」+ 页脚整句 |

### 51-feed ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 今日时段（44px + 柱图 + 轴标）| 已有 | ✅ |
| — | 缺页脚 | ✅ 补页脚 |


### 02-keys ✅
| HTML 元素 | 差距 | 修复 |
|---|---|---|
| 卡前 **5 个胶囊** | 无 chip 行 | ✅ 新增 chipsRow（全部/密码/临时码/指纹/即将到期）|
| 本周到期（总计/密码/指纹 三列 + 页脚）| 缺三列 | ✅ 补 |
| 本周用量（环 + 两列 + 页脚）| overviewCard 已有环/两列/页脚 | ✅ |
| 全部钥匙 | credentialCard | ✅ |


### 04-members ✅
| HTML 元素 | 差距 | 修复 |
|---|---|---|
| 卡前 **4 个胶囊** | 无 | ✅ 新增 membersChipsRow（成员/活跃/归档/未归属）|
| 成员分布（三环 + 钥匙总数/指纹总数 两列 + 页脚）| 无 | ✅ **新增整卡** |
| 头像带 / 成员卡 | avatarStrip / rosterCard | ✅ 已有 |

### 12-tempcode ✅（部分）
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 场景预设 | 裸 ScrollView 无卡结构 | ✅ **新增卡** + 外层改 section 间距 |
| 码值 / 生效时段 | 在 addForm 内 | 🟨 待下一轮细化卡包装 |

### 14-otp ✅ 判定已达标
五卡齐：用于哪把锁 / 锁端 ZOTP（页脚）/ 独立口令 / 导入与添加 / 静态备份码（页脚）。
之前工具报缺卡是因为正则漏了 `staticCard` 的写法。


### 22-firmware ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| **升级进度**（环 + 四步：检查/传输/写入/完成）| **整卡缺失** | ✅ 新增（44px 步数 + 环 + 四步标签 + 页脚）|
| 版本 | versionCard（双角色卡）| ✅ 上一轮已改 |
| 升级前检查 / 操作 | checklistCard / actionCard | ✅ |

### 30-members-list ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| **钥匙分布**（三类占比条）| **整卡缺失** | ✅ 新增（三行彩点 + 横向占比条 + 页脚）|
| 成员分布（环 + 两列 + 页脚）| — | ✅ 上一轮已加 |
| 全部成员 | rosterCard | ✅ |

### 20-locks ✅ 判定保留 List
HTML 2 卡；App 用 List + Section（承载拖动排序 / 滑动删除 / 编辑模式三个真实交互）。
**不改卡片流**：这三套交互重写风险大于收益，而卡片材质不是 HTML 的硬性审美项。


### 31-member-wizard ✅
| HTML 元素 | 差距 | 修复 |
|---|---|---|
| **卡前步骤条** | 无（只有 secLabel "步骤 X/3"）| ✅ 补 `XStepBar(titles:current:)` |
| 称呼卡 + emoji 画廊 + 角色 | 已有 | ✅ |

### 32-member-detail ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| **最近活动**（+页脚）| **整卡缺失** | ✅ 新增（时间列 + 文本 + 页脚，用真实 `Excerpt.time/text`）|
| 名下钥匙 / 本周开门 | memberMetricsCards（双列）| ✅ 上一轮已加 |

### 34-merge ✅ 判定已达标
HTML 两卡「将迁移」「选择副档」在 Swift 中都有对应实现（4 个 XPanel）。


### 45-destroy ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 三级销毁 / 备份闸 / 回收站 / 离职清除 / 安全模式 / 口令复用 / 密码保存 | 已有 | ✅ |
| **敏感操作视图** | 内容散在三级销毁卡内，无独立卡 | ✅ 新增整卡（两行数据 + 页脚）|

### 48-export ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 历史导出（44px + **24 柱 + 轴标**）| 只有 44px，无柱图 | ✅ 补 24 柱 + 0/6AM/12PM/6PM/24 轴标 |
| 范围 / 文件 / 图片 / 打印 / 校验 / 路径 | 已有 | ✅ |

### 49-appearance ✅ 判定已达标
**⚠ 修正映射错误**：`49-appearance` 的真实页面是 `AppearancePage.swift`（外观工作室），
我此前在 MAP 表里错标成 `StudioPage.swift`（钥匙工坊 = 83-studio）。
实审：HTML 仅 1 卡（看得清 / 每周从哪天算），App 也 1 卡且内容一致（高对比开关 + 周起始单选）→ 已达标。

### 50-events ✅ 判定已达标
HTML 2 卡；App 是**真时间轴**（竖线 + 节点）+ 我加的图5 读数条。
时间轴是比"卡片堆"更合适的形态（代码注释明确论证过），不改。


### 85-battery ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 当前电量（44px + 环 + 页脚）| 有 44px/环，**缺卡头** | ✅ 补「当前电量」|
| 换电步骤（+页脚）| 已有 secLabel + 页脚 | ✅ |

### 86-checklist ✅ 判定已达标
两卡齐：保养进度（44px + 环 + 环心数字）/ 五项清单（含页脚）。

### 82-bin ✅
| HTML 卡 | 差距 | 修复 |
|---|---|---|
| 保留期 / 回执 | 横向布局无卡头 | ✅ 补卡头 + VStack 包裹 |
| 下发状态（+页脚）| 缺卡头 | ✅ 补 |

### 52-stats ✅ 判定已达标
7 卡对齐 HTML 七卡（活动环/安全/怎么开的门/一天最忙/工作日出门/分布/近14天），5 处页脚（HTML 3 处）。

---

## 已审

### 84-diagnostics ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 数据健康（44px+环+孤儿数据/日志断档+页脚）| healthMetricCard | ✅ 补两列+页脚 |
| 稳定性（44px+环+异常退出/内存占用/本次启动+页脚）| stabilityCard | ✅ 整卡重构为图5 MetricCard |
| 本机自检 | selfCheckCard | ✅ 已对齐 |
| 蓝牙（连接状态/握手耗时+页脚）| bleCard | ✅ 补页脚 |
| 数据保留（事件记录/审计日志）| retentionCard | ✅ 补页脚 |

### 81-backup-studio ✅
| HTML 卡 | Swift 对位 | 处理 |
|---|---|---|
| 状态（44px+上次导出/上次导入/撤销窗口+页脚）| backupFilesCard | ✅ 补三列+页脚 |
| 撤销本次恢复（24h 内）红卡 | — | ✅ 新增整卡 |
| 三个向导（+页脚）| actionCards | ✅ 已对齐 |

### 前几轮已审 ✅
- 47-backup：卡头「备份时效/备份状态/加密参数」+ 标签 算法/认证/派生
- 89-share-android：新增「关于这个码」卡（有效期/作用）
- 21-lock-profile：新增「指纹余量」「身份（名字/锁态）」+ 四卡头
- 05-system / 4a-me（同为 MePage）：新增「备份恢复」卡 + 四卡头改名
- 41-applock：新增「保护项」卡
- 60-care：「该做的」卡头 + 保养历史横滑
- 25-synctime：「偏差范围」「写入」卡头
- 61-reminders：生日清单 → 图6 横向画廊
- 03-devices：补 XStatChip 玻璃胶囊

---

## 待审（38 页）

| 缺口 | 页 |
|---|---|

| 2 类 | 11-fingerprint、13-key-detail、24-dongles、25-synctime、33-archived、40-security、51-feed、85-battery、86-checklist、87-claim |
| 1 类 | 02-keys、03-devices、04-members、12-tempcode、14-otp、15-add-key、20-locks、22-firmware、30-members-list、32-member-detail、41-applock、45-destroy、48-export、52-stats、70-icon-picker、80-states、89-share-android |

---

## 工具

```bash
node tools/pageaudit.js                        # 全站三层对照总表
node tools/pageaudit.js --page 84-diagnostics  # 单页明细
node tools/parity.js                           # 审美术语缺口
node tools/entrygate.js                        # 入口可点性
```

**工具的局限（2026-10-24 确认）**：`pageaudit.js` 的正则匹配不了单行 `Text("x").xFont(.caption2)` 写法，
导致**已审完的页仍被标成缺口**（05-system/47-backup/4a-me/60-care/81/84 均已人工审完）。
**以本台账为准，不以工具输出为准。**

**工具的局限（原文）**：Swift 侧卡头/标签形态多样（单行 .xFont / 换行 / secLabel / headerTitle），
正则无法 100% 命中，所以 pageaudit 的「缺口」必须**逐页人工复核**才算数——这正是「亲自过一遍」的意义。