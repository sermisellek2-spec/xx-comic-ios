package com.xxcomic.update;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.InetAddress;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

public class AppUpdateCheckerTest {
    private AppUpdateChecker checker;
    private ServerSocket server;
    private Thread serverThread;
    private ExecutorService executor;
    private final CountDownLatch entered = new CountDownLatch(1);
    private final CountDownLatch release = new CountDownLatch(1);
    private final AtomicInteger requests = new AtomicInteger();
    private int status = 200;
    private String url;

    @Before public void setup() throws Exception {
        checker = new AppUpdateChecker();
        executor = Executors.newSingleThreadExecutor();
        server = new ServerSocket(0,10,InetAddress.getByName("127.0.0.1"));
        serverThread = new Thread(() -> {
            while(!server.isClosed()) try(Socket socket=server.accept()) {
            BufferedReader input=new BufferedReader(new InputStreamReader(socket.getInputStream(),StandardCharsets.US_ASCII));
            String line;while((line=input.readLine())!=null && !line.isEmpty()) { }
            requests.incrementAndGet(); entered.countDown();
            try { release.await(5,TimeUnit.SECONDS); } catch(InterruptedException e) { Thread.currentThread().interrupt(); }
            byte[] body = ("{\"versionName\":\"2.0.99\",\"versionCode\":299,\"size\":123,"
                    + "\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"updateMode\":\"prompt\"}").getBytes(StandardCharsets.UTF_8);
            java.io.OutputStream out=socket.getOutputStream();
            out.write(("HTTP/1.1 "+status+" Response\r\nContent-Length: "+body.length+"\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
            out.write(body);out.flush();
            } catch(java.io.IOException ignored) { }
        });
        serverThread.setDaemon(true);serverThread.start(); url="http://127.0.0.1:"+server.getLocalPort()+"/release";
    }
    @After public void cleanup() throws Exception {
        release.countDown(); executor.shutdown(); executor.awaitTermination(5,TimeUnit.SECONDS);server.close();serverThread.join(1000);
    }
    private void await(CountDownLatch latch) throws Exception {assertTrue(latch.await(5,TimeUnit.SECONDS));}

    @Test public void recreatedActivityReceivesInFlightResultWithoutNewRequest() throws Exception {
        AtomicInteger oldCalls=new AtomicInteger(); CountDownLatch newResult=new CountDownLatch(1);
        AppUpdateChecker.StartupCheckCallback old=r -> oldCalls.incrementAndGet();
        checker.triggerStartupCheck(executor,url,"test",217,old);await(entered);
        checker.detachStartupCallback(old);
        assertFalse(checker.triggerStartupCheck(executor,url,"test",217,r -> newResult.countDown()));
        checker.detachStartupCallback(old); // A late destruction must not detach the replacement.
        release.countDown();await(newResult);
        assertEquals(0,oldCalls.get());assertEquals(1,requests.get());
    }
    @Test public void completedUndismissedResultReplaysToReplacement() throws Exception {
        CountDownLatch done=new CountDownLatch(1);
        AppUpdateChecker.StartupCheckCallback old=r -> done.countDown();
        checker.triggerStartupCheck(executor,url,"test",217,old);release.countDown();await(done);
        checker.detachStartupCallback(old);
        AtomicReference<AppRelease> replay=new AtomicReference<>();
        assertFalse(checker.triggerStartupCheck(executor,url,"test",217,replay::set));
        assertEquals(299,replay.get().versionCode);assertEquals(1,requests.get());
    }
    @Test public void dismissalSurvivesActivityReplacement() throws Exception {
        CountDownLatch done=new CountDownLatch(1);
        checker.triggerStartupCheck(executor,url,"test",217,r -> done.countDown());release.countDown();await(done);
        checker.markSessionPromptDismissed(); AtomicInteger replay=new AtomicInteger();
        checker.triggerStartupCheck(executor,url,"test",217,r -> replay.incrementAndGet());
        assertEquals(0,replay.get());assertEquals(1,requests.get());
    }
    @Test public void manualCheckJoinsRequestAndSuppressesAutomaticReplay() throws Exception {
        AtomicInteger automatic=new AtomicInteger(); CountDownLatch manual=new CountDownLatch(1);
        checker.triggerStartupCheck(executor,url,"test",217,r -> automatic.incrementAndGet());await(entered);
        checker.triggerManualCheck(executor,url,"test",new AppUpdateChecker.ManualCheckCallback(){
            public void onManualCheckSuccess(AppRelease r){manual.countDown();}
            public void onManualCheckFailure(Exception e){throw new AssertionError(e);}
        });release.countDown();await(manual);
        checker.triggerStartupCheck(executor,url,"test",217,r -> automatic.incrementAndGet());
        assertEquals(0,automatic.get());assertTrue(checker.isSessionPromptDismissed());assertEquals(1,requests.get());
    }
    @Test public void automaticFailureIsSilentButManualRetryReportsFailure() throws Exception {
        status=503; AtomicReference<AppRelease> result=new AtomicReference<>();CountDownLatch done=new CountDownLatch(1);
        checker.triggerStartupCheck(executor,url,"test",217,r -> {result.set(r);done.countDown();});
        release.countDown();await(done);assertNull(result.get());
        CountDownLatch failed=new CountDownLatch(1);
        checker.triggerManualCheck(executor,url,"test",new AppUpdateChecker.ManualCheckCallback(){
            public void onManualCheckSuccess(AppRelease r){throw new AssertionError("unexpected success");}
            public void onManualCheckFailure(Exception e){failed.countDown();}
        });await(failed);assertEquals(2,requests.get());
    }
}
