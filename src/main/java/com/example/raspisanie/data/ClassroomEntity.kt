package com.example.raspisanie.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index

/**
 * Нормализованная таблица аудиторий
 */
@Entity(
    tableName = "classrooms",
    indices = [Index(value = ["name"], unique = true)]
)
data class ClassroomEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    val name: String // Номер/название аудитории
)
