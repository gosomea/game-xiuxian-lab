def is_logged_in(url: str, html: str) -> bool:
    # Must be on the mixamo.com host, not just contain it in query params
    if not (url.startswith("https://www.mixamo.com") or url.startswith("https://mixamo.com")):
        return False
    # OAuth hand-off page: session token not established yet — keep waiting
    if "#/imsauth" in url:
        return False
    # Positive check: these elements only render after a successful login.
    # (Negative '>Log in<' check alone false-positives on the un-rendered SPA loader.)
    positive = ("Upload Character" in html or "UPLOAD CHARACTER" in html
                or "Sign Out" in html or "Log Out" in html)
    return positive
