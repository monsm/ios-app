# AUDIT-ROUND-34 · 第三十四轮：再验两个闸门，并纠正一次"假正控"

> CI：`d1bf3b5` 已验证（errors=0、build_ok=1）；`ci-test` 上 `5136831` 的 golden 为 `test_ok=1`
> —— 说明 gates job 在 CI 里是绿的，只是 `ci-log`（build 日志分支）滞后。

## 1. 两个正控

| 闸门 | 注入 | 结果 |
|---|---|---|
| `types` | 在 `Locked.swift` 末尾追加一个同名 `final class Locked` 声明 | 红 ✅（`重复声明 Locked → Engine/Locked.swift + Engine/Locked.swift`） |
| `swiftparse` | 在 `enum HexKit {` 后插入一个孤立 `(` | 红 ✅ |

## 2. 一次"假正控"，以及它为什么值得记

第一次做 `types` 正控时，我把"注入"写成了**原文替换原文**（`from` 与 `to` 完全相同），
也就是**什么都没改**，却记录成"红色（正确）"。

后来单独跑 `node Gates/types.js` 才发现：干净树上它本来就 `EXIT=0`。
也就是说那次结论是**假**的 —— 不是闸门有效，是我的正控脚本报错了。

重做（真的追加一个重复声明）之后，才拿到可信结论：红，且复原后绿。

## 3. 方法论

**"正控通过"本身也需要证据。** 一个正控要成立，至少要满足：

1. 注入确实改变了文件（写完后读回来比对）；
2. 闸门在注入前是绿的（否则"红"可能本来就是红的）；
3. 复原后重新变绿（否则可能改坏了别的）。

我这次漏了第 1 步。以后每个正控都按这三步走 —— 否则"我做过正控"这句话本身
就和被审计的那些"命名即承诺"是同一类问题。

## 4. 当前闸门可信度（累计）

已做过**可复现**正控的：`swiftparse` · `types` · `tokens` · `contrast` · `a11y` · `motion` ·
`privacy` · `feedback` · `modal` · `settings` · `workflow`（共 11 道 / 20）。
其余 9 道（`swiftcheck` `glass` `dynamictype` `reducedmotion` `crosprivate` `callsig2`
`lineage` `destmap` `tests`）尚未逐个做，属下一批。
