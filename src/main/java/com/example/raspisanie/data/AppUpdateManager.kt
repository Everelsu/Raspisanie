package com.example.raspisanie.data

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.raspisanie.data.AppVersionInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.TimeUnit

object AppUpdateManager {
    private const val TAG = "AppUpdateManager"
    private const val WORK_NAME = "app_update_check"
    private const val UPDATE_CHECK_INTERVAL_HOURS = 12L // Проверка каждые 12 часов
    
    // Флаг для защиты от повторных установок
    @Volatile
    private var isInstalling = false
    
    /**
     * Настроить периодическую проверку обновлений
     */
    fun setupAutoUpdateCheck(context: Context) {
        val prefs = PreferencesManager(context)
        
        if (!prefs.appAutoUpdateEnabled) {
            Log.d(TAG, "Автообновление приложения отключено")
            return
        }
        
        val workManager = WorkManager.getInstance(context)
        
        // Отменить существующую работу
        workManager.cancelUniqueWork(WORK_NAME)
        
        // Создать периодическую задачу проверки обновлений
        val updateCheckRequest = PeriodicWorkRequest.Builder(
            AppUpdateCheckWorker::class.java,
            UPDATE_CHECK_INTERVAL_HOURS,
            TimeUnit.HOURS,
            // Flex interval: 6 hours
            6,
            TimeUnit.HOURS
        ).build()
        
        workManager.enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            updateCheckRequest
        )
        
