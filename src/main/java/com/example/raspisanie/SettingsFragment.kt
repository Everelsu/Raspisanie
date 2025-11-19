package com.example.raspisanie

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams
import android.widget.ArrayAdapter
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.content.res.AppCompatResources
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.example.raspisanie.data.AppUpdateChecker
import com.example.raspisanie.data.AppUpdateManager
import com.example.raspisanie.data.AppVersionInfo
import com.example.raspisanie.data.Group
import com.example.raspisanie.data.GroupsListParser
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleNotificationManager
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
        
        // Инициализируем настройки
        setupSwitches()
        setupAdditionalSettings()
        setupCollegeSelection()
        setupGroupSelection()
        setupFavoriteButton()
        setupThemeSelection()
        setupAppAutoUpdate()
        setupAppInfo()
        applyNothingFontIfNeeded()
        // Restore scroll position after layout
        if (savedScrollPosition > 0) {
            settingsBinding.nestedScrollView.post {
                settingsBinding.nestedScrollView.scrollTo(0, savedScrollPosition)
                savedScrollPosition = 0
            }
        }
    }

    private fun showNotificationSettingsDialog() {
        val context = requireContext()
        val dialogView = LayoutInflater.from(context).inflate(R.layout.dialog_notification_settings, null)
        val switchNotifications = dialogView.findViewById<MaterialSwitch>(R.id.switchNotifications)
        val switchBreaks = dialogView.findViewById<MaterialSwitch>(R.id.switchBreaks)
        val switchLunch = dialogView.findViewById<MaterialSwitch>(R.id.switchLunch)
        val radioGroup = dialogView.findViewById<RadioGroup>(R.id.radioGroupOffsets)

        val scheduleNotificationsEnabled = prefs.scheduleNotificationsEnabled
        switchNotifications.isChecked = prefs.upcomingNotificationsEnabled && scheduleNotificationsEnabled
        switchBreaks.isChecked = prefs.upcomingBreakRemindersEnabled
        switchLunch.isChecked = prefs.upcomingLunchRemindersEnabled
        selectOffsetRadio(radioGroup, prefs.upcomingLessonOffsetMinutes)

        if (!scheduleNotificationsEnabled) {
            switchNotifications.isEnabled = false
        }

        updateNotificationControlsEnabled(
            switchNotifications.isChecked && scheduleNotificationsEnabled,
            radioGroup,
            switchBreaks,
            switchLunch
        )

        switchNotifications.setOnCheckedChangeListener { _, isChecked ->
            updateNotificationControlsEnabled(isChecked, radioGroup, switchBreaks, switchLunch)
        }

        MaterialAlertDialogBuilder(context)
            .setTitle(R.string.notification_settings_title)
            .setView(dialogView)
            .setPositiveButton(R.string.notification_settings_save) { _, _ ->
                val enabled = switchNotifications.isChecked && scheduleNotificationsEnabled
                prefs.upcomingNotificationsEnabled = enabled

                if (enabled) {
                    val minutes = extractOffsetFromSelection(radioGroup)
                    prefs.upcomingLessonOffsetMinutes = minutes
                    prefs.upcomingBreakRemindersEnabled = switchBreaks.isChecked
                    prefs.upcomingLunchRemindersEnabled = switchLunch.isChecked
                    Toast.makeText(context, R.string.notification_settings_saved, Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(context, R.string.notification_settings_disabled, Toast.LENGTH_SHORT).show()
                }

                ScheduleNotificationManager.scheduleUpcomingEventNotifications(
                    context.applicationContext,
                    scheduleViewModel.schedule.value
                )
            }
            .setNegativeButton(R.string.notification_settings_cancel, null)
            .show()
    }

    private fun updateNotificationControlsEnabled(
        enabled: Boolean,
        radioGroup: RadioGroup,
        switchBreaks: MaterialSwitch,
        switchLunch: MaterialSwitch
    ) {
        for (i in 0 until radioGroup.childCount) {
            radioGroup.getChildAt(i).isEnabled = enabled
        }
        switchBreaks.isEnabled = enabled
        switchLunch.isEnabled = enabled
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
        savedScrollPosition = settingsBinding.nestedScrollView.scrollY
        outState.putInt("scroll_position", savedScrollPosition)
    }
    
    override fun onViewStateRestored(savedInstanceState: Bundle?) {
        super.onViewStateRestored(savedInstanceState)
        savedInstanceState?.getInt("scroll_position", 0)?.let {
            if (it > 0) {
                savedScrollPosition = it
            }
        }
    }
    
    private fun applyNothingFontIfNeeded() {
        if (prefs.theme == PreferencesManager.THEME_NOTHING) {
            try {
                val ndotFont = resources.getFont(R.font.ndot)
                settingsBinding.root.post {
                    applyFontRecursive(settingsBinding.root, ndotFont)
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
                
            } catch (e: Exception) {
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
        
        setupThemeCard(settingsBinding.root, R.id.themeDark, "Темная", "Черный фон", R.drawable.theme_preview_dark, PreferencesManager.THEME_DARK, currentTheme == PreferencesManager.THEME_DARK)
        setupThemeCard(settingsBinding.root, R.id.themeLight, "Светлая", "Яркий белый фон", R.drawable.theme_preview_light, PreferencesManager.THEME_LIGHT, currentTheme == PreferencesManager.THEME_LIGHT)
        setupThemeCard(settingsBinding.root, R.id.themeFiolet, "Фиолетовая", "ФиолетовАААЯ тема", R.drawable.theme_preview_system, PreferencesManager.THEME_PURPLE, currentTheme == PreferencesManager.THEME_PURPLE)
        setupThemeCard(settingsBinding.root, R.id.themeCustom, "Хэллоуин", "Оранжевый акцент хе-хе", R.drawable.theme_preview_custom, PreferencesManager.THEME_HALLOWEEN, currentTheme == PreferencesManager.THEME_HALLOWEEN)
        setupThemeCard(settingsBinding.root, R.id.themeGreen, "Зелёная", "Темная с зелёными акцентами", R.drawable.theme_preview_green, PreferencesManager.THEME_GREEN, currentTheme == PreferencesManager.THEME_GREEN)
        setupThemeCard(settingsBinding.root, R.id.themeNewYear, "Новогодняя", "Красный, белый, зелёный со снегом", R.drawable.theme_preview_newyear, PreferencesManager.THEME_NEW_YEAR, currentTheme == PreferencesManager.THEME_NEW_YEAR)
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
        
        preview?.background = resources.getDrawable(previewDrawable, null)
        nameView?.text = name
        descView?.text = description
        
        val textPrimaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_textColorPrimary, null)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_textColorPrimary, null)
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
            savedScrollPosition = settingsBinding.nestedScrollView.scrollY
            prefs.theme = themeKey
            (activity as? AppCompatActivity)?.recreate()
        }
        
        root.setOnClickListener {
            cardView.performClick()
        }
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
        val textView = TextView(context).apply {
            setPadding(48, 32, 48, 32)
            textSize = 14f
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
        
        val builder = MaterialAlertDialogBuilder(context)
            .setTitle("Доступно обновление")
            .setView(scrollView)
            .setPositiveButton("Обновить") { _, _ ->
                if (versionInfo.downloadUrl != null) {
                    AppUpdateManager.downloadAndInstall(context, versionInfo.downloadUrl, versionInfo.versionName)
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
        
        // Установить имя второго разработчика
        val developer2Name = settingsContent.findViewById<TextView>(R.id.developer2Name)
        developer2Name?.text = getString(R.string.developer_2)
        
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
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
