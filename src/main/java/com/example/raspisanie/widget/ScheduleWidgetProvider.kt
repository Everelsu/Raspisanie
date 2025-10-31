package com.example.raspisanie.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.raspisanie.R
import com.example.raspisanie.data.DayProgressCalculator
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.data.LessonTimes
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleCache
import com.example.raspisanie.data.ScheduleItem
import java.text.SimpleDateFormat
import java.util.*

/**
 * Компактный виджет с текущей парой
 */
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
        
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
            intent.action == "android.appwidget.action.APPWIDGET_UPDATE") {
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
            val prefs = PreferencesManager(context)
            val cache = ScheduleCache(context)
            
            // Get today's schedule
            val todaySchedule = getTodaySchedule(context, prefs, cache)
            
            val views = RemoteViews(context.packageName, R.layout.widget_current_lesson)
            
            if (todaySchedule != null && prefs.isGroupSelected()) {
                val currentLesson = getCurrentLesson(todaySchedule, prefs.college)
                
                if (currentLesson != null) {
                    // Show current lesson
                    val subject = currentLesson.subject ?: "Занятие"
                    val time = LessonTimes.formatTime(currentLesson.lessonNumber, prefs.college)
                    val classroom = currentLesson.classroom ?: ""
                    val teacher = currentLesson.teacher ?: ""
                    
                    views.setTextViewText(R.id.widget_subject, subject)
                    views.setTextViewTextSize(R.id.widget_subject, android.util.TypedValue.COMPLEX_UNIT_SP, 18f)
                    views.setTextViewText(R.id.widget_time, time)
                    views.setTextViewTextSize(R.id.widget_time, android.util.TypedValue.COMPLEX_UNIT_SP, 13f)
                    
                    // Combine classroom and teacher
                    val classroomText = if (classroom.isNotEmpty()) "Аудитория $classroom" else ""
                    val detailsText = when {
                        classroomText.isNotEmpty() && teacher.isNotEmpty() -> "$classroomText • $teacher"
                        classroomText.isNotEmpty() -> classroomText
                        teacher.isNotEmpty() -> teacher
                        else -> ""
                    }
                    
                    views.setTextViewText(R.id.widget_classroom, detailsText)
                    views.setTextViewTextSize(R.id.widget_classroom, android.util.TypedValue.COMPLEX_UNIT_SP, 12f)
                    views.setViewVisibility(R.id.widget_teacher, android.view.View.GONE)
                    
                    views.setViewVisibility(R.id.widget_no_lesson, android.view.View.GONE)
                    views.setViewVisibility(R.id.widget_lesson_info, android.view.View.VISIBLE)
                } else {
                    // No current lesson
                    views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                    views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                    views.setTextViewText(R.id.widget_no_lesson, "Сейчас нет пар")
                }
            } else {
                // No schedule or no group selected
                views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                views.setTextViewText(
                    R.id.widget_no_lesson,
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
        
        private fun getCurrentLesson(
            daySchedule: DaySchedule,
            college: String
        ): ScheduleItem? {
            val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
            
            // Find current or next lesson
            val lessons = daySchedule.items.sortedBy { it.lessonNumber }
            
            for (lesson in lessons) {
                val lessonTime = LessonTimes.getTime(lesson.lessonNumber, college) ?: continue
                val start = parseTime(lessonTime.startTime)
                val end = parseTime(lessonTime.endTime)
                
                // If we're during the lesson or it's the next upcoming lesson
                if (currentMinutes >= start && currentMinutes <= end + 15) {
                    return lesson
                }
            }
            
            // Return next lesson if any
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

