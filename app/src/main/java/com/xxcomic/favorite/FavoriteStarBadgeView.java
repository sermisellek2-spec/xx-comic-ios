package com.xxcomic.favorite;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.View;

import com.xxcomic.UIHelpers;

public final class FavoriteStarBadgeView extends View {
    private final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path starPath = new Path();
    private float lastWidth = 0;
    private float lastHeight = 0;

    public FavoriteStarBadgeView(Context context) {
        super(context);
        init();
    }

    private void init() {
        setClickable(false);
        setFocusable(false);
        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setColor(UIHelpers.ACCENT);

        strokePaint.setStyle(Paint.Style.STROKE);
        strokePaint.setStrokeWidth(UIHelpers.dp(getContext(), 1));
        strokePaint.setColor(Color.argb(230, 255, 255, 255));
        strokePaint.setStrokeJoin(Paint.Join.ROUND);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int defaultSize = UIHelpers.dp(getContext(), 13);
        int w = resolveSize(defaultSize, widthMeasureSpec);
        int h = resolveSize(defaultSize, heightMeasureSpec);
        setMeasuredDimension(w, h);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float w = getWidth();
        float h = getHeight();
        if (w <= 0 || h <= 0) return;

        fillPaint.setColor(UIHelpers.ACCENT);

        if (w != lastWidth || h != lastHeight) {
            lastWidth = w;
            lastHeight = h;
            rebuildStarPath(w, h);
        }

        canvas.drawPath(starPath, fillPaint);
        canvas.drawPath(starPath, strokePaint);
    }

    private void rebuildStarPath(float w, float h) {
        starPath.reset();
        float strokeInset = strokePaint.getStrokeWidth() / 2f;
        float cx = w / 2f;
        float cy = h / 2f;
        float outerRadius = Math.min(cx, cy) - strokeInset;
        float innerRadius = outerRadius * 0.382f;

        for (int i = 0; i < 10; i++) {
            double angle = -Math.PI / 2.0 + i * (Math.PI / 5.0);
            float r = (i % 2 == 0) ? outerRadius : innerRadius;
            float x = (float) (cx + r * Math.cos(angle));
            float y = (float) (cy + r * Math.sin(angle));
            if (i == 0) {
                starPath.moveTo(x, y);
            } else {
                starPath.lineTo(x, y);
            }
        }
        starPath.close();
    }
}
