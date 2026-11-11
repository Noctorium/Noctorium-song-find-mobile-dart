package app.noctorium.songfind

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
import android.os.SystemClock
import kotlin.math.ceil

/**
 * Records for the few seconds asked for, then stops itself: the microphone, or what the phone is playing.
 *
 * Both happen in a foreground service, with a notification counting down for as long as it lasts, so that
 * listening goes on when the listener switches to the app playing the song. Android cuts an app that is not
 * on screen off from the microphone unless a foreground service of the microphone kind holds it; and it only
 * lets an app record another's sound through a media projection, from Android 14 only inside a foreground
 * service of the media-projection kind that is already running when the projection is made.
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
        val playback = request.data != null
        goForeground(playback, request.seconds)

        // The notification counts down with the recording, at most a few times a second.
        var lastShown = 0L
        val progress: (Float, Float) -> Unit = { level, fraction ->
            request.progress(level, fraction)
            val now = SystemClock.elapsedRealtime()
            if (now - lastShown > 400 || fraction >= 1f) {
                lastShown = now
                showProgress(playback, request.seconds, fraction)
            }
        }
        val recorder = Recorder(request.seconds, progress)
        Companion.recorder = recorder

        if (!playback) {
            Thread {
                val outcome = runCatching { recorder.recordMicrophone() }
                Companion.recorder = null
                request.done(outcome)
                finish()
            }.start()
            return START_NOT_STICKY
        }

        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection: MediaProjection? = runCatching { manager.getMediaProjection(request.resultCode, request.data!!) }.getOrNull()
        if (projection == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Companion.recorder = null
            request.done(Result.failure(IllegalStateException("Android did not hand over what the phone is playing.")))
            finish()
            return START_NOT_STICKY
        }
        // Android 14 wants to be told who to tell when the projection ends, before anything is captured.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                recorder.stop()
            }
        }, Handler(Looper.getMainLooper()))

        Thread {
            val outcome = runCatching { recorder.recordPlayback(projection) }
            runCatching { projection.stop() }
            Companion.recorder = null
            request.done(outcome)
            finish()
        }.start()
        return START_NOT_STICKY
    }

    private fun notification(playback: Boolean, seconds: Int, fraction: Float): Notification {
        val left = ceil(seconds * (1 - fraction)).toInt().coerceAtLeast(0)
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this))
        // Android 12 and later hold a foreground service's notification back for ten seconds unless told
        // otherwise, which is about as long as the whole countdown.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return builder
            .setContentTitle(if (playback) "Listening to what's playing" else "Listening to the room")
            .setContentText(if (fraction >= 1f) "Asking who knows the song…" else "${left}s left")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setProgress(100, (fraction * 100).toInt(), false)
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    private fun goForeground(playback: Boolean, seconds: Int) {
        val notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "Listening", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while Song Find listens, counting down."
                },
            )
        }
        val notification = notification(playback, seconds, 0f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = if (playback) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            startForeground(NOTIFICATION, notification, type)
        } else {
            startForeground(NOTIFICATION, notification)
        }
    }

    private fun showProgress(playback: Boolean, seconds: Int, fraction: Float) {
        runCatching {
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(playback, seconds, fraction))
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
        /** The media projection's grant; null for the microphone. */
        val data: Intent?,
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

        /** What the phone plays, with the grant Android's question gave. */
        fun startPlayback(
            context: Context,
            resultCode: Int,
            data: Intent,
            seconds: Int,
            progress: (Float, Float) -> Unit,
            done: (Result<ByteArray>) -> Unit,
        ) = start(context, Request(resultCode, data, seconds, progress, done))

        /** The microphone. */
        fun startMicrophone(
            context: Context,
            seconds: Int,
            progress: (Float, Float) -> Unit,
            done: (Result<ByteArray>) -> Unit,
        ) = start(context, Request(0, null, seconds, progress, done))

        private fun start(context: Context, request: Request) {
            pending = request
            val intent = Intent(context, CaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop() {
            recorder?.stop()
        }
    }
}
