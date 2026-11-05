#!/usr/bin/env python3
"""shots_driver.py —— 模拟器截图驱动（CI 用）。

2026-11-05（实测重构）：原来这两轮截图是 bash 内联脚本，在 GitHub 的 xcode-27 runner 上
反复出现「打印了 scope 行就再也没有下文」——diag 里连一条 fullpage 记录都没有。
命令替换里套 case、set +e 与默认 bash -e 的交互都排查过，每次验证要 10 分钟。

改成独立的 Python 驱动：
  · 子进程调用 simctl，每一步都有超时与返回值检查（不再依赖 shell 的 || true 语义）
  · 每张图自带重试（空白/缺文件都重拍）
  · 全程写 diag，出问题时能一眼看出停在哪一张

用法：python3 Tools/shots_driver.py <udid> <scope> <diag-path>
  scope ∈ door / keys / records / household / settings / all
"""
import os
import subprocess
import sys
import time

OUT = "/tmp/shots"
BUNDLE = "com.aapk.lockkeeper"

# 2026-11-05（实测）：第一次真跑时 step 7 超过 7 分钟还没结束。
# 根因是每个 simctl 调用的超时太宽松（launch 120s × 15 次 ≈ 30 分钟上限），
# 一旦模拟器卡住，整轮就会一直挂到 job 的 70 分钟上限。
# 加一个**全局预算**：超过就把剩下的截图标记为 skipped 并如实报告，
# 让这一轮至少能带着已产出的图和清楚的 diag 结束。
BUDGET_SEC = 15 * 60
_START = time.time()


def budget_left() -> float:
    return BUDGET_SEC - (time.time() - _START)

# scope → (要截的 Tab 序号, 要截的子页 dest)。与 workflow 里 changes job 的判据一致。
# 2026-11-05（对抗审查 · 截图列表没跟着归并更新）：
# 25 页归并后 .lockStatus / .lockSettings / .defend 三个 dest 渲染的是**同一页**
#（LockSettingsHomeScreen），于是旧列表每次都在拍两张一模一样的图 ——
# 实测 12-lockSettings.png 与 13-defend.png **字节相同**。
# 同时旧列表漏掉了 7 个 -kfDest 可达的页面：我的锁 / 凭证工作室 / 安全 / 自动开锁 /
# 关于 / 新建成员 / 添加门锁。
# 现在按**宿主页去重**，并把漏掉的补齐：子页 10 个（含 2 张重复）→ 15 个各不相同的页面。
# 2026-11-05（全技能审核 · 视觉覆盖）：25 个唯一页里原来漏拍 5 个 ——
# keyDetail / mobileKey / recordDetail / memberDetail / appearance。
# 它们恰好是图表与设置控件最密的一批（覆盖率环、周柱图、24h 波形、6 张外观卡）。
_DOOR = ["lockSettings", "deviceInfo", "lockPortfolio", "addLock"]
_KEYS = ["keyCreate", "zotp", "credentialStudio", "keyDetail", "mobileKey"]
_RECORDS = ["recordsStudio", "recordDetail"]
_HOUSE = ["memberCreate", "memberDetail"]
_SETTINGS = ["backupStudio", "godMode", "hardware", "security", "autoOpen", "about", "appearance"]

SCOPES = {
    "door": (["0"], _DOOR),
    "keys": (["1"], _KEYS),
    "records": (["2"], _RECORDS),
    "household": (["3"], _HOUSE),
    "settings": (["4"], _SETTINGS),
    "all": (["0", "1", "2", "3", "4"], _DOOR + _KEYS + _RECORDS + _HOUSE + _SETTINGS),
    # 2026-11-05（Round 5 · 深色矩阵）：4 个根 Tab + 门/钥匙/外观三张信息最密的子页。
    # 深色不是浅色的反相 —— 两套独立取值必须各自有截图证据。
    "dark": (["0", "1", "3", "4"], ["appearance", "security", "keyDetail"]),
    # 2026-11-05（Round 6 · AX 矩阵）：大字号档。芯片行 / 表格行 / 卡头是裁字高发区，
    # 只拍 2 个根 Tab（门 + 凭证）+ 外观/锁设置两张表单最密的子页。
    "ax": (["0", "1"], ["appearance", "lockSettings"]),
}

