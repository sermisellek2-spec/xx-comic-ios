package com.xxcomic;

import android.app.Activity;
import android.app.AlertDialog;
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
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.xxcomic.source.BaoziComicSource;
import com.xxcomic.source.AikanComicSource;
import com.xxcomic.source.ComicModels;
import com.xxcomic.source.ComicSource;
import com.xxcomic.source.GmhComicSource;
import com.xxcomic.source.Mhua5ComicSource;
import com.xxcomic.source.SourceConfig;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
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
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

public class MainActivity extends Activity {
    private static final String PREFS_NAME = "xx-comic";
    private static final String ALL_TAG = "全部";
    private static final int DETAIL_HERO_DP = 128;
    private static final int CHAPTER_DRAWER_BATCH_SIZE = 40;
    private static final long READER_PROGRESS_ANIM_MS = 30L;
    private static final String SUMMARIES_CACHE_KEY = "cache.summaries";
    private static final String DETAILS_CACHE_KEY = "cache.details";
    private static final String CHAPTERS_CACHE_KEY = "cache.chapters";
    private static final String ERROR_LOGS_KEY = "error.logs";
    private static final int ERROR_LOG_MAX_CHARS = 60000;
    private static final int IMPORT_SOURCES_REQUEST = 1001;
    private static final int EXPORT_SOURCES_REQUEST = 1002;
    private static final int EXPORT_LOGS_REQUEST = 1003;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newFixedThreadPool(4);
    private ComicSource sourceClient;
    private ComicSource mhua5Client;
    private ComicSource aikanClient;
    private ComicSource gmhClient;
    private SourceConfig baoziConfig = SourceConfig.baozi(true);
    private SourceConfig mhua5Config = SourceConfig.mhua5(true);
    private SourceConfig aikanConfig = SourceConfig.aikan(true);
    private SourceConfig gmhConfig = SourceConfig.gmh(true);
    private final List<ComicModels.ComicSummary> searchResults = new ArrayList<>();
    private final List<ComicModels.ComicSummary> globalSearchResults = new ArrayList<>();
    private final List<String> globalSearchHistory = new ArrayList<>();
    private final Map<String, ComicModels.ComicSummary> summaries = new LinkedHashMap<>();
    private final Map<String, ComicModels.ComicDetail> details = new HashMap<>();
    private final Map<String, ComicModels.ChapterPage> chapters = new HashMap<>();
    private final List<String> favorites = new ArrayList<>();
    private final List<String> sourceCategories = new ArrayList<>();
    private final List<AppModels.Source> customSources = new ArrayList<>();
    private final Map<String, Integer> progress = new HashMap<>();
    private final Map<String, Long> lastViewedAt = new HashMap<>();

