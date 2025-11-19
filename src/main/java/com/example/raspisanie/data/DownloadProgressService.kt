package com.example.raspisanie.data

import android.app.DownloadManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Service для отслеживания прогресса загрузки APK
 */
class DownloadProgressService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var isTracking = false
    private var downloadId: Long = -1
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        downloadId = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) ?: -1
        
        if (downloadId == -1L) {
            Log.w(TAG, "DownloadProgressService запущен без downloadId")
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Создать канал уведомлений
        AppUpdateManager.createNotificationChannel(this)
        
        // Показать foreground notification для Android 8.0+
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val notification = NotificationCompat.Builder(this, "app_updates_download_progress")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("📥 Скачивание обновления")
                .setContentText("Отслеживание прогресса...")
                .setProgress(0, 0, true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setSilent(true) // Без звука и вибрации
                .build()
            
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                // Android 14+ (API 34+) - требуется указать тип foreground service
                startForeground(1002, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(1002, notification)
            }
        }
        
        if (!isTracking) {
            isTracking = true
            startTracking()
        }
        
        return START_NOT_STICKY
    }
    
    private fun startTracking() {
        val runnable = object : Runnable {
            override fun run() {
                if (!isTracking) return
                
                try {
                    val downloadManager = try {
                        getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при получении DownloadManager", e)
                        stopTracking()
                        stopSelf()
                        return
                    }
                    
                    if (downloadManager == null) {
                        Log.e(TAG, "DownloadManager недоступен")
                        stopTracking()
                        stopSelf()
                        return
                    }
                    
                    val query = DownloadManager.Query().setFilterById(downloadId)
                    val cursor: Cursor? = try {
                        downloadManager.query(query)
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при запросе информации о загрузке", e)
                        stopTracking()
                        stopSelf()
                        return
                    }
                    
                    if (cursor == null) {
                        Log.e(TAG, "Не удалось получить информацию о загрузке")
                        stopTracking()
                        stopSelf()
                        return
                    }
                    
                    try {
                        if (!cursor.moveToFirst()) {
                            Log.w(TAG, "Курсор пуст для downloadId: $downloadId")
                            cursor?.close()
                            stopTracking()
                            stopSelf()
                            return
                        }
                        
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val titleIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TITLE)
                        
                        if (statusIndex == -1 || titleIndex == -1) {
                            Log.e(TAG, "Не найдены необходимые колонки в курсоре")
                            cursor?.close()
                            stopTracking()
                            stopSelf()
                            return
                        }
                        
                        val status = cursor.getInt(statusIndex)
                        val title = cursor.getString(titleIndex) ?: ""
                        
                        if (title == "Обновление приложения") {
                            when (status) {
                                DownloadManager.STATUS_RUNNING -> {
                                    // Загрузка в процессе - обновить прогресс
                                    try {
                                        val bytesIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                                        val totalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                                        val descIndex = cursor.getColumnIndex(DownloadManager.COLUMN_DESCRIPTION)
                                        
                                        val bytesDownloaded = if (bytesIndex != -1) cursor.getLong(bytesIndex) else 0L
                                        val totalSize = if (totalIndex != -1) cursor.getLong(totalIndex) else 0L
                                        
                                        val versionName = if (descIndex != -1) {
                                            val description = cursor.getString(descIndex)
                                            description?.substringAfter("версии ")?.takeIf { it.isNotBlank() } 
                                                ?: "новой версии"
                                        } else {
                                            "новой версии"
                                        }
                                        
                                        if (totalSize > 0 && bytesDownloaded >= 0) {
                                            val progress = try {
                                                ((bytesDownloaded * 100) / totalSize).toInt().coerceIn(0, 100)
                                            } catch (e: Exception) {
                                                Log.w(TAG, "Ошибка при вычислении прогресса", e)
                                                0
                                            }
                                            updateProgressNotification(versionName, progress, bytesDownloaded, totalSize)
                                        } else {
                                            // Размер неизвестен - показать indeterminate progress
                                            updateProgressNotification(versionName, 0, 0, 0)
                                        }
                                        
                                        // Продолжить отслеживание через 1 секунду
                                        handler.postDelayed(this, 1000)
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Ошибка при обновлении прогресса", e)
                                        // Продолжить отслеживание даже при ошибке
                                        handler.postDelayed(this, 1000)
                                    }
                                }
                                DownloadManager.STATUS_SUCCESSFUL -> {
                                    // Загрузка завершена - остановить отслеживание
                                    stopTracking()
                                    stopSelf()
                                }
                                DownloadManager.STATUS_FAILED -> {
                                    // Ошибка загрузки - остановить отслеживание
                                    stopTracking()
                                    stopSelf()
                                }
                                else -> {
                                    // Другие статусы - продолжить отслеживание
                                    handler.postDelayed(this, 1000)
                                }
                            }
                        } else {
                            // Это не наша загрузка
                            stopTracking()
                            stopSelf()
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обработке данных загрузки", e)
                        try {
                            cursor?.close()
                        } catch (e2: Exception) {
                            Log.w(TAG, "Ошибка при закрытии курсора", e2)
                        }
                        stopTracking()
                        stopSelf()
                        return
                    } finally {
                        try {
                            cursor?.let {
                                if (!it.isClosed) {
                                    it.close()
                                }
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Ошибка при закрытии курсора в finally", e)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Критическая ошибка при отслеживании прогресса", e)
                    stopTracking()
                    stopSelf()
                }
            }
        }
        
        handler.post(runnable)
    }
    
    private fun updateProgressNotification(
        versionName: String,
        progress: Int,
        bytesDownloaded: Long,
        totalSize: Long
    ) {
        if (!isTracking) {
            // Service уже остановлен, не обновляем уведомление
            return
        }
        
        try {
            val notificationManager = try {
                getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при получении NotificationManager", e)
                return
            }
            
            if (notificationManager == null) {
                Log.w(TAG, "NotificationManager недоступен")
                return
            }
            
            AppUpdateManager.createNotificationChannel(this)
            
            val notification = try {
                if (totalSize > 0) {
                    // Форматировать размеры
                    val downloadedMB = String.format("%.1f", bytesDownloaded / (1024.0 * 1024.0))
                    val totalMB = String.format("%.1f", totalSize / (1024.0 * 1024.0))
                    val safeProgress = progress.coerceIn(0, 100)
                    
                    NotificationCompat.Builder(this, "app_updates_download_progress")
                        .setSmallIcon(android.R.drawable.stat_notify_sync)
                        .setContentTitle("📥 Скачивание обновления")
                        .setContentText("$safeProgress% • $downloadedMB / $totalMB МБ")
                        .setProgress(100, safeProgress, false)
                        .setPriority(NotificationCompat.PRIORITY_LOW)
                        .setOngoing(true)
                        .setAutoCancel(false)
                        .setSilent(true) // Без звука и вибрации
                        .build()
                } else {
                    // Indeterminate progress
                    NotificationCompat.Builder(this, "app_updates_download_progress")
                        .setSmallIcon(android.R.drawable.stat_notify_sync)
                        .setContentTitle("📥 Скачивание обновления")
                        .setContentText("Скачивание версии $versionName...")
                        .setProgress(0, 0, true)
                        .setPriority(NotificationCompat.PRIORITY_LOW)
                        .setOngoing(true)
                        .setAutoCancel(false)
                        .setSilent(true) // Без звука и вибрации
                        .build()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при создании уведомления о прогрессе", e)
                return
            }
            
            try {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    // Обновить foreground notification
                    if (android.os.Build.VERSION.SDK_INT >= 34) {
                        // Android 14+ (API 34+) - требуется указать тип foreground service
                        startForeground(1002, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                    } else {
                        startForeground(1002, notification)
                    }
                } else {
                    notificationManager.notify(1002, notification)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при показе уведомления о прогрессе", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при обновлении уведомления о прогрессе", e)
        }
    }
    
    private fun stopTracking() {
        isTracking = false
        handler.removeCallbacksAndMessages(null)
        
        // Остановить foreground service
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                // Android 14+ (API 34+)
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopTracking()
    }
    
    companion object {
        private const val TAG = "DownloadProgressService"
    }
}

