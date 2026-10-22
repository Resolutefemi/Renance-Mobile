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
subprojects {
    afterEvaluate {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions.jvmTarget
                    .set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
