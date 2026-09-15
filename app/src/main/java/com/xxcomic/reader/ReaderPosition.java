package com.xxcomic.reader;

/** A position shared by continuous and single-image layouts. */
public final class ReaderPosition {
    public final int imageIndex;
    public final double offset;
    public final boolean atEnd;

    public ReaderPosition(int imageIndex, double offset, boolean atEnd) {
        this.imageIndex = Math.max(0, imageIndex);
        this.offset = Double.isNaN(offset) ? 0 : Math.max(0, Math.min(1, offset));
        this.atEnd = atEnd;
    }

    public int indexFor(int count) { return Math.max(0, Math.min(Math.max(0, count - 1), imageIndex)); }

    public int legacyProgress(int count) {
        if (count <= 0) return 0;
        if (atEnd) return 10000;
        return Math.max(0, Math.min(10000, (int) Math.round((indexFor(count) + offset) * 10000 / count)));
    }

    public static ReaderPosition fromLegacy(int progress, int count) {
        if (count <= 0) return new ReaderPosition(0, 0, false);
        double row = Math.max(0, Math.min(10000, progress)) * (double) count / 10000;
        int index = Math.min(count - 1, (int) Math.floor(row));
        return new ReaderPosition(index, progress >= 10000 ? 0 : row - index, progress >= 10000);
    }
}
