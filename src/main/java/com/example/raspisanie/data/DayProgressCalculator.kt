package com.example.raspisanie.data

import java.text.SimpleDateFormat
import java.util.*

object DayProgressCalculator {
    private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
    
    /**
     * Парсит время в формате "HH:mm" и возвращает минуты с начала дня
     */
    private fun parseTime(timeStr: String): Int {
        val parts = timeStr.split(":")
        if (parts.size == 2) {
            val hours = parts[0].toIntOrNull() ?: 0
            val minutes = parts[1].toIntOrNull() ?: 0
            return hours * 60 + minutes
        }
        return 0
    }
    
    /**
     * Получить текущее время в минутах от начала дня
     */
    fun getCurrentTimeInMinutes(): Int {
        val calendar = Calendar.getInstance()
        return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
    }
    
    /**
     * Проверить, находится ли текущее время в интервале занятия/перемены/обеда
     */
    fun isTimeInRange(currentMinutes: Int, startTime: String, endTime: String): Boolean {
        val start = parseTime(startTime)
        val end = parseTime(endTime)
        return currentMinutes in start..end
    }
    
    /**
     * Получить прогресс занятия (0.0 - 1.0)
     */
    fun getLessonProgress(lessonNumber: Int, currentMinutes: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): Float {
        val time = LessonTimes.getTime(lessonNumber, college) ?: return 0f
        val start = parseTime(time.startTime)
        val end = parseTime(time.endTime)
        
        if (currentMinutes < start) return 0f
        if (currentMinutes > end) return 1f
        
        val duration = end - start
        val elapsed = currentMinutes - start
        return (elapsed.toFloat() / duration).coerceIn(0f, 1f)
    }
    
    /**
     * Проверить, прошло ли занятие
     */
    fun isLessonPassed(lessonNumber: Int, currentMinutes: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): Boolean {
        val time = LessonTimes.getTime(lessonNumber, college) ?: return false
        val end = parseTime(time.endTime)
        return currentMinutes > end
    }
    
    /**
     * Проверить, идет ли сейчас занятие
     */
    fun isLessonActive(lessonNumber: Int, currentMinutes: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): Boolean {
        val time = LessonTimes.getTime(lessonNumber, college) ?: return false
        return isTimeInRange(currentMinutes, time.startTime, time.endTime)
    }
    
    /**
     * Получить прогресс дня (0.0 - 1.0) от начала первой пары до конца последней
     * @param lessonNumbers список номеров пар, которые есть в расписании дня (например [1, 2, 3])
     */
    fun getDayProgress(currentMinutes: Int, lessonNumbers: List<Int>? = null, college: String = PreferencesManager.COLLEGE_CHTOTIB): Float {
        val lessonsToConsider = lessonNumbers?.sorted() ?: (1..8).toList()
        
        if (lessonsToConsider.isEmpty()) return 0f
        
        val firstLessonNum = lessonsToConsider.first()
        val lastLessonNum = lessonsToConsider.last()
        
        val firstLesson = LessonTimes.getTime(firstLessonNum, college)
        val lastLesson = LessonTimes.getTime(lastLessonNum, college)
        
        if (firstLesson == null || lastLesson == null) return 0f
        
        val dayStart = parseTime(firstLesson.startTime)
        val dayEnd = parseTime(lastLesson.endTime)
        
        if (currentMinutes < dayStart) return 0f
        if (currentMinutes > dayEnd) return 1f
        
        val dayDuration = dayEnd - dayStart
        val elapsed = currentMinutes - dayStart
        return (elapsed.toFloat() / dayDuration).coerceIn(0f, 1f)
    }
}

