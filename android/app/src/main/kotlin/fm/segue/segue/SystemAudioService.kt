package fm.segue.segue

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.EventChannel

/**
 * "Что играет?" on Android 10+: the sound other apps play (Chrome, games,
 * most players — apps that forbid it stay silent), never Segue's own,
 * as 16 kHz mono 16-bit PCM like the microphone. Android asks every time
 * ("Start recording or casting?") and shows a notification while it runs.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class SystemAudioService : Service() {
    companion object {
        const val RATE = 16000
        private const val CHANNEL = "segue_listen"
        private const val NOTIFICATION = 0x5E6

        /** Where the sound goes (set by Dart listening). */
        var sink: EventChannel.EventSink? = null

        /** Told once whether the sound comes: null, or why not. */
        var onStarted: ((String?) -> Unit)? = null

        private val main = Handler(Looper.getMainLooper())

        fun start(context: Context, code: Int, data: Intent) {
            val intent = Intent(context, SystemAudioService::class.java)
                .putExtra("code", code)
                .putExtra("data", data)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SystemAudioService::class.java))
        }
    }

    private var projection: MediaProjection? = null
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 14 wants the service in the foreground before the
        // projection is taken.
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Что играет?", NotificationManager.IMPORTANCE_LOW),
        )
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.presence_audio_online)
            .setContentTitle("Segue")
            .setContentText("Слушаю звук телефона…")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION, notification)
        }
        val error = try {
            begin(intent)
            null
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
        report(error)
        if (error != null) stopSelf()
        return START_NOT_STICKY
    }

    private fun report(error: String?) {
        val done = onStarted ?: return
        onStarted = null
        main.post { done(error) }
    }

    @SuppressLint("MissingPermission") // Dart asks for RECORD_AUDIO first.
    private fun begin(intent: Intent?) {
        val code = intent?.getIntExtra("code", Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        @Suppress("DEPRECATION")
        val data = intent?.getParcelableExtra<Intent>("data")
            ?: throw IllegalStateException("no consent")
        val manager = getSystemService(MediaProjectionManager::class.java)
        val p = manager.getMediaProjection(code, data)
            ?: throw IllegalStateException("no projection")
        projection = p
        p.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() {
                    stopSelf()
                }
            },
            main,
        )
        val config = AudioPlaybackCaptureConfiguration.Builder(p)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .excludeUid(Process.myUid())
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()
        val min = AudioRecord.getMinBufferSize(
            RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val r = AudioRecord.Builder()
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(min, RATE)) // half a second
            .setAudioPlaybackCaptureConfig(config)
            .build()
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            throw IllegalStateException("recorder not ready")
        }
        record = r
        r.startRecording()
        running = true
        thread = Thread {
            // A tenth of a second at a time.
            val buf = ByteArray(RATE / 10 * 2)
            while (running) {
                val n = r.read(buf, 0, buf.size)
                if (n > 0) {
                    val chunk = buf.copyOf(n)
                    main.post { sink?.success(chunk) }
                } else if (n < 0) {
                    break
                }
            }
        }.apply {
            name = "segue-listen"
            start()
        }
    }

    override fun onDestroy() {
        running = false
        try {
            record?.stop()
        } catch (_: Exception) {
        }
        thread?.join(500)
        record?.release()
        record = null
        projection?.stop()
        projection = null
        report("stopped")
        super.onDestroy()
    }
}
