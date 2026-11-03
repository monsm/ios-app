# AUDIT-ROUND-337 · 第 337 轮：原生来电滑块 + 滚动截屏算法 + 构建队列减负

> 用户三条指令：① 手开锁只留一种、要系统接电话那种样式；② 截图要**算法级**整页，不是滚到底；
> ③ 安卓/旧版 iOS 构建先停，别占队列。三条全部落地。

## 1. 开锁手势：四套 → 一套（原生来电滑块）

| 删除 | 位置 |
|---|---|
| 按住 0.9 秒（holdProgress / beginHold / holdTask） | DoorScreen |
| 轻点直开（tap 分支） | DoorScreen |
| 双击开锁（handleDoubleTap / lastTapAt） | DoorScreen |
| 沿圆环拖游标（slideStartAngle / angle(of:)） | DoorScreen |
| 圆盘手势态（pressing / armed / firedThisTouch / 进度环 / armed 环） | DoorScreen |
| 手势档四芯片 + 「按住确认开锁」开关 | AccessibilityScreen |
| 「按住确认开锁」开关 | SecurityScreen |

新增 `GlassSlideToUnlock`（Components/Glass*，玻璃闸门 allowlist 内）：

- 玻璃胶囊滑轨 + 圆形玻璃把手（`.glassEffect`，reduceTransparency / 高对比度时退化为不透明）
- 拖动时提示文字渐隐，拖到最右触发**一次**，松手弹回
- 读屏用户不必拖：`.accessibilityAction` 直接触发
- Reduce Motion 下弹回不动画

**圆盘回归纯读数仪表**（电量），不再承担任何手势 —— 它的中心显示电量、下方滑块才是动作。

## 2. 滚动截屏算法（用户指正的核心）

上一版 `-kfScroll` 只是把 ScrollView 锚到底部 —— **中间内容全漏**。这不是滚动截屏，是换个位置截屏。

新算法 `FullPageCapture`：

```
找窗口里 contentSize 最高的 UIScrollView
  → 临时把 frame.height 改成 contentSize.height（全部内容一次进入可见布局）
  → drawHierarchy(afterScreenUpdates: true) 整版渲染
  → 恢复 frame
  → 写 Documents/kf-fullpage-<tab>.png
```

一屏装得下的页面跳过（已有 top 图覆盖）。触发：`-kfFullPage -kfTab N`（仅 CI）。
产物由 `simctl get_app_container` 拷出，**一张图包含整页**，不存在"漏掉中间"。

已知边界（写进文件头）：LazyVStack 离屏行会参与布局渲染；异步图片可能空白 —— 本仓内容以
文本/矢量为主，可接受。真机上这套代码也可当"长截图"分享用。

## 3. 构建队列减负

`ios.yml`（旧版 iOS + Android APK）原来 push 到 main 就跑，与 ios27 抢队列。
改为 **仅 `workflow_dispatch`**（Actions 页手动 Run），三行触发条件注释保留，恢复时取消注释即可。
`ios27.yml` 本来就有 `paths: ios27/**` 过滤，互不干扰。

## 4. 本轮构建事故（诚实记录）

| 错误 | 原因 | 修法 |
|---|---|---|
| `cannot find 'FullPageCapture'` | 文件创建了但 **`git commit -a` 跳过未跟踪文件** —— 第三次栽在同一个坑 | 显式 `git add` |
| `cannot find 'lastFireAt'` | 删手势态时把 `requestUnlock` 还在用的防抖时间戳一起删了 | 补回并注明用途 |
| `types` 闸门报 UIWindowScene 等不存在 | `Gates/sdk-types.txt` 白名单缺 UIKit 截图 API | 补三个类型 |

## 5. 下一轮：玻璃与控件的发散清单（用户要求"每界面每控件"）

按 HIG 功能层/内容层模型，**内容层不铺玻璃**（契约 §6 硬规则），可加玻璃的位置：

| 位置 | 现状 | 方案 |
|---|---|---|
| 门页滑块 | ✅ 本轮已玻璃 | — |
| 标签栏 / 导航栏 | ✅ 系统自带 | — |
| **台账页检索栏** | 卡内嵌 | 提到导航栏下方做浮动玻璃条（搜索框在玻璃胶囊里） |
| **钥匙页凭证工具** | 卡内列表 | 底部浮动玻璃工具条（新增/工作室/动态码三键） |
| **God 模式修池进度** | 无 | 玻璃 sheet + 4 批进度 |
| **Toast** | 已有玻璃 | 复用，无需改 |
| 内容层卡片 | 不透明（正确） | 保持 |

控件/逻辑改进（发散，待用户挑）：

- 开锁成功后圆盘内出现**绿色对勾 + 自动上锁倒计时环**
- 凭证行左侧加**到期临近的琥珀色边条**（不只靠颜色，也能扫）
- 时间线行加**凭证类型小图标**（钥匙/指纹/密码/一次性）
- God 模式「修池」改成**分步进度页**（4 批 PIN 写入逐批打勾）
