package com.example.raspisanie.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.example.raspisanie.data.ScheduleNotificationManager

class ScheduleEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return

        val title = intent.getStringExtra(ScheduleNotificationManager.EXTRA_EVENT_TITLE) ?: return
        val message = intent.getStringExtra(ScheduleNotificationManager.EXTRA_EVENT_MESSAGE) ?: return
        val bigText = intent.getStringExtra(ScheduleNotificationManager.EXTRA_EVENT_BIG_TEXT)
        val notificationId = intent.getIntExtra(
            ScheduleNotificationManager.EXTRA_EVENT_NOTIFICATION_ID,
            (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        )
        val eventType = intent.getStringExtra(ScheduleNotificationManager.EXTRA_EVENT_TYPE)

        ScheduleNotificationManager.showUpcomingEventNotification(
            context.applicationContext,
            notificationId,
            title,
            message,
            bigText,
            eventType
        )
    }
}



























