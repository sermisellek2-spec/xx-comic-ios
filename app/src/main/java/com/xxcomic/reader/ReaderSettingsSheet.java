package com.xxcomic.reader;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;

import java.util.ArrayList;
import java.util.List;

public final class ReaderSettingsSheet {

    public static final int MODE_SCROLL = 0;
    public static final int MODE_NORMAL = 1;
    public static final int MODE_MANGA = 2;

    public static final int THEME_DEFAULT = 0;
    public static final int THEME_DARK = 1;
    public static final int THEME_LIGHT = 2;

    public interface OnSettingsChangeListener {
        void onReadingModeChanged(int mode);
        void onHideStatusBadgeChanged(boolean hide);
        void onEinkModeChanged(boolean eink);
        void onPinchZoomChanged(boolean enabled);
        default void onDisablePageAnimationChanged(boolean disabled) {}
        default void onCropWhiteMarginsChanged(boolean enabled) {}
        default void onReaderThemeChanged(int themeMode) {}
    }

    public static int toReadingMode(int layoutMode, boolean leftHand) {
        if (layoutMode == 0) return MODE_SCROLL;
        return leftHand ? MODE_MANGA : MODE_NORMAL;
    }

    public static int toLayoutMode(int readingMode) {
        return readingMode == MODE_SCROLL ? 0 : 1;
    }

    public static boolean toLeftHand(int readingMode) {
        return readingMode == MODE_MANGA;
    }

    public static Dialog show(Activity activity, int initialMode, boolean initialHideBadge, boolean initialEink,
                              OnSettingsChangeListener listener) {
        return show(activity, initialMode, initialHideBadge, initialEink, true, false, false, listener);
    }

    public static Dialog show(Activity activity, int initialMode, boolean initialHideBadge, boolean initialEink,
                              boolean initialPinchZoom, OnSettingsChangeListener listener) {
        return show(activity, initialMode, initialHideBadge, initialEink, initialPinchZoom, false, false, listener);
    }

    public static Dialog show(Activity activity, int initialMode, boolean initialHideBadge, boolean initialEink,
                              boolean initialPinchZoom, boolean initialDisablePageAnimation,
                              OnSettingsChangeListener listener) {
        return show(activity, initialMode, initialHideBadge, initialEink, initialPinchZoom, initialDisablePageAnimation, false, listener);
    }

    public static Dialog show(Activity activity, int initialMode, boolean initialHideBadge, boolean initialEink,
                              boolean initialPinchZoom, boolean initialDisablePageAnimation, boolean initialCropWhiteMargins,
                              OnSettingsChangeListener listener) {
        return show(activity, initialMode, initialHideBadge, initialEink, initialPinchZoom, initialDisablePageAnimation,
                initialCropWhiteMargins, THEME_DEFAULT, listener);
    }

    public static Dialog show(Activity activity, int initialMode, boolean initialHideBadge, boolean initialEink,
                              boolean initialPinchZoom, boolean initialDisablePageAnimation, boolean initialCropWhiteMargins,
                              int initialReaderTheme, OnSettingsChangeListener listener) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return null;

        boolean isDark = initialEink || (initialReaderTheme == THEME_DARK)
                || (initialReaderTheme == THEME_DEFAULT && UIHelpers.isSystemNightMode(activity));

        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setCanceledOnTouchOutside(true);

        SheetRootLayout panel = new SheetRootLayout(activity);
        panel.setDialog(dialog);
        panel.setOrientation(LinearLayout.VERTICAL);
        int padH = UIHelpers.dp(activity, 18);
        panel.setPadding(padH, UIHelpers.dp(activity, 10), padH, UIHelpers.dp(activity, 16));

        GradientDrawable panelBg = new GradientDrawable();
        panelBg.setColor(isDark ? Color.parseColor("#1C2128") : Color.parseColor("#FFFFFF"));
        float r = UIHelpers.dp(activity, 18);
        panelBg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        panel.setBackground(panelBg);

