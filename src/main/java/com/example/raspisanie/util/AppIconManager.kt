package com.example.raspisanie.util

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.example.raspisanie.MainActivity
import com.example.raspisanie.data.PreferencesManager

object AppIconManager {
    private const val DEFAULT_ALIAS = "com.example.raspisanie.MainActivity.DefaultIcon"
    // compat/extra aliases (may be enabled on old installs / pinned shortcuts)
    private const val BLACK_ALIAS = "com.example.raspisanie.MainActivity.BlackIcon"
    private const val DARK_ALIAS = "com.example.raspisanie.MainActivity.DarkIcon"
    private const val WHITE_ALIAS = "com.example.raspisanie.MainActivity.WhiteIcon"
    private const val LIGHT_ALIAS = "com.example.raspisanie.MainActivity.LightIcon"
    private const val PURPLE_ALIAS = "com.example.raspisanie.MainActivity.PurpleIcon"
    private const val GREEN_ALIAS = "com.example.raspisanie.MainActivity.GreenIcon"
    private const val NEWYEAR_ALIAS = "com.example.raspisanie.MainActivity.NewYearIcon"
    private const val NOTHING_ALIAS = "com.example.raspisanie.MainActivity.NothingIcon"
    private const val HALLOWEEN_ALIAS = "com.example.raspisanie.MainActivity.HalloweenIcon"
    
    // Legacy aliases (for backward compatibility)
    private const val BOOK_ALIAS = "com.example.raspisanie.MainActivity.BookIcon"
    private const val CALENDAR_ALIAS = "com.example.raspisanie.MainActivity.CalendarIcon"
    private const val CLOCK_ALIAS = "com.example.raspisanie.MainActivity.ClockIcon"
    private const val GRADUATION_ALIAS = "com.example.raspisanie.MainActivity.GraduationIcon"
    
    /**
     * Получить все известные aliases (включая legacy для совместимости)
     */
    fun getAllAliases(packageName: String): List<ComponentName> {
        return listOf(
            ComponentName(packageName, DEFAULT_ALIAS),
            ComponentName(packageName, BLACK_ALIAS),
            ComponentName(packageName, DARK_ALIAS),
            ComponentName(packageName, WHITE_ALIAS),
            ComponentName(packageName, LIGHT_ALIAS),
            ComponentName(packageName, PURPLE_ALIAS),
            ComponentName(packageName, GREEN_ALIAS),
            ComponentName(packageName, NEWYEAR_ALIAS),
            ComponentName(packageName, NOTHING_ALIAS),
            ComponentName(packageName, HALLOWEEN_ALIAS),
            // Legacy aliases (for backward compatibility)
            ComponentName(packageName, BOOK_ALIAS),
            ComponentName(packageName, CALENDAR_ALIAS),
            ComponentName(packageName, CLOCK_ALIAS),
            ComponentName(packageName, GRADUATION_ALIAS)
        )
    }
    
    /**
     * Переключить иконку приложения
     * Логика как в Telegram: отключаем все, включаем нужный, перезапускаем приложение
     */
    fun switchIcon(context: Context, iconType: String) {
        val packageManager = context.packageManager
        val packageName = context.packageName
        
        // Определяем какой alias нужно включить
        val targetAlias = when (iconType) {
            PreferencesManager.APP_ICON_DEFAULT -> ComponentName(packageName, DEFAULT_ALIAS)
            PreferencesManager.APP_ICON_BLACK -> ComponentName(packageName, BLACK_ALIAS)
            PreferencesManager.APP_ICON_DARK -> ComponentName(packageName, DARK_ALIAS)
            PreferencesManager.APP_ICON_LIGHT -> ComponentName(packageName, LIGHT_ALIAS)
            PreferencesManager.APP_ICON_PURPLE -> ComponentName(packageName, PURPLE_ALIAS)
            PreferencesManager.APP_ICON_GREEN -> ComponentName(packageName, GREEN_ALIAS)
            PreferencesManager.APP_ICON_NEW_YEAR -> ComponentName(packageName, NEWYEAR_ALIAS)
            PreferencesManager.APP_ICON_NOTHING -> ComponentName(packageName, NOTHING_ALIAS)
            PreferencesManager.APP_ICON_HALLOWEEN -> ComponentName(packageName, HALLOWEEN_ALIAS)
            else -> ComponentName(packageName, DEFAULT_ALIAS) // fallback to default
        }
        
        // КРИТИЧНО: Отключаем ВСЕ aliases сначала (включая DefaultIcon)
        // Это гарантирует, что только один alias будет активен
        getAllAliases(packageName).forEach { alias ->
            try {
                packageManager.setComponentEnabledSetting(
                    alias,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            } catch (e: Exception) {
                android.util.Log.e("AppIconManager", "Ошибка при отключении alias ${alias.className}: ${e.message}")
            }
        }
        
        // Включаем нужный alias
        try {
            packageManager.setComponentEnabledSetting(
                targetAlias,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
        } catch (e: Exception) {
            android.util.Log.e("AppIconManager", "Ошибка при включении alias ${targetAlias.className}: ${e.message}")
            // В случае ошибки включаем DefaultIcon как fallback
            try {
                packageManager.setComponentEnabledSetting(
                    ComponentName(packageName, DEFAULT_ALIAS),
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
            } catch (ex: Exception) {
                android.util.Log.e("AppIconManager", "Критическая ошибка при включении DefaultIcon: ${ex.message}")
            }
        }
        
        // Перезапускаем приложение для применения изменений (как в Telegram)
        if (context is Activity) {
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val intent = Intent(context, MainActivity::class.java)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    context.startActivity(intent)
                    context.finish()
                    // Принудительно завершаем процесс для полного перезапуска
                    android.os.Process.killProcess(android.os.Process.myPid())
                } catch (e: Exception) {
                    android.util.Log.e("AppIconManager", "Ошибка при перезапуске приложения: ${e.message}")
                }
            }, 300)
        }
    }
    
