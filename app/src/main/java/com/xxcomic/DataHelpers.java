package com.xxcomic;

import android.text.TextUtils;
import java.util.ArrayList;
import java.util.List;

public final class DataHelpers {
    private DataHelpers() {
    }

    public static List<String> chaptersFor(AppModels.Comic comic, List<String> baseChapters) {
        List<String> chapters = new ArrayList<>(baseChapters);
        chapters.add(comic.latestChapter);
        return chapters;
    }

    public static List<Integer> chapterOrder(boolean chapterDesc, int size) {
        List<Integer> order = new ArrayList<>();
        if (chapterDesc) {
            for (int i = size - 1; i >= 0; i--) order.add(i);
        } else {
            for (int i = 0; i < size; i++) order.add(i);
        }
        return order;
    }

    public static List<AppModels.Comic> filteredSearchResults(String searchQuery, String searchTag, List<AppModels.Comic> searchResults) {
        List<AppModels.Comic> list = new ArrayList<>();
        String query = searchQuery.trim();
        for (AppModels.Comic comic : searchResults) {
            boolean queryMatched = query.isEmpty()
                    || comic.title.contains(query)
                    || comic.author.contains(query)
                    || TextUtils.join("", comic.tags).contains(query);
            boolean tagMatched = TextUtils.isEmpty(searchTag) || "全部".equals(searchTag) || comic.tags.contains(searchTag);
            if (queryMatched && tagMatched) list.add(comic);
        }
        return list;
    }

    public static int readHistoryCount(List<AppModels.Comic> searchResults) {
        int count = 0;
        for (AppModels.Comic comic : searchResults) {
            if (!TextUtils.isEmpty(comic.lastChapter)) count++;
        }
        return count;
    }

    public static String readHistoryText(List<AppModels.Comic> searchResults) {
        StringBuilder builder = new StringBuilder();
        for (AppModels.Comic comic : searchResults) {
            if (!TextUtils.isEmpty(comic.lastChapter)) {
                if (builder.length() > 0) builder.append("\n");
                builder.append(comic.title).append(" ").append(comic.lastChapter);
            }
        }
        return builder.length() == 0 ? "还没有阅读历史。" : builder.toString();
    }
}
