plugins {
    id("com.android.library")
    id("kotlin-android")
}

group = "one.mixin.oggOpusPlayer"
version = "1.0.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.13.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

android {
    namespace = "one.mixin.oggOpusPlayer"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    sourceSets["main"].java.srcDirs("src/main/kotlin")

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}


dependencies {
    val mediaVersion = "1.8.0"

    implementation("androidx.media3:media3-exoplayer:$mediaVersion")
    implementation("androidx.media3:media3-common:$mediaVersion")
}
