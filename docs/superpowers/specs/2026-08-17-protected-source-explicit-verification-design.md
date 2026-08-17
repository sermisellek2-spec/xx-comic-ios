# Explicit Protected-Source Verification Design

## Goal

Make 18mh and JMComic verification explicit, predictable, and isolated. Only
Settings > Source Management may start an interactive verification WebView.
Discover, detail, catalog, and reader requests must use cached credentials and
must never promote a content request into interactive verification.

## Scope And Ownership

`Mh18WebViewSession` owns the complete 18mh request and verification flow.
`JmComicWebViewSession` owns the complete JMComic request and verification
flow. The two implementations do not share a verification state machine,
request lock, WebView, credential preference, readiness flag, timeout, or site
probe. A small data-only exception may be shared so MainActivity can route a
credential failure without duplicating UI error handling.

The existing `BrowserSession.fetch()` contract becomes cached-credential-only
for both protected sources. `BrowserSession.fetchInteractive()` remains the
manual entry used only by each source's `verifyAccess()` method.

## Cached Content Requests

Ordinary source methods continue calling `fetch()` for lists, searches,
details, catalogs, and reader pages. Each protected-source implementation sends
its own fixed Chrome 124 user agent and that domain's cookies through
`HttpURLConnection`. This path must not create a WebView, run browser-context
JavaScript, navigate to a challenge, or display a challenge page.

The request returns content only for a successful non-challenge response. A
403 with `cf-mitigated: challenge`, a Cloudflare challenge document, or another
known verification page immediately throws `VerificationRequiredException`.
There is no automatic WebView fallback, polling loop, hidden verification, or
120-second wait in this path. Connectivity and VPN failures remain ordinary
network errors and are not reclassified as credential failures.

## Interactive Verification

The Verification button in Source Management calls the selected source's
`verifyAccess()` method. It immediately opens that source's own dialog-hosted
WebView at approximately 90 percent of the available width and 70 percent of
the available height. A compact header contains the source name, a short status,
and a close button. The underlying source card cannot start a duplicate
verification while the dialog is active.

Closing the dialog cancels only that source's current interactive request. It
does not record success and does not show a failure dialog. A timeout or page
error leaves the dialog open with a short status and a Reload action; it never
automatically relaunches the challenge.

Cloudflare UI completion, a Turnstile value, a new cookie, or navigation away
from the challenge is only intermediate progress. After the WebView reaches the
expected site, the source validates its own business page:

- 18mh must load `/manga` and recognize its manga-list business markers.
- JMComic must load `/albums?o=mr&page=1` and recognize catalog cards.

The session then flushes cookies and performs one cached-path probe with the
same transport that content requests use. Only a successful response containing
the same source-specific business markers records verification time, shows
`验证完成`, and closes the dialog. Failure keeps the dialog open and does not
mark the credentials valid.

## UI Routing

When an initial Discover request receives `VerificationRequiredException`, the
page renders the existing Rem-themed state treatment with the source name, the
short message `该站源需要验证`, and a `去验证` action. The action opens Source
Management; it does not start verification by itself.

If credentials expire during pagination, the current results remain visible.
A compact footer reports that verification is required and offers the same
route. Detail, catalog, and reader entry points use the same explicit routing
instead of opening WebView or showing a generic retry loop.

After verification succeeds, the dialog closes while Source Management remains
visible. The user returns with the normal back gesture and retries or reloads
the previous content screen. No automatic navigation or hidden retry is added.

## Credential Lifecycle

Each session stores its verification timestamp and fingerprint version in its
own preferences. Cookies remain separated by domain. In-memory ready state and
active requests are also per source. App cache cleanup clears both protected
sources' cookies, WebStorage, verification metadata, and in-memory readiness,
while preserving unrelated user data according to the existing cleanup policy.

## Error Handling

- Missing or expired credentials: `VerificationRequiredException`; show the
  explicit Source Management route and omit the generic error log.
- VPN or network failure: keep the existing connection error and VPN guidance.
- User cancellation: stop the source's interactive request and return to an
  unverified idle state without an error dialog.
- Verification timeout: keep the dialog open and offer Reload or Close.
- Wrong or incomplete business page: keep the dialog open with
  `页面还未准备好`; never record success.
- Concurrent requests: each source owns its own exclusive session lock.
  Interactive verification may supersede that source's content request, but
  18mh activity cannot cancel, block, or mutate JMComic activity, and vice
  versa.

## Verification And Tests

Unit tests cover cached-only transport selection, immediate challenge mapping,
site-specific business-page success, failed post-verification probes,
cancellation, timeout, and independent source state. MainActivity tests cover
the initial-page and pagination routing to Source Management and ensure a
credential failure is not rendered as a generic error.

Static contracts ensure neither ordinary protected-source session contains an
automatic interactive fallback and that the two session implementations remain
independent. The full unit suite and release build run before publishing. A
device acceptance pass verifies the real Cloudflare challenge, successful
dialog dismissal, cached list loading, and isolation between both sites.
