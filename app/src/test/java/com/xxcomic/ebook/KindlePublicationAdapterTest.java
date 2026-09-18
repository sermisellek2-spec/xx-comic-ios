package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;
import com.xxcomic.local.LocalModels;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.zip.ZipFile;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class KindlePublicationAdapterTest {
    @org.junit.Test public void malformedPalmDocCannotSilentlyDropBytes() {
        org.junit.Assert.assertThrows(IllegalArgumentException.class,()->KindlePublicationAdapter.decompressPalmDoc(new byte[]{(byte)0x80}));
        org.junit.Assert.assertThrows(IllegalArgumentException.class,()->KindlePublicationAdapter.decompressPalmDoc(new byte[]{(byte)0x80,0}));
        org.junit.Assert.assertThrows(IllegalArgumentException.class,()->KindlePublicationAdapter.decompressPalmDoc(new byte[]{3,1}));
    }

    @Test
    public void palmDocRecordPaddingAfterDeclaredTextDoesNotFail() {
        byte[] compressed = new byte[]{'a', 'b', 'c', (byte) 0x80};
        byte[] decompressed = KindlePublicationAdapter.decompressPalmDoc(compressed, 3);
        assertEquals("abc", new String(decompressed, StandardCharsets.US_ASCII));
    }

    @Test
    public void palmDocBackreferenceMaySpanTextRecordBoundary() {
        byte[] first = new byte[]{'H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd', '!', (byte) 0x80};
        byte[] second = new byte[]{0x63};
        byte[] decompressed = KindlePublicationAdapter.decompressPalmDoc(new byte[][]{first, second}, 64);
        assertEquals("Hello World!Hello ", new String(decompressed, StandardCharsets.UTF_8));
    }

    @Test
    public void mobiImportUsesDeclaredTextLengthForPaddedPalmDocRecord() throws Exception {
        byte[] compressed = new byte[]{'a', 'b', 'c', (byte) 0x80};
        byte[] mobiData = createMockMobi("带填充的 MOBI", "作者", compressed, 3,
                new byte[][]{createMockJpeg()}, 0, 2);
        File mobiFile = new File(tempDir, "padded.mobi");
        Files.write(mobiFile.toPath(), mobiData);

        KindlePublicationAdapter.ParseResult result = KindlePublicationAdapter.parse(
                mobiFile, "book_padded", new File(tempDir, "derived"), null);
        assertNotNull(result);
        assertNotNull(result.publication);
    }

    private File tempDir;

    @Before
    public void setUp() throws IOException {
        tempDir = Files.createTempDirectory("kindle_adapter_test").toFile();
    }

    @After
    public void tearDown() {
        if (tempDir != null && tempDir.exists()) {
            deleteRecursive(tempDir);
        }
    }

    private void deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) {
                for (File c : children) deleteRecursive(c);
            }
        }
        f.delete();
    }

    @Test
    public void testPalmDocDecompression() {
        // Construct PalmDOC LZ77 stream:
        // "Hello " -> literals 'H', 'e', 'l', 'l', 'o', ' '
        // Space + 'W' -> 0xC0 | ('W' ^ 0x80)
        // distance/length copy of "Hello "
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        // Literals: "Hello"
        baos.write('H');
        baos.write('e');
        baos.write('l');
        baos.write('l');
        baos.write('o');
        baos.write(' ');
        // Space + 'W' (0x57 ^ 0x80 = 0xD7)
        baos.write(0xD7);
        baos.write('o');
        baos.write('r');
        baos.write('l');
        baos.write('d');
        baos.write('!');

        // Now distance/length pair:
        // Let's copy "Hello " (length 6, distance from current end: 13 bytes back)
        // compound = (distance << 3) | (length - 3)
        // distance = 13, length = 6 -> (13 << 3) | (6 - 3) = 104 | 3 = 107 (0x6B)
        // leading 2 bits = 10 -> 0x80 | (compound >> 8) = 0x80
        // second byte = compound & 0xFF = 0x6B
        baos.write(0x80);
        baos.write(0x6B);

        byte[] compressed = baos.toByteArray();
        byte[] decompressed = KindlePublicationAdapter.decompressPalmDoc(compressed);
        String text = new String(decompressed, StandardCharsets.UTF_8);
        assertEquals("Hello  World!Hello ", text);
    }

    private byte[] createMockMobi(String title, String author, String htmlContent,
                                  byte[][] images, int encryptionType) throws IOException {
        byte[] textBytes = htmlContent.getBytes(StandardCharsets.UTF_8);
        return createMockMobi(title, author, textBytes, textBytes.length, images, encryptionType, 1);
    }

    private byte[] createMockMobi(String title, String author, byte[] textBytes, int declaredTextLength,
                                  byte[][] images, int encryptionType, int compression) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(baos);

        int imageCount = (images != null) ? images.length : 0;
        int numRecords = 1 + 1 + imageCount + 1; // Rec 0 + Rec 1 (text) + Images + End

        // PDB Header (78 bytes)
        byte[] nameBytes = new byte[32];
        byte[] titleRaw = "MobiTest".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(titleRaw, 0, nameBytes, 0, titleRaw.length);
        out.write(nameBytes);
        out.writeShort(0);
        out.writeShort(0);
        out.writeInt(12345);
        out.writeInt(12345);
        out.writeInt(0);
        out.writeInt(0);
        out.writeInt(0);
        out.writeInt(0);
        out.write(new byte[]{'B', 'O', 'O', 'K'});
        out.write(new byte[]{'M', 'O', 'B', 'I'});
        out.writeInt(0);
        out.writeInt(0);
        out.writeShort(numRecords);

        // Record Table
        int recTableSize = numRecords * 8;
        int rec0Offset = 78 + recTableSize;

        // Record 0 construction
        ByteArrayOutputStream rec0Baos = new ByteArrayOutputStream();
        DataOutputStream rec0Out = new DataOutputStream(rec0Baos);

        // PalmDOC Header (16 bytes)
        rec0Out.writeShort(compression);
        rec0Out.writeShort(0);
        rec0Out.writeInt(declaredTextLength);
        rec0Out.writeShort(1); // 1 text record
        rec0Out.writeShort(4096);
        rec0Out.writeShort(encryptionType);
        rec0Out.writeShort(0);

        // MOBI Header (starts at 16)
        rec0Out.write(new byte[]{'M', 'O', 'B', 'I'});
        int mobiHeaderLen = 232;
        rec0Out.writeInt(mobiHeaderLen);
        rec0Out.writeInt(2); // type = book
        rec0Out.writeInt(65001); // encoding = UTF-8
        rec0Out.writeInt(123); // unique id
        rec0Out.writeInt(6); // version 6

        // Pad to offset 68 (fullNameOffset)
        rec0Out.write(new byte[68 - 24]);

        byte[] fullTitleBytes = title.getBytes(StandardCharsets.UTF_8);
        int fullNameOffset = 16 + mobiHeaderLen + 200;
        rec0Out.writeInt(fullNameOffset); // 68
        rec0Out.writeInt(fullTitleBytes.length); // 72
        rec0Out.writeInt(1033); // 76
        rec0Out.writeInt(0); // 80
        rec0Out.writeInt(0); // 84
        rec0Out.writeInt(6); // 88
        int firstImageRec = (imageCount > 0) ? 2 : -1;
        rec0Out.writeInt(firstImageRec); // 92: firstImageRecord

        // Pad to offset 128 (exthFlags)
        rec0Out.write(new byte[128 - 96]);
        rec0Out.writeInt(0x40); // exth exists

        // Pad to offset 168 (DRM fields)
        rec0Out.write(new byte[168 - 132]);
        rec0Out.writeInt(encryptionType != 0 ? 1 : 0);
        rec0Out.writeInt(encryptionType != 0 ? 1 : 0);
        rec0Out.writeInt(0);
        rec0Out.writeInt(encryptionType != 0 ? 1 : 0);

        // Pad rest of MOBI header
        if (mobiHeaderLen > 184) {
            rec0Out.write(new byte[mobiHeaderLen - 184]);
        }

        // EXTH Header
        ByteArrayOutputStream exthBaos = new ByteArrayOutputStream();
        DataOutputStream exthOut = new DataOutputStream(exthBaos);
        int exthCount = 0;

        if (author != null && !author.isEmpty()) {
            byte[] authBytes = author.getBytes(StandardCharsets.UTF_8);
            exthOut.writeInt(100);
            exthOut.writeInt(8 + authBytes.length);
            exthOut.write(authBytes);
            exthCount++;
        }

        if (imageCount > 0) {
            exthOut.writeInt(201); // cover offset
            exthOut.writeInt(12);
            exthOut.writeInt(0); // first image is cover
            exthCount++;
        }

        byte[] exthRecords = exthBaos.toByteArray();
        rec0Out.write(new byte[]{'E', 'X', 'T', 'H'});
        rec0Out.writeInt(12 + exthRecords.length);
        rec0Out.writeInt(exthCount);
        rec0Out.write(exthRecords);

        int currentPosInRec0 = 16 + mobiHeaderLen + 12 + exthRecords.length;
        if (fullNameOffset > currentPosInRec0) {
            rec0Out.write(new byte[fullNameOffset - currentPosInRec0]);
        }
        rec0Out.write(fullTitleBytes);

        byte[] rec0Payload = rec0Baos.toByteArray();

        // Write record offsets table
        int currentOffset = rec0Offset;
        out.writeInt(currentOffset);
        out.writeInt(0); // rec 0
        currentOffset += rec0Payload.length;

        out.writeInt(currentOffset);
        out.writeInt(1); // rec 1 (text)
        currentOffset += textBytes.length;

        for (int i = 0; i < imageCount; i++) {
            out.writeInt(currentOffset);
            out.writeInt(2 + i);
            currentOffset += images[i].length;
        }

        out.writeInt(currentOffset);
        out.writeInt(numRecords - 1); // end record

        // Write payloads
        out.write(rec0Payload);
        out.write(textBytes);
        for (int i = 0; i < imageCount; i++) {
            out.write(images[i]);
        }
        out.write(new byte[]{0, 0, 0, 0}); // end record payload

        return baos.toByteArray();
    }

    private byte[] createMockJpeg() {
        // Standard JPEG SOI + APP0 + EOI
        return new byte[]{
                (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0,
                0x00, 0x10, 'J', 'F', 'I', 'F', 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
                (byte) 0xFF, (byte) 0xD9
        };
    }

    @Test
    public void testMobiTextNovelConversionToDerivedEpub() throws Exception {
        String novelHtml = "<h1>第一章 启程</h1><p>这是一个很长很长的小说正文段落，主角踏上了寻找传说的旅程。天空中飘荡着蓝白色的云朵，微风拂过脸庞，让人感到心旷神怡。前方的道路漫长而充满未知，但他未曾退缩。</p>"
                + "<mbp:pagebreak/>"
                + "<h1>第二章 冒险</h1><p>在森林深处，主角遇到了来自异世界的伙伴。他们携手同行，共同面对前方的艰难险阻。无数险象环生的关卡在他们面前一一被克服，友情的力量在磨砺中愈发坚定。</p>";

        byte[] mockCover = createMockJpeg();
        byte[] mobiData = createMockMobi("从零开始的异世界生活", "长月达平", novelHtml,
                new byte[][]{mockCover}, 0);

        File mobiFile = new File(tempDir, "rezero.mobi");
        Files.write(mobiFile.toPath(), mobiData);

        File derivedDir = new File(tempDir, "derived");
        KindlePublicationAdapter.ParseResult result = KindlePublicationAdapter.parse(mobiFile, "book_novel_1", derivedDir, null);

        assertNotNull(result);
        assertFalse(result.isComic);
        assertEquals("从零开始的异世界生活", result.title);
        assertEquals("长月达平", result.author);
        assertNotNull(result.derivedEpubFile);
        assertTrue(result.derivedEpubFile.exists());

        Publication pub = result.publication;
        assertNotNull(pub);
        assertEquals("从零开始的异世界生活", pub.title);
        assertEquals("长月达平", pub.author);
        assertTrue(pub.spine.size() >= 2);

        // Verify parse result
        try (ZipFile zip = new ZipFile(result.derivedEpubFile)) {
            ArchiveIndex.ParseResult parseRes = pub.toParseResult("book_novel_1", zip, null, null);
            assertNotNull(parseRes);
            assertEquals(2, parseRes.chapters.size());
            assertEquals("第一章 启程", parseRes.chapters.get(0).title);
            assertEquals("第二章 冒险", parseRes.chapters.get(1).title);
        }
    }

    @Test
    public void testMobiComicConversionToDerivedEpub() throws Exception {
        // Comic has 4 image pages and minimal text
        String comicHtml = "<img recindex=\"1\"/><mbp:pagebreak/><img recindex=\"2\"/><mbp:pagebreak/><img recindex=\"3\"/><mbp:pagebreak/><img recindex=\"4\"/>";

        byte[][] comicPages = new byte[][]{
                createMockJpeg(),
                createMockJpeg(),
                createMockJpeg(),
                createMockJpeg()
        };

        byte[] mobiData = createMockMobi("进击的巨人", "谏山创", comicHtml, comicPages, 0);
        File mobiFile = new File(tempDir, "titan.mobi");
        Files.write(mobiFile.toPath(), mobiData);

        File derivedDir = new File(tempDir, "derived");
        KindlePublicationAdapter.ParseResult result = KindlePublicationAdapter.parse(mobiFile, "book_comic_1", derivedDir, null);

        assertNotNull(result);
        assertTrue(result.isComic);
        assertEquals("进击的巨人", result.title);
        assertEquals("谏山创", result.author);
        assertNotNull(result.derivedEpubFile);
        assertTrue(result.derivedEpubFile.exists());

        Publication pub = result.publication;
        assertNotNull(pub);
        assertEquals(4, pub.spine.size());
    }

    @Test
    public void testUnsupportedDrmMobiThrowsClearError() throws Exception {
        byte[] drmMobi = createMockMobi("受加密保护的小说", "无名氏", "正文",
                new byte[][]{createMockJpeg()}, 2);
        File mobiFile = new File(tempDir, "locked.mobi");
        Files.write(mobiFile.toPath(), drmMobi);

        File derivedDir = new File(tempDir, "derived");
        try {
            KindlePublicationAdapter.parse(mobiFile, "book_locked", derivedDir, null);
            fail("Expected IOException for DRM book");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("DRM"));
        }
    }

    @Test
    public void testCancelImportDeletesDerivedEpub() throws Exception {
        byte[] mobiData = createMockMobi("测试小说", "作者", "正文内容",
                new byte[][]{createMockJpeg()}, 0);
        File mobiFile = new File(tempDir, "cancel.mobi");
        Files.write(mobiFile.toPath(), mobiData);

        File derivedDir = new File(tempDir, "derived");
        LocalModels.ImportProgressCallback cancelCb = new LocalModels.ImportProgressCallback() {
            @Override
            public void onProgress(long currentBytes, long totalBytes, String message) {}

            @Override
            public boolean isCancelled() {
                return true;
            }
        };

        try {
            KindlePublicationAdapter.parse(mobiFile, "book_cancel", derivedDir, cancelCb);
            fail("Expected InterruptedException");
        } catch (InterruptedException expected) {
            File targetEpub = new File(derivedDir, "book_cancel.epub");
            assertFalse(targetEpub.exists());
        }
    }
}
