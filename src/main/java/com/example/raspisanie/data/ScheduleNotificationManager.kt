package com.example.raspisanie.data

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.raspisanie.MainActivity
import com.example.raspisanie.R
import com.example.raspisanie.notifications.ScheduleEventReceiver
import com.google.firebase.messaging.RemoteMessage
import com.google.gson.Gson
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.math.abs

object ScheduleNotificationManager {
    private const val TAG = "ScheduleNotification"
    private const val CHANNEL_ID = "schedule_updates"
    private const val REMOTE_CHANNEL_ID = "remote_admin_notifications"
    private const val EVENT_CHANNEL_ID = "schedule_upcoming_events"
    private const val NOTIFICATION_ID = 2001
    private const val MIN_TRIGGER_DELAY_MS = 5_000L
    const val ACTION_SHOW_EVENT_NOTIFICATION = "com.example.raspisanie.action.SHOW_SCHEDULE_EVENT"
    const val EXTRA_EVENT_NOTIFICATION_ID = "extra_event_notification_id"
    const val EXTRA_EVENT_TITLE = "extra_event_title"
    const val EXTRA_EVENT_MESSAGE = "extra_event_message"
    const val EXTRA_EVENT_BIG_TEXT = "extra_event_big_text"
    const val EXTRA_EVENT_TYPE = "extra_event_type"
    private val timeRegex = Regex("(\\d{1,2}:\\d{2})")
    private val gson by lazy { Gson() }

