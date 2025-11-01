package com.example.raspisanie.data

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * BroadcastReceiver для отслеживания завершения загрузки APK и автоматической установки
 */
class DownloadCompleteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
            val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            
            if (downloadId == -1L) return
            
            Log.d(TAG, "Загрузка завершена: $downloadId")
            
            // Получить информацию о загруженном файле
            val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val query = DownloadManager.Query().setFilterById(downloadId)
            val cursor: Cursor = downloadManager.query(query)
            
            if (cursor.moveToFirst()) {
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val title = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE))
                
                if (status == DownloadManager.STATUS_SUCCESSFUL && title == "Обновление приложения") {
                    // Получить URI загруженного файла
                    var fileUri: Uri? = null
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        // Android 10+: использовать URI из DownloadManager
                        fileUri = downloadManager.getUriForDownloadedFile(downloadId)
                    } else {
                        // Старые версии Android: получить путь из COLUMN_LOCAL_URI
                        val localUri = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                        if (localUri != null) {
                            val file = File(Uri.parse(localUri).path ?: return)
                            if (file.exists()) {
                                fileUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    FileProvider.getUriForFile(
                                        context,
                                        "${context.packageName}.fileprovider",
                                        file
                                    )
                                } else {
                                    Uri.fromFile(file)
                                }
                            }
                        }
                    }
                    
                    if (fileUri != null) {
                        Log.d(TAG, "Начинаю установку APK: $fileUri")
                        installApk(context, fileUri)
                    } else {
                        Log.e(TAG, "Не удалось получить URI загруженного файла")
                        
                        // Fallback: попробовать найти файл по стандартному пути
                        val downloadsDir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                        } else {
                            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                        }
                        
                        val apkFile = File(downloadsDir, "raspisanie_update.apk")
                        if (apkFile.exists()) {
                            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                FileProvider.getUriForFile(
                                    context,
                                    "${context.packageName}.fileprovider",
                                    apkFile
                                )
                            } else {
                                Uri.fromFile(apkFile)
                            }
                            installApk(context, uri)
                        }
                    }
                } else {
                    Log.e(TAG, "Загрузка не удалась или это не наш файл. Status: $status")
                }
            }
            
            cursor.close()
        }
    }
    
    private fun installApk(context: Context, apkUri: Uri) {
        try {
            // Проверить разрешение на установку неизвестных источников (для Android 8.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!context.packageManager.canRequestPackageInstalls()) {
                    Log.w(TAG, "Нет разрешения на установку неизвестных источников")
                    // Можно показать диалог для запроса разрешения
                    // Но пока просто попробуем установить - система покажет диалог
                }
            }
            
            // Сохранить URI для последующего удаления
            saveApkUriForCleanup(context, apkUri)
            
            val intent = Intent(Intent.ACTION_VIEW).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                setDataAndType(apkUri, "application/vnd.android.package-archive")
            }
            
            context.startActivity(intent)
            Log.d(TAG, "Запущена установка APK")
            
            // Запланировать удаление файла через 10 секунд (после завершения установки)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                deleteApkFile(context, apkUri)
            }, 10000)
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при установке APK", e)
        }
    }
    
    private fun saveApkUriForCleanup(context: Context, apkUri: Uri) {
        val prefs = context.getSharedPreferences("schedule_prefs", Context.MODE_PRIVATE)
        val apkPath = getFilePathFromUri(context, apkUri)
        if (apkPath != null) {
            prefs.edit().putString("pending_apk_cleanup", apkPath).apply()
            Log.d(TAG, "Сохранён путь для очистки: $apkPath")
        }
    }
    
    private fun getFilePathFromUri(context: Context, uri: Uri): String? {
        return try {
            if (uri.scheme == "file") {
                uri.path
            } else if (uri.scheme == "content") {
                // Для content URI нужно получить реальный путь
                var result: String? = null
                context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (index != -1) {
                            val fileName = cursor.getString(index)
                            // Попробовать найти файл в известных местах
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            val file = File(downloadsDir, fileName)
                            if (file.exists()) {
                                result = file.absolutePath
                            } else {
                                // Попробовать app-specific directory
                                val appDownloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                                val appFile = appDownloadsDir?.let { File(it, fileName) }
                                if (appFile != null && appFile.exists()) {
                                    result = appFile.absolutePath
                                }
                            }
                        }
                    }
                }
                result
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при получении пути файла", e)
            null
        }
    }
    
    private fun deleteApkFile(context: Context, apkUri: Uri) {
        try {
            val filePath = getFilePathFromUri(context, apkUri)
            if (filePath != null) {
                val file = File(filePath)
                if (file.exists() && file.delete()) {
                    Log.d(TAG, "APK файл удалён: $filePath")
                } else {
                    Log.w(TAG, "Не удалось удалить APK файл: $filePath")
                }
            }
            
            // Также попробовать удалить через стандартные пути
            val fileName = "raspisanie_update.apk"
            val locations = listOf(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                context.getExternalFilesDir(null)?.let { File(it, "downloads") }
            )
            
            locations.forEach { dir ->
                dir?.let {
                    val file = File(it, fileName)
                    if (file.exists() && file.delete()) {
                        Log.d(TAG, "APK файл удалён: ${file.absolutePath}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка при удалении APK файла", e)
        }
    }
    
    companion object {
        private const val TAG = "DownloadCompleteReceiver"
    }
}

