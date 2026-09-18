package com.xxcomic.reader;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.animation.DecelerateInterpolator;
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
    private float zoom = 1f, lastX, lastY, lastFocusX, lastFocusY;
    private boolean multiTouch, notifiedZoomed;
    private boolean pinchZoomEnabled = true;
    private Listener listener;
    private ValueAnimator zoomAnimator;

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
                if (!pinchZoomEnabled) return true;
                if (isZoomed()) {
                    animateZoomTo(1f, getWidth() / 2f, getHeight() / 2f);
                } else {
                    animateZoomTo(2.4f, e.getX(), e.getY());
                }
                return true;
            }
        });
        taps.setIsLongpressEnabled(false);
        scales = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScaleBegin(ScaleGestureDetector detector) {
                if (!pinchZoomEnabled) return false;
                cancelAnimation();
                lastFocusX = detector.getFocusX();
                lastFocusY = detector.getFocusY();
                if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(true);
                return true;
            }
            @Override public boolean onScale(ScaleGestureDetector detector) {
                if (!pinchZoomEnabled) return false;
                float focusX = detector.getFocusX();
                float focusY = detector.getFocusY();
                float dx = focusX - lastFocusX;
                float dy = focusY - lastFocusY;
                lastFocusX = focusX;
                lastFocusY = focusY;
                scaleBy(detector.getScaleFactor(), focusX, focusY, dx, dy);
                return true;
            }
        });
        scales.setQuickScaleEnabled(false);
    }

    public void setPinchZoomEnabled(boolean enabled) {
        this.pinchZoomEnabled = enabled;
        if (!enabled) resetZoom();
    }

    public boolean isPinchZoomEnabled() {
        return pinchZoomEnabled;
    }

    public void setListener(Listener listener) {
        this.listener = listener;
        notifiedZoomed = isZoomed();
        if (listener != null) listener.onZoomChanged(notifiedZoomed);
    }
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
        cancelAnimation();
        zoom = 1f;
        Drawable drawable = getDrawable();
        if (drawable != null && drawable.getIntrinsicWidth() > 0 && drawable.getIntrinsicHeight() > 0 && getWidth() > 0 && getHeight() > 0) {
            matrix.setRectToRect(new RectF(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight()),
                    new RectF(0, 0, getWidth(), getHeight()), Matrix.ScaleToFit.CENTER);
            setImageMatrix(matrix);
        }
        notifyZoomChanged();
    }

    private void cancelAnimation() {
        if (zoomAnimator == null) return;
        ValueAnimator running = zoomAnimator;
        zoomAnimator = null;
        running.removeAllListeners();
        running.cancel();
    }

    private void notifyZoomChanged() {
        boolean zoomed = isZoomed();
        if (notifiedZoomed == zoomed) return;
        notifiedZoomed = zoomed;
        if (listener != null) listener.onZoomChanged(zoomed);
    }

    private void animateZoomTo(float targetZoom, float focusX, float focusY) {
        cancelAnimation();
        if (getDrawable() == null) return;
        float startZoom = zoom;
        Matrix start = new Matrix(matrix);
        if (targetZoom <= 1.01f) {
            Drawable drawable = getDrawable();
            matrix.setRectToRect(new RectF(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight()),
                    new RectF(0, 0, getWidth(), getHeight()), Matrix.ScaleToFit.CENTER);
        } else {
            matrix.postScale(targetZoom / zoom, targetZoom / zoom, focusX, focusY);
            constrain(true);
        }
        float[] from = new float[9], to = new float[9], frame = new float[9];
        start.getValues(from);
        matrix.getValues(to);
        matrix.set(start);
        setImageMatrix(matrix);
        zoomAnimator = ValueAnimator.ofFloat(0f, 1f);
        zoomAnimator.setDuration(220);
        zoomAnimator.setInterpolator(new DecelerateInterpolator());
        zoomAnimator.addUpdateListener(a -> {
            float progress = (float) a.getAnimatedValue();
            for (int i = 0; i < frame.length; i++) frame[i] = from[i] + (to[i] - from[i]) * progress;
            matrix.setValues(frame);
            zoom = startZoom + (targetZoom - startZoom) * progress;
            setImageMatrix(matrix);
            notifyZoomChanged();
        });
        zoomAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                zoomAnimator = null;
            }
        });
        zoomAnimator.start();
    }

    private void scaleBy(float factor, float focusX, float focusY, float deltaX, float deltaY) {
        if (getDrawable() == null) return;
        float next = Math.max(0.75f, Math.min(4.5f, zoom * factor));
        float scaleRatio = next / zoom;
        matrix.postScale(scaleRatio, scaleRatio, focusX - deltaX, focusY - deltaY);
        matrix.postTranslate(deltaX, deltaY);
        zoom = next;
        constrain(false);
        notifyZoomChanged();
    }

    private void constrain(boolean hardClamp) {
        Drawable drawable = getDrawable();
        if (drawable == null) return;
        bounds.set(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight());
        matrix.mapRect(bounds);

        float viewW = getWidth();
        float viewH = getHeight();
        if (viewW <= 0 || viewH <= 0) return;

        float dx = ZoomGeometry.correction(bounds.left, bounds.width(), viewW, hardClamp ? 0 : viewW * .2f);
        float dy = ZoomGeometry.correction(bounds.top, bounds.height(), viewH, hardClamp ? 0 : viewH * .2f);

        if (dx != 0 || dy != 0) {
            matrix.postTranslate(dx, dy);
        }
        setImageMatrix(matrix);
    }

    private void animateBoundsCorrection() {
        Drawable drawable = getDrawable();
        if (drawable == null || (zoomAnimator != null && zoomAnimator.isRunning())) return;
        bounds.set(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight());
        matrix.mapRect(bounds);

        float viewW = getWidth();
        float viewH = getHeight();
        if (viewW <= 0 || viewH <= 0) return;

        float dx = ZoomGeometry.correction(bounds.left, bounds.width(), viewW, 0);
        float dy = ZoomGeometry.correction(bounds.top, bounds.height(), viewH, 0);

        if (Math.abs(dx) > 0.5f || Math.abs(dy) > 0.5f) {
            final float targetDx = dx;
            final float targetDy = dy;
            ValueAnimator snap = ValueAnimator.ofFloat(0f, 1f);
            zoomAnimator = snap;
            snap.setDuration(180);
            snap.setInterpolator(new DecelerateInterpolator());
            final float[] lastProgress = new float[]{0f};
            snap.addUpdateListener(a -> {
                float p = (float) a.getAnimatedValue();
                float dp = p - lastProgress[0];
                lastProgress[0] = p;
                matrix.postTranslate(targetDx * dp, targetDy * dp);
                setImageMatrix(matrix);
            });
            snap.addListener(new AnimatorListenerAdapter() {
                @Override public void onAnimationEnd(Animator animation) { zoomAnimator = null; }
            });
            snap.start();
        }
    }

    @Override public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            cancelAnimation();
            multiTouch = false;
            lastX = event.getX(); lastY = event.getY();
        }
        if (action == MotionEvent.ACTION_POINTER_DOWN) {
            cancelAnimation();
            multiTouch = true;
        }
        if (action == MotionEvent.ACTION_POINTER_UP) {
            int actionIndex = event.getActionIndex();
            int newIndex = actionIndex == 0 ? 1 : 0;
            if (newIndex < event.getPointerCount()) {
                lastX = event.getX(newIndex);
                lastY = event.getY(newIndex);
            }
        }
        if (pinchZoomEnabled && event.getPointerCount() > 1) multiTouch = true;
        if (getParent() != null && (isZoomed() || (pinchZoomEnabled && multiTouch))) getParent().requestDisallowInterceptTouchEvent(true);
        if (pinchZoomEnabled) scales.onTouchEvent(event);
        taps.onTouchEvent(event);
        if (action == MotionEvent.ACTION_MOVE && zoomAnimator != null && zoomAnimator.isRunning()) {
            lastX = event.getX(); lastY = event.getY();
            return true;
        }
        if (action == MotionEvent.ACTION_MOVE && isZoomed() && (!pinchZoomEnabled || !scales.isInProgress()) && event.getPointerCount() == 1) {
            matrix.postTranslate(event.getX() - lastX, event.getY() - lastY);
            constrain(false);
        }
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            if (zoomAnimator != null && zoomAnimator.isRunning()) return true;
            if (zoom < 1.02f) {
                animateZoomTo(1f, getWidth() / 2f, getHeight() / 2f);
            } else {
                animateBoundsCorrection();
            }
        }
        if (action != MotionEvent.ACTION_POINTER_UP) {
            lastX = event.getX(); lastY = event.getY();
        }
        return true;
    }
    @Override protected void onDetachedFromWindow() {
        cancelAnimation();
        super.onDetachedFromWindow();
    }
    @Override public boolean performClick() { super.performClick(); return true; }
}