        // Top drag handle
        View handle = new View(activity);
        GradientDrawable handleBg = new GradientDrawable();
        handleBg.setColor(isDark ? Color.parseColor("#444C56") : Color.parseColor("#D0D7DE"));
        handleBg.setCornerRadius(UIHelpers.dp(activity, 2));
        handle.setBackground(handleBg);
        LinearLayout.LayoutParams handleLp = new LinearLayout.LayoutParams(UIHelpers.dp(activity, 36), UIHelpers.dp(activity, 4));
        handleLp.gravity = Gravity.CENTER_HORIZONTAL;
        handleLp.topMargin = UIHelpers.dp(activity, 2);
        handleLp.bottomMargin = UIHelpers.dp(activity, 10);
        panel.addView(handle, handleLp);

        MaxHeightScrollView scroll = new MaxHeightScrollView(activity);
        scroll.setOverScrollMode(View.OVER_SCROLL_IF_CONTENT_SCROLLS);
        scroll.setVerticalScrollBarEnabled(false);
        panel.setScrollView(scroll);

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);

        final List<TextView> primaryTexts = new ArrayList<>();
        final List<TextView> secondaryTexts = new ArrayList<>();
        final List<Switch> switches = new ArrayList<>();
        final List<ModeCardView> allCards = new ArrayList<>();
        final boolean[] currentIsDark = new boolean[]{isDark};

        Runnable updateThemeUi = () -> {
            boolean dark = currentIsDark[0];
            panelBg.setColor(dark ? Color.parseColor("#1C2128") : Color.parseColor("#FFFFFF"));
            handleBg.setColor(dark ? Color.parseColor("#444C56") : Color.parseColor("#D0D7DE"));
            for (TextView tv : primaryTexts) {
                tv.setTextColor(dark ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328"));
            }
            for (TextView tv : secondaryTexts) {
                tv.setTextColor(dark ? Color.parseColor("#8B949E") : Color.parseColor("#656D76"));
            }
            for (Switch sw : switches) {
                setupSwitchColors(activity, sw, dark);
            }
            for (ModeCardView card : allCards) {
                card.setTheme(dark);
            }
        };

        // Row 1: 阅读模式
        LinearLayout modeRow = new LinearLayout(activity);
        modeRow.setOrientation(LinearLayout.HORIZONTAL);
        modeRow.setGravity(Gravity.CENTER_VERTICAL);
        modeRow.setPadding(0, UIHelpers.dp(activity, 4), 0, UIHelpers.dp(activity, 10));

        TextView modeTitle = UIHelpers.text(activity, "阅读模式", 14,
                isDark ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328"), Typeface.NORMAL);
        modeTitle.setIncludeFontPadding(false);
        primaryTexts.add(modeTitle);
        modeRow.addView(modeTitle, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 68), -2));

        LinearLayout cardsContainer = new LinearLayout(activity);
        cardsContainer.setOrientation(LinearLayout.HORIZONTAL);
        cardsContainer.setGravity(Gravity.CENTER_VERTICAL);

        ModeCardView[] cardViews = new ModeCardView[3];
        int[] activeMode = new int[]{initialMode};

        cardViews[0] = new ModeCardView(activity, R.drawable.ic_mode_scroll, "卷轴模式", initialMode == MODE_SCROLL, isDark);
        cardViews[1] = new ModeCardView(activity, R.drawable.ic_mode_normal, "普通模式", initialMode == MODE_NORMAL, isDark);
        cardViews[2] = new ModeCardView(activity, R.drawable.ic_mode_manga, "日漫模式", initialMode == MODE_MANGA, isDark);

        for (int i = 0; i < 3; i++) {
            final int modeIndex = i;
            final ModeCardView card = cardViews[i];
            allCards.add(card);
            card.setOnClickListener(v -> {
                if (activeMode[0] == modeIndex) return;
                activeMode[0] = modeIndex;
                for (int j = 0; j < 3; j++) {
                    cardViews[j].setSelected(j == modeIndex);
                }
                if (listener != null) {
                    listener.onReadingModeChanged(modeIndex);
                }
            });

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 58), 1f);
            if (i > 0) lp.leftMargin = UIHelpers.dp(activity, 8);
            cardsContainer.addView(card, lp);
        }

        modeRow.addView(cardsContainer, new LinearLayout.LayoutParams(-1, -2));
        content.addView(modeRow);

        // Row 2: 阅读主题 (默认 / 深色 / 浅色)
        LinearLayout themeRow = new LinearLayout(activity);
        themeRow.setOrientation(LinearLayout.HORIZONTAL);
        themeRow.setGravity(Gravity.CENTER_VERTICAL);
        themeRow.setPadding(0, UIHelpers.dp(activity, 4), 0, UIHelpers.dp(activity, 10));

        TextView themeTitle = UIHelpers.text(activity, "阅读主题", 14,
                isDark ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328"), Typeface.NORMAL);
        themeTitle.setIncludeFontPadding(false);
        primaryTexts.add(themeTitle);
        themeRow.addView(themeTitle, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 68), -2));

        LinearLayout themeCardsContainer = new LinearLayout(activity);
        themeCardsContainer.setOrientation(LinearLayout.HORIZONTAL);
        themeCardsContainer.setGravity(Gravity.CENTER_VERTICAL);

        ModeCardView[] themeCardViews = new ModeCardView[3];
        int[] activeTheme = new int[]{initialReaderTheme};

        themeCardViews[0] = new ModeCardView(activity, R.drawable.ic_auto, "默认", initialReaderTheme == THEME_DEFAULT, isDark);
        themeCardViews[1] = new ModeCardView(activity, R.drawable.ic_moon, "深色", initialReaderTheme == THEME_DARK, isDark);
        themeCardViews[2] = new ModeCardView(activity, R.drawable.ic_sun, "浅色", initialReaderTheme == THEME_LIGHT, isDark);

        for (int i = 0; i < 3; i++) {
            final int themeIndex = i;
            final ModeCardView card = themeCardViews[i];
            allCards.add(card);
            card.setOnClickListener(v -> {
                if (activeTheme[0] == themeIndex) return;
                activeTheme[0] = themeIndex;
                for (int j = 0; j < 3; j++) {
                    themeCardViews[j].setSelected(j == themeIndex);
                }
                boolean newDark = initialEink || (themeIndex == THEME_DARK)
                        || (themeIndex == THEME_DEFAULT && UIHelpers.isSystemNightMode(activity));
                if (currentIsDark[0] != newDark) {
                    currentIsDark[0] = newDark;
                    updateThemeUi.run();
                }
                if (listener != null) {
                    listener.onReaderThemeChanged(themeIndex);
                }
            });

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 58), 1f);
            if (i > 0) lp.leftMargin = UIHelpers.dp(activity, 8);
            themeCardsContainer.addView(card, lp);
        }

        themeRow.addView(themeCardsContainer, new LinearLayout.LayoutParams(-1, -2));
        content.addView(themeRow);

        // Row 3: 隐藏右下角状态信息
        LinearLayout rowHideStatus = createSwitchRow(activity, "隐藏右下角状态信息", null, initialHideBadge, isDark,
                primaryTexts, secondaryTexts, switches, (view, isChecked) -> {
            if (listener != null) {
                listener.onHideStatusBadgeChanged(isChecked);
            }
        });
        content.addView(rowHideStatus);

        // Row 4: 墨水屏模式
        LinearLayout rowEink = createSwitchRow(activity, "墨水屏模式", null, initialEink, isDark,
                primaryTexts, secondaryTexts, switches, (view, isChecked) -> {
            if (listener != null) {
                listener.onEinkModeChanged(isChecked);
            }
        });
        content.addView(rowEink);

        // Row 5: 搓指放大
        LinearLayout rowPinchZoom = createSwitchRow(activity, "搓指放大", null, initialPinchZoom, isDark,
                primaryTexts, secondaryTexts, switches, (view, isChecked) -> {
            if (listener != null) {
                listener.onPinchZoomChanged(isChecked);
            }
        });
        content.addView(rowPinchZoom);

        // Row 6: 禁止动画翻页
        LinearLayout rowDisableAnimation = createSwitchRow(activity, "禁止动画翻页", "开启后直接切页，滑动手势仍可用",
                initialDisablePageAnimation, isDark, primaryTexts, secondaryTexts, switches, (view, isChecked) -> {
            if (listener != null) {
                listener.onDisablePageAnimationChanged(isChecked);
            }
        });
        content.addView(rowDisableAnimation);

        // Row 7: 去白边
        LinearLayout rowCropWhiteMargins = createSwitchRow(activity, "去白边", "自动裁去图片外围白边，原文件不变",
                initialCropWhiteMargins, isDark, primaryTexts, secondaryTexts, switches, (view, isChecked) -> {
            if (listener != null) {
                listener.onCropWhiteMarginsChanged(isChecked);
            }
        });
        content.addView(rowCropWhiteMargins);

        scroll.addView(content, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        panel.addView(scroll, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        dialog.setContentView(panel);
        dialog.show();

        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            w.setGravity(Gravity.BOTTOM);
            w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            w.setDimAmount(0.5f);
            w.setWindowAnimations(R.style.DownloadSheetAnimation);
        }

        return dialog;
    }

    private static LinearLayout createSwitchRow(Activity activity, String label, String subtitle, boolean initialValue,
                                                boolean isDark, List<TextView> primaryTexts, List<TextView> secondaryTexts,
                                                List<Switch> switches, Switch.OnCheckedChangeListener changeListener) {
        LinearLayout row = new LinearLayout(activity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, UIHelpers.dp(activity, 10), 0, UIHelpers.dp(activity, 10));
        row.setClickable(true);
        row.setFocusable(true);

        LinearLayout textLayout = new LinearLayout(activity);
        textLayout.setOrientation(LinearLayout.VERTICAL);

        TextView text = UIHelpers.text(activity, label, 14,
                isDark ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328"), Typeface.NORMAL);
        text.setIncludeFontPadding(false);
        primaryTexts.add(text);
        textLayout.addView(text, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        if (subtitle != null && !subtitle.isEmpty()) {
            TextView sub = UIHelpers.text(activity, subtitle, 12,
                    isDark ? Color.parseColor("#8B949E") : Color.parseColor("#656D76"), Typeface.NORMAL);
            sub.setIncludeFontPadding(false);
            secondaryTexts.add(sub);
            LinearLayout.LayoutParams subLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            subLp.topMargin = UIHelpers.dp(activity, 2);
            textLayout.addView(sub, subLp);
        }

        row.addView(textLayout, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        Switch sw = new Switch(activity);
        sw.setChecked(initialValue);
        setupSwitchColors(activity, sw, isDark);
        sw.setOnCheckedChangeListener(changeListener);
        row.addView(sw, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        switches.add(sw);

        row.setOnClickListener(v -> sw.toggle());
        return row;
    }

    private static void setupSwitchColors(Context context, Switch sw, boolean isDark) {
        int[][] states = new int[][]{
                new int[]{android.R.attr.state_checked},
                new int[]{-android.R.attr.state_checked}
        };
        int[] thumbColors = new int[]{
                Color.WHITE,
                isDark ? Color.parseColor("#D0D7DE") : Color.parseColor("#8C959F")
        };
        int[] trackColors = new int[]{
                isDark ? Color.parseColor("#2E79E6") : Color.parseColor("#0969DA"),
                isDark ? Color.parseColor("#3B434F") : Color.parseColor("#D0D7DE")
        };
        sw.setThumbTintList(new ColorStateList(states, thumbColors));
        sw.setTrackTintList(new ColorStateList(states, trackColors));
    }

    private static final class ModeCardView extends LinearLayout {
        private final ImageView iconView;
        private final TextView labelView;
        private final GradientDrawable background;
        private boolean isDark;

        ModeCardView(Activity activity, int iconRes, String label, boolean selected, boolean isDark) {
            super(activity);
            this.isDark = isDark;
            setOrientation(VERTICAL);
            setGravity(Gravity.CENTER);
            int padV = UIHelpers.dp(activity, 7);
            setPadding(0, padV, 0, padV);

            background = new GradientDrawable();
            background.setCornerRadius(UIHelpers.dp(activity, 7));
            setBackground(background);

            iconView = new ImageView(activity);
            iconView.setImageResource(iconRes);
            LinearLayout.LayoutParams iconLp = new LinearLayout.LayoutParams(UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 20));
            iconLp.bottomMargin = UIHelpers.dp(activity, 4);
            addView(iconView, iconLp);

            labelView = UIHelpers.text(activity, label, 11, Color.WHITE, Typeface.NORMAL);
            labelView.setIncludeFontPadding(false);
            labelView.setGravity(Gravity.CENTER);
            labelView.setSingleLine(true);
            addView(labelView, new LinearLayout.LayoutParams(-2, -2));

            setSelected(selected);
        }

        void setTheme(boolean isDark) {
            this.isDark = isDark;
            setSelected(isSelected());
        }

        @Override
        public void setSelected(boolean selected) {
            super.setSelected(selected);
            int dp1 = UIHelpers.dp(getContext(), 1);
            if (selected) {
                background.setColor(isDark ? Color.parseColor("#262E79E6") : Color.parseColor("#EBF5FF"));
                background.setStroke(dp1 * 2, isDark ? Color.parseColor("#2E79E6") : Color.parseColor("#0969DA"));
                int accent = isDark ? Color.parseColor("#388BFD") : Color.parseColor("#0969DA");
                iconView.setColorFilter(accent);
                labelView.setTextColor(accent);
                labelView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            } else {
                background.setColor(isDark ? Color.parseColor("#22272E") : Color.parseColor("#F6F8FA"));
                background.setStroke(dp1, isDark ? Color.parseColor("#373E47") : Color.parseColor("#D0D7DE"));
                int unselected = isDark ? Color.parseColor("#8B949E") : Color.parseColor("#656D76");
                iconView.setColorFilter(unselected);
                labelView.setTextColor(unselected);
                labelView.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            }
        }
    }

    public static class MaxHeightScrollView extends ScrollView {
        private int maxHeight;

        public MaxHeightScrollView(Context context) {
            super(context);
            maxHeight = (int) (context.getResources().getDisplayMetrics().heightPixels * 0.65f);
        }

        public void setMaxHeight(int maxHeight) {
            this.maxHeight = maxHeight;
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            if (maxHeight > 0) {
                int hMode = MeasureSpec.getMode(heightMeasureSpec);
                int hSize = MeasureSpec.getSize(heightMeasureSpec);
                if (hMode == MeasureSpec.UNSPECIFIED || hSize > maxHeight) {
                    heightMeasureSpec = MeasureSpec.makeMeasureSpec(maxHeight, MeasureSpec.AT_MOST);
                }
            }
            super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        }
    }

    public static class SheetRootLayout extends LinearLayout {
        private final int touchSlop;
        private float downX, downY;
        private boolean isDragging = false;
        private Dialog dialog;
        private ScrollView scrollView;

        public SheetRootLayout(Context context) {
            super(context);
            touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        }

        public void setDialog(Dialog dialog) {
            this.dialog = dialog;
        }

        public void setScrollView(ScrollView scrollView) {
            this.scrollView = scrollView;
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent ev) {
            switch (ev.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = ev.getRawX();
                    downY = ev.getRawY();
                    isDragging = false;
                    break;
                case MotionEvent.ACTION_MOVE:
                    float dy = ev.getRawY() - downY;
                    float dx = ev.getRawX() - downX;
                    if (dy > touchSlop && dy > Math.abs(dx) * 1.5f) {
                        if (scrollView != null && scrollView.canScrollVertically(-1)) {
                            return false;
                        }
                        isDragging = true;
                        return true;
                    }
                    break;
            }
            return super.onInterceptTouchEvent(ev);
        }

        @Override
        public boolean onTouchEvent(MotionEvent ev) {
            switch (ev.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = ev.getRawX();
                    downY = ev.getRawY();
                    return true;
                case MotionEvent.ACTION_MOVE:
                    float dy = ev.getRawY() - downY;
                    if (dy > 0) {
                        setTranslationY(dy);
                    } else {
                        setTranslationY(0f);
                    }
                    return true;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    float totalDy = ev.getRawY() - downY;
                    if (totalDy > getResources().getDisplayMetrics().density * 60) {
                        if (dialog != null) dialog.dismiss();
                    } else {
                        animate().translationY(0f).setDuration(160).start();
                    }
                    isDragging = false;
                    return true;
            }
            return super.onTouchEvent(ev);
        }
    }
}
