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
        
        holder.dayName.text = formatDayName(daySchedule.day)
        holder.dateText.text = formatDate(daySchedule.date)
        
        // Apply font size
        val fontSizeMultiplier = getFontSizeMultiplier()
        val baseDayNameSize = if (isToday(daySchedule.date)) 26f else 24f
        holder.dayName.textSize = baseDayNameSize * fontSizeMultiplier
        holder.dateText.textSize = 14f * fontSizeMultiplier
        
        // Apply theme-specific gradient background to card
        if (context != null) {
            val bgResId = when (prefs?.theme) {
                PreferencesManager.THEME_LIGHT -> R.drawable.card_background_light
                PreferencesManager.THEME_DARK -> R.drawable.card_background_dark
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
                    
                    if (item.subgroup != null && items.size > 1) {
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
                    updateAllLessonStatuses(holder, currentMinutesForStatus, college)
                } else {
                    hideAllLessonStatuses(holder)
                }
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
            showShareMenu(holder, daySchedule)
            true
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
        // ЖЕСТКАЯ ВАЛИДАЦИЯ: проверяем что ViewHolder еще привязан
        if (!holder.itemView.isAttachedToWindow) {
            android.util.Log.w("ScheduleAdapter", "⚠️ ViewHolder не привязан к окну, пропускаем обновление")
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
        
        // ФИНАЛЬНАЯ ПРОВЕРКА: убеждаемся что линия не вышла за границы
        holder.itemView.postDelayed({
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
    
    private fun updateProgressHeight(holder: ScheduleViewHolder, containerHeight: Int, progress: Float) {
        // ЖЕСТКАЯ ВАЛИДАЦИЯ входных данных
        if (containerHeight <= 0) {
            android.util.Log.w("ScheduleAdapter", "⚠️ containerHeight <= 0: $containerHeight, пропускаем обновление")
            holder.progressIndicator.visibility = View.GONE
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
        val maxAllowedHeight = (containerHeight * 0.999f).toInt()
        progressHeight = progressHeight.coerceAtMost(maxAllowedHeight)
        
        // ОТЛАДОЧНОЕ ЛОГИРОВАНИЕ
        android.util.Log.d("ScheduleAdapter", "📊 Прогресс: clampedProgress=$clampedProgress, containerHeight=$containerHeight, progressHeight=$progressHeight")
        
        // Update layout params - ЖЕСТКИЕ ограничения
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
        
        // ЖЕСТКОЕ позиционирование: убеждаемся что линия привязана к верху контейнера
        // Ограничение высоты через layout params уже применено выше
        holder.progressIndicator.layoutParams = holder.progressIndicator.layoutParams // Принудительное обновление
        
        // Ensure behind items (но не влияет на размеры)
        holder.progressIndicator.elevation = -1f
        
        // ВАЛИДАЦИЯ: проверяем что линия не выходит за границы
        holder.itemView.post {
            val actualHeight = holder.progressIndicator.height
            val wrapperHeight = holder.itemsWrapper.height
            if (actualHeight > wrapperHeight && wrapperHeight > 0) {
                android.util.Log.e("ScheduleAdapter", "🚨 КРИТИЧЕСКАЯ ОШИБКА: actualHeight ($actualHeight) > wrapperHeight ($wrapperHeight)! Исправляю немедленно!")
                val fixedParams = holder.progressIndicator.layoutParams as? ViewGroup.MarginLayoutParams
                fixedParams?.height = wrapperHeight.coerceAtMost(containerHeight)
                holder.progressIndicator.layoutParams = fixedParams
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
        view.alpha = 0f
        view.scaleY = 0f
        view.pivotY = 0f
        
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1500
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val scale = animator.animatedValue as Float
                view.scaleY = scale
                view.alpha = scale
            }
            start()
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
        
        val handler = Handler(Looper.getMainLooper())
        holder.progressHandler = handler
        
        handler.postDelayed({
            try {
                // ЖЕСТКАЯ ПРОВЕРКА: ViewHolder еще привязан и валиден
                if (!holder.itemView.isAttachedToWindow) {
                    android.util.Log.w("ScheduleAdapter", "⚠️ ViewHolder отвязан, отменяю обновление")
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

                    if (holder.itemView.isAttachedToWindow) {
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
        }, 60000) // Update every minute
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
        val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val lessonTime = LessonTimes.getTime(lessonNumber, college) ?: return
        
        val lessonStartMinutes = parseTimeToMinutes(lessonTime.startTime)
        val lessonEndMinutes = parseTimeToMinutes(lessonTime.endTime)
        val context = lessonNumberView.context
        
        // Use theme's textColorPrimary for consistency
        val typedArray = context.theme.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary))
        val normalTextColor = typedArray.getColor(0, context.getColor(R.color.textPrimary))
        typedArray.recycle()
        
        // Get accent color for active lesson
        val typedArrayAccent = context.theme.obtainStyledAttributes(intArrayOf(android.R.attr.colorPrimary))
        val accentColor = typedArrayAccent.getColor(0, context.getColor(R.color.textPrimary))
        typedArrayAccent.recycle()
        
        when {
            currentMinutes >= lessonEndMinutes -> {
                // Lesson passed - filled circle with white text
                progressOverlay.visibility = View.VISIBLE
                
                // Apply theme-specific progress fill
                when {
                    isNothingTheme -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_nothing)
                    isHalloweenTheme -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_halloween)
                    isGreenTheme -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_green)
                    isNewYearTheme -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_newyear)
                    isLightTheme -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_light)
                    isDarkTheme -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill_dark)
                    else -> progressOverlay.setBackgroundResource(R.drawable.lesson_progress_fill)
                }
                
                // Text color based on theme: black for light, white for dark
                val textColorForPassed = if (isLightTheme) {
                    context.getColor(android.R.color.black)
                } else {
                    context.getColor(android.R.color.white)
                }
                lessonNumberView.setTextColor(textColorForPassed)
                lessonNumberView.textSize = 16f
                lessonNumberView.scaleX = 1.0f
                lessonNumberView.scaleY = 1.0f
            }
            currentMinutes >= lessonStartMinutes -> {
                // Lesson is active now - highlight with accent color
                progressOverlay.visibility = View.GONE
                
                // Use theme-specific accent color for active lesson
                val finalAccentColor = when {
                    isHalloweenTheme -> context.getColor(R.color.custom_colorPrimary)
                    isGreenTheme -> context.getColor(R.color.green_colorPrimary)
                    isNewYearTheme -> context.getColor(R.color.newyear_colorPrimary)
                    else -> accentColor
                }
                
                lessonNumberView.setTextColor(finalAccentColor)
                lessonNumberView.textSize = 17f // Slightly larger
                lessonNumberView.alpha = 1f
                
                // Add pulsing animation for better visibility (only if not already animating)
                val existingAnimator = lessonNumberView.tag as? ValueAnimator
                if (existingAnimator == null || !existingAnimator.isRunning) {
                    animateActiveLesson(lessonNumberView)
                }
            }
            else -> {
                // Lesson not started - normal circle
                progressOverlay.visibility = View.GONE
                // Use theme-specific accent color for normal lessons
                val finalNormalColor = when {
                    isHalloweenTheme -> context.getColor(R.color.custom_colorPrimary)
                    isGreenTheme -> context.getColor(R.color.green_colorPrimary)
                    isNewYearTheme -> context.getColor(R.color.newyear_colorPrimary)
                    else -> normalTextColor
                }
                lessonNumberView.setTextColor(finalNormalColor)
                lessonNumberView.textSize = 16f
                lessonNumberView.alpha = 1f
                lessonNumberView.scaleX = 1.0f
                lessonNumberView.scaleY = 1.0f
                // Cancel any active animation
                val animator = lessonNumberView.tag as? ValueAnimator
                animator?.cancel()
                lessonNumberView.tag = null
            }
        }
    }
    
    private fun animateActiveLesson(view: TextView) {
        // Clear any existing animation
        view.clearAnimation()
        view.animate().cancel()
        
        // Pulsing animation for active lesson - more subtle and visible
        ValueAnimator.ofFloat(1.0f, 1.12f, 1.0f).apply {
            duration = 1200
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addUpdateListener { animator ->
                val scale = animator.animatedValue as Float
                view.scaleX = scale
                view.scaleY = scale
            }
            start()
            
            // Store animator in view tag to prevent multiple animations
            view.tag = this
        }
    }
    
    private fun updateAllCircles(holder: ScheduleViewHolder, currentMinutes: Int) {
        for (i in 0 until holder.itemsContainer.childCount) {
            val child = holder.itemsContainer.getChildAt(i)
            val lessonNumberView = child.findViewById<TextView>(R.id.lessonNumber)
            val progressOverlay = child.findViewById<View>(R.id.lessonProgressOverlay)
            
            if (lessonNumberView != null && progressOverlay != null) {
                val lessonNum = lessonNumberView.text.toString().toIntOrNull() ?: continue
                updateCircleState(lessonNumberView, progressOverlay, lessonNum)
            }
        }
    }

    private fun updateAllLessonStatuses(holder: ScheduleViewHolder, currentMinutes: Int, college: String) {
        val context = holder.itemView.context ?: return
        if (!showLessonStatus || currentMinutes < 0) {
            hideAllLessonStatuses(holder)
            return
        }

        val statusMap = linkedMapOf<Int, MutableList<TextView>>()
        for (i in 0 until holder.itemsContainer.childCount) {
            val child = holder.itemsContainer.getChildAt(i)
            val statusView = child.findViewById<TextView>(R.id.lessonStatus) ?: continue
            val lessonNumberView = child.findViewById<TextView>(R.id.lessonNumber) ?: continue
            val lessonNum = lessonNumberView.text.toString().toIntOrNull() ?: continue
            statusView.visibility = View.GONE
            statusMap.getOrPut(lessonNum) { mutableListOf() }.add(statusView)
        }

        if (statusMap.isEmpty()) return

        val sortedNumbers = statusMap.keys.sorted()
        var currentLesson: Int? = null
        var nextLesson: Int? = null

        for (lessonNum in sortedNumbers) {
            val time = LessonTimes.getTime(lessonNum, college) ?: continue
            val start = parseTimeToMinutes(time.startTime)
            val end = parseTimeToMinutes(time.endTime)
            when {
                currentMinutes in start until end -> {
                    currentLesson = lessonNum
                    break
                }
                currentMinutes < start -> {
                    nextLesson = lessonNum
                    break
                }
            }
        }

        if (currentLesson == null) {
            for (lessonNum in sortedNumbers) {
                val time = LessonTimes.getTime(lessonNum, college) ?: continue
                val start = parseTimeToMinutes(time.startTime)
                if (currentMinutes < start) {
                    nextLesson = lessonNum
                    break
                }
            }
        } else {
            val currentIndex = sortedNumbers.indexOf(currentLesson!!)
            if (currentIndex >= 0) {
                for (idx in currentIndex + 1 until sortedNumbers.size) {
                    val candidate = sortedNumbers[idx]
                    if (LessonTimes.getTime(candidate, college) != null) {
                        nextLesson = candidate
                        break
                    }
                }
            }
        }

        val lastLesson = sortedNumbers.lastOrNull()

        fun setStatus(lessonNum: Int?, text: String?) {
            if (lessonNum == null || text == null) return
            statusMap[lessonNum]?.forEach { view ->
                view.text = text
                view.visibility = View.VISIBLE
            }
        }

        currentLesson?.let { lessonNum ->
            val time = LessonTimes.getTime(lessonNum, college)
            if (time != null) {
                val remaining = (parseTimeToMinutes(time.endTime) - currentMinutes).coerceAtLeast(1)
                setStatus(lessonNum, context.getString(R.string.lesson_status_remaining, remaining))
            }
        }

        nextLesson?.let { lessonNum ->
            val time = LessonTimes.getTime(lessonNum, college)
            if (time != null) {
                val diff = (parseTimeToMinutes(time.startTime) - currentMinutes).coerceAtLeast(1)
                setStatus(lessonNum, context.getString(R.string.lesson_status_starts_in, diff))
            }
        }

        if (currentLesson == null && nextLesson == null && lastLesson != null) {
            val time = LessonTimes.getTime(lastLesson, college)
            if (time != null && currentMinutes >= parseTimeToMinutes(time.endTime)) {
                val diff = (currentMinutes - parseTimeToMinutes(time.endTime)).coerceAtLeast(1)
                setStatus(lastLesson, context.getString(R.string.lesson_status_passed, diff))
            }
        }
    }

    private fun hideAllLessonStatuses(holder: ScheduleViewHolder) {
        for (i in 0 until holder.itemsContainer.childCount) {
            val child = holder.itemsContainer.getChildAt(i)
            child.findViewById<TextView>(R.id.lessonStatus)?.visibility = View.GONE
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
            return
        }
        
        view.alpha = 0f
        view.translationY = 20f
        
        view.post {
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 400
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    val progress = animator.animatedValue as Float
                    view.alpha = progress
                    view.translationY = 20f * (1 - progress)
                }
                start()
            }
        }
    }
    
    private fun animateBreakHighlight(view: View) {
        view.postDelayed({
            if (view.isAttachedToWindow) {
                ValueAnimator.ofFloat(0.5f, 1f, 0.5f).apply {
                    duration = 3000
                    repeatCount = ValueAnimator.INFINITE
                    repeatMode = ValueAnimator.REVERSE
                    interpolator = DecelerateInterpolator()
                    addUpdateListener { animator ->
                        val alpha = animator.animatedValue as Float
                        view.alpha = alpha
                    }
                    start()
                }
            }
        }, 100)
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

    private fun showShareMenu(holder: ScheduleViewHolder, daySchedule: DaySchedule) {
        val view = holder.cardBackground
        val context = view.context ?: return
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)

        val dialog = BottomSheetDialog(context)
        val sheetView = LayoutInflater.from(context).inflate(R.layout.bottom_sheet_share_schedule, null)

        sheetView.findViewById<TextView>(R.id.shareSubtitle)?.text = context.getString(R.string.share_menu_hint)

        sheetView.findViewById<MaterialButton>(R.id.btnSharePrimary)?.apply {
            text = context.getString(R.string.share_day)
            setOnClickListener {
                dialog.dismiss()
                // Основная кнопка делится изображением
                shareDaySchedule(holder, daySchedule, PreferencesManager.SHARE_FORMAT_IMAGE)
            }
        }
 
        sheetView.findViewById<MaterialButton>(R.id.btnShareText)?.apply {
            setOnClickListener {
                dialog.dismiss()
                shareDaySchedule(holder, daySchedule, PreferencesManager.SHARE_FORMAT_TEXT)
            }
        }
 
        sheetView.findViewById<MaterialButton>(R.id.btnCopy)?.setOnClickListener {
            dialog.dismiss()
            copyDaySchedule(context, daySchedule)
        }

        dialog.setContentView(sheetView)
        dialog.show()
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
