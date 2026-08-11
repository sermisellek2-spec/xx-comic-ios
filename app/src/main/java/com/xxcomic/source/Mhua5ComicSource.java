package com.xxcomic.source;

import java.io.IOException;
import java.util.List;

/** Resolves cached records from the retired Manga House source without network access. */
public class Mhua5ComicSource implements ComicSource {
    private static final String SOURCE_ID = "mhua5";
    private static final String DOMAIN = "www.mhua5.com";

    @Override
    public String id() {
        return SOURCE_ID;
    }

    @Override
    public String name() {
        return "漫画屋（已下线）";
    }

    @Override
    public String domain() {
        return DOMAIN;
    }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        throw unavailable();
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        throw unavailable();
    }

    @Override
    public List<String> categories() throws IOException {
        throw unavailable();
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        throw unavailable();
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        throw unavailable();
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        throw unavailable();
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        throw unavailable();
    }

    @Override
    public boolean healthCheck() {
        return false;
    }

    private IOException unavailable() {
        return new IOException("漫画屋站源已下线");
    }
}
