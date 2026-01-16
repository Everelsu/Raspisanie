plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    // Используем KSP вместо kapt для Kotlin 2.0+
    id("com.google.devtools.ksp") version "2.0.0-1.0.24"
    // Google Services plugin нужен для OneSignal (использует FCM)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.raspisanie"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.raspisanie"
        minSdk = 28
        targetSdk = 34
        versionCode = 3
        versionName = "1.2.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        
        // Включить MultiDex для поддержки устройств с ограниченной памятью
        multiDexEnabled = true
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // Оптимизации для отладки
            isMinifyEnabled = false
            isDebuggable = true
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        viewBinding = true
        dataBinding = false
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)

    // OneSignal Push Notifications (бесплатно до 10,000 подписчиков)
    implementation("com.onesignal:OneSignal:[5.0.0, 5.99.99]")

    // OkHttp for admin push panel
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Jsoup for HTML parsing
    implementation("org.jsoup:jsoup:1.17.2")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")

    // RecyclerView
    implementation("androidx.recyclerview:recyclerview:1.3.2")

    // SwipeRefreshLayout
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.2.0-alpha01")

    // CardView
    implementation("androidx.cardview:cardview:1.0.0")
    
    // Gson for JSON serialization (for caching)
    implementation("com.google.code.gson:gson:2.10.1")
    
    // WorkManager for auto refresh
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    
    // MultiDex для поддержки устройств с ограниченной памятью
    implementation("androidx.multidex:multidex:2.0.1")
    
    // Fragment
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    
    // Markwon for Markdown rendering
    implementation("io.noties.markwon:core:4.6.2")
    implementation("io.noties.markwon:image:4.6.2")
    implementation("io.noties.markwon:image-glide:4.6.2")
    implementation("io.noties.markwon:html:4.6.2")
    implementation("io.noties.markwon:ext-tables:4.6.2")
    implementation("io.noties.markwon:ext-strikethrough:4.6.2")
    implementation("io.noties.markwon:linkify:4.6.2")
    
    // Glide for image loading
    implementation("com.github.bumptech.glide:glide:4.16.0")
    
    // Room database
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")
}