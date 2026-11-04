# AUDIT-ROUND-169 · 第 169 轮：176 处按钮补上按压反馈（并让它尊重「减弱动态」）

## 0. 先记一条硬证据

**CI 到 `8144102` 全绿**：`build_ok=1`、`errors=0`、`warnings=0`；
`golden` 作业 `test_ok=1`、`test_failed=0`、**84 tests / 2 skipped / 0 failures**。

这意味着：

| 提交 | 内容 | 结果 |
|---|---|---|
| `6743235` | **iOS 27 `reorderable()` + `reorderContainer(for:)`** | ✅ 编译通过 |
| `b5bf30b` | `VListRow` 无障碍字号换行 | ✅ |
| `8144102` | `confirmationDialog` 挂到触发按钮 | ✅ |

本轮之前最大的未知（`reorderable()` 的 API 形状是否与 `views.md` 示例一致）已经证实。

## 1. 缺陷：101 处按钮**没有任何按压反馈**

```
.buttonStyle(.plain)   101 处
PressStyle()             4 处
DialPressStyle()         1 处
```

`.plain` 在 iOS 上不提供视觉反馈 —— 不亮、不缩。用户点下去得不到确认，
只能靠有没有跳页来判断"点到了没有"。

而本仓**早就定义了** `PressStyle`（透明度 0.72 + 缩放 0.985），只是几乎没用上。
这不是"缺能力"，是"没接上"。

## 2. 修法：接在**三个设计系统组件**上，一次覆盖约 176 处

| 组件 | 覆盖调用点 |
|---|---|
| `VActionButton`（主操作） | 约 60 |
| `VOutlineButton`（次要操作） | 约 76 |
| `VListRow`（设置行） | 约 43 |

三处各把 `.buttonStyle(.plain)` 换成 `.buttonStyle(PressStyle())`，
**调用点一行不动**。这又是"改定义点而不是改调用点"。

## 3. 铺开之前先补守卫：`PressStyle` 原来不尊重「减弱动态」

```swift
// 旧
.scaleEffect(configuration.isPressed ? 0.985 : 1)
.animation(V.M.snap, value: configuration.isPressed)
```

`V.M.snap` 是普通弹簧，**没有减弱动态判断**。只有 4 处用时影响很小；
铺到 176 处就是把一个无障碍缺口放大 44 倍。

```swift
// 新
.scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
.animation(reduceMotion ? nil : V.M.snap, value: configuration.isPressed)
```

减弱动态时**只保留透明度**，不做缩放 —— 与 `accessibility.md` 的"换成淡入淡出"一致。

### 实现细节：为什么用内层 `View` 读环境

`ButtonStyle.makeBody` **不是** `View.body`，`@Environment` 写在外层 `ButtonStyle` 结构体里
不保证被注入。所以把实际操作放进内层 `Private struct PressBody: View`，由它读环境 —— 确定生效。

### 顺带：`PressStyle.Configuration` 改成 `ButtonStyleConfiguration`

`callsig2` 闸门把它报成"PressStyle 没有成员 Configuration"。那其实是**协议关联类型**，
闸门不认识。改写成它的**实际类型** `ButtonStyleConfiguration` —— 既避开假红，也更明确。

## 4. 一个「不是缺陷」的核对：17 个滚动页没有 `scrollEdgeEffectStyle`

扫出 17 个「有 `ScrollView` + `navigationTitle` 但没有 `scrollEdgeEffectStyle`」的文件。

**判定：不是缺陷，不改。** 该 API 的默认值就是 `.automatic`，系统自带边缘效果；
显式写 `.soft` 只是风格偏好。**17 个文件全部不动** —— 改了只会制造 17 处无收益的 diff。

## 5. 方法论

**「仓库里已有正确实现，但没接上」是一类独立的缺陷。**

| 形态 | 例子 |
|---|---|
| 缺实现 | 需要的能力根本不存在 |
| **有实现、没接上** | **本轮：`PressStyle` 定义了，只有 4/101 处用** |
| 有实现、接错了 | `LockSettingsScreen` 绕过 `AppModel.setMuted`（ROUND-147） |

第二种最难发现，因为**搜"有没有实现"会得到"有"**，于是检查就结束了。
正确的问题是：**「定义了 N 次的这个东西，实际被用了几次？」**

本轮的问法：

```
grep "ButtonStyle"  →  自定义 PressStyle 存在
grep "\.buttonStyle\(\.plain\)"  →  101 处
```
两个数字放在一起，缺陷就显形了。
