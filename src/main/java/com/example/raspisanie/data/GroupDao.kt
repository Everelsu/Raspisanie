package com.example.raspisanie.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/**
 * DAO для работы с группами
 */
@Dao
interface GroupDao {
    @Query("SELECT * FROM groups WHERE groupFile = :groupFile AND collegeId = :collegeId LIMIT 1")
    suspend fun findByFileAndCollege(groupFile: String, collegeId: Long): GroupEntity?
    
    @Query("SELECT * FROM groups WHERE id = :id")
    suspend fun getById(id: Long): GroupEntity?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(group: GroupEntity): Long
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(groups: List<GroupEntity>): List<Long>
    
    /**
     * Получить или создать группу
     */
    suspend fun getOrCreate(name: String, groupFile: String, collegeId: Long): Long {
        val existing = findByFileAndCollege(groupFile, collegeId)
        return if (existing != null) {
            existing.id
        } else {
            insert(GroupEntity(name = name, groupFile = groupFile, collegeId = collegeId))
        }
    }
}
