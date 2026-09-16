package com.xxcomic;

import org.json.JSONArray;
import org.json.JSONException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Stable source IDs survive enable changes, renames and app upgrades. */
final class SourceOrder {
    interface Id<T> { String get(T item); }

    static List<String> decode(String json) {
        List<String> ids = new ArrayList<>();
        try {
            JSONArray values = new JSONArray(json);
            for (int i = 0; i < values.length(); i++) {
                Object value = values.opt(i);
                if (value instanceof String && !((String) value).isEmpty()
                        && !ids.contains(value)) ids.add((String) value);
            }
        } catch (JSONException ignored) { }
        return ids;
    }

    static <T> List<T> apply(List<T> defaults, List<String> order, Id<T> id) {
        Map<String, T> remaining = new LinkedHashMap<>();
        for (T item : defaults) remaining.put(id.get(item), item);
        List<T> result = new ArrayList<>();
        for (String key : order) {
            T item = remaining.remove(key);
            if (item != null) result.add(item);
        }
        result.addAll(remaining.values());
        return result;
    }

    static List<String> normalize(List<String> order, List<String> available) {
        return apply(available, order, id -> id);
    }

    private SourceOrder() { }
}
