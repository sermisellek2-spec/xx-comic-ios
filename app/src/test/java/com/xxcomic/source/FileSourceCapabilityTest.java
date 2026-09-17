package com.xxcomic.source;

import com.xxcomic.download.DownloadCoordinator;
import com.xxcomic.download.DownloadModels;
import com.xxcomic.download.DownloadStore;

import org.junit.Test;
import org.junit.Rule;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.util.*;

import static org.junit.Assert.*;

public class FileSourceCapabilityTest {

    @Rule
    public TemporaryFolder tempFolder = new TemporaryFolder();

    @Test
    public void existingImageSourcesDoNotImplementFileCapability() {
        assertFalse(new BaoziComicSource(SourceConfig.baozi(true)) instanceof FileSourceCapability);
        assertFalse(new GmhComicSource(SourceConfig.gmh(true)) instanceof FileSourceCapability);
        assertFalse(new CopyMangaComicSource(SourceConfig.copy4000(true)) instanceof FileSourceCapability);
    }

    @Test
    public void fileResourcePropertiesAndExpirationCheck() {
        Map<String, String> headers = new HashMap<>();
        headers.put("Authorization", "Bearer secret");
        long future = System.currentTimeMillis() + 60000;
        FileResource resource = new FileResource("vol1", "v1.0", "第 1 卷", 0,
                "epub", 1024L * 1024L, "aabbccddeeff", "https://cdn.example.com/vol1.epub", headers, future);

        assertEquals("vol1", resource.fileId);
        assertEquals("v1.0", resource.revision);
        assertEquals("第 1 卷", resource.title);
        assertEquals(0, resource.order);
        assertEquals("epub", resource.expectedFormat);
        assertEquals(1024L * 1024L, resource.bytes);
        assertEquals("aabbccddeeff", resource.sha256);
        assertEquals("https://cdn.example.com/vol1.epub", resource.url);
        assertEquals("Bearer secret", resource.headers.get("Authorization"));
        assertFalse(resource.isExpired(System.currentTimeMillis()));
        assertTrue(resource.isExpired(future + 1000));

        FileResource renewed = resource.withUrl("https://cdn.example.com/vol1_new.epub", future + 120000);
        assertEquals("https://cdn.example.com/vol1_new.epub", renewed.url);
        assertEquals(future + 120000, renewed.expiresAt);
    }

    static final class MemoryRepo implements DownloadCoordinator.Repository {
        final Map<String, DownloadModels.Task> data = new LinkedHashMap<>();
        @Override public List<DownloadModels.Task> list() { return new ArrayList<>(data.values()); }
        @Override public DownloadModels.Task get(String id) { return data.get(id); }
        @Override public void save(DownloadModels.Task task) { data.put(task.id, task); }
    }

    @Test
    public void enqueueFilesMaintainsVolumeOrderAndSeparateIdentities() {
        MemoryRepo repo = new MemoryRepo();
        DownloadCoordinator queue = new DownloadCoordinator(repo);

        List<FileResource> files = Arrays.asList(
                new FileResource("vol1", "r1", "第 1 卷", 0, "zip", 5000L, null, "https://example/v1.zip", Collections.emptyMap(), 0),
                new FileResource("vol2", "r1", "第 2 卷", 1, "zip", 6000L, null, "https://example/v2.zip", Collections.emptyMap(), 0),
                new FileResource("vol3", "r1", "第 3 卷", 2, "zip", 7000L, null, "https://example/v3.zip", Collections.emptyMap(), 0)
        );

        // Enqueue only vol1 and vol3
        queue.enqueueFiles("filesource", "comic123", files, Arrays.asList("vol1", "vol3"));
        assertEquals(2, repo.list().size());

        DownloadModels.Task t1 = queue.claim(0, true, true, true);
        assertNotNull(t1);
        assertEquals("vol1", t1.fileId);
        assertTrue(t1.isFileTask);
        assertEquals(0, t1.order);
        assertEquals("zip", t1.expectedFormat);

        // Re-enqueuing duplicate does not duplicate entries
        queue.enqueueFiles("filesource", "comic123", files, Collections.singletonList("vol1"));
        assertEquals(2, repo.list().size());
    }

