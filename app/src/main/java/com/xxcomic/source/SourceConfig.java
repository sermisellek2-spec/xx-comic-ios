package com.xxcomic.source;

import android.text.TextUtils;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Iterator;

public class SourceConfig {
    public final String id;
    public final String name;
    public final String domain;
    public final String baseUrl;
    public final String referer;
    public final String latestPath;
    public final String searchPath;
    public final String categoryPath;
    public final String detailPath;
    public final boolean enabled;
    public final JSONObject routes;
    public final JSONObject filters;

    public SourceConfig(String id, String name, String domain, String baseUrl, String referer, String latestPath, String searchPath, String categoryPath, String detailPath, boolean enabled, JSONObject routes, JSONObject filters) {
        this.id = id;
        this.name = name;
        this.domain = domain;
        this.baseUrl = baseUrl;
        this.referer = TextUtils.isEmpty(referer) ? baseUrl + "/" : referer;
        this.latestPath = latestPath;
        this.searchPath = searchPath;
        this.categoryPath = categoryPath;
        this.detailPath = detailPath;
        this.enabled = enabled;
        this.routes = routes == null ? new JSONObject() : routes;
        this.filters = filters == null ? new JSONObject() : filters;
    }

    public static SourceConfig baozi(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/list/new{pagePath}");
            routes.put("search", "/search?q={keyword}");
            routes.put("category", "/classify?type=all&region={region}&state={state}&filter=all{pageQuery}");
            routes.put("categoryApi", "/api/bzmhq/amp_comic_list?type=all&region={region}&state={state}&filter=*&page={page}&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com");
            routes.put("detail", "/comic/{comicId}");
            routes.put("chapter", "{chapterUrl}");
            filters.put("region.cn", "cn");
            filters.put("region.jp", "jp");
            filters.put("region.kr", "kr");
            filters.put("region.en", "en");
            filters.put("region.all", "all");
            filters.put("state.serial", "serial");
            filters.put("state.pub", "pub");
            filters.put("state.all", "all");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("baozimh", "包子漫画", "cn.bzmgcn.com", "https://cn.bzmgcn.com", "https://cn.bzmgcn.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig mhua5(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/index.php/category{pagePath}");
            routes.put("search", "/index.php/search?key={keyword}{pageQuery}");
            routes.put("category", "/index.php/category{cityPath}{finishPath}{pagePath}");
            routes.put("detail", "/index.php/comic/{comicId}");
            routes.put("chapter", "/index.php/chapter/{chapterId}");
            filters.put("city.cn", "42");
            filters.put("city.jp", "45");
            filters.put("city.kr", "44");
            filters.put("city.en", "");
            filters.put("finish.serial", "1");
            filters.put("finish.pub", "2");
            filters.put("finish.all", "");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("mhua5", "漫画屋", "www.mhua5.com", "https://www.mhua5.com", "https://www.mhua5.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig aikan(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/category{pagePath}");
            routes.put("search", "/index.php/search?key={keyword}{pageQuery}");
            routes.put("category", "/category{finishPath}{pagePath}");
            routes.put("detail", "/youbooks/{comicId}.html");
            routes.put("chapter", "/chook/{chapterId}");
            filters.put("finish.serial", "1");
            filters.put("finish.pub", "2");
            filters.put("finish.all", "");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("aikan", "爱看漫画", "www.0592cr.com", "https://www.0592cr.com", "https://www.0592cr.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig gmh(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/manga{pagePath}");
            routes.put("search", "/s/{keyword}");
            routes.put("category", "/manga{genrePath}{pagePath}");
            routes.put("detail", "/manga/{comicId}");
            routes.put("chapter", "/manga/{comicId}/{chapterSlug}");
            routes.put("mangaApi", "https://v2.apikk.top/api/v2/manga/get?mid={mid}&mode=all");
            routes.put("chapterApi", "https://v2.apikk.top/api/v2/chapter/getinfo?m={mid}&c={chapterId}");
            filters.put("genre.kr", "kr");
            filters.put("genre.hots", "hots");
            filters.put("genre.cn", "cn");
            filters.put("genre.jp", "jp");
            filters.put("genre.all", "");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("gmh", "G社漫画", "m.g-mh.org", "https://m.g-mh.org", "https://m.g-mh.org/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig mkzhan(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/category{query}");
            routes.put("search", "/search/?keyword={keyword}");
            routes.put("category", "/category{query}");
            routes.put("detail", "/{comicId}/");
            routes.put("chapter", "/{comicId}/{chapterId}.html");
            routes.put("chapterApi", "https://comic.mkzcdn.com/chapter/content/v1/?chapter_id={chapterId}&comic_id={comicId}&quality=1&type=1&format=0&uid=&sign=");
            filters.put("filter.serial", "finish=1");
            filters.put("filter.pub", "finish=2");
            filters.put("filter.free", "is_free=1");
            filters.put("filter.fee", "is_fee=1");
            filters.put("filter.vip", "is_vip=1");
            filters.put("filter.all", "");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("mkzhan", "漫客栈", "www.mkzhan.com", "https://www.mkzhan.com", "https://www.mkzhan.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig hiperdex(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/manga/?m_orderby=latest{pageQuery}");
            routes.put("search", "/?s={keyword}&post_type=wp-manga{pageQuery}");
            routes.put("category", "/manga/{genrePath}{pagePath}");
            routes.put("detail", "/manga/{comicId}/");
            routes.put("chapter", "/manga/{comicId}/{chapterSlug}/");
            filters.put("genre.all", "");
            filters.put("genre.manhwa", "manhwa");
            filters.put("genre.webtoon", "webtoon");
            filters.put("genre.romance", "romance");
            filters.put("genre.drama", "drama");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("hiperdex", "HiperDEX", "hiperdex.com", "https://hiperdex.com", "https://hiperdex.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig hanman18(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/list-manga{pagePath}");
            routes.put("search", "/search?search={keyword}");
            routes.put("category", "/list-manga{pagePath}");
            routes.put("detail", "/manhwa/{comicId}");
            routes.put("chapter", "/manhwa/{comicId}/{chapterId}");
            routes.put("home", "/");
            filters.put("category.all", "");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("hanman18", "Hanman18", "hanman18.com", "https://hanman18.com", "https://hanman18.com/", "", "", "", "", enabled, routes, filters);
    }

