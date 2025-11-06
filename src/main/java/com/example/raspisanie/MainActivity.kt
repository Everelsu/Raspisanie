package com.example.raspisanie

import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.example.raspisanie.adapter.ScheduleAdapter
import com.example.raspisanie.data.AutoRefreshManager
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.databinding.ActivityMainBinding
import com.example.raspisanie.viewmodel.ScheduleViewModel
import com.example.raspisanie.viewmodel.ScheduleViewModelFactory
import com.example.raspisanie.widget.CurrentLessonWidgetProvider
import com.example.raspisanie.widget.DayScheduleWidgetProvider
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    companion object {
        private const val TAG = "MainActivity"
    }
    
    private lateinit var binding: ActivityMainBinding
    private val viewModel: ScheduleViewModel by lazy {
        ViewModelProvider(this, ScheduleViewModelFactory(applicationContext))[ScheduleViewModel::class.java]
    }
    private lateinit var adapter: ScheduleAdapter
    private lateinit var prefs: PreferencesManager
    private var currentThemeKey: String = ""
    private var lastKnownGroupFile: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        prefs = PreferencesManager(this)
        
        // Проверить первый запуск
        prefs.checkFirstLaunch()
        
        currentThemeKey = prefs.theme
        applyTheme(currentThemeKey)
        
        super.onCreate(savedInstanceState)
        
        // Инициализировать последнюю известную группу
        lastKnownGroupFile = prefs.selectedGroupFile
        enableEdgeToEdge()
        
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        Log.d(TAG, "MainActivity создана")

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        setupRecyclerView()
        setupSwipeRefresh()
        applyNothingFontIfNeeded()
        observeViewModel()
        
        // Setup auto refresh
        if (prefs.autoRefreshEnabled) {
            AutoRefreshManager.setupAutoRefresh(this)
        }
        
        // Setup app auto-update check
        if (prefs.appAutoUpdateEnabled) {
            com.example.raspisanie.data.AppUpdateManager.setupAutoUpdateCheck(this)
        }
        
        // Update widgets on startup
        updateWidgets()
        
        // Очистить старые APK файлы обновлений
        com.example.raspisanie.data.AppUpdateManager.cleanupOldApkFiles(this)
        
        // Проверить обновления при запуске (фоново, без уведомления если версия актуальна)
        com.example.raspisanie.data.AppUpdateManager.checkForUpdatesOnStartup(this)
        
        // Загрузить расписание для выбранной группы при первом запуске
        // Только если группа выбрана
        if (viewModel.schedule.value.isEmpty() && prefs.isGroupSelected()) {
            viewModel.loadSchedule(prefs.selectedGroupFile, prefs.college)
        } else if (viewModel.schedule.value.isEmpty() && !prefs.isGroupSelected()) {
            // Если группа не выбрана, показать сообщение
            binding.emptyState.visibility = android.view.View.VISIBLE
        }
    }
    
    private fun updateWidgets() {
        try {
            val appWidgetManager = android.appwidget.AppWidgetManager.getInstance(this)
            
            // Update CurrentLesson widgets
            try {
                val currentLessonWidgetIds = appWidgetManager.getAppWidgetIds(
                    android.content.ComponentName(this, CurrentLessonWidgetProvider::class.java)
                )
                if (currentLessonWidgetIds.isNotEmpty()) {
                    for (widgetId in currentLessonWidgetIds) {
                        try {
                            CurrentLessonWidgetProvider.updateAppWidget(this, appWidgetManager, widgetId)
                        } catch (e: Exception) {
                            Log.w(TAG, "Не удалось обновить виджет текущего урока $widgetId: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Ошибка при обновлении виджетов текущего урока: ${e.message}")
            }
            
            // Update DaySchedule widgets
            try {
                val dayScheduleWidgetIds = appWidgetManager.getAppWidgetIds(
                    android.content.ComponentName(this, DayScheduleWidgetProvider::class.java)
                )
                if (dayScheduleWidgetIds.isNotEmpty()) {
                    for (widgetId in dayScheduleWidgetIds) {
                        try {
                            DayScheduleWidgetProvider.updateAppWidget(this, appWidgetManager, widgetId)
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
            // Apply Nothing font to all text views
            try {
                val ndotFont = resources.getFont(R.font.ndot)
                binding.root.post {
                    applyFontRecursive(binding.root, ndotFont)
                }
            } catch (e: Exception) {
                // Fallback to inter if ndot not available
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
    
    override fun onResume() {
        super.onResume()
        
        // Проверить изменение темы
        val savedTheme = prefs.theme
        if (savedTheme != currentThemeKey) {
            currentThemeKey = savedTheme
            // При смене темы только обновляем UI, не загружаем заново данные
            recreate()
            return  // recreate() пересоздаст Activity, поэтому выходим
        }
        
        // Проверить изменение группы
        val selectedGroup = prefs.selectedGroupFile
        
        // Если группа выбрана
        if (prefs.isGroupSelected()) {
            if (lastKnownGroupFile.isEmpty()) {
                lastKnownGroupFile = selectedGroup
            }
            
            // Если группа изменилась - загрузить новое расписание
            if (selectedGroup != lastKnownGroupFile) {
                lastKnownGroupFile = selectedGroup
                viewModel.loadSchedule(selectedGroup, prefs.college)
            } else if (viewModel.schedule.value.isEmpty()) {
                // Если данных нет - загрузить расписание
                viewModel.loadSchedule(selectedGroup, prefs.college)
            } else {
                // Просто обновить адаптер для отражения изменений настроек (показ времени, перерывов и т.д.)
                // Это НЕ вызывает загрузку данных, только перерисовку UI
                // Принудительно обновляем прогресс при изменении настроек
                adapter.forceUpdateProgress()
            }
        } else {
            // Группа не выбрана - очистить расписание
            if (viewModel.schedule.value.isNotEmpty()) {
                adapter.updateSchedules(emptyList())
            }
        }
    }

    private fun setupRecyclerView() {
        adapter = ScheduleAdapter(context = this)
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = adapter
        
        // Add settings button/icon
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_settings -> {
                    val intent = android.content.Intent(this, SettingsActivity::class.java)
                    startActivity(intent)
                    true
                }
                else -> false
            }
        }
    }

    private fun setupSwipeRefresh() {
        binding.swipeRefresh.setOnRefreshListener {
            if (prefs.isGroupSelected()) {
                viewModel.refreshSchedule(prefs.selectedGroupFile, prefs.college)
            } else {
                binding.swipeRefresh.isRefreshing = false
            }
        }
        
        // Configure colors for refresh indicator based on theme
        val refreshColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(android.R.color.black, theme)
            PreferencesManager.THEME_DARK -> resources.getColor(android.R.color.white, theme)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.primaryNothing, theme)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_colorPrimary, theme) // Purple
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_colorPrimary, theme) // Halloween orange
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_colorPrimary, theme) // Green
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_colorPrimary, theme) // New Year green
            else -> resources.getColor(android.R.color.black, theme)
        }
        binding.swipeRefresh.setColorSchemeColors(refreshColor)
    }

    private fun observeViewModel() {
        lifecycleScope.launch {
            viewModel.schedule.collect { schedules ->
                Log.d(TAG, "Получено расписаний: ${schedules.size}")
                if (schedules.isNotEmpty()) {
                    adapter.updateSchedules(schedules)
                    binding.emptyState.visibility = android.view.View.GONE
                    binding.errorText.visibility = android.view.View.GONE
                    binding.recyclerView.visibility = android.view.View.VISIBLE
                    Log.d(TAG, "Расписание отображается, всего дней: ${schedules.size}")
                    
                    // Update widgets when schedule changes
                    updateWidgets()
                } else {
                    binding.recyclerView.visibility = android.view.View.GONE
                    if (viewModel.error.value == null) {
                        binding.emptyState.visibility = android.view.View.VISIBLE
                        binding.errorText.visibility = android.view.View.GONE
                        Log.d(TAG, "Расписание пустое, показываю состояние загрузки")
                    }
                }
            }
        }

        lifecycleScope.launch {
            viewModel.isLoading.collect { isLoading ->
                binding.swipeRefresh.isRefreshing = isLoading
                if (isLoading) {
                    binding.emptyState.visibility = android.view.View.GONE
                    binding.errorText.visibility = android.view.View.GONE
                }
            }
        }

        lifecycleScope.launch {
            viewModel.error.collect { error ->
                if (error != null) {
                    Log.e(TAG, "Ошибка загрузки: $error")
                    binding.errorText.text = "Ошибка: $error\n\nПотяните вниз для обновления"
                    binding.errorText.visibility = android.view.View.VISIBLE
                    binding.emptyState.visibility = android.view.View.GONE
                    binding.recyclerView.visibility = android.view.View.GONE
                } else {
                    binding.errorText.visibility = android.view.View.GONE
                }
            }
        }
    }


    private fun applyTheme(themeKey: String) {
        val themeResId = when (themeKey) {
            PreferencesManager.THEME_LIGHT -> R.style.Theme_Raspisanie_Light
            PreferencesManager.THEME_DARK -> R.style.Theme_Raspisanie_Dark
            PreferencesManager.THEME_PURPLE -> R.style.Theme_Raspisanie_System
            PreferencesManager.THEME_HALLOWEEN -> R.style.Theme_Raspisanie_Custom
            PreferencesManager.THEME_NOTHING -> R.style.Theme_Raspisanie_Nothing
            PreferencesManager.THEME_GREEN -> R.style.Theme_Raspisanie_Green
            PreferencesManager.THEME_NEW_YEAR -> R.style.Theme_Raspisanie_NewYear
            else -> {
                // Fallback - просто фиолетовая тема
                R.style.Theme_Raspisanie_System
            }
        }
        setTheme(themeResId)
    }
}