import java.io.File

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
