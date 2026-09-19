# Mixamo 驱动 · 阶段 2 v3：逐动画独立浏览器会话下载（Edge context 每次下载后会崩）。
# 运行：venv/bin/python mixamo_driver_phase2.py
# 策略：每个动画 fresh browser → search → 精确名匹配 → select → 等 inplace 出现 →
#       下载（S3 拦截 + urllib）。walking 带 skin（提供蒙皮角色），其余仅骨架动作。

import time

import browser
from screens.animations import search, select_animation, get_animation_list, set_checkbox
from screens.download import open_modal, set_format, set_skin, set_fps, confirm

DOWNLOADS = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab/mcp/mixamo/downloads"

ANIMS = [
    ("walking", "walk_skin.fbx", True),
    ("idle", "idle.fbx", False),
    ("running", "run.fbx", False),
    ("jump up", "jump.fbx", False),
]
BAD_WORDS = ("fight", "sword", "gun", "pistol", "rifle")


def pick(items, expect):
    """优先精确名，其次前缀，排除战斗系变体。"""
    best = None
    for item in items:
        name = item["name"].lower().strip()
        if any(b in name for b in BAD_WORDS):
            continue
        if name == expect:
            return item
        if name.startswith(expect) and best is None:
            best = item
    if best is None:
        for item in items:
            name = item["name"].lower()
            if expect in name and not any(b in name for b in BAD_WORDS):
                return item
    return best


def wait_checkbox(page, name="inplace", timeout_s=20):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        found = page.evaluate(
            f"() => {{ const el = document.querySelector('input[name=\"{name}\"]'); return el ? el.checked : null; }}"
        )
        if found is not None:
            return True
        time.sleep(1)
    return False


def do_one(query, out_name, skin):
    page = browser.start()
    search(page, query)
    time.sleep(2)
    items = get_animation_list(page.content())["items"]
    picked = pick(items, query)
    if picked is None:
        print("SKIP", query, "items=", [i["name"] for i in items[:8]], flush=True)
        browser.stop()
        return False
    select_animation(page, picked["id"])
    print("SELECTED", picked["id"], picked["name"], flush=True)
    time.sleep(4)
    if wait_checkbox(page):
        try:
            set_checkbox(page, "inplace", True)
            print("  inplace=on", flush=True)
        except Exception as e:
            print("  inplace err:", str(e)[:60], flush=True)
    open_modal(page)
    set_format(page, "fbx_unity")
    set_skin(page, skin)
    set_fps(page, 30)
    out = "%s/%s" % (DOWNLOADS, out_name)
    captured = []

    def on_request(r):
        u = r.url
        if ("amazonaws.com" in u and (".fbx" in u or "export" in u)) or "response-content-disposition" in u:
            captured.append(u)

    page.on("request", on_request)
    try:
        confirm(page, out)
    except Exception as e:
        print("  save_as err (预期):", str(e)[:50], flush=True)
    for _ in range(90):
        if captured:
            break
        time.sleep(1)
    try:
        page.remove_listener("request", on_request)
    except Exception:
        pass
    ok = False
    if captured:
        import urllib.request
        req = urllib.request.Request(captured[0], headers={"User-Agent": "Mozilla/5.0"})
        data = urllib.request.urlopen(req, timeout=180).read()
        open(out, "wb").write(data)
        print("DOWNLOADED", out, "(%d KB)" % (len(data) // 1024), flush=True)
        ok = True
    else:
        print("DOWNLOAD FAILED", query, flush=True)
    browser.stop()
    return ok


def main():
    results = {}
    for query, out_name, skin in ANIMS:
        results[out_name] = do_one(query, out_name, skin)
        time.sleep(3)
    print("RESULTS", results, flush=True)
    print("PHASE2_OK" if all(results.values()) else "PHASE2_PARTIAL", flush=True)


main()