    fun handleScheduleUpdated(context: Context, schedule: List<DaySchedule>) {
        val prefs = PreferencesManager(context)

        try {
            scheduleUpcomingEventNotifications(context, schedule, prefs)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule upcoming events: ${e.message}", e)
        }

        if (schedule.isEmpty() || !prefs.scheduleNotificationsEnabled) return
        
        // Проверяем настройку уведомлений об обновлении расписания
        if (!prefs.scheduleUpdateNotificationsEnabled) {
            // Обновляем хеш, но не показываем уведомление
            val newHash = computeScheduleHash(schedule)
            if (newHash.isNotEmpty()) {
                prefs.lastScheduleHash = newHash
            }
            return
        }

        val newHash = computeScheduleHash(schedule)
        if (newHash.isEmpty()) return

        val previousHash = prefs.lastScheduleHash
        if (previousHash == newHash) {
            return
        }

        prefs.lastScheduleHash = newHash
        if (previousHash.isEmpty()) {
            return
        }

        ensureChannel(context)
        val (title, message) = buildNotificationContent(context, schedule)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Улучшенный стиль уведомления с большей информацией
        val bigText = buildBigTextForScheduleUpdate(context, schedule, message)
        
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_schedule)
            .setColor(ContextCompat.getColor(context, R.color.dayNamePurple))
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText(bigText)
                .setSummaryText(context.getString(R.string.notification_schedule_updated_tap_to_view)))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    fun handleRemoteMessage(context: Context, message: RemoteMessage) {
        ensureRemoteChannel(context)

        val title = message.data["title"] ?: message.notification?.title
            ?: context.getString(R.string.notification_remote_default_title)
        val body = message.data["body"] ?: message.notification?.body
            ?: context.getString(R.string.notification_remote_default_body)

        if (body.isNullOrBlank()) {
            return
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("from_notification", true)
                putExtra("notification_type", "remote")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, REMOTE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_schedule)
            .setColor(ContextCompat.getColor(context, R.color.dayNamePurple))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)

        val notificationId = message.messageId?.hashCode() ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.notification_schedule_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = context.getString(R.string.notification_schedule_channel_desc)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun ensureRemoteChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                REMOTE_CHANNEL_ID,
                context.getString(R.string.notification_remote_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = context.getString(R.string.notification_remote_channel_desc)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun ensureEventChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                EVENT_CHANNEL_ID,
                context.getString(R.string.notification_events_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = context.getString(R.string.notification_events_channel_desc)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    fun scheduleUpcomingEventNotifications(
        context: Context,
        schedule: List<DaySchedule>,
        prefs: PreferencesManager = PreferencesManager(context)
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        if (alarmManager == null) {
            Log.w(TAG, "AlarmManager unavailable, skipping upcoming event notifications")
            prefs.scheduledEventRequestCodes = emptySet()
            return
        }

        if (!prefs.scheduleNotificationsEnabled) {
            cancelUpcomingEventNotifications(context, prefs)
            return
        }

        // Проверяем, включены ли хотя бы какие-то уведомления (о парах, обеде или переменах)
        val hasAnyNotificationsEnabled = prefs.upcomingNotificationsEnabled || 
                                        prefs.upcomingBreakRemindersEnabled || 
                                        prefs.upcomingLunchRemindersEnabled
        
        if (!hasAnyNotificationsEnabled) {
            cancelUpcomingEventNotifications(context, prefs)
            return
        }

        if (schedule.isEmpty()) {
            cancelUpcomingEventNotifications(context, prefs)
            return
        }

        val targetDay = findUpcomingDay(schedule)
        if (targetDay == null) {
            cancelUpcomingEventNotifications(context, prefs)
            return
        }

        val lessonOffsetMs = TimeUnit.MINUTES.toMillis(prefs.upcomingLessonOffsetMinutes.toLong().coerceAtLeast(0))
        val includeBreaks = prefs.upcomingBreakRemindersEnabled
        val includeLunch = prefs.upcomingLunchRemindersEnabled

        val events = buildUpcomingEvents(
            context,
            targetDay,
            prefs.college,
            lessonOffsetMs,
            includeBreaks,
            includeLunch
        )
        cancelUpcomingEventNotifications(context, prefs)

        if (events.isEmpty()) {
            Log.d(TAG, "No upcoming events to notify for ${targetDay.date}")
            return
        }

        ensureEventChannel(context)

        val now = System.currentTimeMillis()
        val updateFlags = pendingIntentUpdateFlags()
        val scheduledCodes = mutableSetOf<String>()

        events.forEach { event ->
            val triggerAt = event.triggerAtMillis
            // Фильтруем события, которые уже должны были произойти
            // Добавляем небольшой буфер (1 минута), чтобы не пропустить события, которые вот-вот начнутся
            if (triggerAt <= now - TimeUnit.MINUTES.toMillis(1)) {
                Log.d(TAG, "Пропущено прошедшее событие: ${event.title} (triggerAt=${triggerAt}, now=${now})")
                return@forEach
            }

            // Проверяем, что триггер не слишком далеко в будущем (больше недели - подозрительно)
            val maxFutureTime = now + TimeUnit.DAYS.toMillis(7)
            if (triggerAt > maxFutureTime) {
                Log.w(TAG, "Пропущено событие слишком далеко в будущем: ${event.title} (triggerAt=${triggerAt})")
                return@forEach
            }

            val intent = Intent(context, ScheduleEventReceiver::class.java).apply {
                action = ACTION_SHOW_EVENT_NOTIFICATION
                putExtra(EXTRA_EVENT_NOTIFICATION_ID, event.notificationId)
                putExtra(EXTRA_EVENT_TITLE, event.title)
                putExtra(EXTRA_EVENT_MESSAGE, event.contentText)
                putExtra(EXTRA_EVENT_BIG_TEXT, event.bigText ?: event.contentText)
                putExtra(EXTRA_EVENT_TYPE, event.type.name)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                event.requestCode,
                intent,
                updateFlags
            )

            try {
                // Проверить разрешение на точные будильники для Android 12+
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    if (!alarmManager.canScheduleExactAlarms()) {
                        Log.w(TAG, "Нет разрешения SCHEDULE_EXACT_ALARM для планирования уведомления: ${event.title}")
                        // Попробовать использовать неточный будильник как fallback
                        try {
                            alarmManager.setAndAllowWhileIdle(
                                AlarmManager.RTC_WAKEUP,
                                triggerAt,
                                pendingIntent
                            )
                            Log.d(TAG, "Запланировано уведомление (неточное): ${event.title} на ${java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).format(Date(triggerAt))}")
                            scheduledCodes += event.requestCode.toString()
                        } catch (e2: Exception) {
                            Log.e(TAG, "Ошибка при планировании неточного уведомления: ${event.title}", e2)
                        }
                        return
                    }
                }
                
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
                Log.d(TAG, "Запланировано уведомление: ${event.title} на ${java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).format(Date(triggerAt))}")
                scheduledCodes += event.requestCode.toString()
            } catch (e: SecurityException) {
                Log.e(TAG, "Ошибка безопасности при планировании уведомления: ${event.title}. Возможно, требуется разрешение SCHEDULE_EXACT_ALARM.", e)
                // Попробовать использовать неточный будильник как fallback
                try {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                    Log.d(TAG, "Запланировано уведомление (неточное, fallback): ${event.title}")
                    scheduledCodes += event.requestCode.toString()
                } catch (e2: Exception) {
                    Log.e(TAG, "Ошибка при планировании неточного уведомления (fallback): ${event.title}", e2)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при планировании уведомления: ${event.title}", e)
            }
        }

        prefs.scheduledEventRequestCodes = scheduledCodes
    }

    fun cancelUpcomingEventNotifications(context: Context) {
        cancelUpcomingEventNotifications(context, PreferencesManager(context))
    }

    private fun cancelUpcomingEventNotifications(context: Context, prefs: PreferencesManager) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val flags = pendingIntentNoCreateFlags()

        prefs.scheduledEventRequestCodes.forEach { code ->
            val requestCode = code.toIntOrNull() ?: return@forEach
            val intent = Intent(context, ScheduleEventReceiver::class.java).apply {
                action = ACTION_SHOW_EVENT_NOTIFICATION
            }
            val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
            pendingIntent?.let {
                alarmManager.cancel(it)
                it.cancel()
            }
        }

        prefs.scheduledEventRequestCodes = emptySet()
    }

    private fun buildUpcomingEvents(
        context: Context,
        daySchedule: DaySchedule,
        college: String,
        lessonOffsetMs: Long,
        includeBreaks: Boolean,
        includeLunch: Boolean
    ): List<UpcomingEvent> {
        val itemsByLesson = daySchedule.items.groupBy { it.lessonNumber }
        val lessonNumbers = itemsByLesson.keys.sorted()
        if (lessonNumbers.isEmpty()) return emptyList()

        val now = System.currentTimeMillis()
        val events = mutableListOf<UpcomingEvent>()

        lessonNumbers.forEachIndexed { index, lessonNumber ->
            val lessonTime = LessonTimes.getTime(lessonNumber, college) ?: return@forEachIndexed
            val startMillis = parseDateTime(daySchedule.date, lessonTime.startTime) ?: return@forEachIndexed
            
            // Пропускаем пары, которые уже закончились (с небольшим буфером в 5 минут)
            val endMillis = parseDateTime(daySchedule.date, lessonTime.endTime) ?: startMillis
            if (endMillis <= now - TimeUnit.MINUTES.toMillis(5)) {
                Log.d(TAG, "Пропущена прошедшая пара: урок $lessonNumber (закончился в ${lessonTime.endTime})")
                return@forEachIndexed
            }
            
            val trigger = adjustTrigger(startMillis - lessonOffsetMs, startMillis, now)
            if (trigger != null) {
                val summary = buildLessonSummary(context, lessonNumber, lessonTime, itemsByLesson[lessonNumber].orEmpty())
                events += UpcomingEvent(
                    triggerAtMillis = trigger,
                    requestCode = computeRequestCode(startMillis, lessonNumber, EventType.LESSON),
                    notificationId = computeNotificationId(startMillis, lessonNumber, EventType.LESSON),
                    type = EventType.LESSON,
                    title = context.getString(R.string.notification_next_lesson_title),
                    contentText = summary.content,
                    shortLabel = summary.shortLabel,
                    bigText = summary.bigText
                )
            }

            val nextLessonNumber = lessonNumbers.getOrNull(index + 1)
            val breakText = if (includeBreaks && nextLessonNumber != null) LessonTimes.getBreakText(lessonNumber, nextLessonNumber, college) else null
            if (!breakText.isNullOrBlank()) {
                val range = extractTimeRange(breakText)
                if (range != null) {
                    val (startTime, endTime) = range
                    val startMillisBreak = parseDateTime(daySchedule.date, startTime)
                    if (startMillisBreak != null) {
                        // Пропускаем перемены, которые уже прошли
                        val endMillisBreak = if (!endTime.isNullOrEmpty()) {
                            parseDateTime(daySchedule.date, endTime)
                        } else {
                            // Если нет времени окончания, используем начало следующей пары
                            if (nextLessonNumber != null) {
                                val nextLessonTime = LessonTimes.getTime(nextLessonNumber, college)
                                nextLessonTime?.let { parseDateTime(daySchedule.date, it.startTime) }
                            } else {
                                null
                            }
                        }
                        
                        if (endMillisBreak == null || endMillisBreak > now - TimeUnit.MINUTES.toMillis(5)) {
                            // Напоминание о перемене за 2 минуты до начала
                            val breakReminderOffset = TimeUnit.MINUTES.toMillis(2)
                            val triggerBreak = adjustTrigger(startMillisBreak - breakReminderOffset, startMillisBreak, now)
                            if (triggerBreak != null) {
                                val displayRange = if (endTime.isNullOrEmpty()) startTime else "$startTime - $endTime"
                                val title = context.getString(R.string.notification_next_break_title)
                                val message = context.getString(R.string.notification_next_break_body, displayRange)
                                val shortLabel = context.getString(R.string.notification_next_break_short_label, displayRange)
                                events += UpcomingEvent(
                                    triggerAtMillis = triggerBreak,
                                    requestCode = computeRequestCode(startMillisBreak, lessonNumber, EventType.BREAK),
                                    notificationId = computeNotificationId(startMillisBreak, lessonNumber, EventType.BREAK),
                                    type = EventType.BREAK,
                                    title = title,
                                    contentText = message,
                                    shortLabel = shortLabel,
                                    bigText = message
                                )
                                Log.d(TAG, "Добавлено напоминание о перемене: $message на ${java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).format(Date(triggerBreak))}")
                            }
                        }
                    }
                }
            }

            val lunchText = if (includeLunch) LessonTimes.getLunchText(lessonNumber, college) else null
            if (!lunchText.isNullOrBlank()) {
                val range = extractTimeRange(lunchText)
                if (range != null) {
                    val (startTime, endTime) = range
                    val startMillisLunch = parseDateTime(daySchedule.date, startTime)
                    if (startMillisLunch != null) {
                        // Пропускаем обеды, которые уже прошли
                        val endMillisLunch = if (!endTime.isNullOrEmpty()) {
                            parseDateTime(daySchedule.date, endTime)
                        } else {
                            // Если нет времени окончания, используем начало следующей пары
                            val nextLessonTime = LessonTimes.getTime(nextLessonNumber ?: (lessonNumber + 1), college)
                            nextLessonTime?.let { parseDateTime(daySchedule.date, it.startTime) }
                        }
                        
                        if (endMillisLunch == null || endMillisLunch > now - TimeUnit.MINUTES.toMillis(5)) {
                            // Напоминание об обеде за 5 минут до начала
                            val lunchReminderOffset = TimeUnit.MINUTES.toMillis(5)
                            val triggerLunch = adjustTrigger(startMillisLunch - lunchReminderOffset, startMillisLunch, now)
                            if (triggerLunch != null) {
                                val displayRange = if (endTime.isNullOrEmpty()) startTime else "$startTime - $endTime"
                                val title = context.getString(R.string.notification_next_lunch_title)
                                val message = context.getString(R.string.notification_next_lunch_body, displayRange)
                                val shortLabel = context.getString(R.string.notification_next_lunch_short_label, displayRange)
                                events += UpcomingEvent(
                                    triggerAtMillis = triggerLunch,
                                    requestCode = computeRequestCode(startMillisLunch, lessonNumber, EventType.LUNCH),
                                    notificationId = computeNotificationId(startMillisLunch, lessonNumber, EventType.LUNCH),
                                    type = EventType.LUNCH,
                                    title = title,
                                    contentText = message,
                                    shortLabel = shortLabel,
                                    bigText = message
                                )
                                Log.d(TAG, "Добавлено напоминание об обеде: $message на ${java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).format(Date(triggerLunch))}")
                            }
                        }
                    }
                }
            }
        }

        if (events.isEmpty()) return events

        events.sortBy { it.triggerAtMillis }

        for (i in 0 until events.size - 1) {
            val next = events[i + 1]
            val hint = context.getString(R.string.notification_event_after, next.shortLabel)
            val base = events[i].bigText ?: events[i].contentText
            events[i].bigText = "$base\n$hint"
        }

        val last = events.last()
        if (last.bigText == null) {
            last.bigText = last.contentText
        }

        return events
    }

    private fun buildLessonSummary(
        context: Context,
        lessonNumber: Int,
        time: LessonTime,
        items: List<ScheduleItem>
    ): LessonSummary {
        val subjects = items.mapNotNull { it.subject?.trim()?.takeIf { value -> value.isNotEmpty() } }.distinct()
        val subjectText = when {
            subjects.isEmpty() -> context.getString(R.string.notification_next_lesson_default_subject)
            subjects.size == 1 -> subjects.first()
            else -> subjects.joinToString(", ")
        }

        val detailParts = mutableListOf<String>()
        val classrooms = items.mapNotNull { it.classroom?.trim()?.takeIf { value -> value.isNotEmpty() } }.distinct()
        if (classrooms.isNotEmpty()) {
            detailParts += classrooms.joinToString(", ") { "ауд. $it" }
        }
        val teachers = items.mapNotNull { it.teacher?.trim()?.takeIf { value -> value.isNotEmpty() } }.distinct()
        if (teachers.isNotEmpty()) {
            detailParts += teachers.joinToString(", ")
        }

        val detailText = if (detailParts.isEmpty()) subjectText else "$subjectText • ${detailParts.joinToString(" • ")}"

        val content = context.getString(
            R.string.notification_next_lesson_body,
            lessonNumber,
            time.startTime,
            detailText
        )

        val range = "${time.startTime} - ${time.endTime}"
        val shortLabel = context.getString(R.string.notification_next_lesson_short_label, lessonNumber, range)

        val subgroupDetails = if (items.size <= 1) emptyList() else {
            items.mapIndexed { index, item ->
                val subgroupLabel = item.subgroup ?: (index + 1)
                val parts = mutableListOf<String>()
                item.subject?.trim()?.takeIf { value -> value.isNotEmpty() }?.let { parts += it }
                item.classroom?.trim()?.takeIf { value -> value.isNotEmpty() }?.let { parts += "ауд. $it" }
                item.teacher?.trim()?.takeIf { value -> value.isNotEmpty() }?.let { parts += it }
                val detail = if (parts.isEmpty()) {
                    context.getString(R.string.notification_next_lesson_default_subject)
                } else {
                    parts.joinToString(" • ")
                }
                context.getString(R.string.notification_next_lesson_subgroup_format, subgroupLabel, detail)
            }
        }

        val bigText = if (subgroupDetails.isEmpty()) {
            content
        } else {
            buildString {
                append(content)
                subgroupDetails.forEach {
                    append('\n')
                    append("• ")
                    append(it)
                }
            }
        }

        return LessonSummary(
            content = content,
            bigText = bigText,
            shortLabel = shortLabel
        )
    }

    private fun adjustTrigger(triggerMillis: Long, startMillis: Long, now: Long): Long? {
        // Если событие уже началось или прошло - не показываем
        if (startMillis <= now) return null
        
        // Если триггер в будущем - используем его
        if (triggerMillis > now) {
            // Убеждаемся, что триггер не позже начала события
            return if (triggerMillis < startMillis) triggerMillis else null
        }
        
        // Если триггер в прошлом, но событие еще не началось - показываем с минимальной задержкой
        val candidate = now + MIN_TRIGGER_DELAY_MS
        // Но только если это не позже начала события
        return if (candidate < startMillis) candidate else null
    }

    private fun parseDateTime(datePart: String, timePart: String): Long? {
        val formatter = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).apply {
            isLenient = false
            timeZone = java.util.TimeZone.getDefault() // Используем системную временную зону
        }
        return runCatching { 
            val parsed = formatter.parse("$datePart $timePart")
            parsed?.time
        }.getOrNull().also { result ->
            if (result == null) {
                Log.w(TAG, "Не удалось распарсить дату/время: $datePart $timePart")
            }
        }
    }

    private fun extractTimeRange(text: String): Pair<String, String?>? {
        val matches = timeRegex.findAll(text).map { it.value }.toList()
        if (matches.isEmpty()) return null
        val start = matches[0]
        val end = matches.getOrNull(1)
        return start to end
    }

    private fun computeRequestCode(timeMillis: Long, reference: Int, type: EventType): Int {
        val raw = timeMillis.hashCode() xor (reference shl 4) xor (type.ordinal shl 12)
        val normalized = if (raw == Int.MIN_VALUE) 0 else abs(raw)
        return normalized + type.ordinal * 1000
    }

    private fun computeNotificationId(timeMillis: Long, reference: Int, type: EventType): Int {
        val raw = timeMillis.hashCode() xor (reference shl 6) xor (type.ordinal shl 10)
        val normalized = if (raw == Int.MIN_VALUE) 1 else abs(raw)
        val candidate = normalized + 10000
        return if (candidate == NOTIFICATION_ID) candidate + 1 else candidate
    }

    private fun pendingIntentUpdateFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun pendingIntentNoCreateFlags(): Int {
        var flags = PendingIntent.FLAG_NO_CREATE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    fun showUpcomingEventNotification(
        context: Context,
        notificationId: Int,
        title: String,
        message: String,
        bigText: String?,
        eventTypeName: String?
    ) {
        ensureEventChannel(context)

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val eventType = runCatching { eventTypeName?.let { EventType.valueOf(it) } }.getOrNull()
        val contentText = message
        val expandedText = bigText ?: message

        // Улучшенный стиль уведомления о предстоящих событиях
        val improvedBigText = buildImprovedEventNotificationText(context, eventType, expandedText, contentText)
        
        // Определяем приоритет в зависимости от типа события
        val priority = when (eventType) {
            EventType.LESSON -> NotificationCompat.PRIORITY_HIGH
            EventType.BREAK, EventType.LUNCH -> NotificationCompat.PRIORITY_DEFAULT
            null -> NotificationCompat.PRIORITY_DEFAULT
        }
        
        val notification = NotificationCompat.Builder(context, EVENT_CHANNEL_ID)
            .setSmallIcon(getEventIcon(eventType))
            .setColor(ContextCompat.getColor(context, R.color.dayNamePurple))
            .setContentTitle(title)
            .setContentText(contentText)
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText(improvedBigText)
                .setSummaryText(context.getString(R.string.notification_event_tap_to_view)))
            .setAutoCancel(true)
            .setPriority(priority)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    private fun buildImprovedEventNotificationText(
        context: Context,
        eventType: EventType?,
        expandedText: String,
        contentText: String
    ): String {
        val builder = StringBuilder()
        
        // Добавляем эмодзи для лучшей визуализации
        val emoji = when (eventType) {
            EventType.LESSON -> "📚"
            EventType.BREAK -> "☕"
            EventType.LUNCH -> "🍽️"
            null -> "📅"
        }
        
        builder.append("$emoji ")
        builder.append(expandedText)
        
        // Добавляем разделитель для лучшей читаемости
        if (expandedText.contains("\n")) {
            builder.append("\n\n")
            builder.append(context.getString(R.string.notification_event_tap_to_view))
        }
        
        return builder.toString()
    }
    
    private fun getEventIcon(type: EventType?): Int {
        return R.drawable.ic_notification_schedule
    }

    private fun buildNotificationContent(context: Context, schedule: List<DaySchedule>): Pair<String, String> {
        val title = context.getString(R.string.notification_schedule_updated_title)
        val upcomingDay = findUpcomingDay(schedule)
        val message = if (upcomingDay != null) {
            val lessonsCount = upcomingDay.items.count { it.subject?.isNotBlank() == true }
            // Упрощённый текст: только день и количество пар
            "${upcomingDay.day}, ${upcomingDay.date} — $lessonsCount ${if (lessonsCount == 1) "пара" else if (lessonsCount in 2..4) "пары" else "пар"}"
        } else {
            context.getString(R.string.notification_schedule_updated_generic)
        }
        return title to message
    }

    private fun findUpcomingDay(schedule: List<DaySchedule>): DaySchedule? {
        val formatter = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val now = System.currentTimeMillis()
        val todayStart = formatter.parse(formatter.format(Date()))?.time ?: now

        return schedule
            .mapNotNull { day ->
                val parsedDate = runCatching { formatter.parse(day.date)?.time }.getOrNull()
                parsedDate?.let { parsed -> parsed to day }
            }
            .sortedBy { it.first }
            .firstOrNull { (parsedDateMillis, daySchedule) ->
                // Проверяем, что дата >= сегодня
                if (parsedDateMillis < todayStart) return@firstOrNull false
                
                // Если это сегодня, проверяем, есть ли еще не прошедшие пары
                if (parsedDateMillis == todayStart) {
                    val lastLesson = daySchedule.items.maxOfOrNull { it.lessonNumber } ?: return@firstOrNull true
                    // Используем дефолтный колледж для проверки времени
                    // В реальности колледж передается в buildUpcomingEvents, но здесь его нет
                    val lastLessonTime = LessonTimes.getTime(lastLesson, PreferencesManager.COLLEGE_CHTOTIB)
                    
                    if (lastLessonTime != null) {
                        val lastLessonEnd = parseDateTime(daySchedule.date, lastLessonTime.endTime)
                        // Если последняя пара еще не закончилась, или закончилась недавно (в пределах часа), показываем этот день
                        return@firstOrNull lastLessonEnd == null || (lastLessonEnd > now - TimeUnit.HOURS.toMillis(1))
                    }
                    return@firstOrNull true
                }
                
                // Для будущих дней всегда показываем
                true
            }
            ?.second ?: schedule.firstOrNull()
    }

    private fun buildBigTextForScheduleUpdate(context: Context, schedule: List<DaySchedule>, baseMessage: String): String {
        val upcomingDay = findUpcomingDay(schedule) ?: return baseMessage
        
        // Упрощённый текст: только основные предметы без деталей
        val subjects = upcomingDay.items
            .mapNotNull { it.subject?.trim()?.takeIf { s -> s.isNotEmpty() } }
            .distinct()
            .take(5)
        
        return if (subjects.isNotEmpty()) {
            val subjectsText = if (subjects.size <= 3) {
                subjects.joinToString(", ")
            } else {
                "${subjects.take(3).joinToString(", ")} и ещё ${subjects.size - 3}"
            }
            "$baseMessage\n\n$subjectsText"
        } else {
            baseMessage
        }
    }
    
    private fun computeScheduleHash(schedule: List<DaySchedule>): String {
        return runCatching {
            val json = gson.toJson(schedule)
            val digest = MessageDigest.getInstance("SHA-256")
            val bytes = digest.digest(json.toByteArray(Charsets.UTF_8))
            bytes.joinToString(separator = "") { byte -> "%02x".format(byte) }
        }.getOrElse { "" }
    }

    private enum class EventType {
        LESSON, BREAK, LUNCH
    }

    private data class UpcomingEvent(
        val triggerAtMillis: Long,
        val requestCode: Int,
        val notificationId: Int,
        val type: EventType,
        val title: String,
        val contentText: String,
        val shortLabel: String,
        var bigText: String?
    )

    private data class LessonSummary(
        val content: String,
        val bigText: String,
        val shortLabel: String
    )
}
