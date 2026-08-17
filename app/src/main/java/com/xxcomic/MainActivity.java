package com.xxcomic;

import android.app.Activity;
import android.app.AlertDialog;
import android.animation.ValueAnimator;
import android.content.Context;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
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
import com.xxcomic.source.AntbywComicSource;
import com.xxcomic.source.AikanComicSource;
import com.xxcomic.source.ComicModels;
import com.xxcomic.source.ComicSource;
import com.xxcomic.source.CuimhComicSource;
import com.xxcomic.source.D5d6ComicSource;
import com.xxcomic.source.FiveUmComicSource;
import com.xxcomic.source.ManbenComicSource;
import com.xxcomic.source.GmhComicSource;
import com.xxcomic.source.Mh18ComicSource;
import com.xxcomic.source.JmComicSource;
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
import java.security.MessageDigest;
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
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends Activity {
    private static final String PREFS_NAME = "xx-comic";
    private static final String ALL_TAG = "全部";
    private static final int DETAIL_HERO_DP = 190;
    private static final int DETAIL_HERO_MAX_DP = 390;
    private static final int CHAPTER_DRAWER_BATCH_SIZE = 40;
    private static final long READER_PROGRESS_ANIM_MS = 30L;
    private static final long READER_CHROME_ANIM_MS = 180L;
    private static final int READER_CHROME_SHIFT_DP = 6;
    private static final int READER_POSITION_SCALE = 10000;
    private static final long READER_POSITION_SAVE_DELAY_MS = 250L;
    private static final long READER_MAX_DECODE_PIXELS = 8000000L;
    private static final long READER_MAX_DECODE_BYTES = 32L * 1024L * 1024L;
    private static final int READER_PREFETCH_COUNT = 4;
    private static final int SEARCH_PULL_REFRESH_DP = 72;
    private static final String SUMMARIES_CACHE_KEY = "cache.summaries";
    private static final String DETAILS_CACHE_KEY = "cache.details";
    private static final String CHAPTERS_CACHE_KEY = "cache.chapters";
    private static final long IMAGE_CACHE_MAX_BYTES = 1000L * 1024L * 1024L;
    private static final String ERROR_LOGS_KEY = "error.logs";
    private static final int ERROR_LOG_MAX_CHARS = 60000;
    private static final int IMPORT_SOURCES_REQUEST = 1001;
    private static final int EXPORT_SOURCES_REQUEST = 1002;
    private static final int EXPORT_LOGS_REQUEST = 1003;
    private static final int INSTALL_PACKAGES_REQUEST = 1004;
    private static final String UPDATE_METADATA_URL = "https://weifeng.cloud/xx-comic/releases/android-release.json";
    private static final String UPDATE_APK_URL = "https://weifeng.cloud/xx-comic/releases/xx-comic.apk";
    private static final String[] UPDATE_APK_URLS = {
            "https://xx-1321588235.cos.ap-guangzhou.myqcloud.com/apk/xx-comic/xx-comic.bin",
            UPDATE_APK_URL
    };
    private static final String UPDATE_APK_FILE_NAME = "xx-comic.apk";
    private static final String APK_MIME_TYPE = "application/vnd.android.package-archive";
    private static final String IMAGE_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private final Handler main = new Handler(Looper.getMainLooper());
    // 按模块拆分线程池，互不阻塞：搜索中切到收藏页，封面图走 imageIo 不被搜索阻塞
    private final ExecutorService searchIo = Executors.newFixedThreadPool(12);
    private final ExecutorService detailIo = Executors.newFixedThreadPool(2);
    private final ExecutorService imageIo = Executors.newFixedThreadPool(4);
    private final ExecutorService readerPrefetchIo = Executors.newFixedThreadPool(2);
    private final ExecutorService sourceHealthIo = Executors.newFixedThreadPool(1);
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
    private ComicSource mh18Client;
    private JmComicSource jmcomicClient;
    private ComicSource mkzhanClient;
    private ComicSource hiperdexClient;
    private ComicSource manhuaguiClient;
    private ComicSource hanman18Client;
    private ComicSource d5d6Client;
    private ComicSource manbenClient;
    private ComicSource manhuazhanClient;
    private ComicSource bbyinClient;
    private ComicSource antbywClient;
    private ComicSource cuimhClient;
    private CloudflareWebViewSession mh18BrowserSession;
    private CloudflareWebViewSession jmcomicBrowserSession;
    private SourceConfig baoziConfig = SourceConfig.baozi(true);
    private SourceConfig aikanConfig = SourceConfig.aikan(true);
    private SourceConfig gmhConfig = SourceConfig.gmh(true);
    private SourceConfig mh18Config = SourceConfig.mh18(true);
    private SourceConfig jmcomicConfig = SourceConfig.jmcomic(true);
    private SourceConfig mkzhanConfig = SourceConfig.mkzhan(true);
    private SourceConfig hiperdexConfig = SourceConfig.hiperdex(true);
    private SourceConfig manhuaguiConfig = SourceConfig.manhuagui(true);
    private SourceConfig hanman18Config = SourceConfig.hanman18(true);
    private SourceConfig d5d6Config = SourceConfig.d5d6(true);
    private SourceConfig manbenConfig = SourceConfig.manben(true);
    private SourceConfig manhuazhanConfig = SourceConfig.manhuazhan(true);
    private SourceConfig bbyinConfig = SourceConfig.bbyin(true);
    private SourceConfig antbywConfig = SourceConfig.antbyw(true);
    private SourceConfig cuimhConfig = SourceConfig.cuimh(true);
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
    private final Set<String> readerPrefetching = new HashSet<>();
    private final Set<String> verifyingProtectedSourceIds = new HashSet<>();
    private final Map<String, DetailAction> pendingRefreshActions = new HashMap<>();
    private final List<String> favorites = new ArrayList<>();
    private final List<ComicModels.FilterGroup> sourceFilterGroups = new ArrayList<>();
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
    private final Map<String, String> selectedFilters = new LinkedHashMap<>();
    private final Map<String, String> selectedFilterLabels = new LinkedHashMap<>();
    private Runnable filterDrawerAction;
    private boolean sourceEnabled = true;
    private boolean aikanEnabled = true;
    private boolean gmhEnabled = true;
    private boolean mh18Enabled = true;
    private boolean jmcomicEnabled = true;
    private boolean mkzhanEnabled = true;
    private boolean hiperdexEnabled = true;
    private boolean manhuaguiEnabled = true;
    private boolean hanman18Enabled = true;
    private boolean d5d6Enabled = true;
    private boolean manbenEnabled = true;
    private boolean manhuazhanEnabled = true;
    private boolean bbyinEnabled = true;
    private boolean antbywEnabled = true;
    private boolean cuimhEnabled = true;
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
    private boolean searchRefreshing = false;
    private boolean searchPullTracking = false;
    private float searchPullStartY = -1f;
    private float searchPullDistance = 0f;
    private boolean searchHasMore = true;
    private boolean sourceCategoriesFailed = false;
    private boolean searchAppendFailed = false;
    private String searchAppendFailedKeyword = "";
    private int searchAppendFailedPage = -1;
    private boolean searchAppendFailedCategoryMode = false;
    private int searchAppendFailedGeneration = -1;
    private int searchPage = 1;
    private boolean standaloneSearchVisible = false;
    private boolean historyVisible = false;
    private FrameLayout activeFavoriteDeleteCover;
    private View activeFavoriteDeleteOverlay;
    private boolean standaloneSearchResultsMode = false;
    private boolean sourceManagementVisible = false;
    private String settingsScene = "";
    private String activeErrorLog = "";
    private List<String> sourceHealthRows = new ArrayList<>();
    private boolean settingsSceneBackToSources = false;
    private boolean globalSearchMode = false;
    private boolean globalSearchLoading = false;
    private boolean activityDestroyed = false;
    private boolean updateRunning = false;
    private File pendingUpdateApk;
    private AppRelease availableUpdateRelease;
    private Future<?> updateFuture;
    private Future<?> sourceHealthFuture;
    private ProgressBar settingsUpdateProgressBar;
    private TextView settingsUpdateProgressText;
    private TextView settingsUpdateProgressMeta;
    private int updateGeneration = 0;
    private int sourceHealthGeneration = 0;
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
    private ProgressBar searchRefreshIndicator;
    private LinearLayout searchResultsContent;
    private View searchPagingFooter;
    private LinearLayout searchAppendFailedContent;
    // 搜索页分类栏折叠状态：用状态机 + reflow 守卫，避免 GONE/VISIBLE 引发 ScrollView clamp
    // scrollY 产生「隐藏→上滑→显示→下滑→隐藏」的闪烁循环。
    private boolean searchCategoryHidden;
    private boolean searchCategoryToggling;
    private View readerTopBar;
    private View readerBottomBar;
    private View readerProgressView;
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
        applyThemeAndSystemBars();
        root = new FrameLayout(this);
        setContentView(root);
        mh18BrowserSession = new CloudflareWebViewSession(
                this, main, mh18Config.name, false);
        jmcomicBrowserSession = new CloudflareWebViewSession(
                this, main, jmcomicConfig.name, true);
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
        if (mh18BrowserSession != null) mh18BrowserSession.shutdown();
        if (jmcomicBrowserSession != null) jmcomicBrowserSession.shutdown();
        super.onDestroy();
        activityDestroyed = true;
        cancelUpdateDownload();
        cancelSourceHealthCheck();
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
        readerPrefetchIo.shutdownNow();
        sourceHealthIo.shutdownNow();
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
        } else if (requestCode == INSTALL_PACKAGES_REQUEST && pendingUpdateApk != null) {
            if (canInstallPackages()) {
                openPackageInstaller(pendingUpdateApk);
            } else {
                updateRunning = false;
                pendingUpdateApk = null;
                showInfo("无法安装更新", "需要允许 XX Comic 安装未知应用。");
            }
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
        if (activeFavoriteDeleteOverlay != null) {
            if (activeFavoriteDeleteCover != null && activeFavoriteDeleteOverlay.getParent() == activeFavoriteDeleteCover) {
                activeFavoriteDeleteCover.removeView(activeFavoriteDeleteOverlay);
                activeFavoriteDeleteCover.setTag(null);
            }
            activeFavoriteDeleteCover = null;
            activeFavoriteDeleteOverlay = null;
            return true;
        }
        if (historyVisible && TextUtils.isEmpty(activeDetailId)) {
            historyVisible = false;
            showTab(currentTab);
            return true;
        }
        if (sourceManagementVisible) {
            sourceManagementVisible = false;
            showTab(2);
            return true;
        }
        if (!TextUtils.isEmpty(settingsScene)) {
            if (settingsScene.startsWith("update-")) cancelUpdateDownload();
            if (settingsScene.startsWith("health-")) cancelSourceHealthCheck();
            if ("error-detail".equals(settingsScene)) {
                showErrorLogs();
            } else if (settingsSceneBackToSources) {
                settingsScene = "";
                settingsSceneBackToSources = false;
                showSourceManagement();
            } else {
                settingsScene = "";
                showTab(2);
            }
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
        applyReaderSystemBars(false);
    }

    private void applyReaderSystemBars(boolean stableLayout) {
        getWindow().setStatusBarColor(UIHelpers.DARK);
        getWindow().setNavigationBarColor(UIHelpers.DARK);
        int flags = stableLayout
                ? View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                : 0;
        if (readerFullscreen) {
            flags |= View.SYSTEM_UI_FLAG_FULLSCREEN
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
        if (!TextUtils.isEmpty(settingsScene)) {
            rerenderSettingsScene();
            return;
        }
        if (sourceManagementVisible) {
            showSourceManagement();
            return;
        }
        if (historyVisible && TextUtils.isEmpty(activeDetailId)) {
            showHistory();
            return;
        }
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

    private void rerenderSettingsScene() {
        switch (settingsScene) {
            case "cache": showCacheCleanup(); break;
            case "cache-loading": showCacheCleanupLoading(); break;
            case "errors": showErrorLogs(); break;
            case "error-detail": showErrorLogDetail(activeErrorLog); break;
            case "about": showAboutApp(); break;
            case "health-loading": showSourceHealthLoading(); break;
            case "health-results": showSourceHealthResults(); break;
            case "update-loading": showUpdateLoading(); break;
            case "update-available": showUpdateAvailable(availableUpdateRelease); break;
            case "update-download": showUpdateDownload(availableUpdateRelease, settingsUpdateProgressBar == null ? 0 : settingsUpdateProgressBar.getProgress()); break;
            case "update-latest": showUpdateLatest(); break;
            case "update-error": showUpdateFailure(); break;
            default: showTab(2); break;
        }
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
        readerPrefetching.clear();
        searchLoading = false;
        searchAppending = false;
        finishSearchPullRefresh();
        clearSearchAppendFailure();
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
        return submitReaderImage(imageIo, task);
    }

    private Future<?> submitReaderImage(ExecutorService executor, Runnable task) {
        FutureTask<?> future = new FutureTask<Object>(task, null) {
            @Override
            protected void done() {
                main.post(() -> currentImageFutures.remove(this));
            }
        };
        currentImageFutures.add(future);
        executor.execute(future);
        return future;
    }

    private void cancelCurrentImageTasks() {
        for (Future<?> f : currentImageFutures) {
            if (f != null && !f.isDone()) f.cancel(true);
        }
        currentImageFutures = new ArrayList<>();
    }

    // Explicitly exiting standalone search clears its inputs; Tab switches preserve search state.
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
        if (settingsScene.startsWith("health-")) cancelSourceHealthCheck();
        applyThemeAndSystemBars();
        currentTab = tab;
        activeDetailId = "";
        detailBackAction = null;
        historyVisible = false;
        activeFavoriteDeleteCover = null;
        activeFavoriteDeleteOverlay = null;
        sourceManagementVisible = false;
        settingsScene = "";
        activeErrorLog = "";
        settingsSceneBackToSources = false;
        updateGeneration++;
        standaloneSearchVisible = false;
        standaloneSearchResultsMode = false;
        readerVisible = false;
        root.removeAllViews();
        FrameLayout shell = new FrameLayout(this);
        shell.setBackgroundColor(UIHelpers.BG);
        root.addView(shell, UIHelpers.match());

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 68));

        if (tab == 2) {
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
        if (tab == 2) renderSettings(page);
        shell.addView(makeBottomNav(), UIHelpers.frame(-1, UIHelpers.dp(this, 60), Gravity.BOTTOM, 0, 0, 0, 0));
        if (tab == 1 && previousTab != 1 && sourceFilterGroups.isEmpty()
                && !categoriesFollowInitialList(selectedSourceId)) loadSourceCategories();
        if (!globalSearchMode) scheduleDefaultSearchLoad();
    }

    private void renderSettings(LinearLayout page) {
        addTitle(page, "设置", null);
        page.addView(settingsSectionText("阅读与外观"));
        LinearLayout appearance = settingsList();
        appearance.setPadding(0, 0, 0, 0);
        appearance.addView(settingsMenuItem(themeIcon(), "主题模式", "跟随系统、浅色或深色", themeModeLabel(), this::showThemeDrawer));
        appearance.addView(UIHelpers.divider(this));
        appearance.addView(settingsMenuItem(R.drawable.ic_chevron_left, "左右手模式", "切换阅读页左右触控区",
                readerLeftHand ? "左手" : "右手", this::showHandModeDrawer));
        appearance.addView(UIHelpers.divider(this));
        appearance.addView(settingsMenuItem(R.drawable.ic_history, "阅读历史", "章节与阅读位置", progress.size() + " 条", this::showHistory));
        page.addView(appearance);

        page.addView(settingsSectionText("站源与本地数据"));
        LinearLayout local = settingsList();
        local.setPadding(0, 0, 0, 0);
        local.addView(settingsMenuItem(R.drawable.ic_source, "站源管理", "启停、导入导出与检测",
                enabledBuiltinSources().size() + " 个开启", this::showSourceManagement));
        local.addView(UIHelpers.divider(this));
        local.addView(settingsMenuItem(R.drawable.ic_trash, "缓存清理", "保留收藏与阅读历史", cacheSize, this::showCacheCleanup));
        local.addView(UIHelpers.divider(this));
        local.addView(settingsMenuItem(R.drawable.ic_lightning, "错误日志", "只保存在本机", errorLogSummary(), this::showErrorLogs));
        page.addView(local);

        page.addView(settingsSectionText("App"));
        LinearLayout app = settingsList();
        app.setPadding(0, 0, 0, 0);
        app.addView(settingsMenuItem(R.drawable.ic_auto, "版本更新", "", installedVersionLabel(), this::checkForUpdate));
        app.addView(UIHelpers.divider(this));
        app.addView(settingsMenuItem(R.drawable.ic_profile, "关于 App", "", BuildConfig.VERSION_NAME, this::showAboutApp));
        page.addView(app);
    }

    private void showSourceManagement() {
        enterScreen();
        settingsScene = "";
        settingsSceneBackToSources = false;
        sourceManagementVisible = true;
        root.removeAllViews();
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        scroll.setBackgroundColor(UIHelpers.BG);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 24));
        scroll.addView(page, UIHelpers.matchWrap());
        renderSources(page);
        root.addView(scroll, UIHelpers.match());
    }

    private void renderSearch(LinearLayout page) {
        addDiscoveryTitle(page);
        LinearLayout searchBar = new LinearLayout(this);
        searchBar.setGravity(Gravity.CENTER_VERTICAL);
        searchBar.setPadding(UIHelpers.dp(this, 4), 0, UIHelpers.dp(this, 4), 0);
        searchBar.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 8), UIHelpers.BORDER));
        EditText input = UIHelpers.searchBox(this, globalSearchMode ? "搜索全部站源" : "搜索" + selectedSourceName(), true);
        input.setBackgroundColor(Color.TRANSPARENT);
        bindingSearchText = true;
        input.setText(globalSearchMode ? globalSearchQuery : searchQuery);
        input.setSelection(input.getText().length());
        bindingSearchText = false;
        input.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        input.setSingleLine(true);
        input.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                String keyword = v.getText().toString().trim();
                if (globalSearchMode) {
                    globalSearchQuery = keyword;
                    if (!keyword.isEmpty()) {
                        addSearchHistory(keyword);
                        startGlobalSearch(keyword);
                    } else {
                        showTab(1);
                    }
                    return true;
                }
                searchQuery = keyword;
                resetCategoryFilters();
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
                if (globalSearchMode) globalSearchQuery = s.toString();
                else searchQuery = s.toString();
            }
        });
        searchBar.addView(input, new LinearLayout.LayoutParams(0, UIHelpers.dp(this, 42), 1));
        searchBar.addView(searchModeButton(), new LinearLayout.LayoutParams(UIHelpers.dp(this, 52), UIHelpers.dp(this, 38)));
        page.addView(searchBar, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));

        if (globalSearchMode) {
            renderGlobalDiscovery(page);
            return;
        }

        HorizontalScrollView filterScroll = new HorizontalScrollView(this);
        filterScroll.setHorizontalScrollBarEnabled(false);
        LinearLayout filters = new LinearLayout(this);
        filters.setOrientation(LinearLayout.HORIZONTAL);
        for (int i = 0; i < sourceFilterGroups.size(); i++) {
            ComicModels.FilterGroup group = sourceFilterGroups.get(i);
            filters.addView(filterTextButton(group.label, i + 1),
                    UIHelpers.marginRight(-2, i == sourceFilterGroups.size() - 1 ? 0 : UIHelpers.dp(this, 14)));
        }
        filterScroll.addView(filters, UIHelpers.wrap());
        if (!sourceFilterGroups.isEmpty()) {
            page.addView(filterScroll, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 6)));
        }
        if (sourceCategoriesFailed && categoriesFollowInitialList(selectedSourceId)) {
            TextView retryCategories = UIHelpers.text(
                    this, "分类加载失败，重试", 12, UIHelpers.ACCENT, Typeface.BOLD);
            retryCategories.setGravity(Gravity.CENTER_VERTICAL);
            retryCategories.setBackgroundColor(Color.TRANSPARENT);
            retryCategories.setOnClickListener(v -> {
                sourceCategoriesFailed = false;
                showTab(1, false);
                loadSourceCategories();
            });
            page.addView(retryCategories,
                    UIHelpers.marginBottom(-2, UIHelpers.dp(this, 6)));
        }
        page.addView(sectionTitle(selectedSourceName() + " · " + (TextUtils.isEmpty(searchQuery.trim()) ? "全部漫画" : "搜索结果")));

        PullRefreshScrollView scroll = new PullRefreshScrollView(this);
        searchScroll = scroll;
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        searchResultsContent = content;
        searchPagingFooter = null;
        scroll.addView(content, UIHelpers.matchWrap());
        scroll.setOnScrollChangeListener((v, scrollX, scrollY, oldScrollX, oldScrollY) -> {
            View child = scroll.getChildAt(0);
            if (child != null && shouldLoadNextSearchPage(scrollY, oldScrollY,
                    scroll.getHeight(), child.getHeight(), UIHelpers.dp(this, 120))) {
                loadNextSearchPage();
            }
        });
        FrameLayout searchBody = new FrameLayout(this);
        searchBody.addView(scroll, UIHelpers.match());
        searchRefreshIndicator = new ProgressBar(this);
        searchRefreshIndicator.setIndeterminate(true);
        searchRefreshIndicator.setVisibility(searchRefreshing ? View.VISIBLE : View.GONE);
        FrameLayout.LayoutParams indicatorParams = new FrameLayout.LayoutParams(
                UIHelpers.dp(this, 28), UIHelpers.dp(this, 28), Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        indicatorParams.topMargin = UIHelpers.dp(this, 8);
        searchBody.addView(searchRefreshIndicator, indicatorParams);
        page.addView(searchBody, new LinearLayout.LayoutParams(-1, 0, 1));
        if (pendingSearchScrollY >= 0) {
            int restoreY = pendingSearchScrollY;
            pendingSearchScrollY = -1;
            scroll.post(() -> scroll.scrollTo(0, restoreY));
        }

        if (selectedSource() == null) {
            content.addView(emptyState(R.drawable.ic_source, "还没有启用站源", "去设置里打开一个漫画来源", "去设置", () -> showTab(2)));
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
                resetCategoryFilters();
                showTab(1);
            }));
            return;
        }
        appendSearchRows(content, visible);
        renderSearchPagingFooter(content);
    }

    private void addDiscoveryTitle(LinearLayout page) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(UIHelpers.text(this, "发现", 24, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        if (!globalSearchMode) {
            TextView source = UIHelpers.text(this, selectedSourceName() + "  ▾", 12, UIHelpers.ACCENT_DARK, Typeface.BOLD);
            source.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
            source.setSingleLine(true);
            source.setEllipsize(TextUtils.TruncateAt.END);
            source.setMaxWidth(UIHelpers.dp(this, 150));
            source.setPadding(UIHelpers.dp(this, 8), 0, 0, 0);
            source.setBackgroundColor(Color.TRANSPARENT);
            source.setOnClickListener(v -> showFilterDrawer(0));
            row.addView(source, new LinearLayout.LayoutParams(-2, UIHelpers.dp(this, 36)));
        }
        page.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 14)));
    }

    private TextView searchModeButton() {
        TextView mode = UIHelpers.text(this, globalSearchMode ? "全站" : "单站", 12, UIHelpers.ACCENT_DARK, Typeface.BOLD);
        mode.setGravity(Gravity.CENTER);
        mode.setBackgroundColor(Color.TRANSPARENT);
        mode.setOnClickListener(v -> {
            globalSearchMode = !globalSearchMode;
            enterScreen();
            globalSearchGeneration++;
            globalSearchLoading = false;
            showTab(1, false);
        });
        return mode;
    }

    private TextView filterTextButton(String label, int drawerTab) {
        TextView button = UIHelpers.text(this, label + "  ▾", 12, UIHelpers.TEXT2, Typeface.BOLD);
        button.setGravity(Gravity.CENTER_VERTICAL);
        button.setPadding(UIHelpers.dp(this, 2), UIHelpers.dp(this, 7), UIHelpers.dp(this, 2), UIHelpers.dp(this, 7));
        button.setBackgroundColor(Color.TRANSPARENT);
        button.setOnClickListener(v -> showFilterDrawer(drawerTab));
        return button;
    }

    private void renderGlobalDiscovery(LinearLayout page) {
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        if (TextUtils.isEmpty(globalSearchQuery.trim())) {
            renderSearchHistory(content);
            return;
        }
        List<ComicSource> sources = enabledSearchSources();
        ensureSelectedGlobalSearchSource(sources);
        if (sources.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_source, "没有可用站源", "去设置里开启站源", "去设置", () -> showTab(2)));
            return;
        }
        globalSearchTabsScroller = globalSearchSourceTabs(sources);
        content.addView(globalSearchTabsScroller, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
        LinearLayout heading = new LinearLayout(this);
        heading.setGravity(Gravity.CENTER_VERTICAL);
        heading.addView(sectionTitle("搜索结果"), UIHelpers.weight(1));
        globalSearchStatusView = UIHelpers.text(this, "", 11, UIHelpers.TEXT3, Typeface.NORMAL);
        heading.addView(globalSearchStatusView);
        content.addView(heading, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
        globalSearchResultsContainer = new LinearLayout(this);
        globalSearchResultsContainer.setOrientation(LinearLayout.VERTICAL);
        globalSearchContent = globalSearchResultsContainer;
        content.addView(globalSearchResultsContainer);
        refreshGlobalSearchTabs();
        refreshGlobalSearchResults();
        updateGlobalSearchStatus();
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
        for (int i = 0; i < items.size(); i += 3) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            for (int column = 0; column < 3; column++) {
                int index = i + column;
                if (index < items.size()) row.addView(resultCard(items.get(index)), UIHelpers.weight(1));
                else row.addView(new View(this), UIHelpers.weight(1));
                if (column < 2) row.addView(UIHelpers.space(this, UIHelpers.dp(this, 9), 1));
            }
            content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 12)));
        }
    }

    private void renderSearchPagingFooter(LinearLayout content) {
        removeSearchPagingFooter();
        if (searchAppendFailed) {
            TextView retry = UIHelpers.text(this, "加载失败，点击重试", 12, UIHelpers.ACCENT, Typeface.NORMAL);
            retry.setGravity(Gravity.CENTER);
            retry.setOnClickListener(v -> {
                if (currentTab == 1 && searchResultsContent == content && searchAppendFailedContent == content
                        && searchAppendFailedGeneration == searchGeneration && !searchLoading && !searchAppending) {
                    loadSearchPage(searchAppendFailedKeyword, searchAppendFailedPage, true, searchAppendFailedCategoryMode);
                }
            });
            searchPagingFooter = retry;
        } else if (searchAppending) {
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
        addBookshelfTitle(page);
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        List<String> visible = filterFavorites();
        String continueId = null;
        long latestRead = Long.MIN_VALUE;
        for (String id : progress.keySet()) {
            long readAt = lastViewedAt.containsKey(id) ? lastViewedAt.get(id) : Long.MIN_VALUE;
            if (readAt > latestRead) {
                latestRead = readAt;
                continueId = id;
            }
        }
        if (continueId == null && !progress.isEmpty()) continueId = progress.keySet().iterator().next();
        if (favorites.isEmpty() && continueId == null) {
            content.addView(bookshelfEmptyState(false));
            return;
        }
        if (continueId != null) {
            content.addView(bookshelfSectionHeader("接着看", "阅读历史 ›", this::showHistory));
            content.addView(continueReadingRow(continueId));
        }
        content.addView(bookshelfSectionHeader("全部收藏", visible.isEmpty() ? "0 本" : "最近使用排序", null));
        if (visible.isEmpty()) {
            content.addView(bookshelfEmptyState(true));
            return;
        }
        for (int i = 0; i < visible.size(); i += 3) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            for (int column = 0; column < 3; column++) {
                int index = i + column;
                if (index < visible.size()) row.addView(favoriteGridItem(visible.get(index)), UIHelpers.weight(1));
                else row.addView(new View(this), UIHelpers.weight(1));
                if (column < 2) row.addView(UIHelpers.space(this, UIHelpers.dp(this, 5), 1));
            }
            content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));
        }
    }

    private void addBookshelfTitle(LinearLayout page) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = UIHelpers.text(this, "书架", 24, UIHelpers.TEXT, Typeface.BOLD);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        row.addView(title, UIHelpers.weight(1));
        row.addView(UIHelpers.text(this, favorites.size() + " 本", 12, UIHelpers.TEXT3, Typeface.NORMAL));
        ImageView rem = new ImageView(this);
        rem.setImageResource(R.drawable.rem_reader_resume);
        rem.setScaleType(ImageView.ScaleType.CENTER_CROP);
        rem.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 12), UIHelpers.BORDER));
        rem.setClipToOutline(true);
        rem.setContentDescription("蕾姆主题");
        LinearLayout.LayoutParams remParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 23), UIHelpers.dp(this, 23));
        remParams.leftMargin = UIHelpers.dp(this, 8);
        row.addView(rem, remParams);
        page.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 6)));
    }

    private View bookshelfSectionHeader(String title, String end, Runnable endAction) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setMinimumHeight(UIHelpers.dp(this, 36));
        TextView titleView = UIHelpers.text(this, title, 16, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        row.addView(titleView, UIHelpers.weight(1));
        TextView endView = UIHelpers.text(this, end, 12, endAction == null ? UIHelpers.TEXT3 : UIHelpers.ACCENT, Typeface.NORMAL);
        endView.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
        endView.setPadding(UIHelpers.dp(this, 8), 0, 0, 0);
        if (endAction != null) {
            endView.setContentDescription("打开阅读历史");
            endView.setOnClickListener(v -> endAction.run());
        }
        row.addView(endView, new LinearLayout.LayoutParams(-2, -1));
        return row;
    }

    private View continueReadingRow(String id) {
        ComicModels.ComicDetail detail = details.get(id);
        ComicModels.ComicSummary summary = summaries.get(id);
        String title = detail != null ? detail.summary.title : summary != null ? summary.title : id;
        String cover = detail != null ? detail.summary.coverUrl : summary != null ? summary.coverUrl : "";
        LinearLayout strip = new LinearLayout(this);
        strip.setOrientation(LinearLayout.VERTICAL);
        strip.addView(UIHelpers.divider(this));
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 1), 0, UIHelpers.dp(this, 1), 0);
        ImageView coverView = coverView(cover, 34, 34, isRetiredComic(id));
        coverView.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 17), Color.TRANSPARENT));
        coverView.setClipToOutline(true);
        coverView.setContentDescription(title + "封面");
        row.addView(coverView, new LinearLayout.LayoutParams(UIHelpers.dp(this, 34), UIHelpers.dp(this, 34)));
        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(this, 10), 0, 0, 0);
        TextView titleView = UIHelpers.text(this, title, 15, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setSingleLine(true);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(titleView);
        copy.addView(UIHelpers.text(this, "上次看到 · 第 " + (savedChapter(id) + 1) + " 话", 11, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        row.addView(copy, UIHelpers.weight(1));
        TextView resume = UIHelpers.text(this, "续读 ›", 12, UIHelpers.ACCENT, Typeface.BOLD);
        resume.setGravity(Gravity.CENTER);
        resume.setPadding(UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 2), 0);
        resume.setContentDescription("继续阅读");
        resume.setOnClickListener(v -> showDetailThenRead(id));
        row.addView(resume, new LinearLayout.LayoutParams(-2, -1));
        row.setOnClickListener(v -> showDetailThenRead(id));
        strip.addView(row, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 50)));
        strip.addView(UIHelpers.divider(this));
        return strip;
    }

    private View bookshelfEmptyState(boolean compact) {
        LinearLayout state = new LinearLayout(this);
        state.setOrientation(LinearLayout.VERTICAL);
        state.setGravity(Gravity.CENTER);
        state.setMinimumHeight(UIHelpers.dp(this, compact ? 190 : 330));
        ImageView art = new ImageView(this);
        art.setImageResource(R.drawable.rem_empty);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        art.setContentDescription("蕾姆提示书架为空");
        int artSize = UIHelpers.dp(this, compact ? 54 : 78);
        state.addView(art, new LinearLayout.LayoutParams(artSize, artSize));
        TextView title = UIHelpers.text(this, "书架还空着", 17, UIHelpers.TEXT, Typeface.BOLD);
        state.addView(title, UIHelpers.marginTop(-2, UIHelpers.dp(this, 10)));
        String description = compact ? "去发现页收藏喜欢的漫画" : "收藏的漫画和阅读进度都会保存在本机";
        TextView descriptionView = UIHelpers.text(this, description, 12, UIHelpers.TEXT3, Typeface.NORMAL);
        descriptionView.setGravity(Gravity.CENTER);
        state.addView(descriptionView, UIHelpers.marginTop(-2, UIHelpers.dp(this, 5)));
        Button discover = UIHelpers.primaryButton(this, "去发现");
        discover.setOnClickListener(v -> showTab(1));
        state.addView(discover, UIHelpers.marginTop(UIHelpers.dp(this, 92), UIHelpers.dp(this, 10), -2, UIHelpers.dp(this, 38)));
        return state;
    }

    private View favoriteGridItem(String id) {
        ComicModels.ComicDetail detail = details.get(id);
        ComicModels.ComicSummary summary = summaries.get(id);
        String title = detail != null ? detail.summary.title : summary != null ? summary.title : id;
        String cover = detail != null ? detail.summary.coverUrl : summary != null ? summary.coverUrl : "";
        LinearLayout item = new LinearLayout(this);
        item.setOrientation(LinearLayout.VERTICAL);
        int coverHeight = Math.min(154, Math.round((getResources().getDisplayMetrics().widthPixels
                / getResources().getDisplayMetrics().density - 42f) / 3f * 4f / 3f));
        FrameLayout coverWrap = coverFrame(cover, -1, coverHeight, isRetiredComic(id));
        coverWrap.setBackground(UIHelpers.round(UIHelpers.PLACEHOLDER, UIHelpers.dp(this, 4), Color.TRANSPARENT));
        coverWrap.setClipToOutline(true);
        item.addView(coverWrap, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, coverHeight)));
        TextView titleView = UIHelpers.text(this, title, 13, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        titleView.setMinHeight(UIHelpers.dp(this, 34));
        item.addView(titleView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));
        item.setOnClickListener(v -> showDetail(id));
        item.setOnLongClickListener(v -> {
            showFavoriteDeleteOverlay(coverWrap, id);
            return true;
        });
        return item;
    }

    private void showFavoriteDeleteOverlay(FrameLayout coverWrap, String id) {
        Object tag = coverWrap.getTag();
        if (tag instanceof View) {
            coverWrap.removeView((View) tag);
            coverWrap.setTag(null);
            activeFavoriteDeleteCover = null;
            activeFavoriteDeleteOverlay = null;
            return;
        }
        if (activeFavoriteDeleteCover != null && activeFavoriteDeleteOverlay != null
                && activeFavoriteDeleteOverlay.getParent() == activeFavoriteDeleteCover) {
            activeFavoriteDeleteCover.removeView(activeFavoriteDeleteOverlay);
            activeFavoriteDeleteCover.setTag(null);
        }
        FrameLayout overlay = new FrameLayout(this);
        overlay.setBackgroundColor(Color.argb(165, 20, 43, 62));
        ImageView trash = UIHelpers.vectorIconButton(this, R.drawable.ic_trash, Color.WHITE, 13);
        trash.setBackground(UIHelpers.round(UIHelpers.DANGER, UIHelpers.dp(this, 24), Color.TRANSPARENT));
        trash.setContentDescription("删除收藏");
        trash.setOnClickListener(v -> deleteFavoriteWithUndo(id));
        overlay.addView(trash, UIHelpers.frame(UIHelpers.dp(this, 48), UIHelpers.dp(this, 48), Gravity.CENTER, 0, 0, 0, 0));
        overlay.setOnClickListener(v -> {
            coverWrap.removeView(overlay);
            coverWrap.setTag(null);
            activeFavoriteDeleteCover = null;
            activeFavoriteDeleteOverlay = null;
        });
        coverWrap.addView(overlay, UIHelpers.match());
        coverWrap.setTag(overlay);
        activeFavoriteDeleteCover = coverWrap;
        activeFavoriteDeleteOverlay = overlay;
    }

    private void renderSources(LinearLayout page) {
        settingsHeader(page, "站源管理", enabledBuiltinSources().size() + " 个开启", sourceOverflowButton());
        LinearLayout enabledSources = new LinearLayout(this);
        enabledSources.setOrientation(LinearLayout.VERTICAL);
        LinearLayout disabledSources = new LinearLayout(this);
        disabledSources.setOrientation(LinearLayout.VERTICAL);
        addSourceCard(enabledSources, disabledSources, sourceEnabled, sourceCard(baoziConfig, sourceEnabled, () -> {
            sourceEnabled = !sourceEnabled;
            baoziConfig = baoziConfig.withEnabled(sourceEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, aikanEnabled, sourceCard(aikanConfig, aikanEnabled, () -> {
            aikanEnabled = !aikanEnabled;
            aikanConfig = aikanConfig.withEnabled(aikanEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, gmhEnabled, sourceCard(gmhConfig, gmhEnabled, () -> {
            gmhEnabled = !gmhEnabled;
            gmhConfig = gmhConfig.withEnabled(gmhEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, mh18Enabled, sourceCard(mh18Config, mh18Enabled, () -> {
            mh18Enabled = !mh18Enabled;
            mh18Config = mh18Config.withEnabled(mh18Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, jmcomicEnabled, sourceCard(jmcomicConfig, jmcomicEnabled, () -> {
            jmcomicEnabled = !jmcomicEnabled;
            jmcomicConfig = jmcomicConfig.withEnabled(jmcomicEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, mkzhanEnabled, sourceCard(mkzhanConfig, mkzhanEnabled, () -> {
            mkzhanEnabled = !mkzhanEnabled;
            mkzhanConfig = mkzhanConfig.withEnabled(mkzhanEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, hiperdexEnabled, sourceCard(hiperdexConfig, hiperdexEnabled, () -> {
            hiperdexEnabled = !hiperdexEnabled;
            hiperdexConfig = hiperdexConfig.withEnabled(hiperdexEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, manhuaguiEnabled, sourceCard(manhuaguiConfig, manhuaguiEnabled, () -> {
            manhuaguiEnabled = !manhuaguiEnabled;
            manhuaguiConfig = manhuaguiConfig.withEnabled(manhuaguiEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, hanman18Enabled, sourceCard(hanman18Config, hanman18Enabled, () -> {
            hanman18Enabled = !hanman18Enabled;
            hanman18Config = hanman18Config.withEnabled(hanman18Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, d5d6Enabled, sourceCard(d5d6Config, d5d6Enabled, () -> {
            d5d6Enabled = !d5d6Enabled;
            d5d6Config = d5d6Config.withEnabled(d5d6Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, manbenEnabled, sourceCard(manbenConfig, manbenEnabled, () -> {
            manbenEnabled = !manbenEnabled;
            manbenConfig = manbenConfig.withEnabled(manbenEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, manhuazhanEnabled, sourceCard(manhuazhanConfig, manhuazhanEnabled, () -> {
            manhuazhanEnabled = !manhuazhanEnabled;
            manhuazhanConfig = manhuazhanConfig.withEnabled(manhuazhanEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, bbyinEnabled, sourceCard(bbyinConfig, bbyinEnabled, () -> {
            bbyinEnabled = !bbyinEnabled;
            bbyinConfig = bbyinConfig.withEnabled(bbyinEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, antbywEnabled, sourceCard(antbywConfig, antbywEnabled, () -> {
            antbywEnabled = !antbywEnabled;
            antbywConfig = antbywConfig.withEnabled(antbywEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(enabledSources, disabledSources, cuimhEnabled, sourceCard(cuimhConfig, cuimhEnabled, () -> {
            cuimhEnabled = !cuimhEnabled;
            cuimhConfig = cuimhConfig.withEnabled(cuimhEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        LinearLayout sourceList = settingsList();
        sourceList.setPadding(0, 0, 0, 0);
        appendSourceRows(sourceList, enabledSources);
        appendSourceRows(sourceList, disabledSources);
        page.addView(sourceList);
    }

    private void appendSourceRows(LinearLayout target, LinearLayout rows) {
        while (rows.getChildCount() > 0) {
            View row = rows.getChildAt(0);
            rows.removeViewAt(0);
            if (target.getChildCount() > 0) target.addView(UIHelpers.divider(this));
            target.addView(row);
        }
    }

    private void finishSourceToggle() {
        List<ComicSource> enabled = enabledBuiltinSources();
        boolean selectedStillEnabled = false;
        for (ComicSource source : enabled) {
            if (source.id().equals(selectedSourceId)) {
                selectedStillEnabled = true;
                break;
            }
        }
        if (!selectedStillEnabled) {
            searchGeneration++;
            searchLoading = false;
            searchAppending = false;
            finishSearchPullRefresh();
            clearSearchAppendFailure();
            removeSearchPagingFooter();
            selectedSourceId = enabled.isEmpty() ? "" : enabled.get(0).id();
            sourceCategoriesFailed = false;
            searchQuery = "";
            resetCategoryFilters();
            sourceFilterGroups.clear();
            searchResults.clear();
            resetSearchPaging();
        }
        saveLocalState();
        showSourceManagement();
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
        group.addView(menuItemWithIcon(R.drawable.ic_auto, "版本更新", installedVersionLabel(), this::checkForUpdate));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItemWithIcon(R.drawable.ic_profile, "关于 App", BuildConfig.VERSION_NAME, () -> showInfo("关于 App", "XX Comic 已接入多个漫画站源，支持搜索、详情、阅读图片和本地缓存。")));
        page.addView(group);
    }

    private void toggleReaderHand() {
        readerLeftHand = !readerLeftHand;
        saveLocalState();
        showRemToast(readerLeftHand ? "已切换到左手模式" : "已切换到右手模式");
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

    private void showThemeDrawer() {
        LinearLayout choices = new LinearLayout(this);
        choices.setOrientation(LinearLayout.HORIZONTAL);
        choices.setPadding(0, UIHelpers.dp(this, 8), 0, 0);
        String[] labels = {"跟随系统", "浅色", "深色"};
        for (int i = 0; i < labels.length; i++) {
            final int selected = i;
            choices.addView(themeChoice(labels[i], i, themeMode == i, () -> {
                if (activePopup != null) activePopup.dismiss();
                themeMode = selected;
                saveLocalState();
                applyThemeAndSystemBars();
                scheduleThemeSwitch();
                rerenderCurrentScreen();
                main.post(() -> showRemToast("主题已应用"));
            }), UIHelpers.weight(1));
            if (i < labels.length - 1) choices.addView(UIHelpers.space(this, UIHelpers.dp(this, 6), 1));
        }
        showSettingsSheet("选择主题", choices);
    }

    private void showHandModeDrawer() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);

        LinearLayout map = new LinearLayout(this);
        map.setOrientation(LinearLayout.HORIZONTAL);
        map.setPadding(UIHelpers.dp(this, 4), UIHelpers.dp(this, 4), UIHelpers.dp(this, 4), UIHelpers.dp(this, 4));
        map.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, UIHelpers.dp(this, 8), UIHelpers.BORDER));
        map.addView(handZone(readerLeftHand ? "下一章" : "上一章", readerLeftHand),
                new LinearLayout.LayoutParams(0, -1, 1));
        map.addView(UIHelpers.space(this, UIHelpers.dp(this, 4), 1));
        map.addView(handZone("显示控制", false), new LinearLayout.LayoutParams(0, -1, .9f));
        map.addView(UIHelpers.space(this, UIHelpers.dp(this, 4), 1));
        map.addView(handZone(readerLeftHand ? "上一章" : "下一章", !readerLeftHand),
                new LinearLayout.LayoutParams(0, -1, 1));
        content.addView(map, UIHelpers.marginTop(-1, UIHelpers.dp(this, 10), -1, UIHelpers.dp(this, 66)));

        LinearLayout choices = new LinearLayout(this);
        choices.setOrientation(LinearLayout.HORIZONTAL);
        choices.setPadding(UIHelpers.dp(this, 3), UIHelpers.dp(this, 3), UIHelpers.dp(this, 3), UIHelpers.dp(this, 3));
        choices.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        choices.addView(handChoice("左手模式", readerLeftHand, () -> applyHandMode(true)),
                new LinearLayout.LayoutParams(0, -1, 1));
        choices.addView(UIHelpers.space(this, UIHelpers.dp(this, 3), 1));
        choices.addView(handChoice("右手模式", !readerLeftHand, () -> applyHandMode(false)),
                new LinearLayout.LayoutParams(0, -1, 1));
        content.addView(choices, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8), -1, UIHelpers.dp(this, 40)));
        showSettingsSheet("阅读触控方向", content);
    }

    private void applyHandMode(boolean leftHand) {
        if (activePopup != null) activePopup.dismiss();
        readerLeftHand = leftHand;
        saveLocalState();
        rerenderCurrentScreen();
        main.post(() -> showRemToast(readerLeftHand ? "左侧下一章 · 右侧上一章" : "左侧上一章 · 右侧下一章"));
    }

    private View themeChoice(String label, int mode, boolean selected, Runnable onClick) {
        LinearLayout choice = new LinearLayout(this);
        choice.setOrientation(LinearLayout.VERTICAL);
        choice.setGravity(Gravity.CENTER);
        choice.setPadding(UIHelpers.dp(this, 4), UIHelpers.dp(this, 6), UIHelpers.dp(this, 4), UIHelpers.dp(this, 5));
        choice.setMinimumHeight(UIHelpers.dp(this, 70));
        choice.setBackground(UIHelpers.round(selected ? UIHelpers.ACCENT_SOFT : UIHelpers.BG, UIHelpers.dp(this, 7),
                selected ? UIHelpers.ACCENT : UIHelpers.BORDER));
        choice.setOnClickListener(v -> onClick.run());
        choice.addView(themeSwatch(mode), new LinearLayout.LayoutParams(UIHelpers.dp(this, 36), UIHelpers.dp(this, 20)));
        TextView labelView = UIHelpers.text(this, label, 11, selected ? UIHelpers.ACCENT : UIHelpers.TEXT3, Typeface.NORMAL);
        labelView.setGravity(Gravity.CENTER);
        choice.addView(labelView, UIHelpers.marginTop(-2, UIHelpers.dp(this, 4)));
        return choice;
    }

    private View themeSwatch(int mode) {
        FrameLayout swatch = new FrameLayout(this);
        swatch.setBackground(UIHelpers.round(mode == 2 ? Color.rgb(21, 38, 54) : Color.rgb(247, 251, 255), UIHelpers.dp(this, 4), UIHelpers.BORDER));
        if (mode == 0) {
            View dark = new View(this);
            dark.setBackgroundColor(Color.rgb(21, 38, 54));
            swatch.addView(dark, UIHelpers.frame(UIHelpers.dp(this, 18), -1, Gravity.RIGHT, 0, 0, 0, 0));
        }
        return swatch;
    }

    private View handZone(String label, boolean selected) {
        TextView zone = UIHelpers.text(this, label, 11, selected ? UIHelpers.ACCENT : UIHelpers.TEXT3, Typeface.NORMAL);
        zone.setGravity(Gravity.CENTER);
        zone.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        zone.setBackground(UIHelpers.round(selected ? UIHelpers.ACCENT_SOFT : Color.TRANSPARENT,
                UIHelpers.dp(this, 6), Color.TRANSPARENT));
        return zone;
    }

    private View handChoice(String label, boolean selected, Runnable onClick) {
        TextView choice = UIHelpers.text(this, label, 12, selected ? UIHelpers.ON_ACCENT : UIHelpers.TEXT2, Typeface.NORMAL);
        choice.setGravity(Gravity.CENTER);
        choice.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        choice.setBackground(UIHelpers.round(selected ? UIHelpers.ACCENT : Color.TRANSPARENT,
                UIHelpers.dp(this, 6), Color.TRANSPARENT));
        choice.setOnClickListener(v -> onClick.run());
        return choice;
    }

    private PopupWindow showSettingsSheet(String title, View content) {
        FrameLayout overlay = new FrameLayout(this);
        View backdrop = new View(this);
        backdrop.setBackgroundColor(Color.argb(145, 10, 24, 37));
        overlay.addView(backdrop, UIHelpers.match());

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 12), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16));
        android.graphics.drawable.GradientDrawable background = new android.graphics.drawable.GradientDrawable();
        background.setColor(UIHelpers.CARD);
        float radius = UIHelpers.dp(this, 14);
        background.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        panel.setBackground(background);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView label = UIHelpers.text(this, title, 16, UIHelpers.TEXT, Typeface.BOLD);
        label.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        header.addView(label, UIHelpers.weight(1));
        ImageView close = UIHelpers.vectorIconButton(this, R.drawable.ic_close, UIHelpers.TEXT3, 5);
        close.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, UIHelpers.dp(this, 10), Color.TRANSPARENT));
        header.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(this, 24), UIHelpers.dp(this, 24)));
        panel.addView(header, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 28)));
        panel.addView(content);

        PopupWindow popup = new PopupWindow(overlay, -1, -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
        });
        close.setOnClickListener(v -> popup.dismiss());
        backdrop.setOnClickListener(v -> popup.dismiss());
        overlay.addView(panel, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
        activePopup = popup;
        popup.showAtLocation(root, Gravity.CENTER, 0, 0);
        panel.setTranslationY(UIHelpers.dp(this, 220));
        panel.animate().translationY(0).setDuration(200).start();
        return popup;
    }

    private void showChoiceDrawer(String title, String[] labels, int selected, ChoiceAction onSelect) {
        FrameLayout overlay = new FrameLayout(this);
        View backdrop = new View(this);
        backdrop.setBackgroundColor(Color.argb(145, 10, 24, 37));
        overlay.addView(backdrop, UIHelpers.match());
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 14), UIHelpers.dp(this, 16), UIHelpers.dp(this, 20));
        android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
        bg.setColor(UIHelpers.CARD);
        float radius = UIHelpers.dp(this, 8);
        bg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        panel.setBackground(bg);
        panel.addView(UIHelpers.text(this, title, 17, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));
        PopupWindow popup = new PopupWindow(overlay, -1, -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
        });
        for (int i = 0; i < labels.length; i++) {
            final int index = i;
            TextView row = UIHelpers.text(this, labels[i] + (i == selected ? "  ✓" : ""), 15,
                    i == selected ? UIHelpers.ACCENT_DARK : UIHelpers.TEXT, i == selected ? Typeface.BOLD : Typeface.NORMAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(UIHelpers.dp(this, 4), UIHelpers.dp(this, 13), UIHelpers.dp(this, 4), UIHelpers.dp(this, 13));
            row.setOnClickListener(v -> {
                popup.dismiss();
                onSelect.run(index);
            });
            panel.addView(row);
            if (i < labels.length - 1) panel.addView(UIHelpers.divider(this));
        }
        overlay.addView(panel, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
        backdrop.setOnClickListener(v -> popup.dismiss());
        activePopup = popup;
        popup.showAtLocation(root, Gravity.CENTER, 0, 0);
        panel.setTranslationY(UIHelpers.dp(this, 260));
        panel.animate().translationY(0).setDuration(200).start();
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
        List<ComicSource> sources = enabledSearchSources();
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
        List<ComicSource> sources = enabledSearchSources();
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
            globalSearchResultsContainer.addView(emptyState(R.drawable.ic_magnifier, "这个站源暂无结果", "切换其他站源看看", "清空搜索", () -> {
                globalSearchQuery = "";
                showTab(1);
            }));
            return;
        }
        appendSearchRows(globalSearchResultsContainer, new ArrayList<>(selectedResults));
    }

    private void renderSearchHistory(LinearLayout content) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(UIHelpers.text(this, "搜索记录", 16, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        TextView clear = UIHelpers.text(this, "清空", 12, UIHelpers.TEXT2, Typeface.NORMAL);
        clear.setGravity(Gravity.CENTER);
        clear.setOnClickListener(v -> {
            globalSearchHistory.clear();
            saveLocalState();
            globalSearchQuery = "";
            showTab(1);
        });
        row.addView(clear);
        content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
        if (globalSearchHistory.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_history, "暂无搜索记录", "输入关键词后按键盘搜索", "", () -> {}));
            return;
        }
        LinearLayout chips = new LinearLayout(this);
        chips.setOrientation(LinearLayout.VERTICAL);
        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        int availableWidth = getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(this, 32);
        int gap = UIHelpers.dp(this, 6);
        int usedWidth = 0;
        for (String keyword : globalSearchHistory) {
            TextView chip = searchHistoryChip(keyword);
            chip.setOnClickListener(v -> {
                globalSearchQuery = keyword;
                startGlobalSearch(keyword);
            });
            chip.measure(
                    View.MeasureSpec.makeMeasureSpec(availableWidth, View.MeasureSpec.AT_MOST),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
            int chipWidth = Math.min(chip.getMeasuredWidth(), availableWidth);
            if (usedWidth > 0 && usedWidth + gap + chipWidth > availableWidth) {
                chips.addView(line, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 6)));
                line = new LinearLayout(this);
                line.setOrientation(LinearLayout.HORIZONTAL);
                usedWidth = 0;
            }
            LinearLayout.LayoutParams chipParams = new LinearLayout.LayoutParams(-2, UIHelpers.dp(this, 30));
            if (usedWidth > 0) chipParams.leftMargin = gap;
            line.addView(chip, chipParams);
            usedWidth += (usedWidth > 0 ? gap : 0) + chipWidth;
        }
        if (line.getChildCount() > 0) chips.addView(line);
        content.addView(chips);
    }

    private TextView searchHistoryChip(String keyword) {
        TextView chip = UIHelpers.text(this, keyword, 12, UIHelpers.ACCENT_DARK, Typeface.NORMAL);
        chip.setGravity(Gravity.CENTER);
        chip.setSingleLine(true);
        chip.setEllipsize(TextUtils.TruncateAt.END);
        chip.setMaxWidth(UIHelpers.dp(this, 180));
        chip.setPadding(UIHelpers.dp(this, 9), 0, UIHelpers.dp(this, 9), 0);
        chip.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 4), Color.TRANSPARENT));
        return chip;
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
        List<ComicSource> sources = enabledSearchSources();
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
        LinearLayout item = new LinearLayout(this);
        item.setOrientation(LinearLayout.VERTICAL);
        item.setOnClickListener(v -> {
            if (searchScroll != null) pendingSearchScrollY = searchScroll.getScrollY();
            showDetail(comic.comicId);
        });
        item.addView(coverFrame(comic.coverUrl, -1, 154), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 154)));
        TextView title = UIHelpers.text(this, comic.title, 13, UIHelpers.TEXT, Typeface.NORMAL);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setMaxLines(2);
        title.setEllipsize(TextUtils.TruncateAt.END);
        item.addView(title, UIHelpers.marginTop(-1, UIHelpers.dp(this, 6)));
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
        contentCard.addView(coverFrame(cover, 86, 116, isRetiredComic(id)));
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

    private LinearLayout sourceCard(SourceConfig config, boolean enabled, Runnable toggle) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(UIHelpers.dp(this, 9), UIHelpers.dp(this, 6), UIHelpers.dp(this, 9), UIHelpers.dp(this, 6));
        card.setMinimumHeight(UIHelpers.dp(this, 45));
        card.setAlpha(enabled ? 1f : .58f);
        card.setClickable(false);
        card.setFocusable(false);

        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28));
        logoParams.setMargins(0, 0, UIHelpers.dp(this, 9), 0);
        card.addView(sourceLogo(config.name), logoParams);
        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        LinearLayout titleRow = new LinearLayout(this);
        titleRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView sourceTitle = UIHelpers.text(this, config.name, 14, UIHelpers.TEXT, Typeface.NORMAL);
        sourceTitle.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        titleRow.addView(sourceTitle);
        if (requiresVpn(config.id)) {
            TextView vpn = UIHelpers.text(this, "VPN", 10, UIHelpers.ACCENT, Typeface.BOLD);
            LinearLayout.LayoutParams vpnParams = new LinearLayout.LayoutParams(-2, -2);
            vpnParams.leftMargin = UIHelpers.dp(this, 7);
            titleRow.addView(vpn, vpnParams);
        }
        info.addView(titleRow);
        card.addView(info, UIHelpers.weight(1));
        if (supportsManualVerification(config.id)) {
            TextView verify = UIHelpers.text(this, "验证", 12, UIHelpers.ACCENT, Typeface.BOLD);
            verify.setGravity(Gravity.CENTER);
            verify.setMinWidth(UIHelpers.dp(this, 44));
            verify.setMinHeight(UIHelpers.dp(this, 32));
            verify.setContentDescription("验证" + config.name);
            verify.setOnClickListener(v -> verifyProtectedSource(config.id));
            LinearLayout.LayoutParams verifyParams = new LinearLayout.LayoutParams(-2, UIHelpers.dp(this, 32));
            verifyParams.rightMargin = UIHelpers.dp(this, 4);
            card.addView(verify, verifyParams);
        }
        card.addView(sourceSwitch(enabled, toggle), new LinearLayout.LayoutParams(UIHelpers.dp(this, 42), UIHelpers.dp(this, 26)));

        return card;
    }

    static boolean requiresVpn(String sourceId) {
        return "mh18".equals(sourceId) || "jmcomic".equals(sourceId)
                || "hiperdex".equals(sourceId) || "hanman18".equals(sourceId)
                || "manhuagui".equals(sourceId);
    }

    static boolean supportsManualVerification(String sourceId) {
        return "mh18".equals(sourceId) || "jmcomic".equals(sourceId);
    }

    static boolean categoriesFollowInitialList(String sourceId) {
        return "jmcomic".equals(sourceId);
    }

    private void verifyProtectedSource(String sourceId) {
        if (!supportsManualVerification(sourceId) || !verifyingProtectedSourceIds.add(sourceId)) return;
        ComicSource client = sourceForId(sourceId);
        showRemToast(client.name() + " 正在验证");
        sourceHealthIo.submit(() -> {
            String resultMessage;
            try {
                if ("jmcomic".equals(sourceId)) {
                    jmcomicClient.verifyAccess();
                    resultMessage = client.name() + " 验证完成";
                } else {
                    resultMessage = client.name() + (!client.latest(1).isEmpty()
                            ? " 验证完成" : " 验证失败");
                }
            } catch (Exception error) {
                String reason = clean(error.getMessage(), "连接失败");
                resultMessage = client.name() + (reason.contains("超时")
                        ? " 验证超时" : reason.contains("页面") || reason.contains("解析")
                        ? " 页面验证失败" : " 连接失败，请检查 VPN");
            }
            String message = resultMessage;
            postMainIfAlive(() -> {
                verifyingProtectedSourceIds.remove(sourceId);
                showRemToast(message);
            });
        });
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
                        refreshedComicIds.add(comicId);
                        summaries.put(comicId, loaded.summary);
                        persistComicCachesAsync();
                        showDetail(comicId);
                    });
                } catch (Exception error) {
                    main.post(() -> {
                        if (!isCurrentLoading(loadingGeneration)) return;
                        pageLoading = false;
                        pageLoadingBackAction = null;
                        showError("详情加载失败", error, () -> showDetail(comicId));
                    });
                }
            }));
            return;
        }

        root.removeAllViews();
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        scroll.setBackgroundColor(UIHelpers.CARD);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());
        root.addView(scroll, UIHelpers.match());

        FrameLayout hero = new FrameLayout(this);
        hero.setBackgroundColor(UIHelpers.SURFACE);
        boolean cacheOnly = isRetiredComic(detail.summary.comicId);
        addDetailHeroCover(hero, detail.summary.coverUrl, cacheOnly);
        LinearLayout.LayoutParams heroParams = new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, DETAIL_HERO_DP));
        content.addView(hero, heroParams);
        installDetailHeroStretch(scroll, hero, heroParams);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 82));
        body.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(-1, -2);
        bodyParams.topMargin = -UIHelpers.dp(this, 10);
        content.addView(body, bodyParams);

        LinearLayout titleRow = new LinearLayout(this);
        titleRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView detailTitle = UIHelpers.text(this, detail.summary.title, 20, UIHelpers.TEXT, Typeface.BOLD);
        detailTitle.setMaxLines(2);
        detailTitle.setEllipsize(TextUtils.TruncateAt.END);
        titleRow.addView(detailTitle, UIHelpers.weight(1));
        TextView source = UIHelpers.text(this, sourceNameForId(detail.summary.sourceId), 11, UIHelpers.ACCENT, Typeface.NORMAL);
        source.setSingleLine(true);
        source.setPadding(UIHelpers.dp(this, 7), UIHelpers.dp(this, 3), UIHelpers.dp(this, 7), UIHelpers.dp(this, 3));
        source.setBackground(UIHelpers.round(UIHelpers.ACCENT_LIGHT, UIHelpers.dp(this, 5), UIHelpers.BORDER));
        titleRow.addView(source);
        body.addView(titleRow);

        LinearLayout byline = new LinearLayout(this);
        byline.setGravity(Gravity.CENTER_VERTICAL);
        View dot = new View(this);
        dot.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(this, 3), Color.TRANSPARENT));
        byline.addView(dot, new LinearLayout.LayoutParams(UIHelpers.dp(this, 6), UIHelpers.dp(this, 6)));
        TextView meta = UIHelpers.text(this, clean(detail.status, "未知状态") + " · " + clean(detail.author, "未知作者"), 12, UIHelpers.TEXT2, Typeface.NORMAL);
        LinearLayout.LayoutParams metaParams = new LinearLayout.LayoutParams(0, -2, 1);
        metaParams.leftMargin = UIHelpers.dp(this, 7);
        byline.addView(meta, metaParams);
        body.addView(byline, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8)));
        if (!detail.summary.tags.isEmpty()) {
            body.addView(detailTagRow(detail.summary.tags), UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));
        }
        TextView summary = UIHelpers.text(this, clean(detail.description, "暂无简介"), 13, UIHelpers.TEXT2, Typeface.NORMAL);
        summary.setLineSpacing(0f, 1.2f);
        body.addView(summary, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));

        body.addView(chapterEntry(detail), UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 8), UIHelpers.dp(this, 16), UIHelpers.dp(this, 10));
        actions.setBackgroundColor(UIHelpers.CARD);
        ImageView fav = new ImageView(this);
        fav.setScaleType(ImageView.ScaleType.FIT_CENTER);
        fav.setImageResource(favorites.contains(detail.summary.comicId)
                ? R.drawable.rem_in_bookshelf : R.drawable.rem_not_in_bookshelf);
        fav.setContentDescription(favorites.contains(detail.summary.comicId) ? "取消收藏" : "收藏");
        fav.setOnClickListener(v -> toggleFavorite(detail));
        actions.addView(fav, new LinearLayout.LayoutParams(UIHelpers.dp(this, 44), UIHelpers.dp(this, 44)));
        actions.addView(UIHelpers.space(this, UIHelpers.dp(this, 8), 1));
        actions.addView(detailReadButton(detail), new LinearLayout.LayoutParams(0, UIHelpers.dp(this, 44), 1));
        root.addView(actions, UIHelpers.frame(-1, UIHelpers.dp(this, 62), Gravity.BOTTOM, 0, 0, 0, 0));
        refreshCachedComicOnce(detail);
    }

    private void refreshCachedComicOnce(ComicModels.ComicDetail detail) {
        String comicId = detail.summary.comicId;
        if (refreshedComicIds.contains(comicId) || refreshingComicIds.contains(comicId)) return;
        refreshingComicIds.add(comicId);
        ComicSource client = sourceForDetail(detail);
        track(detailIo.submit(() -> {
            try {
                ComicModels.ComicDetail freshDetail = client.detail(comicId);
                ComicModels.ComicDetail loaded = mergeRefreshedDetail(detail, freshDetail);
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
        }));
    }

    static ComicModels.ComicDetail mergeRefreshedDetail(
            ComicModels.ComicDetail cached, ComicModels.ComicDetail fresh) {
        List<ComicModels.Chapter> resolved = fresh.chapters.isEmpty()
                ? new ArrayList<>(cached.chapters) : new ArrayList<>(fresh.chapters);
        return new ComicModels.ComicDetail(fresh.summary, fresh.author, fresh.status,
                fresh.description, fresh.latestChapter, resolved);
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
        if (loaded != null && TextUtils.equals(activeDetailId, comicId) && !readerVisible
                && (activePopup == null || !activePopup.isShowing())) showDetail(comicId);
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
                        appendErrorLog("章节加载失败", error);
                        showReaderError(detail, "加载失败了", "阅读位置已经保留", () -> showReader(detail, chapterIndex));
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
        shell.addView(readerToolbar(detail), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 43)));
        String savedMessage = readerPositions.containsKey(readerPositionKey(detail.summary.comicId,
                detail.chapters.get(readerChapterIndex))) ? "阅读位置已保存" : "蕾姆正在整理页面";
        shell.addView(readerState(R.drawable.rem_loading, "正在加载第 " + (readerChapterIndex + 1) + " 话",
                savedMessage, "", null, true), new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(readerProgressBar(readerChapterIndex + 1, Math.max(1, detail.chapters.size())), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 2)));
    }

    private void showReaderError(ComicModels.ComicDetail detail, String title, String desc, Runnable retry) {
        root.removeAllViews();
        readerVisible = true;
        applyReaderSystemBars();
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());
        shell.addView(readerToolbar(detail), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 43)));
        shell.addView(readerState(R.drawable.rem_error, title, desc, "重试", retry, false), new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(readerProgressBar(readerChapterIndex + 1, Math.max(1, detail.chapters.size())), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 2)));
    }

    private LinearLayout readerToolbar(ComicModels.ComicDetail detail) {
        LinearLayout top = new LinearLayout(this);
        top.setPadding(UIHelpers.dp(this, 12), 0, UIHelpers.dp(this, 12), 0);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setBackgroundColor(UIHelpers.DARK_BAR);
        TextView name = UIHelpers.text(this, detail.chapters.get(readerChapterIndex).title, 12,
                UIHelpers.READER_TEXT, Typeface.NORMAL);
        name.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        name.setGravity(Gravity.CENTER_VERTICAL);
        name.setIncludeFontPadding(false);
        name.setSingleLine(true);
        name.setEllipsize(TextUtils.TruncateAt.END);
        top.addView(name, UIHelpers.weight(1));
        ImageView toc = UIHelpers.vectorIconButton(this, R.drawable.ic_chapter_list, UIHelpers.READER_TEXT, 4);
        toc.setContentDescription("章节目录");
        toc.setClickable(true);
        toc.setFocusable(true);
        toc.setOnClickListener(v -> showChapterDrawer(detail));
        top.addView(toc, new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28)));
        return top;
    }

    private void renderReader(ComicModels.ComicDetail detail, ComicModels.ChapterPage page) {
        root.removeAllViews();
        readerVisible = true;
        readerTopBar = null;
        readerBottomBar = null;
        readerProgressView = null;
        applyReaderSystemBars(true);
        FrameLayout shell = new FrameLayout(this);
        shell.setBackgroundColor(UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());

        LinearLayout top = readerToolbar(detail);

        ComicModels.Chapter activeChapter = detail.chapters.get(readerChapterIndex);
        int generation = readerGeneration;
        String comicId = detail.summary.comicId;
        String chapterUrl = activeChapter.url;
        boolean cacheOnly = isRetiredComic(detail.summary.comicId);
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
        final TextView[] readerCount = {null};
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
                image.setImageResource(R.drawable.rem_loading);
                image.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                image.setTag(imageUrl);
                image.setLayoutParams(new AbsListView.LayoutParams(-1, placeholderHeight));
                Future<?> future = loadReaderImage(image, imageUrl, chapterUrl, generation, comicId,
                        list, restoringPosition, savedPosition, cacheOnly);
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
                if (readerCount[0] != null && totalItemCount > 0) {
                    int currentPage = Math.max(1, Math.min(totalItemCount, firstVisibleItem + 1));
                    int percent = Math.max(1, Math.min(100, Math.round(currentPage * 100f / totalItemCount)));
                    readerCount[0].setText(currentPage + " / " + totalItemCount + " 张 · 本章 " + percent + "%");
                }
                if (visibleItemCount > 0) {
                    prefetchReaderImages(imageUrls, firstVisibleItem + visibleItemCount,
                            chapterUrl, generation, comicId, cacheOnly);
                }
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
        list.post(() -> prefetchReaderImages(imageUrls,
                Math.max(0, list.getLastVisiblePosition() + 1), chapterUrl, generation, comicId, cacheOnly));
        FrameLayout readerContent = new FrameLayout(this);
        readerContent.addView(list, UIHelpers.match());
        View empty = readerState(R.drawable.rem_error, "这一章没有解析出来", "再试一次吧", "重试",
                () -> showReader(detail, readerChapterIndex), false);
        readerContent.addView(empty, UIHelpers.match());
        list.setEmptyView(empty);
        shell.addView(readerContent, UIHelpers.match());

        View chapterProgress = readerProgressBar(readerChapterIndex + 1, detail.chapters.size());
        readerProgressView = chapterProgress;
        chapterProgress.setTranslationY(readerFullscreen ? 0f : -readerChromeBottomOffset());
        shell.addView(chapterProgress, new FrameLayout.LayoutParams(-1, UIHelpers.dp(this, 2), Gravity.BOTTOM));

        FrameLayout.LayoutParams topParams = new FrameLayout.LayoutParams(-1, UIHelpers.dp(this, 43), Gravity.TOP);
        topParams.topMargin = systemBarInset("status_bar_height");
        shell.addView(top, topParams);
        readerTopBar = top;
        prepareReaderChrome(top, true);

        LinearLayout bottom = new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        bottom.setPadding(UIHelpers.dp(this, 12), 0, UIHelpers.dp(this, 12), 0);
        bottom.setBackgroundColor(UIHelpers.DARK_BAR);

        // 全面手势模式：底部仅显示页数，翻章靠左右点按
        TextView count = UIHelpers.text(this, "1 / " + page.imageUrls.size() + " 张 · 本章 1%", 11, UIHelpers.READER_TEXT, Typeface.NORMAL);
        count.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        count.setGravity(Gravity.CENTER);
        count.setIncludeFontPadding(false);
        readerCount[0] = count;
        bottom.addView(count, new LinearLayout.LayoutParams(-1, -2));
        FrameLayout.LayoutParams bottomParams = new FrameLayout.LayoutParams(-1, UIHelpers.dp(this, 36), Gravity.BOTTOM);
        bottomParams.bottomMargin = systemBarInset("navigation_bar_height");
        shell.addView(bottom, bottomParams);
        readerBottomBar = bottom;
        prepareReaderChrome(bottom, false);
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
        applyReaderSystemBars(true);
        animateReaderChrome(readerTopBar, true);
        animateReaderChrome(readerBottomBar, false);
        if (readerProgressView != null) {
            readerProgressView.animate().cancel();
            readerProgressView.animate()
                    .translationY(readerFullscreen ? 0f : -readerChromeBottomOffset())
                    .setDuration(READER_CHROME_ANIM_MS)
                    .start();
        }
    }

    private void prepareReaderChrome(View view, boolean top) {
        float shift = UIHelpers.dp(this, READER_CHROME_SHIFT_DP) * (top ? -1f : 1f);
        view.setAlpha(readerFullscreen ? 0f : 1f);
        view.setTranslationY(readerFullscreen ? shift : 0f);
        view.setVisibility(readerFullscreen ? View.INVISIBLE : View.VISIBLE);
    }

    private void animateReaderChrome(View view, boolean top) {
        if (view == null) return;
        boolean hide = readerFullscreen;
        float shift = UIHelpers.dp(this, READER_CHROME_SHIFT_DP) * (top ? -1f : 1f);
        view.animate().cancel();
        if (!hide) view.setVisibility(View.VISIBLE);
        view.animate()
                .alpha(hide ? 0f : 1f)
                .translationY(hide ? shift : 0f)
                .setDuration(READER_CHROME_ANIM_MS)
                .withEndAction(() -> {
                    if (readerFullscreen) view.setVisibility(View.INVISIBLE);
                })
                .start();
    }

    private int readerChromeBottomOffset() {
        return systemBarInset("navigation_bar_height") + UIHelpers.dp(this, 36);
    }

    private int systemBarInset(String name) {
        int resource = getResources().getIdentifier(name, "dimen", "android");
        return resource == 0 ? 0 : getResources().getDimensionPixelSize(resource);
    }

    private void runSearch(String keyword) {
        resetSearchPaging();
        loadSearchPage(keyword, 1, false, false);
    }

    private final class PullRefreshScrollView extends ScrollView {
        private float interceptDownX;
        private float interceptDownY;

        PullRefreshScrollView(Context context) {
            super(context);
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent event) {
            handleSearchPullRefresh(this, event);
            return super.dispatchTouchEvent(event);
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent event) {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                interceptDownX = event.getX();
                interceptDownY = event.getY();
            } else if (event.getActionMasked() == MotionEvent.ACTION_MOVE && searchPullTracking) {
                float dx = Math.abs(event.getX() - interceptDownX);
                float dy = event.getY() - interceptDownY;
                if (dy > ViewConfiguration.get(PullRefreshScrollView.this.getContext()).getScaledTouchSlop()
                        && dy > dx) return true;
            }
            return super.onInterceptTouchEvent(event);
        }
    }

    private void handleSearchPullRefresh(ScrollView scroll, MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                searchPullTracking = scroll.getScrollY() == 0 && !searchLoading
                        && !searchAppending && !searchRefreshing && currentTab == 1;
                searchPullStartY = searchPullTracking ? event.getY() : -1f;
                searchPullDistance = 0f;
                break;
            case MotionEvent.ACTION_MOVE:
                if (!searchPullTracking) break;
                if (scroll.getScrollY() != 0 || event.getY() <= searchPullStartY) {
                    searchPullTracking = false;
                    searchPullDistance = 0f;
                    scroll.setTranslationY(0f);
                    if (searchRefreshIndicator != null) searchRefreshIndicator.setVisibility(View.GONE);
                    break;
                }
                searchPullDistance = Math.min(UIHelpers.dp(this, 120),
                        (event.getY() - searchPullStartY) * 0.5f);
                scroll.setTranslationY(searchPullDistance);
                if (searchRefreshIndicator != null) {
                    searchRefreshIndicator.setVisibility(View.VISIBLE);
                    searchRefreshIndicator.setAlpha(Math.min(1f,
                            (event.getY() - searchPullStartY)
                                    / UIHelpers.dp(this, SEARCH_PULL_REFRESH_DP)));
                }
                break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                boolean trigger = event.getActionMasked() == MotionEvent.ACTION_UP
                        && searchPullTracking
                        && event.getY() - searchPullStartY
                                >= UIHelpers.dp(this, SEARCH_PULL_REFRESH_DP);
                searchPullTracking = false;
                searchPullStartY = -1f;
                searchPullDistance = 0f;
                scroll.animate().translationY(0f).setDuration(160L).start();
                if (trigger) {
                    refreshCurrentSearch();
                } else if (!searchRefreshing && searchRefreshIndicator != null) {
                    searchRefreshIndicator.setVisibility(View.GONE);
                }
                break;
            default:
                break;
        }
    }

    private void refreshCurrentSearch() {
        if (searchLoading || searchAppending || searchRefreshing || currentTab != 1) return;
        String keyword = searchQuery.trim();
        boolean categoryMode = TextUtils.isEmpty(keyword);
        loadSearchPage(keyword, 1, false, categoryMode, true);
    }

    private void finishSearchPullRefresh() {
        searchRefreshing = false;
        searchPullTracking = false;
        searchPullStartY = -1f;
        searchPullDistance = 0f;
        if (searchScroll != null) {
            searchScroll.animate().cancel();
            searchScroll.setTranslationY(0f);
        }
        if (searchRefreshIndicator != null) {
            searchRefreshIndicator.setAlpha(1f);
            searchRefreshIndicator.setVisibility(View.GONE);
        }
    }

    private void loadSearchPage(String keyword, int page, boolean append, boolean categoryMode) {
        loadSearchPage(keyword, page, append, categoryMode, false);
    }

    private void loadSearchPage(String keyword, int page, boolean append, boolean categoryMode, boolean pullRefresh) {
        ComicSource requestClient = selectedSource();
        if (requestClient == null) {
            if (pullRefresh) finishSearchPullRefresh();
            return;
        }
        if (!categoryMode && !requestClient.supportsSearch()) {
            searchLoading = false;
            searchAppending = false;
            if (pullRefresh) finishSearchPullRefresh();
            showRemToast(requestClient.name() + "暂不支持搜索");
            return;
        }
        String requestSourceId = requestClient.id();
        Map<String, String> requestFilters = new LinkedHashMap<>(selectedFilters);
        int generation = ++searchGeneration;
        clearSearchAppendFailure();
        if (pullRefresh) {
            searchRefreshing = true;
            removeSearchPagingFooter();
        } else if (append) {
            searchAppending = true;
            if (currentTab == 1 && searchResultsContent != null) renderSearchPagingFooter(searchResultsContent);
        } else {
            searchLoading = true;
        }
        if (currentTab == 1 && !append) {
            if (!pullRefresh) showTab(1, false);
        }
        track(searchIo.submit(() -> {
            try {
                List<ComicModels.ComicSummary> list = categoryMode
                        ? requestClient.category(requestFilters, page)
                        : requestClient.search(keyword == null ? "" : keyword.trim(), page);
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    if (!TextUtils.equals(requestSourceId, selectedSourceId)) return;
                    boolean loadCategoriesAfterList = categoriesFollowInitialList(requestSourceId)
                            && categoryMode && page == 1 && !append && sourceFilterGroups.isEmpty();
                    List<ComicModels.ComicSummary> additions = append
                            ? newSearchItems(searchResults, list) : new ArrayList<>(list);
                    if (!append) searchResults.clear();
                    searchResults.addAll(additions);
                    for (ComicModels.ComicSummary item : additions) summaries.put(item.comicId, item);
                    searchPage = page;
                    searchHasMore = !list.isEmpty() && (!append || !additions.isEmpty());
                    clearSearchAppendFailure();
                    searchLoading = false;
                    searchAppending = false;
                    if (pullRefresh) finishSearchPullRefresh();
                    if (currentTab == 1) {
                        if (append && searchResultsContent != null) {
                            appendSearchResults(additions);
                        } else {
                            showTab(1, false);
                        }
                    }
                    if (loadCategoriesAfterList) loadSourceCategories();
                    persistComicCachesAsync();
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    if (!TextUtils.equals(requestSourceId, selectedSourceId)) return;
                    if (isExpectedTaskCancellation(error)) {
                        searchLoading = false;
                        searchAppending = false;
                        if (pullRefresh) finishSearchPullRefresh();
                        return;
                    }
                    searchLoading = false;
                    searchAppending = false;
                    if (pullRefresh) {
                        finishSearchPullRefresh();
                        appendErrorLog("\u641c\u7d22\u5237\u65b0\u5931\u8d25", error);
                        if (currentTab == 1 && searchResultsContent != null) {
                            renderSearchPagingFooter(searchResultsContent);
                        }
                        showToast("\u5237\u65b0\u5931\u8d25");
                    } else if (append) {
                        appendErrorLog("搜索分页加载失败", error);
                        searchAppendFailed = true;
                        searchAppendFailedKeyword = keyword;
                        searchAppendFailedPage = page;
                        searchAppendFailedCategoryMode = categoryMode;
                        searchAppendFailedGeneration = generation;
                        searchAppendFailedContent = searchResultsContent;
                        if (currentTab == 1 && searchResultsContent != null) renderSearchPagingFooter(searchResultsContent);
                        showToast("加载更多失败");
                    } else {
                        showError("加载失败", error, () -> loadSearchPage(keyword, page, false, categoryMode));
                    }
                });
            }
        }));
    }

    private void loadNextSearchPage() {
        if (searchLoading || searchAppending || searchRefreshing || searchAppendFailed
                || !searchHasMore || currentTab != 1 || standaloneSearchVisible) return;
        loadSearchPage(searchQuery, searchPage + 1, true, TextUtils.isEmpty(searchQuery.trim()));
    }

    private void resetSearchPaging() {
        finishSearchPullRefresh();
        searchPage = 1;
        searchHasMore = true;
        clearSearchAppendFailure();
        searchAppending = false;
    }

    private void clearSearchAppendFailure() {
        searchAppendFailed = false;
        searchAppendFailedKeyword = "";
        searchAppendFailedPage = -1;
        searchAppendFailedCategoryMode = false;
        searchAppendFailedGeneration = -1;
        searchAppendFailedContent = null;
    }

    private void startGlobalSearch(String keyword) {
        globalSearchQuery = keyword == null ? "" : keyword.trim();
        globalSearchResults.clear();
        globalSearchShownIds.clear();
        globalSearchResultsBySource.clear();
        globalSearchShownIdsBySource.clear();
        globalSearchFailedSourceIds.clear();
        globalSearchCompletedSourceIds.clear();
        List<ComicSource> clients = enabledSearchSources();
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
        showTab(1);
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
        final List<ComicSource> clients = enabledSearchSources();
        globalSearchTotalSources = clients.size();
        globalSearchCompletedSources = 0;
        globalSearchFailedSources = 0;
        updateGlobalSearchStatus();

        // 边界：没有启用的站源
        if (clients.isEmpty()) {
            main.post(() -> {
                if (generation != globalSearchGeneration) return;
                globalSearchLoading = false;
                if (currentTab == 1 && globalSearchMode) showTab(1, false);
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
            // 受保护站源给浏览器验证留足时间，其他站源保持快速超时。
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
            }, globalSearchTimeoutSeconds(client.id()), TimeUnit.SECONDS);
        }
    }

    static long globalSearchTimeoutSeconds(String sourceId) {
        return "mh18".equals(sourceId) || "jmcomic".equals(sourceId) ? 185L : 10L;
    }

    /** 单个站源完成时的统一收尾（计数、状态、关闭 loading） */
    private void onGlobalSearchSourceDone(int generation) {
        updateGlobalSearchStatus();
        if (globalSearchCompletedSources >= globalSearchTotalSources) {
            globalSearchLoading = false;
            persistComicCachesAsync();
            updateGlobalSearchStatus();
            // 全部完成时若列表仍为空，刷新以显示空状态（移除 loading 动画）
            if (currentTab == 1 && globalSearchMode && globalSearchAllResultsEmpty()) {
                refreshGlobalSearchTabs();
                refreshGlobalSearchResults();
            }
        }
    }

    private void refreshGlobalSearchSourceState(String sourceId) {
        if (currentTab != 1 || !globalSearchMode) return;
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
        if (mh18Client.id().equals(sourceId)) return mh18Client.name();
        if (jmcomicClient.id().equals(sourceId)) return jmcomicClient.name();
        if (mkzhanClient.id().equals(sourceId)) return mkzhanClient.name();
        if (hiperdexClient.id().equals(sourceId)) return hiperdexClient.name();
        if (manhuaguiClient.id().equals(sourceId)) return manhuaguiClient.name();
        if (hanman18Client.id().equals(sourceId)) return hanman18Client.name();
        if (d5d6Client.id().equals(sourceId)) return d5d6Client.name();
        if (manbenClient.id().equals(sourceId)) return manbenClient.name();
        if (manhuazhanClient.id().equals(sourceId)) return manhuazhanClient.name();
        if (bbyinClient.id().equals(sourceId)) return bbyinClient.name();
        if (antbywClient.id().equals(sourceId)) return antbywClient.name();
        if (cuimhClient.id().equals(sourceId)) return cuimhClient.name();
        for (ComicModels.Source item : customSources) {
            if (item.id.equals(sourceId)) return item.name;
        }
        return clean(sourceId, "未知来源");
    }

    private ComicSource selectedSource() {
        if (sourceClient.id().equals(selectedSourceId) && sourceEnabled) return sourceClient;
        if (aikanClient.id().equals(selectedSourceId) && aikanEnabled) return aikanClient;
        if (gmhClient.id().equals(selectedSourceId) && gmhEnabled) return gmhClient;
        if (mh18Client.id().equals(selectedSourceId) && mh18Enabled) return mh18Client;
        if (jmcomicClient.id().equals(selectedSourceId) && jmcomicEnabled) return jmcomicClient;
        if (mkzhanClient.id().equals(selectedSourceId) && mkzhanEnabled) return mkzhanClient;
        if (hiperdexClient.id().equals(selectedSourceId) && hiperdexEnabled) return hiperdexClient;
        if (manhuaguiClient.id().equals(selectedSourceId) && manhuaguiEnabled) return manhuaguiClient;
        if (hanman18Client.id().equals(selectedSourceId) && hanman18Enabled) return hanman18Client;
        if (d5d6Client.id().equals(selectedSourceId) && d5d6Enabled) return d5d6Client;
        if (manbenClient.id().equals(selectedSourceId) && manbenEnabled) return manbenClient;
        if (manhuazhanClient.id().equals(selectedSourceId) && manhuazhanEnabled) return manhuazhanClient;
        if (bbyinClient.id().equals(selectedSourceId) && bbyinEnabled) return bbyinClient;
        if (antbywClient.id().equals(selectedSourceId) && antbywEnabled) return antbywClient;
        if (cuimhClient.id().equals(selectedSourceId) && cuimhEnabled) return cuimhClient;
        List<ComicSource> enabled = enabledBuiltinSources();
        if (enabled.isEmpty()) return null;
        selectedSourceId = enabled.get(0).id();
        sourceCategoriesFailed = false;
        return enabled.get(0);
    }

    private List<ComicSource> enabledBuiltinSources() {
        List<ComicSource> sources = new ArrayList<>();
        if (sourceEnabled) sources.add(sourceClient);
        if (aikanEnabled) sources.add(aikanClient);
        if (gmhEnabled) sources.add(gmhClient);
        if (mh18Enabled) sources.add(mh18Client);
        if (jmcomicEnabled) sources.add(jmcomicClient);
        if (mkzhanEnabled) sources.add(mkzhanClient);
        if (hiperdexEnabled) sources.add(hiperdexClient);
        if (manhuaguiEnabled) sources.add(manhuaguiClient);
        if (hanman18Enabled) sources.add(hanman18Client);
        if (d5d6Enabled) sources.add(d5d6Client);
        if (manbenEnabled) sources.add(manbenClient);
        if (manhuazhanEnabled) sources.add(manhuazhanClient);
        if (bbyinEnabled) sources.add(bbyinClient);
        if (antbywEnabled) sources.add(antbywClient);
        if (cuimhEnabled) sources.add(cuimhClient);
        return sources;
    }

    static boolean shouldLoadNextSearchPage(int scrollY, int oldScrollY, int viewportHeight,
                                            int contentHeight, int threshold) {
        return scrollY > oldScrollY && scrollY > 0
                && scrollY + viewportHeight >= contentHeight - threshold;
    }

    static List<ComicModels.ComicSummary> newSearchItems(
            List<ComicModels.ComicSummary> existing, List<ComicModels.ComicSummary> page) {
        Set<String> seen = new HashSet<>();
        for (ComicModels.ComicSummary item : existing) seen.add(item.comicId);
        List<ComicModels.ComicSummary> additions = new ArrayList<>();
        for (ComicModels.ComicSummary item : page) {
            if (seen.add(item.comicId)) additions.add(item);
        }
        return additions;
    }

    private List<ComicSource> enabledSearchSources() {
        List<ComicSource> sources = new ArrayList<>();
        for (ComicSource source : enabledBuiltinSources()) {
            if (source.supportsSearch()) sources.add(source);
        }
        return sources;
    }

    private ComicSource sourceForComicId(String comicId) {
        if (comicId != null && comicId.startsWith(mhua5Client.id() + ":")) return mhua5Client;
        ComicModels.ComicSummary summary = summaries.get(comicId);
        if (summary != null) return sourceForId(summary.sourceId);
        if (comicId != null && comicId.startsWith(aikanClient.id() + ":")) return aikanClient;
        if (comicId != null && comicId.startsWith(gmhClient.id() + ":")) return gmhClient;
        if (comicId != null && comicId.startsWith(mh18Client.id() + ":")) return mh18Client;
        if (comicId != null && comicId.startsWith(jmcomicClient.id() + ":")) return jmcomicClient;
        if (comicId != null && comicId.startsWith(mkzhanClient.id() + ":")) return mkzhanClient;
        if (comicId != null && comicId.startsWith(hiperdexClient.id() + ":")) return hiperdexClient;
        if (comicId != null && comicId.startsWith(manhuaguiClient.id() + ":")) return manhuaguiClient;
        if (comicId != null && comicId.startsWith(hanman18Client.id() + ":")) return hanman18Client;
        if (comicId != null && comicId.startsWith(d5d6Client.id() + ":")) return d5d6Client;
        if (comicId != null && comicId.startsWith(manbenClient.id() + ":")) return manbenClient;
        if (comicId != null && comicId.startsWith(manhuazhanClient.id() + ":")) return manhuazhanClient;
        if (comicId != null && comicId.startsWith(bbyinClient.id() + ":")) return bbyinClient;
        if (comicId != null && comicId.startsWith(antbywClient.id() + ":")) return antbywClient;
        if (comicId != null && comicId.startsWith(cuimhClient.id() + ":")) return cuimhClient;
        return sourceClient;
    }

    private ComicSource sourceForDetail(ComicModels.ComicDetail detail) {
        if (detail == null || detail.summary == null) return sourceClient;
        if (isRetiredComic(detail.summary.comicId)) return mhua5Client;
        return sourceForId(detail.summary.sourceId);
    }

    private ComicSource sourceForId(String sourceId) {
        if (mhua5Client.id().equals(sourceId)) return mhua5Client;
        if (aikanClient.id().equals(sourceId)) return aikanClient;
        if (gmhClient.id().equals(sourceId)) return gmhClient;
        if (mh18Client.id().equals(sourceId)) return mh18Client;
        if (jmcomicClient.id().equals(sourceId)) return jmcomicClient;
        if (mkzhanClient.id().equals(sourceId)) return mkzhanClient;
        if (hiperdexClient.id().equals(sourceId)) return hiperdexClient;
        if (manhuaguiClient.id().equals(sourceId)) return manhuaguiClient;
        if (hanman18Client.id().equals(sourceId)) return hanman18Client;
        if (d5d6Client.id().equals(sourceId)) return d5d6Client;
        if (manbenClient.id().equals(sourceId)) return manbenClient;
        if (manhuazhanClient.id().equals(sourceId)) return manhuazhanClient;
        if (bbyinClient.id().equals(sourceId)) return bbyinClient;
        if (antbywClient.id().equals(sourceId)) return antbywClient;
        if (cuimhClient.id().equals(sourceId)) return cuimhClient;
        return sourceClient;
    }

    private boolean isRetiredSource(String sourceId) {
        return mhua5Client != null && mhua5Client.id().equals(sourceId);
    }

    private boolean isRetiredComic(String comicId) {
        ComicModels.ComicDetail detail = details.get(comicId);
        ComicModels.ComicSummary summary = summaries.get(comicId);
        String sourceId = detail != null && detail.summary != null
                ? detail.summary.sourceId
                : summary == null ? "" : summary.sourceId;
        return isRetiredSource(sourceId)
                || (mhua5Client != null && comicId != null && comicId.startsWith(mhua5Client.id() + ":"));
    }

    private void loadDefaultCategory() {
        resetSearchPaging();
        loadSearchPage("", 1, false, true);
    }

    private void scheduleDefaultSearchLoad() {
        if (currentTab != 1 || selectedSource() == null || !searchResults.isEmpty()
                || !TextUtils.isEmpty(searchQuery.trim()) || searchLoading) return;
        int generation = searchGeneration;
        searchLoading = true;
        main.post(() -> {
            if (generation != searchGeneration) return;
            if (currentTab != 1 || !searchResults.isEmpty() || !TextUtils.isEmpty(searchQuery.trim())) {
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
        sourceCategoriesFailed = false;
        int generation = ++categoryGeneration;
        String sourceId = client.id();
        track(searchIo.submit(() -> {
            try {
                List<ComicModels.FilterGroup> list = client.filterGroups();
                main.post(() -> {
                    if (generation != categoryGeneration || !TextUtils.equals(sourceId, selectedSourceId)) return;
                    sourceCategoriesFailed = false;
                    sourceFilterGroups.clear();
                    sourceFilterGroups.addAll(list);
                    normalizeSelectedFilters();
                    if (filterDrawerAction != null) {
                        filterDrawerAction.run();
                    } else if (currentTab == 1) {
                        showTab(1, false);
                    }
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (generation != categoryGeneration || !TextUtils.equals(sourceId, selectedSourceId)) return;
                    sourceCategoriesFailed = true;
                    appendErrorLog("分类加载失败", error);
                    if (currentTab == 1) showTab(1, false);
                });
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
            showReaderBoundaryHint(delta > 0 ? "已经是最后一章" : "已经是第一章");
            return;
        }
        showReader(detail, next);
    }

    private void showReaderBoundaryHint(String message) {
        showReaderHint(R.drawable.rem_reader_boundary, message, "轻轻翻到边界啦");
    }

    private void showReaderResumeHint(int savedPosition) {
        int percent = Math.max(1, Math.min(100, Math.round(savedPosition * 100f / READER_POSITION_SCALE)));
        showReaderHint(R.drawable.rem_reader_resume, "已回到 " + percent + "%", "上次阅读位置");
    }

    private void showReaderHint(int imageRes, String message, String desc) {
        if (root == null) return;
        LinearLayout hint = new LinearLayout(this);
        hint.setOrientation(LinearLayout.HORIZONTAL);
        hint.setGravity(Gravity.CENTER_VERTICAL);
        hint.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 5), UIHelpers.dp(this, 12), UIHelpers.dp(this, 5));
        hint.setMinimumHeight(UIHelpers.dp(this, 48));
        hint.setBackground(UIHelpers.round(Color.argb(238, 29, 48, 66), UIHelpers.dp(this, 8), Color.argb(80, 180, 224, 255)));
        ImageView art = new ImageView(this);
        art.setImageResource(imageRes);
        art.setScaleType(ImageView.ScaleType.CENTER_CROP);
        hint.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(this, 38), UIHelpers.dp(this, 38)));
        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        TextView title = UIHelpers.text(this, message, 10, Color.WHITE, Typeface.BOLD);
        title.setIncludeFontPadding(false);
        copy.addView(title);
        if (!TextUtils.isEmpty(desc)) {
            TextView subtitle = UIHelpers.text(this, desc, 8, Color.argb(195, 235, 246, 255), Typeface.NORMAL);
            subtitle.setIncludeFontPadding(false);
            copy.addView(subtitle, UIHelpers.marginTop(-1, UIHelpers.dp(this, 3)));
        }
        LinearLayout.LayoutParams copyParams = new LinearLayout.LayoutParams(-2, -2);
        copyParams.leftMargin = UIHelpers.dp(this, 8);
        hint.addView(copy, copyParams);
        FrameLayout.LayoutParams lp = UIHelpers.frame(-2, UIHelpers.dp(this, 48), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL, 0, 0, 0, UIHelpers.dp(this, 52));
        root.addView(hint, lp);
        main.postDelayed(() -> {
            if (hint.getParent() == root) root.removeView(hint);
        }, 1800L);
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
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 9), UIHelpers.dp(this, 10), UIHelpers.dp(this, 9));
        row.setMinimumHeight(UIHelpers.dp(this, 54));
        row.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 7), UIHelpers.BORDER));
        row.setOnClickListener(v -> showChapterDrawer(detail));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(UIHelpers.text(this, "章节目录", 14, UIHelpers.TEXT, Typeface.BOLD));
        String status = detail.chapters.isEmpty() ? "打开后加载" : detail.chapters.size() + " 话 · 已缓存";
        text.addView(UIHelpers.text(this, status, 11, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 3)));
        row.addView(text, UIHelpers.weight(1));
        ImageView action = UIHelpers.vectorIconButton(this, R.drawable.ic_chevron_right, UIHelpers.TEXT3, 3);
        row.addView(action, new LinearLayout.LayoutParams(UIHelpers.dp(this, 24), UIHelpers.dp(this, 24)));
        return row;
    }

    private interface DetailAction {
        void run(ComicModels.ComicDetail detail);
    }

    private interface ChoiceAction {
        void run(int selected);
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
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 12), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
        panel.setBackgroundColor(UIHelpers.CARD);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setMinimumHeight(UIHelpers.dp(this, 43));
        panel.addView(header, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 43)));
        LinearLayout titleHost = new LinearLayout(this);
        titleHost.setOrientation(LinearLayout.VERTICAL);
        header.addView(titleHost, UIHelpers.weight(1));
        ImageView close = UIHelpers.vectorIconButton(this, R.drawable.ic_close, UIHelpers.TEXT2, 6);
        close.setContentDescription("关闭目录");
        header.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(this, 34), UIHelpers.dp(this, 34)));

        panel.addView(UIHelpers.divider(this));
        LinearLayout drawerTools = new LinearLayout(this);
        drawerTools.setGravity(Gravity.CENTER_VERTICAL);
        drawerTools.setMinimumHeight(UIHelpers.dp(this, 39));
        TextView drawerSource = UIHelpers.text(this, sourceNameForId(detail.summary.sourceId), 11, UIHelpers.TEXT3, Typeface.NORMAL);
        drawerSource.setSingleLine(true);
        drawerSource.setEllipsize(TextUtils.TruncateAt.END);
        drawerTools.addView(drawerSource, UIHelpers.weight(1));
        TextView order = UIHelpers.text(this, chapterDesc ? "倒序" : "正序", 11, UIHelpers.ACCENT, Typeface.BOLD);
        order.setGravity(Gravity.CENTER);
        order.setPadding(UIHelpers.dp(this, 4), 0, UIHelpers.dp(this, 4), 0);
        order.setBackgroundColor(Color.TRANSPARENT);
        LinearLayout orderHost = new LinearLayout(this);
        orderHost.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
        orderHost.addView(order, UIHelpers.wrap());
        drawerTools.addView(orderHost, new LinearLayout.LayoutParams(UIHelpers.dp(this, 54), UIHelpers.dp(this, 39)));
        drawerTools.setVisibility(detail.chapters.isEmpty() ? View.GONE : View.VISIBLE);
        panel.addView(drawerTools, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 39)));
        View drawerToolsDivider = UIHelpers.divider(this);
        drawerToolsDivider.setVisibility(detail.chapters.isEmpty() ? View.GONE : View.VISIBLE);
        panel.addView(drawerToolsDivider);

        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, UIHelpers.matchWrap());
        panel.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        PopupWindow popup = new PopupWindow(panel, Math.round(getResources().getDisplayMetrics().widthPixels * .76f), -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(UIHelpers.CARD));
        popup.setOutsideTouchable(true);
        popup.setElevation(UIHelpers.dp(this, 14));
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
        });

        final ComicModels.ComicDetail[] current = {detail};
        final int[] renderGeneration = {0};
        Runnable fill = () -> {
            int generation = ++renderGeneration[0];
            titleHost.removeAllViews();
            titleHost.addView(chapterDrawerTitle(current[0].chapters.size()));
            int toolsVisibility = current[0].chapters.isEmpty() ? View.GONE : View.VISIBLE;
            drawerTools.setVisibility(toolsVisibility);
            drawerToolsDivider.setVisibility(toolsVisibility);
            list.removeAllViews();
            List<Integer> orderIndexes = DataHelpers.chapterOrder(chapterDesc, current[0].chapters.size());
            fillChapterRows(list, popup, current[0], orderIndexes, 0, generation, renderGeneration);
        };
        order.setOnClickListener(v -> {
            if (current[0].chapters.isEmpty() || activePopup != popup || !popup.isShowing()) return;
            chapterDesc = !chapterDesc;
            saveLocalState();
            order.setText(chapterDesc ? "倒序" : "正序");
            fill.run();
        });
        activePopup = popup;
        popup.showAtLocation(root, Gravity.RIGHT, 0, 0);
        close.setOnClickListener(v -> popup.dismiss());
        if (!detail.chapters.isEmpty()) {
            fill.run();
            return;
        }
        titleHost.addView(chapterDrawerTitle(0));
        Runnable[] load = new Runnable[1];
        load[0] = () -> {
            list.removeAllViews();
            list.addView(remState(R.drawable.rem_loading, "正在解析章节目录", "可以先关闭抽屉", "", null));
            track(detailIo.submit(() -> {
                try {
                    List<ComicModels.Chapter> chapters = sourceForDetail(detail).chapters(detail.summary.comicId);
                    if (chapters.isEmpty()) {
                        main.post(() -> {
                            if (activePopup != popup || !popup.isShowing()) return;
                            list.removeAllViews();
                            list.addView(remState(R.drawable.rem_empty, "这里还没有章节", "稍后再来看看", "重新加载", load[0]));
                        });
                        return;
                    }
                    normalizeChaptersOldestFirst(chapters);
                    ComicModels.ComicDetail loaded = withChapters(detail, chapters);
                    main.post(() -> {
                        if (activePopup != popup || !popup.isShowing()) return;
                        details.put(detail.summary.comicId, loaded);
                        persistComicCachesAsync();
                        current[0] = loaded;
                        fill.run();
                    });
                } catch (Exception error) {
                    boolean expectedCancellation = isExpectedTaskCancellation(error);
                    main.post(() -> {
                        if (expectedCancellation || activePopup != popup || !popup.isShowing()) return;
                        appendErrorLog("目录解析失败", error);
                        list.removeAllViews();
                        list.addView(remState(R.drawable.rem_error, "目录解析失败", "请稍后再试", "重试", load[0]));
                    });
                }
            }));
        };
        load[0].run();
    }

    private void fillChapterRows(LinearLayout list, PopupWindow popup, ComicModels.ComicDetail detail,
                                 List<Integer> orderIndexes, int start, int generation, int[] renderGeneration) {
        if (generation != renderGeneration[0] || activePopup != popup || !popup.isShowing()) return;
        int endIndex = Math.min(start + CHAPTER_DRAWER_BATCH_SIZE, orderIndexes.size());
        for (int i = start; i < endIndex; i++) {
                int chapterIndex = orderIndexes.get(i);
                ComicModels.Chapter chapter = detail.chapters.get(chapterIndex);
                String end = readerChapterIndex == chapterIndex ? "当前" : String.valueOf(chapterIndex + 1);
                View item = chapterDrawerRow(chapter.title, end, chapterIndex == readerChapterIndex);
                item.setOnClickListener(v -> {
                    popup.dismiss();
                    showReader(detail, chapterIndex);
                });
                list.addView(item);
                if (i < orderIndexes.size() - 1) list.addView(UIHelpers.divider(this));
        }
        if (endIndex < orderIndexes.size() && activePopup == popup) {
            main.postDelayed(() -> fillChapterRows(list, popup, detail, orderIndexes, endIndex, generation, renderGeneration), 16);
        }
    }

    private LinearLayout chapterDrawerTitle(int count) {
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(UIHelpers.text(this, "章节目录", 16, UIHelpers.TEXT, Typeface.BOLD));
        text.addView(UIHelpers.text(this, count == 0 ? "打开后异步加载" : "共 " + count + " 话", 11, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        return text;
    }

    private View detailReadButton(ComicModels.ComicDetail detail) {
        LinearLayout button = new LinearLayout(this);
        button.setOrientation(LinearLayout.VERTICAL);
        button.setGravity(Gravity.CENTER);
        button.setPadding(UIHelpers.dp(this, 12), 0, UIHelpers.dp(this, 12), 0);
        button.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(this, 7), Color.TRANSPARENT));
        boolean hasHistory = lastViewedAt.containsKey(detail.summary.comicId);
        int saved = Math.max(0, savedChapter(detail.summary.comicId));
        String title = hasHistory ? "继续阅读" : "开始阅读";
        String subtitle = hasHistory ? "第 " + (saved + 1) + " 话" : "从第 1 话开始";
        if (hasHistory && saved < detail.chapters.size()) {
            Integer position = readerPositions.get(readerPositionKey(detail.summary.comicId, detail.chapters.get(saved)));
            if (position != null && position > 0) {
                subtitle += " · " + Math.max(1, Math.min(100,
                        Math.round(position * 100f / READER_POSITION_SCALE))) + "%";
            }
        }
        TextView titleView = UIHelpers.text(this, title, 13, UIHelpers.ON_ACCENT, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        titleView.setIncludeFontPadding(false);
        titleView.setSingleLine(true);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        button.addView(titleView);
        TextView subtitleView = UIHelpers.text(this, subtitle, 10, UIHelpers.ON_ACCENT, Typeface.NORMAL);
        subtitleView.setGravity(Gravity.CENTER);
        subtitleView.setIncludeFontPadding(false);
        subtitleView.setAlpha(.84f);
        subtitleView.setSingleLine(true);
        subtitleView.setEllipsize(TextUtils.TruncateAt.END);
        button.addView(subtitleView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        button.setContentDescription(title + "，" + subtitle);
        button.setOnClickListener(v -> ensureChaptersThen(detail, loaded -> showReader(loaded,
                Math.min(savedChapter(loaded.summary.comicId), loaded.chapters.size() - 1))));
        return button;
    }

    private void installDetailHeroStretch(ScrollView scroll, View hero, LinearLayout.LayoutParams params) {
        final int baseHeight = UIHelpers.dp(this, DETAIL_HERO_DP);
        final int maxHeight = UIHelpers.dp(this, DETAIL_HERO_MAX_DP);
        final float[] downY = {0f};
        final int[] startHeight = {baseHeight};
        scroll.setOnTouchListener((view, event) -> {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                downY[0] = event.getRawY();
                startHeight[0] = params.height;
                return false;
            }
            if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
                float distance = event.getRawY() - downY[0];
                if ((scroll.getScrollY() == 0 || startHeight[0] > baseHeight) && (distance > 0f || startHeight[0] > baseHeight)) {
                    int height = Math.max(baseHeight, Math.min(maxHeight, startHeight[0] + Math.round(distance)));
                    params.height = height;
                    hero.setLayoutParams(params);
                    return true;
                }
            }
            if (event.getActionMasked() == MotionEvent.ACTION_UP || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
                float distance = event.getRawY() - downY[0];
                int target = distance > UIHelpers.dp(this, 24) ? maxHeight
                        : distance < -UIHelpers.dp(this, 24) ? baseHeight
                        : params.height > (baseHeight + maxHeight) / 2 ? maxHeight : baseHeight;
                if (params.height == target) return false;
                ValueAnimator animator = ValueAnimator.ofInt(params.height, target);
                animator.setDuration(180L);
                animator.addUpdateListener(value -> {
                    params.height = (Integer) value.getAnimatedValue();
                    hero.setLayoutParams(params);
                });
                animator.start();
                return true;
            }
            return false;
        });
    }

    private View chapterDrawerRow(String title, String end, boolean current) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setMinimumHeight(UIHelpers.dp(this, 37));
        row.setPadding(UIHelpers.dp(this, 2), 0, UIHelpers.dp(this, 2), 0);
        if (current) row.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 5), Color.TRANSPARENT));
        TextView name = UIHelpers.text(this, title, 14, current ? UIHelpers.TEXT3 : UIHelpers.TEXT, Typeface.NORMAL);
        name.setGravity(Gravity.CENTER_VERTICAL);
        name.setSingleLine(true);
        name.setEllipsize(TextUtils.TruncateAt.END);
        row.addView(name, UIHelpers.weight(1));
        row.addView(chapterNumberView(end, current), new LinearLayout.LayoutParams(UIHelpers.dp(this, 32), -2));
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
        String message;
        if (favorites.contains(id)) {
            favorites.remove(id);
            favoriteAt.remove(id);
            message = "已移出书架";
        } else {
            removeDuplicateFavorites(detail);
            favorites.remove(id);
            favorites.add(0, id);
            favoriteAt.put(id, System.currentTimeMillis());
            details.put(id, detail);
            summaries.put(id, detail.summary);
            persistComicCachesAsync();
            if (!isRetiredComic(detail.summary.comicId)) loadImageToCache(detail.summary.coverUrl);
            message = "已放进书架";
        }
        saveLocalState();
        showDetail(id);
        main.post(() -> showRemToast(R.drawable.rem_empty, message));
    }

    private void deleteFavorite(String id) {
        favorites.remove(id);
        favoriteAt.remove(id);
        saveLocalState();
        showTab(0);
        main.post(() -> showRemToast("已删除收藏"));
    }

    private void deleteFavoriteWithUndo(String id) {
        int oldIndex = favorites.indexOf(id);
        Long oldFavoriteAt = favoriteAt.get(id);
        ComicModels.ComicSummary summary = summaries.get(id);
        String title = clean(summary == null ? "" : summary.title, "这本漫画");
        favorites.remove(id);
        favoriteAt.remove(id);
        saveLocalState();
        showTab(0);
        showFavoriteUndo(id, oldIndex, oldFavoriteAt, title);
    }

    private void showFavoriteUndo(String id, int oldIndex, Long oldFavoriteAt, String title) {
        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(UIHelpers.dp(this, 12), 0, UIHelpers.dp(this, 8), 0);
        bar.setBackground(UIHelpers.round(Color.rgb(36, 68, 93), UIHelpers.dp(this, 5), Color.TRANSPARENT));
        bar.setElevation(UIHelpers.dp(this, 4));
        TextView message = UIHelpers.text(this, "已移出《" + title + "》", 12, Color.WHITE, Typeface.NORMAL);
        message.setSingleLine(true);
        message.setEllipsize(TextUtils.TruncateAt.END);
        bar.addView(message, UIHelpers.weight(1));
        TextView undo = UIHelpers.text(this, "撤销", 12, Color.rgb(134, 210, 255), Typeface.BOLD);
        undo.setGravity(Gravity.CENTER);
        undo.setPadding(UIHelpers.dp(this, 10), 0, UIHelpers.dp(this, 4), 0);
        undo.setOnClickListener(v -> {
            if (!favorites.contains(id)) {
                favorites.add(Math.max(0, Math.min(oldIndex, favorites.size())), id);
                favoriteAt.put(id, oldFavoriteAt == null ? System.currentTimeMillis() : oldFavoriteAt);
                saveLocalState();
            }
            showTab(0);
        });
        bar.addView(undo, new LinearLayout.LayoutParams(-2, -1));
        root.addView(bar, UIHelpers.frame(-1, UIHelpers.dp(this, 46), Gravity.BOTTOM, UIHelpers.dp(this, 13), 0,
                UIHelpers.dp(this, 13), UIHelpers.dp(this, 70)));
        main.postDelayed(() -> {
            if (bar.getParent() == root) root.removeView(bar);
        }, 3200L);
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

    private ImageView coverView(String url, int widthDp, int heightDp, boolean cacheOnly) {
        ImageView image = new ImageView(this);
        image.setScaleType(TextUtils.isEmpty(url) ? ImageView.ScaleType.FIT_CENTER : ImageView.ScaleType.CENTER_CROP);
        image.setImageResource(R.drawable.rem_no_image);
        image.setBackground(UIHelpers.round(UIHelpers.BORDER_SOFT, UIHelpers.dp(this, 10), Color.TRANSPARENT));
        int width = widthDp < 0 ? -1 : UIHelpers.dp(this, widthDp);
        image.setLayoutParams(new LinearLayout.LayoutParams(width, UIHelpers.dp(this, heightDp)));
        if (!TextUtils.isEmpty(url)) loadImage(image, url, "", cacheOnly);
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
        return coverFrame(url, widthDp, heightDp, false);
    }

    private FrameLayout coverFrame(String url, int widthDp, int heightDp, boolean cacheOnly) {
        FrameLayout frame = new FrameLayout(this);
        frame.setBackground(UIHelpers.round(UIHelpers.PLACEHOLDER, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        int width = widthDp < 0 ? -1 : UIHelpers.dp(this, widthDp);
        frame.setLayoutParams(new LinearLayout.LayoutParams(width, UIHelpers.dp(this, heightDp)));
        ImageView image = coverView(url, -1, heightDp, cacheOnly);
        frame.addView(image, UIHelpers.frame(-1, UIHelpers.dp(this, heightDp), Gravity.CENTER, 0, 0, 0, 0));
        return frame;
    }

    private void addDetailHeroCover(FrameLayout hero, String coverUrl, boolean cacheOnly) {
        ImageView cover = new ImageView(this);
        cover.setBackgroundColor(UIHelpers.SURFACE);
        cover.setImageResource(R.drawable.rem_no_image);
        cover.setScaleType(TextUtils.isEmpty(coverUrl) ? ImageView.ScaleType.FIT_CENTER : ImageView.ScaleType.CENTER_CROP);
        if (!TextUtils.isEmpty(coverUrl)) loadImage(cover, coverUrl, "", cacheOnly);
        hero.addView(cover, UIHelpers.match());
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
        return readerState(message.contains("失败") ? R.drawable.rem_error : R.drawable.rem_loading,
                message, "", "", null, false);
    }

    private View readerState(int imageRes, String title, String desc, String action,
                             Runnable onClick, boolean loading) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        ImageView art = new ImageView(this);
        art.setImageResource(imageRes);
        art.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        box.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(this, 126), UIHelpers.dp(this, 126)));
        TextView titleView = UIHelpers.text(this, title, 14, UIHelpers.READER_TEXT, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        titleView.setIncludeFontPadding(false);
        box.addView(titleView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8)));
        if (!TextUtils.isEmpty(desc)) {
            TextView description = UIHelpers.text(this, desc, 10, Color.argb(190, 235, 246, 255), Typeface.NORMAL);
            description.setGravity(Gravity.CENTER);
            description.setIncludeFontPadding(false);
            box.addView(description, UIHelpers.marginTop(-1, UIHelpers.dp(this, 5)));
        }
        if (loading) {
            View pulse = new View(this);
            pulse.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(this, 2), Color.TRANSPARENT));
            box.addView(pulse, UIHelpers.marginTop(UIHelpers.dp(this, 78), UIHelpers.dp(this, 22), UIHelpers.dp(this, 78), UIHelpers.dp(this, 2)));
        } else if (!TextUtils.isEmpty(action) && onClick != null) {
            TextView retry = UIHelpers.text(this, action, 11, UIHelpers.ACCENT_LIGHT, Typeface.BOLD);
            retry.setGravity(Gravity.CENTER);
            retry.setIncludeFontPadding(false);
            retry.setPadding(UIHelpers.dp(this, 15), UIHelpers.dp(this, 7), UIHelpers.dp(this, 15), UIHelpers.dp(this, 7));
            retry.setBackground(UIHelpers.round(Color.argb(34, 133, 202, 245), UIHelpers.dp(this, 6), Color.TRANSPARENT));
            retry.setOnClickListener(v -> onClick.run());
            box.addView(retry, UIHelpers.marginTop(-2, UIHelpers.dp(this, 18), -2, -2));
        }
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

    private void prefetchReaderImages(List<String> imageUrls, int start, String chapterUrl,
                                      int generation, String comicId, boolean cacheOnly) {
        if (generation != readerGeneration || !readerVisible || imageUrls == null) return;
        int end = Math.min(imageUrls.size(), Math.max(0, start) + READER_PREFETCH_COUNT);
        for (int i = Math.max(0, start); i < end; i++) {
            String imageUrl = imageUrls.get(i);
            String key = chapterUrl + "\n" + imageUrl;
            if (TextUtils.isEmpty(imageUrl) || !readerPrefetching.add(key)) continue;
            submitReaderImage(readerPrefetchIo, () -> {
                try {
                    if (isCurrentReaderImageRequest(generation, comicId, chapterUrl)) {
                        ensureReaderImageCached(imageUrl, chapterUrl, cacheOnly);
                    }
                } catch (Exception error) {
                    if (!isExpectedTaskCancellation(error)) {
                        appendErrorLog("\u9605\u8bfb\u56fe\u7247\u9884\u52a0\u8f7d\u5931\u8d25", error);
                    }
                } finally {
                    main.post(() -> readerPrefetching.remove(key));
                }
            });
        }
    }

    private boolean ensureReaderImageCached(String imageUrl, String chapterUrl, boolean cacheOnly) throws IOException {
        File cached = imageCacheFile(imageUrl);
        long[] cachedIdentity = captureImageCacheIdentity(cached);
        if (cachedIdentity != null && cachedIdentity[0] > 0L) {
            cached.setLastModified(System.currentTimeMillis());
            return true;
        }
        deleteImageCacheIfUnchanged(cached, cachedIdentity);
        if (cacheOnly) return false;
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(imageUrl).openConnection();
            connection.setInstanceFollowRedirects(true);
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(30000);
            String referer = refererForImage(imageUrl, chapterUrl);
            applyImageHeaders(connection, referer);
            int code = connection.getResponseCode();
            if (code >= 400) {
                throw new IOException("Image HTTP " + code + ": " + imageUrl + "; referer=" + referer);
            }
            requireImageContentType(imageUrl, connection.getContentType());
            try (InputStream stream = connection.getInputStream()) {
                writeReaderImageCache(cached, stream);
            }
        } finally {
            if (connection != null) connection.disconnect();
        }
        return true;
    }

    private Future<?> loadReaderImage(ImageView target, String imageUrl, String chapterUrl,
                                      int generation, String comicId, ListView list,
                                      boolean[] restoringPosition, int savedPosition, boolean cacheOnly) {
        if (TextUtils.isEmpty(imageUrl)) return null;
        return submitReaderImage(() -> {
            try {
                File cached = imageCacheFile(imageUrl);
                long[] cachedIdentity = captureImageCacheIdentity(cached);
                Bitmap bitmap = cachedIdentity != null ? decodeReaderImage(cached, readerContentWidth(), imageUrl) : null;
                if (bitmap == null) {
                    deleteImageCacheIfUnchanged(cached, cachedIdentity);
                    if (!ensureReaderImageCached(imageUrl, chapterUrl, cacheOnly)) {
                        main.post(() -> {
                            if (activityDestroyed || !TextUtils.equals(imageUrl, (String) target.getTag())
                                    || !isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                            target.setImageResource(R.drawable.rem_error);
                            target.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                        });
                        return;
                    }
                    bitmap = decodeReaderImage(cached, readerContentWidth(), imageUrl);
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
                    target.setScaleType(ImageView.ScaleType.FIT_CENTER);
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
                    target.setImageResource(R.drawable.rem_error);
                    target.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                });
            }
        });
    }

    private boolean isCurrentReaderImageRequest(int generation, String comicId, String chapterUrl) {
        if (generation != readerGeneration || !readerVisible || !TextUtils.equals(activeDetailId, comicId)) return false;
        ComicModels.ComicDetail detail = details.get(comicId);
        if (detail == null || readerChapterIndex < 0 || readerChapterIndex >= detail.chapters.size()) return false;
        return TextUtils.equals(detail.chapters.get(readerChapterIndex).url, chapterUrl);
    }

    private Bitmap decodeReaderImage(File file, int targetWidth, String imageUrl) {
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
        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
        return restoreJmReaderImage(bitmap, imageUrl);
    }

    private Bitmap restoreJmReaderImage(Bitmap source, String imageUrl) {
        if (source == null || TextUtils.isEmpty(imageUrl)) return source;
        Matcher path = Pattern.compile(
                "https?://cdn-msp[^/]*\\.18comic\\.vip/media/photos/(\\d+)/([^/?#]+)",
                Pattern.CASE_INSENSITIVE).matcher(imageUrl);
        Matcher scramble = Pattern.compile("[?&]scramble_id=(\\d+)").matcher(imageUrl);
        if (!path.find() || !scramble.find()) return source;
        long aid;
        long scrambleId;
        try {
            aid = Long.parseLong(path.group(1));
            scrambleId = Long.parseLong(scramble.group(1));
        } catch (NumberFormatException ignored) {
            return source;
        }
        int slices = jmScrambleSlices(aid, scrambleId, path.group(2));
        if (slices <= 1 || source.getHeight() < slices) return source;
        Bitmap.Config config = source.getConfig();
        if (config == null || config == Bitmap.Config.HARDWARE) config = Bitmap.Config.ARGB_8888;
        Bitmap restored = Bitmap.createBitmap(source.getWidth(), source.getHeight(), config);
        Canvas canvas = new Canvas(restored);
        for (int[] bound : jmSliceBounds(source.getHeight(), slices)) {
            canvas.drawBitmap(source,
                    new Rect(0, bound[0], source.getWidth(), bound[1]),
                    new Rect(0, bound[2], source.getWidth(), bound[3]), null);
        }
        source.recycle();
        return restored;
    }

    static int[][] jmSliceBounds(int height, int slices) {
        int[][] bounds = new int[slices][4];
        int move = height / slices;
        int remainder = height % slices;
        int targetY = 0;
        for (int i = 0; i < slices; i++) {
            int sliceHeight = move + (i == 0 ? remainder : 0);
            int sourceY = height - targetY - sliceHeight;
            bounds[i] = new int[]{sourceY, sourceY + sliceHeight, targetY, targetY + sliceHeight};
            targetY += sliceHeight;
        }
        return bounds;
    }

    static int jmScrambleSlices(long aid, long scrambleId, String fileName) {
        if (aid < scrambleId) return 0;
        if (aid < 268850L) return 10;
        try {
            String baseName = fileName == null ? "" : fileName;
            int extension = baseName.lastIndexOf('.');
            if (extension > 0) baseName = baseName.substring(0, extension);
            byte[] digest = MessageDigest.getInstance("MD5")
                    .digest((aid + baseName).getBytes("UTF-8"));
            StringBuilder hex = new StringBuilder(digest.length * 2);
            for (byte value : digest) hex.append(String.format(Locale.US, "%02x", value & 0xff));
            int divisor = aid >= 421926L ? 8 : 10;
            return hex.charAt(hex.length() - 1) % divisor * 2 + 2;
        } catch (Exception ignored) {
            return 0;
        }
    }

    private int readerContentWidth() {
        return Math.max(1, getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(this, 8));
    }

    private void loadImage(ImageView target, String imageUrl) {
        loadImage(target, imageUrl, "", false);
    }

    private void loadImage(ImageView target, String imageUrl, String pageReferer) {
        loadImage(target, imageUrl, pageReferer, false);
    }

    private void loadImage(ImageView target, String imageUrl, String pageReferer, boolean cacheOnly) {
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
                if (cacheOnly) {
                    main.post(() -> target.setImageResource(R.drawable.rem_no_image));
                    return;
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
                requireImageContentType(imageUrl, contentType);
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
                main.post(() -> target.setImageResource(R.drawable.rem_no_image));
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
                requireImageContentType(imageUrl, connection.getContentType());
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
        if (isFiveUmImage(imageUrl)) {
            return TextUtils.isEmpty(pageReferer) ? manhuazhanConfig.referer : pageReferer;
        }
        if (imageUrl != null && (imageUrl.contains(aikanConfig.domain) || imageUrl.contains("qrqrs.com"))) return aikanConfig.referer;
        if (imageUrl != null && imageUrl.contains(jmcomicConfig.domain)) {
            return TextUtils.isEmpty(pageReferer) ? jmcomicConfig.referer : pageReferer;
        }
        if (imageUrl != null && (imageUrl.contains(mh18Config.domain) || imageUrl.contains("mangabuddy.in"))) {
            return TextUtils.isEmpty(pageReferer) ? mh18Config.referer : pageReferer;
        }
        if (imageUrl != null && (imageUrl.contains(gmhConfig.domain) || imageUrl.contains("g-mh.online") || imageUrl.contains("6wm.top"))) {
            return TextUtils.isEmpty(pageReferer) ? gmhConfig.referer : pageReferer;
        }
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
        if (imageUrl != null && imageUrl.contains("antbyw.com")) return antbywConfig.referer;
        if (imageUrl != null && (imageUrl.contains(cuimhConfig.domain) || imageUrl.contains("baipiaoguai.org"))) {
            return TextUtils.isEmpty(pageReferer) ? cuimhConfig.referer : pageReferer;
        }
        return baoziConfig.referer;
    }

    private boolean isFiveUmImage(String imageUrl) {
        String host = TextUtils.isEmpty(imageUrl) ? "" : Uri.parse(imageUrl).getHost();
        if (host == null) return false;
        host = host.toLowerCase(Locale.US);
        return "5um.net".equals(host) || host.endsWith(".5um.net");
    }

    private void requireImageContentType(String imageUrl, String contentType) throws IOException {
        if (isFiveUmImage(imageUrl)
                && (contentType == null || !contentType.toLowerCase(Locale.US).startsWith("image/"))) {
            throw new IOException("Unexpected image content type: " + contentType + "; url=" + imageUrl);
        }
    }

    private void resetCategoryFilters() {
        selectedFilters.clear();
        selectedFilterLabels.clear();
    }

    private void normalizeSelectedFilters() {
        Set<String> keys = new HashSet<>();
        for (ComicModels.FilterGroup group : sourceFilterGroups) keys.add(group.key);
        selectedFilters.keySet().retainAll(keys);
        selectedFilterLabels.keySet().retainAll(keys);
        for (ComicModels.FilterGroup group : sourceFilterGroups) {
            if (!selectedFilters.containsKey(group.key)) selectedFilters.put(group.key, "all");
            if (!selectedFilterLabels.containsKey(group.key)) selectedFilterLabels.put(group.key, ALL_TAG);
        }
    }

    private View dividerLine() {
        View d = new View(this);
        d.setBackgroundColor(UIHelpers.BORDER_SOFT);
        d.setLayoutParams(new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 1)));
        return d;
    }

    private void showFilterDrawer() {
        showFilterDrawer(1);
    }

    private void showFilterDrawer(int initialTab) {
        int screenWidth = getResources().getDisplayMetrics().widthPixels;
        int panelWidth = Math.min(screenWidth - UIHelpers.dp(this, 56), UIHelpers.dp(this, 320));

        final String origSourceId = selectedSourceId;
        final Map<String, String> origFilters = new LinkedHashMap<>(selectedFilters);
        final Map<String, String> origFilterLabels = new LinkedHashMap<>(selectedFilterLabels);
        final List<ComicModels.FilterGroup> origFilterGroups = new ArrayList<>(sourceFilterGroups);
        final boolean origCategoriesFailed = sourceCategoriesFailed;
        final boolean[] confirmed = {false};

        FrameLayout overlay = new FrameLayout(this);
        View backdrop = new View(this);
        backdrop.setBackgroundColor(Color.argb(150, 0, 0, 0));
        overlay.addView(backdrop, UIHelpers.match());

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        android.graphics.drawable.GradientDrawable panelBg = new android.graphics.drawable.GradientDrawable();
        panelBg.setColor(UIHelpers.CARD);
        float r = UIHelpers.dp(this, 8);
        panelBg.setCornerRadii(new float[]{r, r, 0, 0, 0, 0, r, r});
        panel.setBackground(panelBg);
        panel.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 12));
        overlay.addView(panel, new FrameLayout.LayoutParams(panelWidth, -1, Gravity.RIGHT));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(UIHelpers.text(this, "筛选", 17, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        TextView close = UIHelpers.text(this, "✕", 17, UIHelpers.TEXT2, Typeface.NORMAL);
        close.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 4), UIHelpers.dp(this, 8), UIHelpers.dp(this, 4));
        close.setBackgroundColor(Color.TRANSPARENT);
        header.addView(close);
        panel.addView(header, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));

        HorizontalScrollView tabsScroll = new HorizontalScrollView(this);
        tabsScroll.setHorizontalScrollBarEnabled(false);
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        tabsScroll.addView(tabs, UIHelpers.wrap());
        panel.addView(tabsScroll, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 6)));

        ScrollView contentScroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        contentScroll.addView(content, UIHelpers.matchWrap());
        panel.addView(contentScroll, new LinearLayout.LayoutParams(-1, 0, 1));

        Button confirm = UIHelpers.brandButton(this, "\u786e\u8ba4\u641c\u7d22");
        confirm.setTextSize(15);
        confirm.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        confirm.setPadding(UIHelpers.dp(this, 14), UIHelpers.dp(this, 6), UIHelpers.dp(this, 14), UIHelpers.dp(this, 6));
        confirm.setMinHeight(UIHelpers.dp(this, 44));
        confirm.setMinimumHeight(UIHelpers.dp(this, 44));
        LinearLayout.LayoutParams confirmLp = new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 44));
        confirmLp.topMargin = UIHelpers.dp(this, 10);
        panel.addView(confirm, confirmLp);

        PopupWindow popup = new PopupWindow(overlay, -1, -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        popup.setOnDismissListener(() -> {
            if (activePopup == popup) activePopup = null;
            filterDrawerAction = null;
            if (!confirmed[0]) {
                selectedSourceId = origSourceId;
                selectedFilters.clear();
                selectedFilters.putAll(origFilters);
                selectedFilterLabels.clear();
                selectedFilterLabels.putAll(origFilterLabels);
                categoryGeneration++;
                sourceFilterGroups.clear();
                sourceFilterGroups.addAll(origFilterGroups);
                sourceCategoriesFailed = origCategoriesFailed;
                if (sourceFilterGroups.isEmpty() && !sourceCategoriesFailed) loadSourceCategories();
            }
        });
        close.setOnClickListener(v -> popup.dismiss());
        backdrop.setOnClickListener(v -> popup.dismiss());

        final int[] filterTab = {initialTab};
        final Runnable[] fill = new Runnable[1];
        fill[0] = () -> {
            content.removeAllViews();
            boolean sourceTab = filterTab[0] == 0;
            tabs.removeAllViews();
            tabsScroll.setVisibility(sourceTab ? View.GONE : View.VISIBLE);
            if (sourceTab) {
                filterDrawerAction = null;
                content.addView(UIHelpers.text(this, "已启用站源", 12, UIHelpers.TEXT3, Typeface.NORMAL),
                        UIHelpers.marginBottom(-1, UIHelpers.dp(this, 4)));
                for (String name : enabledSourceNames()) {
                    String sid = sourceIdForName(name);
                    boolean sel = sid.equals(selectedSourceId);
                    LinearLayout row = new LinearLayout(this);
                    row.setGravity(Gravity.CENTER_VERTICAL);
                    row.setMinimumHeight(UIHelpers.dp(this, 40));
                    row.addView(UIHelpers.text(this, name, 14, sel ? UIHelpers.ACCENT : UIHelpers.TEXT,
                            sel ? Typeface.BOLD : Typeface.NORMAL), UIHelpers.weight(1));
                    if (sel) row.addView(UIHelpers.text(this, "✓", 14, UIHelpers.ACCENT, Typeface.BOLD));
                    row.setOnClickListener(v -> {
                        if (!TextUtils.equals(selectedSourceId, sid)) {
                            searchGeneration++;
                            searchLoading = false;
                            searchAppending = false;
                            finishSearchPullRefresh();
                            clearSearchAppendFailure();
                            removeSearchPagingFooter();
                        }
                        selectedSourceId = sid;
                        resetCategoryFilters();
                        sourceFilterGroups.clear();
                        sourceCategoriesFailed = false;
                        if (categoriesFollowInitialList(sid)) {
                            filterTab[0] = 0;
                        } else {
                            loadSourceCategories();
                            filterTab[0] = 1;
                        }
                        fill[0].run();
                    });
                    content.addView(row);
                    content.addView(dividerLine());
                }
            } else {
                filterDrawerAction = () -> fill[0].run();
                if (sourceFilterGroups.isEmpty()) {
                    content.addView(loadingState("正在读取分类", "请稍等"));
                    return;
                }
                if (filterTab[0] < 1 || filterTab[0] > sourceFilterGroups.size()) filterTab[0] = 1;
                for (int i = 0; i < sourceFilterGroups.size(); i++) {
                    final int tabIndex = i + 1;
                    TextView tab = filterDrawerTab(sourceFilterGroups.get(i).label);
                    updateFilterDrawerTab(tab, filterTab[0] == tabIndex);
                    tab.setOnClickListener(v -> {
                        filterTab[0] = tabIndex;
                        fill[0].run();
                    });
                    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(UIHelpers.dp(this, 72), -2);
                    tabs.addView(tab, lp);
                }
                content.addView(filterOptionColumn(sourceFilterGroups.get(filterTab[0] - 1)));
            }
        };
        confirm.setOnClickListener(v -> {
            confirmed[0] = true;
            boolean sourceChanged = !selectedSourceId.equals(origSourceId);
            String keyword = searchQuery.trim();
            searchResults.clear();
            showTab(1);
            if (sourceChanged && !categoriesFollowInitialList(selectedSourceId)
                    && sourceFilterGroups.isEmpty()) loadSourceCategories();
            if (TextUtils.isEmpty(keyword)) loadCategory(); else runSearch(keyword);
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

    private TextView filterDrawerTab(String label) {
        TextView tab = UIHelpers.text(this, label, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        tab.setGravity(Gravity.CENTER);
        tab.setPadding(0, UIHelpers.dp(this, 7), 0, UIHelpers.dp(this, 7));
        tab.setBackgroundColor(Color.TRANSPARENT);
        return tab;
    }

    private void updateFilterDrawerTab(TextView tab, boolean selected) {
        tab.setTextColor(selected ? UIHelpers.ACCENT_DARK : UIHelpers.TEXT3);
        tab.setTypeface(Typeface.create("sans-serif-medium", selected ? Typeface.BOLD : Typeface.NORMAL));
        if (selected) {
            ColorDrawable underline = new ColorDrawable(UIHelpers.ACCENT);
            underline.setBounds(0, 0, UIHelpers.dp(this, 18), UIHelpers.dp(this, 2));
            tab.setCompoundDrawables(null, null, null, underline);
            tab.setCompoundDrawablePadding(UIHelpers.dp(this, 4));
        } else {
            tab.setCompoundDrawables(null, null, null, null);
            tab.setCompoundDrawablePadding(0);
        }
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
                    resetCategoryFilters();
                    sourceFilterGroups.clear();
                    sourceCategoriesFailed = false;
                    searchResults.clear();
                    showTab(1);
                    if (!categoriesFollowInitialList(selectedSourceId)) loadSourceCategories();
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
        if (aikanEnabled) names.add(aikanClient.name());
        if (gmhEnabled) names.add(gmhClient.name());
        if (mh18Enabled) names.add(mh18Client.name());
        if (jmcomicEnabled) names.add(jmcomicClient.name());
        if (mkzhanEnabled) names.add(mkzhanClient.name());
        if (hiperdexEnabled) names.add(hiperdexClient.name());
        if (manhuaguiEnabled) names.add(manhuaguiClient.name());
        if (hanman18Enabled) names.add(hanman18Client.name());
        if (d5d6Enabled) names.add(d5d6Client.name());
        if (manbenEnabled) names.add(manbenClient.name());
        if (manhuazhanEnabled) names.add(manhuazhanClient.name());
        if (bbyinEnabled) names.add(bbyinClient.name());
        if (antbywEnabled) names.add(antbywClient.name());
        if (cuimhEnabled) names.add(cuimhClient.name());
        return names;
    }

    private String selectedSourceName() {
        if (sourceClient.id().equals(selectedSourceId)) return sourceClient.name();
        if (aikanClient.id().equals(selectedSourceId)) return aikanClient.name();
        if (gmhClient.id().equals(selectedSourceId)) return gmhClient.name();
        if (mh18Client.id().equals(selectedSourceId)) return mh18Client.name();
        if (jmcomicClient.id().equals(selectedSourceId)) return jmcomicClient.name();
        if (mkzhanClient.id().equals(selectedSourceId)) return mkzhanClient.name();
        if (hiperdexClient.id().equals(selectedSourceId)) return hiperdexClient.name();
        if (manhuaguiClient.id().equals(selectedSourceId)) return manhuaguiClient.name();
        if (hanman18Client.id().equals(selectedSourceId)) return hanman18Client.name();
        if (d5d6Client.id().equals(selectedSourceId)) return d5d6Client.name();
        if (manbenClient.id().equals(selectedSourceId)) return manbenClient.name();
        if (manhuazhanClient.id().equals(selectedSourceId)) return manhuazhanClient.name();
        if (bbyinClient.id().equals(selectedSourceId)) return bbyinClient.name();
        if (antbywClient.id().equals(selectedSourceId)) return antbywClient.name();
        if (cuimhClient.id().equals(selectedSourceId)) return cuimhClient.name();
        for (ComicModels.Source item : customSources) {
            if (item.id.equals(selectedSourceId)) return item.name;
        }
        return "全部";
    }

    private String sourceIdForName(String name) {
        if (sourceClient.name().equals(name)) return sourceClient.id();
        if (aikanClient.name().equals(name)) return aikanClient.id();
        if (gmhClient.name().equals(name)) return gmhClient.id();
        if (mh18Client.name().equals(name)) return mh18Client.id();
        if (jmcomicClient.name().equals(name)) return jmcomicClient.id();
        if (mkzhanClient.name().equals(name)) return mkzhanClient.id();
        if (hiperdexClient.name().equals(name)) return hiperdexClient.id();
        if (manhuaguiClient.name().equals(name)) return manhuaguiClient.id();
        if (hanman18Client.name().equals(name)) return hanman18Client.id();
        if (d5d6Client.name().equals(name)) return d5d6Client.id();
        if (manbenClient.name().equals(name)) return manbenClient.id();
        if (manhuazhanClient.name().equals(name)) return manhuazhanClient.id();
        if (bbyinClient.name().equals(name)) return bbyinClient.id();
        if (antbywClient.name().equals(name)) return antbywClient.id();
        if (cuimhClient.name().equals(name)) return cuimhClient.id();
        for (ComicModels.Source item : customSources) {
            if (item.name.equals(name)) return item.id;
        }
        return sourceClient.id();
    }

    private LinearLayout filterOptionColumn(ComicModels.FilterGroup group) {
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        if (group == null || group.options.isEmpty()) return column;
        final int columns = 3;
        final int cellHeight = UIHelpers.dp(this, 32);
        final int cellGap = UIHelpers.dp(this, 6);
        LinearLayout row = null;
        for (int i = 0; i < group.options.size(); i++) {
            if (i % columns == 0) {
                row = new LinearLayout(this);
                row.setOrientation(LinearLayout.HORIZONTAL);
                column.addView(row, UIHelpers.marginBottom(-1, cellGap));
            }
            ComicModels.FilterOption option = group.options.get(i);
            boolean selected = option.value.equals(selectedFilters.get(group.key));
            TextView chip = filterGridChip(option.label, selected);
            chip.setSingleLine(true);
            chip.setEllipsize(TextUtils.TruncateAt.END);
            chip.setGravity(Gravity.CENTER);
            chip.setOnClickListener(v -> {
                selectedFilters.put(group.key, option.value);
                selectedFilterLabels.put(group.key, option.label);
                if ((gmhClient.id().equals(selectedSourceId) || mh18Client.id().equals(selectedSourceId)
                        || jmcomicClient.id().equals(selectedSourceId))
                        && !"all".equals(option.value)) {
                    for (ComicModels.FilterGroup other : sourceFilterGroups) {
                        if (!other.key.equals(group.key)) {
                            selectedFilters.put(other.key, "all");
                            selectedFilterLabels.put(other.key, ALL_TAG);
                        }
                    }
                }
                if (filterDrawerAction != null) filterDrawerAction.run();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, cellHeight, 1);
            if (i % columns != columns - 1) lp.rightMargin = cellGap;
            row.addView(chip, lp);
        }
        int remainder = group.options.size() % columns;
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
                UIHelpers.dp(this, 6),
                selected ? Color.TRANSPARENT : UIHelpers.BORDER_SOFT));
        return chip;
    }
    private LinearLayout makeBottomNav() {
        LinearLayout wrap = new LinearLayout(this);
        // 圆角顶背景（仅上方两角圆角），无 elevation 无描边
        android.graphics.drawable.GradientDrawable navBg = new android.graphics.drawable.GradientDrawable();
        navBg.setColor(UIHelpers.CARD);
        float r = UIHelpers.dp(this, 8);
        navBg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        wrap.setBackground(navBg);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(0, UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 6));
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        tabs.setGravity(Gravity.CENTER_VERTICAL);
        wrap.addView(tabs, new LinearLayout.LayoutParams(-1, -1));
        int[] iconRes = { R.drawable.ic_bookshelf, R.drawable.ic_search_nav, R.drawable.ic_profile };
        int[] iconResSelected = { R.drawable.ic_bookshelf, R.drawable.ic_search_nav, R.drawable.ic_profile };
        String[] labels = {"书架", "发现", "设置"};
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
                if (index == currentTab) return;
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

    private void settingsHeader(LinearLayout page, String title, String meta) {
        settingsHeader(page, title, meta, null);
    }

    private void settingsHeader(LinearLayout page, String title, String meta, View trailing) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView titleView = UIHelpers.text(this, title, 20, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        row.addView(titleView, UIHelpers.weight(1));
        if (!TextUtils.isEmpty(meta)) {
            TextView metaView = UIHelpers.text(this, meta, 12, UIHelpers.TEXT3, Typeface.NORMAL);
            LinearLayout.LayoutParams metaParams = new LinearLayout.LayoutParams(-2, -2);
            if (trailing != null) metaParams.rightMargin = UIHelpers.dp(this, 8);
            row.addView(metaView, metaParams);
        }
        if (trailing != null) {
            ViewGroup.LayoutParams currentParams = trailing.getLayoutParams();
            LinearLayout.LayoutParams trailingParams = currentParams instanceof LinearLayout.LayoutParams
                    ? (LinearLayout.LayoutParams) currentParams
                    : new LinearLayout.LayoutParams(UIHelpers.dp(this, 32), UIHelpers.dp(this, 32));
            row.addView(trailing, trailingParams);
        }
        page.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 5)));
    }

    private TextView settingsSectionText(String value) {
        TextView text = UIHelpers.text(this, value, 12, UIHelpers.TEXT3, Typeface.NORMAL);
        text.setPadding(UIHelpers.dp(this, 2), UIHelpers.dp(this, 10), UIHelpers.dp(this, 2), UIHelpers.dp(this, 5));
        return text;
    }

    private LinearLayout settingsList() {
        LinearLayout list = UIHelpers.card(this);
        list.setPadding(0, 0, 0, 0);
        return list;
    }

    private View settingsMenuItem(int iconRes, String title, String subtitle, String end, Runnable onClick) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setMinimumHeight(UIHelpers.dp(this, TextUtils.isEmpty(subtitle) ? 46 : 56));
        row.setPadding(UIHelpers.dp(this, 9), UIHelpers.dp(this, 6), UIHelpers.dp(this, 9), UIHelpers.dp(this, 6));
        row.setClickable(true);
        row.setFocusable(true);
        row.setOnClickListener(v -> onClick.run());

        FrameLayout iconHost = new FrameLayout(this);
        iconHost.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 6), Color.TRANSPARENT));
        ImageView icon = new ImageView(this);
        icon.setImageResource(iconRes);
        icon.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
        icon.setPadding(UIHelpers.dp(this, 5), UIHelpers.dp(this, 5), UIHelpers.dp(this, 5), UIHelpers.dp(this, 5));
        iconHost.addView(icon, UIHelpers.match());
        LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28));
        iconParams.rightMargin = UIHelpers.dp(this, 9);
        row.addView(iconHost, iconParams);

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        TextView titleView = UIHelpers.text(this, title, 14, UIHelpers.TEXT, Typeface.NORMAL);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        copy.addView(titleView);
        if (!TextUtils.isEmpty(subtitle)) {
            TextView subtitleView = UIHelpers.text(this, subtitle, 11, UIHelpers.TEXT3, Typeface.NORMAL);
            subtitleView.setSingleLine(true);
            subtitleView.setEllipsize(TextUtils.TruncateAt.END);
            copy.addView(subtitleView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 1)));
        }
        row.addView(copy, UIHelpers.weight(1));
        if (!TextUtils.isEmpty(end)) {
            TextView endView = UIHelpers.text(this, end, 12, UIHelpers.TEXT3, Typeface.NORMAL);
            endView.setSingleLine(true);
            endView.setEllipsize(TextUtils.TruncateAt.END);
            endView.setMaxWidth(UIHelpers.dp(this, 82));
            row.addView(endView);
        }
        ImageView chevron = new ImageView(this);
        chevron.setImageResource(R.drawable.ic_chevron_right);
        chevron.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.TEXT3));
        LinearLayout.LayoutParams chevronParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));
        chevronParams.leftMargin = UIHelpers.dp(this, 4);
        row.addView(chevron, chevronParams);
        return row;
    }

    private View sourceOverflowButton() {
        TextView button = UIHelpers.text(this, "⋮", 24, UIHelpers.ACCENT, Typeface.BOLD);
        button.setGravity(Gravity.CENTER);
        button.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        button.setContentDescription("站源更多操作");
        button.setOnClickListener(v -> showSourceMenu());
        return button;
    }

    private void addTitle(LinearLayout page, String title, String badge) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(UIHelpers.text(this, title, 24, UIHelpers.TEXT, Typeface.BOLD), UIHelpers.weight(1));
        if (badge != null) row.addView(UIHelpers.chip(this, badge, true));
        if ("书架".equals(title)) {
            ImageView theme = new ImageView(this);
            theme.setImageResource(R.drawable.rem_reader_resume);
            theme.setScaleType(ImageView.ScaleType.CENTER_CROP);
            theme.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 16), Color.TRANSPARENT));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(UIHelpers.dp(this, 30), UIHelpers.dp(this, 30));
            lp.leftMargin = UIHelpers.dp(this, 8);
            row.addView(theme, lp);
        }
        page.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 14)));
    }

    private TextView menuItem(String title, String end, Runnable action) {
        TextView item = UIHelpers.menuItem(this, title, end);
        item.setOnClickListener(v -> action.run());
        return item;
    }

    private void showSourceMenu() {
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        final PopupWindow[] popup = new PopupWindow[1];
        actions.addView(settingsSheetAction(R.drawable.ic_source, "导入", () -> {
            popup[0].dismiss();
            openImportSourceConfig();
        }));
        actions.addView(UIHelpers.divider(this));
        actions.addView(settingsSheetAction(R.drawable.ic_auto, "导出", () -> {
            popup[0].dismiss();
            exportSourceConfig();
        }));
        actions.addView(UIHelpers.divider(this));
        actions.addView(settingsSheetAction(R.drawable.ic_lightning, "检测可用性", () -> {
            popup[0].dismiss();
            healthCheck();
        }));
        popup[0] = showSettingsSheet("站源操作", actions);
    }

    private View settingsSheetAction(int iconRes, String title, Runnable onClick) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setMinimumHeight(UIHelpers.dp(this, 42));
        row.setPadding(UIHelpers.dp(this, 4), 0, UIHelpers.dp(this, 4), 0);
        ImageView icon = UIHelpers.vectorIconButton(this, iconRes, UIHelpers.ACCENT, 4);
        row.addView(icon, new LinearLayout.LayoutParams(UIHelpers.dp(this, 24), UIHelpers.dp(this, 24)));
        TextView label = UIHelpers.text(this, title, 14, UIHelpers.TEXT, Typeface.NORMAL);
        LinearLayout.LayoutParams labelParams = new LinearLayout.LayoutParams(-2, -2);
        labelParams.leftMargin = UIHelpers.dp(this, 8);
        row.addView(label, labelParams);
        row.setOnClickListener(v -> onClick.run());
        return row;
    }

    private View emptyState(int iconRes, String title, String desc, String action, Runnable onClick) {
        return remState(R.drawable.rem_empty, title, desc, action, onClick);
    }

    private View loadingState(String title, String desc) {
        return remState(R.drawable.rem_loading, title, desc, "", null);
    }

    private View remState(int imageRes, String title, String desc, String action, Runnable onClick) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
        box.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));
        box.setMinimumHeight(UIHelpers.dp(this, 280));

        ImageView art = new ImageView(this);
        art.setImageResource(imageRes);
        art.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        box.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(this, 142), UIHelpers.dp(this, 142)));

        TextView titleView = UIHelpers.text(this, title, 16, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(-1, -2);
        titleParams.setMargins(0, UIHelpers.dp(this, 6), 0, 0);
        box.addView(titleView, titleParams);

        TextView description = UIHelpers.text(this, desc, 13, UIHelpers.TEXT3, Typeface.NORMAL);
        description.setGravity(Gravity.CENTER);
        description.setMaxLines(2);
        description.setEllipsize(TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams descParams = new LinearLayout.LayoutParams(-1, -2);
        descParams.setMargins(0, UIHelpers.dp(this, 5), 0, 0);
        box.addView(description, descParams);
        if (!TextUtils.isEmpty(action) && onClick != null) {
            Button button = UIHelpers.primaryButton(this, action);
            button.setOnClickListener(v -> onClick.run());
            box.addView(button, UIHelpers.marginTop(UIHelpers.dp(this, 132), UIHelpers.dp(this, 12), -2, UIHelpers.dp(this, 38)));
        }
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
        String message = error == null ? "请稍后重试" : clean(error.getMessage(), "请稍后重试");
        root.addView(remState(R.drawable.rem_error, title, message, "重试",
                backAction == null ? () -> showTab(currentTab) : backAction), UIHelpers.match());
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
        list.post(() -> showReaderResumeHint(savedPosition));
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
        showRemToast(message);
    }

    private void showRemToast(String message) {
        showRemToast(R.drawable.rem_reader_boundary, message);
    }

    private void showRemToast(int imageRes, String message) {
        if (root == null) {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
            return;
        }
        LinearLayout hint = new LinearLayout(this);
        hint.setOrientation(LinearLayout.HORIZONTAL);
        hint.setGravity(Gravity.CENTER_VERTICAL);
        hint.setPadding(UIHelpers.dp(this, 7), UIHelpers.dp(this, 5), UIHelpers.dp(this, 12), UIHelpers.dp(this, 5));
        hint.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 8), UIHelpers.BORDER));
        hint.setElevation(UIHelpers.dp(this, 3));
        ImageView art = new ImageView(this);
        art.setImageResource(imageRes);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        hint.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(this, 32), UIHelpers.dp(this, 32)));
        TextView label = UIHelpers.text(this, message, 12, UIHelpers.TEXT, Typeface.BOLD);
        LinearLayout.LayoutParams labelLp = new LinearLayout.LayoutParams(-2, -2);
        labelLp.leftMargin = UIHelpers.dp(this, 7);
        hint.addView(label, labelLp);
        root.addView(hint, UIHelpers.frame(-2, UIHelpers.dp(this, 44), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL, 0, 0, 0, UIHelpers.dp(this, 72)));
        main.postDelayed(() -> {
            if (hint.getParent() == root) root.removeView(hint);
        }, 1600L);
    }

    private LinearLayout settingsScenePage(String scene, String title, String meta) {
        enterScreen();
        applyThemeAndSystemBars();
        settingsScene = scene;
        settingsSceneBackToSources = false;
        sourceManagementVisible = false;
        historyVisible = false;
        root.removeAllViews();
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        scroll.setBackgroundColor(UIHelpers.BG);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 24));
        settingsHeader(page, title, meta);
        scroll.addView(page, UIHelpers.matchWrap());
        root.addView(scroll, UIHelpers.match());
        return page;
    }

    private LinearLayout settingsInfoRow(int iconRes, String title, String subtitle, String end) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 9), UIHelpers.dp(this, 7), UIHelpers.dp(this, 9), UIHelpers.dp(this, 7));
        row.setMinimumHeight(UIHelpers.dp(this, 52));
        FrameLayout iconHost = new FrameLayout(this);
        iconHost.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 6), Color.TRANSPARENT));
        ImageView icon = UIHelpers.vectorIconButton(this, iconRes, UIHelpers.ACCENT, 5);
        iconHost.addView(icon, UIHelpers.match());
        LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28));
        iconParams.rightMargin = UIHelpers.dp(this, 9);
        row.addView(iconHost, iconParams);
        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        TextView titleView = UIHelpers.text(this, title, 14, UIHelpers.TEXT, Typeface.NORMAL);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        copy.addView(titleView);
        if (!TextUtils.isEmpty(subtitle)) copy.addView(UIHelpers.text(this, subtitle, 11, UIHelpers.TEXT3, Typeface.NORMAL));
        row.addView(copy, UIHelpers.weight(1));
        if (!TextUtils.isEmpty(end)) row.addView(UIHelpers.text(this, end, 12, UIHelpers.TEXT3, Typeface.NORMAL));
        return row;
    }

    private LinearLayout settingsBottomActions(String secondary, Runnable secondaryAction, String primary, Runnable primaryAction) {
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setPadding(0, UIHelpers.dp(this, 18), 0, 0);
        if (!TextUtils.isEmpty(secondary)) {
            Button button = UIHelpers.secondaryButton(this, secondary);
            button.setOnClickListener(v -> secondaryAction.run());
            actions.addView(button, UIHelpers.buttonWeight(this, 1));
            actions.addView(UIHelpers.space(this, UIHelpers.dp(this, 8), 1));
        }
        Button button = UIHelpers.primaryButton(this, primary);
        button.setOnClickListener(v -> primaryAction.run());
        actions.addView(button, UIHelpers.buttonWeight(this, 1));
        return actions;
    }

    private void showCacheCleanup() {
        LinearLayout page = settingsScenePage("cache", "缓存清理", cacheSize);
        page.addView(settingsSectionText("将被清理"));
        LinearLayout clear = settingsList();
        clear.addView(settingsInfoRow(R.drawable.ic_bookshelf, "漫画图片缓存", "下次阅读时重新获取", cacheSize));
        clear.addView(UIHelpers.divider(this));
        clear.addView(settingsInfoRow(R.drawable.ic_source, "页面解析与验证缓存", "不会删除站源配置", "清理"));
        page.addView(clear);
        page.addView(settingsSectionText("始终保留"));
        LinearLayout keep = settingsList();
        keep.addView(settingsInfoRow(R.drawable.ic_history, "书架收藏、历史与进度", "", "保留"));
        page.addView(keep);
        page.addView(settingsBottomActions("取消", () -> showTab(2), "确认清理", () -> {
            showCacheCleanupLoading();
            main.post(this::clearAppCache);
        }));
    }

    private void showCacheCleanupLoading() {
        LinearLayout page = settingsScenePage("cache-loading", "缓存清理", "处理中");
        page.addView(remState(R.drawable.rem_loading, "正在清理", "收藏与阅读记录会保留", "", null));
    }

    private void showAboutApp() {
        LinearLayout page = settingsScenePage("about", "关于 App", BuildConfig.VERSION_NAME);
        ImageView mark = new ImageView(this);
        mark.setImageResource(R.drawable.rem_reader_resume);
        mark.setScaleType(ImageView.ScaleType.CENTER_CROP);
        mark.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 16), Color.TRANSPARENT));
        LinearLayout.LayoutParams markParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 68), UIHelpers.dp(this, 68));
        markParams.gravity = Gravity.CENTER_HORIZONTAL;
        markParams.topMargin = UIHelpers.dp(this, 16);
        page.addView(mark, markParams);
        TextView name = UIHelpers.text(this, "XX Comic", 18, UIHelpers.TEXT, Typeface.BOLD);
        name.setGravity(Gravity.CENTER);
        page.addView(name, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8), -1, -2));
        TextView desc = UIHelpers.text(this, "多站源漫画浏览与本地阅读工具\n收藏、历史和设置均保存在本机", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        desc.setGravity(Gravity.CENTER);
        page.addView(desc, UIHelpers.marginTop(-1, UIHelpers.dp(this, 5), -1, -2));
        page.addView(settingsSectionText("本地信息"));
        LinearLayout list = settingsList();
        list.addView(settingsPlainRow("版本", installedVersionLabel()));
        list.addView(UIHelpers.divider(this));
        list.addView(settingsPlainRow("数据说明", "仅本地"));
        list.addView(UIHelpers.divider(this));
        list.addView(settingsPlainRow("已接入站源", "12 个"));
        page.addView(list);
    }

    private View settingsPlainRow(String title, String end) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 10), 0, UIHelpers.dp(this, 10), 0);
        row.setMinimumHeight(UIHelpers.dp(this, 44));
        row.addView(UIHelpers.text(this, title, 14, UIHelpers.TEXT, Typeface.NORMAL), UIHelpers.weight(1));
        row.addView(UIHelpers.text(this, end, 12, UIHelpers.TEXT3, Typeface.NORMAL));
        return row;
    }

    private void showInfo(String title, String message) {
        styledDialog(title, message, "知道了", null, null, null);
    }

    private String installedVersionLabel() {
        return BuildConfig.VERSION_NAME + " (" + BuildConfig.VERSION_CODE + ")";
    }

    private void checkForUpdate() {
        if (updateRunning) {
            showToast("正在处理版本更新");
            return;
        }
        updateRunning = true;
        int generation = ++updateGeneration;
        showUpdateLoading();
        updateFuture = miscIo.submit(() -> {
            try {
                AppRelease release = fetchAppRelease();
                postMainIfAlive(() -> {
                    if (generation != updateGeneration) return;
                    updateRunning = false;
                    availableUpdateRelease = release;
                    boolean same = BuildConfig.VERSION_NAME.equals(release.versionName)
                            && BuildConfig.VERSION_CODE == release.versionCode;
                    if (same) {
                        showUpdateLatest();
                    } else {
                        showUpdateAvailable(release);
                    }
                });
            } catch (Exception error) {
                postUpdateFailure("检查更新失败", error, generation);
            }
        });
    }

    private void showUpdateLoading() {
        LinearLayout page = settingsScenePage("update-loading", "版本更新", "当前 " + BuildConfig.VERSION_NAME);
        page.addView(remState(R.drawable.rem_loading, "正在检查更新", "很快就好", "", null));
    }

    private void showUpdateAvailable(AppRelease release) {
        if (release == null) {
            checkForUpdate();
            return;
        }
        availableUpdateRelease = release;
        LinearLayout page = settingsScenePage("update-available", "版本更新", "发现新版本");
        LinearLayout card = settingsList();
        card.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 11), UIHelpers.dp(this, 12), UIHelpers.dp(this, 11));
        TextView title = UIHelpers.text(this, "XX Comic " + release.versionName, 17, UIHelpers.TEXT, Typeface.BOLD);
        card.addView(title);
        card.addView(UIHelpers.text(this, "当前版本 " + BuildConfig.VERSION_NAME + " · " + formatBytes(release.size), 12,
                UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));
        TextView note = UIHelpers.text(this, "包含最新的界面优化与稳定性修复", 13, UIHelpers.TEXT2, Typeface.NORMAL);
        card.addView(note, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));
        page.addView(card);
        page.addView(settingsBottomActions("稍后", () -> showTab(2), "下载更新", () -> startUpdateDownload(release)));
    }

    private void showUpdateLatest() {
        LinearLayout page = settingsScenePage("update-latest", "版本更新", "当前 " + BuildConfig.VERSION_NAME);
        page.addView(remState(R.drawable.rem_reader_resume, "已经是最新版本", "XX Comic " + BuildConfig.VERSION_NAME, "", null));
        page.addView(settingsBottomActions("", null, "重新安装", () -> {
            if (availableUpdateRelease != null) startUpdateDownload(availableUpdateRelease);
        }));
    }

    private void showUpdateFailure() {
        LinearLayout page = settingsScenePage("update-error", "版本更新", "检查失败");
        page.addView(remState(R.drawable.rem_error, "没检查到新版本", "稍后再试", "重试", this::checkForUpdate));
    }

    private AppRelease fetchAppRelease() throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(UPDATE_METADATA_URL).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("User-Agent", IMAGE_USER_AGENT);
        try {
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) throw new IOException("HTTP " + code);
            JSONObject object;
            try (InputStream stream = connection.getInputStream()) {
                object = new JSONObject(new String(readAllBytes(stream), "UTF-8"));
            }
            String versionName = object.optString("versionName", "");
            int versionCode = object.optInt("versionCode", 0);
            long size = object.optLong("size", 0L);
            String sha256 = object.optString("sha256", "").toLowerCase(Locale.US);
            if (!versionName.matches("[0-9]+(?:\\.[0-9]+){2}")
                    || versionCode < 1
                    || size < 1L
                    || !sha256.matches("[0-9a-f]{64}")) {
                throw new IOException("更新元数据无效");
            }
            return new AppRelease(versionName, versionCode, size, sha256);
        } finally {
            connection.disconnect();
        }
    }

    private void startUpdateDownload(AppRelease release) {
        if (updateRunning) {
            showToast("正在处理版本更新");
            return;
        }
        updateRunning = true;
        int generation = ++updateGeneration;
        availableUpdateRelease = release;
        showUpdateDownload(release, 0);
        updateFuture = miscIo.submit(() -> {
            try {
                File apk = downloadAndVerifyUpdate(release, progress -> postMainIfAlive(() -> {
                    if (generation != updateGeneration) return;
                    if (!"update-download".equals(settingsScene)) return;
                    if (settingsUpdateProgressBar != null) settingsUpdateProgressBar.setProgress(progress);
                    if (settingsUpdateProgressText != null) settingsUpdateProgressText.setText(progress + "%");
                    if (settingsUpdateProgressMeta != null) settingsUpdateProgressMeta.setText("已下载 " + progress + "% · " + formatBytes(release.size));
                }));
                postMainIfAlive(() -> {
                    if (generation != updateGeneration) return;
                    installUpdate(apk);
                });
            } catch (Exception error) {
                if (generation != updateGeneration) return;
                if (isExpectedTaskCancellation(error)) {
                    postMainIfAlive(() -> {
                        updateRunning = false;
                        showTab(2);
                    });
                    return;
                }
                postUpdateFailure("下载更新失败", error, generation);
            }
        });
    }

    private void showUpdateDownload(AppRelease release, int progress) {
        if (release == null) return;
        LinearLayout page = settingsScenePage("update-download", "正在下载更新", progress + "%");
        ImageView art = new ImageView(this);
        art.setImageResource(R.drawable.rem_loading);
        art.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        LinearLayout.LayoutParams artParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 132), UIHelpers.dp(this, 132));
        artParams.gravity = Gravity.CENTER_HORIZONTAL;
        artParams.topMargin = UIHelpers.dp(this, 18);
        page.addView(art, artParams);
        TextView title = UIHelpers.text(this, "下载中", 16, UIHelpers.TEXT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        page.addView(title);
        settingsUpdateProgressMeta = UIHelpers.text(this, "已下载 " + progress + "% · " + formatBytes(release.size), 12, UIHelpers.TEXT3, Typeface.NORMAL);
        settingsUpdateProgressMeta.setGravity(Gravity.CENTER);
        page.addView(settingsUpdateProgressMeta, UIHelpers.marginTop(-1, UIHelpers.dp(this, 4), -1, -2));
        settingsUpdateProgressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        settingsUpdateProgressBar.setMax(100);
        settingsUpdateProgressBar.setProgress(progress);
        settingsUpdateProgressBar.setProgressTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
        LinearLayout.LayoutParams progressParams = new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 6));
        progressParams.setMargins(UIHelpers.dp(this, 20), UIHelpers.dp(this, 16), UIHelpers.dp(this, 20), 0);
        page.addView(settingsUpdateProgressBar, progressParams);
        settingsUpdateProgressText = UIHelpers.text(this, progress + "%", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        settingsUpdateProgressText.setGravity(Gravity.CENTER);
        page.addView(settingsUpdateProgressText, UIHelpers.marginTop(-1, UIHelpers.dp(this, 5), -1, -2));
        page.addView(settingsBottomActions("", null, "取消下载", () -> {
            cancelUpdateDownload();
            showTab(2);
        }));
    }

    private void cancelUpdateDownload() {
        updateGeneration++;
        if (updateFuture != null) updateFuture.cancel(true);
        updateFuture = null;
        updateRunning = false;
        settingsUpdateProgressBar = null;
        settingsUpdateProgressText = null;
        settingsUpdateProgressMeta = null;
    }

    private File downloadAndVerifyUpdate(AppRelease release, UpdateProgress listener) throws Exception {
        File directory = new File(getCacheDir(), "app-update");
        if (!directory.exists() && !directory.mkdirs()) throw new IOException("无法创建更新缓存");
        File apk = new File(directory, UPDATE_APK_FILE_NAME);
        File part = new File(directory, UPDATE_APK_FILE_NAME + ".part");
        Exception lastError = null;
        for (String updateUrl : UPDATE_APK_URLS) {
            if (part.exists() && !part.delete()) throw new IOException("无法清理旧下载");
            try {
                downloadAndVerifyUpdateFromUrl(updateUrl, release, part, listener);
                if (apk.exists() && !apk.delete()) throw new IOException("无法替换旧安装包");
                if (!part.renameTo(apk)) throw new IOException("无法保存安装包");
                return apk;
            } catch (Exception error) {
                if (isExpectedTaskCancellation(error)) throw error;
                lastError = error;
                part.delete();
            }
        }
        if (lastError != null) throw lastError;
        throw new IOException("没有可用的更新地址");
    }

    private void downloadAndVerifyUpdateFromUrl(String updateUrl, AppRelease release,
                                                 File part, UpdateProgress listener) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(updateUrl).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(30000);
        connection.setRequestProperty("Accept", APK_MIME_TYPE);
        connection.setRequestProperty("User-Agent", IMAGE_USER_AGENT);
        try {
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) throw new IOException("HTTP " + code);
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            long total = 0L;
            int reported = -1;
            try (InputStream input = connection.getInputStream(); FileOutputStream output = new FileOutputStream(part)) {
                byte[] buffer = new byte[32768];
                int read;
                while ((read = input.read(buffer)) != -1) {
                    if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("下载已取消");
                    output.write(buffer, 0, read);
                    digest.update(buffer, 0, read);
                    total += read;
                    int percent = (int) Math.min(100L, total * 100L / release.size);
                    if (percent != reported) {
                        reported = percent;
                        listener.onProgress(percent);
                    }
                }
                output.getFD().sync();
            }
            String actualHash = hex(digest.digest());
            if (total != release.size || !actualHash.equals(release.sha256)) {
                throw new IOException("安装包校验失败");
            }
        } finally {
            connection.disconnect();
        }
    }

    private void installUpdate(File apk) {
        pendingUpdateApk = apk;
        if (!canInstallPackages()) {
            try {
                Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + getPackageName()));
                startActivityForResult(intent, INSTALL_PACKAGES_REQUEST);
            } catch (Exception error) {
                updateRunning = false;
                pendingUpdateApk = null;
                showInfo("无法安装更新", clean(error.getMessage(), "无法打开安装权限设置"));
            }
            return;
        }
        openPackageInstaller(apk);
    }

    private boolean canInstallPackages() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || getPackageManager().canRequestPackageInstalls();
    }

    private void openPackageInstaller(File apk) {
        try {
            Uri uri = Uri.parse("content://" + getPackageName() + ".updates/" + UPDATE_APK_FILE_NAME);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, APK_MIME_TYPE);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(intent);
        } catch (Exception error) {
            showInfo("无法安装更新", clean(error.getMessage(), "无法打开系统安装程序"));
        } finally {
            updateRunning = false;
            pendingUpdateApk = null;
        }
    }

    private void postUpdateFailure(String title, Exception error, int generation) {
        postMainIfAlive(() -> {
            if (generation != updateGeneration) return;
            updateRunning = false;
            appendErrorLog(title, error);
            showUpdateFailure();
        });
    }

    private String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) result.append(String.format(Locale.US, "%02x", value & 0xff));
        return result.toString();
    }

    private interface UpdateProgress {
        void onProgress(int percent);
    }

    private static final class AppRelease {
        final String versionName;
        final int versionCode;
        final long size;
        final String sha256;

        AppRelease(String versionName, int versionCode, long size, String sha256) {
            this.versionName = versionName;
            this.versionCode = versionCode;
            this.size = size;
            this.sha256 = sha256;
        }
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
        activeErrorLog = "";
        String[] entries = TextUtils.isEmpty(logs) ? new String[0] : logs.split("\\n\\n");
        LinearLayout page = settingsScenePage("errors", "错误日志", entries.length + " 条 · 导出 · 清理");
        if (entries.length == 0) {
            page.addView(remState(R.drawable.rem_empty, "这里很干净", "暂时没有错误日志", "", null));
            return;
        }
        LinearLayout list = settingsList();
        for (int i = 0; i < entries.length; i++) {
            String entry = entries[i];
            String[] lines = entry.split("\\n", 3);
            String header = lines.length > 0 ? clean(lines[0], "错误日志") : "错误日志";
            String detail = lines.length > 1 ? clean(lines[1], "查看详细信息") : "查看详细信息";
            LinearLayout row = settingsErrorRow(header, detail, () -> showErrorLogDetail(entry));
            list.addView(row);
            if (i < entries.length - 1) list.addView(UIHelpers.divider(this));
        }
        page.addView(list);
        TextView note = UIHelpers.text(this, "日志只保存在本机，导出时调用系统文件选择器。", 11, UIHelpers.TEXT3, Typeface.NORMAL);
        page.addView(note, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8), -1, -2));
        page.addView(settingsBottomActions("清理", this::confirmClearErrorLogs, "导出", this::exportErrorLogs));
    }

    private LinearLayout settingsErrorRow(String title, String detail, Runnable onClick) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 7), UIHelpers.dp(this, 8), UIHelpers.dp(this, 7));
        row.setMinimumHeight(UIHelpers.dp(this, 54));
        FrameLayout mark = new FrameLayout(this);
        mark.setBackground(UIHelpers.round(UIHelpers.isNightTheme() ? Color.rgb(70, 39, 53) : Color.rgb(255, 240, 244), UIHelpers.dp(this, 6), Color.TRANSPARENT));
        ImageView icon = UIHelpers.vectorIconButton(this, R.drawable.ic_lightning, UIHelpers.DANGER, 5);
        mark.addView(icon, UIHelpers.match());
        LinearLayout.LayoutParams markParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28));
        markParams.rightMargin = UIHelpers.dp(this, 9);
        row.addView(mark, markParams);
        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        TextView titleView = UIHelpers.text(this, title, 13, UIHelpers.TEXT, Typeface.NORMAL);
        titleView.setMaxLines(1);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(titleView);
        TextView detailView = UIHelpers.text(this, detail, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        detailView.setMaxLines(1);
        detailView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(detailView);
        row.addView(copy, UIHelpers.weight(1));
        TextView action = UIHelpers.text(this, "查看", 12, UIHelpers.ACCENT, Typeface.NORMAL);
        row.addView(action);
        row.setOnClickListener(v -> onClick.run());
        return row;
    }

    private void showErrorLogDetail(String entry) {
        activeErrorLog = entry;
        LinearLayout page = settingsScenePage("error-detail", "错误日志", "详细信息");
        String[] lines = entry.split("\\n", 2);
        page.addView(settingsSectionText(lines.length > 0 ? clean(lines[0], "日志详情") : "日志详情"));
        TextView code = UIHelpers.text(this, entry, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        code.setTypeface(Typeface.MONOSPACE);
        code.setTextIsSelectable(true);
        code.setLongClickable(true);
        code.setPadding(UIHelpers.dp(this, 10), UIHelpers.dp(this, 10), UIHelpers.dp(this, 10), UIHelpers.dp(this, 10));
        code.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 7), UIHelpers.BORDER));
        page.addView(code);
        TextView note = UIHelpers.text(this, "可长按复制。日志不会自动发送给任何服务器。", 11, UIHelpers.TEXT3, Typeface.NORMAL);
        page.addView(note, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8), -1, -2));
        page.addView(settingsBottomActions("复制", () -> copyErrorLog(entry), "导出日志", this::exportErrorLogs));
    }

    private void copyErrorLog(String entry) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) clipboard.setPrimaryClip(ClipData.newPlainText("XX Comic 错误日志", entry));
        showRemToast("日志已复制");
    }

    private void confirmClearErrorLogs() {
        styledDialog("清空错误日志", "所有本地错误记录都会移除。", "清空", this::clearErrorLogs, "取消", null);
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
        showTab(2);
        main.post(() -> showRemToast("错误日志已清理"));
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
                        showSourceManagement();
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
                    resetCategoryFilters();
                    sourceFilterGroups.clear();
                    sourceCategoriesFailed = false;
                    searchResults.clear();
                    showSourceManagement();
                    showRemToast("站源配置已导入");
                    if (!categoriesFollowInitialList(selectedSourceId)) loadSourceCategories();
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
        sources.put(aikanConfig.withEnabled(aikanEnabled).toJson());
        sources.put(gmhConfig.withEnabled(gmhEnabled).toJson());
        sources.put(mh18Config.withEnabled(mh18Enabled).toJson());
        sources.put(jmcomicConfig.withEnabled(jmcomicEnabled).toJson());
        sources.put(mkzhanConfig.withEnabled(mkzhanEnabled).toJson());
        sources.put(hiperdexConfig.withEnabled(hiperdexEnabled).toJson());
        sources.put(manhuaguiConfig.withEnabled(manhuaguiEnabled).toJson());
        sources.put(hanman18Config.withEnabled(hanman18Enabled).toJson());
        sources.put(d5d6Config.withEnabled(d5d6Enabled).toJson());
        sources.put(manbenConfig.withEnabled(manbenEnabled).toJson());
        sources.put(manhuazhanConfig.withEnabled(manhuazhanEnabled).toJson());
        sources.put(bbyinConfig.withEnabled(bbyinEnabled).toJson());
        sources.put(antbywConfig.withEnabled(antbywEnabled).toJson());
        sources.put(cuimhConfig.withEnabled(cuimhEnabled).toJson());
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
                } else if (aikanConfig.id.equals(id)) {
                    aikanConfig = SourceConfig.fromJson(item, SourceConfig.aikan(true));
                    aikanEnabled = aikanConfig.enabled;
                } else if (gmhConfig.id.equals(id)) {
                    gmhConfig = SourceConfig.fromJson(item, SourceConfig.gmh(true));
                    gmhEnabled = gmhConfig.enabled;
                } else if (mh18Config.id.equals(id)) {
                    mh18Config = SourceConfig.fromJson(item, SourceConfig.mh18(true));
                    mh18Enabled = mh18Config.enabled;
                } else if (jmcomicConfig.id.equals(id)) {
                    jmcomicConfig = SourceConfig.fromJson(item, SourceConfig.jmcomic(true));
                    jmcomicEnabled = jmcomicConfig.enabled;
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
                } else if (manhuazhanConfig.id.equals(id)) {
                    manhuazhanConfig = SourceConfig.fromJson(item, SourceConfig.manhuazhan(true));
                    manhuazhanEnabled = manhuazhanConfig.enabled;
                } else if (bbyinConfig.id.equals(id)) {
                    bbyinConfig = SourceConfig.fromJson(item, SourceConfig.bbyin(true));
                    bbyinEnabled = bbyinConfig.enabled;
                } else if (antbywConfig.id.equals(id)) {
                    antbywConfig = SourceConfig.fromJson(item, SourceConfig.antbyw(true));
                    antbywEnabled = antbywConfig.enabled;
                } else if (cuimhConfig.id.equals(id)) {
                    cuimhConfig = SourceConfig.fromJson(item, SourceConfig.cuimh(true));
                    cuimhEnabled = cuimhConfig.enabled;
                }
            }
        }
        JSONArray builtins = root.optJSONArray("builtins");
        if (builtins != null) {
            for (int i = 0; i < builtins.length(); i++) {
                JSONObject item = builtins.getJSONObject(i);
                String id = item.optString("id");
                if (baoziConfig.id.equals(id)) sourceEnabled = item.optBoolean("enabled", true);
                if (aikanConfig.id.equals(id)) aikanEnabled = item.optBoolean("enabled", true);
                if (gmhConfig.id.equals(id)) gmhEnabled = item.optBoolean("enabled", true);
                if (mh18Config.id.equals(id)) mh18Enabled = item.optBoolean("enabled", true);
                if (jmcomicConfig.id.equals(id)) jmcomicEnabled = item.optBoolean("enabled", true);
                if (mkzhanConfig.id.equals(id)) mkzhanEnabled = item.optBoolean("enabled", true);
                if (hiperdexConfig.id.equals(id)) hiperdexEnabled = item.optBoolean("enabled", true);
                if (manhuaguiConfig.id.equals(id)) manhuaguiEnabled = item.optBoolean("enabled", true);
                if (hanman18Config.id.equals(id)) hanman18Enabled = item.optBoolean("enabled", true);
                if (d5d6Config.id.equals(id)) d5d6Enabled = item.optBoolean("enabled", true);
                if (manbenConfig.id.equals(id)) manbenEnabled = item.optBoolean("enabled", true);
                if (manhuazhanConfig.id.equals(id)) manhuazhanEnabled = item.optBoolean("enabled", true);
                if (bbyinConfig.id.equals(id)) bbyinEnabled = item.optBoolean("enabled", true);
                if (antbywConfig.id.equals(id)) antbywEnabled = item.optBoolean("enabled", true);
                if (cuimhConfig.id.equals(id)) cuimhEnabled = item.optBoolean("enabled", true);
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
        settingsSceneBackToSources = true;
        sourceHealthRows = new ArrayList<>();
        cancelSourceHealthCheck();
        int generation = sourceHealthGeneration;
        showSourceHealthLoading();
        sourceHealthFuture = sourceHealthIo.submit(() -> {
            List<String> rows = new ArrayList<>();
            for (ComicSource client : enabledBuiltinSources()) {
                if (Thread.currentThread().isInterrupted()) return;
                boolean ok = client.healthCheck();
                if (Thread.currentThread().isInterrupted()) return;
                rows.add(client.name() + "\u001f" + (ok ? "可用" : "不可用"));
            }
            addDisabledSourceHealthRows(rows);
            postMainIfAlive(() -> {
                if (generation != sourceHealthGeneration) return;
                sourceHealthFuture = null;
                sourceHealthRows = rows;
                showSourceHealthResults();
            });
        });
    }

    private void cancelSourceHealthCheck() {
        sourceHealthGeneration++;
        if (sourceHealthFuture != null) sourceHealthFuture.cancel(true);
        sourceHealthFuture = null;
    }

    private void addDisabledSourceHealthRows(List<String> rows) {
        if (!sourceEnabled) rows.add(baoziConfig.name + "\u001f已关闭");
        if (!aikanEnabled) rows.add(aikanConfig.name + "\u001f已关闭");
        if (!gmhEnabled) rows.add(gmhConfig.name + "\u001f已关闭");
        if (!mh18Enabled) rows.add(mh18Config.name + "\u001f已关闭");
        if (!jmcomicEnabled) rows.add(jmcomicConfig.name + "\u001f已关闭");
        if (!mkzhanEnabled) rows.add(mkzhanConfig.name + "\u001f已关闭");
        if (!hiperdexEnabled) rows.add(hiperdexConfig.name + "\u001f已关闭");
        if (!manhuaguiEnabled) rows.add(manhuaguiConfig.name + "\u001f已关闭");
        if (!hanman18Enabled) rows.add(hanman18Config.name + "\u001f已关闭");
        if (!d5d6Enabled) rows.add(d5d6Config.name + "\u001f已关闭");
        if (!manbenEnabled) rows.add(manbenConfig.name + "\u001f已关闭");
        if (!manhuazhanEnabled) rows.add(manhuazhanConfig.name + "\u001f已关闭");
        if (!bbyinEnabled) rows.add(bbyinConfig.name + "\u001f已关闭");
        if (!antbywEnabled) rows.add(antbywConfig.name + "\u001f已关闭");
        if (!cuimhEnabled) rows.add(cuimhConfig.name + "\u001f已关闭");
    }

    private void showSourceHealthLoading() {
        LinearLayout page = settingsScenePage("health-loading", "检测可用性", "正在检测");
        settingsSceneBackToSources = true;
        page.addView(remState(R.drawable.rem_loading, "正在检测站源", "稍等一下", "", null));
    }

    private void showSourceHealthResults() {
        LinearLayout page = settingsScenePage("health-results", "检测可用性", sourceHealthRows.size() + " 个已完成");
        settingsSceneBackToSources = true;
        LinearLayout list = settingsList();
        for (int i = 0; i < sourceHealthRows.size(); i++) {
            String[] parts = sourceHealthRows.get(i).split("\\u001f", 2);
            String name = parts.length > 0 ? parts[0] : "站源";
            String status = parts.length > 1 ? parts[1] : "不可用";
            list.addView(sourceHealthRow(name, status));
            if (i < sourceHealthRows.size() - 1) list.addView(UIHelpers.divider(this));
        }
        page.addView(list);
        page.addView(settingsBottomActions("", null, "完成", () -> {
            settingsSceneBackToSources = false;
            showSourceManagement();
        }));
    }

    private View sourceHealthRow(String name, String status) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 9), 0, UIHelpers.dp(this, 9), 0);
        row.setMinimumHeight(UIHelpers.dp(this, 42));
        row.addView(UIHelpers.text(this, name, 13, UIHelpers.TEXT, Typeface.NORMAL), UIHelpers.weight(1));
        int color = "可用".equals(status) ? UIHelpers.GREEN : "已关闭".equals(status) ? UIHelpers.TEXT3 : UIHelpers.DANGER;
        TextView statusView = UIHelpers.text(this, status, 12, color, Typeface.NORMAL);
        statusView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        row.addView(statusView);
        return row;
    }

    private void rebuildSourceClients() {
        sourceClient = new BaoziComicSource(baoziConfig.withEnabled(sourceEnabled));
        mhua5Client = new Mhua5ComicSource();
        aikanClient = new AikanComicSource(aikanConfig.withEnabled(aikanEnabled));
        gmhClient = new GmhComicSource(gmhConfig.withEnabled(gmhEnabled));
        mh18Client = new Mh18ComicSource(mh18Config.withEnabled(mh18Enabled), mh18BrowserSession);
        jmcomicClient = new JmComicSource(jmcomicConfig.withEnabled(jmcomicEnabled), jmcomicBrowserSession);
        mkzhanClient = new MkzhanComicSource(mkzhanConfig.withEnabled(mkzhanEnabled));
        hiperdexClient = new HiperdexComicSource(hiperdexConfig.withEnabled(hiperdexEnabled));
        manhuaguiClient = new ManhuaguiComicSource(manhuaguiConfig.withEnabled(manhuaguiEnabled));
        hanman18Client = new Hanman18ComicSource(hanman18Config.withEnabled(hanman18Enabled));
        d5d6Client = new D5d6ComicSource(d5d6Config.withEnabled(d5d6Enabled));
        manbenClient = new ManbenComicSource(manbenConfig.withEnabled(manbenEnabled));
        manhuazhanClient = new FiveUmComicSource(manhuazhanConfig.withEnabled(manhuazhanEnabled));
        bbyinClient = new FiveUmComicSource(bbyinConfig.withEnabled(bbyinEnabled));
        antbywClient = new AntbywComicSource(antbywConfig.withEnabled(antbywEnabled));
        cuimhClient = new CuimhComicSource(cuimhConfig.withEnabled(cuimhEnabled));
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
        aikanEnabled = prefs.getBoolean("source.aikan.enabled", true);
        gmhEnabled = prefs.getBoolean("source.gmh.enabled", true);
        mh18Enabled = prefs.getBoolean("source.mh18.enabled", true);
        jmcomicEnabled = prefs.getBoolean("source.jmcomic.enabled", true);
        mkzhanEnabled = prefs.getBoolean("source.mkzhan.enabled", true);
        hiperdexEnabled = prefs.getBoolean("source.hiperdex.enabled", true);
        manhuaguiEnabled = prefs.getBoolean("source.manhuagui.enabled", true);
        hanman18Enabled = prefs.getBoolean("source.hanman18.enabled", true);
        d5d6Enabled = prefs.getBoolean("source.d5d6.enabled", true);
        manbenEnabled = prefs.getBoolean("source.manben.enabled", true);
        manhuazhanEnabled = prefs.getBoolean("source.manhuazhan.enabled", true);
        bbyinEnabled = prefs.getBoolean("source.bbyin.enabled", true);
        antbywEnabled = prefs.getBoolean("source.antbyw.enabled", true);
        cuimhEnabled = prefs.getBoolean("source.cuimh.enabled", true);
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
        editor.putBoolean("source.aikan.enabled", aikanEnabled);
        editor.putBoolean("source.gmh.enabled", gmhEnabled);
        editor.putBoolean("source.mh18.enabled", mh18Enabled);
        editor.putBoolean("source.jmcomic.enabled", jmcomicEnabled);
        editor.putBoolean("source.mkzhan.enabled", mkzhanEnabled);
        editor.putBoolean("source.hiperdex.enabled", hiperdexEnabled);
        editor.putBoolean("source.manhuagui.enabled", manhuaguiEnabled);
        editor.putBoolean("source.hanman18.enabled", hanman18Enabled);
        editor.putBoolean("source.d5d6.enabled", d5d6Enabled);
        editor.putBoolean("source.manben.enabled", manbenEnabled);
        editor.putBoolean("source.manhuazhan.enabled", manhuazhanEnabled);
        editor.putBoolean("source.bbyin.enabled", bbyinEnabled);
        editor.putBoolean("source.antbyw.enabled", antbywEnabled);
        editor.putBoolean("source.cuimh.enabled", cuimhEnabled);
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
            aikanConfig = SourceConfig.aikan(aikanEnabled);
            gmhConfig = SourceConfig.gmh(gmhEnabled);
            mh18Config = SourceConfig.mh18(mh18Enabled);
            jmcomicConfig = SourceConfig.jmcomic(jmcomicEnabled);
            mkzhanConfig = SourceConfig.mkzhan(mkzhanEnabled);
            hiperdexConfig = SourceConfig.hiperdex(hiperdexEnabled);
            manhuaguiConfig = SourceConfig.manhuagui(manhuaguiEnabled);
            hanman18Config = SourceConfig.hanman18(hanman18Enabled);
            d5d6Config = SourceConfig.d5d6(d5d6Enabled);
            manbenConfig = SourceConfig.manben(manbenEnabled);
            manhuazhanConfig = SourceConfig.manhuazhan(manhuazhanEnabled);
            bbyinConfig = SourceConfig.bbyin(bbyinEnabled);
            antbywConfig = SourceConfig.antbyw(antbywEnabled);
            cuimhConfig = SourceConfig.cuimh(cuimhEnabled);
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
                } else if (SourceConfig.aikan(true).id.equals(id)) {
                    aikanConfig = SourceConfig.fromJson(item, SourceConfig.aikan(aikanEnabled));
                    aikanEnabled = aikanConfig.enabled;
                } else if (SourceConfig.gmh(true).id.equals(id)) {
                    gmhConfig = SourceConfig.fromJson(item, SourceConfig.gmh(gmhEnabled));
                    gmhEnabled = gmhConfig.enabled;
                } else if (SourceConfig.mh18(true).id.equals(id)) {
                    mh18Config = SourceConfig.fromJson(item, SourceConfig.mh18(mh18Enabled));
                    mh18Enabled = mh18Config.enabled;
                } else if (SourceConfig.jmcomic(true).id.equals(id)) {
                    jmcomicConfig = SourceConfig.fromJson(item, SourceConfig.jmcomic(jmcomicEnabled));
                    jmcomicEnabled = jmcomicConfig.enabled;
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
                } else if (SourceConfig.manhuazhan(true).id.equals(id)) {
                    manhuazhanConfig = SourceConfig.fromJson(item, SourceConfig.manhuazhan(manhuazhanEnabled));
                    manhuazhanEnabled = manhuazhanConfig.enabled;
                } else if (SourceConfig.bbyin(true).id.equals(id)) {
                    bbyinConfig = SourceConfig.fromJson(item, SourceConfig.bbyin(bbyinEnabled));
                    bbyinEnabled = bbyinConfig.enabled;
                } else if (SourceConfig.antbyw(true).id.equals(id)) {
                    antbywConfig = SourceConfig.fromJson(item, SourceConfig.antbyw(antbywEnabled));
                    antbywEnabled = antbywConfig.enabled;
                } else if (SourceConfig.cuimh(true).id.equals(id)) {
                    cuimhConfig = SourceConfig.fromJson(item, SourceConfig.cuimh(cuimhEnabled));
                    cuimhEnabled = cuimhConfig.enabled;
                }
            }
        } catch (JSONException ignored) {
            baoziConfig = SourceConfig.baozi(sourceEnabled);
            aikanConfig = SourceConfig.aikan(aikanEnabled);
            gmhConfig = SourceConfig.gmh(gmhEnabled);
            mh18Config = SourceConfig.mh18(mh18Enabled);
            jmcomicConfig = SourceConfig.jmcomic(jmcomicEnabled);
            mkzhanConfig = SourceConfig.mkzhan(mkzhanEnabled);
            hiperdexConfig = SourceConfig.hiperdex(hiperdexEnabled);
            manhuaguiConfig = SourceConfig.manhuagui(manhuaguiEnabled);
            hanman18Config = SourceConfig.hanman18(hanman18Enabled);
            d5d6Config = SourceConfig.d5d6(d5d6Enabled);
            manbenConfig = SourceConfig.manben(manbenEnabled);
            manhuazhanConfig = SourceConfig.manhuazhan(manhuazhanEnabled);
            bbyinConfig = SourceConfig.bbyin(bbyinEnabled);
            antbywConfig = SourceConfig.antbyw(antbywEnabled);
            cuimhConfig = SourceConfig.cuimh(cuimhEnabled);
        }
    }

    private String encodeSourceConfigs() {
        try {
            JSONArray array = new JSONArray();
            array.put(baoziConfig.withEnabled(sourceEnabled).toJson());
            array.put(aikanConfig.withEnabled(aikanEnabled).toJson());
            array.put(gmhConfig.withEnabled(gmhEnabled).toJson());
            array.put(mh18Config.withEnabled(mh18Enabled).toJson());
            array.put(jmcomicConfig.withEnabled(jmcomicEnabled).toJson());
            array.put(mkzhanConfig.withEnabled(mkzhanEnabled).toJson());
            array.put(hiperdexConfig.withEnabled(hiperdexEnabled).toJson());
            array.put(manhuaguiConfig.withEnabled(manhuaguiEnabled).toJson());
            array.put(hanman18Config.withEnabled(hanman18Enabled).toJson());
            array.put(d5d6Config.withEnabled(d5d6Enabled).toJson());
            array.put(manbenConfig.withEnabled(manbenEnabled).toJson());
            array.put(manhuazhanConfig.withEnabled(manhuazhanEnabled).toJson());
            array.put(bbyinConfig.withEnabled(bbyinEnabled).toJson());
            array.put(antbywConfig.withEnabled(antbywEnabled).toJson());
            array.put(cuimhConfig.withEnabled(cuimhEnabled).toJson());
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
        String sourceId = object.optString("sourceId");
        String comicId = object.optString("comicId");
        if (TextUtils.isEmpty(sourceId) && isRetiredComic(comicId)) sourceId = mhua5Client.id();
        return new ComicModels.ComicSummary(
                sourceId,
                comicId,
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
        content.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 24));
        scroll.addView(content, UIHelpers.matchWrap());

        boolean hasAny = !progress.isEmpty();
        if (hasAny) {
            TextView clear = UIHelpers.text(this, "清空", 12, UIHelpers.TEXT3, Typeface.NORMAL);
            clear.setGravity(Gravity.CENTER);
            clear.setLayoutParams(new LinearLayout.LayoutParams(UIHelpers.dp(this, 44), UIHelpers.dp(this, 32)));
            clear.setOnClickListener(v -> {
                styledDialog("清空阅读历史", "将清除所有阅读进度记录，收藏不会受影响。", "清空", () -> {
                    progress.clear();
                    readerPositions.clear();
                    lastViewedAt.clear();
                    saveLocalState();
                    showHistory();
                }, "取消", null);
            });
            settingsHeader(content, "阅读历史", progress.size() + " 条", clear);
        } else {
            settingsHeader(content, "阅读历史", "0 条");
        }

        if (progress.isEmpty()) {
            content.addView(emptyState(R.drawable.ic_history, "还没有阅读记录", "翻开一本，故事从这里开始", "去搜索", () -> showTab(1)));
        } else {
            List<Map.Entry<String, Long>> entries = new ArrayList<>(lastViewedAt.entrySet());
            Collections.sort(entries, (a, b) -> Long.compare(b.getValue(), a.getValue()));
            LinearLayout list = settingsList();
            int visible = 0;
            for (Map.Entry<String, Long> entry : entries) {
                if (!progress.containsKey(entry.getKey())) continue;
                if (visible++ > 0) list.addView(UIHelpers.divider(this));
                list.addView(historyRow(entry.getKey(), entry.getValue()));
            }
            content.addView(list);
            TextView note = UIHelpers.text(this, "删除记录不会移除书架收藏，也不会清理漫画缓存。", 11, UIHelpers.TEXT3, Typeface.NORMAL);
            content.addView(note, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8), -1, -2));
        }
        root.addView(scroll, UIHelpers.match());
    }

    private View historyRow(String comicId, long viewedAt) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 7), UIHelpers.dp(this, 6), UIHelpers.dp(this, 7), UIHelpers.dp(this, 6));
        row.setMinimumHeight(UIHelpers.dp(this, 56));
        ComicModels.ComicSummary summary = summaries.get(comicId);
        ComicModels.ComicDetail detail = details.get(comicId);
        boolean orphaned = summary == null;
        FrameLayout coverWrap = new FrameLayout(this);
        View cover;
        if (orphaned) {
            cover = UIHelpers.coverPlaceholder(this, "");
        } else if (!TextUtils.isEmpty(summary.coverUrl)) {
            cover = coverFrame(summary.coverUrl, 32, 43, isRetiredComic(comicId));
        } else {
            cover = UIHelpers.coverPlaceholder(this, summary.title);
        }
        coverWrap.addView(cover, new FrameLayout.LayoutParams(UIHelpers.dp(this, 32), UIHelpers.dp(this, 43)));
        row.addView(coverWrap, new LinearLayout.LayoutParams(UIHelpers.dp(this, 32), UIHelpers.dp(this, 43)));

        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 8), 0);
        TextView titleView = new TextView(this);
        titleView.setText(orphaned ? "已清除的漫画" : summary.title);
        titleView.setTextSize(14);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        titleView.setTextColor(orphaned ? UIHelpers.TEXT3 : UIHelpers.TEXT);
        titleView.setMaxLines(1);
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
        info.addView(UIHelpers.text(this, chapterText + " · " + DataHelpers.formatRelative(viewedAt), 11, UIHelpers.TEXT3, Typeface.NORMAL),
                UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        row.addView(info, UIHelpers.weight(1));

        ImageView close = new ImageView(this);
        close.setImageResource(R.drawable.ic_trash);
        close.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.TEXT3));
        close.setPadding(UIHelpers.dp(this, 7), UIHelpers.dp(this, 7), UIHelpers.dp(this, 7), UIHelpers.dp(this, 7));
        close.setOnClickListener(v -> {
            String title = orphaned ? "这条记录" : summary.title;
            styledDialog("删除这条记录？", "只移除《" + title + "》的阅读位置，书架收藏保持不变。", "删除", () -> {
                progress.remove(comicId);
                removeReaderPositions(comicId);
                lastViewedAt.remove(comicId);
                saveLocalState();
                showHistory();
            }, "取消", null);
        });
        row.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(this, 30), UIHelpers.dp(this, 30)));

        if (!orphaned) {
            row.setOnClickListener(v -> showDetail(comicId));
        }
        return row;
    }

    private void clearAppCache() {
        if (mh18BrowserSession != null) mh18BrowserSession.clearCache();
        if (jmcomicBrowserSession != null) jmcomicBrowserSession.clearCache();
        android.webkit.WebStorage.getInstance().deleteAllData();
        android.webkit.CookieManager cookies = android.webkit.CookieManager.getInstance();
        cookies.removeAllCookies(ignored -> cookies.flush());
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
        showTab(2);
        main.post(() -> showRemToast("缓存已清理，收藏数据已保留"));
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
