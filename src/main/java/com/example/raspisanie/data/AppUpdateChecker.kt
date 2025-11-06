package com.example.raspisanie.data

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.jsoup.Jsoup

/**
 * Информация о версии приложения
 */
data class AppVersionInfo(
    val versionName: String,
    val versionCode: Int,
    val downloadUrl: String?,
    val changelog: String? = null,
    val isPrerelease: Boolean = false,
    val isCritical: Boolean = false
) {
    /**
     * Определить критичность обновления по changelog
     */
    fun determineCriticality(): Boolean {
        if (isCritical) return true
        
        // Проверяем changelog на ключевые слова, указывающие на критическое обновление
        val changelogText = changelog?.lowercase() ?: ""
        val criticalKeywords = listOf(
            "critical", "критическое", "критично",
            "security", "безопасность",
            "fix", "исправление",
            "bug", "баг",
            "crash", "падение",
            "urgent", "срочно"
        )
        
        return criticalKeywords.any { keyword ->
            changelogText.contains(keyword, ignoreCase = true)
        }
    }
    
    /**
     * Проверить, является ли версия beta/alpha/pre-release
     */
    fun isPreReleaseVersion(): Boolean {
        if (isPrerelease) return true
        
        val versionLower = versionName.lowercase()
        return versionLower.contains("-beta") || 
               versionLower.contains("-alpha") || 
               versionLower.contains("-rc") ||
               versionLower.contains("preview") ||
               versionLower.contains("dev")
    }
}

object AppUpdateChecker {
    private const val TAG = "AppUpdateChecker"
    
    // GitHub Releases API URL для проверки версии
    private const val VERSION_CHECK_URL = "https://api.github.com/repos/Everelsu/Raspisanie/releases/latest"
    
    /**
     * Получить текущую версию приложения
     */
    fun getCurrentVersion(context: Context): AppVersionInfo? {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }
            
