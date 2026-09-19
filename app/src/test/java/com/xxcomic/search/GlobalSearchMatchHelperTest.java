package com.xxcomic.search;

import com.xxcomic.source.ComicModels;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

public class GlobalSearchMatchHelperTest {

    private static ComicModels.ComicSummary comic(String id, String title) {
        return new ComicModels.ComicSummary("testSource", id, title, "", "", Collections.emptyList());
    }

    @Test
    public void testIsExactTitleMatch_BasicAndWhitespace() {
        // 完全一致
        assertTrue(GlobalSearchMatchHelper.isExactTitleMatch("海贼王", "海贼王"));

        // 只去除首尾空白
        assertTrue(GlobalSearchMatchHelper.isExactTitleMatch("  海贼王  ", "海贼王"));
        assertTrue(GlobalSearchMatchHelper.isExactTitleMatch("海贼王", "  海贼王  "));
        assertTrue(GlobalSearchMatchHelper.isExactTitleMatch("\t海贼王\n", " \t海贼王 "));

        // 中间空格不去除
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海 贼 王", "海贼王"));
        assertTrue(GlobalSearchMatchHelper.isExactTitleMatch("ONE PIECE", "ONE PIECE"));
        assertTrue(GlobalSearchMatchHelper.isExactTitleMatch("  ONE PIECE  ", "ONE PIECE"));
    }

    @Test
    public void testIsExactTitleMatch_NoFuzzyOrPunctuationOrSuffixRemoval() {
        // 不做模糊匹配：包含关系不属于完全一致
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王 狂热行动", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王特别篇", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("新海贼王", "海贼王"));

        // 不删除标点符号
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王！", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王.", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("《海贼王》", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王：草帽篇", "海贼王"));

        // 不删除后缀
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王[完]", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王（全彩）", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王-全彩版", "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王 第1部", "海贼王"));
    }

