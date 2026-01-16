package com.example.raspisanie.repository

import android.content.Context
import android.util.Log
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleCache
import com.example.raspisanie.data.ScheduleParser
import com.example.raspisanie.data.ScheduleNotificationManager
import com.example.raspisanie.data.LessonsRepository
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
    private val lessonsRepository: LessonsRepository? = context?.let { LessonsRepository(it) }
    
    private val _schedule = MutableStateFlow<List<DaySchedule>>(emptyList())
    val schedule: StateFlow<List<DaySchedule>> = _schedule.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    suspend fun refreshSchedule(groupFile: String = "cg36.htm", college: String = PreferencesManager.COLLEGE_CHTOTIB, useCache: Boolean = true) {
        // Валидация входных параметров
        if (groupFile.isBlank() || college.isBlank()) {
            Log.e(TAG, "Неверные параметры: groupFile=$groupFile, college=$college")
            _error.value = "Неверные параметры запроса"
            _isLoading.value = false
            return
        }
        
        _isLoading.value = true
        _error.value = null
        
        val cacheEnabled = prefs?.cacheEnabled == true
        
        // Шаг 1: Попытка загрузить из кэша (если включен и useCache = true)
        // При useCache = false (автообновление) пропускаем кэш, но используем его как fallback при ошибках
        if (useCache && cacheEnabled && cache != null) {
            try {
                val cachedSchedule = cache.getCachedSchedule(groupFile, college)
                if (cachedSchedule != null && cachedSchedule.isNotEmpty()) {
                    Log.d(TAG, "✅ Загружено из кэша: ${cachedSchedule.size} дней для $groupFile/$college")
                    _schedule.value = cachedSchedule
                    context?.let { ScheduleNotificationManager.scheduleUpcomingEventNotifications(it, cachedSchedule) }
                    _isLoading.value = false
                    _error.value = null
                    
                    // Пытаемся обновить в фоне (не блокируя пользователя)
                    try {
                        val newSchedule = parser.fetchSchedule(groupFile, college)
                        if (newSchedule.isNotEmpty()) {
                            cache.cacheSchedule(newSchedule, groupFile, college)
                            _schedule.value = newSchedule
                            context?.let { ScheduleNotificationManager.handleScheduleUpdated(it, newSchedule) }
                            
                            // Сохраняем плановые занятия в БД
                            lessonsRepository?.savePlannedLessons(newSchedule, groupFile, college)
                            
                            Log.d(TAG, "✅ Расписание обновлено в фоне: ${newSchedule.size} дней")
                        }
                    } catch (e: Exception) {
                        Log.d(TAG, "Не удалось обновить в фоне (используем кэш): ${e.message}")
                    }
                    
                    // Сохраняем кэшированные занятия в БД
                    lessonsRepository?.savePlannedLessons(cachedSchedule, groupFile, college)
                    return
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при чтении кэша: ${e.message}", e)
            }
        }
        
        // Шаг 2: Загрузка с сервера
        Log.d(TAG, "Загрузка расписания с сервера для $groupFile/$college (useCache=$useCache)")
        try {
            val newSchedule = parser.fetchSchedule(groupFile, college)
            Log.d(TAG, "✅ Расписание получено с сервера: ${newSchedule.size} дней")
            
            // Сохраняем в кэш (всегда, если кэш включен)
            if (newSchedule.isNotEmpty() && cacheEnabled && cache != null) {
                try {
                    cache.cacheSchedule(newSchedule, groupFile, college)
                    Log.d(TAG, "✅ Расписание сохранено в кэш")
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при сохранении в кэш: ${e.message}", e)
                }
            }
            
            // Сохраняем плановые занятия в БД для истории
            if (newSchedule.isNotEmpty()) {
                try {
                    lessonsRepository?.savePlannedLessons(newSchedule, groupFile, college)
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при сохранении занятий в БД: ${e.message}", e)
                }
            }
            
            _schedule.value = newSchedule
            context?.let { ScheduleNotificationManager.handleScheduleUpdated(it, newSchedule) }
            if (newSchedule.isEmpty()) {
                _error.value = "Расписание не найдено"
            }
            _isLoading.value = false
            
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка загрузки с сервера: ${e.message}", e)
            
            // Шаг 3: При ошибке сети ВСЕГДА пытаемся загрузить из кэша (даже если useCache = false)
            // Это важно для автообновления - виджеты должны обновляться из кэша при отсутствии интернета
            val networkError = e is java.net.UnknownHostException || 
                              e is java.net.SocketTimeoutException || 
                              e is java.net.ConnectException || 
                              e is java.io.IOException
            
            if (networkError && cacheEnabled && cache != null) {
                try {
                    val cachedSchedule = cache.getCachedSchedule(groupFile, college)
                    if (cachedSchedule != null && cachedSchedule.isNotEmpty()) {
                        val cacheMessage = if (useCache) {
                            "Нет подключения к интернету. Показано закэшированное расписание."
                        } else {
                            // При автообновлении не показываем ошибку пользователю, просто используем кэш
                            null
                        }
                        Log.d(TAG, "✅ Использую кэш из-за ошибки сети: ${cachedSchedule.size} дней (useCache=$useCache)")
                        _schedule.value = cachedSchedule
                        context?.let { ScheduleNotificationManager.scheduleUpcomingEventNotifications(it, cachedSchedule) }
                        
                        // Сохраняем кэшированные занятия в БД
                        lessonsRepository?.savePlannedLessons(cachedSchedule, groupFile, college)
                        
                        _error.value = cacheMessage
                        _isLoading.value = false
                        return
                    } else {
                        Log.d(TAG, "Кэш пуст для $groupFile/$college при ошибке сети")
                    }
                } catch (cacheException: Exception) {
                    Log.e(TAG, "Ошибка при чтении кэша: ${cacheException.message}", cacheException)
                }
            }
            
            // Если кэша нет или ошибка не связана с сетью
            // При автообновлении (useCache = false) не устанавливаем ошибку, чтобы не мешать виджетам
            if (useCache) {
                _error.value = when (e) {
                    is java.net.UnknownHostException -> "Нет подключения к интернету"
                    is java.net.SocketTimeoutException -> "Таймаут подключения"
                    is java.net.ConnectException -> "Ошибка подключения"
                    is java.io.IOException -> "Ошибка сети: ${e.message}"
                    else -> "Ошибка загрузки: ${e.message ?: e.javaClass.simpleName}"
                }
            } else {
                // При автообновлении просто логируем ошибку, но не устанавливаем её в StateFlow
                Log.d(TAG, "Автообновление: ошибка сети, кэш недоступен")
            }
            _isLoading.value = false
        }
    }
    
}
