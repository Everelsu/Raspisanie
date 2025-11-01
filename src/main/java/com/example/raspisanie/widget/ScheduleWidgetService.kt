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

        override fun onCreate() {}

        override fun onDataSetChanged() {
            val prefs = PreferencesManager(context)
            val todaySchedule = getTodaySchedule(context, prefs)
            lessons = todaySchedule?.items?.sortedBy { it.lessonNumber } ?: emptyList()
            themeColors = getThemeColors(context, prefs.theme)
            lessonNumberBg = getLessonNumberBg(prefs.theme)
        }

        override fun onDestroy() {}

        override fun getCount(): Int = lessons.size

        override fun getViewAt(position: Int): RemoteViews {
            val lesson = lessons[position]
            val lessonView = RemoteViews(context.packageName, R.layout.widget_lesson_item)

            val subject = lesson.subject ?: "Занятие"
            val prefs = PreferencesManager(context)
            val time = LessonTimes.formatTime(lesson.lessonNumber, prefs.college)

            lessonView.setTextViewText(R.id.lesson_number, lesson.lessonNumber.toString())
            lessonView.setTextViewText(R.id.lesson_subject, subject)

            val details = buildString {
                append(time)
                if (lesson.classroom != null) {
                    append(" • ")
                    append("Ауд. ${lesson.classroom}")
                }
                if (lesson.teacher != null) {
                    if (length > 0) append(" • ")
                    append(lesson.teacher)
                }
            }
            lessonView.setTextViewText(R.id.lesson_details, details)

            // Apply colors and background
            lessonView.setTextColor(R.id.lesson_number, themeColors[0]) // Number color
            lessonView.setTextColor(R.id.lesson_subject, themeColors[1]) // Subject color
            lessonView.setTextColor(R.id.lesson_details, themeColors[2]) // Details color
            lessonView.setInt(R.id.lesson_number, "setBackgroundResource", lessonNumberBg)

            return lessonView
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = position.toLong()

        override fun hasStableIds(): Boolean = true

        private fun getTodaySchedule(context: Context, prefs: PreferencesManager): DaySchedule? {
            if (!prefs.isGroupSelected()) return null

            val cache = ScheduleCache(context)
            if (!prefs.cacheEnabled) return null

            val cached = cache.getCachedSchedule(prefs.selectedGroupFile, prefs.college)
            if (cached == null || cached.isEmpty()) return null

            val today = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date())
            return cached.firstOrNull { it.date == today }
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
                PreferencesManager.THEME_PURPLE -> R.drawable.widget_lesson_number_bg_purple
                PreferencesManager.THEME_HALLOWEEN -> R.drawable.widget_lesson_number_bg_halloween
                PreferencesManager.THEME_NOTHING -> R.drawable.widget_lesson_number_bg_nothing
                else -> R.drawable.widget_lesson_number_bg_dark
            }
        }
    }
}

