package com.xxcomic.reader;

import android.content.Context;
import android.graphics.Color;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.recyclerview.widget.RecyclerView;
import androidx.viewpager2.widget.ViewPager2;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Future;

public final class PagedReaderView extends FrameLayout {
    public interface Listener {
        void onPageChanged(int index);
        void onNavigate(int delta);
        void onToggleControls();
        void onInteraction();
    }
    public interface ImageLoader { Future<?> load(ZoomImageView image, String url); }
    private final ViewPager2 pager;
    private final List<Holder> holders = new ArrayList<>();
    private final List<String> urls;
    private final int inputMode;
    private final boolean leftHand;
    private final Listener listener;
    private float downX, downY;
    private long downTime;
    private int downPage;
    private boolean blockedGesture, disposed;

    public PagedReaderView(Context context, List<String> images, int initialPage, int inputMode,
                           boolean leftHand, ImageLoader loader, Listener listener) {
        super(context);
        this.urls = new ArrayList<>(images);
        this.inputMode = inputMode;
        this.leftHand = leftHand;
        this.listener = listener;
        setBackgroundColor(Color.rgb(12, 20, 32));
        pager = new ViewPager2(context);
        pager.setLayoutDirection(leftHand ? View.LAYOUT_DIRECTION_RTL : View.LAYOUT_DIRECTION_LTR);
        pager.setOrientation(ViewPager2.ORIENTATION_HORIZONTAL);
        pager.setUserInputEnabled(inputMode == 2);
        pager.setOffscreenPageLimit(1);
        addView(pager, new FrameLayout.LayoutParams(-1, -1));
        pager.setAdapter(new RecyclerView.Adapter<Holder>() {
            @Override public Holder onCreateViewHolder(ViewGroup parent, int type) {
                ZoomImageView image = new ZoomImageView(context);
                image.setLayoutParams(new ViewGroup.LayoutParams(-1, -1));
                Holder holder = new Holder(image);
                holders.add(holder);
                image.setListener(new ZoomImageView.Listener() {
                    @Override public void onTap(float x, float y) {
                        if (disposed || holder.index != currentPage()) return;
                        if (y < image.getHeight() * .25f || y > image.getHeight() * .75f) return;
                        boolean left = x < image.getWidth() * .28f, right = x > image.getWidth() * .72f;
                        if (inputMode == 0 && !image.isZoomed() && (left || right)) listener.onNavigate(ReaderNavigation.tapDelta(left, leftHand));
                        else listener.onToggleControls();
                    }
                    @Override public void onZoomChanged(boolean zoomed) {
                        if (!disposed && holder.index == currentPage()) pager.setUserInputEnabled(inputMode == 2 && !zoomed);
                    }
                });
                return holder;
            }
            @Override public void onBindViewHolder(Holder holder, int position) {
                if (holder.future != null) holder.future.cancel(true);
                holder.index = position;
                holder.image.setTag(urls.get(position));
                holder.image.setContentDescription("第 " + (position + 1) + " / " + urls.size() + " 页");
                holder.image.setImageDrawable(null);
                holder.future = loader.load(holder.image, urls.get(position));
            }
            @Override public void onViewRecycled(Holder holder) {
                if (holder.future != null) holder.future.cancel(true);
                holder.index = -1;
                holder.image.setTag(null);
                holder.image.setImageDrawable(null);
            }
            @Override public int getItemCount() { return urls.size(); }
        });
        pager.setCurrentItem(Math.max(0, Math.min(urls.size() - 1, initialPage)), false);
        pager.registerOnPageChangeCallback(new ViewPager2.OnPageChangeCallback() {
            @Override public void onPageSelected(int position) {
                if (disposed) return;
                for (Holder holder : holders) if (holder.index != position) holder.image.resetZoom();
                pager.setUserInputEnabled(inputMode == 2 && !isZoomed());
                listener.onPageChanged(position);
            }
        });
    }
    public int currentPage() { return pager.getCurrentItem(); }
    public boolean isZoomed() {
        for (Holder holder : holders) if (holder.index == currentPage()) return holder.image.isZoomed();
        return false;
    }
    public void moveTo(int page) { if (!disposed) pager.setCurrentItem(page, true); }
    public void release() {
        disposed = true;
        for (Holder holder : holders) {
            if (holder.future != null) holder.future.cancel(true);
            holder.image.setTag(null);
        }
        pager.setAdapter(null);
        holders.clear();
    }
    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            downX = event.getX(); downY = event.getY(); downTime = event.getEventTime();
            downPage = currentPage(); blockedGesture = isZoomed();
        }
        if (event.getPointerCount() > 1) blockedGesture = true;
        float dx = event.getX() - downX, dy = event.getY() - downY;
        if (action == MotionEvent.ACTION_MOVE && (Math.abs(dx) > dp(8) || Math.abs(dy) > dp(8))) listener.onInteraction();
        boolean result = super.dispatchTouchEvent(event);
        if (action == MotionEvent.ACTION_UP && inputMode == 2 && !blockedGesture && !isZoomed()
                && Math.abs(dx) > dp(72) && Math.abs(dx) > Math.abs(dy) * 1.35f
                && event.getEventTime() - downTime < 1200 && currentPage() == downPage) {
            int delta = ReaderNavigation.swipeDelta(dx, leftHand);
            if (ReaderNavigation.crossesChapter(downPage, urls.size(), delta)) listener.onNavigate(delta);
        }
        return result;
    }
    private float dp(int value) { return value * getResources().getDisplayMetrics().density; }
    private static final class Holder extends RecyclerView.ViewHolder {
        final ZoomImageView image;
        Future<?> future;
        int index = -1;
        Holder(ZoomImageView image) { super(image); this.image = image; }
    }
}
