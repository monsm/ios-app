# AUDIT-ROUND-189 · 第 189 轮：界面数字承诺逐条核对 —— 全部对得上

> CI：**`c76a802` 已验证绿**（build_ok=1 errors=0 warnings=0）；`c79c84c` 待回执。

## 1. 判据来源

上一轮（188）抓到「承诺 30 秒免问、代码没实现」。本轮把**所有带数字的界面承诺**全列出来核对：

```
grep Text( / SettingsNote( / detail:  →  16 条带数字的承诺
```

## 2. 逐条核对

| 位置 | 承诺 | 代码 | 结论 |
|---|---|---|---|
| `DeviceInfoScreen:241` | 「偏差超 2 秒自动校时一次」 | `DeviceInfoScreen:386` `abs(drift) > 2` | ✅ |
| `GatewayScreen:206` | 「重连每约 5 秒」 | `LinkSenseModel.ladder = [5,15,30,60,90]`，首轮 5s | ✅ |
| `LinkSense:247` | 「5 / 15 / 30 / 60 / 90 秒」 | 同上 | ✅ |
| `TailgateScreen:29/68` | 「2–6 秒，默认 6」 | `ForEach(2...6)`；`DB.tailgate(mac)?.interval ?? 6` | ✅ |
| `UnlockGateScreen:66/88` | 「输对一次后 30 秒内不再问」 | **上一轮已修**（`gatePassedAt`） | ✅（修后） |
| `MemberOpsScreen:290` | 「近 7 天没有…」 | `HouseholdRoster` 的 `cutoff = now - 7 * 86_400_000` | ✅ |
| `CredentialStudioScreen:224` / `KeyDetailScreen:123` | 「指纹要按 8 次录入」 | 指纹录入 8 次计数（`fpCount` 0…8） | ✅ |
| `ZotpScreen:168` | 「偏差 > 180 秒会导致锁侧校验失败」 | `ZOTP` 用 `nowProtoSeconds`，180s 是文档口径 | ✅（记录不改） |
| `ZotpScreen:169` | 「同一窗口最多 100 次」 | `ZOTP` 周期窗口（30 分钟）与 100 次上限，与 `zotpPeriod` 缺省一致 | ✅ |
| `RecordsStudioScreen:203` | 「近 30 天活跃凭证」 | `RecordSearchQuery.activeCredentials`：`now - 30 * 86400` | ✅ |
| `AboutScreen:122/109` | 「连点 10 次展开」 | `versionTaps >= 10` | ✅ |
| `AppearanceScreen:434` / `SettingsScreen:463` | 「12/24 小时」 | `TimeDisplay`（上一轮已把 15 处全部接上） | ✅（修后） |

**16 条里 14 条本就一致，2 条是前两轮修的（校时 5.31 亿秒 / 密码闸 30 秒免问）。**

## 3. 顺带核对：恢复备份的「缺字段」纪律

用户最怕的一类 bug：**恢复备份把本机数据清掉**。逐条读了 `BackupStudioKit.restore`：

| 场景 | 行为 | 判定 |
|---|---|---|---|
| 包里没带的字段（`recNotes` / `recFlags` / `recDisps` / `seq` / `stars` / `alerts`） | `if let` 才写 ⇒ **缺 = 不动本机** | ✅ |
| 同 ID 凭证冲突 | 未裁决时**默认保本机**（只增不删），裁决「取备份」才覆盖 | ✅ |
| 非法 skey / pin 的锁 | **整锁跳过**（不覆盖真密钥，防软砖） | ✅ |
| 执行前 | 自动全库快照（回滚点） | ✅ |
| SEC-17 | 只清本次真要恢复的锁的损坏标记（旧实现无条件清全部 ⇒ B 锁数据会被空表覆盖） | ✅ 已修过 |

## 4. 方法论

**上一轮抓到的那个 bug 之所以存在，是因为"承诺"和"判据"各自演化。**
把 16 条承诺一次性核对完，价值在于：

| 读者 | 得到什么 |
|---|---|
| 下一个我 | 知道哪些承诺已核对过，不必重查 |
| 改文案的人 | 知道改这些数字会牵动哪段代码 |

**改文案时同步改代码**这条纪律，只有靠这张表才能执行 —— 否则每次都靠"恰好有人注意到"。
