package com.xxcomic.reader;

import org.junit.Test;
import static org.junit.Assert.*;

public class WhiteMarginDetectorTest {

    private static int argb(int a, int r, int g, int b) {
        return ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
    }

    private static int white() {
        return argb(255, 255, 255, 255);
    }

    private static int nearWhite() {
        return argb(255, 248, 250, 246);
    }

    private static int black() {
        return argb(255, 0, 0, 0);
    }

    private static int[][] createSampleImage(int width, int height, int fill) {
        int[][] img = new int[height][width];
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                img[y][x] = fill;
            }
        }
        return img;
    }

    @Test
    public void nearWhiteDefinitionValidation() {
        // Pure white is near white
        assertTrue(WhiteMarginDetector.isNearWhite(white()));
        assertTrue(WhiteMarginDetector.isNearWhite(nearWhite()));

        // Exactly at boundary: min >= 245, max - min <= 10
        assertTrue(WhiteMarginDetector.isNearWhite(argb(255, 245, 250, 255)));

        // Component < 245 is NOT near white
        assertFalse(WhiteMarginDetector.isNearWhite(argb(255, 244, 255, 255)));

        // Alpha < 255 is NOT near white
        assertFalse(WhiteMarginDetector.isNearWhite(argb(240, 255, 255, 255)));
        assertFalse(WhiteMarginDetector.isNearWhite(argb(0, 255, 255, 255)));
    }

    @Test
    public void imageWithoutWhiteBordersIsNotCropped() {
        int[][] img = createSampleImage(100, 100, black());
        WhiteMarginDetector.ArrayPixelReader reader = new WhiteMarginDetector.ArrayPixelReader(img);
        WhiteMarginDetector.CropRect rect = WhiteMarginDetector.detect(reader, true);

        assertEquals(0, rect.left);
        assertEquals(0, rect.top);
        assertEquals(100, rect.right);
        assertEquals(100, rect.bottom);
        assertTrue(rect.isNoOp(100, 100));
    }

    @Test
    public void pureWhiteImageRollsBackToFullDimensions() {
        int[][] img = createSampleImage(100, 100, white());
        WhiteMarginDetector.ArrayPixelReader reader = new WhiteMarginDetector.ArrayPixelReader(img);
        WhiteMarginDetector.CropRect rect = WhiteMarginDetector.detect(reader, true);

        // Entire image is white -> exceeds 15% limit -> roll back
        assertEquals(0, rect.left);
        assertEquals(0, rect.top);
        assertEquals(100, rect.right);
        assertEquals(100, rect.bottom);
        assertTrue(rect.isNoOp(100, 100));
    }

    @Test
    public void cropsWhiteBordersWithSafetyMarginInFourDirections() {
        int width = 200;
        int height = 300;
        int[][] img = createSampleImage(width, height, white());

        // Inner content from x: 20 to 180, y: 30 to 270 is black
        // 20px / 200 = 10% (under 15% limit)
        // 30px / 300 = 10% (under 15% limit)
        for (int y = 30; y < 270; y++) {
            for (int x = 20; x < 180; x++) {
                img[y][x] = black();
            }
        }

        WhiteMarginDetector.ArrayPixelReader reader = new WhiteMarginDetector.ArrayPixelReader(img);
        WhiteMarginDetector.CropRect rect = WhiteMarginDetector.detect(reader, true);

        // Safety margin:
        // safetyX = max(2, round(200 * 0.003)) = 2
        // safetyY = max(2, round(300 * 0.003)) = 2
        // Content starts at left = 20 -> safety: 20 - 2 = 18
        // Content ends at right = 180 -> safety: 180 + 2 = 182
        // Content starts at top = 30 -> safety: 30 - 2 = 28
        // Content ends at bottom = 270 -> safety: 270 + 2 = 272
        assertEquals(18, rect.left);
        assertEquals(28, rect.top);
        assertEquals(182, rect.right);
        assertEquals(272, rect.bottom);
    }

    @Test
    public void continuousScrollModeOnlyCropsLeftAndRight() {
        int width = 200;
        int height = 300;
        int[][] img = createSampleImage(width, height, white());

        for (int y = 30; y < 270; y++) {
            for (int x = 20; x < 180; x++) {
                img[y][x] = black();
            }
        }

        WhiteMarginDetector.ArrayPixelReader reader = new WhiteMarginDetector.ArrayPixelReader(img);
        // cropVertical = false for scroll mode
        WhiteMarginDetector.CropRect rect = WhiteMarginDetector.detect(reader, false);

        assertEquals(18, rect.left);
        assertEquals(0, rect.top); // Top is NOT cropped
        assertEquals(182, rect.right);
        assertEquals(300, rect.bottom); // Bottom is NOT cropped
    }

    @Test
    public void borderAbove15PercentRollsBackThatSide() {
        int width = 200;
        int height = 200;
        int[][] img = createSampleImage(width, height, white());

        // Left white border is 40px (40 / 200 = 20% > 15%)
        // Right white border is 10px (10 / 200 = 5% <= 15%)
        for (int y = 0; y < height; y++) {
            for (int x = 40; x < 190; x++) {
                img[y][x] = black();
            }
        }

        WhiteMarginDetector.ArrayPixelReader reader = new WhiteMarginDetector.ArrayPixelReader(img);
        WhiteMarginDetector.CropRect rect = WhiteMarginDetector.detect(reader, false);

        // Left exceeded 15% (maxCropX is 30) -> left rolls back to 0
        assertEquals(0, rect.left);
        // Right is 190, safety margin = 2 -> 192
        assertEquals(192, rect.right);
    }

    @Test
    public void fineTextOrPageNumberStopsCrop() {
        int width = 200;
        int height = 200;
        int[][] img = createSampleImage(width, height, white());

        // A single pixel page number at column 5
        img[100][5] = black();

        // Main content starts at column 25
        for (int y = 20; y < 180; y++) {
            for (int x = 25; x < 180; x++) {
                img[y][x] = black();
            }
        }

        WhiteMarginDetector.ArrayPixelReader reader = new WhiteMarginDetector.ArrayPixelReader(img);
        WhiteMarginDetector.CropRect rect = WhiteMarginDetector.detect(reader, false);

        // Because column 5 contains a non-white pixel, left scan stops at column 5!
        // Safety margin: 5 - 2 = 3
        assertEquals(3, rect.left);
    }

    @Test
    public void buildCacheKeyFormatting() {
        assertEquals("https://example.com/1.jpg|1000x1500|scroll",
                WhiteMarginDetector.buildCacheKey("https://example.com/1.jpg", 1000, 1500, true));
        assertEquals("https://example.com/1.jpg|1000x1500|paged",
                WhiteMarginDetector.buildCacheKey("https://example.com/1.jpg", 1000, 1500, false));
        assertEquals("|800x1200|paged",
                WhiteMarginDetector.buildCacheKey(null, 800, 1200, false));
    }

    @Test
    public void cropRectValidityCheck() {
        WhiteMarginDetector.CropRect valid = new WhiteMarginDetector.CropRect(10, 20, 190, 280);
        assertTrue(valid.isValid(200, 300));

        // Exactly full size
        assertTrue(new WhiteMarginDetector.CropRect(0, 0, 200, 300).isValid(200, 300));

        // Negative left / top
        assertFalse(new WhiteMarginDetector.CropRect(-1, 0, 200, 300).isValid(200, 300));
        assertFalse(new WhiteMarginDetector.CropRect(0, -1, 200, 300).isValid(200, 300));

        // Exceeding width / height
        assertFalse(new WhiteMarginDetector.CropRect(0, 0, 201, 300).isValid(200, 300));
        assertFalse(new WhiteMarginDetector.CropRect(0, 0, 200, 301).isValid(200, 300));

        // Inverted or degenerate bounds
        assertFalse(new WhiteMarginDetector.CropRect(100, 0, 100, 300).isValid(200, 300));
        assertFalse(new WhiteMarginDetector.CropRect(150, 0, 100, 300).isValid(200, 300));
        assertFalse(new WhiteMarginDetector.CropRect(0, 150, 200, 150).isValid(200, 300));
        assertFalse(new WhiteMarginDetector.CropRect(0, 200, 200, 100).isValid(200, 300));
    }

    @Test
    public void cropRectDimensionsAndProperties() {
        WhiteMarginDetector.CropRect rect = new WhiteMarginDetector.CropRect(10, 20, 110, 220);
        assertEquals(100, rect.width());
        assertEquals(200, rect.height());
        assertEquals(10, rect.left);
        assertEquals(20, rect.top);
        assertEquals(110, rect.right);
        assertEquals(220, rect.bottom);
        assertFalse(rect.isNoOp(110, 220));
        assertTrue(new WhiteMarginDetector.CropRect(0, 0, 100, 200).isNoOp(100, 200));
    }
}
