# 18mh Verification Recovery Design

## Goal

Make the explicit 18mh verification action complete reliably whether the current
credentials are already valid or Cloudflare presents a challenge. Keep the
JMComic implementation unchanged and keep ordinary content requests HTTP-only.

## Flow

The Settings verification action first checks `/manga` through the existing
cached HTTP path. A successful response containing an 18mh catalog marker
completes immediately without opening a WebView. A Cloudflare challenge opens
the existing compact verification dialog. Network and ordinary HTTP failures
remain failures instead of being relabeled as verification challenges.

The dialog starts with `正在检查站点`. It changes to `请完成安全验证` only when
the page contains a real Cloudflare challenge. The same WebView is inspected
after navigation callbacks and by a short periodic poll, because Cloudflare can
replace its document without producing a reliable final callback on every
Android WebView version.

## Navigation And Completion

Third-party navigation is blocked. Blocking an advertising or popup destination
must not stop the 18mh verification attempt. Completion still requires the
current document to be the 18mh `/manga` page and contain an 18mh catalog card.

After the browser reaches that business page, cookies are flushed and the
cached HTTP transport probes `/manga` once. Browser and HTTP catalog markers are
both required before recording success and closing the dialog.

## Timeout

One 120-second deadline covers the complete operation: cached preflight,
Cloudflare interaction, browser-page polling, and the final HTTP probe. Starting
the final probe must not cancel the deadline. Navigation during a probe must not
leave the request without a timeout. Timeout keeps the dialog open with Reload
and Close controls.

## Scope

Only `Mh18WebViewSession`, its JVM tests, the 18mh source-session static contract,
and Android release version metadata change. `JmComicWebViewSession` and JMComic
behavior are not modified.

## Tests

Regression tests cover cached-preflight completion, challenge-driven browser
entry, nonfatal external-navigation blocking, periodic inspection eligibility,
and a deadline that remains active during the final probe. The existing full
unit suite, source contracts, release build, APK identity/signature checks, and
public artifact hash checks run before release.
