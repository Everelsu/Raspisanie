package com.example.raspisanie.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import android.util.Log

class GroupsListParser {
    companion object {
        private const val TAG = "GroupsListParser"
        private const val GROUPS_LIST_URL_CHTOTIB = "https://www.chtotib.ru/schedule_gl/cg.htm"
        private const val GROUPS_LIST_URL_ZABGC = "https://bbb.zabgc.ru/cg.htm"
        private const val CACHE_TTL_MS = 24 * 60 * 60 * 1000L // 24 часа вместо 5 минут
        private val cacheMutex = Mutex()
        private val cachedGroups = mutableMapOf<String, CachedEntry>()
    }

    private data class CachedEntry(
        val timestamp: Long,
        val groups: List<Group>
    )
    
    /**
     * Очистить кеш для конкретного техникума (например, при принудительном обновлении)
     */
    suspend fun clearCache(college: String? = null) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        cacheMutex.withLock {
            if (college != null) {
                cachedGroups.remove(college)
                Log.d(TAG, "Кеш очищен для техникума: $college")
            } else {
                cachedGroups.clear()
                Log.d(TAG, "Весь кеш очищен")
            }
        }
    }

    suspend fun fetchGroupsList(
        college: String = PreferencesManager.COLLEGE_CHTOTIB,
        context: Context? = null,
        forceRefresh: Boolean = false
    ): List<Group> = withContext(Dispatchers.IO) {
        try {
            // Сначала проверяем персистентный кеш (если контекст предоставлен)
            if (context != null && !forceRefresh) {
                val cachedGroupsFromStorage = GroupsCacheManager.getCachedGroups(context, college)
                if (cachedGroupsFromStorage != null && cachedGroupsFromStorage.isNotEmpty()) {
                    // Также обновляем in-memory кеш
                    cacheMutex.withLock {
                        cachedGroups[college] = CachedEntry(System.currentTimeMillis(), cachedGroupsFromStorage)
                    }
                    Log.d(TAG, "Использую персистентный кеш для $college (${cachedGroupsFromStorage.size} групп)")
                    return@withContext cachedGroupsFromStorage
                }
            }
            
            // Затем проверяем in-memory кеш
            cacheMutex.withLock {
                val cached = cachedGroups[college]
                if (cached != null && System.currentTimeMillis() - cached.timestamp < CACHE_TTL_MS) {
                    Log.d(TAG, "Использую in-memory кеш для $college (${cached.groups.size})")
                    return@withContext cached.groups
                }
            }

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

            val result = groups.distinctBy { it.fileName }
            
            // Сохраняем в in-memory кеш
            cacheMutex.withLock {
                cachedGroups[college] = CachedEntry(System.currentTimeMillis(), result)
            }
            
            // Сохраняем в персистентный кеш (если контекст предоставлен)
            if (context != null) {
                GroupsCacheManager.saveGroups(context, college, result)
            }
            
            Log.d(TAG, "Парсинг завершен. Найдено групп: ${result.size}")
            return@withContext result
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при парсинге списка групп", e)
            throw e
        }
    }
}

