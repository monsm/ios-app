# AUDIT-ROUND-127 · 第一百二十七轮：核对测试质量与 CI 实跑证据

> CI：`8368291` 全绿；金标 **82 tests / 0 失败 / 2 skipped**（原 80）。
> `24a9551` / `834693f` 待回执。本轮无代码改动。

## 1. 硬证据：我加的两个测试确实在 CI 真跑并通过

```
Test Case '-[LockKeeperTests.FormatterConsistencyTests testDevLayoutKeepsUserOrder]' passed
Test Case '-[LockKeeperTests.TimeBasisTests testDayTitleCarriesYearWhenNotCurrentYear]' passed
Executed 82 tests, with 2 tests skipped and 0 failures
```

这是本段一直强调的判据：**"写了测试" ≠ "测试在跑"**。
要看到 `passed` 行 + `Executed N tests` 才算数。

## 2. 测试形状普查

统计各文件的断言构成（`Equal` 是"两值比对"，其余是"属性/存在/范围"断言）：

| 文件 | 用例数 | `Equal` | 其它 |
|---|---:|---:|---:|
| `GoldenDiffTests` | 16 | 68 | 5 |
| `SecurityRegressionTests` | 28 | 64 | 45 |
| `BackupRoundTripTests` | 9 | 16 | 15 |
| `TimeBasisTests` | 9 | 10 | 13 |
| `FormatterConsistencyTests` | 7 | 11 | 5 |
| `ConcurrencyTests` | 6 | 7 | 5 |
| `DensityScaleTests` | 4 | 2 | 4 |
| `SheetPresentationTests` | 4 | 4 | 9 |

`GoldenDiffTests` 是 `Equal` 密度最高的（68:5）—— 它做的是"Swift 输出 vs JS 金标逐字节比对"，
这个形状**天然正确**（金标是外部真值，不是"另一个实现"）。

## 3. 检查了 `GoldenDiffTests` 是否掉进"比对测试盲区"

上轮的教训是：**当 A 和 B 都错得一样时，`assertEqual(A, B)` 永远通过**。
`GoldenDiffTests` 会不会这样？

关键差别：**金标 `fixtures/golden.json` 来自 vendor JS 的真实输出，是外部真值** ——
不是本仓的第二份实现。所以它不是盲区。

而且它已经**主动防了另一个坑**：

```swift
/// 夹具必须真加载到。为空时下面每条断言都会在空集合上"通过"，等于没测。
func testGoldenFixtureLoaded() throws {
    XCTAssertFalse(GoldenDiffTests.golden.isEmpty, "fixtures/golden.json 未加载进测试 bundle")
    for k in ["aes", "cmds", "parse", ...] { XCTAssertNotNil(golden[k]) }
    XCTAssertEqual(cmds.count, 40, "金标 cmds 应为 40 条")
}
```

**"资源没打进 bundle 时全套会静默通过 —— 那比红更糟"** 这句注释写得很到位，
而它确实实现了（不是只写在注释里）。

各用例还用 `try XCTUnwrap(...)` 而不是 `as?` + 可选绑定 —— 夹具缺键会**抛错**而不是静默跳过。

## 4. 本轮结论

测试体系整体健康，无缺陷。没有为了"有产出"而改任何代码。

## 5. 方法论

**"测试文件多、断言多"不等于"测得对"。三个具体判据**：

| 判据 | 怎么查 |
|---|---|
| 测试真的在跑 | CI `test.log` 里有 `passed` 行 + `Executed N tests` |
| 比对测试有没有外部真值 | 若 A、B 都是本仓实现 ⇒ 有共同出错盲区 |
| 夹具缺失会不会静默通过 | 有 `testXxxFixtureLoaded` 前置用例 + `XCTUnwrap` 而非 `as?` |

本轮三条都查了，`GoldenDiffTests` 三条都过。
