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
    val changelog: String? = null
)

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
                val latestVersionCode = try {
                    // Пытаемся получить versionCode из body или assets
                    jsonObject.optInt("id", -1) // Используем ID релиза как fallback, лучше добавить versionCode в body
                } catch (e: Exception) {
                    -1
                }
                
                // Получить описание (changelog) из body
                val changelog = jsonObject.optString("body", "").takeIf { it.isNotBlank() }
                
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
                    changelog = changelog
                )
                
                Log.d(TAG, "Последняя версия на GitHub: ${latestVersion.versionName}")
                
                // Сравнить версии
                val comparison = compareVersions(latestVersion.versionName, currentVersion.versionName)
                
                if (comparison > 0) {
                    Log.d(TAG, "Найдена новая версия: ${latestVersion.versionName}")
                    UpdateCheckResult.UpdateAvailable(latestVersion)
                } else {
                    Log.d(TAG, "Обновлений не найдено")
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
     * Сравнить версии (возвращает > 0 если version1 > version2)
     */
    private fun compareVersions(version1: String, version2: String): Int {
        val v1Parts = version1.split(".").map { it.toIntOrNull() ?: 0 }
        val v2Parts = version2.split(".").map { it.toIntOrNull() ?: 0 }
        
        val maxLength = maxOf(v1Parts.size, v2Parts.size)
        
        for (i in 0 until maxLength) {
            val v1Part = v1Parts.getOrElse(i) { 0 }
            val v2Part = v2Parts.getOrElse(i) { 0 }
            
            when {
                v1Part > v2Part -> return 1
                v1Part < v2Part -> return -1
            }
        }
        
        return 0
    }
    
    sealed class UpdateCheckResult {
        data class UpdateAvailable(val versionInfo: AppVersionInfo) : UpdateCheckResult()
        object NoUpdate : UpdateCheckResult()
        data class Error(val message: String) : UpdateCheckResult()
    }
}

