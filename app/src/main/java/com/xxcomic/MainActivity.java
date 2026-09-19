package com.xxcomic;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.Window;
import android.view.inputmethod.EditorInfo;
import android.view.animation.AccelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
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
import android.widget.SeekBar;
import android.widget.Space;
import android.widget.TextView;
import android.widget.Toast;

import com.xxcomic.reader.PagedReaderView;
import com.xxcomic.reader.ReaderPosition;
import com.xxcomic.reader.ReaderNavigation;
import com.xxcomic.reader.ReaderSettingsSheet;
import com.xxcomic.reader.ZoomGeometry;
import com.xxcomic.reader.ChapterDrawerSheet;
import com.xxcomic.reader.HistoryProgressLabel;
import com.xxcomic.reader.ReadingHabitTracker;

import com.xxcomic.source.BaoziComicSource;
import com.xxcomic.source.AntbywComicSource;
import com.xxcomic.source.Mh160ComicSource;
import com.xxcomic.source.ComicModels;
import com.xxcomic.source.ComicSource;
import com.xxcomic.source.DetailSourceSearch;
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
import com.xxcomic.source.LiumanhuaComicSource;
import com.xxcomic.source.CopyMangaComicSource;
import com.xxcomic.source.ManwaComicSource;
import com.xxcomic.source.ManwaImageDecoder;
import com.xxcomic.source.SourceConfig;
import com.xxcomic.source.VerificationCancelledException;
import com.xxcomic.source.VerificationRequiredException;

