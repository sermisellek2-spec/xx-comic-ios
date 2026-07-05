# Four Source Integration Design

> Date: 2026-07-05
> Scope: Add source design for DM5, HiperDEX, Hanman18, and Manhuagui.
> Status: Design/spec only. No implementation in this document.

## Goal

Add four comic sources to XX Comic with the same app behavior as existing sources:

- Search from the normal search page and global multi-source search.
- Browse category/latest pages with pagination where the site supports it.
- Open detail pages quickly, without eagerly loading huge chapter/image data.
- Load chapters on demand from the detail drawer.
- Read chapter images in the existing reader.
- Export/import every source route and filter through the app source JSON.

The four sources are:

| Source | Target role | Priority | Main risk |
|---|---|---:|---|
| DM5 | Chinese/Japanese large catalog | P0 | Search/detail pages may redirect between `dm5.com` and mobile/desktop variants |
| HiperDEX | English Korean comics | P0 | Cloudflare/ad scripts, but chapter images are likely direct HTML URLs |
| Hanman18 | Chinese Korean comics | P1 | Chapter images are JS/server loaded; network stability is uneven |
| Manhuagui | Japanese large catalog | P1 | Chapter image JS decoding and DNS/network sensitivity |

## Existing App Fit

The app already has the right boundaries:

- `ComicSource` defines the full source contract.
- `SourceConfig` stores source metadata, routes, filters, and import/export JSON.
- Each existing source is a small Java class under `app/src/main/java/com/xxcomic/source/`.
- `MainActivity` owns registration, enabled sources, source lookup, health check, and import/export wiring.

Do not change the `ComicSource` public interface for this work. Add source-specific parsing inside each new source class. Keep URL templates and filters in `SourceConfig`, so exported JSON can reproduce the source behavior on another device.

## Shared Implementation Rules

### Source Class Pattern

Create one class per source:

- `Dm5ComicSource.java`
- `HiperdexComicSource.java`
- `Hanman18ComicSource.java`
- `ManhuaguiComicSource.java`

Each class should:

- Use `SourceConfig` for base URL, referer, routes, and filters.
- Prefix comic IDs only when needed to avoid collisions, using the existing style: `sourceId + ":" + rawId`.
- Keep `detail()` fast. It may parse metadata and a small latest-chapter hint, but must not fetch every chapter image.
- Put large chapter parsing in `chapters()`.
- Put image parsing in `chapter()`.
- Deduplicate cards, chapters, and images with `LinkedHashSet`.
- Use 10 second connect timeout and 15 second read timeout unless a source has proven need for shorter failure.
- Set a real browser user agent and the configured referer.
- Throw `IOException` with source-specific context when parsing fails.

### JSON Configuration

Every source needs a `SourceConfig` factory method and must be included in import/export:

```java
public static SourceConfig dm5(boolean enabled) { ... }
public static SourceConfig hiperdex(boolean enabled) { ... }
public static SourceConfig hanman18(boolean enabled) { ... }
public static SourceConfig manhuagui(boolean enabled) { ... }
```

The exported JSON must include:

- `id`
- `name`
- `domain`
- `baseUrl`
- `referer`
- `enabled`
- `routes`
- `filters`

Do not hardcode route URLs in the source classes when a route can live in JSON. The source classes may still hardcode parser regexes and decoding algorithms because those are implementation logic, not user-editable config.

### Pagination

All new sources must support search/category pagination when the site supports it. If a source has no verified search pagination, return an empty list for `page > 1` rather than repeating page 1.

Existing search page behavior should remain:

- Keyboard search only.
- Category click resets to page 1.
- Scroll-to-bottom loads next page without jumping to top.
- Global search writes successful results into per-source tabs.

## Source 1: DM5

### Identity

| Field | Value |
|---|---|
| id | `dm5` |
| name | `动漫屋` or `DM5` |
| domain | `www.dm5.com` |
| baseUrl | `https://www.dm5.com` |
| referer | `https://www.dm5.com/` |

Use the user-facing name `动漫屋` only if the UI should remain Chinese. Use `DM5` if avoiding ambiguity with the already connected `漫画屋`.

### Required Probe Before Implementation

Before coding, run a probe for:

- Home response code and encoding.
- Search URL and first result card.
- Detail page metadata and chapter anchors.
- One chapter page image mechanism.

Probe keywords:

- `一人之下`
- `柯南`
- `美丽新世界` only as a false-positive check, not as the primary target.

### Expected Routes

Use these as defaults, but verify before implementation:

```json
{
  "latest": "/manhua-list/",
  "search": "/search?title={keyword}{pageQuery}",
  "category": "/manhua-list-{region}-{state}-{page}.html",
  "detail": "/{comicId}/",
  "chapter": "/{chapterPath}"
}
```

