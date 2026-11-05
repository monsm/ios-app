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

# scope → (要截的 Tab 序号, 要截的子页 dest)。与 workflow 里 changes job 的判据一致。
SCOPES = {
    "door": (["0"], ["lockStatus", "deviceInfo", "lockSettings", "defend"]),
    "keys": (["1"], ["keyCreate", "zotp"]),
    "records": (["2"], ["recordsStudio"]),
    "household": (["3"], []),
    "settings": (["4"], ["backupStudio", "godMode", "hardware"]),
    "all": (
        ["0", "1", "2", "3", "4"],
        ["lockStatus", "deviceInfo", "lockSettings", "defend", "keyCreate", "zotp",
         "recordsStudio", "backupStudio", "godMode", "hardware"],
    ),
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

    def run(args, timeout=180):
        try:
            return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        except Exception as exc:  # 超时或 simctl 崩了都不该打断整轮
            log("cmd failed: " + " ".join(args) + " :: " + repr(exc))
            return None

    def terminate() -> None:
        run(["xcrun", "simctl", "terminate", udid, BUNDLE], timeout=60)

    def launch(extra, wait: float) -> None:
        terminate()
        run(["xcrun", "simctl", "launch", udid, BUNDLE] + extra, timeout=120)
        time.sleep(wait)

    def shot(path: str, min_bytes: int = 40000, tries: int = 3) -> bool:
        for attempt in range(1, tries + 1):
            run(["xcrun", "simctl", "io", udid, "screenshot", path], timeout=120)
            if os.path.exists(path) and os.path.getsize(path) >= min_bytes:
                return True
            log("shot retry %d %s" % (attempt, os.path.basename(path)))
            time.sleep(2)
        return os.path.exists(path)

    tabs, subs = SCOPES.get(scope, SCOPES["all"])
    log("python driver: scope=" + scope + " tabs=[" + " ".join(tabs) + "] subs=[" + " ".join(subs) + "]")
    os.makedirs(OUT, exist_ok=True)

    produced = 0

    # 一、Tab 整页图（算法级整页成像，产物落在 App 容器 Documents/）
    for tab in tabs:
        name = TAB_NAME.get(tab, "tab" + tab)
        log("fullpage begin tab=" + tab + " name=" + name)
        launch(["-kfUITest", "-kfSeed", "-kfFullPage", "-kfTab", tab], 8)
        container = run(["xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"], timeout=60)
        dest = os.path.join(OUT, tab + "-" + name + "-full.png")
        copied = False
        if container is not None and container.returncode == 0:
            src = os.path.join(container.stdout.strip(), "Documents", "kf-fullpage-" + tab + "-tab.png")
            if os.path.exists(src):
                try:
                    with open(src, "rb") as fh, open(dest, "wb") as out:
                        out.write(fh.read())
                    copied = True
                except Exception as exc:
                    log("copy failed: " + repr(exc))
        if copied:
            produced += 1
            log("fullpage ok " + name + " size=" + str(os.path.getsize(dest)))
        else:
            log("fullpage missing " + name)

    # 二、子页视口图（-kfDest 直接把那一页压进导航栈）
    for idx, target in enumerate(subs):
        num = str(10 + idx)
        launch(["-kfUITest", "-kfSeed", "-kfDest", target], 6)
        path = os.path.join(OUT, num + "-" + target + ".png")
        if shot(path):
            produced += 1
            log("subpage ok " + target + " size=" + str(os.path.getsize(path)))
        else:
            log("subpage missing " + target)

    log("python driver done: produced=" + str(produced))
    print("produced " + str(produced) + " screenshots")
    return 0


if __name__ == "__main__":
    sys.exit(main())
