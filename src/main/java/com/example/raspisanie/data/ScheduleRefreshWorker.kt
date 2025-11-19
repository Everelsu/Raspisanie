package com.example.raspisanie.data

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.raspisanie.repository.ScheduleRepository
import com.example.raspisanie.widget.CurrentLessonWidgetProvider
import com.example.raspisanie.widget.DayScheduleWidgetProvider

class ScheduleRefreshWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    
    companion object {
        private const val TAG = "ScheduleRefreshWorker"
    }
    
    override suspend fun doWork(): Result {
        return try {
            Log.d(TAG, "Начато автообновление расписания")
            
            val prefs = PreferencesManager(applicationContext)
            
            if (!prefs.autoRefreshEnabled) {
                Log.d(TAG, "Автообновление отключено")
                return Result.success()
            }
            
            if (!prefs.isGroupSelected()) {
                Log.d(TAG, "Группа не выбрана, пропускаю обновление")
                return Result.success()
            }
            
            val repository = ScheduleRepository(applicationContext)
            
            // Пытаемся обновить расписание (useCache = false для принудительного обновления)
            // Но при ошибке сети будет использован кэш автоматически
            try {
                repository.refreshSchedule(
                    prefs.selectedGroupFile,
                    prefs.college,
                    useCache = false // Force refresh when auto-refreshing
                )
                Log.d(TAG, "Расписание обновлено (или загружено из кэша при отсутствии интернета)")
            } catch (e: Exception) {
                // Ошибка уже обработана в refreshSchedule, просто логируем
                Log.w(TAG, "Ошибка при обновлении расписания: ${e.message}")
                // Продолжаем работу - виджеты обновятся из кэша или останутся с текущими данными
            }
            
            // Обновляем виджеты после обновления расписания
            try {
                val appWidgetManager = android.appwidget.AppWidgetManager.getInstance(applicationContext)
                
                // Update CurrentLesson widgets
                try {
                    val currentLessonWidgetIds = appWidgetManager.getAppWidgetIds(
                        android.content.ComponentName(applicationContext, CurrentLessonWidgetProvider::class.java)
                    )
                    if (currentLessonWidgetIds.isNotEmpty()) {
                        var updatedCount = 0
                        for (widgetId in currentLessonWidgetIds) {
                            try {
                                CurrentLessonWidgetProvider.updateAppWidget(applicationContext, appWidgetManager, widgetId)
                                updatedCount++
                            } catch (e: Exception) {
                                Log.w(TAG, "Не удалось обновить виджет текущего урока $widgetId: ${e.message}")
                            }
                        }
                        Log.d(TAG, "Обновлено виджетов текущего урока: $updatedCount/${currentLessonWidgetIds.size}")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Ошибка при обновлении виджетов текущего урока: ${e.message}")
                }
                
                // Update DaySchedule widgets
                try {
                    val dayScheduleWidgetIds = appWidgetManager.getAppWidgetIds(
                        android.content.ComponentName(applicationContext, DayScheduleWidgetProvider::class.java)
                    )
                    if (dayScheduleWidgetIds.isNotEmpty()) {
                        var updatedCount = 0
                        for (widgetId in dayScheduleWidgetIds) {
                            try {
                                DayScheduleWidgetProvider.updateAppWidget(applicationContext, appWidgetManager, widgetId)
                                updatedCount++
                            } catch (e: Exception) {
                                Log.w(TAG, "Не удалось обновить виджет расписания дня $widgetId: ${e.message}")
                            }
                        }
                        Log.d(TAG, "Обновлено виджетов расписания дня: $updatedCount/${dayScheduleWidgetIds.size}")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Ошибка при обновлении виджетов расписания дня: ${e.message}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Общая ошибка при обновлении виджетов: ${e.message}", e)
            }
            
            Log.d(TAG, "Автообновление завершено успешно")
            // Всегда возвращаем success, даже если были ошибки сети
            // WorkManager сам повторит попытку через заданный интервал
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка при автообновлении расписания", e)
            // При критических ошибках (не связанных с сетью) тоже возвращаем success
            // чтобы не зацикливать попытки. WorkManager повторит через интервал.
            Result.success()
        }
    }
}

