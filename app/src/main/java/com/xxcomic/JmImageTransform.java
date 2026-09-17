package com.xxcomic;
import android.graphics.*;
import android.text.TextUtils;
import java.util.regex.*;
import java.security.MessageDigest;
import java.util.Locale;
public final class JmImageTransform {
    public static Bitmap restore(Bitmap source, String imageUrl) {
        if (source == null || TextUtils.isEmpty(imageUrl)) return source;
        Matcher path = Pattern.compile(
                "https?://cdn-msp[^/]*\\.18comic\\.vip/media/photos/(\\d+)/([^/?#]+)",
                Pattern.CASE_INSENSITIVE).matcher(imageUrl);
        Matcher scramble = Pattern.compile("[?&]scramble_id=(\\d+)").matcher(imageUrl);
        if (!path.find() || !scramble.find()) return source;
        long aid;
        long scrambleId;
        try {
            aid = Long.parseLong(path.group(1));
            scrambleId = Long.parseLong(scramble.group(1));
        } catch (NumberFormatException ignored) {
            return source;
        }
        int slices = jmScrambleSlices(aid, scrambleId, path.group(2));
        if (slices <= 1 || source.getHeight() < slices) return source;
        Bitmap.Config config = source.getConfig();
        if (config == null || (android.os.Build.VERSION.SDK_INT >= 26 && config == Bitmap.Config.HARDWARE)) config = Bitmap.Config.ARGB_8888;
        Bitmap restored = Bitmap.createBitmap(source.getWidth(), source.getHeight(), config);
        Canvas canvas = new Canvas(restored);
        for (int[] bound : jmSliceBounds(source.getHeight(), slices)) {
            canvas.drawBitmap(source,
                    new Rect(0, bound[0], source.getWidth(), bound[1]),
                    new Rect(0, bound[2], source.getWidth(), bound[3]), null);
        }
        source.recycle();
        return restored;
    }

    public static int[][] jmSliceBounds(int height, int slices) {
        int[][] bounds = new int[slices][4];
        int move = height / slices;
        int remainder = height % slices;
        int targetY = 0;
        for (int i = 0; i < slices; i++) {
            int sliceHeight = move + (i == 0 ? remainder : 0);
            int sourceY = height - targetY - sliceHeight;
            bounds[i] = new int[]{sourceY, sourceY + sliceHeight, targetY, targetY + sliceHeight};
            targetY += sliceHeight;
        }
        return bounds;
    }

    public static int jmScrambleSlices(long aid, long scrambleId, String fileName) {
        if (aid < scrambleId) return 0;
        if (aid < 268850L) return 10;
        try {
            String baseName = fileName == null ? "" : fileName;
            int extension = baseName.lastIndexOf('.');
            if (extension > 0) baseName = baseName.substring(0, extension);
            byte[] digest = MessageDigest.getInstance("MD5")
                    .digest((aid + baseName).getBytes("UTF-8"));
            StringBuilder hex = new StringBuilder(digest.length * 2);
            for (byte value : digest) hex.append(String.format(Locale.US, "%02x", value & 0xff));
            int divisor = aid >= 421926L ? 8 : 10;
            return hex.charAt(hex.length() - 1) % divisor * 2 + 2;
        } catch (Exception ignored) {
            return 0;
        }
    }

}
