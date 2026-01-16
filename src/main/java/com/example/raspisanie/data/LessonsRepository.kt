package com.example.raspisanie.data

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import com.google.gson.Gson
import com.google.gson.GsonBuilder

/**
 * Репозиторий для работы с уроками (плановыми и фактическими)
 * Использует нормализованную структуру БД для оптимизации
 */
class LessonsRepository(private val context: Context) {
    private val database = AppDatabase.getDatabase(context)
    private val dao = database.lessonDao()
    private val dayDao = database.dayOfWeekDao()
    private val subjectDao = database.subjectDao()
    private val teacherDao = database.teacherDao()
    private val classroomDao = database.classroomDao()
    private val collegeDao = database.collegeDao()
    private val groupDao = database.groupDao()
    private val prefs = PreferencesManager(context)
    
    companion object {
        private const val TAG = "LessonsRepository"
    }
    
    /**
     * Инициализирует нормализованные таблицы, если они пустые
     */
    suspend fun initializeNormalizedTables() = withContext(Dispatchers.IO) {
        try {
            // Инициализируем дни недели
            val existingDays = dayDao.getAllDays()
            if (existingDays.isEmpty()) {
                dayDao.initializeDefaultDays()
                Log.d(TAG, "Инициализирована таблица дней недели")
            }
            
            // Инициализируем колледжи
            collegeDao.initializeDefaultColleges()
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка инициализации нормализованных таблиц", e)
        }
    }
    
    /**
     * Инициализирует таблицу дней недели, если она пустая (для обратной совместимости)
     */
    suspend fun initializeDaysOfWeek() = initializeNormalizedTables()
    
    /**
     * Получить короткое название дня по ID
     */
    private suspend fun getDayShortName(dayId: Int?): String? {
        if (dayId == null) return null
        return dayDao.getDayById(dayId)?.shortName
    }
    
    /**
     * Получить название предмета по ID
     */
    private suspend fun getSubjectName(subjectId: Long?): String? {
        if (subjectId == null) return null
        return subjectDao.getById(subjectId)?.name
    }
    
    /**
     * Получить ФИО преподавателя по ID
     */
    private suspend fun getTeacherName(teacherId: Long?): String? {
        if (teacherId == null) return null
        return teacherDao.getById(teacherId)?.name
    }
    
    /**
     * Получить номер аудитории по ID
     */
    private suspend fun getClassroomName(classroomId: Long?): String? {
        if (classroomId == null) return null
        return classroomDao.getById(classroomId)?.name
    }
    
    /**
     * Преобразует LessonEntity в ScheduleItem с загрузкой связанных данных
     */
    private suspend fun LessonEntity.toScheduleItemWithRelations(): ScheduleItem {
        val dayShortName = if (dayId != null) getDayShortName(dayId) else null
        val subjectName = if (subjectId != null) getSubjectName(subjectId) else null
        val teacherName = if (teacherId != null) getTeacherName(teacherId) else null
        val classroomName = if (classroomId != null) getClassroomName(classroomId) else null
        
        return toScheduleItem(dayShortName, subjectName, teacherName, classroomName)
    }
    
    /**
     * Создает LessonEntity из ScheduleItem с нормализацией данных через DAO
     */
    private suspend fun ScheduleItem.toLessonEntity(
        lessonType: String,
        groupId: Long? = null,
        dayId: Int? = null,
        journalFile: String? = null
    ): LessonEntity {
        // Нормализуем день недели
        val normalizedDayId = dayId ?: if (day.isNotEmpty()) {
            val normalizedDay = DayOfWeekEntity.normalizeDayName(day)
            DayOfWeekEntity.dayNameToId(normalizedDay)
        } else null
        
        // Получаем или создаём ID для нормализованных данных
        val normalizedSubjectId = subject?.let { 
            val id = subjectDao.getOrCreate(it)
            if (id == null) {
                android.util.Log.w(TAG, "Не удалось создать/найти предмет: $it")
            }
            id
        }
        val normalizedTeacherId = teacher?.let { 
            val id = teacherDao.getOrCreate(it)
            if (id == null) {
                android.util.Log.w(TAG, "Не удалось создать/найти преподавателя: $it")
            }
            id
        }
        val normalizedClassroomId = classroom?.let { 
            val id = classroomDao.getOrCreate(it)
            if (id == null) {
                android.util.Log.w(TAG, "Не удалось создать/найти аудиторию: $it")
            }
            id
        }
        
        return LessonEntity(
            date = date,
            lessonNumber = lessonNumber,
            lessonType = lessonType,
            subjectId = normalizedSubjectId,
            classroomId = normalizedClassroomId,
            teacherId = normalizedTeacherId,
            subgroup = subgroup,
            dayId = normalizedDayId,
            weekNumber = weekNumber,
            groupId = groupId,
            journalFile = journalFile
        )
    }
    
