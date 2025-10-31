package com.example.raspisanie

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.example.raspisanie.data.Group
import com.example.raspisanie.data.GroupsListParser
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.databinding.ActivitySettingsBinding
import kotlinx.coroutines.launch

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding
    private lateinit var prefs: PreferencesManager
    private var savedScrollPosition: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        prefs = PreferencesManager(this)
        applyTheme(prefs.theme)
        
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        prefs = PreferencesManager(this)
        
        setupToolbar()
        setupSwitches()
        setupCollegeSelection()
        setupGroupSelection()
        setupThemeSelection()
        applyNothingFontIfNeeded()
        
        // Restore scroll position after layout
        if (savedScrollPosition > 0) {
            binding.root.post {
                val scrollView = binding.root.findViewById<androidx.core.widget.NestedScrollView>(R.id.nestedScrollView)
                scrollView?.scrollTo(0, savedScrollPosition)
                savedScrollPosition = 0 // Reset after restore
            }
        }
    }
    
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Save scroll position if NestedScrollView exists
        val scrollView = findViewById<androidx.core.widget.NestedScrollView>(R.id.nestedScrollView)
        scrollView?.let {
            outState.putInt("scroll_position", it.scrollY)
        }
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
                binding.root.post {
                    applyFontRecursive(binding.root, ndotFont)
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

    private fun setupToolbar() {
        binding.toolbar.setNavigationOnClickListener {
            finish()
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
                
                // Сначала избранные, потом обычные
                val sortedGroups = favoriteGroups + regularGroups
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
                val currentIndex = groupNames.indexOf(prefs.selectedGroupName)
                if (currentIndex >= 0) {
                    spinner.setSelection(currentIndex)
                }
                
                // Обработчик выбора группы
                spinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                    override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                        val selectedGroup = sortedGroups[position]
                        val wasChanged = selectedGroup.fileName != prefs.selectedGroupFile
                        
                        prefs.selectedGroupName = selectedGroup.name
                        prefs.selectedGroupFile = selectedGroup.fileName
                        binding.selectedGroupName.text = selectedGroup.name
                        
                        // Обновить кнопку избранного
                        updateFavoriteButton(selectedGroup.name)
                        
                        if (wasChanged) {
                            setResult(RESULT_OK)
                            Toast.makeText(
                                this@SettingsActivity,
                                "Группа изменена: ${selectedGroup.name}",
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    }
                    
                    override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
                }
                
                // Настроить кнопку избранного
                setupFavoriteButton()
                
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
                
                // Перезагрузить список групп
                setupGroupSelection()
            }
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
        setupThemeCard(
            R.id.themeSystem,
            "Системная",
            "Автоматический выбор",
            R.drawable.theme_preview_system,
            PreferencesManager.THEME_SYSTEM,
            currentTheme == PreferencesManager.THEME_SYSTEM
        )
        
        setupThemeCard(
            R.id.themeLight,
            "Светлая",
            "Яркий белый фон",
            R.drawable.theme_preview_light,
            PreferencesManager.THEME_LIGHT,
            currentTheme == PreferencesManager.THEME_LIGHT
        )
        
        setupThemeCard(
            R.id.themeDark,
            "Темная",
            "Черный фон",
            R.drawable.theme_preview_dark,
            PreferencesManager.THEME_DARK,
            currentTheme == PreferencesManager.THEME_DARK
        )
        
        setupThemeCard(
            R.id.themeCustom,
            "Хэллоуин",
            "Оранжевый акцент хе-хе",
            R.drawable.theme_preview_custom,
            PreferencesManager.THEME_CUSTOM,
            currentTheme == PreferencesManager.THEME_CUSTOM
        )
        
        setupThemeCard(
            R.id.themeNothing,
            "Nothing theme",
            "Фирменный стиль Nothing",
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
            PreferencesManager.THEME_CUSTOM -> resources.getColor(R.color.custom_textColorPrimary, theme)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_textColorPrimary, theme)
            else -> {
                // For system theme, use TypedArray to get the attribute
                val typedArray = theme.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary))
                val color = typedArray.getColor(0, resources.getColor(R.color.textPrimary, theme))
                typedArray.recycle()
                color
            }
        }
        val textSecondaryColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_textColorSecondary, theme)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_textColorSecondary, theme)
            PreferencesManager.THEME_CUSTOM -> resources.getColor(R.color.custom_textColorSecondary, theme)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_textColorSecondary, theme)
            else -> {
                // For system theme, use TypedArray to get the attribute
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
        }
        
        // Set click listener - use cardView as main target
        cardView.setOnClickListener {
            // Save scroll position before recreate
            val scrollView = findViewById<androidx.core.widget.NestedScrollView>(R.id.nestedScrollView)
            scrollView?.let {
                savedScrollPosition = it.scrollY
            }
            
            // Deselect all
            deselectAllThemes()
            
            // Select this one
            root.isSelected = true
            indicator?.isSelected = true
            
            // Save theme
            prefs.theme = themeKey
            
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
            R.id.themeSystem,
            R.id.themeLight,
            R.id.themeDark,
            R.id.themeCustom,
            R.id.themeNothing
        ).forEach { id ->
            val cardView = findViewById<androidx.cardview.widget.CardView>(id) ?: return@forEach
            val root = cardView.getChildAt(0) as? androidx.constraintlayout.widget.ConstraintLayout
            root?.isSelected = false
            root?.findViewById<android.view.View>(R.id.radioIndicator)?.isSelected = false
        }
    }

    private fun applyTheme(themeKey: String) {
        val themeResId = when (themeKey) {
            PreferencesManager.THEME_LIGHT -> R.style.Theme_Raspisanie_Light
            PreferencesManager.THEME_DARK -> R.style.Theme_Raspisanie_Dark
            PreferencesManager.THEME_CUSTOM -> R.style.Theme_Raspisanie_Custom
            PreferencesManager.THEME_NOTHING -> R.style.Theme_Raspisanie_Nothing
            PreferencesManager.THEME_SYSTEM -> {
                // System theme - автоматически переключается между Light и Dark
                val nightModeFlags = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
                if (nightModeFlags == android.content.res.Configuration.UI_MODE_NIGHT_YES) {
                    R.style.Theme_Raspisanie_Dark
                } else {
                    R.style.Theme_Raspisanie_Light
                }
            }
            else -> {
                // Fallback to system
                val nightModeFlags = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
                if (nightModeFlags == android.content.res.Configuration.UI_MODE_NIGHT_YES) {
                    R.style.Theme_Raspisanie_Dark
                } else {
                    R.style.Theme_Raspisanie_Light
                }
            }
        }
        setTheme(themeResId)
    }
}

