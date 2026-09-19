package com.xxcomic.reader;

import android.graphics.Bitmap;
import android.os.Build;

public final class WhiteMarginDetector {

    public static final float MAX_CROP_RATIO = 0.15f;
    public static final float SAFETY_MARGIN_RATIO = 0.003f;
    public static final int MIN_SAFETY_MARGIN_PX = 2;
    public static final int NEAR_WHITE_MIN_COMPONENT = 245;
    public static final int NEAR_WHITE_MAX_DELTA = 10;

    public interface PixelReader {
        int getPixel(int x, int y);
        int getWidth();
        int getHeight();
    }

    public static class CropRect {
        public final int left;
        public final int top;
        public final int right;
        public final int bottom;

        public CropRect(int left, int top, int right, int bottom) {
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
        }

        public int width() {
            return Math.max(1, right - left);
        }

        public int height() {
            return Math.max(1, bottom - top);
        }

        public boolean isNoOp(int origWidth, int origHeight) {
            return left == 0 && top == 0 && right == origWidth && bottom == origHeight;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            CropRect cropRect = (CropRect) o;
            return left == cropRect.left && top == cropRect.top &&
                    right == cropRect.right && bottom == cropRect.bottom;
        }

        @Override
        public int hashCode() {
            int result = left;
            result = 31 * result + top;
            result = 31 * result + right;
            result = 31 * result + bottom;
            return result;
        }

        @Override
        public String toString() {
            return "CropRect{" + left + "," + top + "," + right + "," + bottom + "}";
        }
    }

    public static class BitmapPixelReader implements PixelReader {
        private final Bitmap bitmap;
        private final int width;
        private final int height;

        public BitmapPixelReader(Bitmap bitmap) {
            this.bitmap = bitmap;
            this.width = bitmap != null ? bitmap.getWidth() : 0;
            this.height = bitmap != null ? bitmap.getHeight() : 0;
        }

        @Override
        public int getPixel(int x, int y) {
            return bitmap.getPixel(x, y);
        }

        @Override
        public int getWidth() {
            return width;
        }

        @Override
        public int getHeight() {
            return height;
        }
    }

    public static class ArrayPixelReader implements PixelReader {
        private final int[][] pixels;
        private final int width;
        private final int height;

        public ArrayPixelReader(int[][] pixels) {
            this.pixels = pixels;
            this.height = pixels != null ? pixels.length : 0;
            this.width = (pixels != null && pixels.length > 0 && pixels[0] != null) ? pixels[0].length : 0;
        }

        @Override
        public int getPixel(int x, int y) {
            if (pixels == null || y < 0 || y >= height || x < 0 || x >= width) return 0;
            return pixels[y][x];
        }

        @Override
        public int getWidth() {
            return width;
        }

        @Override
        public int getHeight() {
            return height;
        }
    }

    public static boolean isNearWhite(int pixel) {
        int a = (pixel >>> 24) & 0xFF;
        if (a != 255) return false;
        int r = (pixel >> 16) & 0xFF;
        int g = (pixel >> 8) & 0xFF;
        int b = pixel & 0xFF;
        int min = Math.min(r, Math.min(g, b));
        int max = Math.max(r, Math.max(g, b));
        return min >= NEAR_WHITE_MIN_COMPONENT && (max - min) <= NEAR_WHITE_MAX_DELTA;
    }

    public static CropRect detect(Bitmap bitmap, boolean cropVertical) {
        if (bitmap == null || bitmap.isRecycled() || bitmap.getWidth() < 10 || bitmap.getHeight() < 10) {
            int w = bitmap != null ? bitmap.getWidth() : 1;
            int h = bitmap != null ? bitmap.getHeight() : 1;
            return new CropRect(0, 0, w, h);
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (bitmap.getConfig() == Bitmap.Config.HARDWARE) {
                    return new CropRect(0, 0, bitmap.getWidth(), bitmap.getHeight());
                }
            }
            return detect(new BitmapPixelReader(bitmap), cropVertical);
        } catch (Exception ignored) {
            return new CropRect(0, 0, bitmap.getWidth(), bitmap.getHeight());
        }
    }

    public static CropRect detect(PixelReader reader, boolean cropVertical) {
        if (reader == null) return new CropRect(0, 0, 1, 1);
        int width = reader.getWidth();
        int height = reader.getHeight();
        if (width < 10 || height < 10) {
            return new CropRect(0, 0, width, height);
        }

        int maxCropX = (int) (width * MAX_CROP_RATIO);
        int maxCropY = (int) (height * MAX_CROP_RATIO);

        int top = 0;
        int bottom = height;

        if (cropVertical) {
            // Scan top
            for (int y = 0; y < maxCropY; y++) {
                boolean allWhite = true;
                for (int x = 0; x < width; x++) {
                    if (!isNearWhite(reader.getPixel(x, y))) {
                        allWhite = false;
                        break;
                    }
                }
                if (allWhite) {
                    top = y + 1;
                } else {
                    break;
                }
            }
            if (top >= maxCropY) {
                // Reached max limit without finding content, rollback this axis
                top = 0;
            }

            // Scan bottom
            for (int y = height - 1; y >= height - maxCropY; y--) {
                boolean allWhite = true;
                for (int x = 0; x < width; x++) {
                    if (!isNearWhite(reader.getPixel(x, y))) {
                        allWhite = false;
                        break;
                    }
                }
                if (allWhite) {
                    bottom = y;
                } else {
                    break;
                }
            }
            if (height - bottom >= maxCropY) {
                bottom = height;
            }
        }

        // Scan left
        int left = 0;
        for (int x = 0; x < maxCropX; x++) {
            boolean allWhite = true;
            for (int y = 0; y < height; y++) {
                if (!isNearWhite(reader.getPixel(x, y))) {
                    allWhite = false;
                    break;
                }
            }
            if (allWhite) {
                left = x + 1;
            } else {
                break;
            }
        }
        if (left >= maxCropX) {
            left = 0;
        }

        // Scan right
        int right = width;
        for (int x = width - 1; x >= width - maxCropX; x--) {
            boolean allWhite = true;
            for (int y = 0; y < height; y++) {
                if (!isNearWhite(reader.getPixel(x, y))) {
                    allWhite = false;
                    break;
                }
            }
            if (allWhite) {
                right = x;
            } else {
                break;
            }
        }
        if (width - right >= maxCropX) {
            right = width;
        }

        // Apply safety margins
        int safetyX = Math.max(MIN_SAFETY_MARGIN_PX, (int) Math.round(width * SAFETY_MARGIN_RATIO));
        int safetyY = Math.max(MIN_SAFETY_MARGIN_PX, (int) Math.round(height * SAFETY_MARGIN_RATIO));

        if (left > 0) {
            left = Math.max(0, left - safetyX);
        }
        if (right < width) {
            right = Math.min(width, right + safetyX);
        }
        if (cropVertical) {
            if (top > 0) {
                top = Math.max(0, top - safetyY);
            }
            if (bottom < height) {
                bottom = Math.min(height, bottom + safetyY);
            }
        }

        if (right <= left || bottom <= top) {
            return new CropRect(0, 0, width, height);
        }

        return new CropRect(left, top, right, bottom);
    }
}
