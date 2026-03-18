package com.example.raspiflutter

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class ScheduleWidgetRemoteService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ScheduleWidgetFactory(applicationContext, intent)
    }
}

private fun contrastOnColor(backgroundColor: Int): Int {
    val r = Color.red(backgroundColor) / 255.0
    val g = Color.green(backgroundColor) / 255.0
    val b = Color.blue(backgroundColor) / 255.0
    val luminance = 0.299 * r + 0.587 * g + 0.114 * b
    return if (luminance > 0.5) Color.BLACK else Color.WHITE
}

private class ScheduleWidgetFactory(
    private val context: Context,
    private val intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {
    private val rows = mutableListOf<String>()
    private var textColor: Int = Color.WHITE
    private var numTextColor: Int = Color.WHITE
    private var itemBgRes: Int = R.drawable.widget_list_item_bg_dark
    private var numBgRes: Int = R.drawable.widget_num_badge_dark
    private var fontScale: Float = 1.0f
    private var accentColor: Int? = null

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
        val raw = rows.getOrElse(position) { "" }
        val parsed = parseRow(raw)
        val accent = accentColor
        return RemoteViews(context.packageName, R.layout.schedule_widget_list_item).apply {
            setTextViewText(R.id.widget_list_item_num, parsed.first)
            setTextViewText(R.id.widget_list_item_text, parsed.second)
            setTextColor(R.id.widget_list_item_text, textColor)
            setTextColor(R.id.widget_list_item_num, if (accent != null) contrastOnColor(accent) else numTextColor)
            setInt(R.id.widget_list_item_root, "setBackgroundResource", itemBgRes)
            if (accent != null) {
                setInt(R.id.widget_list_item_num_bg, "setBackgroundColor", accent)
            } else {
                setInt(R.id.widget_list_item_num_bg, "setBackgroundResource", numBgRes)
            }
            setTextViewTextSize(
                R.id.widget_list_item_text,
                TypedValue.COMPLEX_UNIT_SP,
                12f * fontScale
            )
            setTextViewTextSize(
                R.id.widget_list_item_num,
                TypedValue.COMPLEX_UNIT_SP,
                12f * fontScale
            )
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false

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
        when (themeKey) {
            "light" -> {
                textColor = Color.parseColor("#0F172A")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_light
                numBgRes = R.drawable.widget_num_badge_light
            }
            "green" -> {
                textColor = Color.parseColor("#E7FBEF")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_green
                numBgRes = R.drawable.widget_num_badge_green
            }
            "pink" -> {
                textColor = Color.parseColor("#FCE7F3")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_pink
                numBgRes = R.drawable.widget_num_badge_pink
            }
            "gray" -> {
                textColor = Color.parseColor("#F3F4F6")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_gray
                numBgRes = R.drawable.widget_num_badge_gray
            }
            "purple" -> {
                textColor = Color.parseColor("#F3E8FF")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_purple
                numBgRes = R.drawable.widget_num_badge_purple
            }
            "orange" -> {
                textColor = Color.parseColor("#FFF3E0")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_orange
                numBgRes = R.drawable.widget_num_badge_orange
            }
            "blue" -> {
                textColor = Color.parseColor("#E0E7FF")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_blue
                numBgRes = R.drawable.widget_num_badge_blue
            }
            "red" -> {
                textColor = Color.parseColor("#FFE5E3")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_red
                numBgRes = R.drawable.widget_num_badge_red
            }
            "teal" -> {
                textColor = Color.parseColor("#F8F3D0")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_teal
                numBgRes = R.drawable.widget_num_badge_teal
            }
            "dark" -> {
                textColor = Color.parseColor("#E5E7EB")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_dark
                numBgRes = R.drawable.widget_num_badge_dark
            }
            else -> {
                textColor = Color.parseColor("#E5E7EB")
                numTextColor = Color.WHITE
                itemBgRes = R.drawable.widget_list_item_bg_dark
                numBgRes = R.drawable.widget_num_badge_dark
            }
        }
        if (payload.isBlank()) return
        payload
            .split("\u241E")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { rows.add(it) }
    }

    private fun parseRow(row: String): Pair<String, String> {
        val m = Regex("""^\s*(\d+)\.\s*(.+)$""", RegexOption.DOT_MATCHES_ALL).find(row)
        if (m != null) {
            val num = m.groupValues[1]
            val text = m.groupValues[2]
            return num to text
        }
        return "•" to row
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
