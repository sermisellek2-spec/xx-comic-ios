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
            routes.put("category", "/classify?type={type}&region={region}&state={state}&filter={filter}{pageQuery}");
            routes.put("categoryApi", "/api/bzmhq/amp_comic_list?type={type}&region={region}&state={state}&filter={filter}&page={page}&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com");
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

    public static SourceConfig manhuagui(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/list");
            routes.put("search", "/s/{keyword}.html");
            routes.put("category", "/list");
            routes.put("detail", "/comic/{comicId}");
            routes.put("chapter", "/comic/{comicId}/{chapterId}.html");
            filters.put("region.all", "");
            filters.put("region.jp", "japan");
            filters.put("region.cn", "china");
            filters.put("region.kr", "korea");
            filters.put("region.hk", "hongkong");
            filters.put("region.en", "europe");
            filters.put("region.other", "other");
            filters.put("state.all", "");
            filters.put("state.serial", "lianzai");
            filters.put("state.pub", "wanjie");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("manhuagui", "漫画柜", "www.manhuagui.com", "https://www.manhuagui.com", "https://www.manhuagui.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig d5d6(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/jiujiucate_jiujiuquanbu_allvisit_0_{page}/");
            routes.put("search", "/search/{keyword}/");
            routes.put("category", "/jiujiucate_{slug}_allvisit_{finish}_{page}/");
            routes.put("categoryIndex", "/jiujiucate_quanbu/");
            routes.put("detail", "/jiujiucomic_{comicId}/");
            routes.put("chapter", "/jiujiucomic_{comicId}/{chapterId}.html");
            filters.put("category.all", "jiujiuquanbu");
            filters.put("category.cn", "jiujiudalu");
            filters.put("category.jp", "jiujiuriben");
            filters.put("category.kr", "jiujiuhanguo");
            filters.put("category.en", "jiujiuoumei");
            filters.put("state.all", "0");
            filters.put("state.serial", "1");
            filters.put("state.pub", "2");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("d5d6", "悦看漫画", "www.d5d6.com", "https://www.d5d6.com", "https://www.d5d6.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig manben(boolean enabled) {
        JSONObject routes = new JSONObject();
        JSONObject filters = new JSONObject();
        try {
            routes.put("latest", "/mh-list/pagerdata.ashx");
            routes.put("categoryIndex", "/mh-list/");
            routes.put("category", "/mh-list/pagerdata.ashx");
            routes.put("search", "/search?page={page}&title={keyword}&language=1");
            routes.put("detail", "/mh-{comicId}/");
            routes.put("chapter", "/m{chapterId}/");
            routes.put("chapterImages", "/imageshow.ashx?cid={chapterId}&page={page}&showtype=1&ispre=0");
            filters.put("sort.latest", "2");
            filters.put("sort.popular", "4");
            filters.put("state.all", "0");
            filters.put("state.serial", "1");
            filters.put("state.pub", "2");
            filters.put("category.全部", "");
            filters.put("category.题材·搞笑", "tagid:37");
            filters.put("category.题材·奇幻", "tagid:14");
            filters.put("category.题材·热血", "tagid:31");
            filters.put("category.题材·悬疑", "tagid:17");
            filters.put("category.题材·格斗", "tagid:28");
            filters.put("category.题材·科幻", "tagid:25");
            filters.put("category.题材·励志", "tagid:10");
            filters.put("category.题材·校园", "tagid:1");
            filters.put("category.题材·爱情", "tagid:26");
            filters.put("category.题材·日常", "tagid:7");
            filters.put("category.题材·战争", "tagid:12");
            filters.put("category.题材·其他", "tagid:3");
            filters.put("category.受众·少年向", "tgroup:1");
            filters.put("category.受众·少女向", "tgroup:2");
            filters.put("category.受众·青年向", "tgroup:3");
            filters.put("category.地区·港台", "tarea:35");
            filters.put("category.地区·日韩", "tarea:36");
            filters.put("category.地区·大陆", "tarea:37");
            filters.put("category.地区·欧美", "tarea:52");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("manben", "漫本", "www.manben.com", "https://www.manben.com", "https://www.manben.com/", "", "", "", "", enabled, routes, filters);
    }

    public static SourceConfig manhuazhan(boolean enabled) {
        return fiveUm("manhuazhan", "漫画栈", "www.60ti.com", "https://www.60ti.com", enabled);
    }

    public static SourceConfig bbyin(boolean enabled) {
        return fiveUm("bbyin", "比卡漫画", "bbyin.com", "https://bbyin.com", enabled);
    }

    public static SourceConfig antbyw(boolean enabled) {
        JSONObject routes = new JSONObject();
        try {
            routes.put("latest", "/plugin.php?id=jameson_manhua&c=index&a=ku");
            routes.put("search", "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}");
            routes.put("categoryIndex", "/plugin.php?id=jameson_manhua&a=ku");
            routes.put("category", "/plugin.php?id=jameson_manhua&c=index&a=ku");
            routes.put("detail", "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}");
            routes.put("chapter", "{chapterUrl}");
        } catch (JSONException ignored) {
        }
        return new SourceConfig("antbyw", "tapmanga搬运", "www.antbyw.com", "https://www.antbyw.com", "https://www.antbyw.com/", "", "", "", "", enabled, routes, new JSONObject());
    }

    private static SourceConfig fiveUm(String id, String name, String domain, String baseUrl, boolean enabled) {
        JSONObject routes = new JSONObject();
        try {
            routes.put("latest", "/category{pagePath}");
            routes.put("search", "/search?key={keyword}");
            routes.put("categoryIndex", "/category/");
            routes.put("category", "/category{pagePath}");
            routes.put("detail", "/comic_{comicId}.html");
            routes.put("chapter", "{chapterUrl}");
        } catch (JSONException ignored) {
        }
        return new SourceConfig(id, name, domain, baseUrl, baseUrl + "/", "", "", "", "", enabled, routes, new JSONObject());
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
