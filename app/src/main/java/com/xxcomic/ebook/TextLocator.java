package com.xxcomic.ebook;

import org.json.JSONObject;

import java.io.Serializable;

/**
 * Represents a persistent reading position within a reflowable/text ebook.
 * Unlike image comics where pixel height or discrete page index is fixed,
 * text ebooks reflow when font size, line spacing, margins or screen rotation changes.
 * TextLocator tracks position by spine item, normalized resource href, anchor ID,
 * and relative scroll percentage for stable resumption.
 */
public class TextLocator implements Serializable {
    private static final long serialVersionUID = 1L;

    public final String bookId;
    public final int chapterIndex;
    public final int spineIndex;
    public final String resourceHref;
    public final String anchorId;
    public final float scrollPercentage;
    public final int charOffset;

    public TextLocator(String bookId, int chapterIndex, int spineIndex, String resourceHref,
                       String anchorId, float scrollPercentage, int charOffset) {
        this.bookId = bookId != null ? bookId : "";
        this.chapterIndex = Math.max(0, chapterIndex);
        this.spineIndex = Math.max(0, spineIndex);
        this.resourceHref = resourceHref != null ? resourceHref : "";
        this.anchorId = anchorId != null ? anchorId : "";
        this.scrollPercentage = Math.max(0f, Math.min(1f, scrollPercentage));
        this.charOffset = Math.max(0, charOffset);
    }

    public TextLocator withScrollPercentage(float newPercentage) {
        return new TextLocator(bookId, chapterIndex, spineIndex, resourceHref, anchorId, newPercentage, charOffset);
    }

    public TextLocator withAnchor(String newAnchor) {
        return new TextLocator(bookId, chapterIndex, spineIndex, resourceHref, newAnchor, scrollPercentage, charOffset);
    }

    public String toJson() {
        try {
            JSONObject obj = new JSONObject();
            obj.put("bookId", bookId);
            obj.put("chapterIndex", chapterIndex);
            obj.put("spineIndex", spineIndex);
            obj.put("resourceHref", resourceHref);
            obj.put("anchorId", anchorId);
            obj.put("scrollPercentage", (double) scrollPercentage);
            obj.put("charOffset", charOffset);
            return obj.toString();
        } catch (Exception e) {
            return "";
        }
    }

    public static TextLocator fromJson(String json) {
        if (json == null || json.trim().isEmpty()) return null;
        try {
            JSONObject obj = new JSONObject(json);
            return new TextLocator(
                    obj.optString("bookId"),
                    obj.optInt("chapterIndex", 0),
                    obj.optInt("spineIndex", 0),
                    obj.optString("resourceHref"),
                    obj.optString("anchorId"),
                    (float) obj.optDouble("scrollPercentage", 0.0),
                    obj.optInt("charOffset", 0)
            );
        } catch (Exception e) {
            return null;
        }
    }

    public static TextLocator forSpine(String bookId, int chapterIndex, int spineIndex, String resourceHref) {
        return new TextLocator(bookId, chapterIndex, spineIndex, resourceHref, "", 0.0f, 0);
    }
}
