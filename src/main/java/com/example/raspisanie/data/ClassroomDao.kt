package com.example.raspisanie.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * DAO для работы с аудиториями
 */
@Dao
interface ClassroomDao {
    @Query("SELECT * FROM classrooms WHERE name = :name LIMIT 1")
    suspend fun findByName(name: String): ClassroomEntity?
    
    @Query("SELECT * FROM classrooms WHERE id = :id")
    suspend fun getById(id: Long): ClassroomEntity?
    
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(classroom: ClassroomEntity): Long
    
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(classrooms: List<ClassroomEntity>): List<Long>
    
    /**
     * Получить или создать аудиторию по имени
     */
    suspend fun getOrCreate(name: String?): Long? {
        if (name.isNullOrBlank()) return null
        val existing = findByName(name)
        if (existing != null) {
            return existing.id
        }
        // Вставляем новую аудиторию
        val newId = insert(ClassroomEntity(name = name))
        // Если insert вернул -1 (из-за IGNORE), пытаемся найти снова
        return if (newId > 0) {
            newId
        } else {
            findByName(name)?.id
        }
    }
}
