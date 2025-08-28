plugins {
    id("com.android.application")
    id("com.google.gms.google-services")     // FlutterFire
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")  // Flutter 플러그인은 마지막
}

android {
    namespace = "com.example.gf_alarm_api"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // ✅ desugaring 활성화 (여기가 정답)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.gf_alarm_api"
        minSdk = 21
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ❌ 아래 Groovy식 블록 제거 (필요 없음)
        // javaCompileOptions {
        //     annotationProcessorOptions {
        //         arguments {
        //             put("enableDesugaring", "true")
        //         }
        //     }
        // }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 권장: ktx 사용
    implementation("androidx.core:core-ktx:1.13.1")
    // ▶ AppCompat 테마 사용 시 필수
    implementation("androidx.appcompat:appcompat:1.7.0")

    // ▶ Material3 테마(Theme.Material3.*) 쓸 경우 필요
    implementation("com.google.android.material:material:1.12.0")

    // ✅ desugaring 라이브러리는 전용 configuration 사용
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")

    // (선택) Firebase BOM 사용 시:
    implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
    implementation("com.google.firebase:firebase-messaging")
}
