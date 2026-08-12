package com.xxcomic;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

public class UpdateFileProvider extends ContentProvider {
    private static final String FILE_NAME = "xx-comic.apk";
    private static final String MIME_TYPE = "application/vnd.android.package-archive";

    @Override public boolean onCreate() { return true; }

    @Override
    public String getType(Uri uri) {
        return MIME_TYPE;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("只允许读取安装包");
        return ParcelFileDescriptor.open(validatedFile(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        File file;
        try {
            file = validatedFile(uri);
        } catch (FileNotFoundException error) {
            return null;
        }
        String[] columns = projection == null ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String column : columns) {
            if (OpenableColumns.DISPLAY_NAME.equals(column)) row.add(FILE_NAME);
            else if (OpenableColumns.SIZE.equals(column)) row.add(file.length());
            else row.add(null);
        }
        return cursor;
    }

    private File validatedFile(Uri uri) throws FileNotFoundException {
        if (getContext() == null || uri == null || !FILE_NAME.equals(uri.getLastPathSegment())) {
            throw new FileNotFoundException("安装包路径无效");
        }
        try {
            File root = new File(getContext().getCacheDir(), "app-update").getCanonicalFile();
            File file = new File(root, FILE_NAME).getCanonicalFile();
            if (!root.equals(file.getParentFile()) || !file.isFile()) throw new FileNotFoundException("安装包不存在");
            return file;
        } catch (java.io.IOException error) {
            throw new FileNotFoundException("安装包不可访问");
        }
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { throw new UnsupportedOperationException(); }
}
