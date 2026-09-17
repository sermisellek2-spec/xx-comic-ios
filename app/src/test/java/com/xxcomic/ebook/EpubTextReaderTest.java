package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;

import org.junit.Assert;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

public class EpubTextReaderTest {

    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private File createEpub(String[][] files) throws IOException {
        File epub = temp.newFile("test_novel_" + System.nanoTime() + ".epub");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(epub))) {
            for (String[] item : files) {
                String path = item[0];
                String content = item[1];
                zos.putNextEntry(new ZipEntry(path));
                if (content != null) {
                    zos.write(content.getBytes(StandardCharsets.UTF_8));
                }
                zos.closeEntry();
            }
        }
        return epub;
    }

    @Test
    public void parsesTextNovelIntoChaptersAndXhtmlPages() throws Exception {
        String container = "<?xml version=\"1.0\"?>\n" +
                "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" +
                "  <rootfiles>\n" +
                "    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n" +
                "  </rootfiles>\n" +
                "</container>";

        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>从零开始的异世界生活</dc:title>\n" +
                "    <dc:creator>长月达平</dc:creator>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"ch1\" href=\"text/ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"ch2\" href=\"text/ch2.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"ch3\" href=\"text/ch3.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n" +
                "  </manifest>\n" +
                "  <spine toc=\"ncx\">\n" +
                "    <itemref idref=\"ch1\"/>\n" +
                "    <itemref idref=\"ch2\"/>\n" +
                "    <itemref idref=\"ch3\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String ncx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">\n" +
                "  <navMap>\n" +
                "    <navPoint id=\"np1\" playOrder=\"1\">\n" +
                "      <navLabel><text>第一章：初始的始末</text></navLabel>\n" +
                "      <content src=\"text/ch1.xhtml\"/>\n" +
                "    </navPoint>\n" +
                "    <navPoint id=\"np2\" playOrder=\"2\">\n" +
                "      <navLabel><text>第二章：重逢之夜</text></navLabel>\n" +
                "      <content src=\"text/ch2.xhtml\"/>\n" +
                "    </navPoint>\n" +
                "    <navPoint id=\"np3\" playOrder=\"3\">\n" +
                "      <navLabel><text>第三章：银发的少女</text></navLabel>\n" +
                "      <content src=\"text/ch3.xhtml\"/>\n" +
                "    </navPoint>\n" +
                "  </navMap>\n" +
                "</ncx>";

        String ch1Content = "<html><body><h1>第一章</h1><p>菜月昴突然被召唤到了异世界。</p></body></html>";
        String ch2Content = "<html><body><h1>第二章</h1><p>遇到了自称莎缇拉的半精灵少女。</p></body></html>";
        String ch3Content = "<html><body><h1>第三章</h1><p>微风吹拂着银色长发。</p></body></html>";

        File epub = createEpub(new String[][]{
                {"META-INF/container.xml", container},
                {"OEBPS/content.opf", opf},
                {"OEBPS/toc.ncx", ncx},
                {"OEBPS/text/ch1.xhtml", ch1Content},
                {"OEBPS/text/ch2.xhtml", ch2Content},
                {"OEBPS/text/ch3.xhtml", ch3Content},
        });

        Publication pub = EpubParser.parse(epub);
        Assert.assertEquals("从零开始的异世界生活", pub.title);
        Assert.assertEquals("长月达平", pub.author);
        Assert.assertTrue(pub.isReflowableText);
        Assert.assertFalse(pub.isPurePictureEpub);
        Assert.assertEquals(3, pub.spine.size());
        Assert.assertEquals(3, pub.navItems.size());

        try (ZipFile zip = new ZipFile(epub)) {
            ArchiveIndex.ParseResult pr = pub.toParseResult("re0_book", zip, null, null);
            Assert.assertNotNull(pr);
            Assert.assertEquals(3, pr.totalPages);
            Assert.assertEquals(3, pr.chapters.size());

            Assert.assertEquals("第一章：初始的始末", pr.chapters.get(0).title);
            Assert.assertEquals("第二章：重逢之夜", pr.chapters.get(1).title);
            Assert.assertEquals("第三章：银发的少女", pr.chapters.get(2).title);

            for (int i = 0; i < 3; i++) {
                Assert.assertEquals(1, pr.chapters.get(i).pageCount);
                Assert.assertEquals("application/xhtml+xml",
                        pr.pagesByChapter.get(pr.chapters.get(i).id).get(0).mimeType);
            }
        }
    }

    @Test
    public void parsesMixedEpubWithTextAndImages() throws Exception {
        String container = "<?xml version=\"1.0\"?>\n" +
                "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" +
                "  <rootfiles>\n" +
                "    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n" +
                "  </rootfiles>\n" +
                "</container>";

        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>图文混排轻小说</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"cover\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>\n" +
                "    <item id=\"p1\" href=\"text/ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"ill1\" href=\"img/ill1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine>\n" +
                "    <itemref idref=\"p1\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String ch1Content = "<html><body><h1>第 1 章</h1><p>前方出现了插图：</p><img src=\"../img/ill1.jpg\"/><p>插图后的文字内容。</p></body></html>";

        File epub = createEpub(new String[][]{
                {"META-INF/container.xml", container},
                {"OEBPS/content.opf", opf},
                {"OEBPS/cover.jpg", "dummy_cover_bytes"},
                {"OEBPS/text/ch1.xhtml", ch1Content},
                {"OEBPS/img/ill1.jpg", "dummy_image_bytes"},
        });

        Publication pub = EpubParser.parse(epub);
        Assert.assertNotNull(pub);
        Assert.assertEquals("OEBPS/cover.jpg", pub.coverEntry);

        try (ZipFile zip = new ZipFile(epub)) {
            ArchiveIndex.ParseResult pr = pub.toParseResult("mixed_book", zip, null, null);
            Assert.assertEquals(1, pr.totalPages);
            Assert.assertEquals(1, pr.chapters.size());
            Assert.assertEquals("OEBPS/cover.jpg", pr.candidateCoverEntries.get(0));
        }
    }
}
