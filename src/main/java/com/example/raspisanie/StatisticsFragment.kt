package com.example.raspisanie

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.example.raspisanie.R
import com.example.raspisanie.adapter.StatisticsAdapter
import com.example.raspisanie.data.GroupStatistics
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.StatisticsParser
import com.example.raspisanie.databinding.FragmentStatisticsBinding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class StatisticsFragment : Fragment() {
    companion object {
        private const val TAG = "StatisticsFragment"
    }
    
    private var _binding: FragmentStatisticsBinding? = null
    private val binding get() = _binding!!
    private lateinit var prefs: PreferencesManager
    private lateinit var parser: StatisticsParser
    private var statisticsJob: Job? = null
    private var hasAnimatedSummaryCards = false // Флаг для предотвращения повторной анимации итоговых карточек

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
        binding.progressIndicator.setVisibilityAfterHide(View.GONE)
        
        // Применяем шрифт Ndot для красной темы
        applyNothingFontIfNeeded()
        
        // Долгое нажатие на заголовок "Статистика" - скролл вверх (как в Telegram)
        binding.statisticsTitle.setOnLongClickListener {
            binding.statisticsRecyclerView.smoothScrollToPosition(0)
            // Haptic feedback
            binding.statisticsTitle.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            true
        }
        
        // Настраиваем swipe refresh
        setupSwipeRefresh()
        
        // Статистика доступна для всех колледжей
        loadStatistics()
    }
    
    private fun loadStatistics() {
        val binding = _binding ?: return

        if (!prefs.isGroupSelected()) {
            binding.emptyState.isVisible = true
            binding.errorText.isVisible = false
            binding.statisticsRecyclerView.isVisible = false
            setLoading(binding, false)
            return
        }
        
        binding.emptyState.isVisible = false
        binding.errorText.isVisible = false
        binding.statisticsRecyclerView.isVisible = false
        
        val isSwipeRefresh = binding.swipeRefresh.isRefreshing
        
        if (!isSwipeRefresh) {
            setLoading(binding, true)
        }
        
        statisticsJob?.cancel()
        statisticsJob = viewLifecycleOwner.lifecycleScope.launch {
            val safeBinding = _binding ?: return@launch
            try {
                // Если swipe refresh активен, не показываем кэш, сразу загружаем свежие данные
                if (!isSwipeRefresh) {
                    // Сначала пытаемся загрузить из кэша (быстро)
                    val cachedStatistics = parser.fetchStatistics(prefs.selectedGroupFile, prefs.college, useCache = true)
                    
                    // Если есть кэш, показываем его сразу
                    if (cachedStatistics != null) {
                        setLoading(safeBinding, false)
                        if (cachedStatistics.disciplines.isNotEmpty() || 
                            cachedStatistics.totalHours != null || 
                            cachedStatistics.completedHours != null) {
                            displayStatistics(cachedStatistics)
                            safeBinding.statisticsRecyclerView.isVisible = true
                        }
                    } else {
                        // Если кэша нет, показываем прогресс
                        setLoading(safeBinding, true)
                    }
                }
                
                // Затем загружаем свежие данные с сервера (обновляем кэш)
                val statistics = parser.fetchStatistics(prefs.selectedGroupFile, prefs.college, useCache = false)
                
                setLoading(safeBinding, false)
                safeBinding.swipeRefresh.isRefreshing = false
                
                if (statistics != null && (statistics.disciplines.isNotEmpty() || 
                    statistics.totalHours != null || 
                    statistics.completedHours != null)) {
                    displayStatistics(statistics)
                    safeBinding.statisticsRecyclerView.isVisible = true
                } else if (!isSwipeRefresh) {
                    // Показываем ошибку только если не было кэша
                    val cachedStatistics = parser.fetchStatistics(prefs.selectedGroupFile, prefs.college, useCache = true)
                    if (cachedStatistics == null) {
                        safeBinding.errorText.text = getString(R.string.statistics_loading_error)
                        safeBinding.errorText.isVisible = true
                        safeBinding.statisticsRecyclerView.isVisible = false
                    }
                }
            } catch (ce: CancellationException) {
                setLoading(safeBinding, false)
                safeBinding.swipeRefresh.isRefreshing = false
                throw ce
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при загрузке статистики", e)
                setLoading(safeBinding, false)
                safeBinding.swipeRefresh.isRefreshing = false
                
                // При ошибке пытаемся показать кэш, если он есть
                try {
                    val cachedStatistics = parser.fetchStatistics(prefs.selectedGroupFile, prefs.college, useCache = true)
                    if (cachedStatistics != null && (cachedStatistics.disciplines.isNotEmpty() || 
                        cachedStatistics.totalHours != null || 
                        cachedStatistics.completedHours != null)) {
                        displayStatistics(cachedStatistics)
                        safeBinding.statisticsRecyclerView.isVisible = true
                        return@launch
                    }
                } catch (cacheException: CancellationException) {
                    throw cacheException
                } catch (cacheException: Exception) {
                    Log.e(TAG, "Ошибка при загрузке из кэша", cacheException)
                }
                
                safeBinding.errorText.text = "Ошибка загрузки: ${e.message}"
                safeBinding.errorText.isVisible = true
                safeBinding.statisticsRecyclerView.isVisible = false
            }
        }
    }
    
    private fun displayStatistics(statistics: GroupStatistics) {
        val binding = _binding ?: return
        binding.groupNameText.text = statistics.groupName.ifEmpty { prefs.selectedGroupName }
        
        // Долгое нажатие на название группы - скролл вверх (как в Telegram)
        binding.groupNameText.setOnLongClickListener {
            binding.statisticsRecyclerView.smoothScrollToPosition(0)
            // Haptic feedback
            binding.groupNameText.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            true
        }
        
        // Отображаем итоговые значения
        binding.totalHoursText.text = statistics.totalHours?.toString() ?: "—"
        binding.completedHoursText.text = statistics.completedHours?.toString() ?: "—"
        binding.remainingHoursText.text = statistics.remainingHours?.toString() ?: "—"
        binding.plannedHoursText.text = statistics.plannedHours?.toString() ?: "—"
        
        // Показываем заголовок дисциплин если есть данные
        binding.disciplinesTitle.visibility = if (statistics.disciplines.isNotEmpty()) View.VISIBLE else View.GONE
        
        // Анимируем появление итоговых карточек только один раз
        if (!hasAnimatedSummaryCards) {
            animateSummaryCards(binding)
            hasAnimatedSummaryCards = true
        } else {
            // Если уже анимировали, просто устанавливаем финальное состояние
            val cards = listOf(
                binding.totalHoursCard,
                binding.completedHoursCard,
                binding.remainingHoursCard,
                binding.plannedHoursCard
            )
            cards.forEach { card ->
                card.alpha = 1f
                card.translationY = 0f
                card.scaleX = 1f
                card.scaleY = 1f
            }
        }
        
        // Настраиваем RecyclerView для отображения таблицы дисциплин
        val layoutManager = LinearLayoutManager(requireContext())
        binding.statisticsRecyclerView.layoutManager = layoutManager
        binding.statisticsRecyclerView.adapter = StatisticsAdapter(statistics.disciplines, requireContext())
    }
    
    /**
     * Анимация появления итоговых карточек с эффектом stagger
     */
    private fun animateSummaryCards(binding: FragmentStatisticsBinding) {
        val cards = listOf(
            binding.totalHoursCard,
            binding.completedHoursCard,
            binding.remainingHoursCard,
            binding.plannedHoursCard
        )
        
        cards.forEachIndexed { index, card ->
            // Начальное состояние: карточка смещена вверх и прозрачна
            card.alpha = 0f
            card.translationY = -30f
            card.scaleX = 0.9f
            card.scaleY = 0.9f
            
            // Задержка для stagger эффекта
            val delay = index * 80L
            
            card.postDelayed({
                if (card.isAttachedToWindow) {
                    val animatorSet = AnimatorSet().apply {
                        playTogether(
                            ObjectAnimator.ofFloat(card, "alpha", 0f, 1f).apply {
                                duration = 400
                                interpolator = DecelerateInterpolator()
                            },
                            ObjectAnimator.ofFloat(card, "translationY", -30f, 0f).apply {
                                duration = 500
                                interpolator = OvershootInterpolator(0.8f)
                            },
                            ObjectAnimator.ofFloat(card, "scaleX", 0.9f, 1f).apply {
                                duration = 500
                                interpolator = OvershootInterpolator(0.8f)
                            },
                            ObjectAnimator.ofFloat(card, "scaleY", 0.9f, 1f).apply {
                                duration = 500
                                interpolator = OvershootInterpolator(0.8f)
                            }
                        )
                    }
                    animatorSet.start()
                }
            }, delay)
        }
    }
    
    
    override fun onResume() {
        super.onResume()
        
        // Применяем шрифт при возврате на экран (на случай изменения темы)
        if (::prefs.isInitialized) {
            applyNothingFontIfNeeded()
        }
        
        // Обновляем статистику при возврате на экран
        if (::prefs.isInitialized && prefs.isGroupSelected()) {
            hasAnimatedSummaryCards = false // Сбрасываем для повторной анимации
            loadStatistics()
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        statisticsJob?.cancel()
        statisticsJob = null
        hasAnimatedSummaryCards = false // Сбрасываем флаг для корректной анимации при повторном открытии
        _binding = null
    }

    private fun setLoading(binding: FragmentStatisticsBinding, show: Boolean) {
        if (show) {
            if (!binding.progressIndicator.isVisible) {
                binding.progressIndicator.isVisible = true
            }
            binding.progressIndicator.show()
        } else {
            binding.progressIndicator.hide()
            binding.progressIndicator.isVisible = false
        }
    }
    
    private fun setupSwipeRefresh() {
        try {
            binding.swipeRefresh.setOnRefreshListener {
                try {
                    if (prefs.isGroupSelected()) {
                        // Обновляем статистику
                        loadStatistics()
                        
                        // Добавляем таймаут на случай, если загрузка не завершится
                        binding.swipeRefresh.postDelayed({
                            val safeBinding = _binding
                            if (safeBinding != null && safeBinding.swipeRefresh.isRefreshing) {
                                Log.w(TAG, "Таймаут обновления статистики, останавливаем swipe refresh")
                                safeBinding.swipeRefresh.isRefreshing = false
                            }
                        }, 15000) // 15 секунд таймаут
                    } else {
                        binding.swipeRefresh.isRefreshing = false
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при обновлении статистики: ${e.message}", e)
                    val safeBinding = _binding
                    if (safeBinding != null) {
                        safeBinding.swipeRefresh.isRefreshing = false
                    }
                }
            }
            
            // Настраиваем цвет индикатора обновления
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
    
    private fun applyNothingFontIfNeeded() {
        if (prefs.theme == PreferencesManager.THEME_NOTHING) {
            try {
                val ndotFont = resources.getFont(R.font.ndot)
                val rootView = _binding?.root ?: return
                rootView.post {
                    if (_binding != null && isAdded) {
                        _binding?.root?.let { root ->
                            applyFontRecursive(root, ndotFont)
                        }
                    }
                }
            } catch (e: Exception) {
                // Fallback
            }
        }
    }
    
    private fun applyFontRecursive(view: View, font: android.graphics.Typeface) {
        if (view is android.widget.TextView) {
            view.typeface = font
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                applyFontRecursive(view.getChildAt(i), font)
            }
        }
    }
}

