package com.xxcomic;

import android.app.Activity;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Rect;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Space;
import android.widget.TextView;

import java.util.Calendar;

public final class UIHelpers {
    private UIHelpers() {
    }

    public static int BG = Color.rgb(241, 249, 254);
    public static int SURFACE = Color.rgb(227, 243, 252);
    public static int CARD = Color.rgb(255, 255, 255);
    public static int CARD_SOFT = Color.rgb(243, 249, 255);
    public static int TEXT = Color.rgb(20, 40, 58);
    public static int TEXT2 = Color.rgb(76, 105, 127);
    public static int TEXT3 = Color.rgb(108, 132, 152);
    public static int TEXT4 = Color.rgb(177, 193, 208);
    public static int BORDER = Color.rgb(207, 229, 243);
    public static int BORDER_SOFT = Color.rgb(225, 239, 250);
    public static int ACCENT = Color.rgb(43, 152, 217);
    public static int ON_ACCENT = Color.rgb(255, 255, 255);
    public static int ACCENT_SOFT = Color.rgb(226, 243, 255);
    public static int BRAND = Color.rgb(43, 152, 217);
    public static int PLACEHOLDER = Color.rgb(224, 239, 250);
    public static int READER_TEXT = Color.rgb(235, 246, 255);
    public static int ACCENT_LIGHT = Color.rgb(226, 243, 255);
    public static int ACCENT_DARK = Color.rgb(22, 123, 185);
    public static int GREEN = Color.rgb(68, 161, 133);
    public static int GREEN_LIGHT = Color.rgb(226, 247, 240);
    public static int DANGER = Color.rgb(200, 69, 69);
    public static int STATUS_SERIAL = Color.rgb(68, 161, 133);
    public static int STATUS_COMPLETE = Color.rgb(133, 153, 173);
    public static int STATUS_NEW = Color.rgb(86, 166, 229);
    public static int DARK = Color.rgb(16, 24, 34);
    public static int DARK_BAR = Color.rgb(10, 17, 26);
    private static boolean nightTheme = false;

    public static boolean applyAutoTheme() {
        Calendar now = Calendar.getInstance();
        boolean night = now.get(Calendar.HOUR_OF_DAY) < 8 || now.get(Calendar.HOUR_OF_DAY) >= 18;
        if (night) applyNightTheme(); else applyDayTheme();
        return nightTheme;
    }

    public static boolean applyTheme(boolean night) {
        if (night) applyNightTheme(); else applyDayTheme();
        return nightTheme;
    }

    public static boolean isNightTheme() {
        return nightTheme;
    }

    public static boolean isSystemNightMode(Context context) {
        if (context == null) return false;
        int nightModeFlags = context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return nightModeFlags == Configuration.UI_MODE_NIGHT_YES;
    }

    public static long nextThemeSwitchDelayMs() {
        Calendar now = Calendar.getInstance();
        Calendar next = (Calendar) now.clone();
        int hour = now.get(Calendar.HOUR_OF_DAY);
        if (hour < 8) {
            next.set(Calendar.HOUR_OF_DAY, 8);
        } else if (hour < 18) {
            next.set(Calendar.HOUR_OF_DAY, 18);
        } else {
            next.add(Calendar.DAY_OF_YEAR, 1);
            next.set(Calendar.HOUR_OF_DAY, 8);
        }
        next.set(Calendar.MINUTE, 0);
        next.set(Calendar.SECOND, 0);
        next.set(Calendar.MILLISECOND, 0);
        return Math.max(1000L, next.getTimeInMillis() - now.getTimeInMillis());
    }

