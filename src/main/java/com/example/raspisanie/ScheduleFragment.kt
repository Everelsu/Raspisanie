package com.example.raspisanie

import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.example.raspisanie.adapter.ScheduleAdapter
import com.example.raspisanie.data.AutoRefreshManager
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.databinding.FragmentScheduleBinding
import com.example.raspisanie.viewmodel.ScheduleViewModel
import com.example.raspisanie.viewmodel.ScheduleViewModelFactory
import com.example.raspisanie.widget.CurrentLessonWidgetProvider
import com.example.raspisanie.widget.DayScheduleWidgetProvider
import kotlinx.coroutines.launch

class ScheduleFragment : Fragment() {
    companion object {
        private const val TAG = "ScheduleFragment"
    }
    
    private var _binding: FragmentScheduleBinding? = null
    private val binding get() = _binding!!
    
    private val viewModel: ScheduleViewModel by lazy {
        ViewModelProvider(requireActivity(), ScheduleViewModelFactory(requireContext()))[ScheduleViewModel::class.java]
    }
    private lateinit var adapter: ScheduleAdapter
    private lateinit var prefs: PreferencesManager
    private var lastKnownGroupFile: String = ""

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentScheduleBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        try {
            prefs = PreferencesManager(requireContext())
            lastKnownGroupFile = prefs.selectedGroupFile
            
            setupToolbar()
            setupRecyclerView()
            setupSwipeRefresh()
            applyNothingFontIfNeeded()
            observeViewModel()
            
            // Setup auto refresh
            try {
                if (prefs.autoRefreshEnabled) {
                    AutoRefreshManager.setupAutoRefresh(requireContext())
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при настройке автообновления: ${e.message}", e)
            }
            
            // Update widgets on startup
            try {
                updateWidgets()
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при обновлении виджетов: ${e.message}", e)
            }
            
            // Загрузить расписание для выбранной группы при первом запуске
            try {
                if (viewModel.schedule.value.isEmpty() && prefs.isGroupSelected()) {
                    viewModel.loadSchedule(prefs.selectedGroupFile, prefs.college)
                } else if (viewModel.schedule.value.isEmpty() && !prefs.isGroupSelected()) {
                    binding.emptyState.visibility = View.VISIBLE
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при загрузке расписания: ${e.message}", e)
                binding.errorText.text = "Ошибка инициализации: ${e.message}"
                binding.errorText.visibility = View.VISIBLE
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка в onViewCreated: ${e.message}", e)
        }
    }
    
    override fun onResume() {
        super.onResume()
        
        try {
            if (!::prefs.isInitialized) {
                return
            }
            
            setupToolbar()
            // Проверить изменение группы
            val selectedGroup = prefs.selectedGroupFile
            
            if (prefs.isGroupSelected()) {
                if (lastKnownGroupFile.isEmpty()) {
                    lastKnownGroupFile = selectedGroup
                }
                
                if (selectedGroup != lastKnownGroupFile) {
                    lastKnownGroupFile = selectedGroup
                    try {
                        viewModel.loadSchedule(selectedGroup, prefs.college)
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при загрузке расписания в onResume: ${e.message}", e)
                        showError("Ошибка загрузки: ${e.message}")
                    }
                } else if (viewModel.schedule.value.isEmpty()) {
                    try {
                        viewModel.loadSchedule(selectedGroup, prefs.college)
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при загрузке пустого расписания: ${e.message}", e)
                        showError("Ошибка загрузки: ${e.message}")
                    }
                } else {
                    try {
                        if (::adapter.isInitialized) {
                            adapter.forceUpdateProgress()
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обновлении прогресса: ${e.message}", e)
                    }
                }
            } else {
                try {
                    if (viewModel.schedule.value.isNotEmpty() && ::adapter.isInitialized) {
                        adapter.updateSchedules(emptyList())
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при очистке расписания: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка в onResume: ${e.message}", e)
        }
    }
    
    private fun updateWidgets() {
        try {
            val appWidgetManager = android.appwidget.AppWidgetManager.getInstance(requireContext())
            
            try {
                val currentLessonWidgetIds = appWidgetManager.getAppWidgetIds(
                    android.content.ComponentName(requireContext(), CurrentLessonWidgetProvider::class.java)
                )
                if (currentLessonWidgetIds.isNotEmpty()) {
                    for (widgetId in currentLessonWidgetIds) {
                        try {
                            CurrentLessonWidgetProvider.updateAppWidget(requireContext(), appWidgetManager, widgetId)
                        } catch (e: Exception) {
                            Log.w(TAG, "Не удалось обновить виджет текущего урока $widgetId: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Ошибка при обновлении виджетов текущего урока: ${e.message}")
            }
            
            try {
                val dayScheduleWidgetIds = appWidgetManager.getAppWidgetIds(
                    android.content.ComponentName(requireContext(), DayScheduleWidgetProvider::class.java)
                )
                if (dayScheduleWidgetIds.isNotEmpty()) {
                    for (widgetId in dayScheduleWidgetIds) {
                        try {
                            DayScheduleWidgetProvider.updateAppWidget(requireContext(), appWidgetManager, widgetId)
                        } catch (e: Exception) {
                            Log.w(TAG, "Не удалось обновить виджет расписания дня $widgetId: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Ошибка при обновлении виджетов расписания дня: ${e.message}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Общая ошибка при обновлении виджетов: ${e.message}", e)
        }
    }
    
    private fun applyNothingFontIfNeeded() {
        if (prefs.theme == PreferencesManager.THEME_NOTHING) {
            try {
                val ndotFont = resources.getFont(R.font.ndot)
                binding.root.post {
                    applyFontRecursive(binding.root, ndotFont)
                }
            } catch (e: Exception) {
                try {
                    val fallbackFont = resources.getFont(R.font.inter_regular)
                    binding.root.post {
                        applyFontRecursive(binding.root, fallbackFont)
                    }
                } catch (e2: Exception) {
                    // Ignore font loading errors
                }
            }
        }
    }
    
    private fun applyFontRecursive(view: View, font: android.graphics.Typeface) {
        when (view) {
            is TextView -> {
                view.typeface = font
            }
            is ViewGroup -> {
                for (i in 0 until view.childCount) {
                    applyFontRecursive(view.getChildAt(i), font)
                }
            }
        }
    }
    
    private fun showError(message: String) {
        try {
            binding.errorText.text = message
            binding.errorText.visibility = View.VISIBLE
            binding.emptyState.visibility = View.GONE
            binding.recyclerView.visibility = View.GONE
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при отображении ошибки: ${e.message}", e)
        }
    }

    private fun setupRecyclerView() {
        try {
            adapter = ScheduleAdapter(context = requireContext())
            binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
            binding.recyclerView.adapter = adapter
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при настройке RecyclerView: ${e.message}", e)
        }
    }

    private fun setupToolbar() {
        try {
            val toolbar = binding.toolbar
            toolbar.menu.clear()
            toolbar.setOnMenuItemClickListener(null)
            toolbar.setNavigationOnClickListener(null)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при настройке тулбара: ${e.message}", e)
        }
    }

    private fun setupSwipeRefresh() {
        try {
            binding.swipeRefresh.setOnRefreshListener {
                try {
                    if (prefs.isGroupSelected()) {
                        // Всегда вызываем refreshSchedule - он сам разберется с кэшем и сетью
                        // Если нет интернета, загрузится из кэша (если включен и есть)
                        viewModel.refreshSchedule(prefs.selectedGroupFile, prefs.college)
                    } else {
                        binding.swipeRefresh.isRefreshing = false
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при обновлении расписания: ${e.message}", e)
                    binding.swipeRefresh.isRefreshing = false
                    showError("Ошибка обновления: ${e.message}")
                }
            }
            
            try {
                val refreshColor = when (prefs.theme) {
                    PreferencesManager.THEME_LIGHT -> resources.getColor(android.R.color.black, null)
                    PreferencesManager.THEME_DARK -> resources.getColor(android.R.color.white, null)
                    PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.primaryNothing, null)
                    PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_colorPrimary, null)
                    PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_colorPrimary, null)
                    PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_colorPrimary, null)
                    PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_colorPrimary, null)
                    else -> resources.getColor(android.R.color.black, null)
                }
                binding.swipeRefresh.setColorSchemeColors(refreshColor)
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при настройке цвета refresh: ${e.message}", e)
                binding.swipeRefresh.setColorSchemeColors(resources.getColor(android.R.color.black, null))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при настройке SwipeRefresh: ${e.message}", e)
        }
    }
    
    private fun isNetworkAvailable(): Boolean {
        return try {
            val connectivityManager = requireContext().getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            val network = connectivityManager?.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
            capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) ||
                capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) ||
                capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при проверке сети: ${e.message}", e)
            false
        }
    }

    private fun observeViewModel() {
        lifecycleScope.launch {
            try {
                viewModel.schedule.collect { schedules ->
                    try {
                        Log.d(TAG, "Получено расписаний: ${schedules.size}")
                        if (!::adapter.isInitialized) {
                            Log.w(TAG, "Adapter не инициализирован")
                            return@collect
                        }
                        
                        if (schedules.isNotEmpty()) {
                            adapter.updateSchedules(schedules)
                            binding.emptyState.visibility = View.GONE
                            binding.errorText.visibility = View.GONE
                            binding.recyclerView.visibility = View.VISIBLE
                            Log.d(TAG, "Расписание отображается, всего дней: ${schedules.size}")
                            
                            try {
                                updateWidgets()
                            } catch (e: Exception) {
                                Log.e(TAG, "Ошибка при обновлении виджетов: ${e.message}", e)
                            }
                        } else {
                            binding.recyclerView.visibility = View.GONE
                            if (viewModel.error.value == null) {
                                binding.emptyState.visibility = View.VISIBLE
                                binding.errorText.visibility = View.GONE
                                Log.d(TAG, "Расписание пустое, показываю состояние загрузки")
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обработке расписания: ${e.message}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка в корутине schedule: ${e.message}", e)
            }
        }

        lifecycleScope.launch {
            try {
                viewModel.isLoading.collect { isLoading ->
                    try {
                        binding.swipeRefresh.isRefreshing = isLoading
                        if (isLoading) {
                            binding.emptyState.visibility = View.GONE
                            binding.errorText.visibility = View.GONE
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обработке загрузки: ${e.message}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка в корутине isLoading: ${e.message}", e)
            }
        }

        lifecycleScope.launch {
            try {
                viewModel.error.collect { error ->
                    try {
                        if (error != null) {
                            Log.e(TAG, "Ошибка загрузки: $error")
                            binding.errorText.text = "Ошибка: $error\n\nПотяните вниз для обновления"
                            binding.errorText.visibility = View.VISIBLE
                            binding.emptyState.visibility = View.GONE
                            binding.recyclerView.visibility = View.GONE
                        } else {
                            binding.errorText.visibility = View.GONE
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обработке ошибки: ${e.message}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка в корутине error: ${e.message}", e)
            }
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

