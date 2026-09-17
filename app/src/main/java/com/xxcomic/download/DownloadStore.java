package com.xxcomic.download;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import com.xxcomic.source.ComicModels;
import java.io.File;
import java.util.*;
import org.json.*;
import static com.xxcomic.download.DownloadModels.*;

/** Queue lives beside the local library, outside Android backup and disposable cache. */
public final class DownloadStore implements DownloadCoordinator.Repository {
    private final SQLiteDatabase db;
    public DownloadStore(Context context) {
        this(new File(context.getNoBackupFilesDir(),"database/downloads.db"));
    }
    public DownloadStore(File file) {
        File parent=file.getParentFile(); if(!parent.exists() && !parent.mkdirs()) throw new IllegalStateException("无法创建下载数据库");
        db=SQLiteDatabase.openOrCreateDatabase(file,null); db.enableWriteAheadLogging();
        db.beginTransactionNonExclusive();
        try {
            db.execSQL("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, book_id TEXT NOT NULL, data TEXT NOT NULL)");
            db.execSQL("CREATE INDEX IF NOT EXISTS tasks_book ON tasks(book_id)");
            db.execSQL("CREATE TABLE IF NOT EXISTS snapshots (id TEXT PRIMARY KEY, data TEXT NOT NULL)");
            db.execSQL("CREATE TABLE IF NOT EXISTS downloaded_pages (task_id TEXT NOT NULL, page_index INTEGER NOT NULL, url TEXT NOT NULL, path TEXT NOT NULL, hash TEXT NOT NULL, bytes INTEGER NOT NULL, PRIMARY KEY(task_id,page_index))");
            db.setVersion(1); db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }
    public synchronized List<Task> list() {
        List<Task> tasks=new ArrayList<>();
        try(Cursor c=db.rawQuery("SELECT data FROM tasks ORDER BY rowid",null)) {
            while(c.moveToNext()) tasks.add(parseTask(c.getString(0)));
        } return tasks;
    }
    public synchronized Task get(String id) {
        try(Cursor c=db.rawQuery("SELECT data FROM tasks WHERE id=?",new String[]{id})) {
            return c.moveToFirst()?parseTask(c.getString(0)):null;
        }
    }
    public synchronized void save(Task t) {
        try {
            JSONObject j=serializeTask(t);
            ContentValues values=new ContentValues(); values.put("id",t.id); values.put("book_id",t.bookId); values.put("data",j.toString());
            // UPDATE preserves FIFO rowid; a replacement would move the current task to the end.
            if(db.update("tasks",values,"id=?",new String[]{t.id})==0) db.insertOrThrow("tasks",null,values);
        } catch(JSONException error) { throw new IllegalStateException(error); }
    }
    public static JSONObject serializeTask(Task t) throws JSONException {
        JSONObject j=new JSONObject();
        j.put("id",t.id).put("book",t.bookId).put("source",t.sourceId).put("comic",t.comicId)
                .put("chapter",t.chapterId).put("title",t.title).put("url",t.isFileTask ? "" : t.url).put("order",t.order)
                .put("generation",t.generation).put("failures",t.failures).put("next",t.nextAttempt)
                .put("state",t.state.name()).put("error",t.error).put("done",t.donePages).put("total",t.totalPages).put("bytes",t.bytes)
                .put("is_file",t.isFileTask).put("file_id",t.fileId).put("revision",t.revision)
                .put("format",t.expectedFormat).put("sha256",t.sha256).put("expires_at",t.expiresAt)
                .put("refresh_count",t.refreshCount).put("expected_bytes",t.expectedBytes);
        return j;
    }
    public static Task parseTask(String raw) {
        try {
            JSONObject j=new JSONObject(raw); Task t=new Task();
            t.id=j.getString("id"); t.bookId=j.getString("book"); t.sourceId=j.getString("source"); t.comicId=j.getString("comic");
            t.chapterId=j.getString("chapter"); t.title=j.getString("title"); t.url=j.getString("url"); t.order=j.getInt("order");
            t.generation=j.optLong("generation"); t.failures=j.optInt("failures"); t.nextAttempt=j.optLong("next");
            t.state=State.valueOf(j.getString("state")); t.error=j.optString("error");
            t.donePages=j.optInt("done"); t.totalPages=j.optInt("total"); t.bytes=j.optLong("bytes");
            t.isFileTask=j.optBoolean("is_file",false);
            t.fileId=j.optString("file_id",null);
            t.revision=j.optString("revision","");
            t.expectedFormat=j.optString("format","");
            t.sha256=j.has("sha256") && !j.isNull("sha256") ? j.optString("sha256",null) : null;
            t.expiresAt=j.optLong("expires_at",0L);
            t.refreshCount=j.optInt("refresh_count",0);
            t.expectedBytes=j.optLong("expected_bytes",-1);
            return t;
        } catch(Exception e) { throw new IllegalStateException("下载任务记录损坏",e); }
    }
    public synchronized void saveSnapshot(ComicModels.ComicDetail detail) {
        try {
            ComicModels.ComicSummary s=detail.summary;
            JSONObject j=new JSONObject().put("source",s.sourceId).put("comic",s.comicId).put("title",s.title)
                    .put("cover",s.coverUrl).put("author",detail.author).put("description",detail.description).put("status",detail.status);
            JSONArray chapters=new JSONArray();
            for(ComicModels.Chapter c:detail.chapters) chapters.put(new JSONObject().put("id",c.chapterId).put("title",c.title)
                    .put("url",c.url).put("section",c.sectionSlot).put("slot",c.chapterSlot));
            j.put("chapters",chapters);
            ContentValues v=new ContentValues(); v.put("id",bookId(s.sourceId,s.comicId)); v.put("data",j.toString());
            if(db.insertWithOnConflict("snapshots",null,v,SQLiteDatabase.CONFLICT_REPLACE)==-1) throw new IllegalStateException("无法保存下载目录");
        } catch(JSONException e) { throw new IllegalStateException(e); }
    }
    public synchronized ComicModels.ComicDetail snapshot(String id) {
        try(Cursor c=db.rawQuery("SELECT data FROM snapshots WHERE id=?",new String[]{id})) {
            if(!c.moveToFirst()) return null;
            JSONObject j=new JSONObject(c.getString(0)); List<ComicModels.Chapter> chapters=new ArrayList<>(); JSONArray array=j.getJSONArray("chapters");
            for(int i=0;i<array.length();i++) { JSONObject ch=array.getJSONObject(i); chapters.add(new ComicModels.Chapter(ch.getString("id"),ch.getString("title"),ch.getString("url"),ch.optInt("section"),ch.optInt("slot"))); }
            return new ComicModels.ComicDetail(new ComicModels.ComicSummary(j.getString("source"),j.getString("comic"),j.getString("title"),j.optString("cover"),"离线下载",Collections.emptyList()),j.optString("author"),j.optString("status"),j.optString("description"),"",chapters);
        } catch(JSONException e) { throw new IllegalStateException("下载目录记录损坏",e); }
    }
    public static final class Page {
        public final int index; public final String url,path,hash; public final long bytes;
        public Page(int index,String url,String path,String hash,long bytes) { this.index=index; this.url=url; this.path=path; this.hash=hash; this.bytes=bytes; }
    }
    public synchronized List<Page> pages(String task) {
        List<Page> pages=new ArrayList<>();
        try(Cursor c=db.rawQuery("SELECT page_index,url,path,hash,bytes FROM downloaded_pages WHERE task_id=? ORDER BY page_index",new String[]{task})) {
            while(c.moveToNext()) pages.add(new Page(c.getInt(0),c.getString(1),c.getString(2),c.getString(3),c.getLong(4)));
        } return pages;
    }
    public synchronized void savePage(String task,Page page) {
        ContentValues v=new ContentValues(); v.put("task_id",task); v.put("page_index",page.index); v.put("url",page.url); v.put("path",page.path); v.put("hash",page.hash); v.put("bytes",page.bytes);
        if(db.insertWithOnConflict("downloaded_pages",null,v,SQLiteDatabase.CONFLICT_REPLACE)==-1) throw new IllegalStateException("无法保存下载页面");
    }
    public synchronized void clearPages(String task) { db.delete("downloaded_pages","task_id=?",new String[]{task}); }
    public synchronized void replacePages(String task,List<Page> pages) {
        db.beginTransactionNonExclusive();try {clearPages(task);for(Page page:pages)savePage(task,page);db.setTransactionSuccessful();}finally {db.endTransaction();}
    }
    public synchronized void remove(String task) {
        db.beginTransactionNonExclusive(); try { clearPages(task); db.delete("tasks","id=?",new String[]{task}); db.setTransactionSuccessful(); } finally { db.endTransaction(); }
    }
    public synchronized void close() { db.close(); }
}