    /**
     * Получить текущую активную иконку
     * Обрабатывает все возможные состояния компонента
     */
    fun getCurrentIcon(context: Context): String {
        val packageManager = context.packageManager
        val packageName = context.packageName
        
        val aliases = mapOf(
            PreferencesManager.APP_ICON_DEFAULT to ComponentName(packageName, DEFAULT_ALIAS),
            PreferencesManager.APP_ICON_BLACK to ComponentName(packageName, BLACK_ALIAS),
            PreferencesManager.APP_ICON_DARK to ComponentName(packageName, DARK_ALIAS),
            PreferencesManager.APP_ICON_LIGHT to ComponentName(packageName, LIGHT_ALIAS),
            PreferencesManager.APP_ICON_PURPLE to ComponentName(packageName, PURPLE_ALIAS),
            PreferencesManager.APP_ICON_GREEN to ComponentName(packageName, GREEN_ALIAS),
            PreferencesManager.APP_ICON_NEW_YEAR to ComponentName(packageName, NEWYEAR_ALIAS),
            PreferencesManager.APP_ICON_NOTHING to ComponentName(packageName, NOTHING_ALIAS),
            PreferencesManager.APP_ICON_HALLOWEEN to ComponentName(packageName, HALLOWEEN_ALIAS)
        )
        
        // Проверяем все aliases на состояние ENABLED
        aliases.forEach { (iconType, alias) ->
            try {
                val state = packageManager.getComponentEnabledSetting(alias)
                // COMPONENT_ENABLED_STATE_ENABLED - явно включен
                // COMPONENT_ENABLED_STATE_DEFAULT - использует значение из манифеста (для DefaultIcon это enabled="true")
                if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                    (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && alias.className == DEFAULT_ALIAS)) {
                    return iconType
                }
            } catch (e: Exception) {
                android.util.Log.e("AppIconManager", "Ошибка при проверке alias ${alias.className}: ${e.message}")
            }
        }
        
        // Если ничего не найдено, возвращаем default
        return PreferencesManager.APP_ICON_DEFAULT
    }
    
    /**
     * Проверить, что хотя бы один alias включен (для безопасности при запуске)
     */
    fun ensureAtLeastOneEnabled(context: Context): Boolean {
        val packageManager = context.packageManager
        val packageName = context.packageName
        
        val allAliases = getAllAliases(packageName)
        val anyEnabled = allAliases.any { alias ->
            try {
                val state = packageManager.getComponentEnabledSetting(alias)
                state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                        (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && alias.className == DEFAULT_ALIAS)
            } catch (e: Exception) {
                false
            }
        }
        
        if (!anyEnabled) {
            // Включаем DefaultIcon принудительно
            try {
                val defaultAlias = ComponentName(packageName, DEFAULT_ALIAS)
                packageManager.setComponentEnabledSetting(
                    defaultAlias,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                return true
            } catch (e: Exception) {
                android.util.Log.e("AppIconManager", "Критическая ошибка при включении DefaultIcon: ${e.message}")
                return false
            }
        }
        
        return true
    }
}

