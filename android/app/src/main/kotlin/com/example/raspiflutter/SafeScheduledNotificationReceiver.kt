package com.example.raspiflutter

import android.content.Context
import android.content.Intent
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver

/**
 * Обёртка над ScheduledNotificationReceiver из flutter_local_notifications.
 *
 * Защищает от краша "Invalid notification (no valid small icon)":
 * это происходит когда старое уведомление (запланированное до того как иконка
 * была явно указана в AndroidNotificationDetails) срабатывает через AlarmManager.
 * Receiver работает в отдельном процессе без Flutter — иконка из
 * AndroidInitializationSettings там недоступна, и Android бросает
 * IllegalArgumentException вместо молча игнорировать.
 */
class SafeScheduledNotificationReceiver : ScheduledNotificationReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            super.onReceive(context, intent)
        } catch (e: IllegalArgumentException) {
            // "Invalid notification (no valid small icon)" — старый payload без иконки.
            // Логируем для отладки, но не даём процессу упасть.
            Log.w("SafeNotifReceiver", "Skipped notification with invalid icon: ${e.message}")
        } catch (e: Exception) {
            Log.e("SafeNotifReceiver", "Unexpected error in notification receiver", e)
        }
    }
}
