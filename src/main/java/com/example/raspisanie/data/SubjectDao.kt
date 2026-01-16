package com.example.raspisanie.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * DAO для работы с предметами
 */
@Dao
interface SubjectDao {
    @Query("SELECT * FROM subjects WHERE name = :name LIMIT 1")
    suspend fun findByName(name: String): SubjectEntity?
    
    @Query("SELECT * FROM subjects WHERE id = :id")
    suspend fun getById(id: Long): SubjectEntity?
    
    @Query("SELECT * FROM subjects")
    suspend fun getAllSubjects(): List<SubjectEntity>
    
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(subject: SubjectEntity): Long
    
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(subjects: List<SubjectEntity>): List<Long>
    
    /**
     * Получить или создать предмет по имени
     */
    suspend fun getOrCreate(name: String?): Long? {
        if (name.isNullOrBlank()) return null
        val existing = findByName(name)
        if (existing != null) {
            return existing.id
        }
        // Вставляем новый предмет
        val newId = insert(SubjectEntity(name = name))
        // Если insert вернул -1 (из-за IGNORE), пытаемся найти снова
        return if (newId > 0) {
            newId
        } else {
            findByName(name)?.id
        }
    }
}
