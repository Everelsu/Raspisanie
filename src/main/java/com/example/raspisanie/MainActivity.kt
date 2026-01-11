package com.example.raspisanie

import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.util.Log
import android.content.pm.PackageManager
import android.Manifest
import android.view.View
import android.util.TypedValue
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.Fragment
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.util.AppIconManager
import com.example.raspisanie.databinding.ActivityMainBinding
import com.example.raspisanie.util.NotificationPermissionHelper
import com.google.firebase.messaging.FirebaseMessaging
import com.google.android.material.color.MaterialColors
import android.graphics.Color
import com.google.android.material.shape.ShapeAppearanceModel
import com.google.android.material.shape.CornerFamily

class MainActivity : AppCompatActivity() {
    companion object {
        private const val TAG = "MainActivity"
    }
    
    private lateinit var binding: ActivityMainBinding
    private lateinit var prefs: PreferencesManager
    private var currentThemeKey: String = ""
    private var bottomInset: Int = 0
    private var bottomNavBasePadding = intArrayOf(0, 0, 0, 0)
    private var fragmentContainerBasePadding = intArrayOf(0, 0, 0, 0)
    private var bottomNavActiveColor: Int = Color.WHITE
    private var currentFragmentId: Int = R.id.navigation_schedule // Текущий выбранный фрагмент
    private val SAVED_FRAGMENT_ID_KEY = "saved_fragment_id"

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            prefs = PreferencesManager(this)
            
            // Проверить первый запуск
            prefs.checkFirstLaunch()
            
            currentThemeKey = prefs.theme
            applyTheme(currentThemeKey)
            
            super.onCreate(savedInstanceState)
            
            // Убираем анимацию при пересоздании активити (например, при смене темы)
            overridePendingTransition(0, 0)
            
            enableEdgeToEdge()
            
            binding = ActivityMainBinding.inflate(layoutInflater)
            setContentView(binding.root)
            
            // Устанавливаем цвет текста в статус-баре в зависимости от темы
            setupStatusBarAppearance()
            
            maybeRequestNotificationPermission()
            initFirebaseMessaging()
            
            // Инициализация иконки приложения (как в Telegram)
            // Просто убеждаемся, что хотя бы один alias включен
            try {
                AppIconManager.ensureAtLeastOneEnabled(this)
                
                // Синхронизируем preferences с реальным состоянием
                val currentIcon = AppIconManager.getCurrentIcon(this)
                if (prefs.appIcon != currentIcon) {
                    prefs.appIcon = currentIcon
                    Log.d(TAG, "Синхронизировано: иконка = $currentIcon")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при инициализации иконки: ${e.message}", e)
            }
            bottomNavBasePadding = intArrayOf(
                binding.bottomNavigation.paddingLeft,
                binding.bottomNavigation.paddingTop,
                binding.bottomNavigation.paddingRight,
                binding.bottomNavigation.paddingBottom
            )
            fragmentContainerBasePadding = intArrayOf(
                binding.fragmentContainer.paddingLeft,
                binding.fragmentContainer.paddingTop,
                binding.fragmentContainer.paddingRight,
                binding.fragmentContainer.paddingBottom
            )
            
            Log.d(TAG, "MainActivity создана")

            ViewCompat.setOnApplyWindowInsetsListener(binding.root) { v, insets ->
                try {
                    val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                    v.setPadding(systemBars.left, systemBars.top, systemBars.right, 0)
                    bottomInset = systemBars.bottom
                    applyInsets()
                    insets
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при установке window insets: ${e.message}", e)
                    insets
                }
            }

            setupBottomNavigation()
            setupBottomNavigationAppearance()
            
            // Определяем, какой фрагмент показывать
            val fragmentIdToShow = if (savedInstanceState != null) {
                // Восстанавливаем из сохраненного состояния
                savedInstanceState.getInt(SAVED_FRAGMENT_ID_KEY, R.id.navigation_schedule)
            } else {
                // Первый запуск - показываем расписание
                R.id.navigation_schedule
            }
            
            // Устанавливаем фрагмент
            val fragment: Fragment = when (fragmentIdToShow) {
                R.id.navigation_statistics -> StatisticsFragment()
                R.id.navigation_settings -> SettingsFragment()
                else -> ScheduleFragment()
            }
            
            // Устанавливаем выбранный элемент в навигации ПЕРЕД установкой фрагмента
            // чтобы избежать конфликтов
            binding.bottomNavigation.selectedItemId = fragmentIdToShow
            currentFragmentId = fragmentIdToShow
            
            // Устанавливаем фрагмент после настройки навигации
            supportFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, fragment)
                .commitNow() // Используем commitNow для немедленного выполнения
            
