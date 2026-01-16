package com.example.raspisanie.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import android.util.Log

class ScheduleParser {
    companion object {
        private const val TAG = "ScheduleParser"
        private const val BASE_URL_CHTOTIB = "https://www.chtotib.ru/schedule_gl/"
        private const val BASE_URL_ZABGC = "https://bbb.zabgc.ru/"
    }

    suspend fun fetchSchedule(groupFile: String = "cg36.htm", college: String = PreferencesManager.COLLEGE_CHTOTIB): List<DaySchedule> = withContext(Dispatchers.IO) {
        // Валидация входных параметров
        if (groupFile.isBlank() || college.isBlank()) {
            Log.e(TAG, "Неверные параметры: groupFile=$groupFile, college=$college")
            return@withContext emptyList()
        }
        
        try {
            val baseUrl = if (college == PreferencesManager.COLLEGE_ZABGC) {
                BASE_URL_ZABGC
            } else {
                BASE_URL_CHTOTIB
            }
            val scheduleUrl = "$baseUrl$groupFile"
            Log.d(TAG, "Начинаю загрузку расписания с $scheduleUrl (техникум: $college)")
            
            val doc: Document = try {
                Jsoup.connect(scheduleUrl)
                    .timeout(20000)
                    .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                    .followRedirects(true)
                    .parser(org.jsoup.parser.Parser.htmlParser())
                    .maxBodySize(10 * 1024 * 1024) // Ограничение размера документа до 10MB
                    .get()
            } catch (e: java.net.SocketTimeoutException) {
                Log.e(TAG, "Таймаут при подключении к $scheduleUrl", e)
                throw e
            } catch (e: java.net.UnknownHostException) {
                Log.e(TAG, "Не удалось разрешить хост для $scheduleUrl", e)
                throw e
            } catch (e: java.io.IOException) {
                Log.e(TAG, "Ошибка ввода/вывода при загрузке $scheduleUrl", e)
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Неожиданная ошибка при загрузке $scheduleUrl", e)
                throw e
            }
            
            // Не логируем размер HTML для производительности, только если нужно отладка
            // Log.d(TAG, "HTML загружен, размер: ${doc.html().length} символов")

            val schedules = mutableListOf<DaySchedule>()
            
            // Find the main table with class "inf" which contains schedule
            val table = doc.select("table.inf").firstOrNull()
            
            if (table == null) {
                Log.e(TAG, "Таблица расписания не найдена!")
                return@withContext schedules
            }
            
            Log.d(TAG, "Таблица найдена, строк: ${table.select("tr").size}")

            var currentDay: String? = null
            var currentDate: String? = null
            var currentWeekNumber: Int = 1
            var dayItems = mutableListOf<ScheduleItem>()

            val rows = table.select("tr")
            Log.d(TAG, "Обрабатываю ${rows.size} строк")
            
            // Track processed rows to avoid duplicates
            var rowIndex = 0
            
            for (row in rows) {
                rowIndex++
                val cells = row.select("td")
                if (cells.isEmpty()) {
                    continue
                }

                // Skip header rows (contain "День" or "Пара" in header cells)
                val isHeaderRow = cells.any { it.hasClass("hd") && (it.text().contains("День") || it.text().contains("Пара")) }
                if (isHeaderRow) {
                    continue
                }
                
                // Skip separator rows (class "hd0")
                val isSeparatorRow = cells.any { it.hasClass("hd0") }
                if (isSeparatorRow) {
                    continue
                }

                // Check if first cell has rowspan - this is a day header
                // Also check second cell if first is missing (due to rowspan)
                val firstCell = cells.firstOrNull()
                val secondCell = cells.getOrNull(1)
                
                // Check for day header in first or second cell
                val dayHeaderCell = when {
                    firstCell != null && firstCell.hasAttr("rowspan") -> firstCell
                    secondCell != null && secondCell.hasAttr("rowspan") -> secondCell
                    else -> null
                }
                
                // Flag to track if we just started a new day (so we need to process lesson in the same row)
                var justStartedNewDay = false
                
                if (dayHeaderCell != null) {
                    // This is a new day row - it contains BOTH day header AND first lesson
                    // Get text directly from HTML to handle <br> tags properly
                    val dateHtml = dayHeaderCell.html()
                    val dateText = dateHtml.replace("<br>", "\n")
                        .replace("<br/>", "\n")
                        .replace("<BR>", "\n")
                        .replace("<br />", "\n")
                    
                    // Parse date format: "30.10.2025\nЧт-1" or "01.11.2025<br>Сб-1"
                    // Extract day abbreviation (Чт, Пт, Сб, Вс, Пн, Вт, Ср, etc.) and week number
                    val dateMatch = Regex("(\\d{2}\\.\\d{2}\\.\\d{4})[\\s\\n\\r<>]*([А-Яа-я]+)[\\s\\n\\r<>]*-[\\s\\n\\r<>]*(\\d)").find(dateText)
                    if (dateMatch != null) {
                        // Save previous day if exists
                        if (currentDay != null) {
                            schedules.add(
                                DaySchedule(
                                    day = currentDay,
                                    date = currentDate ?: "",
                                    weekNumber = currentWeekNumber,
                                    items = dayItems.toList()
                                )
                            )
                        }

                        // Start new day
                        currentDate = dateMatch.groupValues[1]
                        currentDay = dateMatch.groupValues[2].trim()
                        currentWeekNumber = dateMatch.groupValues[3].toIntOrNull() ?: 1
                        dayItems = mutableListOf()
                        justStartedNewDay = true
                    }
                }

                // This row is a lesson row if:
                // 1. It doesn't have day header (subsequent rows after first day row)
                // 2. OR it has day header (first row) - in which case we also need to process the lesson in this row
                val isLessonRow = currentDay != null && (dayHeaderCell == null || justStartedNewDay)
                
                if (isLessonRow && cells.size >= 1) {
                    // Find the cell with lesson number - it has class "hd" and contains a number 1-10
                    // Usually it's the first or second cell (if first was day header which is now missing due to rowspan)
                    var lessonNumber: Int? = null
                    var lessonCellIndex = -1
                    
                    // Check cells from the beginning - first cell might be day (if rowspan still present), 
                    // second might be lesson number, or first might be lesson number if day is missing due to rowspan
                    for (i in cells.indices) {
                        val cell = cells[i]
                        
                        // Skip day header cell (has rowspan attribute) - it's not a lesson number
                        if (cell.hasAttr("rowspan")) {
                            continue
                        }
                        
                        // Skip cells that contain subjects (classes "ur" or "nul") - they come after lesson number
                        if (cell.hasClass("ur") || cell.hasClass("nul")) {
                            continue
                        }
                        
                        // Look for cell with class "hd" that contains a lesson number
                        if (cell.hasClass("hd")) {
                            val cellText = cell.text().trim()
                            // Skip empty cells
                            if (cellText.isEmpty()) {
                                continue
                            }
                            val num = cellText.toIntOrNull()
                            // Accept numbers from 1 to 10 (some schedules have more than 8 lessons)
                            if (num != null && num >= 1 && num <= 10) {
                                lessonNumber = num
                                lessonCellIndex = i
                                // Log.d(TAG, "Найден номер пары $lessonNumber в ячейке $i строки #$rowIndex")
                                break
                            }
                        }
                    }
                    
                    // Debug: if lesson number not found, log what cells we have (только в debug режиме)
                    // if (lessonNumber == null && cells.isNotEmpty()) {
                    //     Log.w(TAG, "⚠ Номер пары не найден в строке #$rowIndex (ячеек: ${cells.size})")
                    // }
                    
                    if (lessonNumber != null && lessonNumber >= 1 && lessonNumber <= 10) {
                        // Subject columns are after lesson number cell
                        // Get all cells after lesson number cell
                        val allCellsAfterLesson = cells.drop(lessonCellIndex + 1)
                        
                        // Find all cells with class "ur" (has lesson) in THIS row
                        // IMPORTANT: Each "ur" cell, even if identical to another, should create a separate ScheduleItem
                        // This handles cases where there are multiple identical subjects (subgroups, different classrooms, etc.)
                        val subjectCells = allCellsAfterLesson.filter { cell ->
                            cell.hasClass("ur")
                        }
                        
                        // Determine if there are multiple columns (subgroups)
                        // Check if there are multiple cells after lesson number (even if some are empty)
                        // Empty cells might not have class "ur", but they still indicate separate columns
                        val hasMultipleColumns = allCellsAfterLesson.size > 1
                        
                        // Process each "ur" cell - even if they contain the same subject
                        // Each cell should create a separate ScheduleItem, regardless of content
                        subjectCells.forEach { cell ->
                            val subjectInfo = parseSubjectCell(cell)
                            
                            if (subjectInfo.subject != null && subjectInfo.subject.isNotEmpty()) {
                                // Determine subgroup: if there are multiple columns, determine position
                                // Position is determined by cell's index in allCellsAfterLesson (not just "ur" cells)
                                val subgroup = if (hasMultipleColumns) {
                                    val cellIndexInAllCells = allCellsAfterLesson.indexOf(cell)
                                    // Subgroup number is 1-based position in allCellsAfterLesson
                                    cellIndexInAllCells + 1
                                } else null
                                
                                dayItems.add(
                                    ScheduleItem(
                                        day = currentDay ?: "",
                                        date = currentDate ?: "",
                                        weekNumber = currentWeekNumber,
                                        lessonNumber = lessonNumber,
                                        subject = subjectInfo.subject,
                                        classroom = subjectInfo.classroom,
                                        teacher = subjectInfo.teacher,
                                        subgroup = subgroup
                                    )
                                )
                            }
                        }
                    }
                }
            }

            // Add last day (even if empty)
            if (currentDay != null) {
                schedules.add(
                    DaySchedule(
                        day = currentDay,
                        date = currentDate ?: "",
                        weekNumber = currentWeekNumber,
                        items = dayItems.toList()
                    )
                )
                Log.d(TAG, "✓ Добавлен последний день: $currentDay ($currentDate), занятий: ${dayItems.size}")
            }

            // Final validation and summary
            val totalLessons = schedules.sumOf { it.items.size }
            val daysWithLessons = schedules.count { it.items.isNotEmpty() }
            val daysWithoutLessons = schedules.count { it.items.isEmpty() }
            
            Log.d(TAG, "═══════════════════════════════════════════════════════")
            Log.d(TAG, "Парсинг завершен:")
            Log.d(TAG, "  • Найдено дней: ${schedules.size}")
            Log.d(TAG, "  • Дней с занятиями: $daysWithLessons")
            Log.d(TAG, "  • Дней без занятий: $daysWithoutLessons")
            Log.d(TAG, "  • Всего занятий: $totalLessons")
            
            // Log lessons per day for verification
            schedules.forEach { daySchedule ->
                val lessonsCount = daySchedule.items.size
                val lessonsByNumber = daySchedule.items.groupBy { it.lessonNumber }
                Log.d(TAG, "  • ${daySchedule.day} (${daySchedule.date}): $lessonsCount занятий, пары: ${lessonsByNumber.keys.sorted().joinToString(", ")}")
            }
            Log.d(TAG, "═══════════════════════════════════════════════════════")
            
            return@withContext schedules
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при парсинге расписания", e)
            throw e
        }
    }

