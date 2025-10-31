package com.example.raspisanie.adapter

import android.animation.ValueAnimator
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.animation.DecelerateInterpolator
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.raspisanie.R
import com.example.raspisanie.data.DayProgressCalculator
import com.example.raspisanie.data.DaySchedule
import com.example.raspisanie.data.LessonTimes
import com.example.raspisanie.data.PreferencesManager
import java.text.SimpleDateFormat
import java.util.*

class ScheduleAdapter(
    private var schedules: List<DaySchedule> = emptyList(),
    private val context: Context? = null
) : RecyclerView.Adapter<ScheduleAdapter.ScheduleViewHolder>() {
    
    private val prefs: PreferencesManager? = context?.let { PreferencesManager(it) }
    private val isNothingTheme: Boolean = prefs?.theme == PreferencesManager.THEME_NOTHING
    private val isHalloweenTheme: Boolean = prefs?.theme == PreferencesManager.THEME_CUSTOM
    private val isLightTheme: Boolean = prefs?.theme == PreferencesManager.THEME_LIGHT
    private val isDarkTheme: Boolean = prefs?.theme == PreferencesManager.THEME_DARK

    inner class ScheduleViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val dayName: TextView = view.findViewById(R.id.dayName)
        val dateText: TextView = view.findViewById(R.id.dateText)
        val itemsContainer: ViewGroup = view.findViewById(R.id.itemsContainer)
        val itemsWrapper: ViewGroup = view.findViewById(R.id.itemsWrapper)
        val progressIndicator: View = view.findViewById(R.id.progressIndicator)
        
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
        holder.progressHandler?.removeCallbacksAndMessages(null)
        holder.progressHandler = null
        holder.progressLineSetup = false
        holder.currentLessonNumbers = null
        
        // Cancel any animations on progress indicator
        holder.progressIndicator.clearAnimation()
        holder.progressIndicator.animate().cancel()
    }

    override fun onBindViewHolder(holder: ScheduleViewHolder, position: Int) {
        val daySchedule = schedules[position]
        
        holder.dayName.text = formatDayName(daySchedule.day)
        holder.dateText.text = formatDate(daySchedule.date)
        
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
            holder.dayName.textSize = 26f
            // Add subtle emphasis
            holder.itemView.elevation = 4f
        } else {
            holder.dayName.alpha = 0.85f
            holder.dayName.textSize = 24f
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
            
            var previousLessonNumber: Int? = null
            
            groupedByLesson.keys.sorted().forEach { lessonNum ->
                val items = groupedByLesson[lessonNum] ?: emptyList()
                
                // Add break info if needed
                if (previousLessonNumber != null) {
                    val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
                    // Check for regular break
                    val breakText = LessonTimes.getBreakText(previousLessonNumber, lessonNum, college)
                    if (breakText != null && prefs?.showBreaks == true) {
                        val breakView = LayoutInflater.from(holder.itemView.context)
                            .inflate(R.layout.item_break, holder.itemsContainer, false)
                        val breakTextView = breakView.findViewById<TextView>(R.id.breakText)
                        breakTextView.text = breakText
                        if (isNothingTheme && context != null) {
                            applyFontToView(breakView)
                        }
                        if (isHalloweenTheme && context != null) {
                            applyHalloweenToBreak(breakTextView)
                        }
                        holder.itemsContainer.addView(breakView)
                    }
                    
                    // Check for lunch
                    val lunchText = LessonTimes.getLunchText(previousLessonNumber, college)
                    if (lunchText != null && prefs?.showLunch == true) {
                        val lunchView = LayoutInflater.from(holder.itemView.context)
                            .inflate(R.layout.item_break, holder.itemsContainer, false)
                        val lunchTextView = lunchView.findViewById<TextView>(R.id.breakText)
                        lunchTextView.text = lunchText
                        if (isNothingTheme && context != null) {
                            applyFontToView(lunchView)
                        }
                        if (isHalloweenTheme && context != null) {
                            applyHalloweenToBreak(lunchTextView)
                        }
                        holder.itemsContainer.addView(lunchView)
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

                    lessonNumberView.text = lessonNum.toString()
                    
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
                    
                    // Animate item appearance
                    animateItemAppearance(lessonView)
                    
                    // Update circle state if today - wait for layout first
                    if (isToday) {
                        lessonView.viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
                            override fun onGlobalLayout() {
                                lessonView.viewTreeObserver.removeOnGlobalLayoutListener(this)
                                updateCircleState(lessonNumberView, lessonProgressOverlay, lessonNum)
                            }
                        })
                    }
                }
                
                // Add break/lunch progress if today
                if (isToday && previousLessonNumber != null) {
                    animateBreakProgress(holder.itemsContainer, previousLessonNumber, lessonNum)
                }
                
                previousLessonNumber = lessonNum
            }
            
            // Setup day progress indicator
            if (isToday && prefs?.showProgressLine == true) {
                val lessonNumbers = daySchedule.items.map { it.lessonNumber }.distinct().sorted()
                // Only setup if lesson numbers changed or not setup yet (compare lists)
                val numbersChanged = holder.currentLessonNumbers?.let { 
                    it.size != lessonNumbers.size || it != lessonNumbers 
                } ?: true
                
                if (!holder.progressLineSetup || numbersChanged) {
                    holder.currentLessonNumbers = lessonNumbers
                    setupDayProgress(holder, lessonNumbers)
                } else {
                    // Just update the progress without full setup
                    if (holder.itemsContainer.height > 0) {
                        updateProgressIndicator(holder, lessonNumbers)
                    }
                }
                
                // Apply theme-specific progress line
                when {
                    isNothingTheme -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator_nothing)
                    isHalloweenTheme -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator_halloween)
                    else -> holder.progressIndicator.setBackgroundResource(R.drawable.progress_indicator)
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
                else -> {} // Use default theme color
            }
        }
    }
    
    private fun isToday(dateStr: String): Boolean {
        val today = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date())
        return dateStr == today
    }
    
    private fun setupDayProgress(holder: ScheduleViewHolder, lessonNumbers: List<Int>) {
        // Cancel any existing handlers
        holder.progressHandler?.removeCallbacksAndMessages(null)
        
        holder.progressIndicator.visibility = View.VISIBLE
        
        // Store lesson numbers in holder tag
        holder.itemView.tag = lessonNumbers
        
        // Check if container already has height (fast path - skip ViewTreeObserver)
        val containerHeight = holder.itemsContainer.height
        if (containerHeight > 0) {
            // Already measured, update immediately
            updateProgressIndicator(holder, lessonNumbers)
            holder.progressLineSetup = true
            // Start periodic updates
            updateDayProgress(holder, lessonNumbers)
        } else {
            // Use post() instead of ViewTreeObserver for better performance
            holder.itemView.post {
                // Double-check after posting
                if (holder.itemsContainer.height > 0) {
                    updateProgressIndicator(holder, lessonNumbers)
                    holder.progressLineSetup = true
                    // Start periodic updates
                    updateDayProgress(holder, lessonNumbers)
                } else {
                    // Fallback to ViewTreeObserver only if post() didn't work
                    val listener = object : ViewTreeObserver.OnGlobalLayoutListener {
                        override fun onGlobalLayout() {
                            holder.itemView.viewTreeObserver.removeOnGlobalLayoutListener(this)
                            if (holder.itemsContainer.height > 0) {
                                updateProgressIndicator(holder, lessonNumbers)
                                holder.progressLineSetup = true
                                updateDayProgress(holder, lessonNumbers)
                            }
                        }
                    }
                    holder.itemView.viewTreeObserver.addOnGlobalLayoutListener(listener)
                }
            }
        }
    }
    
    private fun updateProgressIndicator(holder: ScheduleViewHolder, lessonNumbers: List<Int>) {
        val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
        val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val progress = DayProgressCalculator.getDayProgress(currentMinutes, lessonNumbers, college)
        
        // Get height of itemsContainer
        val containerHeight = holder.itemsContainer.height
        
        if (containerHeight <= 0) {
            // Fallback: measure if not laid out yet
            holder.itemsContainer.measure(
                View.MeasureSpec.makeMeasureSpec(holder.itemsContainer.width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            val measuredHeight = holder.itemsContainer.measuredHeight
            if (measuredHeight <= 0) return
            updateProgressHeight(holder, measuredHeight, progress)
            return
        }
        
        updateProgressHeight(holder, containerHeight, progress)
    }
    
    private fun updateProgressHeight(holder: ScheduleViewHolder, containerHeight: Int, progress: Float) {
        // Ensure progress is within bounds (0.0 to 1.0)
        val clampedProgress = progress.coerceIn(0f, 1f)
        
        // Calculate progress height - simply proportion of container height
        val progressHeight = (containerHeight * clampedProgress).toInt().coerceIn(0, containerHeight)
        
        // Update layout params - simple and direct
        val params = holder.progressIndicator.layoutParams as? ViewGroup.MarginLayoutParams
            ?: ViewGroup.MarginLayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also {
                holder.progressIndicator.layoutParams = it
            }
        
        // Simple: start from top (margin = 0), height = progress
        params.topMargin = 0
        params.height = progressHeight
        holder.progressIndicator.layoutParams = params
        
        // Ensure behind items
        holder.progressIndicator.elevation = -1f
        
        // Animate on first setup only (check if already visible)
        if ((holder.progressIndicator.scaleY == 0f || holder.progressIndicator.alpha == 0f) && !holder.progressLineSetup) {
            animateProgressLine(holder.progressIndicator)
        }
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
        
        val handler = Handler(Looper.getMainLooper())
        holder.progressHandler = handler
        
        handler.postDelayed({
                // Check if ViewHolder is still bound to the same item and attached
            if (holder.itemView.isAttachedToWindow && 
                holder.progressIndicator.visibility == View.VISIBLE &&
                holder.currentLessonNumbers?.size == lessonNumbers.size &&
                holder.currentLessonNumbers == lessonNumbers) {
                
                // Get actual layout height
                val containerHeight = holder.itemsContainer.height
                if (containerHeight > 0) {
                    val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                    val college = prefs?.college ?: PreferencesManager.COLLEGE_CHTOTIB
        val progress = DayProgressCalculator.getDayProgress(currentMinutes, lessonNumbers, college)
                    updateProgressHeight(holder, containerHeight, progress)
                } else {
                    updateProgressIndicator(holder, lessonNumbers)
                }
                
                // Update circles
                val currentMinutes = DayProgressCalculator.getCurrentTimeInMinutes()
                updateAllCircles(holder, currentMinutes)
                
                // Schedule next update
                updateDayProgress(holder, lessonNumbers)
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
                
                // Use Halloween orange for active lesson in Halloween theme
                val finalAccentColor = if (isHalloweenTheme) {
                    context.getColor(R.color.custom_colorPrimary)
                } else {
                    accentColor
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
                // Use Halloween orange for normal lessons in Halloween theme
                val finalNormalColor = if (isHalloweenTheme) {
                    context.getColor(R.color.custom_colorPrimary)
                } else {
                    normalTextColor
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
        view.alpha = 0f
        view.translationY = 10f
        
        view.post {
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 300
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    val progress = animator.animatedValue as Float
                    view.alpha = progress
                    view.translationY = 10f * (1 - progress)
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
        schedules = newSchedules
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
}
