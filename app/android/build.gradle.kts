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
// Some plugins (file_picker 8.3.7 among them) pin compileSdk 34 in their own
// build.gradle, but flutter_plugin_android_lifecycle requires callers to compile
// against 36. Raise every subproject to the platform we actually installed so the
// AAR metadata check stops failing.
// This has to be registered BEFORE the evaluationDependsOn block below, because
// that block evaluates :app and afterEvaluate() may no longer be called on it.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
