# 动效频率核查表 (882 闪烁安全线, WCAG 2.3.1)

> 全 App 循环/闪烁类动效逐项登记。纪律: 任何周期性明暗/颜色变化的频率必须 ≤3Hz
> (WCAG 2.3.1 闪光灯阈值); 超阈值的动效必须在"减少动态效果" (227) 下降级为静态。
> 频率 = 1 / 完整循环周期 (s)。

## 循环动效清单

| 动效 | 落点 | 周期 | 频率 | 降级 (reduceMotion) |
|---|---|---|---|---|
| 呼吸光晕 (圆盘 idle) | UnlockDial.swift 呼吸环 | 2.4s 往复 | 0.42Hz | 静止, 保留静态光晕 |
| 待机流光 | UnlockDial.swift UnlockShimmer | 3.2s 环绕 | 0.31Hz | 不出现 |
| Hero 高光漂移 | DesignSystem.swift HeroCard | 9s 往复 | 0.11Hz | 静止 |
| 流光徽章边 (999) | HeroFlairBorder | 1.6s 往复 | 0.63Hz | 静态常亮 |
| 喂电呼吸图标 (1004) | BreathingGlyph | 1.4s 往复 | 0.71Hz | 静止 |
| AppLock 盾呼吸 | LockKeeperApp.swift AppLockView | 3.2s 往复 | 0.31Hz | 静止 |
| 失败搜索符号迭代 | symbolEffect variableColor | 系统迭代 ~1.1s | ≤0.9Hz | 关闭 symbolEffect |
| 881 字幕过程条 | CaptionStepBar | 非循环 (相位推进) | 0 | 静态 |

全部 ≤3Hz ✓。新增循环动效必须先入本表并核算, 超 3Hz 的闪烁在"减少动态效果"下必须静止或降级, 且不得承载唯一信息。
