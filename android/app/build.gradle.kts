import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
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

    defaultConfig {
        applicationId = "com.example.raspiflutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Отключено из-за дублирования SharedPreferencesPlugin при R8 (flutter/plugin)
            isMinifyEnabled = false
            isShrinkResources = false
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

// Убираем дубликат SharedPreferencesPlugin: класс остаётся только из плагина.
tasks.whenTaskAdded {
    if (name == "mergeDexRelease") {
        doFirst {
            val buildDir = layout.buildDirectory.get().asFile
            val dexOut = File(buildDir, "intermediates/project_dex_archive/release/dexBuilderRelease/out")
            if (dexOut.exists()) {
                val pluginDex = File(dexOut, "io/flutter/plugins/sharedpreferences/SharedPreferencesPlugin.dex")
                if (pluginDex.exists()) pluginDex.delete()
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
