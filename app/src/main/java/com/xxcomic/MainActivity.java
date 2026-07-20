package com.xxcomic;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BlurMaskFilter;
import android.graphics.Color;
import android.graphics.RenderEffect;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.PopupWindow;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.xxcomic.source.BaoziComicSource;
import com.xxcomic.source.AikanComicSource;
import com.xxcomic.source.ComicModels;
import com.xxcomic.source.ComicSource;
import com.xxcomic.source.D5d6ComicSource;
import com.xxcomic.source.ManbenComicSource;
import com.xxcomic.source.GmhComicSource;
import com.xxcomic.source.HiperdexComicSource;
import com.xxcomic.source.ManhuaguiComicSource;
import com.xxcomic.source.Hanman18ComicSource;
import com.xxcomic.source.MkzhanComicSource;
import com.xxcomic.source.Mhua5ComicSource;
import com.xxcomic.source.SourceConfig;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.FutureTask;
import java.util.concurrent.Future;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

public class MainActivity extends Activity {
    private static final String PREFS_NAME = "xx-comic";
    private static final String ALL_TAG = "全部";
    private static final int DETAIL_HERO_DP = 128;
    private static final int CHAPTER_DRAWER_BATCH_SIZE = 40;
    private static final long READER_PROGRESS_ANIM_MS = 30L;
    private static final int READER_POSITION_SCALE = 10000;
    private static final long READER_POSITION_SAVE_DELAY_MS = 250L;
    private static final long READER_MAX_DECODE_PIXELS = 8000000L;
    private static final long READER_MAX_DECODE_BYTES = 32L * 1024L * 1024L;
    private static final String SUMMARIES_CACHE_KEY = "cache.summaries";
    private static final String DETAILS_CACHE_KEY = "cache.details";
    private static final String CHAPTERS_CACHE_KEY = "cache.chapters";
    private static final long IMAGE_CACHE_MAX_BYTES = 1000L * 1024L * 1024L;
    private static final String ERROR_LOGS_KEY = "error.logs";
    private static final int ERROR_LOG_MAX_CHARS = 60000;
    private static final int IMPORT_SOURCES_REQUEST = 1001;
    private static final int EXPORT_SOURCES_REQUEST = 1002;
    private static final int EXPORT_LOGS_REQUEST = 1003;
    private static final String IMAGE_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private final Handler main = new Handler(Looper.getMainLooper());
    // 按模块拆分线程池，互不阻塞：搜索中切到收藏页，封面图走 imageIo 不被搜索阻塞
    private final ExecutorService searchIo = Executors.newFixedThreadPool(10);
    private final ExecutorService detailIo = Executors.newFixedThreadPool(2);
    private final ExecutorService imageIo = Executors.newFixedThreadPool(4);
    private final ExecutorService miscIo = Executors.newFixedThreadPool(1);
    private final ScheduledExecutorService scheduledIo = Executors.newScheduledThreadPool(1);
    // 内存级封面缓存：切 Tab 重建结果列表时同步命中，避免 imageIo 被其他站源的网络加载
    // 占满 4 线程时、已解码封面的加载请求被排在网络任务后面阻塞而显示不出来。
    private final android.util.LruCache<String, Bitmap> imageMemoryCache =
            new android.util.LruCache<String, Bitmap>((int) (Runtime.getRuntime().maxMemory() / 8)) {
                @Override
                protected int sizeOf(String key, Bitmap value) {
                    return value == null ? 0 : value.getByteCount();
                }
            };
    private final Object imageCacheLock = new Object();
    private long imageCacheBytes = -1L;
    // 当前页的活跃 Future 列表，切屏时统一 cancel，避免旧页请求占用线程
    private List<Future<?>> currentScreenFutures = new ArrayList<>();
    private List<Future<?>> currentImageFutures = new ArrayList<>();
    private ComicSource sourceClient;
    private ComicSource mhua5Client;
    private ComicSource aikanClient;
    private ComicSource gmhClient;
    private ComicSource mkzhanClient;
    private ComicSource hiperdexClient;
    private ComicSource manhuaguiClient;
    private ComicSource hanman18Client;
    private ComicSource d5d6Client;
    private ComicSource manbenClient;
    private SourceConfig baoziConfig = SourceConfig.baozi(true);
    private SourceConfig mhua5Config = SourceConfig.mhua5(true);
    private SourceConfig aikanConfig = SourceConfig.aikan(true);
    private SourceConfig gmhConfig = SourceConfig.gmh(true);
    private SourceConfig mkzhanConfig = SourceConfig.mkzhan(true);
    private SourceConfig hiperdexConfig = SourceConfig.hiperdex(true);
    private SourceConfig manhuaguiConfig = SourceConfig.manhuagui(true);
    private SourceConfig hanman18Config = SourceConfig.hanman18(true);
    private SourceConfig d5d6Config = SourceConfig.d5d6(true);
    private SourceConfig manbenConfig = SourceConfig.manben(true);
    private final List<ComicModels.ComicSummary> searchResults = new ArrayList<>();
    private final List<ComicModels.ComicSummary> globalSearchResults = new ArrayList<>();
    private final List<String> globalSearchHistory = new ArrayList<>();
    private final Map<String, List<ComicModels.ComicSummary>> globalSearchResultsBySource = new LinkedHashMap<>();
    private final Map<String, Set<String>> globalSearchShownIdsBySource = new HashMap<>();
    private final Set<String> globalSearchFailedSourceIds = new HashSet<>();
    private final Set<String> globalSearchCompletedSourceIds = new HashSet<>();
    private final Map<String, ComicModels.ComicSummary> summaries = new LinkedHashMap<>();
    private final Map<String, ComicModels.ComicDetail> details = new HashMap<>();
    private final Map<String, ComicModels.ChapterPage> chapters = new HashMap<>();
    private final Set<String> refreshedComicIds = new HashSet<>();
    private final Set<String> refreshingComicIds = new HashSet<>();
    private final Map<String, DetailAction> pendingRefreshActions = new HashMap<>();
    private final List<String> favorites = new ArrayList<>();
    private final List<String> sourceCategories = new ArrayList<>();
    private final List<ComicModels.Source> customSources = new ArrayList<>();
    private final Map<String, Integer> progress = new HashMap<>();
    private final Map<String, Integer> readerPositions = new HashMap<>();
    private final Map<String, Long> favoriteAt = new HashMap<>();
    private final Map<String, Long> lastViewedAt = new HashMap<>();
    private final Runnable persistReaderPositionRunnable = this::saveLocalState;

