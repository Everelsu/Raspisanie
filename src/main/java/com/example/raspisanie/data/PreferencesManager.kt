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
        private const val KEY_SELECTED_GROUP = "selected_group"
        private const val KEY_SELECTED_GROUP_NAME = "selected_group_name"
        private const val KEY_FIRST_LAUNCH = "first_launch"
        private const val KEY_INSTITUTE = "institute"
        private const val KEY_FAVORITES = "favorite_groups"
        
        
        const val THEME_SYSTEM = "system"
        const val THEME_LIGHT = "light"
        const val THEME_DARK = "dark"
        const val THEME_CUSTOM = "custom"
        const val THEME_NOTHING = "nothing"
        
        // Ранее использовалась дефолтная группа, теперь по требованию — по умолчанию не выбрано
        const val DEFAULT_GROUP_FILE = ""
        const val DEFAULT_GROUP_NAME = ""
        const val INSTITUTE_CHTOTIB = "chtotib"
        const val INSTITUTE_ZABGK = "zabgk"
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
    
    var selectedGroupFile: String
        get() = prefs.getString(KEY_SELECTED_GROUP, "") ?: ""
        set(value) = prefs.edit().putString(KEY_SELECTED_GROUP, value).apply()
    
    var selectedGroupName: String
        get() = prefs.getString(KEY_SELECTED_GROUP_NAME, "") ?: ""
        set(value) = prefs.edit().putString(KEY_SELECTED_GROUP_NAME, value).apply()

    var institute: String
        get() = prefs.getString(KEY_INSTITUTE, INSTITUTE_CHTOTIB) ?: INSTITUTE_CHTOTIB
        set(value) = prefs.edit().putString(KEY_INSTITUTE, value).apply()

    data class FavoriteGroup(val institute: String, val file: String, val name: String)

    fun getFavoriteGroups(): List<FavoriteGroup> {
        val set = prefs.getStringSet(KEY_FAVORITES, emptySet()) ?: emptySet()
        return set.mapNotNull { token ->
            val parts = token.split("|", limit = 3)
            if (parts.size == 3) FavoriteGroup(parts[0], parts[1], parts[2]) else null
        }
    }

    fun getFavoriteGroups(institute: String): List<FavoriteGroup> =
        getFavoriteGroups().filter { it.institute == institute }

    fun isFavorite(institute: String, file: String): Boolean =
        getFavoriteGroups().any { it.institute == institute && it.file == file }

    fun addFavorite(institute: String, file: String, name: String) {
        val set = prefs.getStringSet(KEY_FAVORITES, emptySet())?.toMutableSet() ?: mutableSetOf()
        set.add("$institute|$file|$name")
        prefs.edit().putStringSet(KEY_FAVORITES, set).apply()
    }

    fun removeFavorite(institute: String, file: String) {
        val set = prefs.getStringSet(KEY_FAVORITES, emptySet())?.toMutableSet() ?: mutableSetOf()
        val toRemove = set.firstOrNull { it.startsWith("$institute|$file|") }
        if (toRemove != null) {
            set.remove(toRemove)
            prefs.edit().putStringSet(KEY_FAVORITES, set).apply()
        }
    }

    
    
    /**
     * Проверяет, был ли это первый запуск приложения.
     * По умолчанию группа НЕ выбрана.
     */
    fun checkFirstLaunch() {
        val isFirstLaunch = prefs.getBoolean(KEY_FIRST_LAUNCH, true)
        if (isFirstLaunch) {
            // На первом запуске — ничего не выбираем
            prefs.edit()
                .putString(KEY_SELECTED_GROUP, DEFAULT_GROUP_FILE)
                .putString(KEY_SELECTED_GROUP_NAME, DEFAULT_GROUP_NAME)
                .putBoolean(KEY_FIRST_LAUNCH, false)
                .apply()
        }
    }
    
    /**
     * Проверяет, выбрана ли группа
     */
    fun isGroupSelected(): Boolean {
        return selectedGroupFile.isNotEmpty() && selectedGroupName.isNotEmpty()
    }
}

