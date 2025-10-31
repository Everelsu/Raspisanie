package com.example.raspisanie.data

data class LessonTime(
    val number: Int,
    val startTime: String,
    val endTime: String
)

object LessonTimes {
    // Расписание для ЧТОТиБ
    private val timesChtotib = mapOf(
        1 to LessonTime(1, "8:15", "9:15"),
        2 to LessonTime(2, "9:25", "10:25"),
        3 to LessonTime(3, "10:35", "11:35"),
        4 to LessonTime(4, "12:15", "13:15"),
        5 to LessonTime(5, "13:25", "14:25"),
        6 to LessonTime(6, "14:35", "15:35"),
        7 to LessonTime(7, "16:05", "17:05"),
        8 to LessonTime(8, "17:15", "18:15")
    )
    
    // Расписание для ЗабГК
    private val timesZabgc = mapOf(
        1 to LessonTime(1, "8:30", "10:05"),
        2 to LessonTime(2, "10:15", "11:50"),
        3 to LessonTime(3, "12:30", "14:05"),
        4 to LessonTime(4, "14:15", "15:50"),
        5 to LessonTime(5, "16:00", "17:35"),
        6 to LessonTime(6, "17:45", "19:20")
    )
    
    // Обеды для ЧТОТиБ (после указанной пары)
    private val lunchesChtotib = mapOf(
        3 to "Обед: 11:35 - 12:15",
        6 to "Обед: 15:35 - 16:05"
    )
    
    // Обеды для ЗабГК (после указанной пары)
    private val lunchesZabgc = mapOf(
        2 to "Обед: 11:50 - 12:30"
    )
    
    // Перемены между парами для ЧТОТиБ
    private val breaksChtotib = mapOf(
        Pair(1, 2) to "Перемена: 9:15 - 9:25",
        Pair(2, 3) to "Перемена: 10:25 - 10:35",
        Pair(3, 4) to null, // Здесь обед
        Pair(4, 5) to "Перемена: 13:15 - 13:25",
        Pair(5, 6) to "Перемена: 14:25 - 14:35",
        Pair(6, 7) to null, // Здесь обед
        Pair(7, 8) to "Перемена: 17:05 - 17:15"
    )
    
    // Перемены между парами для ЗабГК
    private val breaksZabgc = mapOf(
        Pair(1, 2) to "Перемена: 10:05 - 10:15",
        Pair(2, 3) to null, // Здесь обед
        Pair(3, 4) to "Перемена: 14:05 - 14:15",
        Pair(4, 5) to "Перемена: 15:50 - 16:00",
        Pair(5, 6) to "Перемена: 17:35 - 17:45"
    )
    
    private fun getTimesForCollege(college: String): Map<Int, LessonTime> {
        return if (college == PreferencesManager.COLLEGE_ZABGC) {
            timesZabgc
        } else {
            timesChtotib
        }
    }
    
    private fun getBreaksForCollege(college: String): Map<Pair<Int, Int>, String?> {
        return if (college == PreferencesManager.COLLEGE_ZABGC) {
            breaksZabgc
        } else {
            breaksChtotib
        }
    }
    
    private fun getLunchesForCollege(college: String): Map<Int, String> {
        return if (college == PreferencesManager.COLLEGE_ZABGC) {
            lunchesZabgc
        } else {
            lunchesChtotib
        }
    }
    
    fun getTime(lessonNumber: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): LessonTime? {
        return getTimesForCollege(college)[lessonNumber]
    }
    
    fun getBreakText(beforeLesson: Int, afterLesson: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): String? {
        return getBreaksForCollege(college)[Pair(beforeLesson, afterLesson)]
    }
    
    fun getLunchText(afterLesson: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): String? {
        return getLunchesForCollege(college)[afterLesson]
    }
    
    fun formatTime(lessonNumber: Int, college: String = PreferencesManager.COLLEGE_CHTOTIB): String {
        val time = getTime(lessonNumber, college)
        return if (time != null) {
            "${time.startTime} - ${time.endTime}"
        } else {
            ""
        }
    }
    
    // Для обратной совместимости - использует ЧТОТиБ по умолчанию
    @Deprecated("Use getTime(lessonNumber, college) instead", ReplaceWith("getTime(lessonNumber, PreferencesManager.COLLEGE_CHTOTIB)"))
    fun getTime(lessonNumber: Int): LessonTime? = timesChtotib[lessonNumber]
    
    @Deprecated("Use getBreakText(beforeLesson, afterLesson, college) instead", ReplaceWith("getBreakText(beforeLesson, afterLesson, PreferencesManager.COLLEGE_CHTOTIB)"))
    fun getBreakText(beforeLesson: Int, afterLesson: Int): String? {
        return breaksChtotib[Pair(beforeLesson, afterLesson)]
    }
    
    @Deprecated("Use getLunchText(afterLesson, college) instead", ReplaceWith("getLunchText(afterLesson, PreferencesManager.COLLEGE_CHTOTIB)"))
    fun getLunchText(afterLesson: Int): String? = lunchesChtotib[afterLesson]
    
    @Deprecated("Use formatTime(lessonNumber, college) instead", ReplaceWith("formatTime(lessonNumber, PreferencesManager.COLLEGE_CHTOTIB)"))
    fun formatTime(lessonNumber: Int): String {
        val time = timesChtotib[lessonNumber]
        return if (time != null) {
            "${time.startTime} - ${time.endTime}"
        } else {
            ""
        }
    }
}

