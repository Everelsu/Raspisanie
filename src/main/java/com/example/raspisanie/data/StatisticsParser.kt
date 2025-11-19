package com.example.raspisanie.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import android.util.Log

data class DisciplineStatistics(
    val number: String,
    val teacher: String,
    val discipline: String,
    val lessonType: String,
    val totalHours: Int?,
    val plannedHours: Int?,
    val factHours: Int?,
    val remainingHours: Int?,
    val plannedIn2Weeks: String?,
    val factIn2Weeks: String?,
    val completionDate: String?,
    val completionPercent: String?
) {
    // Вычисляем процент выполнения для графика
    fun getCompletionPercentInt(): Int {
        if (totalHours == null || totalHours == 0) return 0
        val fact = factHours ?: 0
        return ((fact * 100) / totalHours).coerceIn(0, 100)
    }
}

data class GroupStatistics(
    val groupName: String,
    val disciplines: List<DisciplineStatistics> = emptyList(),
    val totalHours: Int? = null,
    val completedHours: Int? = null,
    val remainingHours: Int? = null,
    val plannedHours: Int? = null
)

class StatisticsParser(private val context: android.content.Context? = null) {
    companion object {
        private const val TAG = "StatisticsParser"
        private const val BASE_URL_CHTOTIB = "https://www.chtotib.ru/schedule_gl/"
    }
    
    private val cache: StatisticsCache? = context?.let { StatisticsCache(it) }

