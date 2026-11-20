package fm.segue.segue

import android.app.Activity
import android.app.SearchManager
import android.media.projection.MediaProjectionManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

// audio_service needs its own activity so playback survives the UI closing.
class MainActivity : AudioServiceActivity() {
    // "Ok Google, play … on Segue": the query waits here until Dart asks
    // for it (a cold start), or goes straight over (the app was open).
    private var voice: MethodChannel? = null
    private var pendingVoice: String? = null

    private fun voiceQuery(intent: Intent?): String? =
        if (intent?.action == MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH) {
            intent.getStringExtra(SearchManager.QUERY) ?: ""
        } else {
            null
        }

    // "Что играет?" → "На телефоне": waits for the system's consent dialog.
    private var pendingListen: MethodChannel.Result? = null
    private val listenRequest = 0x5E6

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != listenRequest) return
        val result = pendingListen ?: return
        pendingListen = null
        if (resultCode != Activity.RESULT_OK || data == null ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
        ) {
            result.success("permission")
            return
        }
        SystemAudioService.onStarted = { error -> result.success(error) }
        try {
            SystemAudioService.start(this, resultCode, data)
        } catch (e: Exception) {
            SystemAudioService.onStarted = null
            result.success(e.message ?: "start failed")
        }
    }

    private fun listenChannels(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, "fm.segue/sysaudio/pcm")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        SystemAudioService.sink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        SystemAudioService.sink = null
                    }
                },
            )
        MethodChannel(engine.dartExecutor.binaryMessenger, "fm.segue/sysaudio")
            .setMethodCallHandler { call, result ->
                val q = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                when (call.method) {
                    "supported" -> result.success(q)
                    "start" -> {
                        if (!q) return@setMethodCallHandler result.success("unsupported")
                        pendingListen?.success("cancelled")
                        pendingListen = result
                        val manager = getSystemService(MediaProjectionManager::class.java)
                        @Suppress("DEPRECATION")
                        startActivityForResult(manager.createScreenCaptureIntent(), listenRequest)
                    }
                    "stop" -> {
                        pendingListen?.success("cancelled")
                        pendingListen = null
                        if (q) SystemAudioService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) pendingVoice = voiceQuery(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val q = voiceQuery(intent) ?: return
        val ch = voice
        if (ch != null) ch.invokeMethod("play", q) else pendingVoice = q
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        listenChannels(flutterEngine)
        voice = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fm.segue/voice")
            .apply {
                setMethodCallHandler { call, result ->
                    if (call.method == "take") {
                        result.success(pendingVoice)
                        pendingVoice = null
                    } else {
                        result.notImplemented()
                    }
                }
            }
        // In-app update: hands a downloaded APK to the system installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fm.segue/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        // "Install unknown apps" for Segue, once.
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success("permission")
                        return@setMethodCallHandler
                    }
                    val file = File(call.argument<String>("path")!!)
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK,
                            ),
                    )
                    result.success("ok")
                } catch (e: Exception) {
                    result.error("install", e.message, null)
                }
            }
    }
}