    public SourceConfig withEnabled(boolean value) {
        return new SourceConfig(id, name, domain, baseUrl, referer, latestPath, searchPath, categoryPath, detailPath, value, routes, filters);
    }

    public JSONObject toJson() throws JSONException {
        JSONObject object = new JSONObject();
        object.put("id", id);
        object.put("name", name);
        object.put("domain", domain);
        object.put("baseUrl", baseUrl);
        object.put("referer", referer);
        object.put("enabled", enabled);
        object.put("routes", routes);
        object.put("filters", filters);
        return object;
    }

    public static SourceConfig fromJson(JSONObject object, SourceConfig fallback) {
        JSONObject routes = mergeObject(fallback.routes, object.optJSONObject("routes"));
        JSONObject filters = mergeObject(fallback.filters, object.optJSONObject("filters"));
        return new SourceConfig(
                object.optString("id", fallback.id),
                object.optString("name", fallback.name),
                object.optString("domain", fallback.domain),
                trimSlash(object.optString("baseUrl", fallback.baseUrl)),
                object.optString("referer", fallback.referer),
                object.optString("latestPath", fallback.latestPath),
                object.optString("searchPath", fallback.searchPath),
                object.optString("categoryPath", fallback.categoryPath),
                object.optString("detailPath", fallback.detailPath),
                object.optBoolean("enabled", fallback.enabled),
                routes,
                filters);
    }

    public String route(String key) {
        String value = routes.optString(key);
        if (!TextUtils.isEmpty(value)) return value;
        if ("latest".equals(key)) return latestPath;
        if ("search".equals(key)) return searchPath;
        if ("category".equals(key)) return categoryPath;
        if ("detail".equals(key)) return detailPath;
        return "";
    }

    public String filter(String key) {
        return filters.optString(key, "");
    }

    private static String trimSlash(String value) {
        if (value == null) return "";
        while (value.endsWith("/") && value.length() > 8) value = value.substring(0, value.length() - 1);
        return value;
    }

    private static JSONObject mergeObject(JSONObject defaults, JSONObject overrides) {
        JSONObject result = new JSONObject();
        copyInto(result, defaults);
        copyInto(result, overrides);
        return result;
    }

    private static void copyInto(JSONObject target, JSONObject source) {
        if (source == null) return;
        Iterator<String> keys = source.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            try {
                target.put(key, source.opt(key));
            } catch (JSONException ignored) {
            }
        }
    }
}
