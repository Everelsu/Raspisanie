package com.example.raspisanie.data

data class ScheduleItem(
    val day: String,
    val date: String,
    val weekNumber: Int,
    val lessonNumber: Int,
    val subject: String?,
    val classroom: String?,
    val teacher: String?,
    val subgroup: Int? = null // 1 or 2 for different subgroups
)

data class DaySchedule(
    val day: String,
    val date: String,
    val weekNumber: Int,
    val items: List<ScheduleItem>
)

