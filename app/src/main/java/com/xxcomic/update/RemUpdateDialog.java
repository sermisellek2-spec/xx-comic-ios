package com.xxcomic.update;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;

public final class RemUpdateDialog {
    private RemUpdateDialog() {
    }

    public interface UpdateActionListener {
        void onAction(boolean ignoreToday);
    }

    public static AlertDialog show(Activity activity, AppRelease release,
                                   String currentVersionName, String formattedSize,
                                   Runnable onConfirm, Runnable onDismiss) {
        return show(activity, release, currentVersionName, formattedSize,
                ignoreToday -> { if (onConfirm != null) onConfirm.run(); },
                ignoreToday -> { if (onDismiss != null) onDismiss.run(); });
    }

    public static AlertDialog show(Activity activity, AppRelease release,
                                   String currentVersionName, String formattedSize,
                                   UpdateActionListener onConfirm, UpdateActionListener onDismiss) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            return null;
        }

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.HORIZONTAL);
        content.setGravity(Gravity.TOP);
        content.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16),
                UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 10));

        ImageView art = new ImageView(activity);
        art.setImageResource(R.drawable.rem_reader_resume);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        content.addView(art, new LinearLayout.LayoutParams(
                UIHelpers.dp(activity, 56), UIHelpers.dp(activity, 56)));

        LinearLayout copy = new LinearLayout(activity);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 2), 0, 0);

        TextView titleView = UIHelpers.text(activity, "发现新版本 " + release.versionName, 17, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(titleView);

        String metaText = "当前 " + currentVersionName + " · " + formattedSize;
        TextView metaView = UIHelpers.text(activity, metaText, 12, UIHelpers.TEXT3, Typeface.NORMAL);
        copy.addView(metaView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 3)));

        String notesText = TextUtils.isEmpty(release.releaseNotes)
                ? "包含最新的界面优化与稳定性修复"
                : release.releaseNotes;

        ScrollView notesScroll = new ScrollView(activity);
        notesScroll.setVerticalScrollBarEnabled(true);
        FrameLayout.LayoutParams scrollInnerParams = new FrameLayout.LayoutParams(-1, -2);
        TextView notesView = UIHelpers.text(activity, notesText, 13, UIHelpers.TEXT2, Typeface.NORMAL);
        notesView.setLineSpacing(UIHelpers.dp(activity, 2), 1f);
        notesScroll.addView(notesView, scrollInnerParams);

        // Constrain max height so long release notes scroll without pushing dialog buttons off-screen
        int maxHeightPx = UIHelpers.dp(activity, 160);
        LinearLayout notesHost = new LinearLayout(activity) {
            @Override
            protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
                int mode = MeasureSpec.getMode(heightMeasureSpec);
                int size = MeasureSpec.getSize(heightMeasureSpec);
                if (mode == MeasureSpec.UNSPECIFIED || size > maxHeightPx) {
                    heightMeasureSpec = MeasureSpec.makeMeasureSpec(maxHeightPx, MeasureSpec.AT_MOST);
                }
                super.onMeasure(widthMeasureSpec, heightMeasureSpec);
            }
        };
        notesHost.setOrientation(LinearLayout.VERTICAL);
        notesHost.addView(notesScroll, new LinearLayout.LayoutParams(-1, -2));

        copy.addView(notesHost, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 8)));

        CheckBox ignoreTodayCheck = new CheckBox(activity);
        ignoreTodayCheck.setText("今日不再提示");
        ignoreTodayCheck.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        ignoreTodayCheck.setTextColor(UIHelpers.TEXT3);
        ignoreTodayCheck.setChecked(false);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            ignoreTodayCheck.setButtonTintList(ColorStateList.valueOf(UIHelpers.ACCENT));
        }
        LinearLayout.LayoutParams checkLp = new LinearLayout.LayoutParams(-2, -2);
        checkLp.topMargin = UIHelpers.dp(activity, 6);
        copy.addView(ignoreTodayCheck, checkLp);

        content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        AlertDialog.Builder builder = new AlertDialog.Builder(activity)
                .setView(content)
                .setCancelable(true)
                .setPositiveButton("立即更新", (dialog, which) -> {
                    if (onConfirm != null) onConfirm.onAction(ignoreTodayCheck.isChecked());
                })
                .setNegativeButton("稍后再说", (dialog, which) -> {
                    if (onDismiss != null) onDismiss.onAction(ignoreTodayCheck.isChecked());
                })
                .setOnCancelListener(dialog -> {
                    if (onDismiss != null) onDismiss.onAction(ignoreTodayCheck.isChecked());
                });

        AlertDialog dialog = builder.create();
        dialog.setOnShowListener(ignored -> {
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(UIHelpers.round(
                        UIHelpers.CARD, UIHelpers.dp(activity, 8), Color.TRANSPARENT));
                int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels
                        - UIHelpers.dp(activity, 40), UIHelpers.dp(activity, 328));
                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            }
            Button positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            if (positive != null) {
                positive.setTextColor(UIHelpers.ACCENT);
                positive.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            Button negative = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (negative != null) {
                negative.setTextColor(UIHelpers.TEXT3);
                negative.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }

            // Smooth entrance animation (200ms alpha and subtle scale)
            content.setAlpha(0f);
            content.setScaleX(0.95f);
            content.setScaleY(0.95f);
            content.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(200)
                    .start();
        });

        dialog.show();
        return dialog;
    }
}
