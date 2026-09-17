package com.xxcomic.local;
import android.content.Context;

/** One file lock and content index for Activity and background downloads. */
public final class LocalLibrary {
    private static final java.util.concurrent.ExecutorService covers = java.util.concurrent.Executors.newFixedThreadPool(2);
    private static LocalLibrary instance;
    public final LocalStorageManager storage;
    public final LocalLibraryStore store;
    public final LocalContentResolver resolver;
    private LocalLibrary(Context context) {
        storage=new LocalStorageManager(context);store=new LocalLibraryStore(context);
        resolver=new LocalContentResolver(store,storage);
    }
    public static synchronized LocalLibrary get(Context context) {
        if(instance==null) instance=new LocalLibrary(context.getApplicationContext());
        return instance;
    }
    public static void loadCover(android.app.Activity activity,android.widget.ImageView image,LocalModels.Book book) {
        LocalContentResolver resolver=get(activity).resolver;
        image.setTag(book.id);
        covers.execute(()->{
            android.graphics.Bitmap bitmap=resolver.decodeCoverBitmap(book.id,600,800);
            activity.runOnUiThread(()->{
                if(activity.isDestroyed() || !book.id.equals(image.getTag()) || !image.isAttachedToWindow()) {if(bitmap!=null)bitmap.recycle();return;}
                if(bitmap!=null)image.setImageBitmap(bitmap);
            });
        });
    }
}
