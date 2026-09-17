package com.xxcomic.download;

import com.xxcomic.source.FileResource;
import com.xxcomic.source.FileSourceCapability;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;
import java.util.zip.*;

/** Full-file transfer; partial bytes are reusable only with the same strong ETag. */
public final class FileDownloadWorker {
    public interface Check { void check() throws IOException; }
    public interface ProgressListener { void onProgress(long bytes, long total); }
    public static final class Result { public long bytes; public String hash, detectedFormat; }
    private static final long MAX_BYTES=20L*1024*1024*1024;

    public Result download(DownloadModels.Task task, FileSourceCapability source, File part,
                           Check check, ProgressListener progress) throws Exception {
        check.check();
        FileResource resource=resolve(task,source);
        File validator=new File(part.getPath()+".etag");
        try {
            for(int refresh=0;refresh<2;refresh++) {
                if(resource.isExpired(System.currentTimeMillis())) {
                    if(task.refreshCount>=1)throw new IOException("文件链接已过期，请稍后重试");
                    task.refreshCount=1;resource=resolve(task,source);
                    if(resource.isExpired(System.currentTimeMillis()))throw new IOException("文件链接已过期，请稍后重试");
                }
                try { return transfer(resource,part,validator,check,progress); }
                catch(SourceImageFetcher.HttpFailure failure) {
                    if((failure.status!=401 && failure.status!=403) || task.refreshCount>=1 || refresh==1)throw failure;
                    task.refreshCount=1;resource=resolve(task,source);
                }
            }
            throw new IOException("文件链接未生效，请重试");
        } catch(Exception failure) {
            if(!(failure instanceof InterruptedIOException) && !(failure instanceof SocketException)) {
                part.delete();validator.delete();
            }
            throw failure;
        }
    }
    private FileResource resolve(DownloadModels.Task task,FileSourceCapability source) throws IOException {
        if(source==null)throw new IOException("站源不支持文件下载");
        FileResource r=source.resolveFile(task.comicId,task.fileId);
        if(r==null || !task.fileId.equals(r.fileId))throw new IOException("文件身份发生变化，请重新选择");
        task.revision=r.revision;task.sha256=r.sha256;task.expectedBytes=r.bytes;
        task.expectedFormat=r.expectedFormat;task.expiresAt=r.expiresAt;
        return r;
    }
    private Result transfer(FileResource resource,File part,File validator,Check check,ProgressListener progress) throws Exception {
        String saved="";
        if(validator.isFile())try(DataInputStream in=new DataInputStream(new FileInputStream(validator))){saved=in.readUTF();}
        String identity=resource.revision+"\n"+resource.sha256+"\n";
        String etag=saved.startsWith(identity)?saved.substring(identity.length()):"";
        long offset=part.isFile() && etag.startsWith("\"")?part.length():0;
        URL url=httpUrl(resource.url);
        Map<String,String> headers=new HashMap<>(resource.headers);
        HttpURLConnection connection=null;
        try {
            for(int redirects=0;redirects<=5;redirects++) {
                check.check();
                connection=(HttpURLConnection)url.openConnection();
                connection.setConnectTimeout(15000);connection.setReadTimeout(30000);connection.setInstanceFollowRedirects(false);
                connection.setRequestProperty("User-Agent",SourceImageFetcher.USER_AGENT);
                for(Map.Entry<String,String> h:headers.entrySet()) {
                    if(h.getKey()==null || h.getValue()==null || h.getKey().contains("\n") || h.getValue().contains("\n")
                            || h.getKey().contains("\r") || h.getValue().contains("\r"))throw new IOException("站源请求信息无效");
                    if(!Arrays.asList("host","content-length","range","if-range","accept-encoding").contains(h.getKey().toLowerCase(Locale.ROOT)))
                        connection.setRequestProperty(h.getKey(),h.getValue());
                }
                connection.setRequestProperty("Accept-Encoding","identity");
                if(offset>0){connection.setRequestProperty("Range","bytes="+offset+"-");connection.setRequestProperty("If-Range",etag);}
                int status=connection.getResponseCode();
                if(status==301||status==302||status==303||status==307||status==308) {
                    String location=connection.getHeaderField("Location");
                    if(location==null)throw new IOException("文件跳转地址缺失");
                    URL next=httpUrl(new URL(url,location).toString());
                    if(url.getProtocol().equals("https") && !next.getProtocol().equals("https"))throw new IOException("文件链接不允许降级为明文连接");
                    if(!sameOrigin(url,next))headers.clear();
                    url=next;connection.disconnect();continue;
                }
                if(status==416 && offset>0){offset=0;part.delete();validator.delete();connection.disconnect();continue;}
                if(status!=200 && status!=206)throw new SourceImageFetcher.HttpFailure(status,status==429?60000:0);
                String type=connection.getContentType();
                if(type!=null && type.toLowerCase(Locale.ROOT).contains("text/html"))throw new IOException("站源返回了网页，未获取到文件");
                long length=number(connection.getHeaderField("Content-Length")),total=length;
                String responseEtag=connection.getHeaderField("ETag");
                if(status==206) {
                    Matcher range=Pattern.compile("bytes (\\d+)-(\\d+)/(\\d+)").matcher(String.valueOf(connection.getHeaderField("Content-Range")));
                    if(offset<=0 || !etag.equals(responseEtag) || !range.matches())throw new IOException("文件续传响应无效");
                    long first=Long.parseLong(range.group(1)),last=Long.parseLong(range.group(2));total=Long.parseLong(range.group(3));
                    if(first!=offset || last<first || last!=total-1 || (length>=0 && length!=last-first+1))throw new IOException("文件续传范围不符");
                } else offset=0;
                if(total>MAX_BYTES || resource.bytes>MAX_BYTES)throw new IOException("文件超过容量上限");
                if(resource.bytes>=0 && total>=0 && resource.bytes!=total)throw new IOException("文件长度与站源描述不符");
                File parent=part.getParentFile();
                if(parent!=null && !parent.isDirectory() && !parent.mkdirs())throw new IOException("无法创建文件下载目录");
                if(offset==0)try(OutputStream truncate=new FileOutputStream(part)){ /* Invalidate old bytes before the new ETag. */ }
                if(responseEtag!=null && responseEtag.startsWith("\"")) {
                    try(DataOutputStream out=new DataOutputStream(new FileOutputStream(validator))){out.writeUTF(identity+responseEtag);}
                } else validator.delete();
                long written=offset;
                try(InputStream in=connection.getInputStream();OutputStream out=new FileOutputStream(part,offset>0)) {
                    byte[] buffer=new byte[65536];
                    for(int n;(n=in.read(buffer))!=-1;){check.check();written+=n;if(written>MAX_BYTES)throw new IOException("文件超过容量上限");
                        out.write(buffer,0,n);if(progress!=null)progress.onProgress(written,total);}
                }
                check.check();
                if(written==0 || (total>=0 && written!=total) || (resource.bytes>=0 && written!=resource.bytes))throw new IOException("文件传输不完整");
                String hash=calculateSha256(part,check);
                if(resource.sha256!=null && !hash.equalsIgnoreCase(resource.sha256))throw new IOException("文件校验失败");
                String format=detectFormat(part,resource.expectedFormat);
                if(format==null)throw new IOException("文件格式不支持或内容损坏");
                Result result=new Result();result.bytes=written;result.hash=hash;result.detectedFormat=format;
                validator.delete();return result;
            }
            throw new IOException("文件跳转次数过多");
        } finally {if(connection!=null)connection.disconnect();}
    }
    private static URL httpUrl(String raw) throws IOException {
        URL url=new URL(raw);
        if((!url.getProtocol().equals("https")&&!url.getProtocol().equals("http")) || url.getUserInfo()!=null)throw new IOException("文件地址协议不支持");
        return url;
    }
    private static boolean sameOrigin(URL a,URL b) {
        return a.getProtocol().equals(b.getProtocol()) && a.getHost().equalsIgnoreCase(b.getHost())
                && (a.getPort()<0?a.getDefaultPort():a.getPort())==(b.getPort()<0?b.getDefaultPort():b.getPort());
    }
    private static long number(String value){try{return Long.parseLong(value);}catch(Exception e){return -1;}}
    public static String calculateSha256(File file) throws IOException{return calculateSha256(file,()->{});}
    private static String calculateSha256(File file,Check check) throws IOException {
        try {
            java.security.MessageDigest digest=java.security.MessageDigest.getInstance("SHA-256");
            try(InputStream in=new FileInputStream(file)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;){check.check();digest.update(b,0,n);}}
            StringBuilder result=new StringBuilder();for(byte b:digest.digest())result.append(String.format(Locale.ROOT,"%02x",b&255));return result.toString();
        } catch(java.security.NoSuchAlgorithmException e){throw new IOException(e);}
    }
    public static String detectFormat(File file,String hint) throws IOException {
        byte[] head=new byte[68];int n;try(InputStream in=new FileInputStream(file)){n=in.read(head);}
        if(n>=5 && new String(head,0,5,StandardCharsets.US_ASCII).equals("%PDF-"))return "pdf";
        if(n>=68 && (new String(head,60,8,StandardCharsets.US_ASCII).equals("BOOKMOBI")
                || new String(head,60,8,StandardCharsets.US_ASCII).equals("TEXtREAd")))return "mobi";
        if(n>=4 && head[0]=='P' && head[1]=='K' && head[2]==3 && head[3]==4) {
            try(ZipFile zip=new ZipFile(file)) {return zip.getEntry("META-INF/container.xml")!=null?"epub":"cbz".equals(hint)?"cbz":"zip";}
        }
        return null;
    }
}
