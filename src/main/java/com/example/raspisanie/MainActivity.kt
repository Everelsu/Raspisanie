package com.example.raspisanie

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.content.pm.PackageManager
import android.Manifest
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.Fragment
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.databinding.ActivityMainBinding
import com.example.raspisanie.util.NotificationPermissionHelper
import com.google.firebase.messaging.FirebaseMessaging

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

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            prefs = PreferencesManager(this)
            
            // Проверить первый запуск
            prefs.checkFirstLaunch()
            
            currentThemeKey = prefs.theme
            applyTheme(currentThemeKey)
            
            super.onCreate(savedInstanceState)
            
            enableEdgeToEdge()
            
            binding = ActivityMainBinding.inflate(layoutInflater)
            setContentView(binding.root)
            
            maybeRequestNotificationPermission()
            initFirebaseMessaging()
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
            
            if (savedInstanceState == null) {
                supportFragmentManager.beginTransaction()
                    .replace(R.id.fragmentContainer, ScheduleFragment())
                    .commit()
                binding.bottomNavigation.selectedItemId = R.id.navigation_schedule
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
                    recreate()
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка при recreate: ${e.message}", e)
                }
                return
            }
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
    }
    
    private fun setupBottomNavigation() {
        binding.bottomNavigation.visibility = View.VISIBLE
        binding.bottomNavigation.setOnItemSelectedListener { item ->
            val fragment: Fragment = when (item.itemId) {
                R.id.navigation_schedule -> ScheduleFragment()
                R.id.navigation_statistics -> StatisticsFragment()
                R.id.navigation_settings -> SettingsFragment()
                else -> ScheduleFragment()
            }
            
            supportFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, fragment)
                .commit()
            
            true
        }
    }

    fun switchToSettings() {
        binding.bottomNavigation.selectedItemId = R.id.navigation_settings
    }

    fun switchToSchedule() {
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
}