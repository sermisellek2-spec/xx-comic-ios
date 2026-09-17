package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

import java.io.BufferedInputStream;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.StringReader;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

public final class EpubParser {
    private static final int MAX_XHTML_INSPECT_BYTES = 1024 * 1024; // 1 MiB
    private static final Pattern IMG_SRC_PATTERN = Pattern.compile("<img[^>]+src\\s*=\\s*['\"]([^'\"]+)['\"]", Pattern.CASE_INSENSITIVE);
    private static final Pattern SVG_IMAGE_PATTERN = Pattern.compile("<image[^>]+(?:xlink:href|href)\\s*=\\s*['\"]([^'\"]+)['\"]", Pattern.CASE_INSENSITIVE);

    public static Publication parse(File file) throws IOException {
        ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(file);
        try {
            return parse(zip);
        } finally {
            try { zip.close(); } catch (IOException ignored) {}
        }
    }

    public static Publication parse(ZipFile zip) throws IOException {
        // Step 1: Read META-INF/container.xml
        ZipEntry containerEntry = zip.getEntry("META-INF/container.xml");
        if (containerEntry == null) {
            throw new IOException("无效的 EPUB: 缺少 META-INF/container.xml");
        }

        String opfPath;
        try (InputStream in = zip.getInputStream(containerEntry)) {
            Document doc = parseXmlSafely(in);
            NodeList rootfiles = doc.getElementsByTagName("rootfile");
            if (rootfiles.getLength() == 0) {
                throw new IOException("META-INF/container.xml 缺少 rootfile 条目");
            }
            String selected = null;
            for (int i = 0; i < rootfiles.getLength(); i++) {
                Element rf = (Element) rootfiles.item(i);
                String fullPath = rf.getAttribute("full-path");
                String mediaType = rf.getAttribute("media-type");
                if (fullPath != null && !fullPath.trim().isEmpty()) {
                    if ("application/oebps-package+xml".equalsIgnoreCase(mediaType) || selected == null) {
                        selected = fullPath.trim();
                    }
                }
            }
            if (selected == null) {
                throw new IOException("META-INF/container.xml 缺少有效的 rootfile full-path");
            }
            selected = URLDecoder.decode(selected, "UTF-8");
            selected = normalizePath(selected);
            if (selected.startsWith("../")) {
                throw new IOException("EPUB rootfile 路径非法越界: " + selected);
            }
            opfPath = selected;
        } catch (Exception e) {
            if (e instanceof IOException) throw (IOException) e;
            throw new IOException("解析 META-INF/container.xml 失败: " + e.getMessage(), e);
        }

        ZipEntry opfEntry = zip.getEntry(opfPath);
        if (opfEntry == null) {
            throw new IOException("EPUB OPF 文件未找到: " + opfPath);
        }

        String opfBaseDir = getParentDir(opfPath);

        // Step 2: Check META-INF/encryption.xml for DRM and font obfuscation
        boolean hasDrm = false;
        boolean hasFontObfuscation = false;
        String unsupportedReason = null;

        ZipEntry encEntry = zip.getEntry("META-INF/encryption.xml");
        if (encEntry != null) {
            try (InputStream in = zip.getInputStream(encEntry)) {
                Document doc = parseXmlSafely(in);
                NodeList encList = doc.getElementsByTagName("EncryptedData");
                for (int i = 0; i < encList.getLength(); i++) {
                    Element enc = (Element) encList.item(i);
                    String algo = "";
                    NodeList methodList = enc.getElementsByTagName("EncryptionMethod");
                    if (methodList.getLength() > 0) {
                        algo = ((Element) methodList.item(0)).getAttribute("Algorithm");
                    }
                    String cipherUri = "";
                    NodeList refList = enc.getElementsByTagName("CipherReference");
                    if (refList.getLength() > 0) {
                        cipherUri = ((Element) refList.item(0)).getAttribute("URI");
                    }
                    boolean isFontAlgo = "http://www.idpf.org/2008/embedding".equals(algo)
                            || "http://ns.adobe.com/pdf/enc/mono/".equals(algo);
                    boolean isFontUri = cipherUri.endsWith(".otf") || cipherUri.endsWith(".ttf")
                            || cipherUri.endsWith(".woff") || cipherUri.endsWith(".woff2");

                    if (isFontAlgo || isFontUri) {
                        hasFontObfuscation = true;
                    } else {
                        hasDrm = true;
                        unsupportedReason = "该 EPUB 包含受保护或加密的版权内容 (DRM)";
                    }
                }
            } catch (Exception ignored) {}
        }

        // Step 3: Parse OPF Document
        String title = null;
        String author = null;
        String description = null;
        String language = null;
        String metaCoverId = null;
        boolean isFixedLayout = false;

        Map<String, Publication.ManifestItem> manifest = new LinkedHashMap<>();
        List<Publication.SpineItem> spine = new ArrayList<>();
        String coverImageEntry = null;
        String navDocPath = null;
        String ncxDocPath = null;

        try (InputStream in = zip.getInputStream(opfEntry)) {
            Document doc = parseXmlSafely(in);

            // Metadata
            NodeList metadataList = doc.getElementsByTagName("metadata");
            if (metadataList.getLength() > 0) {
                Element metadata = (Element) metadataList.item(0);

                NodeList titles = metadata.getElementsByTagName("dc:title");
                if (titles.getLength() == 0) titles = metadata.getElementsByTagNameNS("*", "title");
                if (titles.getLength() > 0) {
                    title = titles.item(0).getTextContent();
                    if (title != null) title = title.trim();
                }

                NodeList creators = metadata.getElementsByTagName("dc:creator");
                if (creators.getLength() == 0) creators = metadata.getElementsByTagNameNS("*", "creator");
                if (creators.getLength() > 0) {
                    author = creators.item(0).getTextContent();
                    if (author != null) author = author.trim();
                }

                NodeList descs = metadata.getElementsByTagName("dc:description");
                if (descs.getLength() == 0) descs = metadata.getElementsByTagNameNS("*", "description");
                if (descs.getLength() > 0) {
                    description = descs.item(0).getTextContent();
                    if (description != null) description = description.trim();
                }

                NodeList langs = metadata.getElementsByTagName("dc:language");
                if (langs.getLength() == 0) langs = metadata.getElementsByTagNameNS("*", "language");
                if (langs.getLength() > 0) {
                    language = langs.item(0).getTextContent();
                    if (language != null) language = language.trim();
                }

                NodeList metas = metadata.getElementsByTagName("meta");
                for (int i = 0; i < metas.getLength(); i++) {
                    Element m = (Element) metas.item(i);
                    String name = m.getAttribute("name");
                    String prop = m.getAttribute("property");
                    if ("cover".equalsIgnoreCase(name)) {
                        metaCoverId = m.getAttribute("content");
                    }
                    if ("rendition:layout".equalsIgnoreCase(prop)) {
                        String val = m.getTextContent();
                        if (val != null && "pre-paginated".equalsIgnoreCase(val.trim())) {
                            isFixedLayout = true;
                        }
                    }
                }
            }

            // Manifest
            NodeList manifestNodes = doc.getElementsByTagName("manifest");
            if (manifestNodes.getLength() == 0) {
                throw new IOException("EPUB OPF 缺少 manifest 节点");
            }
            Element manifestElem = (Element) manifestNodes.item(0);
            NodeList itemNodes = manifestElem.getElementsByTagName("item");
            if (itemNodes.getLength() == 0) {
                throw new IOException("EPUB manifest 为空");
            }

            Set<String> seenIds = new HashSet<>();
            for (int i = 0; i < itemNodes.getLength(); i++) {
                Element it = (Element) itemNodes.item(i);
                String id = it.getAttribute("id");
                String rawHref = it.getAttribute("href");
                String mediaType = it.getAttribute("media-type");
                String properties = it.getAttribute("properties");

                if (id == null || id.trim().isEmpty()) {
                    throw new IOException("EPUB manifest 包含缺少 id 的条目");
                }
                id = id.trim();
                if (seenIds.contains(id)) {
                    throw new IOException("EPUB manifest 包含重复的条目 id: " + id);
                }
                seenIds.add(id);

                if (rawHref == null || rawHref.trim().isEmpty()) {
                    throw new IOException("EPUB manifest item [" + id + "] 缺少 href");
                }

                String decodedHref = URLDecoder.decode(rawHref.trim(), "UTF-8");
                int hashIdx = decodedHref.indexOf('#');
                if (hashIdx >= 0) decodedHref = decodedHref.substring(0, hashIdx);

                String resolvedPath = resolvePath(opfBaseDir, decodedHref);
                if (resolvedPath.startsWith("../")) {
                    throw new IOException("EPUB 资源路径非法越界: " + rawHref);
                }

                if (properties != null && properties.contains("cover-image")) {
                    coverImageEntry = resolvedPath;
                }
                if (properties != null && properties.contains("nav")) {
                    navDocPath = resolvedPath;
                }
                if ("application/x-dtbncx+xml".equalsIgnoreCase(mediaType)) {
                    ncxDocPath = resolvedPath;
                }
                if (properties != null && properties.contains("rendition:layout-pre-paginated")) {
                    isFixedLayout = true;
                }

                manifest.put(id, new Publication.ManifestItem(id, resolvedPath, mediaType, properties));
            }

            // Spine
            NodeList spineNodes = doc.getElementsByTagName("spine");
            if (spineNodes.getLength() == 0) {
                throw new IOException("EPUB OPF 缺少 spine 节点");
            }
            Element spineElem = (Element) spineNodes.item(0);
            String tocAttr = spineElem.getAttribute("toc");
            if (ncxDocPath == null && tocAttr != null && !tocAttr.trim().isEmpty()) {
                Publication.ManifestItem ncxItem = manifest.get(tocAttr.trim());
                if (ncxItem != null) ncxDocPath = ncxItem.href;
            }

            NodeList itemRefs = spineElem.getElementsByTagName("itemref");
            if (itemRefs.getLength() == 0) {
                throw new IOException("EPUB spine 为空");
            }

            for (int i = 0; i < itemRefs.getLength(); i++) {
                Element ir = (Element) itemRefs.item(i);
                String idref = ir.getAttribute("idref");
                if (idref == null || idref.trim().isEmpty()) {
                    throw new IOException("EPUB spine itemref 缺少 idref");
                }
                idref = idref.trim();
                Publication.ManifestItem mi = manifest.get(idref);
                if (mi == null) {
                    throw new IOException("EPUB spine 引用了 manifest 中不存在的条目: " + idref);
                }
                boolean linear = !"no".equalsIgnoreCase(ir.getAttribute("linear"));

                String resolvedImage = null;
                if (mi.mediaType.startsWith("image/")) {
                    resolvedImage = mi.href;
                } else if ("application/xhtml+xml".equalsIgnoreCase(mi.mediaType)
                        || "text/html".equalsIgnoreCase(mi.mediaType)) {
                    resolvedImage = resolveSingleImageFromHtml(zip, mi.href);
                }

                spine.add(new Publication.SpineItem(idref, mi.href, mi.mediaType, linear, resolvedImage));
            }
        } catch (Exception e) {
            if (e instanceof IOException) throw (IOException) e;
            throw new IOException("解析 EPUB OPF 失败: " + e.getMessage(), e);
        }

        // Step 4: Parse Navigation / TOC
        List<Publication.NavItem> navItems = new ArrayList<>();
        if (navDocPath != null && zip.getEntry(navDocPath) != null) {
            try {
                navItems = parseEpub3Nav(zip, navDocPath, spine);
            } catch (Exception ignored) {}
        }
        if (navItems.isEmpty() && ncxDocPath != null && zip.getEntry(ncxDocPath) != null) {
            try {
                navItems = parseEpub2Ncx(zip, ncxDocPath, spine);
            } catch (Exception ignored) {}
        }

        // Step 5: Classify Pure Picture vs Reflowable vs Mixed
        int totalSpine = spine.size();
        int imageSpineCount = 0;
        for (Publication.SpineItem sp : spine) {
            if (sp.resolvedImageEntry != null) imageSpineCount++;
        }

        boolean isPurePictureEpub = (totalSpine > 0 && imageSpineCount == totalSpine);
        boolean isReflowableText = false;

        if (!isPurePictureEpub) {
            // Check if there are ANY images in the whole book
            int totalManifestImages = 0;
            for (Publication.ManifestItem mi : manifest.values()) {
                if (mi.mediaType.startsWith("image/")) totalManifestImages++;
            }
            if (totalManifestImages <= 1 && imageSpineCount == 0) {
                isReflowableText = true;
            }
        }

        // Step 6: Cover Detection
        String finalCoverEntry = coverImageEntry;
        if (finalCoverEntry == null && metaCoverId != null) {
            Publication.ManifestItem coverItem = manifest.get(metaCoverId);
            if (coverItem != null) {
                if (coverItem.mediaType.startsWith("image/")) {
                    finalCoverEntry = coverItem.href;
                } else if ("application/xhtml+xml".equalsIgnoreCase(coverItem.mediaType)) {
                    finalCoverEntry = resolveSingleImageFromHtml(zip, coverItem.href);
                }
            }
        }
        if (finalCoverEntry == null && !spine.isEmpty() && spine.get(0).resolvedImageEntry != null) {
            finalCoverEntry = spine.get(0).resolvedImageEntry;
        }
        if (finalCoverEntry == null) {
            for (Publication.ManifestItem mi : manifest.values()) {
                if (mi.mediaType.startsWith("image/") && mi.href.toLowerCase(Locale.US).contains("cover")) {
                    finalCoverEntry = mi.href;
                    break;
                }
            }
        }

        return new Publication(title, author, description, language, opfPath, finalCoverEntry,
                spine, navItems, manifest, isFixedLayout, isPurePictureEpub, isReflowableText,
                hasDrm, hasFontObfuscation, unsupportedReason);
    }

