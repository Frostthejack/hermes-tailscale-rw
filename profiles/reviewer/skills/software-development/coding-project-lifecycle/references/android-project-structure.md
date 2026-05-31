# Android Project Structure Reference

> Reference for scaffolding Android projects with Kotlin + Jetpack Compose + Hilt + Room.

## Gradle Configuration

### Root `build.gradle.kts`
```kotlin
plugins {
    id 'com.android.application' version '8.2.0' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.20' apply false
    id 'com.google.dagger.hilt.android' version '2.48' apply false
    id 'org.jetbrains.kotlin.kapt' version '1.9.20' apply false
}
```

### `settings.gradle.kts`
```kotlin
pluginManagement {
    repositories { google(); mavenCentral(); gradlePortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "AppName"
include(":app")
```

### `gradle.properties`
```properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
```

### App `build.gradle.kts` — Key Dependencies
```kotlin
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
    id 'com.google.dagger.hilt.android'
    id 'org.jetbrains.kotlin.kapt'
}

android {
    namespace 'com.app.name'
    compileSdk 34
    defaultConfig {
        applicationId "com.app.name"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "0.1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
    buildFeatures { compose true }
    composeOptions { kotlinCompilerExtensionVersion '1.5.5' }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.6.2'
    implementation 'androidx.activity:activity-compose:1.8.1'
    implementation platform('androidx.compose:compose-bom:2023.10.01')
    implementation 'androidx.compose.ui:ui'
    implementation 'androidx.compose.material3:material3'
    implementation 'com.google.dagger:hilt-android:2.48'
    kapt 'com.google.dagger:hilt-compiler:2.48'
    implementation 'androidx.room:room-runtime:2.6.1'
    implementation 'androidx.room:room-ktx:2.6.1'
    kapt 'androidx.room:room-compiler:2.6.1'
    implementation 'com.squareup.retrofit2:retrofit:2.9.0'
    implementation 'com.squareup.retrofit2:converter-gson:2.9.0'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    implementation 'io.coil-kt:coil-compose:2.5.0'
}
```

## Source Directory Structure
```
app/src/main/java/com/app/name/
├── data/
│   ├── local/
│   │   ├── dao/          # Room DAOs
│   │   ├── entity/       # Room entities
│   │   └── database/     # Room database class
│   ├── remote/           # API clients (Retrofit)
│   └── repository/       # Repository implementations
├── domain/
│   ├── model/            # Domain models
│   ├── repository/       # Repository interfaces
│   └── usecase/          # Use cases
├── ui/
│   ├── <feature>/        # Feature screens (ViewModel + Composables)
│   └── theme/            # Compose theme
├── di/                   # Hilt modules
└── AppApplication.kt     # @HiltAndroidApp
```

## Key Files

### AndroidManifest.xml — Common Permissions
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### Application Class
```kotlin
@HiltAndroidApp
class AppApplication : Application()
```

### Hilt Database Module Pattern
```kotlin
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    @Provides @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(context, AppDatabase::class.java, "app_database").build()
    }
    @Provides fun provideDao(db: AppDatabase) = db.dao()
}
```

## Verification Checklist
- [ ] Project builds without errors
- [ ] Hilt compiles (no missing `@Inject` or `@Provides`)
- [ ] Room schema exports without errors
- [ ] Compose preview renders
- [ ] App launches on emulator/device