    /**
     * Сохранить плановые занятия из расписания
     * Учитывает замены: удаляет только плановые занятия для текущей группы/колледжа,
     * чтобы не затрагивать занятия других групп при смене расписания
     */
    suspend fun savePlannedLessons(
        schedules: List<DaySchedule>,
        groupFile: String,
        college: String,
        groupName: String? = null
    ) = withContext(Dispatchers.IO) {
        try {
            // Инициализируем нормализованные таблицы при первом сохранении
            initializeNormalizedTables()
            
            // Получаем или создаём колледж
            val collegeId = collegeDao.getOrCreate(college, college)
            Log.d(TAG, "Колледж $college -> ID: $collegeId")
            
            // Получаем или создаём группу (используем groupFile как название, если groupName не указано)
            val finalGroupName = groupName ?: groupFile.replace(".htm", "").replace("cg", "").uppercase()
            val groupId = groupDao.getOrCreate(finalGroupName, groupFile, collegeId)
            Log.d(TAG, "Группа $finalGroupName ($groupFile) -> ID: $groupId")
            
            val lessons = mutableListOf<LessonEntity>()
            
            for (schedule in schedules) {
                // Нормализуем день недели из расписания
                val normalizedDay = DayOfWeekEntity.normalizeDayName(schedule.day)
                val dayId = DayOfWeekEntity.dayNameToId(normalizedDay)
                
                for (item in schedule.items) {
                    // Преобразуем ScheduleItem в LessonEntity с нормализацией
                    lessons.add(
                        item.toLessonEntity(
                            lessonType = "planned",
                            groupId = groupId,
                            dayId = dayId
                        )
                    )
                }
            }
            
            if (lessons.isNotEmpty()) {
                // Получаем даты новых занятий
                val dates = lessons.map { it.date }.distinct()
                
                // Удаляем только плановые занятия для ТЕКУЩЕЙ группы за эти даты
                // Это важно при смене расписания - не удаляем занятия других групп
                for (date in dates) {
                    // Получаем все плановые занятия за дату
                    val existingPlanned = dao.getLessonsByDateAndType(date, "planned")
                    
                    // Фильтруем: оставляем только те, что НЕ относятся к текущей группе
                    val toKeep = existingPlanned.filter { 
                        it.groupId != groupId
                    }
                    
                    // Если есть занятия для других групп - пересохраняем их
                    if (toKeep.isNotEmpty() || existingPlanned.any { 
                        it.groupId == groupId 
                    }) {
                        // Удаляем все плановые за дату и сохраняем обратно только чужие
                        dao.deleteLessonsByDateAndType(date, "planned")
                        if (toKeep.isNotEmpty()) {
                            dao.insertLessons(toKeep)
                        }
                    }
                }
                
                // Фильтруем дубликаты перед сохранением
                // Создаем Set для проверки уникальности по ключевым полям (date + lessonNumber + groupId)
                // ВАЖНО: проверяем ПОСЛЕ удаления старых занятий, чтобы не учитывать уже удалённые
                val existingLessonsSet = mutableSetOf<String>()
                for (date in dates) {
                    val existing = dao.getLessonsByDateAndType(date, "planned")
                        .filter { it.groupId == groupId }
                    existingLessonsSet.addAll(
                        existing.map { "${it.date}_${it.lessonNumber}_${it.groupId}" }
                    )
                }
                Log.d(TAG, "Найдено ${existingLessonsSet.size} существующих занятий для группы $groupId")
                
                // Фильтруем новые занятия - убираем те, что уже есть в БД
                val lessonsToSave = lessons.filter { lesson ->
                    val key = "${lesson.date}_${lesson.lessonNumber}_${lesson.groupId}"
                    !existingLessonsSet.contains(key)
                }
                Log.d(TAG, "К сохранению: ${lessonsToSave.size} новых занятий из ${lessons.size}")
                
                // Сохраняем только новые занятия (без дубликатов)
                if (lessonsToSave.isNotEmpty()) {
                    dao.insertLessons(lessonsToSave)
                    Log.d(TAG, "✅ Сохранено ${lessonsToSave.size} плановых занятий (из ${lessons.size}, ${dates.size} дат) для группы $groupFile/$college")
                    
                    // Проверяем, что данные действительно сохранились
                    val savedCount = dao.getLessonsByDateAndType(dates.firstOrNull() ?: "", "planned")
                        .count { it.groupId == groupId }
                    Log.d(TAG, "Проверка: в БД найдено $savedCount занятий для группы $groupId за первую дату")
                    
                    if (lessonsToSave.size < lessons.size) {
                        Log.d(TAG, "Пропущено ${lessons.size - lessonsToSave.size} дубликатов")
                    }
                } else {
                    Log.d(TAG, "Все занятия уже есть в БД, дубликаты не сохраняются")
                }
            } else {
                Log.w(TAG, "⚠️ Нет занятий для сохранения (schedules пуст или items пуст)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при сохранении плановых занятий: ${e.message}", e)
        }
    }
    
    /**
     * Сохранить фактические занятия из журналов
     */
    suspend fun saveActualLessons(
        lessons: List<ScheduleItem>,
        journalFile: String? = null,
        college: String? = null
    ) = withContext(Dispatchers.IO) {
        try {
            // Инициализируем нормализованные таблицы при первом сохранении
            initializeNormalizedTables()
            
            val entities = lessons.map { item ->
                // Преобразуем ScheduleItem в LessonEntity с нормализацией
                item.toLessonEntity(
                    lessonType = "actual",
                    journalFile = journalFile
                )
            }
            
            if (entities.isNotEmpty()) {
                // Группируем по датам и удаляем старые
                val dates = entities.map { it.date }.distinct()
                for (date in dates) {
                    dao.deleteLessonsByDateAndType(date, "actual")
                }
                
                dao.insertLessons(entities)
                Log.d(TAG, "Сохранено ${entities.size} фактических занятий (${dates.size} дат)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при сохранении фактических занятий: ${e.message}", e)
        }
    }
    
    /**
     * Получить все занятия за дату (плановые и фактические)
     * Если указана группа, фильтрует по группе
     */
    suspend fun getLessonsByDate(date: String, groupFile: String? = null, college: String? = null): List<ScheduleItem> = withContext(Dispatchers.IO) {
        try {
            val lessons = if (groupFile != null && college != null) {
                // Фильтруем по группе
                val collegeId = collegeDao.findByCode(college)?.id ?: return@withContext emptyList()
                val group = groupDao.findByFileAndCollege(groupFile, collegeId) ?: return@withContext emptyList()
                dao.getLessonsByDateAndGroup(date, group.id)
            } else {
                // Без фильтрации (для обратной совместимости)
                dao.getLessonsByDate(date)
            }
            lessons.map { lesson -> lesson.toScheduleItemWithRelations() }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении занятий за $date: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Получить занятия за дату по типу
     */
    suspend fun getLessonsByDateAndType(date: String, type: String): List<ScheduleItem> = withContext(Dispatchers.IO) {
        try {
            val lessons = dao.getLessonsByDateAndType(date, type)
            lessons.map { lesson -> lesson.toScheduleItemWithRelations() }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении занятий за $date типа $type: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Получить занятия в диапазоне дат
     */
    suspend fun getLessonsByDateRange(startDate: String, endDate: String): List<ScheduleItem> = withContext(Dispatchers.IO) {
        try {
            val lessons = dao.getLessonsByDateRange(startDate, endDate)
            lessons.map { lesson -> lesson.toScheduleItemWithRelations() }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении занятий в диапазоне: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Получить все даты, для которых есть занятия
     */
    suspend fun getAllDates(): List<String> = withContext(Dispatchers.IO) {
        try {
            dao.getAllDates()
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении дат: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Получить даты по типу
     */
    suspend fun getDatesByType(type: String): List<String> = withContext(Dispatchers.IO) {
        try {
            dao.getDatesByType(type)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении дат типа $type: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Получить все занятия (Flow для наблюдения)
     */
    fun getAllLessons(): Flow<List<LessonEntity>> = dao.getAllLessons()
    
    /**
     * Получить занятия по типу (Flow)
     */
    fun getLessonsByType(type: String): Flow<List<LessonEntity>> = dao.getLessonsByType(type)
    
    /**
     * Удалить все занятия
     */
    suspend fun clearAll() = withContext(Dispatchers.IO) {
        try {
            dao.deleteAllLessons()
            Log.d(TAG, "База данных очищена")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при очистке БД: ${e.message}", e)
        }
    }
    
    /**
     * Удалить занятия по типу
     */
    suspend fun clearByType(type: String) = withContext(Dispatchers.IO) {
        try {
            dao.deleteLessonsByType(type)
            Log.d(TAG, "Удалены занятия типа $type")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при удалении занятий типа $type: ${e.message}", e)
        }
    }
    
    /**
     * Удалить старые занятия (старше указанной даты)
     */
    suspend fun deleteOldLessons(olderThanDate: String) = withContext(Dispatchers.IO) {
        try {
            dao.deleteLessonsOlderThan(olderThanDate)
            Log.d(TAG, "Удалены занятия старше $olderThanDate")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при удалении старых занятий: ${e.message}", e)
        }
    }
    
    /**
     * Получить расширенную статистику с размером БД и разбивкой по типам
     */
    suspend fun getDetailedStatistics(): DetailedLessonStatistics = withContext(Dispatchers.IO) {
        try {
            val basicStats = dao.getStatistics()
            val plannedCount = dao.getCountByType("planned")
            val actualCount = dao.getCountByType("actual")
            val dbSize = getDatabaseSize()
            
            return@withContext DetailedLessonStatistics(
                total = basicStats.total,
                datesCount = basicStats.datesCount,
                oldestDate = basicStats.oldestDate,
                newestDate = basicStats.newestDate,
                plannedCount = plannedCount,
                actualCount = actualCount,
                databaseSizeBytes = dbSize
            )
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении детальной статистики: ${e.message}", e)
            DetailedLessonStatistics(0, 0, null, null, 0, 0, 0)
        }
    }
    
    /**
     * Получить статистику (базовая, для обратной совместимости)
     */
    suspend fun getStatistics(): LessonStatistics = withContext(Dispatchers.IO) {
        try {
            dao.getStatistics()
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении статистики: ${e.message}", e)
            LessonStatistics(0, 0, null, null)
        }
    }
    
    /**
     * Получить размер базы данных в байтах
     */
    private fun getDatabaseSize(): Long {
        return try {
            val dbFile = context.getDatabasePath("raspisanie_database")
            if (dbFile.exists()) {
                dbFile.length()
            } else {
                0L
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении размера БД: ${e.message}", e)
            0L
        }
    }
    
    /**
     * Получить размер базы данных (публичный метод)
     */
    suspend fun getDatabaseSizeBytes(): Long = withContext(Dispatchers.IO) {
        getDatabaseSize()
    }
    
    /**
     * Удалить плановые занятия для конкретной группы и колледжа
     * Используется при смене группы для очистки старых данных
     */
    suspend fun deletePlannedLessonsForGroup(groupFile: String, college: String) = withContext(Dispatchers.IO) {
        try {
            // Получаем все даты с плановыми занятиями
            val dates = dao.getDatesByType("planned")
            var deletedCount = 0
            
            for (date in dates) {
                // Получаем все плановые занятия за дату
                val lessons = dao.getLessonsByDateAndType(date, "planned")
                
                // Получаем ID группы
                val collegeId = collegeDao.findByCode(college)?.id ?: continue
                val group = groupDao.findByFileAndCollege(groupFile, collegeId) ?: continue
                val groupId = group.id
                
                // Фильтруем: оставляем только те, что НЕ относятся к удаляемой группе
                val toKeep = lessons.filter { 
                    it.groupId != groupId
                }
                
                deletedCount += (lessons.size - toKeep.size)
                
                // Если остались занятия других групп - сохраняем их
                if (toKeep.isNotEmpty()) {
                    dao.deleteLessonsByDateAndType(date, "planned")
                    dao.insertLessons(toKeep)
                } else if (lessons.isNotEmpty()) {
                    // Все занятия были для этой группы - удаляем все
                    dao.deleteLessonsByDateAndType(date, "planned")
                }
            }
            
            Log.d(TAG, "Удалено $deletedCount плановых занятий для группы $groupFile/$college")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при удалении занятий группы: ${e.message}", e)
        }
    }
    
    /**
     * Поиск занятий по предмету
     */
    suspend fun searchBySubject(query: String): List<ScheduleItem> = withContext(Dispatchers.IO) {
        try {
            // Ищем предметы по запросу
            val subjects = subjectDao.getAllSubjects().filter { 
                it.name.contains(query, ignoreCase = true) 
            }
            
            // Получаем занятия для найденных предметов
            val lessons = subjects.flatMap { subject ->
                dao.getLessonsBySubjectId(subject.id)
            }
            
            lessons.map { lesson -> lesson.toScheduleItemWithRelations() }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при поиске по предмету: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Поиск занятий по преподавателю
     */
    suspend fun searchByTeacher(query: String): List<ScheduleItem> = withContext(Dispatchers.IO) {
        try {
            // Ищем преподавателей по запросу
            val teachers = teacherDao.getAllTeachers().filter { 
                it.name.contains(query, ignoreCase = true) 
            }
            
            // Получаем занятия для найденных преподавателей
            val lessons = teachers.flatMap { teacher ->
                dao.getLessonsByTeacherId(teacher.id)
            }
            
            lessons.map { lesson -> lesson.toScheduleItemWithRelations() }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при поиске по преподавателю: ${e.message}", e)
            emptyList()
        }
    }
    
    /**
     * Экспорт всех занятий в JSON файл
     * @return File с экспортированными данными или null при ошибке
     */
    suspend fun exportDatabaseToJson(): File? = withContext(Dispatchers.IO) {
        try {
            // Получаем все занятия
            val allLessons = dao.getAllLessons().first()
            
            // Конвертируем в JSON
            val gson = GsonBuilder()
                .setPrettyPrinting()
                .setDateFormat("dd.MM.yyyy")
                .create()
            
            // Загружаем связанные данные для экспорта
            val exportLessons = allLessons.map { lesson ->
                val dayShortName = if (lesson.dayId != null) getDayShortName(lesson.dayId) else null
                val subjectName = if (lesson.subjectId != null) getSubjectName(lesson.subjectId) else null
                val teacherName = if (lesson.teacherId != null) getTeacherName(lesson.teacherId) else null
                val classroomName = if (lesson.classroomId != null) getClassroomName(lesson.classroomId) else null
                val groupName = if (lesson.groupId != null) {
                    groupDao.getById(lesson.groupId)?.name
                } else null
                val groupFile = if (lesson.groupId != null) {
                    groupDao.getById(lesson.groupId)?.groupFile
                } else null
                val collegeCode = if (lesson.groupId != null) {
                    val group = groupDao.getById(lesson.groupId)
                    if (group != null) {
                        collegeDao.getById(group.collegeId)?.code
                    } else null
                } else null
                
                mapOf(
                    "id" to lesson.id,
                    "date" to lesson.date,
                    "lessonNumber" to lesson.lessonNumber,
                    "lessonType" to lesson.lessonType,
                    "subject" to subjectName,
                    "classroom" to classroomName,
                    "teacher" to teacherName,
                    "subgroup" to lesson.subgroup,
                    "dayId" to lesson.dayId,
                    "day" to dayShortName, // Для обратной совместимости
                    "weekNumber" to lesson.weekNumber,
                    "groupId" to lesson.groupId,
                    "groupName" to groupName,
                    "groupFile" to groupFile,
                    "college" to collegeCode,
                    "journalFile" to lesson.journalFile,
                    "savedAt" to lesson.savedAt,
                    // Экспортируем также ID для точного восстановления
                    "subjectId" to lesson.subjectId,
                    "teacherId" to lesson.teacherId,
                    "classroomId" to lesson.classroomId
                )
            }
            
            val exportData = mapOf(
                "exportDate" to System.currentTimeMillis(),
                "totalLessons" to allLessons.size,
                "lessons" to exportLessons
            )
            
            // Создаем файл для экспорта
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.getDefault()).format(Date())
            val exportDir = context.getExternalFilesDir(null) ?: context.filesDir
            val exportFile = File(exportDir, "raspisanie_export_$timestamp.json")
            
            // Записываем JSON
            FileWriter(exportFile).use { writer ->
                gson.toJson(exportData, writer)
            }
            
            Log.d(TAG, "База данных экспортирована: ${exportFile.absolutePath} (${allLessons.size} занятий)")
            return@withContext exportFile
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при экспорте БД: ${e.message}", e)
            return@withContext null
        }
    }
    
    /**
     * Экспортирует базу данных в SQLite .db файл
     * @return File с экспортированной БД или null при ошибке
     */
    suspend fun exportDatabaseToSqlite(): File? = withContext(Dispatchers.IO) {
        try {
            val dbFile = AppDatabase.getDatabaseFile(context)
            if (!dbFile.exists()) {
                Log.e(TAG, "Файл БД не существует: ${dbFile.absolutePath}")
                return@withContext null
            }
            
            // Создаем файл для экспорта
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.getDefault()).format(Date())
            val exportDir = context.getExternalFilesDir(null) ?: context.filesDir
            val exportFile = File(exportDir, "raspisanie_export_$timestamp.db")
            
            // Копируем файл БД
            dbFile.copyTo(exportFile, overwrite = true)
            
            // Также копируем связанные файлы (-wal, -shm для WAL режима)
            val walFile = File(dbFile.absolutePath + "-wal")
            if (walFile.exists()) {
                walFile.copyTo(File(exportFile.absolutePath + "-wal"), overwrite = true)
            }
            val shmFile = File(dbFile.absolutePath + "-shm")
            if (shmFile.exists()) {
                shmFile.copyTo(File(exportFile.absolutePath + "-shm"), overwrite = true)
            }
            
            Log.d(TAG, "База данных экспортирована в SQLite: ${exportFile.absolutePath}")
            return@withContext exportFile
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при экспорте БД в SQLite: ${e.message}", e)
            return@withContext null
        }
    }
    
    /**
     * Импортирует базу данных из SQLite .db файла по URI
     * ВНИМАНИЕ: Заменяет текущую БД! Создает резервную копию перед импортом.
     * @param uri URI .db файла для импорта
     * @return true если успешно, false при ошибке
     */
    suspend fun importDatabaseFromSqliteUri(context: Context, uri: android.net.Uri): Boolean = withContext(Dispatchers.IO) {
        try {
            val dbFile = AppDatabase.getDatabaseFile(context)
            
            // Создаем резервную копию текущей БД
            val backupFile = File(dbFile.absolutePath + ".backup")
            if (dbFile.exists()) {
                dbFile.copyTo(backupFile, overwrite = true)
                Log.d(TAG, "Создана резервная копия БД: ${backupFile.absolutePath}")
            }
            
            // Закрываем текущее подключение к БД
            AppDatabase.getDatabase(context).close()
            
            // Удаляем старые файлы БД
            if (dbFile.exists()) dbFile.delete()
            File(dbFile.absolutePath + "-wal").takeIf { it.exists() }?.delete()
            File(dbFile.absolutePath + "-shm").takeIf { it.exists() }?.delete()
            File(dbFile.absolutePath + "-journal").takeIf { it.exists() }?.delete()
            
            // Открываем поток для чтения импортируемого файла
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                // Копируем новый файл БД
                dbFile.outputStream().use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
                
                // WAL и SHM файлы не копируем - Room создаст их автоматически при следующем подключении
                
                Log.d(TAG, "База данных импортирована из SQLite: $uri")
                return@withContext true
            } ?: run {
                Log.e(TAG, "Не удалось открыть поток для URI: $uri")
                // Восстанавливаем из резервной копии
                if (backupFile.exists()) {
                    backupFile.copyTo(dbFile, overwrite = true)
                }
                return@withContext false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при импорте БД из SQLite: ${e.message}", e)
            // Восстанавливаем из резервной копии
            try {
                val dbFile = AppDatabase.getDatabaseFile(context)
                val backupFile = File(dbFile.absolutePath + ".backup")
                if (backupFile.exists()) {
                    backupFile.copyTo(dbFile, overwrite = true)
                }
            } catch (_: Exception) {}
            return@withContext false
        }
    }
    
    /**
     * Импортирует занятия из JSON файла по URI
     * @param uri URI JSON файла для импорта
     * @return количество импортированных занятий или -1 при ошибке
     */
    suspend fun importDatabaseFromJsonUri(context: Context, uri: android.net.Uri): Int = withContext(Dispatchers.IO) {
        try {
            // Открываем поток для чтения
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                val jsonString = inputStream.bufferedReader().use { it.readText() }
                
                // Парсим JSON
                val jsonObject = com.google.gson.JsonParser.parseString(jsonString).asJsonObject
                
                // Извлекаем массив занятий
                val lessonsArray = jsonObject.getAsJsonArray("lessons")
                if (lessonsArray == null) {
                    Log.e(TAG, "Не найден массив 'lessons' в JSON")
                    return@withContext -1
                }
                
                // Конвертируем JSON в LessonEntity
                val lessonsToImport = mutableListOf<LessonEntity>()
                for (lessonJson in lessonsArray) {
                    try {
                        val lessonObj = lessonJson.asJsonObject
                        
                        // Инициализируем нормализованные таблицы (первый раз)
                        if (lessonsToImport.isEmpty()) {
                            initializeNormalizedTables()
                        }
                        
                        // Поддержка обратной совместимости: если есть "day" (старый формат), конвертируем в dayId
                        val dayIdFromJson = lessonObj.get("dayId")?.asInt
                        val dayFromJson = lessonObj.get("day")?.asString
                        val finalDayId = dayIdFromJson ?: if (dayFromJson != null) {
                            DayOfWeekEntity.dayNameToId(DayOfWeekEntity.normalizeDayName(dayFromJson))
                        } else null
                        
                        // Получаем или создаём нормализованные данные
                        val subjectId = lessonObj.get("subjectId")?.asLong 
                            ?: lessonObj.get("subject")?.asString?.let { subjectDao.getOrCreate(it) }
                        
                        val teacherId = lessonObj.get("teacherId")?.asLong
                            ?: lessonObj.get("teacher")?.asString?.let { teacherDao.getOrCreate(it) }
                        
                        val classroomId = lessonObj.get("classroomId")?.asLong
                            ?: lessonObj.get("classroom")?.asString?.let { classroomDao.getOrCreate(it) }
                        
                        // Получаем или создаём группу
                        val groupId = lessonObj.get("groupId")?.asLong ?: run {
                            val groupFile = lessonObj.get("groupFile")?.asString
                            val collegeCode = lessonObj.get("college")?.asString
                            if (groupFile != null && collegeCode != null) {
                                val collegeId = collegeDao.getOrCreate(collegeCode, collegeCode)
                                val groupName = lessonObj.get("groupName")?.asString ?: groupFile
                                groupDao.getOrCreate(groupName, groupFile, collegeId)
                            } else null
                        }
                        
                        val lesson = LessonEntity(
                            id = 0, // Сбрасываем ID - будет создан новый
                            date = lessonObj.get("date")?.asString ?: continue,
                            lessonNumber = lessonObj.get("lessonNumber")?.asInt ?: continue,
                            lessonType = lessonObj.get("lessonType")?.asString ?: continue,
                            subjectId = subjectId,
                            classroomId = classroomId,
                            teacherId = teacherId,
                            subgroup = lessonObj.get("subgroup")?.asInt,
                            dayId = finalDayId,
                            weekNumber = lessonObj.get("weekNumber")?.asInt,
                            groupId = groupId,
                            journalFile = lessonObj.get("journalFile")?.asString,
                            savedAt = lessonObj.get("savedAt")?.asLong ?: System.currentTimeMillis()
                        )
                        lessonsToImport.add(lesson)
                    } catch (e: Exception) {
                        Log.w(TAG, "Ошибка при парсинге занятия: ${e.message}", e)
                        continue
                    }
                }
                
                if (lessonsToImport.isEmpty()) {
                    Log.w(TAG, "Нет занятий для импорта")
                    return@withContext 0
                }
                
                // Сохраняем импортированные занятия (REPLACE обновит существующие по уникальному индексу)
                dao.insertLessons(lessonsToImport)
                
                Log.d(TAG, "Импортировано ${lessonsToImport.size} занятий из URI: $uri")
                return@withContext lessonsToImport.size
            } ?: run {
                Log.e(TAG, "Не удалось открыть поток для URI: $uri")
                return@withContext -1
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при импорте БД из JSON URI: ${e.message}", e)
            return@withContext -1
        }
    }
}
