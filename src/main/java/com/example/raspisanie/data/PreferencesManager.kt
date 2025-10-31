package com.example.raspisanie.data

import android.content.Context
import android.content.SharedPreferences

class PreferencesManager(context: Context) {
    private val prefs: SharedPreferences = 
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    companion object {
        private const val PREFS_NAME = "schedule_prefs"
        private const val KEY_SHOW_BREAKS = "show_breaks"
        private const val KEY_SHOW_LUNCH = "show_lunch"
        private const val KEY_SHOW_TIME = "show_time"
        private const val KEY_SHOW_PROGRESS_LINE = "show_progress_line"
        private const val KEY_THEME = "theme"
        private const val KEY_COLLEGE = "college"
        private const val KEY_SELECTED_GROUP = "selected_group"
        private const val KEY_SELECTED_GROUP_NAME = "selected_group_name"
        private const val KEY_FAVORITE_GROUPS = "favorite_groups"
        private const val KEY_FIRST_LAUNCH = "first_launch"
        
        const val THEME_SYSTEM = "system"
        const val THEME_LIGHT = "light"
        const val THEME_DARK = "dark"
        const val THEME_CUSTOM = "custom"
        const val THEME_NOTHING = "nothing"
        
        const val COLLEGE_CHTOTIB = "chtotib"
        const val COLLEGE_ZABGC = "zabgc"
        
        // Default values - только для первого запуска
        const val DEFAULT_COLLEGE = COLLEGE_CHTOTIB
        const val DEFAULT_GROUP_FILE = "cg36.htm"
        const val DEFAULT_GROUP_NAME = "ИСиП-23-1п"
    }
    
    var showBreaks: Boolean
        get() = prefs.getBoolean(KEY_SHOW_BREAKS, true)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_BREAKS, value).apply()
    
    var showLunch: Boolean
        get() = prefs.getBoolean(KEY_SHOW_LUNCH, true)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_LUNCH, value).apply()
    
    var showTime: Boolean
        get() = prefs.getBoolean(KEY_SHOW_TIME, true)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_TIME, value).apply()
    
    var showProgressLine: Boolean
        get() = prefs.getBoolean(KEY_SHOW_PROGRESS_LINE, false)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_PROGRESS_LINE, value).apply()
    
    var theme: String
        get() = prefs.getString(KEY_THEME, THEME_SYSTEM) ?: THEME_SYSTEM
        set(value) = prefs.edit().putString(KEY_THEME, value).apply()
    
    var college: String
        get() = prefs.getString(KEY_COLLEGE, DEFAULT_COLLEGE) ?: DEFAULT_COLLEGE
        set(value) = prefs.edit().putString(KEY_COLLEGE, value).apply()
    
    var selectedGroupFile: String
        get() = prefs.getString(KEY_SELECTED_GROUP, "") ?: ""
        set(value) = prefs.edit().putString(KEY_SELECTED_GROUP, value).apply()
    
    var selectedGroupName: String
        get() = prefs.getString(KEY_SELECTED_GROUP_NAME, "") ?: ""
        set(value) = prefs.edit().putString(KEY_SELECTED_GROUP_NAME, value).apply()
    
    /**
     * Проверяет, был ли это первый запуск приложения.
     * При первом запуске устанавливает дефолтную группу.
     */
    fun checkFirstLaunch() {
        val isFirstLaunch = prefs.getBoolean(KEY_FIRST_LAUNCH, true)
        if (isFirstLaunch) {
            // Проверяем напрямую в SharedPreferences, есть ли уже сохраненная группа
            val savedGroupFile = prefs.getString(KEY_SELECTED_GROUP, "")
            val savedGroupName = prefs.getString(KEY_SELECTED_GROUP_NAME, "")
            
            // Если группа не сохранена (первый запуск) - установить дефолтную
            if (savedGroupFile.isNullOrEmpty() || savedGroupName.isNullOrEmpty()) {
                prefs.edit()
                    .putString(KEY_COLLEGE, DEFAULT_COLLEGE)
                    .putString(KEY_SELECTED_GROUP, DEFAULT_GROUP_FILE)
                    .putString(KEY_SELECTED_GROUP_NAME, DEFAULT_GROUP_NAME)
                    .putBoolean(KEY_FIRST_LAUNCH, false)
                    .apply()
            } else {
                // Группа уже выбрана, просто отмечаем что это не первый запуск
                prefs.edit().putBoolean(KEY_FIRST_LAUNCH, false).apply()
            }
        }
    }
    
    /**
     * Проверяет, выбрана ли группа
     */
    fun isGroupSelected(): Boolean {
        return selectedGroupFile.isNotEmpty() && selectedGroupName.isNotEmpty()
    }
    
    /**
     * Получить список избранных групп
     */
    fun getFavoriteGroups(): Set<String> {
        val favoritesString = prefs.getString(KEY_FAVORITE_GROUPS, "") ?: ""
        return if (favoritesString.isEmpty()) {
            emptySet()
        } else {
            favoritesString.split(",").toSet()
        }
    }
    
    /**
     * Добавить группу в избранное
     */
    fun addFavoriteGroup(groupName: String) {
        val favorites = getFavoriteGroups().toMutableSet()
        favorites.add(groupName)
        prefs.edit().putString(KEY_FAVORITE_GROUPS, favorites.joinToString(",")).apply()
    }
    
    /**
     * Удалить группу из избранного
     */
    fun removeFavoriteGroup(groupName: String) {
        val favorites = getFavoriteGroups().toMutableSet()
        favorites.remove(groupName)
        prefs.edit().putString(KEY_FAVORITE_GROUPS, favorites.joinToString(",")).apply()
    }
    
    /**
     * Проверить, является ли группа избранной
     */
    fun isFavoriteGroup(groupName: String): Boolean {
        return getFavoriteGroups().contains(groupName)
    }
}

