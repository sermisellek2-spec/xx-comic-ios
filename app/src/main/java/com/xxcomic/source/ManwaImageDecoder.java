package com.xxcomic.source;

import java.io.IOException;
import java.io.InputStream;
import java.io.PushbackInputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Locale;
import javax.crypto.Cipher;
import javax.crypto.CipherInputStream;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Same public image format as BaseUtil.getSecureImageUrl: IV followed by AES-CBC data. */
public final class ManwaImageDecoder {
    private ManwaImageDecoder() { }

    public static boolean usesImageHost(String imageUrl) {
        try {
            String host = new URL(imageUrl).getHost().toLowerCase(Locale.ROOT);
            for (String domain : new String[]{"mwtuwu.cc", "mwzu.cc", "mhttu.cc", "manwace.cc"}) {
                if (host.equals(domain) || host.endsWith("." + domain)) return true;
            }
        } catch (Exception ignored) { }
        return false;
    }

    /** Streams decrypted bytes into the normal image cache, including prefetch/offline paths. */
    public static InputStream open(InputStream input, String publicKey) throws IOException {
        PushbackInputStream buffered = new PushbackInputStream(input, 16);
        byte[] header = header(buffered);
        if (isImage(header)) { buffered.unread(header); return buffered; }
        try {
            byte[] key = publicKey.getBytes(StandardCharsets.UTF_8);
            if (key.length != 32) throw new IOException("漫蛙图片格式密钥长度无效");
            Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"), new IvParameterSpec(header));
            PushbackInputStream decoded = new PushbackInputStream(new CipherInputStream(buffered, cipher), 16);
            byte[] imageHeader = header(decoded);
            if (!isImage(imageHeader)) throw new IOException("漫蛙图片解码失败");
            decoded.unread(imageHeader);
            return decoded;
        } catch (GeneralSecurityException e) { throw new IOException("漫蛙图片解码失败", e); }
    }

    private static byte[] header(InputStream stream) throws IOException {
        byte[] header = new byte[16];
        int offset = 0;
        while (offset < header.length) {
            int read = stream.read(header, offset, header.length - offset);
            if (read < 0) throw new IOException("漫蛙图片数据不完整");
            offset += read;
        }
        return header;
    }

    private static boolean isImage(byte[] bytes) {
        return (bytes[0] == (byte) 0xff && bytes[1] == (byte) 0xd8 && bytes[2] == (byte) 0xff)
                || (bytes[0] == (byte) 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G')
                || (bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == '8')
                || (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F'
                    && bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P');
    }
}
