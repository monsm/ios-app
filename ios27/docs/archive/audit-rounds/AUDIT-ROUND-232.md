# AUDIT-ROUND-232 · 第 232 轮：一条**自相矛盾**的过期 TODO

> CI：**`8cf6a28` build + golden 双绿**（`build_ok=1` / `test_ok=1`）—— 把清理从 `delPwd` 挪到 `purge` 的修正编译通过、测试通过。

## 1. 缺陷

`RecordsModels.swift` 的 `RecordsOverlay` 头上写着：

```swift
/// TODO(engine) 真实现落 kf_roverlay_（备注/旗标）与 kf_rdispo（处置结论 + 时刻），
/// 删设备时按族清除；这里先用进程内存储，跨屏共用同一份。
```

而**同一个类的第 175 行**写着：

```swift
/// 内存镜像只用于本页计数与即时刷新；真值落 Engine 的 kf_rnote_ / kf_rflag_ / kf_rdisp_（按锁分族）。
```

**两行互相矛盾**，且第一条是错的：

| 检查 | 结果 |
|---|---|
| `RecordOverlay` 持久层存在？ | ✅ `kf_rnote_` / `kf_rflag_` / `kf_rdisp_` |
| `hydrate` 从持久层读？ | ✅ `RecordOverlay.notes(mac)` |
| 删设备时清？ | ✅ `removeDevice` 的「键名含 mac」兜底网覆盖这三族 |
| 键名 `kf_roverlay_` / `kf_rdispo`？ | ❌ **这两个键名全仓不存在** —— TODO 连名字都写错了 |

## 2. 修法

删掉过期 TODO，写成事实：**持久层早已实现，这个类只是内存镜像**。

## 3. 为什么这条比一般注释更该改

它自带矛盾 —— 下一个人读到第一行会去实现一个**已经存在**的东西，
然后发现 `RecordOverlay` 就在那儿，于是要么重复造一份，要么怀疑自己读错了。

| 过期注释的类型 | 危害 |
|---|---|
| 单纯陈旧（描述旧行为） | 误导 |
| **同一文件内自相矛盾** | **让人怀疑整个文件的可靠性** |

## 4. 方法论

**同一文件里出现"TODO 说没有、下文却说有"时，先信下文（代码就在旁边），再用 grep 定案。**

判据：**TODO 里的键名/函数名要 grep 一次** —— 若它指向的标识符根本不存在，这条 TODO 大概率连同结论一起过期了。

（本轮 `kf_roverlay_` / `kf_rdispo` 两个键名全仓零命中，正是这个信号。）
