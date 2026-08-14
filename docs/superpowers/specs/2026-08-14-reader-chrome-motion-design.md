# Reader Chrome Motion Design

## Goal

Make the center-tap transition between immersive reading and visible controls feel soft, while preserving chapter navigation, scrolling, progress persistence, the catalog drawer, and system-bar behavior.

## Approved Direction

Use the approved overlay approach (option A):

- Keep comic content in a stable full-screen frame so toggling controls does not resize it.
- Place the chapter toolbar and reading counter above the content as independent overlays.
- Fade each overlay over 180 ms with only 6 dp of vertical movement.
- Keep the chapter progress line visible; move it smoothly between the screen edge and the visible bottom control.
- Keep visible controls inside the status/navigation bar insets while the comic content remains full bleed.
- Continue using the existing center-tap target, left/right chapter zones, catalog action, and immersive system-bar flags.

## Scope

Only the rendered reader page and release version change. Loading/error pages, parsing, image loading, chapter switching, reader position persistence, gestures, settings, and other screens remain unchanged.

## Verification Constraint

Per the user's instruction, do not run automated tests. Build the release APK and verify its package, version, signature, byte size, and SHA-256 before publishing.
