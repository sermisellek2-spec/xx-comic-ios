package com.xxcomic;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.util.List;

public final class Components {
    private Components() {
    }

    public static LinearLayout comicRow(Activity ctx, AppModels.Comic comic, boolean withContinue, Runnable onDetail) {
        LinearLayout row = UIHelpers.card(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setOnClickListener(v -> onDetail.run());
        View cover = new View(ctx);
        cover.setBackground(UIHelpers.gradient(comic.colors, UIHelpers.dp(ctx, 8)));
        row.addView(cover, new LinearLayout.LayoutParams(UIHelpers.dp(ctx, 80), UIHelpers.dp(ctx, 107)));
        LinearLayout info = new LinearLayout(ctx);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(ctx, 12), 0, 0, 0);
        TextView title = UIHelpers.text(ctx, comic.title, 16, UIHelpers.TEXT, Typeface.NORMAL);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        info.addView(title);
        info.addView(UIHelpers.text(ctx, comic.sourceName + " " + comic.latestChapter, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 6)));
        info.addView(UIHelpers.text(ctx, comic.lastChapter, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 8)));
        if (withContinue) {
            Button button = UIHelpers.brandButton(ctx, "continue");
            button.setOnClickListener(v -> onDetail.run());
            info.addView(button, UIHelpers.marginTop(UIHelpers.dp(ctx, 96), UIHelpers.dp(ctx, 8), -2, UIHelpers.dp(ctx, 32)));
        }
        row.addView(info, UIHelpers.weight(1));
        return row;
    }

    public static LinearLayout resultCard(Activity ctx, AppModels.Comic comic, Runnable onClick) {
        LinearLayout item = new LinearLayout(ctx);
        item.setOrientation(LinearLayout.VERTICAL);
        item.setOnClickListener(v -> onClick.run());
        View cover = new View(ctx);
        cover.setBackground(UIHelpers.gradient(comic.colors, UIHelpers.dp(ctx, 10)));
        item.addView(cover, new LinearLayout.LayoutParams(-1, UIHelpers.dp(ctx, 214)));
        TextView title = UIHelpers.text(ctx, comic.title, 13, UIHelpers.TEXT, Typeface.NORMAL);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        item.addView(title, UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 7)));
        TextView meta = UIHelpers.text(ctx, comic.author, 11, UIHelpers.TEXT2, Typeface.NORMAL);
        meta.setSingleLine(true);
        meta.setEllipsize(TextUtils.TruncateAt.END);
        item.addView(meta, UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 3)));
        return item;
    }

    /**
     * @deprecated 已废弃，请使用 MainActivity.sourceCard() 替代
     * 旧版本源卡片包含绿色开关背景，不符合日漫清爽设计规范
     */
    @Deprecated
    public static LinearLayout sourceCard(Activity ctx, AppModels.Source source, Runnable onToggle) {
        LinearLayout card = UIHelpers.card(ctx);
        card.setOnClickListener(v -> onToggle.run());
        LinearLayout top = new LinearLayout(ctx);
        top.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout info = new LinearLayout(ctx);
        info.setOrientation(LinearLayout.VERTICAL);
        TextView sourceTitle = UIHelpers.text(ctx, source.name, 16, UIHelpers.TEXT, Typeface.NORMAL);
        sourceTitle.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        info.addView(sourceTitle);
        info.addView(UIHelpers.text(ctx, source.domain, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 3)));
        top.addView(info, UIHelpers.weight(1));
        // 注意：此开关使用 GREEN 背景色，已被新的 iOS 风格 toggle 替代
        TextView sw = UIHelpers.text(ctx, source.enabled ? "ON" : "OFF", 12, Color.WHITE, Typeface.NORMAL);
        sw.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        sw.setGravity(Gravity.CENTER);
        sw.setBackground(UIHelpers.round(source.enabled ? UIHelpers.GREEN : UIHelpers.TEXT3, UIHelpers.dp(ctx, 14), Color.TRANSPARENT));
        top.addView(sw, new LinearLayout.LayoutParams(UIHelpers.dp(ctx, 50), UIHelpers.dp(ctx, 28)));
        card.addView(top);
        card.addView(UIHelpers.text(ctx, (source.enabled ? "ON" : "OFF") + " check 2min", 11, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 12)));
        return card;
    }

    public static HorizontalScrollView searchTagRow(Activity ctx, List<String> values, String selectedTag, Runnable onTagClick) {
        HorizontalScrollView scroll = new HorizontalScrollView(ctx);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (String value : values) {
            TextView chip = UIHelpers.pill(ctx, value, value.equals(selectedTag) ? UIHelpers.ACCENT : UIHelpers.SURFACE, value.equals(selectedTag) ? Color.WHITE : UIHelpers.TEXT3);
            chip.setOnClickListener(v -> onTagClick.run());
            row.addView(chip, UIHelpers.marginRight(-2, UIHelpers.dp(ctx, 8)));
        }
        scroll.addView(row, UIHelpers.wrap());
        return scroll;
    }

    public static LinearLayout searchEmptyState(Activity ctx, Runnable onClear) {
        LinearLayout box = emptyState(ctx, "no results", "try another keyword", "clear filters", onClear);
        View button = box.getChildAt(box.getChildCount() - 1);
        button.setOnClickListener(v -> onClear.run());
        return box;
    }

    public static LinearLayout emptyState(Activity ctx, String title, String desc, String action, Runnable onAction) {
        LinearLayout box = new LinearLayout(ctx);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(0, UIHelpers.dp(ctx, 40), 0, 0);
        box.addView(UIHelpers.text(ctx, "*", 42, UIHelpers.TEXT3, Typeface.NORMAL));
        box.addView(UIHelpers.text(ctx, title, 16, UIHelpers.TEXT2, Typeface.BOLD), UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 14)));
        box.addView(UIHelpers.text(ctx, desc, 13, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(ctx, 8)));
        Button button = UIHelpers.secondaryButton(ctx, action);
        button.setOnClickListener(v -> onAction.run());
        box.addView(button, UIHelpers.marginTop(UIHelpers.dp(ctx, 110), UIHelpers.dp(ctx, 16), -2, UIHelpers.dp(ctx, 42)));
        return box;
    }
}
