package app.noctorium.songfind

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Records what the phone is playing, for the few seconds asked for, then stops itself.
 *
 * Android only lets an app record another's sound through a media projection, and from Android 14 only from
 * inside a foreground service of the media-projection kind that is already running when the projection is
 * made -- so the recording happens here, with a notification saying so for as long as it lasts.
 */
class CaptureService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val request = pending
        if (intent == null || request == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        pending = null
        goForeground()

        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection: MediaProjection? = runCatching { manager.getMediaProjection(request.resultCode, request.data) }.getOrNull()
        if (projection == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            request.done(Result.failure(IllegalStateException("Android did not hand over what the phone is playing.")))
            finish()
            return START_NOT_STICKY
        }
        // Android 14 wants to be told who to tell when the projection ends, before anything is captured.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                recorder?.stop()
            }
        }, Handler(Looper.getMainLooper()))

        val recorder = Recorder(request.seconds, request.progress)
        Companion.recorder = recorder
        Thread {
            val outcome = runCatching { recorder.recordPlayback(projection) }
            runCatching { projection.stop() }
            Companion.recorder = null
            request.done(outcome)
            finish()
        }.start()
        return START_NOT_STICKY
    }

    private fun goForeground() {
        val notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "Listening", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while Song Find listens to what the phone is playing."
                },
            )
        }
        val notification = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this))
            .setContentTitle("Listening to what's playing")
            .setContentText("Song Find is finding the song.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION, notification)
        }
    }

    private fun finish() {
        Handler(Looper.getMainLooper()).post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
            stopSelf()
        }
    }

    private class Request(
        val resultCode: Int,
        val data: Intent,
        val seconds: Int,
        val progress: (Float, Float) -> Unit,
        val done: (Result<ByteArray>) -> Unit,
    )

    companion object {
        private const val CHANNEL = "listening"
        private const val NOTIFICATION = 27

        @Volatile
        private var pending: Request? = null

        @Volatile
        private var recorder: Recorder? = null

        fun start(
            context: Context,
            resultCode: Int,
            data: Intent,
            seconds: Int,
            progress: (Float, Float) -> Unit,
            done: (Result<ByteArray>) -> Unit,
        ) {
            pending = Request(resultCode, data, seconds, progress, done)
            val intent = Intent(context, CaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop() {
            recorder?.stop()
        }
    }
}
