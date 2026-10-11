package com.xxcomic;

import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.TextView;
import com.xxcomic.source.ComicModels.*;
import com.xxcomic.source.ComicSource;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Test-APK-only provider. All views and business consumers are the frozen app. */
public final class ParityReferenceInstrumentation extends Instrumentation {
    private MainActivity activity;
    private JSONObject fixture;
    private byte[] image;
    private ServerSocket server;
    private String stem;
    private final List<JSONObject> captures = new ArrayList<>();
    private static final String BASELINE = "696e80a44ab36b19de6f630565df32978e55a19e";

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        stem = arguments == null ? null : arguments.getString("stem");
        if (stem == null || !stem.matches("android_(phone|tablet)_(portrait|landscape)_(light|dark)")) {
            throw new IllegalArgumentException("An explicit reference device/state stem is required");
        }
        start();
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            byte[] manifest = asset("current-pages.json");
            fixture = new JSONObject(new String(manifest, StandardCharsets.UTF_8));
            if (fixture.getInt("schema") != 1 || !BASELINE.equals(fixture.getString("baseline"))) throw new AssertionError("Wrong frozen fixture");
            image = asset("current-page.png"); startServer();
            status("fixture-ready");
            // The reference emulator is isolated and offline. Set statistics off
            // before MainActivity initializes its optional reporting service.
            File stats = new File(getTargetContext().getNoBackupFilesDir(), "usage-stats.json");
            stats.getParentFile().mkdirs();
            try (FileOutputStream out = new FileOutputStream(stats)) { out.write("{\"enabled\":false,\"decided\":true}".getBytes(StandardCharsets.UTF_8)); }
            int rotation = stem.contains("_landscape_") ? UiAutomation.ROTATION_FREEZE_90 : UiAutomation.ROTATION_FREEZE_0;
            if (!getUiAutomation().setRotation(rotation)) throw new AssertionError("Cannot set actual reference display rotation");
            SystemClock.sleep(500);
            activity = (MainActivity) startActivitySync(new Intent(getTargetContext(), MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            status("activity-ready");
            SystemClock.sleep(600); seed();
            status("library-seeded");
            onMain(() -> Phase8Checks.call(activity, "showTab", 0, false)); shot("bookshelf_online");
            onMain(() -> Phase8Checks.call(activity, "showTab", 1, false)); shot("discover");
            onMain(() -> Phase8Checks.call(activity, "showFilterDrawer", 0)); shot("source_drawer");
            dismissDialogs();
            onMain(() -> {
                Phase8Checks.set(activity, "searchQuery", fixture.optJSONArray("titles").optString(0));
                List<ComicSummary> rows = (List<ComicSummary>) Phase8Checks.get(activity, "searchResults");
                ComicSummary first = rows.get(0); rows.clear(); rows.add(first);
                Phase8Checks.call(activity, "showTab", 1, false);
            }); shot("search_results");
            String id = "mh160:comic_0";
            onMain(() -> Phase8Checks.call(activity, "showDetail", id)); shot("detail");
            ComicDetail detail = (ComicDetail) ((Map) Phase8Checks.get(activity, "details")).get(id);
            onMain(() -> Phase8Checks.call(activity, "showReader", detail, 0));
            SystemClock.sleep(1000);
            onMain(() -> Phase8Checks.call(activity, "setReaderFullscreen", false, false)); shot("reader");
            onMain(() -> Phase8Checks.call(activity, "showReaderSettings")); shot("reading_settings");
            dismissDialogs();
            onMain(() -> Phase8Checks.call(activity, "showChapterDrawer", detail)); shot("reader_directory");
            JSONObject proof = new JSONObject();
            proof.put("baseline", BASELINE); proof.put("fixtureID", fixture.getString("fixtureID"));
            proof.put("metadataSHA256", sha(manifest)); proof.put("imageSHA256", sha(image));
            proof.put("fontScale", getTargetContext().getResources().getConfiguration().fontScale);
            proof.put("density", getTargetContext().getResources().getDisplayMetrics().density);
            proof.put("provider", "test APK only; unchanged frozen production views and consumers");
            proof.put("captures", new JSONArray(captures));
            File dir = outputDirectory();
            try (FileOutputStream out = new FileOutputStream(new File(dir, stem + "-manifest.json"))) { out.write(proof.toString(2).getBytes(StandardCharsets.UTF_8)); }
            result.putString("stream", "PASS: " + captures.size() + " actual frozen UI reference captures\n");
            finish(-1, result);
        } catch (Throwable error) {
            StringWriter stack = new StringWriter(); error.printStackTrace(new PrintWriter(stack));
            result.putString("stream", "FAIL: " + stack.toString() + "\n"); finish(0, result);
        } finally {
            if (server != null) try { server.close(); } catch (IOException ignored) { }
        }
    }
    private byte[] asset(String name) throws IOException {
        try (InputStream in = getContext().getAssets().open(name); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192]; int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            return out.toByteArray();
        }
    }
    private void startServer() throws IOException {
        server = new ServerSocket(8767, 16, InetAddress.getByName("127.0.0.1"));
        Thread worker = new Thread(() -> {
            while (!server.isClosed()) {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    BufferedReader input = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                    int count = 0; String line;
                    while ((line = input.readLine()) != null && !line.isEmpty()) { count += line.length(); if (count > 8192) throw new IOException("Oversized test request"); }
                    OutputStream output = socket.getOutputStream();
                    output.write(("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: " + image.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                    output.write(image); output.flush();
                } catch (IOException ignored) { if (server.isClosed()) break; }
            }
        }, "ParityReferenceHTTP"); worker.setDaemon(true); worker.start();
    }
    private void seed() {
        onMain(() -> {
            Phase8Checks.call(activity, "enterScreen");
            Phase8Checks.set(activity, "discoveryAutoLoadPaused", true);
            Phase8Checks.set(activity, "discoveryErrorMessage", "");
            Phase8Checks.set(activity, "searchLoading", false);
            Phase8Checks.set(activity, "selectedSourceId", "mh160");
            // The cross-platform visual reference uses actual original pixels.
            // GPU availability and the separate AI evidence do not alter this state.
            Phase8Checks.set(activity, "readerEnhancementMode", 0);
            Phase8Checks.set(activity, "readerEnhancementComparisonEnabled", false);
            Phase8Checks.set(activity, "readerThemeMode", stem.endsWith("dark") ? MainActivity.READER_THEME_DARK : MainActivity.READER_THEME_LIGHT);
            for (String id : Arrays.asList("mh160", "copy4000", "gmh")) {
                ComicSource old = (ComicSource) Phase8Checks.get(activity, id + "Client");
                FixtureSource source = new FixtureSource(id, old.name());
                Phase8Checks.set(activity, id + "Client", source);
                if (id.equals("mh160")) Phase8Checks.set(activity, "sourceClient", source);
            }
            FixtureSource source = (FixtureSource) Phase8Checks.get(activity, "mh160Client");
            Map<String, ComicSummary> summaries = (Map) Phase8Checks.get(activity, "summaries");
            Map<String, ComicDetail> details = (Map) Phase8Checks.get(activity, "details");
            List<String> favorites = (List) Phase8Checks.get(activity, "favorites");
            Map<String, Long> favoriteAt = (Map) Phase8Checks.get(activity, "favoriteAt");
            List<ComicSummary> rows = (List) Phase8Checks.get(activity, "searchResults");
            summaries.clear(); details.clear(); favorites.clear(); favoriteAt.clear(); rows.clear();
            long clock = 1000;
            for (ComicSummary comic : source.latest(1)) {
                summaries.put(comic.comicId, comic); details.put(comic.comicId, source.detail(comic.comicId));
                favorites.add(comic.comicId); favoriteAt.put(comic.comicId, clock++); rows.add(comic);
            }
            List<FilterGroup> filters = (List) Phase8Checks.get(activity, "sourceFilterGroups");
            filters.clear(); filters.addAll(source.filterGroups());
            ((Map) Phase8Checks.get(activity, "progress")).put("mh160:comic_0", fixture.optInt("readChapterIndex"));
            ((Map) Phase8Checks.get(activity, "lastViewedAt")).put("mh160:comic_0", 2000L);
        });
    }
    private void status(String step) {
        Bundle update = new Bundle(); update.putString("stream", "REFERENCE STEP: " + step + "\n"); sendStatus(1, update);
    }
    private void onMain(Runnable block) {
        CountDownLatch done = new CountDownLatch(1); AtomicReference<Throwable> failure = new AtomicReference<>();
        new Handler(Looper.getMainLooper()).post(() -> {
            try { block.run(); } catch (Throwable error) { failure.set(error); } finally { done.countDown(); }
        });
        try { if (!done.await(15, TimeUnit.SECONDS)) throw new AssertionError("Frozen UI main thread did not respond"); }
        catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new IllegalStateException(error); }
        if (failure.get() != null) throw new IllegalStateException("Frozen UI action failed", failure.get());
        SystemClock.sleep(600);
    }
    private void dismissDialogs() { getUiAutomation().performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK); SystemClock.sleep(500); }
    private File outputDirectory() throws IOException {
        File dir = new File(getTargetContext().getExternalFilesDir(null), "parity-reference");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("Cannot create reference output"); return dir;
    }
    private void shot(String scene) throws Exception {
        status("capture-" + scene);
        // The first-use system cling is delayed after entering immersive mode.
        // Dismiss its actual button rather than masking it in the screenshot.
        SystemClock.sleep(scene.equals("reader") || scene.equals("reading_settings") || scene.equals("reader_directory") ? 1800 : 800);
        dismissFullscreenHelp();
        AccessibilityNodeInfo active = getUiAutomation().getRootInActiveWindow();
        if (active == null) throw new AssertionError("Missing active application window: " + scene);
        String activePackage;
        try { activePackage = String.valueOf(active.getPackageName()); }
        finally { active.recycle(); }
        if (!"com.xxcomic".equals(activePackage)) throw new AssertionError("Unexpected active window " + activePackage + ": " + scene);
        Bitmap screenshot = getUiAutomation().takeScreenshot();
        if (screenshot == null) throw new AssertionError("No actual screenshot");
        String filename = stem + "_" + scene + ".png"; File file = new File(outputDirectory(), filename);
        int width = screenshot.getWidth(), height = screenshot.getHeight();
        try (FileOutputStream out = new FileOutputStream(file)) { if (!screenshot.compress(Bitmap.CompressFormat.PNG, 100, out)) throw new IOException("Cannot encode screenshot"); }
        finally { screenshot.recycle(); }
        JSONObject record = new JSONObject(); record.put("file", filename); record.put("sha256", sha(read(file)));
        record.put("activeWindowPackage", activePackage);
        record.put("pixels", new JSONArray(Arrays.asList(width, height)));
        final JSONArray components = new JSONArray();
        onMain(() -> {
            View decor = activity.getWindow().getDecorView();
            int[] position = new int[2]; decor.getLocationOnScreen(position);
            try {
                record.put("decorBoundsOnScreen", new JSONArray(Arrays.asList(position[0], position[1], position[0] + decor.getWidth(), position[1] + decor.getHeight())));
                record.put("componentCoordinates", "screen");
            } catch (JSONException error) { throw new IllegalStateException(error); }
            component(decor, components);
        });
        if (scene.equals("reader") || scene.equals("reading_settings") || scene.equals("reader_directory")) {
            JSONObject state = new JSONObject();
            state.put("enhancementMode", Phase8Checks.get(activity, "readerEnhancementMode"));
            state.put("enhancementComparison", Phase8Checks.get(activity, "readerEnhancementComparisonEnabled"));
            state.put("themeMode", Phase8Checks.get(activity, "readerThemeMode"));
            state.put("layoutMode", Phase8Checks.get(activity, "readerLayoutMode"));
            state.put("controlsVisible", !((Boolean) Phase8Checks.get(activity, "readerFullscreen")));
            record.put("readerState", state);
        }
        if (scene.equals("source_drawer") || scene.equals("reading_settings") || scene.equals("reader_directory")) {
            AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
            if (root == null) throw new AssertionError("Missing actual modal accessibility tree: " + scene);
            try { modalComponent(root, components); } finally { root.recycle(); }
        }
        record.put("components", components); record.put("capturedAtMillis", System.currentTimeMillis()); captures.add(record);
    }
    private void dismissFullscreenHelp() {
        AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        if (root == null) return;
        List<AccessibilityNodeInfo> heading = root.findAccessibilityNodeInfosByText("Viewing full screen");
        List<AccessibilityNodeInfo> buttons = root.findAccessibilityNodeInfosByText("GOT IT");
        boolean dismissed = false;
        try {
            if (heading.isEmpty()) return;
            String owner = String.valueOf(root.getPackageName());
            if (!"android".equals(owner) && !"com.android.systemui".equals(owner)) throw new AssertionError("Fullscreen help has unexpected owner: " + owner);
            for (AccessibilityNodeInfo button : buttons) {
                if (button.isClickable() && button.performAction(AccessibilityNodeInfo.ACTION_CLICK)) { dismissed = true; break; }
            }
            if (!dismissed) throw new AssertionError("Cannot dismiss the actual system fullscreen help button");
            status("system-fullscreen-help-dismissed");
        } finally {
            for (AccessibilityNodeInfo node : heading) node.recycle();
            for (AccessibilityNodeInfo node : buttons) node.recycle();
            root.recycle();
        }
        if (dismissed) SystemClock.sleep(500);
    }
    private void modalComponent(AccessibilityNodeInfo node, JSONArray rows) throws JSONException {
        if (!node.isVisibleToUser()) return;
        Rect bounds = new Rect(); node.getBoundsInScreen(bounds);
        CharSequence text = node.getText(), description = node.getContentDescription();
        if (text != null || description != null) {
            JSONObject row = new JSONObject(); row.put("text", text == null ? "" : text.toString());
            row.put("description", description == null ? "" : description.toString());
            row.put("type", String.valueOf(node.getClassName())); row.put("origin", "active-modal-accessibility");
            row.put("bounds", new JSONArray(Arrays.asList(bounds.left, bounds.top, bounds.right, bounds.bottom))); rows.put(row);
        }
        for (int n = 0; n < node.getChildCount(); n++) {
            AccessibilityNodeInfo child = node.getChild(n);
            if (child != null) try { modalComponent(child, rows); } finally { child.recycle(); }
        }
    }
    private void component(View view, JSONArray rows) {
        Rect visible = new Rect(); if (!view.getGlobalVisibleRect(visible) || view.getAlpha() == 0) return;
        // getGlobalVisibleRect uses root-view coordinates. Modal accessibility
        // bounds and screenshots use screen coordinates, including window offset.
        int[] rootPosition = new int[2]; view.getRootView().getLocationOnScreen(rootPosition);
        visible.offset(rootPosition[0], rootPosition[1]);
        try {
            String text = view instanceof TextView ? ((TextView) view).getText().toString() : "";
            CharSequence description = view.getContentDescription();
            if (!text.isEmpty() || description != null) {
                JSONObject row = new JSONObject(); row.put("text", text); row.put("description", description == null ? "" : description.toString()); row.put("origin", "view-screen");
                row.put("type", view.getClass().getSimpleName()); row.put("bounds", new JSONArray(Arrays.asList(visible.left, visible.top, visible.right, visible.bottom)));
                if (view instanceof TextView) row.put("fontPx", ((TextView) view).getTextSize()); rows.put(row);
            }
        } catch (JSONException error) { throw new IllegalStateException(error); }
        if (view instanceof ViewGroup) for (int n = 0; n < ((ViewGroup) view).getChildCount(); n++) component(((ViewGroup) view).getChildAt(n), rows);
    }
    private static byte[] read(File file) throws IOException {
        try (InputStream in = new FileInputStream(file); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] bytes = new byte[8192]; int count; while ((count = in.read(bytes)) != -1) out.write(bytes, 0, count); return out.toByteArray();
        }
    }
    private static String sha(byte[] bytes) throws Exception {
        StringBuilder out = new StringBuilder(); for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) out.append(String.format(Locale.ROOT, "%02x", value & 255)); return out.toString();
    }
    private final class FixtureSource implements ComicSource {
        private final String id, name;
        FixtureSource(String id, String name) { this.id = id; this.name = name; }
        public String id() { return id; } public String name() { return name; } public String domain() { return "127.0.0.1"; }
        public List<ComicSummary> latest(int page) {
            List<ComicSummary> rows = new ArrayList<>(); if (page != 1) return rows;
            JSONArray titles = fixture.optJSONArray("titles"), tags = fixture.optJSONArray("tags"); List<String> strings = new ArrayList<>();
            for (int n = 0; n < tags.length(); n++) strings.add(tags.optString(n));
            for (int n = 0; n < titles.length(); n++) rows.add(new ComicSummary(id, id + ":comic_" + n, titles.optString(n),
                "http://127.0.0.1:8767/cover-" + n + ".png", fixture.optString("subtitle"), strings, fixture.optString("latestChapter")));
            return rows;
        }
        public List<ComicSummary> search(String keyword, int page) { List<ComicSummary> rows = latest(page); rows.removeIf(row -> !row.title.contains(keyword.trim())); return rows; }
        public List<String> categories() { return Arrays.asList("热血"); }
        public List<FilterGroup> filterGroups() {
            List<FilterOption> options = new ArrayList<>(); JSONArray values = fixture.optJSONArray("filterOptions");
            for (int n = 0; n < values.length(); n++) options.add(new FilterOption(values.optJSONObject(n).optString("label"), values.optJSONObject(n).optString("value")));
            return Arrays.asList(new FilterGroup(fixture.optString("filterKey"), fixture.optString("filterLabel"), options));
        }
        public List<ComicSummary> category(String region, String state, int page) { return latest(page); }
        public ComicDetail detail(String comicID) {
            ComicSummary summary = null; for (ComicSummary row : latest(1)) if (row.comicId.equals(comicID)) summary = row;
            if (summary == null) throw new IllegalArgumentException("Unknown fixture comic");
            return new ComicDetail(summary, fixture.optString("author"), fixture.optString("status"), fixture.optString("description"), fixture.optString("latestChapter"), chapters(comicID));
        }
        public List<Chapter> chapters(String comicID) {
            List<Chapter> rows = new ArrayList<>(); for (int n = 1; n <= fixture.optInt("chapterCount"); n++)
                rows.add(new Chapter(id + ":chapter_" + n, "第" + n + "话", "http://127.0.0.1:8767/" + id + "/chapter/" + n, 0, n - 1)); return rows;
        }
        public ChapterPage chapter(String url) {
            String number = url.substring(url.lastIndexOf('/') + 1); List<String> urls = new ArrayList<>();
            for (int n = 0; n < fixture.optInt("pagesPerChapter"); n++) urls.add("http://127.0.0.1:8767/page-" + number + "-" + n + ".png");
            return new ChapterPage(id + ":chapter_" + number, "第" + number + "话", urls, null);
        }
        public boolean healthCheck() { return true; }
    }
}
