# AUDIT-ROUND-54 · 第五十四轮：CI 抓到了我两处真错（实参顺序）

> CI run `41269046351`：`errors=4`、`build_ok=0`、`archive_log=no`。
> 我的八笔批次里有两笔编译不过 —— 这是本轮之前二十几轮里第一次被 CI 判红。

## 1. 错误原文

```
App/Engine/BackupKit.swift:186:21: error: argument 'alerts' must precede argument 'recFlags'
App/Engine/BackupKit.swift:218:17: error: argument 'memberExt' must precede argument 'keychainDongles'
```

根因：**Swift 成员逐一构造（memberwise init）的实参顺序必须与字段声明顺序一致。**
我把 `alerts` 声明在 `recNotes` 之后（构造点写在了 `recDisps` 之后），
把 `memberExt` 声明在 `Globals` 最前面（构造点写在了最后）。

## 2. 为什么本地闸门没抓到

20 道闸门里没有一道做"实参与声明顺序"核对：
`callsig2` 因为**跳过所有 `类型.方法(...)` 调用**（见 ROUND-37 记录的盲区）根本看不到这两处。

这次是**真编译器**替我抓的 —— 也正是那两笔我反复说"只过形状闸门、回执前不声称绿"的原因。

## 3. 修法

1. 把 `alerts` 的声明移到 `recDisps` 之后；
2. 把 `memberExt` 的声明移到 `gatewayList` 之后（`passcode` 之前）；
3. 把 `Globals` 构造点的 `memberExt` 从末尾移到 `gatewayList` 之后。

改完用脚本逐字段比对：

```
Meta ctor args:    defend tailgate synctime otpStatus otpIdx mobileKeys recNotes recFlags recDisps alerts
Globals ctor args: keychainDongles gatewayList memberExt passcode duress trace appearance deviceOrg
```

两者与声明顺序**完全一致**。

## 4. 方法论

**"静态闸门全绿"和"能编译"之间的距离，就是成员逐一构造的实参顺序。**
这类错误有个特点：**声明与调用分别看都完全合理**，只有把两份顺序并排才看得出来。

可复用做法：改完结构体字段后，用一条脚本把「声明顺序」与「构造点实参顺序」抓出来并排打印，
而不是靠肉眼比对。这比读 diff 可靠得多 —— 我这轮就是肉眼漏掉的。
