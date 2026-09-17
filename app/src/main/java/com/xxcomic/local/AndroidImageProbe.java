package com.xxcomic.local;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.IOException;
import java.io.InputStream;

/** Native image validation; archive traversal and byte limits remain platform independent. */
final class AndroidImageProbe implements ArchiveIndex.ImageProbe {
    @Override public boolean isReadable(ArchiveIndex.InputStreamSupplier source) throws IOException {
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        try (InputStream in = source.open()) {
            BitmapFactory.decodeStream(in, null, options);
        }
        if (options.outWidth <= 0 || options.outHeight <= 0) return false;
        options.inJustDecodeBounds = false;
        options.inSampleSize = 1;
        while (Math.max(options.outWidth, options.outHeight) / options.inSampleSize > 256) {
            options.inSampleSize *= 2;
        }
        try (InputStream in = source.open()) {
            Bitmap bitmap = BitmapFactory.decodeStream(in, null, options);
            if (bitmap == null) return false;
            bitmap.recycle();
            return true;
        } catch (OutOfMemoryError error) {
            throw new IOException("图片尺寸过大，无法安全解析", error);
        }
    }
}
