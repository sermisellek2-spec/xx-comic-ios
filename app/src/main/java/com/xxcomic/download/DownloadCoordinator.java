package com.xxcomic.download;
import com.xxcomic.source.ComicModels;
import java.util.List;
import java.util.HashSet;
import java.util.Set;
import static com.xxcomic.download.DownloadModels.*;
public final class DownloadCoordinator {
    private static final java.util.concurrent.atomic.AtomicLong generations = new java.util.concurrent.atomic.AtomicLong(System.currentTimeMillis()*1000);
    public static long nextGeneration() { return generations.incrementAndGet(); }
    public interface Repository { List<DownloadModels.Task> list(); DownloadModels.Task get(String id); void save(DownloadModels.Task task); }
    private final Repository repository;
    public DownloadCoordinator(Repository repository) { this.repository=repository; }
    public synchronized void enqueue(String source, String comic, List<ComicModels.Chapter> chapters, List<String> selected) {
        Set<String> wanted=new HashSet<>(selected);
        for(int i=0;i<chapters.size();i++) {
            ComicModels.Chapter ch=chapters.get(i);
            if(!wanted.contains(ch.chapterId)) continue;
            String id=key(source,comic,ch.chapterId);
            Task existing=repository.get(id);
            if(existing!=null) continue;
            Task t=new Task(); t.id=id; t.bookId=bookId(source,comic);
            t.sourceId=source; t.comicId=comic; t.chapterId=ch.chapterId;
            t.title=ch.title; t.url=ch.url; t.order=i; repository.save(t);
        }
    }
    public synchronized void enqueueFiles(String source, String comic, List<com.xxcomic.source.FileResource> files, List<String> selected) {
        Set<String> wanted=new HashSet<>(selected);
        files=new java.util.ArrayList<>(files);
        java.util.Collections.sort(files,(a,b)->Integer.compare(a.order,b.order));
        for(int i=0;i<files.size();i++) {
            com.xxcomic.source.FileResource f=files.get(i);
            if(!wanted.contains(f.fileId)) continue;
            String id=fileTaskId(source,comic,f.fileId);
            Task existing=repository.get(id);
            if(existing!=null && (existing.state!=State.COMPLETED ||
                    (java.util.Objects.equals(existing.revision,f.revision) && java.util.Objects.equals(existing.sha256,f.sha256)))) continue;
            Task t=new Task(); t.id=id; t.bookId=fileBookId(source,comic,f.fileId);
            t.sourceId=source; t.comicId=comic; t.chapterId=f.fileId;
            t.title=f.title; t.url=""; t.order=f.order>=0?f.order:i;
            t.isFileTask=true; t.fileId=f.fileId; t.revision=f.revision;
            t.expectedFormat=f.expectedFormat; t.sha256=f.sha256;
            t.expiresAt=f.expiresAt; t.totalPages=1; t.donePages=0;
            t.expectedBytes=f.bytes;
            repository.save(t);
        }
    }
    public synchronized Task claim(long now, boolean connected, boolean wifi, boolean wifiOnly) {
        List<Task> tasks=repository.list();
        for(Task t:tasks) if(active(t.state)) return null;
        for(Task original:tasks) {
            if(original.state!=State.QUEUED && original.state!=State.WAITING_NETWORK) continue;
            Task t=original.copy();
            if(!connected || (wifiOnly && !wifi)) {
                t.state=State.WAITING_NETWORK; repository.save(t); continue;
            }
            if(t.nextAttempt>now) continue;
            t.state=State.RESOLVING; t.generation=nextGeneration(); repository.save(t); return t.copy();
        }
        return null;
    }
    public synchronized boolean isCurrent(Task lease) {
        Task t=repository.get(lease.id);
        return t!=null && t.generation==lease.generation && active(t.state);
    }
    public synchronized boolean update(Task lease,State state,int done,int total,long bytes) {
        if(!isCurrent(lease)) return false;
        Task t=repository.get(lease.id).copy(); t.state=state;
        t.donePages=done; t.totalPages=total; t.bytes=bytes; repository.save(t); return true;
    }
    public synchronized boolean complete(Task lease) {
        if(!isCurrent(lease)) return false;
        Task t=repository.get(lease.id).copy(); t.state=State.COMPLETED; t.error="";
        repository.save(t); return true;
    }
    private void change(String id,State state,boolean reset) {
        Task found=repository.get(id); if(found==null || found.state==State.COMPLETED || found.state==State.DELETING) return;
        Task t=found.copy(); t.generation=nextGeneration(); t.state=state;
        if(reset) { t.failures=0; t.nextAttempt=0; t.error=""; }
        repository.save(t);
    }
    public synchronized void pause(String id) { change(id,State.PAUSED_USER,false); }
    public synchronized void resume(String id) { change(id,State.QUEUED,true); }
    public synchronized void cancel(String id) { change(id,State.CANCELLED,false); }
    public synchronized void waitForNetwork(Task lease) {
        if(isCurrent(lease)) change(lease.id,State.WAITING_NETWORK,false);
    }
    public synchronized void waitForVerification(Task lease) {
        if(!isCurrent(lease)) return;
        for(Task t:repository.list()) {
            if(t.sourceId.equals(lease.sourceId) && (active(t.state) || t.state==State.QUEUED || t.state==State.WAITING_NETWORK))
                change(t.id,State.WAITING_VERIFICATION,false);
        }
    }
    public synchronized void verificationReady(String source) {
        for(Task t:repository.list()) if(source.equals(t.sourceId) && t.state==State.WAITING_VERIFICATION) resume(t.id);
    }
    public synchronized void failed(Task lease,long now,String error,long retryAfter) {
        if(!isCurrent(lease)) return;
        Task t=repository.get(lease.id).copy(); t.failures++; t.generation=nextGeneration(); t.error=error;
        long[] delays={2000,5000,15000};
        t.state=t.failures>delays.length ? State.FAILED : State.QUEUED;
        t.nextAttempt=now+Math.max(t.failures<=delays.length ? delays[t.failures-1] : 0,
                Math.min(15*60*1000,Math.max(0,retryAfter)));
        repository.save(t);
        if (retryAfter > 0) for (Task other : repository.list()) {
            if (other.sourceId.equals(t.sourceId) && (other.state == State.QUEUED || other.state == State.WAITING_NETWORK)) {
                Task delayed = other.copy(); delayed.nextAttempt = Math.max(delayed.nextAttempt, t.nextAttempt); repository.save(delayed);
            }
        }
    }
    public synchronized void recover() {
        for(Task t:repository.list()) if(active(t.state)) change(t.id,State.QUEUED,false);
    }
}
