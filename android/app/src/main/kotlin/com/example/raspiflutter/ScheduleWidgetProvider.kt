package com.example.raspiflutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.util.TypedValue
import android.appwidget.AppWidgetProvider
import android.widget.RemoteViews

// Расширяем AppWidgetProvider напрямую, не через HomeWidgetProvider,
// чтобы не зависеть от бинарной совместимости native-кода home_widget пакета.
// Данные читаем из тех же SharedPreferences что пишет HomeWidget Dart-сторона.
class ScheduleWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, prefs)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            android.content.ComponentName(context, ScheduleWidgetProvider::class.java)
        )
        if (ids.isEmpty()) return

        // Some launchers/plugins dispatch non-standard actions for widget updates.
        // Force-refresh all existing instances on any broadcast received by provider.
        for (id in ids) {
            updateWidget(context, manager, id, prefs)
        }
    }

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            prefs: SharedPreferences
        ) {
            val title = prefs.getString("widget_title", "Расписание") ?: "Расписание"
            val subtitle = prefs.getString("widget_subtitle", "На сегодня нет данных")
                ?: "На сегодня нет данных"
            val primary = prefs.getString("widget_primary", "Нет пар") ?: "Нет пар"
            val secondary = prefs.getString("widget_secondary", "Откройте приложение")
                ?: "Откройте приложение"
            val footer = prefs.getString("widget_footer", "Raspisanie") ?: "Raspisanie"
            val countLabel = prefs.getString("widget_count_label", "") ?: ""
            val dayItems = prefs.getString("widget_day_items", "") ?: ""
            val themeKey = prefs.getString("widget_theme", "dark") ?: "dark"
            val fontScale = readFontScale(prefs)
            val refreshToken = prefs.getString("widget_refresh_token", "0") ?: "0"
            val accentColorStr = prefs.getString("widget_accent_color", "")?.trim()
            val accentColor = if (!accentColorStr.isNullOrEmpty()) accentColorStr.toIntOrNull() else null
            val bgRes = when (themeKey) {
                "light" -> R.drawable.widget_background_light
                "green" -> R.drawable.widget_background_green
                "pink" -> R.drawable.widget_background_pink
                "blue" -> R.drawable.widget_background
                "gray" -> R.drawable.widget_background_gray
                "purple" -> R.drawable.widget_background_purple
                "orange" -> R.drawable.widget_background_orange
                "red" -> R.drawable.widget_background_red
                "teal" -> R.drawable.widget_background_teal
                "dark" -> R.drawable.widget_background_dark
                else -> R.drawable.widget_background_dark
            }
            val themeTitleColor = when (themeKey) {
                "light" -> Color.parseColor("#111111")
                "green" -> Color.parseColor("#E7FBEF")
                "pink" -> Color.parseColor("#FCE7F3")
                "blue" -> Color.parseColor("#E0E7FF")
                "gray" -> Color.parseColor("#F3F4F6")
                "purple" -> Color.parseColor("#F3E8FF")
                "orange" -> Color.parseColor("#FFF3E0")
                "red" -> Color.parseColor("#FFE5E3")
                "teal" -> Color.parseColor("#F8F3D0")
                "dark" -> Color.parseColor("#FFFFFF")
                else -> Color.parseColor("#FFFFFF")
            }
            // Как в карточке дня: заголовок — обычным цветом текста,
            // акцент несут полоска слева и подсветка текущей пары.
            val titleColor = themeTitleColor
            val subColor = when (themeKey) {
                "light" -> Color.parseColor("#2F2F2F")
                "green" -> Color.parseColor("#BBF7D0")
                "pink" -> Color.parseColor("#F9A8D4")
                "blue" -> Color.parseColor("#93C5FD")
                "gray" -> Color.parseColor("#D1D5DB")
                "purple" -> Color.parseColor("#D8B4FE")
                "orange" -> Color.parseColor("#FDBA74")
                "red" -> Color.parseColor("#FECACA")
                "teal" -> Color.parseColor("#C6C09A")
                "dark" -> Color.parseColor("#B8B8B8")
                else -> Color.parseColor("#B8B8B8")
            }
            val footerColor = when (themeKey) {
                "light" -> Color.parseColor("#3A3A3A")
                "green" -> Color.parseColor("#A7F3D0")
                "pink" -> Color.parseColor("#FBCFE8")
                "blue" -> Color.parseColor("#93C5FD")
                "gray" -> Color.parseColor("#D1D5DB")
                "purple" -> Color.parseColor("#E9D5FF")
                "orange" -> Color.parseColor("#FED7AA")
                "red" -> Color.parseColor("#FDA4AF")
                "teal" -> Color.parseColor("#E8E37A")
                "dark" -> Color.parseColor("#9A9A9A")
                else -> Color.parseColor("#9A9A9A")
            }

            val views = RemoteViews(context.packageName, R.layout.schedule_widget_layout)
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                bgRes
            )
            // Акцентная полоска у названия группы — как в шапке карточки дня.
            views.setInt(R.id.widget_title_bar, "setColorFilter", accentColor ?: themeTitleColor)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)
            views.setTextViewText(R.id.widget_primary, primary)
            views.setTextViewText(R.id.widget_secondary, secondary)
            views.setTextViewText(R.id.widget_footer, footer)
            views.setTextColor(R.id.widget_title, titleColor)
            views.setTextColor(R.id.widget_subtitle, subColor)
            views.setTextColor(R.id.widget_primary, titleColor)
            views.setTextColor(R.id.widget_secondary, subColor)
            views.setTextColor(R.id.widget_footer, footerColor)
            views.setTextColor(R.id.widget_empty, subColor)
            views.setTextViewTextSize(R.id.widget_title, TypedValue.COMPLEX_UNIT_SP, 16f * fontScale)
            views.setTextViewTextSize(R.id.widget_subtitle, TypedValue.COMPLEX_UNIT_SP, 11f * fontScale)
            views.setTextViewTextSize(R.id.widget_primary, TypedValue.COMPLEX_UNIT_SP, 14f * fontScale)
            views.setTextViewTextSize(R.id.widget_secondary, TypedValue.COMPLEX_UNIT_SP, 12f * fontScale)
            views.setTextViewTextSize(R.id.widget_empty, TypedValue.COMPLEX_UNIT_SP, 11f * fontScale)
            views.setTextViewTextSize(R.id.widget_footer, TypedValue.COMPLEX_UNIT_SP, 10f * fontScale)
            // Чип количества пар справа от названия группы (акцентным цветом).
            if (countLabel.isNotBlank()) {
                views.setViewVisibility(R.id.widget_count, android.view.View.VISIBLE)
                views.setTextViewText(R.id.widget_count, countLabel)
                views.setTextColor(R.id.widget_count, subColor)
                views.setTextViewTextSize(R.id.widget_count, TypedValue.COMPLEX_UNIT_SP, 11f * fontScale)
            } else {
                views.setViewVisibility(R.id.widget_count, android.view.View.GONE)
            }
            val hasList = dayItems.isNotBlank()
            views.setViewVisibility(
                R.id.widget_primary,
                if (hasList) android.view.View.GONE else android.view.View.VISIBLE
            )
            views.setViewVisibility(
                R.id.widget_secondary,
                if (hasList) android.view.View.GONE else android.view.View.VISIBLE
            )
            views.setViewVisibility(
                R.id.widget_list,
                if (hasList) android.view.View.VISIBLE else android.view.View.GONE
            )
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            val listIntent = Intent(context, ScheduleWidgetRemoteService::class.java).apply {
                putExtra(EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("widget_refresh_token", refreshToken)
                putExtra("widget_theme", themeKey)
                putExtra("widget_accent_color", accentColorStr ?: "")
                data = android.net.Uri.parse(
                    "widget://${context.packageName}/schedule/$appWidgetId?rev=$refreshToken&theme=$themeKey&accent=${accentColorStr ?: ""}"
                )
            }
            views.setRemoteAdapter(R.id.widget_list, listIntent)

            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
        }

        private fun readFontScale(prefs: SharedPreferences): Float {
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
}
