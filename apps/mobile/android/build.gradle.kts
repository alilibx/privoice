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

// file_picker 11.0.2's android/build.gradle applies the Kotlin plugin only when
// AGP is below 9, on the assumption that AGP 9 means Kotlin is built in. This
// project is on AGP 9.0.1 but the Flutter template sets
// `android.builtInKotlin=false` in gradle.properties, so neither path applies a
// Kotlin compiler: file_picker's Kotlin sources are silently never compiled and
// the build fails late, in :app:compileDebugJavaWithJavac, with
// "cannot find symbol: class FilePickerPlugin" from GeneratedPluginRegistrant.
//
// Applying the plugin here for that one module is narrower than flipping
// builtInKotlin globally, which would change how every other module compiles.
// Remove once file_picker handles AGP 9 without built-in Kotlin.
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
