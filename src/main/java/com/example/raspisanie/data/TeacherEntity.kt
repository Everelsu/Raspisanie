package com.example.raspisanie.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index

/**
 * Нормализованная таблица преподавателей
 */
@Entity(
    tableName = "teachers",
    indices = [Index(value = ["name"], unique = true)]
)
data class TeacherEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    val name: String // ФИО преподавателя
)
