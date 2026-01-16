package com.example.raspisanie.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index
import androidx.room.ForeignKey

/**
 * Нормализованная таблица групп
 */
@Entity(
    tableName = "groups",
    foreignKeys = [
        ForeignKey(
            entity = CollegeEntity::class,
            parentColumns = ["id"],
            childColumns = ["collegeId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["name", "collegeId"]),
        Index(value = ["groupFile", "collegeId"], unique = true),
        Index(value = ["collegeId"]) // Индекс для foreign key
    ]
)
data class GroupEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    val name: String, // Название группы (ИСиП-23-1п)
    val groupFile: String, // Файл группы (cg36.htm)
    val collegeId: Long // ID колледжа (foreign key)
)