TAB_NAME = {"0": "door", "1": "keys", "2": "records", "3": "household", "4": "settings"}


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: shots_driver.py <udid> <scope> <diag>", file=sys.stderr)
        return 2
    udid, scope, diag = sys.argv[1], sys.argv[2], sys.argv[3]

    def log(msg: str) -> None:
        with open(diag, "a", encoding="utf-8") as fh:
            fh.write(msg + "\n")

    def run(args, timeout=90):
        # 全局预算用尽就不再发新命令 —— 已产出的图仍然会被发布。
        if budget_left() <= 5:
            log("budget exhausted before: " + " ".join(args[:4]))
            return None
        try:
            return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        except Exception as exc:  # 超时或 simctl 崩了都不该打断整轮
            log("cmd failed: " + " ".join(args) + " :: " + repr(exc))
            return None

    def terminate() -> None:
        run(["xcrun", "simctl", "terminate", udid, BUNDLE], timeout=60)

    def launch(extra, wait: float) -> None:
        terminate()
        # 2026-11-05（Round 6 · AX 矩阵）：ax 域的每一轮都带上 -kfAX。
        if axmode:
            extra = extra + ["-kfAX"]
        run(["xcrun", "simctl", "launch", udid, BUNDLE] + extra, timeout=60)
        time.sleep(wait)

    def shot(path: str, min_bytes: int = 40000, tries: int = 3) -> bool:
        for attempt in range(1, tries + 1):
            run(["xcrun", "simctl", "io", udid, "screenshot", path], timeout=120)
            if os.path.exists(path) and os.path.getsize(path) >= min_bytes:
                return True
            log("shot retry %d %s" % (attempt, os.path.basename(path)))
            time.sleep(2)
        return os.path.exists(path)

    def fullpage_copy(src: str, dest: str) -> bool:
        """拷出整页图并做单色检测：AX 档下 drawHierarchy 可能拿到一版纯纸色
        （App 侧两遍渲染也没能等到重布局完成）。单色图不覆盖 ci-shots 上的旧图。"""
        if not os.path.exists(src):
            return False
        try:
            with open(src, "rb") as fh, open(dest, "wb") as out:
                out.write(fh.read())
        except Exception as exc:
            log("copy failed: " + repr(exc))
            return False
        try:
            from PIL import Image  # type: ignore
            im = Image.open(dest).convert("RGB").resize((60, 456))
            if len(set(im.getdata())) <= 2:
                log("fullpage BLANK (single-color) " + os.path.basename(dest) + " - discarded")
                os.remove(dest)
                return False
        except ImportError:
            pass  # 无 Pillow 就跳过检测（CI 镜像自带 Pillow）
        except Exception as exc:
            log("blank check failed: " + repr(exc))
        return True

    tabs, subs = SCOPES.get(scope, SCOPES["all"])
    log("python driver: scope=" + scope + " tabs=[" + " ".join(tabs) + "] subs=[" + " ".join(subs) + "]")
    os.makedirs(OUT, exist_ok=True)

    # 2026-11-05（Round 5 · 深色矩阵）：dark 域的图带 dark- 前缀，与浅色图并存；
    # 深浅切换由驱动自己做（workflow 只设一次 light）。
    # 2026-11-05（Round 7）：ax 域整页图改为滚动拼接（tile-stitch，3e47c539 单组版定稿）。
    # 本文件无逻辑变化，此注释用于让 App/Engine 的捕获改动触发截图域复核。
    dark = scope == "dark"
    axmode = scope == "ax"
    prefix = ("dark-" if dark else "") + ("ax-" if axmode else "")

    def flip(appearance: str) -> None:
        run(["xcrun", "simctl", "ui", udid, "appearance", appearance], timeout=60)
        log("appearance=" + appearance)

    if dark:
        flip("dark")

    produced = 0

    # 一、Tab 整页图（算法级整页成像，产物落在 App 容器 Documents/）
    def out_of_budget() -> bool:
        if budget_left() > 5:
            return False
        log("budget exhausted: remaining shots skipped")
        return True

    for tab in tabs:
        if out_of_budget():
            break
        name = TAB_NAME.get(tab, "tab" + tab)
        log("fullpage begin tab=" + tab + " name=" + name + " budget_left=" + str(int(budget_left())) + "s")
        launch(["-kfUITest", "-kfSeed", "-kfFullPage", "-kfTab", tab], 8)
        # 2026-11-05（Round 3 · 导航标题验证）：整页图是「把 ScrollView 撑开」拍的，
        # 不含导航栏 —— 于是「navigationTitle 是否真的出现 / large 还是 inline」在整页图里
        # 根本看不到。这里补一张根页视口图：标题、工具栏按钮、状态行都在这一张里。
        rootShot = os.path.join(OUT, prefix + "root-" + name + ".png")
        if shot(rootShot):
            produced += 1
            log("root viewport ok " + prefix + name + " size=" + str(os.path.getsize(rootShot)))
        else:
            log("root viewport missing " + prefix + name)
        container = run(["xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"], timeout=60)
        dest = os.path.join(OUT, prefix + tab + "-" + name + "-full.png")
        copied = False
        if container is not None and container.returncode == 0:
            docdir = container.stdout.strip()
            src = os.path.join(docdir, "Documents", "kf-fullpage-" + tab + "-tab.png")
            copied = fullpage_copy(src, dest)
            # 2026-11-05（Round 7 · AX 定稿）：整页图空白时（App 侧改为逐屏落盘），
            # 拷出该页所有 tile-N 截图 —— 每一屏都是真实的 AX 布局证据。
            if not copied and os.path.isdir(docdir):
                tdir = os.path.join(docdir, "Documents")
                tiles = sorted([f for f in os.listdir(tdir) if f.startswith("kf-fullpage-" + tab + "-") and "tile" in f])
                for f in tiles:
                    tdest = os.path.join(OUT, prefix + name + "-" + f.split("-tile")[-1].replace(".png", "") + ".png")
                    if fullpage_copy(os.path.join(tdir, f), tdest):
                        produced += 1
                        log("tile ok " + prefix + name + " " + f + " size=" + str(os.path.getsize(tdest)))
                if tiles:
                    copied = True
                    # 用了逐屏 tile 证据时，把**旧的整页文件**从产出里清掉 ——
                    # 否则 publish 的 merge 会把上一轮的空白整页图继续带着走。
                    if os.path.exists(dest):
                        os.remove(dest)
                        log("removed stale full page " + os.path.basename(dest))
        if copied and os.path.exists(dest):
            produced += 1
            log("fullpage ok " + prefix + name + " size=" + str(os.path.getsize(dest)))
        elif not copied:
            log("fullpage missing " + prefix + name)

    # 二、子页视口图（-kfDest 直接把那一页压进导航栈）
    for idx, target in enumerate(subs):
        if out_of_budget():
            break
        launch(["-kfUITest", "-kfSeed", "-kfDest", target], 6)
        # 2026-11-05（截图可信度修复）：原来文件名是「10+序号-页面名」，而序号取决于当轮 scope
        # 的子页列表 —— 同一个页面在不同 run 里会变成不同文件名，merge-publish 只按文件名合并，
        # 于是 ci-shots 上同时存在同一页面的多代图，看图的以为是新的、其实是旧的（为此误判过两次）。
        # 改成稳定名字：只用页面名，同一页永远覆盖同一个文件。
        path = os.path.join(OUT, prefix + target + ".png")
        if shot(path):
            produced += 1
            log("subpage ok " + target + " size=" + str(os.path.getsize(path)))
        else:
            log("subpage missing " + target)

    # 把产出数量也写进 diag：ci-shots 的 meta 里已经有 count，但两个数字对不上时
    # （比如 publish 步骤漏了文件）这里能立刻看出来。
    if dark:
        flip("light")
    log("python driver done: produced=" + str(produced))
    try:
        on_disk = len([f for f in os.listdir(OUT) if f.endswith(".png")])
    except Exception:
        on_disk = -1
    log("python driver: png files on disk=" + str(on_disk))
    print("produced " + str(produced) + " screenshots, on disk " + str(on_disk))
    return 0


if __name__ == "__main__":
    sys.exit(main())
