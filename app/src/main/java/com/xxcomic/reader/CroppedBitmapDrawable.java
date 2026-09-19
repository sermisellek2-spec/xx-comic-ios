package com.xxcomic.reader;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;

public class CroppedBitmapDrawable extends Drawable {
    private final Bitmap bitmap;
    private final Rect srcRect;
    private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.DITHER_FLAG);

    public CroppedBitmapDrawable(Bitmap bitmap, Rect srcRect) {
        this.bitmap = bitmap;
        if (srcRect != null) {
            this.srcRect = new Rect(srcRect);
        } else if (bitmap != null) {
            this.srcRect = new Rect(0, 0, bitmap.getWidth(), bitmap.getHeight());
        } else {
            this.srcRect = new Rect(0, 0, 1, 1);
        }
    }

    public Bitmap getBitmap() {
        return bitmap;
    }

    public Rect getSrcRect() {
        return srcRect;
    }

    @Override
    public int getIntrinsicWidth() {
        return Math.max(1, srcRect.width());
    }

    @Override
    public int getIntrinsicHeight() {
        return Math.max(1, srcRect.height());
    }

    @Override
    public void draw(Canvas canvas) {
        if (bitmap == null || bitmap.isRecycled()) return;
        Rect dstRect = getBounds();
        canvas.drawBitmap(bitmap, srcRect, dstRect, paint);
    }

    @Override
    public void setAlpha(int alpha) {
        paint.setAlpha(alpha);
        invalidateSelf();
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {
        paint.setColorFilter(colorFilter);
        invalidateSelf();
    }

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }
}
