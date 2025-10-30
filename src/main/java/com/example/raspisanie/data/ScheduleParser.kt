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
        try {
            val baseUrl = if (college == PreferencesManager.COLLEGE_ZABGC) {
                BASE_URL_ZABGC
            } else {
                BASE_URL_CHTOTIB
            }
            val scheduleUrl = "$baseUrl$groupFile"
            Log.d(TAG, "Начинаю загрузку расписания с $scheduleUrl (техникум: $college)")
            val doc: Document = Jsoup.connect(scheduleUrl)
                .timeout(20000)
                .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .followRedirects(true)
                .get()
            
            Log.d(TAG, "HTML загружен, размер: ${doc.html().length} символов")

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
            
            for (row in rows) {
                val cells = row.select("td")
                if (cells.isEmpty()) continue

                // Skip header rows (contain "День" or "Пара" in header cells)
                if (cells.any { it.hasClass("hd") && (it.text().contains("День") || it.text().contains("Пара")) }) {
                    continue
                }
                
                // Skip separator rows (class "hd0")
                if (cells.any { it.hasClass("hd0") }) {
                    continue
                }

                // Check if first cell has rowspan - this is a day header
                val firstCell = cells.firstOrNull()
                if (firstCell != null && firstCell.hasAttr("rowspan")) {
                    // This is a new day row
                    // Get text directly from HTML to handle <br> tags properly
                    val dateHtml = firstCell.html()
                    val dateText = dateHtml.replace("<br>", "\n").replace("<br/>", "\n").replace("<BR>", "\n")
                    
                    // Parse date format: "30.10.2025\nЧт-1" or "30.10.2025<br>Чт-1"
                    // Extract day abbreviation (Чт, Пт, etc.) and week number
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
                        
                        Log.d(TAG, "Найден новый день: $currentDate $currentDay неделя $currentWeekNumber")
                    }
                }

                // If this row doesn't have rowspan in first cell (or firstCell is null due to rowspan), it's a lesson row
                // When rowspan is present, firstCell is only in first row of the day, subsequent rows have null firstCell
                val isLessonRow = (firstCell == null || !firstCell.hasAttr("rowspan")) && currentDay != null
                
                if (isLessonRow && cells.size >= 1) {
                    // Find the cell with lesson number - it has class "hd" and contains a number 1-8
                    var lessonNumber: Int? = null
                    var lessonCellIndex = -1
                    
                    for (i in cells.indices) {
                        val cell = cells[i]
                        // Skip cells that contain subjects (classes "ur" or "nul")
                        if (cell.hasClass("ur") || cell.hasClass("nul")) {
                            continue
                        }
                        
                        // Look for cell with class "hd" that contains a lesson number
                        if (cell.hasClass("hd")) {
                            val cellText = cell.text().trim()
                            val num = cellText.toIntOrNull()
                            if (num != null && num in 1..8) {
                                lessonNumber = num
                                lessonCellIndex = i
                                break
                            }
                        }
                    }
                    
                    if (lessonNumber != null && lessonNumber in 1..8) {
                        Log.d(TAG, "Найдена пара $lessonNumber для дня $currentDay (ячейка $lessonCellIndex)")
                        
                        // Subject columns are after lesson number cell
                        val subjectCells = cells.drop(lessonCellIndex + 1).filter { cell ->
                            // Only process cells with class "ur" (has lesson) or "nul" (empty)
                            val hasUrOrNul = cell.hasClass("ur") || cell.hasClass("nul")
                            if (!hasUrOrNul) {
                                Log.d(TAG, "Пропускаю ячейку без классов ur/nul: ${cell.className()}")
                            }
                            hasUrOrNul
                        }
                        
                        Log.d(TAG, "Найдено ${subjectCells.size} ячеек с занятиями для пары $lessonNumber")
                        
                        subjectCells.forEachIndexed { index, cell ->
                            if (cell.hasClass("ur")) {
                                // This cell has a lesson
                                val cellText = cell.text().trim()
                                Log.d(TAG, "Обрабатываю ячейку с занятием (индекс $index): ${cellText.take(50)}")
                                
                                val subjectInfo = parseSubjectCell(cell)
                                
                                Log.d(TAG, "Распарсено: предмет='${subjectInfo.subject}', аудитория='${subjectInfo.classroom}', преподаватель='${subjectInfo.teacher}'")
                                
                                if (subjectInfo.subject != null && subjectInfo.subject.isNotEmpty()) {
                                    dayItems.add(
                                        ScheduleItem(
                                            day = currentDay ?: "",
                                            date = currentDate ?: "",
                                            weekNumber = currentWeekNumber,
                                            lessonNumber = lessonNumber,
                                            subject = subjectInfo.subject,
                                            classroom = subjectInfo.classroom,
                                            teacher = subjectInfo.teacher,
                                            subgroup = if (subjectCells.size > 1) index + 1 else null
                                        )
                                    )
                                    Log.d(TAG, "Добавлено занятие: пара $lessonNumber, ${subjectInfo.subject}")
                                } else {
                                    Log.w(TAG, "Предмет не найден в ячейке для пары $lessonNumber")
                                }
                            }
                        }
                    } else {
                        // Debug: log what we found
                        if (cells.isNotEmpty() && currentDay != null) {
                            val cellTexts = cells.take(3).joinToString(" | ") { it.text().trim() }
                            Log.d(TAG, "Не удалось найти номер пары в строке (ячеек: ${cells.size}, первые 3: $cellTexts)")
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
            }

            Log.d(TAG, "Парсинг завершен. Найдено дней: ${schedules.size}, всего занятий: ${schedules.sumOf { it.items.size }}")
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
        Log.d(TAG, "Найдено ${allLinks.size} ссылок в ячейке")
        
        // Find subject link (class z1 or href starts with "j")
        val subjectLink = cell.select("a.z1").firstOrNull() 
            ?: allLinks.firstOrNull { it.attr("href").startsWith("j") && !it.attr("href").startsWith("cp") && !it.attr("href").startsWith("ca") }
        val subject = subjectLink?.text()?.trim()
        
        Log.d(TAG, "Предмет: '$subject'")
        
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
        
        Log.d(TAG, "Аудитория: '$classroom'")
        
        // Find teacher link (class z3 or href starts with "cp")
        val teacherLink = cell.select("a.z3").firstOrNull()
            ?: allLinks.firstOrNull { it.attr("href").startsWith("cp") }
        val teacher = teacherLink?.text()?.trim()

        Log.d(TAG, "Преподаватель: '$teacher'")

        return SubjectInfo(subject, classroom, teacher)
    }
}
