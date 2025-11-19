package com.example.raspisanie.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.google.gson.Gson
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class StatisticsCache(context: Context) {
    private val prefs: SharedPreferences = 
        context.getSharedPreferences(CACHE_PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()
    
    companion object {
        private const val CACHE_PREFS_NAME = "statistics_cache_v1"
        private const val CACHE_EXPIRY_HOURS = 24 * 7 // Cache expires after 7 days
        private const val TAG = "StatisticsCache"
        
        // Префиксы для ключей
        private const val PREFIX_STATISTICS = "statistics_"
        private const val PREFIX_TIMESTAMP = "timestamp_"
    }
    
    /**
     * Создать уникальный ключ для groupFile
     */
    private fun createCacheKey(groupFile: String): String {
        // Используем URL encoding для безопасного создания ключа
        return URLEncoder.encode(groupFile, StandardCharsets.UTF_8.toString())
    }
    
    /**
     * Получить ключ для хранения статистики
     */
    private fun getStatisticsKey(groupFile: String): String {
        return PREFIX_STATISTICS + createCacheKey(groupFile)
    }
    
    /**
     * Получить ключ для хранения timestamp
     */
    private fun getTimestampKey(groupFile: String): String {
        return PREFIX_TIMESTAMP + createCacheKey(groupFile)
    }
    
    /**
     * Сохранить статистику в кэш
     */
    fun cacheStatistics(statistics: GroupStatistics, groupFile: String) {
        if (groupFile.isBlank()) {
            Log.w(TAG, "Попытка кэширования с пустым groupFile")
            return
        }
        
        if (statistics.disciplines.isEmpty() && 
            statistics.totalHours == null && 
            statistics.completedHours == null && 
            statistics.remainingHours == null && 
            statistics.plannedHours == null) {
            Log.w(TAG, "Попытка кэширования пустой статистики для $groupFile")
            return
        }
        
        try {
            val json = gson.toJson(statistics)
            
            if (json.isBlank()) {
                Log.e(TAG, "Ошибка: JSON сериализация вернула пустую строку")
                return
            }
            
            val statisticsKey = getStatisticsKey(groupFile)
            val timestampKey = getTimestampKey(groupFile)
            val timestamp = System.currentTimeMillis()
            
            // Используем commit() для гарантированного сохранения
            val success = prefs.edit()
                .putString(statisticsKey, json)
                .putLong(timestampKey, timestamp)
                .commit()
            
            if (success) {
                Log.d(TAG, "✅ Статистика закэширована для группы $groupFile (${statistics.disciplines.size} дисциплин)")
                Log.d(TAG, "   Ключ кэша: $statisticsKey, timestamp: $timestamp")
            } else {
                Log.e(TAG, "❌ Не удалось сохранить статистику в кэш (commit вернул false)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при кэшировании статистики для $groupFile", e)
        }
    }
    
    /**
     * Получить статистику из кэша
     */
    fun getCachedStatistics(groupFile: String): GroupStatistics? {
        if (groupFile.isBlank()) {
            Log.w(TAG, "❌ Пустой groupFile при запросе кэша")
            return null
        }
        
        try {
            val statisticsKey = getStatisticsKey(groupFile)
            val timestampKey = getTimestampKey(groupFile)
            
            // Проверить наличие timestamp
            val timestamp = prefs.getLong(timestampKey, 0)
            if (timestamp <= 0) {
                Log.d(TAG, "❌ Кэш отсутствует для $groupFile (timestamp = 0)")
                return null
            }
            
            // Проверить срок действия кэша
            val ageHours = (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
            if (ageHours > CACHE_EXPIRY_HOURS) {
                Log.d(TAG, "❌ Кэш устарел для $groupFile: $ageHours часов (максимум $CACHE_EXPIRY_HOURS)")
                // Удаляем устаревший кэш
                prefs.edit()
                    .remove(statisticsKey)
                    .remove(timestampKey)
                    .apply()
                return null
            }
            
            // Загрузить JSON
            val json = prefs.getString(statisticsKey, null) ?: run {
                Log.d(TAG, "❌ Кэш отсутствует для $groupFile (JSON = null)")
                return null
            }
            
            if (json.isBlank()) {
                Log.d(TAG, "❌ Кэш пуст для $groupFile (json пустой)")
                return null
            }
            
            // Десериализовать
            val statistics = gson.fromJson(json, GroupStatistics::class.java)
            
            if (statistics.disciplines.isEmpty() && 
                statistics.totalHours == null && 
                statistics.completedHours == null && 
                statistics.remainingHours == null && 
                statistics.plannedHours == null) {
                Log.d(TAG, "❌ Кэш содержит пустую статистику для $groupFile")
                return null
            }
            
            Log.d(TAG, "✅ Статистика загружена из кэша для $groupFile (возраст: $ageHours часов, ${statistics.disciplines.size} дисциплин)")
            return statistics
        } catch (e: Exception) {
            Log.e(TAG, "❌ Ошибка при загрузке статистики из кэша для $groupFile", e)
            return null
        }
    }
    
    /**
     * Проверить, есть ли валидный кэш
     */
    fun hasValidCache(groupFile: String): Boolean {
        if (groupFile.isBlank()) {
            return false
        }
        
        try {
            val timestampKey = getTimestampKey(groupFile)
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
    fun clearCacheForGroup(groupFile: String) {
        if (groupFile.isBlank()) {
            return
        }
        
        try {
            val statisticsKey = getStatisticsKey(groupFile)
            val timestampKey = getTimestampKey(groupFile)
            
            prefs.edit()
                .remove(statisticsKey)
                .remove(timestampKey)
                .apply()
            
            Log.d(TAG, "Кэш статистики очищен для группы $groupFile")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при очистке кэша статистики", e)
        }
    }
    
    /**
     * Очистить весь кэш статистики
     */
    fun clearCache() {
        try {
            val allKeys = prefs.all.keys
            val editor = prefs.edit()
            
            // Удаляем только ключи, связанные с кэшем статистики
            allKeys.forEach { key ->
                if (key.startsWith(PREFIX_STATISTICS) || 
                    key.startsWith(PREFIX_TIMESTAMP)) {
                    editor.remove(key)
                }
            }
            
            editor.apply()
            Log.d(TAG, "Весь кэш статистики очищен")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при очистке всего кэша статистики", e)
        }
    }
}

