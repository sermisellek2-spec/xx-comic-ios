package com.xxcomic;

import java.util.List;

public final class AppModels {
    private AppModels() {
    }

    public static class Comic {
        public final String id;
        public final String title;
        public final String author;
        public final String status;
        public final String latestChapter;
        public final String sourceName;
        public final List<String> tags;
        public final String description;
        public final int[] colors;
        public String lastChapter = "";
        public int progressChapter = 0;
        public int progressPage = 3;

        public Comic(String id, String title, String author, String status, String latestChapter, String sourceName, List<String> tags, String description, int[] colors) {
            this.id = id;
            this.title = title;
            this.author = author;
            this.status = status;
            this.latestChapter = latestChapter;
            this.sourceName = sourceName;
            this.tags = tags;
            this.description = description;
            this.colors = colors;
        }
    }

    public static class Source {
        public final String id;
        public final String name;
        public final String domain;
        public final String url;
        public boolean enabled;

        public Source(String id, String name, String domain, boolean enabled) {
            this.id = id;
            this.name = name;
            this.domain = domain;
            this.url = "";
            this.enabled = enabled;
        }

        public Source(String id, String name, String domain, String url, boolean builtin, boolean enabled) {
            this.id = id;
            this.name = name;
            this.domain = domain;
            this.url = url;
            this.enabled = enabled;
        }
    }
}
