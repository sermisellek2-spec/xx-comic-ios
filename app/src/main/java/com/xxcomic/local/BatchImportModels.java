package com.xxcomic.local;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Small, Android-free value objects used before a batch import is persisted. */
public final class BatchImportModels {
    private BatchImportModels() {}

    public static final class FileCandidate {
        public final String sourceId;
        public final String remoteComicId;
        public final String seriesTitle;
        public final String fileName;
        public final String fileId;
        public final Integer sourceOrder;
        public final String format;
        public final String fingerprint;
        public final int selectionIndex;

        public FileCandidate(String sourceId, String remoteComicId, String seriesTitle,
                             String fileName, String fileId, Integer sourceOrder,
                             String format, String fingerprint, int selectionIndex) {
            this.sourceId = clean(sourceId);
            this.remoteComicId = clean(remoteComicId);
            this.seriesTitle = clean(seriesTitle);
            this.fileName = clean(fileName);
            this.fileId = clean(fileId);
            this.sourceOrder = sourceOrder;
            this.format = clean(format);
            this.fingerprint = clean(fingerprint);
            this.selectionIndex = Math.max(0, selectionIndex);
        }

        private static String clean(String value) {
            return value == null ? "" : value.trim();
        }
    }

    public static final class ImportGroup {
        public final String key;
        public final String title;
        public final boolean requiresConfirmation;
        public final List<FileCandidate> volumes;

        public ImportGroup(String key, String title, boolean requiresConfirmation,
                           List<FileCandidate> volumes) {
            this.key = key;
            this.title = title;
            this.requiresConfirmation = requiresConfirmation;
            this.volumes = Collections.unmodifiableList(new ArrayList<>(volumes));
        }
    }
}
