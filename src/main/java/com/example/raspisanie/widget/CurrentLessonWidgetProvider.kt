package com.example.raspisanie.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.raspisanie.R
import com.example.raspisanie.data.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

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
        private val widgetScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        
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
                android.content.ComponentName(context, CurrentLessonWidgetProvider::class.java)
            )
            if (!validWidgetIds.contains(appWidgetId)) {
                android.util.Log.w(TAG, "Widget ID $appWidgetId is no longer valid, skipping update")
                return
            }
            
            updateLock.withLock {
                try {
                    val prefs = PreferencesManager(context)
                    val views = RemoteViews(context.packageName, R.layout.widget_current_lesson)
                    
                    // Apply theme colors
                    applyThemeColors(context, views, prefs.theme)
                    
                    // Apply font size
                    applyFontSize(context, views, prefs.fontSize)
                    
                    if (!prefs.isGroupSelected()) {
                        views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                        views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                        views.setTextViewText(R.id.widget_no_lesson, context.getString(R.string.select_group))
                    } else {
                        val todaySchedule = getTodaySchedule(context, prefs)
                        
                        if (todaySchedule == null) {
                            views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                            views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                            views.setTextViewText(R.id.widget_no_lesson, context.getString(R.string.widget_loading))
                            requestScheduleRefresh(context, prefs, appWidgetManager, appWidgetId)
                        } else {
                            val currentLesson = findCurrentLesson(todaySchedule, prefs.college)
                            
                            if (currentLesson == null) {
                                views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                                views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                                views.setTextViewText(R.id.widget_no_lesson, context.getString(R.string.share_schedule_no_lessons))
                            } else {
                                views.setViewVisibility(R.id.widget_no_lesson, android.view.View.GONE)
                                views.setViewVisibility(R.id.widget_lesson_info, android.view.View.VISIBLE)
                                
                                val subject = currentLesson.subject ?: "Занятие"
                                val time = LessonTimes.formatTime(currentLesson.lessonNumber, prefs.college) ?: ""
                                
                                views.setTextViewText(R.id.widget_subject, subject)
                                views.setTextViewText(R.id.widget_time, time)
                                
                                // Добавляем статус пары (осталось/начнётся через)
                                val statusText = getLessonStatus(context, todaySchedule, currentLesson, prefs.college, prefs)
                                if (statusText != null) {
                                    views.setViewVisibility(R.id.widget_status, android.view.View.VISIBLE)
                                    views.setTextViewText(R.id.widget_status, statusText)
                                } else {
                                    views.setViewVisibility(R.id.widget_status, android.view.View.GONE)
                                }
                                
                                val details = buildString {
                                    if (currentLesson.classroom != null) {
                                        append("Ауд. ${currentLesson.classroom}")
                                    }
                                    if (currentLesson.teacher != null) {
                                        if (length > 0) append(" • ")
                                        append(currentLesson.teacher)
                                    }
                                }
                                views.setTextViewText(R.id.widget_details, details.ifEmpty { "—" })
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
                        val views = RemoteViews(context.packageName, R.layout.widget_current_lesson)
                        views.setViewVisibility(R.id.widget_lesson_info, android.view.View.GONE)
                        views.setViewVisibility(R.id.widget_no_lesson, android.view.View.VISIBLE)
                        views.setTextViewText(R.id.widget_no_lesson, context.getString(R.string.widget_error))
                        appWidgetManager.updateAppWidget(appWidgetId, views)
                    } catch (e2: Exception) {
                        android.util.Log.e(TAG, "Failed to show error state", e2)
                    }
                }
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
                PreferencesManager.THEME_BLUE -> arrayOf(
                    context.getColor(R.color.blue_textColorPrimary),
                    context.getColor(R.color.blue_textColorSecondary),
                    context.getColor(R.color.blue_colorPrimary),
                    R.drawable.widget_background_blue,
                    R.drawable.widget_time_badge_blue
                )
                PreferencesManager.THEME_GRAY -> arrayOf(
                    context.getColor(R.color.gray_textColorPrimary),
                    context.getColor(R.color.gray_textColorSecondary),
                    context.getColor(R.color.gray_colorPrimary),
                    R.drawable.widget_background_gray,
                    R.drawable.widget_time_badge_gray
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
                PreferencesManager.THEME_GREEN -> arrayOf(
                    context.getColor(R.color.green_textColorPrimary), // White subject
                    context.getColor(R.color.green_textColorSecondary), // Light green time/details
                    context.getColor(R.color.green_colorPrimary), // Green accent
                    R.drawable.widget_background_green,
                    R.drawable.widget_time_badge_green
                )
                PreferencesManager.THEME_NEW_YEAR -> arrayOf(
                    context.getColor(R.color.newyear_textColorPrimary), // White subject
                    context.getColor(R.color.newyear_textColorSecondary), // Light gray time/details
                    context.getColor(R.color.newyear_colorPrimary), // Green accent
                    R.drawable.widget_background_newyear,
                    R.drawable.widget_time_badge_newyear
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
            views.setTextColor(R.id.widget_status, textSecondary)
        }
        
        private fun applyFontSize(context: Context, views: RemoteViews, fontSize: String) {
            val multiplier = when (fontSize) {
                PreferencesManager.FONT_SIZE_SMALL -> 0.85f
                PreferencesManager.FONT_SIZE_NORMAL -> 1.0f
                PreferencesManager.FONT_SIZE_LARGE -> 1.15f
                PreferencesManager.FONT_SIZE_EXTRA_LARGE -> 1.3f
                else -> 1.0f
            }
            
            // Применяем размер шрифта ко всем TextView
            views.setTextViewTextSize(R.id.widget_subject, android.util.TypedValue.COMPLEX_UNIT_SP, 15f * multiplier)
            views.setTextViewTextSize(R.id.widget_time, android.util.TypedValue.COMPLEX_UNIT_SP, 13f * multiplier)
            views.setTextViewTextSize(R.id.widget_details, android.util.TypedValue.COMPLEX_UNIT_SP, 12f * multiplier)
            views.setTextViewTextSize(R.id.widget_no_lesson, android.util.TypedValue.COMPLEX_UNIT_SP, 14f * multiplier)
            views.setTextViewTextSize(R.id.widget_status, android.util.TypedValue.COMPLEX_UNIT_SP, 11f * multiplier)
        }
        
        private fun getLessonStatus(
            context: Context,
            daySchedule: DaySchedule,
            currentLesson: ScheduleItem,
            college: String,
            prefs: PreferencesManager
        ): String? {
            if (!prefs.showLessonStatus) return null
            
            try {
                val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                val lessonTime = LessonTimes.getTime(currentLesson.lessonNumber, college) ?: return null
                val start = parseTime(lessonTime.startTime)
                val end = parseTime(lessonTime.endTime)
                
                if (start <= 0 || end <= 0) return null
                
                // Если пара идёт сейчас
                if (currentMinutes >= start && currentMinutes <= end) {
                    val remaining = end - currentMinutes
                    if (remaining > 0 && remaining <= (prefs.lessonStatusCurrentMaxMinutes ?: 60)) {
                        return context.getString(R.string.lesson_status_remaining, remaining)
                    }
                }
                // Если пара ещё не началась
                else if (currentMinutes < start) {
                    val diff = start - currentMinutes
                    if (diff > 0 && diff <= (prefs.lessonStatusNextMaxMinutes ?: 60)) {
                        return context.getString(R.string.lesson_status_starts_in, diff)
                    }
                }
                
                // Показываем следующую пару, если текущая уже закончилась
                if (currentMinutes > end) {
                    val lessons = daySchedule.items.sortedBy { it.lessonNumber }
                    val currentIndex = lessons.indexOfFirst { it.lessonNumber == currentLesson.lessonNumber }
                    if (currentIndex >= 0 && currentIndex < lessons.size - 1) {
                        val nextLesson = lessons[currentIndex + 1]
                        val nextLessonTime = LessonTimes.getTime(nextLesson.lessonNumber, college) ?: return null
                        val nextStart = parseTime(nextLessonTime.startTime)
                        if (nextStart > 0) {
                            val diff = nextStart - currentMinutes
                            if (diff > 0 && diff <= (prefs.lessonStatusNextMaxMinutes ?: 60)) {
                                return "Следующая: ${nextLesson.subject} через $diff мин"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error getting lesson status", e)
            }
            
            return null
        }
        
        private fun getTodaySchedule(context: Context, prefs: PreferencesManager): DaySchedule? {
            if (!prefs.isGroupSelected()) return null
            
            val cache = ScheduleCache(context)
            val cached = cache.getCachedSchedule(prefs.selectedGroupFile, prefs.college)
            if (cached.isNullOrEmpty()) return null
            
            return try {
                val today = dateFormatter.get()?.format(Date()) ?: return null
                cached.firstOrNull { it.date == today }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error formatting date", e)
                null
            }
        }
        
        private fun findCurrentLesson(daySchedule: DaySchedule, college: String): ScheduleItem? {
            try {
                val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                val lessons = daySchedule.items.sortedBy { it.lessonNumber }
                
                // Find currently ongoing lesson (with 15 minute buffer)
                for (lesson in lessons) {
                    val lessonTime = LessonTimes.getTime(lesson.lessonNumber, college) ?: continue
                    val start = parseTime(lessonTime.startTime)
                    val end = parseTime(lessonTime.endTime)
                    
                    if (start <= 0 || end <= 0) continue // Invalid time
                    
                    if (currentMinutes >= start && currentMinutes <= end + 15) {
                        return lesson
                    }
                }
                
                // Find next upcoming lesson
                return lessons.firstOrNull { lesson ->
                    val lessonTime = LessonTimes.getTime(lesson.lessonNumber, college) ?: return@firstOrNull false
                    val start = parseTime(lessonTime.startTime)
                    start > 0 && currentMinutes < start
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error finding current lesson", e)
                return null
            }
        }
        
        private fun parseTime(timeStr: String): Int {
            if (timeStr.isBlank()) return 0
            try {
                val parts = timeStr.split(":")
                if (parts.size == 2) {
                    val hours = parts[0].toIntOrNull() ?: 0
                    val minutes = parts[1].toIntOrNull() ?: 0
                    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return 0
                    return hours * 60 + minutes
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error parsing time: $timeStr", e)
            }
            return 0
        }

        private fun requestScheduleRefresh(
            context: Context,
            prefs: PreferencesManager,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            if (!prefs.isGroupSelected()) return
            widgetScope.launch {
                try {
                    val schedule = ScheduleParser().fetchSchedule(prefs.selectedGroupFile, prefs.college)
                    if (schedule.isNotEmpty()) {
                        ScheduleCache(context).cacheSchedule(schedule, prefs.selectedGroupFile, prefs.college)
                        withContext(Dispatchers.Main) {
                            updateAppWidget(context, appWidgetManager, appWidgetId)
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e(TAG, "Widget background refresh failed", e)
                }
            }
        }
    }
}


