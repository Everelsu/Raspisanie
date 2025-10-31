package com.example.raspisanie.data

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.util.Log
import androidx.core.content.FileProvider
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.raspisanie.data.AppVersionInfo
import java.io.File
import java.util.concurrent.TimeUnit

object AppUpdateManager {
    private const val TAG = "AppUpdateManager"
    private const val WORK_NAME = "app_update_check"
    private const val UPDATE_CHECK_INTERVAL_HOURS = 24L // Проверка раз в сутки
    
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
            // Flex interval: 12 hours
            12,
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
            
            android.widget.Toast.makeText(
                context,
                "Начато скачивание обновления. После завершения загрузки откройте файл для установки.",
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
            
            // Проверить, прошло ли достаточно времени с последней проверки (не более раза в день)
            val lastCheck = prefs.lastUpdateCheck
            val now = System.currentTimeMillis()
            val dayInMillis = 24 * 60 * 60 * 1000L
            
            if (lastCheck > 0 && (now - lastCheck) < dayInMillis) {
                Log.d(TAG, "Проверка уже выполнялась недавно, пропускаем")
                return Result.success()
            }
            
            // Выполнить проверку обновлений (синхронно)
            val result = kotlinx.coroutines.runBlocking {
                AppUpdateChecker.checkForUpdates(applicationContext)
            }
            
            when (result) {
                is AppUpdateChecker.UpdateCheckResult.UpdateAvailable -> {
                    // Показать уведомление о новой версии
                    showUpdateNotification(result.versionInfo)
                    prefs.lastUpdateCheck = now
                    val versionInfo: AppVersionInfo = result.versionInfo
                    Log.d(TAG, "Найдена новая версия: ${versionInfo.versionName}")
                }
                AppUpdateChecker.UpdateCheckResult.NoUpdate -> {
                    prefs.lastUpdateCheck = now
                    Log.d(TAG, "Обновлений не найдено")
                }
                is AppUpdateChecker.UpdateCheckResult.Error -> {
                    Log.e(TAG, "Ошибка при проверке обновлений: ${result.message}")
                }
            }
            
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка в AppUpdateCheckWorker", e)
            Result.retry()
        }
    }
    
    private fun showUpdateNotification(versionInfo: AppVersionInfo) {
        // TODO: Реализовать уведомление о новой версии
        // Можно использовать NotificationManager для показа уведомления
        Log.d(TAG, "Новая версия доступна: ${versionInfo.versionName}")
    }
    
    companion object {
        private const val TAG = "AppUpdateCheckWorker"
    }
}

