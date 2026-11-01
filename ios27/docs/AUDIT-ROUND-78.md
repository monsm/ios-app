# AUDIT-ROUND-78 · 第七十八轮：「再开一次」的语义比标签窄，而它算出的名字没人用

> CI：`1452c0d` 已验证；`9ffbc1a` / `d252700` 待回执。本轮本地提交。

## 1. 缺陷一：标签承诺"开门"，实际只是"跳到那条凭证"

`runQuick` 的 `case "again"` 是：

```swift
if let t = QuickPool.repeatTarget(app.lock?.id ?? "") {
    router.request(.key(id: t.keyID))      // ← 跳转到凭证详情页
} else {
    router.request(.dest(.keys))
}
```

它**不执行开锁**，只是把用户带到那条高频凭证。从安全角度这是对的（自动重放开锁命令很危险），
但按钮标签只是「再开一次」—— 用户会以为点一下门就开了。

同时 `repeatTarget` 返回的元组是 `(name: String, keyID: String)`，而**调用点只用了 `keyID`** ——
`name` 被算出来却从未被使用。

## 2. 修法：把那个没人用的 `name` 用起来

把目标编号拼进无障碍标签：

```swift
quickLabel(action) = action.id == "again" ? "再开一次：#3" : action.label
```

（视觉标签不动：磁贴空间不够，且编号会随高频目标变化。）

## 3. 顺带修掉一个性能坑

`quickLabel` 在 `ForEach` 里**逐磁贴调用**，而 `repeatTarget` 会扫该锁的历史日志 ——
不缓存就是"每次渲染重扫一遍日志"。本仓在 `alertTable` 上吃过同样的亏（那次是每屏刷新深拷贝全库）。

所以用 `@State var repeatTargetName`，在 `.task`（首帧）与 `.onChange(of: app.lock?.id)`（换锁）各算一次。

## 4. 方法论

**"算了却没人用"是接口设计缺陷的信号，而不是"多余计算"。**

`repeatTarget` 返回 `name` 说明作者**本来打算**让调用方显示它（否则返回 `String` 就够了）。
调用方没用，于是这个信息就白白消失了。

判据：**看到返回值里有未被使用的成员，先问"是不是该用"**，而不是直接删掉那个成员。
本轮就是"该用"的情形 —— 删掉 `name` 只会让标签继续模糊。
