package com.example.raspisanie

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
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
        setupInstituteSelection()
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
        binding.selectedGroupName.text = if (prefs.isGroupSelected()) prefs.selectedGroupName else getString(R.string.no_group_selected)

        val groupsParser = GroupsListParser()
        val spinner = binding.groupSpinner
        val favButton = binding.btnToggleFavorite
        var suppressGroupSpinnerCallback = false

        lifecycleScope.launch {
            try {
                val (groupsListUrl, _) = getInstituteUrls(prefs.institute)
                if (groupsListUrl.isEmpty()) {
                    spinner.isEnabled = false
                    binding.selectedGroupName.text = getString(R.string.no_group_selected)
                    return@launch
                }

                val groups = groupsParser.fetchGroupsList(groupsListUrl)

                fun updateFavButtonState() {
                    val file = prefs.selectedGroupFile
                    val isFav = file.isNotEmpty() && prefs.isFavorite(prefs.institute, file)
                    favButton.text = if (isFav) "★" else "☆"
                }

                fun buildItems(): Pair<List<String>, Map<String, String>> {
                    val allNames = groups.map { it.name }
                    val favorites = prefs.getFavoriteGroups(prefs.institute).filter { fg -> allNames.contains(fg.name) }
                    val favNames = favorites.map { "★ " + it.name }
                    val others = allNames.filter { n -> favorites.none { it.name == n } }.sorted()
                    val items = mutableListOf(getString(R.string.no_group_selected)).apply {
                        addAll(favNames)
                        addAll(others)
                    }
                    // map label -> pure name
                    val map = (favNames.map { it to it.removePrefix("★ ") } + others.map { it to it }).toMap()
                    return items to map
                }

                fun applyAdapterAndSelection() {
                    val (items, labelToName) = buildItems()
                    val adapter = ArrayAdapter(this@SettingsActivity, android.R.layout.simple_spinner_item, items).apply {
                        setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
                    }
                    spinner.adapter = adapter
                    val current = prefs.selectedGroupName
                    val currentLabel = if (current.isNotEmpty() && items.contains("★ $current")) "★ $current" else current
                    val idx = items.indexOf(currentLabel).let { if (it >= 0) it else 0 }
                    suppressGroupSpinnerCallback = true
                    spinner.setSelection(idx)
                    suppressGroupSpinnerCallback = false

                    spinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                        override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                            if (suppressGroupSpinnerCallback) return
                            val selectedLabel = items[position]
                            if (position == 0) {
                                if (prefs.isGroupSelected()) {
                                    prefs.selectedGroupName = ""
                                    prefs.selectedGroupFile = ""
                                    binding.selectedGroupName.text = getString(R.string.no_group_selected)
                                    Toast.makeText(this@SettingsActivity, "Группа не выбрана", Toast.LENGTH_SHORT).show()
                                    setResult(RESULT_OK)
                                    updateFavButtonState()
                                }
                            } else {
                                val pureName = labelToName[selectedLabel] ?: selectedLabel
                                val selectedGroup = groups.firstOrNull { it.name == pureName }
                                if (selectedGroup != null) {
                                    val wasChanged = selectedGroup.fileName != prefs.selectedGroupFile
                                    prefs.selectedGroupName = selectedGroup.name
                                    prefs.selectedGroupFile = selectedGroup.fileName
                                    binding.selectedGroupName.text = selectedGroup.name
                                    if (wasChanged) {
                                        Toast.makeText(this@SettingsActivity, "Группа изменена: ${selectedGroup.name}", Toast.LENGTH_SHORT).show()
                                    }
                                    setResult(RESULT_OK)
                                    updateFavButtonState()
                                }
                            }
                        }
                        override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
                    }
                }

                applyAdapterAndSelection()
                updateFavButtonState()

                favButton.setOnClickListener {
                    val file = prefs.selectedGroupFile
                    val name = prefs.selectedGroupName
                    if (file.isNotEmpty() && name.isNotEmpty()) {
                        if (prefs.isFavorite(prefs.institute, file)) {
                            prefs.removeFavorite(prefs.institute, file)
                        } else {
                            prefs.addFavorite(prefs.institute, file, name)
                        }
                        applyAdapterAndSelection()
                        updateFavButtonState()
                    } else {
                        Toast.makeText(this@SettingsActivity, "Сначала выберите группу", Toast.LENGTH_SHORT).show()
                    }
                }
            } catch (e: Exception) {
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

    private fun setupInstituteSelection() {
        val spinner = binding.instituteSpinner
        val label = binding.selectedInstituteName
        val items = listOf("ЧТОТиБ", "ЗабГК")
        val keys = listOf(PreferencesManager.INSTITUTE_CHTOTIB, PreferencesManager.INSTITUTE_ZABGK)

        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            items
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }

        spinner.adapter = adapter
        val currentIndex = keys.indexOf(prefs.institute).coerceAtLeast(0)
        spinner.setSelection(currentIndex)
        label.text = items[currentIndex]

        spinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                val newKey = keys[position]
                if (newKey != prefs.institute) {
                    prefs.institute = newKey
                    label.text = items[position]
                    // Сбросить выбранную группу при смене техникума
                    prefs.selectedGroupName = ""
                    prefs.selectedGroupFile = ""
                    binding.selectedGroupName.text = getString(R.string.no_group_selected)
                    // Перезагрузить список групп
                    setupGroupSelection()
                    setResult(RESULT_OK)
                }
            }
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
    }

    private fun getInstituteUrls(institute: String): Pair<String, String> {
        return when (institute) {
            PreferencesManager.INSTITUTE_CHTOTIB -> "https://www.chtotib.ru/schedule_gl/cg.htm" to "https://www.chtotib.ru/schedule_gl/"
            PreferencesManager.INSTITUTE_ZABGK -> "https://bbb.zabgc.ru/cg.htm" to "https://bbb.zabgc.ru/"
            else -> "https://www.chtotib.ru/schedule_gl/cg.htm" to "https://www.chtotib.ru/schedule_gl/"
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
            "Хеллоуин",
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
        
        // Press animation (micro-scale)
        cardView.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> v.animate().scaleX(0.98f).scaleY(0.98f).setDuration(80).start()
                android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> v.animate().scaleX(1f).scaleY(1f).setDuration(80).start()
            }
            false
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

