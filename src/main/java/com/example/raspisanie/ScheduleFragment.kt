package com.example.raspisanie

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.raspisanie.adapter.ScheduleAdapter
import com.example.raspisanie.data.AutoRefreshManager
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.databinding.FragmentScheduleBinding
import com.example.raspisanie.viewmodel.ScheduleViewModel
import com.example.raspisanie.viewmodel.ScheduleViewModelFactory
import com.example.raspisanie.widget.CurrentLessonWidgetProvider
import com.example.raspisanie.widget.DayScheduleWidgetProvider
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import com.google.android.material.datepicker.MaterialDatePicker
import com.google.android.material.datepicker.CalendarConstraints
import com.google.android.material.datepicker.CompositeDateValidator
import com.google.android.material.datepicker.DateValidatorPointBackward
import com.google.android.material.datepicker.DateValidatorPointForward

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
    private var selectedDaySchedule: com.example.raspisanie.data.DaySchedule? = null
    private var lastKnownGroupFile: String = ""
    private val prefsChangeListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (!::prefs.isInitialized) return@OnSharedPreferenceChangeListener
        
        // Widgets need explicit refresh for theme/font changes
        if (key == "theme" || key == "font_size") {
            try {
                com.example.raspisanie.widget.WidgetUpdateHelper.updateAll(requireContext())
            } catch (_: Exception) {
                // ignore
            }
        }
        
        if (prefs.isGroupOrCollegeKey(key)) {
            if (prefs.isGroupSelected()) {
                lastKnownGroupFile = prefs.selectedGroupFile
                viewLifecycleOwner.lifecycleScope.launch {
                    viewModel.refreshSchedule(prefs.selectedGroupFile, prefs.college)
                }
            } else {
                viewLifecycleOwner.lifecycleScope.launch {
                    if (::adapter.isInitialized) {
                        adapter.updateSchedules(emptyList(), null, null)
                    }
                }
            }
        }
    }

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
            prefs.registerChangeListener(prefsChangeListener)
            
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
            
            // Сбрасываем выбранный день при смене группы
            if (lastKnownGroupFile.isNotEmpty() && lastKnownGroupFile != selectedGroup) {
                selectedDaySchedule = null
            }
            
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
                            // Обновляем статусы при возврате на страницу и возобновляем обновления
                            val safeBinding = _binding
                            if (safeBinding != null) {
                                adapter.resumeUpdates(safeBinding.recyclerView)
                                adapter.forceUpdateStatuses(safeBinding.recyclerView)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обновлении прогресса: ${e.message}", e)
                    }
                }
            } else {
                try {
                    if (viewModel.schedule.value.isNotEmpty() && ::adapter.isInitialized) {
                        adapter.updateSchedules(emptyList(), null, null)
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
            
            // Плавная анимация появления ошибки
            binding.errorText.alpha = 0f
            binding.errorText.translationY = -20f
            binding.errorText.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(300)
                .setInterpolator(android.view.animation.OvershootInterpolator(1.1f))
                .start()
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при отображении ошибки: ${e.message}", e)
        }
    }

    private fun setupRecyclerView() {
        try {
            adapter = ScheduleAdapter(
                context = requireContext(),
                onDayClickListener = { daySchedule ->
                    showCalendarDialog(daySchedule)
                },
                plannedDates = emptySet(), // Будет обновлено при загрузке расписания
                selectedDayDate = null, // Будет обновлено при выборе дня
                onSelectedDayRemoveListener = {
                    // Удаляем выбранный день из списка
                    selectedDaySchedule = null
                    // Обновляем список без выбранного дня
                    val currentSchedules = viewModel.schedule.value
                    val plannedDatesSet = currentSchedules.map { it.date }.toSet()
                    adapter.updateSchedules(currentSchedules, plannedDatesSet, null)
                    
                    // Показываем уведомление
                    Toast.makeText(requireContext(), "Выбранный день убран", Toast.LENGTH_SHORT).show()
                }
            )
            binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
            binding.recyclerView.adapter = adapter
            
            // улучшенный overscroll эффект
            binding.recyclerView.overScrollMode = View.OVER_SCROLL_ALWAYS
            
            // плавный скролл с инерцией
            binding.recyclerView.isNestedScrollingEnabled = true
            
            // Настройка цветного overscroll эффекта через стандартный API
            binding.recyclerView.edgeEffectFactory = object : RecyclerView.EdgeEffectFactory() {
                override fun createEdgeEffect(view: RecyclerView, direction: Int): android.widget.EdgeEffect {
                    return android.widget.EdgeEffect(view.context).apply {
                        val themeColor = when (prefs.theme) {
                            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(requireContext(), R.color.light_colorPrimary)
                            PreferencesManager.THEME_DARK -> ContextCompat.getColor(requireContext(), R.color.dark_colorPrimary)
                            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(requireContext(), R.color.system_colorPrimary)
                            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(requireContext(), R.color.custom_colorPrimary)
                            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(requireContext(), R.color.nothing_colorPrimary)
                            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(requireContext(), R.color.green_colorPrimary)
                            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(requireContext(), R.color.newyear_colorPrimary)
                            else -> ContextCompat.getColor(requireContext(), R.color.dark_colorPrimary)
                        }
                        color = themeColor
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при настройке RecyclerView: ${e.message}", e)
        }
    }

    private fun setupToolbar() {
        try {
            val toolbar = binding.toolbar
            toolbar.menu.clear()
            toolbar.setNavigationOnClickListener(null)
            
            // Прикольная анимация появления toolbar
            toolbar.alpha = 0f
            toolbar.translationY = -20f
            toolbar.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(400)
                .setStartDelay(100)
                .setInterpolator(android.view.animation.DecelerateInterpolator())
                .start()
            
            // Долгое нажатие на toolbar - скролл вверх
            toolbar.setOnLongClickListener {
                // Haptic feedback
                toolbar.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                // Плавная прокрутка вверх до самого верха
                binding.recyclerView.smoothScrollToPosition(0)
                // После завершения прокрутки делаем финальную корректировку с учетом padding
                binding.recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
                    override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                        if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                            val layoutManager = recyclerView.layoutManager as? androidx.recyclerview.widget.LinearLayoutManager
                            val paddingTop = recyclerView.paddingTop
                            if (layoutManager != null && paddingTop > 0) {
                                layoutManager.scrollToPositionWithOffset(0, paddingTop)
                            }
                            recyclerView.removeOnScrollListener(this)
                        }
                    }
                })
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при настройке тулбара: ${e.message}", e)
        }
    }

    private fun setupSwipeRefresh() {
        try {
            // Улучшенная анимация обновления
            binding.swipeRefresh.setProgressViewOffset(false, 0, 100)
            binding.swipeRefresh.setSlingshotDistance(200)
            
            binding.swipeRefresh.setOnRefreshListener {
                try {
                    if (prefs.isGroupSelected()) {
                        // Добавляем плавную анимацию начала обновления
                        binding.recyclerView.animate()
                            .alpha(0.7f)
                            .setDuration(200)
                            .start()
                        
                        // Всегда вызываем refreshSchedule - он сам разберется с кэшем и сетью
                        // Если нет интернета, загрузится из кэша (если включен и есть)
                        viewModel.refreshSchedule(prefs.selectedGroupFile, prefs.college)
                        
                        // Добавляем таймаут на случай, если isLoading не обновится
                        binding.swipeRefresh.postDelayed({
                            val safeBinding = _binding
                            if (safeBinding != null && safeBinding.swipeRefresh.isRefreshing) {
                                Log.w(TAG, "Таймаут обновления, останавливаем swipe refresh")
                                safeBinding.swipeRefresh.isRefreshing = false
                                safeBinding.recyclerView.animate()
                                    .alpha(1f)
                                    .setDuration(200)
                                    .start()
                            }
                        }, 10000) // 10 секунд таймаут
                    } else {
                        binding.swipeRefresh.isRefreshing = false
                        binding.recyclerView.animate()
                            .alpha(1f)
                            .setDuration(200)
                            .start()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при обновлении расписания: ${e.message}", e)
                    val safeBinding = _binding
                    if (safeBinding != null) {
                        safeBinding.swipeRefresh.isRefreshing = false
                        safeBinding.recyclerView.animate()
                            .alpha(1f)
                            .setDuration(200)
                            .start()
                    }
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
                        
                        // Фильтруем прошлые дни, если настройка отключена
                        // Сохраняем даты планового расписания для определения фактических
                        val plannedDatesSet = schedules.map { it.date }.toSet()
                        
                        // Если есть выбранный день - показываем его первым
                        val selectedDay = selectedDaySchedule // Сохраняем в локальную переменную для smart cast
                        val schedulesToShow = if (selectedDay != null) {
                            // Убираем выбранный день из списка, если он там есть, и ставим первым
                            val withoutSelected = schedules.filter { it.date != selectedDay.date }
                            listOf(selectedDay) + withoutSelected
                        } else {
                            schedules
                        }
                        
                        // Показываем только плановые расписания (фактические по запросу)
                        if (schedulesToShow.isNotEmpty()) {
                            adapter.updateSchedules(schedulesToShow, plannedDatesSet, selectedDay?.date)
                            
                            // Скроллим к выбранному дню, если он есть
                            if (selectedDay != null) {
                                binding.recyclerView.post {
                                    binding.recyclerView.smoothScrollToPosition(0)
                                }
                            }
                            binding.emptyState.visibility = View.GONE
                            binding.errorText.visibility = View.GONE
                            binding.recyclerView.visibility = View.VISIBLE
                            Log.d(TAG, "Расписание отображается, всего дней: ${schedules.size}")
                            
                            // Прикольная анимация появления RecyclerView
                            binding.recyclerView.alpha = 0f
                            binding.recyclerView.scaleX = 0.95f
                            binding.recyclerView.scaleY = 0.95f
                            binding.recyclerView.animate()
                                .alpha(1f)
                                .scaleX(1f)
                                .scaleY(1f)
                                .setDuration(400)
                                .setInterpolator(android.view.animation.OvershootInterpolator(0.8f))
                                .start()
                            
                            // Обновляем статусы после загрузки расписания
                            try {
                                adapter.forceUpdateStatuses(binding.recyclerView)
                            } catch (e: Exception) {
                                Log.e(TAG, "Ошибка при обновлении статусов: ${e.message}", e)
                            }
                            
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
                                
                                // Плавная анимация появления пустого состояния
                                binding.emptyState.alpha = 0f
                                binding.emptyState.translationY = 20f
                                binding.emptyState.animate()
                                    .alpha(1f)
                                    .translationY(0f)
                                    .setDuration(300)
                                    .setInterpolator(android.view.animation.OvershootInterpolator(1.1f))
                                    .start()
                                
                                Log.d(TAG, "Расписание пустое, показываю состояние загрузки")
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обработке расписания: ${e.message}", e)
                    }
                }
            } catch (e: CancellationException) {
                Log.d(TAG, "Collect schedule cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка в корутине schedule: ${e.message}", e)
            }
        }

        lifecycleScope.launch {
            try {
                viewModel.isLoading.collect { isLoading ->
                    try {
                        val binding = _binding ?: return@collect
                        binding.swipeRefresh.isRefreshing = isLoading
                        binding.swipeRefresh.isEnabled = !isLoading
                        if (isLoading) {
                            binding.emptyState.visibility = View.GONE
                            // Плавно уменьшаем прозрачность при загрузке
                            binding.recyclerView.animate()
                                .alpha(0.7f)
                                .setDuration(200)
                                .start()
                            binding.errorText.visibility = View.GONE
                        } else {
                            // Прикольная анимация при завершении загрузки
                            binding.recyclerView.animate()
                                .alpha(1f)
                                .setDuration(300)
                                .setInterpolator(android.view.animation.DecelerateInterpolator())
                                .start()
                            
                            // Гарантируем остановку swipe refresh при завершении загрузки
                            binding.swipeRefresh.post {
                                if (_binding != null) {
                                    binding.swipeRefresh.isRefreshing = false
                                    // Плавно возвращаем прозрачность
                                    binding.recyclerView.animate()
                                        .alpha(1f)
                                        .setDuration(300)
                                        .setInterpolator(android.view.animation.DecelerateInterpolator())
                                        .start()
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ошибка при обработке загрузки: ${e.message}", e)
                        // Гарантируем остановку при ошибке
                        _binding?.swipeRefresh?.isRefreshing = false
                    }
                }
            } catch (e: CancellationException) {
                Log.d(TAG, "Collect isLoading cancelled")
                // Гарантируем остановку при отмене
                _binding?.swipeRefresh?.isRefreshing = false
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка в корутине isLoading: ${e.message}", e)
                // Гарантируем остановку при ошибке
                _binding?.swipeRefresh?.isRefreshing = false
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
            } catch (e: CancellationException) {
                Log.d(TAG, "Collect error cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка в корутине error: ${e.message}", e)
            }
        }
    }
    
    override fun onPause() {
        super.onPause()
        // Останавливаем обновления для экономии ресурсов
        try {
            if (::adapter.isInitialized) {
                adapter.pauseUpdates()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при остановке обновлений: ${e.message}", e)
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        if (::prefs.isInitialized) {
            prefs.unregisterChangeListener(prefsChangeListener)
        }
        // Останавливаем все обновления при уничтожении view
        try {
            if (::adapter.isInitialized) {
                adapter.stopAllUpdates()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при остановке обновлений в onDestroyView: ${e.message}", e)
        }
        _binding = null
    }
    
    /**
     * Показывает календарь для выбора даты
     */
    private fun showCalendarDialog(currentDaySchedule: com.example.raspisanie.data.DaySchedule) {
        try {
            val allSchedules = viewModel.schedule.value
            val dateFormat = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

            // Загружаем даты из БД и расписания асинхронно
            lifecycleScope.launch {
                try {
                    val repository = com.example.raspisanie.data.LessonsRepository(requireContext())
                    
                    // Собираем даты из расписания
                    val scheduleDates = allSchedules.mapNotNull { schedule ->
                        try {
                            dateFormat.parse(schedule.date)?.time
                        } catch (_: Exception) {
                            null
                        }
                    }

                    // Загружаем даты из БД
                    val dbDateStrings = repository.getAllDates()
                    val dbDates = dbDateStrings.mapNotNull { dateStr ->
                        try {
                            dateFormat.parse(dateStr)?.time
                        } catch (_: Exception) {
                            null
                        }
                    }

                    // Объединяем даты - только доступные даты
                    val availableDates = (scheduleDates + dbDates).distinct().sorted()
                    
                    if (availableDates.isEmpty()) {
                        Toast.makeText(requireContext(), "Нет доступных дат для выбора", Toast.LENGTH_SHORT).show()
                        return@launch
                    }
                    
                    val minDate = availableDates.first()
                    val maxDate = availableDates.last()

                    // Устанавливаем текущую дату
                    val currentDateMillis = try {
                        dateFormat.parse(currentDaySchedule.date)?.time ?: availableDates.firstOrNull() ?: System.currentTimeMillis()
                    } catch (_: Exception) {
                        availableDates.firstOrNull() ?: System.currentTimeMillis()
                    }

                    // Создаем валидатор - разрешаем только доступные даты
                    val dateValidators = availableDates.map { dateMillis ->
                        DateValidatorPointForward.from(dateMillis) as com.google.android.material.datepicker.CalendarConstraints.DateValidator
                    }
                    val dateValidator = CompositeDateValidator.anyOf(dateValidators)

                    // Создаем календарь с валидатором
                    val constraints = CalendarConstraints.Builder()
                        .setStart(minDate)
                        .setEnd(maxDate + 86400000)
                        .setValidator(dateValidator)
                        .build()

                    val datePicker = MaterialDatePicker.Builder.datePicker()
                        .setTitleText("Выберите дату")
                        .setSelection(currentDateMillis)
                        .setCalendarConstraints(constraints)
                        .setInputMode(com.google.android.material.datepicker.MaterialDatePicker.INPUT_MODE_CALENDAR)
                        .build()

                    // Обработка выбора даты
                    datePicker.addOnPositiveButtonClickListener { selection ->
                        try {
                            val selectedDate = Date(selection)
                            val selectedDateStr = dateFormat.format(selectedDate)

                            // Ищем расписание для выбранной даты
                            val selectedSchedule = allSchedules.firstOrNull { it.date == selectedDateStr }

                            // Вместо диалога показываем выбранный день как первую карточку в списке
                            lifecycleScope.launch {
                                try {
                                    val dayScheduleToShow: com.example.raspisanie.data.DaySchedule?
                                    
                                    if (selectedSchedule != null) {
                                        // Есть плановое расписание
                                        dayScheduleToShow = selectedSchedule
                                    } else {
                                        // Планового нет - проверяем занятия из БД (с фильтрацией по текущей группе)
                                        val dbLessons = repository.getLessonsByDate(
                                            selectedDateStr,
                                            if (prefs.isGroupSelected()) prefs.selectedGroupFile else null,
                                            if (prefs.isGroupSelected()) prefs.college else null
                                        )
                                        
                                        // Создаем DaySchedule даже если нет данных (чтобы показать выходной день с крестиком)
                                        val calendar = Calendar.getInstance().apply { time = selectedDate }
                                        // Используем SHORT и нормализуем через DayOfWeekEntity
                                        val calendarDay = calendar.get(Calendar.DAY_OF_WEEK)
                                        val dayNames = arrayOf("", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб")
                                        val rawDayName = if (calendarDay in 1..7) dayNames[calendarDay] else ""
                                        val dayOfWeek = com.example.raspisanie.data.DayOfWeekEntity.normalizeDayName(rawDayName) ?: ""
                                        
                                        dayScheduleToShow = com.example.raspisanie.data.DaySchedule(
                                            day = dayOfWeek,
                                            date = selectedDateStr,
                                            weekNumber = 1,
                                            items = dbLessons // Может быть пустым для выходных дней
                                        )
                                    }
                                    
                                    if (dayScheduleToShow != null) {
                                        // Сохраняем выбранный день и обновляем список
                                        this@ScheduleFragment.selectedDaySchedule = dayScheduleToShow
                                        
                                        // Обновляем adapter с новым списком (выбранный день будет первым)
                                        val currentSchedules = viewModel.schedule.value
                                        val plannedDatesSet = currentSchedules.map { it.date }.toSet()
                                        val withoutSelected = currentSchedules.filter { it.date != dayScheduleToShow.date }
                                        val schedulesToShow = listOf(dayScheduleToShow) + withoutSelected
                                        
                                        adapter.updateSchedules(schedulesToShow, plannedDatesSet, dayScheduleToShow.date)
                                        
                                        // Скроллим к началу списка
                                        binding.recyclerView.post {
                                            binding.recyclerView.smoothScrollToPosition(0)
                                        }
                                    } else {
                                        Toast.makeText(requireContext(), "На дату $selectedDateStr нет занятий", Toast.LENGTH_SHORT).show()
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Ошибка при загрузке занятий: ${e.message}", e)
                                    Toast.makeText(requireContext(), "Не удалось загрузить расписание", Toast.LENGTH_SHORT).show()
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Ошибка при обработке выбранной даты: ${e.message}", e)
                        }
                    }

                    // Показываем календарь
                    datePicker.show(childFragmentManager, "DATE_PICKER")
                    
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при загрузке дат: ${e.message}", e)
                    Toast.makeText(requireContext(), "Ошибка загрузки дат", Toast.LENGTH_SHORT).show()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при показе календаря: ${e.message}", e)
        }
    }
    
    /**
     * Показывает диалог с расписанием на выбранный день
     */
    private fun showDayScheduleDialog(daySchedule: com.example.raspisanie.data.DaySchedule) {
        try {
            val context = requireContext()
            val items = daySchedule.items.sortedBy { it.lessonNumber }
            
            // Показываем диалог с занятиями
            val message = formatScheduleItems(items, prefs.college)
            
            com.google.android.material.dialog.MaterialAlertDialogBuilder(context)
                .setTitle("${daySchedule.day}, ${daySchedule.date}")
                .setMessage(message)
                .setPositiveButton("ОК", null)
                .show()
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при показе расписания дня: ${e.message}", e)
        }
    }
    
    /**
     * Форматирует список занятий для отображения
     */
    private fun formatScheduleItems(items: List<com.example.raspisanie.data.ScheduleItem>, college: String): String {
        return if (items.isEmpty()) {
            "На этот день нет занятий"
        } else {
            items.joinToString("\n\n") { item ->
                val time = com.example.raspisanie.data.LessonTimes.formatTime(
                    item.lessonNumber, 
                    college
                )
                val timeStr = if (time.isNotEmpty()) "[$time] " else ""
                val subgroupStr = if (item.subgroup != null) " (${item.subgroup} п/г)" else ""
                val classroomStr = if (!item.classroom.isNullOrBlank()) " — ${item.classroom}" else ""
                val teacherStr = if (!item.teacher.isNullOrBlank()) "\n${item.teacher}" else ""
                
                "${item.lessonNumber}. $timeStr${item.subject}$subgroupStr$classroomStr$teacherStr"
            }
        }
    }
    
    
}

