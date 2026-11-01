# AUDIT-ROUND-235 · 第 235 轮：同一个 URL 拼接坑的第二处（`test()`）

> CI：**`bd0f594` build 全绿**；`238f2cc` / `3d37c55` 排队中。

## 1. 缺陷

Round 234 修了 `upload()` 的 URL 拼接，但 `test()` 里是**同一个形状**：

```swift
guard let url = URL(string: normalized(base)) else { throw BLEErrorX.msg("WebDAV 地址不是合法 URL") }
```

用户粘贴的地址里带空格（`https://dav.example.com/my folder/`）时：

| 操作 | 结果 |
|---|---|
| 「测试连接」 | ❌ 「地址不是合法 URL」 |
| 「上传」 | ✅（Round 234 已修） |

**同一个配置、两个按钮给出不同结论** —— 这种不一致比两个都错更难查。

## 2. 修法

```swift
guard let comps = URLComponents(string: normalized(base)), let url = comps.url
else { throw … }
```

## 3. 本轮另外 2 项「审过、正确」

| 检查 | 结论 |
|---|---|
| `tel://` 两处拼接（`HouseholdScreen` / `MemberDetailScreen`） | ✅ 先 `phone.filter(\.isNumber)` 只留数字，不存在特殊字符 |
| `SettingsScreen` 的 `URL(string: UIApplication.openSettingsURLString)` | ✅ 系统常量，非用户输入 |

## 4. 方法论

**修一个"形状"时，要 grep 这个形状，不是 grep 这个函数。**

| 修法 | 覆盖 |
|---|---|
| 改 `upload()` | 1 处 |
| **grep `URL(string:`** | **找到 `test()` 这第二处** |

判据：**修完一处后，把"出错的那一行代码形状"当搜索词再 grep 一次** ——
本轮的形状是 `URL(string:` + 字符串拼接，全仓 7 处，逐处判定后 2 处需要修。