    private static String resolveSingleImageFromHtml(ZipFile zip, String htmlPath) {
        ZipEntry entry = zip.getEntry(htmlPath);
        if (entry == null) return null;
        try (InputStream in = zip.getInputStream(entry)) {
            byte[] buf = readBytesBounded(in, MAX_XHTML_INSPECT_BYTES);
            String html = new String(buf, StandardCharsets.UTF_8);

            // Match <img> and <svg><image>
            List<String> imageSources = new ArrayList<>();
            Matcher imgMatcher = IMG_SRC_PATTERN.matcher(html);
            while (imgMatcher.find()) {
                imageSources.add(imgMatcher.group(1));
            }
            Matcher svgMatcher = SVG_IMAGE_PATTERN.matcher(html);
            while (svgMatcher.find()) {
                imageSources.add(svgMatcher.group(1));
            }

            if (imageSources.size() != 1) {
                return null; // Not a single image wrapper
            }

            String rawSrc = imageSources.get(0);
            String decodedSrc = URLDecoder.decode(rawSrc.trim(), "UTF-8");
            int hashIdx = decodedSrc.indexOf('#');
            if (hashIdx >= 0) decodedSrc = decodedSrc.substring(0, hashIdx);

            String htmlBase = getParentDir(htmlPath);
            String resolved = resolvePath(htmlBase, decodedSrc);
            if (resolved.startsWith("../")) return null;

            if (zip.getEntry(resolved) != null) {
                return resolved;
            }
        } catch (Exception ignored) {}
        return null;
    }

