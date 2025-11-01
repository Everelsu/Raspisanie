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

class CurrentLessonWidgetProvider : AppWidgetProvider() {
    
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
                android.content.ComponentName(context, CurrentLessonWidgetProvider::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }
    
    companion object {
        private const val TAG = "CurrentLessonWidget"
        
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                val prefs = PreferencesManager(context)
                val views = RemoteViews(context.packageName, R.layout.widget_current_lesson)
                
                // Apply theme colors
                applyThemeColors(context, views, prefs.theme)
                
                if (!prefs.isGroupSelected()) {
                    views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                    views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.widget_no_lesson, "Выберите группу")
                } else {
                    val todaySchedule = getTodaySchedule(context, prefs)
                    
                    if (todaySchedule == null) {
                        views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                        views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                        views.setTextViewText(R.id.widget_no_lesson, "Нет расписания")
                    } else {
                        val currentLesson = findCurrentLesson(todaySchedule, prefs.college)
                        
                        if (currentLesson == null) {
                            views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                            views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                            views.setTextViewText(R.id.widget_no_lesson, "Нет пар")
                        } else {
                            views.setViewVisibility(R.id.widget_no_lesson, android.view.View.GONE)
                            views.setViewVisibility(R.id.widget_lesson_info, android.view.View.VISIBLE)
                            
                            val subject = currentLesson.subject ?: "Занятие"
                            val time = LessonTimes.formatTime(currentLesson.lessonNumber, prefs.college)
                            
                            views.setTextViewText(R.id.widget_subject, subject)
                            views.setTextViewText(R.id.widget_time, time)
                            
                            val details = buildString {
                                if (currentLesson.classroom != null) {
                                    append("Ауд. ${currentLesson.classroom}")
                                }
                                if (currentLesson.teacher != null) {
                                    if (length > 0) append(" • ")
                                    append(currentLesson.teacher)
                                }
                            }
                            views.setTextViewText(R.id.widget_details, details)
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
                android.util.Log.e(TAG, "Error updating widget", e)
            }
        }
        
        private fun applyThemeColors(context: Context, views: RemoteViews, theme: String) {
            val (textPrimary, textSecondary, primary, backgroundDrawable, timeBadgeDrawable) = when (theme) {
                PreferencesManager.THEME_LIGHT -> arrayOf(
                    context.getColor(R.color.light_textColorPrimary),
                    context.getColor(R.color.light_textColorSecondary),
                    context.getColor(R.color.light_colorPrimary),
                    R.drawable.widget_background_light,
                    R.drawable.widget_time_badge_light
                )
                PreferencesManager.THEME_DARK -> arrayOf(
                    context.getColor(R.color.dark_textColorPrimary),
                    context.getColor(R.color.dark_textColorSecondary),
                    context.getColor(R.color.dark_colorPrimary),
                    R.drawable.widget_background_dark,
                    R.drawable.widget_time_badge_dark
                )
                PreferencesManager.THEME_PURPLE -> arrayOf(
                    context.getColor(R.color.system_textColorPrimary), // White subject
                    context.getColor(R.color.system_textColorSecondary), // Gray time/details
                    context.getColor(R.color.system_colorPrimary), // Purple accent
                    R.drawable.widget_background_system,
                    R.drawable.widget_time_badge_dark
                )
                PreferencesManager.THEME_HALLOWEEN -> arrayOf(
                    context.getColor(R.color.custom_textColorPrimary), // White subject
                    context.getColor(R.color.custom_textColorPrimary), // White time/details
                    context.getColor(R.color.custom_colorPrimary), // Orange accent
                    R.drawable.widget_background_custom,
                    R.drawable.widget_time_badge_custom
                )
                PreferencesManager.THEME_NOTHING -> arrayOf(
                    context.getColor(R.color.nothing_colorPrimary), // Red subject
                    context.getColor(R.color.nothing_textColorPrimary), // White time/details
                    context.getColor(R.color.nothing_colorPrimary), // Red accent
                    R.drawable.widget_background_nothing,
                    R.drawable.widget_time_badge_nothing
                )
                else -> { // Fallback to Purple theme
                    arrayOf(
                        context.getColor(R.color.system_textColorPrimary),
                        context.getColor(R.color.system_textColorSecondary),
                        context.getColor(R.color.system_colorPrimary),
                        R.drawable.widget_background_system,
                        R.drawable.widget_time_badge_dark
                    )
                }
            }
            
            // Apply background drawable
            views.setInt(R.id.widget_root, "setBackgroundResource", backgroundDrawable)
            
            // Apply text colors
            views.setTextColor(R.id.widget_subject, textPrimary)
            views.setTextColor(R.id.widget_details, textSecondary)
            views.setTextColor(R.id.widget_no_lesson, textSecondary)
            views.setTextColor(R.id.widget_time, textSecondary)
        }
        
        private fun getTodaySchedule(context: Context, prefs: PreferencesManager): DaySchedule? {
            if (!prefs.isGroupSelected()) return null
            
            val cache = ScheduleCache(context)
            if (!prefs.cacheEnabled) return null
            
            val cached = cache.getCachedSchedule(prefs.selectedGroupFile, prefs.college)
            if (cached == null || cached.isEmpty()) return null
            
            val today = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date())
            return cached.firstOrNull { it.date == today }
        }
        
        private fun findCurrentLesson(daySchedule: DaySchedule, college: String): ScheduleItem? {
            val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
            val lessons = daySchedule.items.sortedBy { it.lessonNumber }
            
            for (lesson in lessons) {
                val lessonTime = LessonTimes.getTime(lesson.lessonNumber, college) ?: continue
                val start = parseTime(lessonTime.startTime)
                val end = parseTime(lessonTime.endTime)
                
                if (currentMinutes >= start && currentMinutes <= end + 15) {
                    return lesson
                }
            }
            
            return lessons.firstOrNull { lesson ->
                val lessonTime = LessonTimes.getTime(lesson.lessonNumber, college) ?: return@firstOrNull false
                val start = parseTime(lessonTime.startTime)
                currentMinutes < start
            }
        }
        
        private fun parseTime(timeStr: String): Int {
            val parts = timeStr.split(":")
            if (parts.size == 2) {
                val hours = parts[0].toIntOrNull() ?: 0
                val minutes = parts[1].toIntOrNull() ?: 0
                return hours * 60 + minutes
            }
            return 0
        }
    }
}


