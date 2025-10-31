package com.example.raspisanie.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.raspisanie.R
import com.example.raspisanie.data.LessonTimes
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleCache
import com.example.raspisanie.data.DaySchedule
import java.text.SimpleDateFormat
import java.util.*

/**
 * Виджет с расписанием на день
 */
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
        
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
            intent.action == "android.appwidget.action.APPWIDGET_UPDATE") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, DayScheduleWidgetProvider::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }
    
    companion object {
        private const val TAG = "DayScheduleWidget"
        
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = PreferencesManager(context)
            val cache = ScheduleCache(context)
            
            // Get today's schedule
            val todaySchedule = getTodaySchedule(context, prefs, cache)
            
            val views = RemoteViews(context.packageName, R.layout.widget_day_schedule)
            
            if (todaySchedule != null && prefs.isGroupSelected()) {
                // Show date
                views.setTextViewText(R.id.widget_date, todaySchedule.date)
                
                // Show lessons
                if (todaySchedule.items.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
                    
                    // Clear container and add lessons
                    views.removeAllViews(R.id.widget_lessons_container)
                    
                    val lessons = todaySchedule.items.sortedBy { it.lessonNumber }
                    var index = 0
                    for (lesson in lessons) {
                        // Create lesson item layout
                        val lessonRemoteView = RemoteViews(context.packageName, android.R.layout.simple_list_item_2)
                        
                        val time = LessonTimes.formatTime(lesson.lessonNumber, prefs.college)
                        val subject = lesson.subject ?: "Занятие"
                        val details = "${lesson.classroom ?: ""}${if (lesson.classroom != null && lesson.teacher != null) " • " else ""}${lesson.teacher ?: ""}"
                        
                        lessonRemoteView.setTextViewText(android.R.id.text1, "${lesson.lessonNumber}. $subject")
                        lessonRemoteView.setTextViewTextSize(android.R.id.text1, android.util.TypedValue.COMPLEX_UNIT_SP, 14f)
                        lessonRemoteView.setTextViewText(android.R.id.text2, "$time${if (details.isNotEmpty()) " • $details" else ""}")
                        lessonRemoteView.setTextViewTextSize(android.R.id.text2, android.util.TypedValue.COMPLEX_UNIT_SP, 11f)
                        
                        views.addView(R.id.widget_lessons_container, lessonRemoteView)
                        index++
                        if (index >= 5) break // Limit to 5 lessons for widget
                    }
                } else {
                    views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.widget_empty, "Нет пар на сегодня")
                }
            } else {
                views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_empty,
                    if (!prefs.isGroupSelected()) "Выберите группу" else "Нет расписания"
                )
            }
            
            // Set click intent to open app
            val intent = android.content.Intent(context, com.example.raspisanie.MainActivity::class.java)
            val pendingIntent = android.app.PendingIntent.getActivity(
                context, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
        
        private fun getTodaySchedule(
            context: Context,
            prefs: PreferencesManager,
            cache: ScheduleCache
        ): DaySchedule? {
            if (!prefs.isGroupSelected()) return null
            
            // Try to get from cache
            if (prefs.cacheEnabled) {
                val cached = cache.getCachedSchedule(prefs.selectedGroupFile, prefs.college)
                if (cached != null && cached.isNotEmpty()) {
                    return findTodayInSchedule(cached)
                }
            }
            
            return null
        }
        
        private fun findTodayInSchedule(schedules: List<DaySchedule>): DaySchedule? {
            val today = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
                .format(Date())
            return schedules.firstOrNull { it.date == today } ?: schedules.firstOrNull()
        }
        
        private fun buildLessonsText(daySchedule: DaySchedule, college: String): String {
            val lessons = daySchedule.items.sortedBy { it.lessonNumber }
            return lessons.joinToString("\n") { lesson ->
                val time = LessonTimes.formatTime(lesson.lessonNumber, college)
                "${lesson.lessonNumber}. ${lesson.subject ?: "Занятие"} ($time)"
            }
        }
    }
}

