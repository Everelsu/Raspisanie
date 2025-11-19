# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# ============================================
# Widget-related classes - MUST be kept
# ============================================

# Keep all widget providers
-keep class com.example.raspisanie.widget.** { *; }

# Keep widget service
-keep class com.example.raspisanie.widget.ScheduleWidgetService { *; }
-keep class com.example.raspisanie.widget.ScheduleWidgetService$* { *; }

# Keep PreferencesManager - used by widgets
-keep class com.example.raspisanie.data.PreferencesManager { *; }
-keep class com.example.raspisanie.data.PreferencesManager$* { *; }

# Keep data classes used by widgets
-keep class com.example.raspisanie.data.ScheduleItem { *; }
-keep class com.example.raspisanie.data.DaySchedule { *; }
-keep class com.example.raspisanie.data.LessonTime { *; }

# Keep ScheduleCache - used by widgets
-keep class com.example.raspisanie.data.ScheduleCache { *; }

# Keep LessonTimes object - used by widgets
-keep class com.example.raspisanie.data.LessonTimes { *; }

# Keep DayProgressCalculator object - used by widgets
-keep class com.example.raspisanie.data.DayProgressCalculator { *; }

# Keep MainActivity - widgets create PendingIntent for it
-keep class com.example.raspisanie.MainActivity { *; }

# Keep Application class
-keep class com.example.raspisanie.RaspisanieApplication { *; }

# Keep Worker classes - used by WorkManager
-keep class com.example.raspisanie.data.ScheduleRefreshWorker { *; }
-keep class com.example.raspisanie.data.AppUpdateCheckWorker { *; }

# Keep all data classes in data package (for serialization/caching)
-keep class com.example.raspisanie.data.** { *; }

# ============================================
# Gson rules - required for serialization
# ============================================

# Keep attributes needed for Gson
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes Exceptions
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault

# Keep Gson classes
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }

# Keep TypeToken classes used by Gson
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.reflect.TypeToken

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}