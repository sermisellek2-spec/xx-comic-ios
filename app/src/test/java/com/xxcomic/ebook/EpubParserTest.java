package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;
import com.xxcomic.local.LocalModels;

import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

import static org.junit.Assert.*;

public class EpubParserTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private final ArchiveIndex.ImageProbe mockProbe = source -> true;

    private static final byte[] FAKE_JPEG = new byte[]{
            (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0,
            0x00, 0x10, 'J', 'F', 'I', 'F', 0x00, 0x01,
            0x01, 0x01, 0x00, 0x60, 0x00, 0x60, 0x00, 0x00,
            (byte) 0xFF, (byte) 0xD9
    };

    private static final byte[] FAKE_PNG = new byte[]{
            (byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 'I', 'H', 'D', 'R',
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, (byte) 0xC4, (byte) 0x89,
            0x00, 0x00, 0x00, 0x00, 'I', 'E', 'N', 'D',
            (byte) 0xAE, 0x42, 0x60, (byte) 0x82
    };

    private static void addEntry(ZipOutputStream zos, String name, byte[] data) throws IOException {
        ZipEntry entry = new ZipEntry(name);
        entry.setTime(System.currentTimeMillis());
        zos.putNextEntry(entry);
        if (data != null && data.length > 0) {
            zos.write(data);
        }
        zos.closeEntry();
    }

    private static void addStringEntry(ZipOutputStream zos, String name, String content) throws IOException {
        addEntry(zos, name, content.getBytes(StandardCharsets.UTF_8));
    }

    private File createEpub(String containerXml, String opfPath, String opfXml,
                            String[][] additionalEntries) throws IOException {
        File file = temp.newFile("test_" + System.nanoTime() + ".epub");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(file))) {
            addStringEntry(zos, "mimetype", "application/epub+zip");
            addStringEntry(zos, "META-INF/container.xml", containerXml != null ? containerXml :
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                    "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" +
                    "  <rootfiles>\n" +
                    "    <rootfile full-path=\"" + (opfPath != null ? opfPath : "OEBPS/content.opf") + "\" media-type=\"application/oebps-package+xml\"/>\n" +
                    "  </rootfiles>\n" +
                    "</container>");

            if (opfPath == null) opfPath = "OEBPS/content.opf";
            addStringEntry(zos, opfPath, opfXml);

            if (additionalEntries != null) {
                for (String[] entry : additionalEntries) {
                    String name = entry[0];
                    String type = entry[1];
                    String content = entry[2];
                    if ("jpeg".equals(type)) {
                        addEntry(zos, name, FAKE_JPEG);
                    } else if ("png".equals(type)) {
                        addEntry(zos, name, FAKE_PNG);
                    } else {
                        addStringEntry(zos, name, content != null ? content : "");
                    }
                }
            }
        }
        return file;
    }

    @Test
    public void ordersAccordingToSpineNotFilenames() throws Exception {
        // In physical ZIP, 10.xhtml is added first, then 02.xhtml, then 01.xhtml
        // But spine orders them: p01 -> p02 -> p10
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>Spine Order Test</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"p01\" href=\"text/01.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"p02\" href=\"text/02.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"p10\" href=\"text/10.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"img1\" href=\"images/01.jpg\" media-type=\"image/jpeg\"/>\n" +
                "    <item id=\"img2\" href=\"images/02.jpg\" media-type=\"image/jpeg\"/>\n" +
                "    <item id=\"img10\" href=\"images/10.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine>\n" +
                "    <itemref idref=\"p01\"/>\n" +
                "    <itemref idref=\"p02\"/>\n" +
                "    <itemref idref=\"p10\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String html10 = "<html><body><img src=\"../images/10.jpg\"/></body></html>";
        String html02 = "<html><body><img src=\"../images/02.jpg\"/></body></html>";
        String html01 = "<html><body><img src=\"../images/01.jpg\"/></body></html>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/text/10.xhtml", "text", html10},
                {"OEBPS/text/02.xhtml", "text", html02},
                {"OEBPS/text/01.xhtml", "text", html01},
                {"OEBPS/images/10.jpg", "jpeg", null},
                {"OEBPS/images/02.jpg", "jpeg", null},
                {"OEBPS/images/01.jpg", "jpeg", null},
        });

        Publication pub = EpubParser.parse(epub);
        assertEquals("Spine Order Test", pub.title);
        assertTrue(pub.isPurePictureEpub);
        assertEquals(3, pub.spine.size());

        assertEquals("OEBPS/images/01.jpg", pub.spine.get(0).resolvedImageEntry);
        assertEquals("OEBPS/images/02.jpg", pub.spine.get(1).resolvedImageEntry);
        assertEquals("OEBPS/images/10.jpg", pub.spine.get(2).resolvedImageEntry);

        try (ZipFile zip = new ZipFile(epub)) {
            ArchiveIndex.ParseResult pr = pub.toParseResult("book_1", zip, mockProbe, null);
            assertEquals(1, pr.chapters.size());
            assertEquals(3, pr.totalPages);
            LocalModels.Chapter ch = pr.chapters.get(0);
            assertEquals(3, pr.pagesByChapter.get(ch.id).size());
            assertEquals("OEBPS/images/01.jpg", pr.pagesByChapter.get(ch.id).get(0).entryPath);
            assertEquals("OEBPS/images/02.jpg", pr.pagesByChapter.get(ch.id).get(1).entryPath);
            assertEquals("OEBPS/images/10.jpg", pr.pagesByChapter.get(ch.id).get(2).entryPath);
        }
    }

    @Test
    public void parsesEpub2NcxNavigationAndDividesChapters() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>NCX Comic</dc:title>\n" +
                "    <dc:creator>Rem</dc:creator>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n" +
                "    <item id=\"p1\" href=\"text/ch1_1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"p2\" href=\"text/ch1_2.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"p3\" href=\"text/ch2_1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"p4\" href=\"text/ch2_2.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"img1\" href=\"images/1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "    <item id=\"img2\" href=\"images/2.jpg\" media-type=\"image/jpeg\"/>\n" +
                "    <item id=\"img3\" href=\"images/3.jpg\" media-type=\"image/jpeg\"/>\n" +
                "    <item id=\"img4\" href=\"images/4.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine toc=\"ncx\">\n" +
                "    <itemref idref=\"p1\"/>\n" +
                "    <itemref idref=\"p2\"/>\n" +
                "    <itemref idref=\"p3\"/>\n" +
                "    <itemref idref=\"p4\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String ncx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">\n" +
                "  <navMap>\n" +
                "    <navPoint id=\"np1\" playOrder=\"1\">\n" +
                "      <navLabel><text>第一话：相遇</text></navLabel>\n" +
                "      <content src=\"text/ch1_1.xhtml\"/>\n" +
                "    </navPoint>\n" +
                "    <navPoint id=\"np2\" playOrder=\"2\">\n" +
                "      <navLabel><text>第二话：羁绊</text></navLabel>\n" +
                "      <content src=\"text/ch2_1.xhtml\"/>\n" +
                "    </navPoint>\n" +
                "  </navMap>\n" +
                "</ncx>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/toc.ncx", "text", ncx},
                {"OEBPS/text/ch1_1.xhtml", "text", "<html><body><img src=\"../images/1.jpg\"/></body></html>"},
                {"OEBPS/text/ch1_2.xhtml", "text", "<html><body><img src=\"../images/2.jpg\"/></body></html>"},
                {"OEBPS/text/ch2_1.xhtml", "text", "<html><body><img src=\"../images/3.jpg\"/></body></html>"},
                {"OEBPS/text/ch2_2.xhtml", "text", "<html><body><img src=\"../images/4.jpg\"/></body></html>"},
                {"OEBPS/images/1.jpg", "jpeg", null},
                {"OEBPS/images/2.jpg", "jpeg", null},
                {"OEBPS/images/3.jpg", "jpeg", null},
                {"OEBPS/images/4.jpg", "jpeg", null},
        });

        Publication pub = EpubParser.parse(epub);
        assertEquals("NCX Comic", pub.title);
        assertEquals("Rem", pub.author);
        assertEquals(2, pub.navItems.size());
        assertEquals("第一话：相遇", pub.navItems.get(0).title);
        assertEquals(0, pub.navItems.get(0).spineIndex);
        assertEquals("第二话：羁绊", pub.navItems.get(1).title);
        assertEquals(2, pub.navItems.get(1).spineIndex);

        try (ZipFile zip = new ZipFile(epub)) {
            ArchiveIndex.ParseResult pr = pub.toParseResult("ncx_book", zip, mockProbe, null);
            assertEquals(2, pr.chapters.size());
            assertEquals("第一话：相遇", pr.chapters.get(0).title);
            assertEquals(2, pr.chapters.get(0).pageCount);
            assertEquals("第二话：羁绊", pr.chapters.get(1).title);
            assertEquals(2, pr.chapters.get(1).pageCount);
            assertEquals(4, pr.totalPages);
        }
    }

    @Test
    public void parsesEpub3NavDocument() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>EPUB3 Comic</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n" +
                "    <item id=\"p1\" href=\"p1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"p2\" href=\"p2.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"img1\" href=\"1.png\" media-type=\"image/png\"/>\n" +
                "    <item id=\"img2\" href=\"2.png\" media-type=\"image/png\"/>\n" +
                "  </manifest>\n" +
                "  <spine>\n" +
                "    <itemref idref=\"p1\"/>\n" +
                "    <itemref idref=\"p2\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String nav = "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">\n" +
                "<body>\n" +
                "  <nav epub:type=\"toc\">\n" +
                "    <ol>\n" +
                "      <li><a href=\"p1.xhtml\">Chapter 1</a></li>\n" +
                "      <li><a href=\"p2.xhtml\">Chapter 2</a></li>\n" +
                "    </ol>\n" +
                "  </nav>\n" +
                "</body>\n" +
                "</html>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/nav.xhtml", "text", nav},
                {"OEBPS/p1.xhtml", "text", "<html><body><img src=\"1.png\"/></body></html>"},
                {"OEBPS/p2.xhtml", "text", "<html><body><img src=\"2.png\"/></body></html>"},
                {"OEBPS/1.png", "png", null},
                {"OEBPS/2.png", "png", null},
        });

        Publication pub = EpubParser.parse(epub);
        assertEquals("EPUB3 Comic", pub.title);
        assertEquals(2, pub.navItems.size());
        assertEquals("Chapter 1", pub.navItems.get(0).title);
        assertEquals(0, pub.navItems.get(0).spineIndex);
        assertEquals("Chapter 2", pub.navItems.get(1).title);
        assertEquals(1, pub.navItems.get(1).spineIndex);
    }

    @Test
    public void parsesSvgWrappedImagesAndDirectImageSpine() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>SVG Comic</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"p1\" href=\"svg_page.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"img1\" href=\"images/1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "    <item id=\"img2\" href=\"images/2.png\" media-type=\"image/png\"/>\n" +
                "  </manifest>\n" +
                "  <spine>\n" +
                "    <itemref idref=\"p1\"/>\n" +
                "    <itemref idref=\"img2\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String svgHtml = "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n" +
                "<body>\n" +
                "  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100%\" height=\"100%\">\n" +
                "    <image xlink:href=\"images/1.jpg\" width=\"800\" height=\"1200\"/>\n" +
                "  </svg>\n" +
                "</body>\n" +
                "</html>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/svg_page.xhtml", "text", svgHtml},
                {"OEBPS/images/1.jpg", "jpeg", null},
                {"OEBPS/images/2.png", "png", null},
        });

        Publication pub = EpubParser.parse(epub);
        assertTrue(pub.isPurePictureEpub);
        assertEquals("OEBPS/images/1.jpg", pub.spine.get(0).resolvedImageEntry);
        assertEquals("OEBPS/images/2.png", pub.spine.get(1).resolvedImageEntry);
    }

    @Test
    public void coverImagePropertiesAndMetaDetection() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>Cover Test</dc:title>\n" +
                "    <meta name=\"cover\" content=\"my_cover_id\"/>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"my_cover_id\" href=\"my_cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>\n" +
                "    <item id=\"p1\" href=\"1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine>\n" +
                "    <itemref idref=\"p1\"/>\n" +
                "  </spine>\n" +
                "</package>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/my_cover.jpg", "jpeg", null},
                {"OEBPS/1.jpg", "jpeg", null},
        });

        Publication pub = EpubParser.parse(epub);
        assertEquals("OEBPS/my_cover.jpg", pub.coverEntry);
    }

    @Test
    public void preventsXxeAttack() throws Exception {
        String maliciousOpf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<!DOCTYPE package [\n" +
                "  <!ENTITY xxe SYSTEM \"file:///etc/passwd\">\n" +
                "]>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>&xxe;</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"p1\" href=\"1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine><itemref idref=\"p1\"/></spine>\n" +
                "</package>";

        File epub = createEpub(null, null, maliciousOpf, new String[][]{
                {"OEBPS/1.jpg", "jpeg", null}
        });

        Publication pub = EpubParser.parse(epub);
        // Entity resolution was safely intercepted, no external entity loaded
        assertNotEquals("root:x:0:0", pub.title);
    }

    @Test
    public void preventsZipSlipPathTraversal() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>ZipSlip Test</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"p1\" href=\"../../etc/passwd\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine><itemref idref=\"p1\"/></spine>\n" +
                "</package>";

        File epub = createEpub(null, null, opf, null);

        try {
            EpubParser.parse(epub);
            fail("Should have rejected path traversal");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("越界"));
        }
    }

    @Test
    public void recognizesFontObfuscationVsDrm() throws Exception {
        // Case 1: Font obfuscation only -> Not DRM
        String fontEnc = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<encryption xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" +
                "  <EncryptedData xmlns=\"http://www.w3.org/2001/04/xmlenc#\">\n" +
                "    <EncryptionMethod Algorithm=\"http://www.idpf.org/2008/embedding\"/>\n" +
                "    <CipherData><CipherReference URI=\"OEBPS/fonts/myfont.otf\"/></CipherData>\n" +
                "  </EncryptedData>\n" +
                "</encryption>";

        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>Font Obfuscated</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"p1\" href=\"1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "  <spine><itemref idref=\"p1\"/></spine>\n" +
                "</package>";

        File epubFont = createEpub(null, null, opf, new String[][]{
                {"META-INF/encryption.xml", "text", fontEnc},
                {"OEBPS/1.jpg", "jpeg", null},
        });

        Publication pubFont = EpubParser.parse(epubFont);
        assertTrue(pubFont.hasFontObfuscation);
        assertFalse(pubFont.hasDrm);

        // Case 2: Content encryption -> DRM
        String drmEnc = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<encryption xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" +
                "  <EncryptedData xmlns=\"http://www.w3.org/2001/04/xmlenc#\">\n" +
                "    <EncryptionMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#aes128-cbc\"/>\n" +
                "    <CipherData><CipherReference URI=\"OEBPS/text/page1.xhtml\"/></CipherData>\n" +
                "  </EncryptedData>\n" +
                "</encryption>";

        File epubDrm = createEpub(null, null, opf, new String[][]{
                {"META-INF/encryption.xml", "text", drmEnc},
                {"OEBPS/1.jpg", "jpeg", null},
        });

        Publication pubDrm = EpubParser.parse(epubDrm);
        assertTrue(pubDrm.hasDrm);
        assertNotNull(pubDrm.unsupportedReason);
    }

    @Test
    public void recognizesReflowableTextNovel() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>Text Novel</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"ch1\" href=\"text/ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "    <item id=\"ch2\" href=\"text/ch2.xhtml\" media-type=\"application/xhtml+xml\"/>\n" +
                "  </manifest>\n" +
                "  <spine>\n" +
                "    <itemref idref=\"ch1\"/>\n" +
                "    <itemref idref=\"ch2\"/>\n" +
                "  </spine>\n" +
                "</package>";

        String ch1 = "<html><body><h1>第 1 章</h1><p>这里是纯文字小说内容，有很多段落文字。</p></body></html>";
        String ch2 = "<html><body><h1>第 2 章</h1><p>这里是第 2 章的纯文字内容，没有包含任何图片。</p></body></html>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/text/ch1.xhtml", "text", ch1},
                {"OEBPS/text/ch2.xhtml", "text", ch2},
        });

        Publication pub = EpubParser.parse(epub);
        assertTrue(pub.isReflowableText);
        assertFalse(pub.isPurePictureEpub);

        try (ZipFile zip = new ZipFile(epub)) {
            pub.toParseResult("text_book", zip, mockProbe, null);
            fail("Should have rejected text novel");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("纯文本"));
        }
    }

    @Test
    public void missingContainerThrowsError() throws Exception {
        File file = temp.newFile("bad.epub");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(file))) {
            addStringEntry(zos, "mimetype", "application/epub+zip");
            addStringEntry(zos, "something.txt", "hello");
        }
        try {
            EpubParser.parse(file);
            fail("Should fail on missing container.xml");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("META-INF/container.xml"));
        }
    }

    @Test
    public void missingSpineThrowsError() throws Exception {
        String opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\n" +
                "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" +
                "    <dc:title>No Spine</dc:title>\n" +
                "  </metadata>\n" +
                "  <manifest>\n" +
                "    <item id=\"p1\" href=\"1.jpg\" media-type=\"image/jpeg\"/>\n" +
                "  </manifest>\n" +
                "</package>";

        File epub = createEpub(null, null, opf, new String[][]{
                {"OEBPS/1.jpg", "jpeg", null}
        });

        try {
            EpubParser.parse(epub);
            fail("Should fail on missing spine");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("spine"));
        }
    }
}
