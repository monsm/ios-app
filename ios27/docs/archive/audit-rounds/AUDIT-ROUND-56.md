# AUDIT-ROUND-56 · 第五十六轮：想给 CI 抓到的错加一道闸门，试了两次都该放弃

> CI：`3864e54`（实参顺序修复）已推送，回执未到。本轮本地提交。

## 1. 先确认修复是对的（脚本比对，不靠肉眼）

```
Meta   decl: defend tailgate synctime otpStatus otpIdx mobileKeys recNotes recFlags recDisps alerts
Meta   args: 同上  -> MATCH
Globals decl: keychainDongles gatewayList memberExt passcode duress trace appearance deviceOrg
Globals args: 同上  -> MATCH
```

（第一次跑我的脚本报 `Globals MISMATCH` —— 原因是它把嵌套 `Appearance` 的字段也算进了 `Globals`。
按**顶层缩进**重算后才对上。**脚本自己也会错，得先验证脚本。**）

## 2. 试着把它做成第 21 道闸门 —— 失败

写了 `Gates/memberorder.js`：对本仓 223 个 struct 的具名构造点，比对实参名与字段声明序。

结果：**检查 915 处，报错 839 处**。看前几条就知道为什么：

```
LedgerEntry 第 1 个应为 detail，实际 id（声明：detail, rawType）
StateDot   第 1 个应为 body，实际 tone（声明：body）
Reading    第 1 个应为 unit，实际 value（声明：unit, size, weight, ...）
```

根因：我抓"字段声明序"时把 **`body`（计算属性）** 和嵌套内容都算进去了，
而多数 View struct 用的是**自定义 init**（参数序与字段声明序无关）。

## 3. 为什么放弃而不是继续修

要让它准，需要：区分存储属性 / 计算属性、识别自定义 init 的签名、处理默认值、
处理嵌套 struct 的缩进层级 …… 这是**重写半个 Swift 解析器**。

而收益只有"拦一类编译器已经会拦的错误"。**编译器本来就会拦它，且零误报。**

这与我前几轮定的原则一致：**误报多的 warn-only 闸门比没有更糟**（会训练人忽略它）。
已删除该文件，`allgates` 仍 20/20。

## 4. 真正该留下的东西

不是闸门，是**那个比对脚本的用法**：改完结构体字段后，把「声明序」与「构造点实参序」并排打印。
它只在需要时跑一次，不参与每次全量检查 —— 成本低、无误报、且能抓住这类错。

判据：**能交给编译器的事，不要自己做；自己做的那部分，要么低频手动，要么零误报。**
