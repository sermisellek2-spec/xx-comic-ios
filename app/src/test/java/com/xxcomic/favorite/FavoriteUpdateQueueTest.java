package com.xxcomic.favorite;
import com.xxcomic.source.*;
import org.junit.Test;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.Assert.*;

public class FavoriteUpdateQueueTest {
    private ComicModels.ComicDetail detail(String id, boolean updated) {
        List<ComicModels.Chapter> chapters=new ArrayList<>();
        chapters.add(new ComicModels.Chapter("one","第1话","/1",0,0));
        if(updated)chapters.add(new ComicModels.Chapter("two","第2话","/2",0,1));
        return new ComicModels.ComicDetail(new ComicModels.ComicSummary("test",id,id,"","",null),"","","","",chapters);
    }
    private FavoriteUpdateCoordinator runScenario(int action) throws Exception {
        FavoriteUpdateCoordinator c=FavoriteUpdateCoordinator.getInstance(); c.resetForTesting();
        CountDownLatch started=new CountDownLatch(1), release=new CountDownLatch(1);
        ComicSource source=(ComicSource)Proxy.newProxyInstance(getClass().getClassLoader(),new Class[]{ComicSource.class},(proxy,m,args)->{
            if(m.getName().equals("id"))return "test";
            if(m.getName().equals("detail")){
                String id=(String)args[0];
                if(id.equals("first")){started.countDown();if(!release.await(5,TimeUnit.SECONDS))throw new AssertionError("timeout");}
                if(id.equals("queued") && action==4)throw new java.io.IOException("offline");
                return detail(id,true);
            }
            throw new UnsupportedOperationException(m.getName());
        });
        Map<String,ComicModels.ComicDetail> cache=new HashMap<>();
        cache.put("first",detail("first",false));cache.put("queued",detail("queued",false));
        c.startStartupCheck(Arrays.asList("first","queued"),new FavoriteUpdateCoordinator.SourceResolver(){
            public ComicSource resolveSource(String id){return source;}
            public boolean isSourceAvailable(String id){return true;}
        },cache);
        assertTrue(started.await(5,TimeUnit.SECONDS));
        if(action==1 || action==2)c.onFavoriteRemoved("queued");
        if(action==2)c.onFavoriteAdded("queued",detail("queued",false));
        if(action==0)c.onUserEnterDetail("queued");
        release.countDown();
        Field running=c.getClass().getDeclaredField("runningCount");running.setAccessible(true);
        Field lock=c.getClass().getDeclaredField("lock");lock.setAccessible(true);
        long deadline=System.currentTimeMillis()+5000;
        while(System.currentTimeMillis()<deadline){synchronized(lock.get(c)){if(running.getInt(c)==0)return c;}Thread.sleep(10);}
        throw new AssertionError("checks did not finish");
    }
    @Test public void openingQueuedComicMustPreventLaterBadge() throws Exception {
        assertFalse("A comic opened while waiting in the startup queue must stay acknowledged",runScenario(0).shouldShowBadge("queued"));
    }
    @Test public void removingQueuedComicMustNotRecreateItsState() throws Exception {
        assertNull("A removed favorite must not be recreated by its queued check",runScenario(1).getState("queued"));
    }
    @Test public void readdingFavoriteCannotReceiveTheOldQueuedResult() throws Exception {
        FavoriteUpdateCoordinator c=runScenario(2);
        assertFalse(c.shouldShowBadge("queued"));
        assertEquals(1,c.getState("queued").observedRevision.chapterCount);
    }
    @Test public void successfulNewChapterLightsBadgeUntilOpened() throws Exception {
        FavoriteUpdateCoordinator c=runScenario(3);
        assertTrue(c.shouldShowBadge("queued"));
        c.onUserEnterDetail("queued");
        assertFalse(c.shouldShowBadge("queued"));
    }
    @Test public void failedCheckStaysHiddenAndPreservesBaseline() throws Exception {
        FavoriteUpdateCoordinator c=runScenario(4);
        assertFalse(c.shouldShowBadge("queued"));
        assertEquals(1,c.getState("queued").acknowledgedRevision.chapterCount);
    }
}
