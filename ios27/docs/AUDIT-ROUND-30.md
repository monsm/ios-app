# AUDIT-ROUND-30 · 第三十轮：列表读取器判空壳，单条读取器不判

> CI：`eea6ef1` 已验证（errors=0、build_ok=1）；`98da7ed` / `2d38982` / 本轮提交待回执

## 1. 缺陷：同一份数据，列表视图空壳、详情视图不空壳

| 读取器 | 空壳过滤 |
|---|---|
| `members()` | 有 |
| `member(id)` | **无** |
| `dongles()` | 有 |
| `dongle(mac)` | **无** |
| `gateways()` | 有 |
| `gateway(mac)` | **无** |

后果：空壳模式下凡是用**单条读取器**取名字/读数的界面，都会把真实数据显示出来 ——
而列表页是空的。这比"两处都漏"更糟：看起来"空壳生效了"，实际只是列表路径生效了。

`MemberHub` 里 `DB.member(id)?.name ?? "成员"` 这类用法就是直接读单条。

## 2. 修法（单条过滤 + 写路径配 raw）

`member(id)` 直接加过滤即可 —— 所有成员写函数都自己 `getDict("kf_members")`，不经过它。

但 `dongle` / `gateway` 不同：**写函数反向依赖这个读取器**做"空字段沿用旧值"的合并
（`saveDongle` 里 `if let old = dongle(d.mac)`）。若只加过滤，空壳里保存会把旧字段丢光。
所以：

- 新增 `rawDongle` / `rawGateway`（读原始存储，private）；
- 写函数改用 raw 版本合并；
- 公开的单条读取器加空壳过滤。

## 3. 防复发：privacy 闸门第 18 条

`Store.swift` 里 `member()` / `dongle()` / `gateway()` 的函数体内**必须**出现 `isDecoy`。

第一版规则写成"有 isDecoy **或**有 raw 就放行" —— 结果任何调 raw 包装的函数都能过，
把自己刚修的实现判成绿。收紧成只认 `isDecoy` 后才真正抓得住：

```
privacy: FAIL — 1 处回归
  Engine/Store.swift:310 — dongle() 没有空壳过滤（列表读取器有，单条没有 → 不一致泄露）
    → 加 if isDecoy { return nil }，写路径改用 raw 版本
```

## 4. 方法论

**"同一份数据的多个入口"是这类缺陷的温床。**
列表版与单条版往往由不同时间、不同需求写成，一个补了过滤另一个没补，
而它们的调用方（列表页 / 详情页 / 后台任务）也各不相同，于是漏的那个不容易被发现。

判据：**给一组数据加访问控制时，先枚举它的全部读取入口（列表 + 单条 + 计数 + 导出），一次性都补上。**
本轮就是按这条做的：`members/member`、`dongles/dongle`、`gateways/gateway` 三对一起。
