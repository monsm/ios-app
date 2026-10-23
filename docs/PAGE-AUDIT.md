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

| 2 类 | 01-home、10-keys-manage、11-fingerprint、13-key-detail、24-dongles、25-synctime、33-archived、40-security、51-feed、85-battery、86-checklist、87-claim |
| 1 类 | 02-keys、03-devices、04-members、12-tempcode、14-otp、15-add-key、20-locks、22-firmware、30-members-list、32-member-detail、41-applock、45-destroy、48-export、52-stats、70-icon-picker、80-states、89-share-android |

---

## 工具

```bash
node tools/pageaudit.js                        # 全站三层对照总表
node tools/pageaudit.js --page 84-diagnostics  # 单页明细
node tools/parity.js                           # 审美术语缺口
node tools/entrygate.js                        # 入口可点性
```

**工具的局限**：Swift 侧卡头/标签形态多样（单行 .xFont / 换行 / secLabel / headerTitle），
正则无法 100% 命中，所以 pageaudit 的「缺口」必须**逐页人工复核**才算数——这正是「亲自过一遍」的意义。