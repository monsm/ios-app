# AUDIT-ROUND-66 · 第六十六轮：拖拽排序也不进备份（同族第四例）

> CI：`f5c5238` 已验证；`610681d` / `045b73c` / `ee4b04e` 刚推送。本轮本地提交。

## 1. 缺陷：用户手动排的顺序，换机回到默认

`kf_cseq_<mac>`（`CredentialOrg.seq` / `setSeq`）存的是用户拖拽出来的顺序：
`["p": [别名…], "f": [批次…]]`。全仓搜索：只有读写两侧与 `removeDevice` 的清理清单，
**备份链路里一次都没有**。

与 `alerts` / `stars` 同一族。区别是这一族的数据**本身就是顺序** —— 丢了不是"少一个标记"，
而是"我精心排好的常用顺序全没了"。

## 2. 修法：又是那四处

| # | 位置 | 动作 |
|---|---|---|
| 1 | `BackupBundle.Device.Meta` | 加 `var seq: [String: [Int]]?` |
| 2 | `BackupCanonical.metaValue` | emit `seq` |
| 3 | `BackupKit.collectAll` | `CredentialOrg.seq(mac)` |
| 4 | `BackupStudioKit.restore` | `CredentialOrg.setSeq(mac, sq)` |

## 3. 两个容易踩的点

**（1）字段顺序必须与 canonical 的 emit 顺序一致。**
`Meta` 里我按字母序放在 `alerts` 之后、`stars` 之前（`alerts < seq < stars`）；
构造实参也必须同序 —— 这正是 ROUND-54 被 CI 判红的那个坑。
这次改完立刻用脚本复核：

```
Meta decl: ... alerts, seq, stars
Meta args: ... alerts, seq, stars  -> MATCH
```

**（2）顺序不能排序。** 字典按键排，但**数组必须保持原样** —— 顺序就是数据。
回归测试里专门断言导出文本含 `[3,1,2]` 而不是被规范成 `[1,2,3]`。

## 4. 同族清单（备份完整性）

| 族 | 现状 |
|---|---|
| `kf_calert_`（提醒档位） | 已补（ROUND-48） |
| `kf_cstar_ui_`（星标） | 已补（ROUND-65） |
| `kf_cseq_`（拖拽序） | **本轮已补** |
| `kf_cbin_` / `kf_chist_`（回收站 / 版本快照） | 刻意不收（临时副本，且含明文口令） |
| `kf_rnote_/rflag_/rdisp_` | 早已收（第 66 轮） |
| `kf_member_ext` | 已补（ROUND-44 + 52） |

**至此，所有"用户自己攒的内容"型旁挂表都已进备份。**
