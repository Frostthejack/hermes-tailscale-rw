# Android Build & Dependency Pitfalls

> Common build failures and dependency issues specific to Android projects (Kotlin + Jetpack Compose + Hilt + Room) when working from WSL2 or managing Compose BOM versions.

## WSL2 ↔ Windows Android SDK Path Issue

**Symptom:** Gradle fails with `SDK location not found` or `Build-tool 34.0.0 is missing AAPT` when running `./gradlew` from WSL2, even though the SDK exists on Windows.

**Cause:** `local.properties` contains a Windows path (`sdk.dir=C:\Users\...`) which WSL2's Gradle cannot resolve. WSL2 sees the filesystem at `/mnt/c/`.

**Fix — Build from WSL2:**
```bash
# Temporarily override local.properties for WSL2 builds
echo "sdk.dir=/mnt/c/Users/<user>/AppData/Local/Android/Sdk" > local.properties
./gradlew assembleDebug
```

**Fix — Build from Windows (recommended for Android):**
```powershell
# Run from PowerShell on Windows, not WSL2
cd C:\Users\<user>\Documents\Projects\<project>
.\gradlew assembleDebug
```

> **Note:** Android Studio on Windows uses the Windows path in `local.properties`. If you change it for WSL2, Android Studio may break. The safest approach is to keep `local.properties` with the Windows path and only build Android from Windows PowerShell/Android Studio. Use WSL2 for git operations and file editing only.

## Compose BOM Version vs API Availability

**Symptom:** `Unresolved reference: PullToRefreshBox` or similar import errors for Material3 APIs.

**Cause:** The Compose BOM version is too old for the API being used. Key API milestones:

| API | Minimum BOM | Minimum Material3 |
|-----|-------------|-------------------|
| `PullToRefreshBox` | `2024.01.00` | 1.3.0+ |
| `ExperimentalMaterial3Api` (stable) | `2024.01.00` | 1.2.0+ |
| `material3-window-size-class` | `2023.10.01` | 1.1.0+ |

**Fix:** Bump the BOM in `app/build.gradle.kts`:
```kotlin
// Old (broken):
implementation(platform("androidx.compose:compose-bom:2023.10.01"))

// New (fixes PullToRefreshBox):
implementation(platform("androidx.compose:compose-bom:2024.01.00"))
```

> **Tip:** When a worker adds a new Material3 import that doesn't resolve, check the BOM version first. The BOM controls which Material3 version is pulled in.

## PDF Viewer minSdk / Manifest Merger Conflict

**Symptom:** Build fails with `manifest merger failed` or `minSdk conflict` after adding `androidx.pdf:pdf-viewer`.

**Cause:** `androidx.pdf:pdf-viewer:1.0.0-alpha01` may declare a higher `minSdk` than the app (e.g., app uses `minSdk = 31` but the library requires 34).

**Fix options:**
1. Bump the app's `minSdk` to match the library (check the library's docs)
2. Add `tools:overrideLibrary` in `AndroidManifest.xml`:
   ```xml
   <uses-sdk tools:overrideLibrary="androidx.pdf.viewer" />
   ```
3. Use a newer version of the library that supports your minSdk

## Third-Party Maven Repository Missing

**Symptom:** `Could not find org.readium.kotlin-toolkit:readium-shared:3.0.0` or similar for non-Google/MavenCentral libraries.

**Cause:** Dependencies like Readium, Coil, or other third-party libraries may require additional Maven repositories beyond `google()` and `mavenCentral()`.

**Fix:** Add the required repository in `settings.gradle.kts`:
```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Readium
        maven { url = uri("https://maven.readium.org/repository/releases/") }
        // Add other third-party repos as needed
    }
}
```

## Gradle Daemon Issues from WSL2

**Symptom:** `Starting a Gradle Daemon, 1 incompatible and 1 stopped Daemons could not be reused` on every build.

**Cause:** WSL2 and Windows share the same Gradle daemon cache but with incompatible JVM paths.

**Fix:** Use `--no-daemon` flag for WSL2 builds:
```bash
./gradlew assembleDebug --no-daemon
```

Or set in `gradle.properties`:
```properties
org.gradle.daemon=false
```