    private data class SubjectInfo(
        val subject: String?,
        val classroom: String?,
        val teacher: String?
    )

    private fun parseSubjectCell(cell: Element): SubjectInfo {
        // Links structure:
        // - class "z1" (href starts with "j") - subject
        // - class "z2" (href starts with "ca") - classroom
        // - class "z3" (href starts with "cp") - teacher
        
        val allLinks = cell.select("a")
        
        // Find subject link (class z1 or href starts with "j")
        val subjectLink = cell.select("a.z1").firstOrNull() 
            ?: allLinks.firstOrNull { it.attr("href").startsWith("j") && !it.attr("href").startsWith("cp") && !it.attr("href").startsWith("ca") }
        val subject = subjectLink?.text()?.trim()
        
        // Find classroom link (class z2 or href starts with "ca")
        val classroomLink = cell.select("a.z2").firstOrNull()
            ?: allLinks.firstOrNull { it.attr("href").startsWith("ca") }
        var classroom = classroomLink?.text()?.trim()
        
        // If classroom link has empty text, try to get it from href
        if (classroom.isNullOrEmpty() && classroomLink != null) {
            // Try to extract from href like "ca54.htm" -> "54"
            val href = classroomLink.attr("href")
            val hrefMatch = Regex("ca(\\d+)\\.htm").find(href)
            if (hrefMatch != null) {
                classroom = hrefMatch.groupValues[1]
            } else {
                // Try non-numeric classrooms like "ca112.htm" -> "112" or "ca115.htm" -> might be name
                val hrefMatch2 = Regex("ca([^.]+)\\.htm").find(href)
                if (hrefMatch2 != null) {
                    // Look at the link's title attribute or try to get from cell text
                    val title = classroomLink.attr("title")
                    if (title.isNotEmpty()) {
                        classroom = title
                    }
                }
            }
        }
        
        // Sometimes classroom might be visible but link has no text
        if (classroom.isNullOrEmpty()) {
            // Get all text from z2 links including nested text
            val allZ2Text = cell.select("a.z2").mapNotNull { it.text().trim() }.firstOrNull()
            classroom = allZ2Text
            
            // Last resort: try to find any text that looks like classroom
            if (classroom.isNullOrEmpty()) {
                val cellText = cell.text()
                // Look for patterns like numbers or short text that might be classroom
                val parts = cellText.split("\n")
                if (parts.size > 1) {
                    // Usually classroom is on same line as subject or on next line
                    classroom = parts.firstOrNull { part ->
                        val trimmed = part.trim()
                        // Skip if it's the subject or teacher
                        trimmed.isNotEmpty() && 
                        !trimmed.equals(subject, ignoreCase = true) &&
                        trimmed.length < 50 // Classroom names are usually short
                    }?.trim()
                }
            }
        }
        
        // Find teacher link (class z3 or href starts with "cp")
        val teacherLink = cell.select("a.z3").firstOrNull()
            ?: allLinks.firstOrNull { it.attr("href").startsWith("cp") }
        val teacher = teacherLink?.text()?.trim()

        return SubjectInfo(subject, classroom, teacher)
    }
    
