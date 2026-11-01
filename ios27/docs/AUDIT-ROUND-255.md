# AUDIT-ROUND-255 · 第 255 轮：恢复完备份，设置页还是旧值

> CI：**`e8bccb8` build 全绿**（rcHint 补充编译通过）。

## 1. 怎么发现的

把 `SettingsStore` 里所有可观察键抽出来（27 个），再全仓搜「**直接**写这些键」的地方：

| 写入点 | 判定 |
|---|---|
| `AutoOpenKit` 两处 | ✅ 它自己属性的 setter，不算绕过 |
| **`BackupKit` 六处**（手势档 / 按住确认 / 大字 / 表盘尺寸 / 数字字体 / 双击防抖…） | ⚠️ 恢复路径，直写可接受 —— **但从不通知** |

恢复路径**全仓零处** `SettingsStore.shared` / `revision` 相关调用。

## 2. 缺陷

`@Observable` 的失效靠 `revision`。恢复时直接写 DB 键、不 bump `revision` ⇒
**已经渲染过的设置页不会重算**，用户恢复完备份去看设置，看到的还是恢复前的值，直到 App 重启。

| 时刻 | DB 里的值 | 设置页显示 |
|---|---|---|
| 恢复前 | 手势 = 轻点 | 轻点 |
| 恢复后（包内是长按） | 手势 = **长按** | **轻点**（旧值） |

## 3. 修法

1. `SettingsStore` 增加 `notifyChanged()`（`revision &+= 1`），并写明「直写存储的路径必须调它」。
2. `applyGlobalsAppearanceAndOrg` 末尾投递一次通知。

## 4. 一个必须绕开的坑

`applyGlobalsAppearanceAndOrg` 是 `DB` 的**非隔离静态函数**，而 `SettingsStore` 是 `@MainActor`：
直接调用会产生**并发告警**，而 CI 的判据是「源码 0 warning」。

改用 `Task { @MainActor in SettingsStore.shared.notifyChanged() }` —— 闭包内是主 actor 上下文，不告警；
恢复本身是同步长任务，这次通知在下一轮 runloop 落地，远早于用户打开设置页。

## 5. 方法论

**「直写存储」是允许的，但必须配套「显式通知」—— 两者是一对，不能只做前一半。**

| 路径 | 直写存储 | 需要通知吗 |
|---|---|---|
| 界面上的开关 | ❌ 不该直写 | —— |
| **备份恢复 / 迁移 / 重置** | ✅ 可以直写 | ✅ **必须** |

判据：**每加一处「绕过可观察包装的直写」，就在同一函数末尾补一次 `notifyChanged()`。**
本轮之前，这条恢复路径写了 20+ 个键、一个通知都没有。
