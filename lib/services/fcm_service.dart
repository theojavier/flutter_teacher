import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Background handler MUST be a top-level function
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Handle background notifications here
}

/// Call once during app startup (after Firebase.initializeApp())
Future<void> initializeFCM() async {
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Optional: You can also set notification presentation for iOS
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

/// Register the teacher’s FCM token
Future<void> registerTeacherFCMToken(String teacherId) async {
  final messaging = FirebaseMessaging.instance;

  // Request permission
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  // Get token
  final token = await messaging.getToken();
  if (token == null) return;

  // Save token to Firestore
  final userRef = FirebaseFirestore.instance.collection('users').doc(teacherId);
  await userRef.set({
    'fcmTokens': FieldValue.arrayUnion([token]),
  }, SetOptions(merge: true));

  // Foreground notification handler
  FirebaseMessaging.onMessage.listen((msg) {
    print("Foreground message: ${msg.notification?.title}");
  });

  // Notification tapped
  FirebaseMessaging.onMessageOpenedApp.listen((msg) {
    print("Notification tapped: ${msg.data}");
  });
}

/// Remove token (on logout)
Future<void> removeTeacherFCMToken(String teacherId) async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  final userRef = FirebaseFirestore.instance.collection('users').doc(teacherId);
  await userRef.update({
    'fcmTokens': FieldValue.arrayRemove([token]),
  });
}
