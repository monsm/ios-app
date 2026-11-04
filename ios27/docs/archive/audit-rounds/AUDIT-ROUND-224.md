# AUDIT-ROUND-224 · 第 224 轮：删锁的「孤儿数据」审计 —— 兜底网是承重墙

> CI：`3a0be7e` **build_ok=1 / archive_ok=1 / errors=0 / warnings=0**（全绿）。

## 1. 审计方法

1. 抽出全仓 **145 个 `kf_*` 键字面量**；
2. 抽出 `removeDevice` 里的 **33 条显式前缀**；
3. 求差集 —— 看有没有「每锁但它不删」的族。

## 2. 结果

差集里看起来像「每锁」的只有一处：**`kf_autoopen_lastdispatch_<mac>`** —— 它**不在**显式前缀清单里。

但它**实际会被删掉**，因为 `removeDevice` 末尾有一条兜底：

```swift
let up = m.uppercased()
for k in store.keys() where k.contains(m) || k.contains(up) { store.remove(k) }
```

键名里带归一化 mac 的都会被它收走。

## 3. 这条兜底网是**承重墙**，不是冗余

| 族 | 在显式清单里？ | 靠兜底网？ |
|---|---|---|
| `kf_autoopen_lastdispatch_` | ❌ | ✅ |
| `kf_cdisrea_` / `kf_cestudy_earlyexp_` | ❌ | ✅ |
| `kf_mkey_` / `kf_rnote_` / `kf_rflag_` / `kf_rdisp_` / `kf_rflt_` | ❌ | ✅ |
| `kf_mborrow_` / `kf_mclaim_` | ❌ | ✅ |

**删掉那条兜底，这些族就全变孤儿键** —— 而它们里面有手机钥匙、记录备注、成员认领映射。

已在 `removeDevice` 的注释里补了一句：**这是承重网，不是冗余**，以及它成立的**前提**：
所有每锁键都必须用**归一化 mac** 拼接（`kf_logsync_` 当年就是栽在没归一化）。

## 4. 另外核对的两项

| 检查 | 结论 |
|---|---|
| 键拼接是否用归一化 mac | ✅ 键构造点全部接收 `kc.mac` / `app.currentMac`（钥匙串里存的已是归一化值）；`kf_logsync_` 那处 Round 177 已修 |
| `preferredMac()` 会不会指空 | ✅ 先 `ks.contains(currentMac)` 校验再回落 `ks.first` |

## 5. 方法论

**一条"兜底"规则，最怕的是下一个人以为它冗余而删掉。**

| 兜底的类型 | 该怎么标注 |
|---|---|
| 防御性冗余（删了也没事） | 可以删 |
| **承重（删了会漏数据）** | **必须在注释里写"这是承重的 + 它成立的前提"** |

判据：**任何 `where k.contains(...)` 式的大范围清理，都要写清"它替哪些族兜底"。**