            AppVersionInfo(
                versionName = packageInfo.versionName ?: "unknown",
                versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    packageInfo.longVersionCode.toInt()
                } else {
                    @Suppress("DEPRECATION")
                    packageInfo.versionCode
                },
                downloadUrl = null
            )
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка получения версии приложения", e)
            null
        }
    }
    
    /**
     * Проверить наличие новой версии через GitHub Releases API
     */
    suspend fun checkForUpdates(context: Context): UpdateCheckResult {
        return withContext(Dispatchers.IO) {
            try {
                val currentVersion = getCurrentVersion(context) ?: return@withContext UpdateCheckResult.Error("Не удалось получить текущую версию")
                
                Log.d(TAG, "Проверка обновлений. Текущая версия: ${currentVersion.versionName} (${currentVersion.versionCode})")
                
                // Получить информацию о последнем релизе из GitHub
                val jsonResponse = Jsoup.connect(VERSION_CHECK_URL)
                    .ignoreContentType(true)
                    .timeout(10000)
                    .userAgent("Raspisanie-UpdateChecker")
                    .get()
                    .text()
                
                val jsonObject = JSONObject(jsonResponse)
                val latestVersionName = jsonObject.getString("tag_name").replace("v", "").replace("V", "") // Убрать префикс v/V из тега
                
                // Получить описание (changelog) из body
                val changelogText = jsonObject.optString("body", "")
                val changelog = changelogText.takeIf { it.isNotBlank() }
                
                // Пытаемся получить versionCode из changelog или имени файла APK
                // ID релиза GitHub не является versionCode, поэтому не используем его для сравнения
                var latestVersionCode = -1
                try {
                    // Попытаться извлечь versionCode из changelog (если указан в формате "versionCode: 123")
                    if (changelogText.isNotBlank()) {
                        val versionCodeMatch = Regex("versionCode[\\s:=]+(\\d+)", RegexOption.IGNORE_CASE).find(changelogText)
                        if (versionCodeMatch != null) {
                            latestVersionCode = versionCodeMatch.groupValues[1].toIntOrNull() ?: -1
                            Log.d(TAG, "Найден versionCode в changelog: $latestVersionCode")
                        }
                    }
                    
                    // Если не найден в changelog, попытаться извлечь из имени файла APK
                    if (latestVersionCode == -1) {
                        val assetsArray = jsonObject.getJSONArray("assets")
                        for (i in 0 until assetsArray.length()) {
                            val asset = assetsArray.getJSONObject(i)
                            val fileName = asset.optString("name", "")
                            // Искать versionCode в имени файла (например: app-123-release.apk или Raspisanie.1.0.4.apk)
                            val codeMatch = Regex("(?:app|raspisanie)[-_]?(\\d+)(?:\\.\\d+)*", RegexOption.IGNORE_CASE).find(fileName)
                            if (codeMatch != null) {
                                // Извлечь первую цифру (может быть версией типа 1.0.4)
                                val versionStr = codeMatch.groupValues[1]
                                latestVersionCode = versionStr.toIntOrNull() ?: -1
                                if (latestVersionCode > 0) {
                                    Log.d(TAG, "Найден versionCode в имени файла: $latestVersionCode (из $fileName)")
                                    break
                                }
                            }
                        }
                    }
                    
                    if (latestVersionCode == -1) {
                        Log.d(TAG, "versionCode не найден, будет использоваться только сравнение по versionName")
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Не удалось извлечь versionCode: ${e.message}")
                }
                
                // Проверить, является ли релиз pre-release
                val isPrerelease = jsonObject.optBoolean("prerelease", false)
                
                // Проверить критичность обновления по changelog
                val isCritical = changelog?.let { changelogText ->
                    val lowerChangelog = changelogText.lowercase()
                    val criticalIndicators = listOf(
                        "critical", "критическое", "критично",
                        "security", "безопасность", "уязвимость",
                        "urgent", "срочно", "экстренное"
                    )
                    criticalIndicators.any { indicator ->
                        lowerChangelog.contains(indicator, ignoreCase = true)
                    }
                } ?: false
                
                // Найти ссылку на APK файл в assets
                val assetsArray = jsonObject.getJSONArray("assets")
                var downloadUrl: String? = null
                for (i in 0 until assetsArray.length()) {
                    val asset = assetsArray.getJSONObject(i)
                    val fileName = asset.getString("browser_download_url")
                    if (fileName.endsWith(".apk", ignoreCase = true)) {
                        downloadUrl = asset.getString("browser_download_url")
                        break
                    }
                }
                
                if (downloadUrl == null) {
                    Log.w(TAG, "APK файл не найден в релизе")
                    return@withContext UpdateCheckResult.Error("APK файл не найден в релизе")
                }
                
                val latestVersion = AppVersionInfo(
                    versionName = latestVersionName,
                    versionCode = latestVersionCode,
                    downloadUrl = downloadUrl,
                    changelog = changelog,
                    isPrerelease = isPrerelease,
                    isCritical = isCritical
                )
                
                val versionType = when {
                    latestVersion.isPreReleaseVersion() -> "pre-release"
                    latestVersion.isCritical -> "критическое"
                    else -> "stable"
                }
                
                // Логирование для отладки
                Log.d(TAG, "=== Проверка обновлений ===")
                Log.d(TAG, "Текущая версия: ${currentVersion.versionName} (code: ${currentVersion.versionCode})")
                Log.d(TAG, "Последняя версия на GitHub: ${latestVersion.versionName} (code: ${latestVersion.versionCode}, type: $versionType)")
                
                // Проверка: если последняя версия - pre-release, пропустить (по умолчанию не показывать beta пользователям)
                // Но если пользователь уже на beta - показывать
                val currentIsPreRelease = currentVersion.versionName.lowercase().let {
                    it.contains("-beta") || it.contains("-alpha") || it.contains("-rc") ||
                    it.contains("preview") || it.contains("dev")
                }
                
                // Показывать pre-release только если текущая версия тоже pre-release
                if (latestVersion.isPreReleaseVersion() && !currentIsPreRelease) {
                    Log.d(TAG, "Пропускаем pre-release версию (текущая версия стабильная)")
                    return@withContext UpdateCheckResult.NoUpdate
                }
                
                // Сравнить версии с учетом versionCode
                val comparison = compareVersions(latestVersion, currentVersion)
                
                if (comparison > 0) {
                    val updateType = if (latestVersion.isCritical) "критическое" else "обычное"
                    Log.d(TAG, "Найдена новая версия ($updateType): ${latestVersion.versionName} (текущая: ${currentVersion.versionName})")
                    UpdateCheckResult.UpdateAvailable(latestVersion)
                } else if (comparison < 0) {
                    Log.w(TAG, "Текущая версия новее, чем на GitHub (возможно, beta/dev версия)")
                    UpdateCheckResult.NoUpdate
                } else {
                    Log.d(TAG, "Версия совпадает, обновлений не найдено")
                    UpdateCheckResult.NoUpdate
                }
                
            } catch (e: org.jsoup.HttpStatusException) {
                if (e.statusCode == 404) {
                    Log.d(TAG, "Релизы не найдены на GitHub")
                    UpdateCheckResult.NoUpdate
                } else {
                    Log.e(TAG, "Ошибка HTTP при проверке обновлений: ${e.statusCode}", e)
                    UpdateCheckResult.Error("Ошибка соединения: ${e.statusCode}")
                }
            } catch (e: java.net.SocketTimeoutException) {
                Log.e(TAG, "Таймаут при проверке обновлений", e)
                UpdateCheckResult.Error("Таймаут соединения")
            } catch (e: java.net.UnknownHostException) {
                Log.e(TAG, "Нет интернета при проверке обновлений", e)
                UpdateCheckResult.Error("Нет подключения к интернету")
            } catch (e: Exception) {
                Log.e(TAG, "Ошибка при проверке обновлений", e)
                UpdateCheckResult.Error(e.message ?: "Неизвестная ошибка")
            }
        }
    }
    
    /**
     * Сравнить версии с учетом versionCode (возвращает > 0 если version1 > version2)
     * Приоритет: сначала versionName (более надежно), затем versionCode (если доступен и корректный)
     */
    private fun compareVersions(
        latestVersion: AppVersionInfo,
        currentVersion: AppVersionInfo
    ): Int {
        // Сначала сравниваем по versionName (более надежно, так как versionCode может быть некорректным)
        val nameComparison = compareVersionNames(latestVersion.versionName, currentVersion.versionName)
        
        // Если versionName отличается - используем его
        if (nameComparison != 0) {
            Log.d(TAG, "Сравнение по versionName: $nameComparison (${latestVersion.versionName} vs ${currentVersion.versionName})")
            return nameComparison
        }
        
        // Если versionName одинаковый, проверяем versionCode (только если оба корректные)
        if (latestVersion.versionCode > 0 && currentVersion.versionCode > 0) {
            val codeDiff = latestVersion.versionCode - currentVersion.versionCode
            if (codeDiff != 0) {
                Log.d(TAG, "Сравнение по versionCode: $codeDiff (${latestVersion.versionCode} vs ${currentVersion.versionCode})")
                return codeDiff
            }
        }
        
        // Версии равны
        Log.d(TAG, "Версии равны")
        return 0
    }
    
    /**
     * Сравнить версии по строке (возвращает > 0 если version1 > version2)
     * Поддерживает семантическое версионирование (1.2.3) и дополнительные суффиксы (-beta, -alpha)
     */
    private fun compareVersionNames(version1: String, version2: String): Int {
        // Убрать префиксы v/V и суффиксы для сравнения
        val v1 = version1.replace(Regex("^[vV]"), "").split("-").first().trim()
        val v2 = version2.replace(Regex("^[vV]"), "").split("-").first().trim()
        
        val v1Parts = v1.split(".").map { it.toIntOrNull() ?: 0 }
        val v2Parts = v2.split(".").map { it.toIntOrNull() ?: 0 }
        
        val maxLength = maxOf(v1Parts.size, v2Parts.size)
        
        for (i in 0 until maxLength) {
            val v1Part = v1Parts.getOrElse(i) { 0 }
            val v2Part = v2Parts.getOrElse(i) { 0 }
            
            when {
                v1Part > v2Part -> return 1
                v1Part < v2Part -> return -1
            }
        }
        
        // Если версии одинаковые, проверить суффиксы (beta < release)
        val v1Suffix = version1.split("-").getOrNull(1)?.lowercase() ?: ""
        val v2Suffix = version2.split("-").getOrNull(1)?.lowercase() ?: ""
        
        if (v1Suffix.isEmpty() && v2Suffix.isNotEmpty()) return 1 // release > beta/alpha
        if (v1Suffix.isNotEmpty() && v2Suffix.isEmpty()) return -1 // beta/alpha < release
        if (v1Suffix != v2Suffix) {
            // beta < alpha < release
            val suffixOrder = mapOf("beta" to 1, "alpha" to 2, "" to 3)
            val v1Order = suffixOrder.getOrDefault(v1Suffix, 0)
            val v2Order = suffixOrder.getOrDefault(v2Suffix, 0)
            return (v1Order - v2Order).coerceIn(-1, 1)
        }
        
        return 0
    }
    
    sealed class UpdateCheckResult {
        data class UpdateAvailable(val versionInfo: AppVersionInfo) : UpdateCheckResult()
        object NoUpdate : UpdateCheckResult()
        data class Error(val message: String) : UpdateCheckResult()
    }
}

