# AUDIT-ROUND-121 · 第一百二十一轮：5 个「有读无写」的键，全部已有处置

> CI：`ca5b563` 全绿（build + golden，`errors=0`、`warnings=0`）；`9da0da6` / `91a7f06` 待回执。

## 1. 把上轮的判据做成机械扫描

上轮发现 `kf_week_start` 的方法（**读某键 → 搜谁写它**）是手动的。这轮写成脚本：

```python
for m in re.finditer(r'DB\.store\.get(?:String|Int|...)\("([^"]+)"', s): reads[k].add(f)
for m in re.finditer(r'DB\.store\.set(?:...)?\("([^"]+)"\', s): writes[k].add(f)
ro = [k for k in reads if k.startswith("kf_") and k not in writes]
```

结果：**5 个**「有读无写」的静态键。

## 2. 逐个核查：5 个全部已有明确处置

| 键 | 处置 | 出处 |
|---|---|---|
| `kf_week_start` | 上轮已判：保留未接 + 登记 | `WeekCal` 新标记 |
| `kf_calias_display` | **已记录**："全仓没有 setter —— 这个开关目前改不了" | `CredentialOrg.swift:18` |
| `kf_speek_sharehalf` | **已记录**："原开关 UI 已删，键名直读 —— 默认值即行为" | `LockGuard.swift:10-17` |
| `kf_debug_raw` | **已处理**："诊断页原始帧面板此前恒为空（帧只在 debugRaw 打开时才进缓冲），已改为帧照常进内存" | `LockService.swift:46` |
| `kf_trial_guard` | **假阳性** —— 写入走 `TrialGuard.set`（间接），我的正则没匹配到 | `SettingsParts:337` |

## 3. 假阳性教的一课

我的脚本匹配 `DB.store.set("kf_trial_guard", ...)` 这种**直接**调用，
而真实写入是：

```swift
// TrialGuard.swift
static func set(_ v: Bool) { DB.store.setBool(key, v) }   // 键名经 key 常量间接传递
```

**静态正则扫描抓不到"键名经常量中转"的写入。**
所以这个脚本的结论只能当**候选清单**，每个候选都必须像本轮这样逐个人工核查 ——
不能把"脚本说没写"当成"真的没写"。

（这与 `RESERVED.md` 那次误判同源：**标记/工具的输出是线索，不是证据**。）

## 4. 方法论

**"有读无写"不一定是缺陷 —— 有四种可能，处置各不相同**：

| 形态 | 判定 | 处置 |
|---|---|---|
| 有实现、有编号、无 UI | 保留未接 | 标记 + 登记（`kf_week_start`） |
| **有意只读**（默认值即行为） | 正常设计 | **不动**（`kf_speek_sharehalf`） |
| 只读但已被注意并绕开 | 已处置 | **不动**（`kf_debug_raw`） |
| 只读且无说明 | **可疑** | 深查（本轮无此情况） |

脚本的价值是**把候选数从"全部键"缩到 5 个**，人工核查 5 个是可行的。
