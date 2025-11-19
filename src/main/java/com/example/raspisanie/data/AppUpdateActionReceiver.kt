package com.example.raspisanie.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BroadcastReceiver для обработки действий из уведомлений об обновлениях
 */
class AppUpdateActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            if (intent == null) {
                Log.w(TAG, "Получен null intent")
                return
            }
            
            when (intent.action) {
                "DOWNLOAD_UPDATE" -> {
                    val downloadUrl = intent.getStringExtra("download_url")
                    val versionName = intent.getStringExtra("version_name")
                    
                    if (!downloadUrl.isNullOrBlank()) {
                        Log.d(TAG, "Запуск скачивания обновления из уведомления: $versionName")
                        AppUpdateManager.downloadAndInstall(context, downloadUrl, versionName)
                    } else {
                        Log.e(TAG, "URL скачивания не указан или пуст")
                        try {
                            AppUpdateManager.showDownloadErrorNotification(context, "URL скачивания не указан")
                        } catch (e: Exception) {
                            Log.e(TAG, "Ошибка при показе уведомления об ошибке", e)
                        }
                    }
                }
                else -> {
                    Log.w(TAG, "Неизвестное действие: ${intent.action}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка в AppUpdateActionReceiver", e)
        }
    }
    
    companion object {
        private const val TAG = "AppUpdateActionReceiver"
    }
}

