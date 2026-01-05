package com.example.raspisanie.widget

import android.content.Context
import android.content.Intent
import android.appwidget.AppWidgetManager
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.example.raspisanie.R
import com.example.raspisanie.data.*
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

class ScheduleWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ScheduleRemoteViewsFactory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1))
    }

    inner class ScheduleRemoteViewsFactory(
        private val context: Context,
        private val appWidgetId: Int
    ) : RemoteViewsFactory {
        private var lessons: List<ScheduleItem> = emptyList()
        private var themeColors: Array<Int> = arrayOf(0, 0, 0)
        private var lessonNumberBg: Int = R.drawable.widget_lesson_number_bg_dark
        private var fontSizeMultiplier: Float = 1.0f
        
        // Thread-safe date formatter
        private val dateFormatter = ThreadLocal.withInitial {
            SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        }
        
        // Lock for thread-safe data access
        private val dataLock = ReentrantReadWriteLock()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            dataLock.write {
                try {
                    val prefs = PreferencesManager(context)
                    val todaySchedule = getTodaySchedule(context, prefs)
                    lessons = todaySchedule?.items?.sortedBy { it.lessonNumber } ?: emptyList()
                    themeColors = getThemeColors(context, prefs.theme)
                    lessonNumberBg = getLessonNumberBg(prefs.theme)
                    fontSizeMultiplier = getFontSizeMultiplier(prefs.fontSize)
                } catch (e: Exception) {
                    android.util.Log.e("ScheduleWidgetService", "Error in onDataSetChanged", e)
                    lessons = emptyList()
                }
            }
        }

        override fun onDestroy() {}

        override fun getCount(): Int = dataLock.read { lessons.size }

        override fun getViewAt(position: Int): RemoteViews {
            val (lesson, colors, bg) = dataLock.read {
                if (position < 0 || position >= lessons.size) {
                    return@read Triple<ScheduleItem?, Array<Int>?, Int?>(null, null, null)
                }
                Triple(lessons[position], themeColors, lessonNumberBg)
            }
            
            if (lesson == null || colors == null || bg == null) {
                // Return empty view if data is invalid
                return RemoteViews(context.packageName, R.layout.widget_lesson_item)
            }
            
            return try {
                val lessonView = RemoteViews(context.packageName, R.layout.widget_lesson_item)

                val subject = lesson.subject?.takeIf { it.isNotBlank() } ?: "Занятие"
                val prefs = PreferencesManager(context)
                val time = LessonTimes.formatTime(lesson.lessonNumber, prefs.college) ?: ""

                lessonView.setTextViewText(R.id.lesson_number, lesson.lessonNumber.toString())
                lessonView.setTextViewText(R.id.lesson_subject, subject)

                val details = buildString {
                    if (time.isNotBlank()) {
                        append(time)
                    }
                    if (lesson.classroom != null && lesson.classroom.isNotBlank()) {
                        if (length > 0) append(" • ")
                        append("Ауд. ${lesson.classroom}")
                    }
                    if (lesson.teacher != null && lesson.teacher.isNotBlank()) {
                        if (length > 0) append(" • ")
                        append(lesson.teacher)
                    }
                }
                lessonView.setTextViewText(R.id.lesson_details, details.ifEmpty { "—" })

                // Apply colors and background
                if (colors.size >= 3) {
                    lessonView.setTextColor(R.id.lesson_number, colors[0]) // Number color
                    lessonView.setTextColor(R.id.lesson_subject, colors[1]) // Subject color
                    lessonView.setTextColor(R.id.lesson_details, colors[2]) // Details color
                }
                lessonView.setInt(R.id.lesson_number, "setBackgroundResource", bg)
                
                // Apply font size
                val multiplier = dataLock.read { fontSizeMultiplier }
                lessonView.setTextViewTextSize(R.id.lesson_number, android.util.TypedValue.COMPLEX_UNIT_SP, 15f * multiplier)
                lessonView.setTextViewTextSize(R.id.lesson_subject, android.util.TypedValue.COMPLEX_UNIT_SP, 14f * multiplier)
                lessonView.setTextViewTextSize(R.id.lesson_details, android.util.TypedValue.COMPLEX_UNIT_SP, 12f * multiplier)

                lessonView
            } catch (e: Exception) {
                android.util.Log.e("ScheduleWidgetService", "Error in getViewAt for position $position", e)
                RemoteViews(context.packageName, R.layout.widget_lesson_item)
            }
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = dataLock.read {
            if (position < 0 || position >= lessons.size) return@read -1L
            lessons[position].hashCode().toLong()
        }

        override fun hasStableIds(): Boolean = true

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
                android.util.Log.e("ScheduleWidgetService", "Error formatting date", e)
                return null
            }
        }

        private fun getThemeColors(context: Context, theme: String): Array<Int> {
            return when (theme) {
                PreferencesManager.THEME_LIGHT -> arrayOf(
                    context.getColor(R.color.light_textColorPrimary), // Black number
                    context.getColor(R.color.light_textColorPrimary), // Black subject
                    context.getColor(R.color.light_textColorSecondary) // Gray details
                )
                PreferencesManager.THEME_DARK -> arrayOf(
                    context.getColor(R.color.dark_textColorPrimary), // White number
                    context.getColor(R.color.dark_textColorPrimary), // White subject
                    context.getColor(R.color.dark_textColorSecondary) // Gray details
                )
                PreferencesManager.THEME_BLUE -> arrayOf(
                    context.getColor(R.color.blue_colorPrimary), // Blue number
                    context.getColor(R.color.blue_textColorPrimary), // White subject
                    context.getColor(R.color.blue_textColorSecondary) // Blue-ish details
                )
                PreferencesManager.THEME_GRAY -> arrayOf(
                    context.getColor(R.color.gray_colorPrimary), // Gray number
                    context.getColor(R.color.gray_textColorPrimary), // White subject
                    context.getColor(R.color.gray_textColorSecondary) // Gray details
                )
                PreferencesManager.THEME_PURPLE -> arrayOf(
                    context.getColor(R.color.system_colorPrimary), // Purple number
                    context.getColor(R.color.system_textColorPrimary), // White subject
                    context.getColor(R.color.system_textColorSecondary) // Gray details
                )
                PreferencesManager.THEME_HALLOWEEN -> arrayOf(
                    context.getColor(R.color.custom_colorPrimary), // Orange number - Halloween
                    context.getColor(R.color.custom_textColorPrimary), // White subject
                    context.getColor(R.color.custom_textColorSecondary) // Gray details
                )
                PreferencesManager.THEME_NOTHING -> arrayOf(
                    context.getColor(R.color.nothing_colorPrimary), // Red number - Nothing red
                    context.getColor(R.color.nothing_textColorPrimary), // White subject
                    context.getColor(R.color.nothing_textColorSecondary) // Gray details
                )
                PreferencesManager.THEME_GREEN -> arrayOf(
                    context.getColor(R.color.green_colorPrimary), // Green number
                    context.getColor(R.color.green_textColorPrimary), // White subject
                    context.getColor(R.color.green_textColorSecondary) // Light green details
                )
                PreferencesManager.THEME_NEW_YEAR -> arrayOf(
                    context.getColor(R.color.newyear_colorPrimary), // Green number
                    context.getColor(R.color.newyear_textColorPrimary), // White subject
                    context.getColor(R.color.newyear_textColorSecondary) // Light gray details
                )
                else -> {
                    // Fallback to Purple theme
                    arrayOf(
                        context.getColor(R.color.system_colorPrimary),
                        context.getColor(R.color.system_textColorPrimary),
                        context.getColor(R.color.system_textColorSecondary)
                    )
                }
            }
        }
        
        private fun getLessonNumberBg(theme: String): Int {
            return when (theme) {
                PreferencesManager.THEME_LIGHT -> R.drawable.widget_lesson_number_bg_light
                PreferencesManager.THEME_DARK -> R.drawable.widget_lesson_number_bg_dark
                PreferencesManager.THEME_BLUE -> R.drawable.widget_lesson_number_bg_blue
                PreferencesManager.THEME_GRAY -> R.drawable.widget_lesson_number_bg_gray
                PreferencesManager.THEME_PURPLE -> R.drawable.widget_lesson_number_bg_purple
                PreferencesManager.THEME_HALLOWEEN -> R.drawable.widget_lesson_number_bg_halloween
                PreferencesManager.THEME_NOTHING -> R.drawable.widget_lesson_number_bg_nothing
                PreferencesManager.THEME_GREEN -> R.drawable.widget_lesson_number_bg_green
                PreferencesManager.THEME_NEW_YEAR -> R.drawable.widget_lesson_number_bg_newyear
                else -> R.drawable.widget_lesson_number_bg_dark
            }
        }
        
        private fun getFontSizeMultiplier(fontSize: String): Float {
            return when (fontSize) {
                PreferencesManager.FONT_SIZE_SMALL -> 0.85f
                PreferencesManager.FONT_SIZE_NORMAL -> 1.0f
                PreferencesManager.FONT_SIZE_LARGE -> 1.15f
                PreferencesManager.FONT_SIZE_EXTRA_LARGE -> 1.3f
                else -> 1.0f
            }
        }
    }
}

