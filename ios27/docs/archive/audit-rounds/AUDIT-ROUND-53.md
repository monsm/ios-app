# AUDIT-ROUND-53 · 第五十三轮：44pt 是下限，不是上限

> CI：`8d2c96b`（八笔批次）刚推送，回执未到。本轮本地提交，不推送。

## 1. 缺陷：8 处按钮写死了高度

全仓 8 处 `.frame(height: V.H.action)`，都在**按钮**上（`PrimaryAction` / `SecondaryAction` /
`LockKeeperApp` 两个解锁按钮 / `SettingsParts` / `RecordExportScreen` 三处）。

`V.H.action` 是 44pt —— HIG 里那是**可点区下限**。写成 `height` 就等于把它当上限：

> 用户把动态字号调到最大时，按钮标题会超出 44pt 的容器。
> SwiftUI **不会报错**，只是把文字裁掉（或压成一行溢出）—— 用户看到的是"按钮上字没了"。

这类问题静态闸门抓不到（`a11y` 只查"可点区 ≥44pt"，写死 44pt 恰好满足它），
所以它一路绿到现在。

## 2. 修法

8 处全部改成 `.frame(minHeight: V.H.action)`：保留下限，允许随字号增高。
按钮因此仍是至少 44pt（HIG 满足），但在大字号下会自然变高而不是裁字。

## 3. 为什么不用 `.fixedSize` 或 `minimumScaleFactor`

- `.fixedSize` 会让文字不换行地溢出容器边界（更糟）；
- `minimumScaleFactor` 是"把字缩小以适应容器"—— 对一个**本来就要支持大字**的 App，
  这是把无障碍设置反向抵消掉。

正确方向是**容器让位给文字**，不是文字让位给容器。

## 4. 方法论

**"最小可点区"这个数值一旦被写成固定尺寸，就从保护变成了限制。**

判据：凡是 `V.H.min` / `V.H.action` 这类**下限令牌**，只应出现在 `minHeight` / `frame(minWidth:)` 里；
出现在 `height` / `width` 里就是误用 —— 这一条可以做成闸门（`a11y` 加一条：
`frame(height: V.H.*)` 一律判红）。下一轮补。
