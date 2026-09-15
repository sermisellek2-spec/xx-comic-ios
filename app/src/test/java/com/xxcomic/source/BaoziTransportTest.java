package com.xxcomic.source;

import org.junit.BeforeClass;
import org.junit.Test;
import java.io.*;
import java.net.*;
import java.lang.reflect.*;
import java.util.*;
import javax.net.ssl.SSLHandshakeException;
import static org.junit.Assert.*;

public class BaoziTransportTest {
    private static final List<FakeConnection> opened = new ArrayList<>();
    private static final Queue<IOException> failures = new LinkedList<>();

    @BeforeClass public static void installTransport() {
        URL.setURLStreamHandlerFactory(protocol -> "baozi-test".equals(protocol) ? new URLStreamHandler() {
            @Override protected URLConnection openConnection(URL url) {
                FakeConnection connection = new FakeConnection(url, failures.poll());
                opened.add(connection);
                return connection;
            }
        } : null);
    }

    @Test public void resetRetriesAndReleasesFailedConnections() throws Exception {
        reset(new SocketException("Connection reset"), new SocketException("Connection reset"));
        assertEquals("ok\n", fetch());
        assertEquals(3, opened.size());
        for (FakeConnection connection : opened) assertTrue(connection.closed);
    }

    @Test public void persistentResetStopsAfterThreeAttempts() throws Exception {
        reset(new SocketException("Connection reset"), new SocketException("Connection reset"),
                new SocketException("Connection reset"));
        try { fetch(); fail("Expected bounded failure"); }
        catch (IOException expected) { assertEquals(3, opened.size()); }
        for (FakeConnection connection : opened) assertTrue(connection.closed);
    }

    @Test public void certificateFailureIsNotRetriedAndConnectionIsReleased() throws Exception {
        SSLHandshakeException error = new SSLHandshakeException("Trust anchor not found");
        error.initCause(new java.security.cert.CertificateException("untrusted"));
        reset(error);
        try { fetch(); fail("Expected certificate failure"); }
        catch (IOException expected) {
            assertEquals(1, opened.size());
            assertTrue(expected.getMessage().contains("host"));
            assertSame(error, expected.getCause());
        }
        assertTrue(opened.get(0).closed);
    }

    @Test public void interruptedRequestDoesNotStartConnection() throws Exception {
        reset();
        Thread.currentThread().interrupt();
        try {
            fetch(); fail("Expected cancellation");
        } catch (IOException expected) {
            assertTrue(Thread.currentThread().isInterrupted());
            assertTrue(opened.isEmpty());
        } finally { Thread.interrupted(); }
    }

    private static void reset(IOException... errors) {
        opened.clear(); failures.clear(); failures.addAll(Arrays.asList(errors));
    }

    private static String fetch() throws Exception {
        Method method = BaoziComicSource.class.getDeclaredMethod("fetch", String.class);
        method.setAccessible(true);
        try { return (String) method.invoke(new BaoziComicSource(), "baozi-test://host/list"); }
        catch (InvocationTargetException e) { throw (Exception) e.getCause(); }
    }

    private static final class FakeConnection extends HttpURLConnection {
        final IOException error;
        boolean closed;
        FakeConnection(URL url, IOException error) { super(url); this.error = error; }
        @Override public int getResponseCode() throws IOException { if (error != null) throw error; return 200; }
        @Override public InputStream getInputStream() { return new ByteArrayInputStream(new byte[]{'o', 'k'}); }
        @Override public void disconnect() { closed = true; }
        @Override public boolean usingProxy() { return false; }
        @Override public void connect() { }
    }
}
