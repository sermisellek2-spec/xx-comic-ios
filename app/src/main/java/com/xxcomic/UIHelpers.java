package com.xxcomic;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.Space;
import android.widget.TextView;

import java.util.Calendar;

public final class UIHelpers {
    private UIHelpers() {
    }

    public static int BG = Color.rgb(255, 255, 255);
    public static int SURFACE = Color.rgb(250, 249, 246);
    public static int CARD = Color.rgb(255, 255, 255);
    public static int CARD_SOFT = Color.rgb(250, 249, 246);
    public static int TEXT = Color.rgb(28, 28, 26);
    public static int TEXT2 = Color.rgb(74, 74, 71);
    public static int TEXT3 = Color.rgb(139, 138, 133);
    public static int BORDER = Color.rgb(236, 233, 227);
    public static int BORDER_SOFT = Color.rgb(241, 239, 232);
    public static int ACCENT = Color.rgb(28, 28, 26);
    public static int BRAND = Color.rgb(245, 158, 11);
    public static int PLACEHOLDER = Color.rgb(231, 229, 226);
    public static int READER_TEXT = Color.rgb(232, 232, 230);
    public static int ACCENT_LIGHT = Color.rgb(241, 239, 232);
    public static int ACCENT_SOFT = Color.rgb(250, 249, 246);
    public static int ACCENT_DARK = Color.rgb(28, 28, 26);
    public static int GREEN = Color.rgb(29, 158, 117);
    public static int GREEN_LIGHT = Color.rgb(229, 247, 239);
    public static int DANGER = Color.rgb(220, 77, 77);
    public static int DARK = Color.rgb(22, 22, 26);
    public static int DARK_BAR = Color.rgb(15, 15, 18);
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
        BG = Color.rgb(255, 255, 255);
        SURFACE = Color.rgb(250, 249, 246);
        CARD = Color.rgb(255, 255, 255);
        CARD_SOFT = Color.rgb(250, 249, 246);
        TEXT = Color.rgb(28, 28, 26);
        TEXT2 = Color.rgb(74, 74, 71);
        TEXT3 = Color.rgb(139, 138, 133);
        BORDER = Color.rgb(236, 233, 227);
        BORDER_SOFT = Color.rgb(241, 239, 232);
        ACCENT = Color.rgb(28, 28, 26);
        BRAND = Color.rgb(245, 158, 11);
        PLACEHOLDER = Color.rgb(231, 229, 226);
        READER_TEXT = Color.rgb(232, 232, 230);
        ACCENT_LIGHT = Color.rgb(241, 239, 232);
        ACCENT_SOFT = Color.rgb(250, 249, 246);
        ACCENT_DARK = Color.rgb(28, 28, 26);
        GREEN_LIGHT = Color.rgb(229, 247, 239);
        DARK = Color.rgb(22, 22, 26);
        DARK_BAR = Color.rgb(15, 15, 18);
    }

    private static void applyNightTheme() {
        nightTheme = true;
        BG = Color.rgb(18, 18, 20);
        SURFACE = Color.rgb(28, 28, 31);
        CARD = Color.rgb(34, 34, 38);
        CARD_SOFT = Color.rgb(31, 30, 34);
        TEXT = Color.rgb(242, 238, 232);
        TEXT2 = Color.rgb(190, 184, 176);
        TEXT3 = Color.rgb(134, 128, 121);
        BORDER = Color.rgb(58, 54, 50);
        BORDER_SOFT = Color.rgb(45, 42, 39);
        ACCENT = Color.rgb(74, 74, 71);
        BRAND = Color.rgb(245, 158, 11);
        PLACEHOLDER = Color.rgb(58, 54, 50);
        READER_TEXT = Color.rgb(232, 232, 230);
        ACCENT_LIGHT = Color.rgb(45, 42, 39);
        ACCENT_SOFT = Color.rgb(31, 30, 34);
        ACCENT_DARK = Color.rgb(232, 232, 230);
        GREEN_LIGHT = Color.rgb(24, 58, 42);
        DARK = Color.rgb(22, 22, 26);
        DARK_BAR = Color.rgb(15, 15, 18);
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

    public static GradientDrawable gradient(int[] colors, int radius) {
        return round(PLACEHOLDER, radius, Color.TRANSPARENT);
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

    public static int dp(Activity ctx, int value) {
        return Math.round(value * ctx.getResources().getDisplayMetrics().density);
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
        card.setPadding(dp(ctx, 14), dp(ctx, 14), dp(ctx, 14), dp(ctx, 14));
        card.setBackground(round(CARD, dp(ctx, 12), BORDER));
        card.setElevation(dp(ctx, 1));
        LinearLayout.LayoutParams lp = marginBottom(-1, dp(ctx, 12));
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
        button.setBackground(round(bg, dp(ctx, 12), outlined ? BORDER : Color.TRANSPARENT));
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
        return actionButton(ctx, title, ACCENT, Color.WHITE);
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

    public static TextView pill(Activity ctx, String value, int bg, int fg) {
        TextView pill = text(ctx, value, 12, fg, Typeface.NORMAL);
        pill.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        pill.setGravity(Gravity.CENTER);
        pill.setPadding(dp(ctx, 12), dp(ctx, 6), dp(ctx, 12), dp(ctx, 6));
        pill.setBackground(round(bg, dp(ctx, 15), bg == Color.WHITE ? BORDER : Color.TRANSPARENT));
        return pill;
    }

    public static TextView chip(Activity ctx, String value, boolean selected) {
        TextView chip = text(ctx, value, 12, selected ? Color.WHITE : TEXT3, Typeface.NORMAL);
        chip.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        chip.setGravity(Gravity.CENTER);
        chip.setPadding(dp(ctx, 14), dp(ctx, 7), dp(ctx, 14), dp(ctx, 7));
        chip.setBackground(round(selected ? ACCENT : SURFACE, dp(ctx, 16), Color.TRANSPARENT));
        return chip;
    }

    public static TextView iconButton(Activity ctx, String value) {
        TextView view = text(ctx, value, 27, Color.WHITE, Typeface.BOLD);
        view.setGravity(Gravity.CENTER);
        view.setBackground(round(Color.argb(45, 255, 255, 255), dp(ctx, 20), Color.TRANSPARENT));
        return view;
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
        input.setCompoundDrawablesWithIntrinsicBounds(android.R.drawable.ic_menu_search, 0, 0, 0);
        input.setCompoundDrawablePadding(dp(ctx, 9));
        input.setMinHeight(dp(ctx, 44));
        input.setBackground(round(SURFACE, dp(ctx, 10), BORDER));
        return input;
    }
}
