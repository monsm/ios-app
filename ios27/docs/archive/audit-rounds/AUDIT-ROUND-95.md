# AUDIT-ROUND-95 · 第九十五轮：给记录行加上「通勤」标签（并判定另一个不该接）

> CI：`e736bfa` **已验证**（`errors=0`、`build_ok=1`）—— `KeyItem` 加 `createdAt` 这个模型改动是安全的。
> `bac6cbb`（标定修复）已推送。

## 1. 先判掉一个"看着低成本、其实高成本"的

`TimeWord.word(_:)`（自然时段词：清晨/上午/午间…）的接线点写着"记录组头与行级小字"。
但记录页是**按自然日分组**的（`ForEach(groups)` 每个 group 是一天），而 `TimeWord` 按**小时**给词 ——
粒度不匹配。

要接就得把分组从"按天"改成"按天 + 时段"，那是**改数据结构与视觉层次**，不是加一行字。

所以：**判定为高成本，本轮不接**（并在此记录，避免下一轮又"评估一次"）。

## 2. 接了 `CommuteLabel.tag`（674）

它按「日期 + 小时」判定工作日 7-9 / 17-19，正好能用在**行级**（行已有 `entry.at`）。

```swift
if let commute = CommuteLabel.tag(date: TimeFormat.date(entry.at),
                                  hour: TimeFormat.calendar.component(.hour, from: TimeFormat.date(entry.at))) {
    Text(commute).font(V.F.chipLabel).foregroundStyle(V.C.blue)
}
```

为什么值得标：**通勤时段的开门是"规律性行为"，与随机开门在排查上意义不同**。
用户排查"那天谁来过"时，一眼能分辨"这是我上班那次"还是"别的什么"。

（接线前核对了三处 API：`TimeFormat.date(_:)` 收 `Int64`、`entry.at` 正是 `Int64`、
`V.F.chipLabel` 存在 —— 没有凭印象写。）

## 3. RESERVED 进度

| 状态 | 条数 |
|---|---|
| 已接线 | 4（`removeSearchHistory` / `pwdAgeDays` / `clearAutocal` / `CommuteLabel.tag`） |
| 剩余 | 11 |
| 判定为高成本、暂不接 | 1（`TimeWord.word`） |

## 4. 方法论

**"接线成本"的关键变量是"数据粒度对不对得上"，不是"要不要加一行 UI"。**

`CommuteLabel.tag(date:hour:)` 与行级数据同粒度 ⇒ 一行搞定；
`TimeWord.word(hour:)` 与日级分组不同粒度 ⇒ 要改分组结构。

判据：**评估接线成本时，先比"待接函数的入参粒度"与"接线点的数据粒度"**；
同粒度才是低成本，不同粒度一律按高成本估。
