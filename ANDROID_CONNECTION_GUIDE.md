# Flutter Teacher App - Android Connection Guide

## Overview
This guide explains how to connect your Flutter Teacher app to Android devices and emulators for testing.

---

## Prerequisites

Before you begin, ensure you have:
- ✅ Flutter SDK installed
- ✅ Android Studio installed
- ✅ Java Development Kit (JDK) 11 or higher
- ✅ Firebase project set up
- ✅ Google Services JSON file (`google-services.json`)

---

## Step 1: Setup Android Environment

### Check Flutter Setup
```bash
flutter doctor
```

This should show:
- ✅ Flutter (Channel stable)
- ✅ Android toolchain
- ✅ Android Studio
- ✅ VS Code (if using it)

### Install/Fix Android Setup Issues
```bash
flutter doctor --android-licenses
```
Then press `y` to accept all licenses.

---

## Step 2: Configure Firebase for Android

### Add Google Services JSON

1. **Get your `google-services.json` file:**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project
   - Go to **Project Settings** → **Service Accounts**
   - Click "Generate New Private Key"
   - Or download from **Your Apps** section

2. **Place the file in the correct location:**
   ```
   android/
   └── app/
       └── google-services.json  ← Place it here
   ```

3. **Verify `build.gradle.kts` has the plugin:**
   ```kotlin
   plugins {
       id("com.google.gms.google-services")
   }
   ```
   ✅ Already configured in your project!

---

## Step 3: Enable Internet Permission

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Add this permission -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    
    <application>
        <!-- ... rest of config ... -->
    </application>
</manifest>
```

---

## Step 4: Build APK for Testing

### Option A: Run on Connected Device

**Prerequisite:** Connect your Android device via USB

1. **Enable USB Debugging on Device:**
   - Settings → About Phone → Tap "Build Number" 7 times
   - Go back to Settings → Developer Options → Enable "USB Debugging"
   - Connect via USB cable

2. **List connected devices:**
   ```bash
   flutter devices
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

### Option B: Run on Emulator

1. **Start Android Emulator:**
   - Open Android Studio
   - Click "Device Manager"
   - Start any emulator device

2. **List available devices:**
   ```bash
   flutter devices
   ```

3. **Run on specific emulator:**
   ```bash
   flutter run -d emulator-5554
   ```
   (Replace with your emulator ID)

### Option C: Build Release APK

```bash
flutter build apk --release
```

Output location: `build/app/outputs/apk/release/app-release.apk`

To install on device:
```bash
flutter install
```

---

## Step 5: Connect to Firebase from Android

### Your App Already Has:
✅ Cloud Firestore dependency
✅ Firebase Auth setup
✅ Google Services plugin configured

### Verify Firebase Connectivity

Add this to your `main.dart` to check connection:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

✅ You likely already have this!

### Test Firestore Connection

Create a simple test widget:

```dart
FutureBuilder<QuerySnapshot>(
  future: FirebaseFirestore.instance.collection('exams').limit(1).get(),
  builder: (context, snapshot) {
    if (snapshot.hasError) {
      return Text("Error: ${snapshot.error}");
    }
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const CircularProgressIndicator();
    }
    return Text("Connected! Found ${snapshot.data?.docs.length} exams");
  },
)
```

---

## Step 6: Handle Permissions on Android

### For Camera Access (Your app uses this)

Create `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature
        android:name="android.hardware.camera"
        android:required="false" />
    
    <application
        android:usesCleartextTraffic="true">
        <!-- ... -->
    </application>
</manifest>
```

### Request Runtime Permissions

Install `permission_handler` package:

```bash
flutter pub add permission_handler
```

Use in code:

```dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestCameraPermission() async {
  final status = await Permission.camera.request();
  return status.isGranted;
}

// Usage
bool hasCamera = await requestCameraPermission();
if (!hasCamera) {
  print("Camera permission denied");
}
```

---

## Step 7: Debug Your App

### View Logs
```bash
flutter logs
```

### Hot Reload During Development
```bash
flutter run
# In terminal, press 'r' to hot reload
# Press 'R' to hot restart
```

### Check Firebase Connectivity
In your terminal after `flutter run`:
```bash
adb logcat | grep firebase
```