import com.xxcomic.favorite.FavoriteStarBadgeView;
import com.xxcomic.favorite.FavoriteUpdateCoordinator;
import com.xxcomic.update.AppRelease;
import com.xxcomic.update.AppUpdateChecker;
import com.xxcomic.update.RemUpdateDialog;
import com.xxcomic.update.UpdatePromptPolicy;
import com.xxcomic.local.LocalContentResolver;
import com.xxcomic.local.LocalDetailView;
import com.xxcomic.local.LocalImporter;
import com.xxcomic.local.LocalLibraryStore;
import com.xxcomic.local.LocalLibraryView;
import com.xxcomic.local.BatchImportModels;
import com.xxcomic.local.BatchImportPlanner;
import com.xxcomic.local.BatchImportSession;
import com.xxcomic.download.DownloadRuntime;
import com.xxcomic.download.DownloadViews;
import com.xxcomic.download.DownloadModels;
import com.xxcomic.local.LocalModels;
import com.xxcomic.local.LocalStorageManager;

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
    private static final String PREF_UPDATE_IGNORE_TODAY_DATE = "update_ignore_today_date";
    private static final String ALL_TAG = "全部";
    private static final int DETAIL_HERO_DP = 190;
    private static final int DETAIL_HERO_MAX_DP = 390;
    private static final int CHAPTER_DRAWER_BATCH_SIZE = 40;
    private static final long READER_PROGRESS_ANIM_MS = 30L;
    private static final long READER_CHROME_ANIM_MS = 260L;
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
    private final DetailSourceSearch detailSourceSearch = new DetailSourceSearch(main::post);
    private TextView detailSourceEntry;
    private SourceSwitchSheet detailSourceSheet;
    private boolean detailSourcesLoading;
    private List<ComicModels.ComicSummary> detailSourceOptions = new ArrayList<>();
    private String pendingDetailSourceId = "";
    private int detailSwitchGeneration;
    private Future<?> detailSwitchTask;
    private Runnable detailSwitchTimeout;
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
    private ComicSource mh160Client;
    private ComicSource gmhClient;
    private Mh18ComicSource mh18Client;
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
    private ComicSource liumanhuaClient;
    private ComicSource copy4000Client;
    private ComicSource manwaClient;
    private Mh18WebViewSession mh18BrowserSession;
    private JmComicWebViewSession jmcomicBrowserSession;
    private SourceConfig baoziConfig = SourceConfig.baozi(true);
    private SourceConfig mh160Config = SourceConfig.mh160(true);
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
    private SourceConfig liumanhuaConfig = SourceConfig.liumanhua(true);
    private SourceConfig copy4000Config = SourceConfig.copy4000(true);
    private SourceConfig manwaConfig = SourceConfig.manwa(true);
    private final List<ComicModels.ComicSummary> searchResults = new ArrayList<>();
    private final List<ComicModels.ComicSummary> globalSearchResults = new ArrayList<>();
    private final List<String> globalSearchHistory = new ArrayList<>();
    private final Map<String, List<ComicModels.ComicSummary>> globalSearchResultsBySource = new LinkedHashMap<>();
    private final Map<String, Set<String>> globalSearchShownIdsBySource = new HashMap<>();
    private final Set<String> globalSearchFailedSourceIds = new HashSet<>();
    private final Set<String> globalSearchVerificationRequiredSourceIds = new HashSet<>();
    private final Set<String> globalSearchCompletedSourceIds = new HashSet<>();
    private final Map<String, ComicModels.ComicSummary> summaries = new LinkedHashMap<>();
    private final Map<String, ComicModels.ComicDetail> details = new HashMap<>();
    private final Map<String, ComicModels.ChapterPage> chapters = new HashMap<>();
    private final Set<String> refreshedComicIds = new HashSet<>();
    private final Set<String> refreshingComicIds = new HashSet<>();
    private final Set<String> readerPrefetching = new HashSet<>();
    private final Set<String> verifyingProtectedSourceIds = new HashSet<>();
    private final Set<String> retryProtectedSourceIds = new HashSet<>();
    private final Map<String, DetailAction> pendingRefreshActions = new HashMap<>();
    private final List<String> favorites = new ArrayList<>();
    private final List<ComicModels.FilterGroup> sourceFilterGroups = new ArrayList<>();
    private final List<ComicModels.Source> customSources = new ArrayList<>();
    private final Map<String, Integer> progress = new HashMap<>();
    private final Map<String, Integer> readerPositions = new HashMap<>();
    private final Map<String, Long> favoriteAt = new HashMap<>();
    private final Map<String, Long> lastViewedAt = new HashMap<>();
    private final Runnable persistReaderPositionRunnable = this::saveLocalState;
    private final Map<String, View> favoriteBadgeViews = new HashMap<>();
    private AlertDialog activeUpdateDialog = null;
    private AlertDialog activeRemDialog = null;
    private AppRelease pendingPromptRelease = null;
    private boolean activityResumed = false;
    private final AppUpdateChecker.StartupCheckCallback startupUpdateCallback = release ->
            postMainIfAlive(() -> {
                if (release == null || !release.hasNewVersion(BuildConfig.VERSION_CODE)) return;
                availableUpdateRelease = release;
                if (release.isPromptMode() && !isUpdatePromptIgnoredToday()) tryShowUpdatePrompt(release);
            });

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
    private boolean mh160Enabled = true;
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
    private boolean liumanhuaEnabled = true;
    private boolean copy4000Enabled = true;
    private boolean manwaEnabled = true;
    private boolean chapterDesc = false;
    private int themeMode = 0;
    private int readerLayoutMode = 0; // 0 continuous, 1 single image
    private PagedReaderView readerPager;
    private com.xxcomic.ebook.TextReaderView textReaderView;
    private ListView readerList;
    private boolean[] readerRestoringPosition;
    private TextView readerPreviousButton, readerNextButton;
    private View readerContentView;
    private SeekBar readerSeekBar;
    private boolean readerSeeking = false;
    private TextView readerOverlayBadge;
    private final Set<String> readerLoadedChapterUrls = new HashSet<>();
    private TextView readerToolbarTitle;
    private boolean readerFullyImmersive = false;
    private final android.util.LruCache<String, Bitmap> readerBitmapCache =
            new android.util.LruCache<String, Bitmap>((int) (Runtime.getRuntime().maxMemory() / 6)) {
                @Override
                protected int sizeOf(String key, Bitmap value) {
                    return value == null ? 0 : value.getByteCount();
                }
            };
    private final Map<String, Integer> readerImageHeights = new HashMap<>();
    private BroadcastReceiver readerBatteryReceiver;
    private int currentBatteryLevel = -1;
    private int readerCurrentPageNumber = 1;
    private int readerTotalPages = 1;
    private final Runnable readerTimeUpdateRunnable = new Runnable() {
        @Override
        public void run() {
            if (readerVisible && readerOverlayBadge != null) {
                refreshReaderOverlayBadge();
                main.postDelayed(this, 15000L);
            }
        }
    };
    private String readerSettingsComicId = "";
    private int readerSettingsChapterIndex;
    private String readerEntryChapterUrl = "";
    private int readerEntryTarget = 0; // 0 resume, 1 first image, -1 last image
    private final Map<String, ReaderPosition> readerImagePositions = new HashMap<>();
    private boolean readerLeftHand = false;
    private boolean readerButtonMode = false;
    private int readerPageMode = 0; // 0 touch edge, 1 buttons, 2 horizontal swipe
    private int readerDisplayMode = 0; // 0 normal, 1 e-ink
    private boolean readerPinchZoom = true;
    private boolean readerDisablePageAnimation = false;
    private ColorMatrixColorFilter readerEinkFilter;

    // Local library pickers must not overlap source configuration/log export requests (1001-1004).
    private static final int REQUEST_CODE_IMPORT_ARCHIVE = 2001;
    private static final int REQUEST_CODE_APPEND_VOLUMES = 2003;
    private String appendVolumeBookId;
    private static final int REQUEST_CODE_IMPORT_FOLDER = 2002;

    private static LocalStorageManager localStorageManager;
    private static LocalLibraryStore localLibraryStore;
    private static LocalContentResolver localContentResolver;
    private static final ExecutorService localLibraryIo = Executors.newSingleThreadExecutor();
    private static final ExecutorService localBatchIo = Executors.newFixedThreadPool(2);

    private int bookshelfTab = 0; // 0: 我的书架, 1: 本地书架
    private ReadingHabitTracker readingHabitTracker;
    private final Runnable readerTickRunnable = new Runnable() {
        @Override
        public void run() {
            if (readerVisible && readingHabitTracker != null) {
                readingHabitTracker.tick();
                main.postDelayed(this, 2000L);
            }
        }
    };
    private FrameLayout bookshelfContainer;
    private View onlineBookshelfView;
    private View localBookshelfView;
    private TextView titleMyBookshelf;
    private TextView titleLocalBookshelf;
    private LinearLayout bookshelfRightActions;
    private ValueAnimator bookshelfTabAnimator;

    private static class ActiveImportTask {
        final String title;
        final java.util.concurrent.atomic.AtomicBoolean cancelled = new java.util.concurrent.atomic.AtomicBoolean(false);
        volatile String currentMessage = "准备中...";
        volatile int currentItem = 0;
        volatile int totalItems = 0;
        volatile boolean isFolder = false;
        AlertDialog dialog;
        Runnable showDialogAction;
        java.lang.ref.WeakReference<TextView> messageViewRef;
        java.lang.ref.WeakReference<TextView> bannerMessageViewRef;
        long lastProgressUpdate;
        BatchImportSession session;
        volatile boolean persistenceFailed;
        volatile boolean userCancelled;

        ActiveImportTask(String title, boolean isFolder) {
            this.title = title;
            this.isFolder = isFolder;
        }
    }
    private ActiveImportTask currentImportTask = null;
    private boolean localImportScanning;
    private boolean batchShelfRefreshPending;
    private BatchImportSession savedImportSession;
    private boolean localLibraryReady;
    private Runnable offlinePageBack;
    private String readerLocalBookId = "";
    private String localLibraryRecoveryError;
    private final java.util.concurrent.atomic.AtomicBoolean localStoreRecoveryStarted = new java.util.concurrent.atomic.AtomicBoolean(false);
    private final Set<String> pendingDeleteLocalBookIds = new HashSet<>();
    private final Map<String, Runnable> pendingLocalDeleteRunnables = new HashMap<>();

    private void ensureLocalLibraryRecovery() {
        if (localStoreRecoveryStarted.compareAndSet(false, true)) {
            localLibraryIo.submit(() -> {
                String error = null;
                try {
                    getLocalLibraryStore().recoverOrphanedStates(getLocalStorageManager());
                } catch (Exception e) {
                    error = "本地文件整理失败，请重试";
                    android.util.Log.w("MainActivity", "Local library startup recovery failed", e);
                }
                final String failure = error;
                BatchImportSession recovered = null;
                try { recovered = BatchImportSession.load(batchSessionFile()); }
                catch (IOException e) { android.util.Log.w("MainActivity", "Cannot read saved import session", e); }
                final BatchImportSession restored = recovered;
                main.post(() -> {
                    if (activityDestroyed || isFinishing()) return;
                    localLibraryReady = failure == null;
                    localLibraryRecoveryError = failure;
                    savedImportSession = restored;
                    refreshLocalBookshelf();
                    if (failure == null) {
                        DownloadRuntime runtime = DownloadRuntime.get(this);
                        if (runtime.hasPending()) DownloadViews.startService(this);
                        if (getIntent().getBooleanExtra("open.downloads", false)) {
                            getIntent().removeExtra("open.downloads");
                            showDownloadCenter();
                        }
                    }
                });
            });
        }
    }

    private LocalStorageManager getLocalStorageManager() {
        synchronized (MainActivity.class) {
            if (localStorageManager == null) localStorageManager = com.xxcomic.local.LocalLibrary.get(this).storage;
            return localStorageManager;
        }
    }

    private LocalLibraryStore getLocalLibraryStore() {
        synchronized (MainActivity.class) {
            if (localLibraryStore == null) localLibraryStore = com.xxcomic.local.LocalLibrary.get(this).store;
            return localLibraryStore;
        }
    }

    private LocalContentResolver getLocalContentResolver() {
        synchronized (MainActivity.class) {
            if (localContentResolver == null) {
                localContentResolver = com.xxcomic.local.LocalLibrary.get(this).resolver;
            }
            return localContentResolver;
        }
    }

    private boolean isLocalComic(String comicId) {
        return comicId != null && comicId.startsWith("local_");
    }
    private LocalModels.Book localBookForReading(String id) {
        LocalModels.Book book=getLocalLibraryStore().getBook(id);
        return book!=null?book:getLocalLibraryStore().findByProgressKey(id);
    }

    private ColorMatrixColorFilter readerEinkColorFilter() {
        if (readerEinkFilter == null) {
            ColorMatrix matrix = new ColorMatrix();
            matrix.setSaturation(0f);
            float contrast = 1.25f;
            float translate = (-0.5f * contrast + 0.5f) * 255f;
            ColorMatrix contrastMatrix = new ColorMatrix(new float[]{
                    contrast, 0, 0, 0, translate,
                    0, contrast, 0, 0, translate,
                    0, 0, contrast, 0, translate,
                    0, 0, 0, 1, 0
            });
            matrix.postConcat(contrastMatrix);
            readerEinkFilter = new ColorMatrixColorFilter(matrix);
        }
        return readerEinkFilter;
    }

    private void applyReaderImageDisplayMode(ImageView view) {
        if (view == null) return;
        if (readerDisplayMode == 1) {
            view.setColorFilter(readerEinkColorFilter());
        } else {
            view.setColorFilter(null);
        }
    }
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
    private boolean searchAppendVerificationRequired = false;
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
    private volatile List<String> sourceOrder = Collections.emptyList();
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
    private ChapterDrawerSheet activeChapterSheet;
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
    private View activeTransientHint;
    private Runnable transientHintDismiss;
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
        if (savedInstanceState != null) appendVolumeBookId = savedInstanceState.getString("appendVolumeBookId");
        applyThemeAndSystemBars();
        root = new FrameLayout(this);
        // The pager opts into RTL for left-hand swipes; keep the app's existing layout direction.
        root.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        setContentView(root);
        mh18BrowserSession = new Mh18WebViewSession(
                this, main, mh18Config.name, null,
                () -> requestProtectedSourceRetry("mh18"));
        DownloadSources.attachMh18(mh18BrowserSession);
        jmcomicBrowserSession = new JmComicWebViewSession(
                this, main, jmcomicConfig.name, null,
                () -> requestProtectedSourceRetry("jmcomic"));
        rebuildSourceClients();
        restoreLocalState();
        readingHabitTracker = new ReadingHabitTracker();
        restoreReadingHabitState();
        readingHabitTracker.setListener(tracker -> persistReadingHabitState());
        if (savedInstanceState == null) {
            bookshelfTab = readingHabitTracker.resolveCurrentLaunchTab();
        }
        applyThemeAndSystemBars();
        scheduleThemeSwitch();
        showTab(0);
        FavoriteUpdateCoordinator.getInstance().setBadgeChangeListener((comicId, visible) -> {
            postMainIfAlive(() -> updateFavoriteBadge(comicId,
                    FavoriteUpdateCoordinator.getInstance().shouldShowBadge(comicId)));
        });
        triggerStartupChecks();
        ensureLocalLibraryRecovery();
    }

    @Override
    protected void onResume() {
        super.onResume();
        activityResumed = true;
        if (readingHabitTracker != null) readingHabitTracker.onAppForeground();
        boolean themeChanged = refreshThemeIfChanged();
        scheduleThemeSwitch();
        if (themeChanged && root != null) rerenderCurrentScreen();
        if (readerVisible) {
            applyReaderSystemBars();
            registerReaderBatteryReceiver();
            main.post(readerTimeUpdateRunnable);
            main.removeCallbacks(readerTickRunnable);
            main.postDelayed(readerTickRunnable, 2000L);
        }
        checkPendingUpdatePrompt();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus && readerVisible) {
            applyReaderSystemBars();
        }
        if (hasFocus) checkPendingUpdatePrompt();
    }

    @Override
    protected void onPause() {
        activityResumed = false;
        if (readingHabitTracker != null) readingHabitTracker.onAppBackground();
        main.removeCallbacks(readerTickRunnable);
        if (activeUpdateDialog != null && activeUpdateDialog.isShowing()) {
            pendingPromptRelease = availableUpdateRelease;
            activeUpdateDialog.dismiss();
            activeUpdateDialog = null;
        }
        super.onPause();
        unregisterReaderBatteryReceiver();
        main.removeCallbacks(readerTimeUpdateRunnable);
        captureReaderPosition();
        saveLocalState();
    }

    @Override
    protected void onDestroy() {
        DownloadSources.attachMh18(null);
        activityDestroyed = true;
        if (currentImportTask != null) {
            currentImportTask.cancelled.set(true);
            if (currentImportTask.dialog != null) currentImportTask.dialog.dismiss();
        }
        if (detailSourceSheet != null) detailSourceSheet.dismissImmediately();
        detailSourceSearch.close();
        if (detailSwitchTimeout != null) main.removeCallbacks(detailSwitchTimeout);
        activityResumed = false;
        AppUpdateChecker.getInstance().detachStartupCallback(startupUpdateCallback);
        FavoriteUpdateCoordinator.getInstance().setBadgeChangeListener(null);
        if (activeUpdateDialog != null && activeUpdateDialog.isShowing()) {
            activeUpdateDialog.dismiss();
            activeUpdateDialog = null;
        }
        if (activeRemDialog != null && activeRemDialog.isShowing()) {
            activeRemDialog.dismiss();
            activeRemDialog = null;
        }
        if (readerVisible && readingHabitTracker != null) {
            readingHabitTracker.onExitReader();
        }
        releaseReaderViews();
        dismissTransientHint();
        if (mh18BrowserSession != null) {
            mh18BrowserSession.shutdown();
        }
        if (jmcomicBrowserSession != null) {
            jmcomicBrowserSession.shutdown();
        }
        for (Runnable r : new ArrayList<>(pendingLocalDeleteRunnables.values())) {
            main.removeCallbacks(r);
            r.run();
        }
        pendingLocalDeleteRunnables.clear();
        pendingDeleteLocalBookIds.clear();
        super.onDestroy();
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
        } else if ((requestCode == REQUEST_CODE_IMPORT_ARCHIVE || requestCode == REQUEST_CODE_APPEND_VOLUMES)
                && resultCode == RESULT_OK && data != null) {
            List<Uri> uris = new ArrayList<>();
            if (data.getClipData() != null) {
                for (int i = 0; i < data.getClipData().getItemCount(); i++) {
                    Uri u = data.getClipData().getItemAt(i).getUri();
                    if (u != null) uris.add(u);
                }
            } else if (data.getData() != null) {
                uris.add(data.getData());
            }
            if (!uris.isEmpty()) {
                if (requestCode == REQUEST_CODE_APPEND_VOLUMES && TextUtils.isEmpty(appendVolumeBookId)) {
                    showRemErrorToast("请重新进入漫画详情添加分卷");
                } else handleImportArchiveUris(uris, requestCode == REQUEST_CODE_APPEND_VOLUMES ? appendVolumeBookId : null);
            }
            appendVolumeBookId = null;
        } else if (requestCode == REQUEST_CODE_IMPORT_FOLDER && resultCode == RESULT_OK && data != null && data.getData() != null) {
            handleImportFolderUri(data.getData());
        }
    }

    private void updateImportTaskProgress(ActiveImportTask task, String message) {
        long now = android.os.SystemClock.uptimeMillis();
        if (now - task.lastProgressUpdate < 100) return;
        task.lastProgressUpdate = now;
        main.post(() -> {
            if (activityDestroyed || isFinishing()) return;
            TextView tv = task.messageViewRef != null ? task.messageViewRef.get() : null;
            if (tv != null && task.dialog != null && task.dialog.isShowing()) {
                tv.setText(task.currentMessage);
            }
            TextView banner = task.bannerMessageViewRef != null ? task.bannerMessageViewRef.get() : null;
            if (banner != null) banner.setText(task.currentMessage);
        });
    }

    private AlertDialog showThemedImportProgressDialog(ActiveImportTask task) {
        if (task == null || isFinishing()) return null;
        if (task.dialog != null && task.dialog.isShowing()) {
            return task.dialog;
        }

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.HORIZONTAL);
        content.setGravity(Gravity.TOP);
        content.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16),
                UIHelpers.dp(this, 16), UIHelpers.dp(this, 10));

        ImageView art = new ImageView(this);
        art.setImageResource(R.drawable.rem_loading);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        content.addView(art, new LinearLayout.LayoutParams(
                UIHelpers.dp(this, 56), UIHelpers.dp(this, 56)));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 2), 0, 0);

        TextView titleView = UIHelpers.text(this, task.title, 17, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(titleView);

        TextView messageView = UIHelpers.text(this, task.currentMessage, 13, UIHelpers.TEXT2, Typeface.NORMAL);
        messageView.setMaxLines(3);
        messageView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 5)));
        content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setView(content)
                .setNegativeButton("取消", (d, which) -> {
                    task.userCancelled = true;
                    task.cancelled.set(true);
                    task.currentMessage = "正在取消...";
                    messageView.setText("正在取消...");
                    showRemSuccessToast("已请求取消导入");
                })
                .setNeutralButton("后台运行", (d, which) -> {
                    task.dialog = null;
                    refreshLocalBookshelf();
                })
                .setCancelable(true)
                .create();

        dialog.setOnShowListener(d -> {
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(UIHelpers.round(
                        UIHelpers.CARD, UIHelpers.dp(this, 12), Color.TRANSPARENT));
                int width = Math.min(getResources().getDisplayMetrics().widthPixels
                        - UIHelpers.dp(this, 40), UIHelpers.dp(this, 328));
                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            }
            Button neutral = dialog.getButton(AlertDialog.BUTTON_NEUTRAL);
            if (neutral != null) {
                neutral.setTextColor(UIHelpers.ACCENT);
                neutral.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            Button negative = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (negative != null) {
                negative.setTextColor(UIHelpers.TEXT3);
                negative.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
        });
        dialog.setOnDismissListener(d -> {
            task.dialog = null;
            if (!activityDestroyed) refreshLocalBookshelf();
        });

        task.dialog = dialog;
        task.messageViewRef = new java.lang.ref.WeakReference<>(messageView);
        dialog.show();
        return dialog;
    }

    private View buildActiveImportBanner(ActiveImportTask task) {
        LinearLayout banner = new LinearLayout(this);
        banner.setOrientation(LinearLayout.HORIZONTAL);
        banner.setGravity(Gravity.CENTER_VERTICAL);
        banner.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
        banner.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 8), UIHelpers.BORDER));

        ImageView icon = new ImageView(this);
        icon.setImageResource(R.drawable.rem_loading);
        icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
        banner.addView(icon, new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28)));

        LinearLayout textCol = new LinearLayout(this);
        textCol.setOrientation(LinearLayout.VERTICAL);
        textCol.setPadding(UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 8), 0);

        TextView titleView = UIHelpers.text(this, task.title, 13, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(1);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        textCol.addView(titleView);

        TextView msgView = UIHelpers.text(this, task.currentMessage, 11, UIHelpers.TEXT2, Typeface.NORMAL);
        task.bannerMessageViewRef = new java.lang.ref.WeakReference<>(msgView);
        msgView.setMaxLines(1);
        msgView.setEllipsize(TextUtils.TruncateAt.END);
        textCol.addView(msgView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));

        banner.addView(textCol, UIHelpers.weight(1));

        TextView viewBtn = UIHelpers.text(this, "查看", 12, UIHelpers.ACCENT, Typeface.BOLD);
        viewBtn.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 4), UIHelpers.dp(this, 8), UIHelpers.dp(this, 4));
        viewBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 6), UIHelpers.BORDER));
        viewBtn.setOnClickListener(v -> {
            if (task.showDialogAction != null) {
                task.showDialogAction.run();
            }
        });
        banner.addView(viewBtn);

        TextView cancelBtn = UIHelpers.text(this, "取消", 12, UIHelpers.DANGER, Typeface.BOLD);
        cancelBtn.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 4), UIHelpers.dp(this, 8), UIHelpers.dp(this, 4));
        LinearLayout.LayoutParams cancelParams = new LinearLayout.LayoutParams(-2, -2);
        cancelParams.leftMargin = UIHelpers.dp(this, 6);
        cancelBtn.setLayoutParams(cancelParams);
        cancelBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 6), UIHelpers.BORDER));
        cancelBtn.setOnClickListener(v -> {
            task.userCancelled = true;
            task.cancelled.set(true);
            task.currentMessage = "正在取消...";
            msgView.setText("正在取消...");
            if (task.dialog != null && task.dialog.isShowing()) {
                task.dialog.dismiss();
            }
            showRemSuccessToast("已请求取消导入");
        });
        banner.addView(cancelBtn);

        return banner;
    }

    private static class PendingImportItem {
        final Uri uri;
        final String displayName;
        final String format;
        final String comicTitle;
        final String chapterTitle;
        final boolean matchedFormat;
        final int selectionIndex;
        String seriesTitle;
        java.math.BigDecimal volumeOrder;

        PendingImportItem(Uri uri, String displayName, String format, String comicTitle, String chapterTitle,
                          boolean matchedFormat, int selectionIndex) {
            this.uri = uri;
            this.displayName = displayName;
            this.format = format;
            this.comicTitle = comicTitle;
            this.chapterTitle = chapterTitle;
            this.matchedFormat = matchedFormat;
            this.selectionIndex = selectionIndex;
        }
    }

    private static final class BatchImportOutcome {
        int skippedCount;
        int successCount;
        final List<String> failedItems = new ArrayList<>();
        final List<String> failedReasons = new ArrayList<>();
    }

    private void handleImportArchiveUris(List<Uri> uris, String targetBookId) {
        if (uris == null || uris.isEmpty()) return;
        if (!canStartLocalImport()) return;
        localImportScanning = true;
        showRemSuccessToast("正在读取文件信息，可继续浏览");
        localLibraryIo.submit(() -> {
            try { scanImportArchiveUris(uris, targetBookId); }
            catch (Exception error) {
                main.post(() -> {
                    localImportScanning = false;
                    if (!activityDestroyed && !isFinishing()) showRemErrorToast("读取文件信息失败，请重新选择");
                });
            }
        });
    }

    private void scanImportArchiveUris(List<Uri> uris, String targetBookId) {
        List<PendingImportItem> pendingList = new ArrayList<>();
        for (int i = 0; i < uris.size(); i++) {
            if (activityDestroyed || Thread.currentThread().isInterrupted()) return;
            Uri uri = uris.get(i);
            try {
                getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } catch (Exception ignored) {}
            String displayName = null;
            try {
                android.database.Cursor cursor = getContentResolver().query(uri, new String[]{android.provider.OpenableColumns.DISPLAY_NAME}, null, null, null);
                if (cursor != null) {
                    if (cursor.moveToFirst()) {
                        displayName = cursor.getString(0);
                    }
                    cursor.close();
                }
            } catch (Exception ignored) {}
            if (TextUtils.isEmpty(displayName)) {
                String path = uri.getPath();
                if (path != null && path.contains("/")) {
                    displayName = path.substring(path.lastIndexOf('/') + 1);
                }
            }
            if (TextUtils.isEmpty(displayName)) {
                displayName = "文件 " + (i + 1);
            }

            String lower = displayName.toLowerCase(Locale.US);
            String fmt;
            if (lower.endsWith(".pdf")) fmt = "pdf";
            else if (lower.endsWith(".epub")) fmt = "epub";
            else if (lower.endsWith(".azw3")) fmt = "azw3";
            else if (lower.endsWith(".azw")) fmt = "azw";
            else if (lower.endsWith(".mobi")) fmt = "mobi";
            else if (lower.endsWith(".cbz")) fmt = "cbz";
            else if (lower.endsWith(".zip")) fmt = "zip";
            else fmt = "unknown";

            String comicTitle = displayName;
            int dot = displayName.lastIndexOf('.');
            if (dot > 0) {
                comicTitle = displayName.substring(0, dot).trim();
            }
            PendingImportItem item = new PendingImportItem(uri, displayName, fmt, comicTitle, "全本", false, i);
            // Metadata is optional: providers without a seekable descriptor fall back to filenames,
            // without copying the entire file just to show the confirmation sheet.
            if ("epub".equals(fmt) || LocalModels.isKindleFormat(fmt)) {
                android.os.ParcelFileDescriptor[] descriptor = new android.os.ParcelFileDescriptor[1];
                try {
                    File file = com.xxcomic.local.UriUtils.resolveFileOrProcFd(this, uri, descriptor);
                    if (file != null) {
                        com.xxcomic.ebook.QuickPublicationInfo info = com.xxcomic.ebook.QuickPublicationInfo.read(file, fmt);
                        item.seriesTitle = info.seriesTitle;
                        if (!TextUtils.isEmpty(info.volumeNumber)) {
                            try { item.volumeOrder = new java.math.BigDecimal(info.volumeNumber); }
                            catch (NumberFormatException ignored) { }
                        }
                    }
                } catch (Exception ignored) {
                    // The importer reports structural/DRM errors per file; scanning never blocks the batch.
                } finally {
                    if (descriptor[0] != null) try { descriptor[0].close(); } catch (IOException ignored) { }
                }
            }
            pendingList.add(item);
        }

        final List<PendingImportItem> orderedItems = pendingList;
        final List<BatchImportModels.ImportGroup> plannedGroups = buildImportGroups(orderedItems);
        main.post(() -> {
            localImportScanning = false;
            if (activityDestroyed || isFinishing()) return;
            if (targetBookId != null) {
                LocalModels.Book target = getLocalLibraryStore().getBook(targetBookId);
                if (target == null || !LocalModels.STATUS_READY.equals(target.status)) {
                    showRemErrorToast("原漫画已移除，请重新选择");
                    return;
                }
                List<BatchImportModels.FileCandidate> files = new ArrayList<>();
                for (BatchImportModels.ImportGroup group : plannedGroups) files.addAll(group.volumes);
                List<BatchImportModels.ImportGroup> appendGroups = Collections.singletonList(
                        new BatchImportModels.ImportGroup("append:" + targetBookId, target.getDisplayTitle(), false,
                                BatchImportPlanner.orderVolumes(files)));
                if (canStartLocalImport()) {
                    startBatchImport(orderedItems, appendGroups, null, targetBookId);
                }
            } else if (orderedItems.size() > 1) showBatchImportConfirmation(orderedItems, plannedGroups);
            else startBatchImport(orderedItems, plannedGroups);
        });
    }

    private void showBatchImportConfirmation(List<PendingImportItem> items, List<BatchImportModels.ImportGroup> groups) {
        Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setCanceledOnTouchOutside(true);

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 10), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));

        GradientDrawable panelBg = new GradientDrawable();
        float radius = UIHelpers.dp(this, 18);
        panelBg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        panelBg.setColor(UIHelpers.CARD);
        panel.setBackground(panelBg);

        // Top drag handle bar
        View pullBar = new View(this);
        pullBar.setBackground(UIHelpers.round(UIHelpers.BORDER, UIHelpers.dp(this, 2), Color.TRANSPARENT));
        LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 36), UIHelpers.dp(this, 4));
        barParams.gravity = Gravity.CENTER_HORIZONTAL;
        barParams.bottomMargin = UIHelpers.dp(this, 12);
        panel.addView(pullBar, barParams);

        // Header row
        LinearLayout headerRow = new LinearLayout(this);
        headerRow.setOrientation(LinearLayout.HORIZONTAL);
        headerRow.setGravity(Gravity.CENTER_VERTICAL);

        TextView titleView = UIHelpers.text(this, "整理导入文件", 17, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setSingleLine(true);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        headerRow.addView(titleView, UIHelpers.weight(1));

        TextView badge = UIHelpers.text(this, "共 " + items.size() + " 个文件", 11, UIHelpers.ACCENT, Typeface.NORMAL);
        badge.setSingleLine(true);
        badge.setPadding(UIHelpers.dp(this, 6), UIHelpers.dp(this, 2), UIHelpers.dp(this, 6), UIHelpers.dp(this, 2));
        badge.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 4), Color.TRANSPARENT));
        LinearLayout.LayoutParams badgeParams = new LinearLayout.LayoutParams(-2, -2);
        badgeParams.leftMargin = UIHelpers.dp(this, 8);
        badgeParams.rightMargin = UIHelpers.dp(this, 8);
        headerRow.addView(badge, badgeParams);

        ImageView closeBtn = UIHelpers.vectorIconButton(this, R.drawable.ic_close, UIHelpers.TEXT3, 6);
        closeBtn.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, UIHelpers.dp(this, 14), Color.TRANSPARENT));
        closeBtn.setOnClickListener(v -> dialog.dismiss());
        headerRow.addView(closeBtn, new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28)));
        panel.addView(headerRow);

        TextView subtitle = UIHelpers.text(this, "已按文件信息智能建议分组，请确认或调整合并方式", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        panel.addView(subtitle, UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));

        ScrollView scroll = new ScrollView(this);
        scroll.setVerticalScrollBarEnabled(false);
        LinearLayout scrollContent = new LinearLayout(this);
        scrollContent.setOrientation(LinearLayout.VERTICAL);
        scrollContent.setPadding(0, UIHelpers.dp(this, 10), 0, UIHelpers.dp(this, 10));
        scroll.addView(scrollContent, new ScrollView.LayoutParams(-1, -2));
        panel.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));

        // Combine all card
        LinearLayout combineCard = new LinearLayout(this);
        combineCard.setOrientation(LinearLayout.VERTICAL);
        combineCard.setPadding(UIHelpers.dp(this, 14), UIHelpers.dp(this, 12), UIHelpers.dp(this, 14), UIHelpers.dp(this, 12));
        combineCard.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 10), UIHelpers.BORDER));

        LinearLayout combineHeader = new LinearLayout(this);
        combineHeader.setOrientation(LinearLayout.HORIZONTAL);
        combineHeader.setGravity(Gravity.CENTER_VERTICAL);

        android.widget.CheckBox combineAll = new android.widget.CheckBox(this);
        combineAll.setText("合并为一部完整漫画");
        combineAll.setMaxLines(2);
        combineAll.setEllipsize(TextUtils.TruncateAt.END);
        combineAll.setTextSize(13);
        combineAll.setTypeface(Typeface.DEFAULT_BOLD);
        combineAll.setTextColor(UIHelpers.TEXT);
        combineAll.setButtonTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
        combineHeader.addView(combineAll, UIHelpers.weight(1));

        TextView tip = UIHelpers.text(this, "多卷合集", 10, UIHelpers.TEXT3, Typeface.NORMAL);
        tip.setSingleLine(true);
        tip.setPadding(UIHelpers.dp(this, 6), UIHelpers.dp(this, 2), UIHelpers.dp(this, 6), UIHelpers.dp(this, 2));
        tip.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, UIHelpers.dp(this, 4), Color.TRANSPARENT));
        combineHeader.addView(tip);
        combineCard.addView(combineHeader);

        EditText combinedTitle = new EditText(this);
        combinedTitle.setSingleLine(true);
        combinedTitle.setTextSize(13);
        combinedTitle.setTextColor(UIHelpers.TEXT);
        combinedTitle.setHintTextColor(UIHelpers.TEXT3);
        combinedTitle.setHint("输入漫画合集名称（例如：狂赌之渊）");
        combinedTitle.setText(groups.isEmpty() ? "" : groups.get(0).title);
        combinedTitle.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
        combinedTitle.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 8), UIHelpers.BORDER));
        combinedTitle.setVisibility(View.GONE);
        LinearLayout.LayoutParams editParams = new LinearLayout.LayoutParams(-1, -2);
        editParams.topMargin = UIHelpers.dp(this, 10);
        combineCard.addView(combinedTitle, editParams);

        scrollContent.addView(combineCard);

        TextView groupHeader = UIHelpers.text(this, "建议分组明细", 12, UIHelpers.TEXT2, Typeface.BOLD);
        scrollContent.addView(groupHeader, UIHelpers.marginTop(-1, UIHelpers.dp(this, 14)));

        LinearLayout groupListContainer = new LinearLayout(this);
        groupListContainer.setOrientation(LinearLayout.VERTICAL);
        scrollContent.addView(groupListContainer, UIHelpers.marginTop(-1, UIHelpers.dp(this, 6)));

        combineAll.setOnCheckedChangeListener((button, checked) -> {
            combinedTitle.setVisibility(checked ? View.VISIBLE : View.GONE);
            groupHeader.setVisibility(checked ? View.GONE : View.VISIBLE);
            groupListContainer.setVisibility(checked ? View.GONE : View.VISIBLE);
        });

        List<android.widget.CheckBox> choices = new ArrayList<>();
        for (BatchImportModels.ImportGroup group : groups) {
            LinearLayout groupCard = new LinearLayout(this);
            groupCard.setOrientation(LinearLayout.VERTICAL);
            groupCard.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
            groupCard.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 10), UIHelpers.BORDER));

            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);

            android.widget.CheckBox choice = new android.widget.CheckBox(this);
            choice.setText(group.title + " · " + group.volumes.size() + " 个文件");
            choice.setMaxLines(2);
            choice.setEllipsize(TextUtils.TruncateAt.END);
            choice.setTextSize(13);
            choice.setTypeface(Typeface.DEFAULT_BOLD);
            choice.setTextColor(UIHelpers.TEXT);
            choice.setButtonTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
            choice.setChecked(group.volumes.size() > 1);
            choice.setEnabled(group.volumes.size() > 1);
            choices.add(choice);
            row.addView(choice, UIHelpers.weight(1));
            groupCard.addView(row);

            TextView files = UIHelpers.text(this, "", 11, UIHelpers.TEXT3, Typeface.NORMAL);
            files.setLineSpacing(UIHelpers.dp(this, 2), 1f);
            files.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 6), UIHelpers.dp(this, 8), UIHelpers.dp(this, 6));
            files.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 6), Color.TRANSPARENT));

            StringBuilder names = new StringBuilder();
            for (int i = 0; i < Math.min(group.volumes.size(), 4); i++) {
                if (i > 0) names.append("\n");
                names.append("• ").append(group.volumes.get(i).fileName);
            }
            if (group.volumes.size() > 4) names.append("\n…点击展开其余 ").append(group.volumes.size() - 4).append(" 个文件");
            files.setText(names.toString());
            files.setOnClickListener(v -> {
                if (Boolean.TRUE.equals(files.getTag())) {
                    files.setText(names.toString());
                    files.setTag(false);
                } else {
                    StringBuilder full = new StringBuilder();
                    for (BatchImportModels.FileCandidate file : group.volumes) {
                        if (full.length() > 0) full.append("\n");
                        full.append("• ").append(file.fileName);
                    }
                    full.append("\n(点击收起)");
                    files.setText(full.toString());
                    files.setTag(true);
                }
            });
            groupCard.addView(files, UIHelpers.marginTop(-1, UIHelpers.dp(this, 6)));

            LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(-1, -2);
            cardParams.bottomMargin = UIHelpers.dp(this, 8);
            groupListContainer.addView(groupCard, cardParams);
        }

        Button start = new Button(this);
        start.setText("确认并开始导入 (" + items.size() + " 个文件)");
        start.setTextSize(14);
        start.setTypeface(Typeface.DEFAULT_BOLD);
        start.setTextColor(UIHelpers.ON_ACCENT);
        start.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(this, 10), Color.TRANSPARENT));
        start.setGravity(Gravity.CENTER);
        start.setMinimumHeight(UIHelpers.dp(this, 46));
        panel.addView(start, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8)));

        panel.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        panel.setFocusableInTouchMode(true);
        dialog.setContentView(panel, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        panel.requestFocus();

        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            w.setGravity(Gravity.BOTTOM);
            w.setDimAmount(0.4f);
            w.setWindowAnimations(R.style.DownloadSheetAnimation);
            w.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                    | android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        }
        dialog.show();
        if (w != null) {
            int availableHeight = getWindow().getDecorView().getHeight();
            if (availableHeight <= 0) availableHeight = getResources().getDisplayMetrics().heightPixels;
            w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Math.round(availableHeight * 0.76f));
        }

        start.setOnClickListener(v -> {
            if (!canStartLocalImport()) return;
            List<BatchImportModels.ImportGroup> confirmed = new ArrayList<>();
            if (combineAll.isChecked()) {
                String title = combinedTitle.getText().toString().trim();
                if (title.isEmpty()) {
                    combinedTitle.setError("请填写合集名称");
                    return;
                }
                List<BatchImportModels.FileCandidate> files = new ArrayList<>();
                for (BatchImportModels.ImportGroup group : groups) files.addAll(group.volumes);
                confirmed.add(new BatchImportModels.ImportGroup("confirmed", title, false, BatchImportPlanner.orderVolumes(files)));
            } else {
                for (int i = 0; i < groups.size(); i++) {
                    BatchImportModels.ImportGroup group = groups.get(i);
                    if (choices.get(i).isChecked()) confirmed.add(group);
                    else for (BatchImportModels.FileCandidate file : group.volumes)
                        confirmed.add(new BatchImportModels.ImportGroup(group.key + ":" + file.selectionIndex,
                                stripBatchExtension(file.fileName), false, Collections.singletonList(file)));
                }
            }
            dialog.dismiss();
            startBatchImport(items, confirmed);
        });
    }

    private void startBatchImport(List<PendingImportItem> orderedItems, List<BatchImportModels.ImportGroup> plannedGroups) {
        startBatchImport(orderedItems, plannedGroups, null);
    }

    private File batchSessionFile() {
        return new File(getLocalStorageManager().getLibraryRoot(), "batch-import.json");
    }

    private void resumeBatchImport() {
        if (!canStartLocalImport() || savedImportSession == null) return;
        BatchImportSession session = savedImportSession;
        localImportScanning = true;
        localLibraryIo.submit(() -> {
            try {
                session.retryFailed();
                List<PendingImportItem> items = new ArrayList<>();
                List<BatchImportModels.ImportGroup> groups = new ArrayList<>();
                for (BatchImportSession.Group group : session.pendingGroups()) {
                    List<BatchImportModels.FileCandidate> candidates = new ArrayList<>();
                    for (BatchImportSession.Item item : group.items) {
                        if (!"pending".equals(item.state) && !"running".equals(item.state)) continue;
                        items.add(new PendingImportItem(Uri.parse(item.uri), item.name, item.format, group.title,
                                stripBatchExtension(item.name), false, item.selectionIndex));
                        candidates.add(new BatchImportModels.FileCandidate(null, null, group.title, item.name,
                                item.uri, null, item.format, "", item.selectionIndex));
                    }
                    groups.add(new BatchImportModels.ImportGroup(group.key, group.title, false, candidates));
                }
                main.post(() -> {
                    localImportScanning = false;
                    if (!activityDestroyed && !isFinishing() && !items.isEmpty()) startBatchImport(items, groups, session);
                });
            } catch (IOException e) {
                main.post(() -> { localImportScanning = false; if (!activityDestroyed) showRemErrorToast("无法恢复导入记录，请重试"); });
            }
        });
    }

    private void startBatchImport(List<PendingImportItem> orderedItems, List<BatchImportModels.ImportGroup> plannedGroups,
                                  BatchImportSession resumed) {
        startBatchImport(orderedItems, plannedGroups, resumed, null);
    }

    private void startBatchImport(List<PendingImportItem> orderedItems, List<BatchImportModels.ImportGroup> plannedGroups,
                                  BatchImportSession resumed, String appendToBookId) {
        if (resumed != null && resumed.cancelled) return;
        final Map<Integer, PendingImportItem> itemsBySelection = new HashMap<>();
        for (PendingImportItem item : orderedItems) itemsBySelection.put(item.selectionIndex, item);

        final ActiveImportTask task = new ActiveImportTask("正在导入漫画", false);
        task.totalItems = orderedItems.size();
        task.currentItem = 1;
        task.currentMessage = "准备中...";
        task.showDialogAction = () -> showThemedImportProgressDialog(task);
        currentImportTask = task;

        showThemedImportProgressDialog(task);
        // Batch work is deliberately non-blocking: the bookshelf banner remains available
        // for progress/cancel while the user can continue browsing other tabs.
        if (orderedItems.size() > 1 && task.dialog != null && task.dialog.isShowing()) {
            task.dialog.dismiss();
        }
        refreshLocalBookshelf();

        localLibraryIo.submit(() -> {
            try {
                if (resumed == null) {
                    List<BatchImportSession.Group> groups = new ArrayList<>();
                    for (BatchImportModels.ImportGroup group : plannedGroups) {
                        List<BatchImportSession.Item> files = new ArrayList<>();
                        for (BatchImportModels.FileCandidate candidate : group.volumes) {
                            PendingImportItem item = itemsBySelection.get(candidate.selectionIndex);
                            files.add(new BatchImportSession.Item(item.uri.toString(), item.displayName, item.format, item.selectionIndex));
                        }
                        groups.add(new BatchImportSession.Group(group.key, group.title, appendToBookId, files, appendToBookId != null));
                    }
                    task.session = BatchImportSession.create(batchSessionFile(), groups);
                } else task.session = resumed;
                main.post(() -> savedImportSession = task.session);
            } catch (IOException e) {
                main.post(() -> {
                    appendErrorLog("创建或恢复漫画导入批次失败", e);
                    if (currentImportTask == task) currentImportTask = null;
                    if (task.dialog != null) task.dialog.dismiss();
                    if (!activityDestroyed) { refreshLocalBookshelf(); showRemErrorToast("请先继续或取消上次导入任务；导入记录不可用时请保留日志"); }
                });
                return;
            }
            java.util.concurrent.atomic.AtomicInteger completed = new java.util.concurrent.atomic.AtomicInteger();
            List<Future<BatchImportOutcome>> futures = new ArrayList<>();
            for (BatchImportModels.ImportGroup group : plannedGroups) {
                futures.add(localBatchIo.submit(() -> processImportGroup(group, itemsBySelection, task, completed, orderedItems.size())));
            }

            int successCount = 0;
            int skippedCount = 0;
            List<String> failedItems = new ArrayList<>();
            List<String> failedReasons = new ArrayList<>();
            for (Future<BatchImportOutcome> future : futures) {
                try {
                    BatchImportOutcome outcome = future.get();
                    successCount += outcome.successCount;
                    skippedCount += outcome.skippedCount;
                    failedItems.addAll(outcome.failedItems);
                    failedReasons.addAll(outcome.failedReasons);
                } catch (Exception e) {
                    main.post(() -> appendErrorLog("批量漫画导入任务失败", e));
                    failedItems.add("批量导入任务");
                    failedReasons.add(clean(e.getMessage(), "批量导入失败"));
                }
            }

            final int finalSuccess = successCount;
            final int finalSkipped = skippedCount;
            final boolean wasCancelled = task.cancelled.get();
            final List<String> finalFailedItems = new ArrayList<>(failedItems);
            final List<String> finalFailedReasons = new ArrayList<>(failedReasons);
            if (task.userCancelled && !task.persistenceFailed) {
                try { task.session.cancel(); }
                catch (IOException e) {
                    task.persistenceFailed = true;
                    android.util.Log.w("MainActivity", "Cannot persist cancellation", e);
                }
            }

            main.post(() -> {
                if (activityDestroyed || isFinishing()) return;
                if (currentImportTask == task) {
                    currentImportTask = null;
                }
                if (task.dialog != null && task.dialog.isShowing()) {
                    task.dialog.dismiss();
                    task.dialog = null;
                }
                refreshLocalBookshelf();
                if (isFinishing()) return;

                if (appendToBookId != null) {
                    com.xxcomic.local.VolumeManagerSheet activeSheet = com.xxcomic.local.VolumeManagerSheet.getActiveInstance();
                    if (activeSheet != null && activeSheet.isShowing() && appendToBookId.equals(activeSheet.getBookId())) {
                        activeSheet.reloadVolumes();
                    } else if (TextUtils.equals(activeDetailId, appendToBookId)) {
                        showLocalDetail(appendToBookId);
                    }
                }

                if (task.persistenceFailed) {
                    showRemErrorToast("保存导入状态失败，已暂停；已完成内容保留，可稍后继续");
                } else if (wasCancelled) {
                    showRemSuccessToast("已取消导入" + (finalSuccess > 0 ? "，已完成 " + finalSuccess + " 个文件" : ""));
                } else if (finalFailedItems.isEmpty() && finalSkipped > 0) {
                    showRemSuccessToast("导入 " + finalSuccess + " 个文件，跳过 " + finalSkipped + " 个已有文件");
                } else if (finalSuccess > 0 && finalFailedItems.isEmpty()) {
                    if (orderedItems.size() > 1) {
                        showRemSuccessToast("成功导入 " + finalSuccess + " 个文件");
                    } else {
                        showRemSuccessToast("成功导入《" + orderedItems.get(0).comicTitle + "》");
                    }
                } else if (finalSuccess > 0 && !finalFailedItems.isEmpty()) {
                    StringBuilder sb = new StringBuilder();
                    sb.append("已成功导入 ").append(finalSuccess).append(" 个文件。\n以下 ").append(finalFailedItems.size()).append(" 项导入失败：\n");
                    for (int j = 0; j < Math.min(finalFailedItems.size(), 5); j++) {
                        sb.append("• ").append(finalFailedItems.get(j)).append(": ").append(finalFailedReasons.get(j)).append("\n");
                    }
                    if (finalFailedItems.size() > 5) {
                        sb.append("...等共 ").append(finalFailedItems.size()).append(" 项");
                    }
                    showRemDialog(R.drawable.rem_error, "部分漫画导入失败", sb.toString().trim(), "确定", null);
                } else if (!finalFailedItems.isEmpty()) {
                    String firstReason = finalFailedReasons.get(0);
                    showRemDialog(R.drawable.rem_error, "导入失败", "未能导入所选漫画：\n" + firstReason, "确定", null);
                }
            });
        });
    }

    private List<BatchImportModels.ImportGroup> buildImportGroups(List<PendingImportItem> items) {
        List<BatchImportModels.FileCandidate> candidates = new ArrayList<>();
        for (PendingImportItem item : items) {
            candidates.add(new BatchImportModels.FileCandidate(null, null, item.seriesTitle, item.displayName,
                    item.uri != null ? item.uri.toString() : "", item.volumeOrder, item.format, "", item.selectionIndex));
        }
        return BatchImportPlanner.plan(candidates);
    }

    private BatchImportOutcome processImportGroup(BatchImportModels.ImportGroup group,
                                                   Map<Integer, PendingImportItem> itemsBySelection,
                                                   ActiveImportTask task,
                                                   java.util.concurrent.atomic.AtomicInteger completed,
                                                   int total) {
        BatchImportOutcome outcome = new BatchImportOutcome();
        LocalImporter importer = new LocalImporter(this, getLocalStorageManager(), getLocalLibraryStore());
        BatchImportSession.Group savedGroup = null;
        for (BatchImportSession.Group saved : task.session.groups) if (saved.key.equals(group.key)) { savedGroup = saved; break; }
        if (savedGroup == null) return outcome;
        String targetBookId = TextUtils.isEmpty(savedGroup.targetBookId) ? null : savedGroup.targetBookId;
        final BatchImportSession.Group persistentGroup = savedGroup;
        for (BatchImportModels.FileCandidate candidate : group.volumes) {
            if (task.cancelled.get() || task.session.cancelled) break;
            PendingImportItem item = itemsBySelection.get(candidate.selectionIndex);
            if (item == null) continue;
            BatchImportSession.Item savedItem = null;
            for (BatchImportSession.Item saved : savedGroup.items)
                if (saved.selectionIndex == item.selectionIndex) { savedItem = saved; break; }
            if (savedItem == null) continue;
            int current = completed.get() + 1;
            task.currentItem = current;
            String initialMsg = "(" + current + "/" + total + ") 正在整理《" + group.title + "》· " + item.displayName;
            task.currentMessage = initialMsg;
            updateImportTaskProgress(task, initialMsg);
            try {
                if (getLocalLibraryStore().getBook(targetBookId) == null) {
                    if (savedGroup.requiresExistingBook) throw new IOException("原合集已移除，请取消任务后重新导入");
                    for (BatchImportSession.Item saved : savedGroup.items)
                        if ("completed".equals(saved.state)) throw new IOException("原合集已移除，请取消任务后重新导入");
                }
                task.session.start(savedGroup, savedItem);
                String chapterTitle = stripBatchExtension(item.displayName);
                LocalModels.Book imported = importer.importBatchVolume(item.uri, item.displayName, group.title, chapterTitle, targetBookId,
                        new LocalModels.ImportProgressCallback() {
                            @Override public void onBookIdentified(String id) throws IOException {
                                // This callback runs only when creating a new book. An explicitly chosen
                                // existing series must never be recreated if deleted while hashing a file.
                                if (persistentGroup.requiresExistingBook)
                                    throw new IOException("原合集已移除，请取消任务后重新导入");
                                for (BatchImportSession.Item previous : persistentGroup.items)
                                    if ("completed".equals(previous.state))
                                        throw new IOException("原合集已移除，请取消任务后重新导入");
                                task.session.setTargetBookId(persistentGroup, id);
                            }
                            @Override
                            public void onProgress(long currentBytes, long totalBytes, String message) {
                                String msg = "(" + current + "/" + total + ") " + message;
                                task.currentMessage = msg;
                                updateImportTaskProgress(task, msg);
                            }

                            @Override
                            public boolean isCancelled() {
                                return task.cancelled.get() || task.session.cancelled;
                            }
                        });
                if (targetBookId == null) targetBookId = imported.id;
                task.session.complete(savedGroup, savedItem, targetBookId);
                outcome.successCount++;
                main.post(() -> {
                    if (batchShelfRefreshPending || activityDestroyed || isFinishing()) return;
                    batchShelfRefreshPending = true;
                    main.postDelayed(() -> {
                        batchShelfRefreshPending = false;
                        if (!activityDestroyed && !isFinishing()) refreshLocalBookshelf();
                    }, 800);
                });
            } catch (LocalImporter.AlreadyImportedException e) {
                try { task.session.skip(savedGroup, savedItem); }
                catch (IOException failure) { task.persistenceFailed = true; task.cancelled.set(true); }
                outcome.skippedCount++;
            } catch (InterruptedException e) {
                break;
            } catch (Exception e) {
                if (targetBookId == null && !TextUtils.isEmpty(savedGroup.targetBookId)) targetBookId = savedGroup.targetBookId;
                if (!task.cancelled.get()) main.post(() -> appendErrorLog("漫画文件导入失败：" + item.displayName, e));
                if (!task.cancelled.get()) try { task.session.fail(savedGroup, savedItem, clean(e.getMessage(), "导入失败")); }
                catch (IOException failure) { task.persistenceFailed = true; task.cancelled.set(true); }
                outcome.failedItems.add(item.displayName);
                outcome.failedReasons.add(clean(e.getMessage(), "解析或导入失败"));
            } finally {
                completed.incrementAndGet();
            }
        }
        return outcome;
    }

    private static String stripBatchExtension(String name) {
        if (name == null || name.trim().isEmpty()) return "全本";
        String value = name.trim();
        int dot = value.lastIndexOf('.');
        return dot > 0 ? value.substring(0, dot).trim() : value;
    }

    private void handleImportFolderUri(Uri treeUri) {
        if (treeUri == null) return;
        try {
            getContentResolver().takePersistableUriPermission(treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (Exception ignored) {}
        if (!canStartLocalImport()) return;
        final ActiveImportTask task = new ActiveImportTask("正在导入文件夹漫画", true);
        task.currentMessage = "正在读取文件夹...";
        task.showDialogAction = () -> showThemedImportProgressDialog(task);
        currentImportTask = task;

        showThemedImportProgressDialog(task);
        refreshLocalBookshelf();

        localLibraryIo.submit(() -> {
            LocalImporter importer = new LocalImporter(this, getLocalStorageManager(), getLocalLibraryStore());
            String errorMsg = null;
            boolean success = false;
            try {
                importer.importFolderUri(treeUri, null, new LocalModels.ImportProgressCallback() {
                    @Override
                    public void onProgress(long currentBytes, long totalBytes, String message) {
                        task.currentMessage = message;
                        updateImportTaskProgress(task, message);
                    }

                    @Override
                    public boolean isCancelled() {
                        return task.cancelled.get();
                    }
                });
                success = true;
            } catch (InterruptedException e) {
                // Cancelled
            } catch (Exception e) {
                errorMsg = e.getMessage();
                if (!task.cancelled.get()) main.post(() -> appendErrorLog("漫画文件夹导入失败", e));
            }

            final boolean finalSuccess = success;
            final boolean wasCancelled = task.cancelled.get();
            final String finalError = errorMsg;

            main.post(() -> {
                if (activityDestroyed || isFinishing()) return;
                if (currentImportTask == task) {
                    currentImportTask = null;
                }
                if (task.dialog != null && task.dialog.isShowing()) {
                    task.dialog.dismiss();
                    task.dialog = null;
                }
                refreshLocalBookshelf();
                if (isFinishing()) return;

                if (wasCancelled) {
                    showRemSuccessToast("已取消文件夹导入");
                } else if (finalSuccess) {
                    showRemSuccessToast("成功导入文件夹漫画");
                } else if (finalError != null) {
                    showRemDialog(R.drawable.rem_error, "导入失败", finalError, "确定", null);
                }
            });
        });
    }

    private void showImportOptionsDialog() {
        if (!canStartLocalImport()) return;
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16),
                UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        ImageView rem = new ImageView(this);
        rem.setImageResource(R.drawable.rem_reader_resume);
        rem.setScaleType(ImageView.ScaleType.FIT_CENTER);
        header.addView(rem, new LinearLayout.LayoutParams(UIHelpers.dp(this, 40), UIHelpers.dp(this, 40)));

        LinearLayout headerText = new LinearLayout(this);
        headerText.setOrientation(LinearLayout.VERTICAL);
        headerText.setPadding(UIHelpers.dp(this, 10), 0, 0, 0);
        TextView title = UIHelpers.text(this, "导入本地漫画", 16, UIHelpers.TEXT, Typeface.BOLD);
        headerText.addView(title);
        TextView sub = UIHelpers.text(this, "选择本地漫画的导入来源", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        headerText.addView(sub, UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        header.addView(headerText, UIHelpers.weight(1));
        content.addView(header);

        LinearLayout archiveCard = new LinearLayout(this);
        archiveCard.setOrientation(LinearLayout.VERTICAL);
        archiveCard.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
        archiveCard.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 8), UIHelpers.BORDER));
        archiveCard.addView(UIHelpers.text(this, "📦 压缩包与电子书 (ZIP / CBZ / EPUB / PDF / MOBI / AZW)", 14, UIHelpers.TEXT, Typeface.BOLD));
        archiveCard.addView(UIHelpers.text(this, "支持单个或批量导入 .zip / .cbz / .epub / .pdf / .mobi / .azw / .azw3 文件", 11, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        content.addView(archiveCard, UIHelpers.marginTop(-1, UIHelpers.dp(this, 14)));

        LinearLayout folderCard = new LinearLayout(this);
        folderCard.setOrientation(LinearLayout.VERTICAL);
        folderCard.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
        folderCard.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 8), UIHelpers.BORDER));
        folderCard.addView(UIHelpers.text(this, "📁 图片文件夹", 14, UIHelpers.TEXT, Typeface.BOLD));
        folderCard.addView(UIHelpers.text(this, "支持包含图片或章节子目录的漫画文件夹", 11, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        content.addView(folderCard, UIHelpers.marginTop(-1, UIHelpers.dp(this, 8)));

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setView(content)
                .setNegativeButton("取消", null)
                .create();

        archiveCard.setOnClickListener(v -> {
            dialog.dismiss();
            checkStoragePermissionBeforeImport(() -> {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("*/*");
                intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{
                        "application/zip", "application/x-cbz", "application/x-zip-compressed",
                        "application/epub+zip", "application/pdf",
                        "application/x-mobipocket-ebook", "application/vnd.amazon.ebook",
                        "application/octet-stream"
                });
                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                startActivityForResult(intent, REQUEST_CODE_IMPORT_ARCHIVE);
            });
        });

        folderCard.setOnClickListener(v -> {
            dialog.dismiss();
            checkStoragePermissionBeforeImport(() -> {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
                startActivityForResult(intent, REQUEST_CODE_IMPORT_FOLDER);
            });
        });

        dialog.setOnShowListener(d -> {
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(this, 12), Color.TRANSPARENT));
                int width = Math.min(getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(this, 40), UIHelpers.dp(this, 328));
                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            }
            Button neg = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (neg != null) neg.setTextColor(UIHelpers.TEXT3);
        });

        dialog.show();
    }

    private boolean canStartLocalImport() {
        if (localImportScanning) {
            showRemSuccessToast("正在读取所选文件信息");
            return false;
        }
        if (!localLibraryReady) {
            if (localLibraryRecoveryError != null) {
                localLibraryRecoveryError = null;
                localStoreRecoveryStarted.set(false);
                ensureLocalLibraryRecovery();
            }
            showRemSuccessToast("正在整理本地文件，稍等一下哦");
            return false;
        }
        if (currentImportTask != null) {
            showThemedImportProgressDialog(currentImportTask);
            return false;
        }
        return true;
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putString("appendVolumeBookId", appendVolumeBookId);
        super.onSaveInstanceState(outState);
    }

    private void pickAdditionalVolumes(LocalModels.Book book) {
        if (!canStartLocalImport()) return;
        appendVolumeBookId = book.id;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        startActivityForResult(intent, REQUEST_CODE_APPEND_VOLUMES);
    }

    private void checkStoragePermissionBeforeImport(Runnable proceedAction) {
        if (proceedAction == null) return;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            if (!android.os.Environment.isExternalStorageManager()) {
                showRemDialog(R.drawable.rem_reader_resume, "建议开启文件权限",
                        "为直接读取本地漫画文件并不占用重复手机空间（零拷贝），建议开启「所有文件访问权限」。\n开启后将直接映射原文件，不再复制副本。",
                        "去开启", () -> {
                            try {
                                Intent intent = new Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                                intent.setData(Uri.parse("package:" + getPackageName()));
                                startActivity(intent);
                            } catch (Exception e) {
                                try {
                                    Intent intent = new Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);
                                    startActivity(intent);
                                } catch (Exception ignored) {}
                            }
                        },
                        "直接选择", proceedAction);
                return;
            }
        } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{android.Manifest.permission.READ_EXTERNAL_STORAGE}, 1002);
            }
        }
        proceedAction.run();
    }

    private void showDeleteLocalBookDialog(LocalModels.Book book) {
        LocalDetailView.showDeleteDialog(this, book, getLocalLibraryStore(), getLocalStorageManager(),
                new LocalDetailView.Listener() {
                    @Override public void onBack() {}
                    @Override public void onRead(LocalModels.Book b, ComicModels.ComicDetail d, int chapterIndex) {}
                    @Override public void onBookRenamed(LocalModels.Book updatedBook) { refreshLocalBookshelf(); }
                    @Override public void onBookDeleted(LocalModels.Book deletedBook) {
                        details.remove(deletedBook.id);
                        summaries.remove(deletedBook.id);
                        refreshLocalBookshelf();
                    }
                    @Override public void showToast(String message) {
                        showRemSuccessToast(message);
                    }
                });
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
        if (offlinePageBack != null) {
            Runnable back = offlinePageBack; offlinePageBack = null; back.run(); return true;
        }
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
        if (activeChapterSheet != null && activeChapterSheet.isShowing()) {
            activeChapterSheet.dismiss();
            activeChapterSheet = null;
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
            if ("reader".equals(settingsScene) && !TextUtils.isEmpty(readerSettingsComicId)) {
                ComicModels.ComicDetail saved = details.get(readerSettingsComicId);
                settingsScene = "";
                readerSettingsComicId = "";
                if (saved != null) showReader(saved, readerSettingsChapterIndex); else showTab(2);
                return true;
            }
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            android.view.WindowManager.LayoutParams lp = getWindow().getAttributes();
            if (lp.layoutInDisplayCutoutMode != android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT) {
                lp.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT;
                getWindow().setAttributes(lp);
            }
        }
    }

    private void applyReaderSystemBars() {
        applyReaderSystemBars(true);
    }

    private void applyReaderSystemBars(boolean stableLayout) {
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        int flags = View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;
        getWindow().getDecorView().setSystemUiVisibility(flags);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            android.view.WindowManager.LayoutParams lp = getWindow().getAttributes();
            if (lp.layoutInDisplayCutoutMode != android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES) {
                lp.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
                getWindow().setAttributes(lp);
            }
        }
    }

    private int getStatusBarOrCutoutHeight() {
        int inset = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            View decor = getWindow().getDecorView();
            android.view.WindowInsets insets = decor.getRootWindowInsets();
            if (insets != null) {
                android.view.DisplayCutout cutout = insets.getDisplayCutout();
                if (cutout != null) {
                    inset = Math.max(inset, cutout.getSafeInsetTop());
                }
                inset = Math.max(inset, insets.getSystemWindowInsetTop());
            }
        }
        if (inset <= 0) {
            int resourceId = getResources().getIdentifier("status_bar_height", "dimen", "android");
            if (resourceId > 0) {
                inset = getResources().getDimensionPixelSize(resourceId);
            }
        }
        if (inset <= 0) {
            inset = UIHelpers.dp(this, 28);
        }
        return inset;
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
            case "reader": showReaderSettings(); break;
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
        enterScreen(false);
    }

    private void enterScreen(boolean keepDetailSearch) {
        if (readerVisible) {
            if (readingHabitTracker != null) {
                readingHabitTracker.onExitReader();
            }
            if (main != null && readerTickRunnable != null) {
                main.removeCallbacks(readerTickRunnable);
            }
        }
        offlinePageBack = null;
        if (!keepDetailSearch) detailSourceSearch.detach();
        if (detailSourceSheet != null) detailSourceSheet.dismissImmediately();
        detailSourceEntry = null;
        detailSwitchGeneration++;
        pendingDetailSourceId = "";
        if (detailSwitchTask != null) detailSwitchTask.cancel(true);
        detailSwitchTask = null;
        if (detailSwitchTimeout != null) main.removeCallbacks(detailSwitchTimeout);
        detailSwitchTimeout = null;
        releaseReaderViews();
        dismissTransientHint();
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
        checkPendingUpdatePrompt();
    }

    private String downloadSummaryText() {
        try {
            com.xxcomic.download.DownloadRuntime runtime = com.xxcomic.download.DownloadRuntime.get(this);
            int pending = 0;
            for (com.xxcomic.download.DownloadModels.Task t : runtime.store.list()) {
                if (com.xxcomic.download.DownloadModels.active(t.state)
                        || t.state == com.xxcomic.download.DownloadModels.State.QUEUED
                        || t.state == com.xxcomic.download.DownloadModels.State.WAITING_NETWORK) {
                    pending++;
                }
            }
            return pending > 0 ? pending + " 个进行中" : "";
        } catch (Exception ignored) {
            return "";
        }
    }

    private void renderSettings(LinearLayout page) {
        addTitle(page, "设置", null);
        page.addView(settingsSectionText("阅读与外观"));
        LinearLayout appearance = settingsList();
        appearance.setPadding(0, 0, 0, 0);
        appearance.addView(settingsMenuItem(themeIcon(), "主题模式", "跟随系统、浅色或深色", themeModeLabel(), this::showThemeDrawer));
        appearance.addView(UIHelpers.divider(this));
        appearance.addView(settingsMenuItem(R.drawable.ic_bookshelf, "启动书架", launchBookshelfSubtitle(), launchBookshelfModeLabel(), this::showLaunchBookshelfDrawer));
        appearance.addView(UIHelpers.divider(this));
        appearance.addView(settingsMenuItem(R.drawable.ic_history, "阅读历史", "章节与阅读位置", progress.size() + " 条", this::showHistory));
        page.addView(appearance);

        page.addView(settingsSectionText("站源与本地数据"));
        LinearLayout local = settingsList();
        local.setPadding(0, 0, 0, 0);
        local.addView(settingsMenuItem(R.drawable.ic_source, "站源管理", "拖动排序、启停与导入导出",
                enabledBuiltinSources().size() + " 个开启", this::showSourceManagement));
        local.addView(UIHelpers.divider(this));
        local.addView(settingsMenuItem(R.drawable.ic_download, "下载中心", "任务进度、暂停与章节重试",
                downloadSummaryText(), this::showDownloadCenter));
        local.addView(UIHelpers.divider(this));
        local.addView(settingsMenuItem(R.drawable.ic_bookshelf, "本地存储管理", "仅 Wi-Fi 下载 · 副本与空间统计", "", this::showLocalStorage));
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
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(UIHelpers.BG);
        page.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 12), UIHelpers.dp(this, 16), UIHelpers.dp(this, 24));
        renderSources(page);
        root.addView(page, UIHelpers.match());
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
        if (searchAppendVerificationRequired) {
            TextView verify = UIHelpers.text(
                    this, "验证已失效 · 去验证", 12, UIHelpers.ACCENT, Typeface.NORMAL);
            verify.setGravity(Gravity.CENTER);
            verify.setOnClickListener(v -> showSourceManagement());
            searchPagingFooter = verify;
        } else if (searchAppendFailed) {
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
        addBookshelfHeader(page);

        bookshelfContainer = new FrameLayout(this);
        page.addView(bookshelfContainer, new LinearLayout.LayoutParams(-1, 0, 1));

        onlineBookshelfView = buildOnlineBookshelfView();
        bookshelfContainer.addView(onlineBookshelfView, new FrameLayout.LayoutParams(-1, -1));

        localBookshelfView = buildLocalBookshelfView();
        bookshelfContainer.addView(localBookshelfView, new FrameLayout.LayoutParams(-1, -1));

        onlineBookshelfView.setVisibility(bookshelfTab == 0 ? View.VISIBLE : View.GONE);
        localBookshelfView.setVisibility(bookshelfTab == 1 ? View.VISIBLE : View.GONE);
    }

    private void addBookshelfHeader(LinearLayout page) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        titleMyBookshelf = new TextView(this);
        titleMyBookshelf.setText("我的书架");
        titleMyBookshelf.setTextSize(bookshelfTab == 0 ? 24 : 16);
        titleMyBookshelf.setTextColor(bookshelfTab == 0 ? UIHelpers.TEXT : UIHelpers.TEXT3);
        titleMyBookshelf.setTypeface(Typeface.create("sans-serif-medium", bookshelfTab == 0 ? Typeface.BOLD : Typeface.NORMAL));
        titleMyBookshelf.setGravity(Gravity.CENTER_VERTICAL);
        titleMyBookshelf.setOnClickListener(v -> switchBookshelfTab(0));
        row.addView(titleMyBookshelf);

        TextView divider = UIHelpers.text(this, " | ", 16, UIHelpers.TEXT3, Typeface.NORMAL);
        divider.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(divider);

        titleLocalBookshelf = new TextView(this);
        titleLocalBookshelf.setText("本地书架");
        titleLocalBookshelf.setTextSize(bookshelfTab == 1 ? 24 : 16);
        titleLocalBookshelf.setTextColor(bookshelfTab == 1 ? UIHelpers.TEXT : UIHelpers.TEXT3);
        titleLocalBookshelf.setTypeface(Typeface.create("sans-serif-medium", bookshelfTab == 1 ? Typeface.BOLD : Typeface.NORMAL));
        titleLocalBookshelf.setGravity(Gravity.CENTER_VERTICAL);
        titleLocalBookshelf.setOnClickListener(v -> switchBookshelfTab(1));
        row.addView(titleLocalBookshelf);

        View space = new View(this);
        row.addView(space, new LinearLayout.LayoutParams(0, 0, 1));

        bookshelfRightActions = new LinearLayout(this);
        bookshelfRightActions.setOrientation(LinearLayout.HORIZONTAL);
        bookshelfRightActions.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(bookshelfRightActions);

        updateBookshelfRightActions();

        // Keep the header bounded so the weighted bookshelf below retains its height.
        LinearLayout.LayoutParams headerParams = new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 48));
        headerParams.bottomMargin = UIHelpers.dp(this, 6);
        page.addView(row, headerParams);
    }

    private void switchBookshelfTab(int newTab) {
        if (bookshelfTab == newTab) return;
        if (bookshelfTabAnimator != null && bookshelfTabAnimator.isRunning()) {
            bookshelfTabAnimator.cancel();
        }

        final int oldTab = bookshelfTab;
        bookshelfTab = newTab;
        if (readingHabitTracker != null) {
            readingHabitTracker.setLastManualTab(newTab);
        }

        if (onlineBookshelfView != null) {
            onlineBookshelfView.setVisibility(newTab == 0 ? View.VISIBLE : View.GONE);
        }
        if (localBookshelfView != null) {
            localBookshelfView.setVisibility(newTab == 1 ? View.VISIBLE : View.GONE);
        }
        updateBookshelfRightActions();

        final int activeColor = UIHelpers.TEXT;
        final int inactiveColor = UIHelpers.TEXT3;

        bookshelfTabAnimator = ValueAnimator.ofFloat(0f, 1f);
        bookshelfTabAnimator.setDuration(200);
        bookshelfTabAnimator.setInterpolator(new DecelerateInterpolator());
        bookshelfTabAnimator.addUpdateListener(animation -> {
            float frac = (float) animation.getAnimatedValue();
            if (titleMyBookshelf != null && titleLocalBookshelf != null) {
                float mySize = oldTab == 0 ? 24f - 8f * frac : 16f + 8f * frac;
                float localSize = oldTab == 1 ? 24f - 8f * frac : 16f + 8f * frac;
                int myColor = interpolateColor(oldTab == 0 ? activeColor : inactiveColor,
                        newTab == 0 ? activeColor : inactiveColor, frac);
                int localColor = interpolateColor(oldTab == 1 ? activeColor : inactiveColor,
                        newTab == 1 ? activeColor : inactiveColor, frac);

                titleMyBookshelf.setTextSize(mySize);
                titleMyBookshelf.setTextColor(myColor);
                titleLocalBookshelf.setTextSize(localSize);
                titleLocalBookshelf.setTextColor(localColor);
            }
        });
        bookshelfTabAnimator.addListener(new android.animation.AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(android.animation.Animator animation) {
                if (titleMyBookshelf != null && titleLocalBookshelf != null) {
                    titleMyBookshelf.setTextSize(newTab == 0 ? 24 : 16);
                    titleMyBookshelf.setTextColor(newTab == 0 ? activeColor : inactiveColor);
                    titleMyBookshelf.setTypeface(Typeface.create("sans-serif-medium", newTab == 0 ? Typeface.BOLD : Typeface.NORMAL));

                    titleLocalBookshelf.setTextSize(newTab == 1 ? 24 : 16);
                    titleLocalBookshelf.setTextColor(newTab == 1 ? activeColor : inactiveColor);
                    titleLocalBookshelf.setTypeface(Typeface.create("sans-serif-medium", newTab == 1 ? Typeface.BOLD : Typeface.NORMAL));
                }
            }
        });
        bookshelfTabAnimator.start();
    }

    private static int interpolateColor(int colorStart, int colorEnd, float fraction) {
        float f = Math.max(0f, Math.min(1f, fraction));
        int a = Math.round(Color.alpha(colorStart) + f * (Color.alpha(colorEnd) - Color.alpha(colorStart)));
        int r = Math.round(Color.red(colorStart) + f * (Color.red(colorEnd) - Color.red(colorStart)));
        int g = Math.round(Color.green(colorStart) + f * (Color.green(colorEnd) - Color.green(colorStart)));
        int b = Math.round(Color.blue(colorStart) + f * (Color.blue(colorEnd) - Color.blue(colorStart)));
        return Color.argb(a, r, g, b);
    }

    private void updateBookshelfRightActions() {
        if (bookshelfRightActions == null) return;
        bookshelfRightActions.removeAllViews();
        int count = (bookshelfTab == 0)
                ? favorites.size()
                : (localLibraryReady ? Math.max(0, getLocalLibraryStore().getBookCount() - pendingDeleteLocalBookIds.size()) : 0);
        bookshelfRightActions.addView(UIHelpers.text(this, count + " 本", 12, UIHelpers.TEXT3, Typeface.NORMAL));
        ImageView rem = new ImageView(this);
        rem.setImageResource(R.drawable.rem_reader_resume);
        rem.setScaleType(ImageView.ScaleType.CENTER_CROP);
        rem.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 12), UIHelpers.BORDER));
        rem.setClipToOutline(true);
        rem.setContentDescription("蕾姆主题");
        LinearLayout.LayoutParams remParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 23), UIHelpers.dp(this, 23));
        remParams.leftMargin = UIHelpers.dp(this, 8);
        bookshelfRightActions.addView(rem, remParams);
    }

    private View buildOnlineBookshelfView() {
        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());

        List<String> visible = filterFavorites();
        String continueId = null;
        long latestRead = Long.MIN_VALUE;
        for (String id : progress.keySet()) {
            if (isLocalComic(id)) continue;
            long readAt = lastViewedAt.containsKey(id) ? lastViewedAt.get(id) : Long.MIN_VALUE;
            if (readAt > latestRead) {
                latestRead = readAt;
                continueId = id;
            }
        }
        if (continueId == null && !progress.isEmpty()) {
            for (String id : progress.keySet()) {
                if (!isLocalComic(id)) {
                    continueId = id;
                    break;
                }
            }
        }
        if (favorites.isEmpty() && continueId == null) {
            content.addView(bookshelfEmptyState(false));
            return scroll;
        }
        if (continueId != null) {
            content.addView(bookshelfSectionHeader("接着看", "阅读历史 ›", this::showHistory));
            content.addView(continueReadingRow(continueId));
        }
        content.addView(bookshelfSectionHeader("全部收藏", visible.isEmpty() ? "0 本" : "最近使用排序", null));
        if (visible.isEmpty()) {
            content.addView(bookshelfEmptyState(true));
            return scroll;
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
        return scroll;
    }

    private View buildLocalBookshelfView() {
        if (!localLibraryReady) {
            TextView state = UIHelpers.text(this, localLibraryRecoveryError == null
                    ? "正在整理本地书架…" : localLibraryRecoveryError + " · 点击重试", 14, UIHelpers.TEXT3, Typeface.NORMAL);
            state.setGravity(Gravity.CENTER);
            state.setOnClickListener(v -> canStartLocalImport());
            return state;
        }
        String continueLocalId = null;
        long latestRead = Long.MIN_VALUE;
        for (String id : progress.keySet()) {
            LocalModels.Book local = getLocalLibraryStore().findByProgressKey(id);
            if (local == null || pendingDeleteLocalBookIds.contains(local.id)) continue;
            long readAt = lastViewedAt.containsKey(id) ? lastViewedAt.get(id) : Long.MIN_VALUE;
            if (readAt > latestRead) {
                latestRead = readAt;
                continueLocalId = local.id;
            }
        }
        if (continueLocalId == null) {
            for (String id : progress.keySet()) {
                LocalModels.Book local = getLocalLibraryStore().findByProgressKey(id);
                if (local != null && !pendingDeleteLocalBookIds.contains(local.id)) {
                    continueLocalId = local.id;
                    break;
                }
            }
        }
        LocalModels.Book continuing = continueLocalId == null ? null : getLocalLibraryStore().getBook(continueLocalId);
        int continueChapter = continuing != null ? savedChapter(continuing.progressKey) : 0;

        View importBanner = (currentImportTask != null && !currentImportTask.cancelled.get())
                ? buildActiveImportBanner(currentImportTask)
                : null;
        if (currentImportTask == null && savedImportSession != null) {
            boolean unfinished = savedImportSession.hasPending();
            for (BatchImportSession.Group group : savedImportSession.groups)
                for (BatchImportSession.Item item : group.items) unfinished |= "failed".equals(item.state);
            if (unfinished) {
                LinearLayout banner = new LinearLayout(this);
                banner.setGravity(Gravity.CENTER_VERTICAL);
                banner.setPadding(UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 6), UIHelpers.dp(this, 12));
                banner.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 10), UIHelpers.BORDER));
                banner.addView(UIHelpers.text(this, "有未完成的导入 · 已完成分卷可阅读", 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.weight(1));
                TextView resume = UIHelpers.text(this, "继续", 13, UIHelpers.ACCENT, Typeface.BOLD);
                resume.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 8), UIHelpers.dp(this, 8), UIHelpers.dp(this, 8));
                resume.setOnClickListener(v -> resumeBatchImport());
                banner.addView(resume);
                TextView cancel = UIHelpers.text(this, "取消", 13, UIHelpers.TEXT3, Typeface.NORMAL);
                cancel.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 8), UIHelpers.dp(this, 8), UIHelpers.dp(this, 8));
                cancel.setOnClickListener(v -> {
                    if (!canStartLocalImport()) return;
                    localImportScanning = true;
                    BatchImportSession session = savedImportSession;
                    localLibraryIo.execute(() -> {
                        try {
                            session.cancel();
                            main.post(() -> { localImportScanning = false; if (!activityDestroyed) refreshLocalBookshelf(); });
                        } catch (IOException e) { main.post(() -> {
                            localImportScanning = false;
                            if (!activityDestroyed) showRemErrorToast("无法保存取消操作，请重试");
                        }); }
                    });
                });
                banner.addView(cancel);
                importBanner = banner;
            }
        }

        return LocalLibraryView.build(
                this,
                getLocalLibraryStore(),
                getLocalStorageManager(),
                continueLocalId,
                continueChapter,
                importBanner,
                pendingDeleteLocalBookIds,
                lastViewedAt,
                new LocalLibraryView.Listener() {
                    @Override
                    public void onBookClick(LocalModels.Book book) {
                        showLocalDetail(book.id);
                    }

                    @Override
                    public void onDeleteBookWithUndo(LocalModels.Book book) {
                        deleteLocalBookWithUndo(book);
                    }

                    @Override
                    public void onImportClick() {
                        showImportOptionsDialog();
                    }

                    @Override
                    public void onResumeRead(LocalModels.Book book) {
                        showDetailThenRead(book.id);
                    }

                    @Override
                    public void onHistoryClick() {
                        showHistory();
                    }
                }
        );
    }

    private void deleteLocalBookWithUndo(LocalModels.Book book) {
        if (book == null) return;
        final String bookId = book.id;
        final String title = clean(book.getDisplayTitle(), "本地漫画");

        Runnable existing = pendingLocalDeleteRunnables.remove(bookId);
        if (existing != null) {
            main.removeCallbacks(existing);
        }

        pendingDeleteLocalBookIds.add(bookId);
        refreshLocalBookshelf();

        final Runnable commitDelete = () -> {
            pendingLocalDeleteRunnables.remove(bookId);
            localLibraryIo.submit(() -> {
                try {
                    if (LocalModels.isDownload(book)) {
                        DownloadRuntime.get(this).deleteBook(book.id);
                    } else {
                        getLocalLibraryStore().deleteBook(bookId, getLocalStorageManager());
                    }
                    details.remove(bookId);
                    summaries.remove(bookId);
                } catch (Exception ignored) {
                } finally {
                    main.post(() -> {
                        pendingDeleteLocalBookIds.remove(bookId);
                        updateBookshelfRightActions();
                    });
                }
            });
        };

        pendingLocalDeleteRunnables.put(bookId, commitDelete);
        main.postDelayed(commitDelete, 3500L);

        showRemToast(R.drawable.rem_empty, "已移出《" + title + "》", "撤销", () -> {
            Runnable r = pendingLocalDeleteRunnables.remove(bookId);
            if (r != null) {
                main.removeCallbacks(r);
            }
            pendingDeleteLocalBookIds.remove(bookId);
            refreshLocalBookshelf();
        }, 3200L);
    }

    private void refreshLocalBookshelf() {
        if (bookshelfContainer != null) {
            int scrollY = 0;
            if (localBookshelfView instanceof ScrollView) {
                scrollY = localBookshelfView.getScrollY();
            }
            if (localBookshelfView != null) {
                bookshelfContainer.removeView(localBookshelfView);
            }
            localBookshelfView = buildLocalBookshelfView();
            bookshelfContainer.addView(localBookshelfView, new FrameLayout.LayoutParams(-1, -1));
            localBookshelfView.setVisibility(bookshelfTab == 1 ? View.VISIBLE : View.GONE);
            if (scrollY > 0 && localBookshelfView instanceof ScrollView) {
                final int targetY = scrollY;
                localBookshelfView.post(() -> localBookshelfView.scrollTo(0, targetY));
            }
        }
        updateBookshelfRightActions();
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

        FavoriteStarBadgeView star = new FavoriteStarBadgeView(this);
        boolean showStar = FavoriteUpdateCoordinator.getInstance().shouldShowBadge(id);
        star.setVisibility(showStar ? View.VISIBLE : View.GONE);
        FrameLayout.LayoutParams starParams = new FrameLayout.LayoutParams(
                UIHelpers.dp(this, 13), UIHelpers.dp(this, 13));
        starParams.gravity = Gravity.TOP | Gravity.RIGHT;
        starParams.topMargin = UIHelpers.dp(this, 3);
        starParams.rightMargin = UIHelpers.dp(this, 3);
        coverWrap.addView(star, starParams);
        favoriteBadgeViews.put(id, star);

        item.addView(coverWrap, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, coverHeight)));
        TextView titleView = UIHelpers.text(this, title, 13, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        titleView.setMinHeight(UIHelpers.dp(this, 34));
        item.addView(titleView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));
        item.setOnClickListener(v -> openComicDetail(id));
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
        List<SourceOrderList.Row> rows = new ArrayList<>();
        addSourceCard(rows, baoziConfig.id, () -> sourceCard(baoziConfig, sourceEnabled, () -> {
            sourceEnabled = !sourceEnabled;
            baoziConfig = baoziConfig.withEnabled(sourceEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, mh160Config.id, () -> sourceCard(mh160Config, mh160Enabled, () -> {
            mh160Enabled = !mh160Enabled;
            mh160Config = mh160Config.withEnabled(mh160Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, gmhConfig.id, () -> sourceCard(gmhConfig, gmhEnabled, () -> {
            gmhEnabled = !gmhEnabled;
            gmhConfig = gmhConfig.withEnabled(gmhEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, mh18Config.id, () -> sourceCard(mh18Config, mh18Enabled, () -> {
            mh18Enabled = !mh18Enabled;
            mh18Config = mh18Config.withEnabled(mh18Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, jmcomicConfig.id, () -> sourceCard(jmcomicConfig, jmcomicEnabled, () -> {
            jmcomicEnabled = !jmcomicEnabled;
            jmcomicConfig = jmcomicConfig.withEnabled(jmcomicEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, mkzhanConfig.id, () -> sourceCard(mkzhanConfig, mkzhanEnabled, () -> {
            mkzhanEnabled = !mkzhanEnabled;
            mkzhanConfig = mkzhanConfig.withEnabled(mkzhanEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, hiperdexConfig.id, () -> sourceCard(hiperdexConfig, hiperdexEnabled, () -> {
            hiperdexEnabled = !hiperdexEnabled;
            hiperdexConfig = hiperdexConfig.withEnabled(hiperdexEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, manhuaguiConfig.id, () -> sourceCard(manhuaguiConfig, manhuaguiEnabled, () -> {
            manhuaguiEnabled = !manhuaguiEnabled;
            manhuaguiConfig = manhuaguiConfig.withEnabled(manhuaguiEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, hanman18Config.id, () -> sourceCard(hanman18Config, hanman18Enabled, () -> {
            hanman18Enabled = !hanman18Enabled;
            hanman18Config = hanman18Config.withEnabled(hanman18Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, d5d6Config.id, () -> sourceCard(d5d6Config, d5d6Enabled, () -> {
            d5d6Enabled = !d5d6Enabled;
            d5d6Config = d5d6Config.withEnabled(d5d6Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, manbenConfig.id, () -> sourceCard(manbenConfig, manbenEnabled, () -> {
            manbenEnabled = !manbenEnabled;
            manbenConfig = manbenConfig.withEnabled(manbenEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, manhuazhanConfig.id, () -> sourceCard(manhuazhanConfig, manhuazhanEnabled, () -> {
            manhuazhanEnabled = !manhuazhanEnabled;
            manhuazhanConfig = manhuazhanConfig.withEnabled(manhuazhanEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, bbyinConfig.id, () -> sourceCard(bbyinConfig, bbyinEnabled, () -> {
            bbyinEnabled = !bbyinEnabled;
            bbyinConfig = bbyinConfig.withEnabled(bbyinEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, antbywConfig.id, () -> sourceCard(antbywConfig, antbywEnabled, () -> {
            antbywEnabled = !antbywEnabled;
            antbywConfig = antbywConfig.withEnabled(antbywEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, cuimhConfig.id, () -> sourceCard(cuimhConfig, cuimhEnabled, () -> {
            cuimhEnabled = !cuimhEnabled;
            cuimhConfig = cuimhConfig.withEnabled(cuimhEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, liumanhuaConfig.id, () -> sourceCard(liumanhuaConfig, liumanhuaEnabled, () -> {
            liumanhuaEnabled = !liumanhuaEnabled;
            liumanhuaConfig = liumanhuaConfig.withEnabled(liumanhuaEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, copy4000Config.id, () -> sourceCard(copy4000Config, copy4000Enabled, () -> {
            copy4000Enabled = !copy4000Enabled;
            copy4000Config = copy4000Config.withEnabled(copy4000Enabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        addSourceCard(rows, manwaConfig.id, () -> sourceCard(manwaConfig, manwaEnabled, () -> {
            manwaEnabled = !manwaEnabled;
            manwaConfig = manwaConfig.withEnabled(manwaEnabled);
            rebuildSourceClients();
            finishSourceToggle();
        }));
        TextView hint = UIHelpers.text(this, "按住左侧手柄拖动，排序同步到搜索", 11, UIHelpers.TEXT3, Typeface.NORMAL);
        page.addView(hint, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 8)));
        SourceOrderList list = new SourceOrderList(this,
                SourceOrder.apply(rows, sourceOrder, row -> row.id), this::saveSourceOrder);
        page.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));
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

    private void addSourceCard(List<SourceOrderList.Row> rows, String id, SourceOrderList.Factory factory) {
        rows.add(new SourceOrderList.Row(id, factory));
    }

    private List<String> defaultSourceOrder() {
        return Arrays.asList(baoziConfig.id, mh160Config.id, gmhConfig.id,
                mh18Config.id, jmcomicConfig.id, mkzhanConfig.id, hiperdexConfig.id,
                manhuaguiConfig.id, hanman18Config.id, d5d6Config.id, manbenConfig.id,
                manhuazhanConfig.id, bbyinConfig.id, antbywConfig.id, cuimhConfig.id,
                liumanhuaConfig.id, copy4000Config.id, manwaConfig.id);
    }

    private void saveSourceOrder(List<String> ids) {
        sourceOrder = SourceOrder.normalize(ids, defaultSourceOrder());
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .putString("source.order", new JSONArray(sourceOrder).toString()).apply();
    }

    private void resetSourceOrder() {
        saveSourceOrder(defaultSourceOrder());
        showSourceManagement();
        showRemSuccessToast("已恢复默认排序");
    }

    private int themeIcon() {
        if (themeMode == 1) return R.drawable.ic_sun;
        if (themeMode == 2) return R.drawable.ic_moon;
        return R.drawable.ic_auto;
    }

    private String themeModeLabel() {
        if (themeMode == 1) return "白天";
        if (themeMode == 2) return "黑夜";
        return "自动";
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
                main.post(() -> showRemSuccessToast("主题已应用"));
            }), UIHelpers.weight(1));
            if (i < labels.length - 1) choices.addView(UIHelpers.space(this, UIHelpers.dp(this, 6), 1));
        }
        showSettingsSheet("选择主题", choices);
    }

    private String launchBookshelfModeLabel() {
        int mode = readingHabitTracker != null ? readingHabitTracker.getLaunchMode() : ReadingHabitTracker.LAUNCH_MODE_AUTO;
        if (mode == ReadingHabitTracker.LAUNCH_MODE_MY) return "我的书架";
        if (mode == ReadingHabitTracker.LAUNCH_MODE_LOCAL) return "本地书架";
        return "自动跟随";
    }

    private String launchBookshelfSubtitle() {
        if (readingHabitTracker == null) return "自动跟随习惯";
        int mode = readingHabitTracker.getLaunchMode();
        if (mode == ReadingHabitTracker.LAUNCH_MODE_MY) return "启动默认显示我的书架";
        if (mode == ReadingHabitTracker.LAUNCH_MODE_LOCAL) return "启动默认显示本地书架";
        return readingHabitTracker.getCurrentAutoSubtitle();
    }

    private void showLaunchBookshelfDrawer() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, UIHelpers.dp(this, 10), 0, UIHelpers.dp(this, 6));

        int currentMode = readingHabitTracker != null ? readingHabitTracker.getLaunchMode() : ReadingHabitTracker.LAUNCH_MODE_AUTO;
        String autoSub = readingHabitTracker != null ? readingHabitTracker.getCurrentAutoSubtitle() : "自动跟随阅读偏好";

        PopupWindow[] popup = {null};

        content.addView(launchBookshelfOption("自动跟随习惯（默认）", autoSub, currentMode == ReadingHabitTracker.LAUNCH_MODE_AUTO, () -> {
            if (readingHabitTracker != null) readingHabitTracker.setLaunchMode(ReadingHabitTracker.LAUNCH_MODE_AUTO);
            if (popup[0] != null) popup[0].dismiss();
            rerenderSettingsScene();
        }));
        content.addView(UIHelpers.divider(this));
        content.addView(launchBookshelfOption("我的书架", "启动默认打开我的书架", currentMode == ReadingHabitTracker.LAUNCH_MODE_MY, () -> {
            if (readingHabitTracker != null) readingHabitTracker.setLaunchMode(ReadingHabitTracker.LAUNCH_MODE_MY);
            if (popup[0] != null) popup[0].dismiss();
            rerenderSettingsScene();
        }));
        content.addView(UIHelpers.divider(this));
        content.addView(launchBookshelfOption("本地书架", "启动默认打开本地书架", currentMode == ReadingHabitTracker.LAUNCH_MODE_LOCAL, () -> {
            if (readingHabitTracker != null) readingHabitTracker.setLaunchMode(ReadingHabitTracker.LAUNCH_MODE_LOCAL);
            if (popup[0] != null) popup[0].dismiss();
            rerenderSettingsScene();
        }));

        content.addView(UIHelpers.space(this, 1, UIHelpers.dp(this, 12)));
        TextView reset = UIHelpers.text(this, "重置习惯数据", 13, UIHelpers.ACCENT, Typeface.NORMAL);
        reset.setGravity(Gravity.CENTER);
        reset.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 10), UIHelpers.dp(this, 12), UIHelpers.dp(this, 10));
        reset.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        reset.setClickable(true);
        reset.setFocusable(true);
        reset.setOnClickListener(v -> {
            if (readingHabitTracker != null) readingHabitTracker.resetHabit();
            if (popup[0] != null) popup[0].dismiss();
            showRemSuccessToast("已重置习惯数据");
            rerenderSettingsScene();
        });
        content.addView(reset, new LinearLayout.LayoutParams(-1, -2));

        popup[0] = showSettingsSheet("启动书架", content);
    }

    private View launchBookshelfOption(String title, String subtitle, boolean selected, Runnable onClick) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 10), UIHelpers.dp(this, 8), UIHelpers.dp(this, 10));
        row.setClickable(true);
        row.setFocusable(true);
        UIHelpers.tapFeedback(row);
        row.setOnClickListener(v -> onClick.run());

        LinearLayout textCol = new LinearLayout(this);
        textCol.setOrientation(LinearLayout.VERTICAL);
        TextView titleView = UIHelpers.text(this, title, 14, selected ? UIHelpers.ACCENT : UIHelpers.TEXT, Typeface.BOLD);
        textCol.addView(titleView);
        if (!TextUtils.isEmpty(subtitle)) {
            TextView subView = UIHelpers.text(this, subtitle, 12, UIHelpers.TEXT3, Typeface.NORMAL);
            textCol.addView(subView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        }
        row.addView(textCol, UIHelpers.weight(1));

        if (selected) {
            ImageView check = UIHelpers.vectorIconButton(this, R.drawable.ic_auto, UIHelpers.ACCENT, 0);
            row.addView(check, new LinearLayout.LayoutParams(UIHelpers.dp(this, 20), UIHelpers.dp(this, 20)));
        }
        return row;
    }

    private void restoreReadingHabitState() {
        if (readingHabitTracker == null) return;
        SharedPreferences sp = getSharedPreferences("xxcomic_habit_preferences", MODE_PRIVATE);
        int mode = sp.getInt("launch_bookshelf_mode", ReadingHabitTracker.LAUNCH_MODE_AUTO);
        int lastManual = sp.getInt("last_manual_bookshelf_tab", 0);
        int learned = sp.getInt("learned_preference", ReadingHabitTracker.PREF_NONE);
        String samples = sp.getString("habit_samples", "[]");
        readingHabitTracker.restoreState(mode, lastManual, learned, samples);
    }

    private void persistReadingHabitState() {
        if (readingHabitTracker == null) return;
        getSharedPreferences("xxcomic_habit_preferences", MODE_PRIVATE).edit()
                .putInt("launch_bookshelf_mode", readingHabitTracker.getLaunchMode())
                .putInt("last_manual_bookshelf_tab", readingHabitTracker.getLastManualTab())
                .putInt("learned_preference", readingHabitTracker.getLearnedPreference())
                .putString("habit_samples", readingHabitTracker.serializeSamples())
                .apply();
    }

    private void showReaderSettings() {
        showReaderSettingsDrawer();
    }

    private void showReaderSettingsDrawer() {
        if (!readerVisible) return;
        int currentMode = ReaderSettingsSheet.toReadingMode(readerLayoutMode, readerLeftHand);
        ReaderSettingsSheet.show(this, currentMode, readerFullyImmersive, readerDisplayMode == 1, readerPinchZoom,
                readerDisablePageAnimation, new ReaderSettingsSheet.OnSettingsChangeListener() {
                    @Override
                    public void onReadingModeChanged(int mode) {
                        int newLayoutMode = ReaderSettingsSheet.toLayoutMode(mode);
                        boolean newLeftHand = ReaderSettingsSheet.toLeftHand(mode);
                        if (readerLayoutMode == newLayoutMode && readerLeftHand == newLeftHand) {
                            return;
                        }
                        readerLayoutMode = newLayoutMode;
                        readerLeftHand = newLeftHand;
                        saveLocalState();
                        reloadCurrentReaderContent();
                    }

                    @Override
                    public void onHideStatusBadgeChanged(boolean hide) {
                        readerFullyImmersive = hide;
                        saveLocalState();
                        updateReaderOverlayVisibility(false);
                    }

                    @Override
                    public void onEinkModeChanged(boolean eink) {
                        int newDisplayMode = eink ? 1 : 0;
                        if (readerDisplayMode == newDisplayMode) return;
                        readerDisplayMode = newDisplayMode;
                        saveLocalState();
                        reloadCurrentReaderContent();
                    }

                    @Override
                    public void onPinchZoomChanged(boolean enabled) {
                        readerPinchZoom = enabled;
                        saveLocalState();
                        if (readerPager != null) {
                            readerPager.setPinchZoomEnabled(enabled);
                        }
                        if (readerList != null && !enabled) {
                            readerList.setScaleX(1f);
                            readerList.setScaleY(1f);
                        }
                    }

                    @Override
                    public void onDisablePageAnimationChanged(boolean disabled) {
                        readerDisablePageAnimation = disabled;
                        saveLocalState();
                        if (readerPager != null) {
                            readerPager.setAnimationDisabled(disabled);
                        }
                    }
                });
    }

    private void reloadCurrentReaderContent() {
        if (!readerVisible || TextUtils.isEmpty(activeDetailId)) return;
        ComicModels.ComicDetail detail = details.get(activeDetailId);
        if (detail != null && readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
            ComicModels.Chapter activeChapter = detail.chapters.get(readerChapterIndex);
            ComicModels.ChapterPage page = chapters.get(activeChapter.url);
            if (page != null && !page.imageUrls.isEmpty()) {
                renderReader(detail, page);
            } else {
                showReader(detail, readerChapterIndex);
            }
        }
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
            checkPendingUpdatePrompt();
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
            if (globalSearchVerificationRequiredSourceIds.contains(selectedGlobalSearchSourceId)) {
                globalSearchResultsContainer.addView(
                        verificationRequiredState(selectedGlobalSearchSourceId));
                return;
            }
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
            if (globalSearchVerificationRequiredSourceIds.contains(selectedGlobalSearchSourceId)) {
                content.addView(verificationRequiredState(selectedGlobalSearchSourceId));
                ensureStatusView(content);
                return;
            }
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
        row.setOnClickListener(v -> openComicDetail(item.comicId));
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
            openComicDetail(comic.comicId);
        });
        item.addView(coverFrame(comic.coverUrl, -1, 154), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 154)));
        TextView title = UIHelpers.text(this, comic.title, 13, UIHelpers.TEXT, Typeface.NORMAL);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setMaxLines(2);
        title.setEllipsize(TextUtils.TruncateAt.END);
        item.addView(title, UIHelpers.marginTop(-1, UIHelpers.dp(this, 6)));
        return item;
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

    static boolean shouldOfferSourceVerification(String sourceId, boolean verificationRequired) {
        return verificationRequired && supportsManualVerification(sourceId);
    }

    static boolean categoriesFollowInitialList(String sourceId) {
        if ("mh18".equals(sourceId)) return true;
        return "jmcomic".equals(sourceId);
    }

    private void requestProtectedSourceRetry(String sourceId) {
        if (supportsManualVerification(sourceId)) retryProtectedSourceIds.add(sourceId);
    }

    private void verifyProtectedSource(String sourceId) {
        if (!supportsManualVerification(sourceId) || !verifyingProtectedSourceIds.add(sourceId)) return;
        sourceHealthIo.submit(() -> {
            Exception failure = null;
            try {
                if ("jmcomic".equals(sourceId)) {
                    jmcomicClient.verifyAccess();
                } else if ("mh18".equals(sourceId)) {
                    mh18Client.verifyAccess();
                }
            } catch (Exception error) {
                failure = error;
            }
            Exception verificationFailure = failure;
            postMainIfAlive(() -> {
                verifyingProtectedSourceIds.remove(sourceId);
                boolean retry = retryProtectedSourceIds.remove(sourceId);
                if (verificationFailure == null) {
                    DownloadRuntime runtime = DownloadRuntime.get(this);
                    runtime.queue.verificationReady(sourceId);
                    if (runtime.hasPending()) DownloadViews.startService(this);
                }
                if (retry) {
                    verifyProtectedSource(sourceId);
                } else if (verificationFailure != null
                        && !(verificationFailure instanceof VerificationCancelledException)) {
                    showRemErrorToast(sourceNameForId(sourceId) + " 验证未完成");
                }
            });
        });
    }

    private void showDetailFromReader(String comicId, int chapterIndex) {
        openComicDetail(comicId);
    }

    private void openComicDetail(String comicId) {
        onUserOpenComicDetail(comicId);
        showDetail(comicId);
    }

    private void onUserOpenComicDetail(String comicId) {
        if (!TextUtils.isEmpty(comicId)) {
            FavoriteUpdateCoordinator.getInstance().onUserEnterDetail(comicId);
            updateFavoriteBadge(comicId, false);
        }
    }

    private void updateFavoriteBadge(String comicId, boolean visible) {
        View badge = favoriteBadgeViews.get(comicId);
        if (badge != null) {
            badge.setVisibility(visible ? View.VISIBLE : View.GONE);
        }
    }

    private void showLocalDetail(String comicId) {
        if (!localLibraryReady) {
            showRemSuccessToast("正在整理本地文件，稍等一下哦");
            return;
        }
        if (detailBackAction == null) {
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
        enterScreen(true);
        applyThemeAndSystemBars();
        activeDetailId = comicId;
        readerVisible = false;

        LocalModels.Book book = localBookForReading(comicId);
        if (book == null || !LocalModels.STATUS_READY.equals(book.status)) {
            showRemDialog(R.drawable.rem_empty, "漫画已移除", "该漫画已从本地书架删除，重新导入该文件后可恢复阅读进度", "返回", () -> {
                if (detailBackAction != null) {
                    Runnable back = detailBackAction;
                    detailBackAction = null;
                    back.run();
                } else {
                    showTab(0);
                }
            });
            return;
        }

        List<LocalModels.Chapter> localChapters = getLocalLibraryStore().getChapters(book.id);
        List<ComicModels.Chapter> comicChapters = new ArrayList<>();
        for (LocalModels.Chapter lc : localChapters) {
            comicChapters.add(new ComicModels.Chapter(lc.id, lc.title, LocalContentResolver.buildChapterUrl(lc.id), 0, lc.orderIndex));
        }
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                "local",
                LocalModels.SOURCE_TYPE_FILE_DOWNLOAD.equals(book.sourceType)?book.progressKey:book.id,
                book.getDisplayTitle(),
                LocalContentResolver.buildCoverUrl(book.id),
                "本地导入",
                Collections.emptyList()
        );
        ComicModels.ComicDetail importedDetail = new ComicModels.ComicDetail(
                summary,
                "本地",
                "已完成",
                "本地漫画 · " + book.format.toUpperCase(Locale.US) + " 格式\n文件存储于 App 专属目录，原文件未受修改。",
                "",
                comicChapters
        );
        final ComicModels.ComicDetail detail = LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType)
                ? downloadedDetail(book) : importedDetail;
        if (detail == null) { showRemErrorToast("下载目录缺失，请到下载中心重试"); return; }
        details.put(book.id, detail);
        summaries.put(book.id, summary);
        if(LocalModels.SOURCE_TYPE_FILE_DOWNLOAD.equals(book.sourceType)) {
            details.put(book.progressKey,detail);summaries.put(book.progressKey,summary);
        }
        if (LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType)) {
            details.put(book.progressKey, detail);
            summaries.put(book.progressKey, detail.summary);
        }

        int savedChapter = localReadIndex(book, detail);
        boolean hasRead = lastViewedAt.containsKey(book.progressKey);
        root.removeAllViews();
        View localDetailView = LocalDetailView.build(
                this,
                book,
                detail,
                getLocalLibraryStore(),
                getLocalStorageManager(),
                savedChapter,
                hasRead,
                new LocalDetailView.Listener() {
                    @Override public void onAddVolumes(LocalModels.Book target) {
                        pickAdditionalVolumes(target);
                    }
                    @Override
                    public void onBack() {
                        if (detailBackAction != null) {
                            Runnable back = detailBackAction;
                            detailBackAction = null;
                            back.run();
                        } else {
                            showTab(0);
                        }
                    }

                    @Override
                    public void onRead(LocalModels.Book b, ComicModels.ComicDetail d, int chapterIndex) {
                        readerLocalBookId = b.id;
                        showReader(d, chapterIndex);
                    }

                    @Override
                    public void onBookRenamed(LocalModels.Book updatedBook) {
                        int previousIndex = progress.containsKey(book.progressKey) ? progress.get(book.progressKey) : 0;
                        if (hasRead && previousIndex >= 0 && previousIndex < detail.chapters.size()) {
                            String previousChapter = detail.chapters.get(previousIndex).chapterId;
                            List<LocalModels.Chapter> latestChapters = getLocalLibraryStore().getChapters(updatedBook.id);
                            int restoredIndex = -1;
                            for (int i = 0; i < latestChapters.size(); i++)
                                if (previousChapter.equals(latestChapters.get(i).id)) { restoredIndex = i; break; }
                            progress.put(updatedBook.progressKey, Math.max(0, restoredIndex));
                            android.content.SharedPreferences locators = getSharedPreferences("xxcomic_text_locators", MODE_PRIVATE);
                            String locatorKey = "text_pos_" + book.progressKey;
                            com.xxcomic.ebook.TextLocator locator = com.xxcomic.ebook.TextLocator.fromJson(locators.getString(locatorKey, null));
                            if (locator != null) {
                                if (restoredIndex < 0) locators.edit().remove(locatorKey).apply();
                                else locators.edit().putString(locatorKey, new com.xxcomic.ebook.TextLocator(locator.bookId,
                                        restoredIndex, locator.spineIndex, locator.resourceHref, locator.anchorId,
                                        locator.scrollPercentage, locator.charOffset).toJson()).apply();
                            }
                            saveLocalState();
                        }
                        ComicModels.ComicSummary updatedSummary = new ComicModels.ComicSummary(
                                "local",
                                updatedBook.id,
                                updatedBook.getDisplayTitle(),
                                LocalContentResolver.buildCoverUrl(updatedBook.id),
                                "本地导入",
                                Collections.emptyList()
                        );
                        ComicModels.ComicDetail updatedDetail = new ComicModels.ComicDetail(
                                updatedSummary,
                                "本地",
                                "已完成",
                                detail.description,
                                "",
                                detail.chapters
                        );
                        details.put(updatedBook.id, updatedDetail);
                        summaries.put(updatedBook.id, updatedSummary);
                        refreshLocalBookshelf();
                        showLocalDetail(updatedBook.id);
                    }

                    @Override
                    public void onBookDeleted(LocalModels.Book deletedBook) {
                        details.remove(deletedBook.id);
                        summaries.remove(deletedBook.id);
                        refreshLocalBookshelf();
                        if (detailBackAction != null) {
                            Runnable back = detailBackAction;
                            detailBackAction = null;
                            back.run();
                        } else {
                            showTab(0);
                        }
                    }

                    @Override
                    public void showToast(String message) {
                        showRemSuccessToast(message);
                    }
                }
        );
        root.addView(localDetailView, UIHelpers.match());
    }

    private ComicModels.ComicDetail downloadedDetail(LocalModels.Book book) {
        // The local view uses Book's title/cover; online cache metadata must retain the site's identity.
        return DownloadRuntime.get(this).store.snapshot(book.id);
    }

    private int localReadIndex(LocalModels.Book book, ComicModels.ComicDetail detail) {
        if (progress.containsKey(book.progressKey) || !LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType)) return savedChapter(book.progressKey);
        Set<String> available = new HashSet<>();
        for (LocalModels.Chapter chapter : getLocalLibraryStore().getChapters(book.id)) available.add(chapter.entryPath);
        for (int i=0; i<detail.chapters.size(); i++) if (available.contains(detail.chapters.get(i).chapterId)) return i;
        return 0;
    }

    private void showDownloadCenter() {
        enterScreen(); readerVisible = false; activeDetailId = ""; settingsScene = "";
        sourceManagementVisible = false; historyVisible = false; standaloneSearchVisible = false; detailBackAction = null;
        applyThemeAndSystemBars(); root.removeAllViews();
        offlinePageBack = () -> showTab(2);
        root.addView(DownloadViews.center(this, offlinePageBack, this::showLocalDetail, this::showSourceManagement), UIHelpers.match());
    }

    private void showLocalStorage() {
        enterScreen(); readerVisible = false; activeDetailId = ""; settingsScene = "";
        sourceManagementVisible = false; historyVisible = false; standaloneSearchVisible = false; detailBackAction = null;
        applyThemeAndSystemBars(); root.removeAllViews();
        offlinePageBack = () -> showTab(2);
        root.addView(DownloadViews.storage(this, offlinePageBack, this::showLocalStorage), UIHelpers.match());
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent); setIntent(intent);
        if (intent.getBooleanExtra("open.downloads", false) && localLibraryReady) {
            intent.removeExtra("open.downloads"); showDownloadCenter();
        }
    }

    private void showDetail(String comicId) {
        if (readerVisible && !TextUtils.isEmpty(readerLocalBookId)) {
            LocalModels.Book local = getLocalLibraryStore().getBook(readerLocalBookId);
            if (local != null && local.progressKey.equals(comicId)) { showLocalDetail(local.id); return; }
        }
        readerLocalBookId = "";
        if (isLocalComic(comicId)) {
            showLocalDetail(comicId);
            return;
        }
        if (detailBackAction == null) {
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
        enterScreen(true);
        applyThemeAndSystemBars();
        activeDetailId = comicId;
        readerVisible = false;
        ComicModels.ComicDetail detail = details.get(comicId);
        if (detail == null) {
            int loadingGeneration = showPageLoading("正在加载详情...", "正在获取漫画信息。", detailBackAction);
            ComicSource requestClient = sourceForComicId(comicId);
            String requestSourceId = requestClient.id();
            track(detailIo.submit(() -> {
                try {
                    ComicModels.ComicDetail loaded = requestClient.detail(comicId);
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
                        if (shouldOfferSourceVerification(
                                requestSourceId, isVerificationRequired(error))) {
                            showVerificationRequired(requestSourceId);
                        } else {
                            showError("详情加载失败", error, () -> showDetail(comicId));
                        }
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

        boolean fileSource = sourceForId(detail.summary.sourceId) instanceof com.xxcomic.source.FileSourceCapability;

        ImageView dlBtn = UIHelpers.vectorIconButton(this, R.drawable.ic_download, UIHelpers.ACCENT, 4);
        dlBtn.setContentDescription(fileSource ? "文件与分卷" : "下载离线章节");
        dlBtn.setPadding(UIHelpers.dp(this, 6), UIHelpers.dp(this, 6), UIHelpers.dp(this, 6), UIHelpers.dp(this, 6));
        dlBtn.setOnClickListener(v -> {
            if (fileSource) showFileVolumes(detail);
            else ensureChaptersThen(detail, loaded -> DownloadViews.selection(this, loaded, savedChapter(loaded.summary.comicId), () -> {}));
        });
        titleRow.addView(dlBtn, new LinearLayout.LayoutParams(UIHelpers.dp(this, 36), UIHelpers.dp(this, 36)));

        TextView source = UIHelpers.text(this, sourceNameForId(detail.summary.sourceId) + " ⇄", 12, UIHelpers.ACCENT, Typeface.NORMAL);
        source.setSingleLine(true);
        source.setMaxWidth(UIHelpers.dp(this, 160));
        source.setEllipsize(TextUtils.TruncateAt.END);
        source.setGravity(Gravity.CENTER);
        source.setMinHeight(UIHelpers.dp(this, 44));
        source.setPadding(UIHelpers.dp(this, 8), 0, 0, 0);
        source.setContentDescription("切换站源，当前" + sourceNameForId(detail.summary.sourceId));
        source.setOnClickListener(v -> showDetailSourceSheet());
        detailSourceEntry = source;
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
        detailSourceOptions = Collections.singletonList(detail.summary);
        detailSourcesLoading = true;
        renderDetailSourceOptions();
        detailSourceSearch.start(detail.summary, enabledSearchSources(), (items, loading) -> {
            if (activityDestroyed || detailSourceEntry != source || readerVisible
                    || !TextUtils.equals(activeDetailId, comicId)) return;
            detailSourceOptions = items;
            detailSourcesLoading = loading;
            renderDetailSourceOptions();
        });
        if (!detail.summary.tags.isEmpty()) {
            body.addView(detailTagRow(detail.summary.tags), UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));
        }
        TextView summary = UIHelpers.text(this, clean(detail.description, "暂无简介"), 13, UIHelpers.TEXT2, Typeface.NORMAL);
        summary.setLineSpacing(0f, 1.2f);
        body.addView(summary, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));

        if (!fileSource) body.addView(chapterEntry(detail), UIHelpers.marginTop(-1, UIHelpers.dp(this, 10)));

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

    private void renderDetailSourceOptions() {
        if (detailSourceEntry != null) {
            ComicModels.ComicDetail current = details.get(activeDetailId);
            if (current != null) {
                detailSourceEntry.setText(TextUtils.isEmpty(pendingDetailSourceId)
                        ? sourceNameForId(current.summary.sourceId) + " ⇄"
                        : "切换中…");
            }
        }
        if (detailSourceSheet != null && detailSourceSheet.isShowing()) {
            detailSourceSheet.update(detailSourceOptions, activeDetailId, pendingDetailSourceId, detailSourcesLoading);
        }
    }

    private void showDetailSourceSheet() {
        if (detailSourceEntry == null || (detailSourceSheet != null && detailSourceSheet.isShowing())) return;
        if (activePopup != null) activePopup.dismiss();
        SourceSwitchSheet sheet = new SourceSwitchSheet(this, root,
                comic -> coverFrame(comic.coverUrl, 48, 66), this::sourceNameForId, this::switchDetailSource);
        detailSourceSheet = sheet;
        activePopup = sheet;
        sheet.setOnDismissListener(() -> {
            if (detailSourceSheet == sheet) detailSourceSheet = null;
            if (activePopup == sheet) activePopup = null;
            checkPendingUpdatePrompt();
        });
        sheet.update(detailSourceOptions, activeDetailId, pendingDetailSourceId, detailSourcesLoading);
        sheet.show(root);
    }

    private void showReaderSourceSheet(ComicModels.ComicDetail detail) {
        if (detail == null || detail.summary == null) return;
        if (detailSourceSheet != null && detailSourceSheet.isShowing()) return;
        if (activePopup != null) activePopup.dismiss();
        if (activeChapterSheet != null) activeChapterSheet.dismiss();

        boolean hasValidOptions = false;
        for (ComicModels.ComicSummary item : detailSourceOptions) {
            if (item != null && TextUtils.equals(item.comicId, detail.summary.comicId)) {
                hasValidOptions = true;
                break;
            }
        }
        if (!hasValidOptions) {
            detailSourceOptions = Collections.singletonList(detail.summary);
            detailSourcesLoading = true;
        }

        SourceSwitchSheet sheet = new SourceSwitchSheet(this, root, true,
                comic -> coverFrame(comic.coverUrl, 48, 66), this::sourceNameForId, this::switchReaderSource);
        detailSourceSheet = sheet;
        activePopup = sheet;
        sheet.setOnDismissListener(() -> {
            if (detailSourceSheet == sheet) detailSourceSheet = null;
            if (activePopup == sheet) activePopup = null;
            checkPendingUpdatePrompt();
        });
        sheet.update(detailSourceOptions, activeDetailId, pendingDetailSourceId, detailSourcesLoading);
        sheet.show(root);

        final String comicId = detail.summary.comicId;
        detailSourceSearch.start(detail.summary, enabledSearchSources(), (items, loading) -> {
            if (activityDestroyed || !TextUtils.equals(activeDetailId, comicId)) return;
            detailSourceOptions = items;
            detailSourcesLoading = loading;
            if (detailSourceSheet != null && detailSourceSheet.isShowing()) {
                detailSourceSheet.update(items, activeDetailId, pendingDetailSourceId, loading);
            }
            renderDetailSourceOptions();
        });
    }

    private void switchReaderSource(ComicModels.ComicSummary target) {
        if (target == null || TextUtils.equals(activeDetailId, target.comicId)
                || TextUtils.equals(pendingDetailSourceId, target.sourceId)) return;
        final String originalId = activeDetailId;
        final int token = ++detailSwitchGeneration;
        if (detailSwitchTask != null) detailSwitchTask.cancel(true);
        if (detailSwitchTimeout != null) main.removeCallbacks(detailSwitchTimeout);
        pendingDetailSourceId = target.sourceId;
        renderDetailSourceOptions();

        ComicModels.ComicDetail originalDetail = details.get(originalId);
        final String currentTitle = (originalDetail != null && readerChapterIndex >= 0
                && readerChapterIndex < originalDetail.chapters.size())
                ? originalDetail.chapters.get(readerChapterIndex).title : "";
        final int currentIndex = readerChapterIndex;

        ComicModels.ComicDetail cached = details.get(target.comicId);
        if (cached != null) {
            summaries.put(target.comicId, cached.summary);
            activeDetailId = target.comicId;
            pendingDetailSourceId = "";
            renderDetailSourceOptions();
            if (readerVisible) {
                ensureChaptersThen(cached, loaded -> {
                    int matched = findMatchingChapterIndex(loaded.chapters, currentTitle, currentIndex);
                    showReader(loaded, matched);
                    showRemSuccessToast("已换源至 " + sourceNameForId(target.sourceId));
                });
            } else {
                openComicDetail(target.comicId);
            }
            return;
        }

        showRemSuccessToast("正在切换至 " + sourceNameForId(target.sourceId) + "…");
        ComicSource client = sourceForId(target.sourceId);
        detailSwitchTimeout = () -> {
            if (token != detailSwitchGeneration) return;
            detailSwitchGeneration++;
            if (detailSwitchTask != null) detailSwitchTask.cancel(true);
            pendingDetailSourceId = "";
            renderDetailSourceOptions();
            showRemErrorToast("这个站源有点慢，请重试");
        };
        main.postDelayed(detailSwitchTimeout, 20000);
        detailSwitchTask = track(detailIo.submit(() -> {
            try {
                ComicModels.ComicDetail loaded = client.detail(target.comicId);
                if (loaded == null || loaded.summary == null
                        || !target.sourceId.equals(loaded.summary.sourceId)
                        || !target.comicId.equals(loaded.summary.comicId)) throw new IOException("详情不匹配");
                main.post(() -> {
                    if (activityDestroyed || token != detailSwitchGeneration
                            || !TextUtils.equals(originalId, activeDetailId)) return;
                    main.removeCallbacks(detailSwitchTimeout);
                    details.put(target.comicId, loaded);
                    summaries.put(target.comicId, loaded.summary);
                    refreshedComicIds.add(target.comicId);
                    persistComicCachesAsync();
                    activeDetailId = target.comicId;
                    pendingDetailSourceId = "";
                    renderDetailSourceOptions();
                    if (readerVisible) {
                        ensureChaptersThen(loaded, fullDetail -> {
                            int matched = findMatchingChapterIndex(fullDetail.chapters, currentTitle, currentIndex);
                            showReader(fullDetail, matched);
                            showRemSuccessToast("已换源至 " + sourceNameForId(target.sourceId));
                        });
                    } else {
                        openComicDetail(target.comicId);
                    }
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (activityDestroyed || token != detailSwitchGeneration
                            || !TextUtils.equals(originalId, activeDetailId)) return;
                    main.removeCallbacks(detailSwitchTimeout);
                    pendingDetailSourceId = "";
                    renderDetailSourceOptions();
                    showRemErrorToast(isVerificationRequired(error)
                            ? "请先到站源管理验证" : "切换失败，请重试");
                });
            }
        }));
    }

    private int findMatchingChapterIndex(List<ComicModels.Chapter> chapters, String currentTitle, int defaultIndex) {
        if (chapters == null || chapters.isEmpty()) return 0;
        if (!TextUtils.isEmpty(currentTitle)) {
            String trimmedCurrent = currentTitle.trim();
            for (int i = 0; i < chapters.size(); i++) {
                if (trimmedCurrent.equalsIgnoreCase(chapters.get(i).title.trim())) {
                    return i;
                }
            }
            String normCurrent = normalizeChapterName(trimmedCurrent);
            if (!normCurrent.isEmpty()) {
                for (int i = 0; i < chapters.size(); i++) {
                    if (normCurrent.equalsIgnoreCase(normalizeChapterName(chapters.get(i).title))) {
                        return i;
                    }
                }
                for (int i = 0; i < chapters.size(); i++) {
                    String normTarget = normalizeChapterName(chapters.get(i).title);
                    if (!normTarget.isEmpty() && (normCurrent.contains(normTarget) || normTarget.contains(normCurrent))) {
                        return i;
                    }
                }
            }
        }
        return Math.max(0, Math.min(defaultIndex, chapters.size() - 1));
    }

    private static String normalizeChapterName(String title) {
        if (title == null) return "";
        return title.replaceAll("[\\s第话章节回卷【】\\[\\]()]", "").toLowerCase();
    }

    private boolean isLocalComicDetail(ComicModels.ComicDetail detail) {
        if (detail == null || detail.summary == null) return false;
        String comicId = detail.summary.comicId;
        String sourceId = detail.summary.sourceId;
        if (isLocalComic(comicId) || "local".equals(sourceId) || !TextUtils.isEmpty(readerLocalBookId)) {
            return true;
        }
        if (localLibraryReady && localBookForReading(comicId) != null) {
            return true;
        }
        return sourceForId(sourceId) instanceof com.xxcomic.source.FileSourceCapability;
    }

    private void switchDetailSource(ComicModels.ComicSummary target) {
        if (TextUtils.equals(activeDetailId, target.comicId)
                || TextUtils.equals(pendingDetailSourceId, target.sourceId)) return;
        final String originalId = activeDetailId;
        final int token = ++detailSwitchGeneration;
        if (detailSwitchTask != null) detailSwitchTask.cancel(true);
        if (detailSwitchTimeout != null) main.removeCallbacks(detailSwitchTimeout);
        pendingDetailSourceId = target.sourceId;
        renderDetailSourceOptions();
        ComicModels.ComicDetail cached = details.get(target.comicId);
        if (cached != null) {
            summaries.put(target.comicId, cached.summary);
            openComicDetail(target.comicId);
            return;
        }
        ComicSource client = sourceForId(target.sourceId);
        detailSwitchTimeout = () -> {
            if (token != detailSwitchGeneration) return;
            detailSwitchGeneration++;
            if (detailSwitchTask != null) detailSwitchTask.cancel(true);
            pendingDetailSourceId = "";
            renderDetailSourceOptions();
            showRemErrorToast("这个站源有点慢，请重试");
        };
        main.postDelayed(detailSwitchTimeout, 20000);
        detailSwitchTask = track(detailIo.submit(() -> {
            try {
                ComicModels.ComicDetail loaded = client.detail(target.comicId);
                if (loaded == null || loaded.summary == null
                        || !target.sourceId.equals(loaded.summary.sourceId)
                        || !target.comicId.equals(loaded.summary.comicId)) throw new IOException("详情不匹配");
                main.post(() -> {
                    if (activityDestroyed || token != detailSwitchGeneration
                            || !TextUtils.equals(originalId, activeDetailId)) return;
                    details.put(target.comicId, loaded);
                    summaries.put(target.comicId, loaded.summary);
                    refreshedComicIds.add(target.comicId);
                    persistComicCachesAsync();
                    openComicDetail(target.comicId);
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (activityDestroyed || token != detailSwitchGeneration
                            || !TextUtils.equals(originalId, activeDetailId)) return;
                    main.removeCallbacks(detailSwitchTimeout);
                    pendingDetailSourceId = "";
                    renderDetailSourceOptions();
                    showRemErrorToast(isVerificationRequired(error)
                            ? "请先到站源管理验证" : "切换失败，请重试");
                });
            }
        }));
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
                && TextUtils.isEmpty(pendingDetailSourceId)
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

    private static class ContinuousReaderItem {
        final String imageUrl;
        final String chapterUrl;
        final int chapterIndex;
        final int pageIndex;
        final int pageCount;
        final String positionKey;

        ContinuousReaderItem(String imageUrl, String chapterUrl, int chapterIndex,
                             int pageIndex, int pageCount, String positionKey) {
            this.imageUrl = imageUrl;
            this.chapterUrl = chapterUrl;
            this.chapterIndex = chapterIndex;
            this.pageIndex = pageIndex;
            this.pageCount = pageCount;
            this.positionKey = positionKey;
        }
    }

    private interface ChapterPageCallback {
        void onLoaded(ComicModels.ChapterPage page);
    }

    private void updateReaderToolbarTitle(ComicModels.ComicDetail detail) {
        if (readerToolbarTitle == null || detail == null || readerChapterIndex < 0 || readerChapterIndex >= detail.chapters.size()) return;
        String titleText = detail.chapters.get(readerChapterIndex).title;
        if (!TextUtils.isEmpty(detail.summary.title)) {
            titleText = detail.summary.title + " · " + titleText;
        }
        readerToolbarTitle.setText(titleText);
    }

    private void loadChapterPageAsync(ComicModels.ComicDetail detail, int chapterIndex,
                                      ChapterPageCallback onLoaded, Runnable onError) {
        if (detail == null || detail.chapters == null || chapterIndex < 0 || chapterIndex >= detail.chapters.size()) {
            if (onError != null) onError.run();
            return;
        }
        ComicModels.Chapter targetChapter = detail.chapters.get(chapterIndex);
        String chapterUrl = targetChapter.url;
        String comicId = detail.summary.comicId;
        int generation = readerGeneration;

        if (!isLocalComic(comicId)) {
            DownloadRuntime runtime = DownloadRuntime.get(this);
            DownloadModels.Task task = runtime.store.get(DownloadModels.key(detail.summary.sourceId, comicId, targetChapter.chapterId));
            if (task != null && task.state == DownloadModels.State.COMPLETED) {
                track(detailIo.submit(() -> {
                    try {
                        ComicModels.ChapterPage page = runtime.localChapter(detail, chapterIndex);
                        if (page != null) {
                            main.post(() -> {
                                if (generation == readerGeneration && readerVisible) {
                                    onLoaded.onLoaded(page);
                                }
                            });
                            return;
                        }
                    } catch (Exception ignored) {}
                    main.post(() -> { if (onError != null) onError.run(); });
                }));
                return;
            }
        }

        ComicModels.ChapterPage cached = chapters.get(chapterUrl);
        if (!isEmptyChapterPage(cached)) {
            onLoaded.onLoaded(cached);
            return;
        }

        if (LocalContentResolver.isLocalChapterUrl(chapterUrl) || isLocalComic(comicId)) {
            track(detailIo.submit(() -> {
                try {
                    String chapterId = LocalContentResolver.isLocalChapterUrl(chapterUrl) ?
                            LocalContentResolver.extractId(chapterUrl, LocalContentResolver.PREFIX_CHAPTER) : chapterUrl;
                    List<LocalModels.Page> localPages = getLocalLibraryStore().getPages(chapterId);
                    List<String> imageUrls = new ArrayList<>();
                    for (LocalModels.Page lp : localPages) {
                        imageUrls.add(LocalContentResolver.buildPageUrl(lp.id));
                    }
                    ComicModels.ChapterPage page = new ComicModels.ChapterPage(chapterId, targetChapter.title, imageUrls, null);
                    main.post(() -> {
                        if (generation != readerGeneration || !readerVisible) return;
                        chapters.put(chapterUrl, page);
                        onLoaded.onLoaded(page);
                    });
                } catch (Exception e) {
                    main.post(() -> { if (onError != null) onError.run(); });
                }
            }));
            return;
        }

        track(detailIo.submit(() -> {
            try {
                ComicSource client = sourceForDetail(detail);
                ComicModels.ChapterPage page = client.chapter(chapterUrl);
                main.post(() -> {
                    if (generation != readerGeneration || !readerVisible) return;
                    if (!isEmptyChapterPage(page)) {
                        chapters.put(chapterUrl, page);
                        persistComicCachesAsync();
                        onLoaded.onLoaded(page);
                    } else {
                        if (onError != null) onError.run();
                    }
                });
            } catch (Exception e) {
                main.post(() -> {
                    if (generation != readerGeneration || !readerVisible) return;
                    if (onError != null) onError.run();
                });
            }
        }));
    }

    private void showReader(ComicModels.ComicDetail detail, int chapterIndex) {
        enterScreen();
        if (detail.chapters.isEmpty()) {
            ensureChaptersThen(detail, loaded -> showReader(loaded, chapterIndex));
            return;
        }
        boolean wasVisible = readerVisible;
        boolean keepFullscreen = wasVisible ? readerFullscreen : true;
        readerVisible = true;
        readerFullscreen = keepFullscreen;
        activeDetailId = detail.summary.comicId;
        if (readingHabitTracker != null) {
            readingHabitTracker.onEnterReader(detail.summary.comicId, isLocalComicDetail(detail));
        }
        readerChapterIndex = Math.max(0, Math.min(chapterIndex, detail.chapters.size() - 1));
        ComicModels.Chapter chapter = detail.chapters.get(readerChapterIndex);
        int generation = readerGeneration;
        String comicId = detail.summary.comicId;
        String chapterUrl = chapter.url;
        if (!TextUtils.equals(readerEntryChapterUrl, chapterUrl)) {
            readerEntryChapterUrl = "";
            readerEntryTarget = 0;
        }
        if (!isLocalComic(comicId)) {
            DownloadRuntime runtime = DownloadRuntime.get(this);
            DownloadModels.Task task = runtime.store.get(DownloadModels.key(detail.summary.sourceId, comicId, chapter.chapterId));
            if (task != null && task.state == DownloadModels.State.COMPLETED) {
                showReaderLoading(detail);
                final int localIndex = readerChapterIndex;
                track(detailIo.submit(() -> {
                    try {
                        ComicModels.ChapterPage page = runtime.localChapter(detail, localIndex);
                        if (page == null) throw new IOException("本章下载已移除");
                        main.post(() -> commitReaderPage(generation, comicId, chapterUrl, detail, page));
                    } catch (Exception error) {
                        main.post(() -> {
                            if (!isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
                            showReaderError(detail, "本章下载文件需要修复", "到下载中心重新下载本章", this::showDownloadCenter);
                        });
                    }
                }));
                return;
            }
            if (!runtime.connected() && !TextUtils.isEmpty(readerLocalBookId)) {
                showReaderError(detail, "这一章还没有下载哦", "已下载的章节可以在下载中心找到", this::showDownloadCenter);
                return;
            }
        }
        ComicModels.ChapterPage cached = chapters.get(chapter.url);
        if (isEmptyChapterPage(cached)) {
            chapters.remove(chapter.url);
            cached = null;
        }
        if (cached == null) {
            if (LocalContentResolver.isLocalChapterUrl(chapterUrl) || isLocalComic(comicId)) {
                showReaderLoading(detail);
                track(detailIo.submit(() -> {
                    try {
                        String chapterId = LocalContentResolver.isLocalChapterUrl(chapterUrl) ?
                                LocalContentResolver.extractId(chapterUrl, LocalContentResolver.PREFIX_CHAPTER) : chapterUrl;
                        List<LocalModels.Page> localPages = getLocalLibraryStore().getPages(chapterId);
                        List<String> imageUrls = new ArrayList<>();
                        for (LocalModels.Page lp : localPages) {
                            imageUrls.add(LocalContentResolver.buildPageUrl(lp.id));
                        }
                        ComicModels.ChapterPage page = new ComicModels.ChapterPage(chapterId, chapter.title, imageUrls, null);
                        main.post(() -> {
                            if (!isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
                            chapters.put(chapterUrl, page);
                            commitReaderPage(generation, comicId, chapterUrl, detail, page);
                        });
                    } catch (Exception error) {
                        main.post(() -> {
                            if (!isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
                            appendErrorLog("本地章节加载失败", error);
                            showReaderError(detail, "加载失败了", "无法读取本地章节图片",
                                    () -> showReader(detail, chapterIndex));
                        });
                    }
                }));
                return;
            }
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
                    boolean verificationRequired = isVerificationRequired(error);
                    main.post(() -> {
                        if (expectedCancellation || !isCurrentReaderRequest(generation, comicId, chapterUrl, detail)) return;
                        if (shouldOfferSourceVerification(
                                detail.summary.sourceId, verificationRequired)) {
                            showReaderVerificationRequired(detail);
                        } else {
                            appendErrorLog("章节加载失败", error);
                            showReaderError(detail, "加载失败了", "阅读位置已经保留",
                                    () -> showReader(detail, chapterIndex));
                        }
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
        if (isLocalComic(comicId) && readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
            getSharedPreferences("xxcomic_local_locators", MODE_PRIVATE).edit()
                    .putString(comicId, detail.chapters.get(readerChapterIndex).chapterId).apply();
        }
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
        shell.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());
        int topHeight = UIHelpers.dp(this, 42);
        shell.addView(readerToolbar(detail), new LinearLayout.LayoutParams(-1, topHeight));
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
        shell.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());
        int topHeight = UIHelpers.dp(this, 42);
        shell.addView(readerToolbar(detail), new LinearLayout.LayoutParams(-1, topHeight));
        shell.addView(readerState(R.drawable.rem_error, title, desc, "重试", retry, false), new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(readerProgressBar(readerChapterIndex + 1, Math.max(1, detail.chapters.size())), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 2)));
    }

    private int queryBatteryLevel() {
        try {
            Intent batteryIntent = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (batteryIntent != null) {
                int level = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                if (level >= 0 && scale > 0) {
                    return Math.round(level * 100f / scale);
                }
            }
        } catch (Exception ignored) { }
        return -1;
    }

    private void registerReaderBatteryReceiver() {
        if (readerBatteryReceiver != null) return;
        currentBatteryLevel = queryBatteryLevel();
        readerBatteryReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                if (level >= 0 && scale > 0) {
                    currentBatteryLevel = Math.round(level * 100f / scale);
                    refreshReaderOverlayBadge();
                }
            }
        };
        try {
            registerReceiver(readerBatteryReceiver, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        } catch (Exception ignored) { }
    }

    private void unregisterReaderBatteryReceiver() {
        if (readerBatteryReceiver != null) {
            try {
                unregisterReceiver(readerBatteryReceiver);
            } catch (Exception ignored) { }
            readerBatteryReceiver = null;
        }
    }

    private void refreshReaderOverlayBadge() {
        if (readerOverlayBadge == null || !readerVisible) return;
        ComicModels.ComicDetail detail = details.get(activeDetailId);
        String chapterTitle = "";
        if (detail != null && readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
            chapterTitle = detail.chapters.get(readerChapterIndex).title;
        }
        if (chapterTitle.length() > 14) {
            chapterTitle = chapterTitle.substring(0, 13) + "…";
        }
        String time = new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date());
        String battery = currentBatteryLevel >= 0 ? currentBatteryLevel + "%" : "";
        StringBuilder sb = new StringBuilder();
        if (!TextUtils.isEmpty(chapterTitle)) sb.append(chapterTitle).append("  ");
        if (isLocalTextBook(activeDetailId)) {
            sb.append(readerCurrentPageNumber).append("%  ");
        } else {
            sb.append(readerCurrentPageNumber).append("/").append(readerTotalPages).append("  ");
        }
        sb.append(time);
        if (!TextUtils.isEmpty(battery)) sb.append("  ").append(battery);
        String newText = sb.toString();
        if (!TextUtils.equals(newText, readerOverlayBadge.getText())) {
            readerOverlayBadge.setText(newText);
        }
    }

    private LinearLayout readerToolbar(ComicModels.ComicDetail detail) {
        int statusInset = getStatusBarOrCutoutHeight();
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setPadding(UIHelpers.dp(this, 12), statusInset, UIHelpers.dp(this, 12), 0);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setClickable(true);
        if (readerDisplayMode == 1) {
            top.setBackgroundColor(Color.BLACK);
        } else {
            GradientDrawable bg = new GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    new int[]{0xF00C1420, 0xD80C1420}
            );
            top.setBackground(bg);
        }

        ImageView back = UIHelpers.vectorIconButton(this, R.drawable.ic_back, UIHelpers.READER_TEXT, 4);
        back.setContentDescription("返回");
        back.setClickable(true);
        back.setFocusable(true);
        back.setOnClickListener(v -> {
            if (!TextUtils.isEmpty(activeDetailId)) {
                showDetail(activeDetailId);
            } else {
                onBackPressed();
            }
        });
        top.addView(back, new LinearLayout.LayoutParams(UIHelpers.dp(this, 28), UIHelpers.dp(this, 28)));

        Space space = new Space(this);
        top.addView(space, new LinearLayout.LayoutParams(UIHelpers.dp(this, 8), 1));

        String titleText = detail.chapters.get(readerChapterIndex).title;
        if (!TextUtils.isEmpty(detail.summary.title)) {
            titleText = detail.summary.title + " · " + titleText;
        }
        TextView name = UIHelpers.text(this, titleText, 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        name.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        name.setGravity(Gravity.CENTER_VERTICAL);
        name.setIncludeFontPadding(false);
        name.setSingleLine(true);
        name.setEllipsize(TextUtils.TruncateAt.END);
        readerToolbarTitle = name;
        top.addView(name, UIHelpers.weight(1));
        return top;
    }

    private void renderReader(ComicModels.ComicDetail detail, ComicModels.ChapterPage page) {
        releaseReaderViews();
        readerGeneration++;
        cancelCurrentImageTasks();
        readerPrefetching.clear();
        root.removeAllViews();
        readerVisible = true;
        if (main != null && readerTickRunnable != null) {
            main.removeCallbacks(readerTickRunnable);
            main.postDelayed(readerTickRunnable, 1000L);
        }
        readerTopBar = null;
        readerBottomBar = null;
        readerProgressView = null;
        applyReaderSystemBars(true);
        FrameLayout shell = new FrameLayout(this);
        shell.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());

        int topBarHeight = getStatusBarOrCutoutHeight() + UIHelpers.dp(this, 44);
        int bottomBarHeight = UIHelpers.dp(this, 88);

        LinearLayout top = readerToolbar(detail);

        ComicModels.Chapter activeChapter = detail.chapters.get(readerChapterIndex);
        int generation = readerGeneration;
        String comicId = detail.summary.comicId;
        String chapterUrl = activeChapter.url;
        boolean cacheOnly = isRetiredComic(detail.summary.comicId);
        final TextView[] readerCount = {null};
        readerPreviousButton = null;
        readerNextButton = null;
        String entryKey = readerPositionKey(detail.summary.comicId, activeChapter);
        if (TextUtils.equals(readerEntryChapterUrl, chapterUrl) && readerEntryTarget != 0) {
            int target = readerEntryTarget < 0 ? Math.max(0, page.imageUrls.size() - 1) : 0;
            ReaderPosition entry = new ReaderPosition(target, 0, readerEntryTarget < 0);
            readerImagePositions.put(entryKey, entry);
            readerPositions.put(entryKey, entry.legacyProgress(page.imageUrls.size()));
            readerEntryChapterUrl = "";
            readerEntryTarget = 0;
        }
        if (isLocalTextBook(detail.summary.comicId)) {
            renderTextReader(detail, page, shell, top, topBarHeight, bottomBarHeight);
            return;
        }
        if (readerLayoutMode == 0) {
            readerLoadedChapterUrls.clear();
            readerLoadedChapterUrls.add(chapterUrl);
            int contentWidth = Math.max(1, getResources().getDisplayMetrics().widthPixels);
            int placeholderHeight = Math.max(1, contentWidth * 4 / 3);
            List<String> imageUrls = new ArrayList<>(page.imageUrls);
            List<ContinuousReaderItem> continuousItems = new ArrayList<>();
            for (int i = 0; i < page.imageUrls.size(); i++) {
                continuousItems.add(new ContinuousReaderItem(page.imageUrls.get(i), chapterUrl, readerChapterIndex,
                        i, page.imageUrls.size(), readerPositionKey(detail.summary.comicId, activeChapter)));
            }
            Map<ImageView, Future<?>> readerImageFutures = new HashMap<>();
            ListView list = new ListView(this);
            readerList = list;
            list.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
            list.setCacheColorHint(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
            list.setDivider(null);
            list.setSelector(new ColorDrawable(Color.TRANSPARENT));
            list.setPadding(0, 0, 0, 0);
            list.setVerticalScrollBarEnabled(false);
            list.setHorizontalScrollBarEnabled(false);
            list.setFastScrollEnabled(false);
            String positionKey = readerPositionKey(detail.summary.comicId, activeChapter);
            int savedPosition = readerPositions.containsKey(positionKey) ? readerPositions.get(positionKey) : 0;
            list.setTag(positionKey);
            final boolean[] restoringPosition = {savedPosition > 0 || readerImagePositions.containsKey(positionKey)};
            readerRestoringPosition = restoringPosition;
            LinearLayout listFooter = new LinearLayout(this);
            listFooter.setOrientation(LinearLayout.VERTICAL);
            listFooter.setGravity(Gravity.CENTER);
            listFooter.setPadding(0, UIHelpers.dp(this, 24), 0, UIHelpers.dp(this, 40));
            TextView footerPrompt = UIHelpers.text(this, "—— 已到达全书末尾 ——",
                    12, Color.argb(180, 160, 180, 205), Typeface.NORMAL);
            footerPrompt.setGravity(Gravity.CENTER);
            listFooter.addView(footerPrompt);
            boolean initialIsLast = readerChapterIndex + 1 >= detail.chapters.size();
            listFooter.setVisibility(initialIsLast ? View.VISIBLE : View.GONE);
            list.addFooterView(listFooter, null, false);
            BaseAdapter continuousAdapter = new BaseAdapter() {
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
                        image.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
                    }
                    Future<?> previous = readerImageFutures.remove(image);
                    if (previous != null && !previous.isDone()) previous.cancel(true);
                    String imageUrl = getItem(position);
                    ContinuousReaderItem item = position >= 0 && position < continuousItems.size() ? continuousItems.get(position) : null;
                    String itemChapterUrl = item != null ? item.chapterUrl : chapterUrl;

                    Bitmap cachedMem = readerBitmapCache.get(imageUrl);
                    if (cachedMem != null && !cachedMem.isRecycled()) {
                        if (readingHabitTracker != null) {
                            readingHabitTracker.onContentReadable();
                        }
                        image.setImageBitmap(cachedMem);
                        image.setScaleType(ImageView.ScaleType.FIT_CENTER);
                        applyReaderImageDisplayMode(image);
                        image.setTag(imageUrl);
                        int h = readerImageHeights.containsKey(imageUrl)
                                ? readerImageHeights.get(imageUrl)
                                : Math.max(1, Math.round(contentWidth * cachedMem.getHeight() / (float) Math.max(1, cachedMem.getWidth())));
                        readerImageHeights.put(imageUrl, h);
                        image.setLayoutParams(new AbsListView.LayoutParams(-1, h));
                        return image;
                    }

                    int h = placeholderHeight;
                    Integer knownH = readerImageHeights.get(imageUrl);
                    if (knownH != null) {
                        h = knownH;
                    } else {
                        File cachedFile = imageCacheFile(imageUrl);
                        if (cachedFile != null && cachedFile.length() > 0) {
                            BitmapFactory.Options bounds = new BitmapFactory.Options();
                            bounds.inJustDecodeBounds = true;
                            BitmapFactory.decodeFile(cachedFile.getAbsolutePath(), bounds);
                            if (bounds.outWidth > 0 && bounds.outHeight > 0) {
                                h = Math.max(1, Math.round(contentWidth * bounds.outHeight / (float) bounds.outWidth));
                                readerImageHeights.put(imageUrl, h);
                            }
                        }
                    }

                    image.setLayoutParams(new AbsListView.LayoutParams(-1, h));
                    image.setImageResource(R.drawable.rem_loading);
                    applyReaderImageDisplayMode(image);
                    image.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                    image.setTag(imageUrl);
                    Future<?> future = loadReaderImage(image, imageUrl, itemChapterUrl, generation, comicId,
                            list, restoringPosition, savedPosition, cacheOnly);
                    if (future != null) readerImageFutures.put(image, future);
                    return image;
                }
            };
            list.setAdapter(continuousAdapter);

            final int[] highestLoadedChapter = {readerChapterIndex};
            final boolean[] loadingNextChapter = {false};
            final BaseAdapter listAdapter = continuousAdapter;

            Runnable tryLoadNextChapter = new Runnable() {
                @Override
                public void run() {
                    if (loadingNextChapter[0]) return;
                    int nextIndex = highestLoadedChapter[0] + 1;
                    if (nextIndex >= detail.chapters.size()) {
                        if (listFooter.getVisibility() != View.VISIBLE) {
                            listFooter.setVisibility(View.VISIBLE);
                        }
                        return;
                    }
                    loadingNextChapter[0] = true;
                    loadChapterPageAsync(detail, nextIndex, nextChapterPage -> {
                        if (generation != readerGeneration || readerList != list || !readerVisible) return;
                        loadingNextChapter[0] = false;
                        if (nextChapterPage == null || nextChapterPage.imageUrls == null || nextChapterPage.imageUrls.isEmpty()) return;
                        highestLoadedChapter[0] = nextIndex;
                        ComicModels.Chapter nextChapter = detail.chapters.get(nextIndex);
                        String nextChapterUrl = nextChapter.url;
                        String nextPosKey = readerPositionKey(detail.summary.comicId, nextChapter);
                        readerLoadedChapterUrls.add(nextChapterUrl);
                        int newPageCount = nextChapterPage.imageUrls.size();
                        for (int i = 0; i < newPageCount; i++) {
                            String u = nextChapterPage.imageUrls.get(i);
                            imageUrls.add(u);
                            continuousItems.add(new ContinuousReaderItem(u, nextChapterUrl, nextIndex, i, newPageCount, nextPosKey));
                        }
                        listAdapter.notifyDataSetChanged();
                        prefetchReaderImages(imageUrls, list.getLastVisiblePosition() + 1,
                                nextChapterUrl, generation, comicId, cacheOnly);
                        if (highestLoadedChapter[0] >= detail.chapters.size() - 1) {
                            listFooter.setVisibility(View.VISIBLE);
                        }
                    }, () -> {
                        if (generation != readerGeneration || readerList != list || !readerVisible) return;
                        loadingNextChapter[0] = false;
                    });
                }
            };

            list.setOnScrollListener(new AbsListView.OnScrollListener() {
                @Override
                public void onScrollStateChanged(AbsListView view, int scrollState) {
                    if (scrollState == AbsListView.OnScrollListener.SCROLL_STATE_TOUCH_SCROLL
                            || scrollState == AbsListView.OnScrollListener.SCROLL_STATE_FLING) {
                        if (readingHabitTracker != null) {
                            readingHabitTracker.onUserAction();
                        }
                        if (!readerFullscreen) {
                            setReaderFullscreen(true, true);
                        }
                    }
                }

                @Override
                public void onScroll(AbsListView view, int firstVisibleItem, int visibleItemCount, int totalItemCount) {
                    if (generation != readerGeneration || readerList != list) return;
                    ContinuousReaderItem currentItem = (firstVisibleItem >= 0 && firstVisibleItem < continuousItems.size())
                            ? continuousItems.get(firstVisibleItem) : null;
                    if (!restoringPosition[0]) {
                        saveReaderPosition(list, positionKey);
                        if (currentItem != null && !TextUtils.equals(currentItem.positionKey, positionKey)) {
                            saveContinuousReaderPosition(list, currentItem);
                        }
                    }
                    if (!readerSeeking && readerSeekBar != null && totalItemCount > 0) {
                        readerSeekBar.setProgress(currentItem != null ? currentItem.pageIndex : firstVisibleItem);
                    }
                    if (currentItem != null) {
                        if (currentItem.chapterIndex != readerChapterIndex) {
                            readerChapterIndex = currentItem.chapterIndex;
                            progress.put(comicId, readerChapterIndex);
                            if (isLocalComic(comicId) && readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
                                getSharedPreferences("xxcomic_local_locators", MODE_PRIVATE).edit()
                                        .putString(comicId, detail.chapters.get(readerChapterIndex).chapterId).apply();
                            }
                            lastViewedAt.put(comicId, System.currentTimeMillis());
                            saveLocalState();
                            updateReaderToolbarTitle(detail);
                        }
                        int newPage = currentItem.pageIndex + 1;
                        int newTotal = currentItem.pageCount;
                        if (newPage != readerCurrentPageNumber || newTotal != readerTotalPages) {
                            readerCurrentPageNumber = newPage;
                            readerTotalPages = newTotal;
                            refreshReaderOverlayBadge();
                        }
                    } else if (totalItemCount > 0) {
                        int newPage = Math.max(1, Math.min(totalItemCount, firstVisibleItem + 1));
                        if (newPage != readerCurrentPageNumber || totalItemCount != readerTotalPages) {
                            readerCurrentPageNumber = newPage;
                            readerTotalPages = totalItemCount;
                            refreshReaderOverlayBadge();
                        }
                    }
                    if (visibleItemCount > 0) {
                        prefetchReaderImagesAround(imageUrls, firstVisibleItem, visibleItemCount,
                                currentItem != null ? currentItem.chapterUrl : chapterUrl, generation, comicId, cacheOnly);
                    }
                    if (totalItemCount > 0 && firstVisibleItem + visibleItemCount >= totalItemCount - 5) {
                        tryLoadNextChapter.run();
                    }
                }
            });
            final float[] scaleState = new float[]{1.0f};
            final float[] transXState = new float[]{0.0f};
            final float[] transYState = new float[]{0.0f};
            final float[] lastTouchX = new float[]{0.0f};
            final float[] lastTouchY = new float[]{0.0f};
            final boolean[] skipNextMove = new boolean[]{false};
            final boolean[] multiTouchGesture = new boolean[]{false};
            final boolean[] doubleTapGesture = new boolean[]{false};
            final ValueAnimator[] zoomAnimation = new ValueAnimator[1];

            ScaleGestureDetector listScaleDetector = new ScaleGestureDetector(this, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                private float lastFocusX, lastFocusY;

                @Override
                public boolean onScaleBegin(ScaleGestureDetector detector) {
                    if (!readerPinchZoom) return false;
                    lastFocusX = detector.getFocusX();
                    lastFocusY = detector.getFocusY();
                    list.setPivotX(list.getWidth() / 2f);
                    list.setPivotY(list.getHeight() / 2f);
                    return true;
                }

                @Override
                public boolean onScale(ScaleGestureDetector detector) {
                    if (!readerPinchZoom) return false;
                    float factor = detector.getScaleFactor();
                    float oldScale = scaleState[0];
                    float newScale = Math.max(0.75f, Math.min(3.5f, oldScale * factor));
                    scaleState[0] = newScale;

                    float focusX = detector.getFocusX();
                    float focusY = detector.getFocusY();
                    float centerX = list.getWidth() / 2f;
                    float centerY = list.getHeight() / 2f;
                    float ratio = newScale / oldScale;

                    transXState[0] = ZoomGeometry.followFocus(transXState[0], centerX, lastFocusX, focusX, ratio);
                    transYState[0] = ZoomGeometry.followFocus(transYState[0], centerY, lastFocusY, focusY, ratio);
                    lastFocusX = focusX;
                    lastFocusY = focusY;
                    transXState[0] += ZoomGeometry.correction(centerX * (1f - newScale) + transXState[0],
                            list.getWidth() * newScale, list.getWidth(), list.getWidth() * .2f);
                    transYState[0] += ZoomGeometry.correction(centerY * (1f - newScale) + transYState[0],
                            list.getHeight() * newScale, list.getHeight(), list.getHeight() * .2f);

                    list.setScaleX(newScale);
                    list.setScaleY(newScale);
                    list.setTranslationX(transXState[0]);
                    list.setTranslationY(transYState[0]);
                    return true;
                }

            });
            listScaleDetector.setQuickScaleEnabled(false);

            GestureDetector listTapDetector = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
                @Override
                public boolean onDoubleTap(MotionEvent e) {
                    if (!readerPinchZoom) return false;
                    doubleTapGesture[0] = true;
                    if (scaleState[0] > 1.05f) {
                        animateScaleTo(list, scaleState, transXState, transYState, zoomAnimation, 1f, 0f, 0f);
                    } else {
                        float targetScale = 2.2f;
                        float focusX = e.getX();
                        float focusY = e.getY();
                        float centerX = list.getWidth() / 2f;
                        float centerY = list.getHeight() / 2f;
                        float targetTransX = ZoomGeometry.followFocus(transXState[0], centerX, focusX, focusX, targetScale / scaleState[0]);
                        float targetTransY = ZoomGeometry.followFocus(transYState[0], centerY, focusY, focusY, targetScale / scaleState[0]);
                        float maxPanX = Math.max(0f, (list.getWidth() * (targetScale - 1f)) / 2f);
                        float maxPanY = Math.max(0f, (list.getHeight() * (targetScale - 1f)) / 2f);
                        targetTransX = Math.max(-maxPanX, Math.min(maxPanX, targetTransX));
                        targetTransY = Math.max(-maxPanY, Math.min(maxPanY, targetTransY));
                        animateScaleTo(list, scaleState, transXState, transYState, zoomAnimation, targetScale, targetTransX, targetTransY);
                    }
                    return true;
                }
            });
            listTapDetector.setIsLongpressEnabled(false);

            list.setOnTouchListener((v, event) -> {
                int action = event.getActionMasked();
                if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_POINTER_DOWN) {
                    list.animate().cancel();
                    if (zoomAnimation[0] != null) { zoomAnimation[0].cancel(); zoomAnimation[0] = null; }
                    scaleState[0] = list.getScaleX();
                    transXState[0] = list.getTranslationX();
                    transYState[0] = list.getTranslationY();
                    if (action == MotionEvent.ACTION_DOWN) {
                        multiTouchGesture[0] = false;
                        doubleTapGesture[0] = false;
                        skipNextMove[0] = false;
                    } else if (readerPinchZoom) {
                        multiTouchGesture[0] = true;
                        doubleTapGesture[0] = false;
                        // End native scrolling/fling before the pinch takes ownership.
                        MotionEvent cancel = MotionEvent.obtain(event);
                        cancel.setAction(MotionEvent.ACTION_CANCEL);
                        list.onTouchEvent(cancel);
                        cancel.recycle();
                    }
                }
                if (readerPinchZoom) {
                    // Android delivers inverse-transformed coordinates to the scaled view.
                    // Map them back so changing scale cannot feed back into the next pinch span.
                    MotionEvent viewportEvent = MotionEvent.obtain(event);
                    viewportEvent.transform(list.getMatrix());
                    listScaleDetector.onTouchEvent(viewportEvent);
                    listTapDetector.onTouchEvent(viewportEvent);
                    viewportEvent.recycle();
                }
                if (action == MotionEvent.ACTION_DOWN) {
                    restoringPosition[0] = false;
                    readerDownX = event.getRawX();
                    readerDownY = event.getRawY();
                    lastTouchX[0] = event.getRawX();
                    lastTouchY[0] = event.getRawY();
                    readerDownAt = System.currentTimeMillis();
                    return Math.abs(scaleState[0] - 1f) > .001f || doubleTapGesture[0];
                }
                if (action == MotionEvent.ACTION_POINTER_DOWN || action == MotionEvent.ACTION_POINTER_UP) {
                    skipNextMove[0] = true;
                }
                if (readerPinchZoom && event.getPointerCount() > 1 && action != MotionEvent.ACTION_CANCEL) {
                    return true;
                }
                if (action == MotionEvent.ACTION_MOVE) {
                    if (skipNextMove[0]) {
                        skipNextMove[0] = false;
                        lastTouchX[0] = event.getRawX();
                        lastTouchY[0] = event.getRawY();
                    }
                    float dy = Math.abs(event.getRawY() - readerDownY);
                    float dx = Math.abs(event.getRawX() - readerDownX);
                    if (scaleState[0] > 1.05f) {
                        float deltaX = event.getRawX() - lastTouchX[0];
                        float deltaY = event.getRawY() - lastTouchY[0];
                        lastTouchX[0] = event.getRawX();
                        lastTouchY[0] = event.getRawY();
                        if (doubleTapGesture[0]) return true;
                        transXState[0] += deltaX;
                        transYState[0] += deltaY;
                        transXState[0] += ZoomGeometry.correction(list.getWidth() * (1f - scaleState[0]) / 2f + transXState[0],
                                list.getWidth() * scaleState[0], list.getWidth(), list.getWidth() * .2f);
                        transYState[0] += ZoomGeometry.correction(list.getHeight() * (1f - scaleState[0]) / 2f + transYState[0],
                                list.getHeight() * scaleState[0], list.getHeight(), list.getHeight() * .2f);
                        list.setTranslationX(transXState[0]);
                        list.setTranslationY(transYState[0]);
                        return true;
                    }
                    if (multiTouchGesture[0] || doubleTapGesture[0] || Math.abs(scaleState[0] - 1f) > .001f) return true;
                    if (readerPageMode == 2 && scaleState[0] <= 1.05f && dx > dy && dx > UIHelpers.dp(MainActivity.this, 8)) {
                        if (!readerDisablePageAnimation) {
                            float drag = event.getRawX() - readerDownX;
                            v.setTranslationX(Math.max(-UIHelpers.dp(MainActivity.this, 110), Math.min(UIHelpers.dp(MainActivity.this, 110), drag * .28f)));
                        }
                        return true;
                    }
                    if ((dy > UIHelpers.dp(MainActivity.this, 8) || dx > UIHelpers.dp(MainActivity.this, 8)) && !readerFullscreen) {
                        setReaderFullscreen(true, true);
                    }
                    return false;
                }
                if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                    if (doubleTapGesture[0]) return true;
                    boolean zoomGesture = multiTouchGesture[0] || Math.abs(scaleState[0] - 1f) > .001f;
                    if (scaleState[0] <= 1.05f) {
                        if (zoomGesture) animateScaleTo(list, scaleState, transXState, transYState, zoomAnimation, 1f, 0f, 0f);
                    } else {
                        float maxPanX = Math.max(0f, (list.getWidth() * (scaleState[0] - 1f)) / 2f);
                        float maxPanY = Math.max(0f, (list.getHeight() * (scaleState[0] - 1f)) / 2f);
                        animateScaleTo(list, scaleState, transXState, transYState, zoomAnimation, scaleState[0],
                                Math.max(-maxPanX, Math.min(maxPanX, transXState[0])),
                                Math.max(-maxPanY, Math.min(maxPanY, transYState[0])));
                    }
                    if (zoomGesture) return true;
                    if (action == MotionEvent.ACTION_UP) {
                        float totalDy = event.getRawY() - readerDownY;
                        long duration = System.currentTimeMillis() - readerDownAt;
                        if (scaleState[0] <= 1.05f && duration < 1500) {
                            if (totalDy < -UIHelpers.dp(MainActivity.this, 36)) {
                                int lastVisible = list.getLastVisiblePosition();
                                int total = list.getCount();
                                if (lastVisible >= total - 1) {
                                    View lastChild = list.getChildAt(list.getChildCount() - 1);
                                    if (lastChild != null && lastChild.getBottom() <= list.getHeight() + UIHelpers.dp(MainActivity.this, 30)) {
                                        if (highestLoadedChapter[0] + 1 < detail.chapters.size()) {
                                            tryLoadNextChapter.run();
                                        } else {
                                            showReaderBoundaryHint("已经是最后一章");
                                        }
                                        return true;
                                    }
                                }
                            }
                            if (totalDy > UIHelpers.dp(MainActivity.this, 40)) {
                                int firstVisible = list.getFirstVisiblePosition();
                                if (firstVisible == 0) {
                                    View firstChild = list.getChildAt(0);
                                    if (firstChild != null && firstChild.getTop() >= -UIHelpers.dp(MainActivity.this, 20)) {
                                        navigateReader(detail, page, -1);
                                        return true;
                                    }
                                }
                            }
                        }
                        boolean handled = handleReaderTap(event, detail, page);
                        if (scaleState[0] <= 1.05f) {
                            if (readerDisablePageAnimation) {
                                v.setTranslationX(0f);
                            } else {
                                v.animate().translationX(0f).setDuration(220L).start();
                            }
                        }
                        return handled;
                    }
                    return false;
                }
                return false;
            });
            list.addOnLayoutChangeListener((v, left, topEdge, right, bottomEdge,
                                            oldLeft, oldTop, oldRight, oldBottom) -> {
                if (restoringPosition[0] && savedPosition == READER_POSITION_SCALE) alignReaderBottom(list);
            });
            if (restoringPosition[0]) list.post(() -> {
                if (readerList == list) restoreReaderPosition(list, savedPosition);
            });
            list.post(() -> prefetchReaderImages(imageUrls,
                    Math.max(0, list.getLastVisiblePosition() + 1), chapterUrl, generation, comicId, cacheOnly));
            list.postDelayed(tryLoadNextChapter, 600L);
            FrameLayout readerContent = new FrameLayout(this);
            readerContentView = readerContent;
            FrameLayout.LayoutParams listParams = new FrameLayout.LayoutParams(-1, -1);
            listParams.bottomMargin = readerButtonMode ? UIHelpers.dp(this, 52) : 0;
            readerContent.addView(list, listParams);
            View empty = readerState(R.drawable.rem_error, "这一章没有解析出来", "再试一次吧", "重试",
                    () -> showReader(detail, readerChapterIndex), false);
            readerContent.addView(empty, UIHelpers.match());
            list.setEmptyView(empty);
            shell.addView(readerContent, UIHelpers.match());
        } else {
            FrameLayout content = new FrameLayout(this);
            readerContentView = content;
            FrameLayout.LayoutParams contentParams = new FrameLayout.LayoutParams(-1, -1);
            contentParams.bottomMargin = readerButtonMode ? UIHelpers.dp(this, 52) : 0;
            shell.addView(content, contentParams);
            if (page.imageUrls.isEmpty()) {
                content.addView(readerState(R.drawable.rem_error, "这一章没有解析出来", "再试一次吧", "重试",
                        () -> showReader(detail, readerChapterIndex), false), UIHelpers.match());
            } else {
                ReaderPosition position = readerImagePositions.get(entryKey);
                if (position == null) position = ReaderPosition.fromLegacy(readerPositions.containsKey(entryKey) ? readerPositions.get(entryKey) : 0, page.imageUrls.size());
                int initial = position.indexFor(page.imageUrls.size());
                readerImagePositions.put(entryKey, position);
                readerPager = new PagedReaderView(this, page.imageUrls, initial, readerPageMode, readerLeftHand, readerPinchZoom, readerDisablePageAnimation,
                        (image, imageUrl) -> {
                            applyReaderImageDisplayMode(image);
                            Bitmap mem = readerBitmapCache.get(imageUrl);
                            if (mem != null && !mem.isRecycled()) {
                                if (readingHabitTracker != null) {
                                    readingHabitTracker.onContentReadable();
                                }
                                image.setImageBitmap(mem);
                                image.setScaleType(ImageView.ScaleType.FIT_CENTER);
                                applyReaderImageDisplayMode(image);
                                return null;
                            }
                            image.setImageResource(R.drawable.rem_loading);
                            applyReaderImageDisplayMode(image);
                            return loadReaderImage(image, imageUrl, chapterUrl, generation, comicId, null, new boolean[]{false}, 0, cacheOnly);
                        }, new PagedReaderView.Listener() {
                    @Override public void onPageChanged(int index) {
                        if (readingHabitTracker != null) {
                            readingHabitTracker.onContentReadable();
                            readingHabitTracker.onUserAction();
                        }
                        if (!isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                        recordPagedPosition(entryKey, index, page.imageUrls.size());
                        if (readerCount[0] != null) readerCount[0].setText((index + 1) + " / " + page.imageUrls.size() + " 页");
                        if (!readerSeeking && readerSeekBar != null) readerSeekBar.setProgress(index);
                        readerCurrentPageNumber = index + 1;
                        readerTotalPages = page.imageUrls.size();
                        refreshReaderOverlayBadge();
                        updateReaderButtons(detail, page);
                        prefetchReaderImages(page.imageUrls, index + 1, chapterUrl, generation, comicId, cacheOnly);
                    }
                    @Override public void onNavigate(int delta) { navigateReader(detail, page, delta); }
                    @Override public void onToggleControls() { toggleReaderFullscreen(); }
                    @Override public void onInteraction() {
                        if (readingHabitTracker != null) {
                            readingHabitTracker.onUserAction();
                        }
                        if (!readerFullscreen) setReaderFullscreen(true, true);
                    }
                });
                readerPager.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : Color.rgb(12, 20, 32));
                content.addView(readerPager, UIHelpers.match());
                prefetchReaderImages(page.imageUrls, initial + 1, chapterUrl, generation, comicId, cacheOnly);
            }
        }

        if (readerButtonMode) {
            LinearLayout chapterButtons = new LinearLayout(this);
            chapterButtons.setOrientation(LinearLayout.HORIZONTAL);
            chapterButtons.setGravity(Gravity.CENTER);
            chapterButtons.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 4), UIHelpers.dp(this, 12), UIHelpers.dp(this, 4));
            chapterButtons.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : 0xF00C1420);
            TextView previous = UIHelpers.text(this, readerLayoutMode == 1 ? "上一页" : "上一章", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
            TextView next = UIHelpers.text(this, readerLayoutMode == 1 ? "下一页" : "下一章", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
            previous.setGravity(Gravity.CENTER); next.setGravity(Gravity.CENTER);
            readerPreviousButton = previous; readerNextButton = next;
            updateReaderButtons(detail, page);
            previous.setOnClickListener(v -> navigateReader(detail, page, -1));
            next.setOnClickListener(v -> navigateReader(detail, page, 1));
            chapterButtons.addView(previous, new LinearLayout.LayoutParams(0, -1, 1));
            chapterButtons.addView(UIHelpers.space(this, UIHelpers.dp(this, 8), 1));
            chapterButtons.addView(next, new LinearLayout.LayoutParams(0, -1, 1));
            shell.addView(chapterButtons, new FrameLayout.LayoutParams(-1, UIHelpers.dp(this, 52), Gravity.BOTTOM));
        }

        View chapterProgress = readerProgressBar(readerChapterIndex + 1, detail.chapters.size());
        readerProgressView = chapterProgress;
        chapterProgress.setAlpha(readerFullscreen ? 1f : 0f);
        shell.addView(chapterProgress, new FrameLayout.LayoutParams(-1, UIHelpers.dp(this, 2), Gravity.BOTTOM));

        FrameLayout.LayoutParams topParams = new FrameLayout.LayoutParams(-1, topBarHeight, Gravity.TOP);
        shell.addView(top, topParams);
        readerTopBar = top;

        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.VERTICAL);
        bottom.setClickable(true);
        if (readerDisplayMode == 1) {
            bottom.setBackgroundColor(Color.BLACK);
        } else {
            GradientDrawable bottomBg = new GradientDrawable(
                    GradientDrawable.Orientation.BOTTOM_TOP,
                    new int[]{0xF20C1420, 0xD80C1420}
            );
            bottom.setBackground(bottomBg);
        }

        // Row 1: 上一章 ｜ 本章进度条 ｜ 下一章
        LinearLayout row1 = new LinearLayout(this);
        row1.setOrientation(LinearLayout.HORIZONTAL);
        row1.setGravity(Gravity.CENTER_VERTICAL);
        row1.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 2), UIHelpers.dp(this, 12), 0);

        TextView prevChapter = UIHelpers.text(this, "上一章", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        prevChapter.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        prevChapter.setGravity(Gravity.CENTER);
        prevChapter.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 6), UIHelpers.dp(this, 8), UIHelpers.dp(this, 6));
        prevChapter.setClickable(true);
        prevChapter.setFocusable(true);
        UIHelpers.tapFeedback(prevChapter);
        boolean hasPrevChapter = readerChapterIndex > 0;
        boolean hasNextChapter = readerChapterIndex + 1 < detail.chapters.size();
        prevChapter.setEnabled(hasPrevChapter);
        prevChapter.setAlpha(hasPrevChapter ? 1f : 0.35f);
        prevChapter.setOnClickListener(v -> {
            if (readerChapterIndex > 0) switchChapter(detail, -1);
        });

        TextView nextChapter = UIHelpers.text(this, "下一章", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        nextChapter.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        nextChapter.setGravity(Gravity.CENTER);
        nextChapter.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 6), UIHelpers.dp(this, 8), UIHelpers.dp(this, 6));
        nextChapter.setClickable(true);
        nextChapter.setFocusable(true);
        UIHelpers.tapFeedback(nextChapter);
        nextChapter.setEnabled(hasNextChapter);
        nextChapter.setAlpha(hasNextChapter ? 1f : 0.35f);
        nextChapter.setOnClickListener(v -> {
            if (readerChapterIndex + 1 < detail.chapters.size()) switchChapter(detail, 1);
        });

        int totalPages = Math.max(1, page.imageUrls.size());
        int initialPage = 0;
        if (readerLayoutMode == 1 && readerPager != null) {
            initialPage = readerPager.currentPage();
        }

        SeekBar seekBar = new SeekBar(this);
        readerSeekBar = seekBar;
        seekBar.setMax(Math.max(1, totalPages - 1));
        seekBar.setProgress(Math.min(totalPages - 1, initialPage));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            seekBar.setProgressTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
            seekBar.setThumbTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
        }

        seekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progressVal, boolean fromUser) {
                if (fromUser) {
                    if (readingHabitTracker != null) {
                        readingHabitTracker.onUserAction();
                    }
                    if (readerLayoutMode == 1 && readerPager != null) {
                        readerPager.moveTo(progressVal);
                    } else if (readerLayoutMode == 0 && readerList != null) {
                        readerList.setSelection(progressVal);
                    }
                }
            }
            @Override public void onStartTrackingTouch(SeekBar sb) { readerSeeking = true; }
            @Override public void onStopTrackingTouch(SeekBar sb) { readerSeeking = false; }
        });

        LinearLayout.LayoutParams seekParams = new LinearLayout.LayoutParams(0, -2, 1f);
        seekParams.leftMargin = UIHelpers.dp(this, 10);
        seekParams.rightMargin = UIHelpers.dp(this, 10);

        row1.addView(prevChapter, new LinearLayout.LayoutParams(-2, -2));
        row1.addView(seekBar, seekParams);
        row1.addView(nextChapter, new LinearLayout.LayoutParams(-2, -2));
        bottom.addView(row1, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 42)));

        // Row 2: 目录 ｜ 换源/详情 ｜ 设置
        LinearLayout row2 = new LinearLayout(this);
        row2.setOrientation(LinearLayout.HORIZONTAL);
        row2.setGravity(Gravity.CENTER_VERTICAL);
        row2.setPadding(UIHelpers.dp(this, 16), 0, UIHelpers.dp(this, 16), UIHelpers.dp(this, 4));

        LinearLayout tocBtn = createBottomActionItem(R.drawable.ic_chapter_list, "目录", () -> showChapterDrawer(detail));
        LinearLayout middleBtn = isLocalComicDetail(detail)
                ? createBottomActionItem(R.drawable.ic_detail, "详情", () -> {
                    if (!TextUtils.isEmpty(activeDetailId)) {
                        showDetailFromReader(activeDetailId, readerChapterIndex);
                    } else {
                        onBackPressed();
                    }
                })
                : createBottomActionItem(R.drawable.ic_source, "换源", () -> showReaderSourceSheet(detail));
        LinearLayout settingsBtn = createBottomActionItem(R.drawable.ic_settings, "设置", this::showReaderSettings);

        row2.addView(tocBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        row2.addView(middleBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        row2.addView(settingsBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        bottom.addView(row2, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 46)));

        FrameLayout.LayoutParams bottomParams = new FrameLayout.LayoutParams(-1, bottomBarHeight, Gravity.BOTTOM);
        if (readerButtonMode) bottomParams.bottomMargin = UIHelpers.dp(this, 52);
        shell.addView(bottom, bottomParams);
        readerBottomBar = bottom;

        TextView overlayBadge = new TextView(this);
        overlayBadge.setTextSize(11);
        if (readerDisplayMode == 1) {
            overlayBadge.setTextColor(Color.WHITE);
            overlayBadge.setBackground(UIHelpers.round(Color.BLACK, UIHelpers.dp(this, 6), Color.WHITE));
        } else {
            overlayBadge.setTextColor(Color.argb(220, 230, 240, 255));
            overlayBadge.setShadowLayer(3f, 1f, 1f, Color.argb(180, 0, 0, 0));
            overlayBadge.setBackground(UIHelpers.round(Color.argb(140, 12, 19, 28), UIHelpers.dp(this, 6), Color.TRANSPARENT));
        }
        overlayBadge.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 4), UIHelpers.dp(this, 8), UIHelpers.dp(this, 4));
        overlayBadge.setSingleLine(true);
        overlayBadge.setEllipsize(TextUtils.TruncateAt.END);
        overlayBadge.setGravity(Gravity.CENTER_VERTICAL);
        readerOverlayBadge = overlayBadge;

        readerCurrentPageNumber = initialPage + 1;
        readerTotalPages = Math.max(1, page.imageUrls.size());
        registerReaderBatteryReceiver();
        main.removeCallbacks(readerTimeUpdateRunnable);
        main.postDelayed(readerTimeUpdateRunnable, 15000L);
        refreshReaderOverlayBadge();

        FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.END);
        badgeParams.rightMargin = UIHelpers.dp(this, 10);
        badgeParams.bottomMargin = UIHelpers.dp(this, readerButtonMode ? 60 : 8);
        shell.addView(overlayBadge, badgeParams);
        updateReaderOverlayVisibility(false);

        setReaderFullscreen(readerFullscreen, false);
    }

    private void animateScaleTo(View view, float[] scaleState, float[] transXState, float[] transYState,
                                ValueAnimator[] animation, float targetScale, float targetTransX, float targetTransY) {
        if (animation[0] != null) animation[0].cancel();
        view.animate().cancel();
        view.setPivotX(view.getWidth() / 2f);
        view.setPivotY(view.getHeight() / 2f);
        float startScale = view.getScaleX(), startX = view.getTranslationX(), startY = view.getTranslationY();
        ValueAnimator animator = ValueAnimator.ofFloat(0f, 1f);
        animation[0] = animator;
        animator.setDuration(220L);
        animator.setInterpolator(new DecelerateInterpolator());
        animator.addUpdateListener(a -> {
            float progress = (float) a.getAnimatedValue();
            scaleState[0] = startScale + (targetScale - startScale) * progress;
            transXState[0] = startX + (targetTransX - startX) * progress;
            transYState[0] = startY + (targetTransY - startY) * progress;
            view.setScaleX(scaleState[0]);
            view.setScaleY(scaleState[0]);
            view.setTranslationX(transXState[0]);
            view.setTranslationY(transYState[0]);
        });
        animator.start();
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
        boolean swipe = readerPageMode == 2 && moveX > UIHelpers.dp(this, 72) && moveX > moveY * 1.35f
                && System.currentTimeMillis() - readerDownAt < 1200L;
        if (swipe) {
            navigateReader(detail, page, ReaderNavigation.swipeDelta(x - readerDownX, readerLeftHand));
            return true;
        }
        boolean tap = moveX < UIHelpers.dp(this, 10) && moveY < UIHelpers.dp(this, 10) && System.currentTimeMillis() - readerDownAt < 300L;
        boolean activeY = y > height * 0.25f && y < height * 0.75f;
        if (!tap || !activeY) return false;
        boolean leftSide = x < width * 0.28f;
        boolean rightSide = x > width * 0.72f;
        if (readerPageMode == 0 && (leftSide || rightSide)) {
            navigateReader(detail, page, ReaderNavigation.tapDelta(leftSide, readerLeftHand));
        } else {
            toggleReaderFullscreen();
        }
        return true;
    }

    private void toggleReaderFullscreen() {
        setReaderFullscreen(!readerFullscreen, true);
    }

    private boolean isLocalTextBook(String comicId) {
        if (!isLocalComic(comicId) || !localLibraryReady) return false;
        try {
            LocalModels.Book book = localBookForReading(comicId);
            if (book != null) {
                List<LocalModels.Chapter> chapters = getLocalLibraryStore().getChapters(book.id);
                List<LocalModels.Page> pages = chapters.isEmpty() ? Collections.emptyList()
                        : getLocalLibraryStore().getPages(chapters.get(Math.max(0, Math.min(readerChapterIndex, chapters.size() - 1))).id);
                LocalModels.Page firstPage = pages.isEmpty() ? null : pages.get(0);
                if (firstPage != null && firstPage.mimeType != null) {
                    return firstPage.mimeType.contains("xhtml")
                            || firstPage.mimeType.contains("html")
                            || firstPage.mimeType.contains("text");
                }
            }
        } catch (Exception ignored) {}
        return false;
    }

    private void renderTextReader(ComicModels.ComicDetail detail, ComicModels.ChapterPage page,
                                  FrameLayout shell, LinearLayout top, int topBarHeight, int bottomBarHeight) {
        String comicId = detail.summary.comicId;
        LocalModels.Book book = localBookForReading(comicId);
        if (book == null) return;
        if (readingHabitTracker != null) {
            readingHabitTracker.onEnterReader(comicId, true);
            readingHabitTracker.onContentReadable();
        }

        File epubFile;
        com.xxcomic.ebook.TextReaderView textReader = new com.xxcomic.ebook.TextReaderView(this);
        textReaderView = textReader;
        try {
            LocalModels.Volume volume = null;
            if (readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
                String chapterId = LocalContentResolver.extractId(detail.chapters.get(readerChapterIndex).url, LocalContentResolver.PREFIX_CHAPTER);
                LocalModels.Chapter chapter = getLocalLibraryStore().getChapter(chapterId);
                if (chapter != null && chapter.volumeId != null) {
                    volume = getLocalLibraryStore().getVolume(chapter.volumeId);
                    if (volume == null) throw new IOException("本地分卷已移除");
                }
            }
            String containerId = volume == null ? book.id : volume.id;
            if (LocalModels.isKindleFormat(volume == null ? book.format : volume.format)) {
                epubFile = getLocalStorageManager().getDerivedBookFile(containerId, ".epub");
                if (!epubFile.exists()) {
                    File srcFile = volume == null ? getLocalStorageManager().getBookContentFile(book)
                            : getLocalStorageManager().getBookImportFile(volume.relativePath);
                    com.xxcomic.ebook.KindlePublicationAdapter.convertMobiToDerivedEpub(srcFile, epubFile, containerId);
                }
            } else {
                String chFilePath = book.relativePath;
                if (readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
                    String chUrl = detail.chapters.get(readerChapterIndex).url;
                    if (LocalContentResolver.isLocalChapterUrl(chUrl)) {
                        String chId = LocalContentResolver.extractId(chUrl, LocalContentResolver.PREFIX_CHAPTER);
                        LocalModels.Chapter lc = getLocalLibraryStore().getChapter(chId);
                        if (lc != null && !TextUtils.isEmpty(lc.entryPath) && lc.entryPath.endsWith(".epub")) {
                            chFilePath = lc.entryPath;
                        }
                    }
                }
                epubFile = getLocalStorageManager().getBookImportFile(volume == null ? chFilePath : volume.relativePath);
            }
            textReader.setEpubFile(epubFile, containerId);
        } catch (Exception error) {
            showRemErrorToast("无法打开电子书文件: " + error.getMessage());
            return;
        }

        com.xxcomic.ebook.TextReaderSettingsSheet.Settings settings =
                com.xxcomic.ebook.TextReaderSettingsSheet.loadSettings(this);
        textReader.setSettings(settings.fontSizeSp, settings.lineHeight, settings.theme, settings.pagedMode);

        FrameLayout content = new FrameLayout(this);
        readerContentView = content;
        content.addView(textReader, UIHelpers.match());
        shell.addView(content, UIHelpers.match());

        // Restore locator
        String prefKey = "text_pos_" + comicId;
        String savedLocJson = getSharedPreferences("xxcomic_text_locators", MODE_PRIVATE).getString(prefKey, null);
        com.xxcomic.ebook.TextLocator savedLoc = com.xxcomic.ebook.TextLocator.fromJson(savedLocJson);
        if (savedLoc != null && savedLoc.chapterIndex != readerChapterIndex) {
            savedLoc = null;
        }

        // Determine entryPath
        String entryPath = "";
        if (readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
            String chUrl = detail.chapters.get(readerChapterIndex).url;
            if (LocalContentResolver.isLocalChapterUrl(chUrl)) {
                String chId = LocalContentResolver.extractId(chUrl, LocalContentResolver.PREFIX_CHAPTER);
                List<LocalModels.Page> lps = getLocalLibraryStore().getPages(chId);
                if (lps != null && !lps.isEmpty()) {
                    entryPath = lps.get(0).entryPath;
                }
            }
        }
        if (TextUtils.isEmpty(entryPath) && page != null && !page.imageUrls.isEmpty()) {
            String pUrl = page.imageUrls.get(0);
            if (LocalContentResolver.isLocalPageUrl(pUrl)) {
                LocalModels.Page lp = getLocalLibraryStore().getPage(LocalContentResolver.extractId(pUrl, LocalContentResolver.PREFIX_PAGE));
                if (lp != null) entryPath = lp.entryPath;
            }
        }

        textReader.loadSpineEntry(readerChapterIndex, readerChapterIndex, entryPath, savedLoc);

        textReader.setListener(new com.xxcomic.ebook.TextReaderView.Listener() {
            @Override
            public void onPositionChanged(com.xxcomic.ebook.TextLocator locator) {
                if (readingHabitTracker != null) {
                    readingHabitTracker.onUserAction();
                }
                if (locator != null) {
                    getSharedPreferences("xxcomic_text_locators", MODE_PRIVATE).edit()
                            .putString(prefKey, locator.toJson())
                            .apply();
                }
                int pct = Math.round(locator != null ? locator.scrollPercentage * 100f : 0f);
                if (readerSeekBar != null && !readerSeeking) {
                    readerSeekBar.setProgress(pct);
                }
                readerCurrentPageNumber = pct;
                readerTotalPages = 100;
                refreshReaderOverlayBadge();
            }

            @Override
            public void onToggleControls() {
                toggleReaderFullscreen();
            }

            @Override
            public void onNavigateChapter(int delta) {
                if (readerChapterIndex + delta >= 0 && readerChapterIndex + delta < detail.chapters.size()) {
                    switchChapter(detail, delta);
                } else {
                    showReaderBoundaryHint(delta > 0 ? "已经是最后一章" : "已经是第一章");
                }
            }

            @Override
            public void onExternalLinkClicked(String url) {
                showRemDialog(R.drawable.rem_reader_boundary, "外部链接提示", "该链接指向外部网络：\n" + url + "\n\n是否在外部浏览器打开？",
                        "打开", () -> {
                            try {
                                Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                                startActivity(intent);
                            } catch (Exception ignored) {}
                        });
            }
        });

        // Overlay Badge
        TextView overlayBadge = new TextView(this);
        readerOverlayBadge = overlayBadge;
        overlayBadge.setTextSize(11);
        overlayBadge.setTextColor(Color.argb(220, 230, 240, 255));
        overlayBadge.setShadowLayer(3f, 1f, 1f, Color.argb(180, 0, 0, 0));
        overlayBadge.setBackground(UIHelpers.round(Color.argb(140, 12, 19, 28), UIHelpers.dp(this, 6), Color.TRANSPARENT));
        overlayBadge.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 4), UIHelpers.dp(this, 8), UIHelpers.dp(this, 4));
        overlayBadge.setSingleLine(true);
        FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.START);
        badgeParams.leftMargin = UIHelpers.dp(this, 12);
        badgeParams.bottomMargin = UIHelpers.dp(this, 12);
        shell.addView(overlayBadge, badgeParams);
        overlayBadge.setVisibility(readerFullscreen ? View.VISIBLE : View.GONE);
        refreshReaderOverlayBadge();

        // Top Toolbar
        shell.addView(top, new FrameLayout.LayoutParams(-1, topBarHeight, Gravity.TOP));
        readerTopBar = top;

        // Bottom Bar
        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.VERTICAL);
        bottom.setClickable(true);
        bottom.setBackground(new GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                new int[]{0xF20C1420, 0xD80C1420}
        ));

        // Row 1: Prev Chapter | SeekBar | Next Chapter
        LinearLayout row1 = new LinearLayout(this);
        row1.setOrientation(LinearLayout.HORIZONTAL);
        row1.setGravity(Gravity.CENTER_VERTICAL);
        row1.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 2), UIHelpers.dp(this, 12), 0);

        TextView prevChapter = UIHelpers.text(this, "上一章", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        prevChapter.setGravity(Gravity.CENTER);
        prevChapter.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 6), UIHelpers.dp(this, 8), UIHelpers.dp(this, 6));
        boolean hasPrevChapter = readerChapterIndex > 0;
        boolean hasNextChapter = readerChapterIndex + 1 < detail.chapters.size();
        prevChapter.setEnabled(hasPrevChapter);
        prevChapter.setAlpha(hasPrevChapter ? 1f : 0.35f);
        prevChapter.setOnClickListener(v -> {
            if (readerChapterIndex > 0) switchChapter(detail, -1);
        });

        TextView nextChapter = UIHelpers.text(this, "下一章", 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        nextChapter.setGravity(Gravity.CENTER);
        nextChapter.setPadding(UIHelpers.dp(this, 8), UIHelpers.dp(this, 6), UIHelpers.dp(this, 8), UIHelpers.dp(this, 6));
        nextChapter.setEnabled(hasNextChapter);
        nextChapter.setAlpha(hasNextChapter ? 1f : 0.35f);
        nextChapter.setOnClickListener(v -> {
            if (readerChapterIndex + 1 < detail.chapters.size()) switchChapter(detail, 1);
        });

        SeekBar seekBar = new SeekBar(this);
        readerSeekBar = seekBar;
        seekBar.setMax(100);
        int initialPct = savedLoc != null ? Math.round(savedLoc.scrollPercentage * 100f) : 0;
        seekBar.setProgress(initialPct);
        seekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                if (fromUser) {
                    if (readingHabitTracker != null) {
                        readingHabitTracker.onUserAction();
                    }
                    textReader.scrollToPercent(progress / 100f);
                }
            }

            @Override
            public void onStartTrackingTouch(SeekBar sb) {
                readerSeeking = true;
            }

            @Override
            public void onStopTrackingTouch(SeekBar sb) {
                readerSeeking = false;
                textReader.scrollToPercent(sb.getProgress() / 100f);
            }
        });

        row1.addView(prevChapter);
        row1.addView(seekBar, new LinearLayout.LayoutParams(0, -2, 1));
        row1.addView(nextChapter);
        bottom.addView(row1, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 42)));

        // Row 2: 目录 ｜ 详情 ｜ 排版设置 ｜ 切换主题
        LinearLayout row2 = new LinearLayout(this);
        row2.setOrientation(LinearLayout.HORIZONTAL);
        row2.setGravity(Gravity.CENTER_VERTICAL);
        row2.setPadding(UIHelpers.dp(this, 16), 0, UIHelpers.dp(this, 16), UIHelpers.dp(this, 4));

        LinearLayout tocBtn = createBottomActionItem(R.drawable.ic_chapter_list, "目录", () -> showChapterDrawer(detail));
        LinearLayout detailBtn = createBottomActionItem(R.drawable.ic_detail, "详情", () -> {
            if (!TextUtils.isEmpty(activeDetailId)) {
                showDetailFromReader(activeDetailId, readerChapterIndex);
            } else {
                onBackPressed();
            }
        });
        LinearLayout settingsBtn = createBottomActionItem(R.drawable.ic_settings, "排版", () -> {
            com.xxcomic.ebook.TextReaderSettingsSheet.show(this, (fs, lh, th, paged) -> {
                textReader.setSettings(fs, lh, th, paged);
            });
        });
        LinearLayout themeBtn = createBottomActionItem(R.drawable.ic_moon, "主题", () -> {
            com.xxcomic.ebook.TextReaderSettingsSheet.Settings s =
                    com.xxcomic.ebook.TextReaderSettingsSheet.loadSettings(this);
            s.theme = (s.theme + 1) % 3;
            com.xxcomic.ebook.TextReaderSettingsSheet.saveSettings(this, s);
            textReader.setSettings(s.fontSizeSp, s.lineHeight, s.theme, s.pagedMode);
        });

        row2.addView(tocBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        row2.addView(detailBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        row2.addView(settingsBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        row2.addView(themeBtn, new LinearLayout.LayoutParams(0, -1, 1f));
        bottom.addView(row2, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 46)));

        FrameLayout.LayoutParams bottomParams = new FrameLayout.LayoutParams(-1, bottomBarHeight, Gravity.BOTTOM);
        shell.addView(bottom, bottomParams);
        readerBottomBar = bottom;

        setReaderFullscreen(readerFullscreen, false);
    }

    private void navigateReader(ComicModels.ComicDetail detail, ComicModels.ChapterPage page, int delta) {
        if (readingHabitTracker != null) {
            readingHabitTracker.onUserAction();
        }
        if (readerLayoutMode == 1 && readerPager != null && !page.imageUrls.isEmpty()) {
            int current = readerPager.currentPage();
            if (!ReaderNavigation.crossesChapter(current, page.imageUrls.size(), delta)) {
                readerPager.moveTo(current + delta);
                return;
            }
        }
        int next = readerChapterIndex + delta;
        if (next < 0 || next >= detail.chapters.size()) {
            showReaderBoundaryHint(delta > 0 ? "已经是最后一章" : "已经是第一章");
            return;
        }
        readerEntryChapterUrl = detail.chapters.get(next).url;
        readerEntryTarget = delta > 0 ? 1 : -1;
        switchChapter(detail, delta);
    }

    private void updateReaderButtons(ComicModels.ComicDetail detail, ComicModels.ChapterPage page) {
        if (readerPreviousButton == null || readerNextButton == null) return;
        boolean previous = readerChapterIndex > 0;
        boolean next = readerChapterIndex + 1 < detail.chapters.size();
        if (readerLayoutMode == 1) {
            previous = !page.imageUrls.isEmpty() && (previous || (readerPager != null && readerPager.currentPage() > 0));
            next = !page.imageUrls.isEmpty() && (next || (readerPager != null && readerPager.currentPage() + 1 < page.imageUrls.size()));
        }
        readerPreviousButton.setEnabled(previous);
        readerNextButton.setEnabled(next);
        readerPreviousButton.setAlpha(previous ? 1f : .35f);
        readerNextButton.setAlpha(next ? 1f : .35f);
    }

    private void recordPagedPosition(String key, int index, int count) {
        ReaderPosition position = readerImagePositions.get(key);
        if (position == null || position.imageIndex != index) position = new ReaderPosition(index, 0, index == count - 1);
        readerImagePositions.put(key, position);
        readerPositions.put(key, position.legacyProgress(count));
        main.removeCallbacks(persistReaderPositionRunnable);
        main.postDelayed(persistReaderPositionRunnable, READER_POSITION_SAVE_DELAY_MS);
    }

    private void captureReaderPosition() {
        if (readerList != null && (readerRestoringPosition == null || !readerRestoringPosition[0])) {
            saveReaderPosition(readerList, (String) readerList.getTag());
        }
        if (readerPager != null) {
            ComicModels.ComicDetail detail = details.get(activeDetailId);
            if (detail != null && readerChapterIndex >= 0 && readerChapterIndex < detail.chapters.size()) {
                ComicModels.Chapter chapter = detail.chapters.get(readerChapterIndex);
                ComicModels.ChapterPage page = chapters.get(chapter.url);
                if (page != null && !page.imageUrls.isEmpty()) recordPagedPosition(readerPositionKey(activeDetailId, chapter), readerPager.currentPage(), page.imageUrls.size());
            }
        }
    }

    private void releaseReaderViews() {
        captureReaderPosition();
        unregisterReaderBatteryReceiver();
        main.removeCallbacks(readerTimeUpdateRunnable);
        readerOverlayBadge = null;
        readerLoadedChapterUrls.clear();
        readerToolbarTitle = null;
        readerList = null;
        readerRestoringPosition = null;
        if (readerPager != null) readerPager.release();
        readerPager = null;
        if (textReaderView != null) {
            textReaderView.release();
            textReaderView = null;
        }
        readerPreviousButton = null;
        readerNextButton = null;
        readerContentView = null;
        readerSeekBar = null;
        readerSeeking = false;
        readerBitmapCache.evictAll();
        readerImageHeights.clear();
    }

    private int readerContainerHeight() {
        if (readerContentView != null && readerContentView.getParent() instanceof View) {
            int h = ((View) readerContentView.getParent()).getHeight();
            if (h > 0) return h;
        }
        return getResources().getDisplayMetrics().heightPixels;
    }

    private LinearLayout createBottomActionItem(int iconRes, String title, Runnable action) {
        LinearLayout item = new LinearLayout(this);
        item.setOrientation(LinearLayout.VERTICAL);
        item.setGravity(Gravity.CENTER);
        item.setClickable(true);
        item.setFocusable(true);
        UIHelpers.tapFeedback(item);
        item.setOnClickListener(v -> action.run());

        ImageView icon = UIHelpers.vectorIconButton(this, iconRes, UIHelpers.READER_TEXT, 0);
        item.addView(icon, new LinearLayout.LayoutParams(UIHelpers.dp(this, 20), UIHelpers.dp(this, 20)));

        TextView label = UIHelpers.text(this, title, 11, UIHelpers.READER_TEXT, Typeface.NORMAL);
        label.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        label.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams labelLp = new LinearLayout.LayoutParams(-2, -2);
        labelLp.topMargin = UIHelpers.dp(this, 2);
        item.addView(label, labelLp);

        return item;
    }

    private void setReaderFullscreen(boolean fullscreen, boolean animated) {
        readerFullscreen = fullscreen;
        if (readingHabitTracker != null) {
            readingHabitTracker.onOverlayVisibilityChanged(!fullscreen);
        }
        if (readerDisplayMode == 1) animated = false;
        updateReaderOverlayVisibility(animated);
        if (readerTopBar == null || readerBottomBar == null) return;

        int topHeight = readerTopBar.getHeight();
        if (topHeight <= 0) {
            topHeight = getStatusBarOrCutoutHeight() + UIHelpers.dp(this, 44);
        }
        int bottomHeight = readerBottomBar.getHeight();
        if (bottomHeight <= 0) {
            bottomHeight = UIHelpers.dp(this, 88);
        }

        int shellH = readerContainerHeight();
        float availableH = Math.max(1, shellH - topHeight - bottomHeight);
        float scale = Math.max(0.4f, Math.min(1f, availableH / (float) shellH));
        float targetTransY = (topHeight - bottomHeight) / 2f;

        if (!animated) {
            readerTopBar.animate().cancel();
            readerBottomBar.animate().cancel();
            if (readerProgressView != null) readerProgressView.animate().cancel();
            if (readerContentView != null) readerContentView.animate().cancel();

            readerTopBar.setAlpha(readerFullscreen ? 0f : 1f);
            readerTopBar.setTranslationY(readerFullscreen ? -topHeight : 0f);
            readerTopBar.setVisibility(readerFullscreen ? View.INVISIBLE : View.VISIBLE);

            readerBottomBar.setAlpha(readerFullscreen ? 0f : 1f);
            readerBottomBar.setTranslationY(readerFullscreen ? bottomHeight : 0f);
            readerBottomBar.setVisibility(readerFullscreen ? View.INVISIBLE : View.VISIBLE);

            if (readerContentView != null) {
                readerContentView.setScaleX(readerFullscreen ? 1f : scale);
                readerContentView.setScaleY(readerFullscreen ? 1f : scale);
                readerContentView.setTranslationY(readerFullscreen ? 0f : targetTransY);
            }

            if (readerProgressView != null) {
                readerProgressView.setAlpha(readerFullscreen ? 1f : 0f);
                readerProgressView.setVisibility(View.VISIBLE);
            }

            return;
        }

        long duration = READER_CHROME_ANIM_MS;
        android.view.animation.Interpolator interpolator = readerFullscreen
                ? new AccelerateInterpolator(1.6f)
                : new DecelerateInterpolator(1.6f);

        readerTopBar.animate().cancel();
        if (!readerFullscreen) {
            readerTopBar.setVisibility(View.VISIBLE);
        }
        readerTopBar.animate()
                .alpha(readerFullscreen ? 0f : 1f)
                .translationY(readerFullscreen ? -topHeight : 0f)
                .setDuration(duration)
                .setInterpolator(interpolator)
                .withLayer()
                .withEndAction(() -> {
                    if (readerFullscreen && readerTopBar != null) {
                        readerTopBar.setVisibility(View.INVISIBLE);
                    }
                })
                .start();

        readerBottomBar.animate().cancel();
        if (!readerFullscreen) {
            readerBottomBar.setVisibility(View.VISIBLE);
        }
        readerBottomBar.animate()
                .alpha(readerFullscreen ? 0f : 1f)
                .translationY(readerFullscreen ? bottomHeight : 0f)
                .setDuration(duration)
                .setInterpolator(interpolator)
                .withLayer()
                .withEndAction(() -> {
                    if (readerFullscreen && readerBottomBar != null) {
                        readerBottomBar.setVisibility(View.INVISIBLE);
                    }
                })
                .start();

        if (readerContentView != null) {
            readerContentView.animate().cancel();
            readerContentView.animate()
                    .scaleX(readerFullscreen ? 1f : scale)
                    .scaleY(readerFullscreen ? 1f : scale)
                    .translationY(readerFullscreen ? 0f : targetTransY)
                    .setDuration(duration)
                    .setInterpolator(interpolator)
                    .withLayer()
                    .start();
        }

        if (readerProgressView != null) {
            readerProgressView.animate().cancel();
            readerProgressView.setVisibility(View.VISIBLE);
            readerProgressView.animate()
                    .alpha(readerFullscreen ? 1f : 0f)
                    .setDuration(duration)
                    .setInterpolator(interpolator)
                    .withLayer()
                    .start();
        }

    }

    private void updateReaderOverlayVisibility(boolean animated) {
        final TextView badge = readerOverlayBadge;
        if (badge == null) return;
        badge.animate().cancel();
        if (readerFullyImmersive) {
            badge.setAlpha(0f);
            badge.setVisibility(View.GONE);
            return;
        }
        final boolean show = readerFullscreen;
        if (!animated) {
            badge.setAlpha(show ? 1f : 0f);
            badge.setVisibility(show ? View.VISIBLE : View.INVISIBLE);
            return;
        }
        if (show) badge.setVisibility(View.VISIBLE);
        badge.animate().alpha(show ? 1f : 0f)
                .setDuration(READER_CHROME_ANIM_MS)
                .setInterpolator(show ? new AccelerateInterpolator(1.6f) : new DecelerateInterpolator(1.6f))
                .withLayer()
                .withEndAction(() -> {
                    if (readerOverlayBadge != badge) return;
                    badge.setVisibility(readerFullyImmersive ? View.GONE
                            : readerFullscreen ? View.VISIBLE : View.INVISIBLE);
                }).start();
    }

    private int readerChromeBottomOffset() {
        return UIHelpers.dp(this, 36);
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
            showRemErrorToast(requestClient.name() + "暂不支持搜索");
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
                boolean verificationRequired = isVerificationRequired(error);
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
                    if (shouldOfferSourceVerification(requestSourceId, verificationRequired)) {
                        if (pullRefresh) finishSearchPullRefresh();
                        if (append || pullRefresh) {
                            searchAppendVerificationRequired = true;
                            searchAppendFailedGeneration = generation;
                            searchAppendFailedContent = searchResultsContent;
                            if (currentTab == 1 && searchResultsContent != null) {
                                renderSearchPagingFooter(searchResultsContent);
                            }
                        } else {
                            showVerificationRequired(requestSourceId);
                        }
                    } else if (pullRefresh) {
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
                || searchAppendVerificationRequired
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
        searchAppendVerificationRequired = false;
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
        globalSearchVerificationRequiredSourceIds.clear();
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
                boolean verificationRequired = false;
                try {
                    List<ComicModels.ComicSummary> got = client.search(query, 1);
                    if (got != null) partial = got;
                } catch (Exception e) {
                    failed = true;
                    verificationRequired = isVerificationRequired(e);
                }
                final List<ComicModels.ComicSummary> result = partial;
                final boolean isFailed = failed;
                final boolean needsVerification = verificationRequired;
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
                            if (shouldOfferSourceVerification(sourceId, needsVerification)) {
                                globalSearchVerificationRequiredSourceIds.add(sourceId);
                            } else {
                                globalSearchFailedSourceIds.add(sourceId);
                            }
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
        return 10L;
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
        if ("local".equals(sourceId) || "本地".equals(sourceId)) return "本地导入";
        if (sourceClient.id().equals(sourceId)) return sourceClient.name();
        if (mhua5Client.id().equals(sourceId)) return mhua5Client.name();
        if (mh160Client.id().equals(sourceId)) return mh160Client.name();
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
        if (liumanhuaClient.id().equals(sourceId)) return liumanhuaClient.name();
        if (copy4000Client.id().equals(sourceId)) return copy4000Client.name();
        if (manwaClient.id().equals(sourceId)) return manwaClient.name();
        for (ComicModels.Source item : customSources) {
            if (item.id.equals(sourceId)) return item.name;
        }
        return clean(sourceId, "未知来源");
    }

    private ComicSource selectedSource() {
        if (sourceClient.id().equals(selectedSourceId) && sourceEnabled) return sourceClient;
        if (mh160Client.id().equals(selectedSourceId) && mh160Enabled) return mh160Client;
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
        if (liumanhuaClient.id().equals(selectedSourceId) && liumanhuaEnabled) return liumanhuaClient;
        if (copy4000Client.id().equals(selectedSourceId) && copy4000Enabled) return copy4000Client;
        if (manwaClient.id().equals(selectedSourceId) && manwaEnabled) return manwaClient;
        List<ComicSource> enabled = enabledBuiltinSources();
        if (enabled.isEmpty()) return null;
        selectedSourceId = enabled.get(0).id();
        sourceCategoriesFailed = false;
        return enabled.get(0);
    }

    private List<ComicSource> enabledBuiltinSources() {
        List<ComicSource> sources = new ArrayList<>();
        if (sourceEnabled) sources.add(sourceClient);
        if (mh160Enabled) sources.add(mh160Client);
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
        if (liumanhuaEnabled) sources.add(liumanhuaClient);
        if (copy4000Enabled) sources.add(copy4000Client);
        if (manwaEnabled) sources.add(manwaClient);
        return SourceOrder.apply(sources, sourceOrder, ComicSource::id);
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
        if (comicId != null && comicId.startsWith(mh160Client.id() + ":")) return mh160Client;
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
        if (comicId != null && comicId.startsWith(liumanhuaClient.id() + ":")) return liumanhuaClient;
        if (comicId != null && comicId.startsWith(copy4000Client.id() + ":")) return copy4000Client;
        if (comicId != null && comicId.startsWith(manwaClient.id() + ":")) return manwaClient;
        return sourceClient;
    }

    private ComicSource sourceForDetail(ComicModels.ComicDetail detail) {
        if (detail == null || detail.summary == null) return sourceClient;
        if (isRetiredComic(detail.summary.comicId)) return mhua5Client;
        return sourceForId(detail.summary.sourceId);
    }

    private ComicSource sourceForId(String sourceId) {
        if (mhua5Client.id().equals(sourceId)) return mhua5Client;
        if (mh160Client.id().equals(sourceId)) return mh160Client;
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
        if (liumanhuaClient.id().equals(sourceId)) return liumanhuaClient;
        if (copy4000Client.id().equals(sourceId)) return copy4000Client;
        if (manwaClient.id().equals(sourceId)) return manwaClient;
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
                boolean verificationRequired = isVerificationRequired(error);
                main.post(() -> {
                    if (generation != categoryGeneration || !TextUtils.equals(sourceId, selectedSourceId)) return;
                    sourceCategoriesFailed = true;
                    if (shouldOfferSourceVerification(sourceId, verificationRequired)) {
                        showVerificationRequired(sourceId);
                    } else {
                        appendErrorLog("分类加载失败", error);
                        if (currentTab == 1) showTab(1, false);
                    }
                });
            }
        }));
    }

    private void showDetailThenRead(String id) {
        onUserOpenComicDetail(id);
        if (isLocalComic(id) && localLibraryReady) {
            LocalModels.Book book = localBookForReading(id);
            if (book != null && LocalModels.STATUS_READY.equals(book.status) && LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType)) {
                ComicModels.ComicDetail downloaded = downloadedDetail(book);
                if (downloaded == null) { showRemErrorToast("下载目录缺失，请到下载中心重试"); return; }
                readerLocalBookId = book.id;
                details.put(book.progressKey, downloaded); summaries.put(book.progressKey, downloaded.summary);
                showReader(downloaded, localReadIndex(book, downloaded)); return;
            }
        }
        if (isLocalComic(id)) {
            if (!localLibraryReady) {
                showRemSuccessToast("正在整理本地文件，稍等一下哦");
                return;
            }
            LocalModels.Book book = localBookForReading(id);
            if (book == null || !LocalModels.STATUS_READY.equals(book.status)) {
                showRemDialog(R.drawable.rem_empty, "漫画已移除", "该漫画已从本地书架删除", "确定", null);
                return;
            }
            List<LocalModels.Chapter> localChapters = getLocalLibraryStore().getChapters(book.id);
            List<ComicModels.Chapter> comicChapters = new ArrayList<>();
            for (LocalModels.Chapter lc : localChapters) {
                comicChapters.add(new ComicModels.Chapter(lc.id, lc.title, LocalContentResolver.buildChapterUrl(lc.id), 0, lc.orderIndex));
            }
            ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                    "local",
                    LocalModels.SOURCE_TYPE_FILE_DOWNLOAD.equals(book.sourceType)?book.progressKey:book.id,
                    book.getDisplayTitle(),
                    LocalContentResolver.buildCoverUrl(book.id),
                    "本地导入",
                    Collections.emptyList()
            );
            ComicModels.ComicDetail detail = new ComicModels.ComicDetail(
                    summary,
                    "本地",
                    "已完成",
                    "本地漫画 · " + book.format.toUpperCase(Locale.US),
                    "",
                    comicChapters
            );
            details.put(book.id, detail);
            summaries.put(book.id, summary);
            if(LocalModels.SOURCE_TYPE_FILE_DOWNLOAD.equals(book.sourceType)) {
                details.put(book.progressKey,detail);summaries.put(book.progressKey,summary);
            }
            showReader(detail, savedChapter(book.progressKey));
            return;
        }
        ComicModels.ComicDetail detail = details.get(id);
        if (detail != null) {
            ensureChaptersThen(detail, loaded -> showReader(loaded, savedChapter(id)));
            return;
        }
        openComicDetail(id);
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
        showTransientHint(hint, lp, 1800L);
    }

    private void dismissTransientHint() {
        if (transientHintDismiss != null) main.removeCallbacks(transientHintDismiss);
        if (root != null && activeTransientHint != null
                && activeTransientHint.getParent() == root) {
            root.removeView(activeTransientHint);
        }
        activeTransientHint = null;
        transientHintDismiss = null;
    }

    private void showTransientHint(View hint, FrameLayout.LayoutParams params, long durationMs) {
        if (root == null || hint == null) return;
        dismissTransientHint();
        activeTransientHint = hint;
        root.addView(hint, params);
        hint.setAlpha(0f);
        hint.setTranslationY(UIHelpers.dp(this, 6));
        hint.animate().alpha(1f).translationY(0f).setDuration(140L).start();
        transientHintDismiss = () -> {
            if (activeTransientHint != hint) return;
            hint.animate().alpha(0f).translationY(UIHelpers.dp(this, 4))
                    .setDuration(120L).withEndAction(() -> {
                        if (activeTransientHint == hint) dismissTransientHint();
                    }).start();
        };
        main.postDelayed(transientHintDismiss, durationMs);
    }

    private void normalizeChaptersOldestFirst(List<ComicModels.Chapter> chapters) {
        if (chapters == null || chapters.size() < 2) return;
        // CopyManga already supplies the group order; a final extra chapter may have a lower number.
        String firstUrl = chapters.get(0).url;
        if (firstUrl != null && firstUrl.startsWith(copy4000Config.baseUrl + "/comic/") && firstUrl.contains("/chapter/")) return;
        // Manwa supplies explicit sortId order, including bonus chapters with fractional positions.
        if (firstUrl != null && firstUrl.startsWith(manwaConfig.baseUrl + "/comic/")) return;
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

    private void ensureChaptersThen(ComicModels.ComicDetail detail, DetailAction action) {
        if (refreshingComicIds.contains(detail.summary.comicId)) {
            waitForComicRefresh(detail, action);
            return;
        }
        if (!detail.chapters.isEmpty()) {
            action.run(detail);
            return;
        }
        if (isLocalComic(detail.summary.comicId)) {
            List<LocalModels.Chapter> localChapters = getLocalLibraryStore().getChapters(detail.summary.comicId);
            List<ComicModels.Chapter> comicChapters = new ArrayList<>();
            for (LocalModels.Chapter lc : localChapters) {
                comicChapters.add(new ComicModels.Chapter(lc.id, lc.title, LocalContentResolver.buildChapterUrl(lc.id), 0, lc.orderIndex));
            }
            ComicModels.ComicDetail loaded = new ComicModels.ComicDetail(
                    detail.summary,
                    detail.author,
                    detail.status,
                    detail.description,
                    detail.latestChapter,
                    comicChapters);
            details.put(detail.summary.comicId, loaded);
            action.run(loaded);
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
                        showRemDialog(R.drawable.rem_empty, "暂无章节", "未找到该漫画的章节目录，可能暂无可用章节或站源暂未收录。", "重试", () -> ensureChaptersThen(detail, action), "取消", null);
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
                boolean verificationRequired = isVerificationRequired(error);
                main.post(() -> {
                    if (expectedCancellation || !isCurrentLoading(loadingGeneration)) return;
                    pageLoading = false;
                    pageLoadingBackAction = null;
                    if (shouldOfferSourceVerification(
                            detail.summary.sourceId, verificationRequired)) {
                        showVerificationRequired(detail.summary.sourceId);
                    } else {
                        appendErrorLog("目录加载失败", error);
                        showDetail(detail.summary.comicId);
                        showRemDialog(R.drawable.rem_error, "目录加载失败", clean(error.getMessage(), "请稍后重试。"),
                                "重试", () -> ensureChaptersThen(detail, action), "取消", null);
                    }
                });
            }
        }));
    }

    private void showChapterDrawer(ComicModels.ComicDetail detail) {
        if (detail == null) return;
        if (activeChapterSheet != null && activeChapterSheet.isShowing()) {
            activeChapterSheet.dismiss();
            activeChapterSheet = null;
        }

        int currentChapter;
        boolean hasCurrent;
        if (readerVisible) {
            currentChapter = readerChapterIndex;
            hasCurrent = true;
        } else {
            hasCurrent = lastViewedAt.containsKey(detail.summary.comicId) || progress.containsKey(detail.summary.comicId);
            currentChapter = Math.max(0, savedChapter(detail.summary.comicId));
        }

        ChapterDrawerSheet sheet = new ChapterDrawerSheet(this, detail.chapters,
                currentChapter, hasCurrent, readerVisible, chapterDesc, null,
                selectedChapter -> showReader(detail, selectedChapter));
        sheet.setOrderChangeListener(desc -> {
            chapterDesc = desc;
            saveLocalState();
        });
        sheet.setDismissListener(() -> {
            if (activeChapterSheet == sheet) activeChapterSheet = null;
            checkPendingUpdatePrompt();
        });
        activeChapterSheet = sheet;
        sheet.show();

        if (!detail.chapters.isEmpty()) {
            return;
        }

        sheet.showLoadingState("正在解析章节目录", "可以先关闭抽屉");
        track(detailIo.submit(() -> {
            try {
                List<ComicModels.Chapter> chapters = sourceForDetail(detail).chapters(detail.summary.comicId);
                if (chapters.isEmpty()) {
                    main.post(() -> {
                        if (activeChapterSheet != sheet || !sheet.isShowing()) return;
                        sheet.showErrorState("这里还没有章节", "重新加载", () -> showChapterDrawer(detail));
                    });
                    return;
                }
                normalizeChaptersOldestFirst(chapters);
                ComicModels.ComicDetail loaded = withChapters(detail, chapters);
                main.post(() -> {
                    if (activeChapterSheet != sheet || !sheet.isShowing()) return;
                    details.put(detail.summary.comicId, loaded);
                    persistComicCachesAsync();
                    sheet.updateChapters(loaded.chapters, currentChapter, hasCurrent);
                });
            } catch (Exception error) {
                boolean expectedCancellation = isExpectedTaskCancellation(error);
                boolean verificationRequired = isVerificationRequired(error);
                main.post(() -> {
                    if (expectedCancellation || activeChapterSheet != sheet || !sheet.isShowing()) return;
                    if (shouldOfferSourceVerification(detail.summary.sourceId, verificationRequired)) {
                        sheet.dismiss();
                        showVerificationRequired(detail.summary.sourceId);
                    } else {
                        appendErrorLog("目录解析失败", error);
                        sheet.showErrorState("目录解析失败", "重试", () -> showChapterDrawer(detail));
                    }
                });
            }
        }));
    }

    private void showFileVolumes(ComicModels.ComicDetail detail) {
        ComicSource source=sourceForId(detail.summary.sourceId);
        if(!(source instanceof com.xxcomic.source.FileSourceCapability))return;
        showRemSuccessToast("正在获取文件列表…");
        DownloadRuntime runtime=DownloadRuntime.get(this);
        runtime.io.execute(()->{
            try {
                List<com.xxcomic.source.FileResource> files=((com.xxcomic.source.FileSourceCapability)source).listFiles(detail.summary.comicId);
                runOnUiThread(()->{
                    if(activityDestroyed || readerVisible || !TextUtils.equals(activeDetailId,detail.summary.comicId))return;
                    if(files==null || files.isEmpty()){showRemErrorToast("暂无可下载文件");return;}
                    DownloadViews.fileSelection(this,detail,files,this::showLocalDetail,this::showDownloadCenter);
                });
            } catch(Exception error){runOnUiThread(()->{if(!activityDestroyed && TextUtils.equals(activeDetailId,detail.summary.comicId))showRemErrorToast("文件列表加载失败，点击重试");});}
        });
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
        boolean fileSource=sourceForId(detail.summary.sourceId) instanceof com.xxcomic.source.FileSourceCapability;
        if(fileSource) {
            title="下载后阅读";subtitle="选择文件或分卷";
            DownloadRuntime runtime=DownloadRuntime.get(this);
            for(com.xxcomic.download.DownloadModels.Task task:runtime.store.list()) {
                if(task.isFileTask && task.sourceId.equals(detail.summary.sourceId) && task.comicId.equals(detail.summary.comicId)) {
                    if(runtime.library.store.getBook(task.bookId)!=null){title="继续阅读";break;}
                    if(com.xxcomic.download.DownloadModels.active(task.state) || task.state==com.xxcomic.download.DownloadModels.State.QUEUED)title="正在下载";
                }
            }
        }
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
        button.setOnClickListener(v -> {
            if(fileSource)showFileVolumes(detail);
            else ensureChaptersThen(detail, loaded -> showReader(loaded,Math.min(savedChapter(loaded.summary.comicId), loaded.chapters.size() - 1)));
        });
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

    private void toggleFavorite(ComicModels.ComicDetail detail) {
        String id = detail.summary.comicId;
        String message;
        if (favorites.contains(id)) {
            favorites.remove(id);
            favoriteAt.remove(id);
            FavoriteUpdateCoordinator.getInstance().onFavoriteRemoved(id);
            updateFavoriteBadge(id, false);
            message = "已移出书架";
        } else {
            removeDuplicateFavorites(detail);
            favorites.remove(id);
            favorites.add(0, id);
            favoriteAt.put(id, System.currentTimeMillis());
            details.put(id, detail);
            summaries.put(id, detail.summary);
            persistComicCachesAsync();
            FavoriteUpdateCoordinator.getInstance().onFavoriteAdded(id, detail);
            if (!isRetiredComic(detail.summary.comicId)) loadImageToCache(detail.summary.coverUrl);
            message = "已放进书架";
        }
        saveLocalState();
        showDetail(id);
        main.post(() -> showRemSuccessToast(message));
    }

    private void deleteFavoriteWithUndo(String id) {
        int oldIndex = favorites.indexOf(id);
        Long oldFavoriteAt = favoriteAt.get(id);
        ComicModels.ComicSummary summary = summaries.get(id);
        String title = clean(summary == null ? "" : summary.title, "这本漫画");
        favorites.remove(id);
        favoriteAt.remove(id);
        FavoriteUpdateCoordinator.getInstance().onFavoriteRemoved(id);
        updateFavoriteBadge(id, false);
        saveLocalState();
        showTab(0);
        showFavoriteUndo(id, oldIndex, oldFavoriteAt, title);
    }

    private void showFavoriteUndo(String id, int oldIndex, Long oldFavoriteAt, String title) {
        showRemToast(R.drawable.rem_empty, "已移出《" + title + "》", "撤销", () -> {
            if (!favorites.contains(id)) {
                favorites.add(Math.max(0, Math.min(oldIndex, favorites.size())), id);
                favoriteAt.put(id, oldFavoriteAt == null ? System.currentTimeMillis() : oldFavoriteAt);
                FavoriteUpdateCoordinator.getInstance().onFavoriteAdded(id, details.get(id));
                saveLocalState();
            }
            showTab(0);
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
                FavoriteUpdateCoordinator.getInstance().onFavoriteRemoved(oldId);
                updateFavoriteBadge(oldId, false);
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
        fill.setBackgroundColor(readerDisplayMode == 1 ? Color.WHITE : UIHelpers.BRAND);
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
                } catch (Exception ignored) {
                } finally {
                    main.post(() -> readerPrefetching.remove(key));
                }
            });
        }
    }

    private void prefetchReaderImagesAround(List<String> imageUrls, int firstVisible, int visibleCount,
                                            String chapterUrl, int generation, String comicId, boolean cacheOnly) {
        if (generation != readerGeneration || !readerVisible || imageUrls == null || imageUrls.isEmpty()) return;
        int start = Math.max(0, firstVisible - 2);
        int end = Math.min(imageUrls.size(), firstVisible + visibleCount + READER_PREFETCH_COUNT);
        for (int i = start; i < end; i++) {
            String imageUrl = imageUrls.get(i);
            String key = chapterUrl + "\n" + imageUrl;
            if (TextUtils.isEmpty(imageUrl) || !readerPrefetching.add(key)) continue;
            submitReaderImage(readerPrefetchIo, () -> {
                try {
                    if (isCurrentReaderImageRequest(generation, comicId, chapterUrl)) {
                        ensureReaderImageCached(imageUrl, chapterUrl, cacheOnly);
                    }
                } catch (Exception ignored) {
                } finally {
                    main.post(() -> readerPrefetching.remove(key));
                }
            });
        }
    }

    private boolean ensureReaderImageCached(String imageUrl, String chapterUrl, boolean cacheOnly) throws IOException {
        if (LocalContentResolver.isLocalPageUrl(imageUrl)) {
            String pageId = LocalContentResolver.extractId(imageUrl, LocalContentResolver.PREFIX_PAGE);
            File materialized = getLocalContentResolver().materializePage(pageId);
            return materialized != null && materialized.exists() && materialized.length() > 0;
        }
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
            connection = (HttpURLConnection) new URL(GmhComicSource.migrateImageUrl(imageUrl)).openConnection();
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
                try (InputStream decoded = decodeSourceImage(imageUrl, stream)) {
                    writeReaderImageCache(cached, decoded);
                }
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
                Bitmap bitmap;
                if (LocalContentResolver.isLocalPageUrl(imageUrl)) {
                    bitmap = getLocalContentResolver().withPageFile(
                            LocalContentResolver.extractId(imageUrl, LocalContentResolver.PREFIX_PAGE),
                            file -> decodeReaderImage(file, readerContentWidth(), imageUrl));
                } else {
                    File cached = imageCacheFile(imageUrl);
                    long[] cachedIdentity = captureImageCacheIdentity(cached);
                    bitmap = cachedIdentity != null ? decodeReaderImage(cached, readerContentWidth(), imageUrl) : null;
                    if (bitmap == null) {
                        if (!LocalContentResolver.isLocalPageUrl(imageUrl)) {
                            deleteImageCacheIfUnchanged(cached, cachedIdentity);
                        }
                        if (!ensureReaderImageCached(imageUrl, chapterUrl, cacheOnly)) {
                            main.post(() -> {
                                if (activityDestroyed || !TextUtils.equals(imageUrl, (String) target.getTag())
                                        || !isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                                target.setImageResource(R.drawable.rem_error);
                                applyReaderImageDisplayMode(target);
                                target.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                            });
                            return;
                        }
                        bitmap = decodeReaderImage(cached, readerContentWidth(), imageUrl);
                    } else {
                        cached.setLastModified(System.currentTimeMillis());
                    }
                }
                if (bitmap == null) throw new IOException("Reader image decode failed: " + imageUrl);
                Bitmap loaded = bitmap;
                int targetHeight = Math.max(1, Math.round(readerContentWidth()
                        * loaded.getHeight() / (float) Math.max(1, loaded.getWidth())));
                readerBitmapCache.put(imageUrl, loaded);
                readerImageHeights.put(imageUrl, targetHeight);
                main.post(() -> {
                    if (activityDestroyed || !TextUtils.equals(imageUrl, (String) target.getTag())
                            || !isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                    ViewGroup.LayoutParams params = target.getLayoutParams();
                    if (list != null && params != null && params.height != targetHeight) {
                        params.height = targetHeight;
                        target.setLayoutParams(params);
                    }
                    target.setScaleType(ImageView.ScaleType.FIT_CENTER);
                    target.setImageBitmap(loaded);
                    if (readingHabitTracker != null) {
                        readingHabitTracker.onContentReadable();
                    }
                    applyReaderImageDisplayMode(target);
                    if (list != null && restoringPosition[0] && savedPosition < READER_POSITION_SCALE) {
                        list.post(() -> {
                            ReaderPosition exact = readerImagePositions.get((String) list.getTag());
                            int expected = exact == null ? ReaderPosition.fromLegacy(savedPosition, list.getCount()).imageIndex : exact.indexFor(list.getCount());
                            if (readerList == list && restoringPosition[0] && list.getFirstVisiblePosition() == expected
                                    && target == list.getChildAt(0) && TextUtils.equals(imageUrl, (String) target.getTag())
                                    && isCurrentReaderImageRequest(generation, comicId, chapterUrl)) {
                                restoreReaderPosition(list, savedPosition);
                                restoringPosition[0] = false;
                            }
                        });
                    }
                    if (list != null && restoringPosition[0] && savedPosition == READER_POSITION_SCALE) {
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
                main.post(() -> {
                    if (activityDestroyed || !TextUtils.equals(imageUrl, (String) target.getTag())
                            || !isCurrentReaderImageRequest(generation, comicId, chapterUrl)) return;
                    target.setImageResource(R.drawable.rem_error);
                    applyReaderImageDisplayMode(target);
                    target.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                });
            }
        });
    }

    private boolean isCurrentReaderImageRequest(int generation, String comicId, String chapterUrl) {
        if (generation != readerGeneration || !readerVisible || !TextUtils.equals(activeDetailId, comicId)) return false;
        ComicModels.ComicDetail detail = details.get(comicId);
        if (detail == null || readerChapterIndex < 0 || readerChapterIndex >= detail.chapters.size()) return false;
        if (TextUtils.equals(detail.chapters.get(readerChapterIndex).url, chapterUrl)) return true;
        return readerLoadedChapterUrls.contains(chapterUrl);
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

    private Bitmap restoreJmReaderImage(Bitmap bitmap, String url) {
        if (LocalContentResolver.isLocalPageUrl(url)) {
            LocalModels.Page page = getLocalLibraryStore().getPage(LocalContentResolver.extractId(url, LocalContentResolver.PREFIX_PAGE));
            url = page != null && page.transformation != null && page.transformation.startsWith("jm:")
                    ? page.transformation.substring(3) : "";
        }
        return JmImageTransform.restore(bitmap, url);
    }
    static int[][] jmSliceBounds(int height,int slices) { return JmImageTransform.jmSliceBounds(height,slices); }
    static int jmScrambleSlices(long aid,long scramble,String name) { return JmImageTransform.jmScrambleSlices(aid,scramble,name); }

    private int readerContentWidth() {
        return Math.max(1, getResources().getDisplayMetrics().widthPixels);
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
            if (LocalContentResolver.isLocalUrl(imageUrl)) {
                try {
                    Bitmap bitmap = null;
                    if (LocalContentResolver.isLocalCoverUrl(imageUrl)) {
                        String bookId = LocalContentResolver.extractId(imageUrl, LocalContentResolver.PREFIX_COVER);
                        bitmap = getLocalContentResolver().decodeCoverBitmap(bookId, UIHelpers.dp(this, 120), UIHelpers.dp(this, 160));
                    } else if (LocalContentResolver.isLocalPageUrl(imageUrl)) {
                        String pageId = LocalContentResolver.extractId(imageUrl, LocalContentResolver.PREFIX_PAGE);
                        bitmap = getLocalContentResolver().withPageFile(pageId,
                                file -> decodeReaderImage(file, readerContentWidth(), imageUrl));
                    }
                    if (bitmap != null) {
                        final Bitmap loaded = bitmap;
                        imageMemoryCache.put(imageUrl, loaded);
                        main.post(() -> target.setImageBitmap(loaded));
                        return;
                    }
                } catch (Exception ignored) {
                }
                main.post(() -> target.setImageResource(R.drawable.rem_no_image));
                return;
            }
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
                    byte[] bytes;
                    try (InputStream decoded = decodeSourceImage(imageUrl, stream)) {
                        bytes = readAllBytes(decoded);
                    }
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
                    try (InputStream decoded = decodeSourceImage(imageUrl, stream)) {
                        writeImageCache(cached, readAllBytes(decoded));
                    }
                }
                updateCacheSize();
            } catch (Exception ignored) {
            } finally {
                if (connection != null) connection.disconnect();
            }
        });
    }

    private InputStream decodeSourceImage(String imageUrl, InputStream stream) throws IOException {
        return ManwaImageDecoder.usesImageHost(imageUrl)
                ? ManwaImageDecoder.open(stream, manwaConfig.route("imageKey")) : stream;
    }

    private void applyImageHeaders(HttpURLConnection connection, String referer) {
        com.xxcomic.download.SourceImageFetcher.applyHeaders(connection, referer);
    }

    private String refererForImage(String imageUrl) {
        return refererForImage(imageUrl, "");
    }

    private String refererForImage(String imageUrl, String pageReferer) {
        if (isFiveUmImage(imageUrl)) {
            return TextUtils.isEmpty(pageReferer) ? manhuazhanConfig.referer : pageReferer;
        }
        if (imageUrl != null && (imageUrl.contains(mh160Config.domain)
                || imageUrl.contains("miyeye.cn") || imageUrl.contains("tgmhfc.uk"))) {
            return TextUtils.isEmpty(pageReferer) ? mh160Config.referer : pageReferer;
        }
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
        if (ManwaImageDecoder.usesImageHost(imageUrl)) {
            return TextUtils.isEmpty(pageReferer) ? manwaConfig.referer : pageReferer;
        }
        if (CopyMangaComicSource.usesImageHost(imageUrl)) {
            return TextUtils.isEmpty(pageReferer) ? copy4000Config.referer : pageReferer;
        }
        if (imageUrl != null && imageUrl.contains("s2.bzcdn.net")) {
            return TextUtils.isEmpty(pageReferer) ? liumanhuaConfig.referer : pageReferer;
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
            if (manwaClient.id().equals(selectedSourceId)) {
                for (ComicModels.FilterOption option : group.options) {
                    if (option.value.equals(selectedFilters.get(group.key))) {
                        selectedFilterLabels.put(group.key, option.label);
                        break;
                    }
                }
            }
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
            checkPendingUpdatePrompt();
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

    private List<String> enabledSourceNames() {
        List<String> names = new ArrayList<>();
        for (ComicSource source : enabledBuiltinSources()) names.add(source.name());
        return names;
    }

    private String selectedSourceName() {
        if (sourceClient.id().equals(selectedSourceId)) return sourceClient.name();
        if (mh160Client.id().equals(selectedSourceId)) return mh160Client.name();
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
        if (liumanhuaClient.id().equals(selectedSourceId)) return liumanhuaClient.name();
        if (copy4000Client.id().equals(selectedSourceId)) return copy4000Client.name();
        if (manwaClient.id().equals(selectedSourceId)) return manwaClient.name();
        for (ComicModels.Source item : customSources) {
            if (item.id.equals(selectedSourceId)) return item.name;
        }
        return "全部";
    }

    private String sourceIdForName(String name) {
        if (sourceClient.name().equals(name)) return sourceClient.id();
        if (mh160Client.name().equals(name)) return mh160Client.id();
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
        if (liumanhuaClient.name().equals(name)) return liumanhuaClient.id();
        if (copy4000Client.name().equals(name)) return copy4000Client.id();
        if (manwaClient.name().equals(name)) return manwaClient.id();
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
                if ((mh160Client.id().equals(selectedSourceId) || gmhClient.id().equals(selectedSourceId)
                        || mh18Client.id().equals(selectedSourceId)
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
        actions.addView(UIHelpers.divider(this));
        actions.addView(settingsSheetAction(R.drawable.ic_source, "恢复默认排序", () -> {
            popup[0].dismiss();
            resetSourceOrder();
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

    private View verificationRequiredState(String sourceId) {
        return remState(R.drawable.rem_error, sourceNameForId(sourceId) + "需要验证",
                "请先完成站点验证", "去验证", this::showSourceManagement);
    }

    private void showVerificationRequired(String sourceId) {
        pageLoading = false;
        pageLoadingBackAction = null;
        if (activePopup != null && activePopup.isShowing()) activePopup.dismiss();
        root.removeAllViews();
        root.addView(verificationRequiredState(sourceId), UIHelpers.match());
    }

    private void showReaderVerificationRequired(ComicModels.ComicDetail detail) {
        root.removeAllViews();
        readerVisible = true;
        applyReaderSystemBars();
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(readerDisplayMode == 1 ? Color.BLACK : UIHelpers.DARK);
        root.addView(shell, UIHelpers.match());
        int topHeight = UIHelpers.dp(this, 42);
        shell.addView(readerToolbar(detail), new LinearLayout.LayoutParams(-1, topHeight));
        shell.addView(readerState(R.drawable.rem_error,
                sourceNameForId(detail.summary.sourceId) + "需要验证",
                "请先完成站点验证", "去验证", this::showSourceManagement, false),
                new LinearLayout.LayoutParams(-1, 0, 1));
    }

    private boolean isVerificationRequired(Throwable error) {
        Throwable current = error;
        while (current != null) {
            if (current instanceof VerificationRequiredException) return true;
            current = current.getCause();
        }
        return false;
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
        if (localLibraryReady && isLocalComic(id)) {
            String chapterId = getSharedPreferences("xxcomic_local_locators", MODE_PRIVATE).getString(id, null);
            if (chapterId != null) {
                LocalModels.Chapter chapter = getLocalLibraryStore().getChapter(chapterId);
                return chapter == null ? 0 : chapter.orderIndex;
            }
        }
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
        readerImagePositions.put(positionKey, new ReaderPosition(firstVisible, offset, position == READER_POSITION_SCALE));
        readerPositions.put(positionKey, Math.max(0, Math.min(READER_POSITION_SCALE, position)));
        main.removeCallbacks(persistReaderPositionRunnable);
        main.postDelayed(persistReaderPositionRunnable, READER_POSITION_SAVE_DELAY_MS);
    }

    private void saveContinuousReaderPosition(ListView list, ContinuousReaderItem item) {
        View firstChild = list.getChildAt(0);
        if (firstChild == null || firstChild.getHeight() <= 0) return;
        double offset = Math.max(0d, Math.min(1d, -firstChild.getTop() / (double) firstChild.getHeight()));
        int position = (int) Math.round((item.pageIndex + offset) * READER_POSITION_SCALE / Math.max(1, item.pageCount));
        boolean atBottom = item.pageIndex == item.pageCount - 1 && offset >= 0.95;
        readerImagePositions.put(item.positionKey, new ReaderPosition(item.pageIndex, offset, atBottom));
        readerPositions.put(item.positionKey, Math.max(0, Math.min(READER_POSITION_SCALE, position)));
        main.removeCallbacks(persistReaderPositionRunnable);
        main.postDelayed(persistReaderPositionRunnable, READER_POSITION_SAVE_DELAY_MS);
    }

    private void restoreReaderPosition(ListView list, int savedPosition) {
        int count = list.getCount();
        if (count <= 0) return;
        // showReaderResumeHint(savedPosition); // disabled per user request
        if (savedPosition == READER_POSITION_SCALE) {
            list.setSelection(count - 1);
            list.post(() -> alignReaderBottom(list));
            return;
        }
        ReaderPosition exact = readerImagePositions.get((String) list.getTag());
        if (exact == null) exact = ReaderPosition.fromLegacy(savedPosition, count);
        int index = exact.indexFor(count);
        View first = list.getChildAt(0);
        // A decoded image may have new layout params before its next measurement.
        int rowHeight = first != null && list.getFirstVisiblePosition() == index
                ? Math.max(1, first.getLayoutParams().height) : Math.max(1, readerContentWidth() * 4 / 3);
        int top = -(int) Math.round(exact.offset * rowHeight) - list.getPaddingTop();
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
        for (String key : new ArrayList<>(readerImagePositions.keySet())) {
            if (key.startsWith(prefix)) readerImagePositions.remove(key);
        }
    }

    private void showToast(String message) {
        showRemToast(message);
    }

    private void showRemToast(String message) {
        showRemToast(R.drawable.rem_reader_boundary, message);
    }

    private void showRemToast(int imageRes, String message) {
        showRemToast(imageRes, message, "", null, 1600L);
    }

    private void showRemSuccessToast(String message) {
        showRemToast(R.drawable.rem_reader_resume, message);
    }

    private void showRemErrorToast(String message) {
        showRemToast(R.drawable.rem_error, message);
    }

    private void showRemToast(int imageRes, String message, String actionText,
                              Runnable action, long durationMs) {
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
        label.setMaxLines(2);
        label.setEllipsize(TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams labelLp = new LinearLayout.LayoutParams(0, -2, 1f);
        labelLp.leftMargin = UIHelpers.dp(this, 7);
        hint.addView(label, labelLp);
        if (!TextUtils.isEmpty(actionText) && action != null) {
            TextView actionView = UIHelpers.text(this, actionText, 12, UIHelpers.ACCENT, Typeface.BOLD);
            actionView.setGravity(Gravity.CENTER);
            actionView.setPadding(UIHelpers.dp(this, 10), 0, 0, 0);
            actionView.setOnClickListener(view -> {
                dismissTransientHint();
                action.run();
            });
            hint.addView(actionView, new LinearLayout.LayoutParams(-2, -1));
        }
        int width = Math.min(getResources().getDisplayMetrics().widthPixels
                - UIHelpers.dp(this, 32), UIHelpers.dp(this, 340));
        showTransientHint(hint, UIHelpers.frame(width, -2,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL, 0, 0, 0, UIHelpers.dp(this, 72)), durationMs);
    }

    private LinearLayout settingsScenePage(String scene, String title, String meta) {
        return settingsScenePage(scene, title, meta, null);
    }

    private LinearLayout settingsScenePage(String scene, String title, String meta, View trailing) {
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
        settingsHeader(page, title, meta, trailing);
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
        View menuBtn = cacheOverflowButton();
        LinearLayout page = settingsScenePage("cache", "缓存清理", cacheSize, menuBtn);
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
    }

    private View cacheOverflowButton() {
        TextView button = UIHelpers.text(this, "⋮", 24, UIHelpers.ACCENT, Typeface.BOLD);
        button.setGravity(Gravity.CENTER);
        button.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        button.setContentDescription("缓存更多操作");
        button.setOnClickListener(v -> showCacheMenu());
        return button;
    }

    private void showCacheMenu() {
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        final PopupWindow[] popup = new PopupWindow[1];
        actions.addView(settingsSheetAction(R.drawable.ic_trash, "清理全部缓存", () -> {
            popup[0].dismiss();
            confirmClearAppCache();
        }));
        actions.addView(UIHelpers.divider(this));
        actions.addView(settingsSheetAction(R.drawable.ic_auto, "重新计算大小", () -> {
            popup[0].dismiss();
            updateCacheSize();
            showRemSuccessToast("缓存大小已更新");
            main.postDelayed(this::showCacheCleanup, 200L);
        }));
        popup[0] = showSettingsSheet("缓存操作", actions);
    }

    private void confirmClearAppCache() {
        showRemDialog(R.drawable.rem_empty, "清理缓存", "将清理漫画图片与解析缓存，书架与阅读记录会始终保留。", "立即清理", () -> {
            showCacheCleanupLoading();
            main.post(this::clearAppCache);
        }, "取消", null);
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
        showRemDialog(R.drawable.rem_error, title, message, "知道了", null, null, null);
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
        pendingPromptRelease = null;
        AppUpdateChecker.getInstance().markSessionPromptDismissed();
        int generation = ++updateGeneration;
        showUpdateLoading();
        AppUpdateChecker.getInstance().triggerManualCheck(miscIo, UPDATE_METADATA_URL, IMAGE_USER_AGENT,
                new AppUpdateChecker.ManualCheckCallback() {
                    @Override
                    public void onManualCheckSuccess(AppRelease release) {
                        postMainIfAlive(() -> {
                            if (generation != updateGeneration) return;
                            updateRunning = false;
                            availableUpdateRelease = release;
                            if (release != null && release.hasNewVersion(BuildConfig.VERSION_CODE)) {
                                showUpdateAvailable(release);
                            } else {
                                showUpdateLatest();
                            }
                        });
                    }

                    @Override
                    public void onManualCheckFailure(Exception error) {
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
        String noteText = TextUtils.isEmpty(release.releaseNotes)
                ? "包含最新的界面优化与稳定性修复"
                : release.releaseNotes;
        TextView note = UIHelpers.text(this, noteText, 13, UIHelpers.TEXT2, Typeface.NORMAL);
        card.addView(note, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));
        page.addView(card);
        page.addView(settingsBottomActions("稍后", () -> showTab(2), "下载更新", () -> startUpdateDownload(release)));
    }

    private void showUpdateLatest() {
        LinearLayout page = settingsScenePage("update-latest", "版本更新", "当前 " + BuildConfig.VERSION_NAME);
        page.addView(remState(R.drawable.rem_reader_resume, "已经是最新版本", "XX Comic " + BuildConfig.VERSION_NAME, "", null));
    }

    private void showUpdateFailure() {
        LinearLayout page = settingsScenePage("update-error", "版本更新", "检查失败");
        page.addView(remState(R.drawable.rem_error, "没检查到新版本", "稍后再试", "重试", this::checkForUpdate));
    }

    private AppRelease fetchAppRelease() throws Exception {
        return AppUpdateChecker.fetchAppRelease(UPDATE_METADATA_URL, IMAGE_USER_AGENT);
    }

    private boolean isSourceEnabled(String sourceId) {
        if (TextUtils.isEmpty(sourceId)) return false;
        for (ComicSource s : enabledBuiltinSources()) {
            if (s.id().equals(sourceId)) return true;
        }
        return false;
    }

    private void triggerStartupChecks() {
        AppUpdateChecker.getInstance().triggerStartupCheck(miscIo, UPDATE_METADATA_URL, IMAGE_USER_AGENT,
                BuildConfig.VERSION_CODE, startupUpdateCallback);

        List<String> favoriteSnapshot = new ArrayList<>(favorites);
        FavoriteUpdateCoordinator.getInstance().startStartupCheck(favoriteSnapshot,
                new FavoriteUpdateCoordinator.SourceResolver() {
                    @Override
                    public ComicSource resolveSource(String comicId) {
                        return sourceForComicId(comicId);
                    }

                    @Override
                    public boolean isSourceAvailable(String comicId) {
                        if (isLocalComic(comicId)) return false;
                        if (isRetiredComic(comicId)) return false;
                        ComicSource src = sourceForComicId(comicId);
                        if (src == null) return false;
                        if (isRetiredSource(src.id())) return false;
                        return isSourceEnabled(src.id());
                    }
                }, details);
    }

    private void tryShowUpdatePrompt(AppRelease release) {
        if (release == null) return;
        pendingPromptRelease = release;
        checkPendingUpdatePrompt();
    }

    private void checkPendingUpdatePrompt() {
        if (isUpdatePromptIgnoredToday()) {
            pendingPromptRelease = null;
            return;
        }
        if (AppUpdateChecker.getInstance().isSessionPromptDismissed()) {
            pendingPromptRelease = null;
            return;
        }
        if (pendingPromptRelease == null) return;
        if (!canShowUpdateDialogNow()) return;
        final AppRelease release = pendingPromptRelease;
        pendingPromptRelease = null;
        activeUpdateDialog = RemUpdateDialog.show(this, release,
                installedVersionLabel(), formatBytes(release.size),
                (ignoreToday) -> {
                    activeUpdateDialog = null;
                    AppUpdateChecker.getInstance().markSessionPromptDismissed();
                    if (ignoreToday) markUpdatePromptIgnoredToday();
                    startUpdateDownload(release);
                },
                (ignoreToday) -> {
                    activeUpdateDialog = null;
                    AppUpdateChecker.getInstance().markSessionPromptDismissed();
                    if (ignoreToday) markUpdatePromptIgnoredToday();
                });
    }

    private boolean canShowUpdateDialogNow() {
        if (isUpdatePromptIgnoredToday()) return false;
        if (!activityResumed || !hasWindowFocus() || isFinishing() || isDestroyed()) return false;
        if (!verifyingProtectedSourceIds.isEmpty()) return false;
        if (AppUpdateChecker.getInstance().isSessionPromptDismissed()) return false;
        if (activeUpdateDialog != null && activeUpdateDialog.isShowing()) return false;
        if (activeRemDialog != null && activeRemDialog.isShowing()) return false;
        if (activePopup != null && activePopup.isShowing()) return false;
        if (readerVisible) return false;
        if (updateRunning) return false;
        if (sourceManagementVisible) return false;
        return true;
    }

    private boolean isUpdatePromptIgnoredToday() {
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(new Date());
        String savedDate = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(PREF_UPDATE_IGNORE_TODAY_DATE, "");
        return UpdatePromptPolicy.isIgnoredToday(savedDate, today);
    }

    private void markUpdatePromptIgnoredToday() {
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(new Date());
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .putString(PREF_UPDATE_IGNORE_TODAY_DATE, today)
                .apply();
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

    private AlertDialog showRemDialog(int imageRes, String title, String message,
                                       String positiveText, Runnable positiveAction) {
        return showRemDialog(imageRes, title, message, positiveText, positiveAction, null, null);
    }

    private AlertDialog showRemDialog(int imageRes, String title, String message,
                                      String positiveText, Runnable positiveAction,
                                      String negativeText, Runnable negativeAction) {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.HORIZONTAL);
        content.setGravity(Gravity.TOP);
        content.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16),
                UIHelpers.dp(this, 16), UIHelpers.dp(this, 10));

        ImageView art = new ImageView(this);
        art.setImageResource(imageRes);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        content.addView(art, new LinearLayout.LayoutParams(
                UIHelpers.dp(this, 56), UIHelpers.dp(this, 56)));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(this, 12), UIHelpers.dp(this, 2), 0, 0);
        TextView titleView = UIHelpers.text(this, title, 17, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(titleView);
        TextView messageView = UIHelpers.text(this, message, 13, UIHelpers.TEXT2, Typeface.NORMAL);
        messageView.setMaxLines(3);
        messageView.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(this, 5)));
        content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        AlertDialog.Builder builder = new AlertDialog.Builder(this).setView(content);
        if (!TextUtils.isEmpty(positiveText)) {
            builder.setPositiveButton(positiveText,
                    (dialog, which) -> { if (positiveAction != null) positiveAction.run(); });
        }
        if (!TextUtils.isEmpty(negativeText)) {
            builder.setNegativeButton(negativeText,
                    (dialog, which) -> { if (negativeAction != null) negativeAction.run(); });
        }
        AlertDialog dialog = builder.create();
        activeRemDialog = dialog;
        dialog.setOnDismissListener(d -> {
            if (activeRemDialog == dialog) {
                activeRemDialog = null;
            }
            checkPendingUpdatePrompt();
        });
        dialog.setOnShowListener(ignored -> {
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(UIHelpers.round(
                        UIHelpers.CARD, UIHelpers.dp(this, 8), Color.TRANSPARENT));
                int width = Math.min(getResources().getDisplayMetrics().widthPixels
                        - UIHelpers.dp(this, 40), UIHelpers.dp(this, 328));
                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            }
            android.widget.Button positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            if (positive != null) {
                positive.setTextColor(UIHelpers.ACCENT);
                positive.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
            android.widget.Button negative = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (negative != null) {
                negative.setTextColor(UIHelpers.TEXT3);
                negative.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
        });
        dialog.show();
        return dialog;
    }

    private void showErrorLogs() {
        String logs = errorLogText();
        activeErrorLog = "";
        String[] entries = TextUtils.isEmpty(logs) ? new String[0] : logs.split("\\n\\n");
        View menuBtn = errorLogsOverflowButton();
        LinearLayout page = settingsScenePage("errors", "错误日志", entries.length + " 条", menuBtn);
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
    }

    private View errorLogsOverflowButton() {
        TextView button = UIHelpers.text(this, "⋮", 24, UIHelpers.ACCENT, Typeface.BOLD);
        button.setGravity(Gravity.CENTER);
        button.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 8), Color.TRANSPARENT));
        button.setContentDescription("日志更多操作");
        button.setOnClickListener(v -> showErrorLogsMenu());
        return button;
    }

    private void showErrorLogsMenu() {
        String logs = errorLogText();
        boolean hasLogs = !TextUtils.isEmpty(logs);
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        final PopupWindow[] popup = new PopupWindow[1];
        actions.addView(settingsSheetAction(R.drawable.ic_auto, "导出全部日志", () -> {
            popup[0].dismiss();
            if (hasLogs) {
                exportErrorLogs();
            } else {
                showRemErrorToast("当前暂无错误日志可导出");
            }
        }));
        actions.addView(UIHelpers.divider(this));
        actions.addView(settingsSheetAction(R.drawable.ic_trash, "清空错误日志", () -> {
            popup[0].dismiss();
            if (hasLogs) {
                confirmClearErrorLogs();
            } else {
                showRemErrorToast("当前暂无错误日志可清空");
            }
        }));
        popup[0] = showSettingsSheet("日志操作", actions);
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
        showRemSuccessToast("日志已复制");
    }

    private void confirmClearErrorLogs() {
        showRemDialog(R.drawable.rem_empty, "清空错误日志", "所有本地错误记录都会移除。", "清空", this::clearErrorLogs, "取消", null);
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
        main.post(() -> showRemSuccessToast("错误日志已清理"));
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
                    showRemSuccessToast("站源配置已导入");
                    if (!categoriesFollowInitialList(selectedSourceId)) loadSourceCategories();
                    loadDefaultCategory();
                });
            } catch (Exception error) {
                main.post(() -> appendErrorLog("站源配置导入失败", error));
                postMainIfAlive(() -> showInfo("导入失败", clean(error.getMessage(), "配置文件格式不正确")));
            }
        });
    }

    private JSONObject sourceConfigJson() throws JSONException {
        JSONObject root = new JSONObject();
        root.put("schema", "xx-comic.sources");
        root.put("version", 2);
        root.put("exportedAt", System.currentTimeMillis());
        root.put("sourceOrder", new JSONArray(SourceOrder.normalize(sourceOrder, defaultSourceOrder())));
        JSONArray sources = new JSONArray();
        sources.put(baoziConfig.withEnabled(sourceEnabled).toJson());
        sources.put(mh160Config.withEnabled(mh160Enabled).toJson());
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
        sources.put(liumanhuaConfig.withEnabled(liumanhuaEnabled).toJson());
        sources.put(copy4000Config.withEnabled(copy4000Enabled).toJson());
        sources.put(manwaConfig.withEnabled(manwaEnabled).toJson());
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
                } else if (mh160Config.id.equals(id)) {
                    mh160Config = SourceConfig.fromJson(item, SourceConfig.mh160(true));
                    mh160Enabled = mh160Config.enabled;
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
                } else if (liumanhuaConfig.id.equals(id)) {
                    liumanhuaConfig = SourceConfig.fromJson(item, SourceConfig.liumanhua(true));
                    liumanhuaEnabled = liumanhuaConfig.enabled;
                } else if (copy4000Config.id.equals(id)) {
                    copy4000Config = SourceConfig.fromJson(item, SourceConfig.copy4000(true));
                    copy4000Enabled = copy4000Config.enabled;
                } else if (manwaConfig.id.equals(id)) {
                    manwaConfig = SourceConfig.fromJson(item, SourceConfig.manwa(true));
                    manwaEnabled = manwaConfig.enabled;
                }
            }
        }
        JSONArray importedOrder = root.optJSONArray("sourceOrder");
        if (importedOrder != null) saveSourceOrder(SourceOrder.decode(importedOrder.toString()));
        JSONArray builtins = root.optJSONArray("builtins");
        if (builtins != null) {
            for (int i = 0; i < builtins.length(); i++) {
                JSONObject item = builtins.getJSONObject(i);
                String id = item.optString("id");
                if (baoziConfig.id.equals(id)) sourceEnabled = item.optBoolean("enabled", true);
                if (mh160Config.id.equals(id)) mh160Enabled = item.optBoolean("enabled", true);
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
                if (liumanhuaConfig.id.equals(id)) liumanhuaEnabled = item.optBoolean("enabled", true);
                if (copy4000Config.id.equals(id)) copy4000Enabled = item.optBoolean("enabled", true);
                if (manwaConfig.id.equals(id)) manwaEnabled = item.optBoolean("enabled", true);
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
        if (!mh160Enabled) rows.add(mh160Config.name + "\u001f已关闭");
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
        if (!liumanhuaEnabled) rows.add(liumanhuaConfig.name + "\u001f已关闭");
        if (!copy4000Enabled) rows.add(copy4000Config.name + "\u001f已关闭");
        if (!manwaEnabled) rows.add(manwaConfig.name + "\u001f已关闭");
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
        mh160Client = new Mh160ComicSource(mh160Config.withEnabled(mh160Enabled));
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
        liumanhuaClient = new LiumanhuaComicSource(liumanhuaConfig.withEnabled(liumanhuaEnabled));
        copy4000Client = new CopyMangaComicSource(copy4000Config.withEnabled(copy4000Enabled));
        manwaClient = new ManwaComicSource(manwaConfig.withEnabled(manwaEnabled));
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
        mh160Enabled = prefs.getBoolean("source.mh160.enabled", true);
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
        liumanhuaEnabled = prefs.getBoolean("source.liumanhua.enabled", true);
        copy4000Enabled = prefs.getBoolean("source.copy4000.enabled", true);
        manwaEnabled = prefs.getBoolean("source.manwa.enabled", true);
        restoreSourceConfigs(prefs.getString("source.configs", ""));
        sourceOrder = SourceOrder.normalize(SourceOrder.decode(prefs.getString("source.order", "[]")), defaultSourceOrder());
        rebuildSourceClients();
        chapterDesc = prefs.getBoolean("chapter.desc", false);
        themeMode = prefs.getInt("theme.mode", 0);
        readerLeftHand = prefs.getBoolean("reader.left.hand", false);
        readerButtonMode = prefs.getBoolean("reader.button.mode", false);
        readerPageMode = Math.max(0, Math.min(2, prefs.getInt("reader.page.mode", readerButtonMode ? 1 : 0)));
        readerButtonMode = readerPageMode == 1;
        readerLayoutMode = prefs.getInt("reader.layout.mode", 0) == 1 ? 1 : 0;
        readerFullyImmersive = prefs.getBoolean("reader.fully.immersive", false);
        readerDisplayMode = prefs.getInt("reader.display.mode", 0) == 1 ? 1 : 0;
        readerPinchZoom = prefs.getBoolean("reader.pinch.zoom", true);
        readerDisablePageAnimation = prefs.getBoolean("reader.disable.page.animation", false);
        readerImagePositions.clear();
        try {
            JSONObject savedImages = new JSONObject(prefs.getString("reader.image.positions", "{}"));
            java.util.Iterator<String> imageKeys = savedImages.keys();
            while (imageKeys.hasNext()) {
                String key = imageKeys.next();
                JSONObject value = savedImages.optJSONObject(key);
                if (value != null) readerImagePositions.put(key, new ReaderPosition(value.optInt("index", 0), value.optDouble("offset", 0), value.optBoolean("end", false)));
            }
        } catch (JSONException ignored) { }
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
        FavoriteUpdateCoordinator.getInstance().init(prefs);
        FavoriteUpdateCoordinator.getInstance().pruneDeletedFavorites(favorites);
        updateCacheSize();
    }

    private void saveLocalState() {
        SharedPreferences.Editor editor = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        editor.putBoolean("source.baozi.enabled", sourceEnabled);
        editor.putBoolean("source.mh160.enabled", mh160Enabled);
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
        editor.putBoolean("source.liumanhua.enabled", liumanhuaEnabled);
        editor.putBoolean("source.copy4000.enabled", copy4000Enabled);
        editor.putBoolean("source.manwa.enabled", manwaEnabled);
        editor.putString("source.configs", encodeSourceConfigs());
        editor.putString("source.order", new JSONArray(sourceOrder).toString());
        editor.putBoolean("chapter.desc", chapterDesc);
        editor.putInt("theme.mode", themeMode);
        editor.putBoolean("reader.left.hand", readerLeftHand);
        editor.putBoolean("reader.button.mode", readerButtonMode);
        editor.putInt("reader.page.mode", readerPageMode);
        editor.putInt("reader.layout.mode", readerLayoutMode);
        editor.putBoolean("reader.fully.immersive", readerFullyImmersive);
        editor.putInt("reader.display.mode", readerDisplayMode);
        editor.putBoolean("reader.pinch.zoom", readerPinchZoom);
        editor.putBoolean("reader.disable.page.animation", readerDisablePageAnimation);
        JSONObject savedImages = new JSONObject();
        try {
            for (Map.Entry<String, ReaderPosition> item : readerImagePositions.entrySet()) {
                ReaderPosition value = item.getValue();
                savedImages.put(item.getKey(), new JSONObject().put("index", value.imageIndex).put("offset", value.offset).put("end", value.atEnd));
            }
        } catch (JSONException ignored) { }
        editor.putString("reader.image.positions", savedImages.toString());
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
            mh160Config = SourceConfig.mh160(mh160Enabled);
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
            liumanhuaConfig = SourceConfig.liumanhua(liumanhuaEnabled);
            copy4000Config = SourceConfig.copy4000(copy4000Enabled);
            manwaConfig = SourceConfig.manwa(manwaEnabled);
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
                } else if (SourceConfig.mh160(true).id.equals(id)) {
                    mh160Config = SourceConfig.fromJson(item, SourceConfig.mh160(mh160Enabled));
                    mh160Enabled = mh160Config.enabled;
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
                } else if (SourceConfig.liumanhua(true).id.equals(id)) {
                    liumanhuaConfig = SourceConfig.fromJson(item, SourceConfig.liumanhua(liumanhuaEnabled));
                    liumanhuaEnabled = liumanhuaConfig.enabled;
                } else if (SourceConfig.copy4000(true).id.equals(id)) {
                    copy4000Config = SourceConfig.fromJson(item, SourceConfig.copy4000(copy4000Enabled));
                    copy4000Enabled = copy4000Config.enabled;
                } else if (SourceConfig.manwa(true).id.equals(id)) {
                    manwaConfig = SourceConfig.fromJson(item, SourceConfig.manwa(manwaEnabled));
                    manwaEnabled = manwaConfig.enabled;
                }
            }
        } catch (JSONException ignored) {
            baoziConfig = SourceConfig.baozi(sourceEnabled);
            mh160Config = SourceConfig.mh160(mh160Enabled);
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
            liumanhuaConfig = SourceConfig.liumanhua(liumanhuaEnabled);
            copy4000Config = SourceConfig.copy4000(copy4000Enabled);
            manwaConfig = SourceConfig.manwa(manwaEnabled);
        }
    }

    private String encodeSourceConfigs() {
        try {
            JSONArray array = new JSONArray();
            array.put(baoziConfig.withEnabled(sourceEnabled).toJson());
            array.put(mh160Config.withEnabled(mh160Enabled).toJson());
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
            array.put(liumanhuaConfig.withEnabled(liumanhuaEnabled).toJson());
            array.put(copy4000Config.withEnabled(copy4000Enabled).toJson());
            array.put(manwaConfig.withEnabled(manwaEnabled).toJson());
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
                showRemDialog(R.drawable.rem_empty, "清空阅读历史", "将清除所有阅读进度记录，收藏不会受影响。", "清空", () -> {
                    progress.clear();
                    readerPositions.clear();
                    readerImagePositions.clear();
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
            List<Map.Entry<String, Long>> entries = new ArrayList<>();
            for (Map.Entry<String, Long> entry : lastViewedAt.entrySet()) {
                if (entry != null && entry.getKey() != null) {
                    entries.add(entry);
                }
            }
            Collections.sort(entries, (a, b) -> {
                long va = a.getValue() == null ? 0L : a.getValue();
                long vb = b.getValue() == null ? 0L : b.getValue();
                return Long.compare(vb, va);
            });
            LinearLayout list = settingsList();
            int visible = 0;
            for (Map.Entry<String, Long> entry : entries) {
                if (!progress.containsKey(entry.getKey())) continue;
                try {
                    View row = historyRow(entry.getKey(), entry.getValue() == null ? 0L : entry.getValue());
                    if (row != null) {
                        if (visible++ > 0) list.addView(UIHelpers.divider(this));
                        list.addView(row);
                    }
                } catch (Exception e) {
                    appendErrorLog("渲染历史记录失败: " + entry.getKey(), e);
                }
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
        if (summary == null && isLocalComic(comicId)) {
            LocalModels.Book localBook = localBookForReading(comicId);
            if (localBook != null) {
                summary = new ComicModels.ComicSummary(
                        "local",
                        localBook.id,
                        localBook.getDisplayTitle(),
                        LocalContentResolver.buildCoverUrl(localBook.id),
                        "本地导入",
                        Collections.emptyList()
                );
                summaries.put(comicId, summary);
            }
        }
        final ComicModels.ComicSummary resolvedSummary = summary;
        boolean orphaned = resolvedSummary == null;
        FrameLayout coverWrap = new FrameLayout(this);
        View cover;
        if (orphaned) {
            cover = UIHelpers.coverPlaceholder(this, "");
        } else if (!TextUtils.isEmpty(resolvedSummary.coverUrl)) {
            cover = coverFrame(resolvedSummary.coverUrl, 32, 43, isRetiredComic(comicId));
        } else {
            cover = UIHelpers.coverPlaceholder(this, resolvedSummary.title);
        }
        coverWrap.addView(cover, new FrameLayout.LayoutParams(UIHelpers.dp(this, 32), UIHelpers.dp(this, 43)));
        row.addView(coverWrap, new LinearLayout.LayoutParams(UIHelpers.dp(this, 32), UIHelpers.dp(this, 43)));

        LinearLayout info = new LinearLayout(this);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(this, 8), 0, UIHelpers.dp(this, 8), 0);
        TextView titleView = new TextView(this);
        if (orphaned) {
            String titleText = "已清除的漫画";
            if (isLocalComic(comicId)) {
                LocalLibraryStore.DeletedFingerprint df = getLocalLibraryStore().findDeletedByProgressKey(comicId);
                if (df != null && !TextUtils.isEmpty(df.userTitle)) {
                    titleText = df.userTitle + " [已移除]";
                } else {
                    titleText = "本地漫画 [已移除]";
                }
            }
            titleView.setText(titleText);
        } else {
            titleView.setText(resolvedSummary.title);
        }
        titleView.setTextSize(14);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        titleView.setTextColor(orphaned ? UIHelpers.TEXT3 : UIHelpers.TEXT);
        titleView.setMaxLines(1);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        info.addView(titleView);
        List<String> chapterTitles = null;
        if (detail != null && detail.chapters != null) {
            chapterTitles = new ArrayList<>();
            for (ComicModels.Chapter chapter : detail.chapters) {
                chapterTitles.add(chapter != null ? chapter.title : "");
            }
        } else if (isLocalComic(comicId)) {
            LocalModels.Book localBook = localBookForReading(comicId);
            if (localBook != null) {
                List<LocalModels.Chapter> localChapters = getLocalLibraryStore().getChapters(localBook.id);
                if (localChapters != null && !localChapters.isEmpty()) {
                    chapterTitles = new ArrayList<>();
                    for (LocalModels.Chapter lc : localChapters) {
                        chapterTitles.add(lc != null ? lc.title : "");
                    }
                }
            }
        }
        int chapterIdx = progress.containsKey(comicId) ? progress.get(comicId) : -1;
        String chapterText = HistoryProgressLabel.label(chapterIdx, chapterTitles);
        info.addView(UIHelpers.text(this, chapterText + " · " + DataHelpers.formatRelative(viewedAt), 11, UIHelpers.TEXT3, Typeface.NORMAL),
                UIHelpers.marginTop(-1, UIHelpers.dp(this, 2)));
        row.addView(info, UIHelpers.weight(1));

        final String historyTitle = orphaned ? "这条记录" : resolvedSummary.title;
        ImageView close = new ImageView(this);
        close.setImageResource(R.drawable.ic_trash);
        close.setImageTintList(android.content.res.ColorStateList.valueOf(UIHelpers.TEXT3));
        close.setPadding(UIHelpers.dp(this, 7), UIHelpers.dp(this, 7), UIHelpers.dp(this, 7), UIHelpers.dp(this, 7));
        close.setOnClickListener(v -> {
            showRemDialog(R.drawable.rem_empty, "删除这条记录？", "只移除《" + historyTitle + "》的阅读位置，书架收藏保持不变。", "删除", () -> {
                progress.remove(comicId);
                removeReaderPositions(comicId);
                lastViewedAt.remove(comicId);
                saveLocalState();
                if (isLocalComic(comicId)) {
                    getLocalLibraryStore().removeDeletedFingerprintByProgressKey(comicId);
                }
                showHistory();
            }, "取消", null);
        });
        row.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(this, 30), UIHelpers.dp(this, 30)));

        if (!orphaned) {
            row.setOnClickListener(v -> openComicDetail(comicId));
        } else if (isLocalComic(comicId)) {
            row.setOnClickListener(v -> showRemDialog(R.drawable.rem_empty, "作品已移除", "该漫画已从本地书架移除。如需继续阅读，请重新导入原文件。", "确定", null));
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
        localLibraryIo.submit(() -> {
            getLocalStorageManager().clearDerivedPagesCache();
            main.post(() -> {
                if (!activityDestroyed) showRemSuccessToast("缓存已清理，收藏与本地漫画已保留");
            });
        });
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
