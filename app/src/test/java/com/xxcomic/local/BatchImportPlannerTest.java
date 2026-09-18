package com.xxcomic.local;

import org.junit.Test;

import java.util.Arrays;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class BatchImportPlannerTest {
    @Test
    public void groupsRemoteFilesBySourceAndComicAndSortsByVolume() {
        List<BatchImportModels.FileCandidate> files = Arrays.asList(
                candidate("kzo", "10872", "城市猎人_10.epub", "hash10", null, 1),
                candidate("kzo", "10872", "城市猎人_2.epub", "hash2", null, 0),
                candidate("kzo", "10872", "城市猎人_01.epub", "hash1", null, 2));

        List<BatchImportModels.ImportGroup> groups = BatchImportPlanner.plan(files);

        assertEquals(1, groups.size());
        assertFalse(groups.get(0).requiresConfirmation);
        assertEquals(Arrays.asList("城市猎人_01.epub", "城市猎人_2.epub", "城市猎人_10.epub"),
                names(groups.get(0)));
    }

    @Test
    public void localFilesWithSameTitleAreOnlySuggestedAndNeedConfirmation() {
        List<BatchImportModels.FileCandidate> files = Arrays.asList(
                candidate(null, null, "城市猎人 第02卷.epub", "a", null, 0),
                candidate(null, null, "城市猎人 第01卷.mobi", "b", null, 1));

        List<BatchImportModels.ImportGroup> groups = BatchImportPlanner.plan(files);

        assertEquals(1, groups.size());
        assertTrue(groups.get(0).requiresConfirmation);
        assertEquals("城市猎人", groups.get(0).title);
    }

    @Test
    public void duplicateFingerprintAppearsOnlyOnce() {
        List<BatchImportModels.FileCandidate> files = Arrays.asList(
                candidate("source", "comic", "第一卷.epub", "same", null, 0),
                candidate("source", "comic", "第一卷-copy.epub", "same", null, 1));

        List<BatchImportModels.ImportGroup> groups = BatchImportPlanner.plan(files);

        assertEquals(1, groups.size());
        assertEquals(1, groups.get(0).volumes.size());
    }

    @Test
    public void explicitOrderWinsOverFilenameOrder() {
        BatchImportModels.FileCandidate first = candidate("source", "comic", "卷10.epub", "10", 0, 0);
        BatchImportModels.FileCandidate second = candidate("source", "comic", "卷01.epub", "1", 1, 1);

        List<BatchImportModels.ImportGroup> groups = BatchImportPlanner.plan(Arrays.asList(first, second));

        assertEquals(Arrays.asList("卷10.epub", "卷01.epub"), names(groups.get(0)));
    }

    private static BatchImportModels.FileCandidate candidate(String source, String comic, String name,
                                                               String fingerprint, Integer order, int selection) {
        return new BatchImportModels.FileCandidate(source, comic, null, name, "", order,
                "epub", fingerprint, selection);
    }

    private static List<String> names(BatchImportModels.ImportGroup group) {
        java.util.ArrayList<String> names = new java.util.ArrayList<>();
        for (BatchImportModels.FileCandidate volume : group.volumes) names.add(volume.fileName);
        return names;
    }
}
