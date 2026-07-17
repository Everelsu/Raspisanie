package com.example.raspiflutter

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channel = "com.example.raspiflutter/install_apk"
    private val settingsChannel = "com.example.raspiflutter/system_settings"
    private val iconChannel = "com.example.raspiflutter/app_icon"

    // Тема → alias из AndroidManifest. Включён всегда ровно один.
    private val iconAliases = mapOf(
        "dark" to "IconDark",
        "light" to "IconLight",
        "green" to "IconGreen",
        "pink" to "IconPink",
        "blue" to "IconBlue",
        "gray" to "IconGray",
        "purple" to "IconPurple",
        "orange" to "IconOrange",
        "red" to "IconRed",
        "teal" to "IconTeal",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel).setMethodCallHandler { call, result ->
            if (call.method == "openNotificationSettings") {
                val intent = Intent().apply {
                    action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
                startActivity(intent)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannel).setMethodCallHandler { call, result ->
            if (call.method == "setIcon") {
                val theme = call.arguments as? String
                val alias = iconAliases[theme]
                if (alias == null) {
                    result.error("INVALID_THEME", "Unknown theme: $theme", null)
                    return@setMethodCallHandler
                }
                try {
                    setLauncherIcon(alias)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SET_ICON_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            if (call.method == "install") {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any>
                val path = args?.get("path") as? String
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "path is required", null)
                    return@setMethodCallHandler
                }
                try {
                    installApk(path)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setLauncherIcon(enabledAlias: String) {
        val pm = packageManager
        // В debug-сборках IconDark остаётся включённым всегда: flutter run
        // стартует именно его (первый LAUNCHER в манифесте), а выключенный
        // компонент нельзя вернуть через adb на новых Android — пришлось бы
        // переустанавливать приложение. Цена — вторая иконка на дев-устройстве.
        val isDebuggable =
            (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        fun setState(alias: String, enabled: Boolean) {
            val component = ComponentName(packageName, "$packageName.$alias")
            val state = if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            // DONT_KILL_APP — иначе система убьёт приложение при переключении.
            pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        }
        // Сначала включаем новый alias, потом выключаем остальные: если процесс
        // умрёт посреди цикла, в лаунчере всегда останется хотя бы одна иконка.
        setState(enabledAlias, true)
        for (alias in iconAliases.values) {
            if (alias == enabledAlias) continue
            val keep = isDebuggable && alias == "IconDark"
            setState(alias, keep)
        }
        // Сплэш следующего запуска — в цвет иконки: первый кадр системы
        // совпадает с оверлеем SplashIntro, серой вспышки нет. API 33+.
        if (Build.VERSION.SDK_INT >= 33) {
            // Icon<Theme> → LaunchTheme<Theme>
            val styleName = "LaunchTheme" + enabledAlias.removePrefix("Icon")
            val styleId = resources.getIdentifier(styleName, "style", packageName)
            if (styleId != 0) {
                try {
                    splashScreen.setSplashScreenTheme(styleId)
                } catch (_: Exception) {
                    // Не критично — останется дефолтный тёмный сплэш.
                }
            }
        }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        if (!file.exists()) throw IllegalStateException("APK file not found: $filePath")
        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
        } else {
            Uri.fromFile(file)
        }
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        } else {
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        startActivity(intent)
    }
}
