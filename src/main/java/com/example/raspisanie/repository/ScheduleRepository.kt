package com.example.raspisanie.repository

import android.content.Context
import android.util.Log
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleCache
import com.example.raspisanie.data.ScheduleParser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class ScheduleRepository(private val context: Context? = null) {
    companion object {
        private const val TAG = "ScheduleRepository"
    }
    
    private val parser = ScheduleParser()
    private val cache: ScheduleCache? = context?.let { ScheduleCache(it) }
    private val prefs: PreferencesManager? = context?.let { PreferencesManager(it) }
    
    private val _schedule = MutableStateFlow<List<DaySchedule>>(emptyList())
    val schedule: StateFlow<List<DaySchedule>> = _schedule.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    suspend fun refreshSchedule(groupFile: String = "cg36.htm", college: String = PreferencesManager.COLLEGE_CHTOTIB, useCache: Boolean = true) {
        _isLoading.value = true
        _error.value = null
        
        try {
            // Try to load from cache first if enabled
            if (useCache && prefs?.cacheEnabled == true && cache != null) {
                val cachedSchedule = cache.getCachedSchedule(groupFile, college)
                if (cachedSchedule != null && cachedSchedule.isNotEmpty()) {
                    Log.d(TAG, "Загружено из кэша: ${cachedSchedule.size} дней")
                    _schedule.value = cachedSchedule
                    _isLoading.value = false
                    
                    // Still try to update in background
                    try {
                        val newSchedule = parser.fetchSchedule(groupFile, college)
                        if (newSchedule.isNotEmpty()) {
                            cache.cacheSchedule(newSchedule, groupFile, college)
                            _schedule.value = newSchedule
                            Log.d(TAG, "Расписание обновлено в фоне: ${newSchedule.size} дней")
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Не удалось обновить расписание в фоне: ${e.message}")
                        // Keep using cached version
                    }
                    return
                }
            }
            
            Log.d(TAG, "Начинаю обновление расписания для группы: $groupFile, техникум: $college")
            val newSchedule = parser.fetchSchedule(groupFile, college)
            Log.d(TAG, "Расписание получено: ${newSchedule.size} дней")
            
            // Cache the schedule
            if (newSchedule.isNotEmpty() && prefs?.cacheEnabled == true && cache != null) {
                cache.cacheSchedule(newSchedule, groupFile, college)
                Log.d(TAG, "Расписание закэшировано")
            }
            
            _schedule.value = newSchedule
            if (newSchedule.isEmpty()) {
                _error.value = "Расписание не найдено. Проверьте подключение к интернету."
            }
            
        } catch (e: java.net.UnknownHostException) {
            Log.e(TAG, "Ошибка сети: нет подключения к интернету", e)
            
            // Try to use cache if available
            if (prefs?.cacheEnabled == true && cache != null) {
                val cachedSchedule = cache.getCachedSchedule(groupFile, college)
                if (cachedSchedule != null && cachedSchedule.isNotEmpty()) {
                    Log.d(TAG, "Использую кэш из-за ошибки сети: ${cachedSchedule.size} дней")
                    _schedule.value = cachedSchedule
                    _error.value = "Нет подключения к интернету. Показано закэшированное расписание."
                    return
                }
            }
            
            _error.value = "Нет подключения к интернету"
        } catch (e: java.net.SocketTimeoutException) {
            Log.e(TAG, "Таймаут подключения", e)
            
            // Try to use cache if available
            if (prefs?.cacheEnabled == true && cache != null) {
                val cachedSchedule = cache.getCachedSchedule(groupFile, college)
                if (cachedSchedule != null && cachedSchedule.isNotEmpty()) {
                    Log.d(TAG, "Использую кэш из-за таймаута: ${cachedSchedule.size} дней")
                    _schedule.value = cachedSchedule
                    _error.value = "Таймаут подключения. Показано закэшированное расписание."
                    return
                }
            }
            
            _error.value = "Таймаут подключения. Проверьте интернет."
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка загрузки расписания", e)
            
            // Try to use cache if available
            if (prefs?.cacheEnabled == true && cache != null) {
                val cachedSchedule = cache.getCachedSchedule(groupFile, college)
                if (cachedSchedule != null && cachedSchedule.isNotEmpty()) {
                    Log.d(TAG, "Использую кэш из-за ошибки: ${cachedSchedule.size} дней")
                    _schedule.value = cachedSchedule
                    _error.value = "Ошибка загрузки. Показано закэшированное расписание."
                    return
                }
            }
            
            _error.value = e.message ?: "Ошибка загрузки расписания: ${e.javaClass.simpleName}"
        } finally {
            _isLoading.value = false
        }
    }
    
}
