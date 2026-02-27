package com.example.raspiflutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.util.TypedValue
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ScheduleWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, widgetData)
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
            val primary = prefs.getString("widget_primary", "Нет занятий") ?: "Нет занятий"
            val secondary = prefs.getString("widget_secondary", "Откройте приложение")
                ?: "Откройте приложение"
            val footer = prefs.getString("widget_footer", "Raspisanie") ?: "Raspisanie"
            val dayItems = prefs.getString("widget_day_items", "") ?: ""
            val themeKey = prefs.getString("widget_theme", "dark") ?: "dark"
            val fontScale = readFontScale(prefs)
            val refreshToken = prefs.getString("widget_refresh_token", "0") ?: "0"
            val bgRes = when (themeKey) {
                "light" -> R.drawable.widget_background_light
                "green" -> R.drawable.widget_background_green
                "pink" -> R.drawable.widget_background_pink
                "blue" -> R.drawable.widget_background
                "gray" -> R.drawable.widget_background_gray
                "purple" -> R.drawable.widget_background_purple
                "orange" -> R.drawable.widget_background_orange
                else -> R.drawable.widget_background_dark
            }
            val titleColor = when (themeKey) {
                "light" -> Color.parseColor("#0F172A")
                "green" -> Color.parseColor("#E7FBEF")
                "pink" -> Color.parseColor("#FCE7F3")
                "blue" -> Color.parseColor("#E0F2FE")
                "gray" -> Color.parseColor("#F3F4F6")
                "purple" -> Color.parseColor("#F3E8FF")
                "orange" -> Color.parseColor("#FFF3E0")
                else -> Color.parseColor("#F3F4F6")
            }
            val subColor = when (themeKey) {
                "light" -> Color.parseColor("#4B5563")
                "green" -> Color.parseColor("#BBF7D0")
                "pink" -> Color.parseColor("#F9A8D4")
                "blue" -> Color.parseColor("#BAE6FD")
                "gray" -> Color.parseColor("#D1D5DB")
                "purple" -> Color.parseColor("#D8B4FE")
                "orange" -> Color.parseColor("#FDBA74")
                else -> Color.parseColor("#D1D5DB")
            }
            val footerColor = when (themeKey) {
                "light" -> Color.parseColor("#6B7280")
                "green" -> Color.parseColor("#A7F3D0")
                "pink" -> Color.parseColor("#FBCFE8")
                "blue" -> Color.parseColor("#BFDBFE")
                "gray" -> Color.parseColor("#D1D5DB")
                "purple" -> Color.parseColor("#E9D5FF")
                "orange" -> Color.parseColor("#FED7AA")
                else -> Color.parseColor("#9CA3AF")
            }

            val views = RemoteViews(context.packageName, R.layout.schedule_widget_layout)
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                bgRes
            )
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
                data = android.net.Uri.parse(
                    "widget://${context.packageName}/schedule/$appWidgetId?rev=$refreshToken&theme=$themeKey"
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
