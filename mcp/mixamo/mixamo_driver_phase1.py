# Mixamo 驱动 · 阶段 1 v2：上传 + 人工放标记（Edge 有头窗口）+ 轮询到绑骨完成。
# 运行：cd projects/mixamo-mcp && venv/bin/python mixamo_driver_phase1.py <fbx|obj>
# 标记点拖放（下巴/双腕/胯部/双脚踝，共 3 步）必须由人在 Edge 窗口完成——
# repo 明确不支持自动化（screens/upload.py "Marker placement required — not supported"）。

import sys
import time

import browser
from screens.auth import is_logged_in
from screens.upload import upload_file, get_status, close as upload_close
from screens.animations import get_character_name, is_t_pose

FBX = sys.argv[1]


def main():
    page = browser.start()
    logged = is_logged_in(page.url, page.content())
    print("LOGGED_IN", logged, flush=True)
    if not logged:
        print("NOT_LOGGED_IN — 先跑 login_once.py")
        sys.exit(2)

    html = page.content()
    if "autorig-modal" not in html and "cultivatorjade" in html.lower():
        print("CHARACTER CultivatorJade (already rigged)", flush=True)
        print("PHASE1_OK", flush=True)
        sys.exit(0)
    html = page.content()
    if "autorig-modal" in html:
        st = get_status(html)
        print("STALE_MODAL state=%s — 尝试关闭" % st.get("state"), flush=True)
        try:
            upload_close(page)
            time.sleep(2)
        except Exception as e:
            print("  close err:", str(e)[:80], flush=True)

    print("UPLOAD", FBX, flush=True)
    upload_file(page, FBX)

    human_prompted = False
    deadline = time.time() + 1800
    last_state = ""
    while time.time() < deadline:
        html = page.content()
        if "autorig-modal" not in html:
            print("RIGGING_DONE True", flush=True)
            break
        st = get_status(html)
        state = st.get("state", "")
        if state != last_state:
            print("STATE", state, st.get("text", ""), st.get("progress", ""), flush=True)
            last_state = state
        if state == "markers" and not human_prompted:
            human_prompted = True
            print("HUMAN_ACTION: 请在 Edge 窗口拖放标记点（下巴→双腕→胯部→双脚踝，3 步 Next）", flush=True)
        if state == "change_character":
            try:
                page.click(".modal-footer button.btn-primary")
                print("  change-character confirmed", flush=True)
            except Exception:
                pass
        time.sleep(4)
    else:
        print("RIGGING_DONE False (timeout 900s)", flush=True)
        sys.exit(3)

    time.sleep(4)
    html = page.content()
    print("CHARACTER", get_character_name(html), flush=True)
    print("TPOSE", is_t_pose(html), flush=True)
    print("PHASE1_OK", flush=True)


main()