If the actual site uses different mobile routes, keep both in JSON:

```json
{
  "search": "/search?title={keyword}{pageQuery}",
  "mobileSearch": "https://m.dm5.com/search?title={keyword}{pageQuery}"
}
```

The source class should prefer the route verified by probes.

### Parsing Strategy

Search and category:

- Parse result cards from repeated comic card blocks.
- Extract detail href, title, cover, and latest/status text.
- Normalize relative href to raw comic ID.
- Normalize cover URLs that begin with `//`.

Detail:

- Parse title from `h1`, `title`, or Open Graph meta.
- Parse cover from Open Graph image or detail cover image.
- Parse author/status/description from detail info blocks.
- Return `ComicDetail` with empty chapter list unless the page already contains a small list. The app should call `chapters()` when the user opens the catalog drawer.

Chapters:

- Parse all chapter anchors from the detail page.
- Preserve site order.
- Filter ad/update anchors by requiring links that point to a chapter page, not external/news pages.

Chapter images:

- DM5-style sites often generate images through JavaScript variables and a chapter image endpoint.
- First try to parse direct image URLs from HTML.
- If absent, inspect script variables and JS files for a JSON/image endpoint.
- Do not implement a WebView-only source unless HTTP extraction is impossible and the user approves the extra complexity.

### Filters

Only add filters that are verified. Start with simple values:

```json
{
  "region.all": "",
  "region.jp": "japan",
  "region.cn": "china",
  "region.kr": "korea",
  "region.en": "europe",
  "state.all": "",
  "state.serial": "serial",
  "state.pub": "finish"
}
```

If DM5 route names differ, adjust JSON and keep app filter keys stable.

## Source 2: HiperDEX

### Identity

| Field | Value |
|---|---|
| id | `hiperdex` |
| name | `HiperDEX` |
| domain | `hiperdex.com` |
| baseUrl | `https://hiperdex.com` |
| referer | `https://hiperdex.com/` |

### Verified Behavior

Previously verified:

- Search route works with WordPress/Madara query params.
- `A Wonderful New World` detail exists.
- `Drama Queens` detail exists.
- Detail pages expose chapter lists.
- Chapter pages can expose direct image URLs under the site's image CDN for some comics.

### Routes

```json
{
  "latest": "/manga/?m_orderby=latest{pagePath}",
  "search": "/?s={keyword}&post_type=wp-manga{pageQuery}",
  "category": "/manga/{genrePath}{pagePath}",
  "detail": "/manga/{comicId}/",
  "chapter": "/manga/{comicId}/{chapterSlug}/",
  "ajaxSearch": "/wp-admin/admin-ajax.php"
}
```

For search pagination, verify whether WordPress uses `/page/{page}/?s=...` or `&paged={page}`. Store the working form in JSON as `searchPaged`.

### Parsing Strategy

Search/category:

- Parse Madara manga listing items.
- Extract the detail href under `/manga/{slug}/`.
- Extract title from item title anchor.
- Extract cover from `data-src`, `data-lazy-src`, or `src`.
- Extract latest chapter from list chapter block if present.

Detail:

- Parse Open Graph title/image/description.
- Parse author/status/rating only if present and cheap.
- Raw comic ID is the slug after `/manga/`.

Chapters:

- Parse chapter anchors under the listing area.
- Chapter URL format: `/manga/{comicId}/{chapterSlug}/`.
- Chapter ID can be `{comicId}/{chapterSlug}`.
- Keep the site order, then let existing UI reverse/sort controls handle display.

Chapter images:

- Parse images from the chapter content area only.
- Accept `.jpg`, `.jpeg`, `.png`, `.webp`.
- Ignore logos, avatars, ads, and cover images.
- Good selectors/regex anchors to inspect:
  - `reading-content`
  - `page-break`
  - `wp-manga-chapter-img`
  - `data-src`
  - `src`
- Some images may be lazy loaded. Prefer `data-src` before `src`.

### Filters

Keep filters minimal until categories are verified:

```json
{
  "genre.all": "",
  "genre.korean": "webtoon",
  "genre.manhwa": "manhwa",
  "genre.romance": "romance",
  "genre.drama": "drama"
}
```

The search page can work without category filters. Do not block HiperDEX integration on perfect category support.

### Risk Handling

- If Cloudflare challenge appears, show source failure and log it. Do not hang loading overlays.
- If chapter images are empty, log the first 500 characters around the reading container and return an empty image list with a user-visible error.

## Source 3: Hanman18

### Identity

