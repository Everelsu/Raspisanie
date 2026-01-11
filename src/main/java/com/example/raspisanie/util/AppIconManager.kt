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

/**
 * Менеджер иконок приложения
 * Реализация как в Telegram - перезапуск приложения
 */
object AppIconManager {
    private const val TAG = "AppIconManager"
    
    // Маппинг типов иконок на alias names
    private val ALIASES = mapOf(
        PreferencesManager.APP_ICON_DEFAULT to "DefaultIcon",
        PreferencesManager.APP_ICON_BLACK to "BlackIcon",
        PreferencesManager.APP_ICON_DARK to "DarkIcon",
        PreferencesManager.APP_ICON_LIGHT to "LightIcon",
        PreferencesManager.APP_ICON_PURPLE to "PurpleIcon",
        PreferencesManager.APP_ICON_GREEN to "GreenIcon",
        PreferencesManager.APP_ICON_NEW_YEAR to "NewYearIcon",
        PreferencesManager.APP_ICON_NOTHING to "NothingIcon",
        PreferencesManager.APP_ICON_HALLOWEEN to "HalloweenIcon"
    )
    
    private fun getComponentName(context: Context, aliasName: String): ComponentName {
        return ComponentName(
            context.packageName,
            "com.example.raspisanie.MainActivity.$aliasName"
        )
    }
    
    /**
     * Все aliases (включая legacy для совместимости)
     */
    fun getAllAliases(packageName: String): List<ComponentName> {
        return ALIASES.values.map { alias ->
            ComponentName(packageName, "com.example.raspisanie.MainActivity.$alias")
        } + listOf(
            ComponentName(packageName, "com.example.raspisanie.MainActivity.WhiteIcon"),
            ComponentName(packageName, "com.example.raspisanie.MainActivity.BookIcon"),
            ComponentName(packageName, "com.example.raspisanie.MainActivity.CalendarIcon"),
            ComponentName(packageName, "com.example.raspisanie.MainActivity.ClockIcon"),
            ComponentName(packageName, "com.example.raspisanie.MainActivity.GraduationIcon")
        )
    }
    