    @Test
    public void testIsExactTitleMatch_NullAndEmptySafety() {
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch(null, "海贼王"));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王", null));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch(null, null));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王", ""));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("海贼王", "   "));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("", ""));
        assertFalse(GlobalSearchMatchHelper.isExactTitleMatch("   ", "   "));
    }

    @Test
    public void testPrioritizeExactMatches_SingleExactMatchMovedToTop() {
        ComicModels.ComicSummary c1 = comic("1", "海贼王 剧场版");
        ComicModels.ComicSummary c2 = comic("2", "火影忍者");
        ComicModels.ComicSummary c3 = comic("3", "海贼王");
        ComicModels.ComicSummary c4 = comic("4", "死神");

        List<ComicModels.ComicSummary> items = Arrays.asList(c1, c2, c3, c4);
        List<ComicModels.ComicSummary> prioritized = GlobalSearchMatchHelper.prioritizeExactMatches(items, "海贼王");

        assertEquals(4, prioritized.size());
        assertEquals("3", prioritized.get(0).comicId);
        assertEquals("1", prioritized.get(1).comicId);
        assertEquals("2", prioritized.get(2).comicId);
        assertEquals("4", prioritized.get(3).comicId);
    }

    @Test
    public void testPrioritizeExactMatches_MultipleExactMatchesPreserveOrder() {
        // 多本同名作品全部置顶并保持原相对顺序，其他作品也保持原相对顺序
        ComicModels.ComicSummary c1 = comic("1", "其他作品A");
        ComicModels.ComicSummary c2 = comic("2", "海贼王"); // 同名第1本
        ComicModels.ComicSummary c3 = comic("3", "其他作品B");
        ComicModels.ComicSummary c4 = comic("4", "  海贼王  "); // 同名第2本（首尾空格）
        ComicModels.ComicSummary c5 = comic("5", "其他作品C");
        ComicModels.ComicSummary c6 = comic("6", "海贼王"); // 同名第3本

        List<ComicModels.ComicSummary> items = Arrays.asList(c1, c2, c3, c4, c5, c6);
        List<ComicModels.ComicSummary> prioritized = GlobalSearchMatchHelper.prioritizeExactMatches(items, "  海贼王  ");

        assertEquals(6, prioritized.size());
        // 置顶部分：c2, c4, c6 保持原相对顺序
        assertEquals("2", prioritized.get(0).comicId);
        assertEquals("4", prioritized.get(1).comicId);
        assertEquals("6", prioritized.get(2).comicId);
        // 其余部分：c1, c3, c5 保持原相对顺序
        assertEquals("1", prioritized.get(3).comicId);
        assertEquals("3", prioritized.get(4).comicId);
        assertEquals("5", prioritized.get(5).comicId);
    }

    @Test
    public void testPrioritizeExactMatches_NoMatchesOrAllMatches() {
        ComicModels.ComicSummary c1 = comic("1", "火影忍者");
        ComicModels.ComicSummary c2 = comic("2", "死神");
        List<ComicModels.ComicSummary> items = Arrays.asList(c1, c2);

        // 无同名结果：顺序原样保持
        List<ComicModels.ComicSummary> noMatch = GlobalSearchMatchHelper.prioritizeExactMatches(items, "海贼王");
        assertEquals(2, noMatch.size());
        assertEquals("1", noMatch.get(0).comicId);
        assertEquals("2", noMatch.get(1).comicId);

        // 全是同名结果：顺序原样保持
        ComicModels.ComicSummary h1 = comic("10", "海贼王");
        ComicModels.ComicSummary h2 = comic("20", "海贼王");
        List<ComicModels.ComicSummary> allMatch = GlobalSearchMatchHelper.prioritizeExactMatches(Arrays.asList(h1, h2), "海贼王");
        assertEquals(2, allMatch.size());
        assertEquals("10", allMatch.get(0).comicId);
        assertEquals("20", allMatch.get(1).comicId);
    }

    @Test
    public void testPrioritizeExactMatches_EmptyAndNullSafety() {
        assertTrue(GlobalSearchMatchHelper.prioritizeExactMatches(null, "海贼王").isEmpty());
        assertTrue(GlobalSearchMatchHelper.prioritizeExactMatches(new ArrayList<>(), "海贼王").isEmpty());

        ComicModels.ComicSummary c1 = comic("1", "海贼王");
        List<ComicModels.ComicSummary> items = Collections.singletonList(c1);

        // 空搜索词不重排
        assertEquals(1, GlobalSearchMatchHelper.prioritizeExactMatches(items, "").size());
        assertEquals(1, GlobalSearchMatchHelper.prioritizeExactMatches(items, "   ").size());
        assertEquals(1, GlobalSearchMatchHelper.prioritizeExactMatches(items, null).size());
    }

    @Test
    public void testHasExactTitleMatch_ConsistencyWithPrioritization() {
        ComicModels.ComicSummary c1 = comic("1", "海贼王 剧场版");
        ComicModels.ComicSummary c2 = comic("2", "海贼王");
        ComicModels.ComicSummary c3 = comic("3", "死神");

        List<ComicModels.ComicSummary> listWithMatch = Arrays.asList(c1, c2, c3);
        List<ComicModels.ComicSummary> listWithoutMatch = Arrays.asList(c1, c3);

        assertTrue(GlobalSearchMatchHelper.hasExactTitleMatch(listWithMatch, "海贼王"));
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(listWithoutMatch, "海贼王"));

        // 判定与排序严格一致
        boolean hasMatch = GlobalSearchMatchHelper.hasExactTitleMatch(listWithMatch, "海贼王");
        List<ComicModels.ComicSummary> prioritized = GlobalSearchMatchHelper.prioritizeExactMatches(listWithMatch, "海贼王");
        boolean firstIsExact = !prioritized.isEmpty() && GlobalSearchMatchHelper.isExactTitleMatch(prioritized.get(0).title, "海贼王");
        assertEquals(hasMatch, firstIsExact);

        // 空列表或空关键词不报错且返回 false
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(null, "海贼王"));
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(Collections.emptyList(), "海贼王"));
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(listWithMatch, ""));
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(listWithMatch, "   "));
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(listWithMatch, null));
    }

    @Test
    public void testKeywordSwitchAndOldResultIsolation() {
        // 场景：第一轮搜索关键词“海贼王”
        String query1 = "海贼王";
        List<ComicModels.ComicSummary> results1 = Arrays.asList(
                comic("101", "海贼王 剧场版"),
                comic("102", "海贼王")
        );
        List<ComicModels.ComicSummary> prioritized1 = GlobalSearchMatchHelper.prioritizeExactMatches(results1, query1);
        assertEquals("102", prioritized1.get(0).comicId);
        assertTrue(GlobalSearchMatchHelper.hasExactTitleMatch(prioritized1, query1));

        // 用户发起第二轮搜索关键词“火影忍者”
        String query2 = "火影忍者";
        // 1. 新搜索开始，清除上一轮结果与红点状态
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(Collections.emptyList(), query2));

        // 2. 假设旧请求的延迟结果尝试以新关键词做判定：旧结果不包含“火影忍者”，红点判定为 false
        assertFalse(GlobalSearchMatchHelper.hasExactTitleMatch(prioritized1, query2));

        // 3. 新请求正常到达：包含“火影忍者”
        List<ComicModels.ComicSummary> results2 = Arrays.asList(
                comic("201", "火影忍者博人传"),
                comic("202", "火影忍者")
        );
        List<ComicModels.ComicSummary> prioritized2 = GlobalSearchMatchHelper.prioritizeExactMatches(results2, query2);
        assertEquals("202", prioritized2.get(0).comicId);
        assertTrue(GlobalSearchMatchHelper.hasExactTitleMatch(prioritized2, query2));
    }
}
