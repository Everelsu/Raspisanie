package com.example.raspisanie.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.repository.ScheduleRepository
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScheduleViewModel(private val context: android.content.Context? = null) : ViewModel() {
    private val repository = ScheduleRepository(context)

    val schedule: StateFlow<List<DaySchedule>> = repository.schedule
    val isLoading: StateFlow<Boolean> = repository.isLoading
    val error: StateFlow<String?> = repository.error

    // Кэшируем форматтер даты для производительности
    private val dateFormatter = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

    fun loadSchedule(groupFile: String = "cg36.htm", college: String = com.example.raspisanie.data.PreferencesManager.COLLEGE_CHTOTIB) {
        viewModelScope.launch {
            repository.refreshSchedule(groupFile, college)
        }
    }

    fun refreshSchedule(groupFile: String = "cg36.htm", college: String = com.example.raspisanie.data.PreferencesManager.COLLEGE_CHTOTIB) {
        viewModelScope.launch {
            repository.refreshSchedule(groupFile, college)
        }
    }

    fun getTodaySchedule(): DaySchedule? {
        val today = dateFormatter.format(Date())
        
        return schedule.value.firstOrNull { it.date == today }
            ?: schedule.value.firstOrNull()
    }
}

