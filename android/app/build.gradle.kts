import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.reader(Charsets.UTF_8).use { load(it) }
}
val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0.0"

val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasKeystore = keystoreProps.getProperty("storeFile")?.isNotBlank() == true

android {
    namespace = "com.example.mahmut_sami_ramazanoglu_ihl"

    // AGP 8.7.x ile uyumlu
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.mahmut_sami_ramazanoglu_ihl"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName

        // Emülatör ve fiziksel cihazlar için tüm ABI'ler
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }

        // 65K methodu aşarsan aç
        // multiDexEnabled = true
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    // Tek APK üret (split kapalı)
    splits {
        abi {
            isEnable = false          // universal apk
            // isUniversalApk = true   // (split'i açarsan bunu true yap)
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            signingConfig = signingConfigs.getByName(if (hasKeystore) "release" else "debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }

    lint { disable += setOf("InvalidPackage") }

    packaging {
        resources.excludes += setOf(
            "META-INF/DEPENDENCIES",
            "META-INF/LICENSE*",
            "META-INF/AL2.0",
            "META-INF/LGPL2.1"
        )
    }
}

flutter { source = "../.." }

configurations.all {
    resolutionStrategy {
        force(
            "androidx.core:core:1.13.1",
            "androidx.core:core-ktx:1.13.1"
        )
    }
}

dependencies {
    implementation("androidx.core:core:1.13.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // 65K method sınırı için:
    // implementation("androidx.multidex:multidex:2.0.1")
}

kotlin {
    jvmToolchain(17)
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}
