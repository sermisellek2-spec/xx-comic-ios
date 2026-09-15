package com.xxcomic.source;

import org.json.JSONObject;
import org.junit.Test;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.security.cert.CertificateException;
import java.util.ArrayList;
import java.util.List;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLPeerUnverifiedException;
import static org.junit.Assert.*;

public class CopyMangaConnectionTest {
    private static final String PRIMARY = "https://api.manga2026.xyz";
    private static final String FIRST = "https://mapi.elfgjfghkk.club";
    private static final String SECOND = "https://mapi.fgjfghkkcenter.club";
    private static final String BODY = "{\"code\":200,\"results\":{\"list\":[]}}";

    @Test public void resetSwitchesLineAndReusesWorkingLineWithOriginalPathAndQuery() throws Exception {
        List<String> requests = new ArrayList<>();
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String request(String url, boolean api) throws IOException {
                assertTrue(api);
                requests.add(url);
                if (url.startsWith(PRIMARY)) throw new SocketException("Connection reset");
                return BODY;
            }
        };
        String path = "/api/v3/comic/a/group/default/chapters?limit=100&offset=100&q=a%20b";
        assertEquals(BODY, source.fetchApi(PRIMARY + path));
        source.fetchApi(PRIMARY + "/api/v3/comic/a/chapter/b?platform=3");
        assertEquals(3, requests.size());
        assertEquals(PRIMARY + path, requests.get(0));
        assertEquals(FIRST + path, requests.get(1));
        assertEquals(FIRST + "/api/v3/comic/a/chapter/b?platform=3", requests.get(2));
    }

    @Test public void networkChangeCanRecoverWhenRememberedLineStopsWorking() throws Exception {
        List<String> requests = new ArrayList<>();
        boolean[] changed = {false};
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String request(String url, boolean api) throws IOException {
                requests.add(url);
                if ((!changed[0] && !url.startsWith(FIRST)) || (changed[0] && !url.startsWith(PRIMARY)))
                    throw new SocketTimeoutException("connect timeout");
                return BODY;
            }
        };
        source.fetchApi(PRIMARY + "/api/v3/one");
        changed[0] = true;
        source.fetchApi(PRIMARY + "/api/v3/two");
        source.fetchApi(PRIMARY + "/api/v3/three");
        assertEquals(FIRST + "/api/v3/two", requests.get(2));
        assertEquals(PRIMARY + "/api/v3/two", requests.get(3));
        assertEquals(PRIMARY + "/api/v3/three", requests.get(4));
    }

    @Test public void allFailedLinesAreBoundedAndReportedWithTheirOriginalCauses() throws Exception {
        List<String> requests = new ArrayList<>();
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String request(String url, boolean api) throws IOException {
                requests.add(url);
                if (url.startsWith(PRIMARY)) throw new SocketException("Connection reset");
                if (url.startsWith(FIRST)) throw new UnknownHostException("DNS failed");
                throw new SocketTimeoutException("timed out");
            }
        };
        IOException error = assertThrows(IOException.class, () -> source.fetchApi(PRIMARY + "/api/v3/comic/a"));
        assertEquals(3, requests.size());
        assertEquals(2, error.getSuppressed().length);
        assertTrue(error.getMessage().contains("api.manga2026.xyz"));
        assertTrue(error.getMessage().contains("mapi.elfgjfghkk.club"));
        assertTrue(error.getMessage().contains("mapi.fgjfghkkcenter.club"));
        assertTrue(error.getCause().getCause() instanceof SocketTimeoutException);
    }

    @Test public void secondBackupCanRecoverHandshakeResets() throws Exception {
        List<String> requests = new ArrayList<>();
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String request(String url, boolean api) throws IOException {
                requests.add(url);
                if (!url.startsWith(SECOND)) throw new SSLHandshakeException("Remote host terminated the handshake");
                return BODY;
            }
        };
        assertEquals(BODY, source.fetchApi(PRIMARY + "/api/v3/one"));
        assertEquals(3, requests.size());
        assertEquals(SECOND + "/api/v3/one", requests.get(2));
    }

    @Test public void httpErrorsAndPlaceholderResponsesDoNotFanOutToOtherHosts() throws Exception {
        for (String body : new String[]{null, "<html>error</html>", "{\"code\":403}", "{\"code\":200,\"results\":null}"}) {
            List<String> requests = new ArrayList<>();
            CopyMangaComicSource source = new CopyMangaComicSource() {
                @Override protected String request(String url, boolean api) throws IOException {
                    requests.add(url);
                    if (body == null) throw new IOException("HTTP 429");
                    return body;
                }
            };
            try { source.fetchApi(PRIMARY + "/api/v3/one"); } catch (IOException expected) { }
            assertEquals(1, requests.size());
        }
    }

    @Test public void customApiAndExplicitlyDisabledFallbackStayOnTheSelectedHost() throws Exception {
        for (String host : new String[]{PRIMARY, "https://custom.example"}) {
            JSONObject config = SourceConfig.copy4000(true).toJson();
            config.getJSONObject("routes").put("apiBaseUrl", host);
            if (host.equals(PRIMARY)) config.getJSONObject("routes").put("apiFallbackUrls", "");
            List<String> requests = new ArrayList<>();
            CopyMangaComicSource source = new CopyMangaComicSource(SourceConfig.fromJson(config, SourceConfig.copy4000(true))) {
                @Override protected String request(String url, boolean api) throws IOException {
                    requests.add(url); throw new SocketException("Connection reset");
                }
            };
            assertThrows(IOException.class, () -> source.fetchApi(host + "/api/v3/one"));
            assertEquals(1, requests.size());
            assertTrue(requests.get(0).startsWith(host));
        }
    }

    @Test public void certificateFailuresAndCancellationAreNotRetried() throws Exception {
        SSLHandshakeException certificate = new SSLHandshakeException("Certificate rejected");
        certificate.initCause(new CertificateException("untrusted issuer"));
        for (IOException failure : new IOException[]{certificate, new SSLPeerUnverifiedException("hostname mismatch"), new InterruptedIOException("cancelled")}) {
            List<String> requests = new ArrayList<>();
            CopyMangaComicSource source = new CopyMangaComicSource() {
                @Override protected String request(String url, boolean api) throws IOException { requests.add(url); throw failure; }
            };
            assertThrows(IOException.class, () -> source.fetchApi(PRIMARY + "/api/v3/one"));
            assertEquals(1, requests.size());
        }
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String request(String url, boolean api) { throw new AssertionError("Cancelled request must not connect"); }
        };
        Thread.currentThread().interrupt();
        try { assertThrows(InterruptedIOException.class, () -> source.fetchApi(PRIMARY + "/api/v3/one")); }
        finally { Thread.interrupted(); }
    }
}
