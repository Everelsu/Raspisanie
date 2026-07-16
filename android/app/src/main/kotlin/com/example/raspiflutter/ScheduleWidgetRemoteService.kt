package com.example.raspiflutter

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.util.Calendar

class ScheduleWidgetRemoteService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ScheduleWidgetFactory(applicationContext, intent)
    }
}

/// Одна строка списка: номер пары, время начала/конца, предмет и детали.
/// Поля приходят из Dart через U+241F, легаси-формат ("N. Текст") — без полей.
private data class LessonRow(
    val number: String,
    val start: String,
    val end: String,
    val subject: String,
    val details: String,
)

private enum class RowStatus { PAST, CURRENT, UPCOMING, NONE }

private fun withAlpha(color: Int, alpha: Int): Int =
    Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

/// Контрастный цвет текста поверх [bg] (аналог onPrimary в приложении).
private fun contrastOn(bg: Int): Int {
    val luminance =
        (0.299 * Color.red(bg) + 0.587 * Color.green(bg) + 0.114 * Color.blue(bg)) / 255.0
    return if (luminance > 0.6) Color.parseColor("#111111") else Color.WHITE
}

private class ScheduleWidgetFactory(
    private val context: Context,
    private val intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {
    private val rows = mutableListOf<LessonRow>()
    private var textColor: Int = Color.WHITE
    private var subTextColor: Int = Color.parseColor("#B3FFFFFF")
    private var fontScale: Float = 1.0f
    private var accentColor: Int? = null
    private var isToday: Boolean = false
    private var fontKey: String = ""

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    override fun onDestroy() {
        rows.clear()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = rows.getOrElse(position) { LessonRow("", "", "", "", "") }
        val status = rowStatus(row)
        val accent = accentColor ?: textColor

        // Повторяем карточку пары из приложения (_LessonTile): круглый бейдж
        // с номером — акцентный у текущей и полупрозрачно-акцентный у
        // следующей; текущая пара получает акцентную заливку и полоску слева;
        // прошедшие пары приглушаются.
        val dim = status == RowStatus.PAST
        val mainColor = if (dim) withAlpha(textColor, 110) else textColor
        val secondColor = if (dim) withAlpha(subTextColor, 90) else subTextColor
        val timeColor = if (status == RowStatus.CURRENT) accent else secondColor

        return RemoteViews(context.packageName, widgetItemLayoutRes(fontKey)).apply {
            // Фон карточки: у текущей пары — акцентная заливка, у остальных —
            // едва заметная подложка цветом текста (onSurface с малой альфой).
            if (status == RowStatus.CURRENT) {
                setInt(R.id.widget_item_bg, "setColorFilter", accent)
                setInt(R.id.widget_item_bg, "setImageAlpha", 36)
            } else {
                setInt(R.id.widget_item_bg, "setColorFilter", textColor)
                setInt(R.id.widget_item_bg, "setImageAlpha", if (dim) 12 else 20)
            }

            // Бейдж номера пары.
            setTextViewText(R.id.widget_item_num, if (row.number.isEmpty()) "•" else row.number)
            when {
                status == RowStatus.CURRENT -> {
                    setInt(R.id.widget_item_badge, "setColorFilter", accent)
                    setInt(R.id.widget_item_badge, "setImageAlpha", 255)
                    setTextColor(R.id.widget_item_num, contrastOn(accent))
                }
                status == RowStatus.UPCOMING && isNextNumber(row.number) -> {
                    setInt(R.id.widget_item_badge, "setColorFilter", accent)
                    setInt(R.id.widget_item_badge, "setImageAlpha", 150)
                    setTextColor(R.id.widget_item_num, contrastOn(accent))
                }
                else -> {
                    setInt(R.id.widget_item_badge, "setColorFilter", textColor)
                    setInt(R.id.widget_item_badge, "setImageAlpha", if (dim) 12 else 24)
                    setTextColor(R.id.widget_item_num, mainColor)
                }
            }

            // Время над предметом, как в приложении; без времени — скрываем.
            if (row.start.isNotEmpty() && row.end.isNotEmpty()) {
                setTextViewText(R.id.widget_item_time, "${row.start}–${row.end}")
                setViewVisibility(R.id.widget_item_time, View.VISIBLE)
            } else if (row.start.isNotEmpty()) {
                setTextViewText(R.id.widget_item_time, row.start)
                setViewVisibility(R.id.widget_item_time, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_item_time, View.GONE)
            }
            setTextViewText(R.id.widget_item_subject, row.subject)
            if (row.details.isNotEmpty()) {
                setTextViewText(R.id.widget_item_details, row.details)
                setViewVisibility(R.id.widget_item_details, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_item_details, View.GONE)
            }

            setTextColor(R.id.widget_item_time, timeColor)
            setTextColor(R.id.widget_item_subject, mainColor)
            setTextColor(R.id.widget_item_details, secondColor)

            // Полоска-индикатор слева: видима только у текущей пары.
            if (status == RowStatus.CURRENT) {
                setInt(R.id.widget_item_stripe, "setColorFilter", accent)
                setInt(R.id.widget_item_stripe, "setImageAlpha", 255)
            } else {
                setInt(R.id.widget_item_stripe, "setColorFilter", textColor)
                setInt(R.id.widget_item_stripe, "setImageAlpha", 0)
            }

            setTextViewTextSize(R.id.widget_item_num, TypedValue.COMPLEX_UNIT_SP, 14f * fontScale)
            setTextViewTextSize(R.id.widget_item_time, TypedValue.COMPLEX_UNIT_SP, 11f * fontScale)
            setTextViewTextSize(R.id.widget_item_subject, TypedValue.COMPLEX_UNIT_SP, 13f * fontScale)
            setTextViewTextSize(R.id.widget_item_details, TypedValue.COMPLEX_UNIT_SP, 11f * fontScale)
        }
    }

    /// Номер первой ещё не начавшейся пары — её бейдж красится как «следующая».
    private fun isNextNumber(number: String): Boolean {
        val next = rows.firstOrNull { rowStatus(it) == RowStatus.UPCOMING } ?: return false
        return next.number == number && number.isNotEmpty()
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false

    private fun rowStatus(row: LessonRow): RowStatus {
        if (!isToday || row.start.isEmpty() || row.end.isEmpty()) return RowStatus.NONE
        val start = parseMinutes(row.start) ?: return RowStatus.NONE
        val end = parseMinutes(row.end) ?: return RowStatus.NONE
        val cal = Calendar.getInstance()
        val now = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        return when {
            now >= end -> RowStatus.PAST
            now >= start -> RowStatus.CURRENT
            else -> RowStatus.UPCOMING
        }
    }

    private fun parseMinutes(time: String): Int? {
        val parts = time.split(":")
        if (parts.size != 2) return null
        val h = parts[0].trim().toIntOrNull() ?: return null
        val m = parts[1].trim().toIntOrNull() ?: return null
        return h * 60 + m
    }

    private fun loadData() {
        rows.clear()
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val payload = prefs.getString("widget_day_items", "") ?: ""
        val themeKey = prefs.getString("widget_theme", "dark") ?: "dark"
        fontScale = readFontScale(prefs)
        val accentStr = intent.data?.getQueryParameter("accent")?.trim()
            ?: intent.getStringExtra("widget_accent_color")?.trim()
            ?: prefs.getString("widget_accent_color", "")?.trim()
        accentColor = if (!accentStr.isNullOrEmpty()) accentStr.toIntOrNull() else null
        fontKey = intent.data?.getQueryParameter("font")?.trim()
            ?: prefs.getString("widget_font", "") ?: ""
        isToday = isDateToday(prefs.getString("widget_date", "") ?: "")
        textColor = when (themeKey) {
            "light" -> Color.parseColor("#111111")
            "green" -> Color.parseColor("#E7FBEF")
            "pink" -> Color.parseColor("#FCE7F3")
            "gray" -> Color.parseColor("#F3F4F6")
            "purple" -> Color.parseColor("#F3E8FF")
            "orange" -> Color.parseColor("#FFF3E0")
            "blue" -> Color.parseColor("#E0E7FF")
            "red" -> Color.parseColor("#FFE5E3")
            "teal" -> Color.parseColor("#F8F3D0")
            else -> Color.parseColor("#F5F5F5")
        }
        subTextColor = if (themeKey == "light") {
            withAlpha(textColor, 160)
        } else {
            withAlpha(textColor, 170)
        }
        if (payload.isBlank()) return
        payload
            .split("␞")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { rows.add(parseRow(it)) }
    }

    private fun parseRow(raw: String): LessonRow {
        // Новый формат: номер/начало/конец/предмет/детали через U+241F
        // (детали могут быть многострочными).
        val fields = raw.split("␟")
        if (fields.size >= 5) {
            return LessonRow(
                number = fields[0].trim(),
                start = fields[1].trim(),
                end = fields[2].trim(),
                subject = fields[3].trim(),
                details = fields[4].trim(),
            )
        }
        // Легаси-формат от прошлой версии приложения: "N. Предмет\n  детали".
        val m = Regex("""^\s*(\d+)\.\s*(.+)$""", RegexOption.DOT_MATCHES_ALL).find(raw)
        if (m != null) {
            val lines = m.groupValues[2].lines()
            return LessonRow(
                number = m.groupValues[1],
                start = "",
                end = "",
                subject = lines.first().trim(),
                details = lines.drop(1).joinToString("\n") { it.trim() },
            )
        }
        return LessonRow("", "", "", raw, "")
    }

    private fun isDateToday(date: String): Boolean {
        // Дата приходит как DD.MM.YYYY (см. HomeWidgetService._dateKey).
        val parts = date.split(".")
        if (parts.size != 3) return false
        val cal = Calendar.getInstance()
        return parts[0].toIntOrNull() == cal.get(Calendar.DAY_OF_MONTH) &&
            parts[1].toIntOrNull() == cal.get(Calendar.MONTH) + 1 &&
            parts[2].toIntOrNull() == cal.get(Calendar.YEAR)
    }

    private fun readFontScale(
        prefs: android.content.SharedPreferences,
    ): Float {
        val raw = prefs.all["widget_font_scale"]
        val value = when (raw) {
            is Float -> raw
            is Double -> raw.toFloat()
            is Int -> raw.toFloat()
            is Long -> raw.toFloat()
            is String -> raw.toFloatOrNull()
            else -> null
        } ?: 1.0f
        return value.coerceIn(0.9f, 1.35f)
    }
}
