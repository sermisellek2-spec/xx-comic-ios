package com.xxcomic;

import android.app.Instrumentation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import com.xxcomic.reader.PagedReaderView;
import com.xxcomic.reader.ZoomImageView;
import com.xxcomic.reader.ReaderPosition;
import android.widget.ListView;
import com.xxcomic.source.ComicModels.*;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.*;

/** Offline device regression suite. Run with am instrument -w com.xxcomic.test/com.xxcomic.ReaderInstrumentation. */
public final class ReaderInstrumentation extends Instrumentation {
    private MainActivity activity;
    private ComicDetail detail;
    private int checks;
    private boolean immersionOnly;
    private boolean startupOnly;
    private boolean manwaOnly;
    private boolean sourceOrderOnly;
    private boolean localOnly;
    private boolean downloadsOnly;
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        immersionOnly = arguments != null && "true".equals(arguments.getString("immersionOnly"));
        startupOnly = arguments != null && "true".equals(arguments.getString("startupOnly"));
        manwaOnly = arguments != null && "true".equals(arguments.getString("manwaOnly"));
        sourceOrderOnly = arguments != null && "true".equals(arguments.getString("sourceOrderOnly"));
        localOnly = arguments != null && "true".equals(arguments.getString("localOnly"));
        downloadsOnly = arguments != null && "true".equals(arguments.getString("downloadsOnly"));
        start();
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            if (downloadsOnly) {
                int count = OfflineDownloadChecks.run(getTargetContext());
                result.putString("stream", "PASS: " + count + " offline download native checks\n");
                finish(-1, result); return;
            }
            if (localOnly) {
                int count = LocalLibraryChecks.runChecks(getTargetContext());
                result.putString("stream", "PASS: " + count + " local library database checks\n");
                finish(-1, result);
                return;
            }
            activity = (MainActivity) startActivitySync(new Intent(getTargetContext(), MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            if (sourceOrderOnly) {
                testSourceOrder();
                result.putString("stream", "PASS: " + checks + " source order device checks\n");
                finish(-1, result);
                return;
            }
            if (manwaOnly) {
                testManwaSource();
                result.putString("stream", "PASS: " + checks + " Manwa live source/device checks\n");
                finish(-1, result);
                return;
            }
            seed();
            if (startupOnly) {
                testStartupPromptLifecycle();
                result.putString("stream", "PASS: " + checks + " startup prompt device checks\n");
                finish(-1, result);
                return;
            }
            if (immersionOnly) {
                testImmersion();
                result.putString("stream", "PASS: " + checks + " immersion device checks\n");
                finish(-1, result);
                return;
            }
            for (int mode = 0; mode < 3; mode++) for (boolean left : new boolean[]{false, true}) {
                configure(1, mode, left);
                navigateGesture(mode, left);
                check(((PagedReaderView) get("readerPager")).currentPage() == 1, "single image forward " + mode + "/" + left);
                check((int) get("readerChapterIndex") == 0, "forward stays in chapter");
            }
            configure(1, 1, false);
            onMain(() -> call("navigateReader", detail, page(0), 1)); settle();
            onMain(() -> call("navigateReader", detail, page(0), 1)); settle();
            onMain(() -> call("navigateReader", detail, page(0), 1)); settle();
            check((int) get("readerChapterIndex") == 1 && pager().currentPage() == 0, "next chapter starts at first image");
            onMain(() -> call("navigateReader", detail, page(1), -1)); settle();
            check((int) get("readerChapterIndex") == 0 && pager().currentPage() == 2, "previous chapter starts at last image");
            onMain(() -> call("showReaderSettings")); settle();
            check(findText(activity.getWindow().getDecorView(), "左右手模式") != null, "secondary hand setting");
            check(findText(activity.getWindow().getDecorView(), "翻页方式") != null, "secondary input setting");
            clickText("条漫");
            onMain(() -> activity.onBackPressed()); settle();
            check(get("readerList") != null && (int)get("readerChapterIndex") == 0, "return to continuous reader");
            onMain(() -> call("showReaderSettings")); settle(); clickText("单页（日漫）");
            onMain(() -> activity.onBackPressed()); settle();
            check(pager().currentPage() == 2, "layout round trip preserves image");
            configure(1, 2, false);
            tap(.5f); SystemClock.sleep(70); tap(.5f); settle();
            check(pager().isZoomed(), "double tap zoom");
            swipe(false); settle();
            check(pager().currentPage() == 0 && (int)get("readerChapterIndex") == 0, "zoom pan cannot turn page");
            for (boolean left : new boolean[]{false, true}) {
                configure(1, 2, left);
                onMain(() -> pager().moveTo(2)); settle(); swipe(left); settle();
                check((int)get("readerChapterIndex") == 1 && pager().currentPage() == 0, "edge swipe advances once " + left);
            }
            for (int mode=0; mode<3; mode++) for(boolean left:new boolean[]{false,true}) {
                configure(0,mode,left);
                if(mode==1) onMain(() -> ((View)get("readerNextButton")).performClick());
                else if(mode==0) {
                    View list=(View)get("readerList"); gesture(list,left?.12f:.88f,left?.12f:.88f,80);
                } else gesture((View)get("readerList"),left?.2f:.8f,left?.8f:.2f,240);
                settle(); check((int)get("readerChapterIndex")==1,"continuous chapter navigation "+mode+"/"+left);
            }
            configure(0,1,false);
            onMain(() -> {
                ListView list=(ListView)get("readerList");
                ((boolean[])get("readerRestoringPosition"))[0]=false;
                list.setSelectionFromTop(1,-180);
            }); settle();
            onMain(() -> call("showReaderSettings")); settle();
            String key=detail.summary.comicId+"\u001f"+detail.chapters.get(0).chapterId;
            ReaderPosition before=(ReaderPosition)((Map)get("readerImagePositions")).get(key);
            check(before.imageIndex==1 && before.offset>0,"capture partial continuous image");
            clickText("单页（日漫）"); onMain(() -> activity.onBackPressed()); settle();
            check(pager().currentPage()==1,"partial continuous image enters matching single page");
            onMain(() -> call("showReaderSettings")); settle(); clickText("条漫");
            onMain(() -> activity.onBackPressed()); settle();
            ListView restored=(ListView)get("readerList");
            check(restored.getFirstVisiblePosition()==1 && Math.abs(restored.getChildAt(0).getTop()+180)<12,"partial image offset survives round trip: index="+restored.getFirstVisiblePosition()+", top="+restored.getChildAt(0).getTop()+", savedOffset="+before.offset);
            configure(1,1,false); screenshot("reader-single.png");
            onMain(() -> call("showReaderSettings")); settle(); screenshot("reader-settings.png");
            result.putString("stream", "PASS: " + checks + " reader device checks\n");
            finish(-1, result);
        } catch(Throwable e) {
            result.putString("stream", "FAIL after " + checks + " checks: " + android.util.Log.getStackTraceString(e));
            finish(0, result);
        }
    }
    private void testStartupPromptLifecycle() throws Exception {
        com.xxcomic.update.AppUpdateChecker checker=com.xxcomic.update.AppUpdateChecker.getInstance();
        com.xxcomic.update.AppRelease soft=new com.xxcomic.update.AppRelease("2.0.99",299,100,
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","soft","测试说明");
        com.xxcomic.update.AppRelease prompt=new com.xxcomic.update.AppRelease("2.0.99",299,100,
                soft.sha256,"prompt","可取消的更新提示");
        // Wait for the real startup request to finish before injecting the offline fixture.
        long deadline=SystemClock.uptimeMillis()+30000;
        Field completed=checker.getClass().getDeclaredField("startupCompleted");completed.setAccessible(true);
        while(!(boolean)completed.get(checker) && SystemClock.uptimeMillis()<deadline)SystemClock.sleep(100);
        check((boolean)completed.get(checker),"initial check completed");
        com.xxcomic.update.AppUpdateChecker.StartupCheckCallback callback=
                (com.xxcomic.update.AppUpdateChecker.StartupCheckCallback)get("startupUpdateCallback");
        callback.onStartupCheckFinished(soft);settle();
        check(get("activeUpdateDialog")==null,"soft update stays silent");
        sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_HOME);settle();
        callback.onStartupCheckFinished(prompt);settle();
        check(get("activeUpdateDialog")==null,"background result cannot show dialog");
        check(get("pendingPromptRelease")!=null,"background result retained");
        getTargetContext().startActivity(new Intent(getTargetContext(),MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));settle();
        check(get("activeUpdateDialog")!=null && ((android.app.AlertDialog)get("activeUpdateDialog")).isShowing(),"foreground displays pending prompt");
        onMain(() -> ((android.app.AlertDialog)get("activeUpdateDialog")).getButton(-2).performClick());settle();
        check(checker.isSessionPromptDismissed(),"cancel acknowledges prompt for session");
        onMain(() -> call("tryShowUpdatePrompt",prompt));settle();
        check(get("activeUpdateDialog")==null,"cancelled prompt cannot return");
        Field dismissed=checker.getClass().getDeclaredField("sessionPromptDismissed");dismissed.setAccessible(true);
        Field cached=checker.getClass().getDeclaredField("cachedRelease");cached.setAccessible(true);
        onMain(() -> {dismissed.set(checker,false);cached.set(checker,prompt);call("tryShowUpdatePrompt",prompt);});settle();
        check(get("activeUpdateDialog")!=null,"second fixture prompt displayed");
        ActivityMonitor monitor=addMonitor(MainActivity.class.getName(),null,false);
        onMain(() -> activity.recreate());
        android.app.Activity replacement=waitForMonitorWithTimeout(monitor,10000);removeMonitor(monitor);
        check(replacement instanceof MainActivity,"activity recreated");activity=(MainActivity)replacement;settle();
        check(get("activeUpdateDialog")!=null && ((android.app.AlertDialog)get("activeUpdateDialog")).isShowing(),"prompt survives activity recreation");
        onMain(() -> ((android.app.AlertDialog)get("activeUpdateDialog")).cancel());settle();
        check(checker.isSessionPromptDismissed(),"back or outside cancellation acknowledges prompt");
    }
    private void testImmersion() throws Exception {
        onMain(() -> {
            activity.getSharedPreferences("xx-comic",0).edit().remove("reader.fully.immersive").commit();
            call("restoreLocalState");
        });
        check(!(boolean)get("readerFullyImmersive"), "upgrade defaults to normal");
        for(int layout=0;layout<2;layout++) for(int display=0;display<2;display++) {
            final int screenMode=display;
            onMain(() -> {set("readerFullyImmersive",false);set("readerDisplayMode",screenMode);});
            configure(layout,1,false);
            onMain(() -> call("setReaderFullscreen",true,false));
            check(((View)get("readerOverlayBadge")).getVisibility()==View.VISIBLE,"normal badge visible");
            if(layout==1){onMain(() -> pager().moveTo(1));settle();}
            onMain(() -> call("showReaderSettings"));settle();
            check(findText(activity.getWindow().getDecorView(),"沉浸模式")!=null,"immersion settings section");
            clickText("完全沉浸");
            check(activity.getSharedPreferences("xx-comic",0).getBoolean("reader.fully.immersive",false),"choice persisted");
            onMain(() -> activity.onBackPressed());settle();
            check((int)get("readerChapterIndex")==0,"chapter preserved");
            if(layout==1)check(pager().currentPage()==1,"image preserved");
            check(((View)get("readerOverlayBadge")).getVisibility()==View.GONE,"immersive badge gone");
            onMain(() -> call("setReaderFullscreen",false,true));settle();
            check(((View)get("readerTopBar")).getVisibility()==View.VISIBLE,"controls remain accessible");
            onMain(() -> {call("setReaderFullscreen",true,true);call("refreshReaderOverlayBadge");});settle();
            check(((View)get("readerOverlayBadge")).getVisibility()==View.GONE,"animation and data refresh keep badge hidden");
            onMain(() -> {call("showReader",detail,1);call("onResume");});settle();
            check(((View)get("readerOverlayBadge")).getVisibility()==View.GONE,"chapter change and resume keep badge hidden");
            onMain(() -> {
                call("saveLocalState");set("readerFullyImmersive",false);call("restoreLocalState");
            });
            check((boolean)get("readerFullyImmersive"),"saved preference reloads");
            onMain(() -> call("showReaderSettings"));settle();
            // The page also has a display-mode option named 普通模式; choose within the immersion section.
            onMain(() -> {
                View choice=findText(activity.getWindow().getDecorView(),"完全沉浸");
                ViewGroup row=(ViewGroup)choice.getParent();
                View normal=findText(row,"普通模式");
                while(!normal.isClickable())normal=(View)normal.getParent();normal.performClick();
            });settle();
            onMain(() -> activity.onBackPressed());settle();
            onMain(() -> call("setReaderFullscreen",true,false));
            check(((View)get("readerOverlayBadge")).getVisibility()==View.VISIBLE,"normal restores badge");
        }
    }
    /** Opt-in live smoke test: -e manwaOnly true. Ordinary regression runs stay offline. */
    private void testManwaSource() throws Exception {
        com.xxcomic.source.ComicSource source = (com.xxcomic.source.ComicSource)get("manwaClient");
        check("manwa".equals(source.id()), "source registered");
        onMain(() -> {
            set("selectedSourceId", "manwa");
            check(call("selectedSource") == source, "selected source resolver");
        });
        check(call("sourceForComicId", "manwa:163037") == source, "favorite/history namespace resolver");
        check(((List)call("enabledBuiltinSources")).contains(source), "global search registration");
        check("漫蛙".equals(call("sourceNameForId", "manwa")), "display name registration");
        check(source.search("史莱姆", 1).size() == 20, "Android HTTPS search");
        check(source.latest(2).size() == 36, "Android HTTPS category POST page 2");
        ComicDetail metadata = source.detail("manwa:163037");
        List<Chapter> directory = source.chapters("manwa:163037");
        detail = new ComicDetail(metadata.summary, metadata.author, metadata.status, metadata.description, metadata.latestChapter, directory);
        check(directory.size() == 1 && !metadata.author.isEmpty(), "Android detail and directory");
        ChapterPage chapter = source.chapter(directory.get(0).url);
        check(chapter.imageUrls.size() == 38, "Android full image list");
        String first = chapter.imageUrls.get(0);
        call("ensureReaderImageCached", first, directory.get(0).url, false);
        File cached = (File)call("imageCacheFile", first);
        Bitmap bitmap = android.graphics.BitmapFactory.decodeFile(cached.getAbsolutePath());
        check(bitmap != null && bitmap.getWidth() == 800, "encrypted WebP decoded and cached on Android");
        bitmap.recycle();
        check((boolean)call("ensureReaderImageCached", first, directory.get(0).url, true), "offline reader cache available");
        android.widget.ImageView cover = new android.widget.ImageView(activity);
        onMain(() -> call("loadImage", cover, metadata.summary.coverUrl, "", false));
        File coverFile = (File)call("imageCacheFile", metadata.summary.coverUrl);
        long deadline = SystemClock.uptimeMillis() + 30000;
        while (!coverFile.exists() && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(100);
        Bitmap coverBitmap = android.graphics.BitmapFactory.decodeFile(coverFile.getAbsolutePath());
        check(coverBitmap != null && coverBitmap.getWidth() > 0, "encrypted cover cache path");
        coverBitmap.recycle();
        onMain(() -> {
            ((Map)get("details")).put(detail.summary.comicId, detail);
            ((Map)get("chapters")).put(directory.get(0).url, chapter);
        });
        configure(0, 1, false);
        check(get("readerList") != null, "continuous mode opens Manwa");
        configure(1, 1, false);
        check(pager().currentPage() == 0, "single image mode opens Manwa");
        screenshot("manwa-reader.png");
        onMain(() -> {
            call("releaseReaderViews");
            set("manwaEnabled", false);
            String configs = (String)call("encodeSourceConfigs");
            call("restoreSourceConfigs", configs);
            call("rebuildSourceClients");
            check(!(boolean)get("manwaEnabled"), "disabled state round trip");
            check(!((List)call("enabledBuiltinSources")).contains(get("manwaClient")), "disabled source excluded from global search");
            set("manwaEnabled", true);
            call("rebuildSourceClients");
        });
    }

    private void seed() throws Exception {
        List<Chapter> list = new ArrayList<>();
        for(int c=0;c<2;c++) list.add(new Chapter("fixture-"+c,"测试章节 "+(c+1),"https://reader.invalid/chapter/"+c,0,c));
        detail = new ComicDetail(new ComicSummary("copy4000","reader-fixture","阅读模式测试","","",null),"","","","",list);
        for(int c=0;c<2;c++) {
            List<String> urls = new ArrayList<>();
            for(int i=0;i<3;i++) {
                String url="https://reader.invalid/image/"+c+"/"+i; urls.add(url);
                File file=(File)call("imageCacheFile",url); file.getParentFile().mkdirs();
                Bitmap bmp=Bitmap.createBitmap(700,1000,Bitmap.Config.ARGB_8888);
                Canvas canvas=new Canvas(bmp); canvas.drawColor(Color.rgb(40+c*40,70+i*50,130));
                Paint paint=new Paint(); paint.setColor(Color.WHITE); paint.setTextSize(80); canvas.drawText("PAGE "+(i+1),130,500,paint);
                try(FileOutputStream out=new FileOutputStream(file)){bmp.compress(Bitmap.CompressFormat.PNG,100,out);} bmp.recycle();
            }
            ((Map)get("chapters")).put(list.get(c).url,new ChapterPage(list.get(c).chapterId,list.get(c).title,urls,""));
        }
        onMain(() -> ((Map)get("details")).put(detail.summary.comicId,detail));
    }
    private ChapterPage page(int index) throws Exception { return (ChapterPage)((Map)get("chapters")).get(detail.chapters.get(index).url); }
    private void configure(int layout,int input,boolean left) throws Exception {
        onMain(() -> {
            call("releaseReaderViews");
            ((Map)get("readerImagePositions")).clear(); ((Map)get("readerPositions")).clear();
            set("readerLayoutMode",layout); set("readerPageMode",input); set("readerButtonMode",input==1); set("readerLeftHand",left);
            call("showReader",detail,0);
        }); settle();
    }
    private PagedReaderView pager() throws Exception {return (PagedReaderView)get("readerPager");}
    private void navigateGesture(int mode,boolean left) throws Exception {
        if(mode==0)tap(left?.12f:.88f);
        if(mode==1)onMain(() -> ((View)get("readerNextButton")).performClick());
        if(mode==2)swipe(left);
        settle();
    }
    private void tap(float x) throws Exception {gesture(pager(),x,x,60);}
    private void swipe(boolean left) throws Exception {gesture(pager(),left?.2f:.8f,left?.8f:.2f,240);}
    private void gesture(View target,float from,float to,int duration) throws Exception {
        long start=SystemClock.uptimeMillis();
        int steps=from==to?1:12;
        for(int i=0;i<=steps;i++) {
            final int step=i; final long now=SystemClock.uptimeMillis();
            onMain(() -> {
                MotionEvent e=MotionEvent.obtain(start,now,step==0?MotionEvent.ACTION_DOWN:step==steps?MotionEvent.ACTION_UP:MotionEvent.ACTION_MOVE,
                    target.getWidth()*(from+(to-from)*step/steps),target.getHeight()*.5f,0);
                target.dispatchTouchEvent(e); e.recycle();
            });
            if(i<steps)SystemClock.sleep(duration/steps);
        }
    }
    @SuppressWarnings("unchecked")
    private void testSourceOrder() throws Exception {
        final org.json.JSONObject[] backup = {null};
        onMain(() -> backup[0] = (org.json.JSONObject) call("sourceConfigJson"));
        try {
            onMain(() -> { set("sourceEnabled", true); call("rebuildSourceClients"); call("resetSourceOrder"); });
            settle();
            List<String> original = new ArrayList<>((List<String>)get("sourceOrder"));
            String selected = (String)get("selectedSourceId");
            SourceOrderList list = (SourceOrderList)findSourceList(activity.getWindow().getDecorView());
            check(list != null && list.getAdapter().getItemCount() == original.size(), "all sources appear in draggable list");
            final float[] point = new float[3];
            onMain(() -> {
                View first = list.getLayoutManager().findViewByPosition(0);
                View third = list.getLayoutManager().findViewByPosition(2);
                point[0] = UIHelpers.dp(activity, 20);
                point[1] = (first.getTop() + first.getBottom()) / 2f;
                // Cross the target row's boundary before ACTION_UP, as ItemTouchHelper requires.
                point[2] = (third.getTop() + third.getBottom()) / 2f + UIHelpers.dp(activity, 12);
            });
            long down = SystemClock.uptimeMillis();
            for (int i = 0; i <= 24; i++) {
                final int step = i;
                onMain(() -> {
                    MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(),
                            step == 0 ? MotionEvent.ACTION_DOWN : step == 24 ? MotionEvent.ACTION_UP : MotionEvent.ACTION_MOVE,
                            point[0], point[1] + (point[2] - point[1]) * step / 24f, 0);
                    list.dispatchTouchEvent(event); event.recycle();
                });
                SystemClock.sleep(30);
            }
            settle();
            List<String> expected = new ArrayList<>(original);
            expected.add(2, expected.remove(0));
            screenshot("source-order-drag.png");
            check(expected.equals(get("sourceOrder")), "handle drag changes order without toggling: expected="
                    + expected + " actual=" + get("sourceOrder") + " coordinates=" + Arrays.toString(point));
            check((boolean)get("sourceEnabled"), "drag preserves source enable switch");
            check(selected.equals(get("selectedSourceId")), "drag preserves selected source ID");
            onMain(() -> call("restoreLocalState"));
            check(expected.equals(get("sourceOrder")), "order survives preference reload");
            ActivityMonitor sourceMonitor = addMonitor(MainActivity.class.getName(), null, false);
            onMain(() -> activity.recreate());
            MainActivity restored = (MainActivity)waitForMonitorWithTimeout(sourceMonitor, 10000);
            removeMonitor(sourceMonitor);
            check(restored != null, "activity recreates after sorting");
            activity = restored;
            settle();
            check(expected.equals(get("sourceOrder")), "recreated activity restores saved order");
            final List<String>[] menu = new List[]{null};
            final List<com.xxcomic.source.ComicSource>[] enabled = new List[]{null};
            final List<com.xxcomic.source.ComicSource>[] search = new List[]{null};
            onMain(() -> {
                menu[0] = (List<String>)call("enabledSourceNames");
                enabled[0] = (List<com.xxcomic.source.ComicSource>)call("enabledBuiltinSources");
                search[0] = (List<com.xxcomic.source.ComicSource>)call("enabledSearchSources");
            });
            List<String> names = new ArrayList<>(), ids = new ArrayList<>();
            for (com.xxcomic.source.ComicSource source : enabled[0]) { names.add(source.name()); ids.add(source.id()); }
            check(names.equals(menu[0]), "source switch menu shares enabled order");
            check(ids.equals(SourceOrder.normalize(expected, ids)), "enabled source list follows dragged order");
            ids.clear(); for (com.xxcomic.source.ComicSource source : search[0]) ids.add(source.id());
            check(ids.equals(SourceOrder.normalize(expected, ids)), "global search source tabs share order");
            onMain(() -> call("showSourceManagement"));
            settle();
            onMain(() -> {
                ViewGroup row = activity.getWindow().getDecorView().findViewWithTag("source-row:" + original.get(0));
                ViewGroup line = (ViewGroup)row.getChildAt(0);
                ViewGroup body = (ViewGroup)line.getChildAt(1);
                ViewGroup card = (ViewGroup)body.getChildAt(0);
                card.getChildAt(card.getChildCount() - 1).performClick();
            });
            settle();
            check(!(boolean)get("sourceEnabled"), "switch still disables the dragged source");
            check(expected.equals(get("sourceOrder")), "disabled source keeps its position");
            onMain(() -> {
                ViewGroup row = activity.getWindow().getDecorView().findViewWithTag("source-row:" + original.get(0));
                ViewGroup line = (ViewGroup)row.getChildAt(0);
                ViewGroup body = (ViewGroup)line.getChildAt(1);
                ViewGroup card = (ViewGroup)body.getChildAt(0);
                card.getChildAt(card.getChildCount() - 1).performClick();
            });
            settle();
            check((boolean)get("sourceEnabled") && expected.equals(get("sourceOrder")), "re-enabled source keeps position");
            final org.json.JSONObject[] exported = {null};
            onMain(() -> exported[0] = (org.json.JSONObject)call("sourceConfigJson"));
            check(SourceOrder.decode(exported[0].getJSONArray("sourceOrder").toString()).equals(expected), "export includes source order");
            onMain(() -> { call("resetSourceOrder"); call("applySourceConfigJson", exported[0]); });
            check(expected.equals(get("sourceOrder")), "import restores source order");
            exported[0].remove("sourceOrder");
            onMain(() -> call("applySourceConfigJson", exported[0]));
            check(expected.equals(get("sourceOrder")), "legacy import preserves local order");
            onMain(() -> call("resetSourceOrder"));
            check(original.equals(get("sourceOrder")), "reset restores default order");
            onMain(() -> { call("saveSourceOrder", expected); call("showSourceManagement"); });
            settle(); screenshot("source-order.png");
        } finally {
            onMain(() -> { call("applySourceConfigJson", backup[0]); call("saveLocalState"); });
        }
    }

