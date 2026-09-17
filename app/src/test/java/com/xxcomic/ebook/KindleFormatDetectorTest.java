package com.xxcomic.ebook;

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
import java.util.Arrays;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class KindleFormatDetectorTest {

    private File tempDir;

    @Before
    public void setUp() throws IOException {
        tempDir = Files.createTempDirectory("kindle_detector_test").toFile();
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

    private byte[] createPdbMobiFile(String title, String author, int version, int encryptionType,
                                     boolean addExthBoundary, boolean isDrmServer) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(baos);

        // PDB Header (78 bytes)
        byte[] nameBytes = new byte[32];
        byte[] titleRaw = "KindleTestBook".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(titleRaw, 0, nameBytes, 0, Math.min(31, titleRaw.length));
        out.write(nameBytes); // 0..31
        out.writeShort(0); // 32..33 attr
        out.writeShort(0); // 34..35 ver
        out.writeInt(12345); // 36..39 creation
        out.writeInt(12345); // 40..43 mod
        out.writeInt(0); // 44..47 backup
        out.writeInt(0); // 48..51 mod num
        out.writeInt(0); // 52..55 app info
        out.writeInt(0); // 56..59 sort info
        out.write(new byte[]{'B', 'O', 'O', 'K'}); // 60..63 type
        out.write(new byte[]{'M', 'O', 'B', 'I'}); // 64..67 creator
        out.writeInt(0); // 68..71 unique seed
        out.writeInt(0); // 72..75 next record list
        int numRecords = addExthBoundary ? 6 : 4;
        out.writeShort(numRecords); // 76..77 numRecords

        // Record Table: numRecords * 8 bytes
        // Calculate offsets
        int recordTableSize = numRecords * 8;
        int rec0Offset = 78 + recordTableSize;

        // Construct Record 0 payload in memory first to know size
        ByteArrayOutputStream rec0Baos = new ByteArrayOutputStream();
        DataOutputStream rec0Out = new DataOutputStream(rec0Baos);

        // PalmDOC header (16 bytes)
        rec0Out.writeShort(2); // compression = PalmDOC LZ77
        rec0Out.writeShort(0); // unused
        rec0Out.writeInt(2048); // text length
        rec0Out.writeShort(1); // text record count
        rec0Out.writeShort(4096); // record size
        rec0Out.writeShort(encryptionType); // encryption type (0 = none, 2 = DRM)
        rec0Out.writeShort(0); // unknown

        // MOBI Header (starts at byte 16 of record 0)
        rec0Out.write(new byte[]{'M', 'O', 'B', 'I'}); // 0..3 (relative to MOBI header)
        int mobiHeaderLen = 232;
        rec0Out.writeInt(mobiHeaderLen); // 4..7
        rec0Out.writeInt(2); // 8..11 mobiType = book
        rec0Out.writeInt(65001); // 12..15 encoding = UTF-8
        rec0Out.writeInt(999); // 16..19 unique id
        rec0Out.writeInt(version); // 20..23 mobi version (e.g. 6 or 8)

        // Pad to offset 68 (fullNameOffset)
        // Written so far: 24 bytes -> pad 68 - 24 = 44 bytes
        rec0Out.write(new byte[68 - 24]);

        byte[] fullTitleBytes = title.getBytes(StandardCharsets.UTF_8);
        int fullNameOffset = 16 + mobiHeaderLen + 200; // offset from start of Record 0
        rec0Out.writeInt(fullNameOffset); // 68..71
        rec0Out.writeInt(fullTitleBytes.length); // 72..75
        rec0Out.writeInt(1033); // 76..79 locale
        rec0Out.writeInt(0); // 80..83 input lang
        rec0Out.writeInt(0); // 84..87 output lang
        rec0Out.writeInt(version); // 88..91 min version
        rec0Out.writeInt(2); // 92..95 firstImageRecord = index 2

        // Pad to offset 128 (EXTH flags): 128 - 96 = 32 bytes
        rec0Out.write(new byte[128 - 96]);
        rec0Out.writeInt(0x40); // 128..131: bit 6 = EXTH exists

        // Pad to offset 168 (DRM fields): 168 - 132 = 36 bytes
        rec0Out.write(new byte[168 - 132]);
        rec0Out.writeInt(isDrmServer ? 1001 : 0); // 168..171: DRM Server ID
        rec0Out.writeInt(isDrmServer ? 1 : 0); // 172..175: DRM Count
        rec0Out.writeInt(0); // 176..179: DRM Size
        rec0Out.writeInt(isDrmServer ? 1 : 0); // 180..183: DRM Flags

        // Pad remainder of MOBI header (232 - 184 = 48 bytes)
        int writtenInMobi = 184;
        if (mobiHeaderLen > writtenInMobi) {
            rec0Out.write(new byte[mobiHeaderLen - writtenInMobi]);
        }

        // EXTH Header
        ByteArrayOutputStream exthBaos = new ByteArrayOutputStream();
        DataOutputStream exthOut = new DataOutputStream(exthBaos);
        int exthCount = 0;

        if (author != null && !author.isEmpty()) {
            byte[] authBytes = author.getBytes(StandardCharsets.UTF_8);
            exthOut.writeInt(100); // author
            exthOut.writeInt(8 + authBytes.length);
            exthOut.write(authBytes);
            exthCount++;
        }

        // Cover offset record
        exthOut.writeInt(201);
        exthOut.writeInt(12);
        exthOut.writeInt(0); // cover is firstImageRecord + 0
        exthCount++;

        if (addExthBoundary) {
            exthOut.writeInt(121); // KF8 boundary record
            exthOut.writeInt(12);
            exthOut.writeInt(3); // boundary at record index 3
            exthCount++;
        }

        byte[] exthRecords = exthBaos.toByteArray();
        rec0Out.write(new byte[]{'E', 'X', 'T', 'H'});
        rec0Out.writeInt(12 + exthRecords.length);
        rec0Out.writeInt(exthCount);
        rec0Out.write(exthRecords);

        // Add padding until fullNameOffset
        int currentPosInRec0 = 16 + mobiHeaderLen + 12 + exthRecords.length;
        if (fullNameOffset > currentPosInRec0) {
            rec0Out.write(new byte[fullNameOffset - currentPosInRec0]);
        }
        rec0Out.write(fullTitleBytes);

        byte[] rec0Payload = rec0Baos.toByteArray();

        // Write Record Info Table
        // Record 0
        out.writeInt(rec0Offset);
        out.writeInt(0); // attr + uid

        // Record 1 (text)
        int rec1Offset = rec0Offset + rec0Payload.length;
        out.writeInt(rec1Offset);
        out.writeInt(1);

        // Record 2 (image)
        byte[] textPayload = "Hello MOBI World".getBytes(StandardCharsets.UTF_8);
        int rec2Offset = rec1Offset + textPayload.length;
        out.writeInt(rec2Offset);
        out.writeInt(2);

        // Record 3 (end or boundary)
        byte[] imgPayload = new byte[]{1, 2, 3};
        int rec3Offset = rec2Offset + imgPayload.length;
        out.writeInt(rec3Offset);
        out.writeInt(3);

        if (addExthBoundary) {
            int rec4Offset = rec3Offset + 10;
            out.writeInt(rec4Offset);
            out.writeInt(4);

            int rec5Offset = rec4Offset + 10;
            out.writeInt(rec5Offset);
            out.writeInt(5);
        }

        // Write payloads
        out.write(rec0Payload);
        out.write(textPayload);
        out.write(imgPayload);
        out.write(new byte[addExthBoundary ? 30 : 10]);

        return baos.toByteArray();
    }

    @Test
    public void testDetectMobi7Standard() throws Exception {
        byte[] mobiData = createPdbMobiFile("我的经典小说", "测试作者", 6, 0, false, false);
        File file = new File(tempDir, "classic.mobi");
        Files.write(file.toPath(), mobiData);

        KindleFormatDetector.DetectionResult res = KindleFormatDetector.detect(file);
        assertEquals(KindleFormatDetector.Variant.MOBI7, res.variant);
        assertEquals(KindleFormatDetector.DrmType.NONE, res.drmType);
        assertTrue(res.isReadable);
        assertEquals("我的经典小说", res.title);
        assertEquals("测试作者", res.author);
        assertEquals("UTF-8", res.encoding);
        assertEquals(2, res.firstImageRecord);
        assertEquals(2, res.coverRecordIndex);
    }

    @Test
    public void testDetectKf8Azw3() throws Exception {
        byte[] kf8Data = createPdbMobiFile("现代Kindle书", "亚马逊作者", 8, 0, false, false);
        File file = new File(tempDir, "modern.azw3");
        Files.write(file.toPath(), kf8Data);

        KindleFormatDetector.DetectionResult res = KindleFormatDetector.detect(file);
        assertEquals(KindleFormatDetector.Variant.KF8, res.variant);
        assertEquals(KindleFormatDetector.DrmType.NONE, res.drmType);
        assertFalse(res.isReadable);
        assertTrue(res.unsupportedReason.contains("KF8"));
        assertEquals("现代Kindle书", res.title);
        assertEquals("亚马逊作者", res.author);
    }

    @Test
    public void testDetectComboJointMobi() throws Exception {
        byte[] comboData = createPdbMobiFile("双格式合体书", "大师", 6, 0, true, false);
        File file = new File(tempDir, "combo.mobi");
        Files.write(file.toPath(), comboData);

        KindleFormatDetector.DetectionResult res = KindleFormatDetector.detect(file);
        assertEquals(KindleFormatDetector.Variant.COMBO, res.variant);
        assertEquals(KindleFormatDetector.DrmType.NONE, res.drmType);
        assertTrue(res.isReadable);
        assertEquals(3, res.kf8BoundaryRecord);
        assertEquals("双格式合体书", res.title);
    }

    @Test
    public void testDetectDrmProtectedMobi() throws Exception {
        byte[] drmData = createPdbMobiFile("受保护图书", "神秘人", 6, 2, false, true);
        File file = new File(tempDir, "encrypted.mobi");
        Files.write(file.toPath(), drmData);

        KindleFormatDetector.DetectionResult res = KindleFormatDetector.detect(file);
        assertFalse(res.isReadable);
        assertEquals(KindleFormatDetector.DrmType.AMAZON_DRM, res.drmType);
        assertNotNull(res.unsupportedReason);
        assertTrue(res.unsupportedReason.contains("DRM"));
    }

    @Test
    public void testDetectKfxContainer() throws Exception {
        byte[] kfxBytes = new byte[]{(byte) 0xEA, 'K', 'F', 'X', 0x01, 0x00, 0x00, 0x00, 0x12, 0x34};
        File file = new File(tempDir, "book.kfx");
        Files.write(file.toPath(), kfxBytes);

        KindleFormatDetector.DetectionResult res = KindleFormatDetector.detect(file);
        assertEquals(KindleFormatDetector.Variant.KFX, res.variant);
        assertFalse(res.isReadable);
        assertEquals(KindleFormatDetector.DrmType.KFX_DRM, res.drmType);
        assertTrue(res.unsupportedReason.contains("KFX"));
    }

    @Test
    public void testDetectTopazContainer() throws Exception {
        byte[] tpzBytes = new byte[]{'T', 'P', 'Z', 0x01, 0x00, 0x00, 0x00, 0x00, 0x55, 0x66};
        File file = new File(tempDir, "book.tpz");
        Files.write(file.toPath(), tpzBytes);

        KindleFormatDetector.DetectionResult res = KindleFormatDetector.detect(file);
        assertEquals(KindleFormatDetector.Variant.TOPAZ, res.variant);
        assertFalse(res.isReadable);
        assertTrue(res.unsupportedReason.contains("Topaz"));
    }

    @Test
    public void testExtensionSpoofingDoesNotFoolDetector() throws Exception {
        // A KFX file renamed to .mobi
        byte[] kfxBytes = new byte[]{(byte) 0xEA, 'K', 'F', 'X', 0x01, 0x00, 0x00, 0x00, 0x12, 0x34};
        File fakeMobi = new File(tempDir, "fake_kfx.mobi");
        Files.write(fakeMobi.toPath(), kfxBytes);

        KindleFormatDetector.DetectionResult res1 = KindleFormatDetector.detect(fakeMobi);
        assertEquals(KindleFormatDetector.Variant.KFX, res1.variant);
        assertFalse(res1.isReadable);

        // A valid MOBI file renamed to .png or .txt
        byte[] mobiData = createPdbMobiFile("真真假假", "作者", 6, 0, false, false);
        File fakePng = new File(tempDir, "real_mobi.png");
        Files.write(fakePng.toPath(), mobiData);

        KindleFormatDetector.DetectionResult res2 = KindleFormatDetector.detect(fakePng);
        assertEquals(KindleFormatDetector.Variant.MOBI7, res2.variant);
        assertTrue(res2.isReadable);
        assertEquals("真真假假", res2.title);
    }

    @Test
    public void testTruncatedAndCorruptFiles() throws Exception {
        File emptyFile = new File(tempDir, "empty.mobi");
        Files.write(emptyFile.toPath(), new byte[0]);
        KindleFormatDetector.DetectionResult r1 = KindleFormatDetector.detect(emptyFile);
        assertEquals(KindleFormatDetector.Variant.CORRUPT, r1.variant);
        assertFalse(r1.isReadable);

        File tinyFile = new File(tempDir, "tiny.mobi");
        Files.write(tinyFile.toPath(), new byte[]{1, 2, 3});
        KindleFormatDetector.DetectionResult r2 = KindleFormatDetector.detect(tinyFile);
        assertEquals(KindleFormatDetector.Variant.CORRUPT, r2.variant);
        assertFalse(r2.isReadable);

        File truncatedPdb = new File(tempDir, "trunc.mobi");
        Files.write(truncatedPdb.toPath(), new byte[50]);
        KindleFormatDetector.DetectionResult r3 = KindleFormatDetector.detect(truncatedPdb);
        assertEquals(KindleFormatDetector.Variant.CORRUPT, r3.variant);
        assertFalse(r3.isReadable);
    }
}