    private FrameLayout root;
    private int currentTab = 1;
    private String searchQuery = "";
    private String favoriteQuery = "";
    private String globalSearchQuery = "";
    private String selectedSourceId = "baozimh";
    private String selectedRegion = "all";
    private String selectedState = "all";
    private boolean sourceEnabled = true;
    private boolean mhua5Enabled = true;
    private boolean aikanEnabled = true;
    private boolean gmhEnabled = true;
    private boolean chapterDesc = true;
    private int themeMode = 0;
    private String cacheSize = "42.6 MB";
    private int searchGeneration = 0;
    private int readerChapterIndex = 0;
    private String activeDetailId = "";
    private boolean readerVisible = false;
    private boolean readerFullscreen = false;
    private boolean searchLoading = false;
    private boolean searchAppending = false;
    private boolean searchHasMore = true;
    private int searchPage = 1;
    private boolean standaloneSearchVisible = false;
    private boolean standaloneSearchResultsMode = false;
    private boolean globalSearchLoading = false;
    private boolean pageLoading = false;
    private int pageLoadingReturnTab = 0;
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
    private final Set<String> globalSearchShownIds = new HashSet<>();  // 已显示 comicId 去重
    private int globalSearchTotalSources;          // 本次搜索总站源数
    private int globalSearchCompletedSources;      // 已完成站源数（含失败）
    private int globalSearchFailedSources;         // 失败站源数
    private TextView globalSearchStatusView;       // 底部状态文字
    private View globalSearchLoadingView;          // loading 态视图引用（首个结果到来时移除）
    private String pendingExportJson = "";
    private String pendingLogText = "";
    private PopupWindow activePopup;
    private ScrollView searchScroll;
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
        loadDefaultCategory();
        loadSourceCategories();
    }

    @Override
    protected void onResume() {
        super.onResume();
        boolean themeChanged = refreshThemeIfChanged();
        scheduleThemeSwitch();
        if (themeChanged && root != null) rerenderCurrentScreen();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        main.removeCallbacks(themeSwitchRunnable);
        io.shutdownNow();
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
            pageLoading = false;
            pageLoadingGeneration++;
            if (!TextUtils.isEmpty(activeDetailId)) showDetail(activeDetailId); else showTab(pageLoadingReturnTab);
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
        if (standaloneSearchVisible) {
            if (standaloneSearchResultsMode) {
                showStandaloneSearch(false);
            } else {
                standaloneSearchVisible = false;
                standaloneSearchResultsMode = false;
                showTab(0);
            }
            return true;
        }
        if (readerVisible && !TextUtils.isEmpty(activeDetailId)) {
            showDetail(activeDetailId);
            return true;
        }
        if (!TextUtils.isEmpty(activeDetailId)) {
            activeDetailId = "";
            showTab(currentTab);
            return true;
        }
        return false;
    }

    private void applyThemeAndSystemBars() {
        nightThemeApplied = themeMode == 1 ? UIHelpers.applyTheme(false)
                : themeMode == 2 ? UIHelpers.applyTheme(true)
                : UIHelpers.applyAutoTheme();
        getWindow().setStatusBarColor(UIHelpers.BG);
        getWindow().setNavigationBarColor(UIHelpers.BG);
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

    private void showTab(int tab) {
        applyThemeAndSystemBars();
        currentTab = tab;
        activeDetailId = "";
        readerVisible = false;
        root.removeAllViews();
        FrameLayout shell = new FrameLayout(this);
        shell.setBackgroundColor(UIHelpers.BG);
        root.addView(shell, UIHelpers.match());

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(UIHelpers.dp(this, 18), UIHelpers.dp(this, 16), UIHelpers.dp(this, 18), UIHelpers.dp(this, 96));

        // 站源页内容较多，用 ScrollView 包裹以支持滚动
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
        if (tab == 2) renderSources(page);
        if (tab == 3) renderProfile(page);
        shell.addView(makeBottomNav(), UIHelpers.frame(-1, UIHelpers.dp(this, 78), Gravity.BOTTOM, 0, 0, 0, 0));
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
        page.addView(sectionText("搜索来源 · 已启用的站源"));
        page.addView(sourceDropdown());
        page.addView(searchTagGrid(searchTags()));
        page.addView(sectionTitle("搜索结果"));

        ScrollView scroll = new ScrollView(this);
        searchScroll = scroll;
        tuneScroll(scroll);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
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
            content.addView(emptyState("当前没有启用站源", "请先到站源页启用漫画来源。", "去启用", () -> showTab(2)));
            return;
        }
        if (searchResults.isEmpty()) {
            if (searchLoading) {
                content.addView(loadingState("正在加载", "请稍等，正在获取漫画内容。"));
                return;
            }
            content.addView(emptyState("暂无搜索结果", "按键盘搜索，或点上方分类浏览。", "重新加载", () -> {
                if (TextUtils.isEmpty(searchQuery.trim())) loadDefaultCategory(); else runSearch(searchQuery.trim());
            }));
            return;
        }

        List<ComicModels.ComicSummary> visible = filterResults();
        if (visible.isEmpty()) {
            content.addView(emptyState("没有找到相关漫画", "换个关键词或清空题材筛选再试。", "清空筛选", () -> {
                selectedRegion = "all";
                selectedState = "all";
                showTab(1);
            }));
            return;
        }
        for (int i = 0; i < visible.size(); i += 2) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.addView(resultCard(visible.get(i)), UIHelpers.weight(1));
            if (i + 1 < visible.size()) {
                row.addView(UIHelpers.space(this, UIHelpers.dp(this, 12), 1));
                row.addView(resultCard(visible.get(i + 1)), UIHelpers.weight(1));
            }
            content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 14)));
        }
        if (searchAppending) {
            content.addView(loadingMoreView(), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 16)));
        } else if (!searchHasMore) {
            TextView end = UIHelpers.text(this, "已经到底了", 12, UIHelpers.TEXT3, Typeface.NORMAL);
            end.setGravity(Gravity.CENTER);
            content.addView(end, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 16)));
        }
    }

    private void renderFavorites(LinearLayout page) {
        addTitle(page, "我的收藏", String.valueOf(favorites.size()));
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
            content.addView(emptyState("还没有收藏的漫画", "去搜索页发现漫画，收藏后会出现在这里。", "去搜索", () -> showTab(1)));
            return;
        }
        for (String id : filterFavorites()) {
            content.addView(favoriteRow(id));
        }
    }

    private void renderSources(LinearLayout page) {
        addTitle(page, "站源管理", null);
        TextView add = UIHelpers.pill(this, "+ 添加", UIHelpers.ACCENT_LIGHT, UIHelpers.ACCENT_DARK);
        add.setOnClickListener(v -> showAddSourceDialog());
        page.addView(add, UIHelpers.marginBottom(-1, UIHelpers.dp(this, 10)));
        add.setVisibility(View.GONE);
        page.addView(sourceCard(baoziConfig.name, baoziConfig.domain, sourceEnabled, () -> {
            sourceEnabled = !sourceEnabled;
            baoziConfig = baoziConfig.withEnabled(sourceEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        page.addView(sourceCard(mhua5Config.name, mhua5Config.domain, mhua5Enabled, () -> {
            mhua5Enabled = !mhua5Enabled;
            mhua5Config = mhua5Config.withEnabled(mhua5Enabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        page.addView(sourceCard(aikanConfig.name, aikanConfig.domain, aikanEnabled, () -> {
            aikanEnabled = !aikanEnabled;
            aikanConfig = aikanConfig.withEnabled(aikanEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        page.addView(sourceCard(gmhConfig.name, gmhConfig.domain, gmhEnabled, () -> {
            gmhEnabled = !gmhEnabled;
            gmhConfig = gmhConfig.withEnabled(gmhEnabled);
            rebuildSourceClients();
            saveLocalState();
            showTab(2);
        }));
        for (AppModels.Source item : customSources) {
            page.addView(sourceCard(item.name, item.url, item.enabled, () -> {
                item.enabled = !item.enabled;
                saveLocalState();
                showTab(2);
            }));
        }
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

    private void renderProfile(LinearLayout page) {
        addTitle(page, "我的", null);
        LinearLayout group = UIHelpers.card(this);
        group.addView(menuItem("主题模式", themeModeLabel(), () -> cycleThemeMode()));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItem("缓存清理", cacheSize, () -> {
            clearAppCache();
        }));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItem("错误日志", errorLogSummary(), () -> showErrorLogs()));
        group.addView(UIHelpers.divider(this));
        group.addView(menuItem("关于 App", "1.0.1", () -> showInfo("关于 App", "XX Comic 已接入包子漫画、漫画屋的搜索、详情、阅读图片和本地缓存。")));
        page.addView(group);
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
        standaloneSearchVisible = true;
        standaloneSearchResultsMode = resultsMode;
        root.removeAllViews();
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(UIHelpers.BG);
        root.addView(shell, UIHelpers.match());

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(UIHelpers.dp(this, 18), UIHelpers.dp(this, 12), UIHelpers.dp(this, 18), UIHelpers.dp(this, 10));
        top.setBackgroundColor(UIHelpers.BG);
        TextView back = UIHelpers.text(this, "‹", 30, UIHelpers.TEXT, Typeface.BOLD);
        back.setGravity(Gravity.CENTER);
        back.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(this, 20), UIHelpers.BORDER_SOFT));
        back.setOnClickListener(v -> {
            standaloneSearchVisible = false;
            standaloneSearchResultsMode = false;
            showTab(0);
        });
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
            // 历史页：清空结果容器引用，避免增量 addView 写错地方
            globalSearchContent = null;
            globalSearchStatusView = null;
            renderSearchHistory(content);
            return;
        }
        // 保存结果容器引用，供流式增量 addView 使用
        globalSearchContent = content;
        renderGlobalSearchResults(content);
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
            content.addView(emptyState("暂无搜索记录", "输入关键词后按键盘搜索。", "", () -> {}));
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
        // loading 且无结果：显示 loading 动画
        if (globalSearchLoading && globalSearchResults.isEmpty()) {
            globalSearchLoadingView = loadingState("正在搜索", "正在并发搜索所有开启站源。");
            content.addView(globalSearchLoadingView);
            ensureStatusView(content);
            return;
        }
        // 非 loading 且无结果：空状态
        if (!globalSearchLoading && globalSearchResults.isEmpty()) {
            content.addView(emptyState("没有找到相关漫画", "换个关键词再试。", "返回搜索", () -> showStandaloneSearch(false)));
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
        row.setOnClickListener(v -> {
            standaloneSearchVisible = false;
            standaloneSearchResultsMode = false;
            showDetail(item.comicId);
        });
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
        item.setOnClickListener(v -> showDetail(comic.comicId));
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

    private LinearLayout favoriteRow(String id) {
        ComicModels.ComicDetail detail = details.get(id);
        ComicModels.ComicSummary summary = summaries.get(id);
        String title = detail != null ? detail.summary.title : summary != null ? summary.title : id;
        String cover = detail != null ? detail.summary.coverUrl : summary != null ? summary.coverUrl : "";
        String latest = detail != null ? detail.latestChapter : summary != null ? summary.subtitle : "";
        LinearLayout row = UIHelpers.card(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setOnClickListener(v -> showDetail(id));
        row.addView(coverFrame(cover, 86, 116));
        TextView delete = UIHelpers.text(this, "×", 18, UIHelpers.TEXT3, Typeface.BOLD);
        delete.setGravity(Gravity.CENTER);
        delete.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(this, 18), UIHelpers.BORDER_SOFT));
        delete.setOnClickListener(v -> {
            deleteFavorite(id);
        });
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
        button.setOnClickListener(v -> showDetailThenRead(id));
        info.addView(button, UIHelpers.marginTop(UIHelpers.dp(this, 96), UIHelpers.dp(this, 8), -2, UIHelpers.dp(this, 40)));
        row.addView(info, UIHelpers.weight(1));
        row.addView(delete, new LinearLayout.LayoutParams(UIHelpers.dp(this, 36), UIHelpers.dp(this, 36)));
        return row;
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
        applyThemeAndSystemBars();
        activeDetailId = comicId;
        readerVisible = false;
        ComicModels.ComicDetail detail = details.get(comicId);
        if (detail == null) {
            int loadingGeneration = showPageLoading("正在加载详情...", "正在获取漫画信息。");
            io.execute(() -> {
                try {
                    ComicSource client = sourceForComicId(comicId);
                    ComicModels.ComicDetail loaded = client.detail(comicId);
                    details.put(comicId, loaded);
                    summaries.put(comicId, loaded.summary);
                    persistComicCaches();
                    loadImageToCache(loaded.summary.coverUrl);
                    main.post(() -> {
                        if (!isCurrentLoading(loadingGeneration)) return;
                        pageLoading = false;
                        showDetail(comicId);
                    });
                } catch (Exception error) {
                    main.post(() -> {
                        if (!isCurrentLoading(loadingGeneration)) {
                            appendErrorLog("详情加载失败", error);
                            return;
                        }
                        showError("详情加载失败", error, () -> {
                            pageLoading = false;
                            activeDetailId = "";
                            showTab(currentTab);
                        });
                    });
                }
            });
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
        TextView back = UIHelpers.iconButton(this, "‹");
        back.setOnClickListener(v -> showTab(currentTab));
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
        read.setOnClickListener(v -> ensureChaptersThen(detail, loaded -> showReader(loaded, savedChapter(loaded.summary.comicId))));
        buttons.addView(fav, UIHelpers.buttonWeight(this, 1));
        buttons.addView(UIHelpers.space(this, UIHelpers.dp(this, 10), 1));
        buttons.addView(read, UIHelpers.buttonWeight(this, 1));
        body.addView(buttons, UIHelpers.marginTop(-1, UIHelpers.dp(this, 12)));

        body.addView(chapterEntry(detail), UIHelpers.marginTop(-1, UIHelpers.dp(this, 14)));
    }

    private void showReader(ComicModels.ComicDetail detail, int chapterIndex) {
        if (detail.chapters.isEmpty()) {
            ensureChaptersThen(detail, loaded -> showReader(loaded, chapterIndex));
            return;
        }
        readerVisible = true;
        activeDetailId = detail.summary.comicId;
        readerChapterIndex = Math.max(0, Math.min(chapterIndex, detail.chapters.size() - 1));
        progress.put(detail.summary.comicId, readerChapterIndex);
        lastViewedAt.put(detail.summary.comicId, System.currentTimeMillis());
        saveLocalState();
        ComicModels.Chapter chapter = detail.chapters.get(readerChapterIndex);
        ComicModels.ChapterPage cached = chapters.get(chapter.url);
        if (isEmptyChapterPage(cached)) {
            chapters.remove(chapter.url);
            cached = null;
        }
        if (cached == null) {
            showReaderLoading(detail);
            io.execute(() -> {
                try {
                    ComicSource client = sourceForDetail(detail);
                    ComicModels.ChapterPage page = client.chapter(chapter.url);
                    if (!isEmptyChapterPage(page)) {
                        chapters.put(chapter.url, page);
                        persistComicCaches();
                    }
                    main.post(() -> renderReader(detail, page));
                } catch (Exception error) {
                    main.post(() -> showError("章节加载失败", error));
                }
            });
            return;
        }
        renderReader(detail, cached);
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
        TextView back = UIHelpers.text(this, "‹", 30, UIHelpers.READER_TEXT, Typeface.NORMAL);
        back.setGravity(Gravity.CENTER);
        back.setOnClickListener(v -> showDetail(detail.summary.comicId));
        top.addView(back, new LinearLayout.LayoutParams(UIHelpers.dp(this, 42), -1));
        TextView name = UIHelpers.text(this, detail.chapters.get(readerChapterIndex).title, 13, UIHelpers.READER_TEXT, Typeface.NORMAL);
        name.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
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

        ScrollView scroll = new ScrollView(this);
        tuneScroll(scroll);
        scroll.setFillViewport(true);
        scroll.setOnTouchListener((v, event) -> handleReaderTap(event, detail, page));
        LinearLayout pages = new LinearLayout(this);
        pages.setOrientation(LinearLayout.VERTICAL);
        pages.setPadding(UIHelpers.dp(this, 4), UIHelpers.dp(this, 4), UIHelpers.dp(this, 4), UIHelpers.dp(this, 4));
        scroll.addView(pages, UIHelpers.matchWrap());
        if (page.imageUrls.isEmpty()) {
            pages.addView(readerSkeletonState("没有解析到图片，请返回重试"), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 360)));
        } else {
            for (String url : page.imageUrls) {
                ImageView image = new ImageView(this);
                image.setAdjustViewBounds(true);
                image.setScaleType(ImageView.ScaleType.FIT_CENTER);
                image.setBackgroundColor(UIHelpers.DARK);
                image.setOnTouchListener((v, event) -> handleReaderTap(event, detail, page));
                pages.addView(image, new LinearLayout.LayoutParams(-1, -2));
                loadImage(image, url);
            }
        }
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(readerProgressBar(readerChapterIndex + 1, detail.chapters.size()), new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 1)));

        LinearLayout bottom = new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        bottom.setPadding(UIHelpers.dp(this, 14), 0, UIHelpers.dp(this, 14), 0);
        bottom.setBackgroundColor(UIHelpers.DARK_BAR);
        bottom.setVisibility(readerFullscreen ? View.GONE : View.VISIBLE);
        readerBottomBar = bottom;
        TextView prev = UIHelpers.text(this, "上一章", 12, Color.argb(150, 232, 232, 230), Typeface.NORMAL);
        prev.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        prev.setOnClickListener(v -> switchChapter(detail, -1));
        bottom.addView(prev, UIHelpers.weight(1));
        TextView count = UIHelpers.text(this, page.imageUrls.size() + " 张图", 14, UIHelpers.READER_TEXT, Typeface.NORMAL);
        count.setTypeface(Typeface.MONOSPACE);
        count.setGravity(Gravity.CENTER);
        bottom.addView(count, UIHelpers.weight(1));
        TextView next = UIHelpers.text(this, "下一章", 12, UIHelpers.BRAND, Typeface.NORMAL);
        next.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        next.setGravity(Gravity.RIGHT | Gravity.CENTER_VERTICAL);
        next.setOnClickListener(v -> switchChapter(detail, 1));
        bottom.addView(next, UIHelpers.weight(1));
        shell.addView(bottom, new LinearLayout.LayoutParams(-1, UIHelpers.dp(this, 48)));
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
        boolean tap = moveX < UIHelpers.dp(this, 10) && moveY < UIHelpers.dp(this, 10) && System.currentTimeMillis() - readerDownAt < 450L;
        boolean activeY = y > height * 0.18f && y < height * 0.82f;
        if (!tap || !activeY) return false;
        if (x < width * 0.28f) {
            switchChapter(detail, -1);
        } else if (x > width * 0.72f) {
            switchChapter(detail, 1);
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
        if (keyword != null || keyword == null) return;
        ComicSource client = selectedSource();
        if (client == null) return;
        int generation = ++searchGeneration;
        searchLoading = true;
        if (currentTab == 1) showTab(1);
        io.execute(() -> {
            try {
                List<ComicModels.ComicSummary> list = client.search(keyword == null ? "" : keyword.trim(), 1);
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    searchResults.clear();
                    searchResults.addAll(list);
                    for (ComicModels.ComicSummary item : list) summaries.put(item.comicId, item);
                    persistComicCaches();
                    searchLoading = false;
                    if (currentTab == 1) showTab(1);
                });
            } catch (Exception error) {
                main.post(() -> {
                    searchLoading = false;
                    showError("搜索失败", error);
                });
            }
        });
    }

    private void loadSearchPage(String keyword, int page, boolean append, boolean categoryMode) {
        ComicSource client = selectedSource();
        if (client == null) return;
        int generation = ++searchGeneration;
        if (append) searchAppending = true; else searchLoading = true;
        if (currentTab == 1 && !append) showTab(1);
        io.execute(() -> {
            try {
                List<ComicModels.ComicSummary> list = categoryMode
                        ? client.category(selectedRegion, selectedState, page)
                        : client.search(keyword == null ? "" : keyword.trim(), page);
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    if (!append) searchResults.clear();
                    searchResults.addAll(list);
                    for (ComicModels.ComicSummary item : list) summaries.put(item.comicId, item);
                    persistComicCaches();
                    searchPage = page;
                    searchHasMore = !list.isEmpty();
                    searchLoading = false;
                    searchAppending = false;
                    if (currentTab == 1) {
                        if (append && searchScroll != null) pendingSearchScrollY = searchScroll.getScrollY();
                        showTab(1);
                    }
                });
            } catch (Exception error) {
                main.post(() -> {
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
        });
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
            Future<?> future = io.submit(() -> {
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
            });
            // 10s 超时守护
            final Future<?> f = future;
            io.execute(() -> {
                try {
                    f.get(10, TimeUnit.SECONDS);
                } catch (TimeoutException e) {
                    f.cancel(true);
                    main.post(() -> {
                        if (generation != globalSearchGeneration) return;
                        if (counted.compareAndSet(false, true)) {
                            globalSearchFailedSources++;
                            globalSearchCompletedSources++;
                            onGlobalSearchSourceDone(generation);
                        }
                    });
                } catch (InterruptedException | ExecutionException ignored) {
                    // 任务已正常完成或被取消，主任务回调已处理计数
                }
            });
        }
    }

    /** 单个站源完成时的统一收尾（计数、状态、关闭 loading） */
    private void onGlobalSearchSourceDone(int generation) {
        updateGlobalSearchStatus();
        if (globalSearchCompletedSources >= globalSearchTotalSources) {
            globalSearchLoading = false;
            persistComicCaches();
            updateGlobalSearchStatus();
            // 全部完成时若列表仍为空，重建以显示空状态（移除 loading 动画）
            if (standaloneSearchVisible && globalSearchResults.isEmpty()) {
                showStandaloneSearch(true);
            }
        }
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
        for (AppModels.Source item : customSources) {
            if (item.id.equals(sourceId)) return item.name;
        }
        return clean(sourceId, "未知来源");
    }

    private ComicSource selectedSource() {
        if (sourceClient.id().equals(selectedSourceId) && sourceEnabled) return sourceClient;
        if (mhua5Client.id().equals(selectedSourceId) && mhua5Enabled) return mhua5Client;
        if (aikanClient.id().equals(selectedSourceId) && aikanEnabled) return aikanClient;
        if (gmhClient.id().equals(selectedSourceId) && gmhEnabled) return gmhClient;
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
        return sources;
    }

    private ComicSource sourceForComicId(String comicId) {
        ComicModels.ComicSummary summary = summaries.get(comicId);
        if (summary != null) return sourceForId(summary.sourceId);
        if (comicId != null && comicId.startsWith(mhua5Client.id() + ":")) return mhua5Client;
        if (comicId != null && comicId.startsWith(aikanClient.id() + ":")) return aikanClient;
        if (comicId != null && comicId.startsWith(gmhClient.id() + ":")) return gmhClient;
        return sourceClient;
    }

    private ComicSource sourceForDetail(ComicModels.ComicDetail detail) {
        return detail == null || detail.summary == null ? sourceClient : sourceForId(detail.summary.sourceId);
    }

    private ComicSource sourceForId(String sourceId) {
        if (mhua5Client.id().equals(sourceId)) return mhua5Client;
        if (aikanClient.id().equals(sourceId)) return aikanClient;
        if (gmhClient.id().equals(sourceId)) return gmhClient;
        return sourceClient;
    }

    private void loadDefaultCategory() {
        resetSearchPaging();
        loadSearchPage("", 1, false, true);
        if (sourceClient != null || sourceClient == null) return;
        ComicSource client = selectedSource();
        if (client == null) return;
        int generation = ++searchGeneration;
        searchLoading = true;
        if (currentTab == 1) showTab(1);
        io.execute(() -> {
            try {
                List<ComicModels.ComicSummary> list = client.latest(1);
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    searchResults.clear();
                    searchResults.addAll(list);
                    for (ComicModels.ComicSummary item : list) summaries.put(item.comicId, item);
                    persistComicCaches();
                    searchLoading = false;
                    if (currentTab == 1) showTab(1);
                });
            } catch (Exception error) {
                main.post(() -> {
                    searchLoading = false;
                    showError("默认分类加载失败", error);
                });
            }
        });
    }

    private void loadCategory() {
        resetSearchPaging();
        loadSearchPage("", 1, false, true);
        if (sourceClient != null || sourceClient == null) return;
        ComicSource client = selectedSource();
        if (client == null) return;
        int generation = ++searchGeneration;
        searchLoading = true;
        if (currentTab == 1) showTab(1);
        io.execute(() -> {
            try {
                List<ComicModels.ComicSummary> list = client.category(selectedRegion, selectedState, 1);
                main.post(() -> {
                    if (generation != searchGeneration) return;
                    searchResults.clear();
                    searchResults.addAll(list);
                    for (ComicModels.ComicSummary item : list) summaries.put(item.comicId, item);
                    persistComicCaches();
                    searchLoading = false;
                    if (currentTab == 1) showTab(1);
                });
            } catch (Exception error) {
                main.post(() -> {
                    searchLoading = false;
                    showError("分类加载失败", error);
                });
            }
        });
    }

    private void loadSourceCategories() {
        ComicSource client = selectedSource();
        if (client == null) return;
        io.execute(() -> {
            try {
                List<String> list = client.categories();
                main.post(() -> {
                    sourceCategories.clear();
                    sourceCategories.addAll(list);
                    if (currentTab == 1) showTab(1);
                });
            } catch (Exception ignored) {
            }
        });
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

    private View chapterEntry(ComicModels.ComicDetail detail) {
        LinearLayout card = UIHelpers.card(this);
        card.setOnClickListener(v -> showChapterDrawer(detail));
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(UIHelpers.text(this, "章节目录", 16, UIHelpers.TEXT, Typeface.BOLD));
        String status = detail.chapters.isEmpty() ? "点击后加载目录，提升详情页打开速度" : detail.chapters.size() + " 章 · " + (chapterDesc ? "最新优先" : "最旧优先");
        text.addView(UIHelpers.text(this, status, 12, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(this, 4)));
        row.addView(text, UIHelpers.weight(1));
        TextView action = UIHelpers.chip(this, "打开", true);
        row.addView(action);
        card.addView(row);
        return card;
    }

    private interface DetailAction {
        void run(ComicModels.ComicDetail detail);
    }

    private void ensureChaptersThen(ComicModels.ComicDetail detail, DetailAction action) {
        if (!detail.chapters.isEmpty()) {
            action.run(detail);
            return;
        }
        int loadingGeneration = showPageLoading("正在加载章节目录...", "目录加载完成后会自动打开。");
        io.execute(() -> {
            try {
                ComicSource client = sourceForDetail(detail);
                List<ComicModels.Chapter> loadedChapters = client.chapters(detail.summary.comicId);
                if (loadedChapters.isEmpty()) {
                    throw new IOException("Chapter list is empty: " + detail.summary.title);
                }
                ComicModels.ComicDetail loaded = new ComicModels.ComicDetail(
                        detail.summary,
                        detail.author,
                        detail.status,
                        detail.description,
                        detail.latestChapter,
                        loadedChapters);
                details.put(detail.summary.comicId, loaded);
                persistComicCaches();
                main.post(() -> {
                    if (!isCurrentLoading(loadingGeneration)) return;
                    pageLoading = false;
                    action.run(loaded);
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (!isCurrentLoading(loadingGeneration)) {
                        appendErrorLog("目录加载失败", error);
                        return;
                    }
                    showError("目录加载失败", error, () -> {
                        pageLoading = false;
                        showDetail(detail.summary.comicId);
                    });
                });
            }
        });
    }

    private void showChapterDrawer(ComicModels.ComicDetail detail) {
        if (detail.chapters.isEmpty()) {
            ensureChaptersThen(detail, loaded -> {
                showDetail(loaded.summary.comicId);
                main.post(() -> showChapterDrawer(loaded));
            });
            return;
        }
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16), UIHelpers.dp(this, 16));
        panel.setBackgroundColor(UIHelpers.CARD);

        LinearLayout header = chapterDrawerHeader(detail.chapters.size());
        TextView order = UIHelpers.chip(this, chapterDesc ? "最新优先" : "最旧优先", true);
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
            order.setText(chapterDesc ? "最新优先" : "最旧优先");
            fill.run();
        });
        fill.run();
        activePopup = popup;
        popup.showAtLocation(root, Gravity.RIGHT, 0, 0);
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
            showToast("已取消收藏");
        } else {
            removeDuplicateFavorites(detail);
            favorites.remove(id);
            favorites.add(0, id);
            lastViewedAt.put(id, System.currentTimeMillis());
            details.put(id, detail);
            summaries.put(id, detail.summary);
            persistComicCaches();
            loadImageToCache(detail.summary.coverUrl);
            showToast("已加入收藏");
        }
        saveLocalState();
        showDetail(id);
    }

    private void deleteFavorite(String id) {
        favorites.remove(id);
        progress.remove(id);
        lastViewedAt.remove(id);
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
                progress.remove(oldId);
                lastViewedAt.remove(oldId);
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

    private void loadImage(ImageView target, String imageUrl) {
        io.execute(() -> {
            HttpURLConnection connection = null;
            try {
                File cached = imageCacheFile(imageUrl);
                if (cached.exists()) {
                    Bitmap cachedBitmap = BitmapFactory.decodeFile(cached.getAbsolutePath());
                    if (cachedBitmap != null) {
                        main.post(() -> target.setImageBitmap(cachedBitmap));
                        return;
                    }
                }
                connection = (HttpURLConnection) new URL(imageUrl).openConnection();
                connection.setInstanceFollowRedirects(true);
                connection.setConnectTimeout(10000);
                connection.setReadTimeout(20000);
                connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android) XXComic/1.0");
                connection.setRequestProperty("Referer", refererForImage(imageUrl));
                try (InputStream stream = connection.getInputStream()) {
                    byte[] bytes = readAllBytes(stream);
                    writeImageCache(cached, bytes);
                    Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                    if (bitmap != null) main.post(() -> target.setImageBitmap(bitmap));
                }
            } catch (Exception ignored) {
                main.post(() -> target.setImageDrawable(new ColorDrawable(UIHelpers.BORDER_SOFT)));
            } finally {
                if (connection != null) connection.disconnect();
            }
        });
    }

    private void loadImageToCache(String imageUrl) {
        if (TextUtils.isEmpty(imageUrl)) return;
        io.execute(() -> {
            HttpURLConnection connection = null;
            try {
                File cached = imageCacheFile(imageUrl);
                if (cached.exists()) return;
                connection = (HttpURLConnection) new URL(imageUrl).openConnection();
                connection.setInstanceFollowRedirects(true);
                connection.setConnectTimeout(10000);
                connection.setReadTimeout(20000);
                connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android) XXComic/1.0");
                connection.setRequestProperty("Referer", refererForImage(imageUrl));
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

    private String refererForImage(String imageUrl) {
        if (imageUrl != null && (imageUrl.contains(aikanConfig.domain) || imageUrl.contains("qrqrs.com"))) return aikanConfig.referer;
        if (imageUrl != null && imageUrl.contains(mhua5Config.domain)) return mhua5Config.referer;
        if (imageUrl != null && (imageUrl.contains(gmhConfig.domain) || imageUrl.contains("g-mh.online") || imageUrl.contains("6wm.top"))) return gmhConfig.referer;
        return baoziConfig.referer;
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
        new AlertDialog.Builder(this)
                .setTitle("选择站源")
                .setItems(items, (dialog, which) -> {
                    selectedSourceId = sourceIdForName(items[which]);
                    selectedRegion = "all";
                    selectedState = "all";
                    sourceCategories.clear();
                    searchResults.clear();
                    showTab(1);
                    loadSourceCategories();
                    loadDefaultCategory();
                })
                .show();
    }

    private List<String> enabledSourceNames() {
        List<String> names = new ArrayList<>();
        if (sourceEnabled) names.add(sourceClient.name());
        if (mhua5Enabled) names.add(mhua5Client.name());
        if (aikanEnabled) names.add(aikanClient.name());
        if (gmhEnabled) names.add(gmhClient.name());
        return names;
    }

    private String selectedSourceName() {
        if (sourceClient.id().equals(selectedSourceId)) return sourceClient.name();
        if (mhua5Client.id().equals(selectedSourceId)) return mhua5Client.name();
        if (aikanClient.id().equals(selectedSourceId)) return aikanClient.name();
        if (gmhClient.id().equals(selectedSourceId)) return gmhClient.name();
        for (AppModels.Source item : customSources) {
            if (item.id.equals(selectedSourceId)) return item.name;
        }
        return "全部";
    }

    private String sourceIdForName(String name) {
        if (sourceClient.name().equals(name)) return sourceClient.id();
        if (mhua5Client.name().equals(name)) return mhua5Client.id();
        if (aikanClient.name().equals(name)) return aikanClient.id();
        if (gmhClient.name().equals(name)) return gmhClient.id();
        for (AppModels.Source item : customSources) {
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
                } else {
                    selectedState = codeForState(value);
                }
                searchQuery = "";
                searchResults.clear();
                showTab(1);
                loadCategory();
            });
            row.addView(chip, UIHelpers.marginRight(-2, UIHelpers.dp(this, 14)));
        }
        scroll.addView(row, UIHelpers.wrap());
        return scroll;
    }

    private LinearLayout searchTagGrid(List<String> values) {
        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        if (aikanClient.id().equals(selectedSourceId)) {
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "连载中", "已完结"), false));
            return grid;
        }
        if (gmhClient.id().equals(selectedSourceId)) {
            grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "韩漫", "热门", "国漫", "日漫"), true));
            return grid;
        }
        grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "国漫", "日本", "韩国", "欧美"), true), UIHelpers.marginBottom(-1, UIHelpers.dp(this, 6)));
        grid.addView(searchTagRow(Arrays.asList(ALL_TAG, "连载中", "已完结"), false));
        return grid;
    }

    private String codeForRegion(String value) {
        if ("韩漫".equals(value)) return "kr";
        if ("热门".equals(value)) return "hots";
        if ("日漫".equals(value)) return "jp";
        if ("国漫".equals(value)) return "cn";
        if ("日本".equals(value)) return "jp";
        if ("韩国".equals(value)) return "kr";
        if ("欧美".equals(value)) return "en";
        return "all";
    }

    private String codeForState(String value) {
        if ("连载中".equals(value)) return "serial";
        if ("已完结".equals(value)) return "pub";
        return "all";
    }

    private List<String> searchTags() {
        List<String> values = new ArrayList<>();
        values.add(ALL_TAG);
        if (!sourceCategories.isEmpty()) {
            for (String category : sourceCategories) {
                if (!TextUtils.isEmpty(category) && !values.contains(category) && values.size() < 12) values.add(category);
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
        wrap.setPadding(UIHelpers.dp(this, 18), UIHelpers.dp(this, 6), UIHelpers.dp(this, 18), UIHelpers.dp(this, 10));
        wrap.setBackgroundColor(UIHelpers.CARD);
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        wrap.addView(tabs, new LinearLayout.LayoutParams(-1, -1));
        String[] icons = {"♡", "⌕", "▣", "○"};
        String[] labels = {"收藏", "搜索", "站源", "我的"};
        for (int i = 0; i < labels.length; i++) {
            final int index = i;
            boolean selected = i == currentTab;
            LinearLayout tab = new LinearLayout(this);
            tab.setOrientation(LinearLayout.VERTICAL);
            tab.setGravity(Gravity.CENTER);
            TextView icon = UIHelpers.text(this, icons[i], 16, selected ? UIHelpers.TEXT : UIHelpers.TEXT3, Typeface.NORMAL);
            icon.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            icon.setGravity(Gravity.CENTER);
            TextView label = UIHelpers.text(this, labels[i], 10, selected ? UIHelpers.TEXT : UIHelpers.TEXT3, Typeface.NORMAL);
            label.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            label.setGravity(Gravity.CENTER);
            tab.addView(icon);
            tab.addView(label);
            View indicator = new View(this);
            indicator.setBackgroundColor(selected ? UIHelpers.ACCENT : Color.TRANSPARENT);
            LinearLayout.LayoutParams indicatorParams = new LinearLayout.LayoutParams(UIHelpers.dp(this, 18), UIHelpers.dp(this, 2));
            indicatorParams.setMargins(0, UIHelpers.dp(this, 4), 0, 0);
            tab.addView(indicator, indicatorParams);
            tab.setOnClickListener(v -> showTab(index));
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
            TextView menu = UIHelpers.text(this, "☰", 24, UIHelpers.TEXT, Typeface.BOLD);
            menu.setGravity(Gravity.CENTER);
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

    private View emptyState(String title, String desc, String action, Runnable onClick) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
        box.setPadding(0, UIHelpers.dp(this, 8), 0, 0);
        box.setMinimumHeight(UIHelpers.dp(this, 330));
        TextView icon = UIHelpers.text(this, "♡", 42, UIHelpers.TEXT3, Typeface.NORMAL);
        icon.setGravity(Gravity.CENTER);
        box.addView(icon, new LinearLayout.LayoutParams(-1, -2));
        TextView titleView = UIHelpers.text(this, title, 17, UIHelpers.TEXT2, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(-1, -2);
        titleParams.setMargins(0, UIHelpers.dp(this, 14), 0, 0);
        box.addView(titleView, titleParams);
        TextView description = UIHelpers.text(this, desc, 13, UIHelpers.TEXT3, Typeface.NORMAL);
        description.setGravity(Gravity.CENTER);
        description.setMaxLines(2);
        description.setEllipsize(TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams descParams = new LinearLayout.LayoutParams(-1, -2);
        descParams.setMargins(0, UIHelpers.dp(this, 8), 0, 0);
        box.addView(description, descParams);
        if (!TextUtils.isEmpty(action)) {
            Button button = UIHelpers.secondaryButton(this, action);
            button.setOnClickListener(v -> onClick.run());
            box.addView(button, UIHelpers.marginTop(UIHelpers.dp(this, 120), UIHelpers.dp(this, 18), -2, UIHelpers.dp(this, 42)));
        }
        return box;
    }

    private View loadingState(String title, String desc) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
        box.setPadding(0, UIHelpers.dp(this, 8), 0, 0);
        box.setMinimumHeight(UIHelpers.dp(this, 330));

        ProgressBar progress = new ProgressBar(this);
        progress.setIndeterminate(true);
        box.addView(progress, new LinearLayout.LayoutParams(UIHelpers.dp(this, 42), UIHelpers.dp(this, 42)));

        TextView titleView = UIHelpers.text(this, title, 17, UIHelpers.TEXT2, Typeface.BOLD);
        titleView.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(-1, -2);
        titleParams.setMargins(0, UIHelpers.dp(this, 16), 0, 0);
        box.addView(titleView, titleParams);

        TextView description = UIHelpers.text(this, desc, 13, UIHelpers.TEXT3, Typeface.NORMAL);
        description.setGravity(Gravity.CENTER);
        description.setMaxLines(2);
        description.setEllipsize(TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams descParams = new LinearLayout.LayoutParams(-1, -2);
        descParams.setMargins(0, UIHelpers.dp(this, 8), 0, 0);
        box.addView(description, descParams);
        return box;
    }

    private View loadingMoreView() {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER);
        ProgressBar progress = new ProgressBar(this);
        row.addView(progress, new LinearLayout.LayoutParams(UIHelpers.dp(this, 24), UIHelpers.dp(this, 24)));
        TextView text = UIHelpers.text(this, "加载更多...", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(-2, -2);
        textParams.setMargins(UIHelpers.dp(this, 8), 0, 0, 0);
        row.addView(text, textParams);
        return row;
    }

    private void tuneScroll(ScrollView scroll) {
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroll.setSmoothScrollingEnabled(true);
        scroll.setFadingEdgeLength(0);
    }

    private int showPageLoading(String title, String desc) {
        pageLoading = true;
        pageLoadingReturnTab = currentTab;
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
            long leftTime = lastViewedAt.containsKey(left) ? lastViewedAt.get(left) : 0L;
            long rightTime = lastViewedAt.containsKey(right) ? lastViewedAt.get(right) : 0L;
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

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private void showInfo(String title, String message) {
        new AlertDialog.Builder(this).setTitle(title).setMessage(message).setPositiveButton("知道了", null).show();
    }

    private void showErrorLogs() {
        String logs = errorLogText();
        new AlertDialog.Builder(this)
                .setTitle("错误日志")
                .setMessage(TextUtils.isEmpty(logs) ? "暂无错误日志。" : logs)
                .setPositiveButton("导出", (dialog, which) -> exportErrorLogs())
                .setNegativeButton("清理", (dialog, which) -> clearErrorLogs())
                .setNeutralButton("关闭", null)
                .show();
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
        io.execute(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(uri)) {
                if (stream == null) throw new IOException("无法写入文件");
                stream.write(pendingLogText.getBytes("UTF-8"));
                stream.flush();
                main.post(() -> showToast("错误日志已导出"));
            } catch (Exception error) {
                main.post(() -> showInfo("导出失败", clean(error.getMessage(), "无法写入日志文件")));
            }
        });
    }

    private void showAddSourceDialog() {
        EditText input = new EditText(this);
        input.setHint("https://example.com");
        new AlertDialog.Builder(this)
                .setTitle("添加自定义站源")
                .setView(input)
                .setPositiveButton("添加", (dialog, which) -> {
                    String url = input.getText().toString().trim();
                    if (!url.isEmpty()) {
                        customSources.add(new AppModels.Source("custom_" + System.currentTimeMillis(), url, "", url, false, true));
                        saveLocalState();
                        showTab(2);
                    }
                })
                .setNegativeButton("取消", null)
                .show();
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
        io.execute(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(uri)) {
                if (stream == null) throw new IOException("无法写入文件");
                stream.write(pendingExportJson.getBytes("UTF-8"));
                stream.flush();
                main.post(() -> showToast("站源配置已导出"));
            } catch (Exception error) {
                main.post(() -> showInfo("导出失败", clean(error.getMessage(), "无法写入配置文件")));
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
        io.execute(() -> {
            try (InputStream stream = getContentResolver().openInputStream(uri)) {
                String json = new String(readAllBytes(stream), "UTF-8");
                applySourceConfigJson(new JSONObject(json));
                saveLocalState();
                main.post(() -> {
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
                main.post(() -> showInfo("导入失败", clean(error.getMessage(), "配置文件格式不正确")));
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
        root.put("sources", sources);
        JSONArray custom = new JSONArray();
        for (AppModels.Source item : customSources) {
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
                    customSources.add(new AppModels.Source(id, name, domain, url, false, item.optBoolean("enabled", true)));
                }
            }
        }
        if (selectedSource() == null) {
            sourceEnabled = true;
            selectedSourceId = sourceClient.id();
        }
    }

    private void healthCheck() {
        io.execute(() -> {
            List<String> rows = new ArrayList<>();
            for (ComicSource client : enabledBuiltinSources()) {
                boolean ok = client.healthCheck();
                rows.add(client.name() + (ok ? " 可用" : " 暂不可用"));
            }
            if (rows.isEmpty()) rows.add("当前没有启用站源");
            main.post(() -> showInfo("站源检测", TextUtils.join("\n", rows)));
        });
    }

    private void rebuildSourceClients() {
        sourceClient = new BaoziComicSource(baoziConfig.withEnabled(sourceEnabled));
        mhua5Client = new Mhua5ComicSource(mhua5Config.withEnabled(mhua5Enabled));
        aikanClient = new AikanComicSource(aikanConfig.withEnabled(aikanEnabled));
        gmhClient = new GmhComicSource(gmhConfig.withEnabled(gmhEnabled));
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
        restoreSourceConfigs(prefs.getString("source.configs", ""));
        rebuildSourceClients();
        chapterDesc = prefs.getBoolean("chapter.desc", true);
        themeMode = prefs.getInt("theme.mode", 0);
        cacheSize = prefs.getString("cache.size", cacheSize);
        restoreStringList(globalSearchHistory, prefs.getString("global.search.history", ""));
        favorites.clear();
        String favs = prefs.getString("favorites", "");
        if (!TextUtils.isEmpty(favs)) favorites.addAll(Arrays.asList(favs.split(",")));
        progress.clear();
        String progressText = prefs.getString("progress", "");
        if (!TextUtils.isEmpty(progressText)) {
            for (String row : progressText.split(",")) {
                String[] parts = row.split(":", -1);
                if (parts.length == 2) {
                    try {
                        progress.put(parts[0], Integer.parseInt(parts[1]));
                    } catch (NumberFormatException ignored) {
                    }
                }
            }
        }
        lastViewedAt.clear();
        String viewedText = prefs.getString("last.viewed", "");
        if (!TextUtils.isEmpty(viewedText)) {
            for (String row : viewedText.split(",")) {
                String[] parts = row.split(":", -1);
                if (parts.length == 2) {
                    try {
                        lastViewedAt.put(parts[0], Long.parseLong(parts[1]));
                    } catch (NumberFormatException ignored) {
                    }
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
        editor.putString("source.configs", encodeSourceConfigs());
        editor.putBoolean("chapter.desc", chapterDesc);
        editor.putInt("theme.mode", themeMode);
        editor.putString("cache.size", cacheSize);
        editor.putString("favorites", TextUtils.join(",", favorites));
        editor.putString("global.search.history", TextUtils.join("\n", globalSearchHistory));
        List<String> rows = new ArrayList<>();
        for (Map.Entry<String, Integer> entry : progress.entrySet()) rows.add(entry.getKey() + ":" + entry.getValue());
        editor.putString("progress", TextUtils.join(",", rows));
        List<String> viewedRows = new ArrayList<>();
        for (Map.Entry<String, Long> entry : lastViewedAt.entrySet()) viewedRows.add(entry.getKey() + ":" + entry.getValue());
        editor.putString("last.viewed", TextUtils.join(",", viewedRows));
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
                }
            }
        } catch (JSONException ignored) {
            baoziConfig = SourceConfig.baozi(sourceEnabled);
            mhua5Config = SourceConfig.mhua5(mhua5Enabled);
            aikanConfig = SourceConfig.aikan(aikanEnabled);
            gmhConfig = SourceConfig.gmh(gmhEnabled);
        }
    }

    private String encodeSourceConfigs() {
        try {
            JSONArray array = new JSONArray();
            array.put(baoziConfig.withEnabled(sourceEnabled).toJson());
            array.put(mhua5Config.withEnabled(mhua5Enabled).toJson());
            array.put(aikanConfig.withEnabled(aikanEnabled).toJson());
            array.put(gmhConfig.withEnabled(gmhEnabled).toJson());
            return array.toString();
        } catch (JSONException ignored) {
            return "[]";
        }
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

    private void persistComicCaches() {
        try {
            JSONArray summaryArray = new JSONArray();
            for (ComicModels.ComicSummary summary : summaries.values()) summaryArray.put(summaryToJson(summary));
            JSONArray detailArray = new JSONArray();
            for (ComicModels.ComicDetail detail : details.values()) detailArray.put(detailToJson(detail));
            JSONArray chapterArray = new JSONArray();
            for (ComicModels.ChapterPage page : chapters.values()) chapterArray.put(chapterPageToJson(page));
            getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .putString(SUMMARIES_CACHE_KEY, summaryArray.toString())
                    .putString(DETAILS_CACHE_KEY, detailArray.toString())
                    .putString(CHAPTERS_CACHE_KEY, chapterArray.toString())
                    .apply();
            updateCacheSize();
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
                object.optString("author"),
                object.optString("status"),
                object.optString("description"),
                object.optString("latestChapter"),
                chapterList);
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
        return new File(dir, Integer.toHexString(imageUrl.hashCode()) + ".img");
    }

    private byte[] readAllBytes(InputStream stream) throws java.io.IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = stream.read(buffer)) != -1) output.write(buffer, 0, read);
        return output.toByteArray();
    }

    private void writeImageCache(File file, byte[] bytes) throws java.io.IOException {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        try (FileOutputStream output = new FileOutputStream(file)) {
            output.write(bytes);
        }
    }

    private void clearAppCache() {
        deleteFiles(new File(getCacheDir(), "images"));
        summaries.clear();
        details.clear();
        chapters.clear();
        SharedPreferences.Editor editor = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        editor.remove(DETAILS_CACHE_KEY);
        editor.remove(CHAPTERS_CACHE_KEY);
        editor.remove(SUMMARIES_CACHE_KEY);
        editor.putString("cache.size", "0 MB");
        editor.apply();
        cacheSize = "0 MB";
        showToast("缓存已清理");
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
        long bytes = dirSize(new File(getCacheDir(), "images"))
                + getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(SUMMARIES_CACHE_KEY, "").length()
                + getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(DETAILS_CACHE_KEY, "").length()
                + getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(CHAPTERS_CACHE_KEY, "").length();
        cacheSize = formatBytes(bytes);
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString("cache.size", cacheSize).apply();
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
            customSources.add(new AppModels.Source(parts[0], parts[1], parts[2], parts[3], false, Boolean.parseBoolean(parts[4])));
        }
    }

    private String encodeCustomSources() {
        StringBuilder builder = new StringBuilder();
        for (AppModels.Source item : customSources) {
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
