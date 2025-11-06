package com.example.raspisanie.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.raspisanie.R
import com.example.raspisanie.data.*
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class DayScheduleWidgetProvider : AppWidgetProvider() {
    
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, DayScheduleWidgetProvider::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }
    
    companion object {
        private const val TAG = "DayScheduleWidget"
        
        // Thread-safe date formatter
        private val dateFormatter = ThreadLocal.withInitial {
            SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        }
        
        // Lock for widget updates to prevent race conditions
        private val updateLock = ReentrantLock()
        
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // Validate widget ID before proceeding
            val validWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, DayScheduleWidgetProvider::class.java)
            )
            if (!validWidgetIds.contains(appWidgetId)) {
                android.util.Log.w(TAG, "Widget ID $appWidgetId is no longer valid, skipping update")
                return
            }
            
            updateLock.withLock {
                try {
                    val prefs = PreferencesManager(context)
                    val views = RemoteViews(context.packageName, R.layout.widget_day_schedule)
                    
                    // Apply theme colors
                    applyThemeColors(context, views, prefs.theme)
                    
                    if (!prefs.isGroupSelected()) {
                        views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                        views.setViewVisibility(R.id.widget_lessons_list, android.view.View.GONE)
                        views.setTextViewText(R.id.widget_empty, "Выберите группу")
                    } else {
                        val todaySchedule = getTodaySchedule(context, prefs)
                        
                        if (todaySchedule == null) {
                            views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                            views.setViewVisibility(R.id.widget_lessons_list, android.view.View.GONE)
                            views.setTextViewText(R.id.widget_empty, "Нет расписания")
                        } else {
                            if (todaySchedule.items.isEmpty()) {
                                views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                                views.setViewVisibility(R.id.widget_lessons_list, android.view.View.GONE)
                                views.setTextViewText(R.id.widget_empty, "Нет пар")
                            } else {
                                views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
                                views.setViewVisibility(R.id.widget_lessons_list, android.view.View.VISIBLE)
                                
                                // Setup remote list adapter for scrollable list
                                val serviceIntent = Intent(context, ScheduleWidgetService::class.java).apply {
                                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                                }
                                views.setRemoteAdapter(R.id.widget_lessons_list, serviceIntent)
                                    
                                // Hide navigation since we have scrolling
                                views.setViewVisibility(R.id.widget_navigation, android.view.View.GONE)
                                
                                // Setup click intent to open app
                                val intent = android.content.Intent(context, com.example.raspisanie.MainActivity::class.java)
                                val pendingIntent = android.app.PendingIntent.getActivity(
                                    context, 0, intent,
                                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                                )
                                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                                
                                // Update widget views first
                                appWidgetManager.updateAppWidget(appWidgetId, views)
                                
                                // Notify widget that data has changed after views are updated
                                try {
                                    appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_lessons_list)
                                } catch (e: Exception) {
                                    android.util.Log.e(TAG, "Error notifying widget data changed", e)
                                }
                                return // Early return after successful update
                            }
                        }
                    }
                    
                    val intent = android.content.Intent(context, com.example.raspisanie.MainActivity::class.java)
                    val pendingIntent = android.app.PendingIntent.getActivity(
                        context, 0, intent,
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                    
                    appWidgetManager.updateAppWidget(appWidgetId, views)
                    
                } catch (e: Exception) {
                    android.util.Log.e(TAG, "Error updating widget $appWidgetId", e)
                    // Try to show error state
                    try {
                        val views = RemoteViews(context.packageName, R.layout.widget_day_schedule)
                        views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                        views.setViewVisibility(R.id.widget_lessons_list, android.view.View.GONE)
                        views.setTextViewText(R.id.widget_empty, "Ошибка обновления")
                        appWidgetManager.updateAppWidget(appWidgetId, views)
                    } catch (e2: Exception) {
                        android.util.Log.e(TAG, "Failed to show error state", e2)
                    }
                }
            }
        }
        
        private fun applyThemeColors(context: Context, views: RemoteViews, theme: String) {
            val (textPrimary, textSecondary, backgroundDrawable) = getThemeColors(context, theme)
            
            // Apply background drawable
            views.setInt(R.id.widget_root, "setBackgroundResource", backgroundDrawable)
            
            views.setTextColor(R.id.widget_day_title, textPrimary)
            views.setTextColor(R.id.widget_empty, textSecondary)
        }
        
        private fun getThemeColors(context: Context, theme: String): Array<Int> {
            return when (theme) {
                PreferencesManager.THEME_LIGHT -> arrayOf(
                    context.getColor(R.color.light_textColorPrimary),
                    context.getColor(R.color.light_textColorSecondary),
                    R.drawable.widget_background_light
                )
                PreferencesManager.THEME_DARK -> arrayOf(
                    context.getColor(R.color.dark_textColorPrimary),
                    context.getColor(R.color.dark_textColorSecondary),
                    R.drawable.widget_background_dark
                )
                PreferencesManager.THEME_PURPLE -> arrayOf(
                    context.getColor(R.color.system_textColorPrimary), // White "Расписание"
                    context.getColor(R.color.system_textColorSecondary), // Gray empty message
                    R.drawable.widget_background_system
                )
                PreferencesManager.THEME_HALLOWEEN -> arrayOf(
                    context.getColor(R.color.custom_textColorPrimary), // White "Расписание"
                    context.getColor(R.color.custom_textColorSecondary), // Gray empty message
                    R.drawable.widget_background_custom
                )
                PreferencesManager.THEME_NOTHING -> arrayOf(
                    context.getColor(R.color.nothing_textColorPrimary), // White "Расписание"
                    context.getColor(R.color.nothing_textColorPrimary), // White empty
                    R.drawable.widget_background_nothing
                )
                PreferencesManager.THEME_GREEN -> arrayOf(
                    context.getColor(R.color.green_textColorPrimary), // White "Расписание"
                    context.getColor(R.color.green_textColorSecondary), // Light green empty message
                    R.drawable.widget_background_green
                )
                PreferencesManager.THEME_NEW_YEAR -> arrayOf(
                    context.getColor(R.color.newyear_textColorPrimary), // White "Расписание"
                    context.getColor(R.color.newyear_textColorSecondary), // Light gray empty message
                    R.drawable.widget_background_newyear
                )
                else -> { // Fallback to Purple theme
                    arrayOf(
                        context.getColor(R.color.system_textColorPrimary),
                        context.getColor(R.color.system_textColorSecondary),
                        R.drawable.widget_background_system
                    )
                }
            }
        }
        
        private fun getTodaySchedule(context: Context, prefs: PreferencesManager): DaySchedule? {
            if (!prefs.isGroupSelected()) return null
            
            val cache = ScheduleCache(context)
            if (!prefs.cacheEnabled) return null
            
            val cached = cache.getCachedSchedule(prefs.selectedGroupFile, prefs.college)
            if (cached == null || cached.isEmpty()) return null
            
            try {
                val today = dateFormatter.get()?.format(Date()) ?: return null
                return cached.firstOrNull { it.date == today }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error formatting date", e)
                return null
            }
        }
    }
}