    private static void applyDayTheme() {
        nightTheme = false;
        BG = Color.rgb(241, 249, 254);
        SURFACE = Color.rgb(227, 243, 252);
        CARD = Color.rgb(255, 255, 255);
        CARD_SOFT = Color.rgb(243, 249, 255);
        TEXT = Color.rgb(20, 40, 58);
        TEXT2 = Color.rgb(76, 105, 127);
        TEXT3 = Color.rgb(108, 132, 152);
        TEXT4 = Color.rgb(177, 193, 208);
        BORDER = Color.rgb(207, 229, 243);
        BORDER_SOFT = Color.rgb(225, 239, 250);
        ACCENT = Color.rgb(43, 152, 217);
        ON_ACCENT = Color.rgb(255, 255, 255);
        BRAND = Color.rgb(43, 152, 217);
        PLACEHOLDER = Color.rgb(224, 239, 250);
        READER_TEXT = Color.rgb(235, 246, 255);
        ACCENT_LIGHT = Color.rgb(226, 243, 255);
        ACCENT_SOFT = Color.rgb(226, 243, 255);
        ACCENT_DARK = Color.rgb(22, 123, 185);
        GREEN = Color.rgb(68, 161, 133);
        GREEN_LIGHT = Color.rgb(226, 247, 240);
        DANGER = Color.rgb(200, 69, 69);
        STATUS_SERIAL = Color.rgb(68, 161, 133);
        STATUS_COMPLETE = Color.rgb(133, 153, 173);
        STATUS_NEW = Color.rgb(86, 166, 229);
        DARK = Color.rgb(16, 24, 34);
        DARK_BAR = Color.rgb(10, 17, 26);
    }

    private static void applyNightTheme() {
        nightTheme = true;
        BG = Color.rgb(18, 27, 38);
        SURFACE = Color.rgb(24, 38, 53);
        CARD = Color.rgb(29, 45, 62);
        CARD_SOFT = Color.rgb(26, 41, 57);
        TEXT = Color.rgb(232, 244, 253);
        TEXT2 = Color.rgb(184, 207, 225);
        TEXT3 = Color.rgb(128, 158, 183);
        TEXT4 = Color.rgb(82, 110, 135);
        BORDER = Color.rgb(47, 70, 91);
        BORDER_SOFT = Color.rgb(37, 57, 76);
        ACCENT = Color.rgb(106, 184, 243);
        ON_ACCENT = Color.rgb(10, 24, 37);
        BRAND = Color.rgb(106, 184, 243);
        PLACEHOLDER = Color.rgb(42, 63, 82);
        READER_TEXT = Color.rgb(235, 246, 255);
        ACCENT_LIGHT = Color.rgb(37, 63, 84);
        ACCENT_SOFT = Color.rgb(37, 63, 84);
        ACCENT_DARK = Color.rgb(180, 224, 255);
        GREEN = Color.rgb(91, 190, 157);
        GREEN_LIGHT = Color.rgb(25, 63, 55);
        DANGER = Color.rgb(200, 69, 69);
        STATUS_SERIAL = Color.rgb(91, 190, 157);
        STATUS_COMPLETE = Color.rgb(128, 158, 183);
        STATUS_NEW = Color.rgb(106, 184, 243);
        DARK = Color.rgb(12, 19, 28);
        DARK_BAR = Color.rgb(7, 13, 20);
    }

    public static TextView text(Activity ctx, String value, int sp, int color, int style) {
        TextView tv = new TextView(ctx);
        tv.setText(value);
        tv.setTextSize(sp);
        tv.setTextColor(color);
        tv.setTypeface(Typeface.DEFAULT, style);
        tv.setIncludeFontPadding(true);
        return tv;
    }

