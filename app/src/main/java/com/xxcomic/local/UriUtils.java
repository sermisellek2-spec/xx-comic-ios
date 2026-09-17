package com.xxcomic.local;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;

import java.io.File;

public final class UriUtils {
    private UriUtils() {}

    public static File resolveDirectFile(Context context, Uri uri) {
        if (uri == null) return null;

        // 1. Direct file:// scheme
        if ("file".equalsIgnoreCase(uri.getScheme())) {
            String path = uri.getPath();
            if (path != null) {
                File f = new File(path);
                if (f.exists() && f.canRead()) return f;
            }
        }

        // 2. content:// scheme
        if (ContentResolver.SCHEME_CONTENT.equalsIgnoreCase(uri.getScheme()) && context != null) {
            // Check DocumentsContract document or tree
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    String authority = uri.getAuthority();
                    if ("com.android.externalstorage.documents".equals(authority)) {
                        String docId = null;
                        if (DocumentsContract.isDocumentUri(context, uri)) {
                            docId = DocumentsContract.getDocumentId(uri);
                        } else {
                            try {
                                docId = DocumentsContract.getTreeDocumentId(uri);
                            } catch (Exception ignored) {}
                        }
                        if (docId != null) {
                            String[] split = docId.split(":");
                            if (split.length > 0) {
                                String type = split[0];
                                String relPath = split.length > 1 ? split[1] : "";
                                if ("primary".equalsIgnoreCase(type)) {
                                    File f = new File(Environment.getExternalStorageDirectory(), relPath);
                                    if (f.exists() && f.canRead()) return f;
                                } else {
                                    File f = new File("/storage/" + type, relPath);
                                    if (f.exists() && f.canRead()) return f;
                                }
                            }
                        }
                    } else if ("com.android.providers.downloads.documents".equals(authority)) {
                        if (DocumentsContract.isDocumentUri(context, uri)) {
                            String id = DocumentsContract.getDocumentId(uri);
                            if (id != null) {
                                if (id.startsWith("raw:")) {
                                    File f = new File(id.substring(4));
                                    if (f.exists() && f.canRead()) return f;
                                } else {
                                    try {
                                        long longId = Long.parseLong(id);
                                        Uri contentUri = android.content.ContentUris.withAppendedId(
                                                Uri.parse("content://downloads/public_downloads"), longId);
                                        File f = queryDataColumn(context, contentUri, null, null);
                                        if (f != null && f.canRead()) return f;
                                    } catch (Exception ignored) {}
                                }
                            }
                        }
                    } else if ("com.android.providers.media.documents".equals(authority)) {
                        if (DocumentsContract.isDocumentUri(context, uri)) {
                            String docId = DocumentsContract.getDocumentId(uri);
                            String[] split = docId.split(":");
                            String type = split.length > 0 ? split[0] : "";
                            String id = split.length > 1 ? split[1] : "";
                            Uri contentUri = null;
                            if ("image".equals(type)) {
                                contentUri = android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
                            } else if ("video".equals(type)) {
                                contentUri = android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
                            } else if ("audio".equals(type)) {
                                contentUri = android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
                            } else {
                                contentUri = android.provider.MediaStore.Files.getContentUri("external");
                            }
                            File f = queryDataColumn(context, contentUri, "_id=?", new String[]{id});
                            if (f != null && f.canRead()) return f;
                        }
                    }
                }
            } catch (Exception ignored) {}

            File f = queryDataColumn(context, uri, null, null);
            if (f != null && f.canRead()) return f;
        }

        return null;
    }

    public static File queryDataColumn(Context context, Uri uri, String selection, String[] selectionArgs) {
        if (context == null || uri == null) return null;
        try (Cursor cursor = context.getContentResolver().query(uri,
                new String[]{"_data"}, selection, selectionArgs, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int idx = cursor.getColumnIndex("_data");
                if (idx >= 0) {
                    String path = cursor.getString(idx);
                    if (path != null) {
                        return new File(path);
                    }
                }
            }
        } catch (Exception ignored) {}
        return null;
    }

    public static File resolveFileOrProcFd(Context context, Uri uri, ParcelFileDescriptor[] outPfd) {
        File direct = resolveDirectFile(context, uri);
        if (direct != null && direct.canRead()) {
            return direct;
        }
        if (context == null || uri == null) return null;

        // Try /proc/self/fd approach on Linux / Android
        try {
            ParcelFileDescriptor pfd = context.getContentResolver().openFileDescriptor(uri, "r");
            if (pfd != null) {
                File procFile = new File("/proc/self/fd/" + pfd.getFd());
                if (procFile.exists()) {
                    if (outPfd != null && outPfd.length > 0) {
                        outPfd[0] = pfd;
                    }
                    return procFile;
                } else {
                    pfd.close();
                }
            }
        } catch (Exception ignored) {}

        return null;
    }
}
