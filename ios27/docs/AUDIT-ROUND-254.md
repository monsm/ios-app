# AUDIT-ROUND-254 · 第 254 轮：改完手势档，门页不生效 —— 两份真相

> CI：**`8beeb83` build 全绿**（重试策略修复编译通过）。

## 1. 缺陷

开锁手势有两个写入点、两个读取点，**彼此不通知**：

| 位置 | 做法 |
|---|---|
| `AccessibilityScreen` 的档位按钮 | `DB.store.set("kf_gesture_mode", …)` **直写** |
| `AccessibilityScreen` 的「按住确认」开关 | `DB.store.set("kf_hold_confirm", …)` **直写** |
| 门页 `effectiveGesture` | `AXSettings.gestureMode`（**静态 DB 读**）/ `SettingsStore.shared.holdConfirm`（可观察） |

`@Observable` 只跟踪 `SettingsStore.revision`。**直写 DB 键不 bump revision** ⇒ 门页不会重算，
改完档位回到门页，手势还是旧的 —— 要等下一次别的原因刷新才生效。

## 2. 修法

| 改动 | 说明 |
|---|---|
| `SettingsStore` 新增 `gestureMode` | 与 `holdConfirm` 同款：getter `_ = revision`、setter `revision &+= 1` |
| 门页 `effectiveGesture` | 改读 `SettingsStore.shared.gestureMode`（可观察） |
| 无障碍页两个 setter | 改走 `SettingsStore`，不再直写 DB 键 |

## 3. 为什么这是「两份真相」而不是小瑕疵

该文件**自己**在第 27 行写着：

> …（会整体重置 axBigText / holdConfirm 等）时，这一页会继续显示旧值 —— **两份真相**。

作者已经意识到"这一页"与"别处"会不一致，但当时只处理了**显示**（`onAppear` 重新读），
没处理**通知**（写的时候不 bump revision）。于是：显示是对的，行为是错的。

## 4. 方法论

**「直写存储」这种图省事的做法，会绕过可观察层的失效机制 —— 而症状是"设置好像没生效"。**

| 写法 | 谁会被通知 |
|---|---|
| `DB.store.set(key, v)` | 只有下次读 DB 的人 |
| **`SettingsStore.shared.x = v`** | **所有观察 `SettingsStore` 的视图** |

判据：**任何"设置项"的写入都必须经过它对应的可观察包装，直写 DB 只允许出现在迁移/恢复/重置这类
不面向界面的路径。**
