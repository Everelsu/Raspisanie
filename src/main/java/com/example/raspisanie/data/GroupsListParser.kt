package com.example.raspisanie.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import android.util.Log

class GroupsListParser {
    companion object {
        private const val TAG = "GroupsListParser"
        private const val GROUPS_LIST_URL_CHTOTIB = "https://www.chtotib.ru/schedule_gl/cg.htm"
        private const val GROUPS_LIST_URL_ZABGC = "https://bbb.zabgc.ru/cg.htm"
    }

    suspend fun fetchGroupsList(college: String = PreferencesManager.COLLEGE_CHTOTIB): List<Group> = withContext(Dispatchers.IO) {
        try {
            val groupsListUrl = if (college == PreferencesManager.COLLEGE_ZABGC) {
                GROUPS_LIST_URL_ZABGC
            } else {
                GROUPS_LIST_URL_CHTOTIB
            }
            
            val baseUrl = if (college == PreferencesManager.COLLEGE_ZABGC) {
                "https://bbb.zabgc.ru/"
            } else {
                "https://www.chtotib.ru/schedule_gl/"
            }
            
            Log.d(TAG, "Начинаю загрузку списка групп с $groupsListUrl (техникум: $college)")
            val doc: Document = Jsoup.connect(groupsListUrl)
                .timeout(20000)
                .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .followRedirects(true)
                .parser(org.jsoup.parser.Parser.htmlParser())
                .get()
            
            Log.d(TAG, "HTML загружен, размер: ${doc.html().length} символов")

            val groups = mutableListOf<Group>()
            
            // Find the table with class "inf" which contains groups list
            val table = doc.select("table.inf").firstOrNull()
            
            if (table == null) {
                Log.e(TAG, "Таблица со списком групп не найдена!")
                // Fallback: try to find any table
                val tables = doc.select("table")
                for (table in tables) {
                    val rows = table.select("tr")
                    for (row in rows) {
                        // Look for links that contain "cg" and ".htm" in href
                        val links = row.select("a[href*=cg][href*=htm], a.z0[href*=cg]")
                        
                        for (link in links) {
                            val href = link.attr("href")
                            val groupName = link.text().trim()
                            
                            // Extract filename from href (could be "cg36.htm" or relative path)
                            val fileName = if (href.contains("/")) {
                                href.substringAfterLast("/")
                            } else {
                                href
                            }.substringBefore("?") // Remove query params if any
                            
                            if (groupName.isNotEmpty() && fileName.isNotEmpty() && fileName.startsWith("cg") && fileName.endsWith(".htm")) {
                                groups.add(
                                    Group(
                                        name = groupName,
                                        url = "$baseUrl$fileName",
                                        fileName = fileName
                                    )
                                )
                                Log.d(TAG, "Найдена группа: $groupName -> $fileName")
                            }
                        }
                    }
                }
            } else {
                // Use the inf table
                val rows = table.select("tr")
                for (row in rows) {
                    // Skip header rows (contain "№ п.п" or "День" or "Пара" in header cells)
                    val headerCells = row.select("td.hd")
                    if (headerCells.isNotEmpty()) {
                        val headerText = row.text().lowercase()
                        if (headerText.contains("№ п.п") || 
                            headerText.contains("днев") || 
                            headerText.contains("пара") ||
                            headerText.contains("группа")) {
                            continue
                        }
                    }
                    
                    // Look for links that contain "cg" and ".htm" in href, or links with class "z0"
                    val links = row.select("a[href*=cg][href*=htm], a.z0[href*=cg], a[href^=cg]")
                    
                    for (link in links) {
                        val href = link.attr("href")
                        val groupName = link.text().trim()
                        
                        // Extract filename from href (could be "cg36.htm" or relative path)
                        val fileName = if (href.contains("/")) {
                            href.substringAfterLast("/")
                        } else {
                            href
                        }.substringBefore("?") // Remove query params if any
                        
                        if (groupName.isNotEmpty() && fileName.isNotEmpty() && fileName.startsWith("cg") && fileName.endsWith(".htm")) {
                            groups.add(
                                Group(
                                    name = groupName,
                                    url = "$baseUrl$fileName",
                                    fileName = fileName
                                )
                            )
                            Log.d(TAG, "Найдена группа: $groupName -> $fileName")
                        }
                    }
                }
            }
            
            Log.d(TAG, "Парсинг завершен. Найдено групп: ${groups.size}")
            return@withContext groups.distinctBy { it.fileName } // Remove duplicates
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при парсинге списка групп", e)
            throw e
        }
    }
}

