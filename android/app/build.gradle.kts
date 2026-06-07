import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.raspiflutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        // Если android/key.properties существует — используем релизный keystore.
        // Иначе release-сборка подписывается debug-ключом (для локальной разработки).
        val keyPropsFile = rootProject.file("key.properties")
        if (keyPropsFile.exists()) {
            val keyProps = Properties().also { it.load(keyPropsFile.inputStream()) }
            create("release") {
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.raspiflutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        debug {
            // В debug-режиме Crashlytics отключён на уровне манифеста —
            // иначе SDK инициализирует сессию и падает с ENOENT в logcat.
            manifestPlaceholders["firebaseCrashlyticsEnabled"] = false
        }
        release {
            val hasReleaseKey = signingConfigs.findByName("release") != null
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                           else signingConfigs.getByName("debug")
            manifestPlaceholders["firebaseCrashlyticsEnabled"] = true
            // Минификация + сжатие ресурсов уменьшают размер APK. Если R8 выдаст duplicate class —
            // поставь isMinifyEnabled = false (isShrinkResources оставь true).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
}

// R8 падает из-за дубликата SharedPreferencesPlugin (плагин + копия в app). Удаляем копию до minify.
tasks.whenTaskAdded {
    if (name == "minifyReleaseWithR8") {
        doFirst {
            val buildDir = layout.buildDirectory.get().asFile
            val appClasses = File(buildDir, "intermediates/javac/release/compileReleaseJavaWithJavac/classes")
            val duplicate = File(appClasses, "io/flutter/plugins/sharedpreferences/SharedPreferencesPlugin.class")
            if (duplicate.exists()) {
                duplicate.delete()
            }
        }
    }
}

// Suppress "source value 8 is obsolete" from plugin dependencies
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:-options")
}

flutter {
    source = "../.."
}
