package com.xxcomic.download;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import com.xxcomic.DownloadSources;
import com.xxcomic.local.*;
import com.xxcomic.source.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import static com.xxcomic.download.DownloadModels.*;

/** Single chapter worker, independent of Activity lifetime. Lock order: queue, files, database. */
public final class DownloadRuntime {
    private static final int MAX_ACTIVE_WORKERS = 2;
    private static DownloadRuntime instance;
    private final Context context;
    public final DownloadStore store;
    public final DownloadCoordinator queue;
    public final LocalLibrary library;
    public final ExecutorService io = Executors.newSingleThreadExecutor();
    private final ExecutorService worker = Executors.newFixedThreadPool(MAX_ACTIVE_WORKERS);
    private final Set<String> activeWorkers = new HashSet<>();
    private volatile boolean initialized;
    public static synchronized DownloadRuntime get(Context context) {
        if (instance == null) instance = new DownloadRuntime(context.getApplicationContext());
        return instance;
    }
    private DownloadRuntime(Context context) {
        this.context=context; library=LocalLibrary.get(context); store=new DownloadStore(context);
        queue=new DownloadCoordinator(store);
        io.execute(() -> {
            queue.recover();
            // A crash between file deletion and index deletion is safely resumable.
            for (Task task:store.list()) if (task.state==State.DELETING) {
                try { deleteChapter(task.id); } catch (IOException ignored) { }
            }
            synchronized(queue) { synchronized(library.storage) {
                for(Task task:store.list()) {
                    if(task.state==State.COMPLETED || task.state==State.DELETING)continue;
                    try {
                        File directory=library.storage.getDownloadFile(task.bookId+"/"+task.id);
                        File[] files=directory.listFiles();if(files!=null)for(File file:files)if(file.getName().endsWith(".part"))file.delete();
                        LocalModels.Chapter published=library.store.getChapter(task.id);
                        if(published!=null && task.state!=State.DELETING) {
                            List<DownloadStore.Page> pages=store.pages(task.id);boolean complete=pages.size()==published.pageCount;
                            for(DownloadStore.Page page:pages)complete&=valid(page);
                            if(complete) {task=task.copy();task.state=State.COMPLETED;task.donePages=pages.size();task.totalPages=pages.size();store.save(task);}
                        }
                    } catch(IOException ignored) { }
                }
            } }
            initialized=true;
        });
    }
    public boolean wifiOnly() { return context.getSharedPreferences("xx-comic",0).getBoolean("downloads.wifiOnly",true); }
    public void wifiOnly(boolean value) { context.getSharedPreferences("xx-comic",0).edit().putBoolean("downloads.wifiOnly",value).apply(); }
    public boolean connected() { NetworkInfo n=network(); return n!=null && n.isConnected(); }
    private NetworkInfo network() { return ((ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE)).getActiveNetworkInfo(); }
    private boolean wifi() {
        ConnectivityManager cm=(ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo n=network();if(n==null||!n.isConnected())return false;
        if(n.getType()==ConnectivityManager.TYPE_WIFI)return true;
        if(n.getType()==ConnectivityManager.TYPE_VPN)for(android.net.Network network:cm.getAllNetworks()) {
            android.net.NetworkCapabilities c=cm.getNetworkCapabilities(network);
            if(c!=null&&c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)&&c.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET))return true;
        }
        return false;
    }
    public void enqueue(ComicModels.ComicDetail detail,List<String> selected) {
        synchronized(queue) {
            store.saveSnapshot(detail);
            queue.enqueue(detail.summary.sourceId,detail.summary.comicId,detail.chapters,selected);
        }
    }
    public void enqueueFiles(ComicModels.ComicDetail detail,List<FileResource> files,List<String> selected) {
        synchronized(queue) {
            store.saveSnapshot(detail);
            queue.enqueueFiles(detail.summary.sourceId,detail.summary.comicId,files,selected);
        }
    }
    public void kick() {
        if (!initialized) return;
        while (true) {
            Task task;
            synchronized (this) {
                if (activeWorkers.size() >= MAX_ACTIVE_WORKERS) return;
                task = queue.claim(System.currentTimeMillis(), connected(), wifi(), wifiOnly(),
                        MAX_ACTIVE_WORKERS, MAX_ACTIVE_WORKERS);
                if (task == null) return;
                activeWorkers.add(task.id);
            }
            worker.execute(() -> {
                try {
                    download(task);
                } finally {
                    synchronized (DownloadRuntime.this) {
                        activeWorkers.remove(task.id);
                    }
                    kick();
                }
            });
        }
    }
    public boolean hasPending() {
        for(Task t:store.list()) if(active(t.state) || t.state==State.QUEUED || t.state==State.WAITING_NETWORK)return true;
        return false;
    }
    public void pauseAll() { for(Task t:store.list()) if(active(t.state)||t.state==State.QUEUED||t.state==State.WAITING_NETWORK)queue.pause(t.id); }
    public void resumeAll() { for(Task t:store.list()) if(t.state==State.PAUSED_USER)queue.resume(t.id); }
    public void stopWorker() { for(Task t:store.list()) if(active(t.state))queue.waitForNetwork(t); }
    private void check(Task lease) throws IOException {
        if(!queue.isCurrent(lease))throw new InterruptedIOException("任务已暂停或取消");
        if(!connected() || (wifiOnly()&&!wifi())) {queue.waitForNetwork(lease);throw new InterruptedIOException("等待网络");}
        if(!library.storage.hasSufficientSpace(65536))throw new NoSpaceException();
    }
    private static final class NoSpaceException extends IOException {NoSpaceException(){super("空间不足，请清理后继续");}}
    private void download(Task task) {
        if (task.isFileTask) {
            downloadFile(task);
            return;
        }
        try {
            check(task);
            DownloadSources adapter=new DownloadSources(context,task.sourceId);
            ComicModels.ChapterPage chapter=adapter.source.chapter(task.url);
            check(task);
            // Existing sources resolve within-chapter pagination themselves. Baozi's nextPageUrl is NEXT CHAPTER.
            List<String> urls=new ArrayList<>(new LinkedHashSet<>(chapter.imageUrls));
            if(urls.isEmpty())throw new IOException("章节没有可下载的图片");
            Map<Integer,DownloadStore.Page> saved=new HashMap<>();
            for(DownloadStore.Page page:store.pages(task.id))saved.put(page.index,page);
            long bytes=0; List<DownloadStore.Page> completed=new ArrayList<>();
            for(int i=0;i<urls.size();i++) {
                check(task);
                String image=GmhComicSource.migrateImageUrl(urls.get(i));
                DownloadStore.Page page=saved.get(i);
                // Signed URLs may expire. Stable path + whole-file hash are required before page reuse.
                if(page==null || !sameImage(page.url,image) || !valid(page)) {
                    String path=task.bookId+"/"+task.id+"/"+i+".img";
                    File target=library.storage.getDownloadFile(path);
                    File part=new File(target.getParentFile(),i+"."+task.generation+".part");
                    synchronized(queue) { synchronized(library.storage) {
                        if(!queue.isCurrent(task))throw new InterruptedIOException("任务已停止");
                        if(!target.getParentFile().exists()&&!target.getParentFile().mkdirs())throw new IOException("无法创建下载目录");
                    } }
                    SourceImageFetcher.Result result=new SourceImageFetcher().fetch(task.sourceId,image,adapter.referer(task.url),part,
                            Collections.emptyMap(),in->adapter.decode(image,in),()->check(task),DownloadRuntime::validateImage);
                    synchronized(queue) {
                        synchronized(library.storage) {
                            if(!queue.isCurrent(task)) {part.delete();throw new InterruptedIOException("任务已停止");}
                            if(target.exists()&&!target.delete())throw new IOException("旧页面无法替换");
                            if(!part.renameTo(target))throw new IOException("图片保存失败");
                            page=new DownloadStore.Page(i,imageIdentity(image),path,result.hash,result.bytes); store.savePage(task.id,page);
                        }
                    }
                }
                completed.add(page); bytes+=page.bytes;
                queue.update(task,State.DOWNLOADING,i+1,urls.size(),bytes);
            }
            check(task); queue.update(task,State.VERIFYING,urls.size(),urls.size(),bytes);
            downloadCover(task,adapter);
            synchronized(queue) { synchronized(library.storage) {
                if(!queue.isCurrent(task))return;
                publish(task,completed);
                queue.complete(task);
            } }
        } catch(Exception error) {
            if(error instanceof VerificationRequiredException)queue.waitForVerification(task);
            else if(error instanceof NoSpaceException || (error instanceof SourceImageFetcher.HttpFailure && ((SourceImageFetcher.HttpFailure)error).status==403)) {
                synchronized(queue) {if(queue.isCurrent(task)){queue.pause(task.id);Task paused=store.get(task.id).copy();paused.error=error instanceof NoSpaceException?error.getMessage():"图片拒绝访问，请检查站源验证后重试";store.save(paused);}}
            }
            else {
                long retry=error instanceof SourceImageFetcher.HttpFailure ? ((SourceImageFetcher.HttpFailure)error).retryAfter:0;
                if(error.getMessage()!=null && error.getMessage().contains("429"))retry=Math.max(retry,60000);
                queue.failed(task,System.currentTimeMillis(),safeError(error),retry);
            }
        }
    }
    private void downloadFile(Task task) {
        File target=null,work=null;
        boolean published=false;
        try {
            check(task);
            DownloadSources adapter=new DownloadSources(context,task.sourceId);
            if(!(adapter.source instanceof FileSourceCapability))throw new IOException("站源不支持文件下载");
            work=library.storage.getDownloadFile(task.bookId+"/pending");
            // One worker owns all file transfers; no old writer can race a resumed task.
            File part=new File(work,"content.part");
            task.refreshCount=0;
            final long[] lastProgress={0};
            FileDownloadWorker.Result result=new FileDownloadWorker().download(task,(FileSourceCapability)adapter.source,part,
                    ()->check(task),(bytes,total)->{
                        long now=android.os.SystemClock.elapsedRealtime();
                        if(now-lastProgress[0]>=250 || bytes==total){queue.update(task,State.DOWNLOADING,0,1,bytes);lastProgress[0]=now;}
                    });
            check(task);queue.update(task,State.VERIFYING,0,1,result.bytes);
            target=new File(work,task.bookId+"_"+task.generation+"."+result.detectedFormat);
            synchronized(queue) {synchronized(library.storage) {
                check(task);
                if(target.exists() || !part.renameTo(target))throw new IOException("文件保存失败");
            }}
            ComicModels.ComicDetail snapshot=store.snapshot(bookId(task.sourceId,task.comicId));
            String title=(snapshot==null?"":snapshot.summary.title+" · ")+task.title;
            LocalModels.ImportProgressCallback callback=new LocalModels.ImportProgressCallback() {
                public void onProgress(long current,long total,String message) { }
                public boolean isCancelled() {
                    try {check(task);return false;}catch(IOException error){return true;}
                }
            };
            LocalImporter.PreparedFile prepared=new LocalImporter(context,library.storage,library.store)
                    .prepareDownloadedFile(target,task.bookId,title,result.detectedFormat,result.hash,work,callback);
            synchronized(queue) {synchronized(library.storage) {
                check(task);
                LocalModels.Book old=library.store.getBook(task.bookId);
                File destination=library.storage.getBookImportFile(prepared.book.relativePath);
                if(destination.exists() || !target.renameTo(destination))throw new IOException("本地文件发布失败");
                target=destination;
                library.store.commitImport(prepared.book,prepared.index.chapters,prepared.index.pagesByChapter);
                published=true;
                // Clear regenerated pages/Kindle representation only after the new index is durable.
                library.storage.clearDerivedPagesForBook(task.bookId);
                library.storage.deleteRecursively(library.storage.getDerivedBookFile(task.bookId,".epub"));
                if(old!=null) {
                    File previous=library.storage.getBookContentFile(old);
                    if(!previous.equals(target))library.storage.deleteRecursively(previous);
                    if(old.coverPath!=null && !old.coverPath.equals(prepared.book.coverPath))library.storage.deleteRecursively(new File(old.coverPath));
                }
                Task saved=store.get(task.id).copy();
                saved.revision=task.revision;saved.sha256=task.sha256;saved.expectedBytes=task.expectedBytes;
                saved.bytes=result.bytes;saved.donePages=1;saved.totalPages=1;store.save(saved);
                queue.complete(task);
                library.storage.deleteRecursively(work);
            }}
        } catch(Exception error) {
            if(error instanceof VerificationRequiredException)queue.waitForVerification(task);
            else if(error instanceof NoSpaceException || error instanceof SourceImageFetcher.HttpFailure
                    && (((SourceImageFetcher.HttpFailure)error).status==401 || ((SourceImageFetcher.HttpFailure)error).status==403)) {
                synchronized(queue){if(queue.isCurrent(task)){queue.pause(task.id);Task t=store.get(task.id).copy();t.error="文件下载需要检查空间或站源权限后重试";store.save(t);}}
            } else queue.failed(task,System.currentTimeMillis(),safeError(error),error instanceof SourceImageFetcher.HttpFailure?((SourceImageFetcher.HttpFailure)error).retryAfter:0);
        } finally {
            if(!published && target!=null)synchronized(library.storage){library.storage.deleteRecursively(target);}
            synchronized(queue) {synchronized(library.storage) {
                Task current=store.get(task.id);
                if(work!=null && (current==null || current.state==State.DELETING || current.state==State.CANCELLED))library.storage.deleteRecursively(work);
            }}
        }
    }
    private static String safeError(Exception error) {
        if(error instanceof InterruptedIOException)return "网络中断，请稍后重试";
        String message=error.getMessage();
        if(message==null)return "下载失败，请重试";
        // Do not persist signed request URLs or credentials from source exceptions.
        return message.replaceAll("https?://\\S+","[链接]").replaceAll("(?i)(token|cookie|authorization)=\\S+","$1=[隐藏]");
    }
    public static boolean sameImage(String a,String b) { return imageIdentity(a).equals(imageIdentity(b)); }
    public static String imageIdentity(String url) {
        java.util.regex.Matcher scramble=java.util.regex.Pattern.compile("[?&]scramble_id=(\\d+)").matcher(url);
        return url.split("[?#]",2)[0]+(scramble.find()?"?scramble_id="+scramble.group(1):"");
    }
    private void downloadCover(Task task,DownloadSources adapter) {
        File part=null;
        try {
            ComicModels.ComicDetail detail=store.snapshot(task.bookId);String url=detail.summary.coverUrl;
            if(url==null || !url.startsWith("http"))return;
            File target=library.storage.getDownloadFile(task.bookId+"/cover.img");if(target.isFile()&&target.length()>0)return;
            part=new File(target.getParentFile(),"cover."+task.generation+".part");
            new SourceImageFetcher().fetch(task.sourceId,url,adapter.config.referer,part,Collections.emptyMap(),in->adapter.decode(url,in),()->check(task),DownloadRuntime::validateImage);
            synchronized(queue) {synchronized(library.storage){if(queue.isCurrent(task)&&!target.exists())part.renameTo(target);}}
        } catch(Exception ignored) { /* First readable page is the offline fallback cover. */ }
        finally {if(part!=null)part.delete();}
    }
    private boolean valid(DownloadStore.Page page) throws IOException {
        synchronized(library.storage) {
            File file=library.storage.getDownloadFile(page.path);
            return file.isFile()&&file.length()==page.bytes&&hash(file).equals(page.hash);
        }
    }
    public static String hash(File file) throws IOException {
        try {
            MessageDigest digest=MessageDigest.getInstance("SHA-256");
            try(InputStream in=new FileInputStream(file)) {byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;)digest.update(b,0,n);}
            StringBuilder s=new StringBuilder();for(byte b:digest.digest())s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();
        } catch(java.security.NoSuchAlgorithmException impossible) {throw new IOException(impossible);}
    }
    public static void validateImage(File file) throws IOException {
        BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getAbsolutePath(),o);
        if(o.outWidth<=0||o.outHeight<=0)throw new IOException("图片无法解码，请重试");
        o.inJustDecodeBounds=false;o.inSampleSize=1;
        while(Math.max(o.outWidth,o.outHeight)/o.inSampleSize>512)o.inSampleSize*=2;
        Bitmap bitmap=BitmapFactory.decodeFile(file.getAbsolutePath(),o);
        if(bitmap==null)throw new IOException("图片内容不完整");bitmap.recycle();
    }
    private void publish(Task task,List<DownloadStore.Page> downloaded) throws IOException {
        ComicModels.ComicDetail detail=store.snapshot(task.bookId);
        if(detail==null)throw new IOException("下载目录快照缺失");
        List<LocalModels.Page> pages=new ArrayList<>();
        for(DownloadStore.Page page:downloaded) {
            File file=library.storage.getDownloadFile(page.path);
            if(!file.isFile()||file.length()!=page.bytes)throw new IOException("图片校验失败，请重试");
            // Only the JM scramble identity is kept, not arbitrary signed query parameters.
            String transform=null;
            if(task.sourceId.equals("jmcomic")) {
                java.util.regex.Matcher m=java.util.regex.Pattern.compile("[?&]scramble_id=(\\d+)").matcher(page.url);
                if(m.find())transform="jm:"+page.url.split("[?#]",2)[0]+"?scramble_id="+m.group(1);
            }
            pages.add(new LocalModels.Page(task.id+"_"+page.index,task.bookId,task.id,page.index,
                    page.path.substring(task.bookId.length()+1),0,0,transform,"image/*"));
        }
        Set<String> keep=new HashSet<>();for(DownloadStore.Page page:downloaded)keep.add(new File(page.path).getName());
        File[] oldFiles=library.storage.getDownloadFile(task.bookId+"/"+task.id).listFiles();
        if(oldFiles!=null)for(File file:oldFiles)if(!keep.contains(file.getName())&&!file.delete())throw new IOException("旧页面清理失败");
        store.replacePages(task.id,downloaded);
        long now=System.currentTimeMillis();
        LocalModels.Book old=library.store.getBook(task.bookId);
        LocalLibraryStore.DeletedFingerprint deleted=library.store.findDeletedByFingerprint(task.bookId);
        LocalModels.Book book=new LocalModels.Book(task.bookId,task.bookId,detail.summary.title,
                old!=null?old.userTitle:deleted==null?null:deleted.userTitle,LocalModels.FORMAT_FOLDER,LocalModels.SOURCE_TYPE_DOWNLOAD,
                task.comicId,task.bookId,library.storage.getDownloadFile(task.bookId+"/cover.img").isFile()?library.storage.getDownloadFile(task.bookId+"/cover.img").getAbsolutePath():null,
                size(library.storage.getDownloadFile(task.bookId)),1,pages.size(),LocalModels.STATUS_READY,now,now);
        library.store.publishDownloadedChapter(book,new LocalModels.Chapter(task.id,task.bookId,task.order,task.title,task.chapterId,pages.size()),pages);
    }
    public ComicModels.ChapterPage localChapter(ComicModels.ComicDetail detail,int index) throws IOException {
        ComicModels.Chapter chapter=detail.chapters.get(index);
        String taskId=key(detail.summary.sourceId,detail.summary.comicId,chapter.chapterId);
        Task task=store.get(taskId);
        if(task==null||task.state!=State.COMPLETED)return null;
        synchronized(library.storage) {
            LocalModels.Book book=library.store.getBook(task.bookId);
            if(book==null||!LocalModels.STATUS_READY.equals(book.status))return null;
            List<DownloadStore.Page> pages=store.pages(taskId);
            if(pages.size()!=task.totalPages)throw new IOException("下载文件损坏，请到下载中心重试本章");
            List<String> urls=new ArrayList<>();
            for(DownloadStore.Page page:pages) {
                if(!valid(page))throw new IOException("下载文件缺失或损坏，请到下载中心重新下载本章");
                urls.add(LocalContentResolver.buildPageUrl(taskId+"_"+page.index));
            }
            return new ComicModels.ChapterPage(chapter.chapterId,chapter.title,urls,"");
        }
    }
    public void cancel(String id) throws IOException {
        synchronized(queue) {
            Task task=store.get(id);if(task==null||task.state==State.COMPLETED)return;queue.cancel(id);
            if(task.isFileTask) {
                synchronized(library.storage){library.storage.deleteRecursively(library.storage.getDownloadFile(task.bookId));store.remove(id);}
                return; // A cancelled replacement leaves the previously published volume readable.
            }
        }
        // Generation checks prevent an old stream from publishing after deletion.
        deleteChapter(id);
    }
    public void deleteChapter(String id) throws IOException {
        synchronized(queue) { synchronized(library.storage) {
            Task task=store.get(id);if(task==null)return;
            if(task.isFileTask){if(!deleteBook(task.bookId))throw new IOException("文件未能完全删除，请重试");return;}
            task=task.copy();task.generation=DownloadCoordinator.nextGeneration();task.state=State.DELETING;store.save(task);
            if(!library.storage.deleteRecursively(library.storage.getDownloadFile(task.bookId+"/"+task.id)))throw new IOException("文件未能完全删除，请重试");
            library.store.removeDownloadedChapter(task.bookId,task.id,size(library.storage.getDownloadFile(task.bookId)));
            if(library.store.getChapters(task.bookId).isEmpty()) {
                boolean otherTasks=false;for(Task other:store.list())if(other.bookId.equals(task.bookId)&&!other.id.equals(task.id))otherTasks=true;
                if(!otherTasks && !library.storage.deleteRecursively(library.storage.getDownloadFile(task.bookId)))throw new IOException("封面文件清理失败，请重试");
                LocalModels.Book book=library.store.getBook(task.bookId);
                if(book!=null) {library.store.markDeleting(book.id);library.store.completeDeletion(book.id);}
            }
            store.remove(id);
        } }
    }
    public boolean deleteBook(String bookId) {
        synchronized(queue) { synchronized(library.storage) {
            try {
                for(Task t:store.list())if(t.bookId.equals(bookId)) {t=t.copy();t.generation=DownloadCoordinator.nextGeneration();t.state=State.DELETING;store.save(t);}
                if(library.store.getBook(bookId)!=null) {
                    if(!library.store.deleteBook(bookId,library.storage))return false;
                } else if(!library.storage.deleteRecursively(library.storage.getDownloadFile(bookId)))return false;
                if(!library.storage.deleteRecursively(library.storage.getDownloadFile(bookId)))return false;
                for(Task t:store.list())if(t.bookId.equals(bookId))store.remove(t.id);
                return true;
            } catch(Exception error) {return false;}
        } }
    }
    public static long size(File file) {
        if(!file.exists())return 0;if(file.isFile())return file.length();long total=0;
        File[] children=file.listFiles();if(children!=null)for(File child:children)total+=size(child);return total;
    }
}
