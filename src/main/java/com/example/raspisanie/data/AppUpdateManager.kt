package com.example.raspisanie.data

import android.app.DownloadManager
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
     * Скачать и установить обновление
     */
    fun downloadAndInstall(context: Context, downloadUrl: String) {
        try {
            // Использовать DownloadManager для скачивания APK
            val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            
            // Определить путь для сохранения APK
            val fileName = "raspisanie_update.apk"
            val destinationPath = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                // Android 10+: сохранять в app-specific directory через MediaStore или внешнее хранилище
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            } else {
                // Старые версии Android: использовать внешнее хранилище
                File(context.getExternalFilesDir(null), "downloads").apply {
                    if (!exists()) mkdirs()
                    this
                }
            }
            
            val file = File(destinationPath, fileName)
            // Удалить старый файл, если существует
            if (file.exists()) {
                file.delete()
            }
            
            val request = DownloadManager.Request(Uri.parse(downloadUrl))
                .setTitle("Обновление приложения")
                .setDescription("Скачивание новой версии")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setMimeType("application/vnd.android.package-archive")
            
            // Установить путь для сохранения в зависимости от версии Android
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            } else {
                request.setDestinationUri(Uri.fromFile(file))
            }
            
            val downloadId = downloadManager.enqueue(request)
            
            // Сохранить downloadId для отслеживания
            val prefs = PreferencesManager(context)
            prefs.lastUpdateDownloadId = downloadId
            
            android.widget.Toast.makeText(
                context,
                "Начато скачивание обновления. После завершения загрузки будет запущена установка.",
                android.widget.Toast.LENGTH_LONG
            ).show()
            
            Log.d(TAG, "Начато скачивание обновления: $downloadId, путь: ${file.absolutePath}")
            
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при скачивании обновления", e)
            android.widget.Toast.makeText(
                context,
                "Ошибка при скачивании обновления: ${e.message}",
                android.widget.Toast.LENGTH_SHORT
            ).show()
        }
    }
    
    /**
     * Установить APK файл
     */
    fun installApk(context: Context, apkFile: File) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                
                val uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                    // Использовать FileProvider для Android 7.0+
                    FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        apkFile
                    )
                } else {
                    // Для старых версий Android
                    Uri.fromFile(apkFile)
                }
                
                setDataAndType(uri, "application/vnd.android.package-archive")
            }
            
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при установке APK", e)
            android.widget.Toast.makeText(
                context,
                "Ошибка при установке обновления",
                android.widget.Toast.LENGTH_SHORT
            ).show()
        }
    }
    
    /**
     * Показать уведомление об обновлении
     */
    fun showUpdateNotification(context: Context, versionInfo: AppVersionInfo) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            
            if (notificationManager == null) {
                Log.w(TAG, "NotificationManager недоступен")
                return
            }
            
            // Создать канал уведомлений (для Android 8.0+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channelId = "app_updates"
                val channelName = "Обновления приложения"
                val importance = android.app.NotificationManager.IMPORTANCE_HIGH
                val channel = android.app.NotificationChannel(channelId, channelName, importance)
                channel.description = "Уведомления о доступных обновлениях приложения"
                channel.enableVibration(true)
                notificationManager.createNotificationChannel(channel)
            }
            
            // Создать Intent для открытия настроек при нажатии на уведомление
            val intent = Intent(context, com.example.raspisanie.SettingsActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("show_update_section", true)
            }
            
            val pendingIntent = android.app.PendingIntent.getActivity(
                context,
                0,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            
            // Сформировать текст уведомления
            val updateType = if (versionInfo.isCritical) "критическое" else ""
            val title = if (updateType.isNotBlank()) {
                "Доступно $updateType обновление"
            } else {
                "Доступна новая версия"
            }
            val text = "Версия ${versionInfo.versionName} готова к установке"
            
            // Создать уведомление
            val notification = NotificationCompat.Builder(context, "app_updates")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle()
                    .bigText(text + (versionInfo.changelog?.takeIf { it.isNotBlank() }?.let { "\n\n$it" } ?: "")))
                .setPriority(if (versionInfo.isCritical) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build()
            
            notificationManager.notify(1001, notification)
            Log.d(TAG, "Показано уведомление о новой версии: ${versionInfo.versionName}")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при показе уведомления об обновлении", e)
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
        
        // Проверить, прошло ли достаточно времени с последней проверки
        val lastCheck = prefs.lastUpdateCheck
        val now = System.currentTimeMillis()
        val minIntervalMillis = 2 * 60 * 60 * 1000L // 2 часа минимум между проверками при запуске
        
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
    
    private fun showUpdateNotification(versionInfo: AppVersionInfo) {
        try {
            val context = applicationContext
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            
            if (notificationManager == null) {
                Log.w(TAG, "NotificationManager недоступен")
                return
            }
            
            // Создать канал уведомлений (для Android 8.0+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channelId = "app_updates"
                val channelName = "Обновления приложения"
                val importance = android.app.NotificationManager.IMPORTANCE_HIGH
                val channel = android.app.NotificationChannel(channelId, channelName, importance)
                channel.description = "Уведомления о доступных обновлениях приложения"
                channel.enableVibration(true)
                notificationManager.createNotificationChannel(channel)
            }
            
            // Создать Intent для открытия настроек при нажатии на уведомление
            val intent = Intent(context, com.example.raspisanie.SettingsActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("show_update_section", true)
            }
            
            val pendingIntent = android.app.PendingIntent.getActivity(
                context,
                0,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            
            // Сформировать текст уведомления
            val updateType = if (versionInfo.isCritical) "критическое" else ""
            val title = if (updateType.isNotBlank()) {
                "Доступно $updateType обновление"
            } else {
                "Доступна новая версия"
            }
            val text = "Версия ${versionInfo.versionName} готова к установке"
            
            // Создать уведомление
            val notification = NotificationCompat.Builder(context, "app_updates")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle()
                    .bigText(text + (versionInfo.changelog?.takeIf { it.isNotBlank() }?.let { "\n\n$it" } ?: "")))
                .setPriority(if (versionInfo.isCritical) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build()
            
            notificationManager.notify(1001, notification)
            Log.d(TAG, "Показано уведомление о новой версии: ${versionInfo.versionName}")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при показе уведомления об обновлении", e)
        }
    }
    
    companion object {
        private const val TAG = "AppUpdateCheckWorker"
    }
}

