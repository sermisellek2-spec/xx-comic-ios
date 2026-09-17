package com.xxcomic.download;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Persistent identity never depends on title, directory display order or signed image URLs. */
public final class DownloadModels {
    public enum State { QUEUED, RESOLVING, DOWNLOADING, VERIFYING, COMPLETED, PAUSED_USER, WAITING_NETWORK, WAITING_VERIFICATION, FAILED, CANCELLED, DELETING }
    public static final class Task {
        public String id, bookId, sourceId, comicId, chapterId, title, url, error="";
        public int order, failures, totalPages, donePages;
        public long generation;
        public long bytes, nextAttempt;
        public State state=State.QUEUED;
        public Task copy() {
            Task t=new Task();
            t.id=id; t.bookId=bookId; t.sourceId=sourceId; t.comicId=comicId;
            t.chapterId=chapterId; t.title=title; t.url=url; t.error=error;
            t.order=order; t.generation=generation; t.failures=failures;
            t.totalPages=totalPages; t.donePages=donePages; t.bytes=bytes;
            t.nextAttempt=nextAttempt; t.state=state; return t;
        }
    }
    public static String key(String... components) {
        try {
            MessageDigest digest=MessageDigest.getInstance("SHA-256");
            for(String part:components) {
                if(part==null || part.isEmpty()) throw new IllegalArgumentException("缺少作品或章节身份");
                byte[] bytes=part.getBytes(StandardCharsets.UTF_8);
                digest.update(Integer.toString(bytes.length).getBytes(StandardCharsets.US_ASCII));
                digest.update((byte)':'); digest.update(bytes);
            }
            StringBuilder key=new StringBuilder();
            for(byte b:digest.digest()) key.append(String.format(java.util.Locale.ROOT,"%02x",b & 255));
            return key.toString();
        } catch(java.security.NoSuchAlgorithmException impossible) { throw new IllegalStateException(impossible); }
    }
    public static String bookId(String source,String comic) { return "local_dl_"+key(source,comic); }
    public static boolean active(State state) { return state==State.RESOLVING || state==State.DOWNLOADING || state==State.VERIFYING; }
}
