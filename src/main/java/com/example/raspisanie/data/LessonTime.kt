package com.example.raspisanie.data

data class LessonTime(
    val number: Int,
    val startTime: String,
    val endTime: String
)

object LessonTimes {
    private val timesCHTOTIB = mapOf(
        1 to LessonTime(1, "8:15", "9:15"),
        2 to LessonTime(2, "9:25", "10:25"),
        3 to LessonTime(3, "10:35", "11:35"),
        4 to LessonTime(4, "12:15", "13:15"),
        5 to LessonTime(5, "13:25", "14:25"),
        6 to LessonTime(6, "14:35", "15:35"),
        7 to LessonTime(7, "16:05", "17:05"),
        8 to LessonTime(8, "17:15", "18:15")
    )
    private val lunchesCHTOTIB = mapOf(
        3 to "Обед: 11:35 - 12:15",
        6 to "Обед: 15:35 - 16:05"
    )
    // Перемены между парами (между указанными парами)
    private val breaksCHTOTIB = mapOf(
        Pair(1, 2) to "Перемена: 9:15 - 9:25",
        Pair(2, 3) to "Перемена: 10:25 - 10:35",
        Pair(3, 4) to null, // Здесь обед
        Pair(4, 5) to "Перемена: 13:15 - 13:25",
        Pair(5, 6) to "Перемена: 14:25 - 14:35",
        Pair(6, 7) to null, // Здесь обед
        Pair(7, 8) to "Перемена: 17:05 - 17:15"
    )
    
    // ЗабГК (по умолчанию совпадает, при необходимости обновить конкретными временами)
    private val timesZABGK = timesCHTOTIB
    private val lunchesZABGK = lunchesCHTOTIB
    private val breaksZABGK = breaksCHTOTIB
    
    fun getTime(institute: String, lessonNumber: Int): LessonTime? =
        when (institute) {
            PreferencesManager.INSTITUTE_ZABGK -> timesZABGK[lessonNumber]
            else -> timesCHTOTIB[lessonNumber]
        }
    
    fun getBreakText(institute: String, beforeLesson: Int, afterLesson: Int): String? =
        when (institute) {
            PreferencesManager.INSTITUTE_ZABGK -> breaksZABGK[Pair(beforeLesson, afterLesson)]
            else -> breaksCHTOTIB[Pair(beforeLesson, afterLesson)]
        }
    
    fun getLunchText(institute: String, afterLesson: Int): String? =
        when (institute) {
            PreferencesManager.INSTITUTE_ZABGK -> lunchesZABGK[afterLesson]
            else -> lunchesCHTOTIB[afterLesson]
        }
    
    fun formatTime(institute: String, lessonNumber: Int): String {
        val time = getTime(institute, lessonNumber)
        return if (time != null) {
            "${time.startTime} - ${time.endTime}"
        } else {
            ""
        }
    }

    // Backwards-compatible helpers (default to ЧТОТиБ)
    fun getTime(lessonNumber: Int): LessonTime? = getTime(PreferencesManager.INSTITUTE_CHTOTIB, lessonNumber)
    fun getBreakText(beforeLesson: Int, afterLesson: Int): String? = getBreakText(PreferencesManager.INSTITUTE_CHTOTIB, beforeLesson, afterLesson)
    fun getLunchText(afterLesson: Int): String? = getLunchText(PreferencesManager.INSTITUTE_CHTOTIB, afterLesson)
    fun formatTime(lessonNumber: Int): String = formatTime(PreferencesManager.INSTITUTE_CHTOTIB, lessonNumber)
}

