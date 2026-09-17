package com.xxcomic.ebook;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;

public class TextReaderSettingsSheet {

    private static final String PREF_NAME = "xxcomic_text_reader_prefs";
    private static final String KEY_FONT_SIZE = "font_size_sp";
    private static final String KEY_LINE_HEIGHT = "line_height";
    private static final String KEY_THEME = "reader_theme";
    private static final String KEY_PAGED_MODE = "paged_mode";

    public interface OnSettingsChangeListener {
        void onSettingsChanged(int fontSizeSp, float lineHeight, int theme, boolean pagedMode);
    }

    public static class Settings {
        public int fontSizeSp;
        public float lineHeight;
        public int theme;
        public boolean pagedMode;

        public Settings(int fontSizeSp, float lineHeight, int theme, boolean pagedMode) {
            this.fontSizeSp = fontSizeSp;
            this.lineHeight = lineHeight;
            this.theme = theme;
            this.pagedMode = pagedMode;
        }
    }

    public static Settings loadSettings(Context context) {
        SharedPreferences sp = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        int fontSize = sp.getInt(KEY_FONT_SIZE, 18);
        float lineHeight = sp.getFloat(KEY_LINE_HEIGHT, 1.75f);
        int theme = sp.getInt(KEY_THEME, TextReaderView.THEME_DARK);
        boolean paged = sp.getBoolean(KEY_PAGED_MODE, false);
        return new Settings(fontSize, lineHeight, theme, paged);
    }

    public static void saveSettings(Context context, Settings settings) {
        SharedPreferences sp = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        sp.edit()
                .putInt(KEY_FONT_SIZE, settings.fontSizeSp)
                .putFloat(KEY_LINE_HEIGHT, settings.lineHeight)
                .putInt(KEY_THEME, settings.theme)
                .putBoolean(KEY_PAGED_MODE, settings.pagedMode)
                .apply();
    }