    /**
     * Переключить иконку (как в Telegram)
     */
    fun switchIcon(context: Context, iconType: String) {
        val pm = context.packageManager
        val packageName = context.packageName
        
        val targetAliasName = ALIASES[iconType] ?: ALIASES[PreferencesManager.APP_ICON_DEFAULT]!!
        val targetComponent = getComponentName(context, targetAliasName)
        
        android.util.Log.d(TAG, "🔄 Переключение на: $iconType ($targetAliasName)")
        
        try {
            // Шаг 1: Отключаем все aliases (включая DefaultIcon если он в DEFAULT или ENABLED)
            for ((type, aliasName) in ALIASES) {
                if (type != iconType) {
                    try {
                        val component = getComponentName(context, aliasName)
                        val currentState = pm.getComponentEnabledSetting(component)
                        
                        // Отключаем если включен (ENABLED) или в DEFAULT (DefaultIcon)
                        if (currentState == PackageManager.COMPONENT_ENABLED_STATE_ENABLED || 
                            currentState == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) {
                            pm.setComponentEnabledSetting(
                                component,
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            android.util.Log.d(TAG, "❌ Отключен: $aliasName (было: $currentState)")
                        }
                    } catch (e: Exception) {
                        android.util.Log.w(TAG, "⚠️ Ошибка при отключении $aliasName: ${e.message}")
                    }
                }
            }
            
            // Отключаем legacy aliases
            listOf("WhiteIcon", "BookIcon", "CalendarIcon", "ClockIcon", "GraduationIcon").forEach { aliasName ->
                try {
                    val component = getComponentName(context, aliasName)
                    val currentState = pm.getComponentEnabledSetting(component)
                    if (currentState == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                        pm.setComponentEnabledSetting(
                            component,
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP
                        )
                    }
                } catch (e: Exception) {
                    // ignore
                }
            }
            
            // Шаг 2: Включаем целевой alias
            val targetState = pm.getComponentEnabledSetting(targetComponent)
            if (targetState != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                pm.setComponentEnabledSetting(
                    targetComponent,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                android.util.Log.d(TAG, "✅ Включен: $targetAliasName (было: $targetState)")
            } else {
                android.util.Log.d(TAG, "✅ $targetAliasName уже включен")
            }
            
            // Перезапускаем приложение (как в Telegram)
            if (context is Activity) {
                android.util.Log.d(TAG, "🔄 Запуск перезапуска приложения...")
                restartApp(context, targetComponent)
            } else {
                android.util.Log.e(TAG, "❌ Context не является Activity, перезапуск невозможен")
            }
            
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Ошибка при смене иконки: ${e.message}", e)
        }
    }
    
    /**
     * Перезапуск приложения (как в Telegram)
     */
    private fun restartApp(activity: Activity, targetComponent: ComponentName) {
        // Даем системе время на обновление компонентов
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                android.util.Log.d(TAG, "🚀 Запуск через: ${targetComponent.className}")
                
                // Создаём Intent напрямую для alias компонента (как в Telegram)
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    component = targetComponent
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or 
                            Intent.FLAG_ACTIVITY_CLEAR_TASK
                }
                
                // Запускаем новый процесс через alias
                activity.startActivity(intent)
                
                // Завершаем все activity после запуска
                activity.finishAffinity()
                
                // Убиваем процесс (как в Telegram)
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        android.os.Process.killProcess(android.os.Process.myPid())
                        System.exit(0)
                    } catch (e: Exception) {
                        android.util.Log.w(TAG, "Не удалось убить процесс: ${e.message}")
                        System.exit(0)
                    }
                }, 200)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "❌ Ошибка перезапуска: ${e.message}", e)
                // Пытаемся перезапустить стандартным способом
                try {
                    val pm = activity.packageManager
                    val intent = pm.getLaunchIntentForPackage(activity.packageName)
                    intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    activity.startActivity(intent)
                    activity.finishAffinity()
                    System.exit(0)
                } catch (e2: Exception) {
                    android.util.Log.e(TAG, "Критическая ошибка перезапуска: ${e2.message}", e2)
                }
            }
        }, 500)
    }
    
    /**
     * Получить текущую активную иконку
     */
    fun getCurrentIcon(context: Context): String {
        val pm = context.packageManager
        
        for ((iconType, aliasName) in ALIASES) {
            try {
                val component = getComponentName(context, aliasName)
                val state = pm.getComponentEnabledSetting(component)
                
                if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                    return iconType
                }
                
                // DefaultIcon может быть в DEFAULT состоянии
                if (aliasName == "DefaultIcon" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) {
                    return iconType
                }
            } catch (e: Exception) {
                // continue
            }
        }
        
        return PreferencesManager.APP_ICON_DEFAULT
    }
    
    /**
     * Убедиться что хотя бы один alias включен
     */
    fun ensureAtLeastOneEnabled(context: Context): Boolean {
        val pm = context.packageManager
        
        // Проверяем есть ли включенный
        for ((_, aliasName) in ALIASES) {
            try {
                val component = getComponentName(context, aliasName)
                val state = pm.getComponentEnabledSetting(component)
                
                if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                    return true
                }
                if (aliasName == "DefaultIcon" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) {
                    return true
                }
            } catch (e: Exception) {
                // continue
            }
        }
        
        // Если нет — включаем DefaultIcon (устанавливаем в ENABLED если был DISABLED)
        try {
            val defaultComponent = getComponentName(context, "DefaultIcon")
            val state = pm.getComponentEnabledSetting(defaultComponent)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                pm.setComponentEnabledSetting(
                    defaultComponent,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
            return true
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Критическая ошибка: ${e.message}")
            return false
        }
    }
}
