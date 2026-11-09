package app.noctorium.songfind

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
 */
class MainActivity : FlutterActivity() {

    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())

    private var pendingRecord: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null
    private var recorder: Recorder? = null

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
                recorder?.stop()
                CaptureService.stop()
                result.success(null)
            }
            "updatesFolder" -> result.success(File(filesDir, "updates").apply { mkdirs() }.absolutePath)
            "install" -> result.success(install(call.argument<String>("path") ?: ""))
            "systemAudioSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------------------------- listening

    /** Asks for the microphone first if it has not been allowed: both kinds of listening need it. */
    private fun withMicrophone(then: () -> Unit) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            then()
            return
        }
        pendingRecord = then
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_MICROPHONE) return
        val then = pendingRecord
        pendingRecord = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && then != null) {
            then()
        } else {
            fail("microphone", "Song Find may not use the microphone. Allow it in the phone's settings for this app, then try again.")
        }
    }

    private fun recordMicrophone(seconds: Int) {
        val recorder = Recorder(seconds, ::progress)
        this.recorder = recorder
        Thread {
            val outcome = runCatching { recorder.recordMicrophone() }
            main.post {
                this.recorder = null
                outcome.fold(::succeed) { fail("record", it.message ?: "The microphone could not be recorded.") }
            }
        }.start()
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
        CaptureService.start(this, resultCode, data, pendingSeconds, ::progress) { outcome ->
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
    }
}
