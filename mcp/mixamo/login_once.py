#!/usr/bin/env python3
"""One-shot login helper: opens a visible browser, waits for Mixamo login,
then saves the persistent profile and exits. Run once; mcp_server.py reuses
the same browser_profile afterwards (headless)."""
import sys
import time

import browser

page = browser.start()

DEADLINE = time.time() + 180
last_dump = 0.0
while time.time() < DEADLINE:
    try:
        url = page.evaluate("window.location.href")
        html = page.content()
    except Exception:
        time.sleep(2)
        continue
    if browser.is_logged_in(url, html):
        print(f"\nLOGIN_OK url={url}")
        browser.stop()
        sys.exit(0)
    # every 60s dump page state for diagnosis if positive-feature never appears
    if time.time() - last_dump > 60:
        last_dump = time.time()
        feats = {f: (f in html) for f in
                 ('>Log in<', '>Sign up<', 'Upload Character', 'UPLOAD CHARACTER',
                  'Sign Out', 'Log Out', 'My Assets', 'imsauth', 'character-grid', 'product-animation')}
        print(f"\n[waiting] url={url[:60]} features={feats}", flush=True)
        with open("login_state_dump.html", "w") as f:
            f.write(html)
    time.sleep(2)

print("\nLOGIN_TIMEOUT — see login_state_dump.html for rendered page state")
browser.stop()
sys.exit(1)
