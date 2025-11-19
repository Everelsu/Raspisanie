package com.example.raspisanie

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.example.raspisanie.R
import com.example.raspisanie.adapter.StatisticsAdapter
import com.example.raspisanie.data.GroupStatistics
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.StatisticsParser
import com.example.raspisanie.databinding.FragmentStatisticsBinding
import kotlinx.coroutines.launch

class StatisticsFragment : Fragment() {
    companion object {
        private const val TAG = "StatisticsFragment"
    }
    
    private var _binding: FragmentStatisticsBinding? = null
    private val binding get() = _binding!!
    private lateinit var prefs: PreferencesManager
    private lateinit var parser: StatisticsParser

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentStatisticsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        prefs = PreferencesManager(requireContext())
        parser = StatisticsParser(requireContext())
        
        // Применяем тему сразу после создания view
        view.post {
            if (::prefs.isInitialized) {
                applyThemeToSummaryCards()
            }
        }
        
        // Показываем только для ЧТОТиБ
        if (prefs.college != PreferencesManager.COLLEGE_CHTOTIB) {
            binding.emptyState.text = getString(R.string.statistics_only_chtotib)
            binding.emptyState.visibility = View.VISIBLE
            return
        }
        
        loadStatistics()
    }
    
    private fun loadStatistics() {
        if (!prefs.isGroupSelected()) {
            binding.emptyState.visibility = View.VISIBLE
            binding.errorText.visibility = View.GONE
            binding.statisticsRecyclerView.visibility = View.GONE
            return
        }
        
        binding.emptyState.visibility = View.GONE
        binding.errorText.visibility = View.GONE
        binding.statisticsRecyclerView.visibility = View.GONE
        binding.progressIndicator.visibility = View.VISIBLE
        
        lifecycleScope.launch {
            try {
                // Сначала пытаемся загрузить из кэша (быстро)
                val cachedStatistics = parser.fetchStatistics(prefs.selectedGroupFile, useCache = true)
                
                // Если есть кэш, показываем его сразу
                if (cachedStatistics != null) {
                    binding.progressIndicator.visibility = View.GONE
                    if (cachedStatistics.disciplines.isNotEmpty() || 
                        cachedStatistics.totalHours != null || 
                        cachedStatistics.completedHours != null) {
                        displayStatistics(cachedStatistics)
                        binding.statisticsRecyclerView.visibility = View.VISIBLE
                    }
                } else {
                    // Если кэша нет, показываем прогресс
                    binding.progressIndicator.visibility = View.VISIBLE
                }
                
                // Затем загружаем свежие данные с сервера (обновляем кэш)
                val statistics = parser.fetchStatistics(prefs.selectedGroupFile, useCache = false)
                
                binding.progressIndicator.visibility = View.GONE
                
                if (statistics != null && (statistics.disciplines.isNotEmpty() || 
                    statistics.totalHours != null || 
                    statistics.completedHours != null)) {
                    displayStatistics(statistics)
                    binding.statisticsRecyclerView.visibility = View.VISIBLE
                } else if (cachedStatistics == null) {
                    // Показываем ошибку только если нет кэша
                    binding.errorText.text = getString(R.string.statistics_loading_error)
                    binding.errorText.visibility = View.VISIBLE
                    binding.statisticsRecyclerView.visibility = View.GONE
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при загрузке статистики", e)
                binding.progressIndicator.visibility = View.GONE
                
                // При ошибке пытаемся показать кэш, если он есть
                try {
                    val cachedStatistics = parser.fetchStatistics(prefs.selectedGroupFile, useCache = true)
                    if (cachedStatistics != null && (cachedStatistics.disciplines.isNotEmpty() || 
                        cachedStatistics.totalHours != null || 
                        cachedStatistics.completedHours != null)) {
                        displayStatistics(cachedStatistics)
                        binding.statisticsRecyclerView.visibility = View.VISIBLE
                        return@launch
                    }
                } catch (cacheException: Exception) {
                    Log.e(TAG, "Ошибка при загрузке из кэша", cacheException)
                }
                
                binding.errorText.text = "Ошибка загрузки: ${e.message}"
                binding.errorText.visibility = View.VISIBLE
                binding.statisticsRecyclerView.visibility = View.GONE
            }
        }
    }
    
    private fun displayStatistics(statistics: GroupStatistics) {
        binding.groupNameText.text = statistics.groupName.ifEmpty { prefs.selectedGroupName }
        
        // Отображаем итоговые значения
        binding.totalHoursText.text = statistics.totalHours?.toString() ?: "—"
        binding.completedHoursText.text = statistics.completedHours?.toString() ?: "—"
        binding.remainingHoursText.text = statistics.remainingHours?.toString() ?: "—"
        binding.plannedHoursText.text = statistics.plannedHours?.toString() ?: "—"
        
        // Применяем тему к итоговым карточкам
        applyThemeToSummaryCards()
        
        // Настраиваем RecyclerView для отображения таблицы дисциплин
        val layoutManager = LinearLayoutManager(requireContext())
        binding.statisticsRecyclerView.layoutManager = layoutManager
        binding.statisticsRecyclerView.adapter = StatisticsAdapter(statistics.disciplines, requireContext())
        
        // Верхние карточки теперь закреплены и не скрываются при прокрутке
    }
    
    private fun applyThemeToSummaryCards() {
        val context = requireContext()
        val resources = context.resources
        
        // Применяем фон карточек
        val bgResId = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> R.drawable.card_background_light
            PreferencesManager.THEME_DARK -> R.drawable.card_background_dark
            PreferencesManager.THEME_PURPLE -> R.drawable.card_background_purple
            PreferencesManager.THEME_HALLOWEEN -> R.drawable.card_background_halloween
            PreferencesManager.THEME_NOTHING -> R.drawable.card_background_nothing
            PreferencesManager.THEME_GREEN -> R.drawable.card_background_green
            PreferencesManager.THEME_NEW_YEAR -> R.drawable.card_background_newyear
            else -> R.drawable.card_background_dark
        }
        
        binding.totalHoursCard.setBackgroundResource(bgResId)
        binding.completedHoursCard.setBackgroundResource(bgResId)
        binding.remainingHoursCard.setBackgroundResource(bgResId)
        binding.plannedHoursCard.setBackgroundResource(bgResId)
        
        // Применяем цвета текста для цифр в зависимости от темы
        val primaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_colorPrimary, null)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_colorPrimary, null)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_colorPrimary, null)
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_colorPrimary, null)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_colorPrimary, null)
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_colorPrimary, null)
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_colorPrimary, null)
            else -> resources.getColor(R.color.dark_colorPrimary, null)
        }
        
        // Применяем цвета к TextView с цифрами (используем colorPrimary для всех, чтобы они менялись с темой)
        binding.totalHoursText.setTextColor(primaryColor)
        binding.completedHoursText.setTextColor(primaryColor)
        binding.remainingHoursText.setTextColor(primaryColor)
        binding.plannedHoursText.setTextColor(primaryColor)
    }
    
    
    override fun onResume() {
        super.onResume()
        
        // Применяем тему при возврате на экран (на случай изменения темы)
        if (::prefs.isInitialized) {
            applyThemeToSummaryCards()
        }
        
        // Обновляем статистику при возврате на экран
        if (::prefs.isInitialized && prefs.isGroupSelected()) {
            loadStatistics()
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