    /**
     * Парсит журнал занятий (например, j362.htm) для получения фактических занятий
     * @param journalFile имя файла журнала (например, "j362.htm")
     * @param college колледж
     * @return список фактических занятий из журнала
     */
    suspend fun fetchJournalLessons(journalFile: String, college: String = PreferencesManager.COLLEGE_CHTOTIB): List<ScheduleItem> = withContext(Dispatchers.IO) {
        val journalLessons = mutableListOf<ScheduleItem>()
        
        try {
            val baseUrl = if (college == PreferencesManager.COLLEGE_ZABGC) {
                BASE_URL_ZABGC
            } else {
                BASE_URL_CHTOTIB
            }
            val journalUrl = "$baseUrl$journalFile"
            Log.d(TAG, "Загрузка журнала: $journalUrl")
            
            val doc: Document = try {
                Jsoup.connect(journalUrl)
                    .timeout(20000)
                    .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                    .followRedirects(true)
                    .parser(org.jsoup.parser.Parser.htmlParser())
                    .maxBodySize(10 * 1024 * 1024)
                    .get()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при загрузке журнала $journalUrl: ${e.message}", e)
                return@withContext journalLessons
            }
            
            // Находим таблицу с журналом
            val table = doc.select("table.inf").firstOrNull()
            if (table == null) {
                Log.w(TAG, "Таблица журнала не найдена в $journalUrl")
                return@withContext journalLessons
            }
            
            // Получаем название дисциплины из заголовка (обычно в списке перед таблицей)
            var subjectName: String? = null
            // Ищем в списке перед таблицей (обычно формат: "* МДК.11.01 Технология разработки и защиты баз данных")
            val listItems = doc.select("ul li, ol li, p")
            for (item in listItems) {
                val text = item.text().trim()
                if (text.contains("МДК") || text.contains("дисциплина") || text.matches(Regex(".*МДК\\.\\d+.*"))) {
                    subjectName = text.replace("*", "").trim()
                    break
                }
            }
            // Если не нашли в списке, ищем в заголовках
            if (subjectName.isNullOrEmpty()) {
                subjectName = doc.select("h1, h2, h3").firstOrNull()?.text()?.trim()
                    ?: doc.select("p, div").firstOrNull { it.text().contains("МДК") || it.text().contains("дисциплина") }?.text()?.trim()
            }
            
            val rows = table.select("tr")
            var isHeaderRow = true
            
            for (row in rows) {
                val cells = row.select("td")
                if (cells.isEmpty()) continue
                
                // Пропускаем заголовок таблицы
                if (isHeaderRow) {
                    val headerText = row.text()
                    if (headerText.contains("№ п.п") || headerText.contains("Дата") || headerText.contains("Час")) {
                        isHeaderRow = false
                        continue
                    }
                }
                
                // Парсим строку журнала: № п.п | Дата | Час | Группа | П/г | Преподаватель | Аудитория
                if (cells.size >= 6) {
                    try {
                        // Дата (колонка 2, индекс 1)
                        val dateStr = cells[1].text().trim()
                        if (dateStr.isEmpty() || !dateStr.matches(Regex("\\d{2}\\.\\d{2}\\.\\d{4}"))) {
                            continue
                        }
                        
                        // Час (колонка 3, индекс 2) - это номер пары
                        val hourStr = cells[2].text().trim()
                        val lessonNumber = hourStr.toIntOrNull()
                        if (lessonNumber == null || lessonNumber < 1 || lessonNumber > 10) {
                            continue
                        }
                        
                        // Группа (колонка 4, индекс 3)
                        val group = cells[3].text().trim()
                        
                        // П/г (колонка 5, индекс 4) - подгруппа
                        val subgroupStr = cells[4].text().trim()
                        val subgroup = if (subgroupStr == "0" || subgroupStr.isEmpty()) null else subgroupStr.toIntOrNull()
                        
                        // Преподаватель (колонка 6, индекс 5)
                        val teacher = cells[5].text().trim()
                        
                        // Аудитория (колонка 7, индекс 6)
                        val classroom = if (cells.size > 6) cells[6].text().trim() else ""
                        
                        // Определяем день недели из даты и нормализуем его
                        val dateFormat = java.text.SimpleDateFormat("dd.MM.yyyy", java.util.Locale.getDefault())
                        val date = dateFormat.parse(dateStr)
                        val dayName = if (date != null) {
                            val calendar = java.util.Calendar.getInstance()
                            calendar.time = date
                            // Calendar.DAY_OF_WEEK: 1=ВС, 2=ПН, 3=ВТ, 4=СР, 5=ЧТ, 6=ПТ, 7=СБ
                            val calendarDay = calendar.get(java.util.Calendar.DAY_OF_WEEK)
                            val dayNames = arrayOf("", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб")
                            val rawDayName = if (calendarDay in 1..7) dayNames[calendarDay] else ""
                            // Нормализуем день недели (убирает точки, нормализует регистр)
                            DayOfWeekEntity.normalizeDayName(rawDayName) ?: ""
                        } else ""
                        
                        // Определяем номер недели (можно использовать 1 по умолчанию, так как в журнале это не указано)
                        val weekNumber = 1
                        
                        journalLessons.add(
                            ScheduleItem(
                                day = dayName,
                                date = dateStr,
                                weekNumber = weekNumber,
                                lessonNumber = lessonNumber,
                                subject = subjectName ?: "Занятие",
                                classroom = if (classroom.isNotEmpty()) classroom else null,
                                teacher = if (teacher.isNotEmpty()) teacher else null,
                                subgroup = subgroup
                            )
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "Ошибка при парсинге строки журнала: ${e.message}", e)
                        continue
                    }
                }
            }
            
            Log.d(TAG, "Загружено ${journalLessons.size} фактических занятий из журнала $journalFile")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при парсинге журнала $journalFile: ${e.message}", e)
        }
        
        return@withContext journalLessons
    }
    
    /**
     * Получает список ссылок на журналы из страницы итогов (vg50.htm)
     * @param groupFile имя файла группы (например, "cg50.htm")
     * @param college колледж
     * @return список имен файлов журналов (например, ["j362.htm", "j360.htm"])
     */
    suspend fun fetchJournalLinks(groupFile: String, college: String = PreferencesManager.COLLEGE_CHTOTIB): List<String> = withContext(Dispatchers.IO) {
        val journalLinks = mutableListOf<String>()
        
        try {
            val baseUrl = if (college == PreferencesManager.COLLEGE_ZABGC) {
                BASE_URL_ZABGC
            } else {
                BASE_URL_CHTOTIB
            }
            
            // Преобразуем cg50.htm в vg50.htm (итоги группы)
            val resultsFile = groupFile.replace("cg", "vg").replace("bg", "vg")
            val resultsUrl = "$baseUrl$resultsFile"
            Log.d(TAG, "Загрузка итогов для получения ссылок на журналы: $resultsUrl")
            
            val doc: Document = try {
                Jsoup.connect(resultsUrl)
                    .timeout(20000)
                    .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                    .followRedirects(true)
                    .parser(org.jsoup.parser.Parser.htmlParser())
                    .maxBodySize(10 * 1024 * 1024)
                    .get()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при загрузке итогов $resultsUrl: ${e.message}", e)
                return@withContext journalLinks
            }
            
            // Находим таблицу с итогами
            val table = doc.select("table.inf").firstOrNull()
            if (table == null) {
                Log.w(TAG, "Таблица итогов не найдена в $resultsUrl")
                return@withContext journalLinks
            }
            
            // Ищем ссылки на журналы в колонке "Факт, час." (ссылки вида j362.htm)
            val links = table.select("a[href^='j']")
            for (link in links) {
                val href = link.attr("href")
                if (href.matches(Regex("j\\d+\\.htm"))) {
                    if (!journalLinks.contains(href)) {
                        journalLinks.add(href)
                    }
                }
            }
            
            Log.d(TAG, "Найдено ${journalLinks.size} ссылок на журналы: $journalLinks")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении ссылок на журналы: ${e.message}", e)
        }
        
        return@withContext journalLinks
    }
}

