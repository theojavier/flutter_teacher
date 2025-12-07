# Flutter Teacher App - Mobile Phone Connection Troubleshooting

## Quick Diagnostic Steps

### Step 1: Check USB Connection
```bash
adb devices
```

**Expected output:**
```
List of devices attached
YOUR_DEVICE_ID   device
```

**If showing "unauthorized":**
- Check your phone for the USB authorization prompt
- Accept the "Allow USB debugging?" dialog
- Run `adb devices` again

### Step 2: Check Firebase Connection
```bash
flutter run
```

**If app crashes immediately**, it's likely a Firebase initialization issue.

---

## Common Issues & Solutions

### Issue 1: "No devices found" or "offline"

#### Solution A: Restart ADB
```bash
adb kill-server
adb start-server
adb devices
```

#### Solution B: Reconnect USB Cable
1. Disconnect USB cable from phone
2. Wait 5 seconds
3. Reconnect USB cable
4. Run: `adb devices`

#### Solution C: Enable USB Debugging
On your Android phone:
1. **Settings** → **About Phone**
2. Tap **Build Number** 7 times until "Developer Options" appears
3. Go to **Settings** → **Developer Options**
4. Enable **USB Debugging**
5. Reconnect USB cable

#### Solution D: Check USB Driver
On Windows:
- Download [Google USB Driver](https://developer.android.com/studio/run/win-usb)
- Or use Android Studio's SDK Manager to install USB Driver

---

### Issue 2: "App crashes on startup"

#### Cause: Firebase Not Initialized
Check your `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

#### Cause: Missing `google-services.json`
```
android/
└── app/
    └── google-services.json  ← MUST be here
```

If missing:
1. Download from Firebase Console
2. Place in `android/app/` directory
3. Run: `flutter clean && flutter pub get && flutter run`

#### Cause: Firestore Security Rules
Check Firebase Console → Firestore → Rules

Temporary test rules:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

### Issue 3: "Cannot connect to Firestore"

#### Check Network
```bash
adb shell ping 8.8.8.8
```

If it fails:
- ✅ Enable WiFi on phone
- ✅ Check internet connection
- ✅ Check device is on same network as computer

#### Check Internet Permission
`android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

#### Check Firebase Rules
1. Go to Firebase Console
2. Firestore → Rules tab
3. Ensure rules allow authenticated reads/writes
4. **Publish** the rules

---

### Issue 4: "App opens but crashes immediately"

#### Get Crash Logs
```bash
adb logcat -c
flutter run
# Wait for crash, then copy logs
```

#### Common Firebase Crashes

**Error: "No Firebase project associated"**
```
Check android/app/google-services.json has correct project_id
```

**Error: "FirebaseOptions are not initialized"**
```dart
// Make sure firebase_options.dart exists
// If not, run: flutterfire configure
```

**Error: "com.example.flutter_teacher.MainActivity not found"**
```
Check android/app/src/main/AndroidManifest.xml
Ensure MainActivity is declared correctly
```

---

### Issue 5: "Login page shows but crashes when clicking login"

#### Check Authentication Setup
1. Firebase Console → Authentication
2. Enable "Email/Password" provider
3. Add test user (Email/Password tab)

#### Check Security Rules for Users Collection
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{document=**} {
      allow read, write: if request.auth != null;
    }
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

### Issue 6: "Phone shows "waiting for device""

#### Kill All Java Processes
```powershell
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force
```

#### Clear Flutter Cache
```bash
flutter clean
flutter pub get
flutter run
```

#### Reset ADB
```bash
adb kill-server
adb start-server
adb devices
```

---

### Issue 7: "Phone connects but app won't install"

#### Check Storage Space
```bash
adb shell df /data
```

Free up space if needed (< 100MB free)

#### Clear App Cache
```bash
adb shell pm clear com.example.flutter_teacher
```

#### Reinstall
```bash
flutter clean
flutter pub get
flutter run -v
```

The `-v` flag shows detailed logs for debugging.

---

## Step-by-Step Setup for Phone

### Prerequisites
- ✅ USB cable (must be data cable, not just charging)
- ✅ Android device with Android 5.0+ (API 21+)
- ✅ USB Debugging enabled
- ✅ Google Services JSON configured

### Setup Process

1. **Enable Developer Mode**
   ```
   Settings → About Phone → Build Number (tap 7x)
   → Developer Options → USB Debugging (enable)
   ```

2. **Connect USB Cable**
   - Plug in cable
   - When prompt appears: "Allow USB debugging from this computer?"
   - Tap "Allow"
   - If no prompt, disconnect and retry

3. **Verify Connection**
   ```bash
   adb devices
   ```
   Should show: `YOUR_DEVICE_ID   device`

4. **Place google-services.json**
   - Download from Firebase Console
   - Place in `android/app/google-services.json`

5. **Check Firestore Security Rules**
   - Firebase Console → Firestore → Rules
   - Ensure authenticated access is allowed
   - Click "Publish"

6. **Run App**
   ```bash
   cd c:\Users\Hannah Jomulo\Documents\GitHub\flutter_teacher
   flutter clean
   flutter pub get
   flutter run
   ```

7. **Select Your Device**
   When prompted, select your phone from the list

---

## Detailed Debugging

### View Full Logs
```bash
adb logcat | findstr flutter
```

### Get Specific Error Logs
```bash
adb logcat | findstr FATAL
adb logcat | findstr ERROR
adb logcat | findstr "Exception\|Error"
```

### Save Logs to File
```bash
adb logcat > logs.txt
# Wait 30 seconds, press Ctrl+C
notepad logs.txt
```

---

## Firebase Specific Issues

### Issue: "Firestore not available"

Check in Firebase Console:
1. **Build** → **Firestore Database**
2. Click **Create Database**
3. Select **Test Mode** (for development)
4. Click **Create**

### Issue: "Authentication provider not enabled"

1. **Build** → **Authentication**
2. **Get Started**
3. **Email/Password** → Enable
4. **Save**

---

## Network & Connectivity

### Verify Phone Internet
```bash
adb shell ping 8.8.8.8
```

If fails:
```bash
adb shell netstat  # Check connectivity
adb shell settings get global airplane_mode_on  # Check airplane mode
```

### Verify Firebase Reachability
```bash
adb shell ping firebaseio.com
```

---

## Final Checklist

Before troubleshooting further, verify:

- ✅ USB Debugging is **enabled** on phone
- ✅ USB cable is **plugged in** and recognized
- ✅ `adb devices` shows your phone with status **device**
- ✅ `google-services.json` is in `android/app/`
- ✅ Firebase project is **created** and **configured**
- ✅ Firestore Database is **created**
- ✅ Authentication is **enabled**
- ✅ Phone has **internet connection** (WiFi or mobile data)
- ✅ Flutter version is **compatible**: `flutter doctor` shows ✓

---

## Quick Recovery Commands

```bash
# Complete clean and rebuild
flutter clean
flutter pub get
adb kill-server
adb start-server
adb devices
flutter run -v

# If still fails, try:
flutter doctor --android-licenses  # Accept all
flutter run -v --no-cache
```

---

## Getting Help

If app still crashes, provide this information:

1. **Full flutter run output**
   ```bash
   flutter run -v > output.txt 2>&1
   ```

2. **adb logcat output**
   ```bash
   adb logcat -c
   adb logcat > logs.txt  # Wait 1 minute
   # Ctrl+C to stop
   ```

3. **flutter doctor output**
   ```bash
   flutter doctor -v > doctor.txt
   ```

Share these files for debugging.

---

## Summary

**Your emulator crash likely caused by:**
1. ❌ Emulator offline (port conflict with ADB)
2. ❌ Multiple ADB daemons running
3. ✅ Firebase initialization issue
4. ✅ Missing google-services.json

**Try this first:**
```bash
adb kill-server
adb start-server
flutter clean
flutter pub get
flutter run
```

If using phone, ensure USB Debugging is enabled and phone is recognized by `adb devices`.
