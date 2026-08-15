# Cuimh Request Throttling Design

## Goal

Reduce avoidable requests to `www.cuimh.com` without changing discovery, detail, chapter, reader, or source-management behavior. A fresh default catalog and a fresh comic detail should each require one origin request, and a 403 response must stop further origin traffic for a short cooldown period.

## Request Flow

- Normalize the default catalog URL to `/category/` and keep a small per-instance HTML cache keyed by absolute category URL.
- Serialize Cuimh origin requests. A cached category document may be reused for five minutes; different filtered or paginated URLs remain separate documents.
- Enforce a one-second minimum interval between uncached Cuimh origin requests.
- When the origin returns HTTP 403, remember a 30-minute cooldown. Calls during the cooldown fail locally without opening a connection. A successful response clears the cooldown.
- Parse both comic metadata and chapters from the single detail document returned by `detail()`.
- In the shared detail refresh path, reuse chapters already returned by `detail()` and only call `chapters()` for sources whose detail response has no chapters.
- Mark a newly downloaded detail as fresh before rendering it so the generic cache-refresh path does not immediately request it again.
- When a source was already selected in the filter drawer, confirming the selection must not load its filters a second time.

## Error Handling

The first 403 keeps the existing HTTP error semantics and starts the cooldown. Requests made during cooldown return a concise `IOException` explaining that Cuimh is temporarily unavailable. There is no automatic retry. User-triggered retry remains available after the cooldown or after the source client is rebuilt, such as after an app restart or network/source configuration change.

## Verification

- Unit tests use a local HTTP server to count requests and verify category reuse, detail-plus-chapter parsing, request spacing, and 403 cooldown.
- Existing parser and application regression checks must continue to pass.
- Build release `1.0.22 (22)`, verify APK identity, signature, size, and SHA-256, push `master`, upload the APK and metadata to COS and the server fallback, then download both public artifacts and compare hashes.

