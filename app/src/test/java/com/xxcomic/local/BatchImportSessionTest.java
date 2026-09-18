package com.xxcomic.local;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collections;

import static org.junit.Assert.*;

public class BatchImportSessionTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();

    @Test public void roundTripKeepsMetadataAndRestartsRunningItem() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.setTargetBookId(group, "book-123");
        session.start(group, group.items.get(0));
        BatchImportSession restored = BatchImportSession.load(file);
        assertEquals(session.taskId, restored.taskId);
        assertEquals("series", restored.groups.get(0).key);
        assertEquals("系列", restored.groups.get(0).title);
        assertEquals("book-123", restored.groups.get(0).targetBookId);
        BatchImportSession.Item item = restored.groups.get(0).items.get(0);
        assertEquals("content://books/1", item.uri);
        assertEquals("卷一.epub", item.name);
        assertEquals("epub", item.format);
        assertEquals(4, item.selectionIndex);
        assertEquals("pending", item.state);
        assertTrue(restored.hasPending());
    }

    @Test public void completedAndSkippedItemsNeverRestart() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.complete(group, group.items.get(0), "book-123");
        session.skip(group, group.items.get(1));
        BatchImportSession restored = BatchImportSession.load(file);
        assertFalse(restored.hasPending());
        assertTrue(restored.pendingGroups().isEmpty());
        restored.retryFailed();
        assertEquals("completed", restored.groups.get(0).items.get(0).state);
        assertEquals("skipped", restored.groups.get(0).items.get(1).state);
        assertEquals("book-123", restored.groups.get(0).targetBookId);
    }

    @Test public void failedItemDoesNotBlockRemainingWorkAndCanBeRetried() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.fail(group, group.items.get(0), "权限已失效");
        assertTrue(session.hasPending());
        session.complete(group, group.items.get(1), "book");
        assertFalse(session.hasPending());
        BatchImportSession restored = BatchImportSession.load(file);
        assertEquals("权限已失效", restored.groups.get(0).items.get(0).error);
        restored.retryFailed();
        assertEquals("pending", restored.groups.get(0).items.get(0).state);
        assertEquals("", restored.groups.get(0).items.get(0).error);
        assertTrue(BatchImportSession.load(file).hasPending());
    }

    @Test public void cancelPreservesCompletedItemsAndDoesNotTouchSourceFiles() throws Exception {
        File source = temporary.newFile("source.epub");
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.complete(group, group.items.get(0), "book");
        session.cancel();
        BatchImportSession restored = BatchImportSession.load(file);
        assertTrue(restored.cancelled);
        assertFalse(restored.hasPending());
        assertEquals("completed", restored.groups.get(0).items.get(0).state);
        assertEquals("skipped", restored.groups.get(0).items.get(1).state);
        assertTrue(source.isFile());
    }

    @Test public void corruptFileCannotBeSilentlyOverwritten() throws Exception {
        File file = temporary.newFile("session.json");
        byte[] corrupt = "{broken".getBytes(StandardCharsets.UTF_8);
        Files.write(file.toPath(), corrupt);
        assertThrows(IOException.class, () -> BatchImportSession.load(file));
        assertThrows(IOException.class, () -> create(file));
        assertArrayEquals(corrupt, Files.readAllBytes(file.toPath()));
    }

    @Test public void interruptedReplacementLoadsLastDurableBackup() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.complete(group, group.items.get(0), "book");
        File backup = new File(file.getPath() + ".bak");
        assertTrue(file.renameTo(backup));
        // A blocked primary path emulates failure between backing up and installing temp.
        assertTrue(file.mkdir());
        Files.write(new File(file, "blocker").toPath(), new byte[]{1});
        BatchImportSession restored = BatchImportSession.load(file);
        assertEquals("completed", restored.groups.get(0).items.get(0).state);
        assertEquals("book", restored.groups.get(0).targetBookId);
        assertThrows(IOException.class, restored::cancel);
        assertTrue(backup.isFile());
        assertEquals("pending", BatchImportSession.load(file).groups.get(0).items.get(1).state);
    }

    @Test public void failedTempWriteKeepsPrimaryAndInMemoryState() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        byte[] previous = Files.readAllBytes(file.toPath());
        assertTrue(new File(file.getPath() + ".tmp").mkdir());
        BatchImportSession.Group group = session.groups.get(0);
        assertThrows(IOException.class, () -> session.complete(group, group.items.get(0), "book"));
        assertArrayEquals(previous, Files.readAllBytes(file.toPath()));
        assertEquals("pending", group.items.get(0).state);
        assertEquals("", group.targetBookId);
    }

    @Test public void cannotReplaceAnActiveSession() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        assertThrows(IOException.class, () -> create(file));
        assertEquals(session.taskId, BatchImportSession.load(file).taskId);
    }

    @Test public void retryResetsInterruptedRunningItemInSameProcess() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.setTargetBookId(group, "stable-book");
        session.start(group, group.items.get(0));
        session.complete(group, group.items.get(1), "stable-book");
        session.retryFailed();
        assertEquals("pending", group.items.get(0).state);
        assertEquals("completed", group.items.get(1).state);
        assertEquals("stable-book", BatchImportSession.load(file).groups.get(0).targetBookId);
    }

    @Test public void cancelledSessionRejectsQueuedWorkerStart() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession session = create(file);
        BatchImportSession.Group group = session.groups.get(0);
        session.cancel();
        assertThrows(IOException.class, () -> session.start(group, group.items.get(0)));
        assertFalse(BatchImportSession.load(file).hasPending());
        assertEquals("skipped", group.items.get(0).state);
    }

    @Test public void appendTargetRemainsRequiredAcrossRestartBeforeFirstVolumeCompletes() throws Exception {
        File file = new File(temporary.getRoot(), "session.json");
        BatchImportSession.Group group = new BatchImportSession.Group("append", "Series", "existing-book",
                Collections.singletonList(new BatchImportSession.Item("uri", "vol.epub", "epub", 0)), true);
        BatchImportSession.create(file, Collections.singletonList(group));
        BatchImportSession restored = BatchImportSession.load(file);
        assertTrue(restored.groups.get(0).requiresExistingBook);
        assertEquals("existing-book", restored.groups.get(0).targetBookId);
    }

    private BatchImportSession create(File file) throws IOException {
        return BatchImportSession.create(file, Collections.singletonList(new BatchImportSession.Group(
                "series", "系列", "", Arrays.asList(
                new BatchImportSession.Item("content://books/1", "卷一.epub", "epub", 4),
                new BatchImportSession.Item("content://books/2", "卷二.pdf", "pdf", 5)))));
    }
}