---

## Common Issues & Solutions

### Issue 1: "google-services.json not found"
**Error Message:**
```
Error: google-services.json not found
```

**Solution:**
1. Ensure file is in `android/app/` directory
2. Run: `flutter clean`
3. Run: `flutter pub get`
4. Rebuild: `flutter run`

### Issue 2: "Build fails - Gradle issue"
**Solution:**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Issue 3: "App crashes on startup"
**Solution:**
1. Check Firebase initialization in `main.dart`
2. Verify `google-services.json` has correct Firebase project ID
3. Check Firestore security rules in Firebase Console

### Issue 4: "No internet connection"
**Solution:**
1. Verify `android:name="android.permission.INTERNET"` is in `AndroidManifest.xml`
2. Check device has internet (WiFi or mobile data)
3. Test with: `adb shell ping 8.8.8.8`

### Issue 5: "Firebase Authentication fails"
**Solution:**
1. Go to Firebase Console
2. Authentication → Get Started
3. Enable "Email/Password" provider
4. Add test users in Firebase Console

---

## Step-by-Step Commands

### Quick Start (Emulator)
```bash
# 1. Clean project
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Run on emulator
flutter run

# 4. If issues, try:
flutter run --no-build-cache
```

### Quick Start (Physical Device)
```bash
# 1. Connect device via USB & enable debugging
# 2. List devices
flutter devices

# 3. Run on device
flutter run -d <device-id>

# Example:
flutter run -d 0A281FDH40027M
```

### Build & Share APK
```bash
# Build release APK
flutter build apk --release

# Locate APK
# build/app/outputs/apk/release/app-release.apk

# Share via: AirDrop, Email, Cloud Drive, etc.
```

---

## Testing Your Exam Monitoring Feature

After connecting to Android:

1. **Open your app on the device**
2. **Login as a teacher**
3. **Create a test exam**
4. **Have a student (on another device/emulator) take the exam**
5. **Go to Monitor Exams**
6. **You should see the student appearing in real-time!**

---

## Network Testing

### Test Firestore Query
Add this to your monitoring page temporarily:

```dart
// Add this to _ExamMonitoringPageState
@override
void initState() {
  super.initState();
  _testConnection();
}

Future<void> _testConnection() async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('exams')
        .limit(1)
        .get();
    debugPrint("✅ Firebase connected! Found ${snap.docs.length} docs");
  } catch (e) {
    debugPrint("❌ Firebase error: $e");
  }
}
```

---

## Production Checklist

Before releasing to production:

- ✅ Test on multiple Android versions (API 21+)
- ✅ Test on physical devices, not just emulator
- ✅ Update `android/app/build.gradle.kts` with real app ID
- ✅ Configure Firestore security rules properly
- ✅ Set up proper authentication flow
- ✅ Test offline mode if needed
- ✅ Use ProGuard/R8 obfuscation for release builds
- ✅ Test with real Firebase project (not dev)

---

## Useful Commands Reference

```bash
# Device Management
flutter devices                    # List all devices
adb devices                       # List connected ADB devices
adb kill-server                   # Restart ADB

# Building
flutter build apk                 # Debug APK
flutter build apk --release       # Release APK
flutter build appbundle           # For Play Store

# Running
flutter run                        # Run on default device
flutter run -d all               # Run on all devices
flutter run --debug              # Debug mode
flutter run --release            # Release mode

# Debugging
flutter logs                      # View app logs
adb logcat                        # View Android logs
flutter attach                    # Attach to running app

# Cleaning
flutter clean                     # Clean build files
flutter pub get                   # Get dependencies
flutter pub upgrade               # Upgrade dependencies
```

---

## Next Steps

1. ✅ Follow steps 1-3 above to set up Android
2. ✅ Place `google-services.json` in `android/app/`
3. ✅ Connect a device or start an emulator
4. ✅ Run `flutter run`
5. ✅ Test the exam monitoring feature with real students!

Need help? Check:
- [Flutter Documentation](https://flutter.dev/docs)
- [Firebase for Flutter](https://firebase.flutter.dev/)
- [Android Developer Docs](https://developer.android.com/)