    suspend fun fetchStatistics(groupFile: String = "cg36.htm", useCache: Boolean = true): GroupStatistics? = withContext(Dispatchers.IO) {
        // Сначала пытаемся загрузить из кэша
        if (useCache && cache != null) {
            val cachedStatistics = cache.getCachedStatistics(groupFile)
            if (cachedStatistics != null) {
                Log.d(TAG, "✅ Статистика загружена из кэша для $groupFile")
                // Загружаем свежие данные в фоне, но возвращаем кэш
                // (можно сделать параллельную загрузку, но пока просто возвращаем кэш)
                return@withContext cachedStatistics
            }
        }
        
        // Если кэша нет или он отключен, загружаем с сервера
        try {
            // Преобразуем cg36.htm -> vg36.htm для страницы с итогами
            val statisticsFile = groupFile.replace("cg", "vg")
            val statisticsUrl = "$BASE_URL_CHTOTIB$statisticsFile"
            Log.d(TAG, "Загрузка статистики с $statisticsUrl (из $groupFile)")
            
            val doc: Document = Jsoup.connect(statisticsUrl)
                .timeout(20000)
                .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .followRedirects(true)
                .parser(org.jsoup.parser.Parser.htmlParser())
                .maxBodySize(10 * 1024 * 1024)
                .get()
            
            // Ищем таблицу с итогами
            // Сначала пробуем найти таблицу с классом "inf"
            var statisticsTable = doc.select("table.inf").firstOrNull()
            
            // Если не нашли, ищем таблицу по содержимому (должна содержать колонки "Всего, час.", "План, час." и т.д.)
            if (statisticsTable == null) {
                val allTables = doc.select("table")
                for (table in allTables) {
                    val tableText = table.text().lowercase()
                    // Ищем таблицу, которая содержит все нужные колонки
                    if (tableText.contains("всего") && 
                        (tableText.contains("план") || tableText.contains("факт")) &&
                        tableText.contains("остаток")) {
                        statisticsTable = table
                        Log.d(TAG, "Найдена таблица с итогами по содержимому")
                        break
                    }
                }
            }
            
            if (statisticsTable == null) {
                Log.w(TAG, "Таблица с итогами не найдена")
                return@withContext null
            }
            
            // Пытаемся найти название группы из заголовка страницы
            val h1 = doc.select("h1").firstOrNull()?.text() ?: ""
            val groupName = h1.replace("Группа:", "").trim()
            
            // Парсим данные из таблицы
            // Таблица имеет структуру: № п.п | Преподаватель | Группа | П/г | Дисциплина | Тип занятия | Всего, час. | План, час. | Факт, час. | Остаток, час. | План в 2 нед., час. | Факт в 2 нед., час. | Окончание | Процент выполнения, %
            val rows = statisticsTable.select("tr")
            
            var headerRowFound = false
            var numberColIndex = -1
            var teacherColIndex = -1
            var disciplineColIndex = -1
            var lessonTypeColIndex = -1
            var totalHoursColIndex = -1
            var plannedHoursColIndex = -1
            var factHoursColIndex = -1
            var remainingHoursColIndex = -1
            var plannedIn2WeeksColIndex = -1
            var factIn2WeeksColIndex = -1
            var completionDateColIndex = -1
            var completionPercentColIndex = -1
            
            val disciplines = mutableListOf<DisciplineStatistics>()
            var totalHoursSum = 0
            var plannedHoursSum = 0
            var factHoursSum = 0
            var remainingHoursSum = 0
            
            for (row in rows) {
                val cells = row.select("td, th")
                
                // Ищем заголовок таблицы для определения индексов колонок
                if (!headerRowFound && cells.isNotEmpty()) {
                    val headerText = row.text().lowercase()
                    if (headerText.contains("№") && (headerText.contains("преподаватель") || headerText.contains("дисциплина"))) {
                        headerRowFound = true
                        for (i in cells.indices) {
                            val cellText = cells[i].text().lowercase()
                            when {
                                cellText.contains("№") || cellText.contains("п.п") -> numberColIndex = i
                                cellText.contains("преподаватель") -> teacherColIndex = i
                                cellText.contains("дисциплина") -> disciplineColIndex = i
                                cellText.contains("тип") && cellText.contains("занят") -> lessonTypeColIndex = i
                                cellText.contains("всего") && (cellText.contains("час") || cellText.contains("ч.")) -> totalHoursColIndex = i
                                cellText.contains("план") && cellText.contains("час") && !cellText.contains("2 нед") -> plannedHoursColIndex = i
                                cellText.contains("факт") && cellText.contains("час") && !cellText.contains("2 нед") -> factHoursColIndex = i
                                cellText.contains("остаток") && (cellText.contains("час") || cellText.contains("ч.")) -> remainingHoursColIndex = i
                                cellText.contains("план") && cellText.contains("2 нед") -> plannedIn2WeeksColIndex = i
                                cellText.contains("факт") && cellText.contains("2 нед") -> factIn2WeeksColIndex = i
                                cellText.contains("окончание") -> completionDateColIndex = i
                                cellText.contains("процент") || cellText.contains("выполн") -> completionPercentColIndex = i
                            }
                        }
                        Log.d(TAG, "Найдены индексы колонок: №=$numberColIndex, преподаватель=$teacherColIndex, дисциплина=$disciplineColIndex, всего=$totalHoursColIndex, план=$plannedHoursColIndex, факт=$factHoursColIndex, остаток=$remainingHoursColIndex")
                        continue
                    }
                }
                
                // Парсим строки с данными (пропускаем заголовки)
                if (headerRowFound && cells.size > 3) {
                    // Проверяем, что это не заголовок (не содержит "№ п.п" или "преподаватель")
                    val firstCellText = cells.firstOrNull()?.text()?.lowercase() ?: ""
                    if (firstCellText.contains("№") && firstCellText.contains("п.п") || 
                        firstCellText.contains("преподаватель") || 
                        firstCellText.isEmpty() ||
                        firstCellText.contains("-----")) {
                        continue
                    }
                    
                    // Извлекаем данные из строки
                    val number = if (numberColIndex >= 0 && numberColIndex < cells.size) cells[numberColIndex].text().trim() else ""
                    val teacher = if (teacherColIndex >= 0 && teacherColIndex < cells.size) cells[teacherColIndex].text().trim() else ""
                    val discipline = if (disciplineColIndex >= 0 && disciplineColIndex < cells.size) {
                        // Получаем текст дисциплины из ссылки
                        val disciplineElement = cells[disciplineColIndex]
                        // Сначала пробуем получить текст из ссылки
                        val link = disciplineElement.select("a").firstOrNull()
                        if (link != null) {
                            link.text().trim()
                        } else {
                            // Если ссылки нет, берем весь текст
                            disciplineElement.text().trim()
                        }
                    } else ""
                    val lessonType = if (lessonTypeColIndex >= 0 && lessonTypeColIndex < cells.size) cells[lessonTypeColIndex].text().trim() else ""
                    
                    val totalHours = if (totalHoursColIndex >= 0 && totalHoursColIndex < cells.size) {
                        extractNumber(listOf(cells[totalHoursColIndex].text()))
                    } else null
                    
                    val plannedHours = if (plannedHoursColIndex >= 0 && plannedHoursColIndex < cells.size) {
                        extractNumber(listOf(cells[plannedHoursColIndex].text()))
                    } else null
                    
                    val factHours = if (factHoursColIndex >= 0 && factHoursColIndex < cells.size) {
                        extractNumber(listOf(cells[factHoursColIndex].text()))
                    } else null
                    
                    val remainingHours = if (remainingHoursColIndex >= 0 && remainingHoursColIndex < cells.size) {
                        extractNumber(listOf(cells[remainingHoursColIndex].text()))
                    } else null
                    
                    val plannedIn2Weeks = if (plannedIn2WeeksColIndex >= 0 && plannedIn2WeeksColIndex < cells.size) {
                        cells[plannedIn2WeeksColIndex].text().trim().takeIf { it.isNotEmpty() }
                    } else null
                    
                    val factIn2Weeks = if (factIn2WeeksColIndex >= 0 && factIn2WeeksColIndex < cells.size) {
                        cells[factIn2WeeksColIndex].text().trim().takeIf { it.isNotEmpty() }
                    } else null
                    
                    val completionDate = if (completionDateColIndex >= 0 && completionDateColIndex < cells.size) {
                        cells[completionDateColIndex].text().trim().takeIf { it.isNotEmpty() }
                    } else null
                    
                    val completionPercent = if (completionPercentColIndex >= 0 && completionPercentColIndex < cells.size) {
                        val percentCell = cells[completionPercentColIndex]
                        // Пробуем извлечь процент из текста или атрибута alt изображения
                        val percentText = percentCell.text().trim()
                        if (percentText.isNotEmpty()) {
                            percentText
                        } else {
                            // Пробуем найти в атрибуте alt изображения
                            val img = percentCell.select("img").firstOrNull()
                            img?.attr("alt")?.takeIf { it.isNotEmpty() } ?: null
                        }
                    } else null
                    
                    // Добавляем дисциплину только если есть хотя бы название
                    if (discipline.isNotEmpty() || number.isNotEmpty()) {
                        disciplines.add(DisciplineStatistics(
                            number = number,
                            teacher = teacher,
                            discipline = discipline,
                            lessonType = lessonType,
                            totalHours = totalHours,
                            plannedHours = plannedHours,
                            factHours = factHours,
                            remainingHours = remainingHours,
                            plannedIn2Weeks = plannedIn2Weeks,
                            factIn2Weeks = factIn2Weeks,
                            completionDate = completionDate,
                            completionPercent = completionPercent
                        ))
                        
                        // Суммируем для итогов
                        totalHours?.let { totalHoursSum += it }
                        plannedHours?.let { plannedHoursSum += it }
                        factHours?.let { factHoursSum += it }
                        remainingHours?.let { remainingHoursSum += it }
                    }
                }
            }
            
            val totalHours = if (totalHoursSum > 0) totalHoursSum else null
            val plannedHours = if (plannedHoursSum > 0) plannedHoursSum else null
            val completedHours = if (factHoursSum > 0) factHoursSum else null
            val remainingHours = if (remainingHoursSum > 0) remainingHoursSum else null
            
            Log.d(TAG, "Статистика для $groupName: найдено дисциплин=${disciplines.size}, всего=$totalHours, было=$completedHours, осталось=$remainingHours, запланировано=$plannedHours")
            
            val statistics = GroupStatistics(
                groupName = groupName,
                disciplines = disciplines,
                totalHours = totalHours,
                completedHours = completedHours,
                remainingHours = remainingHours,
                plannedHours = plannedHours
            )
            
            // Сохраняем в кэш
            if (cache != null) {
                cache.cacheStatistics(statistics, groupFile)
            }
            
            return@withContext statistics
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при загрузке статистики", e)
            
            // При ошибке сети пытаемся загрузить из кэша
            if (useCache && cache != null) {
                val cachedStatistics = cache.getCachedStatistics(groupFile)
                if (cachedStatistics != null) {
                    Log.d(TAG, "✅ Используем кэш из-за ошибки сети для $groupFile")
                    return@withContext cachedStatistics
                }
            }
            
            return@withContext null
        }
    }
    
