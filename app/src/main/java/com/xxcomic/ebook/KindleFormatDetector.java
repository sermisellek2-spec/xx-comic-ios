package com.xxcomic.ebook;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public final class KindleFormatDetector {

    public enum Variant {
        MOBI7,
        KF8,
        COMBO,
        PALMDOC,
        KFX,
        TOPAZ,
        UNKNOWN,
        CORRUPT
    }

    public enum DrmType {
        NONE,
        MOBIPOCKET_DRM,
        AMAZON_DRM,
        KFX_DRM
    }

    public static final class DetectionResult {
        public final Variant variant;
        public final DrmType drmType;
        public final boolean isReadable;
        public final String unsupportedReason;
        public final String title;
        public final String author;
        public final int compression;
        public final String encoding;
        public final int recordCount;
        public final int firstImageRecord;
        public final int coverRecordIndex;
        public final int kf8BoundaryRecord;

        public DetectionResult(Variant variant, DrmType drmType, boolean isReadable,
                               String unsupportedReason, String title, String author,
                               int compression, String encoding, int recordCount,
                               int firstImageRecord, int coverRecordIndex, int kf8BoundaryRecord) {
            this.variant = variant;
            this.drmType = drmType;
            this.isReadable = isReadable;
            this.unsupportedReason = unsupportedReason;
            this.title = title != null ? title : "";
            this.author = author != null ? author : "";
            this.compression = compression;
            this.encoding = encoding != null ? encoding : "UTF-8";
            this.recordCount = recordCount;
            this.firstImageRecord = firstImageRecord;
            this.coverRecordIndex = coverRecordIndex;
            this.kf8BoundaryRecord = kf8BoundaryRecord;
        }

        public static DetectionResult unsupported(Variant variant, DrmType drmType, String reason) {
            return new DetectionResult(variant, drmType, false, reason, "", "", 0, "UTF-8", 0, -1, -1, -1);
        }
    }

    private static final byte[] MAGIC_KFX_1 = new byte[]{(byte) 0xEA, 'K', 'F', 'X'};
    private static final byte[] MAGIC_TOPAZ = new byte[]{'T', 'P', 'Z'};
    private static final byte[] MAGIC_AZW1 = new byte[]{'a', 'z', 'w', '1'};
    private static final byte[] TYPE_BOOK = new byte[]{'B', 'O', 'O', 'K'};
    private static final byte[] TYPE_TEXT = new byte[]{'T', 'E', 'X', 't'};
    private static final byte[] CREATOR_MOBI = new byte[]{'M', 'O', 'B', 'I'};
    private static final byte[] MAGIC_MOBI = new byte[]{'M', 'O', 'B', 'I'};
    private static final byte[] MAGIC_EXTH = new byte[]{'E', 'X', 'T', 'H'};

    private KindleFormatDetector() {}

    public static DetectionResult detect(File file) {
        if (file == null || !file.exists() || !file.isFile()) {
            return DetectionResult.unsupported(Variant.UNKNOWN, DrmType.NONE, "文件不存在或不可读取");
        }

        long length = file.length();
        if (length < 8) {
            return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "文件截断：大小过小");
        }

        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            byte[] headerMagic = new byte[8];
            raf.readFully(headerMagic);

            // 1. Detect Amazon KFX container
            if (matches(headerMagic, 0, MAGIC_KFX_1)) {
                return DetectionResult.unsupported(Variant.KFX, DrmType.KFX_DRM,
                        "文件为 Amazon KFX 专有受保护格式，目前移动端不支持直接解析");
            }

            // 2. Detect Amazon Topaz container
            if (matches(headerMagic, 0, MAGIC_TOPAZ) || matches(headerMagic, 0, MAGIC_AZW1)) {
                return DetectionResult.unsupported(Variant.TOPAZ, DrmType.AMAZON_DRM,
                        "文件为 Amazon Topaz (AZW1/TPZ) 矢量格式，暂不支持");
            }

            // 3. Detect PDB Container
            if (length < 78) {
                return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "PDB 文件头不完整");
            }

            // Read PDB Header (78 bytes)
            byte[] pdbHeader = new byte[78];
            System.arraycopy(headerMagic, 0, pdbHeader, 0, 8);
            raf.readFully(pdbHeader, 8, 70);

            String pdbName = extractPdbName(pdbHeader);
            byte[] type = Arrays.copyOfRange(pdbHeader, 60, 64);
            byte[] creator = Arrays.copyOfRange(pdbHeader, 64, 68);
            int numRecords = readUint16(pdbHeader, 76);

            boolean isBookOrText = matches(type, 0, TYPE_BOOK) || matches(type, 0, TYPE_TEXT);
            boolean isMobiCreator = matches(creator, 0, CREATOR_MOBI);

            if (!isBookOrText && !isMobiCreator) {
                // Not standard PDB MOBI/BOOK
                return DetectionResult.unsupported(Variant.UNKNOWN, DrmType.NONE, "不是支持的 Kindle / PalmDOC 电子书容器");
            }

            if (numRecords <= 0) {
                return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "PDB 记录表为空");
            }

            // Read record offset table
            long recordTableSize = (long) numRecords * 8L;
            if (78 + recordTableSize > length) {
                return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "PDB 记录表超出文件范围");
            }

            long[] recordOffsets = new long[numRecords];
            for (int i = 0; i < numRecords; i++) {
                recordOffsets[i] = raf.readInt() & 0xFFFFFFFFL;
                raf.skipBytes(4); // skip attribute (1) + uniqueId (3)
                if(recordOffsets[i]<78+recordTableSize || recordOffsets[i]>=length || (i>0 && recordOffsets[i]<=recordOffsets[i-1]))
                    return DetectionResult.unsupported(Variant.CORRUPT,DrmType.NONE,"电子书记录偏移无效");
            }

            long record0Offset = recordOffsets[0];
            if (record0Offset >= length) {
                return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "Record 0 偏移超出文件大小");
            }

            long record0Length = (numRecords > 1 ? recordOffsets[1] : length) - record0Offset;
            if (record0Length < 16) {
                return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "PalmDOC 头部不完整");
            }

            // Read PalmDOC Header (16 bytes)
            raf.seek(record0Offset);
            byte[] docHeader = new byte[16];
            raf.readFully(docHeader);

            int compression = readUint16(docHeader, 0);
            int encryptionType = readUint16(docHeader, 12);
            if(compression!=1 && compression!=2)
                return DetectionResult.unsupported(Variant.UNKNOWN,DrmType.NONE,"暂不支持此电子书压缩方式（包括 HUFF/CDIC）");

            // Check MOBI Header
            if (record0Length < 16 + 8) {
                // Pure PalmDOC without MOBI header
                DrmType drm = (encryptionType != 0) ? DrmType.MOBIPOCKET_DRM : DrmType.NONE;
                boolean readable = (encryptionType == 0);
                String reason = readable ? null : "PalmDOC 文件已被加密保护";
                return new DetectionResult(Variant.PALMDOC, drm, readable, reason, pdbName, "",
                        compression, "Windows-1252", numRecords, -1, -1, -1);
            }

            byte[] mobiMagic = new byte[4];
            raf.readFully(mobiMagic);
            if (!matches(mobiMagic, 0, MAGIC_MOBI)) {
                // Not MOBI, fallback PalmDOC
                DrmType drm = (encryptionType != 0) ? DrmType.MOBIPOCKET_DRM : DrmType.NONE;
                boolean readable = (encryptionType == 0);
                String reason = readable ? null : "PalmDOC 文件已被加密保护";
                return new DetectionResult(Variant.PALMDOC, drm, readable, reason, pdbName, "",
                        compression, "Windows-1252", numRecords, -1, -1, -1);
            }

            int mobiHeaderLength = raf.readInt();
            if (mobiHeaderLength < 16 || mobiHeaderLength>65536 || 16L + mobiHeaderLength > record0Length) {
                return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "MOBI 头部长度异常");
            }

            byte[] mobiRest = new byte[mobiHeaderLength - 8];
            raf.readFully(mobiRest);

            int mobiType = (mobiRest.length >= 4) ? readUint32(mobiRest, 0) : 0;
            int encodingCode = (mobiRest.length >= 8) ? readUint32(mobiRest, 4) : 1252;
            String encoding = (encodingCode == 65001) ? "UTF-8" : "Windows-1252";
            int mobiVersion = (mobiRest.length >= 16) ? readUint32(mobiRest, 12) : 4;

            // Header offset 68 -> mobiRest offset 60
            int fullNameOffset = (mobiRest.length >= 64) ? readUint32(mobiRest, 60) : -1;
            // Header offset 72 -> mobiRest offset 64
            int fullNameLength = (mobiRest.length >= 68) ? readUint32(mobiRest, 64) : 0;
            // Header offset 92 -> mobiRest offset 84
            int firstImageRecord = (mobiRest.length >= 88) ? readUint32(mobiRest, 84) : -1;

            // EXTH flags: offset 128 -> mobiRest offset 120 (or legacy offset 112 -> 104)
            int exthFlags = 0;
            if (mobiRest.length >= 124) {
                exthFlags = readUint32(mobiRest, 120);
            } else if (mobiRest.length >= 108) {
                exthFlags = readUint32(mobiRest, 104);
            }

            int drmCount = (mobiRest.length >= 168) ? readUint32(mobiRest, 164) : 0;
            int drmFlags = (mobiRest.length >= 176) ? readUint32(mobiRest, 172) : 0;

            DrmType drm = DrmType.NONE;
            if (encryptionType == 1) {
                drm = DrmType.MOBIPOCKET_DRM;
            } else if (encryptionType != 0 || drmCount != 0 || drmFlags != 0) {
                drm = DrmType.AMAZON_DRM;
            }

            // Extract Title from Record 0 if available
            String title = pdbName;
            if (fullNameOffset > 0 && fullNameLength > 0 && fullNameLength<=65536) {
                long nameFilePos = record0Offset + fullNameOffset;
                if (nameFilePos + fullNameLength <= length) {
                    raf.seek(nameFilePos);
                    byte[] nameBuf = new byte[fullNameLength];
                    raf.readFully(nameBuf);
                    String parsedTitle = new String(nameBuf, encodingCode == 65001 ? StandardCharsets.UTF_8 : StandardCharsets.ISO_8859_1).trim();
                    if (!parsedTitle.isEmpty()) {
                        title = parsedTitle;
                    }
                }
                // Fallback if fullNameOffset was relative to mobiHeader start
                if (title.isEmpty() || title.equals(pdbName)) {
                    long altPos = record0Offset + 16 + fullNameOffset;
                    if (altPos + fullNameLength <= length) {
                        raf.seek(altPos);
                        byte[] nameBuf = new byte[fullNameLength];
                        raf.readFully(nameBuf);
                        String parsedTitle = new String(nameBuf, encodingCode == 65001 ? StandardCharsets.UTF_8 : StandardCharsets.ISO_8859_1).trim();
                        if (!parsedTitle.isEmpty()) {
                            title = parsedTitle;
                        }
                    }
                }
            }

            // Parse EXTH Header if present
            String author = "";
            int coverOffset = -1;
            int kf8Boundary = -1;

            long exthOffset = record0Offset + 16 + mobiHeaderLength;
            boolean hasExth = (exthFlags & 0x40) != 0;
            if (!hasExth && exthOffset + 4 <= length) {
                raf.seek(exthOffset);
                byte[] testMagic = new byte[4];
                raf.readFully(testMagic);
                if (matches(testMagic, 0, MAGIC_EXTH)) {
                    hasExth = true;
                }
            }

            if (hasExth) {
                if (exthOffset + 12 <= record0Offset + record0Length) {
                    raf.seek(exthOffset);
                    byte[] exthHead = new byte[12];
                    raf.readFully(exthHead);
                    if (matches(exthHead, 0, MAGIC_EXTH)) {
                        int exthLen = readUint32(exthHead, 4);
                        int exthCount = readUint32(exthHead, 8);
                        long curPos = exthOffset + 12;
                        long endExth = exthOffset + exthLen;
                        if(exthLen<12 || endExth>record0Offset+record0Length)
                            return DetectionResult.unsupported(Variant.CORRUPT,DrmType.NONE,"电子书元数据越界");

                        for (int i = 0; i < exthCount && curPos + 8 <= endExth && curPos + 8 <= length; i++) {
                            raf.seek(curPos);
                            int recType = raf.readInt();
                            int recLen = raf.readInt();
                            if (recLen < 8 || recLen>65536 || curPos + recLen > endExth) break;

                            int dataLen = recLen - 8;
                            if (dataLen > 0) {
                                byte[] data = new byte[dataLen];
                                raf.readFully(data);

                                if (recType == 100) { // Author
                                    author = new String(data, StandardCharsets.UTF_8).trim();
                                } else if (recType == 121) { // KF8 Boundary record
                                    if (dataLen >= 4) {
                                        kf8Boundary = readUint32(data, 0);
                                    }
                                } else if (recType == 201) { // Cover offset
                                    if (dataLen >= 4) {
                                        coverOffset = readUint32(data, 0);
                                    }
                                }
                            }
                            curPos += recLen;
                        }
                    }
                }
            }

            // Determine Variant
            Variant variant;
            if (kf8Boundary > 0 && kf8Boundary < numRecords) {
                variant = Variant.COMBO;
            } else if (mobiVersion >= 8 || mobiType == 248) {
                variant = Variant.KF8;
            } else {
                variant = Variant.MOBI7;
            }

            int coverRecordIndex = -1;
            if (firstImageRecord > 0 && coverOffset >= 0) {
                coverRecordIndex = firstImageRecord + coverOffset;
                if (coverRecordIndex >= numRecords) {
                    coverRecordIndex = -1;
                }
            }

            boolean isReadable = (drm == DrmType.NONE);
            String unsupportedReason = null;
            if (!isReadable) {
                unsupportedReason = "该电子书受 DRM 密码保护，暂无法直接在手机上阅读";
            } else if(variant==Variant.KF8) {
                isReadable=false;
                unsupportedReason="暂不支持 KF8/AZW3 正文重建，请先在本地转换为 EPUB";
            }

            return new DetectionResult(variant, drm, isReadable, unsupportedReason, title, author,
                    compression, encoding, numRecords, firstImageRecord, coverRecordIndex, kf8Boundary);

        } catch (Exception e) {
            return DetectionResult.unsupported(Variant.CORRUPT, DrmType.NONE, "解析文件头部异常: " + e.getMessage());
        }
    }

    private static String extractPdbName(byte[] header) {
        int len = 0;
        while (len < 32 && header[len] != 0) {
            len++;
        }
        return new String(header, 0, len, StandardCharsets.ISO_8859_1).trim();
    }

    private static boolean matches(byte[] data, int offset, byte[] target) {
        if (data == null || target == null || offset + target.length > data.length) return false;
        for (int i = 0; i < target.length; i++) {
            if (data[offset + i] != target[i]) return false;
        }
        return true;
    }

    private static int readUint16(byte[] b, int offset) {
        return ((b[offset] & 0xFF) << 8) | (b[offset + 1] & 0xFF);
    }

    private static int readUint32(byte[] b, int offset) {
        return ((b[offset] & 0xFF) << 24) |
                ((b[offset + 1] & 0xFF) << 16) |
                ((b[offset + 2] & 0xFF) << 8) |
                (b[offset + 3] & 0xFF);
    }
}
