# AUDIT-ROUND-24 · 第二十四轮：ARCHITECTURE 的闸门表只列了 9 道（实际 20）

> CI：`87ee8f8` 已验证（errors=0、build_ok=1）；`98d5fb6` 与本轮提交待回执

## 1. 与上一轮同类的失真，这次在 ARCHITECTURE.md

上一轮修了 README 的闸门表（12 → 20）。本轮查 `docs/ARCHITECTURE.md`，发现它的闸门表**只列 9 道**，
缺 11 道：`types`、`dynamictype`、`reducedmotion`、`crosprivate`、`callsig2`、`workflow`、
`privacy`、`tests`、`feedback`、`modal`、`settings`。

而且三处细节也错了：

| 位置 | 写的 | 实际 |
|---|---|---|
| `contrast` 行 | 「48 条 WCAG 断言」 | 现场解析，当前 76 条（且不该钉死） |
| `tokens` 行 | 「白名单只有 2 条」 | 3 条（两个令牌层 + Dial 的 Canvas 几何） |
| 「做过正控的」 | 只列 4 道（swiftparse/tokens/contrast/a11y） | 实际已对 9 道做过正控 |

## 2. 修法

- 表格补齐到 20 行，按 `allgates.js` 的真实顺序编号；
- 加一句「**当前共 20 道**（这个数字由 `Gates/workflow.js` 对账）」，把它纳入自动核对；
- `contrast` 改为描述"现场解析"而不钉条数；
- 「做过正控的」补齐：`feedback` / `modal` / `settings` / `privacy` / `workflow` 都做过，
  并注明 `settings` 是 warn-only（宁可不判红也不产生假红）。

## 3. 防复发

`workflow.js` 的闸门数对账从 2 个目标扩到 **3 个**：README、CI 工作流、ARCHITECTURE。
已验证：把 ARCHITECTURE 改成「当前共 19 道」立刻红 ——

```
workflow: FAIL — 1 处
  docs\ARCHITECTURE.md 声称 19 道，实际 20 道（与 allgates.js 的 GATES 不一致）
```

## 4. 方法论

**同一类失真会出现在多处，修一处不等于修完。**
上一轮只修 README 时我以为"文档数字"这件事已经闭环；实际上 ARCHITECTURE 里还有一份更旧的地图。
所以本轮的修法不只是补内容，而是把「对账」扩展成覆盖所有声明了数量的文件 ——
这样下一处漏网会被闸门抓到，而不是靠我下次想起来去看。