    private static List<Publication.NavItem> parseEpub3Nav(ZipFile zip, String navPath, List<Publication.SpineItem> spine) throws Exception {
        ZipEntry entry = zip.getEntry(navPath);
        if (entry == null) return Collections.emptyList();
        String baseDir = getParentDir(navPath);

        try (InputStream in = zip.getInputStream(entry)) {
            Document doc = parseXmlSafely(in);
            NodeList navs = doc.getElementsByTagName("nav");
            Element tocNav = null;
            for (int i = 0; i < navs.getLength(); i++) {
                Element n = (Element) navs.item(i);
                if ("toc".equalsIgnoreCase(n.getAttribute("epub:type")) || tocNav == null) {
                    tocNav = n;
                }
            }
            if (tocNav == null) return Collections.emptyList();

            List<Publication.NavItem> result = new ArrayList<>();
            NodeList ols = tocNav.getElementsByTagName("ol");
            if (ols.getLength() > 0) {
                Element topOl = (Element) ols.item(0);
                parseNavList(topOl, baseDir, spine, result);
            }
            return result;
        }
    }

    private static void parseNavList(Element ol, String baseDir, List<Publication.SpineItem> spine, List<Publication.NavItem> out) {
        NodeList children = ol.getChildNodes();
        for (int i = 0; i < children.getLength(); i++) {
            Node node = children.item(i);
            if (node.getNodeType() == Node.ELEMENT_NODE && "li".equalsIgnoreCase(node.getNodeName())) {
                Element li = (Element) node;
                NodeList aList = li.getElementsByTagName("a");
                String title = "";
                String href = "";
                int spineIndex = -1;
                if (aList.getLength() > 0) {
                    Element a = (Element) aList.item(0);
                    title = a.getTextContent() != null ? a.getTextContent().trim() : "";
                    String rawHref = a.getAttribute("href");
                    if (rawHref != null && !rawHref.trim().isEmpty()) {
                        try {
                            String decoded = URLDecoder.decode(rawHref.trim(), "UTF-8");
                            int h = decoded.indexOf('#');
                            String stripped = (h >= 0) ? decoded.substring(0, h) : decoded;
                            href = resolvePath(baseDir, stripped);
                            spineIndex = findSpineIndexByPath(spine, href);
                        } catch (Exception ignored) {}
                    }
                }
                List<Publication.NavItem> subItems = new ArrayList<>();
                NodeList subOls = li.getElementsByTagName("ol");
                if (subOls.getLength() > 0) {
                    parseNavList((Element) subOls.item(0), baseDir, spine, subItems);
                }
                out.add(new Publication.NavItem(title, href, spineIndex, subItems));
            }
        }
    }

