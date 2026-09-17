package com.xxcomic.download;
import org.junit.Test;
import static org.junit.Assert.*;
public class DownloadIdentityTest {
    @Test public void signedImageCredentialsAreDiscardedButScrambleIdentitySurvives() {
        assertEquals("https://cdn/image.jpg?scramble_id=20",DownloadRuntime.imageIdentity("https://cdn/image.jpg?token=secret&scramble_id=20&expires=1"));
        assertTrue(DownloadRuntime.sameImage("https://cdn/image.jpg?token=old","https://cdn/image.jpg?token=new"));
        assertFalse(DownloadRuntime.sameImage("https://cdn/image.jpg?scramble_id=20","https://cdn/image.jpg?scramble_id=21"));
    }
    @Test public void stableIdsDistinguishSourcesAndComponentBoundaries() {
        assertNotEquals(DownloadModels.bookId("a","bc"),DownloadModels.bookId("ab","c"));
        assertNotEquals(DownloadModels.bookId("source1","same"),DownloadModels.bookId("source2","same"));
    }
}
