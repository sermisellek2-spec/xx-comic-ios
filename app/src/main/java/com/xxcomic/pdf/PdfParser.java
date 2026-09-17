package com.xxcomic.pdf;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;

import com.xxcomic.local.ArchiveIndex;
import com.xxcomic.local.LocalModels;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class PdfParser {

    public interface PdfEngine {
        int getPageCount() throws IOException;
        int[] getPageSize(int pageIndex) throws IOException;
        Bitmap renderPage(int pageIndex, int targetWidth, int targetHeight) throws IOException;
        void close();
    }

    public interface PdfEngineFactory {
        PdfEngine open(File file) throws IOException;
    }

    private static PdfEngineFactory customEngineFactory = null;

    public static void setCustomEngineFactory(PdfEngineFactory factory) {
        customEngineFactory = factory;
    }

    public static PdfEngine openEngine(File file) throws IOException {
        if (customEngineFactory != null) {
            return customEngineFactory.open(file);
        }
        return new AndroidPdfEngine(file);
    }

    public static class AndroidPdfEngine implements PdfEngine {
        private final ParcelFileDescriptor pfd;
        private final PdfRenderer renderer;

        public AndroidPdfEngine(File file) throws IOException {
            try {
                this.pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
                this.renderer = new PdfRenderer(pfd);
            } catch (SecurityException se) {
                throw new IOException("PDF 受密码保护，暂不支持加密 PDF 文件", se);
            } catch (Exception e) {
                throw new IOException("无法打开 PDF 文件: " + e.getMessage(), e);
            }
        }

        @Override
        public int getPageCount() {
            return renderer.getPageCount();
        }

        @Override
        public int[] getPageSize(int pageIndex) throws IOException {
            if (pageIndex < 0 || pageIndex >= renderer.getPageCount()) {
                throw new IOException("PDF 页码超出范围: " + pageIndex);
            }
            PdfRenderer.Page page = renderer.openPage(pageIndex);
            try {
                return new int[]{page.getWidth(), page.getHeight()};
            } finally {
                page.close();
            }
        }

        @Override
        public Bitmap renderPage(int pageIndex, int targetWidth, int targetHeight) throws IOException {
            if (pageIndex < 0 || pageIndex >= renderer.getPageCount()) {
                throw new IOException("PDF 页码超出范围: " + pageIndex);
            }
            PdfRenderer.Page page = renderer.openPage(pageIndex);
            try {
                int srcW = page.getWidth();
                int srcH = page.getHeight();
                if (srcW <= 0) srcW = 720;
                if (srcH <= 0) srcH = 1080;

                int rw = targetWidth > 0 ? targetWidth : srcW;
                int rh = targetHeight > 0 ? targetHeight : srcH;

                Bitmap bitmap = Bitmap.createBitmap(rw, rh, Bitmap.Config.ARGB_8888);
                Canvas canvas = new Canvas(bitmap);
                canvas.drawColor(Color.WHITE); // Default white background for transparent pages
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                return bitmap;
            } finally {
                page.close();
            }
        }

        @Override
        public void close() {
            try {
                renderer.close();
            } catch (Exception ignored) { }
            try {
                pfd.close();
            } catch (Exception ignored) { }
        }
    }

    public static boolean isPdfFile(File file, String displayName) {
        if (displayName != null && displayName.toLowerCase(Locale.US).endsWith(".pdf")) {
            return true;
        }
        if (file != null && file.exists() && file.length() >= 5) {
            try (FileInputStream in = new FileInputStream(file)) {
                byte[] header = new byte[5];
                int read = in.read(header);
                if (read == 5 && header[0] == 0x25 && header[1] == 0x50 && header[2] == 0x44 && header[3] == 0x46 && header[4] == 0x2D) { // %PDF-
                    return true;
                }
            } catch (Exception ignored) { }
        }
        return false;
    }

    public static ArchiveIndex.ParseResult parse(File pdfFile, String bookId,
                                                LocalModels.ImportProgressCallback callback) throws IOException {
        return parse(pdfFile, bookId, "全本", 0, null, callback);
    }

    public static ArchiveIndex.ParseResult parse(File pdfFile, String bookId,
                                                String chapterTitle,
                                                int chapterOrderOffset,
                                                String chapterEntryPath,
                                                LocalModels.ImportProgressCallback callback) throws IOException {
        if (!isPdfFile(pdfFile, pdfFile.getName())) {
            throw new IOException("所选文件不是有效的 PDF 文档");
        }

        PdfEngine engine = openEngine(pdfFile);
        try {
            int pageCount = engine.getPageCount();
            if (pageCount <= 0) {
                throw new IOException("PDF 文件不包含有效页面");
            }

            String title = (chapterTitle != null && !chapterTitle.trim().isEmpty()) ? chapterTitle.trim() : "全本";
            String chEntry = (chapterEntryPath != null && !chapterEntryPath.trim().isEmpty())
                    ? chapterEntryPath : "page/" + chapterOrderOffset;
            String chapterId = LocalModels.buildStableChapterId(bookId, chapterOrderOffset);
            LocalModels.Chapter chapter = new LocalModels.Chapter(
                    chapterId, bookId, chapterOrderOffset, title, chEntry, pageCount);
            List<LocalModels.Chapter> chapters = Collections.singletonList(chapter);

            List<LocalModels.Page> pageList = new ArrayList<>(pageCount);
            for (int i = 0; i < pageCount; i++) {
                if (callback != null && callback.isCancelled()) {
                    throw new java.io.InterruptedIOException("导入已取消");
                }
                String pageId = LocalModels.buildStablePageId(chapterId, i);
                int[] dims = engine.getPageSize(i);
                int w = (dims != null && dims.length >= 2) ? dims[0] : 0;
                int h = (dims != null && dims.length >= 2) ? dims[1] : 0;
                LocalModels.Page page = new LocalModels.Page(
                        pageId, bookId, chapterId, i, String.valueOf(i), w, h, null, "image/png");
                pageList.add(page);
            }

            Map<String, List<LocalModels.Page>> pagesByChapter = new LinkedHashMap<>();
            pagesByChapter.put(chapterId, pageList);

            List<String> candidateCovers = Collections.singletonList("0");
            return new ArchiveIndex.ParseResult(
                    chapters, pagesByChapter, pageCount, pdfFile.length(), "0", candidateCovers);
        } finally {
            engine.close();
        }
    }

    public static Bitmap renderPageBitmap(File pdfFile, int pageIndex, int maxDimension) throws IOException {
        PdfEngine engine = openEngine(pdfFile);
        try {
            int[] dims = engine.getPageSize(pageIndex);
            int srcW = dims != null && dims.length >= 2 ? dims[0] : 720;
            int srcH = dims != null && dims.length >= 2 ? dims[1] : 1080;

            int targetMax = maxDimension > 0 ? maxDimension : 2048;
            float scale = Math.min(2.5f, Math.max(1.0f, (float) targetMax / Math.max(srcW, srcH)));
            int rw = Math.max(1, Math.round(srcW * scale));
            int rh = Math.max(1, Math.round(srcH * scale));

            return engine.renderPage(pageIndex, rw, rh);
        } finally {
            engine.close();
        }
    }

    public static boolean renderCover(File pdfFile, File coverTarget) {
        try {
            Bitmap coverBm = renderPageBitmap(pdfFile, 0, 720);
            if (coverBm == null) return false;
            File parent = coverTarget.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            try (OutputStream out = new FileOutputStream(coverTarget)) {
                coverBm.compress(Bitmap.CompressFormat.JPEG, 85, out);
            } finally {
                coverBm.recycle();
            }
            return coverTarget.exists() && coverTarget.length() > 0;
        } catch (Exception ignored) {
            return false;
        }
    }
}
