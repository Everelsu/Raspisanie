package com.example.raspisanie

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.example.raspisanie.data.AppUpdateChecker
import com.example.raspisanie.data.AppUpdateManager
import com.example.raspisanie.data.AppVersionInfo
import com.example.raspisanie.data.Group
import com.example.raspisanie.data.GroupsListParser
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.databinding.ActivitySettingsBinding
import kotlinx.coroutines.launch

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding
    private lateinit var prefs: PreferencesManager
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
        prefs = PreferencesManager(this)
        applyTheme(prefs.theme)
        
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.toolbar.title = getString(R.string.settings_title)
        
        // Долгое нажатие на toolbar - скролл вверх (как в Telegram)
        binding.toolbar.setOnLongClickListener {
            binding.nestedScrollView.smoothScrollTo(0, 0)
            // Haptic feedback
            binding.toolbar.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            true
        }

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        prefs = PreferencesManager(this)
        
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
            binding.root.post {
                binding.nestedScrollView.scrollTo(0, savedScrollPosition)
                savedScrollPosition = 0 // Reset after restore
            }
        }
    }
    
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Save scroll position if NestedScrollView exists
        outState.putInt("scroll_position", binding.nestedScrollView.scrollY)
    }
    
    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        savedInstanceState.getInt("scroll_position", 0).let {
            if (it > 0) {
                savedScrollPosition = it
            }
        }
    }
    
    private fun applyNothingFontIfNeeded() {
        if (prefs.theme == PreferencesManager.THEME_NOTHING) {
            try {
                val ndotFont = resources.getFont(R.font.ndot)
                binding.nestedScrollView.post {
                    applyFontRecursive(binding.nestedScrollView, ndotFont)
                }
            } catch (e: Exception) {
                // Fallback
            }
        }
    }
    
    private fun applyFontRecursive(view: android.view.View, font: android.graphics.Typeface) {
        when (view) {
            is android.widget.TextView -> {
                view.typeface = font
            }
            is android.view.ViewGroup -> {
                for (i in 0 until view.childCount) {
                    applyFontRecursive(view.getChildAt(i), font)
                }
            }
        }
    }


    private fun setupCollegeSelection() {
        val colleges = listOf(
            "ЧТОТиБ" to PreferencesManager.COLLEGE_CHTOTIB,
            "ЗабГК" to PreferencesManager.COLLEGE_ZABGC
        )
        
        val collegeNames = colleges.map { it.first }
        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            collegeNames
        ).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        
        binding.collegeSpinner.adapter = adapter
        
        // Выбрать текущий техникум
        val currentIndex = colleges.indexOfFirst { it.second == prefs.college }
        if (currentIndex >= 0) {
            binding.collegeSpinner.setSelection(currentIndex)
        }
        
        // Обработчик выбора
        binding.collegeSpinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                val selectedCollege = colleges[position].second
                if (selectedCollege != prefs.college) {
                    prefs.college = selectedCollege
                    // Сбросить выбранную группу при смене техникума
                    prefs.selectedGroupName = ""
                    prefs.selectedGroupFile = ""
                    // Перезагрузить список групп
                    setupGroupSelection()
                    setResult(RESULT_OK)
                    Toast.makeText(this@SettingsActivity, "Выбран техникум: ${colleges[position].first}", Toast.LENGTH_SHORT).show()
                }
            }
            
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
    }

    private fun setupSwitches() {
        binding.switchShowBreaks.isChecked = prefs.showBreaks
        binding.switchShowLunch.isChecked = prefs.showLunch
        binding.switchShowTime.isChecked = prefs.showTime
        binding.switchShowProgressLine.isChecked = prefs.showProgressLine

        binding.switchShowBreaks.setOnCheckedChangeListener { _, isChecked ->
            prefs.showBreaks = isChecked
        }

        binding.switchShowLunch.setOnCheckedChangeListener { _, isChecked ->
            prefs.showLunch = isChecked
        }

        binding.switchShowTime.setOnCheckedChangeListener { _, isChecked ->
            prefs.showTime = isChecked
        }

        binding.switchShowProgressLine.setOnCheckedChangeListener { _, isChecked ->
            prefs.showProgressLine = isChecked
            // Перезагрузить активити для применения изменений
            setResult(RESULT_OK)
        }
    }
    
    private fun setupAdditionalSettings() {
        // Auto refresh
        binding.switchAutoRefresh.isChecked = prefs.autoRefreshEnabled
        binding.switchAutoRefresh.setOnCheckedChangeListener { _, isChecked ->
            prefs.autoRefreshEnabled = isChecked
            binding.spinnerRefreshInterval.isEnabled = isChecked
            
            // Update auto refresh
            if (isChecked) {
                com.example.raspisanie.data.AutoRefreshManager.setupAutoRefresh(this)
            } else {
                com.example.raspisanie.data.AutoRefreshManager.cancelAutoRefresh(this)
            }
        }
        
        // Refresh interval spinner
        val intervals = listOf(
            "15 минут" to PreferencesManager.REFRESH_INTERVAL_15,
            "30 минут" to PreferencesManager.REFRESH_INTERVAL_30,
            "1 час" to PreferencesManager.REFRESH_INTERVAL_60,
            "2 часа" to PreferencesManager.REFRESH_INTERVAL_120
        )
        val intervalNames = intervals.map { it.first }
        val intervalAdapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            intervalNames
        ).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        binding.spinnerRefreshInterval.adapter = intervalAdapter
        binding.spinnerRefreshInterval.isEnabled = prefs.autoRefreshEnabled
        
        val currentIntervalIndex = intervals.indexOfFirst { it.second == prefs.autoRefreshInterval }
        if (currentIntervalIndex >= 0) {
            binding.spinnerRefreshInterval.setSelection(currentIntervalIndex)
        }
        
        binding.spinnerRefreshInterval.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                val selectedInterval = intervals[position].second
                prefs.autoRefreshInterval = selectedInterval
                if (prefs.autoRefreshEnabled) {
                    com.example.raspisanie.data.AutoRefreshManager.setupAutoRefresh(this@SettingsActivity)
                }
            }
            
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
        
        // Cache
        binding.switchCache.isChecked = prefs.cacheEnabled
        binding.switchCache.setOnCheckedChangeListener { _, isChecked ->
            prefs.cacheEnabled = isChecked
        }
        
        // Font size with SeekBar
        val fontSizes = listOf(
            PreferencesManager.FONT_SIZE_SMALL,
            PreferencesManager.FONT_SIZE_NORMAL,
            PreferencesManager.FONT_SIZE_LARGE,
            PreferencesManager.FONT_SIZE_EXTRA_LARGE
        )
        val fontSizeLabels = listOf("Мелкий", "Обычный", "Крупный", "Очень крупный")
        
        // Set initial progress based on current font size
        val currentFontSizeIndex = fontSizes.indexOfFirst { it == prefs.fontSize }.coerceAtLeast(0).coerceAtMost(3)
        binding.seekBarFontSize.progress = currentFontSizeIndex
        binding.fontSizeValue.text = fontSizeLabels[currentFontSizeIndex]
        
        // Update font size label and value when SeekBar changes
        binding.seekBarFontSize.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser && progress in 0..3) {
                    val selectedFontSize = fontSizes[progress]
                    binding.fontSizeValue.text = fontSizeLabels[progress]
                    prefs.fontSize = selectedFontSize
                    setResult(RESULT_OK)
                }
            }
            
            override fun onStartTrackingTouch(seekBar: android.widget.SeekBar?) {}
            
            override fun onStopTrackingTouch(seekBar: android.widget.SeekBar?) {}
        })
        
    }

    private fun setupGroupSelection() {
        // Показать текущую выбранную группу или "Не выбрано"
        binding.selectedGroupName.text = if (prefs.isGroupSelected()) {
            prefs.selectedGroupName
        } else {
            getString(R.string.no_group_selected)
        }
        
        // Загрузить список групп асинхронно
        val groupsParser = GroupsListParser()
        val spinner = binding.groupSpinner
        
        lifecycleScope.launch {
            try {
                val groups = groupsParser.fetchGroupsList(prefs.college)
                val favorites = prefs.getFavoriteGroups()
                
                // Разделить на избранные и обычные
                val favoriteGroups = mutableListOf<Group>()
                val regularGroups = mutableListOf<Group>()
                
                for (group in groups.sortedBy { it.name }) {
                    if (favorites.contains(group.name)) {
                        favoriteGroups.add(group)
                    } else {
                        regularGroups.add(group)
                    }
                }
                
                // Сначала "Не выбрано", потом избранные, потом обычные
                val noGroupSelected = Group(
                    name = getString(R.string.no_group_selected),
                    url = "",
                    fileName = ""
                )
                val sortedGroups = listOf(noGroupSelected) + favoriteGroups + regularGroups
                val groupNames = sortedGroups.map { it.name }
                
                val adapter = ArrayAdapter(
                    this@SettingsActivity,
                    android.R.layout.simple_spinner_item,
                    groupNames
                ).apply {
                    setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
                }
                
                spinner.adapter = adapter
                
                // Выбрать текущую группу в списке
                val currentIndex = if (prefs.isGroupSelected()) {
                    groupNames.indexOf(prefs.selectedGroupName)
                } else {
                    0 // "Не выбрано" по умолчанию
                }
                if (currentIndex >= 0) {
                    spinner.setSelection(currentIndex)
                }
                
                // Обработчик выбора группы
                spinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                    override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                        val selectedGroup = sortedGroups[position]
                        val wasChanged = selectedGroup.fileName != prefs.selectedGroupFile
                        
                        if (selectedGroup.fileName.isEmpty()) {
                            // "Не выбрано" - очистить выбранную группу
                            prefs.selectedGroupName = ""
                            prefs.selectedGroupFile = ""
                            binding.selectedGroupName.text = getString(R.string.no_group_selected)
                        } else {
                            prefs.selectedGroupName = selectedGroup.name
                            prefs.selectedGroupFile = selectedGroup.fileName
                            binding.selectedGroupName.text = selectedGroup.name
                        }
                        
                        // Обновить кнопку избранного
                        updateFavoriteButton(selectedGroup.name)
                        
                        if (wasChanged) {
                            setResult(RESULT_OK)
                            val message = if (selectedGroup.fileName.isEmpty()) {
                                "Группа не выбрана"
                            } else {
                                "Группа изменена: ${selectedGroup.name}"
                            }
                            Toast.makeText(
                                this@SettingsActivity,
                                message,
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    }
                    
                    override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
                }
                
            } catch (e: Exception) {
                // Если не удалось загрузить список групп
                android.util.Log.e("SettingsActivity", "Ошибка загрузки групп", e)
                spinner.isEnabled = false
                binding.selectedGroupName.text = if (prefs.isGroupSelected()) {
                    "${prefs.selectedGroupName} (ошибка загрузки списка)"
                } else {
                    "${getString(R.string.no_group_selected)} (ошибка загрузки списка)"
                }
            }
        }
    }
    
    private fun setupFavoriteButton() {
        if (prefs.isGroupSelected()) {
            updateFavoriteButton(prefs.selectedGroupName)
        }
        
        if (!isFavoriteButtonSetup) {
            binding.btnAddToFavorites.setOnClickListener {
                if (prefs.isGroupSelected()) {
                    val groupName = prefs.selectedGroupName
                    val isFavorite = prefs.isFavoriteGroup(groupName)
                    
                    if (isFavorite) {
                        prefs.removeFavoriteGroup(groupName)
                        Toast.makeText(this, "Удалено из избранного", Toast.LENGTH_SHORT).show()
                    } else {
                        prefs.addFavoriteGroup(groupName)
                        Toast.makeText(this, "Добавлено в избранное", Toast.LENGTH_SHORT).show()
                    }
                    
                    updateFavoriteButton(groupName)
                    
                    // Перезагрузить список групп
                    binding.selectedGroupName.text = prefs.selectedGroupName
                    setupGroupSelection()
                }
            }
            isFavoriteButtonSetup = true
        }
    }
    
    private fun updateFavoriteButton(groupName: String) {
        val isFavorite = prefs.isFavoriteGroup(groupName)
        binding.btnAddToFavorites.text = if (isFavorite) {
            "⭐ В избранном"
        } else {
            "⭐ Добавить в избранное"
        }
    }

    private fun setupThemeSelection() {
        val currentTheme = prefs.theme
        
        // Setup all theme cards
        // Row 1: Dark & Light
        setupThemeCard(
            R.id.themeDark,
            "Темная",
            "Черный фон",
            R.drawable.theme_preview_dark,
            PreferencesManager.THEME_DARK,
            currentTheme == PreferencesManager.THEME_DARK
        )
        
        setupThemeCard(
            R.id.themeLight,
            "Светлая",
            "Яркий белый фон(блять)",
            R.drawable.theme_preview_light,
            PreferencesManager.THEME_LIGHT,
            currentTheme == PreferencesManager.THEME_LIGHT
        )
        
        // Row 2: Purple & Halloween
        setupThemeCard(
            R.id.themeFiolet,
            "Фиолетовая",
            "ФиолетовАААЯ тема",
            R.drawable.theme_preview_system,
            PreferencesManager.THEME_PURPLE,
            currentTheme == PreferencesManager.THEME_PURPLE
        )
        
        setupThemeCard(
            R.id.themeCustom,
            "Хэллоуин",
            "Оранжевый акцент хе-хе",
            R.drawable.theme_preview_custom,
            PreferencesManager.THEME_HALLOWEEN,
            currentTheme == PreferencesManager.THEME_HALLOWEEN
        )
        
        setupThemeCard(
            R.id.themeGreen,
            "Зелёная",
            "Темная с зелёными акцентами",
            R.drawable.theme_preview_green,
            PreferencesManager.THEME_GREEN,
            currentTheme == PreferencesManager.THEME_GREEN
        )
        
        setupThemeCard(
            R.id.themeNewYear,
            "Новогодняя",
            "Красный, белый, зелёный со снегом",
            R.drawable.theme_preview_newyear,
            PreferencesManager.THEME_NEW_YEAR,
            currentTheme == PreferencesManager.THEME_NEW_YEAR
        )

        setupThemeCard(
            R.id.themeBlue,
            "Синяя",
            "Темная с синими акцентами",
            R.drawable.theme_preview_blue,
            PreferencesManager.THEME_BLUE,
            currentTheme == PreferencesManager.THEME_BLUE
        )

        setupThemeCard(
            R.id.themeGray,
            "Серая",
            "Темная с серыми акцентами",
            R.drawable.theme_preview_gray,
            PreferencesManager.THEME_GRAY,
            currentTheme == PreferencesManager.THEME_GRAY
        )
        
        setupThemeCard(
            R.id.themeNothing,
            "RedDot",
            "Красный с NDot шрифтом",
            R.drawable.theme_preview_nothing,
            PreferencesManager.THEME_NOTHING,
            currentTheme == PreferencesManager.THEME_NOTHING
        )
    }
    
    private fun setupThemeCard(
        cardId: Int,
        name: String,
        description: String,
        previewDrawable: Int,
        themeKey: String,
        isSelected: Boolean
    ) {
        val cardView = findViewById<androidx.cardview.widget.CardView>(cardId) ?: return
        val root = cardView.getChildAt(0) as? androidx.constraintlayout.widget.ConstraintLayout ?: return
        
        val preview = root.findViewById<android.view.View>(R.id.themePreview)
        val nameView = root.findViewById<android.widget.TextView>(R.id.themeName)
        val descView = root.findViewById<android.widget.TextView>(R.id.themeDescription)
        val indicator = root.findViewById<android.view.View>(R.id.radioIndicator)
        
        preview?.background = resources.getDrawable(previewDrawable, theme)
        nameView?.text = name
        descView?.text = description
        
        // Ensure text colors are applied correctly based on theme
        val textPrimaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_textColorPrimary, theme)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_textColorPrimary, theme)
            PreferencesManager.THEME_BLUE -> resources.getColor(R.color.blue_textColorPrimary, theme)
            PreferencesManager.THEME_GRAY -> resources.getColor(R.color.gray_textColorPrimary, theme)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_textColorPrimary, theme)
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_textColorPrimary, theme)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_textColorPrimary, theme)
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_textColorPrimary, theme)
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_textColorPrimary, theme)
            else -> {
                // Fallback theme, use TypedArray to get the attribute
                val typedArray = theme.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary))
                val color = typedArray.getColor(0, resources.getColor(R.color.textPrimary, theme))
                typedArray.recycle()
                color
            }
        }
        val textSecondaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_textColorSecondary, theme)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_textColorSecondary, theme)
            PreferencesManager.THEME_BLUE -> resources.getColor(R.color.blue_textColorSecondary, theme)
            PreferencesManager.THEME_GRAY -> resources.getColor(R.color.gray_textColorSecondary, theme)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_textColorSecondary, theme)
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_textColorSecondary, theme)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_textColorSecondary, theme)
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_textColorSecondary, theme)
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_textColorSecondary, theme)
            else -> {
                // Fallback theme, use TypedArray to get the attribute
                val typedArray = theme.obtainStyledAttributes(intArrayOf(android.R.attr.textColorSecondary))
                val color = typedArray.getColor(0, resources.getColor(R.color.textSecondary, theme))
                typedArray.recycle()
                color
            }
        }
        nameView?.setTextColor(textPrimaryColor)
        descView?.setTextColor(textSecondaryColor)
        
        // Set selected state
        if (isSelected) {
            root.isSelected = true
            indicator?.isSelected = true
            root.refreshDrawableState()
            indicator?.refreshDrawableState()
        }
        
        // Set click listener - use cardView as main target
        cardView.setOnClickListener {
            // Save scroll position before recreate
            val scrollView = findViewById<androidx.core.widget.NestedScrollView>(R.id.nestedScrollView)
            scrollView?.let {
                savedScrollPosition = it.scrollY
            }
            
            // Save theme
            prefs.theme = themeKey
            
            // Widgets don't update automatically on theme change
            try {
                com.example.raspisanie.widget.WidgetUpdateHelper.updateAll(applicationContext)
            } catch (_: Exception) {
                // ignore
            }
            
            // Apply theme and recreate activity
            applyTheme(themeKey)
            recreate()
        }
        
        // Also make root clickable for better UX
        root.setOnClickListener {
            cardView.performClick()
        }
    }
    
    private fun deselectAllThemes() {
        listOf(
            R.id.themeDark,
            R.id.themeLight,
            R.id.themeFiolet,
            R.id.themeCustom,
            R.id.themeGreen,
            R.id.themeNewYear,
            R.id.themeNothing
        ).forEach { id ->
            val cardView = findViewById<androidx.cardview.widget.CardView>(id) ?: return@forEach
            val root = cardView.getChildAt(0) as? androidx.constraintlayout.widget.ConstraintLayout
            root?.isSelected = false
            root?.refreshDrawableState()
            val indicator = root?.findViewById<android.view.View>(R.id.radioIndicator)
            indicator?.isSelected = false
            indicator?.refreshDrawableState()
        }
    }

    private fun setupAppAutoUpdate() {
        val switchAppAutoUpdate = findViewById<com.google.android.material.switchmaterial.SwitchMaterial>(R.id.switchAppAutoUpdate)
        val btnCheckUpdates = findViewById<com.google.android.material.button.MaterialButton>(R.id.btnCheckUpdates)
        
        // Установить состояние переключателя
        switchAppAutoUpdate?.isChecked = prefs.appAutoUpdateEnabled
        
        // Обработчик переключателя
        switchAppAutoUpdate?.setOnCheckedChangeListener { _, isChecked ->
            prefs.appAutoUpdateEnabled = isChecked
            if (isChecked) {
                // Запустить периодическую проверку обновлений
                AppUpdateManager.setupAutoUpdateCheck(this)
            } else {
                // Отменить проверку обновлений
                AppUpdateManager.cancelAutoUpdateCheck(this)
            }
        }
        
        // Обработчик кнопки проверки обновлений
        btnCheckUpdates?.setOnClickListener {
            checkForUpdates()
        }
    }
    
    private fun checkForUpdates() {
        val btnCheckUpdates = findViewById<com.google.android.material.button.MaterialButton>(R.id.btnCheckUpdates)
        btnCheckUpdates?.isEnabled = false
        btnCheckUpdates?.text = "Проверка..."
        
        lifecycleScope.launch {
            try {
                val result = AppUpdateChecker.checkForUpdates(this@SettingsActivity)
                
                when (result) {
                    is AppUpdateChecker.UpdateCheckResult.UpdateAvailable -> {
                        // Показать диалог с предложением обновления
                        showUpdateDialog(result.versionInfo)
                        prefs.lastUpdateCheck = System.currentTimeMillis()
                    }
                    AppUpdateChecker.UpdateCheckResult.NoUpdate -> {
                        android.widget.Toast.makeText(
                            this@SettingsActivity,
                            "У вас установлена последняя версия",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                        prefs.lastUpdateCheck = System.currentTimeMillis()
                    }
                    is AppUpdateChecker.UpdateCheckResult.Error -> {
                        android.widget.Toast.makeText(
                            this@SettingsActivity,
                            "Ошибка проверки: ${result.message}",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            } catch (e: Exception) {
                android.widget.Toast.makeText(
                    this@SettingsActivity,
                    "Ошибка при проверке обновлений",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            } finally {
                btnCheckUpdates?.isEnabled = true
                btnCheckUpdates?.text = "Проверить обновления"
            }
        }
    }
    
    private fun showUpdateDialog(versionInfo: AppVersionInfo) {
        val context = this
        
        // Создаем кастомный layout для диалога
        val scrollView = android.widget.ScrollView(context).apply {
            layoutParams = android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        val fontSizeMultiplier = getFontSizeMultiplier()
        val textView = android.widget.TextView(context).apply {
            setPadding(48, 32, 48, 32)
            textSize = 14f * fontSizeMultiplier
            layoutParams = android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        scrollView.addView(textView)
        
        // Инициализируем Markwon с поддержкой изображений и ссылок
        val markwon = io.noties.markwon.Markwon.builder(context)
            .usePlugin(io.noties.markwon.image.glide.GlideImagesPlugin.create(context))
            .usePlugin(io.noties.markwon.linkify.LinkifyPlugin.create())
            .build()
        
        // Формируем текст для отображения
        val changelogText = versionInfo.changelog ?: "Обновления и улучшения"
        val fullText = "## Версия ${versionInfo.versionName}\n\n$changelogText"
        
        // Рендерим Markdown
        markwon.setMarkdown(textView, fullText)
        
        val builder = com.google.android.material.dialog.MaterialAlertDialogBuilder(context)
            .setTitle("Доступно обновление")
            .setView(scrollView)
            .setPositiveButton("Обновить") { _, _ ->
                // Запустить установку обновления
                if (versionInfo.downloadUrl != null) {
                    AppUpdateManager.downloadAndInstall(context, versionInfo.downloadUrl, versionInfo.versionName)
                } else {
                    android.widget.Toast.makeText(context, "Ссылка на скачивание недоступна", android.widget.Toast.LENGTH_SHORT).show()
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
        
        val shareIntent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(android.content.Intent.EXTRA_SUBJECT, "Обновление приложения Расписание")
            putExtra(android.content.Intent.EXTRA_TEXT, shareText)
        }
        
        val chooser = android.content.Intent.createChooser(shareIntent, "Поделиться обновлением")
        startActivity(chooser)
    }
    
    private fun setupAppInfo() {
        // Установить версию приложения
        try {
            val packageInfo = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            val versionName = packageInfo.versionName ?: "unknown"
            val versionText = findViewById<android.widget.TextView>(R.id.versionText)
            versionText?.text = getString(R.string.version_format, versionName)
        } catch (e: Exception) {
            // Если не удалось получить версию, оставляем дефолтный текст
        }
        
        // Установить имя автора
        val authorName = findViewById<android.widget.TextView>(R.id.authorName)
        authorName?.text = getString(R.string.author_name)
        
        // Установить обработчик клика на имя автора
        authorName?.setOnClickListener {
            openAuthorProfile()
        }
        
        // Установить имя бета-тестера
        val betaTesterName = findViewById<android.widget.TextView>(R.id.betaTesterName)
        betaTesterName?.text = getString(R.string.beta_tester_name)
        
        // Установить обработчик клика на кнопку патчнотов
        val changelogButton = findViewById<android.widget.TextView>(R.id.changelogButton)
        changelogButton?.setOnClickListener {
            openChangelog()
        }
        
        // Пасхалка: обработчик кликов на текст "Разработано"
        val authorText = findViewById<android.widget.TextView>(R.id.authorText)
        authorText?.setOnClickListener {
            handleEasterEggClick()
        }
    }
    
    private fun handleEasterEggClick() {
        val currentTime = System.currentTimeMillis()
        
        // Сброс счётчика, если прошло больше 5 секунд с последнего клика
        if (currentTime - lastClickTime > 5000) {
            easterEggClickCount = 0
        }
        
        lastClickTime = currentTime
        easterEggClickCount++
        
        // После 5 кликов показываем случайное имя
        if (easterEggClickCount >= 5) {
            val randomName = easterEggNames.random()
            val authorName = findViewById<android.widget.TextView>(R.id.authorName)
            val originalText = getString(R.string.author_name)
            
            // Показываем имя после @Relsev
            authorName?.text = "$originalText\n$randomName"
            
            // Сбрасываем счётчик
            easterEggClickCount = 0
            
            // Через 5 секунд возвращаем оригинальный текст
            authorName?.postDelayed({
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
            android.widget.Toast.makeText(this, getString(R.string.cannot_open_profile), android.widget.Toast.LENGTH_SHORT).show()
        }
    }
    
    private fun openChangelog() {
        val changelogUrl = getString(R.string.changelog_url)
        
        try {
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(changelogUrl))
            startActivity(intent)
        } catch (e: Exception) {
            android.widget.Toast.makeText(this, "Не удалось открыть патчноты", android.widget.Toast.LENGTH_SHORT).show()
        }
    }
    
    private fun applyTheme(themeKey: String) {
        val themeResId = when (themeKey) {
            PreferencesManager.THEME_LIGHT -> R.style.Theme_Raspisanie_Light
            PreferencesManager.THEME_DARK -> R.style.Theme_Raspisanie_Dark
            PreferencesManager.THEME_BLUE -> R.style.Theme_Raspisanie_Blue
            PreferencesManager.THEME_GRAY -> R.style.Theme_Raspisanie_Gray
            PreferencesManager.THEME_PURPLE -> R.style.Theme_Raspisanie_System
            PreferencesManager.THEME_HALLOWEEN -> R.style.Theme_Raspisanie_Custom
            PreferencesManager.THEME_NOTHING -> R.style.Theme_Raspisanie_Nothing
            PreferencesManager.THEME_GREEN -> R.style.Theme_Raspisanie_Green
            PreferencesManager.THEME_NEW_YEAR -> R.style.Theme_Raspisanie_NewYear
            else -> {
                // Fallback - просто фиолетовая тема
                R.style.Theme_Raspisanie_System
            }
        }
        setTheme(themeResId)
    }
    
    private fun getFontSizeMultiplier(): Float {
        return when (prefs.fontSize) {
            PreferencesManager.FONT_SIZE_SMALL -> 0.85f
            PreferencesManager.FONT_SIZE_NORMAL -> 1.0f
            PreferencesManager.FONT_SIZE_LARGE -> 1.15f
            PreferencesManager.FONT_SIZE_EXTRA_LARGE -> 1.3f
            else -> 1.0f
        }
    }
}

