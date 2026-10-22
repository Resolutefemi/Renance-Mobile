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

// Round-8 (founder pass VIII): plugin modules that ship Java+Kotlin
// sources (flutter_timezone) can disagree on the JVM bytecode target -
// their Java task compiles at 11 while their Kotlin task falls back to
// 1.8, which Gradle rejects. Pin every Kotlin compile in every module to
// the same target the Java side already uses.
// Lazy rule - safe even for subprojects that are already evaluated.
// One JVM target for EVERY module, both compilers, so the Java/Kotlin
// consistency check can never trip again (plugins ship different pins).
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.name
        targetCompatibility = JavaVersion.VERSION_17.name
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
        .configureEach {
            compilerOptions.jvmTarget
                .set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
