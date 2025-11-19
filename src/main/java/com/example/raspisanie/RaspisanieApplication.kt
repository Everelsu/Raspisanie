package com.example.raspisanie

import android.util.Log
import androidx.multidex.MultiDexApplication
import java.io.PrintWriter
import java.io.StringWriter

class RaspisanieApplication : MultiDexApplication() {
    companion object {
        private const val TAG = "RaspisanieApp"
    }
    
    override fun onCreate() {
        super.onCreate()
        // MultiDexApplication автоматически вызывает MultiDex.install()
        
        // Установить глобальный обработчик необработанных исключений
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            handleUncaughtException(thread, throwable, defaultHandler)
        }
        
        Log.d(TAG, "Application инициализировано")
    }
    
    private fun handleUncaughtException(thread: Thread, throwable: Throwable, defaultHandler: Thread.UncaughtExceptionHandler?) {
        try {
            // Логируем полную информацию об ошибке
            val stackTrace = StringWriter()
            throwable.printStackTrace(PrintWriter(stackTrace))
            
            Log.e(TAG, "КРИТИЧЕСКАЯ ОШИБКА в потоке ${thread.name}: ${throwable.message}")
            Log.e(TAG, "Stack trace:\n${stackTrace.toString()}")
            
            // Здесь можно добавить отправку на сервер (Firebase Crashlytics, Sentry и т.д.)
            // FirebaseCrashlytics.getInstance().recordException(throwable)
            
        } catch (e: Exception) {
            // Если даже обработка ошибки упала, логируем хотя бы основную информацию
            Log.e(TAG, "Ошибка при обработке исключения: ${e.message}")
        } finally {
            // Вызываем стандартный обработчик для завершения процесса
            try {
                defaultHandler?.uncaughtException(thread, throwable)
            } catch (e: Exception) {
                // Если стандартный обработчик тоже упал, завершаем процесс напрямую
                Log.e(TAG, "Ошибка в стандартном обработчике: ${e.message}", e)
                android.os.Process.killProcess(android.os.Process.myPid())
                System.exit(10)
            }
        }
    }
}