    private static List<Publication.NavItem> parseEpub2Ncx(ZipFile zip, String ncxPath, List<Publication.SpineItem> spine) throws Exception {
        ZipEntry entry = zip.getEntry(ncxPath);
        if (entry == null) return Collections.emptyList();
        String baseDir = getParentDir(ncxPath);

        try (InputStream in = zip.getInputStream(entry)) {
            Document doc = parseXmlSafely(in);
            NodeList navMaps = doc.getElementsByTagName("navMap");
            if (navMaps.getLength() == 0) return Collections.emptyList();
            Element navMap = (Element) navMaps.item(0);

            List<Publication.NavItem> result = new ArrayList<>();
            NodeList children = navMap.getChildNodes();
            for (int i = 0; i < children.getLength(); i++) {
                Node node = children.item(i);
                if (node.getNodeType() == Node.ELEMENT_NODE && "navPoint".equalsIgnoreCase(node.getNodeName())) {
                    parseNcxPoint((Element) node, baseDir, spine, result);
                }
            }
            return result;
        }
    }

    private static void parseNcxPoint(Element point, String baseDir, List<Publication.SpineItem> spine, List<Publication.NavItem> out) {
        String title = "";
        NodeList labels = point.getElementsByTagName("text");
        if (labels.getLength() > 0) {
            title = labels.item(0).getTextContent() != null ? labels.item(0).getTextContent().trim() : "";
        }

        String href = "";
        int spineIndex = -1;
        NodeList contents = point.getElementsByTagName("content");
        if (contents.getLength() > 0) {
            String rawSrc = ((Element) contents.item(0)).getAttribute("src");
            if (rawSrc != null && !rawSrc.trim().isEmpty()) {
                try {
                    String decoded = URLDecoder.decode(rawSrc.trim(), "UTF-8");
                    int h = decoded.indexOf('#');
                    String stripped = (h >= 0) ? decoded.substring(0, h) : decoded;
                    href = resolvePath(baseDir, stripped);
                    spineIndex = findSpineIndexByPath(spine, href);
                } catch (Exception ignored) {}
            }
        }

        List<Publication.NavItem> subItems = new ArrayList<>();
        NodeList children = point.getChildNodes();
        for (int i = 0; i < children.getLength(); i++) {
            Node n = children.item(i);
            if (n.getNodeType() == Node.ELEMENT_NODE && "navPoint".equalsIgnoreCase(n.getNodeName())) {
                parseNcxPoint((Element) n, baseDir, spine, subItems);
            }
        }

        out.add(new Publication.NavItem(title, href, spineIndex, subItems));
    }

