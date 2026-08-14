package com.xxcomic.source;

import android.text.TextUtils;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

final class SourceFilters {
    private SourceFilters() {
    }

    static ComicModels.FilterGroup group(String key, String label, String... pairs) {
        List<ComicModels.FilterOption> options = new ArrayList<>();
        for (int i = 0; i + 1 < pairs.length; i += 2) {
            options.add(new ComicModels.FilterOption(pairs[i], pairs[i + 1]));
        }
        return new ComicModels.FilterGroup(key, label, options);
    }

    static ComicModels.FilterGroup group(String key, String label, Map<String, String> values) {
        List<ComicModels.FilterOption> options = new ArrayList<>();
        options.add(new ComicModels.FilterOption("全部", "all"));
        for (Map.Entry<String, String> entry : values.entrySet()) {
            if (!TextUtils.isEmpty(entry.getKey()) && !"全部".equals(entry.getKey())) {
                options.add(new ComicModels.FilterOption(entry.getKey(), entry.getValue()));
            }
        }
        return new ComicModels.FilterGroup(key, label, options);
    }

    static String value(Map<String, String> filters, String key, String fallback) {
        String value = filters == null ? null : filters.get(key);
        return TextUtils.isEmpty(value) ? fallback : value;
    }
}
