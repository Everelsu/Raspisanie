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
import android.view.animation.PathInterpolator
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.DiffUtil
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
    private val context: Context? = null,
    private val onDayClickListener: ((DaySchedule) -> Unit)? = null,
    private var plannedDates: Set<String> = emptySet(), // Даты из планового расписания
    private var selectedDayDate: String? = null, // Дата выбранного дня (если есть)
    private val onSelectedDayRemoveListener: (() -> Unit)? = null // Callback для удаления выбранного дня
) : RecyclerView.Adapter<ScheduleAdapter.ScheduleViewHolder>() {
    
    // Защита от множественных кликов
    private var lastClickTime: Long = 0
    private val clickDebounceTime = 500L // 500ms между кликами

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
    private val isBlueTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_BLUE
    private val isGrayTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_GRAY
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
        val cardBackground: View = view.findViewById(R.id.cardBackground)
        val btnRemoveSelectedDay: android.widget.ImageButton = view.findViewById(R.id.btnRemoveSelectedDay)

        var statusHandler: Handler? = null
        var currentLessonNumbers: List<Int>? = null
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ScheduleViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_day_schedule, parent, false)
        // Инициализируем тег для анимации появления
        view.tag = false
        return ScheduleViewHolder(view)
    }
    
    override fun onViewRecycled(holder: ScheduleViewHolder) {
        super.onViewRecycled(holder)
        // Clean up handlers and listeners when ViewHolder is recycled
        try {
            holder.statusHandler?.removeCallbacksAndMessages(null)
            holder.statusHandler = null
            holder.currentLessonNumbers = null
            
            // Отменить анимации itemView при переработке (тег сохраняется для проверки при повторном использовании)
            holder.itemView.animate().cancel()
            
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
        // Use adapterPosition to get the current position (may differ from parameter)
        val adapterPosition = holder.adapterPosition
        if (adapterPosition == RecyclerView.NO_POSITION || adapterPosition < 0 || adapterPosition >= schedules.size) {
            return
        }
        val daySchedule = schedules[adapterPosition]
        
        // Анимация появления только для действительно новых элементов (не при скролле)
        // Используем payload для определения, является ли это обновлением или новым элементом
        val viewId = holder.itemView.tag as? Long
        val currentId = daySchedule.date.hashCode().toLong()
        if (viewId == null || viewId != currentId) {
            // Новый элемент - анимируем только если он не был виден ранее
            val wasVisible = holder.itemView.alpha > 0.5f
            if (!wasVisible) {
                holder.itemView.alpha = 0f
                holder.itemView.translationY = 30f
                holder.itemView.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(300)
                    .setInterpolator(android.view.animation.DecelerateInterpolator())
                    .start()
            }
            holder.itemView.tag = currentId
        }

        // Сбросить состояние подсветки при перепривязке (на случай изменения настроек)
        holder.currentLessonNumbers = null
        holder.statusHandler?.removeCallbacksAndMessages(null)
        holder.statusHandler = null
        
        // Проверяем, является ли это фактическим занятием (не в плановом расписании)
        val isActual = !plannedDates.contains(daySchedule.date)

        holder.dayName.text = formatDayName(daySchedule.day)
        holder.dateText.text = formatDate(daySchedule.date)
        
        // Apply font size
        val fontSizeMultiplier = getFontSizeMultiplier()
        val baseDayNameSize = if (isToday(daySchedule.date)) 26f else 24f
        holder.dayName.textSize = baseDayNameSize * fontSizeMultiplier
        holder.dateText.textSize = 14f * fontSizeMultiplier
        
        // Клик на название дня - открыть календарь (с защитой от множественных кликов)
        holder.dayName.setOnClickListener {
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastClickTime > clickDebounceTime) {
                lastClickTime = currentTime
                onDayClickListener?.invoke(daySchedule)
            }
        }

        // Клик на дату - открыть календарь (с защитой от множественных кликов)
        holder.dateText.setOnClickListener {
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastClickTime > clickDebounceTime) {
                lastClickTime = currentTime
                onDayClickListener?.invoke(daySchedule)
            }
        }

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

            // Визуальное отличие для фактических занятий - немного прозрачнее
            if (isActual) {
                holder.cardBackground.alpha = 0.9f
            } else {
                holder.cardBackground.alpha = 1.0f
            }
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
                // Обновляем кружки и подсветку при инициализации
                holder.itemView.post {
                    if (holder.itemView.isAttachedToWindow && isFragmentVisible) {
                        val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                        updateAllCircles(holder, currentMinutes)
                    }
                }

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
            
            // Setup lesson highlight for current day
            if (isToday) {
                val lessonNumbers = daySchedule.items.map { it.lessonNumber }.distinct().sorted()
                holder.currentLessonNumbers = lessonNumbers
                
                if (prefs?.showProgressLine == true) {
                    // Setup lesson highlighting
                    setupLessonHighlight(holder, lessonNumbers)
                } else {
                    // Remove all highlights
                    removeAllHighlights(holder)
                    holder.currentLessonNumbers = null
                }
            } else {
                // Remove all highlights for past/future days
                removeAllHighlights(holder)
                holder.currentLessonNumbers = null
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

        // Показываем крестик только для выбранного дня (если это первый элемент И это выбранный день)
        // Показываем крестик даже если день пустой (без данных)
        val isSelectedDay = selectedDayDate != null && daySchedule.date == selectedDayDate && adapterPosition == 0
        holder.btnRemoveSelectedDay.visibility = if (isSelectedDay) View.VISIBLE else View.GONE

        // Обработчик клика на крестик
        holder.btnRemoveSelectedDay.setOnClickListener {
            holder.btnRemoveSelectedDay.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
            onSelectedDayRemoveListener?.invoke()
        }

        holder.cardBackground.setOnLongClickListener {
            // Всегда показываем одинаковое меню (с pull-to-reveal функционалом)
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
            // Use adapterPosition to get current position when delayed execution happens
            val itemPosition = adapterPosition.coerceAtLeast(0)
            val delay = (itemPosition * 50L).coerceAtMost(300L) // Максимум 300ms задержка
            holder.itemView.postDelayed({
                if (holder.itemView.isAttachedToWindow && holder.itemView.alpha < 1f) {
                    // Фишка из Telegram: улучшенная анимация появления с задержкой
                    val currentPosition = holder.adapterPosition
                    if (currentPosition != RecyclerView.NO_POSITION) {
                        val animationDelay = (currentPosition * 30L).coerceAtMost(300L)
                        holder.itemView.postDelayed({
                            animateItemAppearance(holder.itemView)
                        }, animationDelay)
                    }
                }
            }, delay)
        }
    }
    
    private fun isToday(dateStr: String): Boolean {
        val today = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date())
        return dateStr == today
    }
    
    /**
     * Настройка подсветки текущего урока
     */
    private fun setupLessonHighlight(holder: ScheduleViewHolder, lessonNumbers: List<Int>) {
        // Обновляем подсветку сразу
        updateLessonHighlight(holder)
        
        // Обновляем при обновлении кружков (каждые 2 минуты)
        // Подсветка будет обновляться вместе с кружками в updateAllCircles
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

            // Обновляем подсветку текущего урока
            if (prefs?.showProgressLine == true) {
                updateLessonHighlight(holder)
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении всех кружков: ${e.message}", e)
        }
    }

    /**
     * Подсвечивает текущий активный урок, перемену или обед
     */
    private fun updateLessonHighlight(holder: ScheduleViewHolder) {
        if (!holder.itemView.isAttachedToWindow || !isFragmentVisible) {
            return
        }

        // Проверяем что настройка включена
        if (prefs?.showProgressLine != true) {
            removeAllHighlights(holder, animate = false)
            return
        }

        val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val context = holder.itemView.context ?: return

        try {
            // Находим текущий подсвеченный элемент (если есть)
            var currentlyHighlighted: View? = null
            for (i in 0 until holder.itemsContainer.childCount) {
                val child = holder.itemsContainer.getChildAt(i) ?: continue
                if (child.tag == "highlighted") {
                    currentlyHighlighted = child
                    break
                }
            }

            var targetHighlightView: View? = null
            val lessonNumbers = holder.currentLessonNumbers ?: emptyList()

            // СНАЧАЛА проверяем все уроки - они имеют приоритет
            for (i in 0 until holder.itemsContainer.childCount) {
                val child = holder.itemsContainer.getChildAt(i) ?: continue
                val lessonNumberView = child.findViewById<TextView>(R.id.lessonNumber) ?: continue

                val lessonNum = lessonNumberView.text.toString().toIntOrNull() ?: continue
                val lessonTime = LessonTimes.getTime(lessonNum, college) ?: continue
                val lessonStartMinutes = DayProgressCalculator.parseTime(lessonTime.startTime)
                val lessonEndMinutes = DayProgressCalculator.parseTime(lessonTime.endTime)

                // Если сейчас идет этот урок - подсвечиваем
                // Включаем момент начала (>=) и исключаем момент окончания (<)
                // Чтобы в момент начала пары (16:05) подсветка сразу переключалась на пару
                if (currentMinutes >= lessonStartMinutes && currentMinutes < lessonEndMinutes) {
                    targetHighlightView = child
                    break
                }
            }

            // Если активный урок не найден, проверяем перемены и обеды
            if (targetHighlightView == null) {
                var previousLessonNumber: Int? = null

                for (i in 0 until holder.itemsContainer.childCount) {
                    val child = holder.itemsContainer.getChildAt(i) ?: continue
                    val lessonNumberView = child.findViewById<TextView>(R.id.lessonNumber)
                    val breakTextView = child.findViewById<TextView>(R.id.breakText)

                    if (lessonNumberView != null) {
                        previousLessonNumber = lessonNumberView.text.toString().toIntOrNull()
                    } else if (breakTextView != null && previousLessonNumber != null) {
                        val breakText = breakTextView.text.toString()
                        val isLunch = breakText.contains("Обед", ignoreCase = true)
                        val isBreak = breakText.contains("Перемена", ignoreCase = true)

                        if (isLunch) {
                            // Проверяем обед
                            if (checkLunchTime(previousLessonNumber, currentMinutes)) {
                                targetHighlightView = child
                                break
                            }
                        } else if (isBreak) {
                            // Для перемены нужно найти следующую пару
                            var nextLessonNumber: Int? = null
                            for (j in i + 1 until holder.itemsContainer.childCount) {
                                val nextChild = holder.itemsContainer.getChildAt(j) ?: continue
                                val nextLessonView = nextChild.findViewById<TextView>(R.id.lessonNumber)
                                if (nextLessonView != null) {
                                    nextLessonNumber = nextLessonView.text.toString().toIntOrNull()
                                    break
                                }
                            }

                            if (nextLessonNumber != null) {
                                // Сначала пытаемся использовать время из текста перемены
                                val breakTimeText = LessonTimes.getBreakText(previousLessonNumber, nextLessonNumber, college)

                                if (breakTimeText != null) {
                                    // Парсим время перемены из текста "Перемена: HH:mm - HH:mm"
                                    val regex = Regex("\\d{1,2}:\\d{2}")
                                    val times = regex.findAll(breakTimeText).map { it.value }.toList()
                                    if (times.size == 2) {
                                        val breakStartMinutes = DayProgressCalculator.parseTime(times[0])
                                        val breakEndMinutes = DayProgressCalculator.parseTime(times[1])

                                        // Если сейчас идет перемена - подсвечиваем
                                        if (currentMinutes >= breakStartMinutes && currentMinutes < breakEndMinutes) {
                                            targetHighlightView = child
                                            break
                                        }
                                    }
                                } else {
                                    // Fallback: используем проверку по времени пар
                                    if (checkBreakTime(previousLessonNumber, nextLessonNumber, currentMinutes)) {
                                        targetHighlightView = child
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Если нужно подсветить тот же элемент - ничего не делаем
            if (targetHighlightView == currentlyHighlighted) {
                return
            }

            // Убираем подсветку со старого элемента (с анимацией только если элемент другой)
            if (currentlyHighlighted != null && currentlyHighlighted != targetHighlightView) {
                removeHighlight(currentlyHighlighted, animate = true)
            }

            // Применяем подсветку к новому элементу (с анимацией только если это новый элемент)
            if (targetHighlightView != null && targetHighlightView != currentlyHighlighted) {
                applyHighlight(targetHighlightView, context, animate = true)
            } else if (targetHighlightView == null && currentlyHighlighted != null) {
                // Если ничего не найдено, убираем подсветку без анимации
                removeHighlight(currentlyHighlighted, animate = false)
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при обновлении подсветки урока: ${e.message}", e)
        }
    }

    /**
     * Применяет подсветку к элементу урока/перемены/обеда с анимацией
     */
    private fun applyHighlight(lessonView: View, context: Context, animate: Boolean = true) {
        try {
            // Отменяем текущие анимации если есть
            lessonView.animate().cancel()

            val highlightRes = when {
                isLightTheme -> R.drawable.lesson_current_highlight_light
                isDarkTheme -> R.drawable.lesson_current_highlight_dark
                isBlueTheme -> R.drawable.lesson_current_highlight_blue
                isGrayTheme -> R.drawable.lesson_current_highlight_gray
                isPurpleTheme -> R.drawable.lesson_current_highlight_purple
                isGreenTheme -> R.drawable.lesson_current_highlight_green
                isHalloweenTheme -> R.drawable.lesson_current_highlight_halloween
                isNothingTheme -> R.drawable.lesson_current_highlight_nothing
                isNewYearTheme -> R.drawable.lesson_current_highlight_newyear
                else -> R.drawable.lesson_current_highlight
            }
            // Сохраняем текущие отступы перед применением фона
            val paddingLeft = lessonView.paddingLeft
            val paddingTop = lessonView.paddingTop
            val paddingRight = lessonView.paddingRight
            val paddingBottom = lessonView.paddingBottom

            // Помечаем элемент как подсвеченный
            lessonView.tag = "highlighted"

            // Устанавливаем фон сразу
            lessonView.background = context.getDrawable(highlightRes)

            // Восстанавливаем отступы (могут быть сброшены при установке background)
            if (lessonView.paddingLeft != paddingLeft ||
                lessonView.paddingTop != paddingTop ||
                lessonView.paddingRight != paddingRight ||
                lessonView.paddingBottom != paddingBottom) {
                lessonView.setPadding(paddingLeft, paddingTop, paddingRight, paddingBottom)
            }

            if (animate && lessonView.isAttachedToWindow) {
                // Жидкая анимация появления: плавное проскальзывание с расширением
                val width = lessonView.width.toFloat()
                val height = lessonView.height.toFloat()
                lessonView.pivotX = width / 2f
                lessonView.pivotY = height / 2f

                // Начальное состояние: выше, уменьшен, полупрозрачен
                lessonView.translationY = -25f
                lessonView.scaleX = 0.92f
                lessonView.scaleY = 0.92f
                lessonView.alpha = 0.5f

                // Жидкая анимация: плавное расширение с проскальзыванием
                // Используем кастомный PathInterpolator для "жидкого" эффекта (ease-in-out-cubic)
                val liquidInterpolator = PathInterpolator(0.25f, 0.1f, 0.25f, 1f)

                lessonView.animate()
                    .translationY(0f)
                    .scaleX(1.03f)  // Слегка расширяемся
                    .scaleY(1.03f)
                    .alpha(1f)
                    .setDuration(400)  // Более плавная и длинная анимация
                    .setInterpolator(liquidInterpolator)
                    .withEndAction {
                        // Плавное возвращение к нормальному размеру с легким отскоком
                        if (lessonView.isAttachedToWindow) {
                            lessonView.animate()
                                .scaleX(1f)
                                .scaleY(1f)
                                .setDuration(250)
                                .setInterpolator(PathInterpolator(0.34f, 1.56f, 0.64f, 1f)) // Overshoot-like
                                .start()
                        }
                    }
                    .start()
            } else {
                // Без анимации - просто устанавливаем нормальное состояние
                lessonView.translationY = 0f
                lessonView.scaleX = 1f
                lessonView.scaleY = 1f
                lessonView.alpha = 1f
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при применении подсветки: ${e.message}", e)
        }
    }

    /**
     * Убирает подсветку со всех элементов (уроки, перемены, обеды) с анимацией
     */
    private fun removeAllHighlights(holder: ScheduleViewHolder, animate: Boolean = false) {
        try {
            for (i in 0 until holder.itemsContainer.childCount) {
                val child = holder.itemsContainer.getChildAt(i) ?: continue
                if (child.tag == "highlighted") {
                    removeHighlight(child, animate)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при удалении подсветки: ${e.message}", e)
        }
    }

    /**
     * Убирает подсветку с одного элемента
     */
    private fun removeHighlight(view: View, animate: Boolean = false) {
        try {
            if (animate && view.isAttachedToWindow) {
                // Отменяем текущие анимации
                view.animate().cancel()
                val width = view.width.toFloat()
                val height = view.height.toFloat()
                view.pivotX = width / 2f
                view.pivotY = height / 2f

                // Жидкая анимация исчезновения: плавное сжатие с уходом вниз
                // Используем плавный interpolator для "жидкого" эффекта
                val liquidOutInterpolator = PathInterpolator(0.55f, 0.085f, 0.68f, 0.53f)

                view.animate()
                    .scaleX(0.94f)  // Плавно сжимаемся
                    .scaleY(0.94f)
                    .translationY(20f)  // Плавно уходим вниз
                    .alpha(0.4f)  // Плавно исчезаем
                    .setDuration(300)  // Плавная анимация
                    .setInterpolator(liquidOutInterpolator)
                    .withEndAction {
                        // Сбрасываем состояние после анимации
                        view.background = null
                        view.tag = null
                        view.translationY = 0f
                        view.scaleX = 1f
                        view.scaleY = 1f
                        view.alpha = 1f
                    }
                    .start()
            } else {
                // Отменяем анимации и сразу убираем подсветку
                view.animate().cancel()
                view.background = null
                view.tag = null
                view.translationY = 0f
                view.scaleX = 1f
                view.scaleY = 1f
                view.alpha = 1f
            }
        } catch (e: Exception) {
            android.util.Log.e("ScheduleAdapter", "Ошибка при удалении подсветки: ${e.message}", e)
            // Fallback: просто убираем подсветку
            view.background = null
            view.tag = null
            view.translationY = 0f
            view.scaleX = 1f
            view.scaleY = 1f
            view.alpha = 1f
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

                // Обновляем кружки и подсветку урока
                updateAllCircles(holder, currentMinutes)

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
        // Перемена активна только СТРОГО между окончанием одной пары и началом следующей
        // Используем < для afterStart чтобы в момент начала пары (16:05) перемена была неактивна
        return currentMinutes > beforeEnd && currentMinutes < afterStart
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

    fun updateSchedules(newSchedules: List<DaySchedule>, newPlannedDates: Set<String>? = null, newSelectedDayDate: String? = null) {
        val previousSchedules = schedules.toList() // Создаем копию для DiffUtil

        // Обновляем plannedDates если передано
        if (newPlannedDates != null) {
            plannedDates = newPlannedDates
        }

        // Обновляем выбранную дату
        selectedDayDate = newSelectedDayDate

        // Используем DiffUtil для анимаций
        val diffCallback = ScheduleDiffCallback(previousSchedules, newSchedules)
        val diffResult = DiffUtil.calculateDiff(diffCallback, false) // false = не проверять перемещения для производительности

        schedules = newSchedules
        
        // Применяем изменения с анимациями
        diffResult.dispatchUpdatesTo(this)
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
                
                // Обновляем подсветку урока если включена
                if (prefs?.showProgressLine == true && holder.currentLessonNumbers != null) {
                    updateLessonHighlight(holder)
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
        // Убираем точки и нормализуем
        val normalized = day.trim().removeSuffix(".").trim()
        return when (normalized) {
            "Пн" -> "Понедельник"
            "Вт" -> "Вторник"
            "Ср" -> "Среда"
            "Чт", "чт" -> "Четверг"
            "Пт" -> "Пятница"
            "Сб" -> "Суббота"
            "Вс" -> "Воскресенье"
            else -> {
                // Если уже полное название - возвращаем как есть
                if (normalized.length > 4) {
                    normalized
                } else {
                    // Пытаемся найти в разных вариантах
                    when (normalized.lowercase()) {
                        "пн", "понедельник" -> "Понедельник"
                        "вт", "вторник" -> "Вторник"
                        "ср", "среда" -> "Среда"
                        "чт", "четверг" -> "Четверг"
                        "пт", "пятница" -> "Пятница"
                        "сб", "суббота" -> "Суббота"
                        "вс", "воскресенье" -> "Воскресенье"
                        else -> normalized
                    }
                }
            }
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
    
    /**
     * Показывает меню для выбранного дня с опцией удаления
     */
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
        
        // Находим скрытый контент
        val hiddenContent = sheetView.findViewById<View>(R.id.hiddenContent)
        val hiddenAvatarDDoS = sheetView.findViewById<ImageView>(R.id.hiddenAvatarDDoS)
        val hiddenAvatarRelsev = sheetView.findViewById<ImageView>(R.id.hiddenAvatarRelsev)
        var isHiddenRevealed = false

        // Скрытый функционал - клик на аватар DDoSa
        hiddenAvatarDDoS?.setOnClickListener { view: View ->
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
            Toast.makeText(context, "DDoSa - предложил сохранять пары... 🔥", Toast.LENGTH_SHORT).show()
        }

        // Клик на аватар автора
        hiddenAvatarRelsev?.setOnClickListener { view: View ->
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
            Toast.makeText(context, "Relsev - Автор приложения 🎨", Toast.LENGTH_SHORT).show()
        }

        // Настройка поведения BottomSheet
        dialog.behavior.isDraggable = true
        dialog.behavior.skipCollapsed = false // Важно! Не пропускать состояние collapsed

        // Также отслеживаем через BottomSheetBehavior для pull-to-reveal и сброса состояния
        dialog.behavior.addBottomSheetCallback(object : com.google.android.material.bottomsheet.BottomSheetBehavior.BottomSheetCallback() {
            override fun onStateChanged(bottomSheet: android.view.View, newState: Int) {
                // Сбрасываем состояние при закрытии или сворачивании
                if (newState == com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_HIDDEN ||
                    newState == com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_COLLAPSED) {
                    if (isHiddenRevealed && hiddenContent != null) {
                        isHiddenRevealed = false
                        hiddenContent.alpha = 0f
                        hiddenContent.translationY = 20f
                    }
                }
            }

            override fun onSlide(bottomSheet: android.view.View, slideOffset: Float) {
                // slideOffset: от 0 (collapsed) до 1 (expanded)
                // Когда sheet почти полностью раскрыт (slideOffset > 0.85), показываем скрытый контент
                if (slideOffset > 0.85f && !isHiddenRevealed && hiddenContent != null) {
                    // Пользователь потянул sheet вверх - показываем скрытый контент
                    isHiddenRevealed = true
                    hiddenContent.animate()
                        .alpha(1f)
                        .translationY(0f)
                        .setDuration(400)
                        .setInterpolator(PathInterpolator(0.25f, 0.1f, 0.25f, 1f))
                        .start()
                } else if (slideOffset < 0.8f && isHiddenRevealed && hiddenContent != null) {
                    // Пользователь отпустил - скрываем обратно
                    isHiddenRevealed = false
                    hiddenContent.animate()
                        .alpha(0f)
                        .translationY(20f)
                        .setDuration(300)
                        .setInterpolator(PathInterpolator(0.55f, 0.085f, 0.68f, 0.53f))
                        .start()
                }
            }
        })

        // Устанавливаем начальное состояние - collapsed (частично открыт)
        // Устанавливаем примерную высоту peekHeight в пикселях (примерно до кнопки "Копировать")
        // Это примерно: заголовок + подзаголовок + 3 кнопки + отступы = ~360dp (увеличено для большей видимости)
        val density = context.resources.displayMetrics.density
        dialog.behavior.peekHeight = (360 * density).toInt() // примерно 360dp для начальной высоты
        dialog.behavior.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_COLLAPSED
        
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
        
        // Применение закругления и уточнение peekHeight после показа диалога
        dialog.setOnShowListener {
            // Уточняем peekHeight на основе реальных измерений после layout
            sheetView.post {
                val hiddenContent = sheetView.findViewById<View>(R.id.hiddenContent)
                val contentLayout = sheetView as? android.view.ViewGroup

                contentLayout?.let { layout ->
                    layout.viewTreeObserver.addOnGlobalLayoutListener(object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
                        override fun onGlobalLayout() {
                            layout.viewTreeObserver.removeOnGlobalLayoutListener(this)

                            hiddenContent?.let { hidden ->
                                // Измеряем точную позицию скрытого контента
                                val hiddenTop = hidden.top

                                // peekHeight = позиция скрытого контента + padding
                                val measuredPeekHeight = hiddenTop + layout.paddingBottom
                                if (measuredPeekHeight > 0) {
                                    dialog.behavior.peekHeight = measuredPeekHeight.coerceAtLeast(280)
                                    // Принудительно устанавливаем collapsed состояние после измерения
                                    dialog.behavior.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_COLLAPSED
                                }
                            }
                        }
                    })
                }
            }

            // Применяем закругление
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
                    PreferencesManager.THEME_BLUE -> ContextCompat.getColor(context, R.color.blue_colorBackground)
                    PreferencesManager.THEME_GRAY -> ContextCompat.getColor(context, R.color.gray_colorBackground)
                    PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_windowBackground)
                    PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_colorBackground)
                    PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_colorBackground)
                    PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_colorBackground)
                    PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_colorBackground)
                    else -> ContextCompat.getColor(context, R.color.dark_colorBackground)
                }
                
                // Сначала очищаем старый фон для устранения черных уголков
                view.background = null
                
                val backgroundDrawable = com.google.android.material.shape.MaterialShapeDrawable(shapeAppearanceModel).apply {
                    fillColor = android.content.res.ColorStateList.valueOf(backgroundColor)
                }
                
                // Устанавливаем фон
                view.background = backgroundDrawable
                
                // Убеждаемся что фон правильно применен (особенно для синей и серой тем)
                view.post {
                    // Принудительно устанавливаем фон еще раз для устранения черных уголков
                    if (view.background != backgroundDrawable) {
                        view.background = null
                        view.setBackgroundColor(backgroundColor)
                        view.background = backgroundDrawable
                    }
                    // Инвалидируем view для перерисовки
                    view.invalidate()
                }
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
