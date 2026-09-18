package com.xxcomic.download;
import java.io.*;
import java.util.Map;
import java.util.Locale;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
public final class SourceImageFetcher {
    private static final SourceRequestGate DEFAULT_GATE = new SourceRequestGate(350L, 120000L);
    public interface Check { void check() throws IOException; }
    public interface Decoder { InputStream open(InputStream in) throws IOException; }
    public interface Validator { void validate(File file) throws IOException; }
    public static final class Result { public long bytes; public String hash; }
    public static final String USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    public static void applyHeaders(HttpURLConnection connection,String referer) {
        connection.setRequestProperty("User-Agent",USER_AGENT);
        connection.setRequestProperty("Accept","image/webp,image/apng,image/*,*/*;q=0.8");
        connection.setRequestProperty("Accept-Language","zh-CN,zh;q=0.9,en;q=0.8");
        connection.setRequestProperty("Sec-Fetch-Dest","image");
        connection.setRequestProperty("Sec-Fetch-Mode","no-cors");
        connection.setRequestProperty("Sec-Fetch-Site","cross-site");
        if(referer!=null && !referer.isEmpty()) connection.setRequestProperty("Referer",referer);
    }
    public static final class HttpFailure extends IOException {
        public final int status; public final long retryAfter;
        HttpFailure(int status,long delay) { super("图片请求失败 HTTP "+status);this.status=status;this.retryAfter=delay; }
    }
    /** Page-level restart only: never append an untrusted HTTP entity to an existing partial file. */
    public Result fetch(String url,String referer,File part,Map<String,String> headers,Decoder decoder,Check check,Validator validator) throws IOException {
        return fetch(null, url, referer, part, headers, decoder, check, validator);
    }
    public static long cooldownRemaining(String sourceId) {
        return DEFAULT_GATE.cooldownRemaining(sourceId);
    }

    /** Same request path with a source identity for per-source pacing and throttle backoff. */
    public Result fetch(String sourceId, String url,String referer,File part,Map<String,String> headers,
                        Decoder decoder,Check check,Validator validator) throws IOException {
        HttpURLConnection connection=null; boolean success=false;
        try {
            check.check();
            DEFAULT_GATE.before(sourceId);
            check.check();
            connection=(HttpURLConnection)new URL(url).openConnection();
            connection.setConnectTimeout(10000); connection.setReadTimeout(25000); connection.setInstanceFollowRedirects(true);
            applyHeaders(connection,referer); connection.setRequestProperty("Accept-Encoding","identity");
            for(Map.Entry<String,String> header:headers.entrySet()) connection.setRequestProperty(header.getKey(),header.getValue());
            int status=connection.getResponseCode();
            if(status!=200) {
                long retryAfter = retryAfter(connection.getHeaderField("Retry-After"));
                DEFAULT_GATE.onFailure(sourceId, status, retryAfter);
                throw new HttpFailure(status,retryAfter);
            }
            DEFAULT_GATE.onSuccess(sourceId);
            String type=connection.getContentType();
            if(type!=null && (type.toLowerCase(Locale.ROOT).contains("text/") || type.toLowerCase(Locale.ROOT).contains("json"))) throw new IOException("服务器返回了网页，未下载图片");
            long expected=-1; try { expected=Long.parseLong(connection.getHeaderField("Content-Length")); } catch(Exception ignored) { }
            if(expected>128L*1024*1024) throw new IOException("单页超过 128MiB 限制");
            MessageDigest digest; try { digest=MessageDigest.getInstance("SHA-256"); } catch(Exception impossible) { throw new IOException(impossible); }
            long[] rawCount={0}; long written=0;
            try(InputStream network=connection.getInputStream();
                InputStream counted=new FilterInputStream(network) {
                    @Override public int read() throws IOException { int n=in.read();if(n>=0)rawCount[0]++;return n; }
                    @Override public int read(byte[] b,int off,int len)throws IOException { int n=in.read(b,off,len);if(n>0)rawCount[0]+=n;return n; }
                };
                InputStream decoded=decoder.open(counted);
                OutputStream out=new FileOutputStream(part,false)) {
                byte[] buffer=new byte[65536];
                for(int n;(n=decoded.read(buffer))!=-1;) {
                    check.check(); if(n==0)continue;
                    written+=n; if(written>128L*1024*1024)throw new IOException("单页超过 128MiB 限制");
                    out.write(buffer,0,n);digest.update(buffer,0,n);
                }
            }
            check.check();
            if(written==0 || (expected>=0 && rawCount[0]!=expected)) throw new IOException("图片传输不完整，请重试");
            validator.validate(part); check.check();
            Result result=new Result(); result.bytes=written;
            StringBuilder hash=new StringBuilder();for(byte b:digest.digest())hash.append(String.format(Locale.ROOT,"%02x",b&255));
            result.hash=hash.toString(); success=true; return result;
        } finally {
            if(connection!=null)connection.disconnect();
            if(!success)part.delete();
        }
    }
    private static long retryAfter(String value) {
        if(value==null)return 0;
        try {return Math.min(900,Math.max(0,Long.parseLong(value)))*1000;} catch(NumberFormatException ignored) { }
        try {return Math.min(900000,Math.max(0,new java.text.SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz",Locale.US).parse(value).getTime()-System.currentTimeMillis()));}
        catch(Exception ignored){return 0;}
    }
}
