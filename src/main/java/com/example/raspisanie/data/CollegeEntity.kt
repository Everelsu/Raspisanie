package com.example.raspisanie.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index

/**
 * Нормализованная таблица колледжей
 */
@Entity(
    tableName = "colleges",
    indices = [Index(value = ["code"], unique = true)]
)
data class CollegeEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    val name: String, // Полное название (ЧТОТиБ, ЗабГК)
    val code: String // Код (chtotib, zabgc)
) {
    companion object {
        const val CODE_CHTOTIB = "chtotib"
        const val CODE_ZABGC = "zabgc"
        
        /**
         * Получить колледжи по умолчанию
         */
        fun getDefaultColleges(): List<CollegeEntity> {
            return listOf(
                CollegeEntity(1, "ЧТОТиБ", CODE_CHTOTIB),
                CollegeEntity(2, "ЗабГК", CODE_ZABGC)
            )
        }
    }
}
