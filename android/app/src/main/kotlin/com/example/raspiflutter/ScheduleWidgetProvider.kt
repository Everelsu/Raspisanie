package com.example.raspiflutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.appwidget.AppWidgetProvider
import android.os.Bundle
import android.widget.RemoteViews
import kotlin.math.roundToInt

// Расширяем AppWidgetProvider напрямую, не через HomeWidgetProvider,
// чтобы не зависеть от бинарной совместимости native-кода home_widget пакета.
// Данные читаем из тех же SharedPreferences что пишет HomeWidget Dart-сторона.
//
// Кастомный шрифт (Space Grotesk / Ndot 77) RemoteViews не резолвит через
// android:fontFamily="@font/..." при инфлейте в процессе лаунчера (проверено
// живьём — виджет молча падает на системный шрифт). Поэтому текстовые поля
// рисуются в Bitmap через WidgetTextRenderer и вставляются как ImageView —
// перенос/эллипсис/размер теперь считаются здесь вручную под текущую ширину
// виджета (см. onAppWidgetOptionsChanged).
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

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        // Пользователь изменил размер виджета — перерисовываем bitmap-текст под
        // новую ширину (иначе он останется зафиксирован под старый размер).
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        updateWidget(context, appWidgetManager, appWidgetId, prefs)
    }

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"

        // Фиксированные отступы вокруг текстовых полей — см. schedule_widget_layout.xml
        // и drawable/widget_background_*.xml (<padding> у shape-фона).
        private const val BG_PADDING_DP = 14
        private const val COUNT_CHIP_MARGIN_START_DP = 8
        private const val COUNT_CHIP_PADDING_H_DP = 8 // на сторону

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
            val fontKey = prefs.getString("widget_font", "") ?: ""
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

            val density = context.resources.displayMetrics.density
            fun dp(v: Int) = (v * density).roundToInt()

            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val totalWidthPx = dp(minWidthDp)
            val contentWidthPx = (totalWidthPx - dp(BG_PADDING_DP * 2)).coerceAtLeast(dp(80))
            prefs.edit().putInt("widget_last_content_width_px", contentWidthPx).apply()

            val regularTypeface = WidgetTextRenderer.typeface(context, fontKey, bold = false)
            val boldTypeface = WidgetTextRenderer.typeface(context, fontKey, bold = true)

            val views = RemoteViews(context.packageName, R.layout.schedule_widget_layout)
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                bgRes
            )
            // Чип количества пар рендерим первым — заголовку нужна его ширина,
            // чтобы не наехать друг на друга (оба в одном Row).
            var chipWidthPx = 0
            if (countLabel.isNotBlank()) {
                val chipBitmap = WidgetTextRenderer.render(
                    context, countLabel, boldTypeface, 11f, subColor,
                    maxWidthPx = contentWidthPx, maxLines = 1, fontScale = fontScale,
                )
                chipWidthPx = chipBitmap.width + dp(COUNT_CHIP_PADDING_H_DP * 2)
                views.setViewVisibility(R.id.widget_count, android.view.View.VISIBLE)
                views.setImageViewBitmap(R.id.widget_count, chipBitmap)
            } else {
                views.setViewVisibility(R.id.widget_count, android.view.View.GONE)
            }

            val titleMaxWidthPx = (
                contentWidthPx -
                    if (chipWidthPx > 0) chipWidthPx + dp(COUNT_CHIP_MARGIN_START_DP) else 0
                ).coerceAtLeast(dp(40))

            views.setImageViewBitmap(
                R.id.widget_title,
                WidgetTextRenderer.render(
                    context, title, boldTypeface, 16f, titleColor,
                    maxWidthPx = titleMaxWidthPx, maxLines = 1, fontScale = fontScale,
                ),
            )
            views.setImageViewBitmap(
                R.id.widget_subtitle,
                WidgetTextRenderer.render(
                    context, subtitle, regularTypeface, 11f, subColor,
                    maxWidthPx = contentWidthPx, maxLines = 1, fontScale = fontScale,
                ),
            )
            val showFooter = prefs.getString("widget_show_footer", "1") != "0"
            if (showFooter) {
                views.setImageViewBitmap(
                    R.id.widget_footer,
                    WidgetTextRenderer.render(
                        context, footer, regularTypeface, 10f, footerColor,
                        maxWidthPx = contentWidthPx, maxLines = 1, fontScale = fontScale,
                    ),
                )
            }
            views.setViewVisibility(
                R.id.widget_footer,
                if (showFooter) android.view.View.VISIBLE else android.view.View.GONE
            )

            val hasList = dayItems.isNotBlank()
            if (!hasList) {
                views.setImageViewBitmap(
                    R.id.widget_primary,
                    WidgetTextRenderer.render(
                        context, primary, boldTypeface, 14f, titleColor,
                        maxWidthPx = contentWidthPx, maxLines = 1, fontScale = fontScale,
                    ),
                )
                views.setImageViewBitmap(
                    R.id.widget_secondary,
                    WidgetTextRenderer.render(
                        context, secondary, regularTypeface, 12f, subColor,
                        maxWidthPx = contentWidthPx, maxLines = 2, fontScale = fontScale,
                    ),
                )
            }
            views.setImageViewBitmap(
                R.id.widget_empty,
                WidgetTextRenderer.render(
                    context, "Нет пар на день", regularTypeface, 11f, subColor,
                    maxWidthPx = contentWidthPx, maxLines = 1, fontScale = fontScale,
                ),
            )
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
                    "widget://${context.packageName}/schedule/$appWidgetId?rev=$refreshToken&theme=$themeKey&accent=${accentColorStr ?: ""}&font=$fontKey&width=$contentWidthPx"
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
