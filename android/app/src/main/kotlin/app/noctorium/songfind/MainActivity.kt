package app.noctorium.songfind

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The window Flutter draws in, and the one channel Dart talks to Android through, `noctorium/song-find`:
 *
 * - `record` {source: "mic" | "system", seconds} -> 16 kHz mono 16-bit PCM, little-endian, as bytes. While
 *   it records, `progress` {level, fraction} is called back on the same channel.
 * - `stop` ends a recording early; what was heard so far is returned.
 * - `updatesFolder` -> where an update is downloaded to, the one folder the installer can be shown.
 * - `install` {path} hands a downloaded APK to Android's own installer.
 * - `systemAudioSupported` -> whether this Android can record what it plays (10 and later).
 * - `notify` {title, body, cover?} says how a search went, in a notification that opens Song Find.
 */
class MainActivity : FlutterActivity() {

    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())

    private var pendingRecord: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noctorium/song-find")
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "record" -> {
                if (pendingResult != null) {
                    result.error("busy", "Already listening.", null)
                    return
                }
                val system = call.argument<String>("source") == "system"
                val seconds = (call.argument<Int>("seconds") ?: 10).coerceIn(3, 20)
                pendingResult = result
                withMicrophone {
                    if (system) askToCapture(seconds) else recordMicrophone(seconds)
                }
            }
            "stop" -> {
                CaptureService.stop()
                result.success(null)
            }
            "updatesFolder" -> result.success(File(filesDir, "updates").apply { mkdirs() }.absolutePath)
            "install" -> result.success(install(call.argument<String>("path") ?: ""))
            "systemAudioSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            "notify" -> {
                notifyFound(call.argument<String>("title") ?: "", call.argument<String>("body") ?: "", call.argument<String>("cover"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------------------------- listening

    /**
     * Asks for the microphone first if it has not been allowed: both kinds of listening need it. Android 13
     * and later also want notifications allowed, for the countdown and for "found it" -- asked once, with
     * the microphone, and listening goes ahead whatever the answer to that.
     */
    private fun withMicrophone(then: () -> Unit) {
        val wanted = mutableListOf<String>()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            wanted += Manifest.permission.RECORD_AUDIO
        }
        val prefs = getSharedPreferences("android", MODE_PRIVATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            !prefs.getBoolean("asked_notifications", false)
        ) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
            prefs.edit().putBoolean("asked_notifications", true).apply()
        }
        if (wanted.isEmpty()) {
            then()
            return
        }
        pendingRecord = then
        requestPermissions(wanted.toTypedArray(), REQUEST_MICROPHONE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_MICROPHONE) return
        val then = pendingRecord
        pendingRecord = null
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED && then != null) {
            then()
        } else {
            fail("microphone", "Song Find may not use the microphone. Allow it in the phone's settings for this app, then try again.")
        }
    }

    /** In the foreground service, so the microphone is still heard once another app is in front. */
    private fun recordMicrophone(seconds: Int) {
        CaptureService.startMicrophone(this, seconds, ::progress) { outcome ->
            main.post {
                outcome.fold(::succeed) { fail("record", it.message ?: "The microphone could not be recorded.") }
            }
        }
    }

    private fun askToCapture(seconds: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            fail("unsupported", "Listening to what the phone plays needs Android 10 or later. Use the microphone instead.")
            return
        }
        pendingSeconds = seconds
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        // The whole phone's sound rather than one app's: Android 14 and later otherwise open the question on
        // "a single app", which would then have to be picked by hand.
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_CAPTURE)
    }

    private var pendingSeconds = 10

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            fail("declined", "Android was not allowed to share what the phone is playing, so nothing was heard.")
            return
        }
        CaptureService.startPlayback(this, resultCode, data, pendingSeconds, ::progress) { outcome ->
            main.post {
                outcome.fold(::succeed) { fail("record", it.message ?: "What the phone is playing could not be recorded.") }
            }
        }
    }

    private fun progress(level: Float, fraction: Float) {
        main.post { channel.invokeMethod("progress", mapOf("level" to level.toDouble(), "fraction" to fraction.toDouble())) }
    }

    private fun succeed(pcm: ByteArray) {
        pendingResult?.success(pcm)
        pendingResult = null
    }

    private fun fail(code: String, message: String) {
        pendingResult?.error(code, message, null)
        pendingResult = null
    }

    // ------------------------------------------------------------------------------------- found it

    /** How a search went, with the cover where there is one; tapping it brings Song Find back. */
    private fun notifyFound(title: String, body: String, cover: String?) {
        Thread {
            val picture = cover?.takeIf { it.startsWith("https://") }?.let(::fetchPicture)
            main.post {
                val notifications = getSystemService(NotificationManager::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    notifications.createNotificationChannel(
                        NotificationChannel(FOUND_CHANNEL, "Song found", NotificationManager.IMPORTANCE_HIGH).apply {
                            description = "When a search ends while Song Find is not on screen."
                        },
                    )
                }
                val open = PendingIntent.getActivity(
                    this,
                    1,
                    Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                val builder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, FOUND_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this))
                    .setContentTitle(title)
                    .setContentText(body)
                    .setSmallIcon(android.R.drawable.ic_media_play)
                    .setContentIntent(open)
                    .setAutoCancel(true)
                if (picture != null) builder.setLargeIcon(picture)
                runCatching { notifications.notify(FOUND_NOTIFICATION, builder.build()) }
            }
        }.start()
    }

    private fun fetchPicture(url: String): Bitmap? = runCatching {
        val connection = java.net.URL(url).openConnection().apply {
            connectTimeout = 5000
            readTimeout = 5000
        }
        connection.getInputStream().use { BitmapFactory.decodeStream(it) }
    }.getOrNull()

    // ------------------------------------------------------------------------------------------ updates

    /**
     * Hands the APK to Android's installer, which shows its own screen and asks. The first time, Android
     * also sends the listener to allow this app to install others; null when the installer opened.
     */
    private fun install(path: String): String? {
        val file = File(path)
        val folder = File(filesDir, "updates").canonicalPath
        if (!file.isFile || !file.canonicalPath.startsWith(folder)) return "The update is not where it was downloaded to."
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "Allow Song Find to install updates, then tap Install again."
        }
        return runCatching {
            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            null
        }.getOrElse { "The installer could not be opened: ${it.message}" }
    }

    companion object {
        private const val REQUEST_MICROPHONE = 4101
        private const val REQUEST_CAPTURE = 4102
        private const val FOUND_CHANNEL = "found"
        private const val FOUND_NOTIFICATION = 28
    }
}
