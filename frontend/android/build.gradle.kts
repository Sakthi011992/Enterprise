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

// Some plugins pin an old compileSdk while their dependencies need 36+.
subprojects {
    val raiseCompileSdk = {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { android ->
            val current = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current < 36) android.compileSdkVersion(36)
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