    private View findSourceList(View view) {
        if (view instanceof SourceOrderList) return view;
        if (view instanceof ViewGroup) for (int i = 0; i < ((ViewGroup)view).getChildCount(); i++) {
            View found = findSourceList(((ViewGroup)view).getChildAt(i));
            if (found != null) return found;
        }
        return null;
    }

    private void clickText(String text) throws Exception {
        onMain(() -> {View v=findText(activity.getWindow().getDecorView(),text); if(v==null)throw new AssertionError(text); while(!v.isClickable())v=(View)v.getParent(); v.performClick();}); settle();
    }
    private View findText(View view,String text) {
        if(view instanceof TextView && text.equals(((TextView)view).getText().toString()))return view;
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View found=findText(((ViewGroup)view).getChildAt(i),text);if(found!=null)return found;}
        return null;
    }
    private void check(boolean ok,String message){if(!ok)throw new AssertionError(message);checks++;}
    private void screenshot(String name) throws Exception {
        Bitmap bitmap=getUiAutomation().takeScreenshot();
        try(FileOutputStream out=new FileOutputStream(new File(getTargetContext().getExternalFilesDir(null),name))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);}
        bitmap.recycle();
    }
    private void settle(){waitForIdleSync();SystemClock.sleep(800);waitForIdleSync();}
    private Object get(String name) throws Exception {Field f=MainActivity.class.getDeclaredField(name);f.setAccessible(true);return f.get(activity);}
    private void set(String name,Object value) throws Exception {Field f=MainActivity.class.getDeclaredField(name);f.setAccessible(true);f.set(activity,value);}
    private Object call(String name,Object... args) throws Exception {
        for(Method method:MainActivity.class.getDeclaredMethods())if(method.getName().equals(name)&&method.getParameterTypes().length==args.length){method.setAccessible(true);return method.invoke(activity,args);}
        throw new NoSuchMethodException(name);
    }
    private interface Checked {void run() throws Exception;}
    private void onMain(Checked work) throws Exception {
        final Throwable[] error={null};runOnMainSync(() -> {try{work.run();}catch(Throwable e){error[0]=e;}});
        if(error[0]!=null)throw new Exception(error[0]);
    }
}
