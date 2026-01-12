package com.example.raspisanie.adapter

import android.animation.ValueAnimator
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.view.MotionEvent
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.example.raspisanie.R
import com.example.raspisanie.data.DayProgressCalculator
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.data.LessonTimes
import com.example.raspisanie.data.PreferencesManager
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

class ScheduleAdapter(
    private var schedules: List<DaySchedule> = emptyList(),
    private val context: Context? = null
) : RecyclerView.Adapter<ScheduleAdapter.ScheduleViewHolder>() {
    
    private val prefs: PreferencesManager? = context?.let { PreferencesManager(it) }
    
    // Флаг видимости фрагмента для оптимизации обновлений
    @Volatile
    private var isFragmentVisible: Boolean = true
    
    // Получать настройки динамически при каждом обращении для актуальности
    private val isNothingTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_NOTHING
    private val isHalloweenTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_HALLOWEEN
    private val isLightTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_LIGHT
    private val isDarkTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_DARK
    private val isPurpleTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_PURPLE
    private val isGreenTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_GREEN
    private val isNewYearTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_NEW_YEAR
    private val showLessonStatus: Boolean get() = prefs?.showLessonStatus ?: true
    
    // Font size multiplier based on preference
    private fun getFontSizeMultiplier(): Float {
        return when (prefs?.fontSize) {
            PreferencesManager.FONT_SIZE_SMALL -> 0.85f
            PreferencesManager.FONT_SIZE_NORMAL -> 1.0f
            PreferencesManager.FONT_SIZE_LARGE -> 1.15f
            PreferencesManager.FONT_SIZE_EXTRA_LARGE -> 1.3f
            else -> 1.0f
        }
    }
    
    private val animationsEnabled: Boolean = true // Always enabled

    inner class ScheduleViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val dayName: TextView = view.findViewById(R.id.dayName)
        val dateText: TextView = view.findViewById(R.id.dateText)
        val itemsContainer: ViewGroup = view.findViewById(R.id.itemsContainer)
        val itemsWrapper: ViewGroup = view.findViewById(R.id.itemsWrapper)
        val progressIndicator: View = view.findViewById(R.id.progressIndicator)
        val cardBackground: View = view.findViewById(R.id.cardBackground)
        
        // Cache for progress line state to avoid recalculation on scroll
        var progressLineSetup: Boolean = false
        var progressHandler: Handler? = null
        var statusHandler: Handler? = null
        var currentLessonNumbers: List<Int>? = null
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ScheduleViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_day_schedule, parent, false)
        return ScheduleViewHolder(view)
    }
    
    override fun onViewRecycled(holder: ScheduleViewHolder) {
        super.onViewRecycled(holder)
        // Clean up handlers and listeners when ViewHolder is recycled
        try {
            holder.progressHandler?.removeCallbacksAndMessages(null)
            holder.progressHandler = null
            holder.statusHandler?.removeCallbacksAndMessages(null)
            holder.statusHandler = null
            holder.progressLineSetup = false
            holder.currentLessonNumbers = null
            
            // Cancel any animations on progress indicator
            holder.progressIndicator.clearAnimation()
            holder.progressIndicator.animate().cancel()
            
            // Отменить все анимации в дочерних view
            cancelAnimationsInView(holder.itemView)
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при очистке ViewHolder: ${e.message}", e)
        }
    }
    
    private fun cancelAnimationsInView(view: View) {
        try {
            view.clearAnimation()
            view.animate().cancel()
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) {
                    cancelAnimationsInView(view.getChildAt(i))
                }
            }
        } catch (e: Exception) {
            // Игнорируем ошибки при очистке
        }
    }

    override fun onBindViewHolder(holder: ScheduleViewHolder, position: Int) {
        val daySchedule = schedules[position]
        
        // Сбросить состояние прогресса при перепривязке (на случай изменения настроек)
        holder.progressLineSetup = false
        holder.currentLessonNumbers = null
        holder.progressHandler?.removeCallbacksAndMessages(null)
        holder.progressHandler = null
        holder.statusHandler?.removeCallbacksAndMessages(null)
        holder.statusHandler = null
        
        holder.dayName.text = formatDayName(daySchedule.day)
        holder.dateText.text = formatDate(daySchedule.date)
        
        // Apply font size
        val fontSizeMultiplier = getFontSizeMultiplier()
        val baseDayNameSize = if (isToday(daySchedule.date)) 26f else 24f
        holder.dayName.textSize = baseDayNameSize * fontSizeMultiplier
        holder.dateText.textSize = 14f * fontSizeMultiplier
        
        // Долгое нажатие на название дня - скролл вверх (как в Telegram)
        holder.dayName.setOnLongClickListener {
            val recyclerView = holder.itemView.parent as? RecyclerView ?: return@setOnLongClickListener false
            // Haptic feedback
            holder.dayName.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            // Плавная прокрутка вверх до самого верха
            recyclerView.smoothScrollToPosition(0)
            // После завершения прокрутки делаем финальную корректировку с учетом padding
            recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
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
        
        // Apply theme-specific gradient background to card
        if (context != null) {
            val bgResId = when (prefs?.theme) {
                PreferencesManager.THEME_LIGHT -> R.drawable.card_background_light
                PreferencesManager.THEME_DARK -> R.drawable.card_background_dark
                PreferencesManager.THEME_BLUE -> R.drawable.card_background_blue
                PreferencesManager.THEME_GRAY -> R.drawable.card_background_gray
                PreferencesManager.THEME_PURPLE -> R.drawable.card_background_purple
                PreferencesManager.THEME_HALLOWEEN -> R.drawable.card_background_halloween
                PreferencesManager.THEME_NOTHING -> R.drawable.card_background_nothing
                PreferencesManager.THEME_GREEN -> R.drawable.card_background_green
                PreferencesManager.THEME_NEW_YEAR -> R.drawable.card_background_newyear
                else -> R.drawable.card_background_dark
            }
            holder.cardBackground.setBackgroundResource(bgResId)
        }
        
        // Apply Nothing font if needed
        if (isNothingTheme && context != null) {
            try {
                val ndotFont = context.resources.getFont(R.font.ndot)
                holder.dayName.typeface = ndotFont
                holder.dateText.typeface = ndotFont
            } catch (e: Exception) {
                // Fallback
            }
        }

        // Check if this is today
        val isToday = isToday(daySchedule.date)
        
        // Add accent to today's card
        if (isToday) {
            holder.dayName.alpha = 1f
            // Add subtle emphasis
            holder.itemView.elevation = 4f
        } else {
            holder.dayName.alpha = 0.85f
            holder.itemView.elevation = 0f
        }
        
        // Clear previous items
        holder.itemsContainer.removeAllViews()

        if (daySchedule.items.isEmpty()) {
            val emptyView = LayoutInflater.from(holder.itemView.context)
                .inflate(R.layout.item_empty_lesson, holder.itemsContainer, false)
            if (isNothingTheme && context != null) {
                applyFontToView(emptyView)
            }
            holder.itemsContainer.addView(emptyView)
        } else {
            // Group items by lesson number
            val groupedByLesson = daySchedule.items.groupBy { it.lessonNumber }
            val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
            val statusEnabled = isToday && showLessonStatus
            val currentMinutesForStatus = if (statusEnabled) DayProgressCalculator.getCurrentTimeInMinutes() else -1
            
            var previousLessonNumber: Int? = null
            
            groupedByLesson.keys.sorted().forEach { lessonNum ->
                val items = groupedByLesson[lessonNum] ?: emptyList()
                
                // Add break info if needed
                if (previousLessonNumber != null) {
                    // Check for regular break
                    val breakText = LessonTimes.getBreakText(previousLessonNumber, lessonNum, college)
                    if (breakText != null && prefs?.showBreaks == true) {
                        val breakView = LayoutInflater.from(holder.itemView.context)
                            .inflate(R.layout.item_break, holder.itemsContainer, false)
                        val breakTextView = breakView.findViewById<TextView>(R.id.breakText)
                        breakTextView.text = breakText
                        
                        // Apply font size
                        val fontSizeMultiplier = getFontSizeMultiplier()
                        breakTextView.textSize = 13f * fontSizeMultiplier
                        
                        
                        if (isNothingTheme && context != null) {
                            applyFontToView(breakView)
                        }
                        if (isHalloweenTheme && context != null) {
                            applyHalloweenToBreak(breakTextView)
                        }
                        holder.itemsContainer.addView(breakView)
                        
                        // Animate break appearance if enabled
                        if (animationsEnabled) {
                            animateItemAppearance(breakView)
                        }
                    }
                    
                    // Check for lunch
                    val lunchText = LessonTimes.getLunchText(previousLessonNumber, college)
                    if (lunchText != null && prefs?.showLunch == true) {
                        val lunchView = LayoutInflater.from(holder.itemView.context)
                            .inflate(R.layout.item_break, holder.itemsContainer, false)
                        val lunchTextView = lunchView.findViewById<TextView>(R.id.breakText)
                        lunchTextView.text = lunchText
                        
                        // Apply font size
                        val fontSizeMultiplier = getFontSizeMultiplier()
                        lunchTextView.textSize = 13f * fontSizeMultiplier
                        
                        
                        if (isNothingTheme && context != null) {
                            applyFontToView(lunchView)
                        }
                        if (isHalloweenTheme && context != null) {
                            applyHalloweenToBreak(lunchTextView)
                        }
                        holder.itemsContainer.addView(lunchView)
                        
                        // Animate lunch appearance if enabled
                        if (animationsEnabled) {
                            animateItemAppearance(lunchView)
                        }
                    }
                }
                
                // Show each subgroup separately
                items.forEach { item ->
                    val lessonView = LayoutInflater.from(holder.itemView.context)
                        .inflate(R.layout.item_lesson, holder.itemsContainer, false)
                    
                    val lessonNumberView = lessonView.findViewById<TextView>(R.id.lessonNumber)
                    val lessonTimeView = lessonView.findViewById<TextView>(R.id.lessonTime)
                    val subjectView = lessonView.findViewById<TextView>(R.id.subject)
                    val detailsView = lessonView.findViewById<TextView>(R.id.details)
                    val subgroupIndicator = lessonView.findViewById<TextView>(R.id.subgroupIndicator)
                    val lessonProgressOverlay = lessonView.findViewById<View>(R.id.lessonProgressOverlay)
                    val lessonStatusView = lessonView.findViewById<TextView>(R.id.lessonStatus)
                    val circleBackground = lessonView.findViewById<View>(R.id.circleBackground)

                    lessonNumberView.text = lessonNum.toString()
                    
                    // Apply font size to lesson views
                    val fontSizeMultiplier = getFontSizeMultiplier()
                    lessonNumberView.textSize = 16f * fontSizeMultiplier
                    subjectView.textSize = 16f * fontSizeMultiplier
                    lessonTimeView.textSize = 11f * fontSizeMultiplier
                    detailsView.textSize = 13f * fontSizeMultiplier
                    
                    // Apply theme-specific gradient background to circle
                    if (context != null) {
                        val bgResId = when (prefs?.theme) {
                            PreferencesManager.THEME_LIGHT -> R.drawable.widget_lesson_number_bg_light
                            PreferencesManager.THEME_DARK -> R.drawable.widget_lesson_number_bg_dark
                            PreferencesManager.THEME_BLUE -> R.drawable.widget_lesson_number_bg_blue
                            PreferencesManager.THEME_GRAY -> R.drawable.widget_lesson_number_bg_gray
                            PreferencesManager.THEME_PURPLE -> R.drawable.widget_lesson_number_bg_purple
                            PreferencesManager.THEME_HALLOWEEN -> R.drawable.widget_lesson_number_bg_halloween
                            PreferencesManager.THEME_NOTHING -> R.drawable.widget_lesson_number_bg_nothing
                            PreferencesManager.THEME_GREEN -> R.drawable.widget_lesson_number_bg_green
                            PreferencesManager.THEME_NEW_YEAR -> R.drawable.widget_lesson_number_bg_newyear
                            else -> R.drawable.widget_lesson_number_bg_dark
                        }
                        circleBackground.setBackgroundResource(bgResId)
                    }
                    
                    // Set lesson time
                    val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
                    val timeText = LessonTimes.formatTime(lessonNum, college)
                    val showTime = prefs?.showTime ?: true
                    lessonTimeView.text = timeText
                    lessonTimeView.visibility = if (timeText.isNotEmpty() && showTime) View.VISIBLE else View.GONE
                    
                    subjectView.text = item.subject
                    detailsView.text = buildDetails(item)
                    
                    // Show subgroup indicator if subgroup is set, even if only one subgroup exists
                    if (item.subgroup != null) {
                        subgroupIndicator.text = "${item.subgroup}"
                        subgroupIndicator.visibility = View.VISIBLE
                    } else {
                        subgroupIndicator.visibility = View.GONE
                    }
                    
                    // Apply Nothing font to all text views
                    if (isNothingTheme && context != null) {
                        applyFontToView(lessonView)
                    }
                    
                    // Apply Halloween theme accents
                    if (isHalloweenTheme && context != null) {
                        applyHalloweenAccents(lessonView, subjectView, lessonNumberView, lessonProgressOverlay)
                    }
                    
                    holder.itemsContainer.addView(lessonView)
                    
                    // Add subtle accent to lesson number
                    addLessonNumberAccent(lessonNumberView, lessonNum)
                    
                    // Animate item appearance (if enabled)
                    if (animationsEnabled) {
                        animateItemAppearance(lessonView)
                    }
                    
                    // Update circle state if today - wait for layout first
                    if (isToday) {
                        lessonView.viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
                            override fun onGlobalLayout() {
                                lessonView.viewTreeObserver.removeOnGlobalLayoutListener(this)
                                updateCircleState(lessonNumberView, lessonProgressOverlay, lessonNum)
                            }
                        })
                        lessonStatusView?.visibility = View.GONE
                    } else {
                        lessonStatusView?.visibility = View.GONE
                    }
                }
                
                // Add break/lunch progress if today
                if (isToday && previousLessonNumber != null) {
                    if (animationsEnabled) {
                        animateBreakProgress(holder.itemsContainer, previousLessonNumber, lessonNum)
                    }
                }
                
                previousLessonNumber = lessonNum
            }
            
            if (isToday) {
                if (statusEnabled) {
                    // Обновляем статус сразу, если layout уже готов
                    if (holder.itemsContainer.width > 0 && holder.itemsContainer.height > 0) {
                        // Layout уже готов, обновляем сразу
                        holder.itemView.post {
                            if (holder.itemView.isAttachedToWindow && isFragmentVisible) {
                                updateAllLessonStatuses(holder, currentMinutesForStatus, college)
                            }
                        }
                    } else {
                        // Layout ещё не готов, ждём его завершения
                        holder.itemsContainer.viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
                            override fun onGlobalLayout() {
                                holder.itemsContainer.viewTreeObserver.removeOnGlobalLayoutListener(this)
                                // Обновляем статус сразу, без задержки
                                if (holder.itemView.isAttachedToWindow && isFragmentVisible) {
                                    updateAllLessonStatuses(holder, currentMinutesForStatus, college)
                                }
                            }
                        })
                    }
                    // Запускаем периодическое обновление статуса
                    startStatusUpdates(holder, college)
                } else {
                    hideAllLessonStatuses(holder)
                    // Останавливаем обновление статуса
                    holder.statusHandler?.removeCallbacksAndMessages(null)
                    holder.statusHandler = null
                }
            } else {
                // Если не сегодня, скрываем все статусы
                hideAllLessonStatuses(holder)
                // Останавливаем обновление статуса
                holder.statusHandler?.removeCallbacksAndMessages(null)
                holder.statusHandler = null
            }
            
            // Setup day progress indicator
            if (isToday) {
                val lessonNumbers = daySchedule.items.map { it.lessonNumber }.distinct().sorted()
                holder.currentLessonNumbers = lessonNumbers
                
                if (prefs?.showProgressLine == true) {
                    when {
                        isNothingTheme -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator_nothing)
                        isHalloweenTheme -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator_halloween)
                        isGreenTheme -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator_green)
                        isNewYearTheme -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator_newyear)
                        else -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator)
                    }
                    
                    holder.progressIndicator.visibility = View.VISIBLE
                    setupDayProgress(holder, lessonNumbers)
                } else {
                    holder.progressIndicator.visibility = View.GONE
                    holder.progressLineSetup = false
                    holder.progressHandler?.removeCallbacksAndMessages(null)
                    updateDayProgress(holder, lessonNumbers)
                }
            } else {
                holder.progressIndicator.visibility = View.GONE
                holder.progressLineSetup = false
                holder.currentLessonNumbers = null
                // Cancel any pending updates
                holder.progressHandler?.removeCallbacksAndMessages(null)
                holder.progressHandler = null
            }
            
            // Apply theme-specific color to day name
            when {
                isHalloweenTheme -> holder.dayName.setTextColor(context?.getColor(R.color.custom_colorPrimary) ?: holder.dayName.textColors?.defaultColor ?: 0xFFFFFFFF.toInt())
                isNothingTheme -> holder.dayName.setTextColor(context?.getColor(R.color.nothing_colorPrimary) ?: 0xFFFF3333.toInt())
                isGreenTheme -> holder.dayName.setTextColor(context?.getColor(R.color.green_colorPrimary) ?: 0xFF4CAF50.toInt())
                isNewYearTheme -> holder.dayName.setTextColor(context?.getColor(R.color.newyear_colorPrimary) ?: 0xFF2E7D32.toInt())
                isLightTheme -> holder.dayName.setTextColor(context?.getColor(R.color.light_colorPrimary) ?: 0xFF000000.toInt()) // Черный для светлой темы
                isDarkTheme -> holder.dayName.setTextColor(context?.getColor(R.color.dark_colorPrimary) ?: 0xFFFFFFFF.toInt()) // Белый для темной темы
                isPurpleTheme -> holder.dayName.setTextColor(context?.getColor(R.color.system_textColorPrimary) ?: 0xFFFFFFFF.toInt()) // Белый для фиолетовой темы для лучшей читаемости
                else -> holder.dayName.setTextColor(context?.getColor(R.color.system_textColorPrimary) ?: 0xFFFFFFFF.toInt()) // Белый по умолчанию для фиолетовой темы
            }
        }

        holder.cardBackground.setOnLongClickListener {
            animateCardPress(holder.cardBackground) {
                showShareMenu(holder, daySchedule)
            }
            true
        }
        
        // Добавляем анимацию при нажатии (для визуальной обратной связи)
        holder.cardBackground.setOnTouchListener { view, event ->
            when (event.action) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    // Фишка из Telegram: более плавная анимация нажатия
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    view.animate()
                        .scaleX(0.97f)
                        .scaleY(0.97f)
                        .alpha(0.8f)
                        .setDuration(120)
                        .setInterpolator(DecelerateInterpolator(1.5f))
                        .start()
                }
                android.view.MotionEvent.ACTION_UP, 
                android.view.MotionEvent.ACTION_CANCEL -> {
                    // Фишка из Telegram: плавный возврат с эффектом отскока
                    view.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .alpha(1f)
                        .setDuration(200)
                        .setInterpolator(OvershootInterpolator(1.15f))
                        .start()
                }
            }
            false // Позволяем другим обработчикам работать
        }
        
        // Staggered animation для карточки (как в Telegram - элементы появляются с задержкой)
        // Анимация применяется только при первой загрузке, не при скролле
        if (animationsEnabled && holder.itemView.alpha == 1f && holder.itemView.translationY == 0f) {
            // Если элемент уже видим, не анимируем повторно
            // Это предотвращает повторную анимацию при скролле
        } else if (animationsEnabled) {
            // Задержка зависит от позиции для эффекта каскада
            val itemPosition = position // Сохраняем position в локальную переменную
            val delay = (itemPosition * 50L).coerceAtMost(300L) // Максимум 300ms задержка
            holder.itemView.postDelayed({
                if (holder.itemView.isAttachedToWindow && holder.itemView.alpha < 1f) {
                    // Фишка из Telegram: улучшенная анимация появления с задержкой
                    val position = holder.adapterPosition
                    val delay = (position * 30L).coerceAtMost(300L)
                    holder.itemView.postDelayed({
                        animateItemAppearance(holder.itemView)
                    }, delay)
                }
            }, delay)
        }
    }
    
    private fun isToday(dateStr: String): Boolean {
        val today = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date())
        return dateStr == today
    }
    
    private fun setupDayProgress(holder: ScheduleViewHolder, lessonNumbers: List<Int>) {
        // Cancel any existing handlers
        holder.progressHandler?.removeCallbacksAndMessages(null)
        
        // ЖЕСТКАЯ ИНИЦИАЛИЗАЦИЯ: сброс всех параметров
        holder.progressIndicator.visibility = View.VISIBLE
        holder.progressIndicator.alpha = 1f
        holder.progressIndicator.scaleY = 1f
        holder.progressIndicator.scaleX = 1f
        holder.progressIndicator.rotation = 0f
        holder.progressIndicator.translationX = 0f
        holder.progressIndicator.translationY = 0f
        
        // Reset animation state for fresh calculation
        holder.progressIndicator.clearAnimation()
        holder.progressIndicator.animate().cancel()
        
        // ЖЕСТКОЕ позиционирование: убеждаемся что margin top = 0
        val params = holder.progressIndicator.layoutParams as? ViewGroup.MarginLayoutParams
        params?.let {
            it.topMargin = 0
            it.bottomMargin = 0
            holder.progressIndicator.layoutParams = it
        }
        
        // Store lesson numbers in holder tag
        holder.itemView.tag = lessonNumbers
        
        android.util.Log.d("ScheduleAdapter", "🔧 setupDayProgress: начинаю установку для ${lessonNumbers.size} уроков")
        
        // Check if container already has height (fast path - skip ViewTreeObserver)
        val containerHeight = holder.itemsContainer.height
        val wrapperHeight = holder.itemsWrapper.height
        
        if (containerHeight > 0 && wrapperHeight > 0) {
            // Already measured, update immediately
            android.util.Log.d("ScheduleAdapter", "✅ Быстрый путь: containerHeight=$containerHeight, wrapperHeight=$wrapperHeight")
            updateProgressIndicator(holder, lessonNumbers)
            holder.progressLineSetup = true
            // Start periodic updates
            updateDayProgress(holder, lessonNumbers)
        } else {
            // Use post() instead of ViewTreeObserver for better performance
            holder.itemView.post {
                // Double-check after posting
                val postedContainerHeight = holder.itemsContainer.height
                val postedWrapperHeight = holder.itemsWrapper.height
                
                android.util.Log.d("ScheduleAdapter", "📐 После post: containerHeight=$postedContainerHeight, wrapperHeight=$postedWrapperHeight")
                
                if (postedContainerHeight > 0 && postedWrapperHeight > 0) {
                    updateProgressIndicator(holder, lessonNumbers)
                    holder.progressLineSetup = true
                    // Start periodic updates
                    updateDayProgress(holder, lessonNumbers)
                } else {
                    // Fallback to ViewTreeObserver only if post() didn't work
                    android.util.Log.w("ScheduleAdapter", "⚠️ Используем ViewTreeObserver как fallback")
                    val listener = object : ViewTreeObserver.OnGlobalLayoutListener {
                        override fun onGlobalLayout() {
                            holder.itemView.viewTreeObserver.removeOnGlobalLayoutListener(this)
                            val measuredContainerHeight = holder.itemsContainer.height
                            val measuredWrapperHeight = holder.itemsWrapper.height
                            
                            android.util.Log.d("ScheduleAdapter", "📏 ViewTreeObserver: containerHeight=$measuredContainerHeight, wrapperHeight=$measuredWrapperHeight")
                            
                            if (measuredContainerHeight > 0 && measuredWrapperHeight > 0) {
                                updateProgressIndicator(holder, lessonNumbers)
                                holder.progressLineSetup = true
                                updateDayProgress(holder, lessonNumbers)
                            } else {
                                android.util.Log.e("ScheduleAdapter", "❌ ViewTreeObserver: размеры не определены!")
                            }
                        }
                    }
                    holder.itemView.viewTreeObserver.addOnGlobalLayoutListener(listener)
                }
            }
        }
    }
    
    private fun updateProgressIndicator(holder: ScheduleViewHolder, lessonNumbers: List<Int>) {
        // ЖЕСТКАЯ ВАЛИДАЦИЯ: проверяем что ViewHolder еще привязан и фрагмент виден
        if (!holder.itemView.isAttachedToWindow || !isFragmentVisible) {
            android.util.Log.w("ScheduleAdapter", "⚠️ ViewHolder не привязан к окну или фрагмент не виден, пропускаем обновление")
            return
        }
        
        val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val progress = DayProgressCalculator.getDayProgress(currentMinutes, lessonNumbers, college)
        
        // ЖЕСТКОЕ получение высоты: используем реальную высоту контейнера И wrapper
        var containerHeight = holder.itemsContainer.height
        val wrapperHeight = holder.itemsWrapper.height
        
        // ОТЛАДКА
        android.util.Log.d("ScheduleAdapter", "🔍 updateProgressIndicator: progress=$progress, containerHeight=$containerHeight, wrapperHeight=$wrapperHeight")
        
        if (containerHeight <= 0) {
            // Fallback: measure if not laid out yet
            holder.itemsContainer.measure(
                View.MeasureSpec.makeMeasureSpec(holder.itemsContainer.width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            containerHeight = holder.itemsContainer.measuredHeight
            android.util.Log.d("ScheduleAdapter", "📏 Измерено: containerHeight=$containerHeight")
            
            if (containerHeight <= 0) {
                android.util.Log.w("ScheduleAdapter", "⚠️ containerHeight <= 0 после измерения, пропускаем")
                return
            }
        }
        
        // ЖЕСТКОЕ ограничение: используем минимальную из двух высот (container и wrapper)
        val finalHeight = if (wrapperHeight > 0 && wrapperHeight < containerHeight) {
            android.util.Log.d("ScheduleAdapter", "📐 Используем wrapperHeight как ограничитель: $wrapperHeight < $containerHeight")
            wrapperHeight
        } else {
            containerHeight
        }
        
        updateProgressHeight(holder, finalHeight, progress)
        
        // ФИНАЛЬНАЯ ПРОВЕРКА: убеждаемся что линия не вышла за границы (только если фрагмент виден)
        if (isFragmentVisible) {
            holder.itemView.postDelayed({
                // Проверяем видимость перед выполнением
                if (!isFragmentVisible || !holder.itemView.isAttachedToWindow) {
                    return@postDelayed
                }
                
                val actualIndicatorHeight = holder.progressIndicator.height
                val actualIndicatorTop = holder.progressIndicator.top
                val actualWrapperHeight = holder.itemsWrapper.height
                val actualWrapperTop = holder.itemsWrapper.top
                
                if (actualIndicatorHeight > actualWrapperHeight && actualWrapperHeight > 0) {
                    android.util.Log.e("ScheduleAdapter", "🚨 ФИНАЛЬНАЯ ПРОВЕРКА ПРОВАЛЕНА: actualIndicatorHeight ($actualIndicatorHeight) > actualWrapperHeight ($actualWrapperHeight)")
                    android.util.Log.e("ScheduleAdapter", "   actualIndicatorTop=$actualIndicatorTop, actualWrapperTop=$actualWrapperTop")
                    // Немедленное исправление
                    val emergencyParams = holder.progressIndicator.layoutParams as? ViewGroup.MarginLayoutParams
                    emergencyParams?.height = actualWrapperHeight
                    emergencyParams?.topMargin = 0
                    holder.progressIndicator.layoutParams = emergencyParams
                }
            }, 100) // Небольшая задержка для проверки после layout
        }
    }
    
    private fun updateProgressHeight(holder: ScheduleViewHolder, containerHeight: Int, progress: Float) {
        // ЖЕСТКАЯ ВАЛИДАЦИЯ входных данных
        if (containerHeight <= 0) {
            android.util.Log.w("ScheduleAdapter", "⚠️ containerHeight <= 0: $containerHeight, пропускаем обновление")
            holder.progressIndicator.visibility = View.GONE
            return
        }
        
        // Проверка что ViewHolder еще привязан
        if (!holder.itemView.isAttachedToWindow) {
            android.util.Log.w("ScheduleAdapter", "⚠️ ViewHolder не привязан, пропускаем обновление")
            return
        }
        
        // Ensure progress is within bounds (0.0 to 1.0)
        val clampedProgress = progress.coerceIn(0f, 1f)
        
        // ЖЕСТКИЙ расчет высоты - НИКОГДА не превышаем контейнер
        var progressHeight = (containerHeight * clampedProgress).toInt()
        progressHeight = progressHeight.coerceIn(0, containerHeight) // Двойная проверка
        
        // ДОПОЛНИТЕЛЬНАЯ ПРОВЕРКА: высота не должна быть больше контейнера НИ ПРИ КАКИХ ОБСТОЯТЕЛЬСТВАХ
        if (progressHeight > containerHeight) {
            android.util.Log.e("ScheduleAdapter", "🚨 ОШИБКА: progressHeight ($progressHeight) > containerHeight ($containerHeight)! Исправляю...")
            progressHeight = containerHeight
        }
        
        // ЖЕСТКОЕ ограничение: не более чем 99.9% от высоты контейнера (запас безопасности)
        val maxAllowedHeight = (containerHeight * 0.999f).toInt().coerceAtLeast(0)
        progressHeight = progressHeight.coerceAtMost(maxAllowedHeight).coerceAtLeast(0)
        
        // ОТЛАДОЧНОЕ ЛОГИРОВАНИЕ
        android.util.Log.d("ScheduleAdapter", "📊 Прогресс: clampedProgress=$clampedProgress, containerHeight=$containerHeight, progressHeight=$progressHeight")
        
        // Update layout params - ЖЕСТКИЕ ограничения
        try {
            val params = holder.progressIndicator.layoutParams
            if (params == null || params !is ViewGroup.MarginLayoutParams) {
                val newParams = ViewGroup.MarginLayoutParams(
                    2.dpToPx(), // Fixed width: 2dp
                    progressHeight // Уже проверено выше
                ).apply {
                    topMargin = 0 // ЖЕСТКО: начинаем с самого верха
                    marginStart = 17.dpToPx() // Fixed start margin
                    bottomMargin = 0 // ЖЕСТКО: без отступов снизу
                    marginEnd = 0
                }
                holder.progressIndicator.layoutParams = newParams
                android.util.Log.d("ScheduleAdapter", "✅ Создан новый layout params: height=$progressHeight")
            } else {
                // ЖЕСТКОЕ обновление параметров
                params.topMargin = 0 // Всегда начинаем сверху
                params.height = progressHeight // Уже валидировано
                params.width = 2.dpToPx() // Фиксированная ширина
                params.bottomMargin = 0 // Нет отступа снизу
                params.marginEnd = 0
                if (params.marginStart != 17.dpToPx()) {
                    params.marginStart = 17.dpToPx()
                }
                holder.progressIndicator.layoutParams = params
                android.util.Log.d("ScheduleAdapter", "✅ Обновлен layout params: height=$progressHeight, topMargin=${params.topMargin}")
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении layout params: ${e.message}", e)
            // Скрываем индикатор при ошибке
            holder.progressIndicator.visibility = View.GONE
        }
        
        // ЖЕСТКОЕ позиционирование: убеждаемся что линия привязана к верху контейнера
        // Ограничение высоты через layout params уже применено выше
        holder.progressIndicator.layoutParams = holder.progressIndicator.layoutParams // Принудительное обновление
        
        // Ensure behind items (но не влияет на размеры)
        holder.progressIndicator.elevation = -1f
        
        // ВАЛИДАЦИЯ: проверяем что линия не выходит за границы
        holder.itemView.post {
            // Проверка что ViewHolder еще привязан
            if (!holder.itemView.isAttachedToWindow) {
                return@post
            }
            
            try {
                val actualHeight = holder.progressIndicator.height
                val wrapperHeight = holder.itemsWrapper.height
                if (actualHeight > wrapperHeight && wrapperHeight > 0) {
                    android.util.Log.e("ScheduleAdapter", "🚨 КРИТИЧЕСКАЯ ОШИБКА: actualHeight ($actualHeight) > wrapperHeight ($wrapperHeight)! Исправляю немедленно!")
                    val fixedParams = holder.progressIndicator.layoutParams as? ViewGroup.MarginLayoutParams
                    fixedParams?.height = wrapperHeight.coerceAtMost(containerHeight)
                    holder.progressIndicator.layoutParams = fixedParams
                }
            } catch (e: Exception) {
                android.util.Log.e("ScheduleAdapter", "Ошибка при валидации прогресса: ${e.message}", e)
            }
        }
        
        // Animate on first setup only (check if already visible)
        if ((holder.progressIndicator.scaleY == 0f || holder.progressIndicator.alpha == 0f) && !holder.progressLineSetup) {
            animateProgressLine(holder.progressIndicator)
        }
    }
    
    // Helper function to convert dp to pixels
    private fun Int.dpToPx(): Int {
        val density = context?.resources?.displayMetrics?.density ?: 1f
        return (this * density + 0.5f).toInt()
    }
    
    private fun animateProgressLine(view: View) {
        // Проверка что view еще привязан
        if (!view.isAttachedToWindow) {
            view.alpha = 1f
            view.scaleY = 1f
            return
        }
        
        try {
            view.alpha = 0f
            view.scaleY = 0f
            view.pivotY = 0f
            
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 1500
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    // Проверка что view еще привязан перед обновлением
                    if (view.isAttachedToWindow) {
                        try {
                            val scale = animator.animatedValue as Float
                            view.scaleY = scale
                            view.alpha = scale
                        } catch (e: Exception) {
                            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении анимации прогресса: ${e.message}")
                            cancel()
                        }
                    } else {
                        cancel()
                    }
                }
                start()
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при создании анимации прогресса: ${e.message}", e)
            // Fallback: просто показываем без анимации
            view.alpha = 1f
            view.scaleY = 1f
        }
    }
    
    private fun updateDayProgress(holder: ScheduleViewHolder, lessonNumbers: List<Int>) {
        // Cancel any existing handler
        holder.progressHandler?.removeCallbacksAndMessages(null)
        
        // Проверка валидности контекста
        if (context == null) {
            android.util.Log.w("ScheduleAdapter", "⚠️ Context null, отменяю обновление прогресса")
            return
        }
        
        // Оптимизация: не обновляем, если фрагмент не виден
        if (!isFragmentVisible) {
            return
        }
        
        val handler = Handler(Looper.getMainLooper())
        holder.progressHandler = handler
        
        handler.postDelayed({
            try {
                // ЖЕСТКАЯ ПРОВЕРКА: ViewHolder еще привязан и валиден, фрагмент виден
                if (!holder.itemView.isAttachedToWindow || !isFragmentVisible) {
                    android.util.Log.w("ScheduleAdapter", "⚠️ ViewHolder отвязан или фрагмент не виден, отменяю обновление")
                    holder.progressHandler = null
                    return@postDelayed
                }

                val progressVisible = holder.progressIndicator.visibility == View.VISIBLE

                // Check if ViewHolder is still bound to the same item and attached
                if (holder.currentLessonNumbers?.size == lessonNumbers.size &&
                    holder.currentLessonNumbers == lessonNumbers) {

                    val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                    val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB

                    if (progressVisible) {
                        // ЖЕСТКОЕ получение высоты: проверяем оба контейнера
                        val containerHeight = holder.itemsContainer.height
                        val wrapperHeight = holder.itemsWrapper.height

                        val safeHeight = when {
                            containerHeight > 0 && wrapperHeight > 0 -> minOf(containerHeight, wrapperHeight)
                            containerHeight > 0 -> containerHeight
                            wrapperHeight > 0 -> wrapperHeight
                            else -> {
                                android.util.Log.w("ScheduleAdapter", "⚠️ Высоты не определены, пропускаю обновление прогресса")
                                null
                            }
                        }

                        if (safeHeight != null) {
                            val progress = DayProgressCalculator.getDayProgress(currentMinutes, lessonNumbers, college)

                            android.util.Log.d("ScheduleAdapter", "🔄 Обновление прогресса: safeHeight=$safeHeight, progress=$progress")
                            updateProgressHeight(holder, safeHeight, progress)
                        } else {
                            updateProgressIndicator(holder, lessonNumbers)
                        }
                    }

                    updateAllCircles(holder, currentMinutes)
                    if (showLessonStatus) {
                        updateAllLessonStatuses(holder, currentMinutes, college)
                    } else {
                        hideAllLessonStatuses(holder)
                    }

                    // Обновляем только если фрагмент виден
                    if (holder.itemView.isAttachedToWindow && isFragmentVisible) {
                        updateDayProgress(holder, lessonNumbers)
                    } else {
                        holder.progressHandler = null
                    }
                } else {
                    android.util.Log.w("ScheduleAdapter", "⚠️ Уроки изменились, отменяю периодическое обновление")
                    holder.progressHandler = null
                }
            } catch (e: Exception) {
                android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении прогресса: ${e.message}", e)
                holder.progressHandler = null
            }
        }, 120000) // Update every 2 minutes (увеличено с 1 минуты для экономии ресурсов)
    }
    
    private fun parseTimeToMinutes(timeStr: String?): Int {
        if (timeStr == null) return 0
        val parts = timeStr.split(":")
        if (parts.size == 2) {
            val hours = parts[0].toIntOrNull() ?: 0
            val minutes = parts[1].toIntOrNull() ?: 0
            return hours * 60 + minutes
        }
        return 0
    }
    
    private fun updateCircleState(lessonNumberView: TextView, progressOverlay: View, lessonNumber: Int) {
        if (!lessonNumberView.isAttachedToWindow || !progressOverlay.isAttachedToWindow) return

        try {
            val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
            val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
            val lessonTime = LessonTimes.getTime(lessonNumber, college) ?: return

            val lessonStartMinutes = parseTimeToMinutes(lessonTime.startTime)
            val lessonEndMinutes = parseTimeToMinutes(lessonTime.endTime)
            val context = lessonNumberView.context ?: return

            val typedArray = context.theme.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary))
            val normalTextColor = typedArray.getColor(0, context.getColor(R.color.textPrimary))
            typedArray.recycle()

            val typedArrayAccent = context.theme.obtainStyledAttributes(intArrayOf(android.R.attr.colorPrimary))
            val accentColor = typedArrayAccent.getColor(0, context.getColor(R.color.textPrimary))
            typedArrayAccent.recycle()

            when {
                currentMinutes >= lessonEndMinutes -> {
                    progressOverlay.visibility = View.VISIBLE
                    val progressFillRes = when {
                        isNothingTheme -> R.drawable.lesson_progress_fill_nothing
                        isHalloweenTheme -> R.drawable.lesson_progress_fill_halloween
                        isGreenTheme -> R.drawable.lesson_progress_fill_green
                        isNewYearTheme -> R.drawable.lesson_progress_fill_newyear
                        isLightTheme -> R.drawable.lesson_progress_fill_light
                        isDarkTheme -> R.drawable.lesson_progress_fill_dark
                        else -> R.drawable.lesson_progress_fill
                    }
                    progressOverlay.setBackgroundResource(progressFillRes)

                    val textColorForPassed = if (isLightTheme) {
                        context.getColor(android.R.color.black)
                    } else {
                        context.getColor(android.R.color.white)
                    }
                    lessonNumberView.setTextColor(textColorForPassed)
                    val fontSizeMultiplier = getFontSizeMultiplier()
                    lessonNumberView.textSize = 16f * fontSizeMultiplier
                    lessonNumberView.scaleX = 1.0f
                    lessonNumberView.scaleY = 1.0f
                }
                currentMinutes >= lessonStartMinutes -> {
                    progressOverlay.visibility = View.GONE
                    val finalAccentColor = when {
                        isHalloweenTheme -> context.getColor(R.color.custom_colorPrimary)
                        isGreenTheme -> context.getColor(R.color.green_colorPrimary)
                        isNewYearTheme -> context.getColor(R.color.newyear_colorPrimary)
                        else -> accentColor
                    }
                    lessonNumberView.setTextColor(finalAccentColor)
                    val fontSizeMultiplier = getFontSizeMultiplier()
                    lessonNumberView.textSize = 17f * fontSizeMultiplier
                    lessonNumberView.alpha = 1f

                    val existingAnimator = lessonNumberView.tag as? ValueAnimator
                    if (existingAnimator == null || !existingAnimator.isRunning) {
                        animateActiveLesson(lessonNumberView)
                    }
                }
                else -> {
                    progressOverlay.visibility = View.GONE
                    val finalNormalColor = when {
                        isHalloweenTheme -> context.getColor(R.color.custom_colorPrimary)
                        isGreenTheme -> context.getColor(R.color.green_colorPrimary)
                        isNewYearTheme -> context.getColor(R.color.newyear_colorPrimary)
                        else -> normalTextColor
                    }
                    lessonNumberView.setTextColor(finalNormalColor)
                    val fontSizeMultiplier = getFontSizeMultiplier()
                    lessonNumberView.textSize = 16f * fontSizeMultiplier
                    lessonNumberView.alpha = 1f
                    lessonNumberView.scaleX = 1.0f
                    lessonNumberView.scaleY = 1.0f
                    (lessonNumberView.tag as? ValueAnimator)?.cancel()
                    lessonNumberView.tag = null
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении состояния кружка: ${e.message}", e)
        }
    }
    
    private fun animateActiveLesson(view: TextView) {
        // Проверка что view еще привязан
        if (!view.isAttachedToWindow) {
            return
        }
        
        try {
            // Clear any existing animation
            val existingAnimator = view.tag as? ValueAnimator
            existingAnimator?.cancel()
            view.clearAnimation()
            view.animate().cancel()
            
            // Pulsing animation for active lesson - more subtle and visible
            ValueAnimator.ofFloat(1.0f, 1.12f, 1.0f).apply {
                duration = 1200
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.REVERSE
                addUpdateListener { animator ->
                    // Проверка что view еще привязан перед обновлением
                    if (view.isAttachedToWindow) {
                        try {
                            val scale = animator.animatedValue as Float
                            view.scaleX = scale
                            view.scaleY = scale
                        } catch (e: Exception) {
                            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении анимации: ${e.message}")
                            cancel()
                        }
                    } else {
                        cancel()
                    }
                }
                start()
                
                // Store animator in view tag to prevent multiple animations
                view.tag = this
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при создании анимации: ${e.message}", e)
        }
    }
    
    private fun updateAllCircles(holder: ScheduleViewHolder, currentMinutes: Int) {
        // Проверка что ViewHolder еще привязан
        if (!holder.itemView.isAttachedToWindow) {
            return
        }
        
        try {
            for (i in 0 until holder.itemsContainer.childCount) {
                val child = holder.itemsContainer.getChildAt(i) ?: continue
                val lessonNumberView = child.findViewById<TextView>(R.id.lessonNumber) ?: continue
                val progressOverlay = child.findViewById<View>(R.id.lessonProgressOverlay) ?: continue
                
                try {
                    val lessonNum = lessonNumberView.text.toString().toIntOrNull() ?: continue
                    updateCircleState(lessonNumberView, progressOverlay, lessonNum)
                } catch (e: Exception) {
                    android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении кружка для урока: ${e.message}")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении всех кружков: ${e.message}", e)
        }
    }

    /**
     * Обновляет статусы всех пар и возвращает задержку до следующего обновления в миллисекундах
     * @return Задержка в миллисекундах до следующего обновления (минимум 1000мс, максимум 60000мс)
     */
    private fun updateAllLessonStatuses(holder: ScheduleViewHolder, currentMinutes: Int, college: String): Long {
        // Быстрая проверка
        if (!holder.itemView.isAttachedToWindow || !showLessonStatus || currentMinutes < 0) {
            if (!showLessonStatus) {
                hideAllLessonStatuses(holder)
            }
            return 60000 // Если статус выключен, проверяем раз в минуту
        }
        
        val context = holder.itemView.context ?: return 60000

        try {
            // Кэшируем настройки
            val currentMaxMinutes = prefs?.lessonStatusCurrentMaxMinutes ?: 60
            val nextMaxMinutes = prefs?.lessonStatusNextMaxMinutes ?: 60
            
            // Быстро собираем все View статусов и кэшируем времена пар
            val statusMap = linkedMapOf<Int, MutableList<TextView>>()
            val lessonTimesMap = mutableMapOf<Int, Pair<Int, Int>>() // lessonNum -> (start, end)
            
            val childCount = holder.itemsContainer.childCount
            for (i in 0 until childCount) {
                val child = holder.itemsContainer.getChildAt(i) ?: continue
                val statusView = child.findViewById<TextView>(R.id.lessonStatus) ?: continue
                val lessonNumberView = child.findViewById<TextView>(R.id.lessonNumber) ?: continue
                val lessonNum = lessonNumberView.text.toString().toIntOrNull() ?: continue
                
                statusView.visibility = View.GONE
                statusMap.getOrPut(lessonNum) { mutableListOf() }.add(statusView)
                
                // Кэшируем время пар
                if (!lessonTimesMap.containsKey(lessonNum)) {
                    val time = LessonTimes.getTime(lessonNum, college)
                    if (time != null) {
                        lessonTimesMap[lessonNum] = Pair(
                            parseTimeToMinutes(time.startTime),
                            parseTimeToMinutes(time.endTime)
                        )
                    }
                }
            }

            if (statusMap.isEmpty()) return 60000

            val sortedNumbers = statusMap.keys.sorted()
            
            // Быстро определяем текущую и следующую пару
            var currentLesson: Int? = null
            var nextLesson: Int? = null
            var nextImportantTime: Int? = null // Следующее важное событие (начало/конец пары)
            
            for (lessonNum in sortedNumbers) {
                val (start, end) = lessonTimesMap[lessonNum] ?: continue
                
                when {
                    // Текущая пара
                    currentMinutes >= start && currentMinutes <= end -> {
                        currentLesson = lessonNum
                        nextImportantTime = end // Конец текущей пары
                        // Сразу ищем следующую после текущей
                        val currentIndex = sortedNumbers.indexOf(lessonNum)
                        if (currentIndex >= 0 && currentIndex < sortedNumbers.size - 1) {
                            for (idx in currentIndex + 1 until sortedNumbers.size) {
                                val candidate = sortedNumbers[idx]
                                if (lessonTimesMap.containsKey(candidate)) {
                                    nextLesson = candidate
                                    // Устанавливаем время начала следующей пары как важное событие
                                    val (nextStart, _) = lessonTimesMap[candidate] ?: continue
                                    nextImportantTime = nextStart
                                    break
                                }
                            }
                        }
                        break
                    }
                    // Следующая пара (если текущей еще нет)
                    currentLesson == null && currentMinutes < start -> {
                        nextLesson = lessonNum
                        nextImportantTime = start // Начало следующей пары
                        break
                    }
                }
            }

            // Функция для установки статуса
            fun setStatus(lessonNum: Int, text: String) {
                val fontSizeMultiplier = getFontSizeMultiplier()
                statusMap[lessonNum]?.forEach { view ->
                    view.text = text
                    view.textSize = 12f * fontSizeMultiplier // Размер шрифта для статуса
                    view.visibility = View.VISIBLE
                }
            }
            
            // Показываем статус текущей пары (сколько осталось)
            var currentLessonShowsStatus = false
            var nextUpdateDelay: Long = 60000 // По умолчанию обновляем раз в минуту
            
            currentLesson?.let { lessonNum ->
                val (_, end) = lessonTimesMap[lessonNum] ?: return@let
                val remaining = end - currentMinutes
                
                if (remaining > 0 && remaining <= currentMaxMinutes) {
                    setStatus(lessonNum, context.getString(R.string.lesson_status_remaining, remaining))
                    currentLessonShowsStatus = true
                    // Если осталось меньше минуты, обновляем каждую секунду
                    nextUpdateDelay = if (remaining <= 1) 1000 else 1000
                } else if (remaining <= 0) {
                    // Пара только что закончилась, обновим через секунду
                    nextUpdateDelay = 1000
                }
            }

            // Показываем статус следующей пары (через сколько начнётся)
            // Показываем всегда, если условия выполнены, независимо от текущей пары
            nextLesson?.let { lessonNum ->
                val (start, _) = lessonTimesMap[lessonNum] ?: return@let
                val diff = start - currentMinutes
                
                if (diff > 0 && diff <= nextMaxMinutes) {
                    // Всегда показываем статус следующей пары, если она в пределах настроек
                    setStatus(lessonNum, context.getString(R.string.lesson_status_starts_in, diff))
                    // Если до начала пары меньше минуты, обновляем каждую секунду
                    if (diff <= 1) {
                        nextUpdateDelay = 1000
                    } else if (diff <= 5) {
                        nextUpdateDelay = 1000 // Обновляем каждую секунду в последние 5 минут
                    } else {
                        nextUpdateDelay = 1000 // Всегда обновляем каждую секунду для точности
                    }
                } else if (diff > 0) {
                    // До следующей пары еще далеко - обновляем раз в минуту
                    if (currentLesson == null && !currentLessonShowsStatus) {
                        nextUpdateDelay = 60000
                    }
                }
            }
            
            // Если нет активного статуса, проверяем раз в минуту
            if (currentLesson == null && nextLesson == null) {
                nextUpdateDelay = 60000
            } else if (!currentLessonShowsStatus && nextLesson == null) {
                // Есть текущая пара, но статус не показывается - проверяем раз в минуту
                nextUpdateDelay = 60000
            }
            
            // Вычисляем оптимальную задержку на основе следующего важного события
            nextImportantTime?.let { importantTime ->
                val secondsUntilImportant = (importantTime - currentMinutes) * 60L
                if (secondsUntilImportant > 0 && secondsUntilImportant < 300) {
                    // Если до важного события меньше 5 минут, обновляем каждую секунду
                    nextUpdateDelay = 1000
                } else if (secondsUntilImportant > 0) {
                    // Иначе обновляем каждую секунду для точности счётчика
                    nextUpdateDelay = 1000
                }
            }
            
            // Ограничиваем задержку: минимум 1 секунда, максимум 1 минута
            return nextUpdateDelay.coerceIn(1000, 60000)
            
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении статусов уроков: ${e.message}", e)
            return 60000
        }
    }

    private fun startStatusUpdates(holder: ScheduleViewHolder, college: String) {
        // Отменяем предыдущий handler
        holder.statusHandler?.removeCallbacksAndMessages(null)
        
        // Проверка валидности контекста
        if (context == null) {
            return
        }
        
        // Оптимизация: не обновляем, если фрагмент не виден
        if (!isFragmentVisible) {
            return
        }
        
        val handler = Handler(Looper.getMainLooper())
        holder.statusHandler = handler
        
        fun scheduleNextUpdate() {
            try {
                // Проверяем, что ViewHolder еще привязан и фрагмент виден
                if (!holder.itemView.isAttachedToWindow || !isFragmentVisible) {
                    holder.statusHandler = null
                    return
                }
                
                // Проверяем, что это сегодня и статус включен
                if (!showLessonStatus) {
                    hideAllLessonStatuses(holder)
                    holder.statusHandler = null
                    return
                }
                
                val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                val nextUpdateDelay = updateAllLessonStatuses(holder, currentMinutes, college)
                
                // Продолжаем обновление с умным интервалом
                if (holder.itemView.isAttachedToWindow && isFragmentVisible && nextUpdateDelay > 0) {
                    handler.postDelayed({
                        scheduleNextUpdate()
                    }, nextUpdateDelay)
                } else {
                    holder.statusHandler = null
                }
            } catch (e: Exception) {
                android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении статуса: ${e.message}", e)
                holder.statusHandler = null
            }
        }
        
        // Запускаем первое обновление через минимальную задержку (чтобы не дублировать первое обновление)
        handler.postDelayed({
            scheduleNextUpdate()
        }, 1000) // 1 секунда - минимальный интервал для следующего обновления
    }
    
    private fun hideAllLessonStatuses(holder: ScheduleViewHolder) {
        // Проверка что ViewHolder еще привязан
        if (!holder.itemView.isAttachedToWindow) {
            return
        }
        
        try {
            for (i in 0 until holder.itemsContainer.childCount) {
                val child = holder.itemsContainer.getChildAt(i) ?: continue
                child.findViewById<TextView>(R.id.lessonStatus)?.visibility = View.GONE
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при скрытии статусов уроков: ${e.message}", e)
        }
    }
    
    private fun animateBreakProgress(container: ViewGroup, beforeLesson: Int, afterLesson: Int) {
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val breakText = LessonTimes.getBreakText(beforeLesson, afterLesson, college)
        val lunchText = LessonTimes.getLunchText(beforeLesson, college)
        
        val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
        val isDuringBreak = breakText != null && checkBreakTime(beforeLesson, afterLesson, currentMinutes)
        val isDuringLunch = lunchText != null && checkLunchTime(beforeLesson, currentMinutes)
        
        if (isDuringBreak || isDuringLunch) {
            // Find break view and animate it
            container.postDelayed({
                for (i in 0 until container.childCount) {
                    val child = container.getChildAt(i)
                    val breakText = child.findViewById<TextView>(R.id.breakText)
                    if (breakText != null && (breakText.text.toString().contains("Перемена") || breakText.text.toString().contains("Обед"))) {
                        animateBreakHighlight(child)
                        break
                    }
                }
            }, 100)
        }
    }
    
    private fun checkBreakTime(beforeLesson: Int, afterLesson: Int, currentMinutes: Int): Boolean {
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val beforeTime = LessonTimes.getTime(beforeLesson, college)
        val afterTime = LessonTimes.getTime(afterLesson, college)
        if (beforeTime == null || afterTime == null) return false

        val beforeEnd = parseTimeToMinutes(beforeTime.endTime)
        val afterStart = parseTimeToMinutes(afterTime.startTime)
        return currentMinutes in (beforeEnd + 1) until afterStart
    }

    private fun checkLunchTime(afterLesson: Int, currentMinutes: Int): Boolean {
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val lunchText = LessonTimes.getLunchText(afterLesson, college)
        if (lunchText == null) return false
        
        // Parse lunch time from text (format: "Обед: HH:mm - HH:mm")
        val regex = Regex("\\d{1,2}:\\d{2}")
        val times = regex.findAll(lunchText).map { it.value }.toList()
        if (times.size != 2) return false
        
        val startMinutes = parseTimeToMinutes(times[0])
        val endMinutes = parseTimeToMinutes(times[1])
        return currentMinutes in startMinutes..endMinutes
    }
    
    private fun addLessonNumberAccent(lessonNumberView: TextView, lessonNum: Int) {
        // Add subtle scale accent to make numbers more prominent
        lessonNumberView.scaleX = 1.0f
        lessonNumberView.scaleY = 1.0f
        
        // Subtle elevation effect
        lessonNumberView.elevation = 1.5f
        
        // Add letter spacing for better readability
        lessonNumberView.letterSpacing = 0.03f
    }
    
    private fun animateItemAppearance(view: View) {
        if (!animationsEnabled) {
            view.alpha = 1f
            view.translationY = 0f
            view.scaleX = 1f
            view.scaleY = 1f
            return
        }
        
        // Проверка что view еще привязан
        if (!view.isAttachedToWindow) {
            view.alpha = 1f
            view.translationY = 0f
            view.scaleX = 1f
            view.scaleY = 1f
            return
        }
        
        try {
            view.alpha = 0f
            view.translationY = 40f
            view.scaleX = 0.92f
            view.scaleY = 0.92f
            view.rotationX = 5f // Легкий 3D эффект
            
            view.post {
                // Двойная проверка после post
                if (!view.isAttachedToWindow) {
                    view.alpha = 1f
                    view.rotationX = 0f
                    view.translationY = 0f
                    view.scaleX = 1f
                    view.scaleY = 1f
                    return@post
                }
                
                try {
                    // Анимация с эффектом пружины (как в Telegram)
                    val animatorSet = android.animation.AnimatorSet()
                    
                    val alphaAnimator = android.animation.ObjectAnimator.ofFloat(view, "alpha", 0f, 1f)
                    val translationAnimator = android.animation.ObjectAnimator.ofFloat(view, "translationY", 40f, 0f)
                    val scaleXAnimator = android.animation.ObjectAnimator.ofFloat(view, "scaleX", 0.92f, 1f)
                    val scaleYAnimator = android.animation.ObjectAnimator.ofFloat(view, "scaleY", 0.92f, 1f)
                    val rotationXAnimator = android.animation.ObjectAnimator.ofFloat(view, "rotationX", 5f, 0f)
                    
                    alphaAnimator.duration = 300
                    translationAnimator.duration = 400
                    scaleXAnimator.duration = 400
                    scaleYAnimator.duration = 400
                    rotationXAnimator.duration = 400
                    
                    // Используем OvershootInterpolator для эффекта пружины
                    translationAnimator.interpolator = OvershootInterpolator(1.1f)
                    scaleXAnimator.interpolator = OvershootInterpolator(1.1f)
                    scaleYAnimator.interpolator = OvershootInterpolator(1.1f)
                    rotationXAnimator.interpolator = OvershootInterpolator(1.1f)
                    alphaAnimator.interpolator = DecelerateInterpolator()
                    
                    animatorSet.playTogether(alphaAnimator, translationAnimator, scaleXAnimator, scaleYAnimator, rotationXAnimator)
                    
                    animatorSet.addListener(object : android.animation.AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: android.animation.Animator) {
                            // Убеждаемся что значения установлены правильно
                            if (view.isAttachedToWindow) {
                                view.alpha = 1f
                                view.translationY = 0f
                                view.scaleX = 1f
                                view.scaleY = 1f
                            }
                        }
                    })
                    
                    animatorSet.start()
                } catch (e: Exception) {
                    android.util.Log.e("ScheduleAdapter", "Ошибка при создании анимации появления: ${e.message}", e)
                    // Fallback: просто показываем без анимации
                    view.alpha = 1f
                    view.translationY = 0f
                    view.scaleX = 1f
                    view.scaleY = 1f
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при настройке анимации появления: ${e.message}", e)
            // Fallback: просто показываем без анимации
            view.alpha = 1f
            view.translationY = 0f
            view.scaleX = 1f
            view.scaleY = 1f
        }
    }
    
    private fun animateBreakHighlight(view: View) {
        // Проверка что view еще привязан
        if (!view.isAttachedToWindow) {
            return
        }
        
        try {
            view.postDelayed({
                if (view.isAttachedToWindow) {
                    try {
                        ValueAnimator.ofFloat(0.5f, 1f, 0.5f).apply {
                            duration = 3000
                            repeatCount = ValueAnimator.INFINITE
                            repeatMode = ValueAnimator.REVERSE
                            interpolator = DecelerateInterpolator()
                            addUpdateListener { animator ->
                                // Проверка что view еще привязан перед обновлением
                                if (view.isAttachedToWindow) {
                                    try {
                                        val alpha = animator.animatedValue as Float
                                        view.alpha = alpha
                                    } catch (e: Exception) {
                                        android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении анимации перерыва: ${e.message}")
                                        cancel()
                                    }
                                } else {
                                    cancel()
                                }
                            }
                            start()
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("ScheduleAdapter", "Ошибка при создании анимации перерыва: ${e.message}", e)
                    }
                }
            }, 100)
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при настройке анимации перерыва: ${e.message}", e)
        }
    }

    override fun getItemCount(): Int = schedules.size

    fun updateSchedules(newSchedules: List<DaySchedule>) {
        val previousSchedules = schedules
        schedules = newSchedules
        
        // Принудительно пересчитать прогресс если изменилась группа/колледж
        // или если изменилось количество уроков в текущем дне
        val needsFullRefresh = previousSchedules.isNotEmpty() && newSchedules.isNotEmpty()
        
        notifyDataSetChanged()
    }
    
    /**
     * Принудительно обновить прогресс для всех карточек (вызывается при изменении настроек)
     */
    fun forceUpdateProgress() {
        // Уведомить адаптер о необходимости пересчета прогресса
        notifyDataSetChanged()
    }
    
    /**
     * Принудительно обновить статусы для всех видимых элементов
     */
    fun forceUpdateStatuses(recyclerView: RecyclerView) {
        try {
            val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
            val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
            
            // Обновляем статусы для всех видимых ViewHolder'ов
            for (i in 0 until recyclerView.childCount) {
                val child = recyclerView.getChildAt(i) ?: continue
                val holder = recyclerView.getChildViewHolder(child) as? ScheduleViewHolder ?: continue
                
                if (showLessonStatus) {
                    updateAllLessonStatuses(holder, currentMinutes, college)
                    // Перезапускаем обновление статуса только если фрагмент виден
                    if (isFragmentVisible) {
                        startStatusUpdates(holder, college)
                    }
                } else {
                    hideAllLessonStatuses(holder)
                    // Останавливаем обновление статуса
                    holder.statusHandler?.removeCallbacksAndMessages(null)
                    holder.statusHandler = null
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при принудительном обновлении статусов: ${e.message}", e)
        }
    }
    
    /**
     * Приостановить все обновления (вызывается при onPause)
     */
    fun pauseUpdates() {
        isFragmentVisible = false
        // Останавливаем все активные обновления для всех ViewHolder'ов
        // Это делается через проверку isFragmentVisible в методах обновления
        // Но также можно явно остановить все handlers, если нужно
    }
    
    /**
     * Остановить все обновления для всех ViewHolder'ов (вызывается при onDestroyView)
     */
    fun stopAllUpdates() {
        isFragmentVisible = false
        // Все handlers будут остановлены автоматически при следующей проверке isFragmentVisible
    }
    
    /**
     * Возобновить обновления (вызывается при onResume)
     */
    fun resumeUpdates(recyclerView: RecyclerView) {
        isFragmentVisible = true
        // Перезапускаем обновления для видимых элементов
        try {
            val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
            
            for (i in 0 until recyclerView.childCount) {
                val child = recyclerView.getChildAt(i) ?: continue
                val holder = recyclerView.getChildViewHolder(child) as? ScheduleViewHolder ?: continue
                
                // Перезапускаем обновление прогресса
                holder.currentLessonNumbers?.let { lessonNumbers ->
                    updateDayProgress(holder, lessonNumbers)
                }
                
                // Перезапускаем обновление статуса, если включено
                if (showLessonStatus) {
                    startStatusUpdates(holder, college)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при возобновлении обновлений: ${e.message}", e)
        }
    }

    private fun formatDayName(day: String): String {
        return when (day) {
            "Пн" -> "Понедельник"
            "Вт" -> "Вторник"
            "Ср" -> "Среда"
            "Чт" -> "Четверг"
            "Пт" -> "Пятница"
            "Сб" -> "Суббота"
            "Вс" -> "Воскресенье"
            else -> day
        }
    }

    private fun formatDate(date: String): String {
        return try {
            val inputFormat = java.text.SimpleDateFormat("dd.MM.yyyy", java.util.Locale.getDefault())
            val outputFormat = java.text.SimpleDateFormat("d MMMM", java.util.Locale.forLanguageTag("ru-RU"))
            val dateObj = inputFormat.parse(date)
            outputFormat.format(dateObj ?: java.util.Date())
        } catch (e: Exception) {
            date
        }
    }

    private fun buildDetails(item: com.example.raspisanie.data.ScheduleItem): String {
        val parts = mutableListOf<String>()
        item.classroom?.let { parts.add("Ауд. $it") }
        item.teacher?.let { parts.add(it) }
        return parts.joinToString(" • ")
    }
    
    private fun applyFontToView(view: View) {
        try {
            val ndotFont = context?.resources?.getFont(R.font.ndot)
            if (ndotFont != null) {
                applyFontRecursive(view, ndotFont)
            }
        } catch (e: Exception) {
            // Fallback
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
    
    private fun applyHalloweenAccents(
        lessonView: View,
        subjectView: TextView,
        lessonNumberView: TextView,
        lessonProgressOverlay: View
    ) {
        val halloweenOrange = context?.getColor(R.color.custom_colorPrimary) ?: 0xFFFF6B35.toInt()
        
        // Apply orange tint to subject name (soft orange glow)
        val subjectText = subjectView.text.toString()
        if (subjectText.isNotEmpty()) {
            // Create a softer orange tint (85% orange, 15% white)
            val orangeTint = android.graphics.Color.argb(
                255,
                (255 * 0.85 + 255 * 0.15).toInt().coerceAtMost(255), // R
                (107 * 0.85 + 255 * 0.15).toInt().coerceAtMost(255), // G
                (53 * 0.85 + 255 * 0.15).toInt().coerceAtMost(255) // B
            )
            subjectView.setTextColor(orangeTint)
        }
        
        // Apply bright orange to lesson number (will be overridden by updateCircleState if needed)
        // Only set if it's not a passed lesson
        lessonNumberView.elevation = 3f
        
        // Apply theme-specific progress overlay fill
        when {
            isNothingTheme -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_nothing)
            isHalloweenTheme -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_halloween)
            isGreenTheme -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_green)
            isNewYearTheme -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_newyear)
            isLightTheme -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_light)
            isDarkTheme -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_dark)
            else -> lessonProgressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill)
        }
    }
    
    private fun applyHalloweenToBreak(breakTextView: TextView) {
        val halloweenOrange = context?.getColor(R.color.custom_colorPrimary) ?: 0xFFFF6B35.toInt()
        // Soft orange tint for breaks/lunches
        val orangeTint = android.graphics.Color.argb(
            255,
            (255 * 0.75 + 153 * 0.25).toInt().coerceAtMost(255), // R
            (107 * 0.75 + 153 * 0.25).toInt().coerceAtMost(255), // G
            (53 * 0.75 + 153 * 0.25).toInt().coerceAtMost(255) // B
        )
        breakTextView.setTextColor(orangeTint)
    }

    /**
     * Анимация зажатия карточки с эффектом масштабирования и вибрации
     */
    private fun animateCardPress(view: View, onComplete: () -> Unit) {
        if (!view.isAttachedToWindow) {
            onComplete()
            return
        }
        
        // Сохраняем исходное значение elevation
        val originalElevation = view.elevation
        
        // Тактильная обратная связь
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        
        // Анимация зажатия: уменьшение с легким подъемом
        val scaleAnimator = android.animation.ObjectAnimator.ofFloat(view, "scaleX", 1f, 0.95f)
        val scaleYAnimator = android.animation.ObjectAnimator.ofFloat(view, "scaleY", 1f, 0.95f)
        val elevationAnimator = android.animation.ObjectAnimator.ofFloat(view, "elevation", originalElevation, originalElevation + 8f)
        
        val pressAnimator = android.animation.AnimatorSet().apply {
            playTogether(scaleAnimator, scaleYAnimator, elevationAnimator)
            duration = 150
            interpolator = DecelerateInterpolator()
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    // Легкое возвращение с эффектом отскока
                    val releaseAnimator = android.animation.AnimatorSet().apply {
                        playTogether(
                            android.animation.ObjectAnimator.ofFloat(view, "scaleX", 0.95f, 1f),
                            android.animation.ObjectAnimator.ofFloat(view, "scaleY", 0.95f, 1f),
                            android.animation.ObjectAnimator.ofFloat(view, "elevation", originalElevation + 8f, originalElevation)
                        )
                        duration = 200
                        interpolator = OvershootInterpolator(1.2f)
                        addListener(object : android.animation.AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: android.animation.Animator) {
                                onComplete()
                            }
                        })
                    }
                    releaseAnimator.start()
                }
            })
        }
        
        pressAnimator.start()
    }
    
    private fun showShareMenu(holder: ScheduleViewHolder, daySchedule: DaySchedule) {
        val view = holder.cardBackground
        val context = view.context ?: return

        // Применяем тему к BottomSheetDialog
        val dialog = BottomSheetDialog(context, getBottomSheetTheme(context))
        val sheetView = LayoutInflater.from(context).inflate(R.layout.bottom_sheet_share_schedule, null)
        
        // Применяем тему к элементам внутри sheetView
        applyThemeToShareSheet(sheetView, context)

        sheetView.findViewById<TextView>(R.id.shareSubtitle)?.text = context.getString(R.string.share_menu_hint)

        sheetView.findViewById<MaterialButton>(R.id.btnSharePrimary)?.apply {
            text = context.getString(R.string.share_day)
            setOnClickListener { view ->
                // Haptic feedback для лучшего UX (как в exteraGram)
                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                dialog.dismiss()
                // Основная кнопка делится изображением
                shareDaySchedule(holder, daySchedule, PreferencesManager.SHARE_FORMAT_IMAGE)
            }
        }
 
        sheetView.findViewById<MaterialButton>(R.id.btnShareText)?.apply {
            setOnClickListener { view ->
                // Haptic feedback
                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                dialog.dismiss()
                shareDaySchedule(holder, daySchedule, PreferencesManager.SHARE_FORMAT_TEXT)
            }
        }
 
        sheetView.findViewById<MaterialButton>(R.id.btnCopy)?.setOnClickListener { view ->
            // Haptic feedback
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
            dialog.dismiss()
            copyDaySchedule(context, daySchedule)
        }

        dialog.setContentView(sheetView)
        
        // Настройка поведения BottomSheet
        dialog.behavior.isDraggable = true
        dialog.behavior.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
        
        // Настройка закругления верхних углов
        dialog.window?.let { window ->
            window.setLayout(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        
        // Улучшенная анимация появления элементов (как в Telegram)
        sheetView.post {
            val title = sheetView.findViewById<TextView>(R.id.shareTitle)
            val subtitle = sheetView.findViewById<TextView>(R.id.shareSubtitle)
            val buttons = listOf(
                sheetView.findViewById<MaterialButton>(R.id.btnSharePrimary),
                sheetView.findViewById<MaterialButton>(R.id.btnShareText),
                sheetView.findViewById<MaterialButton>(R.id.btnCopy)
            )
            
            // Анимация заголовка и подзаголовка
            title?.let {
                it.alpha = 0f
                it.translationY = 20f
                it.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(200)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }
            
            subtitle?.let {
                it.alpha = 0f
                it.translationY = 20f
                it.postDelayed({
                    if (it.isAttachedToWindow) {
                        it.animate()
                            .alpha(1f)
                            .translationY(0f)
                            .setDuration(200)
                            .setInterpolator(DecelerateInterpolator())
                            .start()
                    }
                }, 50)
            }
            
            // Анимация кнопок с более плавным эффектом
            buttons.forEachIndexed { index, button ->
                button?.let {
                    it.alpha = 0f
                    it.translationY = 25f
                    it.scaleX = 0.95f
                    it.scaleY = 0.95f
                    it.postDelayed({
                        if (it.isAttachedToWindow) {
                            it.animate()
                                .alpha(1f)
                                .translationY(0f)
                                .scaleX(1f)
                                .scaleY(1f)
                                .setDuration(300)
                                .setInterpolator(OvershootInterpolator(0.8f))
                                .setStartDelay(index * 40L)
                                .start()
                        }
                    }, 100 + (index * 30L))
                }
            }
        }
        
        // Применяем закругление через MaterialShapeDrawable после показа диалога
        dialog.setOnShowListener {
            val bottomSheet = dialog.findViewById<android.view.View>(com.google.android.material.R.id.design_bottom_sheet)
            bottomSheet?.let { view ->
                val shapeAppearanceModel = com.google.android.material.shape.ShapeAppearanceModel.builder()
                    .setTopLeftCorner(com.google.android.material.shape.CornerFamily.ROUNDED, 24f)
                    .setTopRightCorner(com.google.android.material.shape.CornerFamily.ROUNDED, 24f)
                    .build()
                
                // Применяем цвет фона в зависимости от темы
                val prefs = PreferencesManager(context)
                val backgroundColor = when (prefs.theme) {
                    PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_colorBackground)
                    PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_colorBackground)
                    PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_windowBackground)
                    PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_colorBackground)
                    PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_colorBackground)
                    PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_colorBackground)
                    PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_colorBackground)
                    else -> ContextCompat.getColor(context, R.color.dark_colorBackground)
                }
                
                val backgroundDrawable = com.google.android.material.shape.MaterialShapeDrawable(shapeAppearanceModel).apply {
                    fillColor = android.content.res.ColorStateList.valueOf(backgroundColor)
                }
                
                view.background = backgroundDrawable
            }
        }
        
        dialog.show()
    }
    
    /**
     * Получить тему для BottomSheetDialog в зависимости от выбранной темы приложения
     */
    private fun getBottomSheetTheme(context: Context): Int {
        val prefs = PreferencesManager(context)
        return when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> com.google.android.material.R.style.Theme_MaterialComponents_Light_BottomSheetDialog
            PreferencesManager.THEME_DARK -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
            PreferencesManager.THEME_PURPLE -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
            PreferencesManager.THEME_HALLOWEEN -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
            PreferencesManager.THEME_NOTHING -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
            PreferencesManager.THEME_GREEN -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
            PreferencesManager.THEME_NEW_YEAR -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
            else -> com.google.android.material.R.style.Theme_MaterialComponents_BottomSheetDialog
        }
    }
    
    /**
     * Применить тему к элементам внутри BottomSheet
     */
    private fun applyThemeToShareSheet(sheetView: View, context: Context) {
        val prefs = PreferencesManager(context)
        
        // Применяем цвета текста
        val textPrimaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_textColorPrimary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_textColorPrimary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_textColorPrimary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_textColorPrimary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_textColorPrimary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_textColorPrimary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_textColorPrimary)
            else -> ContextCompat.getColor(context, R.color.dark_textColorPrimary)
        }
        
        val textSecondaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_textColorSecondary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_textColorSecondary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_textColorSecondary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_textColorSecondary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_textColorSecondary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_textColorSecondary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_textColorSecondary)
            else -> ContextCompat.getColor(context, R.color.dark_textColorSecondary)
        }
        
        val primaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_colorPrimary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_colorPrimary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_colorPrimary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_colorPrimary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_colorPrimary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_colorPrimary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_colorPrimary)
            else -> ContextCompat.getColor(context, R.color.dark_colorPrimary)
        }
        
        val onPrimaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_colorOnPrimary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_colorOnPrimary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_colorOnPrimary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_colorOnPrimary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_colorOnPrimary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_colorOnPrimary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_colorOnPrimary)
            else -> ContextCompat.getColor(context, R.color.dark_colorOnPrimary)
        }
        
        // Применяем цвета к тексту
        sheetView.findViewById<TextView>(R.id.shareTitle)?.setTextColor(textPrimaryColor)
        sheetView.findViewById<TextView>(R.id.shareSubtitle)?.setTextColor(textSecondaryColor)
        
        // Применяем цвета к кнопкам с улучшенным стилем
        sheetView.findViewById<MaterialButton>(R.id.btnSharePrimary)?.apply {
            setBackgroundColor(primaryColor)
            setTextColor(onPrimaryColor)
            // Улучшаем визуальное восприятие основной кнопки
            rippleColor = android.content.res.ColorStateList.valueOf(onPrimaryColor)
        }
        
        sheetView.findViewById<MaterialButton>(R.id.btnShareText)?.apply {
            setTextColor(textPrimaryColor)
            // Добавляем легкий ripple эффект
            rippleColor = android.content.res.ColorStateList.valueOf(textPrimaryColor)
        }
        
        sheetView.findViewById<MaterialButton>(R.id.btnCopy)?.apply {
            setTextColor(textPrimaryColor)
            // Добавляем легкий ripple эффект
            rippleColor = android.content.res.ColorStateList.valueOf(textPrimaryColor)
        }
    }

    private fun shareDaySchedule(holder: ScheduleViewHolder, daySchedule: DaySchedule, formatOverride: String?) {
        val context = holder.itemView.context ?: return
        val format = formatOverride ?: PreferencesManager.SHARE_FORMAT_TEXT
        try {
            when (format) {
                PreferencesManager.SHARE_FORMAT_IMAGE -> shareDayAsImage(context, holder.cardBackground, daySchedule)
                else -> shareDayAsText(context, daySchedule)
            }
        } catch (e: Exception) {
            Toast.makeText(context, context.getString(R.string.share_schedule_failed), Toast.LENGTH_SHORT).show()
        }
    }

    private fun shareDayAsText(context: Context, daySchedule: DaySchedule) {
        val shareText = buildShareText(context, daySchedule)
        val subject = context.getString(R.string.share_schedule_subject, daySchedule.day, daySchedule.date)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, shareText)
        }
        val chooser = Intent.createChooser(shareIntent, context.getString(R.string.share_schedule_title))
        startActivitySafely(context, chooser)
    }

    private fun shareDayAsImage(context: Context, shareView: View, daySchedule: DaySchedule) {
        if (shareView.width == 0 || shareView.height == 0) {
            shareView.post { shareDayAsImage(context, shareView, daySchedule) }
            return
        }

        try {
            val bitmap = captureViewBitmap(shareView)
            
            if (bitmap == null) {
                android.util.Log.e("ScheduleAdapter", "Не удалось создать bitmap из view")
                Toast.makeText(context, "Не удалось создать изображение для шаринга", Toast.LENGTH_SHORT).show()
                return
            }

            val shareDir = File(context.cacheDir, "schedule_share").apply {
                if (!exists()) {
                    mkdirs()
                } else {
                    listFiles()?.forEach { child ->
                        if (child.name.startsWith("schedule_share_")) {
                            child.delete()
                        }
                    }
                }
            }

            val file = File.createTempFile("schedule_share_", ".png", shareDir)
            FileOutputStream(file).use { stream ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    android.util.Log.e("ScheduleAdapter", "Не удалось сохранить bitmap в файл")
                    Toast.makeText(context, "Не удалось сохранить изображение", Toast.LENGTH_SHORT).show()
                    return
                }
            }

            val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            
            // Создаем Intent для шаринга изображения
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.share_schedule_subject, daySchedule.day, daySchedule.date))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            
            // Предоставляем временные права на чтение URI для всех приложений
            val chooser = Intent.createChooser(shareIntent, context.getString(R.string.share_schedule_title))
            val resInfoList = context.packageManager.queryIntentActivities(chooser, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
            for (resolveInfo in resInfoList) {
                val packageName = resolveInfo.activityInfo.packageName
                context.grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            
            startActivitySafely(context, chooser)
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при шаринге изображения", e)
            Toast.makeText(context, "Ошибка при создании изображения: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun buildShareText(context: Context, daySchedule: DaySchedule): String {
        val builder = StringBuilder()
        builder.append(context.getString(R.string.share_schedule_subject, daySchedule.day, daySchedule.date))
        builder.append('\n')
        builder.append("==============================")
        builder.append('\n')

        val items = daySchedule.items
        if (items.isEmpty()) {
            builder.append(context.getString(R.string.share_schedule_no_lessons))
            builder.append('\n')
        } else {
            val grouped = items.groupBy { it.lessonNumber }.toSortedMap()
            val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB

            grouped.forEach { (lessonNumber, lessonItems) ->
                val time = LessonTimes.formatTime(lessonNumber, college)
                builder.append(lessonNumber)
                builder.append('.').append(' ')
                if (time.isNotEmpty()) {
                    builder.append('[').append(time).append(']').append(' ')
                }

                if (lessonItems.size == 1) {
                    builder.append(formatLessonLine(lessonItems.first()))
                    builder.append('\n')
                } else {
                    builder.append('\n')
                    lessonItems.forEach { item ->
                        builder.append("    • ")
                        val subgroup = item.subgroup
                        if (subgroup != null) {
                            builder.append(subgroup).append(" подг. ")
                        }
                        builder.append(formatLessonLine(item))
                        builder.append('\n')
                    }
                }
                builder.append('\n')
            }
        }

        builder.append("#Расписание")
        return builder.toString().trimEnd()
    }

    private fun formatLessonLine(item: com.example.raspisanie.data.ScheduleItem): String {
        val parts = mutableListOf<String>()
        item.subject?.let { subject -> parts.add(subject) }
        item.classroom?.let { classroom -> parts.add("ауд. $classroom") }
        item.teacher?.let { teacher -> parts.add(teacher) }
        return if (parts.isEmpty()) {
            "—"
        } else {
            parts.joinToString(", ")
        }
    }

    private fun copyDaySchedule(context: Context, daySchedule: DaySchedule) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val clip = ClipData.newPlainText("schedule", buildShareText(context, daySchedule))
        clipboard?.setPrimaryClip(clip)
        Toast.makeText(context, context.getString(R.string.share_copy_success), Toast.LENGTH_SHORT).show()
    }

    private fun startActivitySafely(context: Context, intent: Intent) {
        val safeIntent = Intent(intent)
        if (context !is Activity) {
            safeIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(safeIntent)
            Toast.makeText(context, context.getString(R.string.share_schedule_ready), Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(context, context.getString(R.string.share_schedule_failed), Toast.LENGTH_SHORT).show()
        }
    }

    private fun captureViewBitmap(view: View): Bitmap? {
        return try {
            if (view.width <= 0 || view.height <= 0) {
                android.util.Log.w("ScheduleAdapter", "View имеет нулевой размер: ${view.width}x${view.height}")
                return null
            }
            
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val background: Drawable? = view.background
            if (background != null) {
                background.draw(canvas)
            } else {
                val color = ContextCompat.getColor(view.context, android.R.color.background_light)
                canvas.drawColor(color)
            }
            view.draw(canvas)
            bitmap
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при создании bitmap из view", e)
            null
        }
    }

    private fun animateArc(previousArc: View, nextArc: View) {
        if (!animationsEnabled) {
            previousArc.alpha = 0f
            nextArc.alpha = 1f
            return
        }

        previousArc.alpha = 1f
        nextArc.alpha = 0f

        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 500
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val progress = animator.animatedValue as Float
                previousArc.alpha = 1f - progress
                nextArc.alpha = progress
            }
            start()
        }
    }
}