    private FrameLayout root;
    private int currentTab = 1;
    private String searchQuery = "";
    private String favoriteQuery = "";
    private String globalSearchQuery = "";
    private String selectedSourceId = "baozimh";
    private String selectedRegion = "all";
    private String selectedState = "all";
    private String selectedRegionLabel = ALL_TAG;
    private String selectedStateLabel = ALL_TAG;
    private Runnable filterDrawerAction;
    private boolean sourceEnabled = true;
    private boolean mhua5Enabled = true;
    private boolean aikanEnabled = true;
    private boolean gmhEnabled = true;
    private boolean mkzhanEnabled = true;
    private boolean hiperdexEnabled = true;
    private boolean manhuaguiEnabled = true;
    private boolean hanman18Enabled = true;
    private boolean d5d6Enabled = true;
    private boolean manbenEnabled = true;
    private boolean chapterDesc = false;
    private int themeMode = 0;
    private boolean readerLeftHand = false;
    private String cacheSize = "42.6 MB";
    private int searchGeneration = 0;
    private int readerGeneration = 0;
    private int categoryGeneration = 0;
    private int readerChapterIndex = 0;
    private String activeDetailId = "";
    private boolean readerVisible = false;
    private boolean readerFullscreen = false;
    private boolean searchLoading = false;
    private boolean searchAppending = false;
    private boolean defaultSearchRefreshPending = false;
    private boolean searchHasMore = true;
    private int searchPage = 1;
    private boolean standaloneSearchVisible = false;
    private boolean historyVisible = false;
    private boolean standaloneSearchResultsMode = false;
    private boolean globalSearchLoading = false;
    private boolean activityDestroyed = false;
    private boolean pageLoading = false;
    private Runnable pageLoadingBackAction;
    private Runnable detailBackAction;
    private int pageLoadingGeneration = 0;
    private int pendingSearchScrollY = -1;
    private float edgeDownX = -1f;
    private float edgeDownY = -1f;
    private boolean edgeTracking = false;
    private float readerDownX = -1f;
    private float readerDownY = -1f;
    private long readerDownAt = 0L;
    private boolean bindingSearchText = false;
    private int globalSearchGeneration = 0;
    // —— 并发站源搜索流式填充 ——
    private LinearLayout globalSearchContent;      // 结果列表容器引用（增量 addView 用）
    private HorizontalScrollView globalSearchTabsScroller;  // 站源 Tab 行（持久，避免点击 Tab 时 scrollX 归零）
    private LinearLayout globalSearchResultsContainer;     // 当前选中站源的结果列表容器（持久，便于局部刷新）
    private final Set<String> globalSearchShownIds = new HashSet<>();  // 已显示 comicId 去重
    private String selectedGlobalSearchSourceId = "";
    private int globalSearchTotalSources;          // 本次搜索总站源数
    private int globalSearchCompletedSources;      // 已完成站源数（含失败）
    private int globalSearchFailedSources;         // 失败站源数
    private TextView globalSearchStatusView;       // 底部状态文字
    private View globalSearchLoadingView;          // loading 态视图引用（首个结果到来时移除）
    private String pendingExportJson = "";
    private String pendingLogText = "";
    private PopupWindow activePopup;
    private ScrollView searchScroll;
    private LinearLayout searchResultsContent;
    private View searchPagingFooter;
    // 搜索页分类栏折叠状态：用状态机 + reflow 守卫，避免 GONE/VISIBLE 引发 ScrollView clamp
    // scrollY 产生「隐藏→上滑→显示→下滑→隐藏」的闪烁循环。
    private boolean searchCategoryHidden;
    private boolean searchCategoryToggling;
    private View readerTopBar;
    private View readerBottomBar;
    private boolean nightThemeApplied = false;
    private final Runnable themeSwitchRunnable = new Runnable() {
        @Override public void run() {
            applyThemeAndSystemBars();
            rerenderCurrentScreen();
            scheduleThemeSwitch();
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
        applyThemeAndSystemBars();
        root = new FrameLayout(this);
        setContentView(root);
        rebuildSourceClients();
        restoreLocalState();
        applyThemeAndSystemBars();
        scheduleThemeSwitch();
        showTab(0);
    }

    @Override
    protected void onResume() {
        super.onResume();
        boolean themeChanged = refreshThemeIfChanged();
        scheduleThemeSwitch();
        if (themeChanged && root != null) rerenderCurrentScreen();
    }

    @Override
    protected void onPause() {
        super.onPause();
        saveLocalState();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        activityDestroyed = true;
        main.removeCallbacks(themeSwitchRunnable);
        main.removeCallbacks(persistReaderPositionRunnable);
        for (Future<?> f : currentScreenFutures) {
            if (f != null && !f.isDone()) f.cancel(true);
        }
        currentScreenFutures = new ArrayList<>();
        cancelCurrentImageTasks();
        pageLoadingGeneration++;
        readerGeneration++;
        categoryGeneration++;
        searchGeneration++;
        globalSearchGeneration++;
        pageLoading = false;
        readerVisible = false;
        pageLoadingBackAction = null;
        detailBackAction = null;
        searchIo.shutdownNow();
        detailIo.shutdownNow();
        imageIo.shutdownNow();
        miscIo.shutdown();
        scheduledIo.shutdownNow();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == IMPORT_SOURCES_REQUEST && resultCode == RESULT_OK && data != null && data.getData() != null) {
            importSourceConfig(data.getData());
        } else if (requestCode == EXPORT_SOURCES_REQUEST && resultCode == RESULT_OK && data != null && data.getData() != null) {
            writeExportSourceConfig(data.getData());
        } else if (requestCode == EXPORT_LOGS_REQUEST && resultCode == RESULT_OK && data != null && data.getData() != null) {
            writeExportLogs(data.getData());
        }
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        int width = getResources().getDisplayMetrics().widthPixels;
        int edge = UIHelpers.dp(this, 24);
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                edgeDownX = event.getX();
                edgeDownY = event.getY();
                edgeTracking = edgeDownX <= edge || edgeDownX >= width - edge;
                break;
            case MotionEvent.ACTION_UP:
                if (edgeTracking) {
                    float dx = event.getX() - edgeDownX;
                    float dy = Math.abs(event.getY() - edgeDownY);
                    boolean rightFromLeft = edgeDownX <= edge && dx > UIHelpers.dp(this, 72);
                    boolean leftFromRight = edgeDownX >= width - edge && dx < -UIHelpers.dp(this, 72);
                    if ((rightFromLeft || leftFromRight) && Math.abs(dx) > dy * 1.4f && navigateBack()) {
                        edgeTracking = false;
                        return true;
                    }
                }
                edgeTracking = false;
                break;
            case MotionEvent.ACTION_CANCEL:
                edgeTracking = false;
                break;
            default:
                break;
        }
        return super.dispatchTouchEvent(event);
    }

    @Override
    public void onBackPressed() {
        if (!navigateBack()) super.onBackPressed();
    }

    private boolean navigateBack() {
        if (pageLoading) {
            Runnable backAction = pageLoadingBackAction;
            pageLoading = false;
            pageLoadingBackAction = null;
            pageLoadingGeneration++;
            enterScreen();
            if (backAction != null) backAction.run();
            return true;
        }
        if (readerVisible && readerFullscreen) {
            toggleReaderFullscreen();
            return true;
        }
        if (activePopup != null && activePopup.isShowing()) {
            activePopup.dismiss();
            activePopup = null;
            return true;
        }
        if (historyVisible && TextUtils.isEmpty(activeDetailId)) {
            historyVisible = false;
            showTab(3);
            return true;
        }
        if (readerVisible && !TextUtils.isEmpty(activeDetailId)) {
            showDetail(activeDetailId);
            return true;
        }
        if (!TextUtils.isEmpty(activeDetailId)) {
            Runnable backAction = detailBackAction;
            detailBackAction = null;
            activeDetailId = "";
            if (backAction != null) {
                backAction.run();
            } else if (standaloneSearchVisible) {
                showStandaloneSearch(standaloneSearchResultsMode);
            } else {
                showTab(currentTab);
            }
            return true;
        }
        if (standaloneSearchVisible) {
            if (standaloneSearchResultsMode) {
                showStandaloneSearch(false);
            } else {
                standaloneSearchVisible = false;
                standaloneSearchResultsMode = false;
                clearSearchInputs();
                showTab(0);
            }
            return true;
        }
        return false;
    }

    private void applyThemeAndSystemBars() {
        nightThemeApplied = themeMode == 1 ? UIHelpers.applyTheme(false)
                : themeMode == 2 ? UIHelpers.applyTheme(true)
                : UIHelpers.applyAutoTheme();
        getWindow().setStatusBarColor(UIHelpers.BG);
        getWindow().setNavigationBarColor(UIHelpers.SURFACE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            int flags = UIHelpers.isNightTheme() ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            getWindow().getDecorView().setSystemUiVisibility(flags);
        }
    }

    private void applyReaderSystemBars() {
        getWindow().setStatusBarColor(UIHelpers.DARK);
        getWindow().setNavigationBarColor(UIHelpers.DARK);
        int flags = 0;
        if (readerFullscreen) {
            flags = View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE;
        }
        getWindow().getDecorView().setSystemUiVisibility(flags);
    }

    private void scheduleThemeSwitch() {
        main.removeCallbacks(themeSwitchRunnable);
        if (themeMode != 0) return;
        main.postDelayed(themeSwitchRunnable, UIHelpers.nextThemeSwitchDelayMs() + 250L);
    }

    private boolean refreshThemeIfChanged() {
        boolean before = nightThemeApplied;
        applyThemeAndSystemBars();
        return before != nightThemeApplied;
    }

    private void rerenderCurrentScreen() {
        if (standaloneSearchVisible) {
            showStandaloneSearch(standaloneSearchResultsMode);
            return;
        }
        if (readerVisible && !TextUtils.isEmpty(activeDetailId)) {
            ComicModels.ComicDetail detail = details.get(activeDetailId);
            if (detail != null && !detail.chapters.isEmpty()) {
                int index = Math.max(0, Math.min(readerChapterIndex, detail.chapters.size() - 1));
                ComicModels.ChapterPage page = chapters.get(detail.chapters.get(index).url);
                if (page != null) {
                    renderReader(detail, page);
                    return;
                }
            }
        }
        if (!TextUtils.isEmpty(activeDetailId)) {
            showDetail(activeDetailId);
            return;
        }
        showTab(currentTab);
    }

    /** 切屏：cancel 上一屏所有未完成的 Future（排队中的不再执行，运行中的收到 interrupt） */
    private void enterScreen() {
        if (pageLoading) {
            pageLoading = false;
            pageLoadingBackAction = null;
            pageLoadingGeneration++;
        }
        for (Future<?> f : currentScreenFutures) {
            if (f != null && !f.isDone()) f.cancel(true);
        }
        currentScreenFutures = new ArrayList<>();
        searchGeneration++;
        readerGeneration++;
        searchLoading = false;
        searchAppending = false;
        cancelCurrentImageTasks();
    }

    /** 跟踪一个 Future 到当前屏，切屏时会被 cancel */
    private Future<?> track(Future<?> f) {
        currentScreenFutures.add(f);
        return f;
    }

    private Future<?> trackImage(Future<?> f) {
        currentImageFutures.add(f);
        return f;
    }

    private Future<?> submitReaderImage(Runnable task) {
        FutureTask<?> future = new FutureTask<Object>(task, null) {
            @Override
            protected void done() {
                main.post(() -> currentImageFutures.remove(this));
            }
        };
        currentImageFutures.add(future);
        imageIo.execute(future);
        return future;
    }

    private void cancelCurrentImageTasks() {
        for (Future<?> f : currentImageFutures) {
            if (f != null && !f.isDone()) f.cancel(true);
        }
        currentImageFutures = new ArrayList<>();
    }

    // Top-level page switch (bottom-nav tap / exiting standalone search) should clear the search
    // inputs; down-navigation (entering detail) and back-from-detail must NOT clear them.
    private void clearSearchInputs() {
        searchQuery = "";
        globalSearchQuery = "";
    }

    private void showTab(int tab) {
        showTab(tab, true);
    }

    private void showTab(int tab, boolean cancelTasks) {
        int previousTab = currentTab;
        if (cancelTasks) enterScreen();
        applyThemeAndSystemBars();
        currentTab = tab;
        if (tab == 1 && previousTab != 1 && TextUtils.isEmpty(searchQuery.trim())) defaultSearchRefreshPending = true;
        activeDetailId = "";
        historyVisible = false;
        standaloneSearchVisible = false;
        standaloneSearchResultsMode = false;
        readerVisible = false;
        root.removeAllViews();
        FrameLayout shell = new FrameLayout(this);
        shell.setBackgroundColor(UIHelpers.BG);
        root.addView(shell, UIHelpers.match());

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(UIHelpers.dp(this, 20), UIHelpers.dp(this, 16), UIHelpers.dp(this, 20), UIHelpers.dp(this, 72));

        // 站源页和我的页内容较多，用 ScrollView 包裹以支持滚动
        if (tab == 2 || tab == 3) {
            ScrollView scroll = new ScrollView(this);
            scroll.setBackgroundColor(UIHelpers.BG);
            tuneScroll(scroll);
            shell.addView(scroll, UIHelpers.match());
            scroll.addView(page, UIHelpers.matchWrap());
        } else {
            shell.addView(page, UIHelpers.frame(-1, -1, Gravity.TOP, 0, 0, 0, 0));
        }

        if (tab == 0) renderFavorites(page);
        if (tab == 1) renderSearch(page);
        if (tab == 2) renderSources(page);
        if (tab == 3) renderProfile(page);
        shell.addView(makeBottomNav(), UIHelpers.frame(-1, UIHelpers.dp(this, 64), Gravity.BOTTOM, UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 8), 0));
        if (tab == 1 && previousTab != 1 && sourceCategories.isEmpty()) loadSourceCategories();
        scheduleDefaultSearchLoad();
    }

    private void renderSearch(LinearLayout page) {
        EditText input = UIHelpers.searchBox(this, "搜索漫画名称或作者", true);
        bindingSearchText = true;
        input.setText(searchQuery);
        input.setSelection(input.getText().length());
        bindingSearchText = false;
        input.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        input.setSingleLine(true);
        input.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                searchQuery = v.getText().toString().trim();
                selectedRegion = "all";
                selectedState = "all";
                searchResults.clear();
                resetSearchPaging();
                showTab(1);
                if (searchQuery.isEmpty()) {
                    loadDefaultCategory();
                } else {
                    runSearch(searchQuery);
                }
                return true;
            }
            return false;
        });
        input.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
            @Override public void afterTextChanged(Editable s) {
                if (bindingSearchText) return;
                searchQuery = s.toString();
            }
        });
        page.addView(input, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 42)));
        TextView filterTrigger = UIHelpers.chip(this, "▾ " + selectedSourceName() + " · " + currentFilterLabel(), true);
        filterTrigger.setOnClickListener(v -> showFilterDrawer());
        page.addView(filterTrigger, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));
        page.addView(sectionTitle("搜索结果"));

        ScrollView scroll = new ScrollView(this);
        searchScroll = scroll;
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        searchResultsContent = content;
        searchPagingFooter = null;
        scroll.addView(content, UIHelpers.matchWrap());
        scroll.setOnScrollChangeListener((v, scrollX, scrollY, oldScrollX, oldScrollY) -> {
            View child = scroll.getChildAt(0);
            if (child != null && scrollY + scroll.getHeight() >= child.getHeight() - UIHelpers.dp(this, 120)) {
                loadNextSearchPage();
            }
        });
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        if (pendingSearchScrollY >= 0) {
            int restoreY = pendingSearchScrollY;
            pendingSearchScrollY = -1;
            scroll.post(() -> scroll.scrollTo(0, restoreY));
        }

        if (selectedSource() == null) {
            content.addView(emptyState(R.drawable.ic_source, "还没有启用站源", "去站源页打开一个漫画来源吧", "去启用", () -> showTab(2)));
            return;
        }
        if (searchResults.isEmpty()) {
            if (searchLoading) {
                content.addView(loadingState("正在加载", "请稍等，正在获取漫画内容。"));
                return;
            }
            content.addView(emptyState(R.drawable.ic_magnifier, "这里还空着", "按键盘搜索，或点上方分类浏览", "重新加载", () -> {
                if (TextUtils.isEmpty(searchQuery.trim())) loadDefaultCategory(); else runSearch(searchQuery.trim());
            }));
            return;
        }

        List<ComicModels.ComicSummary> visible = filterResults();
        if (visible.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_magnifier, "没找到这本漫画", "换个关键词，或清空题材筛选再试", "清空筛选", () -> {
                selectedRegion = "all";
                selectedState = "all";
                showTab(1);
            }));
            return;
        }
        appendSearchRows(content, visible);
        renderSearchPagingFooter(content);
    }

    private void appendSearchResults(List<ComicModels.ComicSummary> list) {
        if (searchResultsContent == null) {
            showTab(1);
            return;
        }
        appendSearchRows(searchResultsContent, list);
        renderSearchPagingFooter(searchResultsContent);
    }

    private void appendSearchRows(LinearLayout content, List<ComicModels.ComicSummary> items) {
        for (int i = 0; i < items.size(); i += 2) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.addView(resultCard(items.get(i)), UIHelpers.weight(1));
            if (i + 1 < items.size()) {
                row.addView(UIHelpers.space(this, UIHelpers.dp(this, 12), 1));
                row.addView(resultCard(items.get(i + 1)), UIHelpers.weight(1));
            } else {
                row.addView(UIHelpers.space(this, UIHelpers.dp(this, 12), 1));
                row.addView(new View(this), UIHelpers.weight(1));
            }
            content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 14)));
        }
    }

    private void renderSearchPagingFooter(LinearLayout content) {
        removeSearchPagingFooter();
        if (searchAppending) {
            searchPagingFooter = loadingMoreView();
        } else if (!searchHasMore) {
            TextView end = UIHelpers.text(this, "\u5df2\u7ecf\u5230\u5e95\u4e86", 12, UIHelpers.TEXT3, Typeface.NORMAL);
            end.setGravity(Gravity.CENTER);
            searchPagingFooter = end;
        }
        if (searchPagingFooter != null) {
            content.addView(searchPagingFooter, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 16)));
        }
    }

    private void removeSearchPagingFooter() {
        if (searchPagingFooter != null && searchPagingFooter.getParent() instanceof ViewGroup) {
            ((ViewGroup) searchPagingFooter.getParent()).removeView(searchPagingFooter);
        }
        searchPagingFooter = null;
    }
    private void renderFavorites(LinearLayout page) {
        addTitle(page, "我的收藏", null);
        EditText input = UIHelpers.searchBox(this, "搜索漫画名称或作者", true);
        input.setFocusable(false);
        input.setText("");
        input.setSingleLine(true);
        input.setOnClickListener(v -> showStandaloneSearch(false));
        page.addView(input, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 42)));
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        if (favorites.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_bookshelf, "书架还空着", "等你把第一本放进来", "去搜索", () -> showTab(1)));
            return;
        }
        for (String id : filterFavorites()) {
            content.addView(favoriteRow(id));
        }
    }

    private void renderSources(LinearLayout page) {
        addTitle(page, "站源管理", null);
        TextView add = UIHelpers.chip(this, "+ 添加", true);
        add.setOnClickListener(v -> showAddSourceDialog());
        page.addView(add, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));
        add.setVisibility(View.GONE);
        LinearLayout enabledSources = new LinearLayout(this);
        enabledSources.setOrientation(LinearLayout.VERTICAL);
        LinearLayout disabledSources = new LinearLayout(this);
        disabledSources.setOrientation(LinearLayout.VERTICAL);
        addSourceCard(enabledSources, disabledSources, sourceEnabled, sourceCard(baoziConfig.name, baoziConfig.domain, sourceEnabled, () -> {
            sourceEnabled = !sourceEnabled;
            baoziConfig = baoziConfig.withEnabled(sourceEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, mhua5Enabled, sourceCard(mhua5Config.name, mhua5Config.domain, mhua5Enabled, () -> {
            mhua5Enabled = !mhua5Enabled;
            mhua5Config = mhua5Config.withEnabled(mhua5Enabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, aikanEnabled, sourceCard(aikanConfig.name, aikanConfig.domain, aikanEnabled, () -> {
            aikanEnabled = !aikanEnabled;
            aikanConfig = aikanConfig.withEnabled(aikanEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, gmhEnabled, sourceCard(gmhConfig.name, gmhConfig.domain, gmhEnabled, () -> {
            gmhEnabled = !gmhEnabled;
            gmhConfig = gmhConfig.withEnabled(gmhEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, mkzhanEnabled, sourceCard(mkzhanConfig.name, mkzhanConfig.domain, mkzhanEnabled, () -> {
            mkzhanEnabled = !mkzhanEnabled;
            mkzhanConfig = mkzhanConfig.withEnabled(mkzhanEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, hiperdexEnabled, sourceCard(hiperdexConfig.name, hiperdexConfig.domain, hiperdexEnabled, () -> {
            hiperdexEnabled = !hiperdexEnabled;
            hiperdexConfig = hiperdexConfig.withEnabled(hiperdexEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, manhuaguiEnabled, sourceCard(manhuaguiConfig.name, manhuaguiConfig.domain, manhuaguiEnabled, () -> {
            manhuaguiEnabled = !manhuaguiEnabled;
            manhuaguiConfig = manhuaguiConfig.withEnabled(manhuaguiEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, hanman18Enabled, sourceCard(hanman18Config.name, hanman18Config.domain, hanman18Enabled, () -> {
            hanman18Enabled = !hanman18Enabled;
            hanman18Config = hanman18Config.withEnabled(hanman18Enabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, d5d6Enabled, sourceCard(d5d6Config.name, d5d6Config.domain, d5d6Enabled, () -> {
            d5d6Enabled = !d5d6Enabled;
            d5d6Config = d5d6Config.withEnabled(d5d6Enabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        addSourceCard(enabledSources, disabledSources, manbenEnabled, sourceCard(manbenConfig.name, manbenConfig.domain, manbenEnabled, () -> {
            manbenEnabled = !manbenEnabled;
            manbenConfig = manbenConfig.withEnabled(manbenEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        for (ComicModels.Source item : customSources) {
            addSourceCard(enabledSources, disabledSources, item.enabled, sourceCard(item.name, item.url, item.enabled, () -> {
                item.enabled = !item.enabled;
                saveLocalState();
                showTab(2);
            }));
        }
        page.addView(enabledSources);
        page.addView(disabledSources);
        LinearLayout ioButtons = new LinearLayout(this);
        ioButtons.setOrientation(LinearLayout.HORIZONTAL);
        Button export = UIHelpers.primaryButton(this, "导出站源配置");
        export.setOnClickListener(v -> exportSourceConfig());
        Button importBtn = UIHelpers.secondaryButton(this, "导入配置");
        importBtn.setOnClickListener(v -> openImportSourceConfig());
        ioButtons.addView(export, UIHelpers.buttonWeight(this, 1));
        ioButtons.addView(UIHelpers.space(this, UIHelpers.dp(this, 10), 1));
        ioButtons.addView(importBtn, UIHelpers.buttonWeight(this, 1));
        page.addView(ioButtons, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));
        ioButtons.setVisibility(View.GONE);
        Button check = UIHelpers.secondaryButton(this, "检测站源可用性");
        check.setOnClickListener(v -> healthCheck());
        page.addView(check, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));
        check.setVisibility(View.GONE);
    }

    private void addSourceCard(LinearLayout enabledSources, LinearLayout disabledSources, boolean enabled, View card) {
        (enabled ? enabledSources : disabledSources).addView(card);
    }

    private void renderProfile(LinearLayout page) {
        addTitle(page, "我的", null);
        LinearLayout group = UIHelpers.card(this);
        group.addView(menuItemWithIcon(R.drawable.ic_history, "阅读历史", "", () -> showHistory()));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItemWithIcon(themeIcon(), "主题模式", themeModeLabel(), () -> cycleThemeMode()));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItemWithIcon(R.drawable.ic_chevron_left, "左右手模式", readerLeftHand ? "左手" : "右手", () -> toggleReaderHand()));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItemWithIcon(R.drawable.ic_trash, "缓存清理", cacheSize, () -> {
            clearAppCache();
        }));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItemWithIcon(R.drawable.ic_lightning, "错误日志", errorLogSummary(), () -> showErrorLogs()));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItemWithIcon(R.drawable.ic_profile, "关于 App", "1.0.3", () -> showInfo("关于 App", "XX Comic 已接入包子漫画、漫画屋的搜索、详情、阅读图片和本地缓存。")));
        page.addView(group);
    }

    private void toggleReaderHand() {
        readerLeftHand = !readerLeftHand;
        saveLocalState();
        showToast(readerLeftHand ? "已切换到左手模式：点左=下一章，点右=上一章" : "已切换到右手模式：点左=上一章，点右=下一章");
        if (readerVisible) {
            ComicModels.ComicDetail detail = details.get(activeDetailId);
            if (detail != null && !detail.chapters.isEmpty()) {
                showReader(detail, readerChapterIndex);
            }
        } else {
            rerenderCurrentScreen();
        }
    }

    private int themeIcon() {
        if (themeMode == 1) return R.drawable.ic_sun;
        if (themeMode == 2) return R.drawable.ic_moon;
        return R.drawable.ic_auto;
    }

    private View menuItemWithIcon(int iconRes, String title, String end, Runnable onClick) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        int padH = UIHelpers.dp(this, 16);
        int padV = UIHelpers.dp(this, 14);
        row.setPadding(padH, padV, padH, padV);
        row.setMinimumHeight(UIHelpers.dp(this, 50));
        row.setClickable(true);
        row.setFocusable(true);
        row.setOnClickListener(v -> onClick.run());
        try {
            ImageView icon = new ImageView(this);
            icon.setImageResource(iconRes);
            icon.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.TEXT3));
            row.addView(icon, new LinearLayout.LayoutParams(UIHelpers.dp(this, 22), UIHelpers.dp(this, 22)));
        } catch (Exception ignored) { }
        TextView titleView = UIHelpers.text(this, title, 15, UIHelpers.TEXT, Typeface.NORMAL);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(-2, -2);
        tlp.leftMargin = UIHelpers.dp(this, 14);
        row.addView(titleView, tlp);
        View spacer = new View(this);
        row.addView(spacer, new LinearLayout.LayoutParams(0, 1, 1f));
        if (!TextUtils.isEmpty(end)) {
            TextView endView = UIHelpers.text(this, end, 12, UIHelpers.TEXT3, Typeface.NORMAL);
            row.addView(endView, new LinearLayout.LayoutParams(-2, -2));
        }
        try {
            ImageView chev = new ImageView(this);
            chev.setImageResource(R.drawable.ic_chevron_right);
            chev.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.TEXT3));
            LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));
            clp.leftMargin = UIHelpers.dp(this, 6);
            row.addView(chev, clp);
        } catch (Exception ignored) { }
        row.setLayoutParams(new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        return row;
    }

    private String themeModeLabel() {
        if (themeMode == 1) return "白天";
        if (themeMode == 2) return "黑夜";
        return "自动";
    }

    private void cycleThemeMode() {
        themeMode = (themeMode + 1) % 3;
        saveLocalState();
        applyThemeAndSystemBars();
        scheduleThemeSwitch();
        rerenderCurrentScreen();
    }

    private void showStandaloneSearch(boolean resultsMode) {
        enterScreen();
        standaloneSearchVisible = true;
        standaloneSearchResultsMode = resultsMode;
        root.removeAllViews();
        // 全屏重建：旧的持久容器引用失效，将在结果模式下重新创建
        globalSearchContent = null;
        globalSearchTabsScroller = null;
        globalSearchResultsContainer = null;
        globalSearchStatusView = null;
        globalSearchLoadingView = null;
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(UIHelpers.BG);
        root.addView(shell, UIHelpers.match());

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(UIHelpers.dp(this, 18), UIHelpers.dp(this, 12), UIHelpers.dp(this, 18), UIHelpers.dp(this, 10));
        top.setBackgroundColor(UIHelpers.BG);
        ImageView back = UIHelpers.vectorIconButton(this, R.drawable.ic_back, UIHelpers.TEXT, 8);
        back.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 20), UIHelpers.BORDER_SOFT));
        back.setOnClickListener(v -> navigateBack());
        LinearLayout.LayoutParams backParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 40), UIHelpers.dp(this, 40));
        backParams.setMargins(0, 0, UIHelpers.dp(this, 10), 0);
        top.addView(back, backParams);

        EditText input = UIHelpers.searchBox(this, "搜索漫画名称或作者", true);
        input.setText(globalSearchQuery);
        input.setSelection(input.getText().length());
        input.setSingleLine(true);
        input.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        input.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                globalSearchQuery = v.getText().toString().trim();
                if (!globalSearchQuery.isEmpty()) {
                    addSearchHistory(globalSearchQuery);
                    startGlobalSearch(globalSearchQuery);
                }
                return true;
            }
            return false;
        });
        top.addView(input, new LinearLayout.LayoutParams(0, UIHelpers.dp(this, 42), 1));
        shell.addView(top, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 64)));

        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 20));
        scroll.addView(content, UIHelpers.matchWrap());
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        if (!resultsMode) {
            renderSearchHistory(content);
            return;
        }
        // 结果模式：创建持久容器，Tab 行和结果列表分离
        List<ComicSource> sources = enabledBuiltinSources();
        ensureSelectedGlobalSearchSource(sources);
        if (sources.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_source, "没有可用站源", "先去站源页打开一个吧", "返回搜索", () -> showStandaloneSearch(false)));
            return;
        }
        globalSearchTabsScroller = globalSearchSourceTabs(sources);
        content.addView(globalSearchTabsScroller, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));
        globalSearchResultsContainer = new LinearLayout(this);
        globalSearchResultsContainer.setOrientation(LinearLayout.VERTICAL);
        content.addView(globalSearchResultsContainer);
        // globalSearchContent 兼容旧引用，指向同一容器
        globalSearchContent = globalSearchResultsContainer;
        refreshGlobalSearchTabs();
        refreshGlobalSearchResults();
        ensureStatusView(content);
    }

    /** 局部刷新 Tab 行：重建内部 tabs LinearLayout，保留 HorizontalScrollView 的 scrollX */
    private void refreshGlobalSearchTabs() {
        if (globalSearchTabsScroller == null) return;
        LinearLayout tabs = (LinearLayout) globalSearchTabsScroller.getChildAt(0);
        if (tabs == null) {
            tabs = new LinearLayout(this);
            tabs.setOrientation(LinearLayout.HORIZONTAL);
            tabs.setGravity(Gravity.CENTER_VERTICAL);
            globalSearchTabsScroller.addView(tabs, new HorizontalScrollView.LayoutParams(-2, UIHelpers.dp(this, 48)));
        } else {
            tabs.removeAllViews();
        }
        List<ComicSource> sources = enabledBuiltinSources();
        for (ComicSource source : sources) {
            String sourceId = source.id();
            boolean selected = sourceId.equals(selectedGlobalSearchSourceId);
            int count = globalResultsForSource(sourceId).size();
            boolean pending = globalSearchLoading
                    && !globalSearchFailedSourceIds.contains(sourceId)
                    && !globalSearchCompletedSourceIds.contains(sourceId);
            String label = source.name() + (count > 0 ? " " + count : pending ? " ..." : "");
            TextView tab = UIHelpers.chip(this, label, selected);
            tab.setSingleLine(true);
            tab.setEllipsize(TextUtils.TruncateAt.END);
            tab.setGravity(Gravity.CENTER);
            tab.setMinWidth(UIHelpers.dp(this, 108));
            tab.setMaxWidth(UIHelpers.dp(this, 150));
            tab.setOnClickListener(v -> {
                cancelCurrentImageTasks();
                selectedGlobalSearchSourceId = sourceId;
                refreshGlobalSearchTabs();
                refreshGlobalSearchResults();
            });
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-2, UIHelpers.dp(this, 36));
            params.setMargins(0, UIHelpers.dp(this, 6), UIHelpers.dp(this, 8), UIHelpers.dp(this, 6));
            tabs.addView(tab, params);
        }
    }

    /** 局部刷新结果列表：清空 globalSearchResultsContainer 并重新填充当前选中站源的结果 */
    private void refreshGlobalSearchResults() {
        if (globalSearchResultsContainer == null) return;
        globalSearchResultsContainer.removeAllViews();
        globalSearchLoadingView = null;
        List<ComicModels.ComicSummary> selectedResults = globalResultsForSource(selectedGlobalSearchSourceId);
        if (selectedResults.isEmpty()) {
            if (globalSearchLoading
                    && !globalSearchFailedSourceIds.contains(selectedGlobalSearchSourceId)
                    && !globalSearchCompletedSourceIds.contains(selectedGlobalSearchSourceId)) {
                globalSearchLoadingView = loadingState("正在搜索", "正在搜索 " + sourceNameForId(selectedGlobalSearchSourceId));
                globalSearchResultsContainer.addView(globalSearchLoadingView);
                return;
            }
            globalSearchResultsContainer.addView(emptyState(R.drawable.ic_magnifier, "这个站源暂无结果", "切换其他站源看看", "返回搜索", () -> showStandaloneSearch(false)));
            return;
        }
        for (ComicModels.ComicSummary item : new ArrayList<>(selectedResults)) {
            globalSearchResultsContainer.addView(globalResultRow(item));
        }
    }

    private void renderSearchHistory(LinearLayout content) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(UIHelpers.text(this, "搜索记录", 18, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        TextView clear = UIHelpers.text(this, "清空", 13, UIHelpers.TEXT2, Typeface.NORMAL);
        clear.setGravity(Gravity.CENTER);
        clear.setOnClickListener(v -> {
            globalSearchHistory.clear();
            saveLocalState();
            showStandaloneSearch(false);
        });
        row.addView(clear);
        content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));
        if (globalSearchHistory.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_history, "暂无搜索记录", "输入关键词后按键盘搜索", "", () -> {}));
            return;
        }
        LinearLayout chips = new LinearLayout(this);
        chips.setOrientation(LinearLayout.VERTICAL);
        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        int count = 0;
        for (String keyword : globalSearchHistory) {
            TextView chip = UIHelpers.chip(this, keyword, false);
            chip.setOnClickListener(v -> {
                globalSearchQuery = keyword;
                startGlobalSearch(keyword);
            });
            line.addView(chip, UIHelpers.marginRight(-2, UIHelpers.dp(this, 10)));
            count++;
            if (count % 3 == 0) {
                chips.addView(line, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));
                line = new LinearLayout(this);
                line.setOrientation(LinearLayout.HORIZONTAL);
            }
        }
        if (line.getChildCount() > 0) chips.addView(line);
        content.addView(chips);
    }

    private void renderGlobalSearchResults(LinearLayout content) {
        renderGlobalSearchResultsTabbed(content);
        if (System.currentTimeMillis() >= 0) return;
    }

    private void renderGlobalSearchResultsLegacy(LinearLayout content) {
        // loading 且无结果：显示 loading 动画
        if (globalSearchLoading && globalSearchResults.isEmpty()) {
            globalSearchLoadingView = loadingState("正在搜索", "正在并发搜索所有开启站源。");
            content.addView(globalSearchLoadingView);
            ensureStatusView(content);
            return;
        }
        // 非 loading 且无结果：空状态
        if (!globalSearchLoading && globalSearchResults.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_magnifier, "没找到这本漫画", "换个关键词再试一次", "返回搜索", () -> showStandaloneSearch(false)));
            return;
        }
        // 有结果：全量渲染（页面重建场景，如主题切换）
        // 重建 shownIds 以反映当前 content 中的内容，供后续流式增量去重
        globalSearchShownIds.clear();
        for (ComicModels.ComicSummary item : new ArrayList<>(globalSearchResults)) {
            globalSearchShownIds.add(item.comicId);
            content.addView(globalResultRow(item));
        }
        ensureStatusView(content);
    }

    /** 在列表底部追加/更新状态文字（N/M 完成 · K 失败） */
    private void renderGlobalSearchResultsTabbed(LinearLayout content) {
        List<ComicSource> sources = enabledBuiltinSources();
        ensureSelectedGlobalSearchSource(sources);
        if (sources.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_source, "没有可用站源", "先去站源页打开一个吧", "返回搜索", () -> showStandaloneSearch(false)));
            return;
        }
        content.addView(globalSearchSourceTabs(sources), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));
        List<ComicModels.ComicSummary> selectedResults = globalResultsForSource(selectedGlobalSearchSourceId);
        if (selectedResults.isEmpty()) {
            if (globalSearchLoading
                    && !globalSearchFailedSourceIds.contains(selectedGlobalSearchSourceId)
                    && !globalSearchCompletedSourceIds.contains(selectedGlobalSearchSourceId)) {
                globalSearchLoadingView = loadingState("正在搜索", "正在搜索 " + sourceNameForId(selectedGlobalSearchSourceId));
                content.addView(globalSearchLoadingView);
                ensureStatusView(content);
                return;
            }
            content.addView(emptyState(R.drawable.ic_magnifier, "这个站源暂无结果", "切换其他站源看看", "返回搜索", () -> showStandaloneSearch(false)));
            ensureStatusView(content);
            return;
        }
        for (ComicModels.ComicSummary item : new ArrayList<>(selectedResults)) {
            content.addView(globalResultRow(item));
        }
        ensureStatusView(content);
    }

    private HorizontalScrollView globalSearchSourceTabs(List<ComicSource> sources) {
        HorizontalScrollView scroller = new HorizontalScrollView(this);
        scroller.setHorizontalScrollBarEnabled(false);
        scroller.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroller.setFillViewport(false);
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        tabs.setGravity(Gravity.CENTER_VERTICAL);
        scroller.addView(tabs, new HorizontalScrollView.LayoutParams(-2, UIHelpers.dp(this, 48)));
        // Tab 内容由 refreshGlobalSearchTabs() 统一填充，保留 scroller 的 scrollX
        return scroller;
    }

    private void ensureSelectedGlobalSearchSource(List<ComicSource> sources) {
        if (sources.isEmpty()) {
            selectedGlobalSearchSourceId = "";
            return;
        }
        for (ComicSource source : sources) {
            if (source.id().equals(selectedGlobalSearchSourceId)) return;
        }
        selectedGlobalSearchSourceId = sources.get(0).id();
    }

    private List<ComicModels.ComicSummary> globalResultsForSource(String sourceId) {
        List<ComicModels.ComicSummary> list = globalSearchResultsBySource.get(sourceId);
        return list == null ? new ArrayList<>() : list;
    }

    private boolean globalSearchAllResultsEmpty() {
        for (List<ComicModels.ComicSummary> list : globalSearchResultsBySource.values()) {
            if (list != null && !list.isEmpty()) return false;
        }
        return true;
    }

    private void addGlobalSearchSourceResults(String sourceId, List<ComicModels.ComicSummary> result) {
        List<ComicModels.ComicSummary> sourceResults = globalSearchResultsBySource.get(sourceId);
        if (sourceResults == null) {
            sourceResults = new ArrayList<>();
            globalSearchResultsBySource.put(sourceId, sourceResults);
        }
        Set<String> sourceShownIds = globalSearchShownIdsBySource.get(sourceId);
        if (sourceShownIds == null) {
            sourceShownIds = new HashSet<>();
            globalSearchShownIdsBySource.put(sourceId, sourceShownIds);
        }
        for (ComicModels.ComicSummary item : result) {
            if (sourceShownIds.add(item.comicId)) {
                sourceResults.add(item);
                globalSearchResults.add(item);
                summaries.put(item.comicId, item);
            }
        }
    }

    private void ensureStatusView(LinearLayout content) {
        if (globalSearchStatusView == null || globalSearchStatusView.getParent() != content) {
            globalSearchStatusView = UIHelpers.text(this, "", 12, UIHelpers.TEXT3, Typeface.NORMAL);
            globalSearchStatusView.setGravity(Gravity.CENTER);
            globalSearchStatusView.setPadding(0, UIHelpers.dp(this, 16), 0, UIHelpers.dp(this, 8));
            content.addView(globalSearchStatusView);
        }
        updateGlobalSearchStatus();
    }

    private LinearLayout globalResultRow(ComicModels.ComicSummary item) {
        LinearLayout row = UIHelpers.card(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setOnClickListener(v -> showDetail(item.comicId));
        row.addView(coverFrame(item.coverUrl, 72, 96));
        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(this, 14), 0, 0, 0);
        TextView title = UIHelpers.text(this, item.title, 16, UIHelpers.TEXT, Typeface.NORMAL);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        info.addView(title);
        info.addView(UIHelpers.text(this, clean(item.subtitle, "暂无"), 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));
        info.addView(UIHelpers.text(this, sourceNameForId(item.sourceId), 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));
        row.addView(info, UIHelpers.weight(1));
        return row;
    }

    private LinearLayout resultCard(ComicModels.ComicSummary comic) {
        LinearLayout item = UIHelpers.surfaceCard(this);
        item.setOrientation(LinearLayout.VERTICAL);
        item.setPadding(UIHelpers.dp(this, 10), UIHelpers.dp(this, 10), UIHelpers.dp(this, 10), UIHelpers.dp(this, 10));
        item.setOnClickListener(v -> {
            if (searchScroll != null) pendingSearchScrollY = searchScroll.getScrollY();
            showDetail(comic.comicId);
        });
        item.addView(coverFrame(comic.coverUrl, -1, 202));
        TextView title = UIHelpers.text(this, comic.title, 14, UIHelpers.TEXT, Typeface.NORMAL);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        item.addView(title, UIHelpers.marginTop(-1, UIHelpers.dp(this, 7)));
        TextView sub = UIHelpers.text(this, clean(comic.subtitle, sourceNameForId(comic.sourceId)), 12, UIHelpers.TEXT3, Typeface.NORMAL);
        sub.setSingleLine(true);
        sub.setEllipsize(TextUtils.TruncateAt.END);
        item.addView(sub, UIHelpers.marginTop(-1, UIHelpers.dp(this, 3)));
        return item;
    }

    private View favoriteRow(String id) {
        ComicModels.ComicDetail detail = details.get(id);
        ComicModels.ComicSummary summary = summaries.get(id);
        String title = detail != null ? detail.summary.title : summary != null ? summary.title : id;
        String cover = detail != null ? detail.summary.coverUrl : summary != null ? summary.coverUrl : "";
        String latest = detail != null ? detail.latestChapter : summary != null ? summary.subtitle : "";
        // 内容卡片
        LinearLayout contentCard = UIHelpers.card(this);
        contentCard.setOrientation(LinearLayout.HORIZONTAL);
        contentCard.addView(coverFrame(cover, 86, 116));
        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(this, 12), 0, 0, 0);
        TextView titleView = UIHelpers.text(this, title, 16, UIHelpers.TEXT, Typeface.NORMAL);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        titleView.setSingleLine(true);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        info.addView(titleView);
        String sourceName = detail != null ? sourceNameForId(detail.summary.sourceId) : summary != null ? sourceNameForId(summary.sourceId) : sourceNameForId(sourceForComicId(id).id());
        info.addView(UIHelpers.text(this, sourceName + " · " + clean(latest, "未知章节"), 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 6)));
        info.addView(UIHelpers.text(this, "上次看到：第 " + (savedChapter(id) + 1) + " 章", 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 8)));
        Button button = UIHelpers.brandButton(this, "继续阅读");
        button.setTypeface(Typeface.SERIF);
        button.setOnClickListener(v -> showDetailThenRead(id));
        info.addView(button, UIHelpers.marginTop(UIHelpers.dp(this, 96), UIHelpers.dp(this, 8), -2, UIHelpers.dp(this, 40)));
        contentCard.addView(info, UIHelpers.weight(1));
        contentCard.setOnClickListener(v -> showDetail(id));

        // 外层 SwipeToDeleteLayout：delete 层在下，content 在上，自定义手势处理
        int deleteWidth = UIHelpers.dp(this, 80);
        SwipeToDeleteLayout wrapper = new SwipeToDeleteLayout(this, contentCard, deleteWidth, () -> showDetail(id));
        wrapper.setLayoutParams(UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));
        // delete 层
        LinearLayout deleteLayer = new LinearLayout(this);
        deleteLayer.setOrientation(LinearLayout.HORIZONTAL);
        deleteLayer.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
        deleteLayer.setBackground(UIHelpers.round(UIHelpers.DANGER, UIHelpers.dp(this, 12), Color.TRANSPARENT));
        ImageView trashIcon = new ImageView(this);
        trashIcon.setImageResource(R.drawable.ic_trash);
        trashIcon.setImageTintList(android.content.res.ColorStateList.valueOf(Color.WHITE));
        int pad = UIHelpers.dp(this, 22);
        trashIcon.setPadding(pad, pad, pad, pad);
        deleteLayer.addView(trashIcon, new LinearLayout.LayoutParams(deleteWidth, -1));
        trashIcon.setOnClickListener(v -> styledDialog("删除收藏", "确认删除这条收藏吗？", "删除", () -> deleteFavorite(id), "取消", null));
        wrapper.addView(deleteLayer, new FrameLayout.LayoutParams(-1, -1));
        wrapper.addView(contentCard, new FrameLayout.LayoutParams(-1, -1));
        return wrapper;
    }

    /** 自定义 FrameLayout：onInterceptTouchEvent 阶段判定方向，横向拦截处理滑动，纵向放行给 ScrollView */
    private static class SwipeToDeleteLayout extends FrameLayout {
        private final View contentCard;
        private final int deleteWidth;
        private final Runnable onTap;
        private final int touchSlop;
        private float startX, startY;
        private boolean swiping = false;
        private boolean revealed = false;

        public SwipeToDeleteLayout(Context ctx, View contentCard, int deleteWidth, Runnable onTap) {
            super(ctx);
            this.contentCard = contentCard;
            this.deleteWidth = deleteWidth;
            this.onTap = onTap;
            this.touchSlop = ViewConfiguration.get(ctx).getScaledTouchSlop();
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    startX = event.getRawX();
                    startY = event.getRawY();
                    swiping = false;
                    // 阻止父级 ScrollView 在 MOVE 时拦截，直到本控件确定方向
                    if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(true);
                    return false;
                case MotionEvent.ACTION_MOVE: {
                    float dx = event.getRawX() - startX;
                    float dy = event.getRawY() - startY;
                    // 横向占优 → 进入滑动模式并拦截
                    if (Math.abs(dx) > touchSlop && Math.abs(dx) > Math.abs(dy) * 1.2f) {
                        swiping = true;
                        return true;
                    }
                    // 纵向占优 → 放行给 ScrollView
                    if (Math.abs(dy) > touchSlop && Math.abs(dy) > Math.abs(dx) * 1.2f) {
                        if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
                        swiping = false;
                        return false;
                    }
                    return false;
                }
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
                    return false;
            }
            return false;
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    if (!swiping) return false;
                    float dx = event.getRawX() - startX;
                    float base = revealed ? -deleteWidth : 0f;
                    float target = Math.max(-deleteWidth, Math.min(0f, base + dx));
                    contentCard.setTranslationX(target);
                    return true;
                }
                case MotionEvent.ACTION_UP: {
                    if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
                    if (swiping) {
                        float current = contentCard.getTranslationX();
                        if (current < -deleteWidth / 2f) {
                            contentCard.animate().translationX(-deleteWidth).setDuration(180).start();
                            revealed = true;
                        } else {
                            contentCard.animate().translationX(0).setDuration(180).start();
                            revealed = false;
                        }
                        return true;
                    }
                    // 无滑动 → 视为点击（交由 contentCard.OnClickListener 处理，这里不消费）
                    if (Math.abs(event.getRawX() - startX) < touchSlop && Math.abs(event.getRawY() - startY) < touchSlop) {
                        if (revealed) {
                            contentCard.animate().translationX(0).setDuration(180).start();
                            revealed = false;
                        } else {
                            contentCard.performClick();
                        }
                    }
                    return false;
                }
                case MotionEvent.ACTION_CANCEL:
                    if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
                    if (swiping) {
                        contentCard.animate().translationX(revealed ? -deleteWidth : 0).setDuration(180).start();
                        return true;
                    }
                    return false;
            }
            return false;
        }
    }

    private LinearLayout sourceCard(String name, String domain, boolean enabled, Runnable toggle) {
        // 直接创建 LinearLayout，不使用 UIHelpers.card()，确保背景明确为白色
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(UIHelpers.dp(this, 14), UIHelpers.dp(this, 14), UIHelpers.dp(this, 14), UIHelpers.dp(this, 14));
        card.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 12), UIHelpers.BORDER));
        card.setElevation(UIHelpers.dp(this, 1));
        card.setLayoutParams(UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));
        // 卡片本身不可点击，只有开关可点击
        card.setClickable(false);
        card.setFocusable(false);

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 48), UIHelpers.dp(this, 48));
        logoParams.setMargins(0, 0, UIHelpers.dp(this, 12), 0);
        top.addView(sourceLogo(name), logoParams);
        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        TextView sourceTitle = UIHelpers.text(this, name, 16, UIHelpers.TEXT, Typeface.NORMAL);
        sourceTitle.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        info.addView(sourceTitle);
        info.addView(UIHelpers.text(this, domain, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 3)));
        top.addView(info, UIHelpers.weight(1));
        top.addView(sourceSwitch(enabled, toggle), new LinearLayout.LayoutParams(UIHelpers.dp(this, 50), UIHelpers.dp(this, 28)));
        card.addView(top);

        LinearLayout status = new LinearLayout(this);
        status.setGravity(Gravity.CENTER_VERTICAL);
        // 修复：使用明确的尺寸而非 WRAP_CONTENT，确保 statusDot 可见
        LinearLayout.LayoutParams dotParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 8), UIHelpers.dp(this, 8));
        dotParams.setMargins(0, 0, UIHelpers.dp(this, 8), 0);
        status.addView(statusDot(enabled), dotParams);
        status.addView(UIHelpers.text(this, enabled ? "已启用" : "已停用", 11, UIHelpers.TEXT2, Typeface.NORMAL));
        card.addView(status, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));

        return card;
    }

    private void showDetail(String comicId) {
        if (TextUtils.isEmpty(activeDetailId)) {
            final boolean returnToHistory = historyVisible;
            final boolean returnToStandaloneSearch = standaloneSearchVisible;
            final boolean returnToStandaloneSearchResults = standaloneSearchResultsMode;
            final int returnTab = currentTab;
            detailBackAction = () -> {
                activeDetailId = "";
                detailBackAction = null;
                if (returnToHistory) {
                    showHistory();
                } else if (returnToStandaloneSearch) {
                    showStandaloneSearch(returnToStandaloneSearchResults);
                } else {
                    showTab(returnTab);
                }
            };
        }
        enterScreen();
        applyThemeAndSystemBars();
        activeDetailId = comicId;
        readerVisible = false;
        ComicModels.ComicDetail detail = details.get(comicId);
        if (detail == null) {
            int loadingGeneration = showPageLoading("正在加载详情...", "正在获取漫画信息。", detailBackAction);
            track(detailIo.submit(() -> {
                try {
                    ComicSource client = sourceForComicId(comicId);
                    ComicModels.ComicDetail loaded = client.detail(comicId);
                    loadImageToCache(loaded.summary.coverUrl);
                    main.post(() -> {
                        if (!isCurrentLoading(loadingGeneration)) return;
                        pageLoading = false;
                        pageLoadingBackAction = null;
                        details.put(comicId, loaded);
                        summaries.put(comicId, loaded.summary);
                        persistComicCachesAsync();
                        showDetail(comicId);
                    });
                } catch (Exception error) {
                    main.post(() -> {
                        if (!isCurrentLoading(loadingGeneration)) return;
                        pageLoading = false;
                        pageLoadingBackAction = null;
                        showError("详情加载失败", error, detailBackAction);
                    });
                }
            }));
            return;
        }

        root.removeAllViews();
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        scroll.setBackgroundColor(UIHelpers.BG);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());
        root.addView(scroll, UIHelpers.match());

        FrameLayout hero = new FrameLayout(this);
        hero.setBackgroundColor(UIHelpers.SURFACE);
        addBlurredHeroCover(hero, detail.summary.coverUrl, detail.summary.title);
        content.addView(hero, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, DETAIL_HERO_DP)));
        ImageView back = UIHelpers.vectorIconButton(this, R.drawable.ic_back, Color.WHITE, 10);
        back.setBackground(UIHelpers.round(Color.argb(90, 0, 0, 0), UIHelpers.dp(this, 22), Color.TRANSPARENT));
        back.setOnClickListener(v -> navigateBack());
        hero.addView(back, UIHelpers.frame(UIHelpers.dp(this, 44), UIHelpers.dp(this, 44), Gravity.TOP | Gravity.LEFT, UIHelpers.dp(this, 14), UIHelpers.dp(this, 18), 0, 0));

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(UIHelpers.dp(this, 18), 0, UIHelpers.dp(this, 18), UIHelpers.dp(this, 92));
        content.addView(body, UIHelpers.matchWrap());

        LinearLayout info = UIHelpers.card(this);
        LinearLayout.LayoutParams infoParams = UIHelpers.marginTop(-1, UIHelpers.dp(this, 10));
        info.setLayoutParams(infoParams);
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.addView(coverFrame(detail.summary.coverUrl, 92, 124));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.setPadding(UIHelpers.dp(this, 12), 0, 0, 0);
        TextView detailTitle = UIHelpers.text(this, detail.summary.title, 20, UIHelpers.TEXT, Typeface.BOLD);
        detailTitle.setMaxLines(2);
        detailTitle.setEllipsize(TextUtils.TruncateAt.END);
        text.addView(detailTitle);
        text.addView(UIHelpers.text(this, clean(detail.author, "未知作者") + " · " + clean(detail.status, "未知状态") + " · " + sourceNameForId(detail.summary.sourceId), 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 8)));
        text.addView(detailTagRow(detail.summary.tags), UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));
        top.addView(text, UIHelpers.weight(1));
        info.addView(top);
        info.addView(UIHelpers.text(this, clean(detail.description, "暂无简介"), 13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));
        body.addView(info);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        Button fav = UIHelpers.softButton(this, favorites.contains(detail.summary.comicId) ? "取消收藏" : "收藏");
        fav.setOnClickListener(v -> toggleFavorite(detail));
        Button read = UIHelpers.brandButton(this, savedChapter(detail.summary.comicId) > 0 ? "继续阅读" : "开始阅读");
        read.setTypeface(Typeface.SERIF);
        read.setOnClickListener(v -> ensureChaptersThen(detail, loaded -> showReader(loaded, savedChapter(loaded.summary.comicId))));
        buttons.addView(fav, UIHelpers.buttonWeight(this, 1));
        buttons.addView(UIHelpers.space(this, UIHelpers.dp(this, 10), 1));
        buttons.addView(read, UIHelpers.buttonWeight(this, 1));
        body.addView(buttons, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));

        body.addView(chapterEntry(detail), UIHelpers.marginTop(-1, UIHelpers.dp(this, 14)));
        refreshCachedComicOnce(detail);
    }

    private void refreshCachedComicOnce(ComicModels.ComicDetail detail) {
        String comicId = detail.summary.comicId;
        if (refreshedComicIds.contains(comicId) || refreshingComicIds.contains(comicId)) return;
        refreshingComicIds.add(comicId);
        ComicSource client = sourceForDetail(detail);
        detailIo.submit(() -> {
            try {
                ComicModels.ComicDetail freshDetail = client.detail(comicId);
                List<ComicModels.Chapter> loadedChapters = client.chapters(comicId);
                if (loadedChapters.isEmpty()) {
                    main.post(() -> {
                        if (activityDestroyed) return;
                        finishComicRefresh(comicId, null);
                    });
                    return;
                }
                ComicModels.ComicDetail loaded = withChapters(freshDetail, loadedChapters);
                main.post(() -> {
                    if (activityDestroyed) return;
                    finishComicRefresh(comicId, loaded);
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (activityDestroyed) return;
                    finishComicRefresh(comicId, null);
                });
            }
        });
    }

    private void finishComicRefresh(String comicId, ComicModels.ComicDetail loaded) {
        refreshingComicIds.remove(comicId);
        refreshedComicIds.add(comicId);
        DetailAction pendingAction = pendingRefreshActions.remove(comicId);
        if (loaded != null) {
            details.put(comicId, loaded);
            summaries.put(comicId, loaded.summary);
            persistComicCachesAsync();
            loadImageToCache(loaded.summary.coverUrl);
        }
        if (pendingAction != null) {
            pendingAction.run(loaded);
            return;
        }
        if (loaded != null && TextUtils.equals(activeDetailId, comicId) && !readerVisible) showDetail(comicId);
    }

    private void waitForComicRefresh(ComicModels.ComicDetail detail, DetailAction action) {
        String comicId = detail.summary.comicId;
        int loadingGeneration = showPageLoading("正在加载章节目录...", "目录加载完成后会自动打开。", () -> showDetail(comicId));
        pendingRefreshActions.put(comicId, loaded -> {
            if (!isCurrentLoading(loadingGeneration)) return;
            pageLoading = false;
            pageLoadingBackAction = null;
            if (loaded != null && !loaded.chapters.isEmpty()) {
                action.run(loaded);
            } else {
                ensureChaptersThen(detail, action);
            }
        });
    }

    private ComicModels.ComicDetail withChapters(ComicModels.ComicDetail detail, List<ComicModels.Chapter> loadedChapters) {
        List<ComicModels.Chapter> resolved = new ArrayList<>(loadedChapters);
        normalizeChaptersOldestFirst(resolved);
        return new ComicModels.ComicDetail(
                detail.summary,
                detail.author,
                detail.status,
                detail.description,
                detail.latestChapter,
                resolved);
    }

    private void showReader(ComicModels.ComicDetail detail, int chapterIndex) {
        enterScreen();
        if (detail.chapters.isEmpty()) {
            ensureChaptersThen(detail, loaded -> showReader(loaded, chapterIndex));
            return;
        }
        readerVisible = true;
        activeDetailId = detail.summary.comicId;
        readerChapterIndex = Math.max(0, Math.min(chapterIndex, detail.chapters.size() - 1));
        ComicModels.Chapter chapter = detail.chapters.get(readerChapterIndex);
        int generation = readerGeneration;
        String comicId = detail.summary.comicId;
        String chapterUrl = chapter.url;
        ComicModels.ChapterPage cached = chapters.get(chapter.url);
        if (isEmptyChapterPage(cached)) {
            chapters.remove(chapter.url);
            cached = null;
        }
        if (cached == null) {
            showReaderLoading(detail);
            track(detailIo.submit(() -> {
                try {
                    ComicSource client = sourceForDetail(detail);
                    ComicModels.ChapterPage page = client.chapter(chapterUrl);
                    main.post(() -> {
                        if (!isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
                        if (!isEmptyChapterPage(page)) {
                            chapters.put(chapterUrl, page);
                            persistComicCachesAsync();
                        }
                        commitReaderPage(generation, comicId, chapterUrl, detail, page);
                    });
                } catch (Exception error) {
                    boolean expectedCancellation = isExpectedTaskCancellation(error);
                    main.post(() -> {
                        if (expectedCancellation || !isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
                        showError("章节加载失败", error);
                    });
                }
            }));
            return;
        }
        commitReaderPage(generation, comicId, chapterUrl, detail, cached);
    }

    private void commitReaderPage(int generation, String comicId, String chapterUrl,
                                  ComicModels.ComicDetail detail, ComicModels.ChapterPage page) {
        if (!isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
        if (isEmptyChapterPage(page)) {
            if (page != null) renderReader(detail, page);
            return;
        }
        progress.put(comicId, readerChapterIndex);
        lastViewedAt.put(comicId, System.currentTimeMillis());
        saveLocalState();
        renderReader(detail, page);
    }

    private boolean isCurrentReaderRequest(int generation, String comicId, String chapterUrl, ComicModels.ComicDetail detail) {
        if (generation != readerGeneration || !readerVisible || !TextUtils.equals(activeDetailId, comicId)) return false;
        if (readerChapterIndex < 0 || readerChapterIndex >= detail.chapters.size()) return false;
        return TextUtils.equals(detail.chapters.get(readerChapterIndex).url, chapterUrl);
    }

    private void showReaderLoading(ComicModels.ComicDetail detail) {
        root.removeAllViews();
        readerVisible = true;
        applyReaderSystemBars();
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());
        TextView top = UIHelpers.text(this, detail.summary.title, 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        top.setGravity(Gravity.CENTER);
        top.setBackgroundColor(UIHelpers.DARK_BAR);
        shell.addView(top, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 56)));
        shell.addView(readerSkeletonState("正在解析本章图片"), new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(readerProgressBar(readerChapterIndex + 1, Math.max(1, detail.chapters.size())), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 1)));
    }

    private void renderReader(ComicModels.ComicDetail detail, ComicModels.ChapterPage page) {
        root.removeAllViews();
        readerVisible = true;
        readerTopBar = null;
        readerBottomBar = null;
        applyReaderSystemBars();
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());

        LinearLayout top = new LinearLayout(this);
        top.setPadding(UIHelpers.dp(this, 14), 0, UIHelpers.dp(this, 14), 0);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setBackgroundColor(UIHelpers.DARK_BAR);
        ImageView back = UIHelpers.vectorIconButton(this, R.drawable.ic_back, UIHelpers.READER_TEXT, 8);
        back.setOnClickListener(v -> navigateBack());
        top.addView(back, new LinearLayout.LayoutParams(UIHelpers.dp(this, 42), -1));
        TextView name = UIHelpers.text(this, detail.chapters.get(readerChapterIndex).title, 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        name.setTypeface(Typeface.SERIF);
        name.setGravity(Gravity.CENTER);
        name.setSingleLine(true);
        name.setEllipsize(TextUtils.TruncateAt.END);
        top.addView(name, UIHelpers.weight(1));
        TextView toc = UIHelpers.text(this, "目录", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        toc.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        toc.setGravity(Gravity.CENTER);
        toc.setOnClickListener(v -> showChapterDrawer(detail));
        top.addView(toc, new LinearLayout.LayoutParams(UIHelpers.dp(this, 48), -1));
        shell.addView(top, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 56)));
        readerTopBar = top;
        top.setVisibility(readerFullscreen ? View.GONE : View.VISIBLE);

        ComicModels.Chapter activeChapter = detail.chapters.get(readerChapterIndex);
        int generation = readerGeneration;
        String comicId = detail.summary.comicId;
        String chapterUrl = activeChapter.url;
        int contentWidth = Math.max(1, getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(this, 8));
        int placeholderHeight = Math.max(1, contentWidth * 4 / 3);
        List<String> imageUrls = new ArrayList<>(page.imageUrls);
        Map<ImageView, Future<?>> readerImageFutures = new HashMap<>();
        ListView list = new ListView(this);
        list.setBackgroundColor(UIHelpers.DARK);
        list.setCacheColorHint(UIHelpers.DARK);
        list.setDivider(null);
        list.setSelector(new ColorDrawable(Color.TRANSPARENT));
        list.setPadding(UIHelpers.dp(this, 4), UIHelpers.dp(this, 4), UIHelpers.dp(this, 4), UIHelpers.dp(this, 4));
        list.setClipToPadding(false);
        String positionKey = readerPositionKey(detail.summary.comicId, activeChapter);
        int savedPosition = readerPositions.containsKey(positionKey) ? readerPositions.get(positionKey) : 0;
        final boolean[] restoringPosition = {savedPosition > 0};
        list.setAdapter(new BaseAdapter() {
            @Override
            public int getCount() {
                return imageUrls.size();
            }

            @Override
            public String getItem(int position) {
                return imageUrls.get(position);
            }

            @Override
            public long getItemId(int position) {
                return position;
            }

            @Override
            public View getView(int position, View convertView, ViewGroup parent) {
                ImageView image;
                if (convertView instanceof ImageView) {
                    image = (ImageView) convertView;
                } else {
                    image = new ImageView(MainActivity.this);
                    image.setScaleType(ImageView.ScaleType.FIT_CENTER);
                    image.setBackgroundColor(UIHelpers.DARK);
                }
                Future<?> previous = readerImageFutures.remove(image);
                if (previous != null && !previous.isDone()) previous.cancel(true);
                String imageUrl = getItem(position);
                image.setImageDrawable(null);
                image.setTag(imageUrl);
                image.setLayoutParams(new AbsListView.LayoutParams(-1, placeholderHeight));
                Future<?> future = loadReaderImage(image, imageUrl, chapterUrl, generation, comicId,
                        list, restoringPosition, savedPosition);
                if (future != null) readerImageFutures.put(image, future);
                return image;
            }
        });

        list.setOnScrollListener(new AbsListView.OnScrollListener() {
            @Override
            public void onScrollStateChanged(AbsListView view, int scrollState) {
            }

            @Override
            public void onScroll(AbsListView view, int firstVisibleItem, int visibleItemCount, int totalItemCount) {
                if (!restoringPosition[0]) saveReaderPosition(list, positionKey);
            }
        });
        list.setOnTouchListener((v, event) -> {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) restoringPosition[0] = false;
            return handleReaderTap(event, detail, page);
        });
        list.addOnLayoutChangeListener((v, left, topEdge, right, bottomEdge,
                                        oldLeft, oldTop, oldRight, oldBottom) -> {
            if (restoringPosition[0] && savedPosition == READER_POSITION_SCALE) alignReaderBottom(list);
        });
        if (savedPosition > 0) {
            list.post(() -> {
                restoreReaderPosition(list, savedPosition);
                if (savedPosition < READER_POSITION_SCALE) list.post(() -> restoringPosition[0] = false);
            });
        }
        FrameLayout readerContent = new FrameLayout(this);
        readerContent.addView(list, UIHelpers.match());
        View empty = readerSkeletonState("没有解析到图片，请返回重试");
        readerContent.addView(empty, UIHelpers.match());
        list.setEmptyView(empty);
        shell.addView(readerContent, new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(readerProgressBar(readerChapterIndex + 1, detail.chapters.size()), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 1)));

        LinearLayout bottom = new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        bottom.setPadding(UIHelpers.dp(this, 14), 0, UIHelpers.dp(this, 14), 0);
        bottom.setBackgroundColor(UIHelpers.DARK_BAR);
        bottom.setVisibility(readerFullscreen ? View.GONE : View.VISIBLE);
        readerBottomBar = bottom;

        // 全面手势模式：底部仅显示页数，翻章靠左右点按
        TextView count = UIHelpers.text(this, page.imageUrls.size() + " 张图", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        count.setTypeface(Typeface.MONOSPACE);
        count.setGravity(Gravity.CENTER);
        bottom.addView(count, new LinearLayout.LayoutParams(-1, -2));
        shell.addView(bottom, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 36)));
    }

    private boolean handleReaderTap(MotionEvent event, ComicModels.ComicDetail detail, ComicModels.ChapterPage page) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            readerDownX = event.getRawX();
            readerDownY = event.getRawY();
            readerDownAt = System.currentTimeMillis();
            return false;
        }
        if (event.getActionMasked() != MotionEvent.ACTION_UP) return false;
        int width = getResources().getDisplayMetrics().widthPixels;
        int height = getResources().getDisplayMetrics().heightPixels;
        float x = event.getRawX();
        float y = event.getRawY();
        float moveX = Math.abs(x - readerDownX);
        float moveY = Math.abs(y - readerDownY);
        boolean tap = moveX < UIHelpers.dp(this, 10) && moveY < UIHelpers.dp(this, 10) && System.currentTimeMillis() - readerDownAt < 300L;
        boolean activeY = y > height * 0.25f && y < height * 0.75f;
        if (!tap || !activeY) return false;
        boolean leftSide = x < width * 0.28f;
        boolean rightSide = x > width * 0.72f;
        if (leftSide || rightSide) {
            boolean wantPrev = readerLeftHand ? rightSide : leftSide;
            switchChapter(detail, wantPrev ? -1 : 1);
        } else {
            toggleReaderFullscreen();
        }
        return true;
    }

    private void toggleReaderFullscreen() {
        readerFullscreen = !readerFullscreen;
        if (readerTopBar != null) readerTopBar.setVisibility(readerFullscreen ? View.GONE : View.VISIBLE);
        if (readerBottomBar != null) readerBottomBar.setVisibility(readerFullscreen ? View.GONE : View.VISIBLE);
        applyReaderSystemBars();
    }

    private void runSearch(String keyword) {
        resetSearchPaging();
        loadSearchPage(keyword, 1, false, false);
    }

    private void loadSearchPage(String keyword, int page, boolean append, boolean categoryMode) {
        ComicSource client = selectedSource();
        if (client == null) return;
        int generation = ++searchGeneration;
        if (append) {
            searchAppending = true;
            if (currentTab == 1 && searchResultsContent != null) renderSearchPagingFooter(searchResultsContent);
        } else {
            searchLoading = true;
        }
        if (currentTab == 1 && !append) showTab(1, false);
        track(searchIo.submit(() -> {
            try {
                List<ComicModels.ComicSummary> list = categoryMode
                        ? client.category(selectedRegion, selectedState, page)
                        : client.search(keyword == null ? "" : keyword.trim(), page);
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    if (!append) searchResults.clear();
                    searchResults.addAll(list);
                    for (ComicModels.ComicSummary item : list) summaries.put(item.comicId, item);
                    searchPage = page;
                    searchHasMore = !list.isEmpty();
                    searchLoading = false;
                    searchAppending = false;
                    if (currentTab == 1) {
                        if (append && searchResultsContent != null) {
                            appendSearchResults(list);
                        } else {
                            showTab(1, false);
                        }
                    }
                    persistComicCachesAsync();
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    if (isExpectedTaskCancellation(error)) {
                        searchLoading = false;
                        searchAppending = false;
                        return;
                    }
                    searchLoading = false;
                    searchAppending = false;
                    if (append) {
                        appendErrorLog("搜索分页加载失败", error);
                        searchHasMore = false;
                        showToast("加载更多失败");
                    } else {
                        showError("加载失败", error);
                    }
                });
            }
        }));
    }

    private void loadNextSearchPage() {
        if (searchLoading || searchAppending || !searchHasMore || currentTab != 1 || standaloneSearchVisible) return;
        loadSearchPage(searchQuery, searchPage + 1, true, TextUtils.isEmpty(searchQuery.trim()));
    }

    private void resetSearchPaging() {
        searchPage = 1;
        searchHasMore = true;
        searchAppending = false;
    }

    private void startGlobalSearch(String keyword) {
        globalSearchQuery = keyword == null ? "" : keyword.trim();
        globalSearchResults.clear();
        globalSearchShownIds.clear();
        globalSearchResultsBySource.clear();
        globalSearchShownIdsBySource.clear();
        globalSearchFailedSourceIds.clear();
        globalSearchCompletedSourceIds.clear();
        List<ComicSource> clients = enabledBuiltinSources();
        selectedGlobalSearchSourceId = clients.isEmpty() ? "" : clients.get(0).id();
        for (ComicSource client : clients) {
            globalSearchResultsBySource.put(client.id(), new ArrayList<>());
            globalSearchShownIdsBySource.put(client.id(), new HashSet<>());
        }
        globalSearchTotalSources = 0;
        globalSearchCompletedSources = 0;
        globalSearchFailedSources = 0;
        globalSearchLoadingView = null;
        globalSearchLoading = true;
        showStandaloneSearch(true);
        runGlobalSearch(globalSearchQuery);
    }

    /**
     * 并发站源搜索 · 流式填充
     * - 每个站源独立 io.submit()，完成（成功/失败/超时）后立即 main.post() 增量追加结果
     * - 不再用 CountDownLatch.await() 阻塞等待所有站源
     * - 每站源 10s 超时守护，超时算失败
     * - per-task AtomicBoolean counted 防止正常完成与超时重复计数
     * - generation 检查防止旧搜索污染新结果
     */
    private void runGlobalSearch(String keyword) {
        final int generation = ++globalSearchGeneration;
        final List<ComicSource> clients = enabledBuiltinSources();
        globalSearchTotalSources = clients.size();
        globalSearchCompletedSources = 0;
        globalSearchFailedSources = 0;
        updateGlobalSearchStatus();

        // 边界：没有启用的站源
        if (clients.isEmpty()) {
            main.post(() -> {
                if (generation != globalSearchGeneration) return;
                globalSearchLoading = false;
                if (standaloneSearchVisible) showStandaloneSearch(true);
            });
            return;
        }

        final String query = keyword == null ? "" : keyword.trim();

        for (final ComicSource client : clients) {
            final AtomicBoolean counted = new AtomicBoolean(false);
            Future<?> future = track(searchIo.submit(() -> {
                List<ComicModels.ComicSummary> partial = new ArrayList<>();
                boolean failed = false;
                try {
                    List<ComicModels.ComicSummary> got = client.search(query, 1);
                    if (got != null) partial = got;
                } catch (Exception e) {
                    failed = true;
                }
                final List<ComicModels.ComicSummary> result = partial;
                final boolean isFailed = failed;
                main.post(() -> {
                    if (generation != globalSearchGeneration) return;
                    String sourceId = client.id();
                    if (!isFailed) {
                        addGlobalSearchSourceResults(sourceId, result);
                        if (!globalResultsForSource(sourceId).isEmpty() && globalResultsForSource(selectedGlobalSearchSourceId).isEmpty()) {
                            selectedGlobalSearchSourceId = sourceId;
                        }
                    }
                    if (counted.compareAndSet(false, true)) {
                        if (isFailed) {
                            globalSearchFailedSources++;
                            globalSearchFailedSourceIds.add(sourceId);
                        }
                        globalSearchCompletedSourceIds.add(sourceId);
                        globalSearchCompletedSources++;
                        refreshGlobalSearchSourceState(sourceId);
                        onGlobalSearchSourceDone(generation);
                    }
                    if (System.currentTimeMillis() >= 0) return;
                    if (!isFailed) {
                        // 增量追加 + comicId 去重
                        for (ComicModels.ComicSummary item : result) {
                            if (globalSearchShownIds.add(item.comicId)) {
                                globalSearchResults.add(item);
                                summaries.put(item.comicId, item);
                                // 增量 addView，不重建整个列表
                                if (globalSearchContent != null) {
                                    // 首个结果到来时移除 loading 动画
                                    if (globalSearchLoadingView != null
                                            && globalSearchLoadingView.getParent() == globalSearchContent) {
                                        globalSearchContent.removeView(globalSearchLoadingView);
                                        globalSearchLoadingView = null;
                                    }
                                    globalSearchContent.addView(globalResultRow(item));
                                }
                            }
                        }
                    }
                    if (counted.compareAndSet(false, true)) {
                        if (isFailed) globalSearchFailedSources++;
                        globalSearchCompletedSources++;
                        onGlobalSearchSourceDone(generation);
                    }
                });
            }));
            // 10s 超时守护（非阻塞调度，不占 io 线程）
            final Future<?> f = future;
            scheduledIo.schedule(() -> {
                if (f.isDone()) return;
                f.cancel(true);
                main.post(() -> {
                    if (generation != globalSearchGeneration) return;
                    if (counted.compareAndSet(false, true)) {
                        globalSearchFailedSources++;
                        globalSearchFailedSourceIds.add(client.id());
                        globalSearchCompletedSourceIds.add(client.id());
                        globalSearchCompletedSources++;
                        refreshGlobalSearchSourceState(client.id());
                        onGlobalSearchSourceDone(generation);
                    }
                });
            }, 10, TimeUnit.SECONDS);
        }
    }

    /** 单个站源完成时的统一收尾（计数、状态、关闭 loading） */
    private void onGlobalSearchSourceDone(int generation) {
        updateGlobalSearchStatus();
        if (globalSearchCompletedSources >= globalSearchTotalSources) {
            globalSearchLoading = false;
            persistComicCachesAsync();
            updateGlobalSearchStatus();
            // 全部完成时若列表仍为空，刷新以显示空状态（移除 loading 动画）
            if (standaloneSearchVisible && globalSearchAllResultsEmpty()) {
                refreshGlobalSearchTabs();
                refreshGlobalSearchResults();
            }
        }
    }

    private void refreshGlobalSearchSourceState(String sourceId) {
        if (!standaloneSearchVisible || !standaloneSearchResultsMode) return;
        refreshGlobalSearchTabs();
        if (sourceId.equals(selectedGlobalSearchSourceId)) refreshGlobalSearchResults();
    }

    /** 更新底部状态文字：N/M 完成 · K 失败 */
    private void updateGlobalSearchStatus() {
        if (globalSearchStatusView == null) return;
        if (globalSearchLoading) {
            String text = "正在搜索 · " + globalSearchCompletedSources + "/" + globalSearchTotalSources + " 个站源";
            if (globalSearchFailedSources > 0) {
                text += " · " + globalSearchFailedSources + " 个失败";
            }
            globalSearchStatusView.setText(text);
        } else {
            String text = "完成 · " + globalSearchCompletedSources + "/" + globalSearchTotalSources + " 个站源";
            if (globalSearchFailedSources > 0) {
                text += " · " + globalSearchFailedSources + " 个失败";
            }
            globalSearchStatusView.setText(text);
        }
    }

    private void addSearchHistory(String keyword) {
        if (TextUtils.isEmpty(keyword)) return;
        globalSearchHistory.remove(keyword);
        globalSearchHistory.add(0, keyword);
        while (globalSearchHistory.size() > 60) globalSearchHistory.remove(globalSearchHistory.size() - 1);
        saveLocalState();
    }

    private String sourceNameForId(String sourceId) {
        if (sourceClient.id().equals(sourceId)) return sourceClient.name();
        if (mhua5Client.id().equals(sourceId)) return mhua5Client.name();
        if (aikanClient.id().equals(sourceId)) return aikanClient.name();
        if (gmhClient.id().equals(sourceId)) return gmhClient.name();
        if (mkzhanClient.id().equals(sourceId)) return mkzhanClient.name();
        if (hiperdexClient.id().equals(sourceId)) return hiperdexClient.name();
        if (manhuaguiClient.id().equals(sourceId)) return manhuaguiClient.name();
        if (hanman18Client.id().equals(sourceId)) return hanman18Client.name();
        if (d5d6Client.id().equals(sourceId)) return d5d6Client.name();
        if (manbenClient.id().equals(sourceId)) return manbenClient.name();
        for (ComicModels.Source item : customSources) {
            if (item.id.equals(sourceId)) return item.name;
        }
        return clean(sourceId, "未知来源");
    }

    private ComicSource selectedSource() {
        if (sourceClient.id().equals(selectedSourceId) && sourceEnabled) return sourceClient;
        if (mhua5Client.id().equals(selectedSourceId) && mhua5Enabled) return mhua5Client;
        if (aikanClient.id().equals(selectedSourceId) && aikanEnabled) return aikanClient;
        if (gmhClient.id().equals(selectedSourceId) && gmhEnabled) return gmhClient;
        if (mkzhanClient.id().equals(selectedSourceId) && mkzhanEnabled) return mkzhanClient;
        if (hiperdexClient.id().equals(selectedSourceId) && hiperdexEnabled) return hiperdexClient;
        if (manhuaguiClient.id().equals(selectedSourceId) && manhuaguiEnabled) return manhuaguiClient;
        if (hanman18Client.id().equals(selectedSourceId) && hanman18Enabled) return hanman18Client;
        if (d5d6Client.id().equals(selectedSourceId) && d5d6Enabled) return d5d6Client;
        if (manbenClient.id().equals(selectedSourceId) && manbenEnabled) return manbenClient;
        List<ComicSource> enabled = enabledBuiltinSources();
        if (enabled.isEmpty()) return null;
        selectedSourceId = enabled.get(0).id();
        return enabled.get(0);
    }

    private List<ComicSource> enabledBuiltinSources() {
        List<ComicSource> sources = new ArrayList<>();
        if (sourceEnabled) sources.add(sourceClient);
        if (mhua5Enabled) sources.add(mhua5Client);
        if (aikanEnabled) sources.add(aikanClient);
        if (gmhEnabled) sources.add(gmhClient);
        if (mkzhanEnabled) sources.add(mkzhanClient);
        if (hiperdexEnabled) sources.add(hiperdexClient);
        if (manhuaguiEnabled) sources.add(manhuaguiClient);
        if (hanman18Enabled) sources.add(hanman18Client);
        if (d5d6Enabled) sources.add(d5d6Client);
        if (manbenEnabled) sources.add(manbenClient);
        return sources;
    }

    private ComicSource sourceForComicId(String comicId) {
        ComicModels.ComicSummary summary = summaries.get(comicId);
        if (summary != null) return sourceForId(summary.sourceId);
        if (comicId != null && comicId.startsWith(mhua5Client.id() + ":")) return mhua5Client;
        if (comicId != null && comicId.startsWith(aikanClient.id() + ":")) return aikanClient;
        if (comicId != null && comicId.startsWith(gmhClient.id() + ":")) return gmhClient;
        if (comicId != null && comicId.startsWith(mkzhanClient.id() + ":")) return mkzhanClient;
        if (comicId != null && comicId.startsWith(hiperdexClient.id() + ":")) return hiperdexClient;
        if (comicId != null && comicId.startsWith(manhuaguiClient.id() + ":")) return manhuaguiClient;
        if (comicId != null && comicId.startsWith(hanman18Client.id() + ":")) return hanman18Client;
        if (comicId != null && comicId.startsWith(d5d6Client.id() + ":")) return d5d6Client;
        if (comicId != null && comicId.startsWith(manbenClient.id() + ":")) return manbenClient;
        return sourceClient;
    }

    private ComicSource sourceForDetail(ComicModels.ComicDetail detail) {
        return detail == null || detail.summary == null ? sourceClient : sourceForId(detail.summary.sourceId);
    }

    private ComicSource sourceForId(String sourceId) {
        if (mhua5Client.id().equals(sourceId)) return mhua5Client;
        if (aikanClient.id().equals(sourceId)) return aikanClient;
        if (gmhClient.id().equals(sourceId)) return gmhClient;
        if (mkzhanClient.id().equals(sourceId)) return mkzhanClient;
        if (hiperdexClient.id().equals(sourceId)) return hiperdexClient;
        if (manhuaguiClient.id().equals(sourceId)) return manhuaguiClient;
        if (hanman18Client.id().equals(sourceId)) return hanman18Client;
        if (d5d6Client.id().equals(sourceId)) return d5d6Client;
        if (manbenClient.id().equals(sourceId)) return manbenClient;
        return sourceClient;
    }

    private void loadDefaultCategory() {
        resetSearchPaging();
        loadSearchPage("", 1, false, true);
    }

    private void scheduleDefaultSearchLoad() {
        if (currentTab != 1 || selectedSource() == null
                || (!searchResults.isEmpty() && !defaultSearchRefreshPending)
                || !TextUtils.isEmpty(searchQuery.trim()) || searchLoading) return;
        int generation = searchGeneration;
        boolean refreshCached = defaultSearchRefreshPending;
        defaultSearchRefreshPending = false;
        searchLoading = true;
        main.post(() -> {
            if (generation != searchGeneration) return;
            if (currentTab != 1 || (!searchResults.isEmpty() && !refreshCached)
                    || !TextUtils.isEmpty(searchQuery.trim())) {
                searchLoading = false;
                return;
            }
            loadDefaultCategory();
        });
    }

    private void loadCategory() {
        resetSearchPaging();
        loadSearchPage("", 1, false, true);
    }

    private void loadSourceCategories() {
        ComicSource client = selectedSource();
        if (client == null) return;
        int generation = ++categoryGeneration;
        String sourceId = client.id();
        track(searchIo.submit(() -> {
            try {
                List<String> list = client.categories();
                main.post(() -> {
                    if (generation != categoryGeneration || !TextUtils.equals(sourceId, selectedSourceId)) return;
                    sourceCategories.clear();
                    sourceCategories.addAll(list);
                    if (filterDrawerAction != null) {
                        filterDrawerAction.run();
                    } else if (currentTab == 1) {
                        showTab(1, false);
                    }
                });
            } catch (Exception ignored) {
            }
        }));
    }

    private void showDetailThenRead(String id) {
        ComicModels.ComicDetail detail = details.get(id);
        if (detail != null) {
            ensureChaptersThen(detail, loaded -> showReader(loaded, savedChapter(id)));
            return;
        }
        showDetail(id);
    }

    private void switchChapter(ComicModels.ComicDetail detail, int delta) {
        int next = readerChapterIndex + delta;
        if (next < 0 || next >= detail.chapters.size()) {
            showToast(delta > 0 ? "已经是最后一章" : "已经是第一章");
            return;
        }
        showReader(detail, next);
    }

    private void normalizeChaptersOldestFirst(List<ComicModels.Chapter> chapters) {
        if (chapters == null || chapters.size() < 2) return;
        Long first = extractChapterNumber(chapters.get(0).title);
        Long last = extractChapterNumber(chapters.get(chapters.size() - 1).title);
        if (first == null || last == null) return;
        if (first > last) {
            Collections.reverse(chapters);
        }
    }

    private static Long extractChapterNumber(String title) {
        if (title == null) return null;
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("(\\d+)").matcher(title);
        if (m.find()) {
            try {
                return Long.parseLong(m.group(1));
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }

    private View chapterEntry(ComicModels.ComicDetail detail) {
        LinearLayout card = UIHelpers.card(this);
        card.setOnClickListener(v -> showChapterDrawer(detail));
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(UIHelpers.text(this, "章节目录", 16, UIHelpers.TEXT, Typeface.BOLD));
        String status = detail.chapters.isEmpty() ? "点击后加载目录，提升详情页打开速度" : detail.chapters.size() + " 章 · " + (chapterDesc ? "倒序" : "正序");
        text.addView(UIHelpers.text(this, status, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));
        row.addView(text, UIHelpers.weight(1));
        TextView action = UIHelpers.chip(this, "打开", false);
        action.setTextColor(UIHelpers.TEXT2);
        action.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 12), UIHelpers.BORDER));
        row.addView(action);
        card.addView(row);
        return card;
    }

    private interface DetailAction {
        void run(ComicModels.ComicDetail detail);
    }

    private void ensureChaptersThen(ComicModels.ComicDetail detail, DetailAction action) {
        if (refreshingComicIds.contains(detail.summary.comicId)) {
            waitForComicRefresh(detail, action);
            return;
        }
        if (!detail.chapters.isEmpty()) {
            action.run(detail);
            return;
        }
        int loadingGeneration = showPageLoading("正在加载章节目录...", "目录加载完成后会自动打开。", () -> showDetail(detail.summary.comicId));
        track(detailIo.submit(() -> {
            try {
                ComicSource client = sourceForDetail(detail);
                List<ComicModels.Chapter> loadedChapters = client.chapters(detail.summary.comicId);
                if (loadedChapters.isEmpty()) {
                    main.post(() -> {
                        if (!isCurrentLoading(loadingGeneration)) return;
                        pageLoading = false;
                        pageLoadingBackAction = null;
                        showDetail(detail.summary.comicId);
                        styledDialog("暂无章节", "未找到该漫画的章节目录，可能暂无可用章节或站源暂未收录。", "重试", () -> ensureChaptersThen(detail, action), "取消", null);
                    });
                    return;
                }
                normalizeChaptersOldestFirst(loadedChapters);
                ComicModels.ComicDetail loaded = new ComicModels.ComicDetail(
                        detail.summary,
                        detail.author,
                        detail.status,
                        detail.description,
                        detail.latestChapter,
                        loadedChapters);
                main.post(() -> {
                    if (!isCurrentLoading(loadingGeneration)) return;
                    pageLoading = false;
                    pageLoadingBackAction = null;
                    details.put(detail.summary.comicId, loaded);
                    persistComicCachesAsync();
                    action.run(loaded);
                });
            } catch (Exception error) {
                boolean expectedCancellation = isExpectedTaskCancellation(error);
                main.post(() -> {
                    if (expectedCancellation || !isCurrentLoading(loadingGeneration)) return;
                    pageLoading = false;
                    pageLoadingBackAction = null;
                    appendErrorLog("目录加载失败", error);
                    showDetail(detail.summary.comicId);
                    styledDialog("目录加载失败", clean(error.getMessage(), "请稍后重试。"), "重试", () -> ensureChaptersThen(detail, action), "取消", null);
                });
            }
        }));
    }

    private void showChapterDrawer(ComicModels.ComicDetail detail) {
        if (detail.chapters.isEmpty()) {
            ensureChaptersThen(detail, loaded -> {
                showDetail(loaded.summary.comicId);
                main.post(() -> showChapterDrawer(loaded));
            });
            return;
        }
        chapterDesc = false;
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));
        panel.setBackgroundColor(UIHelpers.CARD);

        LinearLayout header = chapterDrawerHeader(detail.chapters.size());
        TextView order = UIHelpers.chip(this, chapterDesc ? "倒序" : "正序", true);
        header.addView(order);
        panel.addView(header, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));

        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, UIHelpers.matchWrap());
        panel.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        PopupWindow popup = new PopupWindow(panel, Math.min(getResources().getDisplayMetrics().widthPixels, UIHelpers.dp(this, 340)), -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(UIHelpers.CARD));
        popup.setOutsideTouchable(true);
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
        });

        Runnable fill = () -> {
            list.removeAllViews();
            List<Integer> orderIndexes = DataHelpers.chapterOrder(chapterDesc, detail.chapters.size());
            fillChapterRows(list, popup, detail, orderIndexes, 0);
        };
        order.setOnClickListener(v -> {
            chapterDesc = !chapterDesc;
            saveLocalState();
            order.setText(chapterDesc ? "倒序" : "正序");
            fill.run();
        });
        activePopup = popup;
        popup.showAtLocation(root, Gravity.RIGHT, 0, 0);
        fill.run();
    }

    private void fillChapterRows(LinearLayout list, PopupWindow popup, ComicModels.ComicDetail detail, List<Integer> orderIndexes, int start) {
        int endIndex = Math.min(start + CHAPTER_DRAWER_BATCH_SIZE, orderIndexes.size());
        for (int i = start; i < endIndex; i++) {
                int chapterIndex = orderIndexes.get(i);
                ComicModels.Chapter chapter = detail.chapters.get(chapterIndex);
                String end = readerChapterIndex == chapterIndex ? "当前" : (i == 0 ? "新着" : chapterNumber(chapterIndex, detail.chapters.size()));
                View item = chapterDrawerRow(chapter.title, end, chapterIndex == readerChapterIndex);
                item.setOnClickListener(v -> {
                    popup.dismiss();
                    showReader(detail, chapterIndex);
                });
                list.addView(item);
                if (i < orderIndexes.size() - 1) list.addView(UIHelpers.divider(this));
        }
        if (endIndex < orderIndexes.size() && activePopup == popup) {
            main.postDelayed(() -> fillChapterRows(list, popup, detail, orderIndexes, endIndex), 16);
        }
    }

    private LinearLayout chapterDrawerHeader(int count) {
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(UIHelpers.text(this, "章节目录", 18, UIHelpers.TEXT, Typeface.BOLD));
        text.addView(UIHelpers.text(this, count + " 章", 12, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 3)));
        header.addView(text, UIHelpers.weight(1));
        return header;
    }

    private View chapterDrawerRow(String title, String end, boolean current) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, UIHelpers.dp(this, 14), 0, UIHelpers.dp(this, 14));
        TextView name = UIHelpers.text(this, title, 14, current ? UIHelpers.TEXT3 : UIHelpers.TEXT, Typeface.NORMAL);
        name.setSingleLine(true);
        name.setEllipsize(TextUtils.TruncateAt.END);
        row.addView(name, UIHelpers.weight(1));
        row.addView(chapterNumberView(end, current));
        return row;
    }

    private TextView chapterNumberView(String value, boolean current) {
        TextView view = UIHelpers.text(this, value, 12, current ? UIHelpers.ACCENT : UIHelpers.TEXT3, Typeface.NORMAL);
        view.setTypeface(Typeface.MONOSPACE);
        view.setGravity(Gravity.RIGHT | Gravity.CENTER_VERTICAL);
        return view;
    }

    private void toggleFavorite(ComicModels.ComicDetail detail) {
        String id = detail.summary.comicId;
        if (favorites.contains(id)) {
            favorites.remove(id);
            favoriteAt.remove(id);
            showToast("已取消收藏");
        } else {
            removeDuplicateFavorites(detail);
            favorites.remove(id);
            favorites.add(0, id);
            favoriteAt.put(id, System.currentTimeMillis());
            details.put(id, detail);
            summaries.put(id, detail.summary);
            persistComicCachesAsync();
            loadImageToCache(detail.summary.coverUrl);
            showToast("已加入收藏");
        }
        saveLocalState();
        showDetail(id);
    }

    private void deleteFavorite(String id) {
        favorites.remove(id);
        favoriteAt.remove(id);
        saveLocalState();
        showToast("已删除收藏");
        showTab(0);
    }

    private void removeDuplicateFavorites(ComicModels.ComicDetail detail) {
        String target = normalizedComicTitle(detail.summary.title);
        if (TextUtils.isEmpty(target)) return;
        for (String oldId : new ArrayList<>(favorites)) {
            if (oldId.equals(detail.summary.comicId)) continue;
            ComicModels.ComicDetail oldDetail = details.get(oldId);
            ComicModels.ComicSummary oldSummary = summaries.get(oldId);
            String oldTitle = oldDetail != null ? oldDetail.summary.title : oldSummary != null ? oldSummary.title : "";
            if (target.equals(normalizedComicTitle(oldTitle))) {
                favorites.remove(oldId);
                favoriteAt.remove(oldId);
            }
        }
    }

    private String normalizedComicTitle(String title) {
        return title == null ? "" : title.toLowerCase(Locale.ROOT).replaceAll("[\\s《》〈〉【】\\[\\]（）()\\-_:：·.,，。!！?？]+", "");
    }

    private ImageView coverView(String url, int widthDp, int heightDp) {
        ImageView image = new ImageView(this);
        image.setScaleType(ImageView.ScaleType.CENTER_CROP);
        image.setBackground(UIHelpers.round(UIHelpers.BORDER_SOFT, UIHelpers.dp(this, 10), Color.TRANSPARENT));
        int width = widthDp < 0 ? -1 : UIHelpers.dp(this, widthDp);
        image.setLayoutParams(new LinearLayout.LayoutParams(width, UIHelpers.dp(this, heightDp)));
        if (!TextUtils.isEmpty(url)) loadImage(image, url);
        return image;
    }

    private HorizontalScrollView detailTagRow(List<String> tags) {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (String tag : tags) {
            if (!TextUtils.isEmpty(tag)) row.addView(detailTagPill(tag), UIHelpers.marginRight(-2, UIHelpers.dp(this, 8)));
        }
        scroll.addView(row, UIHelpers.wrap());
        return scroll;
    }

    private TextView detailTagPill(String value) {
        TextView pill = UIHelpers.text(this, value, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        pill.setGravity(Gravity.CENTER);
        pill.setPadding(UIHelpers.dp(this, 10), UIHelpers.dp(this, 5), UIHelpers.dp(this, 10), UIHelpers.dp(this, 5));
        pill.setBackground(UIHelpers.round(Color.TRANSPARENT, UIHelpers.dp(this, 14), UIHelpers.BORDER));
        return pill;
    }

    private FrameLayout coverFrame(String url, int widthDp, int heightDp) {
        FrameLayout frame = new FrameLayout(this);
        frame.setBackground(UIHelpers.round(UIHelpers.PLACEHOLDER, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        int width = widthDp < 0 ? -1 : UIHelpers.dp(this, widthDp);
        frame.setLayoutParams(new LinearLayout.LayoutParams(width, UIHelpers.dp(this, heightDp)));
        ImageView image = coverView(url, -1, heightDp);
        frame.addView(image, UIHelpers.frame(-1, UIHelpers.dp(this, heightDp), Gravity.CENTER, 0, 0, 0, 0));
        if (TextUtils.isEmpty(url)) {
            TextView mark = UIHelpers.text(this, "漫", 20, UIHelpers.TEXT3, Typeface.NORMAL);
            mark.setGravity(Gravity.CENTER);
            frame.addView(mark, UIHelpers.frame(-1, -1, Gravity.CENTER, 0, 0, 0, 0));
        }
        return frame;
    }

    private void addBlurredHeroCover(FrameLayout hero, String coverUrl, String fallbackTitle) {
        if (!TextUtils.isEmpty(coverUrl)) {
            ImageView cover = new ImageView(this);
            cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
            cover.setAlpha(0.36f);
            applyHeroBlur(cover);
            hero.addView(cover, UIHelpers.frame(-1, -1, Gravity.CENTER, 0, 0, 0, 0));
            loadImage(cover, coverUrl);
        } else {
            TextView title = UIHelpers.text(this, clean(fallbackTitle, "XX Comic"), 20, UIHelpers.TEXT3, Typeface.NORMAL);
            title.setGravity(Gravity.CENTER);
            hero.addView(title, UIHelpers.frame(-1, -1, Gravity.CENTER, 0, 0, 0, 0));
        }
        View veil = new View(this);
        veil.setBackgroundColor(Color.argb(82, 15, 15, 18));
        hero.addView(veil, UIHelpers.frame(-1, -1, Gravity.CENTER, 0, 0, 0, 0));
    }

    private void applyHeroBlur(ImageView cover) {
        BlurMaskFilter fallback = new BlurMaskFilter(UIHelpers.dp(this, 12), BlurMaskFilter.Blur.NORMAL);
        cover.setLayerType(View.LAYER_TYPE_SOFTWARE, null);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            cover.setRenderEffect(RenderEffect.createBlurEffect(UIHelpers.dp(this, 14), UIHelpers.dp(this, 14), Shader.TileMode.CLAMP));
        } else if (fallback != null) {
            cover.setAlpha(0.28f);
        }
    }

    private String chapterNumber(int index, int total) {
        int width = Math.max(3, String.valueOf(Math.max(1, total)).length());
        return String.format(java.util.Locale.US, "%0" + width + "d/%0" + width + "d", index + 1, Math.max(1, total));
    }

    private TextView sourceLogo(String name) {
        String first = TextUtils.isEmpty(name) ? "源" : name.substring(0, 1);
        TextView logo = UIHelpers.text(this, first, 18, UIHelpers.ACCENT, Typeface.NORMAL);
        logo.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        logo.setGravity(Gravity.CENTER);
        logo.setBackground(UIHelpers.round(UIHelpers.ACCENT_LIGHT, UIHelpers.dp(this, 24), Color.TRANSPARENT));
        logo.setLayoutParams(new LinearLayout.LayoutParams(UIHelpers.dp(this, 48), UIHelpers.dp(this, 48)));
        return logo;
    }

    private View statusDot(boolean enabled) {
        View dot = new View(this);
        dot.setBackground(UIHelpers.round(enabled ? UIHelpers.GREEN : UIHelpers.TEXT3, UIHelpers.dp(this, 4), Color.TRANSPARENT));
        dot.setLayoutParams(new LinearLayout.LayoutParams(UIHelpers.dp(this, 8), UIHelpers.dp(this, 8)));
        return dot;
    }

    private FrameLayout sourceSwitch(boolean enabled, Runnable toggle) {
        FrameLayout track = new FrameLayout(this);
        track.setPadding(UIHelpers.dp(this, 4), 0, UIHelpers.dp(this, 4), 0);
        track.setClipToPadding(false);
        track.setClickable(true);
        track.setFocusable(true);
        track.setContentDescription(enabled ? "站源已启用" : "站源已停用");
        track.setOnClickListener(v -> toggle.run());
        track.setBackground(UIHelpers.round(enabled ? UIHelpers.ACCENT : UIHelpers.SURFACE, UIHelpers.dp(this, 14), enabled ? Color.TRANSPARENT : UIHelpers.BORDER));
        View knob = new View(this);
        knob.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 10), enabled ? Color.TRANSPARENT : UIHelpers.BORDER_SOFT));
        knob.setElevation(UIHelpers.dp(this, enabled ? 2 : 1));
        track.addView(knob, UIHelpers.frame(UIHelpers.dp(this, 20), UIHelpers.dp(this, 20), enabled ? Gravity.RIGHT | Gravity.CENTER_VERTICAL : Gravity.LEFT | Gravity.CENTER_VERTICAL, 0, 0, 0, 0));
        return track;
    }

    private View readerProgressBar(int current, int total) {
        FrameLayout track = new FrameLayout(this);
        track.setBackgroundColor(Color.argb(70, 232, 232, 230));
        View fill = new View(this);
        fill.setBackgroundColor(UIHelpers.BRAND);
        int screen = getResources().getDisplayMetrics().widthPixels;
        int width = Math.max(1, Math.round(screen * (current / (float) Math.max(1, total))));
        fill.setAlpha(READER_PROGRESS_ANIM_MS > 0 ? 1f : 1f);
        track.addView(fill, new FrameLayout.LayoutParams(width, -1));
        return track;
    }

    private View readerSkeletonState(String message) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        View block = new View(this);
        block.setBackground(UIHelpers.round(Color.rgb(42, 42, 46), UIHelpers.dp(this, 8), Color.TRANSPARENT));
        box.addView(block, new LinearLayout.LayoutParams(UIHelpers.dp(this, 170), UIHelpers.dp(this, 226)));
        TextView text = UIHelpers.text(this, message, 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        text.setGravity(Gravity.CENTER);
        box.addView(text, UIHelpers.marginTop(-1, UIHelpers.dp(this, 16)));
        return box;
    }

    private long[] captureImageCacheIdentity(File file) {
        synchronized (imageCacheLock) {
            if (!file.exists()) return null;
            return new long[]{file.length(), file.lastModified()};
        }
    }

    private void deleteImageCacheIfUnchanged(File file, long[] identity) {
        if (identity == null) return;
        synchronized (imageCacheLock) {
            if (file.exists() && file.length() == identity[0] && file.lastModified() == identity[1]) {
                long length = file.length();
                if (file.delete() && imageCacheBytes >= 0L) imageCacheBytes = Math.max(0L, imageCacheBytes - length);
            }
        }
    }

    private Future<?> loadReaderImage(ImageView target, String imageUrl, String chapterUrl,
                                      int generation, String comicId, ListView list,
                                      boolean[] restoringPosition, int savedPosition) {
        if (TextUtils.isEmpty(imageUrl)) return null;
        return submitReaderImage(() -> {
            HttpURLConnection connection = null;
            try {
                File cached = imageCacheFile(imageUrl);
                long[] cachedIdentity = captureImageCacheIdentity(cached);
                Bitmap bitmap = cachedIdentity != null ? decodeReaderImage(cached, readerContentWidth()) : null;
                if (bitmap == null) {
                    deleteImageCacheIfUnchanged(cached, cachedIdentity);
                    connection = (HttpURLConnection) new URL(imageUrl).openConnection();
                    connection.setInstanceFollowRedirects(true);
                    connection.setConnectTimeout(10000);
                    connection.setReadTimeout(30000);
                    String referer = refererForImage(imageUrl, chapterUrl);
                    applyImageHeaders(connection, referer);
                    int code = connection.getResponseCode();
                    if (code >= 400) throw new IOException("Image HTTP " + code + ": " + imageUrl + "; referer=" + referer);
                    try (InputStream stream = connection.getInputStream()) {
                        writeReaderImageCache(cached, stream);
                    }
                    bitmap = decodeReaderImage(cached, readerContentWidth());
                } else {
                    cached.setLastModified(System.currentTimeMillis());
                }
                if (bitmap == null) throw new IOException("Reader image decode failed: " + imageUrl);
                Bitmap loaded = bitmap;
                main.post(() -> {
                    if (activityDestroyed || !TextUtils.equals(imageUrl, (String) target.getTag())
                            || !isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                    ViewGroup.LayoutParams params = target.getLayoutParams();
                    params.height = Math.max(1, Math.round(readerContentWidth()
                            * loaded.getHeight() / (float) Math.max(1, loaded.getWidth())));
                    target.setLayoutParams(params);
                    target.setImageBitmap(loaded);
                    if (restoringPosition[0] && savedPosition == READER_POSITION_SCALE) {
                        list.post(() -> {
                            if (!activityDestroyed && restoringPosition[0]
                                    && savedPosition == READER_POSITION_SCALE
                                    && TextUtils.equals(imageUrl, (String) target.getTag())
                                    && isCurrentReaderImageRequest(generation, comicId, chapterUrl)) {
                                alignReaderBottom(list);
                            }
                        });
                    }
                });
            } catch (Exception error) {
                if (isExpectedTaskCancellation(error)) return;
                appendErrorLog("图片加载失败", error);
                main.post(() -> {
                    if (activityDestroyed || !TextUtils.equals(imageUrl, (String) target.getTag())
                            || !isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                    target.setImageDrawable(new ColorDrawable(UIHelpers.BORDER_SOFT));
                });
            } finally {
                if (connection != null) connection.disconnect();
            }
        });
    }

    private boolean isCurrentReaderImageRequest(int generation, String comicId, String chapterUrl) {
        if (generation != readerGeneration || !readerVisible || !TextUtils.equals(activeDetailId, comicId)) return false;
        ComicModels.ComicDetail detail = details.get(comicId);
        if (detail == null || readerChapterIndex < 0 || readerChapterIndex >= detail.chapters.size()) return false;
        return TextUtils.equals(detail.chapters.get(readerChapterIndex).url, chapterUrl);
    }

    private Bitmap decodeReaderImage(File file, int targetWidth) {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;
        long sampleSize = 1L;
        long maxBytes = READER_MAX_DECODE_BYTES;
        while (true) {
            long sampledWidth = (bounds.outWidth + sampleSize - 1L) / sampleSize;
            long sampledHeight = (bounds.outHeight + sampleSize - 1L) / sampleSize;
            long sampledPixels = sampledWidth * sampledHeight;
            boolean tooWide = sampledWidth > Math.max(1, targetWidth);
            boolean tooLarge = sampledPixels > READER_MAX_DECODE_PIXELS || sampledPixels > maxBytes / 4L;
            if (!tooWide && !tooLarge) break;
            if (sampleSize > Integer.MAX_VALUE / 2L) return null;
            sampleSize *= 2L;
        }
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = (int) sampleSize;
        return BitmapFactory.decodeFile(file.getAbsolutePath(), options);
    }

    private int readerContentWidth() {
        return Math.max(1, getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(this, 8));
    }

    private void loadImage(ImageView target, String imageUrl) {
        loadImage(target, imageUrl, "");
    }

    private void loadImage(ImageView target, String imageUrl, String pageReferer) {
        if (TextUtils.isEmpty(imageUrl)) return;
        // 内存命中：同步 set，不进 imageIo，切 Tab 重建列表时即时显示。
        Bitmap memHit = imageMemoryCache.get(imageUrl);
        if (memHit != null) {
            target.setImageBitmap(memHit);
            return;
        }
        trackImage(imageIo.submit(() -> {
            HttpURLConnection connection = null;
            try {
                File cached = imageCacheFile(imageUrl);
                long[] cachedIdentity = captureImageCacheIdentity(cached);
                if (cachedIdentity != null) {
                    Bitmap cachedBitmap = BitmapFactory.decodeFile(cached.getAbsolutePath());
                    if (cachedBitmap != null) {
                        cached.setLastModified(System.currentTimeMillis());
                        imageMemoryCache.put(imageUrl, cachedBitmap);
                        main.post(() -> target.setImageBitmap(cachedBitmap));
                        return;
                    }
                    deleteImageCacheIfUnchanged(cached, cachedIdentity);
                }
                connection = (HttpURLConnection) new URL(imageUrl).openConnection();
                connection.setInstanceFollowRedirects(true);
                connection.setConnectTimeout(10000);
                connection.setReadTimeout(30000);
                String referer = refererForImage(imageUrl, pageReferer);
                applyImageHeaders(connection, referer);
                int code = connection.getResponseCode();
                if (code >= 400) throw new IOException("Image HTTP " + code + ": " + imageUrl + "; referer=" + referer);
                String contentType = clean(connection.getContentType(), "");
                try (InputStream stream = connection.getInputStream()) {
                    byte[] bytes = readAllBytes(stream);
                    Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                    if (bitmap != null) {
                        writeImageCache(cached, bytes);
                        imageMemoryCache.put(imageUrl, bitmap);
                        main.post(() -> target.setImageBitmap(bitmap));
                    } else {
                        throw new IOException("Image decode failed: " + imageUrl + "; bytes=" + bytes.length + "; type=" + contentType + "; referer=" + referer);
                    }
                }
            } catch (Exception error) {
                if (isExpectedTaskCancellation(error)) return;
                appendErrorLog("图片加载失败", error);
                main.post(() -> target.setImageDrawable(new ColorDrawable(UIHelpers.BORDER_SOFT)));
            } finally {
                if (connection != null) connection.disconnect();
            }
        }));
    }

    private void loadImageToCache(String imageUrl) {
        if (TextUtils.isEmpty(imageUrl)) return;
        imageIo.execute(() -> {
            HttpURLConnection connection = null;
            try {
                File cached = imageCacheFile(imageUrl);
                if (cached.exists()) {
                    cached.setLastModified(System.currentTimeMillis());
                    return;
                }
                connection = (HttpURLConnection) new URL(imageUrl).openConnection();
                connection.setInstanceFollowRedirects(true);
                connection.setConnectTimeout(10000);
                connection.setReadTimeout(20000);
                applyImageHeaders(connection, refererForImage(imageUrl));
                try (InputStream stream = connection.getInputStream()) {
                    writeImageCache(cached, readAllBytes(stream));
                }
                updateCacheSize();
            } catch (Exception ignored) {
            } finally {
                if (connection != null) connection.disconnect();
            }
        });
    }

    private void applyImageHeaders(HttpURLConnection connection, String referer) {
        connection.setRequestProperty("User-Agent", IMAGE_USER_AGENT);
        connection.setRequestProperty("Accept", "image/webp,image/apng,image/*,*/*;q=0.8");
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
        connection.setRequestProperty("Sec-Fetch-Dest", "image");
        connection.setRequestProperty("Sec-Fetch-Mode", "no-cors");
        connection.setRequestProperty("Sec-Fetch-Site", "cross-site");
        if (!TextUtils.isEmpty(referer)) connection.setRequestProperty("Referer", referer);
    }

    private String refererForImage(String imageUrl) {
        return refererForImage(imageUrl, "");
    }

    private String refererForImage(String imageUrl, String pageReferer) {
        if (imageUrl != null && (imageUrl.contains(aikanConfig.domain) || imageUrl.contains("qrqrs.com"))) return aikanConfig.referer;
        if (imageUrl != null && imageUrl.contains(mhua5Config.domain)) return mhua5Config.referer;
        if (imageUrl != null && (imageUrl.contains(gmhConfig.domain) || imageUrl.contains("g-mh.online") || imageUrl.contains("6wm.top"))) return gmhConfig.referer;
        if (imageUrl != null && (imageUrl.contains(mkzhanConfig.domain) || imageUrl.contains("mkzcdn.com"))) return mkzhanConfig.referer;
        if (imageUrl != null && (imageUrl.contains(hiperdexConfig.domain) || imageUrl.contains("r2d2storage.com"))) return hiperdexConfig.referer;
        if (imageUrl != null && (imageUrl.contains(manhuaguiConfig.domain) || imageUrl.contains("mhgui.com") || imageUrl.contains("hamreus.com"))) {
            return TextUtils.isEmpty(pageReferer) ? manhuaguiConfig.referer : pageReferer;
        }
        if (imageUrl != null && (imageUrl.contains(hanman18Config.domain) || imageUrl.contains("manga18.club"))) return hanman18Config.referer;
        if (imageUrl != null && imageUrl.contains(d5d6Config.domain)) return d5d6Config.referer;
        if (imageUrl != null && (imageUrl.contains(manbenConfig.domain) || imageUrl.contains("cdndm5.com"))) {
            return TextUtils.isEmpty(pageReferer) ? manbenConfig.referer : pageReferer;
        }
        return baoziConfig.referer;
    }

    private String currentFilterLabel() {
        if (!"all".equals(selectedRegion) && !TextUtils.isEmpty(selectedRegion)) return selectedRegionLabel;
        if (!"all".equals(selectedState) && !TextUtils.isEmpty(selectedState)) return selectedStateLabel;
        return ALL_TAG;
    }

    private View dividerLine() {
        View d = new View(this);
        d.setBackgroundColor(UIHelpers.BORDER_SOFT);
        d.setLayoutParams(new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 1)));
        return d;
    }

    private void showFilterDrawer() {
        int screenWidth = getResources().getDisplayMetrics().widthPixels;
        int panelWidth = Math.min(screenWidth - UIHelpers.dp(this, 56), UIHelpers.dp(this, 320));

        final String origSourceId = selectedSourceId;
        final String origRegion = selectedRegion;
        final String origState = selectedState;
        final String origRegionLabel = selectedRegionLabel;
        final String origStateLabel = selectedStateLabel;
        final boolean[] confirmed = {false};

        FrameLayout overlay = new FrameLayout(this);
        View backdrop = new View(this);
        backdrop.setBackgroundColor(Color.argb(150, 0, 0, 0));
        overlay.addView(backdrop, UIHelpers.match());

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        android.graphics.drawable.GradientDrawable panelBg = new android.graphics.drawable.GradientDrawable();
        panelBg.setColor(UIHelpers.CARD);
        float r = UIHelpers.dp(this, 22);
        panelBg.setCornerRadii(new float[]{r, r, 0, 0, 0, 0, r, r});
        panel.setBackground(panelBg);
        panel.setPadding(UIHelpers.dp(this, 18), UIHelpers.dp(this, 14), UIHelpers.dp(this, 18), UIHelpers.dp(this, 16));
        overlay.addView(panel, new FrameLayout.LayoutParams(panelWidth, -1, Gravity.RIGHT));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(UIHelpers.text(this, "筛选", 18, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        TextView close = UIHelpers.text(this, "✕", 18, UIHelpers.TEXT2, Typeface.NORMAL);
        close.setPadding(UIHelpers.dp(this, 14), UIHelpers.dp(this, 6), UIHelpers.dp(this, 14), UIHelpers.dp(this, 6));
        close.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 18), UIHelpers.BORDER_SOFT));
        header.addView(close);
        panel.addView(header, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));

        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        TextView tabSource = UIHelpers.text(this, "站源", 14, UIHelpers.TEXT2, Typeface.NORMAL);
        TextView tabCategory = UIHelpers.text(this, "分类", 14, UIHelpers.TEXT2, Typeface.NORMAL);
        tabSource.setGravity(Gravity.CENTER);
        tabCategory.setGravity(Gravity.CENTER);
        tabSource.setPadding(0, UIHelpers.dp(this, 10), 0, UIHelpers.dp(this, 10));
        tabCategory.setPadding(0, UIHelpers.dp(this, 10), 0, UIHelpers.dp(this, 10));
        tabSource.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 12), UIHelpers.BORDER_SOFT));
        tabCategory.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 12), UIHelpers.BORDER_SOFT));
        tabs.addView(tabSource, UIHelpers.weight(1));
        tabs.addView(tabCategory, UIHelpers.weight(1));
        panel.addView(tabs, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));

        ScrollView contentScroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        contentScroll.addView(content, UIHelpers.matchWrap());
        panel.addView(contentScroll, new LinearLayout.LayoutParams(-1, 0, 1));

        Button confirm = UIHelpers.brandButton(this, "\u786e\u8ba4\u641c\u7d22");
        confirm.setTextSize(15);
        confirm.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        confirm.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 8), UIHelpers.dp(this, 16), UIHelpers.dp(this, 8));
        confirm.setMinHeight(UIHelpers.dp(this, 48));
        confirm.setMinimumHeight(UIHelpers.dp(this, 48));
        LinearLayout.LayoutParams confirmLp = new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 48));
        confirmLp.topMargin = UIHelpers.dp(this, 12);
        panel.addView(confirm, confirmLp);

        PopupWindow popup = new PopupWindow(overlay, -1, -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
            filterDrawerAction = null;
            if (!confirmed[0]) {
                selectedSourceId = origSourceId;
                selectedRegion = origRegion;
                selectedState = origState;
                selectedRegionLabel = origRegionLabel;
                selectedStateLabel = origStateLabel;
            }
        });
        close.setOnClickListener(v -> popup.dismiss());
        backdrop.setOnClickListener(v -> popup.dismiss());

        final int[] filterTab = {1};
        final Runnable[] fill = new Runnable[1];
        fill[0] = () -> {
            content.removeAllViews();
            boolean sourceTab = filterTab[0] == 0;
            tabSource.setTextColor(sourceTab ? UIHelpers.ACCENT : UIHelpers.TEXT2);
            tabCategory.setTextColor(!sourceTab ? UIHelpers.ACCENT : UIHelpers.TEXT2);
            tabSource.setTypeface(Typeface.create("sans-serif-medium", sourceTab ? Typeface.BOLD : Typeface.NORMAL));
            tabCategory.setTypeface(Typeface.create("sans-serif-medium", !sourceTab ? Typeface.BOLD : Typeface.NORMAL));
            if (sourceTab) {
                filterDrawerAction = null;
                for (String name : enabledSourceNames()) {
                    String sid = sourceIdForName(name);
                    boolean sel = sid.equals(selectedSourceId);
                    TextView row = UIHelpers.text(this, name, 15, sel ? UIHelpers.ACCENT : UIHelpers.TEXT, sel ? Typeface.BOLD : Typeface.NORMAL);
                    row.setPadding(0, UIHelpers.dp(this, 13), 0, UIHelpers.dp(this, 13));
                    row.setOnClickListener(v -> {
                        selectedSourceId = sid;
                        selectedRegion = "all";
                        selectedState = "all";
                        selectedRegionLabel = ALL_TAG;
                        selectedStateLabel = ALL_TAG;
                        sourceCategories.clear();
                        loadSourceCategories();
                        filterTab[0] = 1;
                        fill[0].run();
                    });
                    content.addView(row);
                    content.addView(dividerLine());
                }
            } else {
                filterDrawerAction = () -> fill[0].run();
                content.addView(searchTagGrid(searchTags()));
            }
        };
        tabSource.setOnClickListener(v -> { filterTab[0] = 0; fill[0].run(); });
        tabCategory.setOnClickListener(v -> { filterTab[0] = 1; fill[0].run(); });
        confirm.setOnClickListener(v -> {
            confirmed[0] = true;
            boolean sourceChanged = !selectedSourceId.equals(origSourceId);
            searchQuery = "";
            searchResults.clear();
            showTab(1);
            if (sourceChanged) loadSourceCategories();
            loadCategory();
            popup.dismiss();
        });

        activePopup = popup;
        popup.showAtLocation(root, Gravity.CENTER, 0, 0);
        fill[0].run();
        panel.setTranslationX(panelWidth);
        panel.animate().translationX(0).setDuration(220).start();
        backdrop.setAlpha(0f);
        backdrop.animate().alpha(1f).setDuration(220).start();
    }

    private TextView sourceDropdown() {
        String name = selectedSourceName();
        TextView view = UIHelpers.chip(this, "▾ " + name, true);
        view.setOnClickListener(v -> showSourceChooser());
        return view;
    }

    private void showSourceChooser() {
        List<String> names = enabledSourceNames();
        if (names.isEmpty()) {
            showToast("当前没有启用站源");
            return;
        }
        String[] items = names.toArray(new String[0]);
        AlertDialog listDialog = new AlertDialog.Builder(this)
                .setTitle("选择站源")
                .setItems(items, (dialog, which) -> {
                    selectedSourceId = sourceIdForName(items[which]);
                    selectedRegion = "all";
                    selectedState = "all";
                    selectedRegionLabel = ALL_TAG;
                    selectedStateLabel = ALL_TAG;
                    sourceCategories.clear();
                    searchResults.clear();
                    showTab(1);
                    loadSourceCategories();
                    loadDefaultCategory();
                })
                .create();
        listDialog.setOnShowListener(d -> {
            if (listDialog.getWindow() != null) {
                listDialog.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 16), Color.TRANSPARENT));
            }
            TextView titleView = (TextView) listDialog.findViewById(android.R.id.title);
            if (titleView != null) {
                titleView.setTextColor(UIHelpers.TEXT);
                titleView.setTextSize(17);
                titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            ListView listView = listDialog.getListView();
            if (listView != null) {
                listView.setDivider(new ColorDrawable(UIHelpers.BORDER));
                listView.setDividerHeight(1);
                android.widget.ArrayAdapter<String> adapter = new android.widget.ArrayAdapter<String>(this, android.R.layout.simple_list_item_1, items) {
                    @Override
                    public View getView(int position, View convertView, ViewGroup parent) {
                        TextView tv = (TextView) super.getView(position, convertView, parent);
                        tv.setTextColor(UIHelpers.TEXT);
                        tv.setTextSize(15);
                        tv.setPadding(UIHelpers.dp(MainActivity.this, 20), UIHelpers.dp(MainActivity.this, 14), UIHelpers.dp(MainActivity.this, 20), UIHelpers.dp(MainActivity.this, 14));
                        return tv;
                    }
                };
                listView.setAdapter(adapter);
            }
        });
        listDialog.show();
    }

    private List<String> enabledSourceNames() {
        List<String> names = new ArrayList<>();
        if (sourceEnabled) names.add(sourceClient.name());
        if (mhua5Enabled) names.add(mhua5Client.name());
        if (aikanEnabled) names.add(aikanClient.name());
        if (gmhEnabled) names.add(gmhClient.name());
        if (mkzhanEnabled) names.add(mkzhanClient.name());
        if (hiperdexEnabled) names.add(hiperdexClient.name());
        if (manhuaguiEnabled) names.add(manhuaguiClient.name());
        if (hanman18Enabled) names.add(hanman18Client.name());
        if (d5d6Enabled) names.add(d5d6Client.name());
        if (manbenEnabled) names.add(manbenClient.name());
        return names;
    }

    private String selectedSourceName() {
        if (sourceClient.id().equals(selectedSourceId)) return sourceClient.name();
        if (mhua5Client.id().equals(selectedSourceId)) return mhua5Client.name();
        if (aikanClient.id().equals(selectedSourceId)) return aikanClient.name();
        if (gmhClient.id().equals(selectedSourceId)) return gmhClient.name();
        if (mkzhanClient.id().equals(selectedSourceId)) return mkzhanClient.name();
        if (hiperdexClient.id().equals(selectedSourceId)) return hiperdexClient.name();
        if (manhuaguiClient.id().equals(selectedSourceId)) return manhuaguiClient.name();
        if (hanman18Client.id().equals(selectedSourceId)) return hanman18Client.name();
        if (d5d6Client.id().equals(selectedSourceId)) return d5d6Client.name();
        if (manbenClient.id().equals(selectedSourceId)) return manbenClient.name();
        for (ComicModels.Source item : customSources) {
            if (item.id.equals(selectedSourceId)) return item.name;
        }
        return "全部";
    }

    private String sourceIdForName(String name) {
        if (sourceClient.name().equals(name)) return sourceClient.id();
        if (mhua5Client.name().equals(name)) return mhua5Client.id();
        if (aikanClient.name().equals(name)) return aikanClient.id();
        if (gmhClient.name().equals(name)) return gmhClient.id();
        if (mkzhanClient.name().equals(name)) return mkzhanClient.id();
        if (hiperdexClient.name().equals(name)) return hiperdexClient.id();
        if (manhuaguiClient.name().equals(name)) return manhuaguiClient.id();
        if (hanman18Client.name().equals(name)) return hanman18Client.id();
        if (d5d6Client.name().equals(name)) return d5d6Client.id();
        if (manbenClient.name().equals(name)) return manbenClient.id();
        for (ComicModels.Source item : customSources) {
            if (item.name.equals(name)) return item.id;
        }
        return sourceClient.id();
    }

    private HorizontalScrollView searchTagRow(List<String> values, boolean regionRow) {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(UIHelpers.dp(this, 1), UIHelpers.dp(this, 2), UIHelpers.dp(this, 1), UIHelpers.dp(this, 2));
        for (String value : values) {
            boolean selected = regionRow ? codeForRegion(value).equals(selectedRegion) : codeForState(value).equals(selectedState);
            TextView chip = UIHelpers.chip(this, value, selected);
            chip.setOnClickListener(v -> {
                if (regionRow) {
                    selectedRegion = codeForRegion(value);
                    selectedRegionLabel = value;
                } else {
                    selectedState = codeForState(value);
                    selectedStateLabel = value;
                }
                if (filterDrawerAction != null) filterDrawerAction.run();
            });
            row.addView(chip, UIHelpers.marginRight(-2, UIHelpers.dp(this, 14)));
        }
        scroll.addView(row, UIHelpers.wrap());
        return scroll;
    }

    private LinearLayout searchTagColumn(List<String> values, boolean regionRow) {
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        if (values == null || values.isEmpty()) return column;
        final int columns = 3;
        final int cellHeight = UIHelpers.dp(this, 34);
        final int cellGap = UIHelpers.dp(this, 8);
        LinearLayout row = null;
        for (int i = 0; i < values.size(); i++) {
            if (i % columns == 0) {
                row = new LinearLayout(this);
                row.setOrientation(LinearLayout.HORIZONTAL);
                column.addView(row, UIHelpers.marginBottom(-1, cellGap));
            }
            String value = values.get(i);
            boolean selected = regionRow ? codeForRegion(value).equals(selectedRegion) : codeForState(value).equals(selectedState);
            TextView chip = filterGridChip(value, selected);
            chip.setSingleLine(true);
            chip.setEllipsize(TextUtils.TruncateAt.END);
            chip.setGravity(Gravity.CENTER);
            chip.setOnClickListener(v -> {
                if (regionRow) {
                    selectedRegion = codeForRegion(value);
                    selectedRegionLabel = value;
                } else {
                    selectedState = codeForState(value);
                    selectedStateLabel = value;
                }
                if (filterDrawerAction != null) filterDrawerAction.run();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, cellHeight, 1);
            if (i % columns != columns - 1) lp.rightMargin = cellGap;
            row.addView(chip, lp);
        }
        int remainder = values.size() % columns;
        if (remainder != 0 && column.getChildCount() > 0) {
            LinearLayout lastRow = (LinearLayout) column.getChildAt(column.getChildCount() - 1);
            for (int i = remainder; i < columns; i++) {
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, cellHeight, 1);
                if (i != columns - 1) lp.rightMargin = cellGap;
                lastRow.addView(new View(this), lp);
            }
        }
        return column;
    }

    private TextView filterGridChip(String value, boolean selected) {
        TextView chip = UIHelpers.text(this, value, 12, selected ? UIHelpers.ON_ACCENT : UIHelpers.TEXT3, Typeface.NORMAL);
        chip.setIncludeFontPadding(false);
        chip.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        chip.setPadding(UIHelpers.dp(this, 6), 0, UIHelpers.dp(this, 6), 0);
        chip.setBackground(UIHelpers.round(
                selected ? UIHelpers.ACCENT : UIHelpers.SURFACE,
                UIHelpers.dp(this, 10),
                selected ? Color.TRANSPARENT : UIHelpers.BORDER_SOFT));
        return chip;
    }
    private LinearLayout searchTagGrid(List<String> values) {
        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        if (mkzhanClient.id().equals(selectedSourceId)) {
            grid.addView(searchTagRow(mkzhanFilterLabels(), false));
            return grid;
        }
        if (hanman18Client.id().equals(selectedSourceId)) {
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "受欢迎的"), true));
            return grid;
        }
        if (manhuaguiClient.id().equals(selectedSourceId)) {
            List<String> categories = values == null || values.isEmpty() ? Arrays.asList(ALL_TAG) : values;
            grid.addView(searchTagColumn(categories, true), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "\u8fde\u8f7d", "\u5b8c\u7ed3"), false));
            return grid;
        }
        if (hiperdexClient.id().equals(selectedSourceId)) {
            List<String> categories = values == null || values.isEmpty() ? Arrays.asList(ALL_TAG) : values;
            grid.addView(searchTagColumn(categories, true));
            return grid;
        }
        if (aikanClient.id().equals(selectedSourceId)) {
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "连载中", "已完结"), false));
            return grid;
        }
        if (d5d6Client.id().equals(selectedSourceId)) {
            List<String> categories = values == null || values.isEmpty() ? Arrays.asList(ALL_TAG) : values;
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "\u8fde\u8f7d\u4e2d", "\u5df2\u5b8c\u6210"), false), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
            grid.addView(searchTagColumn(categories, true));
            return grid;
        }
        if (manbenClient.id().equals(selectedSourceId)) {
            List<String> categories = values == null || values.isEmpty() ? Arrays.asList(ALL_TAG) : values;
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "\u8fde\u8f7d\u4e2d", "\u5df2\u5b8c\u6210"), false), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
            grid.addView(searchTagColumn(categories, true));
            return grid;
        }
        if (gmhClient.id().equals(selectedSourceId)) {
            List<String> categories = values == null || values.isEmpty() ? Arrays.asList(ALL_TAG) : values;
            grid.addView(searchTagColumn(categories, true));
            return grid;
        }
        grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "国漫", "日本", "韩国", "欧美"), true), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 6)));
        grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "连载中", "已完结"), false));
        return grid;
    }

    private List<String> mkzhanFilterLabels() {
        return Arrays.asList(ALL_TAG, "连载", "完结", "免费", "付费", "VIP");
    }

    private String codeForRegion(String value) {
        if ("韩漫".equals(value)) return "kr";
        if ("热门".equals(value)) return "hots";
        if ("日漫".equals(value)) return "jp";
        if ("国漫".equals(value)) return "cn";
        if ("日本".equals(value)) return "jp";
        if ("韩国".equals(value)) return "kr";
        if ("欧美".equals(value)) return "en";
        if ("内地".equals(value)) return "cn";
        if ("港台".equals(value)) return "hk";
        if ("其它".equals(value)) return "other";
        if ("Manhwa".equals(value)) return "manhwa";
        if ("Webtoon".equals(value)) return "webtoon";
        if ("Romance".equals(value)) return "romance";
        if ("Drama".equals(value)) return "drama";
        if ("受欢迎的".equals(value)) return "popular";
        if ("大陆".equals(value)) return "cn";
        if ("日本".equals(value)) return "jp";
        if ("韩国".equals(value)) return "kr";
        if ("欧美".equals(value)) return "en";
        if (d5d6Client != null && d5d6Client.id().equals(selectedSourceId) && !ALL_TAG.equals(value)) return value;
        if (manbenClient != null && manbenClient.id().equals(selectedSourceId) && !ALL_TAG.equals(value)) return value;
        return "all";
    }

    private String codeForState(String value) {
        if ("\u8fde\u8f7d".equals(value) || "\u8fde\u8f7d\u4e2d".equals(value)) return "serial";
        if ("\u5b8c\u7ed3".equals(value) || "\u5df2\u5b8c\u7ed3".equals(value) || "\u5df2\u5b8c\u6210".equals(value)) return "pub";
        if ("连载".equals(value)) return "serial";
        if ("完结".equals(value)) return "pub";
        if ("免费".equals(value)) return "free";
        if ("付费".equals(value)) return "fee";
        if ("VIP".equals(value)) return "vip";
        if ("连载中".equals(value)) return "serial";
        if ("已完结".equals(value)) return "pub";
        if ("连载中".equals(value)) return "serial";
        if ("已完成".equals(value)) return "pub";
        if ("\u5df2\u5b8c\u6210".equals(value)) return "pub";
        return "all";
    }

    private List<String> searchTags() {
        List<String> values = new ArrayList<>();
        values.add(ALL_TAG);
        if (!sourceCategories.isEmpty()) {
            for (String category : sourceCategories) {
                if (!TextUtils.isEmpty(category) && !values.contains(category)) values.add(category);
            }
        } else {
            for (ComicModels.ComicSummary item : searchResults) {
                for (String tag : item.tags) {
                    if (!TextUtils.isEmpty(tag) && !values.contains(tag) && values.size() < 12) values.add(tag);
                }
            }
        }
        return values;
    }

    private LinearLayout makeBottomNav() {
        LinearLayout wrap = new LinearLayout(this);
        // 圆角顶背景（仅上方两角圆角），无 elevation 无描边
        android.graphics.drawable.GradientDrawable navBg = new android.graphics.drawable.GradientDrawable();
        navBg.setColor(UIHelpers.CARD);
        float r = UIHelpers.dp(this, 22);
        navBg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        wrap.setBackground(navBg);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(0, UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 6));
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        tabs.setGravity(Gravity.CENTER_VERTICAL);
        wrap.addView(tabs, new LinearLayout.LayoutParams(-1, -1));
        int[] iconRes = { R.drawable.ic_favorite, R.drawable.ic_search_nav, R.drawable.ic_source, R.drawable.ic_profile };
        int[] iconResSelected = { R.drawable.ic_favorite_fill, R.drawable.ic_search_nav, R.drawable.ic_source, R.drawable.ic_profile };
        String[] labels = {"收藏", "搜索", "站源", "我的"};
        for (int i = 0; i < labels.length; i++) {
            final int index = i;
            boolean selected = i == currentTab;
            LinearLayout tab = new LinearLayout(this);
            tab.setOrientation(LinearLayout.VERTICAL);
            tab.setGravity(Gravity.CENTER);
            ImageView icon = new ImageView(this);
            icon.setImageResource(selected ? iconResSelected[i] : iconRes[i]);
            icon.setImageTintList(android.content.res.ColorStateList.valueOf(selected ? UIHelpers.ACCENT : UIHelpers.TEXT3));
            icon.setLayoutParams(new LinearLayout.LayoutParams(UIHelpers.dp(this, 20), UIHelpers.dp(this, 20)));
            TextView label = UIHelpers.text(this, labels[i], 10, selected ? UIHelpers.ACCENT : UIHelpers.TEXT3, Typeface.NORMAL);
            label.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            label.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams labelLp = new LinearLayout.LayoutParams(-2, -2);
            labelLp.topMargin = UIHelpers.dp(this, 4);
            tab.addView(icon);
            tab.addView(label, labelLp);
            tab.setOnClickListener(v -> {
                if (index != currentTab) clearSearchInputs();
                showTab(index);
            });
            tabs.addView(tab, UIHelpers.weight(1));
        }
        return wrap;
    }

    private TextView sectionTitle(String value) {
        return UIHelpers.text(this, value, 16, UIHelpers.TEXT, Typeface.BOLD);
    }

    private TextView sectionText(String value) {
        TextView text = UIHelpers.text(this, value, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        text.setPadding(0, UIHelpers.dp(this, 12), 0, UIHelpers.dp(this, 4));
        return text;
    }

    private void addTitle(LinearLayout page, String title, String badge) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(UIHelpers.text(this, title, 24, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        if (badge != null) row.addView(UIHelpers.chip(this, badge, true));
        if (currentTab == 2) {
            ImageView menu = UIHelpers.vectorIconButton(this, R.drawable.ic_menu, UIHelpers.TEXT, 8);
            menu.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 18), UIHelpers.BORDER));
            menu.setOnClickListener(v -> showSourceMenu(menu));
            row.addView(menu, new LinearLayout.LayoutParams(UIHelpers.dp(this, 42), UIHelpers.dp(this, 38)));
        }
        page.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 14)));
    }

    private TextView menuItem(String title, String end, Runnable action) {
        TextView item = UIHelpers.menuItem(this, title, end);
        item.setOnClickListener(v -> action.run());
        return item;
    }

    private void showSourceMenu(View anchor) {
        LinearLayout panel = UIHelpers.card(this);
        panel.setPadding(0, UIHelpers.dp(this, 6), 0, UIHelpers.dp(this, 6));
        PopupWindow popup = new PopupWindow(panel, UIHelpers.dp(this, 190), -2, true);
        popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        popup.setOutsideTouchable(true);
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
        });
        panel.addView(menuItem("添加站源", "", () -> {
            popup.dismiss();
            showAddSourceDialog();
        }));
        panel.addView(UIHelpers.divider(this));
        panel.addView(menuItem("导出配置", "", () -> {
            popup.dismiss();
            exportSourceConfig();
        }));
        panel.addView(UIHelpers.divider(this));
        panel.addView(menuItem("导入配置", "", () -> {
            popup.dismiss();
            openImportSourceConfig();
        }));
        panel.addView(UIHelpers.divider(this));
        panel.addView(menuItem("检测可用性", "", () -> {
            popup.dismiss();
            healthCheck();
        }));
        activePopup = popup;
        popup.showAsDropDown(anchor, -UIHelpers.dp(this, 148), UIHelpers.dp(this, 6));
    }

    private View emptyState(int iconRes, String title, String desc, String action, Runnable onClick) {
        return UIHelpers.emptyState(this, iconRes, title, desc, action, onClick);
    }

    private View loadingState(String title, String desc) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
        box.setPadding(0, UIHelpers.dp(this, 8), 0, 0);
        box.setMinimumHeight(UIHelpers.dp(this, 330));

        com.facebook.shimmer.ShimmerFrameLayout shimmer = UIHelpers.shimmerFrame(this);
        LinearLayout skeletonBox = new LinearLayout(this);
        skeletonBox.setOrientation(LinearLayout.VERTICAL);
        for (int i = 0; i < 5; i++) {
            View skel = UIHelpers.skeletonCard(this, "list");
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.topMargin = i == 0 ? 0 : UIHelpers.dp(this, 12);
            skeletonBox.addView(skel, lp);
        }
        shimmer.addView(skeletonBox);
        box.addView(shimmer, new LinearLayout.LayoutParams(-1, -2));

        TextView titleView = UIHelpers.text(this, title, 17, UIHelpers.TEXT2, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        titleView.setVisibility(View.GONE);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(-1, -2);
        titleParams.setMargins(0, UIHelpers.dp(this, 16), 0, 0);
        box.addView(titleView, titleParams);

        TextView description = UIHelpers.text(this, desc, 13, UIHelpers.TEXT3, Typeface.NORMAL);
        description.setGravity(Gravity.CENTER);
        description.setMaxLines(2);
        description.setEllipsize(TextUtils.TruncateAt.END);
        description.setVisibility(View.GONE);
        LinearLayout.LayoutParams descParams = new LinearLayout.LayoutParams(-1, -2);
        descParams.setMargins(0, UIHelpers.dp(this, 8), 0, 0);
        box.addView(description, descParams);
        return box;
    }

    private View loadingMoreView() {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER);
        com.facebook.shimmer.ShimmerFrameLayout shimmer = UIHelpers.shimmerFrame(this);
        View skel = UIHelpers.skeletonCard(this, "list");
        LinearLayout.LayoutParams skelLp = new LinearLayout.LayoutParams(UIHelpers.dp(this, 200), UIHelpers.dp(this, 50));
        shimmer.addView(skel, skelLp);
        row.addView(shimmer);
        return row;
    }

    private void tuneScroll(ScrollView scroll) {
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroll.setSmoothScrollingEnabled(true);
        scroll.setFadingEdgeLength(0);
    }

    private int showPageLoading(String title, String desc, Runnable backAction) {
        pageLoading = true;
        pageLoadingBackAction = backAction;
        int generation = ++pageLoadingGeneration;
        root.removeAllViews();
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(UIHelpers.BG);
        frame.addView(loadingState(title == null ? "正在加载" : title.replace("...", ""), desc), UIHelpers.frame(-1, -1, Gravity.CENTER, 0, 0, 0, 0));
        root.addView(frame, UIHelpers.match());
        return generation;
    }

    private boolean isCurrentLoading(int generation) {
        return pageLoading && pageLoadingGeneration == generation;
    }

    private View centerState(String message) {
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(UIHelpers.BG);
        String title = message == null ? "正在加载" : message.replace("...", "").replace("…", "");
        frame.addView(loadingState(title, "请稍等，内容马上就绪。"), UIHelpers.frame(-1, -1, Gravity.CENTER, 0, 0, 0, 0));
        return frame;
    }

    private void showError(String title, Exception error) {
        showError(title, error, () -> showTab(currentTab));
    }

    private void showError(String title, Exception error, Runnable backAction) {
        appendErrorLog(title, error);
        pageLoading = false;
        root.removeAllViews();
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(UIHelpers.dp(this, 20), 0, UIHelpers.dp(this, 20), 0);
        box.setBackgroundColor(UIHelpers.BG);
        box.addView(UIHelpers.text(this, title, 18, UIHelpers.TEXT, Typeface.BOLD));
        TextView msg = UIHelpers.text(this, error == null ? "未知错误" : clean(error.getMessage(), error.getClass().getSimpleName()), 13, UIHelpers.TEXT2, Typeface.NORMAL);
        msg.setGravity(Gravity.CENTER);
        box.addView(msg, UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));
        Button back = UIHelpers.secondaryButton(this, "返回");
        back.setOnClickListener(v -> {
            if (backAction != null) backAction.run(); else showTab(currentTab);
        });
        box.addView(back, UIHelpers.marginTop(UIHelpers.dp(this, 110), UIHelpers.dp(this, 16), -2, UIHelpers.dp(this, 42)));
        root.addView(box, UIHelpers.match());
    }

    private List<ComicModels.ComicSummary> filterResults() {
        return new ArrayList<>(searchResults);
    }

    private List<String> filterFavorites() {
        List<String> visible = new ArrayList<>();
        String query = favoriteQuery.trim().toLowerCase(java.util.Locale.ROOT);
        for (String id : new ArrayList<>(favorites)) {
            ComicModels.ComicDetail detail = details.get(id);
            ComicModels.ComicSummary summary = summaries.get(id);
            String title = detail != null ? detail.summary.title : summary != null ? summary.title : id;
            String latest = detail != null ? detail.latestChapter : summary != null ? summary.subtitle : "";
            String haystack = (title + " " + latest + " " + id).toLowerCase(java.util.Locale.ROOT);
            if (query.isEmpty() || haystack.contains(query)) visible.add(id);
        }
        Collections.sort(visible, (left, right) -> {
            long leftFavoriteTime = favoriteAt.containsKey(left) ? favoriteAt.get(left) : 0L;
            long rightFavoriteTime = favoriteAt.containsKey(right) ? favoriteAt.get(right) : 0L;
            long leftReadTime = lastViewedAt.containsKey(left) ? lastViewedAt.get(left) : 0L;
            long rightReadTime = lastViewedAt.containsKey(right) ? lastViewedAt.get(right) : 0L;
            long leftTime = Math.max(leftFavoriteTime, leftReadTime);
            long rightTime = Math.max(rightFavoriteTime, rightReadTime);
            if (leftTime != rightTime) return Long.compare(rightTime, leftTime);
            return Integer.compare(favorites.indexOf(left), favorites.indexOf(right));
        });
        return visible;
    }

    private int[] colorSeed(String value) {
        int hash = Math.abs(value == null ? 1 : value.hashCode());
        int r1 = 120 + hash % 80;
        int g1 = 90 + (hash / 7) % 90;
        int b1 = 70 + (hash / 13) % 80;
        return new int[]{r1, g1, b1, Math.max(40, r1 - 70), Math.max(35, g1 - 55), Math.max(35, b1 - 45)};
    }

    private String clean(String value, String fallback) {
        return TextUtils.isEmpty(value) ? fallback : value;
    }

    private int savedChapter(String id) {
        Integer value = progress.get(id);
        return value == null ? 0 : value;
    }

    private String readerPositionKey(String comicId, ComicModels.Chapter chapter) {
        String chapterId = TextUtils.isEmpty(chapter.chapterId) ? chapter.url : chapter.chapterId;
        return comicId + "\u001f" + chapterId;
    }

    private void saveReaderPosition(ListView list, String positionKey) {
        int count = list.getCount();
        View firstChild = list.getChildAt(0);
        if (count <= 0 || firstChild == null || firstChild.getHeight() <= 0) return;
        int firstVisible = list.getFirstVisiblePosition();
        double offset = Math.max(0d, Math.min(1d, -firstChild.getTop() / (double) firstChild.getHeight()));
        int childCount = list.getChildCount();
        View lastChild = childCount > 0 ? list.getChildAt(childCount - 1) : null;
        int position;
        if (list.getLastVisiblePosition() == count - 1 && lastChild != null
                && lastChild.getBottom() <= list.getHeight() - list.getPaddingBottom()) {
            position = READER_POSITION_SCALE;
        } else {
            position = (int) Math.round((firstVisible + offset) * READER_POSITION_SCALE / count);
        }
        readerPositions.put(positionKey, Math.max(0, Math.min(READER_POSITION_SCALE, position)));
        main.removeCallbacks(persistReaderPositionRunnable);
        main.postDelayed(persistReaderPositionRunnable, READER_POSITION_SAVE_DELAY_MS);
    }

    private void restoreReaderPosition(ListView list, int savedPosition) {
        int count = list.getCount();
        if (count <= 0 || savedPosition <= 0) return;
        if (savedPosition == READER_POSITION_SCALE) {
            list.setSelection(count - 1);
            list.post(() -> alignReaderBottom(list));
            return;
        }
        int clamped = Math.max(0, Math.min(READER_POSITION_SCALE, savedPosition));
        double row = clamped * (double) count / READER_POSITION_SCALE;
        int index = Math.max(0, Math.min(count - 1, (int) Math.floor(row)));
        int rowHeight = Math.max(1, readerContentWidth() * 4 / 3);
        int top = -(int) Math.round((row - Math.floor(row)) * rowHeight);
        list.setSelectionFromTop(index, top);
    }

    private void alignReaderBottom(ListView list) {
        int last = list.getCount() - 1;
        if (last < 0) return;
        if (list.getLastVisiblePosition() != last) {
            list.setSelection(last);
            return;
        }
        View lastChild = list.getChildAt(list.getChildCount() - 1);
        if (lastChild == null || lastChild.getHeight() <= 0) return;
        int childHeight = lastChild.getHeight();
        int listHeight = Math.max(list.getPaddingTop(), list.getHeight() - list.getPaddingBottom());
        int top = listHeight - childHeight;
        if (lastChild.getTop() != top) list.setSelectionFromTop(last, listHeight - childHeight);
    }

    private void removeReaderPositions(String comicId) {
        String prefix = comicId + "\u001f";
        for (String key : new ArrayList<>(readerPositions.keySet())) {
            if (key.startsWith(prefix)) readerPositions.remove(key);
        }
    }

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private void showInfo(String title, String message) {
        styledDialog(title, message, "知道了", null, null, null);
    }

    /** 统一 AlertDialog 样式：背景用 CARD，标题 INK_1，正文 INK_2，确定按钮 ACCENT，取消按钮 TEXT3 */
    private AlertDialog styledDialog(String title, String message, String positiveText, Runnable positiveAction, String negativeText, Runnable negativeAction) {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        if (title != null) builder.setTitle(title);
        if (message != null) builder.setMessage(message);
        if (positiveText != null) builder.setPositiveButton(positiveText, (d, w) -> { if (positiveAction != null) positiveAction.run(); });
        if (negativeText != null) builder.setNegativeButton(negativeText, (d, w) -> { if (negativeAction != null) negativeAction.run(); });
        AlertDialog dialog = builder.create();
        dialog.setOnShowListener(d -> {
            if (dialog.getWindow() != null) {
                dialog.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 16), Color.TRANSPARENT));
            }
            TextView titleView = (TextView) dialog.findViewById(android.R.id.title);
            if (titleView != null) {
                titleView.setTextColor(UIHelpers.TEXT);
                titleView.setTextSize(17);
                titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            TextView messageView = (TextView) dialog.findViewById(android.R.id.message);
            if (messageView != null) {
                messageView.setTextColor(UIHelpers.TEXT2);
                messageView.setTextSize(14);
            }
            android.widget.Button pos = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            if (pos != null) {
                pos.setTextColor(UIHelpers.ACCENT);
                pos.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            android.widget.Button neg = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (neg != null) {
                neg.setTextColor(UIHelpers.TEXT3);
                neg.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
        });
        dialog.show();
        return dialog;
    }

    private void showErrorLogs() {
        String logs = errorLogText();
        AlertDialog dialog = styledDialog(
            "错误日志",
            TextUtils.isEmpty(logs) ? "暂无错误日志。" : logs,
            "导出", () -> exportErrorLogs(),
            "清理", () -> clearErrorLogs());
        // 补充第三个"关闭"按钮
        dialog.setButton(AlertDialog.BUTTON_NEUTRAL, "关闭", (d, w) -> d.dismiss());
        android.widget.Button neu = dialog.getButton(AlertDialog.BUTTON_NEUTRAL);
        if (neu != null) neu.setTextColor(UIHelpers.TEXT3);
        TextView messageView = (TextView) dialog.findViewById(android.R.id.message);
        if (messageView != null) {
            messageView.setTextIsSelectable(true);
            messageView.setLongClickable(true);
        }
    }

    private String errorLogSummary() {
        String logs = errorLogText();
        if (TextUtils.isEmpty(logs)) return "无";
        return logs.split("\\n\\n").length + " 条";
    }

    private String errorLogText() {
        return getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(ERROR_LOGS_KEY, "");
    }

    private void appendErrorLog(String title, Exception error) {
        StringBuilder entry = new StringBuilder();
        entry.append(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA).format(new Date()));
        entry.append(" · ").append(clean(title, "错误"));
        entry.append("\n").append(error == null ? "未知错误" : error.getClass().getSimpleName() + ": " + clean(error.getMessage(), ""));
        if (error != null) {
            StringWriter writer = new StringWriter();
            error.printStackTrace(new PrintWriter(writer));
            entry.append("\n").append(writer);
        }
        String current = errorLogText();
        String logs = entry + (TextUtils.isEmpty(current) ? "" : "\n\n" + current);
        if (logs.length() > ERROR_LOG_MAX_CHARS) logs = logs.substring(0, ERROR_LOG_MAX_CHARS);
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(ERROR_LOGS_KEY, logs).apply();
    }

    private boolean isExpectedTaskCancellation(Exception error) {
        return Thread.currentThread().isInterrupted()
                || error instanceof InterruptedException
                || (error instanceof InterruptedIOException
                && "thread interrupted".equalsIgnoreCase(clean(error.getMessage(), "")));
    }

    private void postMainIfAlive(Runnable action) {
        main.post(() -> {
            if (activityDestroyed) return;
            action.run();
        });
    }

    private void clearErrorLogs() {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().remove(ERROR_LOGS_KEY).apply();
        showToast("错误日志已清理");
        showTab(3);
    }

    private void exportErrorLogs() {
        pendingLogText = errorLogText();
        if (TextUtils.isEmpty(pendingLogText)) {
            showToast("暂无错误日志");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("text/plain");
        intent.putExtra(Intent.EXTRA_TITLE, "xx-comic-error-logs.txt");
        try {
            startActivityForResult(intent, EXPORT_LOGS_REQUEST);
        } catch (Exception ignored) {
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_SUBJECT, "xx-comic-error-logs.txt");
            send.putExtra(Intent.EXTRA_TEXT, pendingLogText);
            startActivity(Intent.createChooser(send, "导出错误日志"));
        }
    }

    private void writeExportLogs(Uri uri) {
        miscIo.execute(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(uri)) {
                if (stream == null) throw new IOException("无法写入文件");
                stream.write(pendingLogText.getBytes("UTF-8"));
                stream.flush();
                postMainIfAlive(() -> showToast("错误日志已导出"));
            } catch (Exception error) {
                postMainIfAlive(() -> showInfo("导出失败", clean(error.getMessage(), "无法写入日志文件")));
            }
        });
    }

    private void showAddSourceDialog() {
        EditText input = new EditText(this);
        input.setHint("https://example.com");
        input.setHintTextColor(UIHelpers.TEXT3);
        input.setTextColor(UIHelpers.TEXT);
        input.setTextSize(14);
        input.setSingleLine(true);
        input.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 12));
        AlertDialog addDialog = new AlertDialog.Builder(this)
                .setTitle("添加自定义站源")
                .setView(input)
                .setPositiveButton("添加", (dialog, which) -> {
                    String url = input.getText().toString().trim();
                    if (!url.isEmpty()) {
                        customSources.add(new ComicModels.Source("custom_" + System.currentTimeMillis(), url, "", url, false, true));
                        saveLocalState();
                        showTab(2);
                    }
                })
                .setNegativeButton("取消", null)
                .create();
        addDialog.setOnShowListener(d -> {
            if (addDialog.getWindow() != null) {
                addDialog.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 16), Color.TRANSPARENT));
            }
            TextView titleView = (TextView) addDialog.findViewById(android.R.id.title);
            if (titleView != null) {
                titleView.setTextColor(UIHelpers.TEXT);
                titleView.setTextSize(17);
                titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            android.widget.Button pos = addDialog.getButton(AlertDialog.BUTTON_POSITIVE);
            if (pos != null) {
                pos.setTextColor(UIHelpers.ACCENT);
                pos.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            android.widget.Button neg = addDialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (neg != null) {
                neg.setTextColor(UIHelpers.TEXT3);
                neg.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
        });
        addDialog.show();
    }

    private void exportSourceConfig() {
        try {
            pendingExportJson = sourceConfigJson().toString(2);
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("application/json");
            intent.putExtra(Intent.EXTRA_TITLE, "xx-comic-sources.json");
            try {
                startActivityForResult(intent, EXPORT_SOURCES_REQUEST);
            } catch (Exception ignored) {
                Intent send = new Intent(Intent.ACTION_SEND);
                send.setType("application/json");
                send.putExtra(Intent.EXTRA_SUBJECT, "xx-comic-sources.json");
                send.putExtra(Intent.EXTRA_TEXT, pendingExportJson);
                startActivity(Intent.createChooser(send, "导出站源配置"));
            }
        } catch (JSONException error) {
            showToast("导出失败");
        }
    }

    private void writeExportSourceConfig(Uri uri) {
        miscIo.execute(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(uri)) {
                if (stream == null) throw new IOException("无法写入文件");
                stream.write(pendingExportJson.getBytes("UTF-8"));
                stream.flush();
                postMainIfAlive(() -> showToast("站源配置已导出"));
            } catch (Exception error) {
                postMainIfAlive(() -> showInfo("导出失败", clean(error.getMessage(), "无法写入配置文件")));
            }
        });
    }

    private void openImportSourceConfig() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, IMPORT_SOURCES_REQUEST);
    }

    private void importSourceConfig(Uri uri) {
        miscIo.execute(() -> {
            try (InputStream stream = getContentResolver().openInputStream(uri)) {
                String json = new String(readAllBytes(stream), "UTF-8");
                applySourceConfigJson(new JSONObject(json));
                saveLocalState();
                postMainIfAlive(() -> {
                    selectedRegion = "all";
                    selectedState = "all";
                    sourceCategories.clear();
                    searchResults.clear();
                    showToast("站源配置已导入");
                    showTab(2);
                    loadSourceCategories();
                    loadDefaultCategory();
                });
            } catch (Exception error) {
                postMainIfAlive(() -> showInfo("导入失败", clean(error.getMessage(), "配置文件格式不正确")));
            }
        });
    }

    private JSONObject sourceConfigJson() throws JSONException {
        JSONObject root = new JSONObject();
        root.put("schema", "xx-comic.sources");
        root.put("version", 2);
        root.put("exportedAt", System.currentTimeMillis());
        JSONArray sources = new JSONArray();
        sources.put(baoziConfig.withEnabled(sourceEnabled).toJson());
        sources.put(mhua5Config.withEnabled(mhua5Enabled).toJson());
        sources.put(aikanConfig.withEnabled(aikanEnabled).toJson());
        sources.put(gmhConfig.withEnabled(gmhEnabled).toJson());
        sources.put(mkzhanConfig.withEnabled(mkzhanEnabled).toJson());
        sources.put(hiperdexConfig.withEnabled(hiperdexEnabled).toJson());
        sources.put(manhuaguiConfig.withEnabled(manhuaguiEnabled).toJson());
        sources.put(hanman18Config.withEnabled(hanman18Enabled).toJson());
        sources.put(d5d6Config.withEnabled(d5d6Enabled).toJson());
        sources.put(manbenConfig.withEnabled(manbenEnabled).toJson());
        root.put("sources", sources);
        JSONArray custom = new JSONArray();
        for (ComicModels.Source item : customSources) {
            custom.put(sourceConfigItem(item.id, item.name, item.domain, item.url, false, item.enabled));
        }
        root.put("custom", custom);
        return root;
    }

    private JSONObject sourceConfigItem(String id, String name, String domain, String url, boolean builtin, boolean enabled) throws JSONException {
        JSONObject object = new JSONObject();
        object.put("id", id);
        object.put("name", name);
        object.put("domain", domain);
        object.put("url", url);
        object.put("builtin", builtin);
        object.put("enabled", enabled);
        return object;
    }

    private void applySourceConfigJson(JSONObject root) throws JSONException {
        if (!"xx-comic.sources".equals(root.optString("schema"))) throw new JSONException("不是 XX Comic 站源配置");
        JSONArray sources = root.optJSONArray("sources");
        if (sources != null) {
            for (int i = 0; i < sources.length(); i++) {
                JSONObject item = sources.getJSONObject(i);
                String id = item.optString("id");
                if (baoziConfig.id.equals(id)) {
                    baoziConfig = SourceConfig.fromJson(item, SourceConfig.baozi(true));
                    sourceEnabled = baoziConfig.enabled;
                } else if (mhua5Config.id.equals(id)) {
                    mhua5Config = SourceConfig.fromJson(item, SourceConfig.mhua5(true));
                    mhua5Enabled = mhua5Config.enabled;
                } else if (aikanConfig.id.equals(id)) {
                    aikanConfig = SourceConfig.fromJson(item, SourceConfig.aikan(true));
                    aikanEnabled = aikanConfig.enabled;
                } else if (gmhConfig.id.equals(id)) {
                    gmhConfig = SourceConfig.fromJson(item, SourceConfig.gmh(true));
                    gmhEnabled = gmhConfig.enabled;
                } else if (mkzhanConfig.id.equals(id)) {
                    mkzhanConfig = SourceConfig.fromJson(item, SourceConfig.mkzhan(true));
                    mkzhanConfig = normalizeMkzhanConfig(mkzhanConfig);
                    mkzhanEnabled = mkzhanConfig.enabled;
                } else if (hiperdexConfig.id.equals(id)) {
                    hiperdexConfig = SourceConfig.fromJson(item, SourceConfig.hiperdex(true));
                    hiperdexEnabled = hiperdexConfig.enabled;
                } else if (manhuaguiConfig.id.equals(id)) {
                    manhuaguiConfig = SourceConfig.fromJson(item, SourceConfig.manhuagui(true));
                    manhuaguiEnabled = manhuaguiConfig.enabled;
                } else if (hanman18Config.id.equals(id)) {
                    hanman18Config = SourceConfig.fromJson(item, SourceConfig.hanman18(true));
                    hanman18Enabled = hanman18Config.enabled;
                } else if (d5d6Config.id.equals(id)) {
                    d5d6Config = SourceConfig.fromJson(item, SourceConfig.d5d6(true));
                    d5d6Enabled = d5d6Config.enabled;
                } else if (manbenConfig.id.equals(id)) {
                    manbenConfig = SourceConfig.fromJson(item, SourceConfig.manben(true));
                    manbenEnabled = manbenConfig.enabled;
                }
            }
        }
        JSONArray builtins = root.optJSONArray("builtins");
        if (builtins != null) {
            for (int i = 0; i < builtins.length(); i++) {
                JSONObject item = builtins.getJSONObject(i);
                String id = item.optString("id");
                if (baoziConfig.id.equals(id)) sourceEnabled = item.optBoolean("enabled", true);
                if (mhua5Config.id.equals(id)) mhua5Enabled = item.optBoolean("enabled", true);
                if (aikanConfig.id.equals(id)) aikanEnabled = item.optBoolean("enabled", true);
                if (gmhConfig.id.equals(id)) gmhEnabled = item.optBoolean("enabled", true);
                if (mkzhanConfig.id.equals(id)) mkzhanEnabled = item.optBoolean("enabled", true);
                if (hiperdexConfig.id.equals(id)) hiperdexEnabled = item.optBoolean("enabled", true);
                if (manhuaguiConfig.id.equals(id)) manhuaguiEnabled = item.optBoolean("enabled", true);
                if (hanman18Config.id.equals(id)) hanman18Enabled = item.optBoolean("enabled", true);
                if (d5d6Config.id.equals(id)) d5d6Enabled = item.optBoolean("enabled", true);
                if (manbenConfig.id.equals(id)) manbenEnabled = item.optBoolean("enabled", true);
            }
        }
        rebuildSourceClients();
        customSources.clear();
        JSONArray custom = root.optJSONArray("custom");
        if (custom != null) {
            for (int i = 0; i < custom.length(); i++) {
                JSONObject item = custom.getJSONObject(i);
                String id = clean(item.optString("id"), "custom_" + System.currentTimeMillis() + "_" + i);
                String name = clean(item.optString("name"), item.optString("url"));
                String domain = item.optString("domain");
                String url = item.optString("url");
                if (!TextUtils.isEmpty(url)) {
                    customSources.add(new ComicModels.Source(id, name, domain, url, false, item.optBoolean("enabled", true)));
                }
            }
        }
        if (selectedSource() == null) {
            sourceEnabled = true;
            selectedSourceId = sourceClient.id();
        }
    }

    private void healthCheck() {
        miscIo.execute(() -> {
            List<String> rows = new ArrayList<>();
            for (ComicSource client : enabledBuiltinSources()) {
                boolean ok = client.healthCheck();
                rows.add(client.name() + (ok ? " 可用" : " 暂不可用"));
            }
            if (rows.isEmpty()) rows.add("当前没有启用站源");
            postMainIfAlive(() -> showInfo("站源检测", TextUtils.join("\n", rows)));
        });
    }

    private void rebuildSourceClients() {
        sourceClient = new BaoziComicSource(baoziConfig.withEnabled(sourceEnabled));
        mhua5Client = new Mhua5ComicSource(mhua5Config.withEnabled(mhua5Enabled));
        aikanClient = new AikanComicSource(aikanConfig.withEnabled(aikanEnabled));
        gmhClient = new GmhComicSource(gmhConfig.withEnabled(gmhEnabled));
        mkzhanClient = new MkzhanComicSource(mkzhanConfig.withEnabled(mkzhanEnabled));
        hiperdexClient = new HiperdexComicSource(hiperdexConfig.withEnabled(hiperdexEnabled));
        manhuaguiClient = new ManhuaguiComicSource(manhuaguiConfig.withEnabled(manhuaguiEnabled));
        hanman18Client = new Hanman18ComicSource(hanman18Config.withEnabled(hanman18Enabled));
        d5d6Client = new D5d6ComicSource(d5d6Config.withEnabled(d5d6Enabled));
        manbenClient = new ManbenComicSource(manbenConfig.withEnabled(manbenEnabled));
    }

    private String readHistoryText() {
        if (progress.isEmpty()) return "还没有阅读历史。";
        StringBuilder builder = new StringBuilder();
        for (Map.Entry<String, Integer> entry : progress.entrySet()) {
            ComicModels.ComicSummary summary = summaries.get(entry.getKey());
            if (builder.length() > 0) builder.append("\n");
            builder.append(summary == null ? entry.getKey() : summary.title).append(" 第").append(entry.getValue() + 1).append("章");
        }
        return builder.toString();
    }

    private void restoreLocalState() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        sourceEnabled = prefs.getBoolean("source.baozi.enabled", true);
        mhua5Enabled = prefs.getBoolean("source.mhua5.enabled", true);
        aikanEnabled = prefs.getBoolean("source.aikan.enabled", true);
        gmhEnabled = prefs.getBoolean("source.gmh.enabled", true);
        mkzhanEnabled = prefs.getBoolean("source.mkzhan.enabled", true);
        hiperdexEnabled = prefs.getBoolean("source.hiperdex.enabled", true);
        manhuaguiEnabled = prefs.getBoolean("source.manhuagui.enabled", true);
        hanman18Enabled = prefs.getBoolean("source.hanman18.enabled", true);
        d5d6Enabled = prefs.getBoolean("source.d5d6.enabled", true);
        manbenEnabled = prefs.getBoolean("source.manben.enabled", true);
        restoreSourceConfigs(prefs.getString("source.configs", ""));
        rebuildSourceClients();
        chapterDesc = prefs.getBoolean("chapter.desc", false);
        themeMode = prefs.getInt("theme.mode", 0);
        readerLeftHand = prefs.getBoolean("reader.left.hand", false);
        cacheSize = prefs.getString("cache.size", cacheSize);
        restoreStringList(globalSearchHistory, prefs.getString("global.search.history", ""));
        favorites.clear();
        String favs = prefs.getString("favorites", "");
        if (!TextUtils.isEmpty(favs)) favorites.addAll(Arrays.asList(favs.split(",")));
        progress.clear();
        String progressText = prefs.getString("progress", "");
        if (!TextUtils.isEmpty(progressText)) {
            for (String row : progressText.split(",")) {
                int sep = row.lastIndexOf(':');
                if (sep <= 0) continue;
                String comicId = row.substring(0, sep);
                String valueStr = row.substring(sep + 1);
                try {
                    progress.put(comicId, Integer.parseInt(valueStr));
                } catch (NumberFormatException ignored) {
                }
            }
        }
        readerPositions.clear();
        String readerPositionsText = prefs.getString("reader.positions", "");
        if (!TextUtils.isEmpty(readerPositionsText)) {
            try {
                JSONObject object = new JSONObject(readerPositionsText);
                JSONArray names = object.names();
                if (names != null) {
                    for (int i = 0; i < names.length(); i++) {
                        String key = names.optString(i);
                        if (!TextUtils.isEmpty(key)) readerPositions.put(key, object.optInt(key, 0));
                    }
                }
            } catch (JSONException ignored) {
            }
        }
        lastViewedAt.clear();
        String viewedText = prefs.getString("last.viewed", "");
        if (!TextUtils.isEmpty(viewedText)) {
            for (String row : viewedText.split(",")) {
                int sep = row.lastIndexOf(':');
                if (sep <= 0) continue;
                String comicId = row.substring(0, sep);
                String valueStr = row.substring(sep + 1);
                try {
                    lastViewedAt.put(comicId, Long.parseLong(valueStr));
                } catch (NumberFormatException ignored) {
                }
            }
        }
        favoriteAt.clear();
        String favoriteText = prefs.getString("favorite.at", "");
        if (!TextUtils.isEmpty(favoriteText)) {
            for (String row : favoriteText.split(",")) {
                int sep = row.lastIndexOf(':');
                if (sep <= 0) continue;
                String comicId = row.substring(0, sep);
                String valueStr = row.substring(sep + 1);
                try {
                    favoriteAt.put(comicId, Long.parseLong(valueStr));
                } catch (NumberFormatException ignored) {
                }
            }
        }
        restoreCustomSources(prefs.getString("custom.sources", ""));
        restoreComicCaches(prefs);
        updateCacheSize();
    }

    private void saveLocalState() {
        SharedPreferences.Editor editor = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        editor.putBoolean("source.baozi.enabled", sourceEnabled);
        editor.putBoolean("source.mhua5.enabled", mhua5Enabled);
        editor.putBoolean("source.aikan.enabled", aikanEnabled);
        editor.putBoolean("source.gmh.enabled", gmhEnabled);
        editor.putBoolean("source.mkzhan.enabled", mkzhanEnabled);
        editor.putBoolean("source.hiperdex.enabled", hiperdexEnabled);
        editor.putBoolean("source.manhuagui.enabled", manhuaguiEnabled);
        editor.putBoolean("source.hanman18.enabled", hanman18Enabled);
        editor.putBoolean("source.d5d6.enabled", d5d6Enabled);
        editor.putBoolean("source.manben.enabled", manbenEnabled);
        editor.putString("source.configs", encodeSourceConfigs());
        editor.putBoolean("chapter.desc", chapterDesc);
        editor.putInt("theme.mode", themeMode);
        editor.putBoolean("reader.left.hand", readerLeftHand);
        editor.putString("cache.size", cacheSize);
        editor.putString("favorites", TextUtils.join(",", favorites));
        editor.putString("global.search.history", TextUtils.join("\n", globalSearchHistory));
        List<String> rows = new ArrayList<>();
        for (Map.Entry<String, Integer> entry : progress.entrySet()) rows.add(entry.getKey() + ":" + entry.getValue());
        editor.putString("progress", TextUtils.join(",", rows));
        JSONObject readerPositionObject = new JSONObject();
        try {
            for (Map.Entry<String, Integer> entry : readerPositions.entrySet()) {
                readerPositionObject.put(entry.getKey(), entry.getValue());
            }
        } catch (JSONException ignored) {
        }
        editor.putString("reader.positions", readerPositionObject.toString());
        List<String> viewedRows = new ArrayList<>();
        for (Map.Entry<String, Long> entry : lastViewedAt.entrySet()) viewedRows.add(entry.getKey() + ":" + entry.getValue());
        editor.putString("last.viewed", TextUtils.join(",", viewedRows));
        List<String> favoriteRows = new ArrayList<>();
        for (Map.Entry<String, Long> entry : favoriteAt.entrySet()) favoriteRows.add(entry.getKey() + ":" + entry.getValue());
        editor.putString("favorite.at", TextUtils.join(",", favoriteRows));
        editor.putString("custom.sources", encodeCustomSources());
        editor.apply();
    }

    private void restoreStringList(List<String> target, String value) {
        target.clear();
        if (TextUtils.isEmpty(value)) return;
        for (String item : value.split("\\n")) {
            if (!TextUtils.isEmpty(item) && !target.contains(item)) target.add(item);
        }
    }

    private void restoreSourceConfigs(String value) {
        if (TextUtils.isEmpty(value)) {
            baoziConfig = SourceConfig.baozi(sourceEnabled);
            mhua5Config = SourceConfig.mhua5(mhua5Enabled);
            aikanConfig = SourceConfig.aikan(aikanEnabled);
            gmhConfig = SourceConfig.gmh(gmhEnabled);
            mkzhanConfig = SourceConfig.mkzhan(mkzhanEnabled);
            hiperdexConfig = SourceConfig.hiperdex(hiperdexEnabled);
            manhuaguiConfig = SourceConfig.manhuagui(manhuaguiEnabled);
            hanman18Config = SourceConfig.hanman18(hanman18Enabled);
            d5d6Config = SourceConfig.d5d6(d5d6Enabled);
            manbenConfig = SourceConfig.manben(manbenEnabled);
            return;
        }
        try {
            JSONArray array = new JSONArray(value);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.getJSONObject(i);
                String id = item.optString("id");
                if (SourceConfig.baozi(true).id.equals(id)) {
                    baoziConfig = SourceConfig.fromJson(item, SourceConfig.baozi(sourceEnabled));
                    sourceEnabled = baoziConfig.enabled;
                } else if (SourceConfig.mhua5(true).id.equals(id)) {
                    mhua5Config = SourceConfig.fromJson(item, SourceConfig.mhua5(mhua5Enabled));
                    mhua5Enabled = mhua5Config.enabled;
                } else if (SourceConfig.aikan(true).id.equals(id)) {
                    aikanConfig = SourceConfig.fromJson(item, SourceConfig.aikan(aikanEnabled));
                    aikanEnabled = aikanConfig.enabled;
                } else if (SourceConfig.gmh(true).id.equals(id)) {
                    gmhConfig = SourceConfig.fromJson(item, SourceConfig.gmh(gmhEnabled));
                    gmhEnabled = gmhConfig.enabled;
                } else if (SourceConfig.mkzhan(true).id.equals(id)) {
                    mkzhanConfig = SourceConfig.fromJson(item, SourceConfig.mkzhan(mkzhanEnabled));
                    mkzhanConfig = normalizeMkzhanConfig(mkzhanConfig);
                    mkzhanEnabled = mkzhanConfig.enabled;
                } else if (SourceConfig.hiperdex(true).id.equals(id)) {
                    hiperdexConfig = SourceConfig.fromJson(item, SourceConfig.hiperdex(hiperdexEnabled));
                    hiperdexEnabled = hiperdexConfig.enabled;
                } else if (SourceConfig.manhuagui(true).id.equals(id)) {
                    manhuaguiConfig = SourceConfig.fromJson(item, SourceConfig.manhuagui(manhuaguiEnabled));
                    manhuaguiEnabled = manhuaguiConfig.enabled;
                } else if (SourceConfig.hanman18(true).id.equals(id)) {
                    hanman18Config = SourceConfig.fromJson(item, SourceConfig.hanman18(hanman18Enabled));
                    hanman18Enabled = hanman18Config.enabled;
                } else if (SourceConfig.d5d6(true).id.equals(id)) {
                    d5d6Config = SourceConfig.fromJson(item, SourceConfig.d5d6(d5d6Enabled));
                    d5d6Enabled = d5d6Config.enabled;
                } else if (SourceConfig.manben(true).id.equals(id)) {
                    manbenConfig = SourceConfig.fromJson(item, SourceConfig.manben(manbenEnabled));
                    manbenEnabled = manbenConfig.enabled;
                }
            }
        } catch (JSONException ignored) {
            baoziConfig = SourceConfig.baozi(sourceEnabled);
            mhua5Config = SourceConfig.mhua5(mhua5Enabled);
            aikanConfig = SourceConfig.aikan(aikanEnabled);
            gmhConfig = SourceConfig.gmh(gmhEnabled);
            mkzhanConfig = SourceConfig.mkzhan(mkzhanEnabled);
            hiperdexConfig = SourceConfig.hiperdex(hiperdexEnabled);
            manhuaguiConfig = SourceConfig.manhuagui(manhuaguiEnabled);
            hanman18Config = SourceConfig.hanman18(hanman18Enabled);
            d5d6Config = SourceConfig.d5d6(d5d6Enabled);
            manbenConfig = SourceConfig.manben(manbenEnabled);
        }
    }

    private String encodeSourceConfigs() {
        try {
            JSONArray array = new JSONArray();
            array.put(baoziConfig.withEnabled(sourceEnabled).toJson());
            array.put(mhua5Config.withEnabled(mhua5Enabled).toJson());
            array.put(aikanConfig.withEnabled(aikanEnabled).toJson());
            array.put(gmhConfig.withEnabled(gmhEnabled).toJson());
            array.put(mkzhanConfig.withEnabled(mkzhanEnabled).toJson());
            array.put(hiperdexConfig.withEnabled(hiperdexEnabled).toJson());
            array.put(manhuaguiConfig.withEnabled(manhuaguiEnabled).toJson());
            array.put(hanman18Config.withEnabled(hanman18Enabled).toJson());
            array.put(d5d6Config.withEnabled(d5d6Enabled).toJson());
            array.put(manbenConfig.withEnabled(manbenEnabled).toJson());
            return array.toString();
        } catch (JSONException ignored) {
            return "[]";
        }
    }

    private SourceConfig normalizeMkzhanConfig(SourceConfig config) {
        if (config == null) return SourceConfig.mkzhan(mkzhanEnabled);
        if ("/manga{genrePath}{pagePath}".equals(config.route("category"))
                || "/manga{pagePath}".equals(config.route("latest"))
                || "/category{genrePath}{pagePath}".equals(config.route("category"))
                || "/category{pagePath}".equals(config.route("latest"))) {
            return SourceConfig.mkzhan(config.enabled);
        }
        return config;
    }

    private void restoreComicCaches(SharedPreferences prefs) {
        try {
            JSONArray summaryArray = new JSONArray(prefs.getString(SUMMARIES_CACHE_KEY, "[]"));
            for (int i = 0; i < summaryArray.length(); i++) {
                ComicModels.ComicSummary summary = summaryFromJson(summaryArray.getJSONObject(i));
                summaries.put(summary.comicId, summary);
            }
            JSONArray detailArray = new JSONArray(prefs.getString(DETAILS_CACHE_KEY, "[]"));
            for (int i = 0; i < detailArray.length(); i++) {
                ComicModels.ComicDetail detail = detailFromJson(detailArray.getJSONObject(i));
                details.put(detail.summary.comicId, detail);
                summaries.put(detail.summary.comicId, detail.summary);
            }
            JSONArray chapterArray = new JSONArray(prefs.getString(CHAPTERS_CACHE_KEY, "[]"));
            for (int i = 0; i < chapterArray.length(); i++) {
                ComicModels.ChapterPage page = chapterPageFromJson(chapterArray.getJSONObject(i));
                if (!isEmptyChapterPage(page)) chapters.put(page.chapterId, page);
            }
        } catch (JSONException ignored) {
        }
    }

    private boolean isEmptyChapterPage(ComicModels.ChapterPage page) {
        return page == null || page.imageUrls == null || page.imageUrls.isEmpty();
    }

    private void persistComicCachesAsync() {
        if (activityDestroyed || miscIo.isShutdown()) return;
        List<ComicModels.ComicSummary> summarySnapshot = new ArrayList<>(summaries.values());
        List<ComicModels.ComicDetail> detailSnapshot = new ArrayList<>(details.values());
        List<ComicModels.ChapterPage> chapterSnapshot = new ArrayList<>(chapters.values());
        miscIo.execute(() -> writeComicCacheSnapshots(summarySnapshot, detailSnapshot, chapterSnapshot));
    }

    private void writeComicCacheSnapshots(List<ComicModels.ComicSummary> summarySnapshot,
                                          List<ComicModels.ComicDetail> detailSnapshot,
                                          List<ComicModels.ChapterPage> chapterSnapshot) {
        try {
            JSONArray summaryArray = new JSONArray();
            for (ComicModels.ComicSummary summary : summarySnapshot) summaryArray.put(summaryToJson(summary));
            JSONArray detailArray = new JSONArray();
            for (ComicModels.ComicDetail detail : detailSnapshot) detailArray.put(detailToJson(detail));
            JSONArray chapterArray = new JSONArray();
            for (ComicModels.ChapterPage page : chapterSnapshot) chapterArray.put(chapterPageToJson(page));
            getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .putString(SUMMARIES_CACHE_KEY, summaryArray.toString())
                    .putString(DETAILS_CACHE_KEY, detailArray.toString())
                    .putString(CHAPTERS_CACHE_KEY, chapterArray.toString())
                    .apply();
            updateCacheSize(false);
        } catch (JSONException ignored) {
        }
    }

    private JSONObject summaryToJson(ComicModels.ComicSummary summary) throws JSONException {
        JSONObject object = new JSONObject();
        object.put("sourceId", summary.sourceId);
        object.put("comicId", summary.comicId);
        object.put("title", summary.title);
        object.put("coverUrl", summary.coverUrl);
        object.put("subtitle", summary.subtitle);
        object.put("tags", new JSONArray(summary.tags));
        return object;
    }

    private ComicModels.ComicSummary summaryFromJson(JSONObject object) throws JSONException {
        JSONArray tagsJson = object.optJSONArray("tags");
        List<String> tags = new ArrayList<>();
        if (tagsJson != null) {
            for (int i = 0; i < tagsJson.length(); i++) tags.add(tagsJson.optString(i));
        }
        return new ComicModels.ComicSummary(
                object.optString("sourceId"),
                object.optString("comicId"),
                object.optString("title"),
                object.optString("coverUrl"),
                object.optString("subtitle"),
                tags);
    }

    private JSONObject detailToJson(ComicModels.ComicDetail detail) throws JSONException {
        JSONObject object = new JSONObject();
        object.put("summary", summaryToJson(detail.summary));
        object.put("author", detail.author);
        object.put("status", detail.status);
        object.put("description", detail.description);
        object.put("latestChapter", detail.latestChapter);
        JSONArray chapterArray = new JSONArray();
        for (ComicModels.Chapter chapter : detail.chapters) {
            JSONObject chapterJson = new JSONObject();
            chapterJson.put("chapterId", chapter.chapterId);
            chapterJson.put("title", chapter.title);
            chapterJson.put("url", chapter.url);
            chapterJson.put("sectionSlot", chapter.sectionSlot);
            chapterJson.put("chapterSlot", chapter.chapterSlot);
            chapterArray.put(chapterJson);
        }
        object.put("chapters", chapterArray);
        return object;
    }

    private ComicModels.ComicDetail detailFromJson(JSONObject object) throws JSONException {
        ComicModels.ComicSummary summary = summaryFromJson(object.getJSONObject("summary"));
        List<ComicModels.Chapter> chapterList = new ArrayList<>();
        JSONArray chapterArray = object.optJSONArray("chapters");
        if (chapterArray != null) {
            for (int i = 0; i < chapterArray.length(); i++) {
                JSONObject chapter = chapterArray.getJSONObject(i);
                chapterList.add(new ComicModels.Chapter(
                        chapter.optString("chapterId"),
                        chapter.optString("title"),
                        chapter.optString("url"),
                        chapter.optInt("sectionSlot"),
                        chapter.optInt("chapterSlot")));
            }
        }
        return new ComicModels.ComicDetail(
                summary,
                cachedAuthor(summary.sourceId, object.optString("author")),
                object.optString("status"),
                object.optString("description"),
                object.optString("latestChapter"),
                chapterList);
    }

    private String cachedAuthor(String sourceId, String author) {
        if (!"manben".equals(sourceId) || TextUtils.isEmpty(author)) return author;
        int marker = author.lastIndexOf('>');
        return marker >= 0 ? author.substring(marker + 1).trim() : author;
    }

    private JSONObject chapterPageToJson(ComicModels.ChapterPage page) throws JSONException {
        JSONObject object = new JSONObject();
        object.put("chapterId", page.chapterId);
        object.put("title", page.title);
        object.put("imageUrls", new JSONArray(page.imageUrls));
        object.put("nextPageUrl", page.nextPageUrl);
        return object;
    }

    private ComicModels.ChapterPage chapterPageFromJson(JSONObject object) {
        JSONArray urlsJson = object.optJSONArray("imageUrls");
        List<String> urls = new ArrayList<>();
        if (urlsJson != null) {
            for (int i = 0; i < urlsJson.length(); i++) urls.add(urlsJson.optString(i));
        }
        return new ComicModels.ChapterPage(
                object.optString("chapterId"),
                object.optString("title"),
                urls,
                object.optString("nextPageUrl"));
    }

    private File imageCacheFile(String imageUrl) {
        File dir = new File(getCacheDir(), "images");
        if (!dir.exists()) dir.mkdirs();
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(imageUrl.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : hash) sb.append(String.format("%02x", b));
            return new File(dir, sb.toString() + ".img");
        } catch (java.security.NoSuchAlgorithmException e) {
            return new File(dir, Integer.toHexString(imageUrl.hashCode()) + ".img");
        }
    }

    private byte[] readAllBytes(InputStream stream) throws java.io.IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = stream.read(buffer)) != -1) output.write(buffer, 0, read);
        return output.toByteArray();
    }

    private void writeImageCache(File file, byte[] bytes) throws java.io.IOException {
        synchronized (imageCacheLock) {
            File parent = file.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            if (imageCacheBytes < 0L) imageCacheBytes = dirSize(parent);
            long previousLength = file.exists() ? file.length() : 0L;
            try (FileOutputStream output = new FileOutputStream(file)) {
                output.write(bytes);
            }
            imageCacheBytes += file.length() - previousLength;
            if (imageCacheBytes > IMAGE_CACHE_MAX_BYTES) trimImageCache();
        }
    }

    private void writeReaderImageCache(File file, InputStream stream) throws java.io.IOException {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        File temp = File.createTempFile("reader-", ".tmp", parent);
        File backup = new File(parent, file.getName() + ".bak-" + System.nanoTime());
        boolean replaced = false;
        try {
            try (FileOutputStream output = new FileOutputStream(temp)) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = stream.read(buffer)) != -1) {
                    if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("Reader image cancelled");
                    output.write(buffer, 0, read);
                }
            }
            synchronized (imageCacheLock) {
                if (imageCacheBytes < 0L) imageCacheBytes = Math.max(0L, dirSize(parent) - temp.length());
                long previousLength = file.exists() ? file.length() : 0L;
                boolean hadPrevious = file.exists();
                if (hadPrevious && !file.renameTo(backup)) throw new IOException("Cannot back up image cache: " + file);
                if (!temp.renameTo(file)) {
                    if (hadPrevious && !restoreReaderImageBackup(backup, file)) {
                        throw new IOException("Cannot restore image cache backup; retained at: " + backup);
                    }
                    throw new IOException("Cannot move image cache: " + file);
                }
                replaced = true;
                if (backup.exists()) backup.delete();
                imageCacheBytes += file.length() - previousLength;
                if (imageCacheBytes > IMAGE_CACHE_MAX_BYTES) trimImageCache();
            }
        } finally {
            if (temp.exists()) temp.delete();
            if (!replaced && backup.exists() && !file.exists()
                    && !restoreReaderImageBackup(backup, file)) {
                appendErrorLog("阅读图片缓存恢复失败",
                        new IOException("Backup retained at: " + backup));
            }
            if (replaced && backup.exists()) backup.delete();
        }
    }

    private boolean restoreReaderImageBackup(File backup, File target) {
        synchronized (imageCacheLock) {
            if (!backup.exists()) return target.exists();
            if (target.exists()) return true;
            if (backup.renameTo(target)) return true;
            File parent = target.getParentFile();
            File restore = null;
            try {
                restore = File.createTempFile("reader-restore-", ".tmp", parent);
                try (InputStream input = new FileInputStream(backup);
                     FileOutputStream output = new FileOutputStream(restore)) {
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
                    output.getFD().sync();
                }
                if (!restore.renameTo(target)) return false;
                if (backup.exists() && !backup.delete()) return false;
                return true;
            } catch (IOException error) {
                return false;
            } finally {
                if (restore != null && restore.exists()) restore.delete();
            }
        }
    }

    private void trimImageCache() {
        File dir = new File(getCacheDir(), "images");
        File[] files = dir.listFiles(File::isFile);
        if (files == null || files.length == 0) return;
        Arrays.sort(files, (left, right) -> Long.compare(left.lastModified(), right.lastModified()));
        for (File file : files) {
            if (imageCacheBytes <= IMAGE_CACHE_MAX_BYTES) break;
            long length = file.length();
            if (file.delete()) imageCacheBytes -= length;
        }
    }

    private void showHistory() {
        enterScreen();
        historyVisible = true;
        root.removeAllViews();
        applyThemeAndSystemBars();
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        scroll.setBackgroundColor(UIHelpers.BG);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(UIHelpers.dp(this, 20), UIHelpers.dp(this, 12), UIHelpers.dp(this, 20), UIHelpers.dp(this, 24));
        scroll.addView(content, UIHelpers.matchWrap());

        FrameLayout topBar = new FrameLayout(this);
        topBar.setBackgroundColor(UIHelpers.BG);
        ImageView back = UIHelpers.vectorIconButton(this, R.drawable.ic_back, UIHelpers.TEXT, 10);
        back.setOnClickListener(v -> navigateBack());
        topBar.addView(back, UIHelpers.frame(UIHelpers.dp(this, 44), UIHelpers.dp(this, 48), Gravity.CENTER_VERTICAL | Gravity.LEFT, UIHelpers.dp(this, 4), 0, 0, 0));
        TextView title = new TextView(this);
        title.setText("阅读历史");
        title.setTypeface(Typeface.SERIF);
        title.setTextSize(13);
        title.setTextColor(UIHelpers.TEXT);
        title.setGravity(Gravity.CENTER);
        topBar.addView(title, UIHelpers.frame(-2, -2, Gravity.CENTER, 0, 0, 0, 0));
        boolean hasAny = !progress.isEmpty();
        if (hasAny) {
            TextView clear = new TextView(this);
            clear.setText("清空");
            clear.setTextSize(13);
            clear.setTextColor(UIHelpers.TEXT3);
            clear.setGravity(Gravity.CENTER);
            clear.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 12));
            clear.setOnClickListener(v -> {
                styledDialog("清空阅读历史", "将清除所有阅读进度记录，收藏不会受影响。", "清空", () -> {
                    progress.clear();
                    readerPositions.clear();
                    lastViewedAt.clear();
                    saveLocalState();
                    showHistory();
                }, "取消", null);
            });
            topBar.addView(clear, UIHelpers.frame(-2, -2, Gravity.CENTER_VERTICAL | Gravity.RIGHT, 0, 0, UIHelpers.dp(this, 4), 0));
        }
        content.addView(topBar, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 48)));

        if (progress.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_history, "还没有阅读记录", "翻开一本，故事从这里开始", "去搜索", () -> showTab(1)));
        } else {
            List<Map.Entry<String, Long>> entries = new ArrayList<>(lastViewedAt.entrySet());
            Collections.sort(entries, (a, b) -> Long.compare(b.getValue(), a.getValue()));
            for (Map.Entry<String, Long> entry : entries) {
                if (!progress.containsKey(entry.getKey())) continue;
                content.addView(historyRow(entry.getKey(), entry.getValue()));
            }
        }
        root.addView(scroll, UIHelpers.match());
    }

    private View historyRow(String comicId, long viewedAt) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 4), UIHelpers.dp(this, 12), UIHelpers.dp(this, 4), UIHelpers.dp(this, 12));
        row.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 12), Color.TRANSPARENT));
        row.setElevation(UIHelpers.dp(this, 1));
        UIHelpers.tapFeedback(row);
        ComicModels.ComicSummary summary = summaries.get(comicId);
        ComicModels.ComicDetail detail = details.get(comicId);
        boolean orphaned = summary == null;
        FrameLayout coverWrap = new FrameLayout(this);
        View cover;
        if (orphaned) {
            cover = UIHelpers.coverPlaceholder(this, "");
        } else if (!TextUtils.isEmpty(summary.coverUrl)) {
            cover = coverFrame(summary.coverUrl, 80, 107);
        } else {
            cover = UIHelpers.coverPlaceholder(this, summary.title);
        }
        coverWrap.addView(cover, new FrameLayout.LayoutParams(UIHelpers.dp(this, 80), UIHelpers.dp(this, 107)));
        if (!orphaned && detail != null && !TextUtils.isEmpty(detail.status)) {
            UIHelpers.StatusDotView dot = new UIHelpers.StatusDotView(this);
            dot.setStatus(detail.status);
            FrameLayout.LayoutParams dotLp = new FrameLayout.LayoutParams(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), Gravity.BOTTOM | Gravity.END);
            dotLp.rightMargin = UIHelpers.dp(this, 6);
            dotLp.bottomMargin = UIHelpers.dp(this, 6);
            coverWrap.addView(dot, dotLp);
        }
        row.addView(coverWrap, new LinearLayout.LayoutParams(UIHelpers.dp(this, 80), UIHelpers.dp(this, 107)));

        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(this, 12), 0, UIHelpers.dp(this, 12), 0);
        TextView titleView = new TextView(this);
        titleView.setText(orphaned ? "已清除的漫画" : summary.title);
        titleView.setTextSize(16);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        titleView.setLetterSpacing(-0.02f);
        titleView.setTextColor(orphaned ? UIHelpers.TEXT3 : UIHelpers.TEXT);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        info.addView(titleView);
        int chapterIdx = progress.getOrDefault(comicId, 0);
        String chapterText;
        if (chapterIdx == 0) {
            chapterText = "刚开始看";
        } else if (detail != null && chapterIdx >= detail.chapters.size() - 1 && !detail.chapters.isEmpty()) {
            chapterText = "已读完整 · " + detail.chapters.get(chapterIdx).title;
        } else {
            chapterText = "上次看到 第 " + (chapterIdx + 1) + " 章";
        }
        info.addView(UIHelpers.text(this, chapterText, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 6)));
        info.addView(UIHelpers.text(this, DataHelpers.formatRelative(viewedAt), 12, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));
        row.addView(info, UIHelpers.weight(1));

        ImageView close = new ImageView(this);
        close.setImageResource(R.drawable.ic_close);
        close.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.TEXT3));
        close.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 12), UIHelpers.dp(this, 12), UIHelpers.dp(this, 12));
        close.setOnClickListener(v -> {
            styledDialog("删除这条记录", "将移除该漫画的阅读进度。", "删除", () -> {
                progress.remove(comicId);
                removeReaderPositions(comicId);
                lastViewedAt.remove(comicId);
                saveLocalState();
                showHistory();
            }, "取消", null);
        });
        row.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(this, 44), UIHelpers.dp(this, 44)));

        if (!orphaned) {
            row.setOnClickListener(v -> showDetail(comicId));
        }
        LinearLayout.LayoutParams lp = UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12));
        row.setLayoutParams(lp);
        return row;
    }

    private void clearAppCache() {
        synchronized (imageCacheLock) {
            deleteFiles(new File(getCacheDir(), "images"));
            imageCacheBytes = 0L;
        }
        imageMemoryCache.evictAll();
        Set<String> favoriteIds = new HashSet<>(favorites);
        summaries.keySet().retainAll(favoriteIds);
        details.keySet().retainAll(favoriteIds);
        chapters.clear();
        searchResults.clear();
        persistComicCachesAsync();
        showToast("缓存已清理，收藏数据已保留");
        showTab(3);
    }

    private void deleteFiles(File file) {
        if (file == null || !file.exists()) return;
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) deleteFiles(child);
            }
        }
        file.delete();
    }

    private void updateCacheSize() {
        updateCacheSize(true);
    }

    private void updateCacheSize(boolean trimIfNeeded) {
        long imageBytes;
        synchronized (imageCacheLock) {
            imageCacheBytes = dirSize(new File(getCacheDir(), "images"));
            if (trimIfNeeded && imageCacheBytes > IMAGE_CACHE_MAX_BYTES) trimImageCache();
            imageBytes = imageCacheBytes;
        }
        long bytes = imageBytes
                + getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(SUMMARIES_CACHE_KEY, "").length()
                + getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(DETAILS_CACHE_KEY, "").length()
                + getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(CHAPTERS_CACHE_KEY, "").length();
        String updatedCacheSize = formatBytes(bytes);
        main.post(() -> {
            if (activityDestroyed) return;
            cacheSize = updatedCacheSize;
            getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString("cache.size", updatedCacheSize).apply();
        });
    }

    private long dirSize(File file) {
        if (file == null || !file.exists()) return 0L;
        if (file.isFile()) return file.length();
        long total = 0L;
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) total += dirSize(child);
        }
        return total;
    }

    private String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        double kb = bytes / 1024.0;
        if (kb < 1024) return String.format(java.util.Locale.US, "%.1f KB", kb);
        return String.format(java.util.Locale.US, "%.1f MB", kb / 1024.0);
    }

    private void restoreCustomSources(String value) {
        customSources.clear();
        if (TextUtils.isEmpty(value)) return;
        for (String row : value.split("\\n")) {
            String[] parts = row.split("\\|", -1);
            if (parts.length < 5) continue;
            customSources.add(new ComicModels.Source(parts[0], parts[1], parts[2], parts[3], false, Boolean.parseBoolean(parts[4])));
        }
    }

    private String encodeCustomSources() {
        StringBuilder builder = new StringBuilder();
        for (ComicModels.Source item : customSources) {
            if (builder.length() > 0) builder.append("\n");
            builder.append(safeSourceField(item.id)).append("|")
                    .append(safeSourceField(item.name)).append("|")
                    .append(safeSourceField(item.domain)).append("|")
                    .append(safeSourceField(item.url)).append("|")
                    .append(item.enabled);
        }
        return builder.toString();
    }

    private String safeSourceField(String value) {
        return value == null ? "" : value.replace("|", " ").replace("\n", " ").replace("\r", " ");
    }
}
