package com.example.raspisanie

import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams
import android.widget.LinearLayout
import android.widget.ArrayAdapter
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.example.raspisanie.data.AppUpdateChecker
import com.example.raspisanie.data.AppUpdateManager
import com.example.raspisanie.data.AppVersionInfo
import com.example.raspisanie.data.Group
import com.example.raspisanie.data.GroupsListParser
import com.example.raspisanie.adapter.AppIconAdapter
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleNotificationManager
import com.example.raspisanie.util.AppIconManager
import androidx.recyclerview.widget.GridLayoutManager
import com.example.raspisanie.databinding.ActivitySettingsBinding
import com.example.raspisanie.databinding.FragmentSettingsBinding
import com.example.raspisanie.viewmodel.ScheduleViewModel
import com.example.raspisanie.viewmodel.ScheduleViewModelFactory
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch
import io.noties.markwon.Markwon
import io.noties.markwon.image.glide.GlideImagesPlugin
import io.noties.markwon.linkify.LinkifyPlugin
import kotlinx.coroutines.launch
import android.content.Intent
import android.widget.ScrollView
import android.app.DownloadManager
import android.database.Cursor
import android.os.Handler
import android.os.Looper

class SettingsFragment : Fragment() {
    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!
    private val settingsBinding: ActivitySettingsBinding get() = binding.settingsLayout
    
    private lateinit var prefs: PreferencesManager
    private lateinit var scheduleViewModel: ScheduleViewModel
    private var savedScrollPosition: Int = 0
    private var isFavoriteButtonSetup = false
    private var easterEggClickCount = 0
    private var lastClickTime = 0L
    private val easterEggNames = listOf(
        "@Serpartine", "@kameko4", "@KIR", "Ever", "Everelsu", "Durov",
        "Stalin", "Lenin", "Владимир", "ВОЛОДЯ", "Егор",
        "ВАЛЕРА", "Wplace", "SVO", "ZZZ", "Goida", "КАЛЛда?",
    )
    
    // Для отслеживания прогресса загрузки
    private var downloadProgressHandler: Handler? = null
    private var downloadProgressRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        scheduleViewModel = ViewModelProvider(
            requireActivity(),
            ScheduleViewModelFactory(requireContext().applicationContext)
        )[ScheduleViewModel::class.java]
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        prefs = PreferencesManager(requireContext())
        val toolbar = settingsBinding.toolbar
        toolbar.title = getString(R.string.settings_title)
        toolbar.menu.clear()
        toolbar.inflateMenu(R.menu.settings_toolbar_menu)
        
        // Долгое нажатие на toolbar - скролл вверх (как в Telegram)
        toolbar.setOnLongClickListener {
            settingsBinding.nestedScrollView.smoothScrollTo(0, 0)
            // Haptic feedback
            toolbar.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            true
        }
        
        // Применяем тему к иконке уведомления
        applyThemeToNotificationIcon(toolbar)
        
        toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_notification_settings -> {
                    showNotificationSettingsDialog()
                    true
                }
                else -> false
            }
        }

        toolbar.navigationIcon = null
        toolbar.setNavigationOnClickListener(null)
        
        // Применяем тему к иконке уведомления после создания меню
        toolbar.post {
            if (isAdded && context != null) {
                applyThemeToNotificationIcon(toolbar)
            }
        }
        
        // Инициализируем настройки
        setupSwitches()
        setupAdditionalSettings()
        setupCollegeSelection()
        setupGroupSelection()
        setupFavoriteButton()
        setupThemeSelection()
        setupAppIconAndName()
        setupAppAutoUpdate()
        setupAppInfo()
        applyNothingFontIfNeeded()
        
        // Восстанавливаем позицию прокрутки только после смены темы
        val savedPosition = prefs.settingsScrollPosition
        if (savedPosition > 0) {
            _binding?.settingsLayout?.nestedScrollView?.post {
                if (_binding != null && isAdded) {
                    _binding?.settingsLayout?.nestedScrollView?.scrollTo(0, savedPosition)
                    // Сбрасываем сохраненную позицию после восстановления
                    prefs.settingsScrollPosition = 0
                }
            }
        }
    }

    private fun showNotificationSettingsDialog() {
        val context = requireContext()
        val dialogView = LayoutInflater.from(context).inflate(R.layout.dialog_notification_settings, null)
        val switchNotifications = dialogView.findViewById<MaterialSwitch>(R.id.switchNotifications)
        val switchBreaks = dialogView.findViewById<MaterialSwitch>(R.id.switchBreaks)
        val switchLunch = dialogView.findViewById<MaterialSwitch>(R.id.switchLunch)
        val switchScheduleUpdates = dialogView.findViewById<MaterialSwitch>(R.id.switchScheduleUpdates)
        val radioGroup = dialogView.findViewById<RadioGroup>(R.id.radioGroupOffsets)

        val scheduleNotificationsEnabled = prefs.scheduleNotificationsEnabled
        switchNotifications.isChecked = prefs.upcomingNotificationsEnabled && scheduleNotificationsEnabled
        switchBreaks.isChecked = prefs.upcomingBreakRemindersEnabled
        switchLunch.isChecked = prefs.upcomingLunchRemindersEnabled
        switchScheduleUpdates.isChecked = prefs.scheduleUpdateNotificationsEnabled
        selectOffsetRadio(radioGroup, prefs.upcomingLessonOffsetMinutes)

        if (!scheduleNotificationsEnabled) {
            switchNotifications.isEnabled = false
        }

        val lessonsSettingsContainer = dialogView.findViewById<LinearLayout>(R.id.lessonsSettingsContainer)
        val lessonsSettingsDivider = dialogView.findViewById<View>(R.id.lessonsSettingsDivider)
        
        updateNotificationControlsEnabled(
            switchNotifications.isChecked && scheduleNotificationsEnabled,
            radioGroup,
            switchBreaks,
            switchLunch,
            lessonsSettingsContainer,
            lessonsSettingsDivider
        )

        switchNotifications.setOnCheckedChangeListener { _, isChecked ->
            updateNotificationControlsEnabled(
                isChecked && scheduleNotificationsEnabled,
                radioGroup,
                switchBreaks,
                switchLunch,
                lessonsSettingsContainer,
                lessonsSettingsDivider
            )
        }

        // Применяем тему к диалогу
        val dialogBuilder = MaterialAlertDialogBuilder(context, getDialogTheme(context))
            .setTitle(R.string.notification_settings_title)
            .setView(dialogView)
        
        // Применяем тему к элементам внутри диалога
        applyThemeToNotificationDialog(dialogView, context)
        
        dialogBuilder.setPositiveButton(R.string.notification_settings_save) { _, _ ->
                val enabled = switchNotifications.isChecked && scheduleNotificationsEnabled
                prefs.upcomingNotificationsEnabled = enabled

                // Сохраняем настройки напоминаний об обеде и переменах независимо от общего состояния
                val minutes = extractOffsetFromSelection(radioGroup)
                prefs.upcomingLessonOffsetMinutes = minutes
                prefs.upcomingBreakRemindersEnabled = switchBreaks.isChecked
                prefs.upcomingLunchRemindersEnabled = switchLunch.isChecked
                prefs.scheduleUpdateNotificationsEnabled = switchScheduleUpdates.isChecked

                if (enabled) {
                    Toast.makeText(context, R.string.notification_settings_saved, Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(context, R.string.notification_settings_disabled, Toast.LENGTH_SHORT).show()
                }

                // Перепланируем уведомления при изменении настроек
                ScheduleNotificationManager.scheduleUpcomingEventNotifications(
                    context.applicationContext,
                    scheduleViewModel.schedule.value
                )
            }
            .setNegativeButton(R.string.notification_settings_cancel, null)
        
        val dialog = dialogBuilder.create()
        
        // Получаем цвет для кнопок в зависимости от темы
        val buttonTextColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_colorPrimary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_colorPrimary)
            PreferencesManager.THEME_BLUE -> ContextCompat.getColor(context, R.color.blue_colorPrimary)
            PreferencesManager.THEME_GRAY -> ContextCompat.getColor(context, R.color.gray_colorPrimary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_colorPrimary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_colorPrimary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_colorPrimary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_colorPrimary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_colorPrimary)
            else -> ContextCompat.getColor(context, R.color.dark_colorPrimary)
        }
        
        dialog.show()
        
        // Применяем правильные цвета к кнопкам диалога после показа
        dialog.window?.decorView?.post {
            val positiveButton = dialog.getButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE)
            val negativeButton = dialog.getButton(androidx.appcompat.app.AlertDialog.BUTTON_NEGATIVE)
            
            positiveButton?.setTextColor(buttonTextColor)
            negativeButton?.setTextColor(buttonTextColor)
        }
        
        // Убеждаемся, что диалог не обрезается
        dialog.window?.let { window ->
            // MaterialAlertDialogBuilder автоматически управляет размерами диалога
            // ScrollView в layout файле обеспечит прокрутку при необходимости
            window.setLayout(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
    }
    
    /**
     * Получить тему для MaterialAlertDialogBuilder в зависимости от выбранной темы приложения
     */
    private fun getDialogTheme(context: Context): Int {
        return when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> com.google.android.material.R.style.ThemeOverlay_Material3_Light
            PreferencesManager.THEME_DARK -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_BLUE -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_GRAY -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_PURPLE -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_HALLOWEEN -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_NOTHING -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_GREEN -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            PreferencesManager.THEME_NEW_YEAR -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
            else -> com.google.android.material.R.style.ThemeOverlay_Material3_Dark
        }
    }
    
    /**
     * Применить тему к элементам внутри диалога уведомлений
     */
    private fun applyThemeToNotificationDialog(dialogView: View, context: Context) {
        // Применяем цвета текста
        val textPrimaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_textColorPrimary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_textColorPrimary)
            PreferencesManager.THEME_BLUE -> ContextCompat.getColor(context, R.color.blue_textColorPrimary)
            PreferencesManager.THEME_GRAY -> ContextCompat.getColor(context, R.color.gray_textColorPrimary)
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
            PreferencesManager.THEME_BLUE -> ContextCompat.getColor(context, R.color.blue_textColorSecondary)
            PreferencesManager.THEME_GRAY -> ContextCompat.getColor(context, R.color.gray_textColorSecondary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_textColorSecondary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_textColorSecondary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_textColorSecondary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_textColorSecondary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_textColorSecondary)
            else -> ContextCompat.getColor(context, R.color.dark_textColorSecondary)
        }
        
        dialogView.findViewById<TextView>(R.id.notificationsDescription)?.setTextColor(textSecondaryColor)
        
        // Применяем цвета к MaterialSwitch
        dialogView.findViewById<MaterialSwitch>(R.id.switchNotifications)?.apply {
            setTextColor(textPrimaryColor)
        }
        dialogView.findViewById<MaterialSwitch>(R.id.switchBreaks)?.apply {
            setTextColor(textPrimaryColor)
        }
        dialogView.findViewById<MaterialSwitch>(R.id.switchLunch)?.apply {
            setTextColor(textPrimaryColor)
        }
        
        // Применяем цвета к RadioButton
        val radioGroup = dialogView.findViewById<RadioGroup>(R.id.radioGroupOffsets)
        for (i in 0 until radioGroup.childCount) {
            val radioButton = radioGroup.getChildAt(i) as? RadioButton
            radioButton?.setTextColor(textPrimaryColor)
        }
    }

    private fun updateNotificationControlsEnabled(
        enabled: Boolean,
        radioGroup: RadioGroup,
        switchBreaks: MaterialSwitch,
        switchLunch: MaterialSwitch,
        lessonsSettingsContainer: LinearLayout? = null,
        lessonsSettingsDivider: View? = null
    ) {
        // Включаем/отключаем настройки времени напоминаний о парах
        radioGroup.isEnabled = enabled
        for (i in 0 until radioGroup.childCount) {
            radioGroup.getChildAt(i).isEnabled = enabled
        }
        
        // Показываем/скрываем настройки времени напоминаний
        lessonsSettingsContainer?.visibility = if (enabled) View.VISIBLE else View.GONE
        lessonsSettingsDivider?.visibility = if (enabled) View.VISIBLE else View.GONE
        
        // Перемены и обед можно включать независимо от напоминаний о парах
        // Они остаются всегда доступными
    }

    private fun selectOffsetRadio(radioGroup: RadioGroup, minutes: Int) {
        val normalized = when {
            minutes <= 0 -> 0
            minutes <= 5 -> 5
            minutes <= 10 -> 10
            else -> 15
        }
        for (i in 0 until radioGroup.childCount) {
            val child = radioGroup.getChildAt(i)
            val tagValue = (child as? RadioButton)?.tag?.toString()?.toIntOrNull()
            if (tagValue == normalized) {
                child.isChecked = true
                return
            }
        }
        radioGroup.check(radioGroup.getChildAt(0).id)
    }

    private fun extractOffsetFromSelection(radioGroup: RadioGroup): Int {
        val selectedId = radioGroup.checkedRadioButtonId
        val radio = radioGroup.findViewById<RadioButton>(selectedId)
        return radio?.tag?.toString()?.toIntOrNull() ?: 5
    }
    
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
    }
    
    private fun applyNothingFontIfNeeded() {
        if (prefs.theme == PreferencesManager.THEME_NOTHING) {
            try {
                val ndotFont = resources.getFont(R.font.ndot)
                val rootView = _binding?.settingsLayout?.root ?: return
                rootView.post {
                    if (_binding != null && isAdded) {
                        _binding?.settingsLayout?.root?.let { root ->
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

    private fun setupCollegeSelection() {
        val collegeSpinner = settingsBinding.collegeSpinner
        
        val colleges = listOf(
            "ЧТОТиБ" to PreferencesManager.COLLEGE_CHTOTIB,
            "ЗабГК" to PreferencesManager.COLLEGE_ZABGC
        )
        
        val collegeNames = colleges.map { it.first }
        val adapter = ArrayAdapter(
            requireContext(),
            android.R.layout.simple_spinner_item,
            collegeNames
        ).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        
        collegeSpinner.adapter = adapter
        
        val currentIndex = colleges.indexOfFirst { it.second == prefs.college }
        if (currentIndex >= 0) {
            collegeSpinner.setSelection(currentIndex)
        }
        
        collegeSpinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) {
                val selectedCollege = colleges[position].second
                if (selectedCollege != prefs.college) {
                    prefs.college = selectedCollege
                    prefs.selectedGroupName = ""
                    prefs.selectedGroupFile = ""
                    setupGroupSelection()
                    Toast.makeText(requireContext(), "Выбран техникум: ${colleges[position].first}", Toast.LENGTH_SHORT).show()
                }
            }
            
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
    }

    private fun setupSwitches() {
        val switchShowBreaks = settingsBinding.switchShowBreaks
        val switchShowLunch = settingsBinding.switchShowLunch
        val switchShowTime = settingsBinding.switchShowTime
        val switchShowLessonStatus = settingsBinding.switchShowLessonStatus
        val switchShowProgressLine = settingsBinding.switchShowProgressLine
        
        switchShowBreaks.isChecked = prefs.showBreaks
        switchShowLunch.isChecked = prefs.showLunch
        switchShowTime.isChecked = prefs.showTime
        switchShowLessonStatus.isChecked = prefs.showLessonStatus
        switchShowProgressLine.isChecked = prefs.showProgressLine

        switchShowBreaks.setOnCheckedChangeListener { _, isChecked ->
            prefs.showBreaks = isChecked
        }

        switchShowLunch.setOnCheckedChangeListener { _, isChecked ->
            prefs.showLunch = isChecked
        }

        switchShowTime.setOnCheckedChangeListener { _, isChecked ->
            prefs.showTime = isChecked
        }

        switchShowLessonStatus.setOnCheckedChangeListener { _, isChecked ->
            prefs.showLessonStatus = isChecked
        }

        switchShowProgressLine.setOnCheckedChangeListener { _, isChecked ->
            prefs.showProgressLine = isChecked
            // Уведомить MainActivity о необходимости обновления
            (activity as? MainActivity)?.let {
                // Можно обновить расписание если нужно
            }
        }
        
        // ========== НАСТРОЙКИ СТАТУСА ПАР ==========
        
        // Максимальное время отображения для текущей пары
        val seekBarCurrentMax = settingsBinding.seekBarLessonStatusCurrentMax
        val currentMaxValue = settingsBinding.lessonStatusCurrentMaxValue
        
        val currentMax = prefs.lessonStatusCurrentMaxMinutes
        // SeekBar: 0-90, значение: 30-120 (0 -> 30, 90 -> 120)
        val progress = (currentMax - 30).coerceIn(0, 90)
        seekBarCurrentMax.progress = progress
        currentMaxValue.text = currentMax.toString()
        
        seekBarCurrentMax.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    // progress: 0-90 -> value: 30-120
                    val value = 30 + progress
                    currentMaxValue.text = value.toString()
                    prefs.lessonStatusCurrentMaxMinutes = value
                }
            }
            
            override fun onStartTrackingTouch(seekBar: android.widget.SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: android.widget.SeekBar?) {}
        })
        
        // Максимальное время отображения для следующей пары
        val seekBarNextMax = settingsBinding.seekBarLessonStatusNextMax
        val nextMaxValue = settingsBinding.lessonStatusNextMaxValue
        
        val nextMax = prefs.lessonStatusNextMaxMinutes
        val nextProgress = (nextMax - 30).coerceIn(0, 90)
        seekBarNextMax.progress = nextProgress
        nextMaxValue.text = nextMax.toString()
        
        seekBarNextMax.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    // progress: 0-90 -> value: 30-120
                    val value = 30 + progress
                    nextMaxValue.text = value.toString()
                    prefs.lessonStatusNextMaxMinutes = value
                }
            }
            
            override fun onStartTrackingTouch(seekBar: android.widget.SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: android.widget.SeekBar?) {}
        })
    }
    
    private fun setupAdditionalSettings() {
        val switchAutoRefresh = settingsBinding.switchAutoRefresh
        val spinnerRefreshInterval = settingsBinding.spinnerRefreshInterval
        
        switchAutoRefresh.isChecked = prefs.autoRefreshEnabled
        switchAutoRefresh.setOnCheckedChangeListener { _, isChecked ->
            prefs.autoRefreshEnabled = isChecked
            spinnerRefreshInterval.isEnabled = isChecked
            
            if (isChecked) {
                com.example.raspisanie.data.AutoRefreshManager.setupAutoRefresh(requireContext())
            } else {
                com.example.raspisanie.data.AutoRefreshManager.cancelAutoRefresh(requireContext())
            }
        }
        
        val intervals = listOf(
            "15 минут" to PreferencesManager.REFRESH_INTERVAL_15,
            "30 минут" to PreferencesManager.REFRESH_INTERVAL_30,
            "1 час" to PreferencesManager.REFRESH_INTERVAL_60,
            "2 часа" to PreferencesManager.REFRESH_INTERVAL_120
        )
        val intervalNames = intervals.map { it.first }
        val intervalAdapter = ArrayAdapter(
            requireContext(),
            android.R.layout.simple_spinner_item,
            intervalNames
        ).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        spinnerRefreshInterval.adapter = intervalAdapter
        spinnerRefreshInterval.isEnabled = prefs.autoRefreshEnabled
        
        val currentIntervalIndex = intervals.indexOfFirst { it.second == prefs.autoRefreshInterval }
        if (currentIntervalIndex >= 0) {
            spinnerRefreshInterval.setSelection(currentIntervalIndex)
        }
        
        spinnerRefreshInterval.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) {
                val selectedInterval = intervals[position].second
                prefs.autoRefreshInterval = selectedInterval
                if (prefs.autoRefreshEnabled) {
                    com.example.raspisanie.data.AutoRefreshManager.setupAutoRefresh(requireContext())
                }
            }
            
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
        
        val switchCache = settingsBinding.switchCache
        switchCache.isChecked = prefs.cacheEnabled
        switchCache.setOnCheckedChangeListener { _, isChecked ->
            prefs.cacheEnabled = isChecked
        }
        
        val seekBarFontSize = settingsBinding.seekBarFontSize
        val fontSizeValue = settingsBinding.fontSizeValue
        
        val fontSizes = listOf(
            PreferencesManager.FONT_SIZE_SMALL,
            PreferencesManager.FONT_SIZE_NORMAL,
            PreferencesManager.FONT_SIZE_LARGE,
            PreferencesManager.FONT_SIZE_EXTRA_LARGE
        )
        val fontSizeLabels = listOf("Мелкий", "Обычный", "Крупный", "Очень крупный")
        
        val currentFontSizeIndex = fontSizes.indexOfFirst { it == prefs.fontSize }.coerceAtLeast(0).coerceAtMost(3)
        seekBarFontSize.progress = currentFontSizeIndex
        fontSizeValue.text = fontSizeLabels[currentFontSizeIndex]
        
        seekBarFontSize.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser && progress in 0..3) {
                    val selectedFontSize = fontSizes[progress]
                    fontSizeValue.text = fontSizeLabels[progress]
                    prefs.fontSize = selectedFontSize
                }
            }
            
            override fun onStartTrackingTouch(seekBar: android.widget.SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: android.widget.SeekBar?) {}
        })
    }


    private fun setupGroupSelection() {
        val selectedGroupName = settingsBinding.selectedGroupName
        val groupSpinner = settingsBinding.groupSpinner
        
        selectedGroupName.text = if (prefs.isGroupSelected()) {
            prefs.selectedGroupName
        } else {
            getString(R.string.no_group_selected)
        }
        
        val groupsParser = GroupsListParser()
        
        lifecycleScope.launch {
            try {
                val groups = groupsParser.fetchGroupsList(prefs.college)
                val favorites = prefs.getFavoriteGroups()
                
                val favoriteGroups = mutableListOf<Group>()
                val regularGroups = mutableListOf<Group>()
                
                for (group in groups.sortedBy { it.name }) {
                    if (favorites.contains(group.name)) {
                        favoriteGroups.add(group)
                    } else {
                        regularGroups.add(group)
                    }
                }
                
                // Проверяем, что фрагмент еще активен
                if (!isAdded || _binding == null) return@launch
                
                val noGroupSelected = Group(
                    name = getString(R.string.no_group_selected),
                    url = "",
                    fileName = ""
                )
                val sortedGroups = listOf(noGroupSelected) + favoriteGroups + regularGroups
                val groupNames = sortedGroups.map { it.name }
                
                val adapter = ArrayAdapter(
                    requireContext(),
                    android.R.layout.simple_spinner_item,
                    groupNames
                ).apply {
                    setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
                }
                
                groupSpinner.adapter = adapter
                
                val currentIndex = if (prefs.isGroupSelected()) {
                    groupNames.indexOf(prefs.selectedGroupName)
                } else {
                    0
                }
                if (currentIndex >= 0) {
                    groupSpinner.setSelection(currentIndex)
                }
                
                groupSpinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                    override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) {
                        val selectedGroup = sortedGroups[position]
                        val wasChanged = selectedGroup.fileName != prefs.selectedGroupFile
                        
                        if (selectedGroup.fileName.isEmpty()) {
                            prefs.selectedGroupName = ""
                            prefs.selectedGroupFile = ""
                            selectedGroupName.text = getString(R.string.no_group_selected)
                        } else {
                            prefs.selectedGroupName = selectedGroup.name
                            prefs.selectedGroupFile = selectedGroup.fileName
                            selectedGroupName.text = selectedGroup.name
                        }
                        
                        updateFavoriteButton(selectedGroup.name)
                        
                        if (wasChanged) {
                            val message = if (selectedGroup.fileName.isEmpty()) {
                                "Группа не выбрана"
                            } else {
                                "Группа изменена: ${selectedGroup.name}"
                            }
                            Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
                        }
                    }
                    
                    override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
                }
                
            } catch (e: kotlinx.coroutines.CancellationException) {
                // Игнорируем отмену корутины - это нормально при уничтожении фрагмента
                throw e
            } catch (e: Exception) {
                if (isAdded && _binding != null) {
                    android.util.Log.e("SettingsFragment", "Ошибка загрузки групп", e)
                    groupSpinner.isEnabled = false
                    selectedGroupName.text = if (prefs.isGroupSelected()) {
                        "${prefs.selectedGroupName} (ошибка загрузки списка)"
                    } else {
                        "${getString(R.string.no_group_selected)} (ошибка загрузки списка)"
                    }
                }
            }
        }
    }
    
    private fun setupFavoriteButton() {
        val btnAddToFavorites = settingsBinding.btnAddToFavorites
        
        if (prefs.isGroupSelected()) {
            updateFavoriteButton(prefs.selectedGroupName)
        }
        
        if (!isFavoriteButtonSetup) {
            btnAddToFavorites.setOnClickListener {
                if (prefs.isGroupSelected()) {
                    val groupName = prefs.selectedGroupName
                    val isFavorite = prefs.isFavoriteGroup(groupName)
                    
                    if (isFavorite) {
                        prefs.removeFavoriteGroup(groupName)
                        Toast.makeText(requireContext(), "Удалено из избранного", Toast.LENGTH_SHORT).show()
                    } else {
                        prefs.addFavoriteGroup(groupName)
                        Toast.makeText(requireContext(), "Добавлено в избранное", Toast.LENGTH_SHORT).show()
                    }
                    
                    updateFavoriteButton(groupName)
                    
                    val selectedGroupName = settingsBinding.selectedGroupName
                    selectedGroupName?.text = prefs.selectedGroupName
                    setupGroupSelection()
                }
            }
            isFavoriteButtonSetup = true
        }
    }
    
    private fun updateFavoriteButton(groupName: String) {
        val btnAddToFavorites = settingsBinding.btnAddToFavorites
        
        val isFavorite = prefs.isFavoriteGroup(groupName)
        btnAddToFavorites.text = if (isFavorite) {
            "⭐ В избранном"
        } else {
            "⭐ Добавить в избранное"
        }
    }

    private fun setupThemeSelection() {
        val currentTheme = prefs.theme
        
        setupThemeCard(settingsBinding.root, R.id.themeDark, "Темная", "Черный ворон", R.drawable.theme_preview_dark, PreferencesManager.THEME_DARK, currentTheme == PreferencesManager.THEME_DARK)
        setupThemeCard(settingsBinding.root, R.id.themeLight, "Светлая", "Яркий белый фон(блять)", R.drawable.theme_preview_light, PreferencesManager.THEME_LIGHT, currentTheme == PreferencesManager.THEME_LIGHT)
        setupThemeCard(settingsBinding.root, R.id.themeFiolet, "Фиолетовая", "Танос тут был", R.drawable.theme_preview_system, PreferencesManager.THEME_PURPLE, currentTheme == PreferencesManager.THEME_PURPLE)
        setupThemeCard(settingsBinding.root, R.id.themeCustom, "Хэллоуин", "Оранжевая страшилка", R.drawable.theme_preview_custom, PreferencesManager.THEME_HALLOWEEN, currentTheme == PreferencesManager.THEME_HALLOWEEN)
        setupThemeCard(settingsBinding.root, R.id.themeGreen, "Зелёная", "Ну это больше салатовый", R.drawable.theme_preview_green, PreferencesManager.THEME_GREEN, currentTheme == PreferencesManager.THEME_GREEN)
        setupThemeCard(settingsBinding.root, R.id.themeNewYear, "Новогодняя", "Красный, белый, зелёный со снегом", R.drawable.theme_preview_newyear, PreferencesManager.THEME_NEW_YEAR, currentTheme == PreferencesManager.THEME_NEW_YEAR)
        setupThemeCard(settingsBinding.root, R.id.themeBlue, "Синяя", "Грязный gay", R.drawable.theme_preview_blue, PreferencesManager.THEME_BLUE, currentTheme == PreferencesManager.THEME_BLUE)
        setupThemeCard(settingsBinding.root, R.id.themeGray, "Серая", "Грязный серый цвет", R.drawable.theme_preview_gray, PreferencesManager.THEME_GRAY, currentTheme == PreferencesManager.THEME_GRAY)
        setupThemeCard(settingsBinding.root, R.id.themeNothing, "RedDot", "Красный с NDot шрифтом", R.drawable.theme_preview_nothing, PreferencesManager.THEME_NOTHING, currentTheme == PreferencesManager.THEME_NOTHING)
    }

    private fun setupThemeCard(
        parent: View,
        cardId: Int,
        name: String,
        description: String,
        previewDrawable: Int,
        themeKey: String,
        isSelected: Boolean
    ) {
        val cardView = parent.findViewById<androidx.cardview.widget.CardView>(cardId) ?: return
        val root = cardView.getChildAt(0) as? androidx.constraintlayout.widget.ConstraintLayout ?: return

        val preview = root.findViewById<View>(R.id.themePreview)
        val nameView = root.findViewById<TextView>(R.id.themeName)
        val descView = root.findViewById<TextView>(R.id.themeDescription)
        val indicator = root.findViewById<View>(R.id.radioIndicator)

        preview?.background = ContextCompat.getDrawable(requireContext(), previewDrawable)
        nameView?.text = name
        descView?.text = description

        val textPrimaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_textColorPrimary, null)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_textColorPrimary, null)
            PreferencesManager.THEME_BLUE -> resources.getColor(R.color.blue_textColorPrimary, null)
            PreferencesManager.THEME_GRAY -> resources.getColor(R.color.gray_textColorPrimary, null)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_textColorPrimary, null)
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_textColorPrimary, null)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_textColorPrimary, null)
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_textColorPrimary, null)
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_textColorPrimary, null)
            else -> resources.getColor(android.R.color.black, null)
        }
        val textSecondaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_textColorSecondary, null)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_textColorSecondary, null)
            PreferencesManager.THEME_BLUE -> resources.getColor(R.color.blue_textColorSecondary, null)
            PreferencesManager.THEME_GRAY -> resources.getColor(R.color.gray_textColorSecondary, null)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_textColorSecondary, null)
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_textColorSecondary, null)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_textColorSecondary, null)
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_textColorSecondary, null)
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_textColorSecondary, null)
            else -> resources.getColor(android.R.color.darker_gray, null)
        }
        nameView?.setTextColor(textPrimaryColor)
        descView?.setTextColor(textSecondaryColor)

        if (isSelected) {
            root.isSelected = true
            indicator?.isSelected = true
            root.refreshDrawableState()
            indicator?.refreshDrawableState()
        }

        cardView.setOnClickListener {
            // Сохраняем позицию прокрутки перед сменой темы
            val scrollY = settingsBinding.nestedScrollView.scrollY
            if (scrollY > 0) {
                prefs.settingsScrollPosition = scrollY
            }
            prefs.theme = themeKey
            val activity = activity as? AppCompatActivity
            // Убираем все анимации при переключении темы
            activity?.overridePendingTransition(0, 0)
            activity?.recreate()
        }
        
        root.setOnClickListener {
            cardView.performClick()
        }
    }

    private fun setupAppIconAndName() {
        // Настройка RecyclerView для иконок прямо в настройках (как в Telegram)
        val recyclerViewIcons = settingsBinding.recyclerViewIcons
        val currentIcon = prefs.appIcon
        
        val icons = listOf(
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_DEFAULT,
                getString(R.string.app_icon_default),
                R.drawable.ic_launcher_foreground
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_BLACK,
                getString(R.string.app_icon_black),
                R.drawable.ic_launcher_blue
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_DARK,
                getString(R.string.app_icon_dark),
                R.drawable.ic_launcher_gray
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_LIGHT,
                getString(R.string.app_icon_light),
                R.drawable.ic_launcher_light
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_PURPLE,
                getString(R.string.app_icon_purple),
                R.drawable.ic_launcher_purple
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_GREEN,
                getString(R.string.app_icon_green),
                R.drawable.ic_launcher_green
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_NEW_YEAR,
                getString(R.string.app_icon_newyear),
                R.drawable.ic_launcher_newyear
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_NOTHING,
                getString(R.string.app_icon_nothing),
                R.drawable.ic_launcher_nothing
            ),
            AppIconAdapter.IconItem(
                PreferencesManager.APP_ICON_HALLOWEEN,
                getString(R.string.app_icon_halloween),
                R.drawable.ic_launcher_halloween
            )
        )
        
        val iconAdapter = AppIconAdapter(icons, currentIcon) { iconId ->
            // Сохранение выбранной иконки сразу при выборе (как в Telegram)
            if (prefs.appIcon != iconId) {
                prefs.appIcon = iconId
                // Передаём Activity для перезапуска
                AppIconManager.switchIcon(requireActivity(), iconId)
            }
        }
        
        // Grid layout с 4 колонками (как в Telegram)
        recyclerViewIcons.layoutManager = GridLayoutManager(requireContext(), 4)
        recyclerViewIcons.adapter = iconAdapter
    }

    private fun setupAppAutoUpdate() {
        val switchAppAutoUpdate = settingsBinding.switchAppAutoUpdate
        val btnCheckUpdates = settingsBinding.btnCheckUpdates
        
        switchAppAutoUpdate.isChecked = prefs.appAutoUpdateEnabled
        switchAppAutoUpdate.setOnCheckedChangeListener { _, isChecked ->
            prefs.appAutoUpdateEnabled = isChecked
            if (isChecked) {
                AppUpdateManager.setupAutoUpdateCheck(requireContext())
            } else {
                AppUpdateManager.cancelAutoUpdateCheck(requireContext())
            }
        }
        
        btnCheckUpdates.setOnClickListener {
            checkForUpdates(btnCheckUpdates)
        }
        
        // Проверить и начать отслеживание прогресса загрузки, если идет загрузка
        checkAndStartDownloadProgressTracking()
    }
    
    private fun checkForUpdates(btnCheckUpdates: com.google.android.material.button.MaterialButton) {
        btnCheckUpdates.isEnabled = false
        btnCheckUpdates.text = "Проверка..."
        
        lifecycleScope.launch {
            try {
                val result = AppUpdateChecker.checkForUpdates(requireContext())
                
                when (result) {
                    is AppUpdateChecker.UpdateCheckResult.UpdateAvailable -> {
                        showUpdateDialog(result.versionInfo)
                        prefs.lastUpdateCheck = System.currentTimeMillis()
                    }
                    AppUpdateChecker.UpdateCheckResult.NoUpdate -> {
                        Toast.makeText(requireContext(), "У вас установлена последняя версия", Toast.LENGTH_SHORT).show()
                        prefs.lastUpdateCheck = System.currentTimeMillis()
                    }
                    is AppUpdateChecker.UpdateCheckResult.Error -> {
                        Toast.makeText(requireContext(), "Ошибка проверки: ${result.message}", Toast.LENGTH_SHORT).show()
                    }
                }
            } catch (e: Exception) {
                Toast.makeText(requireContext(), "Ошибка при проверке обновлений", Toast.LENGTH_SHORT).show()
            } finally {
                btnCheckUpdates.isEnabled = true
                btnCheckUpdates.text = "Проверить обновления"
            }
        }
    }
    
    private fun showUpdateDialog(versionInfo: AppVersionInfo) {
        val context = requireContext()
        
        // Создаем кастомный layout для диалога
        val scrollView = ScrollView(context).apply {
            layoutParams = LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.WRAP_CONTENT
            )
        }
        val fontSizeMultiplier = getFontSizeMultiplier()
        val textView = TextView(context).apply {
            setPadding(48, 32, 48, 32)
            textSize = 14f * fontSizeMultiplier
            layoutParams = LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.WRAP_CONTENT
            )
        }
        scrollView.addView(textView)
        
        // Инициализируем Markwon с поддержкой изображений и ссылок
        val markwon = Markwon.builder(context)
            .usePlugin(GlideImagesPlugin.create(context))
            .usePlugin(LinkifyPlugin.create())
            .build()
        
        // Формируем текст для отображения
        val changelogText = versionInfo.changelog ?: "Обновления и улучшения"
        val fullText = "## Версия ${versionInfo.versionName}\n\n$changelogText"
        
        // Рендерим Markdown
        markwon.setMarkdown(textView, fullText)
        
        val builder = MaterialAlertDialogBuilder(context, getDialogTheme(context))
            .setTitle("Доступно обновление")
            .setView(scrollView)
            .setPositiveButton("Обновить") { _, _ ->
                if (versionInfo.downloadUrl != null) {
                    // Показать прогресс-бар сразу после начала загрузки
                    showDownloadProgress()
                    AppUpdateManager.downloadAndInstall(context, versionInfo.downloadUrl, versionInfo.versionName)
                    // Начать отслеживание прогресса через небольшую задержку (чтобы downloadId успел сохраниться)
                    Handler(Looper.getMainLooper()).postDelayed({
                        checkAndStartDownloadProgressTracking()
                    }, 500)
                } else {
                    Toast.makeText(context, "Ссылка на скачивание недоступна", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Позже", null)
            .setNeutralButton("Поделиться") { _, _ ->
                shareUpdateInfo(versionInfo)
            }
        
        builder.show()
    }
    
    private fun shareUpdateInfo(versionInfo: AppVersionInfo) {
        val shareText = buildString {
            append("Доступна новая версия приложения Расписание!\n\n")
            append("Версия: ${versionInfo.versionName}\n\n")
            if (versionInfo.changelog != null) {
                // Убираем Markdown форматирование для текстового шаринга
                val plainText = versionInfo.changelog
                    .replace(Regex("!\\[.*?\\]\\(.*?\\)"), "") // Убираем изображения
                    .replace(Regex("\\[([^\\]]+)\\]\\([^)]+\\)"), "$1") // Преобразуем ссылки в текст
                    .replace(Regex("#+\\s*"), "") // Убираем заголовки
                    .replace(Regex("\\*\\*([^*]+)\\*\\*"), "$1") // Убираем жирный текст
                    .replace(Regex("\\*([^*]+)\\*"), "$1") // Убираем курсив
                    .replace(Regex("`([^`]+)`"), "$1") // Убираем код
                    .trim()
                append("Изменения:\n$plainText")
            } else {
                append("Обновления и улучшения")
            }
        }
        
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "Обновление приложения Расписание")
            putExtra(Intent.EXTRA_TEXT, shareText)
        }
        
        val chooser = Intent.createChooser(shareIntent, "Поделиться обновлением")
        startActivity(chooser)
    }
    
    private fun setupAppInfo() {
        val settingsContent = settingsBinding.root
        
        try {
            val packageInfo = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                requireContext().packageManager.getPackageInfo(requireContext().packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                requireContext().packageManager.getPackageInfo(requireContext().packageName, 0)
            }
            val versionName = packageInfo.versionName ?: "unknown"
            val versionText = settingsContent.findViewById<TextView>(R.id.versionText)
            versionText?.text = getString(R.string.version_format, versionName)
        } catch (e: Exception) {
            // Ignore
        }
        
        val authorName = settingsBinding.authorName
        authorName?.text = getString(R.string.author_name)
        authorName?.setOnClickListener {
            openAuthorProfile()
        }
        
        // Установить имя бета-тестера
        val betaTesterName = settingsContent.findViewById<TextView>(R.id.betaTesterName)
        betaTesterName?.text = getString(R.string.beta_tester_name)
        
        val changelogButton = settingsContent.findViewById<TextView>(R.id.changelogButton)
        changelogButton?.setOnClickListener {
            openChangelog()
        }
        
        val authorText = settingsContent.findViewById<TextView>(R.id.authorText)
        authorText?.setOnClickListener {
            handleEasterEggClick()
        }
    }
    
    private fun handleEasterEggClick() {
        val currentTime = System.currentTimeMillis()
        
        if (currentTime - lastClickTime > 5000) {
            easterEggClickCount = 0
        }
        
        lastClickTime = currentTime
        easterEggClickCount++
        
        if (easterEggClickCount >= 5) {
            val settingsContent = settingsBinding.root
            val authorName = settingsBinding.authorName ?: return
            val randomName = easterEggNames.random()
            val originalText = getString(R.string.author_name)
            
            authorName.text = "$originalText\n$randomName"
            easterEggClickCount = 0
            
            authorName.postDelayed({
                authorName.text = originalText
            }, 5000)
        }
    }
    
    private fun openAuthorProfile() {
        val profileUrl = getString(R.string.author_profile_url)
        try {
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(profileUrl))
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(requireContext(), getString(R.string.cannot_open_profile), Toast.LENGTH_SHORT).show()
        }
    }
    
    private fun openChangelog() {
        val changelogUrl = getString(R.string.changelog_url)
        try {
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(changelogUrl))
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(requireContext(), "Не удалось открыть патчноты", Toast.LENGTH_SHORT).show()
        }
    }
    
    /**
     * Применить тему к иконке уведомления в toolbar
     */
    private fun getFontSizeMultiplier(): Float {
        return when (prefs.fontSize) {
            PreferencesManager.FONT_SIZE_SMALL -> 0.85f
            PreferencesManager.FONT_SIZE_NORMAL -> 1.0f
            PreferencesManager.FONT_SIZE_LARGE -> 1.15f
            PreferencesManager.FONT_SIZE_EXTRA_LARGE -> 1.3f
            else -> 1.0f
        }
    }
    
    private fun applyThemeToNotificationIcon(toolbar: androidx.appcompat.widget.Toolbar) {
        val notificationItem = toolbar.menu.findItem(R.id.action_notification_settings) ?: return
        val context = context ?: return
        
        // Получаем цвет иконки в зависимости от темы
        // Для светлой темы используем темный цвет для лучшей видимости
        val iconColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> ContextCompat.getColor(context, R.color.light_textColorPrimary)
            PreferencesManager.THEME_DARK -> ContextCompat.getColor(context, R.color.dark_textColorPrimary)
            PreferencesManager.THEME_BLUE -> ContextCompat.getColor(context, R.color.blue_textColorPrimary)
            PreferencesManager.THEME_GRAY -> ContextCompat.getColor(context, R.color.gray_textColorPrimary)
            PreferencesManager.THEME_PURPLE -> ContextCompat.getColor(context, R.color.system_textColorPrimary)
            PreferencesManager.THEME_HALLOWEEN -> ContextCompat.getColor(context, R.color.custom_textColorPrimary)
            PreferencesManager.THEME_NOTHING -> ContextCompat.getColor(context, R.color.nothing_textColorPrimary)
            PreferencesManager.THEME_GREEN -> ContextCompat.getColor(context, R.color.green_textColorPrimary)
            PreferencesManager.THEME_NEW_YEAR -> ContextCompat.getColor(context, R.color.newyear_textColorPrimary)
            else -> ContextCompat.getColor(context, R.color.dark_textColorPrimary)
        }
        
        // Применяем цвет к иконке
        val icon = AppCompatResources.getDrawable(context, R.drawable.ic_notification_schedule)
        icon?.let {
            it.setTint(iconColor)
            notificationItem.icon = it
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        // Остановить отслеживание прогресса загрузки
        stopDownloadProgressTracking()
        _binding = null
    }
    
    override fun onResume() {
        super.onResume()
        // Проверить и начать отслеживание прогресса загрузки, если идет загрузка
        checkAndStartDownloadProgressTracking()
    }
    
    override fun onPause() {
        super.onPause()
        // Остановить отслеживание прогресса при уходе с экрана
        stopDownloadProgressTracking()
    }
    
    /**
     * Проверить и начать отслеживание прогресса загрузки обновления
     */
    private fun checkAndStartDownloadProgressTracking() {
        if (!isAdded || _binding == null) return
        
        val downloadId = prefs.lastUpdateDownloadId
        if (downloadId <= 0) {
            // Нет активной загрузки - скрыть прогресс-бар
            hideDownloadProgress()
            return
        }
        
        // Проверить статус загрузки
        val context = requireContext()
        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            ?: run {
                hideDownloadProgress()
                return
            }
        
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor: Cursor? = try {
            downloadManager.query(query)
        } catch (e: Exception) {
            hideDownloadProgress()
            return
        }
        
        if (cursor == null) {
            hideDownloadProgress()
            return
        }
        
        try {
            if (!cursor.moveToFirst()) {
                hideDownloadProgress()
                return
            }
            
            val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            if (statusIndex == -1) {
                hideDownloadProgress()
                return
            }
            
            val status = cursor.getInt(statusIndex)
            when (status) {
                DownloadManager.STATUS_RUNNING -> {
                    // Загрузка идет - показать прогресс-бар и начать отслеживание
                    showDownloadProgress()
                    startDownloadProgressTracking(downloadId)
                }
                DownloadManager.STATUS_PENDING -> {
                    // Загрузка ожидает - показать прогресс-бар
                    showDownloadProgress()
                    startDownloadProgressTracking(downloadId)
                }
                DownloadManager.STATUS_SUCCESSFUL,
                DownloadManager.STATUS_FAILED -> {
                    // Загрузка завершена или провалилась - скрыть прогресс-бар
                    hideDownloadProgress()
                    prefs.lastUpdateDownloadId = -1
                }
                else -> {
                    hideDownloadProgress()
                }
            }
        } catch (e: Exception) {
            hideDownloadProgress()
        } finally {
            cursor.close()
        }
    }
    
    /**
     * Начать отслеживание прогресса загрузки
     */
    private fun startDownloadProgressTracking(downloadId: Long) {
        stopDownloadProgressTracking() // Остановить предыдущее отслеживание, если есть
        
        downloadProgressHandler = Handler(Looper.getMainLooper())
        downloadProgressRunnable = object : Runnable {
            override fun run() {
                if (!isAdded || _binding == null) {
                    stopDownloadProgressTracking()
                    return
                }
                
                val context = requireContext()
                val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
                    ?: run {
                        stopDownloadProgressTracking()
                        return
                    }
                
                val query = DownloadManager.Query().setFilterById(downloadId)
                val cursor: Cursor? = try {
                    downloadManager.query(query)
                } catch (e: Exception) {
                    stopDownloadProgressTracking()
                    return
                }
                
                if (cursor == null) {
                    stopDownloadProgressTracking()
                    return
                }
                
                try {
                    if (!cursor.moveToFirst()) {
                        stopDownloadProgressTracking()
                        return
                    }
                    
                    val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                    val bytesIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                    val totalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                    
                    if (statusIndex == -1) {
                        stopDownloadProgressTracking()
                        return
                    }
                    
                    val status = cursor.getInt(statusIndex)
                    when (status) {
                        DownloadManager.STATUS_RUNNING -> {
                            // Загрузка идет - обновить прогресс
                            val bytesDownloaded = if (bytesIndex != -1) cursor.getLong(bytesIndex) else 0L
                            val totalSize = if (totalIndex != -1) cursor.getLong(totalIndex) else 0L
                            
                            updateDownloadProgress(bytesDownloaded, totalSize)
                            
                            // Продолжить отслеживание через 500ms
                            downloadProgressHandler?.postDelayed(this, 500)
                        }
                        DownloadManager.STATUS_SUCCESSFUL,
                        DownloadManager.STATUS_FAILED -> {
                            // Загрузка завершена - остановить отслеживание
                            hideDownloadProgress()
                            prefs.lastUpdateDownloadId = -1
                            stopDownloadProgressTracking()
                        }
                        else -> {
                            // Другие статусы - продолжить отслеживание
                            downloadProgressHandler?.postDelayed(this, 1000)
                        }
                    }
                } catch (e: Exception) {
                    stopDownloadProgressTracking()
                } finally {
                    cursor.close()
                }
            }
        }
        
        downloadProgressHandler?.post(downloadProgressRunnable!!)
    }
    
    /**
     * Остановить отслеживание прогресса загрузки
     */
    private fun stopDownloadProgressTracking() {
        downloadProgressHandler?.removeCallbacksAndMessages(null)
        downloadProgressRunnable = null
        downloadProgressHandler = null
    }
    
    /**
     * Показать прогресс-бар загрузки
     */
    private fun showDownloadProgress() {
        if (!isAdded || _binding == null) return
        
        val container = settingsBinding.downloadProgressContainer
        container?.visibility = View.VISIBLE
    }
    
    /**
     * Скрыть прогресс-бар загрузки
     */
    private fun hideDownloadProgress() {
        if (!isAdded || _binding == null) return
        
        val container = settingsBinding.downloadProgressContainer
        container?.visibility = View.GONE
        
        val progressBar = settingsBinding.downloadProgressBar
        val progressText = settingsBinding.downloadProgressText
        val progressPercent = settingsBinding.downloadProgressPercent
        
        progressBar?.progress = 0
        progressText?.text = "Скачивание обновления..."
        progressPercent?.text = "0%"
    }
    
    /**
     * Обновить прогресс загрузки
     */
    private fun updateDownloadProgress(bytesDownloaded: Long, totalSize: Long) {
        if (!isAdded || _binding == null) return
        
        val progressBar = settingsBinding.downloadProgressBar
        val progressText = settingsBinding.downloadProgressText
        val progressPercent = settingsBinding.downloadProgressPercent
        
        if (totalSize > 0 && bytesDownloaded >= 0) {
            val progress = ((bytesDownloaded * 100) / totalSize).toInt().coerceIn(0, 100)
            
            progressBar?.progress = progress
            progressPercent?.text = "$progress%"
            
            // Форматировать размеры
            val downloadedMB = String.format("%.1f", bytesDownloaded / (1024.0 * 1024.0))
            val totalMB = String.format("%.1f", totalSize / (1024.0 * 1024.0))
            progressText?.text = "Скачивание обновления: $downloadedMB / $totalMB МБ"
        } else {
            // Размер неизвестен - показать indeterminate progress
            progressBar?.progress = 0
            progressPercent?.text = ""
            progressText?.text = "Скачивание обновления..."
        }
    }
}