        Log.d(TAG, "Автоматическая проверка обновлений настроена")
    }
    
    /**
     * Отменить автоматическую проверку обновлений
     */
    fun cancelAutoUpdateCheck(context: Context) {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(WORK_NAME)
        Log.d(TAG, "Автоматическая проверка обновлений отменена")
    }
    
    /**
     * Очистка старых APK файлов обновлений
     */
    fun cleanupOldApkFiles(context: Context) {
        try {
            val fileName = "raspisanie_update.apk"
            
            // Места, где может находиться APK
            val locations = mutableListOf<File?>(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                context.getExternalFilesDir(null)?.let { File(it, "downloads") }
            )
            
            // Также проверить сохранённый путь
            val prefs = PreferencesManager(context)
            val pendingCleanupPath = context.getSharedPreferences("schedule_prefs", Context.MODE_PRIVATE)
                .getString("pending_apk_cleanup", null)
            
            pendingCleanupPath?.let {
                locations.add(File(it).parentFile)
            }
            
            var deletedCount = 0
            locations.forEach { dir ->
                dir?.let {
                    val file = File(it, fileName)
                    if (file.exists()) {
                        try {
                            if (file.delete()) {
                                Log.d(TAG, "Удалён старый APK: ${file.absolutePath}")
                                deletedCount++
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Ошибка при удалении ${file.absolutePath}", e)
                        }
                    }
                }
            }
            
            // Очистить сохранённый путь
            if (pendingCleanupPath != null) {
                context.getSharedPreferences("schedule_prefs", Context.MODE_PRIVATE)
                    .edit()
                    .remove("pending_apk_cleanup")
                    .apply()
            }
            
            // Удалить все файлы с похожим именем (например, raspisanie_update (1).apk)
            locations.forEach { dir ->
                dir?.listFiles()?.forEach { file ->
                    if (file.name.startsWith("raspisanie_update") && file.name.endsWith(".apk", ignoreCase = true)) {
                        try {
                            if (file.delete()) {
                                Log.d(TAG, "Удалён старый APK: ${file.absolutePath}")
                                deletedCount++
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Ошибка при удалении ${file.absolutePath}", e)
                        }
                    }
                }
            }
            
            if (deletedCount > 0) {
                Log.d(TAG, "Очищено $deletedCount старых APK файлов")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при очистке APK файлов", e)
        }
    }
    
    /**
     * Скачать и установить обновление (упрощенная и улучшенная версия)
     */
    fun downloadAndInstall(context: Context, downloadUrl: String?, versionName: String? = null) {
        if (downloadUrl.isNullOrBlank()) {
            Log.e(TAG, "URL скачивания не указан")
            showDownloadErrorNotification(context, "Ссылка для скачивания не указана")
            return
        }
        
        val uri = Uri.parse(downloadUrl)
        if (uri.scheme != "http" && uri.scheme != "https") {
            Log.e(TAG, "Неподдерживаемый протокол: ${uri.scheme}")
            showDownloadErrorNotification(context, "Неподдерживаемый протокол. Используйте http или https.")
            return
        }
        
        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            ?: run {
                Log.e(TAG, "DownloadManager недоступен")
                showDownloadErrorNotification(context, "Системный сервис загрузки недоступен")
                return
            }
        
        val fileName = "raspisanie_update.apk"
        
        // Создать запрос на скачивание
        val request = DownloadManager.Request(uri).apply {
            setTitle("Обновление приложения")
            setDescription("Скачивание версии ${versionName ?: "новой"}")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setMimeType("application/vnd.android.package-archive")
            setAllowedOverMetered(true)
            setAllowedOverRoaming(false)
            
            // Установить путь для сохранения в зависимости от версии Android
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: используем публичную директорию Downloads
                setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            } else {
                // Старые версии: используем внутреннюю директорию приложения
                val downloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                    ?: context.getExternalFilesDir(null)?.let { 
                        val dir = File(it, "downloads")
                        if (!dir.exists()) dir.mkdirs()
                        dir
                    }
                    ?: context.cacheDir.let {
                        val dir = File(it, "downloads")
                        if (!dir.exists()) dir.mkdirs()
                        dir
                    }
                
                if (downloadsDir != null && downloadsDir.exists()) {
                    val file = File(downloadsDir, fileName)
                    setDestinationUri(Uri.fromFile(file))
                }
                // Если путь не установлен, DownloadManager выберет путь сам
            }
        }
        
        // Запустить скачивание
        val downloadId = try {
            downloadManager.enqueue(request)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при запуске скачивания", e)
            showDownloadErrorNotification(context, "Не удалось начать загрузку. Проверьте подключение к интернету.")
            return
        }
        
        if (downloadId <= 0) {
            Log.e(TAG, "Неверный downloadId: $downloadId")
            showDownloadErrorNotification(context, "Ошибка при запуске загрузки")
            return
        }
        
        // Сохранить downloadId для отслеживания
        try {
            PreferencesManager(context).lastUpdateDownloadId = downloadId
        } catch (e: Exception) {
            Log.w(TAG, "Не удалось сохранить downloadId", e)
        }
        
        // Запустить Service для отслеживания прогресса (не критично)
        try {
            val serviceIntent = Intent(context, DownloadProgressService::class.java).apply {
                putExtra(DownloadManager.EXTRA_DOWNLOAD_ID, downloadId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Не удалось запустить сервис отслеживания прогресса", e)
            // Не критично, загрузка продолжится через DownloadManager
        }
        
        Log.d(TAG, "✅ Начато скачивание обновления: $downloadId, версия: $versionName")
    }
    
    /**
     * Установить APK файл (упрощенная и улучшенная версия)
     */
    fun installApk(context: Context, apkFile: File?) {
        if (isInstalling) {
            Log.w(TAG, "Установка уже выполняется")
            return
        }
        
        if (apkFile == null || !apkFile.exists() || !apkFile.isFile) {
            Log.e(TAG, "APK файл не существует или неверный")
            showDownloadErrorNotification(context, "Файл обновления не найден")
            return
        }
        
        if (!apkFile.canRead() || apkFile.length() < 1024) {
            Log.e(TAG, "APK файл поврежден или недоступен: ${apkFile.absolutePath}")
            showDownloadErrorNotification(context, "Файл обновления поврежден")
            return
        }
        
        isInstalling = true
        
        // Проверить разрешение на установку для Android 8.0+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!context.packageManager.canRequestPackageInstalls()) {
                isInstalling = false
                showInstallPermissionNotification(context)
                return
            }
        }
        
        // Получить URI для файла
        val uri = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apkFile)
            } else {
                Uri.fromFile(apkFile)
            }
        } catch (e: Exception) {
            isInstalling = false
            Log.e(TAG, "Ошибка при получении URI для APK", e)
            showDownloadErrorNotification(context, "Не удалось получить доступ к файлу обновления")
            return
        }
        
        // Создать Intent для установки
        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            setDataAndType(uri, "application/vnd.android.package-archive")
        }
        
        // Предоставить разрешения на чтение URI (для Android 7.0+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val resInfoList = context.packageManager.queryIntentActivities(
                    intent,
                    android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
                )
                
                resInfoList.forEach { resolveInfo ->
                    try {
                        context.grantUriPermission(
                            resolveInfo.activityInfo.packageName,
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "Не удалось предоставить разрешение для ${resolveInfo.activityInfo.packageName}", e)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Ошибка при предоставлении разрешений", e)
            }
        }
        
        // Запустить установку
        try {
            context.startActivity(intent)
            Log.d(TAG, "✅ Запущена установка APK: ${apkFile.name}")
            
            // Сбросить флаг через 3 секунды
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                isInstalling = false
            }, 3000)
        } catch (e: ActivityNotFoundException) {
            isInstalling = false
            Log.e(TAG, "Не найдено приложение для установки", e)
            showDownloadErrorNotification(context, "Не найдено приложение для установки. Включите установку из неизвестных источников.")
        } catch (e: SecurityException) {
            isInstalling = false
            Log.e(TAG, "Ошибка безопасности при установке", e)
            showInstallPermissionNotification(context)
        } catch (e: Exception) {
            isInstalling = false
            Log.e(TAG, "Ошибка при установке", e)
            showDownloadErrorNotification(context, "Не удалось запустить установку. Попробуйте установить вручную.")
        }
    }
    
    /**
     * Показать уведомление о необходимости разрешения на установку и открыть настройки
     */
    fun showInstallPermissionNotification(context: Context) {
        try {
            // Сначала попытаемся открыть настройки напрямую
            val intent = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // Android 8.0+: открыть настройки для конкретного приложения
                    Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:${context.packageName}")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                } else {
                    // Для старых версий: открыть общие настройки безопасности
                    Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании Intent для настроек разрешений", e)
                null
            }
            
            // Попытаться открыть настройки напрямую
            if (intent != null) {
                try {
                    context.startActivity(intent)
                    Log.d(TAG, "✅ Открыты настройки разрешений")
                    return // Успешно открыли, уведомление не нужно
                } catch (e: android.content.ActivityNotFoundException) {
                    Log.w(TAG, "Не найдена активность для открытия настроек, показываю уведомление", e)
                } catch (e: Exception) {
                    Log.w(TAG, "Ошибка при открытии настроек, показываю уведомление", e)
                }
            }
            
            // Если не удалось открыть напрямую, показываем уведомление
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
            
            createNotificationChannel(context)
            
            // Fallback Intent для уведомления
            val fallbackIntent = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:${context.packageName}")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                } else {
                    Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании fallback Intent", e)
                return
            }
            
            val pendingIntent = try {
                android.app.PendingIntent.getActivity(
                    context,
                    3,
                    fallbackIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании PendingIntent для разрешений", e)
                return
            }
            
            val notification = try {
                NotificationCompat.Builder(context, "app_updates")
                    .setSmallIcon(android.R.drawable.stat_notify_error)
                    .setContentTitle("⚠️ Требуется разрешение")
                    .setContentText("Нажмите, чтобы разрешить установку из неизвестных источников")
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setContentIntent(pendingIntent)
                    .setAutoCancel(true)
                    .build()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании уведомления о разрешении", e)
                return
            }
            
            try {
                notificationManager.notify(1005, notification)
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при показе уведомления о разрешении", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при показе уведомления о разрешении", e)
        }
    }
    
    /**
     * Создать канал уведомлений (если еще не создан)
     */
    fun createNotificationChannel(context: Context) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val notificationManager = try {
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при получении NotificationManager для создания канала", e)
                    return
                }
                
                if (notificationManager == null) {
                    Log.w(TAG, "NotificationManager недоступен для создания канала")
                    return
                }
                
                val channelId = "app_updates"
                val channelName = "Обновления приложения"
                val importance = android.app.NotificationManager.IMPORTANCE_HIGH
                val channel = android.app.NotificationChannel(channelId, channelName, importance)
                channel.description = "Уведомления о доступных обновлениях приложения"
                channel.enableVibration(true)
                channel.enableLights(true)
                channel.setShowBadge(true)
                
                // Создать отдельный канал для прогресса загрузки без вибрации
                val downloadProgressChannelId = "app_updates_download_progress"
                val downloadProgressChannel = android.app.NotificationChannel(
                    downloadProgressChannelId,
                    "Прогресс загрузки",
                    android.app.NotificationManager.IMPORTANCE_LOW
                )
                downloadProgressChannel.description = "Уведомления о прогрессе загрузки обновлений"
                downloadProgressChannel.enableVibration(false) // Без вибрации
                downloadProgressChannel.enableLights(false)
                downloadProgressChannel.setShowBadge(false)
                
                try {
                    notificationManager.createNotificationChannel(channel)
                    notificationManager.createNotificationChannel(downloadProgressChannel)
                    Log.d(TAG, "Каналы уведомлений созданы: $channelId, $downloadProgressChannelId")
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при создании канала уведомлений", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при создании канала уведомлений", e)
        }
    }
    
    /**
     * Показать уведомление об обновлении
     */
    fun showUpdateNotification(context: Context, versionInfo: AppVersionInfo?) {
        try {
            // Валидация входных данных
            if (versionInfo == null) {
                Log.e(TAG, "versionInfo равен null")
                return
            }
            
            if (versionInfo.downloadUrl.isNullOrBlank()) {
                Log.e(TAG, "URL скачивания пуст в versionInfo")
                return
            }
            
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
            
            // Создать канал уведомлений
            createNotificationChannel(context)
            
            // Создать Intent для открытия приложения при нажатии на уведомление
            val intent = try {
                Intent(context, com.example.raspisanie.MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании Intent для MainActivity", e)
                return
            }
            
            val pendingIntent = try {
                android.app.PendingIntent.getActivity(
                context,
                0,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании PendingIntent", e)
                return
            }
            
            // Создать Intent для кнопки "Скачать"
            val downloadIntent = try {
                Intent(context, AppUpdateActionReceiver::class.java).apply {
                    action = "DOWNLOAD_UPDATE"
                    putExtra("download_url", versionInfo.downloadUrl)
                    putExtra("version_name", versionInfo.versionName)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании Intent для скачивания", e)
                return
            }
            
            val downloadPendingIntent = try {
                android.app.PendingIntent.getBroadcast(
                    context,
                    1,
                    downloadIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании PendingIntent для скачивания", e)
                return
            }
            
            // Сформировать текст уведомления
            val updateType = if (versionInfo.isCritical) "критическое" else ""
            val title = if (updateType.isNotBlank()) {
                "🔔 Доступно $updateType обновление"
            } else {
                "🔔 Доступна новая версия"
            }
            val text = "Версия ${versionInfo.versionName} готова к установке"
            val bigText = text + (versionInfo.changelog?.takeIf { it.isNotBlank() }?.let { "\n\n📝 Изменения:\n$it" } ?: "")
            
            // Создать уведомление с кнопкой действия
            val notification = try {
                NotificationCompat.Builder(context, "app_updates")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle(title)
                .setContentText(text)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
                .setPriority(if (versionInfo.isCritical) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
                .setContentIntent(pendingIntent)
                    .addAction(0, "Скачать", downloadPendingIntent)
                .setAutoCancel(true)
                    .setDefaults(android.app.Notification.DEFAULT_ALL)
                .build()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании уведомления", e)
                return
            }
            
            try {
            notificationManager.notify(1001, notification)
                Log.d(TAG, "✅ Показано уведомление о новой версии: ${versionInfo.versionName}")
        } catch (e: Exception) {
                Log.e(TAG, "Ошибка при показе уведомления", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при показе уведомления об обновлении", e)
        }
    }
    
    /**
     * Показать уведомление о начале скачивания
     */
    fun showDownloadStartedNotification(context: Context, versionName: String) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                ?: return
            
            createNotificationChannel(context)
            
            // Не показываем уведомление здесь - DownloadManager сам покажет системное уведомление
            // А мы будем обновлять его через DownloadProgressReceiver
            Log.d(TAG, "Начато скачивание: $versionName")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при показе уведомления о скачивании", e)
        }
    }
    
    /**
     * Показать уведомление о завершении скачивания
     */
    fun showDownloadCompleteNotification(context: Context, versionName: String, apkFile: File?) {
        try {
            if (apkFile == null || !apkFile.exists() || !apkFile.isFile) {
                Log.e(TAG, "Некорректный APK файл для уведомления о завершении")
                return
            }
            
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
            
            createNotificationChannel(context)
            
            // Intent для установки
            val uri = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        apkFile
                    )
                } else {
                    Uri.fromFile(apkFile)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при получении URI для установки", e)
                return
            }
            
            val installIntent = try {
                Intent(Intent.ACTION_VIEW).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                    setDataAndType(uri, "application/vnd.android.package-archive")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании Intent для установки", e)
                return
            }
            
            // Предоставить разрешения на чтение URI для PackageInstaller (Android 7.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val resInfoList = context.packageManager.queryIntentActivities(
                        installIntent,
                        android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
                    )
                    
                    for (resolveInfo in resInfoList) {
                        try {
                            val packageName = resolveInfo.activityInfo.packageName
                            if (!packageName.isNullOrBlank()) {
                                context.grantUriPermission(
                                    packageName,
                                    uri,
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Ошибка при предоставлении разрешения для пакета в уведомлении", e)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Ошибка при предоставлении URI разрешений для уведомления", e)
                }
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
                NotificationCompat.Builder(context, "app_updates")
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("✅ Скачивание завершено")
                    .setContentText("Версия $versionName готова к установке")
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
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
    
    /**
     * Показать уведомление об ошибке скачивания
     */
    fun showDownloadErrorNotification(context: Context, errorMessage: String?) {
        try {
            val message = errorMessage?.takeIf { it.isNotBlank() } ?: "Произошла неизвестная ошибка"
            
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
            
            createNotificationChannel(context)
            
            val notification = try {
                NotificationCompat.Builder(context, "app_updates")
                    .setSmallIcon(android.R.drawable.stat_notify_error)
                    .setContentTitle("❌ Ошибка скачивания")
                    .setContentText(message)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setAutoCancel(true)
                    .build()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании уведомления об ошибке", e)
                return
            }
            
            try {
                notificationManager.notify(1004, notification)
                Log.d(TAG, "Показано уведомление об ошибке скачивания: $message")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при показе уведомления об ошибке", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при показе уведомления об ошибке", e)
        }
    }
    
    /**
     * Проверить обновления при запуске приложения (фоново, без уведомления при актуальной версии)
     */
    fun checkForUpdatesOnStartup(context: Context, showNotificationOnlyIfUpdateAvailable: Boolean = true) {
        val prefs = PreferencesManager(context)
        
        // Проверить, нужно ли проверять обновления при запуске
        if (!prefs.appAutoUpdateEnabled && !showNotificationOnlyIfUpdateAvailable) {
            return
        }
        
        // Если автообновление включено, проверяем при каждом запуске (или почти при каждом)
        // Минимальный интервал уменьшен до 5 минут, чтобы проверка происходила при почти каждом запуске
        val lastCheck = prefs.lastUpdateCheck
        val now = System.currentTimeMillis()
        val minIntervalMillis = 5 * 60 * 1000L // 5 минут минимум между проверками при запуске (было 2 часа)
        
        if (lastCheck > 0 && (now - lastCheck) < minIntervalMillis) {
            // Если недавно проверяли и есть кэшированный результат - проверить его
            if (prefs.lastUpdateResult.startsWith("update_available:")) {
                Log.d(TAG, "Обновление уже найдено ранее, можно показать уведомление при необходимости")
                // Уведомление уже должно быть показано worker'ом, но если нужно - можно показать снова
            }
            return
        }
        
        // Запустить проверку в фоновом режиме
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val result = AppUpdateChecker.checkForUpdates(context)
                
                when (result) {
                    is AppUpdateChecker.UpdateCheckResult.UpdateAvailable -> {
                        prefs.lastUpdateCheck = now
                        prefs.lastUpdateCheckSuccess = now
                        prefs.lastUpdateResult = "update_available:${result.versionInfo.versionName}"
                        prefs.resetUpdateCheckErrorCount()
                        
                        // Показать уведомление только если найдено обновление
                        showUpdateNotification(context, result.versionInfo)
                        Log.d(TAG, "При запуске найдена новая версия: ${result.versionInfo.versionName}")
                    }
                    AppUpdateChecker.UpdateCheckResult.NoUpdate -> {
                        prefs.lastUpdateCheck = now
                        prefs.lastUpdateCheckSuccess = now
                        prefs.lastUpdateResult = "no_update"
                        prefs.resetUpdateCheckErrorCount()
                        // Не показываем уведомление - версия актуальная
                        Log.d(TAG, "При запуске: версия актуальна")
                    }
                    is AppUpdateChecker.UpdateCheckResult.Error -> {
                        prefs.lastUpdateCheck = now
                        prefs.incrementUpdateCheckErrorCount()
                        prefs.lastUpdateResult = "error:${result.message}"
                        // Не показываем уведомление при ошибке при запуске
                        Log.w(TAG, "Ошибка при проверке обновлений при запуске: ${result.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Исключение при проверке обновлений при запуске", e)
                prefs.incrementUpdateCheckErrorCount()
            }
        }
    }
}

/**
 * Worker для периодической проверки обновлений
 */
class AppUpdateCheckWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            val prefs = PreferencesManager(applicationContext)
            
            // Проверить, включено ли автообновление
            if (!prefs.appAutoUpdateEnabled) {
                Log.d(TAG, "Автообновление отключено, пропускаем проверку")
                return Result.success()
            }
            
            // Умная проверка: нужно ли выполнять проверку сейчас
            if (!shouldCheckForUpdates(applicationContext, prefs)) {
                Log.d(TAG, "Проверка пропущена по умной логике")
                return Result.success()
            }
            
            // Выполнить проверку обновлений (синхронно)
            val result = kotlinx.coroutines.runBlocking {
                AppUpdateChecker.checkForUpdates(applicationContext)
            }
            
            val now = System.currentTimeMillis()
            
            when (result) {
                is AppUpdateChecker.UpdateCheckResult.UpdateAvailable -> {
                    // Показать уведомление о новой версии
                    AppUpdateManager.showUpdateNotification(applicationContext, result.versionInfo)
                    prefs.lastUpdateCheck = now
                    prefs.lastUpdateCheckSuccess = now
                    prefs.lastUpdateResult = "update_available:${result.versionInfo.versionName}"
                    prefs.resetUpdateCheckErrorCount()
                    val versionInfo: AppVersionInfo = result.versionInfo
                    Log.d(TAG, "Найдена новая версия: ${versionInfo.versionName}")
                }
                AppUpdateChecker.UpdateCheckResult.NoUpdate -> {
                    prefs.lastUpdateCheck = now
                    prefs.lastUpdateCheckSuccess = now
                    prefs.lastUpdateResult = "no_update"
                    prefs.resetUpdateCheckErrorCount()
                    Log.d(TAG, "Обновлений не найдено")
                }
                is AppUpdateChecker.UpdateCheckResult.Error -> {
                    prefs.lastUpdateCheck = now
                    prefs.incrementUpdateCheckErrorCount()
                    prefs.lastUpdateResult = "error:${result.message}"
                    Log.e(TAG, "Ошибка при проверке обновлений: ${result.message}")
                }
            }
            
            Result.success()
        } catch (e: Exception) {
            val prefs = PreferencesManager(applicationContext)
            prefs.incrementUpdateCheckErrorCount()
            Log.e(TAG, "Ошибка в AppUpdateCheckWorker", e)
            // Не ретраить сразу, если много ошибок подряд - пропустить
            if (prefs.updateCheckErrorCount >= 5) {
                Log.w(TAG, "Слишком много ошибок подряд (${prefs.updateCheckErrorCount}), пропускаем ретрай")
                return Result.success()
            }
            Result.retry()
        }
    }
    
    /**
     * Умная логика проверки: определяет, нужно ли выполнять проверку сейчас
     */
    private fun shouldCheckForUpdates(context: Context, prefs: PreferencesManager): Boolean {
        val now = System.currentTimeMillis()
        val lastCheck = prefs.lastUpdateCheck
        val lastSuccess = prefs.lastUpdateCheckSuccess
        
        // Если проверка уже выполнялась недавно - пропустить
        val minIntervalMillis = getMinimumCheckInterval(prefs)
        if (lastCheck > 0 && (now - lastCheck) < minIntervalMillis) {
            Log.d(TAG, "Проверка уже выполнялась недавно (${(now - lastCheck) / 1000 / 60} минут назад)")
            return false
        }
        
        // Если было много ошибок - увеличить интервал между проверками
        val errorCount = prefs.updateCheckErrorCount
        if (errorCount >= 3) {
            val backoffInterval = minIntervalMillis * (1 + errorCount / 3) // Экспоненциальный backoff
            if (lastCheck > 0 && (now - lastCheck) < backoffInterval) {
                Log.d(TAG, "Много ошибок ($errorCount), пропускаем проверку (backoff)")
                return false
            }
        }
        
        // Проверить состояние сети
        if (!isNetworkAvailable(context)) {
            Log.d(TAG, "Нет доступной сети, пропускаем проверку")
            return false
        }
        
        // Проверить, не находится ли устройство в режиме энергосбережения
        if (isDeviceInBatterySaverMode(context)) {
            Log.d(TAG, "Устройство в режиме энергосбережения, пропускаем проверку")
            return false
        }
        
        // Если последняя успешная проверка была недавно и показала отсутствие обновлений
        // можно пропустить проверку
        if (lastSuccess > 0 && prefs.lastUpdateResult == "no_update") {
            val timeSinceSuccess = now - lastSuccess
            val cacheValidityMillis = 6 * 60 * 60 * 1000L // 6 часов кэша для "нет обновлений"
            if (timeSinceSuccess < cacheValidityMillis) {
                Log.d(TAG, "Результат 'нет обновлений' еще актуален, пропускаем проверку")
                return false
            }
        }
        
        // Если была найдена критическая версия ранее - проверять чаще
        if (prefs.lastUpdateResult.startsWith("update_available:")) {
            // Если найдено обновление, проверить, не критическое ли оно
            // Для критических обновлений не использовать кэш
            // (логика может быть расширена для принудительной проверки критических обновлений)
        }
        
        return true
    }
    
    /**
     * Получить минимальный интервал между проверками в зависимости от количества ошибок
     */
    private fun getMinimumCheckInterval(prefs: PreferencesManager): Long {
        val errorCount = prefs.updateCheckErrorCount
        val baseInterval = 12 * 60 * 60 * 1000L // 12 часов
        
        return when {
            errorCount >= 5 -> baseInterval * 3 // 36 часов при 5+ ошибках
            errorCount >= 3 -> baseInterval * 2 // 24 часа при 3-4 ошибках
            else -> baseInterval // 12 часов нормально
        }
    }
    
    /**
     * Проверить доступность сети
     */
    private fun isNetworkAvailable(context: Context): Boolean {
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return true // Если менеджер недоступен, разрешить проверку
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = connectivityManager.activeNetwork ?: return false
                val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
                capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            } else {
                // Для старых версий Android (API < 23) используем deprecated API
                // Это необходимо для обратной совместимости
                @Suppress("DEPRECATION")
                val activeNetworkInfo = connectivityManager.activeNetworkInfo
                @Suppress("DEPRECATION")
                return activeNetworkInfo?.isConnected == true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при проверке сети", e)
            true // По умолчанию разрешить проверку
        }
    }
    
    /**
     * Проверить, находится ли устройство в режиме энергосбережения
     */
    private fun isDeviceInBatterySaverMode(context: Context): Boolean {
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                powerManager?.isPowerSaveMode == true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при проверке режима энергосбережения", e)
            false // По умолчанию не блокировать проверку
        }
    }
    
    companion object {
        private const val TAG = "AppUpdateCheckWorker"
    }
}