    private static int findSpineIndexByPath(List<Publication.SpineItem> spine, String path) {
        if (path == null || path.isEmpty()) return -1;
        for (int i = 0; i < spine.size(); i++) {
            if (path.equals(spine.get(i).fullZipPath)) {
                return i;
            }
        }
        return -1;
    }

    public static Document parseXmlSafely(InputStream in) throws Exception {
        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        dbf.setNamespaceAware(true);
        try {
            dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
        } catch (Throwable ignored) {}
        try {
            dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        } catch (Throwable ignored) {}
        try {
            dbf.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
        } catch (Throwable ignored) {}
        try {
            dbf.setFeature("http://xml.org/sax/features/validation", false);
        } catch (Throwable ignored) {}
        try {
            dbf.setXIncludeAware(false);
        } catch (Throwable ignored) {}
        try {
            dbf.setExpandEntityReferences(false);
        } catch (Throwable ignored) {}
        DocumentBuilder builder = dbf.newDocumentBuilder();
        builder.setEntityResolver((publicId, systemId) -> new InputSource(new StringReader("")));

        BufferedInputStream bin = (in instanceof BufferedInputStream) ? (BufferedInputStream) in : new BufferedInputStream(in);
        bin.mark(4);
        byte[] bom = new byte[3];
        int read = bin.read(bom, 0, 3);
        if (read == 3 && bom[0] == (byte) 0xEF && bom[1] == (byte) 0xBB && bom[2] == (byte) 0xBF) {
            // UTF-8 BOM detected and stripped
        } else {
            bin.reset();
        }
        return builder.parse(bin);
    }

