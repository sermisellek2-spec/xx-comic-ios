package com.xxcomic.search;

import com.xxcomic.source.ComicModels;

import java.util.ArrayList;
import java.util.List;

public final class GlobalSearchMatchHelper {

    private GlobalSearchMatchHelper() {}

    /**
     * 比较漫画标题与搜索关键词是否完全一致。
     * 规则：只去除首尾空白，不做模糊匹配，不删除标点或后缀。
     */
    public static boolean isExactTitleMatch(String title, String query) {
        if (title == null || query == null) return false;
        String trimmedTitle = title.trim();
        String trimmedQuery = query.trim();
        if (trimmedQuery.isEmpty()) return false;
        return trimmedTitle.equals(trimmedQuery);
    }

    /**
     * 将第一页搜索结果中与关键词完全一致的漫画置顶。
     * 多本同名作品全部保留并保持原相对顺序，其他结果也保持原顺序。
     */
    public static List<ComicModels.ComicSummary> prioritizeExactMatches(
            List<ComicModels.ComicSummary> items, String query) {
        if (items == null || items.isEmpty()) return new ArrayList<>();
        String trimmedQuery = query == null ? "" : query.trim();
        if (trimmedQuery.isEmpty()) return new ArrayList<>(items);

        List<ComicModels.ComicSummary> exactMatches = new ArrayList<>();
        List<ComicModels.ComicSummary> others = new ArrayList<>();

        for (ComicModels.ComicSummary item : items) {
            if (item != null && isExactTitleMatch(item.title, trimmedQuery)) {
                exactMatches.add(item);
            } else {
                others.add(item);
            }
        }

        if (exactMatches.isEmpty()) {
            return new ArrayList<>(items);
        }

        List<ComicModels.ComicSummary> result = new ArrayList<>(items.size());
        result.addAll(exactMatches);
        result.addAll(others);
        return result;
    }

    /**
     * 判断结果列表中是否存在与关键词完全一致的作品。
     * 判定逻辑与 prioritizeExactMatches 保持 100% 一致。
     */
    public static boolean hasExactTitleMatch(List<ComicModels.ComicSummary> items, String query) {
        if (items == null || items.isEmpty()) return false;
        String trimmedQuery = query == null ? "" : query.trim();
        if (trimmedQuery.isEmpty()) return false;

        for (ComicModels.ComicSummary item : items) {
            if (item != null && isExactTitleMatch(item.title, trimmedQuery)) {
                return true;
            }
        }
        return false;
    }
}
