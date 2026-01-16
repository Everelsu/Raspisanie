package com.example.raspisanie

import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.content.pm.PackageManager
import android.Manifest
import android.view.View
import android.util.TypedValue
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleNotificationManager
import com.example.raspisanie.util.AppIconManager
import com.example.raspisanie.databinding.ActivityMainBinding
import com.example.raspisanie.util.NotificationPermissionHelper
import com.onesignal.OneSignal
import com.onesignal.debug.LogLevel
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
            
            // Инициализируем OneSignal
            initOneSignal()
            
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
        // Обрабатываем стандартный запрос разрешений Android (если используется)
        if (requestCode == NotificationPermissionHelper.REQUEST_CODE_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Android notification permission granted: $granted")
            if (::prefs.isInitialized) {
                prefs.scheduleNotificationsEnabled = granted
            }
            // OneSignal обрабатывает разрешения самостоятельно через requestPermission()
            // Перепроверяем статус через некоторое время
            Handler(Looper.getMainLooper()).postDelayed({
                checkOneSignalStatus()
            }, 2000)
        }
    }

    private fun maybeRequestNotificationPermission(): Boolean {
        if (!::prefs.isInitialized) return false
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) {
            // Для старых версий Android разрешение не требуется
            return true
        }

        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            if (!prefs.scheduleNotificationsEnabled) {
                prefs.scheduleNotificationsEnabled = true
            }
            return true
        }

        // Запрашиваем разрешение всегда, если его нет
        NotificationPermissionHelper.requestIfNeeded(this)
        return false
    }

    private fun initOneSignal() {
        try {
            // Проверяем, не инициализирован ли OneSignal уже (например, через BootUpReceiver)
            try {
                val existingPlayerId = OneSignal.User.pushSubscription.id
                if (existingPlayerId.isNotEmpty()) {
                    Log.d(TAG, "OneSignal уже инициализирован (Player ID: $existingPlayerId)")
                    checkOneSignalStatus()
                    return
                }
            } catch (e: Exception) {
                // OneSignal еще не инициализирован, продолжаем инициализацию
                Log.d(TAG, "OneSignal еще не инициализирован, начинаем инициализацию...")
            }

            // Инициализация OneSignal всегда должна происходить, даже если уведомления отключены
            // Пользователь может включить их позже в настройках
            val oneSignalAppId = getString(R.string.onesignal_app_id)

            // Настройка логирования (включаем VERBOSE для отладки)
            OneSignal.Debug.logLevel = LogLevel.VERBOSE

            // Инициализация OneSignal
            OneSignal.initWithContext(this, oneSignalAppId)
            Log.d(TAG, "OneSignal инициализирован с App ID: $oneSignalAppId")

            // ВАЖНО: OneSignal SDK 5.x использует свой собственный метод запроса разрешений
            // Это необходимо для корректной работы push-уведомлений
            // requestPermission - это suspend функция, поэтому вызываем в корутине
            lifecycleScope.launch {
                try {
                    val granted = OneSignal.Notifications.requestPermission(true)
                    Log.d(TAG, "Запрос разрешения на уведомления через OneSignal SDK: $granted")

                    if (granted) {
                        // Разрешение предоставлено, активируем подписку
                        OneSignal.User.pushSubscription.optIn()
                        Log.d(TAG, "✅ Подписка OneSignal активирована после получения разрешения")

                        // Обновляем настройки
                        if (::prefs.isInitialized) {
                            prefs.scheduleNotificationsEnabled = true
                        }

                        // Проверяем статус через несколько секунд
                        Handler(Looper.getMainLooper()).postDelayed({
                            checkOneSignalStatus()
                        }, 5000)
                    } else {
                        Log.w(TAG, "⚠️ Разрешение на уведомления отклонено")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при запросе разрешения OneSignal: ${e.message}", e)
                }
            }

            // Для получения Player ID используем отложенную проверку
            // (Player ID может быть еще не готов сразу после инициализации)
            Handler(Looper.getMainLooper()).postDelayed({
                checkOneSignalStatus()
            }, 5000) // Увеличено до 5 секунд для надежности

        } catch (e: Exception) {
            Log.e(TAG, "❌ Критическая ошибка инициализации OneSignal: ${e.message}", e)
            e.printStackTrace()
        }
    }

    private fun checkOneSignalStatus() {
        try {
            val pushSubscription = OneSignal.User.pushSubscription
            val playerId = pushSubscription.id
            val isSubscribed = pushSubscription.optedIn
            val token = pushSubscription.token

            Log.d(TAG, "=== OneSignal Status ===")
            Log.d(TAG, "Player ID: $playerId")
            Log.d(TAG, "Подписка активна: $isSubscribed")
            Log.d(TAG, "Token: $token")
            Log.d(TAG, "Уведомления включены в настройках: ${prefs.scheduleNotificationsEnabled}")

            if (playerId.isNotEmpty()) {
                if (prefs.fcmToken != playerId) {
                    prefs.fcmToken = playerId
                    Log.d(TAG, "✅ OneSignal Player ID сохранен: $playerId")
                    Log.d(TAG, "📱 ИСПОЛЬЗУЙТЕ ЭТОТ Player ID для отправки тестового уведомления в OneSignal Dashboard")
                } else {
                    Log.d(TAG, "OneSignal Player ID уже сохранен: $playerId")
                }
                    } else {
                        Log.w(TAG, "⚠️ OneSignal Player ID пустой. Возможные причины:")
                        Log.w(TAG, "   1. Firebase Server Key не настроен в OneSignal Dashboard")
                        Log.w(TAG, "   2. google-services.json неверный или отсутствует")
                        Log.w(TAG, "   3. Разрешения на уведомления не предоставлены")
                        Log.w(TAG, "   4. VPN/AdBlock блокирует HTTPS соединения с OneSignal")
                    }

                    if (!isSubscribed) {
                        Log.w(TAG, "⚠️ Устройство не подписано на уведомления!")
                        Log.w(TAG, "   Проверьте разрешения в настройках Android для этого приложения")
                        Log.w(TAG, "   Также проверьте, не блокирует ли VPN/AdBlock соединения")
                    }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Ошибка при получении OneSignal Player ID: ${e.message}", e)
            e.printStackTrace()
        }
    }


    private fun applyTheme(themeKey: String) {
        try {
            // Для системной темы устанавливаем режим ночи из системы ОС
            if (themeKey == PreferencesManager.THEME_PURPLE) {
                AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
            } else {
                // Для остальных тем принудительно устанавливаем режим ночи
                val nightMode = when (themeKey) {
                    PreferencesManager.THEME_LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
                    PreferencesManager.THEME_DARK,
                    PreferencesManager.THEME_BLUE,
                    PreferencesManager.THEME_GRAY,
                    PreferencesManager.THEME_HALLOWEEN,
                    PreferencesManager.THEME_NOTHING,
                    PreferencesManager.THEME_GREEN,
                    PreferencesManager.THEME_NEW_YEAR -> AppCompatDelegate.MODE_NIGHT_YES
                    else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
                }
                AppCompatDelegate.setDefaultNightMode(nightMode)
            }

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
                AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
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