    private static String getParentDir(String path) {
        if (path == null) return "";
        int idx = path.lastIndexOf('/');
        return (idx >= 0) ? path.substring(0, idx + 1) : "";
    }

    public static String resolvePath(String baseDir, String relativePath) {
        if (relativePath == null) return "";
        if (relativePath.startsWith("/")) {
            return normalizePath(relativePath.substring(1));
        }
        return normalizePath((baseDir != null ? baseDir : "") + relativePath);
    }

    public static String normalizePath(String path) {
        if (path == null) return "";
        String s = path.replace('\\', '/');
        String[] parts = s.split("/+");
        List<String> normalized = new ArrayList<>();
        for (String p : parts) {
            if (p.isEmpty() || p.equals(".")) continue;
            if (p.equals("..")) {
                if (!normalized.isEmpty() && !normalized.get(normalized.size() - 1).equals("..")) {
                    normalized.remove(normalized.size() - 1);
                } else {
                    normalized.add("..");
                }
            } else {
                normalized.add(p);
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < normalized.size(); i++) {
            if (i > 0) sb.append('/');
            sb.append(normalized.get(i));
        }
        return sb.toString();
    }

    private static byte[] readBytesBounded(InputStream in, int maxBytes) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int total = 0;
        int n;
        while ((n = in.read(buf)) > 0) {
            int toWrite = Math.min(n, maxBytes - total);
            out.write(buf, 0, toWrite);
            total += toWrite;
            if (total >= maxBytes) break;
        }
        return out.toByteArray();
    }
}
