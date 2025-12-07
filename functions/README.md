# Flutter Teacher - Real-Time Exam Monitoring with FCM

## Overview

This system enables **real-time push notifications** to teachers when students take exams, even when the teacher app is closed. It combines:

- **Flutter Client** (`lib/services/fcm_service.dart`) — Registers teacher device tokens
- **Firebase Cloud Messaging (FCM)** — Delivers push notifications
- **Cloud Functions** (`functions/index.js`) — Triggers notifications on student exam events
- **Firestore** — Stores teacher tokens and exam data

---

## How It Works

1. **Teacher opens app** → FCM token auto-registered in `users/{teacherId}.fcmTokens`
2. **Student starts exam** → Writes to `examResults/{examId}/{studentId}/result` with `status: "in-progress"`
3. **Cloud Function triggers** → Listens to result writes, finds teacher, sends FCM to all tokens
4. **Notification delivered** → Teacher receives push even if app is closed

---

## Files & Structure

```
flutter_teacher/
├── lib/
│   ├── services/
│   │   └── fcm_service.dart          # Token registration & handlers
│   ├── main.dart                     # Initialize FCM on startup
│   └── pages/teacher/
│       └── teacher_dashboard_page.dart # Register token on load
├── functions/
│   ├── package.json                  # Node.js dependencies
│   └── index.js                      # Cloud Function code
├── android/
│   ├── app/
│   │   ├── build.gradle(.kts)        # Google services plugin
│   │   ├── google-services.json      # Download from Firebase
│   │   └── AndroidManifest.xml       # Permissions
│   └── build.gradle(.kts)            # Google services classpath
├── ios/
│   ├── Runner/
│   │   ├── Info.plist                # Push capability keys
│   │   └── Runner.xcworkspace        # Xcode capabilities
│   └── Podfile                       # CocoaPods (auto-managed)
├── pubspec.yaml                      # firebase_messaging: ^16.0.4
├── firebase.json                     # Firebase config
└── FCM_SETUP_GUIDE.md               # Detailed setup instructions
```

---

## Quick Start

### 1. Flutter Setup (✅ Already Done)
```bash
flutter pub get
flutter run
```

### 2. Android Setup (See `FCM_SETUP_GUIDE.md`)
- [ ] Download `google-services.json` from Firebase
- [ ] Place in `android/app/google-services.json`
- [ ] Verify Gradle has Google services plugin

### 3. iOS Setup (See `FCM_SETUP_GUIDE.md`)
- [ ] Enable Push Notifications in Xcode
- [ ] Upload APNs key to Firebase Console
- [ ] Update `ios/Runner/Info.plist`

### 4. Deploy Cloud Function
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

### 5. Test End-to-End
- [ ] Run app as teacher
- [ ] Grant notification permissions
- [ ] Verify token in Firestore (`users/{uid}.fcmTokens`)
- [ ] Create test exam result
- [ ] Confirm notification appears

---

## Key Functions

### `fcm_service.dart`

| Function | Purpose |
|----------|---------|
| `initializeFCM()` | Register background handler (call in main.dart) |
| `registerTeacherFCMToken(teacherId)` | Get token & save to Firestore |
| `removeTeacherFCMToken(teacherId)` | Delete token on logout |
| `firebaseMessagingBackgroundHandler()` | Handle background notifications |

### `functions/index.js`

| Function | Trigger | Action |
|----------|---------|--------|
| `notifyTeacherOnExamResult` | Write to `examResults/{examId}/{studentId}/result` | Send FCM to teacher tokens |
| `notifyTeacherTest` (optional) | HTTP callable | Send test notification |

---

## Firestore Structure

### Users Document
```firestore
users/{teacherId}
├── name: string
├── email: string
├── fcmTokens: array
│   ├── "token_xyz123..."
│   └── "token_abc789..."
└── ... (other fields)
```

### Exam Results
```firestore
examResults/{examId}/{studentId}/result
├── examId: string
├── studentId: string
├── status: "in-progress" | "completed" | "incomplete"
├── startedAt: timestamp
├── score: number (optional)
└── ... (other fields)
```

---

## Monitoring & Debugging

### View Cloud Function Logs
```bash
firebase functions:log
```

### Test Function Locally
```bash
firebase functions:shell
notifyTeacherTest({teacherId: "YOUR_UID"})
```

### Check Firestore Tokens
1. Firebase Console → **Firestore**
2. Navigate to `users/{teacherId}`
3. Look for `fcmTokens` array

### Check FCM Delivery
1. Firebase Console → **Cloud Messaging** → **Metrics**
2. See delivery statistics for your project

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Notification not received | Check `fcmTokens` in Firestore; verify permissions granted |
| Cloud Function errors | Run `firebase functions:log` to see error messages |
| APNs errors on iOS | Verify `.p8` key uploaded; check Team ID in Firebase Console |
| No tokens registering | Ensure `registerTeacherFCMToken()` is called after login |
| Function doesn't trigger | Check Cloud Function logs; verify Firestore path matches exactly |

---

## Security Notes

- **Firestore Rules**: Restrict token reads/writes to authenticated users
- **Sensitive Data**: Avoid putting PII in notification bodies (use data payloads instead)
- **Token Rotation**: Tokens rotate automatically; old tokens removed after send failure
- **Rate Limiting**: Consider throttling notifications to avoid spam (optional enhancement)

---

## Next Steps

1. Follow `FCM_SETUP_GUIDE.md` for platform-specific setup
2. Deploy Cloud Function (`firebase deploy --only functions`)
3. Test end-to-end with a real device
4. Monitor logs and adjust notification trigger logic as needed
5. (Optional) Add notification tapping to navigate to exam monitoring page

---

## References

- [Firebase Messaging Documentation](https://firebase.flutter.dev/docs/messaging/overview/)
- [Cloud Functions for Firebase](https://firebase.google.com/docs/functions)
- [FCM Best Practices](https://firebase.google.com/docs/cloud-messaging/best-practices)

