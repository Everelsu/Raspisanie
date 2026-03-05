// Patch isar_flutter_libs for AGP 8+ namespace (runs before plugin is configured)
val isarBuildGradle = System.getenv("LOCALAPPDATA")?.replace("\\", "/")?.let { "$it/Pub/Cache/hosted/pub.dev/isar_flutter_libs-3.1.0+1/android/build.gradle" }
    ?: (System.getenv("PUB_CACHE")?.replace("\\", "/")?.let { "$it/hosted/pub.dev/isar_flutter_libs-3.1.0+1/android/build.gradle" })
if (isarBuildGradle != null) {
    val isarFile = file(isarBuildGradle)
    if (isarFile.exists()) {
        var content = isarFile.readText()
        var changed = false
        if (!content.contains("namespace")) {
            content = content.replace("android {", "android {\n    namespace 'dev.isar.isar_flutter_libs'")
            changed = true
        }
        if (content.contains("compileSdkVersion 30") && !content.contains("compileSdkVersion 34")) {
            content = content.replace("compileSdkVersion 30", "compileSdkVersion 34")
            changed = true
        }
        if (changed) isarFile.writeText(content)
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

