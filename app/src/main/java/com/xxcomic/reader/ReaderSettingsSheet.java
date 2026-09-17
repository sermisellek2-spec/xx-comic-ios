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
import android.widget.Switch;
import android.widget.TextView;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;

public final class ReaderSettingsSheet {

    public static final int MODE_SCROLL = 0;
    public static final int MODE_NORMAL = 1;
    public static final int MODE_MANGA = 2;

    public interface OnSettingsChangeListener {
        void onReadingModeChanged(int mode);
        void onHideStatusBadgeChanged(boolean hide);
        void onEinkModeChanged(boolean eink);
        void onPinchZoomChanged(boolean enabled);
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
        return show(activity, initialMode, initialHideBadge, initialEink, true, listener);
    }

    public static Dialog show(Activity activity, int initialMode, boolean initialHideBadge, boolean initialEink,
                              boolean initialPinchZoom, OnSettingsChangeListener listener) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return null;

        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setCanceledOnTouchOutside(true);

        SheetRootLayout panel = new SheetRootLayout(activity);
        panel.setDialog(dialog);
        panel.setOrientation(LinearLayout.VERTICAL);
        int padH = UIHelpers.dp(activity, 18);
        panel.setPadding(padH, UIHelpers.dp(activity, 10), padH, UIHelpers.dp(activity, 24));

        GradientDrawable panelBg = new GradientDrawable();
        panelBg.setColor(Color.parseColor("#1C2128"));
        float r = UIHelpers.dp(activity, 18);
        panelBg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        panel.setBackground(panelBg);

        // Top drag handle
        View handle = new View(activity);
        GradientDrawable handleBg = new GradientDrawable();
        handleBg.setColor(Color.parseColor("#444C56"));
        handleBg.setCornerRadius(UIHelpers.dp(activity, 2));
        handle.setBackground(handleBg);
        LinearLayout.LayoutParams handleLp = new LinearLayout.LayoutParams(UIHelpers.dp(activity, 36), UIHelpers.dp(activity, 4));
        handleLp.gravity = Gravity.CENTER_HORIZONTAL;
        handleLp.topMargin = UIHelpers.dp(activity, 2);
        handleLp.bottomMargin = UIHelpers.dp(activity, 14);
        panel.addView(handle, handleLp);

        // Row 1: 阅读模式
        LinearLayout modeRow = new LinearLayout(activity);
        modeRow.setOrientation(LinearLayout.HORIZONTAL);
        modeRow.setGravity(Gravity.CENTER_VERTICAL);
        modeRow.setPadding(0, UIHelpers.dp(activity, 4), 0, UIHelpers.dp(activity, 10));

        TextView modeTitle = UIHelpers.text(activity, "阅读模式", 14, Color.parseColor("#E6EDF3"), Typeface.NORMAL);
        modeTitle.setIncludeFontPadding(false);
        modeRow.addView(modeTitle, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 68), -2));

        LinearLayout cardsContainer = new LinearLayout(activity);
        cardsContainer.setOrientation(LinearLayout.HORIZONTAL);
        cardsContainer.setGravity(Gravity.CENTER_VERTICAL);

        ModeCardView[] cardViews = new ModeCardView[3];
        int[] activeMode = new int[]{initialMode};

        cardViews[0] = new ModeCardView(activity, R.drawable.ic_mode_scroll, "卷轴模式", initialMode == MODE_SCROLL);
        cardViews[1] = new ModeCardView(activity, R.drawable.ic_mode_normal, "普通模式", initialMode == MODE_NORMAL);
        cardViews[2] = new ModeCardView(activity, R.drawable.ic_mode_manga, "日漫模式", initialMode == MODE_MANGA);

        for (int i = 0; i < 3; i++) {
            final int modeIndex = i;
            final ModeCardView card = cardViews[i];
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
        panel.addView(modeRow);

        // Row 2: 隐藏右下角状态信息
        LinearLayout rowHideStatus = createSwitchRow(activity, "隐藏右下角状态信息", initialHideBadge, (view, isChecked) -> {
            if (listener != null) {
                listener.onHideStatusBadgeChanged(isChecked);
            }
        });
        panel.addView(rowHideStatus);

        // Row 3: 墨水屏模式
        LinearLayout rowEink = createSwitchRow(activity, "墨水屏模式", initialEink, (view, isChecked) -> {
            if (listener != null) {
                listener.onEinkModeChanged(isChecked);
            }
        });
        panel.addView(rowEink);

        // Row 4: 搓指放大
        LinearLayout rowPinchZoom = createSwitchRow(activity, "搓指放大", initialPinchZoom, (view, isChecked) -> {
            if (listener != null) {
                listener.onPinchZoomChanged(isChecked);
            }
        });
        panel.addView(rowPinchZoom);

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

    private static LinearLayout createSwitchRow(Activity activity, String label, boolean initialValue,
                                                Switch.OnCheckedChangeListener changeListener) {
        LinearLayout row = new LinearLayout(activity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, UIHelpers.dp(activity, 12), 0, UIHelpers.dp(activity, 12));
        row.setClickable(true);
        row.setFocusable(true);

        TextView text = UIHelpers.text(activity, label, 14, Color.parseColor("#E6EDF3"), Typeface.NORMAL);
        text.setIncludeFontPadding(false);
        row.addView(text, new LinearLayout.LayoutParams(0, -2, 1f));

        Switch sw = new Switch(activity);
        sw.setChecked(initialValue);
        setupSwitchColors(activity, sw);
        sw.setOnCheckedChangeListener(changeListener);
        row.addView(sw, new LinearLayout.LayoutParams(-2, -2));

        row.setOnClickListener(v -> sw.toggle());
        return row;
    }

    private static void setupSwitchColors(Context context, Switch sw) {
        int[][] states = new int[][]{
                new int[]{android.R.attr.state_checked},
                new int[]{-android.R.attr.state_checked}
        };
        int[] thumbColors = new int[]{
                Color.WHITE,
                Color.parseColor("#D0D7DE")
        };
        int[] trackColors = new int[]{
                Color.parseColor("#2E79E6"),
                Color.parseColor("#3B434F")
        };
        sw.setThumbTintList(new ColorStateList(states, thumbColors));
        sw.setTrackTintList(new ColorStateList(states, trackColors));
    }

    private static final class ModeCardView extends LinearLayout {
        private final ImageView iconView;
        private final TextView labelView;
        private final GradientDrawable background;

        ModeCardView(Activity activity, int iconRes, String label, boolean selected) {
            super(activity);
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

        @Override
        public void setSelected(boolean selected) {
            super.setSelected(selected);
            int dp1 = UIHelpers.dp(getContext(), 1);
            if (selected) {
                background.setColor(Color.parseColor("#262E79E6")); // translucent accent blue
                background.setStroke(dp1 * 2, Color.parseColor("#2E79E6"));
                iconView.setColorFilter(Color.parseColor("#388BFD"));
                labelView.setTextColor(Color.parseColor("#388BFD"));
                labelView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            } else {
                background.setColor(Color.parseColor("#22272E"));
                background.setStroke(dp1, Color.parseColor("#373E47"));
                iconView.setColorFilter(Color.parseColor("#8B949E"));
                labelView.setTextColor(Color.parseColor("#8B949E"));
                labelView.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            }
        }
    }

    public static class SheetRootLayout extends LinearLayout {
        private final int touchSlop;
        private float downX, downY;
        private boolean isDragging = false;
        private Dialog dialog;

        public SheetRootLayout(Context context) {
            super(context);
            touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        }

        public void setDialog(Dialog dialog) {
            this.dialog = dialog;
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
