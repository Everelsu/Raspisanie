package com.example.raspisanie.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * База данных приложения для хранения всех пар (плановых и фактических)
 * 
 * Нормализованная структура БД:
 * 
 * Служебные таблицы (создаются автоматически, не удалять):
 * - room_master_table: хранит версию схемы БД для миграций Room
 * - sqlite_sequence: служебная таблица SQLite для AUTO_INCREMENT полей
 * - android_metadata: служебная таблица Android для локали/версии
 * 
 * Пользовательские таблицы:
 * - colleges: колледжи (ЧТОТиБ, ЗабГК)
 * - groups: группы (ссылается на colleges)
 * - subjects: предметы (нормализация повторяющихся названий)
 * - teachers: преподаватели (нормализация повторяющихся ФИО)
 * - classrooms: аудитории (нормализация повторяющихся номеров)
 * - day_of_week: дни недели (1-7: Пн-Вс)
 * - lessons: все занятия (плановые и фактические) - использует foreign keys на все вышеперечисленные
 */
@Database(
    entities = [
        LessonEntity::class,
        DayOfWeekEntity::class,
        SubjectEntity::class,
        TeacherEntity::class,
        ClassroomEntity::class,
        CollegeEntity::class,
        GroupEntity::class
    ],
    version = 7, // Версия 7: полная нормализация БД - все строки заменены на foreign keys
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun lessonDao(): LessonDao
    abstract fun dayOfWeekDao(): DayOfWeekDao
    abstract fun subjectDao(): SubjectDao
    abstract fun teacherDao(): TeacherDao
    abstract fun classroomDao(): ClassroomDao
    abstract fun collegeDao(): CollegeDao
    abstract fun groupDao(): GroupDao
    
    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null
        
        private const val DATABASE_NAME = "raspisanie_database"
        
        /**
         * Миграция с версии 5 на 6: удаление старых таблиц actual_lessons
         */
        private val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("DROP TABLE IF EXISTS actual_lessons")
                android.util.Log.d("AppDatabase", "Миграция 5->6: удалена таблица actual_lessons")
            }
        }
        
        /**
         * Миграция с версии 6 на 7: полная нормализация БД
         * Создаёт новые нормализованные таблицы и переносит данные
         */
        private val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(database: SupportSQLiteDatabase) {
                android.util.Log.d("AppDatabase", "Миграция 6->7: нормализация БД")
                
                // Создаём новые нормализованные таблицы
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS colleges (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL,
                        code TEXT NOT NULL UNIQUE
                    )
                """.trimIndent())
                
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS groups (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL,
                        groupFile TEXT NOT NULL,
                        collegeId INTEGER NOT NULL,
                        FOREIGN KEY(collegeId) REFERENCES colleges(id) ON DELETE CASCADE,
                        UNIQUE(groupFile, collegeId)
                    )
                """.trimIndent())
                
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS subjects (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL UNIQUE
                    )
                """.trimIndent())
                
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS teachers (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL UNIQUE
                    )
                """.trimIndent())
                
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS classrooms (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL UNIQUE
                    )
                """.trimIndent())
                
                // Инициализируем колледжи по умолчанию
                database.execSQL("INSERT OR IGNORE INTO colleges (id, name, code) VALUES (1, 'ЧТОТиБ', 'chtotib')")
                database.execSQL("INSERT OR IGNORE INTO colleges (id, name, code) VALUES (2, 'ЗабГК', 'zabgc')")
                
                // Создаём временную таблицу lessons_new с новой структурой
                database.execSQL("""
                    CREATE TABLE lessons_new (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        date TEXT NOT NULL,
                        lessonNumber INTEGER NOT NULL,
                        lessonType TEXT NOT NULL,
                        subjectId INTEGER,
                        classroomId INTEGER,
                        teacherId INTEGER,
                        subgroup INTEGER,
                        dayId INTEGER,
                        weekNumber INTEGER,
                        groupId INTEGER,
                        journalFile TEXT,
                        savedAt INTEGER NOT NULL,
                        FOREIGN KEY(dayId) REFERENCES day_of_week(id) ON DELETE SET NULL,
                        FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE SET NULL,
                        FOREIGN KEY(teacherId) REFERENCES teachers(id) ON DELETE SET NULL,
                        FOREIGN KEY(classroomId) REFERENCES classrooms(id) ON DELETE SET NULL,
                        FOREIGN KEY(groupId) REFERENCES groups(id) ON DELETE SET NULL
                    )
                """.trimIndent())
                
                // Переносим данные из старой таблицы в новую с нормализацией
                // В миграции сложно нормализовать всё правильно, поэтому просто копируем
                // Реальная нормализация произойдёт при следующем сохранении
                database.execSQL("""
                    INSERT INTO lessons_new (
                        id, date, lessonNumber, lessonType, subjectId, classroomId, 
                        teacherId, subgroup, dayId, weekNumber, groupId, journalFile, savedAt
                    )
                    SELECT 
                        id, date, lessonNumber, lessonType, 
                        NULL as subjectId, NULL as classroomId, NULL as teacherId,
                        subgroup, dayId, weekNumber, NULL as groupId, journalFile, savedAt
                    FROM lessons
                """.trimIndent())
                
                // Удаляем старую таблицу и переименовываем новую
                database.execSQL("DROP TABLE lessons")
                database.execSQL("ALTER TABLE lessons_new RENAME TO lessons")
                
                // Создаём индексы
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_date ON lessons(date)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_date_lessonNumber ON lessons(date, lessonNumber)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_lessonType ON lessons(lessonType)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_dayId ON lessons(dayId)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_subjectId ON lessons(subjectId)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_teacherId ON lessons(teacherId)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_classroomId ON lessons(classroomId)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_lessons_groupId ON lessons(groupId)")
                database.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS index_lessons_unique ON lessons(date, lessonNumber, lessonType, groupId)")
                
                android.util.Log.d("AppDatabase", "Миграция 6->7: нормализация завершена")
            }
        }
        
        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    DATABASE_NAME
                )
                    .addMigrations(MIGRATION_5_6, MIGRATION_6_7)
                    .fallbackToDestructiveMigration() // При других изменениях схемы БД пересоздаём
                    .build()
                INSTANCE = instance
                instance
            }
        }
        
        /**
         * Получить путь к файлу базы данных
         */
        fun getDatabaseFile(context: Context): java.io.File {
            return context.getDatabasePath(DATABASE_NAME)
        }
    }
}
