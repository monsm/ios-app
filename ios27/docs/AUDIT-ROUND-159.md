# AUDIT-ROUND-159 · 第 159 轮：两处自定义控件改原生（一改覆盖 65 处调用）

> CI：`61b9037` 已验证绿；`95a036a`（液态玻璃）待回执。
> 本轮继续 objective 的「尽可能有原生控件就用原生控件」。

## 1. 档位选择：自定义 chip 行 → 原生 `Picker(.segmented)`

`SettingChips` 有 **10 处调用**，全部是 3–4 档的枚举：

| 设置项 | 档数 |
|---|---|
| 主题 `AppearanceTheme` | 4 |
| 密度 `LayoutDensity` | 3 |
| 动效 `MotionTier` | 3 |
| 时间显示 `TimeDisplayStyle` | 3 |
| 面容确认 `FaceConfirmTier` | 3 |
| 圆角 / 行高 / 行距 / 主控读数 / 记录页 | 2–3 |

这正是 `.segmented` 的标准场景。改造后**一个定义点覆盖 10 处**：

```swift
Picker("", selection: $selection) {
    ForEach(items, id: \.self) { Text(title($0)).tag($0) }
}
.pickerStyle(.segmented)
.labelsHidden()
```

原生的收益（自定义 chip 行都要自己写，且很难写全）：

| 能力 | 自定义 chip | 原生 segmented |
|---|---|---|
| VoiceOver 语义 | 自己写 `.isSelected` | 系统给「第 N 项，共 M 项」 |
| Switch Control / 全键盘 | 无 | 有 |
| 系统外观（含 iOS 26 材质） | 自己画 | 自动 |
| Dynamic Type | 自己处理 | 自动 |

**保留 `VChipRow`** 给档位多到放不下的场景（家页分组标签、凭证类型筛选）——
那种情况分段控件会被压扁，`ScrollView` 里的 chip 行反而更合适。已在注释里写明这条边界。

## 2. 读数行：手写 HStack → 原生 `LabeledContent`

`VFieldRow` 有 **55 处调用**。旧写法：

```swift
HStack { Text(label); Spacer(minLength: gapS); 值 }
.accessibilityElement(children: .combine)
```

新写法：

```swift
LabeledContent { 值 } label: { Text(label) }
```

两处收益：

| 维度 | 旧（手写） | 新（`LabeledContent`） |
| **文字占用** | 长标签 + 大字号时，`Spacer(minLength:)` 挡不住，**数值被压缩甚至截断** | 系统先给标签让位：标签换行，数值保持完整 |
| **无障碍** | `.combine` 只是"合并"，语义仍是一串文字 | 系统读成「型号，K1」这种**标签-值对** |

`LabeledContent` 还自动处理 RTL 与系统强调色。

## 3. 顺带删掉一处死代码

`Design/Components/Reading.swift` 里有个 `FieldRow` —— 与 `VFieldRow` **功能完全重复**，
且**零调用**（`grep "\bFieldRow("` 无命中）。按本仓既有判据（零调用 + 无需求编号 + 无接线点 = 死代码）删除。

删除后 `swiftcheck` 与 `swiftparse` 均通过。

## 4. 本轮的原生控件统计（改造前后）

| API | 改造前 | 改造后 |
|---|---|---|
| `Picker` | 1 | **+1 处定义覆盖 10 个调用点** |
| `LabeledContent` | 0 | **+1 处定义覆盖 55 个调用点** |
| `glassEffect` | 0 | 1（唯一入口 `VGlassSurface`） |

## 5. 方法论

**「原生控件」要改在"定义点"，不是"调用点"。**

`SettingChips`（1 个定义 / 10 处调用）与 `VFieldRow`（1 个定义 / 55 处调用）都是**单点改造覆盖全场**；
如果逐个调用点去改，既要改 65 处，又会改出不一致。

判据：**动手前先问"这个自定义控件有几个调用点、有没有唯一入口"** ——
有唯一入口就先改定义，没有就先抽一个入口。
