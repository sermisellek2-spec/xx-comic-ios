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
    private final ImageLoader loader;
    private final Listener listener;
    private boolean pinchZoomEnabled = true;
    private boolean animationDisabled = false;
    private float downX, downY;
    private long downTime;
    private int downPage;
    private boolean blockedGesture, disposed;
    private boolean controlsVisible;
    private boolean navigationTriggeredInGesture;
    private long lastNavigateTime = 0L;
    private static final long MIN_NAVIGATE_INTERVAL_MS = 200L;

    public PagedReaderView(Context context, List<String> images, int initialPage, int inputMode,
                           boolean leftHand, boolean pinchZoomEnabled, boolean animationDisabled, ImageLoader loader, Listener listener) {
        super(context);
        this.urls = new ArrayList<>(images);
        this.inputMode = inputMode;
        this.leftHand = leftHand;
        this.loader = loader;
        this.pinchZoomEnabled = pinchZoomEnabled;
        this.animationDisabled = animationDisabled;
        this.listener = listener;
        setBackgroundColor(Color.rgb(12, 20, 32));
        pager = new ViewPager2(context);
        pager.setLayoutDirection(leftHand ? View.LAYOUT_DIRECTION_RTL : View.LAYOUT_DIRECTION_LTR);
        pager.setOrientation(ViewPager2.ORIENTATION_HORIZONTAL);
        updateUserInputEnabled();
        pager.setOffscreenPageLimit(1);
        pager.setVerticalScrollBarEnabled(false);
        pager.setHorizontalScrollBarEnabled(false);
        View child = pager.getChildAt(0);
        if (child != null) {
            child.setVerticalScrollBarEnabled(false);
            child.setHorizontalScrollBarEnabled(false);
        }
        addView(pager, new FrameLayout.LayoutParams(-1, -1));
        pager.setAdapter(new RecyclerView.Adapter<Holder>() {
            @Override public Holder onCreateViewHolder(ViewGroup parent, int type) {
                ZoomImageView image = new ZoomImageView(context);
                image.setLayoutParams(new ViewGroup.LayoutParams(-1, -1));
                image.setPinchZoomEnabled(PagedReaderView.this.pinchZoomEnabled);
                Holder holder = new Holder(image);
                holders.add(holder);
                image.setListener(new ZoomImageView.Listener() {
                    @Override public void onTap(float x, float y) {
                        if (disposed || holder.getBindingAdapterPosition() != currentPage()) return;
                        if (controlsVisible) {
                            listener.onToggleControls();
                            return;
                        }
                        if (y < image.getHeight() * .25f || y > image.getHeight() * .75f) return;
                        boolean left = x < image.getWidth() * .28f, right = x > image.getWidth() * .72f;
                        if (inputMode != 1 && !image.isZoomed() && (left || right)) listener.onNavigate(ReaderNavigation.tapDelta(left, leftHand));
                        else listener.onToggleControls();
                    }
                    @Override public void onZoomChanged(boolean zoomed) {
                        if (!disposed && holder.getBindingAdapterPosition() == currentPage()) {
                            updateUserInputEnabled();
                        }
                    }
                });
                return holder;
            }
            @Override public void onBindViewHolder(Holder holder, int position) {
                if (holder.future != null) holder.future.cancel(true);
                holder.image.setTag(urls.get(position));
                holder.image.setContentDescription("第 " + (position + 1) + " / " + urls.size() + " 页");
                holder.image.setImageDrawable(null);
                holder.future = loader.load(holder.image, urls.get(position));
            }
            @Override public void onViewRecycled(Holder holder) {
                if (holder.future != null) holder.future.cancel(true);
                holder.image.setTag(null);
                holder.image.setImageDrawable(null);
            }
            @Override public int getItemCount() { return urls.size(); }
        });
        pager.setCurrentItem(Math.max(0, Math.min(urls.size() - 1, initialPage)), false);
        pager.registerOnPageChangeCallback(new ViewPager2.OnPageChangeCallback() {
            @Override public void onPageSelected(int position) {
                if (disposed) return;
                for (Holder holder : holders) if (holder.getBindingAdapterPosition() != position) holder.image.resetZoom();
                updateUserInputEnabled();
                listener.onPageChanged(position);
            }
        });
    }

    public PagedReaderView(Context context, List<String> images, int initialPage, int inputMode,
                           boolean leftHand, boolean pinchZoomEnabled, ImageLoader loader, Listener listener) {
        this(context, images, initialPage, inputMode, leftHand, pinchZoomEnabled, false, loader, listener);
    }

    public PagedReaderView(Context context, List<String> images, int initialPage, int inputMode,
                           boolean leftHand, ImageLoader loader, Listener listener) {
        this(context, images, initialPage, inputMode, leftHand, true, false, loader, listener);
    }

    public void setPinchZoomEnabled(boolean enabled) {
        this.pinchZoomEnabled = enabled;
        for (Holder holder : holders) {
            if (holder.image != null) holder.image.setPinchZoomEnabled(enabled);
        }
    }

    public void setAnimationDisabled(boolean disabled) {
        this.animationDisabled = disabled;
        blockedGesture = true;
        updateUserInputEnabled();
        if (disabled && pager != null && pager.getScrollState() != ViewPager2.SCROLL_STATE_IDLE) {
            pager.registerOnPageChangeCallback(new ViewPager2.OnPageChangeCallback() {
                @Override
                public void onPageScrollStateChanged(int state) {
                    if (state == ViewPager2.SCROLL_STATE_IDLE) {
                        pager.unregisterOnPageChangeCallback(this);
                        if (!disposed && pager != null) {
                            pager.setCurrentItem(pager.getCurrentItem(), false);
                            updateUserInputEnabled();
                        }
                    }
                }
            });
        }
    }

    public boolean isAnimationDisabled() {
        return animationDisabled;
    }

    public void setControlsVisible(boolean visible) {
        this.controlsVisible = visible;
    }

    public boolean isControlsVisible() {
        return controlsVisible;
    }

    public void setCanvasBackground(int color) {
        setBackgroundColor(color);
    }

    public void refreshVisiblePages() {
        if (disposed || loader == null) return;
        for (Holder holder : holders) {
            int pos = holder.getBindingAdapterPosition();
            if (pos >= 0 && pos < urls.size() && holder.image != null) {
                holder.image.resetZoom();
                if (holder.future != null) holder.future.cancel(true);
                holder.image.setTag(urls.get(pos));
                holder.future = loader.load(holder.image, urls.get(pos));
            }
        }
        updateUserInputEnabled();
    }

    private void updateUserInputEnabled() {
        if (pager != null) {
            pager.setUserInputEnabled(inputMode != 1 && !isZoomed() && !animationDisabled);
        }
    }

    public int currentPage() { return pager.getCurrentItem(); }
    public boolean isZoomed() {
        for (Holder holder : holders) if (holder.getBindingAdapterPosition() == currentPage()) return holder.image.isZoomed();
        return false;
    }
    public void moveTo(int page) { if (!disposed) pager.setCurrentItem(page, !animationDisabled); }
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
            navigationTriggeredInGesture = false;
        }
        if (action == MotionEvent.ACTION_POINTER_DOWN || event.getPointerCount() > 1) {
            blockedGesture = true;
        }
        if (action == MotionEvent.ACTION_CANCEL) {
            blockedGesture = true;
            navigationTriggeredInGesture = true;
        }
        float dx = event.getX() - downX, dy = event.getY() - downY;
        if (action == MotionEvent.ACTION_MOVE && (Math.abs(dx) > dp(8) || Math.abs(dy) > dp(8))) listener.onInteraction();
        boolean result = super.dispatchTouchEvent(event);
        if (action == MotionEvent.ACTION_UP && inputMode != 1 && !blockedGesture && !isZoomed()
                && !navigationTriggeredInGesture
                && Math.abs(dx) > dp(36) && Math.abs(dx) > Math.abs(dy) * 1.1f
                && event.getEventTime() - downTime < 1000) {
            long now = event.getEventTime();
            if (now - lastNavigateTime >= MIN_NAVIGATE_INTERVAL_MS) {
                int delta = ReaderNavigation.swipeDelta(dx, leftHand);
                if (delta != 0) {
                    lastNavigateTime = now;
                    navigationTriggeredInGesture = true;
                    if (animationDisabled) {
                        listener.onNavigate(delta);
                    } else if (currentPage() == downPage && ReaderNavigation.crossesChapter(downPage, urls.size(), delta)) {
                        listener.onNavigate(delta);
                    }
                }
            }
        }
        return result;
    }
    private float dp(int value) { return value * getResources().getDisplayMetrics().density; }
    private static final class Holder extends RecyclerView.ViewHolder {
        final ZoomImageView image;
        Future<?> future;
        Holder(ZoomImageView image) { super(image); this.image = image; }
    }
}
