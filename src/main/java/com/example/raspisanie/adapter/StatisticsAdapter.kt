package com.example.raspisanie.adapter

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.raspisanie.R
import com.example.raspisanie.data.DisciplineStatistics
import com.example.raspisanie.data.PreferencesManager

class StatisticsAdapter(
    private val disciplines: List<DisciplineStatistics>,
    private val context: Context? = null
) : RecyclerView.Adapter<StatisticsAdapter.StatisticsViewHolder>() {
    
    private val prefs: PreferencesManager? = context?.let { PreferencesManager(it) }
    
    // Кэшируем шрифт Ndot для темы Nothing
    private val ndotFont: android.graphics.Typeface? by lazy {
        try {
            context?.resources?.getFont(R.font.ndot)
        } catch (e: Exception) {
            null
        }
    }
    
    // Отслеживание анимированных позиций на уровне адаптера (не сбрасывается при переиспользовании ViewHolder)
    private val animatedPositions = mutableSetOf<Int>()
    private val animatedProgressPositions = mutableSetOf<Int>()
    
    // Получать настройки динамически при каждом обращении для актуальности
    private val isNothingTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_NOTHING
    private val isHalloweenTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_HALLOWEEN
    private val isLightTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_LIGHT
    private val isDarkTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_DARK
    private val isPurpleTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_PURPLE
    private val isGreenTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_GREEN
    private val isNewYearTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_NEW_YEAR
    
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

    class StatisticsViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val numberBg: View = itemView.findViewById(R.id.statNumberBg)
        val numberText: TextView = itemView.findViewById(R.id.statNumberText)
        val disciplineText: TextView = itemView.findViewById(R.id.statDisciplineText)
        val teacherText: TextView = itemView.findViewById(R.id.statTeacherText)
        val lessonTypeText: TextView = itemView.findViewById(R.id.statLessonTypeText)
        val totalHoursText: TextView = itemView.findViewById(R.id.statTotalHoursText)
        val plannedHoursText: TextView = itemView.findViewById(R.id.statPlannedHoursText)
        val factHoursText: TextView = itemView.findViewById(R.id.statFactHoursText)
        val remainingHoursText: TextView = itemView.findViewById(R.id.statRemainingHoursText)
        val plannedIn2WeeksText: TextView = itemView.findViewById(R.id.statPlannedIn2WeeksText)
        val factIn2WeeksText: TextView = itemView.findViewById(R.id.statFactIn2WeeksText)
        val completionDateText: TextView = itemView.findViewById(R.id.statCompletionDateText)
        val completionPercentText: TextView = itemView.findViewById(R.id.statCompletionPercentText)
        val progressFill: View = itemView.findViewById(R.id.progressFill)
        val additionalInfo: View = itemView.findViewById(R.id.statAdditionalInfo)
        val cardBackground: View = itemView.findViewById(R.id.cardBackground)
        
        // Флаги для отслеживания состояния
        var isExpanded: Boolean = false
        var currentAnimator: Animator? = null
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): StatisticsViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_statistics_discipline, parent, false)
        return StatisticsViewHolder(view)
    }
    
    override fun onViewRecycled(holder: StatisticsViewHolder) {
        super.onViewRecycled(holder)
        // Отменяем все анимации при переиспользовании ViewHolder
        try {
            holder.currentAnimator?.cancel()
            holder.currentAnimator = null
            holder.itemView.clearAnimation()
            holder.itemView.animate().cancel()
            holder.progressFill.clearAnimation()
            holder.progressFill.animate().cancel()
            holder.additionalInfo.clearAnimation()
            holder.additionalInfo.animate().cancel()
            // Сбрасываем состояние
            holder.itemView.alpha = 1f
            holder.itemView.translationY = 0f
            holder.itemView.scaleX = 1f
            holder.itemView.scaleY = 1f
            holder.progressFill.alpha = 0.4f
        } catch (e: Exception) {
            // Игнорируем ошибки при очистке
        }
        // НЕ сбрасываем флаги анимаций - они отслеживаются на уровне адаптера через animatedPositions
        // Сбрасываем только локальные флаги ViewHolder
        holder.isExpanded = false
    }

    override fun onBindViewHolder(holder: StatisticsViewHolder, position: Int) {
        val discipline = disciplines[position]
        
        // Отменяем предыдущую анимацию, если есть
        holder.currentAnimator?.cancel()
        holder.currentAnimator = null
        
        // Применяем тему к карточке
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
            
            val numberBgResId = when (prefs?.theme) {
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
            holder.numberBg.setBackgroundResource(numberBgResId)
            
            // Применяем цвет к номеру дисциплины в зависимости от темы
            val numberTextColor = when (prefs?.theme) {
                PreferencesManager.THEME_LIGHT -> context.getColor(R.color.light_textColorPrimary)
                PreferencesManager.THEME_DARK -> context.getColor(R.color.dark_textColorPrimary)
                PreferencesManager.THEME_BLUE -> context.getColor(R.color.blue_textColorPrimary)
                PreferencesManager.THEME_GRAY -> context.getColor(R.color.gray_textColorPrimary)
                PreferencesManager.THEME_PURPLE -> context.getColor(R.color.system_textColorPrimary)
                PreferencesManager.THEME_HALLOWEEN -> context.getColor(R.color.custom_textColorPrimary)
                PreferencesManager.THEME_NOTHING -> context.getColor(R.color.nothing_textColorPrimary)
                PreferencesManager.THEME_GREEN -> context.getColor(R.color.green_textColorPrimary)
                PreferencesManager.THEME_NEW_YEAR -> context.getColor(R.color.newyear_textColorPrimary)
                else -> context.getColor(R.color.dark_textColorPrimary)
            }
            holder.numberText.setTextColor(numberTextColor)
            
            // Применяем цвет к часам (Всего, План, Факт, Остаток) в зависимости от темы
            val hoursTextColor = when (prefs?.theme) {
                PreferencesManager.THEME_LIGHT -> context.getColor(R.color.light_textColorPrimary)
                PreferencesManager.THEME_DARK -> context.getColor(R.color.dark_textColorPrimary)
                PreferencesManager.THEME_BLUE -> context.getColor(R.color.blue_textColorPrimary)
                PreferencesManager.THEME_GRAY -> context.getColor(R.color.gray_textColorPrimary)
                PreferencesManager.THEME_PURPLE -> context.getColor(R.color.system_textColorPrimary)
                PreferencesManager.THEME_HALLOWEEN -> context.getColor(R.color.custom_textColorPrimary)
                PreferencesManager.THEME_NOTHING -> context.getColor(R.color.nothing_textColorPrimary)
                PreferencesManager.THEME_GREEN -> context.getColor(R.color.green_textColorPrimary)
                PreferencesManager.THEME_NEW_YEAR -> context.getColor(R.color.newyear_textColorPrimary)
                else -> context.getColor(R.color.dark_textColorPrimary)
            }
            holder.totalHoursText.setTextColor(hoursTextColor)
            holder.plannedHoursText.setTextColor(hoursTextColor)
            holder.factHoursText.setTextColor(hoursTextColor)
            holder.remainingHoursText.setTextColor(hoursTextColor)
        }
        
        // Применяем размер шрифта ко всем TextView
        val fontSizeMultiplier = getFontSizeMultiplier()
        holder.numberText.textSize = 18f * fontSizeMultiplier
        holder.disciplineText.textSize = 16f * fontSizeMultiplier
        holder.teacherText.textSize = 13f * fontSizeMultiplier
        holder.lessonTypeText.textSize = 12f * fontSizeMultiplier
        holder.totalHoursText.textSize = 12f * fontSizeMultiplier
        holder.plannedHoursText.textSize = 12f * fontSizeMultiplier
        holder.factHoursText.textSize = 12f * fontSizeMultiplier
        holder.remainingHoursText.textSize = 12f * fontSizeMultiplier
        holder.plannedIn2WeeksText.textSize = 11f * fontSizeMultiplier
        holder.factIn2WeeksText.textSize = 11f * fontSizeMultiplier
        holder.completionDateText.textSize = 11f * fontSizeMultiplier
        holder.completionPercentText.textSize = 20f * fontSizeMultiplier
        
        // Применяем шрифт Ndot для темы Nothing
        if (isNothingTheme && ndotFont != null) {
            holder.numberText.typeface = ndotFont
            holder.disciplineText.typeface = ndotFont
            holder.teacherText.typeface = ndotFont
            holder.lessonTypeText.typeface = ndotFont
            holder.totalHoursText.typeface = ndotFont
            holder.plannedHoursText.typeface = ndotFont
            holder.factHoursText.typeface = ndotFont
            holder.remainingHoursText.typeface = ndotFont
            holder.plannedIn2WeeksText.typeface = ndotFont
            holder.factIn2WeeksText.typeface = ndotFont
            holder.completionDateText.typeface = ndotFont
            holder.completionPercentText.typeface = ndotFont
        }
        
        holder.numberText.text = discipline.number.ifEmpty { (position + 1).toString() }
        holder.disciplineText.text = discipline.discipline.ifEmpty { "—" }
        holder.teacherText.text = discipline.teacher.ifEmpty { "—" }
        holder.lessonTypeText.text = discipline.lessonType.ifEmpty { "—" }
        holder.totalHoursText.text = discipline.totalHours?.toString() ?: "—"
        holder.plannedHoursText.text = discipline.plannedHours?.toString() ?: "—"
        holder.factHoursText.text = discipline.factHours?.toString() ?: "—"
        holder.remainingHoursText.text = discipline.remainingHours?.toString() ?: "—"
        holder.plannedIn2WeeksText.text = discipline.plannedIn2Weeks ?: "—"
        holder.factIn2WeeksText.text = discipline.factIn2Weeks ?: "—"
        holder.completionDateText.text = discipline.completionDate ?: "—"
        
        // Вычисляем процент выполнения
        val percent = if (discipline.completionPercent != null && discipline.completionPercent.isNotEmpty()) {
            val percentMatch = Regex("(\\d+)").find(discipline.completionPercent)
            percentMatch?.groupValues?.get(1)?.toIntOrNull() ?: discipline.getCompletionPercentInt()
        } else {
            discipline.getCompletionPercentInt()
        }
        
        // Устанавливаем текст процента
        holder.completionPercentText.text = if (discipline.completionPercent != null && discipline.completionPercent.isNotEmpty()) {
            if (discipline.completionPercent.contains("%")) {
                discipline.completionPercent
            } else {
                "${discipline.completionPercent}%"
            }
        } else {
            "$percent%"
        }
        
        // Применяем тему к прогресс-заполнению
        if (context != null) {
            val progressResId = when (prefs?.theme) {
                PreferencesManager.THEME_LIGHT -> R.drawable.statistics_progress_fill_light
                PreferencesManager.THEME_DARK -> R.drawable.statistics_progress_fill_dark
                PreferencesManager.THEME_BLUE -> R.drawable.statistics_progress_fill_blue
                PreferencesManager.THEME_GRAY -> R.drawable.statistics_progress_fill_gray
                PreferencesManager.THEME_PURPLE -> R.drawable.statistics_progress_fill_purple
                PreferencesManager.THEME_HALLOWEEN -> R.drawable.statistics_progress_fill_halloween
                PreferencesManager.THEME_NOTHING -> R.drawable.statistics_progress_fill_nothing
                PreferencesManager.THEME_GREEN -> R.drawable.statistics_progress_fill_green
                PreferencesManager.THEME_NEW_YEAR -> R.drawable.statistics_progress_fill_newyear
                else -> R.drawable.statistics_progress_fill_dark
            }
            holder.progressFill.setBackgroundResource(progressResId)
        }
        
        // Проверяем, была ли позиция уже анимирована
        val shouldAnimateAppearance = !animatedPositions.contains(position)
        val shouldAnimateProgress = !animatedProgressPositions.contains(position)
        
        // Устанавливаем финальное состояние, если позиция уже была анимирована
        if (!shouldAnimateAppearance) {
            holder.itemView.alpha = 1f
            holder.itemView.translationY = 0f
            holder.itemView.scaleX = 1f
            holder.itemView.scaleY = 1f
        } else {
            // Сбрасываем состояние карточки для анимации
            holder.itemView.alpha = 0f
            holder.itemView.translationY = 40f
            holder.itemView.scaleX = 0.9f
            holder.itemView.scaleY = 0.9f
        }
        
        // Устанавливаем прогресс
        if (!shouldAnimateProgress) {
            // Если прогресс уже был анимирован, устанавливаем финальное значение сразу
            holder.itemView.post {
                if (holder.itemView.isAttachedToWindow && holder.itemView.width > 0) {
                    val cardWidth = holder.itemView.width
                    val targetWidth = (cardWidth * percent / 100).coerceAtLeast(0).coerceAtMost(cardWidth)
                    val params = holder.progressFill.layoutParams
                    params.width = targetWidth
                    holder.progressFill.layoutParams = params
                    holder.progressFill.alpha = 0.4f
                }
            }
        } else {
            holder.progressFill.alpha = 0f
            holder.progressFill.layoutParams.width = 0
        }
        
        // Инициализируем анимации после измерения
        holder.itemView.post {
            if (holder.itemView.isAttachedToWindow && holder.itemView.width > 0) {
                if (shouldAnimateAppearance) {
                    animateCardAppearance(holder, position)
                }
                if (shouldAnimateProgress) {
                    animateProgressFill(holder, percent, position)
                }
            }
        }
        
        // Показываем дополнительную информацию, если есть данные
        val hasAdditionalInfo = (discipline.plannedIn2Weeks != null && discipline.plannedIn2Weeks.isNotEmpty()) || 
                                (discipline.factIn2Weeks != null && discipline.factIn2Weeks.isNotEmpty()) || 
                                (discipline.completionDate != null && discipline.completionDate.isNotEmpty())
        
        // Дополнительная информация скрыта по умолчанию
        holder.additionalInfo.visibility = View.GONE
        holder.additionalInfo.alpha = 0f
        holder.isExpanded = false
        
        // Добавляем возможность разворачивать/сворачивать дополнительную информацию по клику
        if (hasAdditionalInfo) {
            holder.itemView.setOnClickListener {
                // Haptic feedback для лучшего UX (как в Telegram)
                holder.itemView.performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
                toggleAdditionalInfo(holder)
            }
        } else {
            holder.itemView.setOnClickListener(null)
        }
    }
    
    /**
     * Плавная анимация появления карточки с эффектом масштабирования и смещения
     */
    private fun animateCardAppearance(holder: StatisticsViewHolder, position: Int) {
        if (animatedPositions.contains(position) || !holder.itemView.isAttachedToWindow) return
        
        // Отмечаем позицию как анимированную сразу, чтобы избежать повторных запусков
        animatedPositions.add(position)
        
        // Для первых 4 карточек используем задержку для stagger эффекта
        // Для остальных запускаем сразу, чтобы они успели анимироваться при быстрой прокрутке
        val delay = if (position < 4) {
            (position * 50L).coerceAtMost(200L)
        } else {
            0L // Нет задержки для карточек, появляющихся при прокрутке
        }
        
        val startAnimation: Runnable = Runnable {
            if (!holder.itemView.isAttachedToWindow || holder.adapterPosition != position) return@Runnable
            
            val animatorSet = AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(holder.itemView, "alpha", 0f, 1f).apply {
                        duration = 400
                        interpolator = DecelerateInterpolator()
                    },
                    ObjectAnimator.ofFloat(holder.itemView, "translationY", 40f, 0f).apply {
                        duration = 500
                        interpolator = OvershootInterpolator(0.8f)
                    },
                    ObjectAnimator.ofFloat(holder.itemView, "scaleX", 0.9f, 1f).apply {
                        duration = 500
                        interpolator = OvershootInterpolator(0.8f)
                    },
                    ObjectAnimator.ofFloat(holder.itemView, "scaleY", 0.9f, 1f).apply {
                        duration = 500
                        interpolator = OvershootInterpolator(0.8f)
                    }
                )
            }
            
            animatorSet.start()
            holder.currentAnimator = animatorSet
        }
        
        if (delay > 0) {
            holder.itemView.postDelayed(startAnimation, delay)
        } else {
            // Для карточек без задержки запускаем сразу
            holder.itemView.post(startAnimation)
        }
    }
    
    /**
     * Плавная анимация заполнения прогресс-бара с эффектом волны
     */
    private fun animateProgressFill(holder: StatisticsViewHolder, percent: Int, position: Int) {
        if (animatedProgressPositions.contains(position) || !holder.itemView.isAttachedToWindow) return
        
        val cardWidth = holder.itemView.width
        if (cardWidth <= 0) return
        
        val targetWidth = (cardWidth * percent / 100).coerceAtLeast(0).coerceAtMost(cardWidth)
        if (targetWidth <= 0) {
            holder.progressFill.alpha = 0f
            animatedProgressPositions.add(position)
            return
        }
        
        // Отмечаем позицию как анимированную сразу, чтобы избежать повторных запусков
        animatedProgressPositions.add(position)
        
        // Для первых 4 карточек используем задержку для stagger эффекта
        // Для остальных запускаем сразу, чтобы они успели анимироваться при быстрой прокрутке
        val delay = if (position < 4) {
            (position * 50L).coerceAtMost(200L) + 200L
        } else {
            100L // Минимальная задержка для карточек, появляющихся при прокрутке
        }
        
        val startAnimation: Runnable = Runnable {
            if (!holder.itemView.isAttachedToWindow || holder.adapterPosition != position) return@Runnable
            
            // Анимация ширины
            val widthAnimator = ValueAnimator.ofInt(0, targetWidth).apply {
                duration = 800
                interpolator = DecelerateInterpolator()
                addUpdateListener { animation ->
                    if (holder.itemView.isAttachedToWindow) {
                        try {
                            val animatedValue = animation.animatedValue as Int
                            val params = holder.progressFill.layoutParams
                            params.width = animatedValue
                            holder.progressFill.layoutParams = params
                        } catch (e: Exception) {
                            // Игнорируем ошибки
                        }
                    }
                }
            }
            
            // Анимация прозрачности с эффектом волны
            val alphaAnimator = ValueAnimator.ofFloat(0f, 0.6f, 0.4f).apply {
                duration = 800
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { animation ->
                    if (holder.itemView.isAttachedToWindow) {
                        try {
                            holder.progressFill.alpha = animation.animatedValue as Float
                        } catch (e: Exception) {
                            // Игнорируем ошибки
                        }
                    }
                }
            }
            
            val animatorSet = AnimatorSet().apply {
                playTogether(widthAnimator, alphaAnimator)
            }
            
            animatorSet.start()
            holder.currentAnimator = animatorSet
        }
        
        if (delay > 0) {
            holder.itemView.postDelayed(startAnimation, delay)
        } else {
            // Для карточек без задержки запускаем сразу
            holder.itemView.post(startAnimation)
        }
    }
    
    /**
     * Плавная анимация разворачивания/сворачивания дополнительной информации
     */
    private fun toggleAdditionalInfo(holder: StatisticsViewHolder) {
        if (holder.currentAnimator?.isRunning == true) return
        
        val isExpanding = !holder.isExpanded
        
        if (isExpanding) {
            // Разворачиваем
            holder.additionalInfo.visibility = View.VISIBLE
            holder.additionalInfo.alpha = 0f
            holder.additionalInfo.translationY = -20f
            holder.additionalInfo.scaleY = 0.8f
            
            val animatorSet = AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(holder.additionalInfo, "alpha", 0f, 1f).apply {
                        duration = 300
                        interpolator = DecelerateInterpolator()
                    },
                    ObjectAnimator.ofFloat(holder.additionalInfo, "translationY", -20f, 0f).apply {
                        duration = 300
                        interpolator = OvershootInterpolator(0.8f)
                    },
                    ObjectAnimator.ofFloat(holder.additionalInfo, "scaleY", 0.8f, 1f).apply {
                        duration = 300
                        interpolator = OvershootInterpolator(0.8f)
                    }
                )
            }
            
            animatorSet.start()
            holder.currentAnimator = animatorSet
            holder.isExpanded = true
        } else {
            // Сворачиваем
            val animatorSet = AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(holder.additionalInfo, "alpha", 1f, 0f).apply {
                        duration = 250
                        interpolator = DecelerateInterpolator()
                    },
                    ObjectAnimator.ofFloat(holder.additionalInfo, "translationY", 0f, -20f).apply {
                        duration = 250
                        interpolator = DecelerateInterpolator()
                    },
                    ObjectAnimator.ofFloat(holder.additionalInfo, "scaleY", 1f, 0.8f).apply {
                        duration = 250
                        interpolator = DecelerateInterpolator()
                    }
                )
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        holder.additionalInfo.visibility = View.GONE
                    }
                })
            }
            
            animatorSet.start()
            holder.currentAnimator = animatorSet
            holder.isExpanded = false
        }
    }

    override fun getItemCount(): Int = disciplines.size
}
