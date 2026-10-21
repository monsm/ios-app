# 教训：把 Section 换成 XPanel/Group 时踩的两个坑

> 2026-10-21。连续两次 CI 失败，同一个根因。

## 背景

清理 Form→ScrollView 迁移遗留时，需要把 `ScrollView` 里的 `Section` 换掉
（`Section` 在 `List`/`Form` 外没有视觉容器，是死包装）。

## 坑 1：`Section` 可能带 `header:` / `footer:`

```swift
Section {
    ForEach(items) { ... }
} header: {                    // ← 这一行是闭合 + 新开
    Text("逐条处置")
}
```

我用 `Section {` → `XPanel(kind: .group) {` 直接替换，
结果留下 `} header: {` —— `XPanel` 没有这个参数：

```
error: extra trailing closure passed in call
```

**修法**：`header` 的内容搬到 `VStack` 的第一行。

```swift
VStack(alignment: .leading, spacing: XSpace.xs) {
    Text("逐条处置")           // 原 header
        .xFont(.caption, weight: .semibold)
    ForEach(items) { ... }
}
```

**检查方法**：替换前必须做括号匹配找到 Section 的闭合行，
看它是不是 `} header: {` / `} footer: {` / `} header: { ... } footer: { ... }`。

## 坑 2：文件是 CRLF 行尾，`$/ 正则匹配不到`

```js
if (/^(\s*)Section \{$/.test(line))   // ❌ 永不命中（行尾是 \r）
if (line.trim() === 'Section {')       // ✅
```

第一次批量替换时，`AlarmCenterView` 的 3 处"成功"了、`MemberCenterView` 的 3 处
**静默失败**了。因为前者是 LF、后者是 CRLF？不 —— 复查后发现两处都被 `$/ 挡住了，
只是 `AlarmCenterView` 那次用的是 `.trim()` 判断。

**后果**：我以为改完了，实际没改，下一轮扫描才发现。

## 坑 3：`Section("标题") {` 这种形式也被漏掉

除了 `Section {`，还有带标题字符串的：

```swift
Section("前后事件") {
Section("响应时长 (已有 \(n) 条留痕)") {
```

我的扫描模式 `^\s*Section \{$` 完全抓不到。
全仓最后找出 **7 处**这种：

- `AlarmCenterView` 509 / 515 / 737（带标题）
- `AlarmCenterView` 318 / 343（带 header）/ 806
- `MemberExitWizard` 1377 / 1383（带 header）

## 正确的扫描方式

```bash
# 全仓所有 Section（不管后面跟什么）
Select-String -Path App/UI/*.swift -Pattern '^\s*Section[ (]'
```

然后**逐个人工判断**它是不是在 `List` 里。全仓唯一合法的在
`LocksPage.swift:40`（它在一个 `List` 内，需要 `.swipeActions` + `.onMove`）。

## 闸门为什么没拦住

- `swiftcheck` 只查括号平衡 —— 替换后括号仍然平衡，**查不出**
- `swiftshape` 的 R8/R9 只查 `Section("标题")` **带 footer** 的写法 ——
  带 header 的、不带标题字符串的都查不出
- 只有 CI 的 Swift 编译器能报 `extra trailing closure`

## 结论

**容器语义错位（Section 在 List 外）是闸门覆盖不到的一类问题。**
只能靠：

1. 全仓模式扫描 `^\s*Section[ (]`
2. 人工判断每个是否在 `List` 内
3. 替换前做括号匹配确认有没有 `header:`/`footer:`
4. 替换后用 **`trim()`** 而不是正则 `$`
5. **推 CI 验证** —— 这是唯一能确认的方式
