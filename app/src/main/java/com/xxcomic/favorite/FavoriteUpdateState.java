package com.xxcomic.favorite;

import org.json.JSONException;
import org.json.JSONObject;

public final class FavoriteUpdateState {
    public final String sourceId;
    public final String comicId;
    public boolean pendingUpdate;
    public FavoriteRevision observedRevision;
    public FavoriteRevision acknowledgedRevision;

    public FavoriteUpdateState(String sourceId, String comicId, boolean pendingUpdate,
                               FavoriteRevision observedRevision, FavoriteRevision acknowledgedRevision) {
        this.sourceId = sourceId == null ? "" : sourceId;
        this.comicId = comicId == null ? "" : comicId;
        this.pendingUpdate = pendingUpdate;
        this.observedRevision = observedRevision;
        this.acknowledgedRevision = acknowledgedRevision;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject object = new JSONObject();
        object.put("sourceId", sourceId);
        object.put("comicId", comicId);
        object.put("pendingUpdate", pendingUpdate);
        if (observedRevision != null) {
            object.put("observedRevision", observedRevision.toJson());
        }
        if (acknowledgedRevision != null) {
            object.put("acknowledgedRevision", acknowledgedRevision.toJson());
        }
        return object;
    }

    public static FavoriteUpdateState fromJson(JSONObject object) {
        if (object == null) return null;
        String sourceId = object.optString("sourceId", "");
        String comicId = object.optString("comicId", "");
        boolean pendingUpdate = object.optBoolean("pendingUpdate", false);
        FavoriteRevision observed = object.has("observedRevision")
                ? FavoriteRevision.fromJson(object.optJSONObject("observedRevision")) : null;
        FavoriteRevision acknowledged = object.has("acknowledgedRevision")
                ? FavoriteRevision.fromJson(object.optJSONObject("acknowledgedRevision")) : null;
        return new FavoriteUpdateState(sourceId, comicId, pendingUpdate, observed, acknowledged);
    }
}
