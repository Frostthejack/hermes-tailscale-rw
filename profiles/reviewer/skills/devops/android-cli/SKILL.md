---
name: android-cli
description: Android CLI development — build, test, and package Android apps from the command line using sdkmanager, gradle, aapt2, adb, and d8. No Android Studio required.
---

# Android CLI Development

Android SDK command-line tools installed on WSL Ubuntu 24.04 for building Android apps without Android Studio.

## Environment Setup

**All tools are pre-installed.** Source the environment before running any Android commands:

```bash
source /home/frostthejack/.hermes/android-env.sh
```

Or manually set:
```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME=/home/frostthejack/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:/home/frostthejack/gradle/bin:$PATH"
```

## Installed Components

| Component | Location | Version |
|-----------|----------|---------|
| Java JDK | `/usr/lib/jvm/java-17-openjdk-amd64` | 17.0.18 |
| Android SDK | `/home/frostthejack/android-sdk` | — |
| Command Line Tools | `$ANDROID_HOME/cmdline-tools/latest` | 20.0 |
| Build Tools | `$ANDROID_HOME/build-tools/34.0.0` | 34.0.0 |
| Platform | `$ANDROID_HOME/platforms/android-34` | API 34 (Android 14) |
| Platform Tools | `$ANDROID_HOME/platform-tools` | 37.0.0 |
| Gradle | `/home/frostthejack/gradle` | 8.10.2 |

## Quick Verification

```bash
source /home/frostthejack/.hermes/android-env.sh
java -version          # openjdk 17.0.18
gradle --version       # Gradle 8.10.2
sdkmanager --version   # 20.0
adb version            # 1.0.41
aapt2 version          # Android Asset Packaging Tool 2.x
```

## Creating a New Project

```bash
PROJECT_DIR=/path/to/myapp
mkdir -p $PROJECT_DIR/app/src/main/java/com/example/myapp
mkdir -p $PROJECT_DIR/app/src/main/res/values
```

Required files:
- `settings.gradle.kts` — project name + modules
- `build.gradle.kts` (root) — plugin declarations
- `app/build.gradle.kts` — android config + dependencies
- `app/src/main/AndroidManifest.xml` — manifest
- `gradle.properties` — **must include `android.useAndroidX=true`**

### Minimal gradle.properties

```properties
android.useAndroidX=true
android.enableJetifier=false
org.gradle.jvmargs=-Xmx2048m
```

### Building

```bash
cd $PROJECT_DIR
gradle assembleDebug --no-daemon    # Debug APK
gradle assembleRelease --no-daemon  # Release APK (needs signing)
```

Output: `app/build/outputs/apk/debug/app-debug.apk`

### Installing on Device

```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Adding More SDK Components

```bash
source /home/frostthejack/.hermes/android-env.sh
sdkmanager --list                  # List available packages
sdkmanager "platforms;android-35"  # Add another API level
sdkmanager "build-tools;35.0.0"    # Add newer build tools
sdkmanager "ndk;27.0.12077973"     # Add NDK
```

## Key Pitfalls

1. **Always set `android.useAndroidX=true`** in `gradle.properties` — build fails without it when using AndroidX dependencies
2. **Always source the env file** — tools won't be on PATH in fresh shells/agents
3. **Use `--no-daemon`** in CI/agent contexts to avoid daemon lifecycle issues
4. **compileSdk and buildToolsVersion must match installed versions** — currently 34 / 34.0.0
5. **Gradle wrapper vs system Gradle** — projects may use their own wrapper (`./gradlew`); system Gradle is at `/home/frostthejack/gradle/bin/gradle`

## ADB Device Connection

For physical devices over USB (from WSL):
```bash
adb devices          # List connected devices
adb connect <ip>     # Wireless debugging
adb install <apk>    # Install APK
adb logcat           # View device logs
```

Note: USB passthrough from Windows host to WSL may require `usbipd-win` on the Windows side.
