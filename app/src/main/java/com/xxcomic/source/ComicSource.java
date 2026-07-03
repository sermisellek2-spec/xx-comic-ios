package com.xxcomic.source;

import java.io.IOException;
import java.util.List;

public interface ComicSource {
    String id();

    String name();

    String domain();

    List<ComicModels.ComicSummary> latest(int page) throws IOException;

    List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException;

    List<String> categories() throws IOException;

    List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException;

    ComicModels.ComicDetail detail(String comicId) throws IOException;

    List<ComicModels.Chapter> chapters(String comicId) throws IOException;

    ComicModels.ChapterPage chapter(String chapterUrl) throws IOException;

    boolean healthCheck();
}
