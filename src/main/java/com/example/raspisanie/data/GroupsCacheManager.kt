package com.example.raspisanie.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Менеджер кеширования списков групп с персистентным хранением
 * Избегает повторного парсинга при каждом открытии настроек
 */
class GroupsCacheManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("groups_cache", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val groupsListParser = GroupsListParser()
    
    /**
     * Получить список групп (из кеша или загрузить с сервера)
     */
    suspend fun getGroups(college: String, forceRefresh: Boolean = false): List<Group> = withContext(Dispatchers.IO) {
        if (!forceRefresh) {
            val cached = getCachedGroups(college)
            if (cached != null && cached.isNotEmpty()) {
                Log.d(TAG, "Использую кешированные группы для $college (${cached.size} групп)")
                return@withContext cached
            }
        }
        
        // Загружаем с сервера
        try {
            Log.d(TAG, "Загружаю группы с сервера для $college")
            val groups = groupsListParser.fetchGroupsList(college)
            
            // Сохраняем в кеш
            saveGroups(college, groups)
            
            return@withContext groups
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при загрузке групп с сервера", e)
            
            // Пытаемся вернуть старый кеш, даже если он устарел
            val oldCache = getCachedGroups(college, ignoreTTL = true)
            if (oldCache != null && oldCache.isNotEmpty()) {
                Log.d(TAG, "Использую устаревший кеш из-за ошибки загрузки")
                return@withContext oldCache
            }
            
            return@withContext emptyList()
        }
    }
    
    /**
     * Сохранить список групп в кеш
     */
    private fun saveGroups(college: String, groups: List<Group>) {
        try {
            val groupsJson = gson.toJson(groups)
            prefs.edit()
                .putString("${KEY_CACHE_TIMESTAMP}$college", System.currentTimeMillis().toString())
                .putString("${KEY_CACHE_DATA}$college", groupsJson)
                .apply()
            Log.d(TAG, "Список групп сохранён в кеш для $college (${groups.size} групп)")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при сохранении кеша групп", e)
        }
    }
    
    /**
     * Получить список групп из кеша
     */
    private fun getCachedGroups(college: String, ignoreTTL: Boolean = false): List<Group>? {
        try {
            val timestampStr = prefs.getString("${KEY_CACHE_TIMESTAMP}$college", null)
            
            if (timestampStr == null) {
                Log.d(TAG, "Нет кешированных групп для $college")
                return null
            }
            
            val timestamp = timestampStr.toLongOrNull() ?: return null
            
            if (!ignoreTTL) {
                val age = System.currentTimeMillis() - timestamp
                
                if (age > CACHE_TTL_MS) {
                    Log.d(TAG, "Кеш групп для $college истёк (возраст: ${age / (60 * 60 * 1000)} часов)")
                    return null
                }
            }
            
            val groupsJson = prefs.getString("${KEY_CACHE_DATA}$college", null)
            if (groupsJson == null) {
                Log.d(TAG, "Нет данных групп в кеше для $college")
                return null
            }
            
            val type = object : TypeToken<List<Group>>() {}.type
            val groups = gson.fromJson<List<Group>>(groupsJson, type)
            
            Log.d(TAG, "Загружены группы из кеша для $college (${groups.size} групп)")
            return groups
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при загрузке кеша групп", e)
            return null
        }
    }
    
    companion object {
        private const val TAG = "GroupsCacheManager"
        const val KEY_CACHE_TIMESTAMP = "cache_timestamp_"
        const val KEY_CACHE_DATA = "cache_data_"
        const val CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000L // 7 дней
        
        /**
         * Сохранить список групп в кеш
         */
        fun saveGroups(context: Context, college: String, groups: List<Group>) {
            try {
                val prefs = context.getSharedPreferences("groups_cache", Context.MODE_PRIVATE)
                val gson = Gson()
                val groupsJson = gson.toJson(groups)
                
                prefs.edit()
                    .putString("${KEY_CACHE_TIMESTAMP}$college", System.currentTimeMillis().toString())
                    .putString("${KEY_CACHE_DATA}$college", groupsJson)
                    .apply()
                
                Log.d(TAG, "Список групп сохранён в кеш для $college (${groups.size} групп)")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при сохранении кеша групп", e)
            }
        }
        
        /**
         * Получить список групп из кеша (если не истёк)
         */
        fun getCachedGroups(context: Context, college: String): List<Group>? {
            try {
                val prefs = context.getSharedPreferences("groups_cache", Context.MODE_PRIVATE)
                val timestampStr = prefs.getString("${KEY_CACHE_TIMESTAMP}$college", null)
                
                if (timestampStr == null) {
                    Log.d(TAG, "Нет кешированных групп для $college")
                    return null
                }
                
                val timestamp = timestampStr.toLongOrNull() ?: return null
                val age = System.currentTimeMillis() - timestamp
                
                if (age > CACHE_TTL_MS) {
                    Log.d(TAG, "Кеш групп для $college истёк (возраст: ${age / (60 * 60 * 1000)} часов)")
                    return null
                }
                
                val groupsJson = prefs.getString("${KEY_CACHE_DATA}$college", null)
                if (groupsJson == null) {
                    Log.d(TAG, "Нет данных групп в кеше для $college")
                    return null
                }
                
                val gson = Gson()
                val type = object : TypeToken<List<Group>>() {}.type
                val groups = gson.fromJson<List<Group>>(groupsJson, type)
                
                Log.d(TAG, "Загружены группы из кеша для $college (${groups.size} групп, возраст: ${age / (60 * 60 * 1000)} часов)")
                return groups
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при загрузке кеша групп", e)
                return null
            }
        }
        
        /**
         * Очистить кеш для конкретного техникума
         */
        fun clearCache(context: Context, college: String? = null) {
            val prefs = context.getSharedPreferences("groups_cache", Context.MODE_PRIVATE)
            if (college != null) {
                prefs.edit()
                    .remove("${KEY_CACHE_TIMESTAMP}$college")
                    .remove("${KEY_CACHE_DATA}$college")
                    .apply()
                Log.d(TAG, "Кеш очищен для техникума: $college")
            } else {
                prefs.edit().clear().apply()
                Log.d(TAG, "Весь кеш групп очищен")
            }
        }
        
        /**
         * Проверить, нужно ли обновлять кеш
         */
        fun shouldRefreshCache(context: Context, college: String): Boolean {
            val prefs = context.getSharedPreferences("groups_cache", Context.MODE_PRIVATE)
            val timestampStr = prefs.getString("${KEY_CACHE_TIMESTAMP}$college", null)
            
            if (timestampStr == null) return true
            
            val timestamp = timestampStr.toLongOrNull() ?: return true
            val age = System.currentTimeMillis() - timestamp
            
            return age > CACHE_TTL_MS
        }
    }
}
