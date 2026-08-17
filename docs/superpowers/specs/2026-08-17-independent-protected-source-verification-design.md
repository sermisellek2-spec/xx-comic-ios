# Independent Protected Source Verification Design

## Goal

Restore automatic Cloudflare verification for 18mh and JMComic by using each
device's native Android WebView fingerprint, while preventing verification
changes for either source from affecting the other.

## Architecture

18mh uses `Mh18WebViewSession`; JMComic uses `JmComicWebViewSession`. Each class
owns its WebView, request lock, request state, browser-context readiness,
timeouts, challenge detection, UI transitions, cookies, and native user agent.
Neither implementation calls, extends, or wraps the other. They only implement
the existing `BrowserSession` interface used by their comic source.

Android's `CookieManager` remains process-wide, but credentials remain isolated
by the sites' distinct domains. Clearing app cache continues to clear both
sessions and the process cookie store.

## Behavior

- Both implementations derive the HTTP user agent from the native WebView user
  agent so the HTTP and WebView fingerprints remain aligned.
- Ordinary content requests first try HTTP and then open that source's own
  hidden WebView when Cloudflare returns a challenge.
- Existing verified browser context is reused only inside the same source
  session.
- 18mh retains its current visible fallback when Cloudflare requires human
  interaction.
- JMComic retains silent automatic verification for ordinary requests; its
  settings verification action remains the only explicit interactive entry.
- Automatic verification cannot bypass a Cloudflare challenge that explicitly
  requires human input.

## Verification

Unit tests lock native user-agent selection and independent class ownership.
Static source contracts lock distinct MainActivity fields and constructors.
The Android unit suite and release build must pass before publishing.
