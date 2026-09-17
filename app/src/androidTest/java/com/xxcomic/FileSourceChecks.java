package com.xxcomic;

import android.content.Context;
import android.graphics.Bitmap;
import com.xxcomic.download.*;
import com.xxcomic.local.*;
import com.xxcomic.source.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.zip.*;

/** Controlled file source, private SQLite and real image parsing. Never registers a release source. */
public final class FileSourceChecks {
    public static int run(Context context) throws Exception {
        File root=new File(context.getCacheDir(),"file-source-check-"+System.nanoTime());
        LocalStorageManager storage=new LocalStorageManager(root);
        File dbFile=new File(root,"library.db");
        LocalLibraryStore store=new LocalLibraryStore(context,dbFile);
        DownloadStore tasks=new DownloadStore(new File(root,"queue.db"));
        try {
            byte[] bytes=archive(2);
            FileResource resource;
            File part=storage.getDownloadFile("fixture/content.part");
            FileDownloadWorker.Result transfer;
            DownloadModels.Task task;
            try(ServerSocket server=new ServerSocket(0)) {
                resource=new FileResource("volume1","r1","第一卷",0,"zip",bytes.length,null,
                        "http://127.0.0.1:"+server.getLocalPort()+"/file",Collections.emptyMap(),0);
                FileSourceCapability source=new FileSourceCapability(){
                    public List<FileResource> listFiles(String comic){return Collections.singletonList(resource);}
                    public FileResource resolveFile(String comic,String file){return resource;}
                };
                DownloadCoordinator queue=new DownloadCoordinator(tasks);
                queue.enqueueFiles("fixture","comic",source.listFiles("comic"),Collections.singletonList("volume1"));
                task=queue.claim(0,true,true,true);
                Thread response=new Thread(()->{
                    try(Socket client=server.accept()) {
                        BufferedReader reader=new BufferedReader(new InputStreamReader(client.getInputStream(),"US-ASCII"));
                        while(!reader.readLine().isEmpty()) { }
                        client.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Length: "+bytes.length+"\r\nConnection: close\r\n\r\n").getBytes("US-ASCII"));
                        client.getOutputStream().write(bytes);
                    }catch(IOException ignored) { }
                });response.setDaemon(true);response.start();
                transfer=new FileDownloadWorker().download(task,source,part,()->{},null);
                response.join(2000);
                queue.update(task,DownloadModels.State.VERIFYING,0,1,transfer.bytes);
                require(store.getBook(task.bookId)==null,"not readable before parsing");
            }
            File target=storage.getBookImportFile(task.bookId+"_1.zip");
            require(part.renameTo(target),"publish without a second source copy");
            LocalImporter importer=new LocalImporter(context,storage,store);
            LocalImporter.PreparedFile prepared=importer.prepareDownloadedFile(target,task.bookId,"示例 · 第一卷","zip",transfer.hash,part.getParentFile(),null);
            require(store.getBook(task.bookId)==null,"parsing does not publish early");
            store.commitImport(prepared.book,prepared.index.chapters,prepared.index.pagesByChapter);
            require(new DownloadCoordinator(tasks).complete(task),"complete only after readable index");
            store.close();store=new LocalLibraryStore(context,dbFile);
            LocalContentResolver resolver=new LocalContentResolver(store,storage);
            LocalModels.Page first=store.getFirstPage(task.bookId);
            try(InputStream input=resolver.openPage(first.id)){require(input.read()==137,"offline PNG remains readable after reopening database");}
            storage.clearDerivedPagesCache();require(target.isFile(),"cache cleaning preserves original download");
            store.renameBook(task.bookId,"我的标题");
            LocalImporter replacementImporter=new LocalImporter(context,storage,store);
            File replacement=storage.getBookImportFile(task.bookId+"_2.zip");
            try(OutputStream out=new FileOutputStream(replacement)){out.write(archive(1));}
            LocalImporter.PreparedFile next=replacementImporter.prepareDownloadedFile(replacement,task.bookId,"新标题","zip",
                    FileDownloadWorker.calculateSha256(replacement),part.getParentFile(),null);
            require(store.getBook(task.bookId).pageCount==2 && target.isFile(),"old version remains readable until commit");
            require(!prepared.book.progressKey.equals(next.book.progressKey),"changed content cannot silently reuse old locator");
            require(next.book.getDisplayTitle().equals("我的标题"),"rename survives replacement");
            store.commitImport(next.book,next.index.chapters,next.index.pagesByChapter);
            require(store.getPage(first.id)==null && store.getBook(task.bookId).pageCount==1,"replacement removes obsolete page index");
            File invalid=storage.getBookImportFile(task.bookId+"_invalid.zip");
            try(OutputStream out=new FileOutputStream(invalid)){out.write("<html>error</html>".getBytes("UTF-8"));}
            try {replacementImporter.prepareDownloadedFile(invalid,task.bookId,"bad","zip","bad",part.getParentFile(),null);throw new AssertionError("accepted invalid archive");}
            catch(IOException expected) {require(store.getBook(task.bookId).relativePath.equals(next.book.relativePath),"bad replacement keeps prior version");}
            require(store.deleteBook(task.bookId,storage),"delete owned files and index");
            require(!target.exists() && !replacement.exists() && store.getBook(task.bookId)==null,"all versions removed");
            return 13;
        } finally {tasks.close();store.close();storage.deleteRecursively(root);}
    }
    private static byte[] archive(int pages) throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        Bitmap image=Bitmap.createBitmap(4,6,Bitmap.Config.ARGB_8888);
        try(ZipOutputStream zip=new ZipOutputStream(bytes)) {
            for(int i=0;i<pages;i++){zip.putNextEntry(new ZipEntry((i+1)+".png"));image.compress(Bitmap.CompressFormat.PNG,100,zip);zip.closeEntry();}
        }finally{image.recycle();}
        return bytes.toByteArray();
    }
    private static void require(boolean result,String message){if(!result)throw new AssertionError(message);}
}
