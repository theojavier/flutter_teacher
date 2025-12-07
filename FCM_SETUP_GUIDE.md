# FCM Setup Guide for Flutter Teacher

## Overview
This guide covers complete setup for Firebase Cloud Messaging (FCM) on Android and iOS, plus Cloud Function deployment.

---

## Step 1: Android Setup

### 1.1 Download google-services.json
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project → **Project Settings** (gear icon top-left)
3. Go to **Your apps** tab
4. Find your Android app and click **Download google-services.json**
5. Place the file here: `android/app/google-services.json`

### 1.2 Verify Gradle Configuration

**File: `android/app/build.gradle` or `android/app/build.gradle.kts`**

For **build.gradle** (Groovy):
```gradle
plugins {
    id 'com.google.gms.google-services'  // Add this line
    // ... other plugins
}

dependencies {
    // Firebase already included by Flutter, no need to add manually
}
```

For **build.gradle.kts** (Kotlin DSL):
```kotlin
plugins {
    id("com.google.gms.google-services")  // Add this line
    // ... other plugins
}

dependencies {
    // Firebase already included by Flutter
}
```

**File: `android/build.gradle` or `android/build.gradle.kts`**

For **build.gradle** (Groovy):
```gradle
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.google.gms:google-services:4.3.15'  // Add this
        // ... other dependencies
    }
}
```

For **build.gradle.kts** (Kotlin DSL):
```kotlin
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.3.15")  // Add this
        // ... other dependencies
    }
}
```

### 1.3 Verify AndroidManifest.xml

**File: `android/app/src/main/AndroidManifest.xml`**

Ensure these permissions exist:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<application>
    <!-- ... existing config ... -->
</application>
```

**Done for Android!** The `firebase_messaging` package handles the rest automatically.

---

## Step 2: iOS Setup

### 2.1 Enable Push Notifications in Xcode

1. Open your iOS project in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. Select **Runner** project → **Runner** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Search for and add:
   - **Push Notifications**
   - **Background Modes** → Check **Remote notifications**

### 2.2 Upload APNs Key to Firebase

1. Go to [Apple Developer](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles** → **Keys**
3. Create a new key with **Apple Push Notifications service (APNs)** capability
4. Download the `.p8` file
5. In [Firebase Console](https://console.firebase.google.com/):
   - Select your project → **Project Settings** → **Cloud Messaging** tab
   - Under **iOS app configuration**, upload the APNs key
   - Enter your **Team ID** and **Key ID** from the file name/details

### 2.3 Update Info.plist

**File: `ios/Runner/Info.plist`**

Add or verify these keys:
```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.google.firebase.firestore.cleanup</string>
</array>
```

### 2.4 Verify Runner Delegate (optional)

**File: `ios/Runner/GeneratedPluginRegistrant.m`** (auto-generated)

Firebase messaging should auto-register. No manual edits needed.

**Done for iOS!**

---

## Step 3: Cloud Function Deployment

### 3.1 Initialize Firebase Functions (if not already done)

```bash
# From repo root
firebase init functions
```

The `functions/` folder already has `package.json` and `index.js` in place.

### 3.2 Install Dependencies

```bash
cd functions
npm install
cd ..
```

### 3.3 Deploy the Function

```bash
firebase deploy --only functions
```

You should see output like:
```
✔  Function URL: https://us-central1-YOUR_PROJECT.cloudfunctions.net/notifyTeacherTest
✔  Deploy complete!
```

### 3.4 Verify the Function Works (Optional)

Test the function via Firebase CLI shell:

```bash
firebase functions:shell
```

Then in the shell:
```js
notifyTeacherTest({teacherId: "YOUR_TEACHER_UID"})
```

If there are tokens registered, you should get a success response.

---

## Step 4: Testing End-to-End

### 4.1 Run the Flutter App

```bash
flutter clean
flutter pub get
flutter run
```

Teacher should see a permission prompt → grant notification access.

### 4.2 Verify Token Registration

1. Open the app as a teacher
2. Go to **Teacher Dashboard** (or any page that calls `registerTeacherFCMToken`)
3. Check Firebase Console:
   - **Firestore** → **users** collection → find the teacher document
   - Verify `fcmTokens` array has entries

### 4.3 Trigger a Notification

Create a dummy exam result in Firebase:

1. Firestore Console → **examResults** → **{examId}** → **{studentId}** → **result**
2. Create/update a document with:
   ```json
   {
     "examId": "exam123",
     "studentId": "student456",
     "status": "in-progress",
     "startedAt": <current timestamp>
   }
   ```

3. The Cloud Function should trigger automatically and send FCM to all registered teacher tokens
4. You should see the notification on your device/emulator

### 4.4 Check Cloud Function Logs

```bash
firebase functions:log
```

Look for messages like:
- `Sent notifications to X device(s)`
- `No FCM tokens found for teacher...` (if tokens aren't registered)
- Any error messages

---

## Troubleshooting

### Notification not received
- [ ] Check device has **Post Notifications** permission enabled (Android 13+)
- [ ] Verify `fcmTokens` array is not empty in Firestore
- [ ] Check Cloud Function logs for errors
- [ ] Ensure app is running or in background (not force-stopped)

### APNs errors on iOS
- [ ] Verify APNs key `.p8` file is uploaded to Firebase
- [ ] Check Team ID and Key ID are correct
- [ ] Ensure bundle ID matches in Xcode and Firebase

### Cloud Function fails
- [ ] Check `firebase functions:log` for errors
- [ ] Verify Firestore security rules allow reading/writing `examResults` and `users`
- [ ] Ensure `firebase-admin` and `firebase-functions` packages are installed

### Token not saving to Firestore
- [ ] Check Firestore permissions for `users/{userId}` document
- [ ] Verify teacher is logged in before `registerTeacherFCMToken` is called
- [ ] Check browser/app console for FCM permission errors

---

## Quick Reference: Deployment Commands

```bash
# Setup
cd functions
npm install
cd ..

# Deploy
firebase deploy --only functions

# View logs
firebase functions:log

# Local testing
firebase emulators:start --only functions,firestore
```

---

## Next Steps

1. ✅ Run app on Android/iOS device
2. ✅ Grant notification permissions
3. ✅ Verify `fcmTokens` in Firestore
4. ✅ Create test exam result to trigger notification
5. ✅ Confirm notification appears on teacher device

Happy monitoring! 🎉
