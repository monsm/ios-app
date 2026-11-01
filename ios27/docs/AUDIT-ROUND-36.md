# AUDIT-ROUND-36 · 第三十六轮：再验三道闸门（含两次脚本自身出错）

> CI：`aeca8e4` 已验证（errors=0、build_ok=1）；`c12c91d` 待回执

## 1. 结果

| 闸门 | 注入 | 前 / 中 / 后 | 结论 |
|---|---|---|---|
| `glass` | `Text("还没有记录").glassEffect()` | 0 / 1 / 0 | ✅ |
| `dynamictype` | `Text("还没有记录").font(.system(size: 17))` | 0 / 1 / 0 | ✅ |
| `lineage` | `Text(VKTypography.title)` | 0 / 1 / 0 | ✅ |

（前=注入前退出码，中=注入后，后=复原后。三列必须是 0 / 1 / 0。）

## 2. 这轮我自己错了两次，都记下来

**错一：脚本漏传参数。** 第一次跑这三条时，`ctl()` 的第 5 个参数（闸门名）忘了传，
于是执行的是 `node Gates/undefined.js` —— 每次都返回 1。
三条全被记成"异常（注入前就是红的）"。**如果我没看输出里的命令名，就会得出"三个闸门都坏了"的错误结论。**

**错二：`lineage` 的注入符号不在禁表里。** 我先注入了 `Card { ... }`，闸门不红 ——
但读 `lineage.js` 才发现禁表是 `VKTypography / DS.Space / …` 那 18 个，`Card` 根本不在其中。
换成 `VKTypography` 后立刻红。**"闸门没红"有两种可能：闸门坏了，或我注入的不是它管的事。**

## 3. 方法论（对上一轮三步法的补充）

上一轮我写的三步是：注入必须改变文件 / 注入前必须绿 / 复原后必须绿。
这轮暴露了两步缺口：

4. **必须确认跑的是哪个闸门**（命令名要打印出来，不能只看退出码）；
5. **必须确认注入的确实是该闸门的判据**（先去读判据表，别凭印象挑符号）。

否则"正控失败"会被误读成"闸门坏了"，然后去改一个本来正确的闸门 —— 那是更糟的结果。

## 4. 闸门可信度进度

已做可复现正控：`swiftparse` `types` `swiftcheck`? 否 —— 实际为：
`swiftparse` · `types` · `tokens` · `contrast` · `glass` · `motion` · `a11y` · `dynamictype` ·
`lineage` · `privacy` · `feedback` · `modal` · `settings` · `workflow` = **14 / 20**。

剩余 6 道待验：`swiftcheck` · `reducedmotion` · `crosprivate` · `callsig2` · `destmap` · `tests`。
