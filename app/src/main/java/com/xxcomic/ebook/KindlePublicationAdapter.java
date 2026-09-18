package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;
import com.xxcomic.local.LocalModels;

import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class KindlePublicationAdapter {

    private KindlePublicationAdapter() {}

    public static class ImageEntry {
        public final int relativeIndex; // 1-based (recindex="1")
        public final byte[] data;
        public final String mimeType;
        public final String extension;

        public ImageEntry(int relativeIndex, byte[] data, String mimeType, String extension) {
            this.relativeIndex = relativeIndex;
            this.data = data;
            this.mimeType = mimeType;
            this.extension = extension;
        }
    }

    public static class ParseResult {
        public final Publication publication;
        public final File derivedEpubFile;
        public final byte[] coverBytes;
        public final String coverMimeType;
        public final boolean isComic;
        public final String title;
        public final String author;

        public ParseResult(Publication publication, File derivedEpubFile, byte[] coverBytes,
                           String coverMimeType, boolean isComic, String title, String author) {
            this.publication = publication;
            this.derivedEpubFile = derivedEpubFile;
            this.coverBytes = coverBytes;
            this.coverMimeType = coverMimeType;
            this.isComic = isComic;
            this.title = title;
            this.author = author;
        }
    }

    public static ParseResult parse(File sourceFile, String bookId, File derivedDir,
                                    LocalModels.ImportProgressCallback callback) throws Exception {
        if (sourceFile == null || !sourceFile.exists()) {
            throw new IOException("Kindle 电子书源文件不存在");
        }

        KindleFormatDetector.DetectionResult detection = KindleFormatDetector.detect(sourceFile);
        if (!detection.isReadable) {
            throw new IOException(detection.unsupportedReason != null ? detection.unsupportedReason : "该电子书不受支持");
        }

        if (callback != null && callback.isCancelled()) {
            throw new InterruptedException("用户取消导入");
        }

        if (derivedDir != null && !derivedDir.exists()) {
            derivedDir.mkdirs();
        }

        File targetEpub = new File(derivedDir, bookId + ".epub");
        File tempEpub = new File(derivedDir, bookId + ".epub.tmp");

        try {
            ParseResult result = convertToDerivedEpubInternal(sourceFile, detection, tempEpub, bookId, callback);
            if (targetEpub.exists()) targetEpub.delete();
            if (!tempEpub.renameTo(targetEpub)) {
                // If atomic rename fails, copy and delete
                copyFile(tempEpub, targetEpub);
                tempEpub.delete();
            }

            Publication pub = EpubParser.parse(targetEpub);
            return new ParseResult(pub, targetEpub, result.coverBytes, result.coverMimeType, result.isComic, result.title, result.author);
        } catch (Throwable t) {
            if (tempEpub.exists()) tempEpub.delete();
            if (targetEpub.exists()) targetEpub.delete();
            if (t instanceof InterruptedException) throw (InterruptedException) t;
            if (t instanceof IOException) throw (IOException) t;
            throw new IOException("Kindle 电子书解析失败: " + t.getMessage(), t);
        }
    }

    public static boolean convertMobiToDerivedEpub(File sourceFile, File targetEpub, String bookId) {
        try {
            KindleFormatDetector.DetectionResult detection = KindleFormatDetector.detect(sourceFile);
            if (!detection.isReadable) return false;
            File parent = targetEpub.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            File tempEpub = new File(parent, targetEpub.getName() + ".tmp");
            convertToDerivedEpubInternal(sourceFile, detection, tempEpub, bookId, null);
            if (targetEpub.exists()) targetEpub.delete();
            if (!tempEpub.renameTo(targetEpub)) {
                copyFile(tempEpub, targetEpub);
                tempEpub.delete();
            }
            return targetEpub.exists() && targetEpub.length() > 0;
        } catch (Exception e) {
            return false;
        }
    }

    private static ParseResult convertToDerivedEpubInternal(File sourceFile,
                                                            KindleFormatDetector.DetectionResult detection,
                                                            File destEpubFile,
                                                            String bookId,
                                                            LocalModels.ImportProgressCallback callback) throws Exception {
        long fileLength = sourceFile.length();
        try (RandomAccessFile raf = new RandomAccessFile(sourceFile, "r")) {
            byte[] pdbHeader = new byte[78];
            raf.readFully(pdbHeader);
            int numRecords = readUint16(pdbHeader, 76);
            if (numRecords <= 0) {
                throw new IOException("电子书记录表为空");
            }

            long[] recordOffsets = new long[numRecords];
            for (int i = 0; i < numRecords; i++) {
                recordOffsets[i] = raf.readInt() & 0xFFFFFFFFL;
                raf.skipBytes(4);
                if(recordOffsets[i]<78L+numRecords*8L || recordOffsets[i]>=fileLength || (i>0 && recordOffsets[i]<=recordOffsets[i-1]))
                    throw new IOException("电子书记录偏移无效");
            }

            // Record 0: PalmDOC + MOBI
            raf.seek(recordOffsets[0]);
            byte[] docHeader = new byte[16];
            raf.readFully(docHeader);
            int compression = readUint16(docHeader, 0);
            long declaredTextLength = readUint32(docHeader, 4);
            int textRecordCount = readUint16(docHeader, 8);
            int encryptionType = readUint16(docHeader, 12);
            if (encryptionType != 0) {
                throw new IOException("该电子书受 DRM 加密保护，暂不支持阅读");
            }

            if (compression != 1 && compression != 2) {
                throw new IOException("该电子书采用 Huff/CDIC 压缩算法，移动端暂不支持解压");
            }

            // Decompress text records
            ByteArrayOutputStream textBaos = new ByteArrayOutputStream();
            if(textRecordCount>numRecords-1)throw new IOException("电子书正文记录缺失");
            int maxTextRec = textRecordCount;
            if (detection.kf8BoundaryRecord > 0 && detection.kf8BoundaryRecord < maxTextRec) {
                // If combo, text is up to kf8 boundary
                maxTextRec = detection.kf8BoundaryRecord - 1;
            }

            for (int i = 1; i <= maxTextRec; i++) {
                if (callback != null && callback.isCancelled()) {
                    throw new InterruptedException("用户取消导入");
                }
                long start = recordOffsets[i];
                long end = (i + 1 < numRecords) ? recordOffsets[i + 1] : fileLength;
                if(end-start>8L*1024*1024)throw new IOException("电子书单条记录过大");
                int len = (int) (end - start);
                if (len <= 0) continue;

                int remainingText = declaredTextLength > 0 && declaredTextLength < Integer.MAX_VALUE
                        ? (int) Math.min(8L * 1024L * 1024L, declaredTextLength - textBaos.size())
                        : 8 * 1024 * 1024 - textBaos.size();
                if (remainingText <= 0) break;

                byte[] recData = new byte[len];
                raf.seek(start);
                raf.readFully(recData);

                if (compression == 2) {
                    byte[] decomp = decompressPalmDoc(recData, remainingText);
                    textBaos.write(decomp);
                } else {
                    textBaos.write(recData, 0, Math.min(recData.length, remainingText));
                }
                if(textBaos.size()>8*1024*1024)throw new IOException("电子书正文超出当前解析容量");
            }

            Charset textCharset = StandardCharsets.UTF_8;
            if ("Windows-1252".equalsIgnoreCase(detection.encoding)) {
                textCharset = Charset.forName("windows-1252");
            }

            String rawHtml = new String(textBaos.toByteArray(), textCharset);

            // Extract image records
            Map<Integer, ImageEntry> imageMap = new LinkedHashMap<>();
            int firstImg = detection.firstImageRecord;
            byte[] coverData = null;
            String coverMime = null;
            long imageBytes=0;

            if (firstImg > 0 && firstImg < numRecords) {
                for (int recIdx = firstImg; recIdx < numRecords; recIdx++) {
                    if (callback != null && callback.isCancelled()) {
                        throw new InterruptedException("用户取消导入");
                    }
                    long start = recordOffsets[recIdx];
                    long end = (recIdx + 1 < numRecords) ? recordOffsets[recIdx + 1] : fileLength;
                    imageBytes+=end-start;
                    if(end-start>8L*1024*1024 || imageBytes>32L*1024*1024)throw new IOException("电子书图片超出当前解析容量");
                    int len = (int) (end - start);
                    if (len < 4) continue;

                    byte[] imgBuf = new byte[len];
                    raf.seek(start);
                    raf.readFully(imgBuf);

                    String ext = detectImageExtension(imgBuf);
                    if (ext == null) {
                        // Not an image record (likely boundary or trailing control record)
                        continue;
                    }

                    String mime = "image/" + (ext.equals("jpg") ? "jpeg" : ext);
                    int relIdx = recIdx - firstImg + 1; // 1-based index
                    ImageEntry ie = new ImageEntry(relIdx, imgBuf, mime, ext);
                    imageMap.put(relIdx, ie);

                    if (recIdx == detection.coverRecordIndex) {
                        coverData = imgBuf;
                        coverMime = mime;
                    }
                }
            }

            if (coverData == null && !imageMap.isEmpty()) {
                ImageEntry first = imageMap.values().iterator().next();
                coverData = first.data;
                coverMime = first.mimeType;
            }

            // Determine whether Comic or Text Novel
            String textWithoutTags = rawHtml.replaceAll("<[^>]+>", " ").trim();
            boolean isComic = imageMap.size() >= 3 && textWithoutTags.length() < 300;

            String title = !detection.title.isEmpty() ? detection.title : "未命名电子书";
            String author = detection.author;

            // Build Derived EPUB
            buildDerivedEpub(destEpubFile, title, author, rawHtml, imageMap, isComic, coverData, coverMime, callback);

            return new ParseResult(null, destEpubFile, coverData, coverMime, isComic, title, author);
        }
    }

    public static byte[] decompressPalmDoc(byte[] input) {
        return decompressPalmDoc(input, 8 * 1024 * 1024);
    }

    static byte[] decompressPalmDoc(byte[] input, int maxOutputBytes) {
        if (input == null || input.length == 0) return new byte[0];
        if(input.length>8*1024*1024)throw new IllegalArgumentException("PalmDOC 记录过大");
        if (maxOutputBytes <= 0) return new byte[0];
        maxOutputBytes = Math.min(maxOutputBytes, 8 * 1024 * 1024);
        byte[] outBuf = new byte[Math.max(4096, input.length * 3)];
        int outPos = 0;
        int pos = 0;

        while (pos < input.length && outPos < maxOutputBytes) {
            if(outPos>8*1024*1024-10)throw new IllegalArgumentException("PalmDOC 解压数据过大");
            int b = input[pos++] & 0xFF;
            if (b == 0) {
                // Literal null byte
                if (outPos >= outBuf.length) outBuf = Arrays.copyOf(outBuf, outBuf.length * 2);
                outBuf[outPos++] = 0;
            } else if (b <= 8) {
                // Next b bytes are literals
                int count = b;
                if(pos+count>input.length)throw new IllegalArgumentException("PalmDOC 字面量记录截断");
                while (count > 0 && pos < input.length && outPos < maxOutputBytes) {
                    if (outPos >= outBuf.length) outBuf = Arrays.copyOf(outBuf, outBuf.length * 2);
                    outBuf[outPos++] = input[pos++];
                    count--;
                }
            } else if (b <= 0x7F) {
                // Single literal byte
                if (outPos >= outBuf.length) outBuf = Arrays.copyOf(outBuf, outBuf.length * 2);
                outBuf[outPos++] = (byte) b;
            } else if (b <= 0xBF) {
                // Distance/length pair
                if (pos >= input.length)throw new IllegalArgumentException("PalmDOC 回溯记录截断");
                int b2 = input[pos++] & 0xFF;
                int compound = ((b & 0x3F) << 8) | b2;
                int distance = compound >> 3;
                int length = (compound & 0x07) + 3;

                int copyStart = outPos - distance;
                if(distance==0 || copyStart<0)throw new IllegalArgumentException("PalmDOC 回溯距离无效");
                if (copyStart >= 0) {
                    int copyLength = Math.min(length, maxOutputBytes - outPos);
                    while (outPos + length > outBuf.length) {
                        outBuf = Arrays.copyOf(outBuf, outBuf.length * 2);
                    }
                    for (int i = 0; i < copyLength; i++) {
                        outBuf[outPos++] = outBuf[copyStart + i];
                    }
                }
            } else {
                // 0xC0 .. 0xFF: space + char
                if (outPos + 2 > outBuf.length) outBuf = Arrays.copyOf(outBuf, outBuf.length * 2);
                outBuf[outPos++] = ' ';
                outBuf[outPos++] = (byte) (b ^ 0x80);
            }
        }

        return Arrays.copyOf(outBuf, outPos);
    }

    private static long readUint32(byte[] b, int offset) {
        return ((long) (b[offset] & 0xFF) << 24)
                | ((long) (b[offset + 1] & 0xFF) << 16)
                | ((long) (b[offset + 2] & 0xFF) << 8)
                | (long) (b[offset + 3] & 0xFF);
    }

    private static String detectImageExtension(byte[] data) {
        if (data == null || data.length < 4) return null;
        if ((data[0] & 0xFF) == 0xFF && (data[1] & 0xFF) == 0xD8 && (data[2] & 0xFF) == 0xFF) {
            return "jpg";
        }
        if ((data[0] & 0xFF) == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G') {
            return "png";
        }
        if (data[0] == 'G' && data[1] == 'I' && data[2] == 'F' && data[3] == '8') {
            return "gif";
        }
        if (data.length >= 12 && data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F'
                && data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P') {
            return "webp";
        }
        if (data[0] == 'B' && data[1] == 'M') {
            return "bmp";
        }
        return null;
    }

    private static void buildDerivedEpub(File destFile, String title, String author, String rawHtml,
                                        Map<Integer, ImageEntry> imageMap, boolean isComic,
                                        byte[] coverData, String coverMime,
                                        LocalModels.ImportProgressCallback callback) throws Exception {
        if (destFile.getParentFile() != null && !destFile.getParentFile().exists()) {
            destFile.getParentFile().mkdirs();
        }

        try (FileOutputStream fos = new FileOutputStream(destFile);
             BufferedOutputStream bos = new BufferedOutputStream(fos);
             ZipOutputStream zos = new ZipOutputStream(bos)) {

            // 1. Write uncompressed mimetype
            byte[] mimeBytes = "application/epub+zip".getBytes(StandardCharsets.US_ASCII);
            ZipEntry mimeEntry = new ZipEntry("mimetype");
            mimeEntry.setMethod(ZipEntry.STORED);
            mimeEntry.setSize(mimeBytes.length);
            mimeEntry.setCrc(calculateCrc32(mimeBytes));
            zos.putNextEntry(mimeEntry);
            zos.write(mimeBytes);
            zos.closeEntry();

            // 2. Write META-INF/container.xml
            String containerXml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                    + "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n"
                    + "  <rootfiles>\n"
                    + "    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n"
                    + "  </rootfiles>\n"
                    + "</container>";
            writeZipEntry(zos, "META-INF/container.xml", containerXml.getBytes(StandardCharsets.UTF_8));

            // 3. Write Images
            for (ImageEntry ie : imageMap.values()) {
                String imgPath = "OEBPS/images/img_" + ie.relativeIndex + "." + ie.extension;
                writeZipEntry(zos, imgPath, ie.data);
            }

            // 4. Write Chapters / Pages
            List<String> pagePaths = new ArrayList<>();
            List<String> pageTitles = new ArrayList<>();

            if (isComic) {
                // Generate one XHTML page per image for PagedReader
                int pageNum = 1;
                for (ImageEntry ie : imageMap.values()) {
                    String pageFileName = String.format(Locale.US, "page_%04d.xhtml", pageNum);
                    String fullPath = "OEBPS/text/" + pageFileName;
                    String pageHtml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                            + "<!DOCTYPE html>\n"
                            + "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n"
                            + "<head><title>Page " + pageNum + "</title></head>\n"
                            + "<body style=\"margin:0;padding:0;text-align:center;background-color:#000;\">\n"
                            + "  <img src=\"../images/img_" + ie.relativeIndex + "." + ie.extension + "\" style=\"max-width:100%;max-height:100%;\" />\n"
                            + "</body>\n</html>";
                    writeZipEntry(zos, fullPath, pageHtml.getBytes(StandardCharsets.UTF_8));
                    pagePaths.add("text/" + pageFileName);
                    pageTitles.add("第 " + pageNum + " 页");
                    pageNum++;
                }
            } else {
                // Text novel: split chapters by <mbp:pagebreak> or <h2> / <h3> or chunking
                List<String> rawChapters = splitTextChapters(rawHtml);
                for (int ch = 0; ch < rawChapters.size(); ch++) {
                    String chFileName = String.format(Locale.US, "chapter_%04d.xhtml", ch + 1);
                    String fullPath = "OEBPS/text/" + chFileName;
                    String processedChapterHtml = processTextHtml(rawChapters.get(ch), imageMap);
                    String chTitle = extractChapterTitle(processedChapterHtml, ch + 1);
                    String chapterDoc = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                            + "<!DOCTYPE html>\n"
                            + "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n"
                            + "<head>\n"
                            + "  <title>" + escapeXml(chTitle) + "</title>\n"
                            + "  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"/>\n"
                            + "</head>\n"
                            + "<body>\n"
                            + "  <h2>" + escapeXml(chTitle) + "</h2>\n"
                            + processedChapterHtml + "\n"
                            + "</body>\n</html>";
                    writeZipEntry(zos, fullPath, chapterDoc.getBytes(StandardCharsets.UTF_8));
                    pagePaths.add("text/" + chFileName);
                    pageTitles.add(chTitle);
                }
            }

            if (pagePaths.isEmpty()) {
                // Fallback single page
                String pageHtml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                        + "<!DOCTYPE html>\n"
                        + "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>正文</title></head><body><p>正文内容</p></body></html>";
                writeZipEntry(zos, "OEBPS/text/page_0001.xhtml", pageHtml.getBytes(StandardCharsets.UTF_8));
                pagePaths.add("text/page_0001.xhtml");
                pageTitles.add("正文");
            }

            // 5. Write OEBPS/toc.ncx
            StringBuilder ncx = new StringBuilder();
            ncx.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
               .append("<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">\n")
               .append("  <head>\n    <meta name=\"dtb:uid\" content=\"urn:uuid:xxcomic-kindle-derived\"/>\n  </head>\n")
               .append("  <docTitle><text>").append(escapeXml(title)).append("</text></docTitle>\n")
               .append("  <navMap>\n");
            for (int i = 0; i < pagePaths.size(); i++) {
                ncx.append("    <navPoint id=\"navPoint-").append(i + 1).append("\" playOrder=\"").append(i + 1).append("\">\n")
                   .append("      <navLabel><text>").append(escapeXml(pageTitles.get(i))).append("</text></navLabel>\n")
                   .append("      <content src=\"").append(pagePaths.get(i)).append("\"/>\n")
                   .append("    </navPoint>\n");
            }
            ncx.append("  </navMap>\n</ncx>");
            writeZipEntry(zos, "OEBPS/toc.ncx", ncx.toString().getBytes(StandardCharsets.UTF_8));

            // 6. Write OEBPS/content.opf
            StringBuilder opf = new StringBuilder();
            opf.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
               .append("<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"BookId\" version=\"2.0\">\n")
               .append("  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n")
               .append("    <dc:title>").append(escapeXml(title)).append("</dc:title>\n")
               .append("    <dc:creator>").append(escapeXml(author)).append("</dc:creator>\n")
               .append("    <dc:identifier id=\"BookId\">urn:uuid:xxcomic-kindle-derived</dc:identifier>\n")
               .append("    <dc:language>zh</dc:language>\n");
            if (coverData != null && !imageMap.isEmpty()) {
                opf.append("    <meta name=\"cover\" content=\"cover-image\"/>\n");
            }
            opf.append("  </metadata>\n  <manifest>\n")
               .append("    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n");

            // Manifest images
            boolean coverAssigned = false;
            for (ImageEntry ie : imageMap.values()) {
                String imgId = "img_" + ie.relativeIndex;
                if (!coverAssigned && coverData != null && Arrays.equals(coverData, ie.data)) {
                    imgId = "cover-image";
                    coverAssigned = true;
                }
                opf.append("    <item id=\"").append(imgId).append("\" href=\"images/img_")
                   .append(ie.relativeIndex).append(".").append(ie.extension)
                   .append("\" media-type=\"").append(ie.mimeType).append("\"/>\n");
            }

            // Manifest text pages
            for (int i = 0; i < pagePaths.size(); i++) {
                opf.append("    <item id=\"page_").append(i + 1).append("\" href=\"")
                   .append(pagePaths.get(i)).append("\" media-type=\"application/xhtml+xml\"/>\n");
            }

            opf.append("  </manifest>\n  <spine toc=\"ncx\">\n");
            for (int i = 0; i < pagePaths.size(); i++) {
                opf.append("    <itemref idref=\"page_").append(i + 1).append("\"/>\n");
            }
            opf.append("  </spine>\n</package>");
            writeZipEntry(zos, "OEBPS/content.opf", opf.toString().getBytes(StandardCharsets.UTF_8));
        }
    }

    private static List<String> splitTextChapters(String rawHtml) {
        List<String> list = new ArrayList<>();
        if (rawHtml == null || rawHtml.isEmpty()) return list;

        String[] parts = rawHtml.split("(?i)<(?:mbp:pagebreak|pagebreak)[^>]*>");
        for (String part : parts) {
            String trimmed = part.trim();
            if (!trimmed.isEmpty()) {
                list.add(trimmed);
            }
        }

        if (list.isEmpty()) {
            list.add(rawHtml);
        }
        return list;
    }

    private static final Pattern RECINDEX_PATTERN = Pattern.compile("(?i)<(?:img|image)[^>]*recindex=[\"']?(\\d+)[\"']?[^>]*>", Pattern.CASE_INSENSITIVE);

    private static String processTextHtml(String chapterHtml, Map<Integer, ImageEntry> imageMap) {
        if (chapterHtml == null) return "";
        Matcher m = RECINDEX_PATTERN.matcher(chapterHtml);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            try {
                int recIdx = Integer.parseInt(m.group(1));
                ImageEntry ie = imageMap.get(recIdx);
                if (ie != null) {
                    m.appendReplacement(sb, "<p style=\"text-align:center;\"><img src=\"../images/img_" + ie.relativeIndex + "." + ie.extension + "\" style=\"max-width:100%;\" /></p>");
                } else {
                    m.appendReplacement(sb, "");
                }
            } catch (Exception e) {
                m.appendReplacement(sb, "");
            }
        }
        m.appendTail(sb);
        return sb.toString();
    }

    private static String extractChapterTitle(String chapterHtml, int fallbackIndex) {
        Pattern p = Pattern.compile("(?i)<(?:h1|h2|h3|h4)[^>]*>(.*?)</(?:h1|h2|h3|h4)>");
        Matcher m = p.matcher(chapterHtml);
        if (m.find()) {
            String t = m.group(1).replaceAll("<[^>]+>", "").trim();
            if (!t.isEmpty() && t.length() < 50) return t;
        }
        return "第 " + fallbackIndex + " 章";
    }

    private static String escapeXml(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&apos;");
    }

    private static void writeZipEntry(ZipOutputStream zos, String path, byte[] data) throws IOException {
        ZipEntry entry = new ZipEntry(path);
        zos.putNextEntry(entry);
        zos.write(data);
        zos.closeEntry();
    }

    private static long calculateCrc32(byte[] data) {
        CRC32 crc = new CRC32();
        crc.update(data);
        return crc.getValue();
    }

    private static int readUint16(byte[] b, int offset) {
        return ((b[offset] & 0xFF) << 8) | (b[offset + 1] & 0xFF);
    }

    private static void copyFile(File src, File dst) throws IOException {
        try (FileInputStream in = new FileInputStream(src);
             FileOutputStream out = new FileOutputStream(dst)) {
            byte[] buf = new byte[65536];
            int len;
            while ((len = in.read(buf)) > 0) {
                out.write(buf, 0, len);
            }
        }
    }
}
