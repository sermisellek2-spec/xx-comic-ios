package com.xxcomic;

import android.app.Instrumentation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
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
            onMain(() -> Phase8Checks.call(activity, "showReader", detail, 0)); shot("reader");
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
            Phase8Checks.set(activity, "readerEnhancementMode", 2);
            Phase8Checks.set(activity, "readerEnhancementComparisonEnabled", true);
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
        status("capture-" + scene); SystemClock.sleep(800);
        Bitmap screenshot = getUiAutomation().takeScreenshot();
        if (screenshot == null) throw new AssertionError("No actual screenshot");
        String filename = stem + "_" + scene + ".png"; File file = new File(outputDirectory(), filename);
        int width = screenshot.getWidth(), height = screenshot.getHeight();
        try (FileOutputStream out = new FileOutputStream(file)) { if (!screenshot.compress(Bitmap.CompressFormat.PNG, 100, out)) throw new IOException("Cannot encode screenshot"); }
        finally { screenshot.recycle(); }
        JSONObject record = new JSONObject(); record.put("file", filename); record.put("sha256", sha(read(file)));
        record.put("pixels", new JSONArray(Arrays.asList(width, height)));
        final JSONArray components = new JSONArray();
        onMain(() -> component(activity.getWindow().getDecorView(), components));
        record.put("components", components); record.put("capturedAtMillis", System.currentTimeMillis()); captures.add(record);
    }
    private void component(View view, JSONArray rows) {
        Rect visible = new Rect(); if (!view.getGlobalVisibleRect(visible) || view.getAlpha() == 0) return;
        try {
            String text = view instanceof TextView ? ((TextView) view).getText().toString() : "";
            CharSequence description = view.getContentDescription();
            if (!text.isEmpty() || description != null) {
                JSONObject row = new JSONObject(); row.put("text", text); row.put("description", description == null ? "" : description.toString());
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
