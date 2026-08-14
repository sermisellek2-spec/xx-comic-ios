package com.xxcomic.source;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public interface ComicSource {
    String id();

    String name();

    String domain();

    List<ComicModels.ComicSummary> latest(int page) throws IOException;

    List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException;

    List<String> categories() throws IOException;

    default List<ComicModels.FilterGroup> filterGroups() throws IOException {
        List<ComicModels.FilterOption> options = new ArrayList<>();
        options.add(new ComicModels.FilterOption("全部", "all"));
        for (String category : categories()) {
            if (category != null && !category.isEmpty() && !"全部".equals(category)) {
                options.add(new ComicModels.FilterOption(category, category));
            }
        }
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        groups.add(new ComicModels.FilterGroup("region", "题材", options));
        return groups;
    }

    List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException;

    default List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String region = filters == null ? "all" : filters.get("region");
        String state = filters == null ? "all" : filters.get("state");
        return category(region == null ? "all" : region, state == null ? "all" : state, page);
    }

    ComicModels.ComicDetail detail(String comicId) throws IOException;

    List<ComicModels.Chapter> chapters(String comicId) throws IOException;

    ComicModels.ChapterPage chapter(String chapterUrl) throws IOException;

    boolean healthCheck();
}
