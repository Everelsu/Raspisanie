package com.example.raspisanie.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.repository.ScheduleRepository
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class ScheduleViewModel(private val context: android.content.Context? = null) : ViewModel() {
    private val repository = ScheduleRepository(context)

    val schedule: StateFlow<List<DaySchedule>> = repository.schedule
    val isLoading: StateFlow<Boolean> = repository.isLoading
    val error: StateFlow<String?> = repository.error

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
        val today = java.text.SimpleDateFormat("dd.MM.yyyy", java.util.Locale.getDefault())
            .format(java.util.Date())
        
        return schedule.value.firstOrNull { it.date == today }
            ?: schedule.value.firstOrNull()
    }
}

