package com.example.raspisanie.adapter

import android.animation.ValueAnimator
import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
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
    
    // Получать настройки динамически при каждом обращении для актуальности
    private val isNothingTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_NOTHING
    private val isHalloweenTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_HALLOWEEN
    private val isLightTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_LIGHT
    private val isDarkTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_DARK
    private val isPurpleTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_PURPLE
    private val isGreenTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_GREEN
    private val isNewYearTheme: Boolean get() = prefs?.theme == PreferencesManager.THEME_NEW_YEAR

    class StatisticsViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
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
        
        // Флаги для отслеживания состояния анимаций
        var hasAnimatedAppearance: Boolean = false
        var hasAnimatedProgress: Boolean = false
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
            holder.itemView.clearAnimation()
            holder.itemView.animate().cancel()
            holder.progressFill.clearAnimation()
            holder.progressFill.animate().cancel()
            holder.additionalInfo.clearAnimation()
            holder.additionalInfo.animate().cancel()
        } catch (e: Exception) {
            // Игнорируем ошибки при очистке
        }
        // Сбрасываем флаги анимаций при переиспользовании
        holder.hasAnimatedAppearance = false
        holder.hasAnimatedProgress = false
    }

    override fun onBindViewHolder(holder: StatisticsViewHolder, position: Int) {
        val discipline = disciplines[position]
        
        // Применяем тему к карточке
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
            
            // Применяем цвет к номеру дисциплины в зависимости от темы
            val numberTextColor = when (prefs?.theme) {
                PreferencesManager.THEME_LIGHT -> context.getColor(R.color.light_textColorPrimary)
                PreferencesManager.THEME_DARK -> context.getColor(R.color.dark_textColorPrimary)
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
            // Пробуем извлечь число из строки процента (может быть "94%" или "94")
            val percentMatch = Regex("(\\d+)").find(discipline.completionPercent)
            percentMatch?.groupValues?.get(1)?.toIntOrNull() ?: discipline.getCompletionPercentInt()
        } else {
            discipline.getCompletionPercentInt()
        }
        
        // Устанавливаем текст процента
        holder.completionPercentText.text = if (discipline.completionPercent != null && discipline.completionPercent.isNotEmpty()) {
            // Если процент уже содержит %, оставляем как есть, иначе добавляем %
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
                PreferencesManager.THEME_PURPLE -> R.drawable.statistics_progress_fill_purple
                PreferencesManager.THEME_HALLOWEEN -> R.drawable.statistics_progress_fill_halloween
                PreferencesManager.THEME_NOTHING -> R.drawable.statistics_progress_fill_nothing
                PreferencesManager.THEME_GREEN -> R.drawable.statistics_progress_fill_green
                PreferencesManager.THEME_NEW_YEAR -> R.drawable.statistics_progress_fill_newyear
                else -> R.drawable.statistics_progress_fill_dark
            }
            holder.progressFill.setBackgroundResource(progressResId)
        }
        
        // Устанавливаем прогресс сразу (без анимации для стабильности)
        holder.itemView.post {
            if (holder.itemView.isAttachedToWindow) {
                val cardWidth = holder.itemView.width
                if (cardWidth > 0) {
                    val targetWidth = (cardWidth * percent / 100).toInt()
                    val layoutParams = holder.progressFill.layoutParams
                    layoutParams.width = targetWidth
                    holder.progressFill.layoutParams = layoutParams
                    holder.progressFill.alpha = 0.4f
                    
                    // Анимируем заполнение только один раз при первой загрузке (первые 5 карточек)
                    if (!holder.hasAnimatedProgress && position < 5) {
                        holder.hasAnimatedProgress = true
                        holder.itemView.postDelayed({
                            if (holder.itemView.isAttachedToWindow) {
                                holder.progressFill.alpha = 0f
                                val layoutParams2 = holder.progressFill.layoutParams
                                layoutParams2.width = 0
                                holder.progressFill.layoutParams = layoutParams2
                                
                                animateProgressFill(holder, percent)
                            }
                        }, 100 + (position * 30).toLong())
                    }
                }
            }
        }
        
        // Убеждаемся, что карточка всегда видна
        holder.itemView.alpha = 1f
        holder.itemView.translationY = 0f
        holder.itemView.scaleX = 1f
        holder.itemView.scaleY = 1f
        
        // Анимируем появление карточки только один раз при первой загрузке (первые 5 карточек)
        if (!holder.hasAnimatedAppearance && position < 5) {
            holder.hasAnimatedAppearance = true
            holder.itemView.postDelayed({
                if (holder.itemView.isAttachedToWindow) {
                    animateCardAppearance(holder.itemView, position)
                }
            }, 50)
        }
        
        // Показываем дополнительную информацию, если есть данные (скрыта по умолчанию)
        val hasAdditionalInfo = (discipline.plannedIn2Weeks != null && discipline.plannedIn2Weeks.isNotEmpty()) || 
                                (discipline.factIn2Weeks != null && discipline.factIn2Weeks.isNotEmpty()) || 
                                (discipline.completionDate != null && discipline.completionDate.isNotEmpty())
        
        // Дополнительная информация скрыта по умолчанию, разворачивается по клику
        holder.additionalInfo.visibility = View.GONE
        holder.additionalInfo.alpha = 0f
        
        // Добавляем возможность разворачивать/сворачивать дополнительную информацию по клику
        if (hasAdditionalInfo) {
            holder.itemView.setOnClickListener {
                val isVisible = holder.additionalInfo.visibility == View.VISIBLE
                animateAdditionalInfo(holder.additionalInfo, !isVisible)
            }
        } else {
            holder.itemView.setOnClickListener(null)
        }
    }
    
    private fun animateCardAppearance(view: View, position: Int) {
        // Сохраняем текущее состояние (карточка уже видна)
        // Добавляем легкий эффект появления без скрытия карточки
        view.translationY = 15f
        view.scaleX = 0.98f
        view.scaleY = 0.98f
        
        // Анимация с минимальной задержкой для stagger эффекта (максимум 100мс)
        val delay = (position * 20).coerceAtMost(100).toLong()
        view.postDelayed({
            if (view.isAttachedToWindow) {
                try {
                    view.animate()
                        .translationY(0f)
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(300)
                        .setInterpolator(DecelerateInterpolator())
                        .start()
                } catch (e: Exception) {
                    // Если анимация не удалась, просто устанавливаем финальное состояние
                    view.translationY = 0f
                    view.scaleX = 1f
                    view.scaleY = 1f
                }
            } else {
                // Если view не прикреплен, просто устанавливаем финальное состояние
                view.translationY = 0f
                view.scaleX = 1f
                view.scaleY = 1f
            }
        }, delay)
    }
    
    private fun animateProgressFill(holder: StatisticsViewHolder, percent: Int) {
        if (!holder.itemView.isAttachedToWindow) return
        
        val cardWidth = holder.itemView.width
        if (cardWidth <= 0) return
        
        val targetWidth = (cardWidth * percent / 100).toInt()
        if (targetWidth <= 0) return
        
        try {
            // Упрощенная анимация заполнения
            val widthAnimator = ValueAnimator.ofInt(0, targetWidth)
            widthAnimator.duration = 500
            widthAnimator.interpolator = DecelerateInterpolator()
            widthAnimator.addUpdateListener { animation ->
                if (holder.itemView.isAttachedToWindow) {
                    try {
                        val animatedValue = animation.animatedValue as Int
                        val params = holder.progressFill.layoutParams
                        params.width = animatedValue
                        holder.progressFill.layoutParams = params
                        
                        // Одновременно анимируем прозрачность
                        val progress = animation.animatedFraction
                        holder.progressFill.alpha = progress * 0.4f
                    } catch (e: Exception) {
                        // Игнорируем ошибки при анимации
                    }
                }
            }
            widthAnimator.start()
        } catch (e: Exception) {
            // Если анимация не удалась, просто устанавливаем финальное значение
            val params = holder.progressFill.layoutParams
            params.width = targetWidth
            holder.progressFill.layoutParams = params
            holder.progressFill.alpha = 0.4f
        }
    }
    
    private fun animateAdditionalInfo(view: View, show: Boolean) {
        if (show) {
            view.visibility = View.VISIBLE
            view.alpha = 0f
            view.translationY = -20f
            
            view.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(300)
                .setInterpolator(DecelerateInterpolator())
                .start()
        } else {
            view.animate()
                .alpha(0f)
                .translationY(-20f)
                .setDuration(250)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction {
                    view.visibility = View.GONE
                }
                .start()
        }
    }

    override fun getItemCount(): Int = disciplines.size
}

