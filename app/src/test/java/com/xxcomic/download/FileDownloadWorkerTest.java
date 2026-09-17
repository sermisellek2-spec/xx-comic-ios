package com.xxcomic.download;

import com.xxcomic.source.*;
import org.junit.*;
import org.junit.rules.TemporaryFolder;
import java.io.*;
import java.net.*;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.zip.*;
import static org.junit.Assert.*;

public class FileDownloadWorkerTest {
    @Rule public TemporaryFolder temp=new TemporaryFolder();
    private HttpServer server;
    private byte[] zip;
    private File part;
    private DownloadModels.Task task;
    @Before public void setup() throws Exception {
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){z.putNextEntry(new ZipEntry("1.png"));z.write(new byte[]{1,2,3});z.closeEntry();}
        zip=out.toByteArray();part=new File(temp.getRoot(),"book.part");
        task=new DownloadModels.Task();task.fileId="vol1";task.comicId="comic";task.isFileTask=true;
        server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);server.start();
    }
    @After public void stop(){server.stop(0);}
    private String url(String path){return "http://127.0.0.1:"+server.getAddress().getPort()+path;}
    private FileResource resource(String path,long bytes,String hash,Map<String,String> headers) {
        return new FileResource("vol1","v1","第一卷",0,"zip",bytes,hash,url(path),headers,0);
    }
    private FileSourceCapability source(FileResource... resources) {
        AtomicInteger count=new AtomicInteger();
        return new FileSourceCapability(){
            public List<FileResource> listFiles(String id){return Arrays.asList(resources);}
            public FileResource resolveFile(String comic,String file){return resources[Math.min(count.getAndIncrement(),resources.length-1)];}
        };
    }
    private FileDownloadWorker.Result run(FileResource resource) throws Exception {
        return new FileDownloadWorker().download(task,source(resource),part,()->{},null);
    }
    private void respond(HttpExchange e,int status,byte[] bytes,boolean chunked) throws IOException {
        e.sendResponseHeaders(status,chunked?0:bytes.length);
        try(OutputStream out=e.getResponseBody()){out.write(bytes);}
    }
    @Test public void preservesBytesAndUsesResolvedHeadersWithoutPersistingTokens() throws Exception {
        server.createContext("/file",e->{assertEquals("Bearer sample",e.getRequestHeaders().getFirst("Authorization"));respond(e,200,zip,false);});
        FileDownloadWorker.Result result=run(resource("/file",zip.length,null,Collections.singletonMap("Authorization","Bearer sample")));
        assertArrayEquals(zip,Files.readAllBytes(part.toPath()));assertEquals(zip.length,result.bytes);assertEquals("zip",result.detectedFormat);
        assertNull(task.url);
    }
    @Test public void supportsUnknownLengthAndDetectsEpubFromContent() throws Exception {
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream z=new ZipOutputStream(out)){z.putNextEntry(new ZipEntry("META-INF/container.xml"));z.write("sample".getBytes("UTF-8"));z.closeEntry();}
        byte[] epub=out.toByteArray();server.createContext("/file",e->respond(e,200,epub,true));
        assertEquals("epub",run(resource("/file",-1,null,Collections.emptyMap())).detectedFormat);
        assertArrayEquals(epub,Files.readAllBytes(part.toPath()));
    }
    @Test public void rejectsHtmlTruncationChecksumAndUnsolicitedPartial() throws Exception {
        server.createContext("/html",e->respond(e,200,"<html>error</html>".getBytes("UTF-8"),false));
        server.createContext("/partial",e->{e.getResponseHeaders().set("Content-Range","bytes 0-"+(zip.length-1)+"/"+zip.length);respond(e,206,zip,false);});
        server.createContext("/short",e->{e.sendResponseHeaders(200,zip.length+100);e.getResponseBody().write(zip);e.close();});
        server.createContext("/hash",e->respond(e,200,zip,false));
        for(String path:new String[]{"/html","/partial","/short","/hash"}) {
            FileResource r=resource(path,-1,path.equals("/hash")?"bad-hash":null,Collections.emptyMap());
            assertThrows(Exception.class,()->run(r));assertFalse(part.exists());
        }
    }
    private void seedPartial(int length) throws Exception {
        Files.write(part.toPath(),Arrays.copyOf(zip,length));
        try(DataOutputStream out=new DataOutputStream(new FileOutputStream(part.getPath()+".etag"))){out.writeUTF("v1\nnull\n\"same\"");}
    }
    @Test public void resumesOnlyValidRangeWithSameStrongEtag() throws Exception {
        seedPartial(10);
        server.createContext("/file",e->{assertEquals("bytes=10-",e.getRequestHeaders().getFirst("Range"));assertEquals("\"same\"",e.getRequestHeaders().getFirst("If-Range"));
            e.getResponseHeaders().set("ETag","\"same\"");e.getResponseHeaders().set("Content-Range","bytes 10-"+(zip.length-1)+"/"+zip.length);
            respond(e,206,Arrays.copyOfRange(zip,10,zip.length),false);});
        run(resource("/file",zip.length,null,Collections.emptyMap()));assertArrayEquals(zip,Files.readAllBytes(part.toPath()));
    }
    @Test public void rangeIgnoredByServerRestartsFile() throws Exception {
        seedPartial(10);server.createContext("/file",e->respond(e,200,zip,false));
        run(resource("/file",-1,null,Collections.emptyMap()));assertArrayEquals(zip,Files.readAllBytes(part.toPath()));
    }
    @Test public void rejectsWrongRangeAndEtag() throws Exception {
        server.createContext("/range",e->{e.getResponseHeaders().set("ETag","\"same\"");e.getResponseHeaders().set("Content-Range","bytes 9-"+(zip.length-1)+"/"+zip.length);respond(e,206,Arrays.copyOfRange(zip,10,zip.length),false);});
        server.createContext("/etag",e->{e.getResponseHeaders().set("ETag","\"changed\"");e.getResponseHeaders().set("Content-Range","bytes 10-"+(zip.length-1)+"/"+zip.length);respond(e,206,Arrays.copyOfRange(zip,10,zip.length),false);});
        for(String path:new String[]{"/range","/etag"}){seedPartial(10);assertThrows(IOException.class,()->run(resource(path,-1,null,Collections.emptyMap())));assertFalse(part.exists());}
    }
    @Test public void stripsAllSourceHeadersOnCrossOriginRedirect() throws Exception {
        HttpServer other=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);other.start();
        AtomicInteger visited=new AtomicInteger();
        try {
            other.createContext("/file",e->{assertNull(e.getRequestHeaders().getFirst("Authorization"));assertNull(e.getRequestHeaders().getFirst("X-Custom-Key"));visited.incrementAndGet();respond(e,200,zip,false);});
            server.createContext("/file",e->{e.getResponseHeaders().set("Location","http://127.0.0.1:"+other.getAddress().getPort()+"/file");e.sendResponseHeaders(302,-1);e.close();});
            Map<String,String> headers=new HashMap<>();headers.put("authorization","secret");headers.put("X-Custom-Key","secret");
            run(resource("/file",-1,null,headers));assertEquals(1,visited.get());
        } finally {other.stop(0);}
    }
    @Test public void refreshesExpiredAccessOnceAndRejectsRepeated403() throws Exception {
        AtomicInteger count=new AtomicInteger();
        server.createContext("/expired",e->{count.incrementAndGet();e.sendResponseHeaders(403,-1);e.close();});
        server.createContext("/valid",e->respond(e,200,zip,false));
        FileResource expired=resource("/expired",-1,null,Collections.emptyMap()),valid=resource("/valid",-1,null,Collections.emptyMap());
        new FileDownloadWorker().download(task,source(expired,valid),part,()->{},null);
        assertEquals(1,count.get());assertArrayEquals(zip,Files.readAllBytes(part.toPath()));
        task.refreshCount=0;count.set(0);
        assertThrows(IOException.class,()->new FileDownloadWorker().download(task,source(expired),part,()->{},null));assertEquals(2,count.get());
    }
    @Test public void newRevisionDiscardsPartialBytes() throws Exception {
        seedPartial(10);server.createContext("/file",e->{assertNull(e.getRequestHeaders().getFirst("Range"));respond(e,200,zip,false);});
        run(new FileResource("vol1","v2","卷",0,"zip",zip.length,null,url("/file"),Collections.emptyMap(),0));
        assertArrayEquals(zip,Files.readAllBytes(part.toPath()));
    }
    @Test public void pauseStopsTransferAndRetainsOnlyValidatedResumeState() throws Exception {
        server.createContext("/file",e->{e.getResponseHeaders().set("ETag","\"same\"");respond(e,200,zip,false);});
        assertThrows(InterruptedIOException.class,()->new FileDownloadWorker().download(task,source(resource("/file",-1,null,Collections.emptyMap())),part,
                ()->{if(part.length()>0)throw new InterruptedIOException("pause");},null));
        assertTrue(new File(part.getPath()+".etag").isFile());
    }
    // Android's test bootclasspath excludes jdk.httpserver; use the standard socket API.
    private interface Handler {void handle(HttpExchange exchange) throws IOException;}
    private static final class Headers extends TreeMap<String,String> {
        Headers(){super(String.CASE_INSENSITIVE_ORDER);}
        void set(String k,String v){put(k,v);} String getFirst(String k){return get(k);}
    }
    private static final class HttpExchange {
        final Socket socket;final Headers request=new Headers(),response=new Headers();final String path;
        HttpExchange(Socket socket) throws IOException {
            this.socket=socket;socket.setSoTimeout(2000);
            BufferedReader in=new BufferedReader(new InputStreamReader(socket.getInputStream(),"US-ASCII"));
            path=in.readLine().split(" ")[1];
            for(String line;(line=in.readLine())!=null && !line.isEmpty();){int i=line.indexOf(':');request.set(line.substring(0,i),line.substring(i+1).trim());}
        }
        Headers getRequestHeaders(){return request;} Headers getResponseHeaders(){return response;}
        OutputStream getResponseBody() throws IOException{return socket.getOutputStream();}
        void sendResponseHeaders(int code,long size) throws IOException {
            StringBuilder head=new StringBuilder("HTTP/1.1 "+code+" Response\r\nConnection: close\r\n");
            if(size>0)head.append("Content-Length: ").append(size).append("\r\n");
            for(Map.Entry<String,String> h:response.entrySet())head.append(h.getKey()).append(": ").append(h.getValue()).append("\r\n");
            getResponseBody().write(head.append("\r\n").toString().getBytes("US-ASCII"));
        }
        void close() throws IOException{socket.close();}
    }
    private static final class HttpServer {
        final ServerSocket socket;final Map<String,Handler> routes=new java.util.concurrent.ConcurrentHashMap<>();
        volatile Throwable failure;
        HttpServer(InetSocketAddress address) throws IOException {socket=new ServerSocket();socket.bind(address);}
        static HttpServer create(InetSocketAddress address,int ignored) throws IOException{return new HttpServer(address);}
        InetSocketAddress getAddress(){return (InetSocketAddress)socket.getLocalSocketAddress();}
        void createContext(String path,Handler handler){routes.put(path,handler);}
        void start(){Thread t=new Thread(()->{while(!socket.isClosed())try(Socket client=socket.accept()){
            HttpExchange exchange=new HttpExchange(client);routes.get(exchange.path).handle(exchange);
        }catch(Throwable e){if(!socket.isClosed())failure=e;}});t.setDaemon(true);t.start();}
        void stop(int ignored){try{socket.close();}catch(IOException e){throw new AssertionError(e);}if(failure!=null)throw new AssertionError(failure);}
    }
}