    public static GradientDrawable round(int color, int radius, int stroke) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radius);
        if (stroke != Color.TRANSPARENT) drawable.setStroke(1, stroke);
        return drawable;
    }

    public static GradientDrawable round(int color, int radius, int strokeColor, int strokeWidth) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radius);
        if (strokeColor != Color.TRANSPARENT && strokeWidth > 0) drawable.setStroke(strokeWidth, strokeColor);
        return drawable;
    }

    public static Drawable paperTexture(Activity ctx) {
        final int step = dp(ctx, 8);
        return new Drawable() {
            private final Paint bgPaint = new Paint();
            private final Paint linePaint = new Paint();
            {
                bgPaint.setColor(PLACEHOLDER);
                linePaint.setColor(Color.argb(13, 0, 0, 0));
                linePaint.setStrokeWidth(0.5f);
                linePaint.setAntiAlias(true);
            }
            @Override
            public void draw(Canvas canvas) {
                Rect b = getBounds();
                canvas.drawRect(b, bgPaint);
                int h = b.height(), w = b.width();
                for (int x = -h; x < w + h; x += step) {
                    canvas.drawLine(x, 0, x + h, h, linePaint);
                }
            }
            @Override public void setAlpha(int alpha) { }
            @Override public void setColorFilter(android.graphics.ColorFilter colorFilter) { }
            @Override public int getOpacity() { return android.graphics.PixelFormat.OPAQUE; }
        };
    }

    public static View coverPlaceholder(Activity ctx, String title) {
        FrameLayout frame = new FrameLayout(ctx);
        GradientDrawable bg = round(PLACEHOLDER, dp(ctx, 8), Color.TRANSPARENT);
        Drawable texture = paperTexture(ctx);
        android.graphics.drawable.LayerDrawable layers = new android.graphics.drawable.LayerDrawable(new Drawable[]{ bg, texture });
        frame.setBackground(layers);
        char first = (title == null || title.isEmpty()) ? '·' : title.charAt(0);
        TextView tv = new TextView(ctx);
        tv.setText(String.valueOf(first));
        tv.setTypeface(Typeface.SERIF);
        tv.setTextSize(32);
        tv.setTextColor(TEXT3);
        tv.setGravity(Gravity.CENTER);
        frame.addView(tv, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT));
        return frame;
    }

    public static final class StatusDotView extends View {
        private int color = Color.TRANSPARENT;
        private final Paint dotPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ringPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint haloPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        public StatusDotView(Context ctx) {
            super(ctx);
            ringPaint.setStyle(Paint.Style.STROKE);
            ringPaint.setStrokeWidth(dpFromContext(ctx, 1.5f));
        }

        private static int dpFromContext(Context ctx, float v) {
            return Math.round(v * ctx.getResources().getDisplayMetrics().density);
        }

        public void setStatus(String status) {
            if (status == null || status.isEmpty()) {
                setVisibility(View.GONE);
                return;
            }
            if (status.contains("連載") || status.contains("连载") || status.toLowerCase().contains("ongoing")) {
                color = STATUS_SERIAL;
            } else if (status.contains("完結") || status.contains("完结") || status.toLowerCase().contains("complet")) {
                color = STATUS_COMPLETE;
            } else if (status.contains("新着") || status.contains("新") || status.toLowerCase().contains("new")) {
                color = STATUS_NEW;
            } else {
                setVisibility(View.GONE);
                return;
            }
            setVisibility(View.VISIBLE);
            invalidate();
        }

        @Override
        protected void onMeasure(int widthSpec, int heightSpec) {
            int size = dpFromContext(getContext(), 16f);
            setMeasuredDimension(size, size);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            if (color == Color.TRANSPARENT) return;
            int w = getWidth(), h = getHeight();
            float cx = w / 2f, cy = h / 2f;
            float haloR = Math.min(w, h) / 2f;
            RadialGradient halo = new RadialGradient(cx, cy, haloR,
                new int[]{ Color.argb(80, Color.red(color), Color.green(color), Color.blue(color)),
                           Color.argb(0, Color.red(color), Color.green(color), Color.blue(color)) },
                null, Shader.TileMode.CLAMP);
            haloPaint.setShader(halo);
            canvas.drawCircle(cx, cy, haloR, haloPaint);
            float dotR = dpFromContext(getContext(), 4f);
            dotPaint.setColor(color);
            canvas.drawCircle(cx, cy, dotR, dotPaint);
            ringPaint.setColor(Color.WHITE);
            canvas.drawCircle(cx, cy, dotR + dpFromContext(getContext(), 0.75f), ringPaint);
        }
    }

    public static Space space(Activity ctx, int width, int height) {
        Space space = new Space(ctx);
        space.setLayoutParams(new LinearLayout.LayoutParams(width, height));
        return space;
    }

    public static LinearLayout.LayoutParams weight(float weight) {
        return new LinearLayout.LayoutParams(0, -2, weight);
    }

    public static LinearLayout.LayoutParams marginBottom(int width, int bottom) {
        return marginBottom(width, bottom, -2, -2);
    }

    public static LinearLayout.LayoutParams marginBottom(int width, int bottom, int explicitWidth, int explicitHeight) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(explicitWidth == -2 ? width : explicitWidth, explicitHeight);
        lp.setMargins(0, 0, 0, bottom);
        return lp;
    }

    public static LinearLayout.LayoutParams marginTop(int width, int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(width, -2);
        lp.setMargins(0, top, 0, 0);
        return lp;
    }

    public static LinearLayout.LayoutParams marginTop(int width, int top, int explicitWidth, int explicitHeight) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(explicitWidth, explicitHeight);
        lp.setMargins(0, top, 0, 0);
        return lp;
    }

    public static LinearLayout.LayoutParams marginRight(int width, int right) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(width, -2);
        lp.setMargins(0, 0, right, 0);
        return lp;
    }

    public static FrameLayout.LayoutParams frame(int width, int height, int gravity, int left, int top, int right, int bottom) {
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(width, height, gravity);
        lp.setMargins(left, top, right, bottom);
        return lp;
    }

    public static ViewGroup.LayoutParams match() {
        return new ViewGroup.LayoutParams(-1, -1);
    }

    public static ViewGroup.LayoutParams wrap() {
        return new ViewGroup.LayoutParams(-2, -2);
    }

    public static ViewGroup.LayoutParams matchWrap() {
        return new ViewGroup.LayoutParams(-1, -2);
    }

    public static int dp(Context ctx, int value) {
        if (ctx == null) return value;
        return Math.round(value * ctx.getResources().getDisplayMetrics().density);
    }

    public static int dp(Activity ctx, int value) {
        return dp((Context) ctx, value);
    }

    public static TextView menuItem(Activity ctx, String title, String end) {
        TextView item = text(ctx, title + (TextUtils.isEmpty(end) ? "" : "     " + end), 15, TEXT, Typeface.NORMAL);
        item.setGravity(Gravity.CENTER_VERTICAL);
        item.setPadding(dp(ctx, 16), 0, dp(ctx, 16), 0);
        item.setSingleLine(true);
        item.setEllipsize(TextUtils.TruncateAt.END);
        item.setMinHeight(dp(ctx, 50));
        return item;
    }

    public static View divider(Activity ctx) {
        View v = new View(ctx);
        v.setBackgroundColor(BORDER_SOFT);
        v.setLayoutParams(new LinearLayout.LayoutParams(-1, 1));
        return v;
    }

    public static LinearLayout card(Activity ctx) {
        return surfaceCard(ctx);
    }

    public static LinearLayout surfaceCard(Activity ctx) {
        LinearLayout card = new LinearLayout(ctx);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(ctx, 12), dp(ctx, 11), dp(ctx, 12), dp(ctx, 11));
        card.setBackground(round(CARD, dp(ctx, 8), BORDER_SOFT));
        card.setElevation(0);
        LinearLayout.LayoutParams lp = marginBottom(-1, dp(ctx, 10));
        card.setLayoutParams(lp);
        return card;
    }

    public static Button actionButton(Activity ctx, String title, int bg, int fg) {
        Button button = new Button(ctx);
        button.setAllCaps(false);
        button.setText(title);
        button.setTextSize(14);
        button.setTextColor(fg);
        button.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        boolean outlined = bg == Color.WHITE || bg == SURFACE || bg == CARD || bg == ACCENT_LIGHT || bg == ACCENT_SOFT;
        button.setBackground(round(bg, dp(ctx, 8), outlined ? BORDER : Color.TRANSPARENT));
        button.setGravity(Gravity.CENTER);
        button.setMinHeight(0);
        button.setMinimumHeight(0);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setSingleLine(true);
        button.setEllipsize(TextUtils.TruncateAt.END);
        button.setPadding(dp(ctx, 12), 0, dp(ctx, 12), 0);
        return button;
    }

    public static Button primaryButton(Activity ctx, String title) {
        return actionButton(ctx, title, ACCENT, ON_ACCENT);
    }

    public static Button brandButton(Activity ctx, String title) {
        return actionButton(ctx, title, BRAND, Color.WHITE);
    }

    public static Button secondaryButton(Activity ctx, String title) {
        return actionButton(ctx, title, SURFACE, TEXT2);
    }

    public static Button softButton(Activity ctx, String title) {
        return secondaryButton(ctx, title);
    }

    public static LinearLayout.LayoutParams buttonWeight(Activity ctx, float weight) {
        return new LinearLayout.LayoutParams(0, dp(ctx, 44), weight);
    }

    public static TextView chip(Activity ctx, String value, boolean selected) {
        TextView chip = text(ctx, value, 12, selected ? ON_ACCENT : TEXT3, Typeface.NORMAL);
        chip.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        chip.setGravity(Gravity.CENTER);
        chip.setPadding(dp(ctx, 11), dp(ctx, 6), dp(ctx, 11), dp(ctx, 6));
        chip.setBackground(round(selected ? ACCENT_SOFT : Color.TRANSPARENT, dp(ctx, 6), Color.TRANSPARENT));
        chip.setTextColor(selected ? ACCENT_DARK : TEXT3);
        return chip;
    }

    public static TextView iconButton(Activity ctx, String value) {
        TextView view = text(ctx, value, 27, Color.WHITE, Typeface.BOLD);
        view.setGravity(Gravity.CENTER);
        view.setBackground(round(Color.argb(45, 255, 255, 255), dp(ctx, 20), Color.TRANSPARENT));
        return view;
    }

    public static ImageView vectorIconButton(Activity ctx, int iconRes, int color, int paddingDp) {
        ImageView iv = new ImageView(ctx);
        iv.setImageResource(iconRes);
        iv.setImageTintList(android.content.res.ColorStateList.valueOf(color));
        int pad = dp(ctx, paddingDp);
        iv.setPadding(pad, pad, pad, pad);
        iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
        return iv;
    }

    public static HorizontalScrollView tagRow(Activity ctx, java.util.List<String> values) {
        HorizontalScrollView scroll = new HorizontalScrollView(ctx);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (String value : values) row.addView(chip(ctx, value, false), marginRight(-2, dp(ctx, 8)));
        scroll.addView(row, wrap());
        return scroll;
    }

    public static LinearLayout chipRow(Activity ctx, java.util.List<String> values, int selected) {
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (int i = 0; i < values.size(); i++) {
            row.addView(chip(ctx, values.get(i), i == selected), marginRight(-2, dp(ctx, 8)));
        }
        return row;
    }

    public static EditText searchBox(Activity ctx, String hint, boolean editable) {
        EditText input = new EditText(ctx);
        input.setTextSize(14);
        input.setHint(hint);
        input.setHintTextColor(TEXT3);
        input.setTextColor(TEXT);
        input.setSingleLine(true);
        input.setFocusable(editable);
        input.setPadding(dp(ctx, 16), 0, dp(ctx, 16), 0);
        input.setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0);
        input.setCompoundDrawableTintList(android.content.res.ColorStateList.valueOf(TEXT3));
        input.setCompoundDrawablePadding(dp(ctx, 9));
        input.setMinHeight(dp(ctx, 44));
        input.setBackground(round(SURFACE, dp(ctx, 10), BORDER));
        return input;
    }

    public static com.facebook.shimmer.ShimmerFrameLayout shimmerFrame(Activity ctx) {
        com.facebook.shimmer.ShimmerFrameLayout frame = new com.facebook.shimmer.ShimmerFrameLayout(ctx);
        com.facebook.shimmer.Shimmer shimmer = new com.facebook.shimmer.Shimmer.AlphaHighlightBuilder()
            .setDuration(1500L)
            .setRepeatDelay(300L)
            .setBaseAlpha(0.4f)
            .setHighlightAlpha(0.3f)
            .setDirection(com.facebook.shimmer.Shimmer.Direction.LEFT_TO_RIGHT)
            .build();
        frame.setShimmer(shimmer);
        frame.startShimmer();
        return frame;
    }

    public static View skeletonCard(Activity ctx, String variant) {
        boolean grid = "grid".equals(variant);
        LinearLayout card = new LinearLayout(ctx);
        card.setOrientation(LinearLayout.VERTICAL);
        int coverH = grid ? dp(ctx, 214) : dp(ctx, 107);
        int coverW = grid ? -1 : dp(ctx, 80);
        View cover = new View(ctx);
        cover.setBackground(round(SURFACE, dp(ctx, 8), Color.TRANSPARENT));
        if (grid) {
            card.addView(cover, new LinearLayout.LayoutParams(-1, coverH));
        } else {
            LinearLayout row = new LinearLayout(ctx);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.addView(cover, new LinearLayout.LayoutParams(coverW, coverH));
            LinearLayout info = new LinearLayout(ctx);
            info.setOrientation(LinearLayout.VERTICAL);
            info.setPadding(dp(ctx, 12), 0, 0, 0);
            View line1 = new View(ctx);
            line1.setBackground(round(TEXT3, dp(ctx, 4), Color.TRANSPARENT));
            info.addView(line1, new LinearLayout.LayoutParams(dp(ctx, 120), dp(ctx, 16)));
            View line2 = new View(ctx);
            line2.setBackground(round(BORDER, dp(ctx, 4), Color.TRANSPARENT));
            LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(dp(ctx, 80), dp(ctx, 12));
            lp2.topMargin = dp(ctx, 8);
            info.addView(line2, lp2);
            row.addView(info, weight(1));
            card.addView(row);
        }
        return card;
    }

    public static View emptyState(Activity ctx, int iconRes, String title, String desc, String action, Runnable onAction) {
        LinearLayout box = new LinearLayout(ctx);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(ctx, 24), dp(ctx, 48), dp(ctx, 24), dp(ctx, 48));
        ImageView icon = new ImageView(ctx);
        icon.setImageResource(iconRes);
        icon.setImageTintList(android.content.res.ColorStateList.valueOf(TEXT3));
        LinearLayout.LayoutParams iconLp = new LinearLayout.LayoutParams(dp(ctx, 72), dp(ctx, 72));
        box.addView(icon, iconLp);
        TextView t = new TextView(ctx);
        t.setText(title);
        t.setTypeface(Typeface.SERIF);
        t.setTextSize(16);
        t.setTextColor(TEXT2);
        t.setLetterSpacing(-0.02f);
        t.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        tlp.topMargin = dp(ctx, 20);
        box.addView(t, tlp);
        if (!TextUtils.isEmpty(desc)) {
            TextView d = new TextView(ctx);
            d.setText(desc);
            d.setTextSize(13);
            d.setTextColor(TEXT3);
            d.setGravity(Gravity.CENTER);
            d.setMaxLines(2);
            d.setEllipsize(TextUtils.TruncateAt.END);
            LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            dlp.topMargin = dp(ctx, 8);
            box.addView(d, dlp);
        }
        if (!TextUtils.isEmpty(action) && onAction != null) {
            Button btn = secondaryButton(ctx, action);
            btn.setOnClickListener(v -> onAction.run());
            LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(ctx, 42));
            blp.topMargin = dp(ctx, 20);
            box.addView(btn, blp);
        }
        return box;
    }

    public static void tapFeedback(View v) {
        v.setOnTouchListener((view, e) -> {
            switch (e.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    animateAlpha(view, 1f, 0.7f);
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    animateAlpha(view, 0.7f, 1f);
                    break;
            }
            return false;
        });
    }

    private static void animateAlpha(View v, float from, float to) {
        android.animation.ValueAnimator a = android.animation.ValueAnimator.ofFloat(from, to);
        a.setDuration(250L);
        a.setInterpolator(new android.view.animation.PathInterpolator(0.2f, 0f, 0f, 1f));
        a.addUpdateListener(an -> v.setAlpha((float) an.getAnimatedValue()));
        a.start();
    }
}
