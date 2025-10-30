package com.example.raspisanie.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import android.util.Log

class GroupsListParser {
    companion object {
        private const val TAG = "GroupsListParser"
    }

    suspend fun fetchGroupsList(groupsListUrl: String): List<Group> = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Начинаю загрузку списка групп с $groupsListUrl")
            val doc: Document = Jsoup.connect(groupsListUrl)
                .timeout(20000)
                .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .followRedirects(true)
                .get()
            
            Log.d(TAG, "HTML загружен, размер: ${doc.html().length} символов")

            val groups = mutableListOf<Group>()
            
            // Find the table with groups list - it has groups with links like "cg36.htm"
            // The table structure: rows with group names and links
            val tables = doc.select("table")
            
            for (table in tables) {
                val rows = table.select("tr")
                for (row in rows) {
                    // Look for links that contain "cg" and ".htm" in href
                    val links = row.select("a[href*=cg][href*=htm]")
                    
                    for (link in links) {
                        val href = link.attr("href")
                        val groupName = link.text().trim()
                        
                        // Extract filename from href (could be "cg36.htm" or relative path)
                        val fileName = if (href.contains("/")) {
                            href.substringAfterLast("/")
                        } else {
                            href
                        }.substringBefore("?") // Remove query params if any
                        
                        if (groupName.isNotEmpty() && fileName.isNotEmpty() && fileName.endsWith(".htm")) {
                            groups.add(
                                Group(
                                    name = groupName,
                                    url = fileName, // store file name; full URL will be built by parser
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

