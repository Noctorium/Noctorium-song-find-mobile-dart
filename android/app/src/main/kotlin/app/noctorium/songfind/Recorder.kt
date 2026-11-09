package app.noctorium.songfind

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.os.Build
import androidx.annotation.RequiresApi
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * A few seconds of sound at 16 kHz in one channel, 16-bit: what the providers want, recorded at that rate
 * so nothing has to be resampled. From the microphone, or from what the phone plays.
 */
class Recorder(private val seconds: Int, private val progress: (Float, Float) -> Unit) {

    @Volatile
    private var stopped = false

    fun stop() {
        stopped = true
    }

    @SuppressLint("MissingPermission") // asked for before this is called
    fun recordMicrophone(): ByteArray {
        val size = bufferSize()
        val record = AudioRecord(MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
        return run(record)
    }

    @SuppressLint("MissingPermission")
    @RequiresApi(Build.VERSION_CODES.Q)
    fun recordPlayback(projection: MediaProjection): ByteArray {
        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val record = AudioRecord.Builder()
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(bufferSize())
            .setAudioPlaybackCaptureConfig(config)
            .build()
        return run(record)
    }

    private fun bufferSize() = max(AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT), RATE / 5 * 2)

    private fun run(record: AudioRecord): ByteArray {
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw IllegalStateException("The sound could not be opened. Another app may be using it.")
        }
        val total = RATE * 2 * seconds
        val out = ByteArrayOutputStream(total)
        val chunk = ByteArray(RATE / 10 * 2)
        try {
            record.startRecording()
            while (!stopped && out.size() < total) {
                val read = record.read(chunk, 0, chunk.size)
                if (read < 0) throw IllegalStateException("The sound stopped (error $read).")
                out.write(chunk, 0, read)
                var peak = 0
                var i = 0
                while (i + 1 < read) {
                    val sample = (chunk[i].toInt() and 0xff) or (chunk[i + 1].toInt() shl 8)
                    peak = max(peak, abs(sample.toShort().toInt()))
                    i += 2
                }
                progress(peak / 32768f, min(1f, out.size().toFloat() / total))
            }
        } finally {
            runCatching { record.stop() }
            record.release()
        }
        return out.toByteArray()
    }

    companion object {
        const val RATE = 16_000
    }
}
