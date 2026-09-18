package com.xxcomic;

import android.app.Instrumentation;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import com.xxcomic.reader.ZoomImageView;

/** Real MotionEvent regressions; runs offline with -e zoomOnly true. */
public final class ReaderZoomChecks {
    private final Instrumentation instrumentation;
    private ZoomImageView image;
    private Bitmap bitmap;
    private long downTime;

    private ReaderZoomChecks(Instrumentation instrumentation) { this.instrumentation = instrumentation; }

    public static int run(Instrumentation instrumentation) throws Exception {
        return new ReaderZoomChecks(instrumentation).run();
    }

    private int run() throws Exception {
        instrumentation.runOnMainSync(() -> {
            image = new ZoomImageView(instrumentation.getTargetContext());
            image.layout(0, 0, 1000, 1000);
            bitmap = Bitmap.createBitmap(1000, 1000, Bitmap.Config.ARGB_8888);
            image.setImageBitmap(bitmap);
        });
        try {
            event(MotionEvent.ACTION_DOWN, new int[]{0}, 300);
            event(MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), new int[]{0, 1}, 300, 700);
            event(MotionEvent.ACTION_MOVE, new int[]{0, 1}, 220, 780);
            event(MotionEvent.ACTION_MOVE, new int[]{0, 1}, 180, 820);
            check(values()[Matrix.MSCALE_X] > 1.05f, "pinch must zoom");
            event(MotionEvent.ACTION_POINTER_UP, new int[]{0, 1}, 180, 820);
            float[] before = values();
            event(MotionEvent.ACTION_MOVE, new int[]{1}, 832);
            float[] after = values();
            check(Math.abs(after[Matrix.MTRANS_X] - before[Matrix.MTRANS_X] - 12f) < .5f,
                    "lifting pointer 0 must keep remaining pointer's pan origin");
            event(MotionEvent.ACTION_UP, new int[]{1}, 832);
            settle();

            instrumentation.runOnMainSync(image::resetZoom);
            doubleTap();
            settle();
            check(values()[Matrix.MSCALE_X] > 2f, "second tap UP must not cancel double-tap zoom");

            // Reset animation must not snap to fit when a new gesture cancels it.
            SystemClock.sleep(350);
            doubleTap();
            SystemClock.sleep(65);
            final float[][] interrupted = new float[2][];
            instrumentation.runOnMainSync(() -> {
                interrupted[0] = valuesOnMain();
                send(MotionEvent.ACTION_DOWN, new int[]{0}, 500);
                interrupted[1] = valuesOnMain();
            });
            check(interrupted[0][Matrix.MSCALE_X] > 1.01f, "fixture must interrupt active reset");
            check(Math.abs(interrupted[0][Matrix.MSCALE_X] - interrupted[1][Matrix.MSCALE_X]) < .001f,
                    "new DOWN must cancel reset without snapping");
            settle();
            check(Math.abs(values()[Matrix.MSCALE_X] - interrupted[1][Matrix.MSCALE_X]) < .001f,
                    "cancelled animation must not keep changing the transform");
            event(MotionEvent.ACTION_UP, new int[]{0}, 500);
            return 6;
        } finally {
            instrumentation.runOnMainSync(() -> { image.resetZoom(); image.setImageDrawable(null); bitmap.recycle(); });
        }
    }

    private void doubleTap() {
        event(MotionEvent.ACTION_DOWN, new int[]{0}, 500);
        event(MotionEvent.ACTION_UP, new int[]{0}, 500);
        SystemClock.sleep(65);
        event(MotionEvent.ACTION_DOWN, new int[]{0}, 500);
        event(MotionEvent.ACTION_UP, new int[]{0}, 500);
    }

    private void event(int action, int[] ids, float... x) {
        instrumentation.runOnMainSync(() -> send(action, ids, x));
    }

    private void send(int action, int[] ids, float... x) {
        long now = SystemClock.uptimeMillis();
        if (action == MotionEvent.ACTION_DOWN) downTime = now;
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[ids.length];
        MotionEvent.PointerCoords[] points = new MotionEvent.PointerCoords[ids.length];
        for (int i = 0; i < ids.length; i++) {
            properties[i] = new MotionEvent.PointerProperties();
            properties[i].id = ids[i];
            properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            points[i] = new MotionEvent.PointerCoords();
            points[i].x = x[i]; points[i].y = 500; points[i].pressure = 1; points[i].size = 1;
        }
        MotionEvent event = MotionEvent.obtain(downTime, now, action, ids.length, properties, points,
                0, 0, 1, 1, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
        image.onTouchEvent(event);
        event.recycle();
    }

    private float[] values() {
        float[][] result = new float[1][];
        instrumentation.runOnMainSync(() -> result[0] = valuesOnMain());
        return result[0];
    }

    private float[] valuesOnMain() {
        float[] result = new float[9];
        image.getImageMatrix().getValues(result);
        return result;
    }

    private void settle() { SystemClock.sleep(300); instrumentation.waitForIdleSync(); }
    private static void check(boolean success, String message) { if (!success) throw new AssertionError(message); }
}
