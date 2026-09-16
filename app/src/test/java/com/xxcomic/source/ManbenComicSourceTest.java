package com.xxcomic.source;

import org.junit.Test;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import static org.junit.Assert.*;

public class ManbenComicSourceTest {
    @Test(timeout = 2000) public void liveDetailParsesAuthorWithoutOverflowOrBacktracking() throws Exception {
        try (InputStream stream = getClass().getResourceAsStream("/manben/detail-info.html")) {
            assertNotNull(stream);
            String html = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertEquals("踏雪动漫", ManbenComicSource.authorHtml(html).trim());
        }
    }

    @Test(timeout = 2000) public void longLinksWithoutAuthorFinishAndTemplateHrefKeepsItsGreaterThan() {
        String prefix = "<a href=\"" + new String(new char[20000]).replace('\0', 'x') + "\">other</a>";
        assertEquals("", ManbenComicSource.authorHtml(prefix));
        assertEquals("作者", ManbenComicSource.authorHtml(prefix
                + "<a href=\"/search?title=<%htmlurlencode(作者)%>\" class='small avatar'>作者</a>"));
        assertEquals("", ManbenComicSource.authorHtml("<a href=\"class='avatar'\" class='other'>错误作者</a>"));
    }
}
