# AUDIT-ROUND-13 · 第十三轮：我上一轮修的密度缩放，其实改坏了设计稿

> 执行日期：2026-11-01 08:05 → 08:40（+08:00）
> 起点 `33d2c1b` → 终点 `db31ecf`
> CI：build `errors=0`；golden **54 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **1 个缺陷**（上一轮我自己引入的） |
| 新增测试 | **4 条**（`DensityScaleTests`） |
| 测试总数 | 50 → **54**，7 文件 |
| 闸门 | 20 / 20 |

---

## 1. 我上一轮的密度缩放**改坏了默认档**

上一轮把死开关 `LayoutDensity` 接到 `V.S` 间距上，写法是：

```swift
private static func d(_ base: CGFloat) -> CGFloat { (base * densityScale).rounded() }
static var gapS: CGFloat { d(7.7) }
static var gapM: CGFloat { d(14.3) }
```

本轮逐个验算三档的实际取值，发现两个问题：

### ① 默认档（标准 = 1.0）不再等于设计稿

设计令牌是**刻意的亚像素值**（7.7 / 14.3 / 16.3 / 14.67 —— 它们来自设计稿的具体测量）。
`.rounded()` 在系数 1.0 时就把它们改掉：

| 令牌 | 设计值 | 取整后 |
|---|---|---|
| gapS | 7.7 | **8** |
| gapM | 14.3 | **14** |
| cardPad | 16.3 | **16** |
| cardGutter | 14.67 | **15** |

也就是说**用户什么都没选的状态**（最常被看到的状态）偏离了设计参考。
"接线让开关生效"绝不能以改坏默认外观为代价。

### ② 最小两档被压平

`gapXXS(2)` 与 `gapXS(4)` 在三档下都取整成同一个值：

| 令牌 | 紧凑 | 标准 | 宽松 |
|---|---|---|---|
| gapXXS | 2 | 2 | 2 |
| gapXS | 4 | 4 | 4 |

用户改档位时**最小的间距纹丝不动** —— 观感上像"只改了一半"，这本身又是一种假开关。

### 修法：不取整

```swift
private static func d(_ base: CGFloat) -> CGFloat { base * densityScale }
```

SwiftUI 的布局是浮点运算，亚像素值本来就合法（与设计稿逐值一致）。
现在三档的实际值：

| 令牌 | 紧凑 (0.88) | 标准 (1.0) | 宽松 (1.12) |
|---|---|---|---|
| gapXXS | 1.76 | 2 | 2.24 |
| gapS | 6.776 | 7.7 | 8.624 |
| gapM | 12.584 | 14.3 | 16.016 |
| gapXXL | 28.16 | 32 | 35.84 |

---

## 2. 新增测试：`DensityScaleTests`（4 条）

把"接线不能改坏默认"这条纪律变成可执行断言：

| 测试 | 钉住什么 |
|---|---|
| `testStandardTierReproducesDesignValuesExactly` | 默认档**逐值精确**等于设计稿（有人加回 `.rounded()` 立刻红） |
| `testTiersAreStrictlyMonotonic` | 三档**严格**递增（取整压平小值会红） |
| `testTierDifferenceIsPerceptible` | 主间距（14.3）紧凑↔宽松至少差 3pt —— 否则用户看不出，等于假开关 |
| `testHitTargetIsNotScaledByDensity` | 读源码断言 `V.Hit.min` 是字面 44，**不是** `d(44)`（后者紧凑档会跌到 38.72，低于 HIG 下限） |

第 4 条特意做成"读源码"而不是"算数值" —— 因为它要防的是**未来有人把命中区也塞进缩放**，
那种改动在当前数值上是看不出来的（44 在标准档仍是 44）。

---

## 3. 这一轮的方法论收获

**"修好一个开关"和"修好一个开关且没弄坏别的东西"是两件事。**

上一轮我验证的是"改档位有变化了吗"（有），但没验证：
- 默认档还等于设计稿吗？（**不等了**）
- 三档每一档都真的不同吗？（**最小两档没变**）

所以这一轮的检查方式改成：**把三档 × 全部令牌的取值打成表格逐个验算**，
而不是"抽一个值看看有没有变"。表格立刻暴露了这两个问题。

---

## 4. 验证链

```
$ node Gates/allgates.js
… 20 道闸门全部通过
settings: OK - 30 settings all have a direct consumer

$ git show origin/ci-log:meta.txt
commit=db31ecf… errors=0  build_ok=1  archive_ok=1

$ git show origin/ci-test:meta.txt
commit=db31ecf… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=54
```

---

## 5. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
SEC-01 残余（Swift `String` 无法清零）· SEC-18 残余（需真机）·
SEC-22（固件 AES-ECB 限制）· SEC-26（出口合规需法律复核）·
SEC-01 单测（未签名宿主无钥匙串权限 ⇒ CI skipped）· D-12（竖屏产品决定）。

### P3
D-11 已确认误报。D-14（DesignLab `<img>` 缺 alt）、`ForEach` 下标身份若干处、
`.toolbar(.hidden, for:)` 软废弃、VoiceOver 转子（可选优化）。

### 需要真机/人工的
SwiftUI 真实渲染与浅色主题观感、手势、触觉、BLE 回执、指纹录入、
DFU 真实续传、WebDAV 真实链路。
**密度三档现在数值上正确了（默认档与设计稿逐值一致），但"12% 的间距差异是否观感合适"
仍需人眼确认** —— 这是本轮之后最具体的待人工项。
