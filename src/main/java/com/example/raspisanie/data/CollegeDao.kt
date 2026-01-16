package com.example.raspisanie.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * DAO для работы с колледжами
 */
@Dao
interface CollegeDao {
    @Query("SELECT * FROM colleges")
    suspend fun getAll(): List<CollegeEntity>
    
    @Query("SELECT * FROM colleges WHERE code = :code LIMIT 1")
    suspend fun findByCode(code: String): CollegeEntity?
    
    @Query("SELECT * FROM colleges WHERE id = :id")
    suspend fun getById(id: Long): CollegeEntity?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(college: CollegeEntity): Long
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(colleges: List<CollegeEntity>): List<Long>
    
    /**
     * Инициализировать колледжи по умолчанию
     */
    suspend fun initializeDefaultColleges() {
        val existing = getAll()
        if (existing.isEmpty()) {
            insertAll(CollegeEntity.getDefaultColleges())
        }
    }
    
    /**
     * Получить или создать колледж по коду
     */
    suspend fun getOrCreate(code: String, name: String? = null): Long {
        val existing = findByCode(code)
        return if (existing != null) {
            existing.id
        } else {
            insert(CollegeEntity(name = name ?: code, code = code))
        }
    }
}
