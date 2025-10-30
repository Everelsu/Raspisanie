package com.example.raspisanie.repository

import android.util.Log
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.data.ScheduleParser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class ScheduleRepository {
    companion object {
        private const val TAG = "ScheduleRepository"
    }
    
    private val parser = ScheduleParser()
    private val _schedule = MutableStateFlow<List<DaySchedule>>(emptyList())
    val schedule: StateFlow<List<DaySchedule>> = _schedule.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    suspend fun refreshSchedule(groupFile: String, baseUrl: String) {
        _isLoading.value = true
        _error.value = null
        
        try {
            Log.d(TAG, "Начинаю обновление расписания: $groupFile (base=$baseUrl)")
            val newSchedule = parser.fetchSchedule(groupFile, baseUrl)
            Log.d(TAG, "Расписание получено: ${newSchedule.size} дней")
            _schedule.value = newSchedule
            if (newSchedule.isEmpty()) {
                _error.value = "Расписание не найдено. Проверьте подключение к интернету."
            }
        } catch (e: java.net.UnknownHostException) {
            Log.e(TAG, "Ошибка сети: нет подключения к интернету", e)
            _error.value = "Нет подключения к интернету"
        } catch (e: java.net.SocketTimeoutException) {
            Log.e(TAG, "Таймаут подключения", e)
            _error.value = "Таймаут подключения. Проверьте интернет."
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка загрузки расписания", e)
            _error.value = e.message ?: "Ошибка загрузки расписания: ${e.javaClass.simpleName}"
        } finally {
            _isLoading.value = false
        }
    }
}
