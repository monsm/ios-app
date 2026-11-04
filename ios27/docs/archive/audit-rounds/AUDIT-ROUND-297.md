# AUDIT-ROUND-297 · 第 297 轮：撤销恢复撤不回**星标 / 提醒档位 / 手机钥匙**

> CI：`e01e792` build 全绿；`1fd329f` / `cfe43dd` 排队中。

## 1. 缺陷

`restore` 会写这三族，而 `rollbackFamilies`（回滚快照的键族清单）**没收**：

| 族 | 内容 | restore 写入点 | 在快照里？ |
|---|---|---|---|
| `kf_cstar_ui_` | 星标（哪几条最重要） | `BackupStudioKit:470` | ❌ |
| `kf_calert_` | 每条凭证的到期提醒档位 | `:471` | ❌ |
| `kf_mkey_` | 手机钥匙（归属/有效期/pin） | `MobileKeyService.save` | ❌ |

后果与这个文件里已经记录过的三次完全同源：
**导错备份 → 点「撤销恢复」→ 台账/成员都回去了，星标、提醒档位、手机钥匙却停在错包的值上。**

## 2. 为什么这次特别值得修

`kf_cstar_ui_` / `kf_calert_` 正是**我自己在早前几轮补进备份包**的两族
（当时判据是「用户自己攒的内容 + restore 会写」）。补进备份时只改了 `BackupBundle`，
**没有同步加进回滚清单** —— 于是「备份能带走了，但撤销恢复带不回来」。

## 3. 修法

在 `rollbackFamilies` 末尾补 `"kf_cstar_ui_", "kf_calert_", "kf_mkey_"`，并把判据写进注释。
（`makeRollbackPoint` 把每个键的**原始字节** base64 存进 extras，所以任何键族都能原样回滚，不需要额外结构。）

## 4. 这是第 4 次同类漏项

| 轮次 | 漏的族 |
|---|---|
| 第 63 轮 | `kf_hc` / `kf_plain` / `kf_hero_stats` / `kf_recent_count` |
| 第 65 轮 | 外观 + 无障碍共 10 个键 |
| 第 66 轮 | `kf_rnote_` / `kf_rflag_` / `kf_rdisp_` |
| **本轮** | **`kf_cstar_ui_` / `kf_calert_` / `kf_mkey_`** |

四次都是同一个形状：**「恢复会写 X」和「快照要收 X」是两份清单，相距 300+ 行，靠人记不住。**

## 5. 方法论

**给 restore 增加一个写入族时，必须同步问：这个族在 `rollbackFamilies` 里吗？**

| 检查顺序 | 漏的概率 |
|---|---|
| 只改 `BackupBundle`（能导出能导入） | 高 —— 看起来功能已完成 |
| **再查 `rollbackFamilies`（能撤销）** | 低 |

判据：**「恢复」是两条链（正向导入 + 反向撤销），加字段时两条都要过一遍；只跑通正向就等于默认接受「撤销不完整」。**
