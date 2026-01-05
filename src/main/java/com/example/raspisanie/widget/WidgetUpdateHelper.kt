package com.example.raspisanie.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import com.example.raspisanie.R

/**
 * Widgets are RemoteViews-based and won't automatically update when in-app theme changes.
 * Call this helper right after changing theme/font/group settings.
 */
object WidgetUpdateHelper {
    private const val TAG = "WidgetUpdateHelper"

    fun updateAll(context: Context) {
        val appCtx = context.applicationContext
        val mgr = AppWidgetManager.getInstance(appCtx)

        try {
            val currentIds = mgr.getAppWidgetIds(ComponentName(appCtx, CurrentLessonWidgetProvider::class.java))
            currentIds.forEach { id ->
                try {
                    CurrentLessonWidgetProvider.updateAppWidget(appCtx, mgr, id)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to update CurrentLesson widget $id: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update CurrentLesson widgets: ${e.message}")
        }

        try {
            val dayIds = mgr.getAppWidgetIds(ComponentName(appCtx, DayScheduleWidgetProvider::class.java))
            dayIds.forEach { id ->
                try {
                    DayScheduleWidgetProvider.updateAppWidget(appCtx, mgr, id)
                    // Ensure list items refresh (RemoteViewsService)
                    mgr.notifyAppWidgetViewDataChanged(id, R.id.widget_lessons_list)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to update DaySchedule widget $id: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update DaySchedule widgets: ${e.message}")
        }
    }
}


