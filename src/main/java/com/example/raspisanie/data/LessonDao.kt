package com.example.raspisanie.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

/**
 * DAO для работы с уроками (плановыми и фактическими)
 */
@Dao
interface LessonDao {
    /**
     * Получить все занятия за конкретную дату (и плановые, и фактические)
     */
    @Query("SELECT * FROM lessons WHERE date = :date ORDER BY lessonNumber ASC")
    suspend fun getLessonsByDate(date: String): List<LessonEntity>
    
    /**
     * Получить занятия за дату с фильтром по группе
     */
    @Query("SELECT * FROM lessons WHERE date = :date AND groupId = :groupId ORDER BY lessonNumber ASC")
    suspend fun getLessonsByDateAndGroup(date: String, groupId: Long): List<LessonEntity>
    
    /**
     * Получить занятия за дату с фильтром по типу
     */
    @Query("SELECT * FROM lessons WHERE date = :date AND lessonType = :type ORDER BY lessonNumber ASC")
    suspend fun getLessonsByDateAndType(date: String, type: String): List<LessonEntity>
    
    /**
     * Получить все занятия в диапазоне дат
     */
    @Query("""
        SELECT * FROM lessons 
        WHERE date >= :startDate AND date <= :endDate 
        ORDER BY date ASC, lessonNumber ASC
    """)
    suspend fun getLessonsByDateRange(startDate: String, endDate: String): List<LessonEntity>
    
    /**
     * Получить все уникальные даты, для которых есть занятия
     */
    @Query("SELECT DISTINCT date FROM lessons ORDER BY date ASC")
    suspend fun getAllDates(): List<String>
    
    /**
     * Получить даты с фильтром по типу
     */
    @Query("SELECT DISTINCT date FROM lessons WHERE lessonType = :type ORDER BY date ASC")
    suspend fun getDatesByType(type: String): List<String>
    
    /**
     * Получить все занятия (Flow для наблюдения)
     */
    @Query("SELECT * FROM lessons ORDER BY date DESC, lessonNumber ASC")
    fun getAllLessons(): Flow<List<LessonEntity>>
    
    /**
     * Получить занятия по типу (Flow)
     */
    @Query("SELECT * FROM lessons WHERE lessonType = :type ORDER BY date DESC, lessonNumber ASC")
    fun getLessonsByType(type: String): Flow<List<LessonEntity>>
    
    /**
     * Вставить или обновить занятия
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertLessons(lessons: List<LessonEntity>)
    
    /**
     * Вставить одно занятие
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertLesson(lesson: LessonEntity)
    
    /**
     * Удалить занятия за конкретную дату
     */
    @Query("DELETE FROM lessons WHERE date = :date")
    suspend fun deleteLessonsByDate(date: String)
    
    /**
     * Удалить занятия за дату по типу
     */
    @Query("DELETE FROM lessons WHERE date = :date AND lessonType = :type")
    suspend fun deleteLessonsByDateAndType(date: String, type: String)
    
    /**
     * Удалить все занятия
     */
    @Query("DELETE FROM lessons")
    suspend fun deleteAllLessons()
    
    /**
     * Удалить занятия по типу
     */
    @Query("DELETE FROM lessons WHERE lessonType = :type")
    suspend fun deleteLessonsByType(type: String)
    
    /**
     * Удалить старые занятия (старше указанной даты)
     */
    @Query("DELETE FROM lessons WHERE date < :date")
    suspend fun deleteLessonsOlderThan(date: String)
    
    /**
     * Получить количество занятий
     */
    @Query("SELECT COUNT(*) FROM lessons")
    suspend fun getCount(): Int
    
    /**
     * Получить количество занятий по типу
     */
    @Query("SELECT COUNT(*) FROM lessons WHERE lessonType = :type")
    suspend fun getCountByType(type: String): Int
    
    /**
     * Получить самую раннюю дату
     */
    @Query("SELECT MIN(date) FROM lessons")
    suspend fun getOldestDate(): String?
    
    /**
     * Получить самую позднюю дату
     */
    @Query("SELECT MAX(date) FROM lessons")
    suspend fun getNewestDate(): String?
    
    /**
     * Получить статистику по датам
     */
    @Query("""
        SELECT 
            COUNT(*) as total,
            COUNT(DISTINCT date) as datesCount,
            MIN(date) as oldestDate,
            MAX(date) as newestDate
        FROM lessons
    """)
    suspend fun getStatistics(): LessonStatistics
    
    /**
     * Получить занятия по ID предмета
     */
    @Query("SELECT * FROM lessons WHERE subjectId = :subjectId ORDER BY date DESC, lessonNumber ASC")
    suspend fun getLessonsBySubjectId(subjectId: Long): List<LessonEntity>
    
    /**
     * Получить занятия по ID преподавателя
     */
    @Query("SELECT * FROM lessons WHERE teacherId = :teacherId ORDER BY date DESC, lessonNumber ASC")
    suspend fun getLessonsByTeacherId(teacherId: Long): List<LessonEntity>
    
    /**
     * Поиск занятий по предмету (используется через SubjectDao - для обратной совместимости)
     * @deprecated Используйте поиск через SubjectDao
     */
    @Deprecated("Используйте поиск через SubjectDao и getLessonsBySubjectId")
    @Query("""
        SELECT * FROM lessons 
        WHERE subjectId IN (SELECT id FROM subjects WHERE name LIKE '%' || :query || '%') 
        ORDER BY date DESC, lessonNumber ASC
    """)
    suspend fun searchLessonsBySubject(query: String): List<LessonEntity>
    
    /**
     * Поиск занятий по преподавателю (используется через TeacherDao - для обратной совместимости)
     * @deprecated Используйте поиск через TeacherDao
     */
    @Deprecated("Используйте поиск через TeacherDao и getLessonsByTeacherId")
    @Query("""
        SELECT * FROM lessons 
        WHERE teacherId IN (SELECT id FROM teachers WHERE name LIKE '%' || :query || '%') 
        ORDER BY date DESC, lessonNumber ASC
    """)
    suspend fun searchLessonsByTeacher(query: String): List<LessonEntity>
}

/**
 * Статистика по занятиям (базовая)
 */
data class LessonStatistics(
    val total: Int,
    val datesCount: Int,
    val oldestDate: String?,
    val newestDate: String?
)

/**
 * Детальная статистика по занятиям с размером БД и разбивкой по типам
 */
data class DetailedLessonStatistics(
    val total: Int,
    val datesCount: Int,
    val oldestDate: String?,
    val newestDate: String?,
    val plannedCount: Int,
    val actualCount: Int,
    val databaseSizeBytes: Long
)
