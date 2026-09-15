package com.xxcomic.reader;

import android.content.Context;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.widget.ImageView;

/** Full-page image: fit without cropping, pinch/double-tap zoom, then pan. */
public final class ZoomImageView extends ImageView {
    public interface Listener {
        void onTap(float x, float y);
        void onZoomChanged(boolean zoomed);
    }
    private final Matrix matrix = new Matrix();
    private final RectF bounds = new RectF();
    private final GestureDetector taps;
    private final ScaleGestureDetector scales;
    private float zoom = 1f, lastX, lastY;
    private boolean multiTouch;
    private Listener listener;

    public ZoomImageView(Context context) {
        super(context);
        super.setScaleType(ScaleType.MATRIX);
        taps = new GestureDetector(context, new GestureDetector.SimpleOnGestureListener() {
            @Override public boolean onDown(MotionEvent e) { return true; }
            @Override public boolean onSingleTapConfirmed(MotionEvent e) {
                if (listener != null && !multiTouch) listener.onTap(e.getX(), e.getY());
                performClick();
                return true;
            }
            @Override public boolean onDoubleTap(MotionEvent e) {
                if (isZoomed()) resetZoom(); else scaleBy(2.5f, e.getX(), e.getY());
                return true;
            }
        });
        taps.setIsLongpressEnabled(false);
        scales = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScaleBegin(ScaleGestureDetector detector) {
                getParent().requestDisallowInterceptTouchEvent(true);
                return true;
            }
            @Override public boolean onScale(ScaleGestureDetector detector) {
                scaleBy(detector.getScaleFactor(), detector.getFocusX(), detector.getFocusY());
                return true;
            }
        });
    }

    public void setListener(Listener listener) { this.listener = listener; }
    public boolean isZoomed() { return zoom > 1.01f; }
    @Override public void setScaleType(ScaleType type) { super.setScaleType(ScaleType.MATRIX); }
    @Override public void setImageDrawable(Drawable drawable) {
        super.setImageDrawable(drawable);
        if (matrix != null) resetZoom();
    }
    @Override protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        resetZoom();
    }
    public void resetZoom() {
        zoom = 1f;
        Drawable drawable = getDrawable();
        if (drawable != null && drawable.getIntrinsicWidth() > 0 && drawable.getIntrinsicHeight() > 0 && getWidth() > 0 && getHeight() > 0) {
            matrix.setRectToRect(new RectF(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight()),
                    new RectF(0, 0, getWidth(), getHeight()), Matrix.ScaleToFit.CENTER);
            setImageMatrix(matrix);
        }
        if (listener != null) listener.onZoomChanged(false);
    }
    private void scaleBy(float factor, float x, float y) {
        if (getDrawable() == null) return;
        float next = Math.max(1f, Math.min(4f, zoom * factor));
        matrix.postScale(next / zoom, next / zoom, x, y);
        zoom = next;
        constrain();
        if (listener != null) listener.onZoomChanged(isZoomed());
    }
    private void constrain() {
        Drawable drawable = getDrawable();
        if (drawable == null) return;
        bounds.set(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight());
        matrix.mapRect(bounds);
        float dx = bounds.width() <= getWidth() ? (getWidth() - bounds.width()) / 2 - bounds.left
                : bounds.left > 0 ? -bounds.left : bounds.right < getWidth() ? getWidth() - bounds.right : 0;
        float dy = bounds.height() <= getHeight() ? (getHeight() - bounds.height()) / 2 - bounds.top
                : bounds.top > 0 ? -bounds.top : bounds.bottom < getHeight() ? getHeight() - bounds.bottom : 0;
        matrix.postTranslate(dx, dy);
        setImageMatrix(matrix);
    }
    @Override public boolean onTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            multiTouch = false;
            lastX = event.getX(); lastY = event.getY();
        }
        if (event.getPointerCount() > 1) multiTouch = true;
        if (getParent() != null && (isZoomed() || multiTouch)) getParent().requestDisallowInterceptTouchEvent(true);
        scales.onTouchEvent(event);
        taps.onTouchEvent(event);
        if (event.getActionMasked() == MotionEvent.ACTION_MOVE && isZoomed() && !scales.isInProgress() && event.getPointerCount() == 1) {
            matrix.postTranslate(event.getX() - lastX, event.getY() - lastY);
            constrain();
        }
        lastX = event.getX(); lastY = event.getY();
        return true;
    }
    @Override public boolean performClick() { super.performClick(); return true; }
}
