-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

-keep class com.example.raspiflutter.** { *; }

# flutter_local_notifications — ресиверы и сервисы объявлены в манифесте,
# но R8 может их удалить если нет явного keep.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Service { *; }

# WorkManager / workmanager plugin
-keep class androidx.work.** { *; }
-keep class be.tramckrijte.workmanager.** { *; }

# Firebase — сохранить стек-трейсы в Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Прочие атрибуты
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
