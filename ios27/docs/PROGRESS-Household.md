# PROGRESS · Household 域（task-3）

写作用域：`ios27/App/Features/Household/`（只新增文件，未改 Design/、Shell/、其它 Features/）

## 文件清单

| 文件 | 行数 | 一句话 |
|---|---|---|
| `HouseholdScreen.swift` | 372 | **HouseholdScreen** —— 家 Tab 根：家庭概览读数（成员 / 名下凭证 / 本周开门 / 归档）+ 名册（头像·称呼·角色·名下枚数·活跃度）+ 分组 chip + 四档排序 + 本周主责菜单 + 访客虚拟分组入口 + 家庭场景便签 + 唯一主动作「新建成员」，全空时给建档向导出路。 |
| `MemberDetailScreen.swift` | 367 | **MemberDetailScreen** —— 成员 360：这一周小结 / 角色三档与五项权限矩阵（点一下即改，矩阵当场亮灭）/ 档案九字段（关系·备注·emoji·分组·便签·紧急联系）/ 紧急管理员点名 / 家庭场景（本周主责）/ 归档与删除（两种后果同屏预告）。 |
| `MemberCreateScreen.swift` | 309 | **MemberCreateScreen** —— 建档向导四步真序列（01 称呼与代号 → 02 角色与备注 → 03 档案 → 04 初始凭证），每步校验、重名/上限拦截、可回退、取消回收已建号。 |
| `MemberArchiveScreen.swift` | 166 | **MemberArchiveScreen** —— 归档名单逐位恢复 + 归档影响面（记录页仍能筛到、凭证页仍列名下凭证、名册不再出现），空态给回名册的出路。 |
| `HouseholdRoster.swift` | 282 | 家域数据层：档案扩展落 kf_member_ext、本周主责落 kf_duty_week、成员上限与活跃度口径（`HHPerm` 直接委托 Engine 的 `MemberHub.permRows`）。 |
| `HouseholdParts.swift` | 351 | 家域语法层：`HHPageHeader`（34pt semibold + 一行状态）/ `HHMemberRow` / `HHRoleMark` / `HHRowButton` / `HHToggleRow` / `HHPill` / `HHAvatar` / `HHTextField` / `HHRule`。 |
| `MemberDetailParts.swift` | 232 | 成员 360 的三块面板：名下凭证 / 最近开门摘录 / 这一周 / 家庭场景 / 档案收尾（拆文件，避免单文件超 400 行）。 |
| `MemberCreateParts.swift` | 171 | 向导零件：四步刻度（01/02/03/04）/ emoji 代号 / 角色单选行 / 校验提示 / 临时码块。 |

> 8 个文件、4 个屏幕类型；`Destinations.swift` 引用的 `HouseholdScreen` / `MemberDetailScreen` / `MemberCreateScreen` / `MemberArchiveScreen` 同名实现，destmap 闸门通过。

## 未接真数据（全部标了 `TODO(engine)`）

| 位置 | 字段 / 链路 |
|---|---|
| `HouseholdRoster` · 成员列表 | 名册仍读 `AppModel.members`（MemberCard 样例）；真实现应改 `DB.members()` + `MemberHub.allExt()`，角色与归档两处写回点已留在 `mirrorRole` / `mirrorArchived`。 |
| `HouseholdRoster` · 档案扩展 | 已真落盘 `kf_member_ext`（emoji / 备注 / 分组 / 便签 / 紧急联系 / 紧急管理员）；关系落 `kf_member_relation` 覆盖层 + `DB.setMemberInfo`。 |
| `HHStats.weekOpens` / `opens30Counts` / `weekSentence` | 需接 `MemberHub.activityBundle`（`Attribution.classify` 按指纹/密码归属推断）；现在只认台账里已写 owner 的行，界面一律写「约」。 |
| `HHStats.memberLimit` | 15 位上限是旧仓文案口径；应改读锁端槽位表。 |
| `HouseholdScreen` · 访客虚拟分组 | 需接 `MemberHub.isVisitorRow`（kind==temp 且 who==nil）；现在按台账 event 文案 + owner 为空近似。 |
| `MemberDetailScreen` · 名下凭证 | 需按 member id 跨锁遍历 `DB.listPwds/listFps`；现在按 owner 姓名匹配本机 `app.keys`。 |
| `MemberDetailScreen` · 最近开门 | 需接 cmd16 日志 + `MemberHub.recentExcerpts`；现在只读 `app.entries` 已归属的行。 |
| `MemberDetailScreen` · 删除成员 | 需 `CredentialOrg.cascadeBinMember` + 锁端删除队列（删密码/删指纹）；现在只动本机台账，文案如实写「锁端仍需线下删」。 |
| `MemberCreateScreen` · 临时码 | 需 `ensureConnected` → `pwdAdd` 下发 10 分钟有效临时码并写台账快照；现在只写本机 `app.keys`（并校验「先有锁」）。 |
| `MemberCreateScreen` · 建档 | 已真落 `DB.addMember`；角色/归档写回 `MemberHub.saveExt`。 |
| `HouseholdScreen` · 本周主责 | 读写 `kf_duty_week`（与 `MemberHub.dutyThisWeek` 同键同周界）。 |
| `MemberDetailScreen` · 重复合并 | 未实现（`member.merge` 功能点）：需要同名检测 + 凭证迁移 + 认领迁移，本版 4 屏范围内不做。 |

## 自查

- `node Gates/allgates.js` → 11 道闸门全绿（swiftparse / types / swiftcheck / tokens / contrast / glass / motion / a11y / callsig / lineage / destmap）。
- 家域目录内逐项 grep：`Color(hex:` 0、`.padding(数字)` 0、`Text` 上 `.system(size: 数字)` 0、`.bold()` 0、`glassEffect` 0、系统颜色字面量 0、`.cornerRadius(数字)` 0。
- 四屏各一个主角 Panel：家 = 家庭概览；成员 360 = 角色与权限；建档向导 = 当前步骤面板；归档 = 归档名单。
- 同屏 signal 填充：家只有「新建成员」、成员 360 只有「保存档案」、向导只有「下一步/完成建档」；归档屏刻意不给单一主填充（逐位恢复）。
- 所有数字走 `Reading` / `FieldRow` / `ReadingGrid`；所有时刻走 `TimeFormat`（`clock` / `dayShort` / `ago`）。
- 空态都给出路：无成员 → 建档向导；分组筛空 → 清除筛选；成员不存在 → 回名册；归档为空 → 回名册；无锁时建码 → 如实说「先添加门锁」。
- 中文标题全部 `T.F.display()` semibold，无 `.bold()`。
