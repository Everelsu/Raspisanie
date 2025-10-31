package com.example.raspisanie.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.text.SimpleDateFormat
import java.util.*

class ScheduleCache(context: Context) {
    private val prefs: SharedPreferences = 
        context.getSharedPreferences(CACHE_PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()
    
    companion object {
        private const val CACHE_PREFS_NAME = "schedule_cache"
        private const val KEY_SCHEDULE_CACHE = "schedule_cache_data"
        private const val KEY_CACHE_TIMESTAMP = "cache_timestamp"
        private const val KEY_GROUP_FILE = "cached_group_file"
        private const val KEY_COLLEGE = "cached_college"
        private const val CACHE_EXPIRY_HOURS = 24 // Cache expires after 24 hours
        
        private const val TAG = "ScheduleCache"
    }
    
    /**
     * Сохранить расписание в кэш
     */
    fun cacheSchedule(schedules: List<DaySchedule>, groupFile: String, college: String) {
        try {
            val type = object : TypeToken<List<DaySchedule>>() {}.type
            val json = gson.toJson(schedules, type)
            
            prefs.edit()
                .putString(KEY_SCHEDULE_CACHE, json)
                .putLong(KEY_CACHE_TIMESTAMP, System.currentTimeMillis())
                .putString(KEY_GROUP_FILE, groupFile)
                .putString(KEY_COLLEGE, college)
                .apply()
            
            Log.d(TAG, "Расписание закэшировано: ${schedules.size} дней для группы $groupFile")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при кэшировании расписания", e)
        }
    }
    
    /**
     * Получить расписание из кэша
     */
    fun getCachedSchedule(groupFile: String, college: String): List<DaySchedule>? {
        try {
            // Проверить, что кэш для правильной группы и колледжа
            val cachedGroupFile = prefs.getString(KEY_GROUP_FILE, "")
            val cachedCollege = prefs.getString(KEY_COLLEGE, "")
            
            if (cachedGroupFile != groupFile || cachedCollege != college) {
                Log.d(TAG, "Кэш не соответствует запрошенной группе: $groupFile/$college vs $cachedGroupFile/$cachedCollege")
                return null
            }
            
            // Проверить срок действия кэша
            val timestamp = prefs.getLong(KEY_CACHE_TIMESTAMP, 0)
            val ageHours = (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
            
            if (ageHours > CACHE_EXPIRY_HOURS) {
                Log.d(TAG, "Кэш устарел: $ageHours часов (максимум $CACHE_EXPIRY_HOURS)")
                return null
            }
            
            val json = prefs.getString(KEY_SCHEDULE_CACHE, null) ?: return null
            val type = object : TypeToken<List<DaySchedule>>() {}.type
            val schedules = gson.fromJson<List<DaySchedule>>(json, type)
            
            Log.d(TAG, "Расписание загружено из кэша: ${schedules.size} дней (возраст: $ageHours часов)")
            return schedules
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при загрузке расписания из кэша", e)
            return null
        }
    }
    
    /**
     * Проверить, есть ли валидный кэш
     */
    fun hasValidCache(groupFile: String, college: String): Boolean {
        val cachedGroupFile = prefs.getString(KEY_GROUP_FILE, "")
        val cachedCollege = prefs.getString(KEY_COLLEGE, "")
        
        if (cachedGroupFile != groupFile || cachedCollege != college) {
            return false
        }
        
        val timestamp = prefs.getLong(KEY_CACHE_TIMESTAMP, 0)
        val ageHours = (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
        
        return ageHours <= CACHE_EXPIRY_HOURS
    }
    
    /**
     * Очистить кэш
     */
    fun clearCache() {
        prefs.edit().clear().apply()
        Log.d(TAG, "Кэш очищен")
    }
    
    /**
     * Получить возраст кэша в часах
     */
    fun getCacheAgeHours(): Long {
        val timestamp = prefs.getLong(KEY_CACHE_TIMESTAMP, 0)
        return if (timestamp > 0) {
            (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
        } else {
            -1
        }
    }
}

