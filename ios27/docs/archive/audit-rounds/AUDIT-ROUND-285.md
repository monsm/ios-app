# AUDIT-ROUND-285 · 第 285 轮：记录页的备注/标旗计数**跨锁累加**，且「全部锁」模式看不到别的锁的

> CI：`9b7e853` build 全绿。

## 1. 缺陷一：内存镜像是**累加**，不是重建

    func hydrate(mac: String) {
        for (key, value) in RecordOverlay.notes(mac) { notes[key] = value }   // 只 insert
        for key in RecordOverlay.flags(mac) { flagged.insert(key) }
    }

而界面拿到的是 `overlay.notes.count` / `overlay.flagged.count` / `overlay.disposed.count`：

| 操作 | 计数 |
|---|---|
| 在 A 锁下进记录页（A 有 3 条备注） | 备注 3 条 ✅ |
| 切到 B 锁（B 有 2 条）再进记录页 | **备注 5 条** ❌ |

## 2. 缺陷二：「全部锁」模式只水合**一把**锁

    overlay.hydrate(mac: mac.isEmpty ? app.currentMac : mac)

`mac` 在「全部锁」范围下是空串 ⇒ 回落成**当前锁**。于是：

| 现象 | 原因 |
|---|---|
| 列表里别的锁的行**显示不出备注/标旗** | 那些锁的覆盖层压根没进内存 |
| 计数偏小 | 同上 |

## 3. 修法

| 改动 | 说明 |
|---|---|
| `hydrate(macs: [String])` | **整份重建**（先清空再装），支持多把锁 |
| `hydrate(mac:)` | 保留为单锁便捷入口（详情页在用） |
| `reload()` | 先算 `targets`，再 `overlay.hydrate(macs: targets.map(\.mac))` |

内存镜像本来就只是「本页投影」，整份重建既简单又不会漂 —— 累加式更新只适合「只增不减」的数据。

## 4. 方法论

**「内存镜像」必须明确它是**缓存**还是**累积账本** —— 两者对不存在的键的处理完全相反。**

| 语义 | 更新方式 |
|---|---|
| 缓存/投影（本处） | **重建**：以持久层为准，整份替换 |
| 累积账本 | 增量 insert |

判据：**凡是「按实体加载到内存、供界面计数/判断」的镜像，一律整份重建；增量只在账本类数据上正确。**
