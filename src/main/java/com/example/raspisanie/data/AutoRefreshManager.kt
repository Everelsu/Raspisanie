package com.example.raspisanie.data

import android.content.Context
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

object AutoRefreshManager {
    private const val TAG = "AutoRefreshManager"
    private const val WORK_NAME = "schedule_auto_refresh"
    
    /**
     * Настроить автообновление расписания
     */
    fun setupAutoRefresh(context: Context) {
        val prefs = PreferencesManager(context)
        val workManager = WorkManager.getInstance(context)
        
        // Cancel existing work
        workManager.cancelUniqueWork(WORK_NAME)
        
        if (!prefs.autoRefreshEnabled) {
            Log.d(TAG, "Автообновление отключено")
            return
        }
        
        val intervalMinutes = prefs.autoRefreshInterval.toLong()
        // Minimum interval for periodic work is 15 minutes
        val actualInterval = intervalMinutes.coerceAtLeast(15)
        
        val repeatInterval = PeriodicWorkRequest.Builder(
            ScheduleRefreshWorker::class.java,
            actualInterval,
            TimeUnit.MINUTES,
            // Flex interval: allow some flexibility in execution time (50% of repeat interval, but at least 15 minutes)
            (actualInterval / 2).coerceAtLeast(15),
            TimeUnit.MINUTES
        ).build()
        
        workManager.enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            repeatInterval
        )
        
        Log.d(TAG, "Автообновление настроено с интервалом $intervalMinutes минут")
    }
    
    /**
     * Отключить автообновление
     */
    fun cancelAutoRefresh(context: Context) {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(WORK_NAME)
        Log.d(TAG, "Автообновление отменено")
    }
}

