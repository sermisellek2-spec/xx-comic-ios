package com.xxcomic;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public final class DataHelpers {
    private DataHelpers() {
    }

    public static List<Integer> chapterOrder(boolean chapterDesc, int size) {
        List<Integer> order = new ArrayList<>();
        if (chapterDesc) {
            for (int i = size - 1; i >= 0; i--) order.add(i);
        } else {
            for (int i = 0; i < size; i++) order.add(i);
        }
        return order;
    }

    public static String formatRelative(long ts) {
        long diff = System.currentTimeMillis() - ts;
        long min = diff / 60000L;
        if (min < 1L) return "刚刚";
        if (min < 60L) return min + " 分钟前";
        long hr = min / 60L;
        if (hr < 24L) return hr + " 小时前";
        long day = hr / 24L;
        if (day == 1L) return "昨天";
        if (day < 7L) return day + " 天前";
        if (day < 30L) return (day / 7L) + " 周前";
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());
        return sdf.format(new Date(ts));
    }
}
