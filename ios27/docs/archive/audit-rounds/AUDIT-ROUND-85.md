# AUDIT-ROUND-85 · 第八十五轮：电池采样只有时间上限，没有条数上限

> CI：`e150d03` 已验证；`816aa3f` / `efc94c8` / `dc7b29c` 待回执。本轮本地提交。

## 1. 缺陷

```swift
static func sample(_ mac: String, pct: Int) -> Bool {
    var list = samples(mac)
    let cutoff = nowMs - 90 * 24 * 3600 * 1000
    list.removeAll { $0.t < cutoff }      // 只按**时间**裁
    ...
    list.append(BattSample(t: nowMs, pct: pct))
    DB.store.setCodable("kf_batt_" + mac, list)   // 整表写回
}
```

90 天是**时间**上限，不是**条数**上限：

- 一次开锁会连读几遍状态（同分钟同读数已去重，但读数变化时会各记一条）；
- 每天连 10 次、每次读数变 2 次 ⇒ 20 条/天 ⇒ 90 天 **1800 条**；
- 而本函数每次都要「整表解码 + 整表写回」，成本随条数线性涨。

（这与我在 `alertTable` 上修过的坑同源：**按条数 O(n) 的操作被放进高频路径**。）

## 2. 修法

加条数上限 720（≈ 每天 8 次 × 90 天，足够画续航趋势），超出丢最旧的：

```swift
let maxSamples = 720
if list.count > maxSamples { list = Array(list.suffix(maxSamples)) }
```

注意方向：数组是**追加在后**（`append`），所以丢**前缀**（最旧）、保留 `suffix`（最新）——
正是 ROUND-40 那个「回收站上限丢错端」的同一类判断，这次先确认了数组方向再写。

## 3. 同类核查：其余 13 处上限都正确

| 位置 | 裁剪方向 | 数组方向 | 判定 |
|---|---|---|---|
| `AutoOpenKit.audit`（500） | `prefix` | `insert(at: 0)` 新的在前 | ✅ |
| `DiagKit.recordEvent`（200）/ `recordAttempt`（300） | `prefix` | 同上 | ✅ |
| `DiagKit` 日志（500/300） | `suffix` | `append` 追加 | ✅ |
| `CredentialOrg` 停用便签（200） | `sorted(at>).prefix` | 字典按时间排 | ✅ |
| `CredHistoryStore`（10） | `removeLast` | `insert(at: 0)` | ✅ |
| `LockService.logs`（200）/ `recentFrames`（60） | `removeFirst` | `append` | ✅ |
| `CredBinStore`（100） | `prefix` 丢最旧 | 插入序 | ✅（ROUND-40 修过） |

13 处里只有电池采样没条数上限 —— 又是"同族里只有一处漏了"。

## 4. 方法论

**"有时间上限"给人一种"已经限制了"的错觉。**

判据：**凡是往存储里 append 的数组，都要同时问"时间上限"与"条数上限"两个问题** ——
因为写入成本与存储体积都跟**条数**走，时间只是间接相关。

而且**方向必须逐个确认**：同样叫 `prefix`/`suffix`，数组是"新的在前"还是"追加在后"，
意思正好相反（ROUND-40 就是把方向搞反了，丢掉了刚写入的数据）。
