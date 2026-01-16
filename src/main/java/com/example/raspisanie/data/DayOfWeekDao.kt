package com.example.raspisanie.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * DAO для работы с днями недели
 */
@Dao
interface DayOfWeekDao {
    /**
     * Получить все дни недели
     */
    @Query("SELECT * FROM day_of_week ORDER BY id ASC")
    suspend fun getAllDays(): List<DayOfWeekEntity>
    
    /**
     * Получить день недели по ID
     */
    @Query("SELECT * FROM day_of_week WHERE id = :id")
    suspend fun getDayById(id: Int): DayOfWeekEntity?
    
    /**
     * Получить день недели по короткому названию
     */
    @Query("SELECT * FROM day_of_week WHERE shortName = :shortName LIMIT 1")
    suspend fun getDayByShortName(shortName: String): DayOfWeekEntity?
    
    /**
     * Вставить или обновить день недели
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDay(day: DayOfWeekEntity)
    
    /**
     * Вставить несколько дней недели
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDays(days: List<DayOfWeekEntity>)
    
    /**
     * Инициализировать таблицу днями недели по умолчанию
     */
    suspend fun initializeDefaultDays() {
        insertDays(DayOfWeekEntity.getDefaultDays())
    }
}