    @Test
    public void fileTaskSerializationRoundTripInDownloadStore() throws Exception {
        DownloadModels.Task task = new DownloadModels.Task();
        task.id = "task_test_file";
        task.bookId = "book_file_1";
        task.sourceId = "test_source";
        task.comicId = "comic_abc";
        task.chapterId = "vol_01";
        task.title = "第 1 卷";
        task.url = "https://cdn.test/vol1.epub";
        task.order = 1;
        task.isFileTask = true;
        task.fileId = "vol_01";
        task.revision = "rev-2026";
        task.expectedFormat = "epub";
        task.sha256 = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        task.expiresAt = 9999999999L;
        task.refreshCount = 1;

        org.json.JSONObject serialized = DownloadStore.serializeTask(task);
        assertNotNull(serialized);
        assertFalse(serialized.toString().contains("https://cdn.test"));

        DownloadModels.Task loaded = DownloadStore.parseTask(serialized.toString());
        assertNotNull(loaded);
        assertTrue(loaded.isFileTask);
        assertEquals("vol_01", loaded.fileId);
        assertEquals("rev-2026", loaded.revision);
        assertEquals("epub", loaded.expectedFormat);
        assertEquals("1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", loaded.sha256);
        assertEquals(9999999999L, loaded.expiresAt);
        assertEquals(1, loaded.refreshCount);

        // Also test legacy task backwards compatibility (missing file fields)
        DownloadModels.Task legacy = new DownloadModels.Task();
        legacy.id = "legacy_ch_1";
        legacy.bookId = "b1";
        legacy.sourceId = "s1";
        legacy.comicId = "c1";
        legacy.chapterId = "ch1";
        legacy.title = "第 1 话";
        legacy.url = "https://cdn/ch1";
        legacy.order = 0;
        legacy.isFileTask = false;
        DownloadModels.Task parsedLegacy = DownloadStore.parseTask(DownloadStore.serializeTask(legacy).toString());
        assertFalse(parsedLegacy.isFileTask);
        assertNull(parsedLegacy.fileId);
        assertEquals("", parsedLegacy.revision);
        assertEquals(0, parsedLegacy.refreshCount);
    }

    @Test public void changedRevisionRequeuesSameVolumeAndOldLeaseCannotPublishAfterDelete() {
        MemoryRepo repo=new MemoryRepo();DownloadCoordinator queue=new DownloadCoordinator(repo);
        FileResource first=new FileResource("v1","a","第一卷",0,"zip",10,null,"https://cdn/a?token=secret",null,0);
        FileResource second=new FileResource("v2","a","第二卷",1,"zip",10,null,"https://cdn/same",null,0);
        queue.enqueueFiles("source","comic",Arrays.asList(second,first),Arrays.asList("v2","v1"));
        DownloadModels.Task lease=queue.claim(0,true,true,true);assertEquals("v1",lease.fileId);
        assertNotEquals(lease.bookId,repo.list().get(1).bookId);
        queue.complete(lease);
        FileResource changed=new FileResource("v1","b","第一卷",0,"zip",20,null,"https://cdn/new",null,0);
        queue.enqueueFiles("source","comic",Collections.singletonList(changed),Collections.singletonList("v1"));
        assertEquals(2,repo.list().size());assertEquals(DownloadModels.State.QUEUED,repo.get(lease.id).state);
        DownloadModels.Task replacement=queue.claim(0,true,true,true);assertEquals(lease.bookId,replacement.bookId);
        repo.data.remove(replacement.id);
        queue.enqueueFiles("source","comic",Collections.singletonList(changed),Collections.singletonList("v1"));
        assertFalse(queue.complete(replacement));
        for(DownloadModels.Task task:repo.list())assertEquals("",task.url);
    }
}
