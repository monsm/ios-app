# AUDIT-ROUND-228 · 第 228 轮：第四样漏删 —— 「提前失效分钟数」会让新凭证被误判成已失效

> CI：`651da0f` 全绿（`project=yes / swift_files=150`）。

## 1. 缺陷

`kf_cestudy_earlyexp_<mac>_<别名>` 是**按别名挂在外面的状态**（详情页那个「提前失效提示」滑杆）。
`delPwd` 不清它。

后果比前几样更重：

```swift
static func isEarlyExpired(_ mac: String, _ p: LedgerPwd, _ now: Date) -> Bool {
    guard earlyExpireMin(mac, p.alias) > 0, let e = effectiveExpiry(mac, p) else { return false }
    return now >= e          // e = 真实到期 − 提前量
}
```

| 场景 | 结果 |
|---|---|
| 旧凭证设了「提前 120 分钟」，删掉 | 键还在 |
| 锁端复用同一别名给新凭证 | 新凭证继承提前量 120 分钟 |
| 新凭证真实到期还有 1 小时 | **被判「已失效」** —— 变灰、被过滤、提醒提前 2 小时弹 |

而界面上只能看到「这条怎么灰了」，**看不出原因**。

## 2. 修法

```swift
static func clearEarlyExpireMin(_ mac: String, _ alias: Int) {
    DB.store.remove("kf_cestudy_earlyexp_" + mac + "_" + String(alias))
}
```

`delPwd` 调用它。

## 3. 「按别名挂在外面的状态」现在清齐了

| 状态 | 键 | 清理点 |
|---|---|---|
| 星标 | `kf_cstar_ui_<mac>` | ✅ 227 |
| 拖拽顺序 | `kf_cseq_<mac>` | ✅ 227 |
| 本机停用位 | `kf_v7_disabled_<mac>` | ✅ 227 |
| **提前失效分钟数** | **`kf_cestudy_earlyexp_<mac>_<alias>`** | ✅ **本轮** |
| 到期提醒 | 系统通知中心 | ✅ 第 94 轮 |

## 4. 方法论

**「派生状态」会随着功能增加而增加，而删除逻辑不会自动跟上。**

| 时间 | 新增的状态 | 删除时清了吗 |
|---|---|---|
| 第 94 轮 | 到期提醒 | ✅ 当时就加了 |
| 后来 | 星标 / 拖拽顺序 / 停用位 / 提前失效 | ❌ 一直没加 |

判据：**每加一个「按实体 id 存的状态」，就在 PR 描述里写一句「删除时清理点：X」。**
写不出来，就是还没想清楚它归谁管。
