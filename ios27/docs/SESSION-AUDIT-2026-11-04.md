# 审计手记 · 2026-11-04（账本阶段收尾）

> 这份文件只记**这一阶段新发现、且已修**的东西，以及**明确还没做**的。
> 历史轮次的细节在 `AUDIT-ROUND-*.md`；闸门清单见 `ARCHITECTURE.md`。

## 一、这一阶段修的（按类）

| 类 | 代表 |
|---|---|
| 归属链路 | `RecordsSource.load` 用 `Attribution.classify` 建立 `idxRaw → 成员名` 映射；手动认领（`kf_mclaim_`）读/写两端接通，且统计 `activityBundle` 同源 |
| 字段从未被填 | `lastActiveAt` 由 `activityBundle.lastUnix` 提供（原硬写 nil）；`opens30Counts` / `visitorOpens` 改引擎 |
| 假选项 / 假开关 | 「纯黑（AMOLED）」与「深色」同观感 → 不再展示；`encryptBackup` 遗骸删除 |
| 死控件 | 「换锁」「读取锁内日志」（空态卡 + ⋯ 菜单）在「全部锁」模式下隐藏；指纹不再显示改到期菜单；动态密码按钮按三条 guard 同步禁用 |
| 空壳（胁迫码） | 五个泄漏面：成员写入、诊断流水、剪贴板、通知生产者、覆盖层写入；闸门 36 守 21 个签名 |
| 只读试验 | 录指纹直发绕过 `assertReadOnly` → 补；闸门 37 守全部直发帧点 |
| 合规 | 隐私清单补 `SystemBootTime`；`ITSAppUsesNonExemptEncryption: false` |
| 可致锁死 | 全角数字可被设为密码/胁迫码 → 只收 ASCII |
| 呈现 | 中文标点空格 73 处、半角括号 70 处、Tab/页面命名、到期日三种说法、时刻标签 `HH:mm`、CSV 行数 |

## 二、明确**没做**的（别当成已完成）

1. **`kf_mclaim_` 不进备份包** —— 已在备份页披露；要真正随备份迁移需动 schema 与三方导入兼容。
2. **角色权限从不生效** —— `permCan`/`permCannot`/`roleLabel` 零调用；但全仓无任何文案承诺角色限制，属未启用特性而非坏承诺。
3. **`Dest.unlockGate` 是死路由** —— 真实入口是 `DoorScreen` 的 `.sheet`；若有人走 `Dest` 会变成 push，语义不同。
4. **记录认领 UI 只做了「未归属 → 认人」**；改判/撤销认领尚无入口。
5. **`RecordOverlay` 与 `MemberHub.claim` 的空壳守卫是防御性**：当前路径不可达。

## 三、验证纪律

- 每道闸门必须**注入验证**；抓不到就删（`typecheck`/`copynum` 就是这么删掉的）。
- 闸门 37 的第一次注入「没变红」是**注入点选错**（落在注释里），不是闸门错 —— 用隔离探针确认。
- 闸门 36 曾抓到我自己「插入了注释但漏了 guard」，这是它最有价值的一次命中。
- 云构建只跑 `xcodebuild`；本地 38 道闸门**不做类型检查**，所以每次改完要留意 `ci-log`。

## 四、下一阶段建议入口

- 数据规模：1000 条日志下记录页的筛选与渲染（`filtered` / `LedgerGrouping` 每次 body 重算）。
- 并发：BLE 断连中途的操作序列（已修 E-07 族若干处，仍值得系统化扫）。
- 真机：CI 截图管线一次完整 run，复核最近十余个提交的视觉结果。