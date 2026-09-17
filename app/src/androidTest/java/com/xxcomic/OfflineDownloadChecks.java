package com.xxcomic;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import com.xxcomic.download.*;
import com.xxcomic.local.*;
import com.xxcomic.source.ComicModels;
import java.io.*;
import java.util.*;

/** Isolated native SQLite / bitmap checks. Does not touch the user's library or external sources. */
public final class OfflineDownloadChecks {
    public static int run(Context context) throws Exception {
        File root=new File(context.getCacheDir(),"offline-check-"+System.nanoTime());
        LocalStorageManager storage=new LocalStorageManager(root);
        File queueFile=new File(root,"queue.db");
        DownloadStore queueDb=new DownloadStore(queueFile);
        LocalLibraryStore library=new LocalLibraryStore(context,new File(root,"library.db"));
        int checks=0;
        try {
            ComicModels.Chapter a=new ComicModels.Chapter("chapterA","A","https://fixture/a",0,0);
            ComicModels.Chapter b=new ComicModels.Chapter("chapterB","B","https://fixture/b",0,1);
            ComicModels.ComicDetail detail=new ComicModels.ComicDetail(new ComicModels.ComicSummary("fixture","online-key","作品","","",Collections.emptyList()),"作者","连载","简介","",Arrays.asList(a,b));
            DownloadCoordinator queue=new DownloadCoordinator(queueDb);
            queueDb.saveSnapshot(detail);queue.enqueue("fixture","online-key",detail.chapters,Arrays.asList("chapterA","chapterB"));
            DownloadModels.Task lease=queue.claim(0,true,true,true);
            queueDb.savePage(lease.id,new DownloadStore.Page(0,"https://fixture/page","book/a.img","hash",20));
            queue.pause(DownloadModels.key("fixture","online-key","chapterB"));
            queueDb.close();queueDb=new DownloadStore(queueFile);queue=new DownloadCoordinator(queueDb);queue.recover();
            check(queueDb.get(lease.id).generation!=lease.generation,"process recovery invalidates old lease");checks++;
            check(queueDb.list().size()==2 && queueDb.pages(lease.id).size()==1,"queue and completed page persisted");checks++;
            check(queueDb.get(DownloadModels.key("fixture","online-key","chapterB")).state==DownloadModels.State.PAUSED_USER,"manual pause survives recreation");checks++;
            check(queueDb.snapshot(lease.bookId).chapters.get(1).chapterId.equals("chapterB"),"whole chapter snapshot survives recreation");checks++;
            LocalModels.Book imported=new LocalModels.Book("local_import","fp","导入",null,"folder","import","local_import","imported",null,1,0,0,"ready",0,0);
            library.commitImport(imported,Collections.emptyList(),Collections.emptyMap());
            File pageFile=storage.getDownloadFile(lease.bookId+"/a.img");check(pageFile.getParentFile().mkdirs(),"create fixture directory");
            Bitmap pixels=Bitmap.createBitmap(4,13,Bitmap.Config.ARGB_8888);
            // Ten bottom-to-top strips for aid<268850: first decoded strip is 4 rows, remaining are 1 row.
            for(int y=0;y<13;y++)for(int x=0;x<4;x++)pixels.setPixel(x,y,Color.rgb(y*15,x*30,0));
            try(OutputStream out=new FileOutputStream(pageFile)){pixels.compress(Bitmap.CompressFormat.PNG,100,out);}pixels.recycle();
            LocalModels.Book download=new LocalModels.Book(lease.bookId,lease.bookId,"作品",null,"folder","download","online-key",lease.bookId,null,pageFile.length(),1,1,"ready",0,0);
            LocalModels.Chapter first=new LocalModels.Chapter(lease.id,lease.bookId,0,"A","chapterA",1);
            LocalModels.Page page=new LocalModels.Page("page-a",lease.bookId,lease.id,0,"a.img",4,13,"jm:https://cdn-msp.example.18comic.vip/media/photos/200000/00001.png?scramble_id=1","image/png");
            library.publishDownloadedChapter(download,first,Collections.singletonList(page));
            library.renameBook(lease.bookId,"用户命名");
            LocalModels.Chapter second=new LocalModels.Chapter("second",lease.bookId,1,"B","chapterB",1);
            LocalModels.Page secondPage=new LocalModels.Page("page-b",lease.bookId,"second",0,"a.img",4,13,page.transformation,"image/png");
            library.publishDownloadedChapter(download,second,Collections.singletonList(secondPage));
            check(library.getChapters(lease.bookId).size()==2 && library.getPages(lease.id).size()==1,"append chapter preserves old chapter");checks++;
            check(library.getBook("local_import")!=null && library.getBook(lease.bookId).getDisplayTitle().equals("用户命名"),"old imports and renamed title survive publication");checks++;
            check(library.findByProgressKey("online-key").id.equals(lease.bookId),"download and online progress share identity");checks++;
            LocalContentResolver resolver=new LocalContentResolver(library,storage);
            storage.clearDerivedPagesCache();
            check(resolver.materializePage(page.id).equals(pageFile),"cache cleanup preserves original downloaded page");checks++;
            Bitmap decoded=resolver.decodeCoverBitmap(lease.bookId,40,130);
            check(decoded!=null && decoded.getPixel(0,0)==Color.rgb(9*15,0,0) && decoded.getPixel(0,12)==Color.rgb(0,0,0),"JM offline transform uses saved metadata once and retains last strip");checks++;
            decoded.recycle();
            library.removeDownloadedChapter(lease.bookId,"second",pageFile.length());
            check(library.getChapters(lease.bookId).size()==1 && library.getPage("page-a")!=null,"partial deletion preserves remaining chapter");checks++;
            check(library.deleteBook(lease.bookId,storage) && !pageFile.exists() && library.getBook("local_import")!=null,"whole download deletion preserves imports");checks++;
            check(library.findDeletedByProgressKey("online-key")!=null,"deletion keeps progress tombstone");checks++;
        } finally {queueDb.close();library.close();storage.deleteRecursively(root);}
        return checks;
    }
    private static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
}
