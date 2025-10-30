package com.example.raspisanie.data

data class LessonTime(
    val number: Int,
    val startTime: String,
    val endTime: String
)

object LessonTimes {
    val times = mapOf(
        1 to LessonTime(1, "8:15", "9:15"),
        2 to LessonTime(2, "9:25", "10:25"),
        3 to LessonTime(3, "10:35", "11:35"),
        4 to LessonTime(4, "12:15", "13:15"),
        5 to LessonTime(5, "13:25", "14:25"),
        6 to LessonTime(6, "14:35", "15:35"),
        7 to LessonTime(7, "16:05", "17:05"),
        8 to LessonTime(8, "17:15", "18:15")
    )
    
    // Обеды (после указанной пары)
    val lunches = mapOf(
        3 to "Обед: 11:35 - 12:15",
        6 to "Обед: 15:35 - 16:05"
    )
    
    // Перемены между парами (между указанными парами)
    private val breaks = mapOf(
        Pair(1, 2) to "Перемена: 9:15 - 9:25",
        Pair(2, 3) to "Перемена: 10:25 - 10:35",
        Pair(3, 4) to null, // Здесь обед
        Pair(4, 5) to "Перемена: 13:15 - 13:25",
        Pair(5, 6) to "Перемена: 14:25 - 14:35",
        Pair(6, 7) to null, // Здесь обед
        Pair(7, 8) to "Перемена: 17:05 - 17:15"
    )
    
    fun getTime(lessonNumber: Int): LessonTime? = times[lessonNumber]
    
    fun getBreakText(beforeLesson: Int, afterLesson: Int): String? {
        return breaks[Pair(beforeLesson, afterLesson)]
    }
    
    fun getLunchText(afterLesson: Int): String? = lunches[afterLesson]
    
    fun formatTime(lessonNumber: Int): String {
        val time = getTime(lessonNumber)
        return if (time != null) {
            "${time.startTime} - ${time.endTime}"
        } else {
            ""
        }
    }
}