| Field | Value |
|---|---|
| id | `hanman18` |
| name | `Hanman18` |
| domain | `hanman18.com` |
| baseUrl | `https://hanman18.com` |
| referer | `https://hanman18.com/` |

Use the non-`www` domain first. Earlier checks showed `www.hanman18.com` can behave differently.

### Verified Behavior

Previously verified:

- `/search?search=美麗新世界` returns JSON data.
- `/search?search=社團學姊` returns JSON data.
- `/list-manga?search=美麗新世界` returns list HTML.
- `/manhwa/meilixinshijie` opens a detail page.
- `/manhwa/shechanhuazi` opens a detail/chapter chain.
- Chapter pages contain a `chapter_boxImages` container, but images are likely loaded by JS/server selection.
- Network stability is uneven. Timeouts must not block back navigation.

### Routes

```json
{
  "latest": "/list-manga{pageQuery}",
  "search": "/list-manga?search={keyword}{pageQuery}",
  "searchApi": "/search?search={keyword}",
  "detail": "/manhwa/{comicId}",
  "chapter": "/manhwa/{comicId}/{chapterId}",
  "chapterImages": "/ajax/chapter/images"
}
```

`chapterImages` is a configurable placeholder route for the discovered image endpoint. The implementation must replace this value after probing the chapter scripts, and imported JSON can override it if the site changes later.

### Parsing Strategy

Search:

Use two-stage search:

1. Try `searchApi` JSON for exact name/slug suggestions.
2. Fetch `search` list page for covers and latest chapter.

This gives accurate Chinese names while still producing full `ComicSummary` cards.

Detail:

- Raw comic ID is the slug after `/manhwa/`.
- Parse title from `title`, `h1`, or detail heading.
- Parse cover from `/uploads/manga/{slug}/cover/cover_250x350.jpg` if visible.
- Parse description/status if present.

Chapters:

- Parse all `/manhwa/{comicId}/{chapterId}` links.
- Filter duplicates.
- Exclude navigation links, unrelated recommendations, and non-chapter links.

Chapter images:

This is the hard part and must be probe-driven.

Probe order:

1. Fetch one chapter page.
2. Save script URLs and inline scripts.
3. Search scripts for:
   - `chapter_boxImages`
   - `data-value='s1'`
   - `server`
   - `image`
   - `manga`
   - `chapter`
   - `ajax`
4. Identify whether images are returned by an AJAX endpoint or generated from known path patterns.
5. Verify direct image URLs with `Referer: https://hanman18.com/`.

Only after step 5 should `Hanman18ComicSource.chapter()` be implemented.

If no HTTP image path is found, defer reader support and mark the source as search/detail/catalog only. Do not ship a source that opens every chapter as "no images".

### Stability Rules

- Use 8 second connect timeout and 12 second read timeout for Hanman18.
- On timeout, return a source-specific `IOException`.
- Loading overlays must be dismissible through the existing back flow.
- Log the failing URL and source ID.

### Filters

Start without category filters unless verified:

```json
{
  "category.all": ""
}
```

Hanman18 is valuable mainly for exact search, not broad category browsing.

## Source 4: Manhuagui

### Identity

| Field | Value |
|---|---|
| id | `manhuagui` |
| name | `漫画柜` |
| domain | `m.manhuagui.com` |
| baseUrl | `https://m.manhuagui.com` |
| referer | `https://m.manhuagui.com/` |

Use mobile pages first because they are simpler for the app UI. Keep desktop base URL in JSON as fallback if needed.

### Verified Behavior

Previously observed:

- Home and listing pages can be opened by browser tooling.
- Search route shape is likely `/s/{keyword}.html`.
- Category route shape is likely `/list/{region}/`.
- Detail and catalog are HTML friendly.
- Command-line HTTP requests timed out in the local environment, so Android networking must be tested carefully.
- Chapter image parsing needs dedicated JS reverse engineering.

### Routes

```json
{
  "latest": "/list/{pagePath}",
  "search": "/s/{keyword}.html{pagePath}",
  "category": "/list/{regionPath}{statePath}{pagePath}",
  "detail": "/comic/{comicId}/",
  "chapter": "/comic/{comicId}/{chapterId}.html",
  "desktopBaseUrl": "https://www.manhuagui.com"
}
```

The exact pagination format must be verified. Keep `searchPaged` and `categoryPaged` if the site requires special page URLs.

### Parsing Strategy

Search/category:

- Parse cards from mobile list blocks.
- Extract href, title, cover, author/latest/status.
- Raw comic ID is the numeric ID from `/comic/{id}/`.

Detail:

- Parse title, cover, author, status, description.
- Do not parse every image or chapter image here.

Chapters:

- Parse chapter anchors from the detail page.
- Exclude recommendation/update/news anchors.
- Keep both title and numeric chapter URL.

Chapter images:

Manhuagui likely stores a packed chapter config in page JavaScript. The implementation must:

1. Fetch chapter HTML.
2. Locate chapter config script variables.
3. Decode packed/encrypted image list.
4. Build image URLs with path, image filenames, and host.
5. Request images with `Referer` and mobile/desktop UA.

Do not implement Manhuagui reader by guessing. Add a probe script first and only code the decoding algorithm after at least one full chapter returns direct image URLs.

### Filters

Use stable app filter keys and source-specific values:

```json
{
  "region.all": "",
  "region.jp": "japan",
  "region.cn": "china",
  "region.hk": "hongkong",
  "region.kr": "korea",
  "region.en": "europe",
  "state.all": "",
  "state.serial": "serial",
  "state.pub": "finish"
}
```

Adjust values after verifying actual URLs.

## MainActivity Integration

Add source fields, configs, and enabled flags for each source:

- `dm5Client`, `dm5Config`, `dm5Enabled`
- `hiperdexClient`, `hiperdexConfig`, `hiperdexEnabled`
- `hanman18Client`, `hanman18Config`, `hanman18Enabled`
- `manhuaguiClient`, `manhuaguiConfig`, `manhuaguiEnabled`

Register each source in:

- Source client rebuild.
- Enabled source list.
- Source list shown on the source-management page.
- Source lookup by ID.
- Source display-name lookup.
- Source config import/export JSON.
- Health check flow.

Do not special-case search UI per source. All differences should live in `ComicSource` implementations and `SourceConfig`.

## Probe Scripts

Add probe scripts before Java implementation:

- `tools/probe-dm5.js`
- `tools/probe-hiperdex.js`
- `tools/probe-hanman18.js`
- `tools/probe-manhuagui.js`

Each script must print:

- Home status.
- Search URL and count.
- First parsed result.
- Detail URL and parsed metadata.
- Chapter count.
- First chapter URL.
- Image count and first image URL.

Treat a source as implementation-ready only when the probe prints at least one direct chapter image URL, except Hanman18 if the user explicitly accepts search/detail/catalog-only mode.

## Error Logging

All new sources should use clear `IOException` messages:

- `DM5 search parse failed: {url}`
- `HiperDEX chapter image list empty: {url}`
- `Hanman18 chapter image endpoint unresolved: {url}`
- `Manhuagui chapter decode failed: {url}`

The app's existing log page should surface these errors. Avoid swallowed exceptions except for optional metadata fields.

## Testing Plan

### Probe Verification

Run all probes:

```powershell
node tools/probe-dm5.js
node tools/probe-hiperdex.js
node tools/probe-hanman18.js
node tools/probe-manhuagui.js
```

Expected:

- Each probe prints search/detail/chapter summary.
- HiperDEX prints direct image URLs.
- DM5 and Manhuagui print either direct image URLs or a documented JS decoding blocker.
- Hanman18 prints exact search matches and either direct image URLs or the unresolved image endpoint.

### App Build

```powershell
.\gradlew.bat assembleDebug
```

Expected:

- Build succeeds.
- No new Android dependencies are required.

### Manual App Checks

For each source:

- Enable the source.
- Search a known title.
- Open detail.
- Open catalog drawer.
- Open first chapter.
- Scroll reader until images are visible.
- Use next/previous chapter buttons.
- Export source JSON.
- Clear app source state.
- Import JSON.
- Repeat one search and one chapter open.

Known titles:

| Source | Test title |
|---|---|
| DM5 | `一人之下`, `柯南` |
| HiperDEX | `A Wonderful New World`, `Drama Queens` |
| Hanman18 | `美麗新世界`, `社團學姊` |
| Manhuagui | `一拳超人`, `名侦探柯南` |

## Implementation Order

Use this order to reduce risk:

1. HiperDEX: likely direct images, fastest full-chain win.
2. DM5: high value if chapter image endpoint is discoverable.
3. Hanman18: high value for Chinese Korean comics, but image endpoint must be solved first.
4. Manhuagui: high catalog value, but decoding/network sensitivity make it last.

If a source fails at chapter image probing, stop that source and move to the next one rather than blocking the whole batch.

## Open Decisions

These decisions are intentionally fixed for the first implementation pass:

- No WebView extraction unless HTTP extraction fails and the user explicitly approves it.
- No new dependencies.
- No changes to `ComicSource`.
- No UI redesign.
- No manual source-specific toggles beyond existing source enable/disable.
- Do not ship a source with broken reader support unless clearly marked as search/detail/catalog-only.