            // Настроить снег после полной инициализации view
            binding.root.post {
                setupSnowfallEffect()
            }
            
            // Setup app auto-update check
            try {
                if (prefs.appAutoUpdateEnabled) {
                    com.example.raspisanie.data.AppUpdateManager.setupAutoUpdateCheck(this)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при настройке автообновления приложения: ${e.message}", e)
            }
            
            // Очистить старые APK файлы обновлений
            try {
                com.example.raspisanie.data.AppUpdateManager.cleanupOldApkFiles(this)
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при очистке старых APK: ${e.message}", e)
            }
            
            // Проверить обновления при запуске (фоново, без уведомления если версия актуальна)
            try {
                com.example.raspisanie.data.AppUpdateManager.checkForUpdatesOnStartup(this)
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при проверке обновлений: ${e.message}", e)
            }
            
            // Логика загрузки расписания теперь в ScheduleFragment
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка в onCreate: ${e.message}", e)
            // Ошибки теперь обрабатываются в ScheduleFragment
        }
    }
    
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Сохраняем текущий фрагмент перед recreate()
        outState.putInt(SAVED_FRAGMENT_ID_KEY, currentFragmentId)
    }
    
    override fun onResume() {
        super.onResume()
        
        try {
            if (!::prefs.isInitialized) {
                return
            }

            // Проверить изменение темы
            val savedTheme = prefs.theme
            if (savedTheme != currentThemeKey) {
                currentThemeKey = savedTheme
                try {
                    setupStatusBarAppearance()
                    // Сохраняем текущий фрагмент перед recreate()
                    // Это будет восстановлено в onCreate через onSaveInstanceState
                    // Убираем все анимации при переключении темы
                    overridePendingTransition(0, 0)
                    recreate()
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при recreate: ${e.message}", e)
                }
                return
            }
            
            setupBottomNavigationAppearance()
            setupSnowfallEffect()
        } catch (e: Exception) {
            Log.e(TAG, "Критическая ошибка в onResume: ${e.message}", e)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NotificationPermissionHelper.REQUEST_CODE_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Notification permission granted: $granted")
            if (::prefs.isInitialized) {
                prefs.scheduleNotificationsEnabled = granted
                if (granted) {
                    initFirebaseMessaging()
                }
            }
        }
    }

    private fun maybeRequestNotificationPermission() {
        if (!::prefs.isInitialized) return
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) {
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            if (!prefs.scheduleNotificationsEnabled) {
                prefs.scheduleNotificationsEnabled = true
            }
            return
        }

        if (prefs.scheduleNotificationsEnabled) {
            NotificationPermissionHelper.requestIfNeeded(this)
        }
    }

    private fun initFirebaseMessaging() {
        try {
            if (!prefs.scheduleNotificationsEnabled) {
                return
            }

            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    Log.e(TAG, "Failed to get FCM token", task.exception)
                    return@addOnCompleteListener
                }

                val token = task.result
                if (!token.isNullOrEmpty()) {
                    if (prefs.fcmToken != token) {
                        prefs.fcmToken = token
                    }
                    Log.d(TAG, "FCM token: $token")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "initFirebaseMessaging error: ${e.message}", e)
        }
    }


    private fun applyTheme(themeKey: String) {
        try {
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
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при применении темы: ${e.message}", e)
            // Применить тему по умолчанию
            try {
                setTheme(R.style.Theme_Raspisanie_System)
            } catch (e2: Exception) {
                Log.e(TAG, "Критическая ошибка при применении темы по умолчанию: ${e2.message}", e2)
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
    }
    
    override fun onPause() {
        super.onPause()
        // Остановить обновления виджетов для экономии ресурсов
        // Виджеты будут обновляться при необходимости через WorkManager
        // Остановить снег для экономии ресурсов
        try {
            binding.snowfallView.pause()
        } catch (e: Exception) {
            // Игнорируем ошибки, если view еще не инициализирован
        }
    }
    
    /**
     * Настроить эффект снега для новогодней темы (как в exteraGram)
     */
    private fun setupSnowfallEffect() {
        try {
            if (!::binding.isInitialized) return
            
            val isNewYearTheme = prefs.theme == PreferencesManager.THEME_NEW_YEAR
            
            // Используем post для гарантии, что view полностью инициализирован
            binding.snowfallView.post {
                if (isNewYearTheme) {
                    binding.snowfallView.visibility = View.VISIBLE
                    // Убеждаемся, что снежинки созданы
                    if (binding.snowfallView.width > 0 && binding.snowfallView.height > 0) {
                        binding.snowfallView.resume()
                    }
                } else {
                    binding.snowfallView.visibility = View.GONE
                    binding.snowfallView.pause()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при настройке снега: ${e.message}", e)
        }
    }
    
    private fun setupBottomNavigation() {
        binding.bottomNavigation.visibility = View.VISIBLE
        binding.bottomNavigation.setOnItemSelectedListener { item ->
            // Проверяем, не нажимаем ли мы на уже выбранный элемент
            // Но только если фрагмент действительно отображается и это тот же тип
            val currentFragment = supportFragmentManager.findFragmentById(R.id.fragmentContainer)
            
            // Проверяем, что это действительно тот же фрагмент по типу
            val isSameFragmentType = when {
                item.itemId == R.id.navigation_schedule -> currentFragment is ScheduleFragment
                item.itemId == R.id.navigation_statistics -> currentFragment is StatisticsFragment
                item.itemId == R.id.navigation_settings -> currentFragment is SettingsFragment
                else -> false
            }
            
            // Если это тот же фрагмент по типу И currentFragmentId совпадает - не переключаем
            if (isSameFragmentType && item.itemId == currentFragmentId && currentFragment != null) {
                return@setOnItemSelectedListener true
            }
            
            // Haptic feedback для лучшего UX (как в exteraGram)
            binding.bottomNavigation.performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
            
            // Прикольная анимация при нажатии на элемент навигации
            val menuView = binding.bottomNavigation.findViewById<View>(item.itemId)
            menuView?.let { view ->
                view.animate()
                    .scaleX(0.9f)
                    .scaleY(0.9f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(150)
                            .setInterpolator(android.view.animation.OvershootInterpolator(1.2f))
                            .start()
                    }
                    .start()
            }
            
            val fragment: Fragment = when (item.itemId) {
                R.id.navigation_schedule -> ScheduleFragment()
                R.id.navigation_statistics -> StatisticsFragment()
                R.id.navigation_settings -> SettingsFragment()
                else -> ScheduleFragment()
            }
            
            // Плавные переходы между фрагментами (как в Telegram)
            // Определяем направление навигации на основе порядка вкладок
            val isForward = when {
                currentFragmentId == R.id.navigation_schedule && item.itemId == R.id.navigation_statistics -> true
                currentFragmentId == R.id.navigation_statistics && item.itemId == R.id.navigation_settings -> true
                currentFragmentId == R.id.navigation_schedule && item.itemId == R.id.navigation_settings -> true
                else -> false // Назад или переход через несколько вкладок
            }
            
            // Обновляем текущий фрагмент ПЕРЕД транзакцией
            currentFragmentId = item.itemId
            
            // Фишка из Telegram: улучшенные анимации переходов с fade эффектом
            supportFragmentManager.beginTransaction()
                .setCustomAnimations(
                    if (isForward) R.anim.slide_in_right else R.anim.slide_in_left,
                    if (isForward) R.anim.slide_out_left else R.anim.slide_out_right,
                    if (isForward) R.anim.slide_in_left else R.anim.slide_in_right,
                    if (isForward) R.anim.slide_out_right else R.anim.slide_out_left
                )
                .setReorderingAllowed(true) // Фишка из Telegram: оптимизация анимаций
                .replace(R.id.fragmentContainer, fragment)
                .commit()
            
            true
        }

        setupBottomNavigationAppearance()
    }

    fun switchToSettings() {
        binding.bottomNavigation.selectedItemId = R.id.navigation_settings
    }

    fun switchToSchedule() {
        // Принудительно переключаемся на расписание
        if (currentFragmentId != R.id.navigation_schedule) {
            currentFragmentId = R.id.navigation_schedule
            val fragment = ScheduleFragment()
            supportFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, fragment)
                .commit()
        }
        binding.bottomNavigation.selectedItemId = R.id.navigation_schedule
    }

    fun switchToStatistics() {
        binding.bottomNavigation.selectedItemId = R.id.navigation_statistics
    }

    private fun applyInsets() {
        if (!::binding.isInitialized) return
        binding.bottomNavigation.setPadding(
            bottomNavBasePadding[0],
            bottomNavBasePadding[1],
            bottomNavBasePadding[2],
            bottomNavBasePadding[3] + bottomInset
        )
        binding.fragmentContainer.setPadding(
            fragmentContainerBasePadding[0],
            fragmentContainerBasePadding[1],
            fragmentContainerBasePadding[2],
            fragmentContainerBasePadding[3]
        )
    }

    private fun setupBottomNavigationAppearance() {
        if (!::binding.isInitialized) return
        val tint = createBottomNavColorState()
        binding.bottomNavigation.itemIconTintList = tint
        binding.bottomNavigation.itemTextColor = tint
        val background = getThemeColor(com.google.android.material.R.attr.colorSurface)
        binding.bottomNavigation.setBackgroundColor(background)
        applyBottomNavActiveIndicator()
        applyNothingFontToBottomNav()
    }
    
    /**
     * Применить шрифт Ndot к BottomNavigationView для темы Nothing
     */
    private fun applyNothingFontToBottomNav() {
        if (!::binding.isInitialized || !::prefs.isInitialized) return
        if (prefs.theme != PreferencesManager.THEME_NOTHING) return
        
        try {
            val ndotFont = resources.getFont(R.font.ndot)
            // Применяем шрифт ко всем TextView внутри BottomNavigationView
            applyFontToViewGroup(binding.bottomNavigation, ndotFont)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при применении шрифта Ndot к навбару: ${e.message}")
        }
    }
    
    /**
     * Рекурсивно применить шрифт ко всем TextView в ViewGroup
     */
    private fun applyFontToViewGroup(viewGroup: android.view.ViewGroup, font: android.graphics.Typeface) {
        for (i in 0 until viewGroup.childCount) {
            val child = viewGroup.getChildAt(i)
            if (child is android.widget.TextView) {
                child.typeface = font
            } else if (child is android.view.ViewGroup) {
                applyFontToViewGroup(child, font)
            }
        }
    }

    private fun createBottomNavColorState(): ColorStateList {
        val prefs = PreferencesManager(this)
        val background = getThemeColor(com.google.android.material.R.attr.colorSurface)
        
        // Используем colorPrimary каждой темы как базовый оттенок выбранной иконки
        val baseActiveColor = when (prefs.theme) {
            PreferencesManager.THEME_LIGHT -> resources.getColor(R.color.light_colorPrimary, null)
            PreferencesManager.THEME_DARK -> resources.getColor(R.color.dark_colorPrimary, null)
            PreferencesManager.THEME_BLUE -> resources.getColor(R.color.blue_colorPrimary, null)
            PreferencesManager.THEME_GRAY -> resources.getColor(R.color.gray_colorPrimary, null)
            PreferencesManager.THEME_PURPLE -> resources.getColor(R.color.system_colorPrimary, null)
            PreferencesManager.THEME_HALLOWEEN -> resources.getColor(R.color.custom_colorPrimary, null)
            PreferencesManager.THEME_NOTHING -> resources.getColor(R.color.nothing_colorPrimary, null)
            PreferencesManager.THEME_GREEN -> resources.getColor(R.color.green_colorPrimary, null)
            PreferencesManager.THEME_NEW_YEAR -> resources.getColor(R.color.newyear_colorPrimary, null)
            else -> resources.getColor(R.color.system_colorPrimary, null)
        }
        
        // Усиливаем контраст (как в предыдущей реализации) чтобы иконка была видна на любом фоне
        val activeColor = ensureStrongContrast(baseActiveColor, background)
        bottomNavActiveColor = activeColor
        
        // Для неактивных иконок используем полупрозрачный цвет
        val inactiveBase = getThemeColor(androidx.appcompat.R.attr.colorControlNormal)
        val inactiveColor = ColorUtils.setAlphaComponent(inactiveBase, (0.6f * 255).toInt())
        
        return ColorStateList(
            arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf(-android.R.attr.state_checked)),
            intArrayOf(activeColor, inactiveColor)
        )
    }
    
    /**
     * Обеспечивает сильный контраст (минимум 4.5:1 для выбранных элементов)
     */
    private fun ensureStrongContrast(color: Int, background: Int): Int {
        val contrast = ColorUtils.calculateContrast(color, background)
        
        // Для выбранных элементов нужен контраст минимум 4.5:1
        if (contrast >= 4.5f) return color
        
        // Определяем целевой цвет для смешивания
        val blendTarget = if (ColorUtils.calculateLuminance(background) > 0.5) {
            // Светлый фон - используем темный цвет
            Color.BLACK
        } else {
            // Темный фон - используем светлый цвет
            Color.WHITE
        }
        
        // Смешиваем до достижения нужного контраста
        var blendedColor = color
        var blendAmount = 0.3f
        var currentContrast = contrast
        
        while (currentContrast < 4.5f && blendAmount < 0.9f) {
            blendedColor = ColorUtils.blendARGB(color, blendTarget, blendAmount)
            currentContrast = ColorUtils.calculateContrast(blendedColor, background)
            blendAmount += 0.1f
        }
        
        return blendedColor
    }

    private fun applyBottomNavActiveIndicator() {
        if (!::binding.isInitialized) return
        val indicatorColor = ColorUtils.setAlphaComponent(bottomNavActiveColor, (0.2f * 255).toInt())
        binding.bottomNavigation.setItemActiveIndicatorEnabled(true)
        binding.bottomNavigation.setItemActiveIndicatorColor(ColorStateList.valueOf(indicatorColor))
        binding.bottomNavigation.setItemActiveIndicatorWidth(
            resources.getDimensionPixelSize(R.dimen.bottom_nav_indicator_width)
        )
        binding.bottomNavigation.setItemActiveIndicatorHeight(
            resources.getDimensionPixelSize(R.dimen.bottom_nav_indicator_height)
        )
        val radius = resources.getDimension(R.dimen.bottom_nav_indicator_corner_radius)
        val shape = ShapeAppearanceModel.builder()
            .setAllCorners(CornerFamily.ROUNDED, radius)
            .build()
        binding.bottomNavigation.setItemActiveIndicatorShapeAppearance(shape)
    }
    
    /**
     * Настроить внешний вид статус-бара в зависимости от темы
     */
    private fun setupStatusBarAppearance() {
        val isLightTheme = prefs.theme == PreferencesManager.THEME_LIGHT
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                // Для светлой темы используем темные иконки (APPEARANCE_LIGHT_STATUS_BARS)
                // Для темной темы - светлые иконки (0)
                if (isLightTheme) {
                    controller.setSystemBarsAppearance(
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    )
                } else {
                    controller.setSystemBarsAppearance(
                        0,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    )
                }
            }
        } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            val flags = window.decorView.systemUiVisibility
            if (isLightTheme) {
                // Для светлой темы - темные иконки (добавляем флаг)
                window.decorView.systemUiVisibility = flags or android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            } else {
                // Для темной темы - светлые иконки (убираем флаг)
                window.decorView.systemUiVisibility = flags and android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
            }
        }
    }

    private fun getThemeColor(attr: Int): Int {
        if (::binding.isInitialized) {
            try {
                return MaterialColors.getColor(binding.root, attr)
            } catch (_: IllegalArgumentException) {
                // fallback to manual resolution
            }
        }
        val typedValue = TypedValue()
        val resolved = theme.resolveAttribute(attr, typedValue, true)
        return if (resolved) {
            if (typedValue.resourceId != 0) {
                ContextCompat.getColor(this, typedValue.resourceId)
            } else {
                typedValue.data
            }
        } else {
            ContextCompat.getColor(this, android.R.color.white)
        }
    }

}