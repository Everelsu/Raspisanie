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
        private const val KEY_SHOW_LESSON_STATUS = "show_lesson_status"
        private const val KEY_THEME = "theme"
        private const val KEY_COLLEGE = "college"
        private const val KEY_SELECTED_GROUP = "selected_group"
        private const val KEY_SELECTED_GROUP_NAME = "selected_group_name"
        private const val KEY_FAVORITE_GROUPS = "favorite_groups"
        private const val KEY_FIRST_LAUNCH = "first_launch"
        private const val KEY_AUTO_REFRESH_ENABLED = "auto_refresh_enabled"
        private const val KEY_AUTO_REFRESH_INTERVAL = "auto_refresh_interval"
        private const val KEY_CACHE_ENABLED = "cache_enabled"
        private const val KEY_FONT_SIZE = "font_size"
        private const val KEY_COMPACT_VIEW = "compact_view"
        private const val KEY_ANIMATIONS_ENABLED = "animations_enabled"
        private const val KEY_APP_AUTO_UPDATE_ENABLED = "app_auto_update_enabled"
        private const val KEY_LAST_UPDATE_CHECK = "last_update_check"
        private const val KEY_LAST_UPDATE_DOWNLOAD_ID = "last_update_download_id"
        private const val KEY_LAST_UPDATE_RESULT = "last_update_result"
        private const val KEY_UPDATE_CHECK_ERROR_COUNT = "update_check_error_count"
        private const val KEY_LAST_UPDATE_CHECK_SUCCESS = "last_update_check_success"
        private const val KEY_BOTTOM_NAVIGATION_ENABLED = "bottom_navigation_enabled"
        private const val KEY_LAST_SCHEDULE_HASH = "last_schedule_hash"
        private const val KEY_SCHEDULE_NOTIFICATIONS_ENABLED = "schedule_notifications_enabled"
        private const val KEY_FCM_TOKEN = "fcm_token"
        private const val KEY_SCHEDULED_EVENT_REQUESTS = "scheduled_event_requests"
        private const val KEY_UPCOMING_NOTIFICATIONS_ENABLED = "upcoming_notifications_enabled"
        private const val KEY_UPCOMING_LESSON_OFFSET_MIN = "upcoming_lesson_offset_min"
        private const val KEY_UPCOMING_BREAK_ENABLED = "upcoming_break_enabled"
        private const val KEY_UPCOMING_LUNCH_ENABLED = "upcoming_lunch_enabled"
        private const val KEY_SCHEDULE_UPDATE_NOTIFICATIONS_ENABLED = "schedule_update_notifications_enabled"
        // Настройки статуса пар
        private const val KEY_LESSON_STATUS_NEXT_MAX_MINUTES = "lesson_status_next_max_minutes"
        private const val KEY_LESSON_STATUS_CURRENT_MAX_MINUTES = "lesson_status_current_max_minutes"
        private const val KEY_SETTINGS_SCROLL_POSITION = "settings_scroll_position"
        private const val KEY_APP_ICON = "app_icon"
        private const val KEY_APP_NAME = "app_name"
        
        // Font size options
        const val FONT_SIZE_SMALL = "small"
        const val FONT_SIZE_NORMAL = "normal"
        const val FONT_SIZE_LARGE = "large"
        const val FONT_SIZE_EXTRA_LARGE = "extra_large"
        
        const val SHARE_FORMAT_TEXT = "text"
        const val SHARE_FORMAT_IMAGE = "image"
        
        // Auto refresh intervals (in minutes)
        const val REFRESH_INTERVAL_15 = 15
        const val REFRESH_INTERVAL_30 = 30
        const val REFRESH_INTERVAL_60 = 60
        const val REFRESH_INTERVAL_120 = 120
        
        const val THEME_LIGHT = "light"
        const val THEME_DARK = "dark"
        const val THEME_BLUE = "blue"
        const val THEME_GRAY = "gray"
        const val THEME_PURPLE = "purple"
        const val THEME_HALLOWEEN = "halloween"
        const val THEME_NOTHING = "nothing"
        const val THEME_GREEN = "green"
        const val THEME_NEW_YEAR = "new_year"
        
        @Deprecated("Use THEME_PURPLE instead")
        const val THEME_SYSTEM = "system"
        
        const val COLLEGE_CHTOTIB = "chtotib"
        const val COLLEGE_ZABGC = "zabgc"
        
        // App icon options
        // Legacy value kept for backward compatibility: treat as black/default
        const val APP_ICON_DEFAULT = "default"

        // Current icon options (color variants of the main icon)
        const val APP_ICON_BLACK = "black" // default = black
        const val APP_ICON_LIGHT = THEME_LIGHT
        const val APP_ICON_DARK = THEME_DARK
        const val APP_ICON_PURPLE = THEME_PURPLE
        const val APP_ICON_GREEN = THEME_GREEN
        const val APP_ICON_NEW_YEAR = THEME_NEW_YEAR
        const val APP_ICON_NOTHING = THEME_NOTHING
        const val APP_ICON_HALLOWEEN = THEME_HALLOWEEN
        
        // App name options
        const val APP_NAME_DEFAULT = "default"
        const val APP_NAME_SHORT = "short"
        const val APP_NAME_SCHEDULE = "schedule"
        const val APP_NAME_RASPISANIE = "raspisanie"
        
        // Default values - только для первого запуска
        const val DEFAULT_COLLEGE = COLLEGE_CHTOTIB
        const val DEFAULT_GROUP_FILE = "cg36.htm"
        const val DEFAULT_GROUP_NAME = "ИСиП-23-1п"
    }
    fun registerChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    fun unregisterChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
    }

    fun isGroupOrCollegeKey(key: String?): Boolean {
        if (key == null) return false
        return key == KEY_SELECTED_GROUP || key == KEY_SELECTED_GROUP_NAME || key == KEY_COLLEGE
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
    
    var showLessonStatus: Boolean
        get() = prefs.getBoolean(KEY_SHOW_LESSON_STATUS, true)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_LESSON_STATUS, value).apply()
    
    var theme: String
        get() = prefs.getString(KEY_THEME, THEME_DARK) ?: THEME_DARK
        set(value) {
            if (value.isNotBlank()) {
                prefs.edit().putString(KEY_THEME, value).apply()
            }
        }
    
    var college: String
        get() = prefs.getString(KEY_COLLEGE, DEFAULT_COLLEGE) ?: DEFAULT_COLLEGE
        set(value) {
            if (value.isNotBlank()) {
                prefs.edit().putString(KEY_COLLEGE, value).apply()
            }
        }
    
    var selectedGroupFile: String
        get() = prefs.getString(KEY_SELECTED_GROUP, "") ?: ""
        set(value) {
            // Use commit() for critical widget-affecting settings to ensure immediate persistence
            prefs.edit().putString(KEY_SELECTED_GROUP, value).commit()
        }
    
    var selectedGroupName: String
        get() = prefs.getString(KEY_SELECTED_GROUP_NAME, "") ?: ""
        set(value) {
            // Use commit() for critical widget-affecting settings to ensure immediate persistence
            prefs.edit().putString(KEY_SELECTED_GROUP_NAME, value).commit()
        }
    
    /**
     * Проверяет, был ли это первый запуск приложения.
     * При первом запуске не устанавливает дефолтную группу - пользователь сам выберет.
     */
    fun checkFirstLaunch() {
        val isFirstLaunch = prefs.getBoolean(KEY_FIRST_LAUNCH, true)
        if (isFirstLaunch) {
            // Просто отмечаем, что это уже не первый запуск
            prefs.edit().putBoolean(KEY_FIRST_LAUNCH, false).apply()
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
        if (groupName.isBlank()) return
        val favorites = getFavoriteGroups().toMutableSet()
        favorites.add(groupName)
        prefs.edit().putString(KEY_FAVORITE_GROUPS, favorites.joinToString(",")).apply()
    }
    
    /**
     * Удалить группу из избранного
     */
    fun removeFavoriteGroup(groupName: String) {
        if (groupName.isBlank()) return
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
    
    // Auto refresh settings
    var autoRefreshEnabled: Boolean
        get() = prefs.getBoolean(KEY_AUTO_REFRESH_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_REFRESH_ENABLED, value).apply()
    
    var autoRefreshInterval: Int
        get() = prefs.getInt(KEY_AUTO_REFRESH_INTERVAL, REFRESH_INTERVAL_60)
        set(value) = prefs.edit().putInt(KEY_AUTO_REFRESH_INTERVAL, value).apply()
    
    // Cache settings
    var cacheEnabled: Boolean
        get() = prefs.getBoolean(KEY_CACHE_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_CACHE_ENABLED, value).apply()
    
    // Font size
    var fontSize: String
        get() = prefs.getString(KEY_FONT_SIZE, FONT_SIZE_NORMAL) ?: FONT_SIZE_NORMAL
        set(value) = prefs.edit().putString(KEY_FONT_SIZE, value).apply()
    
    // View mode
    var compactView: Boolean
        get() = prefs.getBoolean(KEY_COMPACT_VIEW, false)
        set(value) = prefs.edit().putBoolean(KEY_COMPACT_VIEW, value).apply()
    
    // Animations
    var animationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_ANIMATIONS_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ANIMATIONS_ENABLED, value).apply()

    var bottomNavigationEnabled: Boolean
        get() = prefs.getBoolean(KEY_BOTTOM_NAVIGATION_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_BOTTOM_NAVIGATION_ENABLED, value).apply()
    
    var scheduleNotificationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_SCHEDULE_NOTIFICATIONS_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_SCHEDULE_NOTIFICATIONS_ENABLED, value).apply()

    var fcmToken: String
        get() = prefs.getString(KEY_FCM_TOKEN, "") ?: ""
        set(value) = prefs.edit().putString(KEY_FCM_TOKEN, value).apply()

    var scheduledEventRequestCodes: Set<String>
        get() = prefs.getStringSet(KEY_SCHEDULED_EVENT_REQUESTS, emptySet()) ?: emptySet()
        set(value) = prefs.edit().putStringSet(KEY_SCHEDULED_EVENT_REQUESTS, value).apply()

    var upcomingNotificationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_UPCOMING_NOTIFICATIONS_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_UPCOMING_NOTIFICATIONS_ENABLED, value).apply()

    var upcomingLessonOffsetMinutes: Int
        get() = prefs.getInt(KEY_UPCOMING_LESSON_OFFSET_MIN, 5).coerceIn(0, 30)
        set(value) = prefs.edit().putInt(KEY_UPCOMING_LESSON_OFFSET_MIN, value.coerceIn(0, 60)).apply()

    var upcomingBreakRemindersEnabled: Boolean
        get() = prefs.getBoolean(KEY_UPCOMING_BREAK_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_UPCOMING_BREAK_ENABLED, value).apply()

    var upcomingLunchRemindersEnabled: Boolean
        get() = prefs.getBoolean(KEY_UPCOMING_LUNCH_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_UPCOMING_LUNCH_ENABLED, value).apply()
    
    var scheduleUpdateNotificationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_SCHEDULE_UPDATE_NOTIFICATIONS_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_SCHEDULE_UPDATE_NOTIFICATIONS_ENABLED, value).apply()
    
    // ========== НАСТРОЙКИ СТАТУСА ПАР ==========
    
    // Максимальное количество минут для отображения статуса текущей пары (сколько осталось)
    // Диапазон: 30-120 минут
    var lessonStatusCurrentMaxMinutes: Int
        get() = prefs.getInt(KEY_LESSON_STATUS_CURRENT_MAX_MINUTES, 60).coerceIn(30, 120)
        set(value) = prefs.edit().putInt(KEY_LESSON_STATUS_CURRENT_MAX_MINUTES, value.coerceIn(30, 120)).apply()
    
    // Максимальное количество минут для отображения статуса следующей пары (через сколько начнётся)
    // Диапазон: 30-120 минут
    var lessonStatusNextMaxMinutes: Int
        get() = prefs.getInt(KEY_LESSON_STATUS_NEXT_MAX_MINUTES, 60).coerceIn(30, 120)
        set(value) = prefs.edit().putInt(KEY_LESSON_STATUS_NEXT_MAX_MINUTES, value.coerceIn(30, 120)).apply()

    var lastScheduleHash: String
        get() = prefs.getString(KEY_LAST_SCHEDULE_HASH, "") ?: ""
        set(value) = prefs.edit().putString(KEY_LAST_SCHEDULE_HASH, value).apply()
    
    // App auto-update settings
    var appAutoUpdateEnabled: Boolean
        get() = prefs.getBoolean(KEY_APP_AUTO_UPDATE_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_APP_AUTO_UPDATE_ENABLED, value).apply()
    
    var lastUpdateCheck: Long
        get() = prefs.getLong(KEY_LAST_UPDATE_CHECK, 0)
        set(value) = prefs.edit().putLong(KEY_LAST_UPDATE_CHECK, value).apply()
    
    var lastUpdateDownloadId: Long
        get() = prefs.getLong(KEY_LAST_UPDATE_DOWNLOAD_ID, -1)
        set(value) = prefs.edit().putLong(KEY_LAST_UPDATE_DOWNLOAD_ID, value).apply()
    
    // Кэширование результата последней проверки обновлений
    var lastUpdateResult: String
        get() = prefs.getString(KEY_LAST_UPDATE_RESULT, "") ?: ""
        set(value) = prefs.edit().putString(KEY_LAST_UPDATE_RESULT, value).apply()
    
    // Счетчик ошибок при проверке обновлений (для умной логики пропуска проверок)
    var updateCheckErrorCount: Int
        get() = prefs.getInt(KEY_UPDATE_CHECK_ERROR_COUNT, 0)
        set(value) = prefs.edit().putInt(KEY_UPDATE_CHECK_ERROR_COUNT, value.coerceAtLeast(0)).apply()
    
    // Время последней успешной проверки обновлений
    var lastUpdateCheckSuccess: Long
        get() = prefs.getLong(KEY_LAST_UPDATE_CHECK_SUCCESS, 0)
        set(value) = prefs.edit().putLong(KEY_LAST_UPDATE_CHECK_SUCCESS, value).apply()
    
    /**
     * Сбросить счетчик ошибок при успешной проверке
     */
    fun resetUpdateCheckErrorCount() {
        updateCheckErrorCount = 0
    }
    
    /**
     * Увеличить счетчик ошибок
     */
    fun incrementUpdateCheckErrorCount() {
        updateCheckErrorCount = updateCheckErrorCount + 1
    }
    
    var settingsScrollPosition: Int
        get() = prefs.getInt(KEY_SETTINGS_SCROLL_POSITION, 0)
        set(value) = prefs.edit().putInt(KEY_SETTINGS_SCROLL_POSITION, value).apply()
    
    var appIcon: String
        get() {
            val raw = prefs.getString(KEY_APP_ICON, APP_ICON_DEFAULT) ?: APP_ICON_DEFAULT
            // Backward compatibility for removed icon ids
            return when (raw) {
                "book", "calendar", "clock", "graduation" -> APP_ICON_DEFAULT
                "white" -> APP_ICON_LIGHT
                else -> raw
            }
        }
        set(value) = prefs.edit().putString(KEY_APP_ICON, value).apply()
    
    var appName: String
        get() = prefs.getString(KEY_APP_NAME, "") ?: ""
        set(value) = prefs.edit().putString(KEY_APP_NAME, value).apply()
}

