package com.xxcomic.ebook;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.Assert.*;

public class QuickPublicationInfoTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();

    @Test public void readsMetadataWithoutOpeningMissingBodyOrCover() throws Exception {
        File file = epub("metadata.epub", "<metadata><dc:title> 夏日列车 </dc:title>"
                + "<meta name='calibre:series' content='四季故事'/>"
                + "<meta name='calibre:series_index' content='2.5'/><meta name='cover' content='cover'/></metadata>"
                + "<manifest><item id='cover' href='../Images/cover%20art.jpg' media-type='image/jpeg'/>"
                + "<item id='body' href='missing.xhtml' media-type='application/xhtml+xml'/></manifest>"
                + "<spine><itemref idref='body'/></spine>");
        QuickPublicationInfo info = QuickPublicationInfo.read(file);
        assertEquals("夏日列车", info.title);
        assertEquals("四季故事", info.seriesTitle);
        assertEquals("2.5", info.volumeNumber);
        assertEquals("Images/cover art.jpg", info.coverEntry);
        assertTrue(info.isReadable);
    }

    @Test public void readsEpub3SeriesRefinementsAndCoverProperty() throws Exception {
        File file = epub("data.bin", "<metadata><meta property='belongs-to-collection' id='set'>长篇</meta>"
                + "<meta refines='#set' property='collection-type'>series</meta>"
                + "<meta refines='#set' property='group-position'>3</meta></metadata>"
                + "<manifest><item href='cover+one.png' properties='nav cover-image' media-type='image/png'/></manifest>");
        QuickPublicationInfo info = QuickPublicationInfo.read(file, "EPUB");
        assertEquals("长篇", info.seriesTitle);
        assertEquals("3", info.volumeNumber);
        assertEquals("OPS/cover+one.png", info.coverEntry);
    }

    @Test public void missingMetadataReturnsEmptyFields() throws Exception {
        QuickPublicationInfo info = QuickPublicationInfo.read(epub("empty.epub", "<manifest/><spine/>"));
        assertEquals("", info.title);
        assertEquals("", info.seriesTitle);
        assertEquals("", info.volumeNumber);
        assertEquals("", info.coverEntry);
        assertTrue(info.isReadable);
    }

    @Test public void rejectsDoctypeEvenWhenEntityIsNotUsed() throws Exception {
        File file = temporary.newFile("unsafe.epub");
        try (ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(file))) {
            entry(zip, "META-INF/container.xml", container());
            entry(zip, "OPS/book.opf", "<!DOCTYPE package [<!ENTITY secret SYSTEM 'file:///never-read-this'>]>"
                    + "<package><metadata><title>Book</title></metadata></package>");
        }
        assertThrows(IOException.class, () -> QuickPublicationInfo.read(file));
    }

    @Test public void rejectsOversizedCompressedMetadata() throws Exception {
        StringBuilder large = new StringBuilder("<metadata><dc:title>");
        for (int i = 0; i < 1100000; i++) large.append('a');
        large.append("</dc:title></metadata>");
        File file = epub("large.epub", large.toString());
        assertThrows(IOException.class, () -> QuickPublicationInfo.read(file));
    }

    @Test public void malformedCoverUriProducesCheckedScanFailure() throws Exception {
        File file = epub("bad-uri.epub", "<manifest><item href='cover%xx.jpg' properties='cover-image'/></manifest>");
        assertThrows(IOException.class, () -> QuickPublicationInfo.read(file));
    }

    @Test public void readsMobiHeaderTitleAndDetectsUnsupportedAzw3() throws Exception {
        QuickPublicationInfo mobi = QuickPublicationInfo.read(mobi("book.mobi", 6));
        assertEquals("头部标题", mobi.title);
        assertTrue(mobi.isReadable);
        QuickPublicationInfo azw3 = QuickPublicationInfo.read(mobi("book.azw3", 8));
        assertEquals("头部标题", azw3.title);
        assertFalse(azw3.isReadable);
        assertTrue(azw3.unsupportedReason.contains("KF8"));
    }

    private File epub(String name, String contents) throws Exception {
        File file = temporary.newFile(name);
        try (ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(file))) {
            entry(zip, "META-INF/container.xml", container());
            entry(zip, "OPS/book.opf", "<package xmlns='http://www.idpf.org/2007/opf' "
                    + "xmlns:dc='http://purl.org/dc/elements/1.1/'>" + contents + "</package>");
        }
        return file;
    }

    private String container() {
        return "<container xmlns='urn:oasis:names:tc:opendocument:xmlns:container'><rootfiles>"
                + "<rootfile full-path='OPS/book.opf' media-type='application/oebps-package+xml'/>"
                + "</rootfiles></container>";
    }

    private void entry(ZipOutputStream zip, String name, String value) throws IOException {
        zip.putNextEntry(new ZipEntry(name));
        zip.write(value.getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
    }

    private File mobi(String name, int version) throws IOException {
        byte[] title = "头部标题".getBytes(StandardCharsets.UTF_8);
        int recordOffset = 94, titleOffset = 248;
        ByteBuffer bytes = ByteBuffer.allocate(recordOffset + titleOffset + title.length + 1);
        bytes.position(60);
        bytes.put("BOOKMOBI".getBytes(StandardCharsets.US_ASCII));
        bytes.putShort(76, (short) 2);
        bytes.putInt(78, recordOffset);
        bytes.putInt(86, bytes.capacity() - 1);
        bytes.putShort(recordOffset, (short) 2);
        bytes.putShort(recordOffset + 8, (short) 1);
        bytes.position(recordOffset + 16);
        bytes.put("MOBI".getBytes(StandardCharsets.US_ASCII));
        bytes.putInt(232);
        bytes.putInt(2);
        bytes.putInt(65001);
        bytes.putInt(0);
        bytes.putInt(version);
        bytes.putInt(recordOffset + 16 + 68, titleOffset);
        bytes.putInt(recordOffset + 16 + 72, title.length);
        bytes.position(recordOffset + titleOffset);
        bytes.put(title);
        File file = temporary.newFile(name);
        Files.write(file.toPath(), bytes.array());
        return file;
    }
}
