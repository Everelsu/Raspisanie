package com.example.raspisanie.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class ScheduleCache(context: Context) {
    private val prefs: SharedPreferences = 
        context.getSharedPreferences(CACHE_PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()
    
    companion object {
        private const val CACHE_PREFS_NAME = "schedule_cache_v2"
        private const val CACHE_EXPIRY_HOURS = 24 * 7 // Cache expires after 7 days
        private const val TAG = "ScheduleCache"
        
        // Префиксы для ключей
        private const val PREFIX_SCHEDULE = "schedule_"
        private const val PREFIX_TIMESTAMP = "timestamp_"
        private const val PREFIX_LAST_GROUP = "last_group_"
        private const val PREFIX_LAST_COLLEGE = "last_college_"
    }
    
    /**
     * Создать уникальный ключ для комбинации college и groupFile
     */
    private fun createCacheKey(college: String, groupFile: String): String {
        // Используем URL encoding для безопасного создания ключа
        val encodedCollege = URLEncoder.encode(college, StandardCharsets.UTF_8.toString())
        val encodedGroupFile = URLEncoder.encode(groupFile, StandardCharsets.UTF_8.toString())
        return "${encodedCollege}_${encodedGroupFile}"
    }
    
    /**
     * Получить ключ для хранения расписания
     */
    private fun getScheduleKey(college: String, groupFile: String): String {
        return PREFIX_SCHEDULE + createCacheKey(college, groupFile)
    }
    
    /**
     * Получить ключ для хранения timestamp
     */
    private fun getTimestampKey(college: String, groupFile: String): String {
        return PREFIX_TIMESTAMP + createCacheKey(college, groupFile)
    }
    
    /**
     * Сохранить расписание в кэш
     */
    fun cacheSchedule(schedules: List<DaySchedule>, groupFile: String, college: String) {
        if (groupFile.isBlank() || college.isBlank()) {
            Log.w(TAG, "Попытка кэширования с пустыми параметрами: groupFile=$groupFile, college=$college")
            return
        }
        
        if (schedules.isEmpty()) {
            Log.w(TAG, "Попытка кэширования пустого расписания для $groupFile/$college")
            return
        }
        
        try {
            val type = object : TypeToken<List<DaySchedule>>() {}.type
            val json = gson.toJson(schedules, type)
            
            if (json.isBlank()) {
                Log.e(TAG, "Ошибка: JSON сериализация вернула пустую строку")
                return
            }
            
            val scheduleKey = getScheduleKey(college, groupFile)
            val timestampKey = getTimestampKey(college, groupFile)
            val timestamp = System.currentTimeMillis()
            
            // Используем commit() для гарантированного сохранения
            val success = prefs.edit()
                .putString(scheduleKey, json)
                .putLong(timestampKey, timestamp)
                .putString(PREFIX_LAST_GROUP, groupFile)
                .putString(PREFIX_LAST_COLLEGE, college)
                .commit()
            
            if (success) {
                Log.d(TAG, "✅ Расписание закэшировано: ${schedules.size} дней для группы $groupFile/$college")
                Log.d(TAG, "   Ключ кэша: $scheduleKey, timestamp: $timestamp")
                
                // Проверка сохранения
                val savedJson = prefs.getString(scheduleKey, null)
                val savedTimestamp = prefs.getLong(timestampKey, 0)
                if (savedJson != null && savedTimestamp > 0) {
                    Log.d(TAG, "✅ Проверка: данные сохранены корректно (размер JSON: ${savedJson.length} символов)")
                } else {
                    Log.e(TAG, "❌ ОШИБКА: Данные не сохранились! savedJson=${savedJson != null}, savedTimestamp=$savedTimestamp")
                }
            } else {
                Log.e(TAG, "❌ Не удалось сохранить расписание в кэш (commit вернул false)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при кэшировании расписания для $groupFile/$college", e)
        }
    }
    
    /**
     * Получить расписание из кэша
     */
    fun getCachedSchedule(groupFile: String, college: String): List<DaySchedule>? {
        if (groupFile.isBlank() || college.isBlank()) {
            Log.w(TAG, "❌ Пустые параметры запроса кэша: groupFile=$groupFile, college=$college")
            return null
        }
        
        try {
            val scheduleKey = getScheduleKey(college, groupFile)
            val timestampKey = getTimestampKey(college, groupFile)
            
            // Проверить наличие timestamp
            val timestamp = prefs.getLong(timestampKey, 0)
            if (timestamp <= 0) {
                Log.d(TAG, "❌ Кэш отсутствует для $groupFile/$college (timestamp = 0)")
                return null
            }
            
            // Проверить срок действия кэша
            val ageHours = (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
            if (ageHours > CACHE_EXPIRY_HOURS) {
                Log.d(TAG, "❌ Кэш устарел для $groupFile/$college: $ageHours часов (максимум $CACHE_EXPIRY_HOURS)")
                // Удаляем устаревший кэш
                prefs.edit()
                    .remove(scheduleKey)
                    .remove(timestampKey)
                    .apply()
                return null
            }
            
            // Загрузить JSON
            val json = prefs.getString(scheduleKey, null) ?: run {
                Log.d(TAG, "❌ Кэш отсутствует для $groupFile/$college (JSON = null)")
                return null
            }
            
            if (json.isBlank()) {
                Log.d(TAG, "❌ Кэш пуст для $groupFile/$college (json пустой)")
                return null
            }
            
            // Десериализовать
            val type = object : TypeToken<List<DaySchedule>>() {}.type
            val schedules = gson.fromJson<List<DaySchedule>>(json, type)
            
            if (schedules.isNullOrEmpty()) {
                Log.d(TAG, "❌ Кэш содержит пустое расписание для $groupFile/$college")
                return null
            }
            
            Log.d(TAG, "✅ Расписание загружено из кэша: ${schedules.size} дней для $groupFile/$college (возраст: $ageHours часов)")
            return schedules
        } catch (e: Exception) {
            Log.e(TAG, "❌ Ошибка при загрузке расписания из кэша для $groupFile/$college", e)
            return null
        }
    }
    
    /**
     * Проверить, есть ли валидный кэш
     */
    fun hasValidCache(groupFile: String, college: String): Boolean {
        if (groupFile.isBlank() || college.isBlank()) {
            return false
        }
        
        try {
            val timestampKey = getTimestampKey(college, groupFile)
            val timestamp = prefs.getLong(timestampKey, 0)
            
            if (timestamp <= 0) {
                return false
            }
            
            val ageHours = (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
            return ageHours <= CACHE_EXPIRY_HOURS
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при проверке кэша", e)
            return false
        }
    }
    
    /**
     * Очистить кэш для конкретной группы
     */
    fun clearCacheForGroup(groupFile: String, college: String) {
        if (groupFile.isBlank() || college.isBlank()) {
            return
        }
        
        try {
            val scheduleKey = getScheduleKey(college, groupFile)
            val timestampKey = getTimestampKey(college, groupFile)
            
            prefs.edit()
                .remove(scheduleKey)
                .remove(timestampKey)
                .apply()
            
            Log.d(TAG, "Кэш очищен для группы $groupFile/$college")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при очистке кэша", e)
        }
    }
    
    /**
     * Очистить весь кэш
     */
    fun clearCache() {
        try {
            val allKeys = prefs.all.keys
            val editor = prefs.edit()
            
            // Удаляем только ключи, связанные с кэшем расписания
            allKeys.forEach { key ->
                if (key.startsWith(PREFIX_SCHEDULE) || 
                    key.startsWith(PREFIX_TIMESTAMP) ||
                    key.startsWith(PREFIX_LAST_GROUP) ||
                    key.startsWith(PREFIX_LAST_COLLEGE)) {
                    editor.remove(key)
                }
            }
            
            editor.apply()
            Log.d(TAG, "Весь кэш очищен")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при очистке всего кэша", e)
        }
    }
    
    /**
     * Получить возраст кэша в часах для конкретной группы
     */
    fun getCacheAgeHours(groupFile: String, college: String): Long {
        if (groupFile.isBlank() || college.isBlank()) {
            return -1
        }
        
        try {
            val timestampKey = getTimestampKey(college, groupFile)
            val timestamp = prefs.getLong(timestampKey, 0)
            return if (timestamp > 0) {
                (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
            } else {
                -1
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении возраста кэша", e)
            return -1
        }
    }
    
    /**
     * Получить список всех закэшированных групп
     */
    fun getCachedGroups(): List<Pair<String, String>> {
        val groups = mutableListOf<Pair<String, String>>()
        
        try {
            val allKeys = prefs.all.keys
            val scheduleKeys = allKeys.filter { it.startsWith(PREFIX_SCHEDULE) }
            
            scheduleKeys.forEach { key ->
                // Извлекаем college и groupFile из ключа
                val cacheKey = key.removePrefix(PREFIX_SCHEDULE)
                val parts = cacheKey.split("_", limit = 2)
                if (parts.size == 2) {
                    try {
                        val college = java.net.URLDecoder.decode(parts[0], StandardCharsets.UTF_8.toString())
                        val groupFile = java.net.URLDecoder.decode(parts[1], StandardCharsets.UTF_8.toString())
                        groups.add(Pair(college, groupFile))
                    } catch (e: Exception) {
                        Log.w(TAG, "Не удалось декодировать ключ кэша: $key", e)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении списка закэшированных групп", e)
        }
        
        return groups
    }
}

