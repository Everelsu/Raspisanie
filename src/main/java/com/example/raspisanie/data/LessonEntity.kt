package com.example.raspisanie.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index
import androidx.room.ForeignKey

/**
 * Entity для хранения всех пар (плановых и фактических) в базе данных
 * Использует нормализованные внешние ключи для оптимизации
 */
@Entity(
    tableName = "lessons",
    foreignKeys = [
        ForeignKey(
            entity = DayOfWeekEntity::class,
            parentColumns = ["id"],
            childColumns = ["dayId"],
            onDelete = ForeignKey.SET_NULL
        ),
        ForeignKey(
            entity = SubjectEntity::class,
            parentColumns = ["id"],
            childColumns = ["subjectId"],
            onDelete = ForeignKey.SET_NULL
        ),
        ForeignKey(
            entity = TeacherEntity::class,
            parentColumns = ["id"],
            childColumns = ["teacherId"],
            onDelete = ForeignKey.SET_NULL
        ),
        ForeignKey(
            entity = ClassroomEntity::class,
            parentColumns = ["id"],
            childColumns = ["classroomId"],
            onDelete = ForeignKey.SET_NULL
        ),
        ForeignKey(
            entity = GroupEntity::class,
            parentColumns = ["id"],
            childColumns = ["groupId"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [
        Index(value = ["date", "lessonNumber"]),
        Index(value = ["date"]),
        Index(value = ["lessonType"]),
        Index(value = ["dayId"]),
        Index(value = ["subjectId"]),
        Index(value = ["teacherId"]),
        Index(value = ["classroomId"]),
        Index(value = ["groupId"]),
        // Уникальный индекс для предотвращения дубликатов (дата + номер пары + тип + группа)
        Index(value = ["date", "lessonNumber", "lessonType", "groupId"], unique = true)
    ]
)
data class LessonEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    // Основная информация о паре
    val date: String, // Формат: dd.MM.yyyy
    val lessonNumber: Int, // Номер пары (1-10)
    
    // Тип занятия: "planned" (плановое) или "actual" (фактическое из журнала)
    val lessonType: String,
    
    // Нормализованные внешние ключи (вместо строк для оптимизации)
    val subjectId: Long? = null, // ID предмета (foreign key)
    val classroomId: Long? = null, // ID аудитории (foreign key)
    val teacherId: Long? = null, // ID преподавателя (foreign key)
    val subgroup: Int? = null, // Подгруппа (1, 2 или null)
    
    // Дополнительная информация для плановых занятий
    val dayId: Int? = null, // ID дня недели из таблицы day_of_week (1-7)
    val weekNumber: Int? = null, // Номер недели (1 или 2)
    
    // Метаданные
    val groupId: Long? = null, // ID группы (foreign key) для плановых занятий
    val journalFile: String? = null, // Файл журнала (j362.htm) для фактических (временно, можно нормализовать позже)
    val savedAt: Long = System.currentTimeMillis() // Время сохранения
) {
    /**
     * Преобразует Entity в ScheduleItem
     * Требует нормализованные данные для преобразования ID в строки
     */
    fun toScheduleItem(
        dayShortName: String? = null,
        subjectName: String? = null,
        teacherName: String? = null,
        classroomName: String? = null
    ): ScheduleItem {
        return ScheduleItem(
            day = dayShortName ?: "",
            date = date,
            weekNumber = weekNumber ?: 1,
            lessonNumber = lessonNumber,
            subject = subjectName,
            classroom = classroomName,
            teacher = teacherName,
            subgroup = subgroup
        )
    }
}
