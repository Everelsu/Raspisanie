package com.example.raspisanie.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * DAO для работы с преподавателями
 */
@Dao
interface TeacherDao {
    @Query("SELECT * FROM teachers WHERE name = :name LIMIT 1")
    suspend fun findByName(name: String): TeacherEntity?
    
    @Query("SELECT * FROM teachers WHERE id = :id")
    suspend fun getById(id: Long): TeacherEntity?
    
    @Query("SELECT * FROM teachers")
    suspend fun getAllTeachers(): List<TeacherEntity>
    
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(teacher: TeacherEntity): Long
    
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(teachers: List<TeacherEntity>): List<Long>
    
    /**
     * Получить или создать преподавателя по имени
     */
    suspend fun getOrCreate(name: String?): Long? {
        if (name.isNullOrBlank()) return null
        val existing = findByName(name)
        if (existing != null) {
            return existing.id
        }
        // Вставляем нового преподавателя
        val newId = insert(TeacherEntity(name = name))
        // Если insert вернул -1 (из-за IGNORE), пытаемся найти снова
        return if (newId > 0) {
            newId
        } else {
            findByName(name)?.id
        }
    }
}
