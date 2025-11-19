package com.example.raspisanie.data

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * BroadcastReceiver для отслеживания завершения загрузки APK и автоматической установки
 */
class DownloadCompleteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            if (intent == null || intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
                return
            }
            
            val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            
            if (downloadId == -1L) {
                Log.w(TAG, "Получен broadcast без downloadId")
                return
            }
            
            Log.d(TAG, "Загрузка завершена: $downloadId")
            
            // Получить информацию о загруженном файле
            val downloadManager = try {
                context.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при получении DownloadManager", e)
                return
            }
            
            if (downloadManager == null) {
                Log.e(TAG, "DownloadManager недоступен")
                return
            }
            
            val query = DownloadManager.Query().setFilterById(downloadId)
            val cursor: Cursor? = try {
                downloadManager.query(query)
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при запросе информации о загрузке", e)
                return
            }
            
            if (cursor == null) {
                Log.e(TAG, "Не удалось получить информацию о загрузке")
                return
            }
            
            try {
                if (!cursor.moveToFirst()) {
                    Log.w(TAG, "Курсор пуст для downloadId: $downloadId")
                    cursor.close()
                    return
                }
                
                val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                val titleIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TITLE)
                
                if (statusIndex == -1 || titleIndex == -1) {
                    Log.e(TAG, "Не найдены необходимые колонки в курсоре")
                    cursor.close()
                    return
                }
                
                val status = cursor.getInt(statusIndex)
                val title = cursor.getString(titleIndex) ?: ""
                
                if (status == DownloadManager.STATUS_SUCCESSFUL && title == "Обновление приложения") {
                    // Получить URI загруженного файла
                    var fileUri: Uri? = null
                    var apkFile: File? = null
                    
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            // Android 10+: использовать URI из DownloadManager
                            fileUri = try {
                                downloadManager.getUriForDownloadedFile(downloadId)
                            } catch (e: Exception) {
                                Log.w(TAG, "Ошибка при получении URI из DownloadManager", e)
                                null
                            }
                            // Попробовать получить файл из URI
                            if (fileUri != null) {
                                val filePath = getFilePathFromUri(context, fileUri)
                                if (filePath != null) {
                                    apkFile = File(filePath)
                                }
                            }
                        } else {
                            // Старые версии Android: получить путь из COLUMN_LOCAL_URI
                            val localUriIndex = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
                            if (localUriIndex != -1) {
                                val localUri = cursor.getString(localUriIndex)
                                if (!localUri.isNullOrBlank()) {
                                    try {
                                        val parsedUri = Uri.parse(localUri)
                                        val path = parsedUri.path
                                        if (!path.isNullOrBlank()) {
                                            val file = File(path)
                                            if (file.exists() && file.isFile) {
                                                apkFile = file
                                                fileUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                                    try {
                                                        FileProvider.getUriForFile(
                                                            context,
                                                            "${context.packageName}.fileprovider",
                                                            file
                                                        )
                                                    } catch (e: Exception) {
                                                        Log.w(TAG, "Ошибка при создании FileProvider URI", e)
                                                        Uri.fromFile(file)
                                                    }
                                                } else {
                                                    Uri.fromFile(file)
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        Log.w(TAG, "Ошибка при парсинге localUri: $localUri", e)
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при получении URI файла", e)
                    }
                    
                    // Fallback: попробовать найти файл по стандартному пути
                    if (apkFile == null || !apkFile.exists()) {
                        try {
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            if (downloadsDir.exists() && downloadsDir.canRead()) {
                                val fallbackFile = File(downloadsDir, "raspisanie_update.apk")
                                if (fallbackFile.exists() && fallbackFile.isFile && fallbackFile.canRead()) {
                                    apkFile = fallbackFile
                                    fileUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        try {
                                            FileProvider.getUriForFile(
                                                context,
                                                "${context.packageName}.fileprovider",
                                                fallbackFile
                                            )
                                        } catch (e: Exception) {
                                            Log.w(TAG, "Ошибка при создании FileProvider URI для fallback", e)
                                            Uri.fromFile(fallbackFile)
                                        }
                                    } else {
                                        Uri.fromFile(fallbackFile)
                                    }
                                }
                            }
                            
                            // Также проверить app-specific directory
                            if ((apkFile == null || !apkFile.exists()) && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                val appDownloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                                if (appDownloadsDir != null && appDownloadsDir.exists()) {
                                    val appFile = File(appDownloadsDir, "raspisanie_update.apk")
                                    if (appFile.exists() && appFile.isFile && appFile.canRead()) {
                                        apkFile = appFile
                                        fileUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                            try {
                                                FileProvider.getUriForFile(
                                                    context,
                                                    "${context.packageName}.fileprovider",
                                                    appFile
                                                )
                                            } catch (e: Exception) {
                                                Log.w(TAG, "Ошибка при создании FileProvider URI для app file", e)
                                                Uri.fromFile(appFile)
                                            }
                                        } else {
                                            Uri.fromFile(appFile)
                                        }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Ошибка при поиске файла в fallback директориях", e)
                        }
                    }
                    
                    // Для Android 10+ можно использовать content URI напрямую
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && fileUri != null) {
                        // Остановить Service отслеживания прогресса
                        try {
                            val serviceIntent = Intent(context, DownloadProgressService::class.java)
                            context.stopService(serviceIntent)
                        } catch (e: Exception) {
                            Log.w(TAG, "Ошибка при остановке DownloadProgressService", e)
                        }
                        
                        // Извлечь версию из описания или использовать дефолтную
                        val descriptionIndex = cursor.getColumnIndex(DownloadManager.COLUMN_DESCRIPTION)
                        val versionName = if (descriptionIndex != -1) {
                            val description = cursor.getString(descriptionIndex)
                            description?.substringAfter("версии ")?.takeIf { it.isNotBlank() } 
                                ?: "новой версии"
                        } else {
                            "новой версии"
                        }
                        
                        // Попробовать получить файл из URI для уведомления
                        val tempFile = if (apkFile != null && apkFile.exists()) {
                            apkFile
                        } else {
                            // Создать временный файл для уведомления (не обязательно)
                            null
                        }
                        
                        // Показать уведомление о завершении скачивания с content URI
                        try {
                            showDownloadCompleteNotificationWithUri(context, versionName, fileUri)
                        } catch (e: Exception) {
                            Log.e(TAG, "Ошибка при показе уведомления о завершении", e)
                        }
                        
                        Log.d(TAG, "Начинаю установку APK через content URI: $fileUri")
                        installApkFromUri(context, fileUri, versionName)
                    } else if (fileUri != null && apkFile != null && apkFile.exists() && apkFile.isFile && apkFile.canRead()) {
                        // Для старых версий Android используем File напрямую
                        // Остановить Service отслеживания прогресса
                        try {
                            val serviceIntent = Intent(context, DownloadProgressService::class.java)
                            context.stopService(serviceIntent)
                        } catch (e: Exception) {
                            Log.w(TAG, "Ошибка при остановке DownloadProgressService", e)
                        }
                        
                        // Извлечь версию из описания или использовать дефолтную
                        val descriptionIndex = cursor.getColumnIndex(DownloadManager.COLUMN_DESCRIPTION)
                        val versionName = if (descriptionIndex != -1) {
                            val description = cursor.getString(descriptionIndex)
                            description?.substringAfter("версии ")?.takeIf { it.isNotBlank() } 
                                ?: "новой версии"
                        } else {
                            "новой версии"
                        }
                        
                        // Показать уведомление о завершении скачивания
                        try {
                            AppUpdateManager.showDownloadCompleteNotification(context, versionName, apkFile)
                        } catch (e: Exception) {
                            Log.e(TAG, "Ошибка при показе уведомления о завершении", e)
                        }
                        
                        Log.d(TAG, "Начинаю установку APK: $fileUri")
                        installApk(context, fileUri)
                    } else {
                        Log.e(TAG, "Не удалось получить валидный файл. fileUri=$fileUri, apkFile=$apkFile, exists=${apkFile?.exists()}, isFile=${apkFile?.isFile}, canRead=${apkFile?.canRead()}")
                        AppUpdateManager.showDownloadErrorNotification(
                            context, 
                            "Не удалось найти загруженный файл"
                        )
                    }
                } else if (status == DownloadManager.STATUS_FAILED && title == "Обновление приложения") {
                    // Остановить Service отслеживания прогресса
                    try {
                        val serviceIntent = Intent(context, DownloadProgressService::class.java)
                        context.stopService(serviceIntent)
                    } catch (e: Exception) {
                        Log.w(TAG, "Ошибка при остановке DownloadProgressService", e)
                    }
                    
                    val reasonIndex = cursor.getColumnIndex(DownloadManager.COLUMN_REASON)
                    val reason = if (reasonIndex != -1) {
                        cursor.getInt(reasonIndex)
                    } else {
                        -1
                    }
                    
                    val errorMessage = when (reason) {
                        DownloadManager.ERROR_CANNOT_RESUME -> "Ошибка возобновления загрузки"
                        DownloadManager.ERROR_DEVICE_NOT_FOUND -> "Устройство хранения не найдено"
                        DownloadManager.ERROR_FILE_ALREADY_EXISTS -> "Файл уже существует"
                        DownloadManager.ERROR_FILE_ERROR -> "Ошибка файловой системы"
                        DownloadManager.ERROR_HTTP_DATA_ERROR -> "Ошибка HTTP"
                        DownloadManager.ERROR_INSUFFICIENT_SPACE -> "Недостаточно места на диске"
                        DownloadManager.ERROR_TOO_MANY_REDIRECTS -> "Слишком много перенаправлений"
                        DownloadManager.ERROR_UNHANDLED_HTTP_CODE -> "Неизвестный HTTP код"
                        else -> "Ошибка загрузки (код: $reason)"
                    }
                    Log.e(TAG, "Загрузка не удалась: $errorMessage")
                    try {
                        AppUpdateManager.showDownloadErrorNotification(context, errorMessage)
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при показе уведомления об ошибке", e)
                    }
                } else {
                    Log.d(TAG, "Загрузка завершена, но это не наше обновление. Status: $status, Title: $title")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при обработке завершенной загрузки", e)
            } finally {
                try {
                    cursor.close()
                } catch (e: Exception) {
                    Log.w(TAG, "Ошибка при закрытии курсора", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка в DownloadCompleteReceiver", e)
        }
    }
    
    private fun installApk(context: Context, apkUri: Uri?) {
        try {
            if (apkUri == null) {
                Log.e(TAG, "URI равен null")
                AppUpdateManager.showDownloadErrorNotification(context, "URI файла не указан")
                return
            }
            
            // Использовать метод из AppUpdateManager для установки
            val filePath = getFilePathFromUri(context, apkUri)
            if (filePath != null && filePath.isNotBlank()) {
                val apkFile = File(filePath)
                AppUpdateManager.installApk(context, apkFile)
            } else {
                Log.e(TAG, "Не удалось получить путь к APK файлу из URI: $apkUri")
                AppUpdateManager.showDownloadErrorNotification(context, "Не удалось получить путь к файлу")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при установке APK", e)
            try {
                AppUpdateManager.showDownloadErrorNotification(context, "Ошибка при установке: ${e.message ?: "Неизвестная ошибка"}")
            } catch (e2: Exception) {
                Log.e(TAG, "Критическая ошибка при показе уведомления об ошибке", e2)
            }
        }
    }
    
    private fun installApkFromUri(context: Context, apkUri: Uri, versionName: String) {
        try {
            // Для Android 10+ используем content URI напрямую
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!context.packageManager.canRequestPackageInstalls()) {
                    Log.w(TAG, "Нет разрешения на установку неизвестных источников")
                    AppUpdateManager.showDownloadErrorNotification(context, "Разрешите установку из неизвестных источников в настройках")
                    return
                }
            }
            
            val intent = Intent(Intent.ACTION_VIEW).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                setDataAndType(apkUri, "application/vnd.android.package-archive")
            }
            
            // Предоставить временные разрешения на чтение URI
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val resInfoList = context.packageManager.queryIntentActivities(
                        intent, 
                        android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
                    )
                    
                    if (resInfoList.isEmpty()) {
                        Log.e(TAG, "Не найдено приложений для установки APK")
                        AppUpdateManager.showDownloadErrorNotification(context, "Не найдено приложение для установки. Включите установку из неизвестных источников в настройках.")
                        return
                    }
                    
                    for (resolveInfo in resInfoList) {
                        try {
                            val packageName = resolveInfo.activityInfo.packageName
                            if (!packageName.isNullOrBlank()) {
                                context.grantUriPermission(
                                    packageName,
                                    apkUri,
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                                )
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Ошибка при предоставлении разрешения для пакета", e)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Ошибка при предоставлении URI разрешений", e)
                }
            }
            
            // Запустить установку
            try {
                context.startActivity(intent)
                Log.d(TAG, "✅ Запущена установка APK из content URI: $apkUri")
            } catch (e: android.content.ActivityNotFoundException) {
                Log.e(TAG, "Не найдено приложение для установки APK", e)
                AppUpdateManager.showDownloadErrorNotification(context, "Не найдено приложение для установки. Включите установку из неизвестных источников в настройках.")
            } catch (e: SecurityException) {
                Log.e(TAG, "Ошибка безопасности при установке APK", e)
                AppUpdateManager.showDownloadErrorNotification(context, "Ошибка безопасности. Проверьте разрешения в настройках.")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при запуске установки APK", e)
                AppUpdateManager.showDownloadErrorNotification(context, "Ошибка при установке: ${e.message ?: "Неизвестная ошибка"}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при установке APK из URI", e)
            AppUpdateManager.showDownloadErrorNotification(context, "Критическая ошибка при установке: ${e.message ?: "Неизвестная ошибка"}")
        }
    }
    
    private fun saveApkUriForCleanup(context: Context, apkUri: Uri) {
        val prefs = context.getSharedPreferences("schedule_prefs", Context.MODE_PRIVATE)
        val apkPath = getFilePathFromUri(context, apkUri)
        if (apkPath != null) {
            prefs.edit().putString("pending_apk_cleanup", apkPath).apply()
            Log.d(TAG, "Сохранён путь для очистки: $apkPath")
        }
    }
    
    private fun getFilePathFromUri(context: Context, uri: Uri?): String? {
        if (uri == null) {
            return null
        }
        
        return try {
            when (uri.scheme) {
                "file" -> {
                    val path = uri.path
                    if (!path.isNullOrBlank()) {
                        val file = File(path)
                        if (file.exists() && file.isFile) {
                            path
                        } else {
                            null
                        }
                    } else {
                        null
                    }
                }
                "content" -> {
                    // Для content URI нужно получить реальный путь
                    var result: String? = null
                    try {
                        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                                if (index != -1) {
                                    val fileName = cursor.getString(index)
                                    if (!fileName.isNullOrBlank()) {
                                        // Попробовать найти файл в известных местах
                                        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                                        if (downloadsDir.exists() && downloadsDir.canRead()) {
                                            val file = File(downloadsDir, fileName)
                                            if (file.exists() && file.isFile && file.canRead()) {
                                                result = file.absolutePath
                                            }
                                        }
                                        
                                        // Попробовать app-specific directory
                                        if (result == null) {
                                            val appDownloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                                            if (appDownloadsDir != null && appDownloadsDir.exists()) {
                                                val appFile = File(appDownloadsDir, fileName)
                                                if (appFile.exists() && appFile.isFile && appFile.canRead()) {
                                                    result = appFile.absolutePath
                                                }
                                            }
                                        }
                                        
                                        // Попробовать стандартное имя файла
                                        if (result == null && fileName == "raspisanie_update.apk") {
                                            val standardLocations = listOf(
                                                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                                                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                                                context.getExternalFilesDir(null)?.let { File(it, "downloads") }
                                            )
                                            
                                            for (dir in standardLocations) {
                                                if (dir != null && dir.exists() && dir.canRead()) {
                                                    val file = File(dir, fileName)
                                                    if (file.exists() && file.isFile && file.canRead()) {
                                                        result = file.absolutePath
                                                        break
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Ошибка при запросе content resolver", e)
                    }
                    result
                }
                else -> {
                    Log.w(TAG, "Неподдерживаемый scheme URI: ${uri.scheme}")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении пути файла из URI: $uri", e)
            null
        }
    }
    
    private fun deleteApkFile(context: Context, apkUri: Uri) {
        try {
            val filePath = getFilePathFromUri(context, apkUri)
            if (filePath != null) {
                val file = File(filePath)
                if (file.exists() && file.delete()) {
                    Log.d(TAG, "APK файл удалён: $filePath")
                } else {
                    Log.w(TAG, "Не удалось удалить APK файл: $filePath")
                }
            }
            
            // Также попробовать удалить через стандартные пути
            val fileName = "raspisanie_update.apk"
            val locations = listOf(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                context.getExternalFilesDir(null)?.let { File(it, "downloads") }
            )
            
            locations.forEach { dir ->
                dir?.let {
                    val file = File(it, fileName)
                    if (file.exists() && file.delete()) {
                        Log.d(TAG, "APK файл удалён: ${file.absolutePath}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при удалении APK файла", e)
        }
    }
    
    private fun showDownloadCompleteNotificationWithUri(context: Context, versionName: String, apkUri: Uri) {
        try {
            val notificationManager = try {
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при получении NotificationManager", e)
                return
            }
            
            if (notificationManager == null) {
                Log.w(TAG, "NotificationManager недоступен")
                return
            }
            
            AppUpdateManager.createNotificationChannel(context)
            
            val installIntent = try {
                Intent(Intent.ACTION_VIEW).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании Intent для установки", e)
                return
            }
            
            val installPendingIntent = try {
                android.app.PendingIntent.getActivity(
                    context,
                    2,
                    installIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании PendingIntent для установки", e)
                return
            }
            
            val notification = try {
                androidx.core.app.NotificationCompat.Builder(context, "app_updates")
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("✅ Скачивание завершено")
                    .setContentText("Версия $versionName готова к установке")
                    .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                    .setContentIntent(installPendingIntent)
                    .addAction(0, "Установить", installPendingIntent)
                    .setAutoCancel(true)
                    .setDefaults(android.app.Notification.DEFAULT_ALL)
                    .build()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании уведомления", e)
                return
            }
            
            try {
                notificationManager.notify(1003, notification)
                Log.d(TAG, "✅ Показано уведомление о завершении скачивания: $versionName")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при показе уведомления", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при показе уведомления о завершении скачивания", e)
        }
    }
    
    companion object {
        private const val TAG = "DownloadCompleteReceiver"
    }
}

