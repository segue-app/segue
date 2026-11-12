package fm.segue.segue

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// audio_service needs its own activity so playback survives the UI closing.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
