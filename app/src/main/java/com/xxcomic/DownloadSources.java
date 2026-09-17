package com.xxcomic;

import android.content.Context;
import android.content.SharedPreferences;
import com.xxcomic.source.*;
import java.io.*;
import java.lang.ref.WeakReference;
import org.json.*;

/** Application-owned sources; never starts interactive verification or retains an Activity. */
public final class DownloadSources {
    private static WeakReference<BrowserSession> mh18Session = new WeakReference<>(null);
    public static synchronized void attachMh18(BrowserSession session) { mh18Session = new WeakReference<>(session); }
    private static String mh18Fetch(String url) throws IOException {
        BrowserSession current;
        synchronized (DownloadSources.class) { current = mh18Session.get(); }
        return current != null ? current.fetch(url) : Mh18WebViewSession.fetchCachedForDownload(url);
    }
    private static final java.util.Map<String, ComicSource> customSources = new java.util.HashMap<>();
    public static synchronized void registerSource(ComicSource customSource) {
        if (customSource instanceof FileSourceCapability) customSources.put(customSource.id(), customSource);
        else throw new IllegalArgumentException("Only optional file sources can be registered here");
    }
    public static synchronized void unregisterSource(String id) {
        if (id != null) customSources.remove(id);
    }

    public final SourceConfig config;
    public final ComicSource source;
    public DownloadSources(Context context, String id) throws IOException {
        synchronized (DownloadSources.class) {
            if (customSources.containsKey(id)) {
                ComicSource cs = customSources.get(id);
                this.source = cs;
                this.config = null; // File capabilities resolve their own request descriptors.
                return;
            }
        }
        SourceConfig[] defaults = {SourceConfig.baozi(true), SourceConfig.mh160(true), SourceConfig.gmh(true),
                SourceConfig.mh18(true), SourceConfig.jmcomic(true), SourceConfig.mkzhan(true), SourceConfig.hiperdex(true),
                SourceConfig.manhuagui(true), SourceConfig.hanman18(true), SourceConfig.d5d6(true), SourceConfig.manben(true),
                SourceConfig.manhuazhan(true), SourceConfig.bbyin(true), SourceConfig.antbyw(true), SourceConfig.cuimh(true),
                SourceConfig.liumanhua(true), SourceConfig.copy4000(true), SourceConfig.manwa(true)};
        SourceConfig found = null;
        for (SourceConfig candidate : defaults) if (candidate.id.equals(id)) found = candidate;
        if (found == null) throw new IOException("此站源暂不支持离线下载");
        SharedPreferences prefs = context.getSharedPreferences("xx-comic", Context.MODE_PRIVATE);
        try {
            String raw = prefs.getString("source.configs", "[]");
            JSONArray saved = new JSONArray(raw == null || raw.trim().isEmpty() ? "[]" : raw);
            for (int i=0; i<saved.length(); i++) {
                JSONObject item = saved.getJSONObject(i);
                if (id.equals(item.optString("id"))) found = SourceConfig.fromJson(item, found);
            }
        } catch (JSONException error) { throw new IOException("站源配置无法读取", error); }
        config = found;
        String preferenceId = id.equals("baozimh") ? "baozi" : id;
        if (!config.enabled || !prefs.getBoolean("source."+preferenceId+".enabled", true)) throw new IOException("站源已关闭，请开启后重试");
        if (id.equals(defaults[0].id)) source = new BaoziComicSource(config);
        else if (id.equals(defaults[1].id)) source = new Mh160ComicSource(config);
        else if (id.equals(defaults[2].id)) source = new GmhComicSource(config);
        else if (id.equals(defaults[3].id)) source = new Mh18ComicSource(config, DownloadSources::mh18Fetch);
        else if (id.equals(defaults[4].id)) source = new JmComicSource(config, JmComicWebViewSession::fetchCachedForDownload);
        else if (id.equals(defaults[5].id)) source = new MkzhanComicSource(config);
        else if (id.equals(defaults[6].id)) source = new HiperdexComicSource(config);
        else if (id.equals(defaults[7].id)) source = new ManhuaguiComicSource(config);
        else if (id.equals(defaults[8].id)) source = new Hanman18ComicSource(config);
        else if (id.equals(defaults[9].id)) source = new D5d6ComicSource(config);
        else if (id.equals(defaults[10].id)) source = new ManbenComicSource(config);
        else if (id.equals(defaults[11].id) || id.equals(defaults[12].id)) source = new FiveUmComicSource(config);
        else if (id.equals(defaults[13].id)) source = new AntbywComicSource(config);
        else if (id.equals(defaults[14].id)) source = new CuimhComicSource(config);
        else if (id.equals(defaults[15].id)) source = new LiumanhuaComicSource(config);
        else if (id.equals(defaults[16].id)) source = new CopyMangaComicSource(config);
        else source = new ManwaComicSource(config);
    }
    public String referer(String chapterUrl) {
        String id = config.id;
        return id.equals("baozimh") || id.equals("mkzhan") || id.equals("hiperdex") || id.equals("hanman18")
                || id.equals("d5d6") || id.equals("antbyw") || chapterUrl == null || chapterUrl.isEmpty()
                ? config.referer : chapterUrl;
    }
    public InputStream decode(String imageUrl, InputStream input) throws IOException {
        return ManwaImageDecoder.usesImageHost(imageUrl) ? ManwaImageDecoder.open(input, config.route("imageKey")) : input;
    }
}
