from pathlib import Path
import os
from playwright.sync_api import sync_playwright, BrowserContext, Page
from screens.auth import is_logged_in

PROFILE_DIR = Path(__file__).parent / "browser_profile"
MIXAMO_URL = "https://www.mixamo.com"

_pw = None
_context: BrowserContext = None
_page: Page = None


def _proxy_opt():
    """Use env proxy (WorkBuddy injects HTTPS_PROXY) — Chromium otherwise ignores it on macOS."""
    p = (os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
         or os.environ.get("HTTP_PROXY") or os.environ.get("http_proxy"))
    return {"server": p} if p else None


def _has_edge() -> bool:
    return Path("/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge").exists()


def _goto(page: Page, wait: str = "domcontentloaded", timeout_ms: int = 120_000):
    """Tolerant navigation: long timeout + retries. networkidle is best-effort."""
    last = None
    for _ in range(3):
        try:
            page.goto(MIXAMO_URL, wait_until=wait, timeout=timeout_ms)
            try:
                page.wait_for_load_state("networkidle", timeout=30_000)
            except Exception:
                pass  # SPA long-polling may never go idle
            return
        except Exception as e:
            last = e
    raise last


def _launch(headless: bool) -> Page:
    global _pw, _context, _page
    if not PROFILE_DIR.exists():  # WorkBuddy shim breaks mkdir(exist_ok=True)
        PROFILE_DIR.mkdir(parents=True)
    _pw = sync_playwright().start()
    # Prefer system Edge: same network stack as the user's daily browser.
    # Playwright's bundled Chromium times out on mixamo.com in this environment.
    channel = "msedge" if _has_edge() else None
    _context = _pw.chromium.launch_persistent_context(
        user_data_dir=str(PROFILE_DIR),
        channel=channel,
        headless=headless,
        proxy=_proxy_opt(),
        viewport={"width": 1280, "height": 900},
    )
    _page = _context.new_page()
    return _page


def _close():
    global _pw, _context, _page
    try:
        if _context:
            _context.close()
    except Exception:
        pass
    try:
        if _pw:
            _pw.stop()
    except Exception:
        pass
    _pw = _context = _page = None


def _check_logged_in(page: Page) -> bool:
    _goto(page)
    try:
        url = page.evaluate("window.location.href")
        html = page.content()
        return is_logged_in(url, html)
    except Exception:
        return False


DEBUG = True  # set to False to run headless after login


def start() -> Page:
    """Start browser. If not logged in, open visible browser for login, then resume in configured mode."""
    page = _launch(headless=False if DEBUG else True)

    if _check_logged_in(page):
        print("Session active.")
        return page

    if not DEBUG:
        # Relaunch visible just for login
        _close()
        print("\nNot logged in. Opening browser for login...")
        page = _launch(headless=False)
        _goto(page)

    print("Waiting for login", end="", flush=True)
    while True:
        try:
            url = page.evaluate("window.location.href")
            html = page.content()
        except Exception:
            import time; time.sleep(1)
            continue

        if is_logged_in(url, html):
            print(" done.")
            break

        import time
        time.sleep(1)
        print(".", end="", flush=True)

    if not DEBUG:
        _close()
        print("Resuming in headless mode.")
        page = _launch(headless=True)
        _goto(page)

    return page


def stop():
    _close()


def get_page() -> Page:
    return _page
