package com.xxcomic.source;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class BaoziComicSourceTest {
    @Test
    public void categoryFiltersOverrideValuesFromOldPersistedRoute() {
        String oldUrl = "https://cn.bzmgcn.com/classify?type=all&region=all&state=all&filter=all";

        assertEquals(
                "https://cn.bzmgcn.com/classify?type=rexie&region=jp&state=serial&filter=ABCD",
                BaoziComicSource.withCategoryFilters(oldUrl, "rexie", "jp", "serial", "ABCD", 1));
    }

    @Test
    public void categoryFiltersKeepApiOptionsAndSetPage() {
        String oldUrl = "https://cn.bzmgcn.com/api/bzmhq/amp_comic_list?type=all&region=all&state=all&filter=*&page=2&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com";

        assertEquals(
                "https://cn.bzmgcn.com/api/bzmhq/amp_comic_list?limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com&type=qihuan&region=kr&state=pub&filter=XYZ&page=3",
                BaoziComicSource.withCategoryFilters(oldUrl, "qihuan", "kr", "pub", "XYZ", 3));
    }
}
