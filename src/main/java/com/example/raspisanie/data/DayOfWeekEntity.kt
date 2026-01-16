package com.example.raspisanie.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Нормализованная таблица дней недели
 */
@Entity(tableName = "day_of_week")
data class DayOfWeekEntity(
    @PrimaryKey
    val id: Int, // 1-7: Понедельник=1, Вторник=2, ..., Воскресенье=7
    
    val shortName: String, // Пн, Вт, Ср, Чт, Пт, Сб, Вс
    val fullName: String, // Понедельник, Вторник, ..., Воскресенье
    val dayNumber: Int // 1-7
) {
    companion object {
        /**
         * Получить все дни недели по умолчанию
         */
        fun getDefaultDays(): List<DayOfWeekEntity> {
            return listOf(
                DayOfWeekEntity(1, "Пн", "Понедельник", 1),
                DayOfWeekEntity(2, "Вт", "Вторник", 2),
                DayOfWeekEntity(3, "Ср", "Среда", 3),
                DayOfWeekEntity(4, "Чт", "Четверг", 4),
                DayOfWeekEntity(5, "Пт", "Пятница", 5),
                DayOfWeekEntity(6, "Сб", "Суббота", 6),
                DayOfWeekEntity(7, "Вс", "Воскресенье", 7)
            )
        }
        
        /**
         * Нормализует короткое название дня (убирает точки, нормализует регистр)
         */
        fun normalizeDayName(day: String?): String? {
            if (day.isNullOrBlank()) return null
            val normalized = day.trim().removeSuffix(".").trim()
            
            // Маппинг различных вариантов
            return when (normalized) {
                "Пн", "пн" -> "Пн"
                "Вт", "вт" -> "Вт"
                "Ср", "ср" -> "Ср"
                "Чт", "чт" -> "Чт"
                "Пт", "пт" -> "Пт"
                "Сб", "сб" -> "Сб"
                "Вс", "вс" -> "Вс"
                "Понедельник", "понедельник" -> "Пн"
                "Вторник", "вторник" -> "Вт"
                "Среда", "среда" -> "Ср"
                "Четверг", "четверг" -> "Чт"
                "Пятница", "пятница" -> "Пт"
                "Суббота", "суббота" -> "Сб"
                "Воскресенье", "воскресенье" -> "Вс"
                else -> {
                    // Если уже полное название длиннее 4 символов, оставляем как есть
                    // но пытаемся найти короткое
                    if (normalized.length > 4) {
                        // Пытаемся извлечь первые 2 символа или найти в полных названиях
                        when {
                            normalized.contains("Понедельник", ignoreCase = true) -> "Пн"
                            normalized.contains("Вторник", ignoreCase = true) -> "Вт"
                            normalized.contains("Среда", ignoreCase = true) -> "Ср"
                            normalized.contains("Четверг", ignoreCase = true) -> "Чт"
                            normalized.contains("Пятница", ignoreCase = true) -> "Пт"
                            normalized.contains("Суббота", ignoreCase = true) -> "Сб"
                            normalized.contains("Воскресенье", ignoreCase = true) -> "Вс"
                            else -> normalized.take(2)
                        }
                    } else {
                        normalized.take(2)
                    }
                }
            }
        }
        
        /**
         * Преобразует день недели из Calendar в ID (Calendar.DAY_OF_WEEK: 1=воскресенье, 7=суббота)
         * Возвращает наш ID (1=понедельник, 7=воскресенье)
         */
        fun fromCalendarDay(calendarDay: Int): Int {
            // Calendar: 1=ВС, 2=ПН, 3=ВТ, 4=СР, 5=ЧТ, 6=ПТ, 7=СБ
            // Наш формат: 1=ПН, 2=ВТ, 3=СР, 4=ЧТ, 5=ПТ, 6=СБ, 7=ВС
            return when (calendarDay) {
                java.util.Calendar.MONDAY -> 1
                java.util.Calendar.TUESDAY -> 2
                java.util.Calendar.WEDNESDAY -> 3
                java.util.Calendar.THURSDAY -> 4
                java.util.Calendar.FRIDAY -> 5
                java.util.Calendar.SATURDAY -> 6
                java.util.Calendar.SUNDAY -> 7
                else -> {
                    // Fallback: если номер дня от 1 до 7, преобразуем
                    if (calendarDay in 1..7) {
                        ((calendarDay + 5) % 7) + 1 // Преобразование: ПН=2->1, ВС=1->7
                    } else 1
                }
            }
        }
        
        /**
         * Преобразует короткое название в ID
         */
        fun dayNameToId(dayName: String?): Int? {
            val normalized = normalizeDayName(dayName) ?: return null
            return when (normalized) {
                "Пн" -> 1
                "Вт" -> 2
                "Ср" -> 3
                "Чт" -> 4
                "Пт" -> 5
                "Сб" -> 6
                "Вс" -> 7
                else -> null
            }
        }
    }
}