    private fun parseFromPageText(doc: Document, groupFile: String): GroupStatistics? {
        // Fallback: пытаемся найти данные в тексте страницы
        val pageText = doc.text()
        val title = doc.select("title").firstOrNull()?.text() ?: ""
        val h1 = doc.select("h1").firstOrNull()?.text() ?: ""
        val groupName = h1.ifEmpty { title }
        
        // Ищем паттерны типа "Всего: 120 часов", "Было: 80 часов" и т.д.
        val totalMatch = Regex("(?:всего|итого)[:\\s]*(\\d+)\\s*(?:час|ч\\.?)", RegexOption.IGNORE_CASE).find(pageText)
        val completedMatch = Regex("(?:было|прошло|выполнено)[:\\s]*(\\d+)\\s*(?:час|ч\\.?)", RegexOption.IGNORE_CASE).find(pageText)
        val remainingMatch = Regex("(?:осталось|остаток)[:\\s]*(\\d+)\\s*(?:час|ч\\.?)", RegexOption.IGNORE_CASE).find(pageText)
        val plannedMatch = Regex("(?:запланировано|будет|планируется)[:\\s]*(\\d+)\\s*(?:час|ч\\.?)", RegexOption.IGNORE_CASE).find(pageText)
        
        val totalHours = totalMatch?.groupValues?.get(1)?.toIntOrNull()
        val completedHours = completedMatch?.groupValues?.get(1)?.toIntOrNull()
        val remainingHours = remainingMatch?.groupValues?.get(1)?.toIntOrNull()
        val plannedHours = plannedMatch?.groupValues?.get(1)?.toIntOrNull()
        
        if (totalHours != null || completedHours != null || remainingHours != null || plannedHours != null) {
            Log.d(TAG, "Найдены данные в тексте страницы: всего=$totalHours, было=$completedHours, осталось=$remainingHours")
            return GroupStatistics(
                groupName = groupName,
                totalHours = totalHours,
                completedHours = completedHours,
                remainingHours = remainingHours,
                plannedHours = plannedHours
            )
        }
        
        return null
    }
    
    private fun extractNumber(cellValues: List<String>): Int? {
        for (value in cellValues) {
            // Ищем число в тексте (может быть "120 часов" или просто "120")
            val numberMatch = Regex("(\\d+)").find(value)
            if (numberMatch != null) {
                return numberMatch.groupValues[1].toIntOrNull()
            }
        }
        return null
    }
}

