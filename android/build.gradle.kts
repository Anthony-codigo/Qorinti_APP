allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Ajusta la carpeta de build (opcional)
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    //Unifica jvmTarget en todos los submódulos (incluye google_api_headers)
    afterEvaluate {
        extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinJvmOptions::class.java)?.apply {
            jvmTarget = "1.8"
        }
    }
}

// Asegura que flutter clean limpie bien
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

plugins {
    // Firebase / Google Services plugin
    id("com.google.gms.google-services") version "4.4.3" apply false
}
