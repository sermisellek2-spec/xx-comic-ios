package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Metadata-only scan: never opens EPUB body/cover entries or decodes Kindle content. */
public final class QuickPublicationInfo {
    private static final int MAX_XML_BYTES = 1024 * 1024;
    public final String title, seriesTitle, volumeNumber, coverEntry;
    /** EPUB only checks metadata readability; body integrity and DRM are checked when opening. */
    public final boolean isReadable;
    public final String unsupportedReason;

    private QuickPublicationInfo(String title, String seriesTitle, String volumeNumber,
                                 String coverEntry, boolean isReadable, String unsupportedReason) {
        this.title = title;
        this.seriesTitle = seriesTitle;
        this.volumeNumber = volumeNumber;
        this.coverEntry = coverEntry;
        this.isReadable = isReadable;
        this.unsupportedReason = unsupportedReason;
    }

    public static QuickPublicationInfo read(File file) throws IOException {
        return read(file, file == null ? "" : file.getName());
    }

    public static QuickPublicationInfo read(File file, String formatOrFileName) throws IOException {
        if (file == null || !file.isFile()) throw new IOException("电子书文件不存在");
        String format = formatOrFileName == null ? file.getName() : formatOrFileName;
        format = format.substring(format.lastIndexOf('.') + 1).toLowerCase(Locale.ROOT);
        if ("mobi".equals(format) || "azw".equals(format) || "azw3".equals(format) || "prc".equals(format)) {
            // This detector reads the record table, bounded headers and EXTH/title metadata only.
            KindleFormatDetector.DetectionResult result = KindleFormatDetector.detect(file);
            return new QuickPublicationInfo(result.title, "", "", "", result.isReadable, result.unsupportedReason);
        }
        if (!"epub".equals(format)) throw new IOException("不支持的电子书格式: " + format);
        try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(file)) {
            Document container = readXml(zip, "META-INF/container.xml");
            NodeList roots = container.getElementsByTagNameNS("*", "rootfile");
            String opf = "";
            for (int i = 0; i < roots.getLength(); i++) {
                Element root = (Element) roots.item(i);
                String path = root.getAttribute("full-path").trim();
                if (!path.isEmpty() && (opf.isEmpty()
                        || "application/oebps-package+xml".equals(root.getAttribute("media-type")))) opf = path;
            }
            opf = resolve("", opf);
            Document document = readXml(zip, opf);
            String title = "", series = "", volume = "", coverId = "", cover = "";
            NodeList metadata = document.getElementsByTagNameNS("*", "metadata");
            if (metadata.getLength() > 0) {
                Element meta = (Element) metadata.item(0);
                NodeList titles = meta.getElementsByTagNameNS("*", "title");
                if (titles.getLength() > 0) title = titles.item(0).getTextContent().trim();
                NodeList metas = meta.getElementsByTagNameNS("*", "meta");
                for (int i = 0; i < metas.getLength(); i++) {
                    Element item = (Element) metas.item(i);
                    String name = item.getAttribute("name");
                    if ("calibre:series".equals(name)) series = item.getAttribute("content").trim();
                    if ("calibre:series_index".equals(name)) volume = item.getAttribute("content").trim();
                    if ("cover".equals(name)) coverId = item.getAttribute("content");
                }
                if (series.isEmpty()) {
                    for (int i = 0; i < metas.getLength(); i++) {
                        Element collection = (Element) metas.item(i);
                        if (!"belongs-to-collection".equals(collection.getAttribute("property"))) continue;
                        String id = collection.getAttribute("id"), position = "", type = "";
                        if (id.isEmpty()) continue;
                        for (int j = 0; j < metas.getLength(); j++) {
                            Element refinement = (Element) metas.item(j);
                            if (!("#" + id).equals(refinement.getAttribute("refines"))) continue;
                            String property = refinement.getAttribute("property");
                            if ("collection-type".equals(property)) type = refinement.getTextContent().trim();
                            if ("group-position".equals(property)) position = refinement.getTextContent().trim();
                        }
                        if ("series".equals(type)) {
                            series = collection.getTextContent().trim();
                            volume = position;
                            break;
                        }
                    }
                }
            }
            NodeList items = document.getElementsByTagNameNS("*", "item");
            for (int i = 0; i < items.getLength(); i++) {
                Element item = (Element) items.item(i);
                boolean coverProperty = (" " + item.getAttribute("properties").trim().replaceAll("\\s+", " ") + " ")
                        .contains(" cover-image ");
                if (coverProperty || (!coverId.isEmpty() && coverId.equals(item.getAttribute("id")))) {
                    cover = resolve(opf.substring(0, opf.lastIndexOf('/') + 1), item.getAttribute("href"));
                    break;
                }
            }
            return new QuickPublicationInfo(title, series, volume, cover, true, null);
        }
    }

    private static String resolve(String base, String path) throws IOException {
        // URLDecoder's form semantics would otherwise turn literal '+' filenames into spaces.
        String decoded;
        try {
            decoded = URLDecoder.decode(path.replace("+", "%2B"), "UTF-8");
        } catch (IllegalArgumentException e) {
            throw new IOException("EPUB 元数据路径编码无效", e);
        }
        String resolved = EpubParser.resolvePath(base, decoded);
        if (resolved.isEmpty() || resolved.equals("..") || resolved.startsWith("../") || resolved.contains(":")) {
            throw new IOException("EPUB 元数据路径无效");
        }
        return resolved;
    }

    private static Document readXml(ZipFile zip, String path) throws IOException {
        ZipEntry entry = zip.getEntry(path);
        if (entry == null) throw new IOException("EPUB 缺少元数据: " + path);
        if (entry.getSize() > MAX_XML_BYTES) throw new IOException("EPUB 元数据过大");
        try (InputStream in = zip.getInputStream(entry)) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = in.read(buffer)) != -1) {
                if (bytes.size() + count > MAX_XML_BYTES) throw new IOException("EPUB 元数据过大");
                bytes.write(buffer, 0, count);
            }
            byte[] xml = bytes.toByteArray();
            // Reject before parsing, including UTF-16/32 declarations, without relying on
            // the disallow-doctype-decl feature absent from some Android XML factories.
            if (new String(xml, StandardCharsets.ISO_8859_1).replace("\u0000", "").contains("<!DOCTYPE")) {
                throw new IOException("EPUB 元数据禁止 DOCTYPE");
            }
            // Reuse the reader's Android-compatible external-entity protections.
            Document document = EpubParser.parseXmlSafely(new ByteArrayInputStream(xml));
            if (document.getDoctype() != null) throw new IOException("EPUB 元数据禁止 DOCTYPE");
            return document;
        } catch (Exception e) {
            if (e instanceof IOException) throw (IOException) e;
            throw new IOException("EPUB 元数据解析失败: " + path, e);
        }
    }
}