    public static void show(Activity activity, OnSettingsChangeListener listener) {
        if (activity == null || activity.isFinishing()) return;
        Settings current = loadSettings(activity);
        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 14),
                UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 20));
        panel.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 16), UIHelpers.BORDER));

        // Header
        LinearLayout header = new LinearLayout(activity);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = UIHelpers.text(activity, "文字排版设置", 15, UIHelpers.TEXT, Typeface.BOLD);
        header.addView(title, UIHelpers.weight(1));

        View close = UIHelpers.vectorIconButton(activity, R.drawable.ic_close, UIHelpers.TEXT3, 4);
        close.setOnClickListener(v -> dialog.dismiss());
        header.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 32), UIHelpers.dp(activity, 32)));
        panel.addView(header);

        panel.addView(UIHelpers.divider(activity), UIHelpers.marginTop(-1, UIHelpers.dp(activity, 8)));

        // 1. Font Size Row: 字号  [-] 18 sp [+]
        LinearLayout fontRow = new LinearLayout(activity);
        fontRow.setGravity(Gravity.CENTER_VERTICAL);
        fontRow.setPadding(0, UIHelpers.dp(activity, 10), 0, UIHelpers.dp(activity, 10));
        fontRow.addView(UIHelpers.text(activity, "字体大小", 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.weight(1));

        TextView fontMinus = UIHelpers.text(activity, "－", 16, UIHelpers.TEXT, Typeface.BOLD);
        fontMinus.setGravity(Gravity.CENTER);
        fontMinus.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 6), UIHelpers.BORDER));
        fontRow.addView(fontMinus, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 38), UIHelpers.dp(activity, 32)));

        TextView fontSizeVal = UIHelpers.text(activity, current.fontSizeSp + " sp", 13, UIHelpers.TEXT, Typeface.BOLD);
        fontSizeVal.setGravity(Gravity.CENTER);
        fontRow.addView(fontSizeVal, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 64), UIHelpers.dp(activity, 32)));

        TextView fontPlus = UIHelpers.text(activity, "＋", 16, UIHelpers.TEXT, Typeface.BOLD);
        fontPlus.setGravity(Gravity.CENTER);
        fontPlus.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 6), UIHelpers.BORDER));
        fontRow.addView(fontPlus, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 38), UIHelpers.dp(activity, 32)));

        fontMinus.setOnClickListener(v -> {
            if (current.fontSizeSp > 12) {
                current.fontSizeSp -= 1;
                fontSizeVal.setText(current.fontSizeSp + " sp");
                saveSettings(activity, current);
                if (listener != null) listener.onSettingsChanged(current.fontSizeSp, current.lineHeight, current.theme, current.pagedMode);
            }
        });

        fontPlus.setOnClickListener(v -> {
            if (current.fontSizeSp < 32) {
                current.fontSizeSp += 1;
                fontSizeVal.setText(current.fontSizeSp + " sp");
                saveSettings(activity, current);
                if (listener != null) listener.onSettingsChanged(current.fontSizeSp, current.lineHeight, current.theme, current.pagedMode);
            }
        });

        panel.addView(fontRow);

        // 2. Line Spacing Row: 行间距  [紧凑 1.5] [标准 1.75] [宽松 2.0]
        LinearLayout lineRow = new LinearLayout(activity);
        lineRow.setGravity(Gravity.CENTER_VERTICAL);
        lineRow.setPadding(0, UIHelpers.dp(activity, 6), 0, UIHelpers.dp(activity, 10));
        lineRow.addView(UIHelpers.text(activity, "行间距", 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.weight(1));

        TextView[] lineButtons = new TextView[3];
        float[] lineValues = new float[]{1.5f, 1.75f, 2.0f};
        String[] lineLabels = new String[]{"紧凑", "标准", "宽松"};

        for (int i = 0; i < 3; i++) {
            final int idx = i;
            TextView btn = UIHelpers.text(activity, lineLabels[i], 12, UIHelpers.TEXT, Typeface.NORMAL);
            btn.setGravity(Gravity.CENTER);
            btn.setPadding(UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 6));
            lineButtons[i] = btn;

            boolean isSelected = Math.abs(current.lineHeight - lineValues[i]) < 0.05f;
            btn.setBackground(UIHelpers.round(isSelected ? UIHelpers.ACCENT_SOFT : UIHelpers.SURFACE,
                    UIHelpers.dp(activity, 6), isSelected ? UIHelpers.ACCENT : UIHelpers.BORDER));
            btn.setTextColor(isSelected ? UIHelpers.ACCENT : UIHelpers.TEXT);

            btn.setOnClickListener(v -> {
                current.lineHeight = lineValues[idx];
                for (int j = 0; j < 3; j++) {
                    boolean sel = j == idx;
                    lineButtons[j].setBackground(UIHelpers.round(sel ? UIHelpers.ACCENT_SOFT : UIHelpers.SURFACE,
                            UIHelpers.dp(activity, 6), sel ? UIHelpers.ACCENT : UIHelpers.BORDER));
                    lineButtons[j].setTextColor(sel ? UIHelpers.ACCENT : UIHelpers.TEXT);
                }
                saveSettings(activity, current);
                if (listener != null) listener.onSettingsChanged(current.fontSizeSp, current.lineHeight, current.theme, current.pagedMode);
            });

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 32), 1);
            if (i > 0) lp.leftMargin = UIHelpers.dp(activity, 6);
            lineRow.addView(btn, lp);
        }
        panel.addView(lineRow);

        // 3. Theme Row: 背景主题  [⚪ 浅色] [🟡 护眼] [⚫ 夜间]
        LinearLayout themeRow = new LinearLayout(activity);
        themeRow.setGravity(Gravity.CENTER_VERTICAL);
        themeRow.setPadding(0, UIHelpers.dp(activity, 6), 0, UIHelpers.dp(activity, 10));
        themeRow.addView(UIHelpers.text(activity, "阅读背景", 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.weight(1));

        TextView[] themeButtons = new TextView[3];
        int[] themeValues = new int[]{TextReaderView.THEME_LIGHT, TextReaderView.THEME_SEPIA, TextReaderView.THEME_DARK};
        String[] themeLabels = new String[]{"⚪ 浅白", "🟡 护眼", "⚫ 夜空"};

        for (int i = 0; i < 3; i++) {
            final int idx = i;
            TextView btn = UIHelpers.text(activity, themeLabels[i], 12, UIHelpers.TEXT, Typeface.NORMAL);
            btn.setGravity(Gravity.CENTER);
            btn.setPadding(UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 6));
            themeButtons[i] = btn;

            boolean isSelected = current.theme == themeValues[i];
            btn.setBackground(UIHelpers.round(isSelected ? UIHelpers.ACCENT_SOFT : UIHelpers.SURFACE,
                    UIHelpers.dp(activity, 6), isSelected ? UIHelpers.ACCENT : UIHelpers.BORDER));
            btn.setTextColor(isSelected ? UIHelpers.ACCENT : UIHelpers.TEXT);

            btn.setOnClickListener(v -> {
                current.theme = themeValues[idx];
                for (int j = 0; j < 3; j++) {
                    boolean sel = j == idx;
                    themeButtons[j].setBackground(UIHelpers.round(sel ? UIHelpers.ACCENT_SOFT : UIHelpers.SURFACE,
                            UIHelpers.dp(activity, 6), sel ? UIHelpers.ACCENT : UIHelpers.BORDER));
                    themeButtons[j].setTextColor(sel ? UIHelpers.ACCENT : UIHelpers.TEXT);
                }
                saveSettings(activity, current);
                if (listener != null) listener.onSettingsChanged(current.fontSizeSp, current.lineHeight, current.theme, current.pagedMode);
            });

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 32), 1);
            if (i > 0) lp.leftMargin = UIHelpers.dp(activity, 6);
            themeRow.addView(btn, lp);
        }
        panel.addView(themeRow);

        // 4. Reading Mode: 翻页模式  [📜 连续滚动] [📖 点击翻页]
        LinearLayout modeRow = new LinearLayout(activity);
        modeRow.setGravity(Gravity.CENTER_VERTICAL);
        modeRow.setPadding(0, UIHelpers.dp(activity, 6), 0, UIHelpers.dp(activity, 4));
        modeRow.addView(UIHelpers.text(activity, "阅读模式", 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.weight(1));

        TextView scrollBtn = UIHelpers.text(activity, "连续滚动", 12, UIHelpers.TEXT, Typeface.NORMAL);
        scrollBtn.setGravity(Gravity.CENTER);
        scrollBtn.setPadding(UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 6));
        scrollBtn.setBackground(UIHelpers.round(!current.pagedMode ? UIHelpers.ACCENT_SOFT : UIHelpers.SURFACE,
                UIHelpers.dp(activity, 6), !current.pagedMode ? UIHelpers.ACCENT : UIHelpers.BORDER));
        scrollBtn.setTextColor(!current.pagedMode ? UIHelpers.ACCENT : UIHelpers.TEXT);

        TextView pagedBtn = UIHelpers.text(activity, "点击翻页", 12, UIHelpers.TEXT, Typeface.NORMAL);
        pagedBtn.setGravity(Gravity.CENTER);
        pagedBtn.setPadding(UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 6));
        pagedBtn.setBackground(UIHelpers.round(current.pagedMode ? UIHelpers.ACCENT_SOFT : UIHelpers.SURFACE,
                UIHelpers.dp(activity, 6), current.pagedMode ? UIHelpers.ACCENT : UIHelpers.BORDER));
        pagedBtn.setTextColor(current.pagedMode ? UIHelpers.ACCENT : UIHelpers.TEXT);

        scrollBtn.setOnClickListener(v -> {
            current.pagedMode = false;
            scrollBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 6), UIHelpers.ACCENT));
            scrollBtn.setTextColor(UIHelpers.ACCENT);
            pagedBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 6), UIHelpers.BORDER));
            pagedBtn.setTextColor(UIHelpers.TEXT);
            saveSettings(activity, current);
            if (listener != null) listener.onSettingsChanged(current.fontSizeSp, current.lineHeight, current.theme, current.pagedMode);
        });

        pagedBtn.setOnClickListener(v -> {
            current.pagedMode = true;
            pagedBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 6), UIHelpers.ACCENT));
            pagedBtn.setTextColor(UIHelpers.ACCENT);
            scrollBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 6), UIHelpers.BORDER));
            scrollBtn.setTextColor(UIHelpers.TEXT);
            saveSettings(activity, current);
            if (listener != null) listener.onSettingsChanged(current.fontSizeSp, current.lineHeight, current.theme, current.pagedMode);
        });

        LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 32), 1);
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 32), 1);
        lp2.leftMargin = UIHelpers.dp(activity, 6);
        modeRow.addView(scrollBtn, lp1);
        modeRow.addView(pagedBtn, lp2);
        panel.addView(modeRow);

        dialog.setContentView(panel, new ViewGroup.LayoutParams(
                activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 32), -2));
        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            dialog.getWindow().setGravity(Gravity.BOTTOM);
            dialog.getWindow().getAttributes().y = UIHelpers.dp(activity, 16);
        }
        dialog.show();
    }
}
