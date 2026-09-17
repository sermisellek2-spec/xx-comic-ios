package com.xxcomic.pdf;

import android.graphics.Bitmap;

import com.xxcomic.local.ArchiveIndex;
import com.xxcomic.local.LocalModels;

import org.junit.After;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class PdfParserTest {

    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    @Before
    @After
    public void resetEngineFactory() {
        PdfParser.setCustomEngineFactory(null);
    }

    private File createDummyPdfFile(String name, byte[] headerPrefix) throws IOException {
        File f = temp.newFile(name);
        try (FileOutputStream out = new FileOutputStream(f)) {
            if (headerPrefix != null) {
                out.write(headerPrefix);
            }
            out.write("Dummy PDF body content".getBytes(StandardCharsets.UTF_8));
        }
        return f;
    }

    @Test
    public void detectsPdfByMagicHeaderAndExtension() throws IOException {
        byte[] pdfMagic = new byte[]{0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34}; // %PDF-1.4
        File pdfWithExt = createDummyPdfFile("test.pdf", pdfMagic);
        File pdfWithoutExt = createDummyPdfFile("test_no_ext.bin", pdfMagic);
        File nonPdfWithExt = createDummyPdfFile("fake.pdf", "NOT_A_PDF".getBytes(StandardCharsets.UTF_8));
        File nonPdfZip = createDummyPdfFile("test.zip", "PK\u0003\u0004".getBytes(StandardCharsets.UTF_8));

        Assert.assertTrue("Should detect by magic even without extension", PdfParser.isPdfFile(pdfWithoutExt, "test_no_ext.bin"));
        Assert.assertTrue("Should detect with extension and magic", PdfParser.isPdfFile(pdfWithExt, "test.pdf"));
        Assert.assertTrue("Extension .pdf matches even if buffer is small", PdfParser.isPdfFile(nonPdfWithExt, "fake.pdf"));
        Assert.assertFalse("ZIP is not PDF", PdfParser.isPdfFile(nonPdfZip, "test.zip"));
    }

    @Test
    public void parsesPdfIntoStableChapterAndPages() throws IOException {
        byte[] pdfMagic = new byte[]{0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37};
        File pdfFile = createDummyPdfFile("sample.pdf", pdfMagic);

        PdfParser.setCustomEngineFactory(file -> new PdfParser.PdfEngine() {
            @Override
            public int getPageCount() {
                return 5;
            }

            @Override
            public int[] getPageSize(int pageIndex) {
                return new int[]{1080, 1920};
            }

            @Override
            public Bitmap renderPage(int pageIndex, int targetWidth, int targetHeight) {
                return null;
            }

            @Override
            public void close() {
            }
        });

        ArchiveIndex.ParseResult result = PdfParser.parse(pdfFile, "pdf_book_1", null);
        Assert.assertNotNull(result);
        Assert.assertEquals(5, result.totalPages);
        Assert.assertEquals(1, result.chapters.size());

        LocalModels.Chapter chapter = result.chapters.get(0);
        Assert.assertEquals("全本", chapter.title);
        Assert.assertEquals(5, chapter.pageCount);

        Assert.assertTrue(result.pagesByChapter.containsKey(chapter.id));
        Assert.assertEquals(5, result.pagesByChapter.get(chapter.id).size());

        for (int i = 0; i < 5; i++) {
            LocalModels.Page page = result.pagesByChapter.get(chapter.id).get(i);
            Assert.assertEquals(String.valueOf(i), page.entryPath);
            Assert.assertEquals("image/png", page.mimeType);
            Assert.assertEquals(1080, page.width);
            Assert.assertEquals(1920, page.height);
        }
    }

    @Test(expected = IOException.class)
    public void rejectsEmptyPdf() throws IOException {
        byte[] pdfMagic = new byte[]{0x25, 0x50, 0x44, 0x46, 0x2D};
        File pdfFile = createDummyPdfFile("empty.pdf", pdfMagic);

        PdfParser.setCustomEngineFactory(file -> new PdfParser.PdfEngine() {
            @Override
            public int getPageCount() {
                return 0;
            }

            @Override
            public int[] getPageSize(int pageIndex) {
                return new int[]{0, 0};
            }

            @Override
            public Bitmap renderPage(int pageIndex, int targetWidth, int targetHeight) {
                return null;
            }

            @Override
            public void close() {}
        });

        PdfParser.parse(pdfFile, "pdf_empty", null);
    }

    @Test
    public void throwsFriendlyErrorOnPasswordProtectedPdf() throws IOException {
        byte[] pdfMagic = new byte[]{0x25, 0x50, 0x44, 0x46, 0x2D};
        File pdfFile = createDummyPdfFile("encrypted.pdf", pdfMagic);

        PdfParser.setCustomEngineFactory(file -> {
            throw new IOException("PDF 受密码保护，暂不支持加密 PDF 文件", new SecurityException());
        });

        try {
            PdfParser.parse(pdfFile, "pdf_encrypted", null);
            Assert.fail("Should have thrown IOException for encrypted PDF");
        } catch (IOException expected) {
            Assert.assertTrue("Exception message should mention password protection",
                    expected.getMessage().contains("密码保护"));
        }
    }
}
