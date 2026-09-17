package com.xxcomic.download;

import android.app.*;
import android.graphics.Typeface;
import android.os.*;
import android.view.*;
import android.widget.*;
import com.xxcomic.R;
import com.xxcomic.UIHelpers;
import com.xxcomic.local.*;
import com.xxcomic.source.ComicModels;
import java.util.*;
import static com.xxcomic.download.DownloadModels.*;

/** Native themed lists; recycled chapter rows keep very large directories responsive. */
public final class DownloadViews {
    public interface OpenBook { void accept(String bookId); }
    public static void selection(Activity a, ComicModels.ComicDetail detail,int current,Runnable onAdded) {
        DownloadRuntime runtime=DownloadRuntime.get(a);
        Set<String> selected=new LinkedHashSet<>();
        if(!detail.chapters.isEmpty())selected.add(detail.chapters.get(Math.max(0,Math.min(current,detail.chapters.size()-1))).chapterId);
        Dialog dialog=new Dialog(a);dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout panel=column(a);panel.setPadding(dp(a,18),dp(a,12),dp(a,18),dp(a,14));
        panel.setBackground(UIHelpers.round(UIHelpers.CARD,dp(a,18),android.graphics.Color.TRANSPARENT));
        panel.addView(label(a,"下载到本地书架",19,UIHelpers.TEXT));
        panel.addView(label(a,"仅保存本次选择的章节 · "+(runtime.wifiOnly()?"仅 Wi-Fi":"允许移动网络"),12,UIHelpers.TEXT3));
        LinearLayout tools=row(a);panel.addView(tools);
        ListView list=new ListView(a);list.setDividerHeight(0);
        List<ComicModels.Chapter> visible=new ArrayList<>(detail.chapters);
        BaseAdapter adapter=new BaseAdapter(){
            public int getCount(){return visible.size();}public Object getItem(int i){return visible.get(i);}public long getItemId(int i){return i;}
            public View getView(int i,View recycled,ViewGroup parent){
                CheckBox check=recycled instanceof CheckBox?(CheckBox)recycled:new CheckBox(a);
                ComicModels.Chapter ch=visible.get(i);Task task=runtime.store.get(key(detail.summary.sourceId,detail.summary.comicId,ch.chapterId));
                boolean exists=task!=null;
                check.setOnCheckedChangeListener(null);check.setText(ch.title+(exists?" · "+state(task):""));
                check.setTextSize(13);check.setTextColor(exists?UIHelpers.TEXT3:UIHelpers.TEXT);check.setMinHeight(dp(a,48));
                check.setButtonTintList(android.content.res.ColorStateList.valueOf(UIHelpers.ACCENT));
                check.setEnabled(!exists);check.setChecked(!exists&&selected.contains(ch.chapterId));
                check.setOnCheckedChangeListener((button,value)->{if(value)selected.add(ch.chapterId);else selected.remove(ch.chapterId);});return check;
            }
        };list.setAdapter(adapter);
        action(a,tools,"本章",()->{selected.clear();if(!detail.chapters.isEmpty())selected.add(detail.chapters.get(Math.max(0,Math.min(current,detail.chapters.size()-1))).chapterId);adapter.notifyDataSetChanged();});
        action(a,tools,"全选",()->{for(ComicModels.Chapter ch:detail.chapters)selected.add(ch.chapterId);adapter.notifyDataSetChanged();});
        action(a,tools,"清空",()->{selected.clear();adapter.notifyDataSetChanged();});
        action(a,tools,"倒序 ⇄",()->{Collections.reverse(visible);adapter.notifyDataSetChanged();});
        panel.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        Button start=UIHelpers.primaryButton(a,"下载选中章节");panel.addView(start,new LinearLayout.LayoutParams(-1,dp(a,48)));
        start.setOnClickListener(v->{
            List<String> ids=new ArrayList<>();for(String id:selected)if(runtime.store.get(key(detail.summary.sourceId,detail.summary.comicId,id))==null)ids.add(id);
            if(ids.isEmpty()){toast(a,"先选择未下载的章节哦");return;}
            start.setEnabled(false);
            runtime.io.execute(()->{try {runtime.enqueue(detail,ids);a.runOnUiThread(()->{if(a.isDestroyed())return;dialog.dismiss();startService(a);toast(a,"已加入下载队列");onAdded.run();});}
                catch(Exception error){a.runOnUiThread(()->{if(a.isDestroyed())return;start.setEnabled(true);toast(a,"无法创建下载任务，请重试");});}});
        });
        dialog.setContentView(panel);dialog.show();Window w=dialog.getWindow();if(w!=null){w.setBackgroundDrawableResource(android.R.color.transparent);w.setGravity(Gravity.BOTTOM);w.setLayout(-1,(int)(a.getResources().getDisplayMetrics().heightPixels*.76f));w.setDimAmount(.28f);w.setWindowAnimations(R.style.DownloadSheetAnimation);}
    }
    public static void startService(Activity a) {
        try {DownloadService.start(a);}catch(RuntimeException error){toast(a,"后台下载暂时无法启动，请回到 App 后重试");}
        if(Build.VERSION.SDK_INT>=33 && a.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED
                && !a.getPreferences(0).getBoolean("downloads.notificationAsked",false)) {
            a.getPreferences(0).edit().putBoolean("downloads.notificationAsked",true).apply();
            a.requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},2302);
        }
    }
    public static View center(Activity a,Runnable back,OpenBook read,Runnable verify) {
        DownloadRuntime runtime=DownloadRuntime.get(a);
        LinearLayout page=column(a);page.setBackgroundColor(UIHelpers.BG);
        header(a,page,"下载中心",back);
        LinearLayout tools=row(a);page.addView(tools);
        action(a,tools,"全部暂停",runtime::pauseAll);
        action(a,tools,"继续下载",()->{runtime.resumeAll();startService(a);});
        LinearLayout remRow=row(a);ImageView rem=new ImageView(a);rem.setImageResource(R.drawable.rem_reader_resume);
        remRow.addView(rem,new LinearLayout.LayoutParams(dp(a,48),dp(a,48)));
        TextView hint=label(a,"蕾姆会把完整章节收进本地书架",12,UIHelpers.TEXT3);remRow.addView(hint,new LinearLayout.LayoutParams(0,-2,1));page.addView(remRow);
        List<String> books=new ArrayList<>();Map<String,List<Task>> groups=new LinkedHashMap<>();
        Map<String,String> titles=new HashMap<>();
        ListView list=new ListView(a);list.setDividerHeight(0);page.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        BaseAdapter adapter=new BaseAdapter(){
            public int getCount(){return books.size();}public Object getItem(int i){return books.get(i);}public long getItemId(int i){return i;}
            public View getView(int i,View view,ViewGroup parent){
                String id=books.get(i);List<Task> tasks=groups.get(id);
                LinearLayout card=column(a);card.setPadding(dp(a,16),dp(a,14),dp(a,16),dp(a,14));card.setBackgroundColor(UIHelpers.CARD);
                card.addView(label(a,titles.containsKey(id)?titles.get(id):"离线漫画",16,UIHelpers.TEXT));
                int done=0;long bytes=0;String current="";for(Task t:tasks){if(t.state==State.COMPLETED)done++;else current=state(t);bytes+=t.bytes;}
                card.addView(label(a,done+" / "+tasks.size()+" 章 · "+format(bytes)+(current.isEmpty()?"":" · "+current),12,UIHelpers.TEXT3));
                card.setOnClickListener(v->taskSheet(a,id,read,verify));return card;
            }
        };list.setAdapter(adapter);
        Runnable refresh=new Runnable(){public void run(){
            Map<String,String> cached=new HashMap<>(titles);
            runtime.io.execute(()->{
                Map<String,List<Task>> next=new LinkedHashMap<>();
                for(Task t:runtime.store.list()){List<Task> g=next.get(t.bookId);if(g==null){g=new ArrayList<>();next.put(t.bookId,g);}g.add(t);}
                for(String id:next.keySet())if(!cached.containsKey(id)){ComicModels.ComicDetail detail=runtime.store.snapshot(id);cached.put(id,detail==null?"离线漫画":detail.summary.title);}
                a.runOnUiThread(()->{
                    if(!page.isAttachedToWindow()||a.isDestroyed())return;
                    groups.clear();groups.putAll(next);titles.clear();titles.putAll(cached);books.clear();books.addAll(groups.keySet());
                    hint.setText(books.isEmpty()?"还没有下载任务，去漫画详情选择章节吧":"蕾姆会把完整章节收进本地书架");adapter.notifyDataSetChanged();page.postDelayed(this,1500);
                });
            });
        }};
        page.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){public void onViewAttachedToWindow(View v){page.post(refresh);}public void onViewDetachedFromWindow(View v){page.removeCallbacks(refresh);}});
        return page;
    }
    private static void taskSheet(Activity a,String bookId,OpenBook read,Runnable verify) {
        DownloadRuntime runtime=DownloadRuntime.get(a);List<Task> tasks=new ArrayList<>();
        LinearLayout panel=column(a);panel.setPadding(dp(a,16),dp(a,12),dp(a,16),dp(a,16));
        panel.addView(label(a,"章节下载",18,UIHelpers.TEXT));
        LinearLayout tools=row(a);panel.addView(tools);Dialog dialog=new Dialog(a);dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        action(a,tools,"阅读",()->{dialog.dismiss();read.accept(bookId);});
        action(a,tools,"去验证",()->{dialog.dismiss();verify.run();});
        ListView list=new ListView(a);panel.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        BaseAdapter adapter=new BaseAdapter(){public int getCount(){return tasks.size();}public Object getItem(int i){return tasks.get(i);}public long getItemId(int i){return i;}
            public View getView(int i,View old,ViewGroup parent){Task task=tasks.get(i);TextView text=label(a,task.title+"\n"+state(task)+" · "+task.donePages+" / "+task.totalPages+" 页"+(task.error.isEmpty()?"":"\n"+task.error),13,UIHelpers.TEXT);
                text.setMinHeight(dp(a,64));text.setOnClickListener(v->taskActions(a,task));return text;}};
        list.setAdapter(adapter);panel.setBackgroundColor(UIHelpers.CARD);dialog.setContentView(panel);dialog.show();
        Window w=dialog.getWindow();if(w!=null){w.setBackgroundDrawableResource(android.R.color.transparent);w.setGravity(Gravity.BOTTOM);w.setLayout(-1,(int)(a.getResources().getDisplayMetrics().heightPixels*.76f));w.setDimAmount(.28f);w.setWindowAnimations(R.style.DownloadSheetAnimation);}
        Runnable refresh=new Runnable(){public void run(){runtime.io.execute(()->{
            List<Task> next=new ArrayList<>();for(Task t:runtime.store.list())if(t.bookId.equals(bookId))next.add(t);Collections.sort(next,(x,y)->Integer.compare(x.order,y.order));
            a.runOnUiThread(()->{if(!dialog.isShowing()||a.isDestroyed())return;tasks.clear();tasks.addAll(next);adapter.notifyDataSetChanged();list.postDelayed(this,1500);});
        });}};
        list.post(refresh);dialog.setOnDismissListener(d->list.removeCallbacks(refresh));
    }
    private static void taskActions(Activity a,Task task) {
        DownloadRuntime runtime=DownloadRuntime.get(a);boolean completed=task.state==State.COMPLETED;
        String[] options=completed?new String[]{"删除此章","重新下载此章"}:new String[]{"暂停","继续 / 重试","取消并清理本章"};
        ArrayAdapter<String> menu=new ArrayAdapter<String>(a,android.R.layout.simple_list_item_1,options){
            @Override public View getView(int i,View old,ViewGroup parent){TextView view=(TextView)super.getView(i,old,parent);view.setTextColor(UIHelpers.TEXT);return view;}
        };
        AlertDialog dialog=new AlertDialog.Builder(a).setCustomTitle(label(a,task.title,17,UIHelpers.TEXT)).setAdapter(menu,(d,which)->{
            if(completed){confirm(a,"删除此章的下载文件？","阅读进度和在线收藏会保留。",()->{
                runtime.io.execute(()->{try{runtime.deleteChapter(task.id);if(which==1){Task retry=task.copy();retry.state=State.QUEUED;retry.generation=DownloadCoordinator.nextGeneration();retry.failures=0;retry.donePages=0;retry.totalPages=0;retry.bytes=0;retry.error="";retry.nextAttempt=0;synchronized(runtime.queue){if(runtime.store.get(retry.id)==null)runtime.store.save(retry);}}
                    a.runOnUiThread(()->{if(which==1)startService(a);});}catch(Exception error){a.runOnUiThread(()->toast(a,"删除未完成，请重试"));}});
            });}
            else if(which==0)runtime.queue.pause(task.id);
            else if(which==1){
                if(task.state==State.DELETING)runtime.io.execute(()->{try{runtime.deleteChapter(task.id);}catch(Exception error){a.runOnUiThread(()->toast(a,"清理未完成，请重试"));}});
                else {runtime.queue.resume(task.id);startService(a);}
            }
            else confirm(a,"取消本章下载？","只清理这章的未完成文件，其他已下载章节会保留。",()->{
                runtime.queue.cancel(task.id);runtime.io.execute(()->{try{runtime.cancel(task.id);}catch(Exception error){a.runOnUiThread(()->toast(a,"清理未完成，请重试"));}});
            });
        }).create();theme(dialog,a);dialog.show();
    }
    public static View storage(Activity a,Runnable back,Runnable refresh) {
        DownloadRuntime runtime=DownloadRuntime.get(a);LinearLayout page=column(a);page.setBackgroundColor(UIHelpers.BG);header(a,page,"本地存储",back);
        Switch wifi=new Switch(a);wifi.setText("仅 Wi-Fi 下载");wifi.setTextColor(UIHelpers.TEXT);wifi.setPadding(dp(a,16),0,dp(a,16),0);wifi.setMinHeight(dp(a,52));wifi.setChecked(runtime.wifiOnly());wifi.setOnCheckedChangeListener((v,value)->{runtime.wifiOnly(value);if(runtime.hasPending())startService(a);});page.addView(wifi);
        TextView totals=label(a,"正在统计…",13,UIHelpers.TEXT3);page.addView(totals);
        Set<String> selected=new HashSet<>();ListView list=new ListView(a);page.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        List<LocalModels.Book> books=runtime.library.store.listBooks();
        list.setAdapter(new BaseAdapter(){public int getCount(){return books.size();}public Object getItem(int i){return books.get(i);}public long getItemId(int i){return i;}
            public View getView(int i,View old,ViewGroup p){LocalModels.Book book=books.get(i);CheckBox check=old instanceof CheckBox?(CheckBox)old:new CheckBox(a);check.setOnCheckedChangeListener(null);check.setText(book.getDisplayTitle()+" · "+format(book.totalSize));check.setTextColor(UIHelpers.TEXT);check.setMinHeight(dp(a,52));check.setChecked(selected.contains(book.id));check.setOnCheckedChangeListener((v,value)->{if(value)selected.add(book.id);else selected.remove(book.id);});return check;}});
        LinearLayout actions=row(a);page.addView(actions);
        action(a,actions,"清理可再生缓存",()->{runtime.io.execute(()->{runtime.library.storage.clearDerivedPagesCache();a.runOnUiThread(refresh);});});
        action(a,actions,"删除选中漫画",()->{if(selected.isEmpty()){toast(a,"先选择需要删除的漫画");return;}confirm(a,"删除选中的本地漫画？","仅删除 App 中的副本，原文件、在线收藏和阅读记录不受影响。",()->{
            Set<String> ids=new HashSet<>(selected);runtime.io.execute(()->{int failures=0;for(String id:ids){LocalModels.Book b=runtime.library.store.getBook(id);if(b==null)continue;boolean ok=LocalModels.SOURCE_TYPE_DOWNLOAD.equals(b.sourceType)?runtime.deleteBook(id):runtime.library.store.deleteBook(id,runtime.library.storage);if(!ok)failures++;}final int errors=failures;a.runOnUiThread(()->{toast(a,errors==0?"已清理本地副本":"部分文件删除失败，请重试");refresh.run();});});
        });});
        runtime.io.execute(()->{long imported=DownloadRuntime.size(runtime.library.storage.getImportsDir()),downloaded=DownloadRuntime.size(runtime.library.storage.getDownloadsDir()),cache=DownloadRuntime.size(runtime.library.storage.getPagesCacheDir());a.runOnUiThread(()->{if(!a.isDestroyed())totals.setText("导入 "+format(imported)+" · 下载 "+format(downloaded)+"\n可清缓存 "+format(cache)+" · 剩余 "+format(runtime.library.storage.getUsableSpace()));});});
        return page;
    }
    private static void confirm(Activity a,String title,String message,Runnable action) {
        LinearLayout content=row(a);ImageView rem=new ImageView(a);rem.setImageResource(R.drawable.rem_empty);content.addView(rem,new LinearLayout.LayoutParams(dp(a,64),dp(a,64)));
        TextView text=label(a,title+"\n\n"+message,14,UIHelpers.TEXT);content.addView(text,new LinearLayout.LayoutParams(0,-2,1));
        AlertDialog dialog=new AlertDialog.Builder(a).setView(content).setNegativeButton("取消",null).setPositiveButton("确认",(d,w)->action.run()).create();theme(dialog,a);dialog.show();
    }
    private static void theme(AlertDialog dialog,Activity a){dialog.setOnShowListener(d->{
        if(dialog.getWindow()!=null)dialog.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD,dp(a,16),android.graphics.Color.TRANSPARENT));
        Button positive=dialog.getButton(AlertDialog.BUTTON_POSITIVE),negative=dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
        if(positive!=null)positive.setTextColor(UIHelpers.ACCENT);if(negative!=null)negative.setTextColor(UIHelpers.TEXT3);
    });}
    public static String state(Task t){switch(t.state){case QUEUED:return "等待下载";case RESOLVING:return "读取章节";case DOWNLOADING:return "下载中";case VERIFYING:return "校验中";case COMPLETED:return "已完成";case PAUSED_USER:return "已暂停";case WAITING_NETWORK:return "等待 Wi-Fi / 网络";case WAITING_VERIFICATION:return "等待站源验证";case FAILED:return "失败 · 可重试";case CANCELLED:return "已取消";default:return "删除中 · 失败可重试";}}
    public static String format(long bytes){return bytes<1024*1024 ? String.format(Locale.CHINA,"%.1f KB",bytes/1024d) : String.format(Locale.CHINA,"%.1f MB",bytes/1048576d);}
    private static int dp(Activity a,int value){return UIHelpers.dp(a,value);}
    private static LinearLayout column(Activity a){LinearLayout l=new LinearLayout(a);l.setOrientation(LinearLayout.VERTICAL);return l;}
    private static LinearLayout row(Activity a){LinearLayout l=new LinearLayout(a);l.setGravity(Gravity.CENTER_VERTICAL);return l;}
    private static TextView label(Activity a,String text,int size,int color){TextView v=UIHelpers.text(a,text,size,color,Typeface.NORMAL);v.setPadding(dp(a,12),dp(a,8),dp(a,12),dp(a,8));return v;}
    private static void action(Activity a,LinearLayout row,String text,Runnable run){TextView v=label(a,text,13,UIHelpers.ACCENT);v.setGravity(Gravity.CENTER);v.setMinHeight(dp(a,48));v.setOnClickListener(w->run.run());row.addView(v,new LinearLayout.LayoutParams(0,-2,1));}
    private static void header(Activity a,LinearLayout page,String title,Runnable back){LinearLayout row=row(a);TextView close=label(a,"‹",28,UIHelpers.TEXT);close.setContentDescription("返回");close.setMinWidth(dp(a,48));close.setOnClickListener(v->back.run());row.addView(close);row.addView(label(a,title,20,UIHelpers.TEXT));page.addView(row);}
    private static void toast(Activity a,String message){if(!a.isDestroyed())Toast.makeText(a,message,Toast.LENGTH_SHORT).show();}
}
