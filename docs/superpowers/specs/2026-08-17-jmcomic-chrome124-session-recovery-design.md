# JMComic Chrome 124 Session Recovery Design

## Goal

Restore JMComic catalog loading after changing its HTTP and WebView fingerprint
back to Android 14 / Chrome 124, and make the settings verification action usable
while an automatic catalog request is still verifying.

## Scope

The change is owned entirely by `JmComicWebViewSession` and the JMComic branch of
`MainActivity.verifyProtectedSource`. `Mh18WebViewSession` and 18mh credentials
must not be read, cleared, cancelled, or reloaded by this flow.

## Credential Migration

JMComic stores the browser fingerprint version in a dedicated preference file.
When the stored version differs from the current Chrome 124 version, the session
expires cookies for `18comic.vip`, deletes that origin's WebStorage, clears its
own browser context state, and then records the new version. This runs once per
fingerprint version and does not clear application caches or other domains.

## Manual Verification Takeover

`fetchInteractive` marks an interactive takeover before waiting for the session
semaphore. An automatic JMComic request checks this flag before transport work
and when its WebView request starts. If a non-interactive request is active, it
is completed as an expected cancellation so it releases the semaphore promptly.
The interactive request then owns the existing JMComic WebView and may display
the Cloudflare challenge. A manual request never cancels another manual request.

## Catalog Recovery

After a successful JMComic manual verification, MainActivity reloads the current
single-site catalog only when the user has moved to the Discover tab and JMComic
is still selected. Verification from Settings does not navigate the user away;
opening Discover later follows its existing initial-load path.

## Errors And Tests

Automatic cancellation remains an expected cancellation and does not create an
error page. Manual verification keeps the existing timeout, page-validation, and
VPN failure messages. JVM tests lock fingerprint migration decisions, takeover
policy, and reload gating. Static contracts lock JMComic-only credential state
and takeover wiring. The full unit suite and release build run before publishing.
