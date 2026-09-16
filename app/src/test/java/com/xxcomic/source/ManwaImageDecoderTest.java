package com.xxcomic.source;

import org.junit.Test;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;
import java.util.Base64;
import static org.junit.Assert.*;

public class ManwaImageDecoderTest {
    // Independent fixture: .NET AES-CBC encryption of a one-pixel PNG, with the site's public key.
    private static final byte[] PNG = Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9AAAAABJRU5ErkJggg==");
    private static final byte[] ENCRYPTED = Base64.getDecoder().decode("AAECAwQFBgcICQoLDA0OD54Tk4Nv+8l3Uh1THnnKXglPAH8cC/Tv25bOvDH6oRQArf7/DrKbyeVJ4noUr0XJwZLp/D3rGO6sUAtVnQsw81HqEsIN/dDPOSp+6DzeooBM");

    @Test public void encryptedImageDecodesToOriginalBytes() throws Exception { assertArrayEquals(PNG, decode(ENCRYPTED)); }
    @Test public void plainImagesPassThroughUnchanged() throws Exception { assertArrayEquals(PNG, decode(PNG)); }
    @Test public void networkStreamsMayReturnOneByteAtATime() throws Exception {
        try (InputStream input = ManwaImageDecoder.open(new ByteArrayInputStream(ENCRYPTED) {
            @Override public synchronized int read(byte[] bytes, int offset, int length) { return super.read(bytes, offset, Math.min(1, length)); }
        }, SourceConfig.manwa(true).route("imageKey"))) { assertArrayEquals(PNG, read(input)); }
    }
    @Test public void corruptTruncatedHtmlAndWrongKeyFailInsteadOfBeingCached() throws Exception {
        assertThrows(IOException.class, () -> decode(new byte[5]));
        assertThrows(IOException.class, () -> decode(Arrays.copyOf(ENCRYPTED, ENCRYPTED.length - 1)));
        assertThrows(IOException.class, () -> decode("<html><body>Access denied</body></html>".getBytes("UTF-8")));
        assertThrows(IOException.class, () -> ManwaImageDecoder.open(new ByteArrayInputStream(ENCRYPTED), "invalid"));
        assertThrows(IOException.class, () -> ManwaImageDecoder.open(new ByteArrayInputStream(ENCRYPTED), "01234567890123456789012345678901"));
    }
    @Test public void hostCheckDoesNotAffectOtherSourcesOrLookalikeDomains() {
        assertTrue(ManwaImageDecoder.usesImageHost("https://tu.mwzu.cc/a.jpg"));
        assertTrue(ManwaImageDecoder.usesImageHost("https://tu.mhttu.cc/a.jpg"));
        assertTrue(ManwaImageDecoder.usesImageHost("https://mwtuwu.cc/a.jpg"));
        assertFalse(ManwaImageDecoder.usesImageHost("https://mwtuwu.cc.example.com/a.jpg"));
        assertFalse(ManwaImageDecoder.usesImageHost("https://other.test/a?host=mwtuwu.cc"));
        assertFalse(ManwaImageDecoder.usesImageHost(null));
    }
    private static byte[] decode(byte[] bytes) throws Exception {
        try (InputStream input = ManwaImageDecoder.open(new ByteArrayInputStream(bytes), SourceConfig.manwa(true).route("imageKey"))) { return read(input); }
    }
    private static byte[] read(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream(); byte[] buffer = new byte[8192]; int count;
        while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        return output.toByteArray();
    }
}
