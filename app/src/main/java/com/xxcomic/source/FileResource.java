package com.xxcomic.source;

import java.io.Serializable;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * Describes a downloadable file resource representing a single volume or book file.
 */
public final class FileResource implements Serializable {
    private static final long serialVersionUID = 1L;

    public final String fileId;
    public final String revision;
    public final String title;
    public final int order;
    public final String expectedFormat; // "zip", "cbz", "epub", "pdf", "mobi", "azw", "azw3"
    public final long bytes; // -1 if unknown
    public final String sha256; // optional expected SHA-256 hash (hex string, can be null/empty)
    public final String url;
    public final Map<String, String> headers;
    public final long expiresAt; // timestamp in millis, <= 0 means indefinite

    public FileResource(String fileId, String revision, String title, int order,
                        String expectedFormat, long bytes, String sha256,
                        String url, Map<String, String> headers, long expiresAt) {
        if (fileId == null || fileId.trim().isEmpty()) {
            throw new IllegalArgumentException("fileId cannot be null or empty");
        }
        this.fileId = fileId.trim();
        this.revision = revision != null ? revision.trim() : "";
        this.title = title != null ? title.trim() : "";
        this.order = order;
        this.expectedFormat = expectedFormat != null ? expectedFormat.trim().toLowerCase(java.util.Locale.ROOT) : "";
        this.bytes = bytes;
        this.sha256 = sha256 != null && !sha256.trim().isEmpty() ? sha256.trim().toLowerCase(java.util.Locale.ROOT) : null;
        this.url = url != null ? url.trim() : "";
        this.headers = headers != null ? Collections.unmodifiableMap(new HashMap<>(headers)) : Collections.emptyMap();
        this.expiresAt = expiresAt;
    }

    public boolean isExpired(long now) {
        return expiresAt > 0 && now >= expiresAt;
    }

    public FileResource withUrl(String newUrl, long newExpiresAt) {
        return new FileResource(fileId, revision, title, order, expectedFormat, bytes, sha256, newUrl, headers, newExpiresAt);
    }
}
