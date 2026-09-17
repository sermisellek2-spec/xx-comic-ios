package com.xxcomic.download;

import android.app.*;
import android.content.*;
import android.os.*;
import com.xxcomic.MainActivity;
import com.xxcomic.R;

/** Foreground only after an explicit user download/resume or foreground App startup recovery. */
public final class DownloadService extends Service {
    private static final String CHANNEL="comic_downloads";
    private static final int NOTIFICATION=2302;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private DownloadRuntime runtime;
    private PowerManager.WakeLock wakeLock;
    private boolean paused;
    private boolean destroyed;
    public static void start(Context context) {
        Intent intent=new Intent(context,DownloadService.class);
        if(Build.VERSION.SDK_INT>=26)context.startForegroundService(intent);else context.startService(intent);
    }
    @Override public void onCreate() {
        super.onCreate();runtime=DownloadRuntime.get(this);
        if(Build.VERSION.SDK_INT>=26) {
            NotificationChannel channel=new NotificationChannel(CHANNEL,"漫画离线下载",NotificationManager.IMPORTANCE_LOW);
            channel.setShowBadge(false);getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
        wakeLock=((PowerManager)getSystemService(POWER_SERVICE)).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"xxcomic:downloads");
        wakeLock.setReferenceCounted(false);
        startForeground(NOTIFICATION,notification("准备下载"));
    }
    @Override public int onStartCommand(Intent intent,int flags,int startId) {
        String action=intent==null?"":intent.getAction();
        if("pause".equals(action)){runtime.pauseAll();paused=true;}
        else if("resume".equals(action)){runtime.resumeAll();paused=false;}
        else paused=false;
        handler.removeCallbacks(tick);handler.post(tick);return START_NOT_STICKY;
    }
    private final Runnable tick=new Runnable(){public void run(){
        runtime.kick();
        runtime.io.execute(()->{
            String status="等待网络或重试";boolean active=false,pending=false;
            for(DownloadModels.Task task:runtime.store.list()) {
                pending|=DownloadModels.active(task.state)||task.state==DownloadModels.State.QUEUED||task.state==DownloadModels.State.WAITING_NETWORK;
                if(DownloadModels.active(task.state)){active=true;status=task.title+" · "+task.donePages+" / "+task.totalPages+" 页";}
            }
            final String message=status;final boolean running=active,waiting=pending;
            handler.post(()->{
                if(destroyed)return;
                if(running)wakeLock.acquire(10000);else if(wakeLock.isHeld())wakeLock.release();
                if(!waiting&&!paused){stopForeground(true);stopSelf();return;}
                getSystemService(NotificationManager.class).notify(NOTIFICATION,notification(paused?"下载已暂停":message));
                handler.postDelayed(tick,2000);
            });
        });
    }};
    private Notification notification(String text) {
        int flags=PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE;
        Intent open=new Intent(this,MainActivity.class).putExtra("open.downloads",true)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content=PendingIntent.getActivity(this,2302,open,flags);
        PendingIntent toggle=PendingIntent.getService(this,paused?2:1,new Intent(this,DownloadService.class).setAction(paused?"resume":"pause"),flags);
        Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,CHANNEL):new Notification.Builder(this);
        return b.setSmallIcon(R.drawable.ic_download).setContentTitle("蕾姆正在整理离线漫画")
                .setContentText(text).setContentIntent(content).setOngoing(true).setOnlyAlertOnce(true)
                .addAction(new Notification.Action.Builder(null,paused?"继续":"暂停",toggle).build()).build();
    }
    @Override public void onDestroy(){destroyed=true;handler.removeCallbacks(tick);runtime.stopWorker();if(wakeLock.isHeld())wakeLock.release();super.onDestroy();}
    @Override public IBinder onBind(Intent intent){return null;}
}
