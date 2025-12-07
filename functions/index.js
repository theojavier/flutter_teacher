const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Cloud Function: Triggered when a student exam result is created or updated.
 * Sends FCM push notification to the teacher when:
 * - Student starts exam (status: 'in-progress')
 * - Student completes exam (status: 'completed')
 */
exports.notifyTeacherOnExamResult = functions.firestore
  .document('examResults/{examId}/{studentId}/result')
  .onWrite(async (change, context) => {
    try {
      const before = change.before.exists ? change.before.data() : null;
      const after = change.after.exists ? change.after.data() : null;
      
      // Only proceed if result exists
      if (!after) {
        console.log('Result deleted, skipping notification');
        return null;
      }

      const currentStatus = after.status;
      const previousStatus = before ? before.status : null;

      // Only notify on status changes to 'in-progress' or 'completed'
      if (
        (currentStatus === 'in-progress' && previousStatus !== 'in-progress') ||
        (currentStatus === 'completed' && previousStatus !== 'completed')
      ) {
        // Proceed with notification
      } else {
        console.log(`Skipping: status ${currentStatus}, previous ${previousStatus}`);
        return null;
      }

      const examId = context.params.examId;
      const studentId = context.params.studentId;

      // Get exam document to find the teacher
      const examSnap = await admin.firestore()
        .collection('exams')
        .doc(examId)
        .get();

      if (!examSnap.exists) {
        console.log(`Exam ${examId} not found`);
        return null;
      }

      const examData = examSnap.data();
      const teacherId = examData.teacherId;

      if (!teacherId) {
        console.log(`No teacherId found in exam ${examId}`);
        return null;
      }

      // Get teacher's FCM tokens from users collection
      const userSnap = await admin.firestore()
        .collection('users')
        .doc(teacherId)
        .get();

      let tokens = [];
      if (userSnap.exists) {
        tokens = userSnap.data().fcmTokens || [];
      }

      if (!tokens || tokens.length === 0) {
        console.log(`No FCM tokens found for teacher ${teacherId}`);
        return null;
      }

      // Determine notification message based on status
      let notificationTitle = '';
      let notificationBody = '';

      if (currentStatus === 'completed') {
        notificationTitle = '✅ Student Exam Completed';
        notificationBody = `Student ${studentId} finished ${examData.subject || 'the exam'}`;
      } else if (currentStatus === 'in-progress') {
        notificationTitle = '📝 Student Started Exam';
        notificationBody = `Student ${studentId} started ${examData.subject || 'the exam'}`;
      }

      // Build notification payload
      const message = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          examId: examId,
          studentId: studentId,
          subject: examData.subject || 'Exam',
          type: 'exam_started',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      // Send to all teacher tokens using multicast
      const response = await admin.messaging().sendMulticast({
        tokens: tokens,
        notification: message.notification,
        data: message.data,
      });

      console.log(`Sent notifications to ${response.successCount} device(s)`);

      // Remove invalid tokens (failed sends)
      const tokensToRemove = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const error = resp.error;
          if (
            error &&
            (error.code === 'messaging/invalid-registration-token' ||
              error.code === 'messaging/registration-token-not-registered')
          ) {
            console.log(`Removing invalid token: ${tokens[idx]}`);
            tokensToRemove.push(tokens[idx]);
          }
        }
      });

      // Update Firestore to remove invalid tokens
      if (tokensToRemove.length > 0) {
        await admin.firestore()
          .collection('users')
          .doc(teacherId)
          .update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
          });
        console.log(`Removed ${tokensToRemove.length} invalid token(s)`);
      }

      return null;
    } catch (error) {
      console.error('Error in notifyTeacherOnExamResult:', error);
      return null;
    }
  });

/**
 * Optional: Cloud Function to send test notifications (for debugging)
 * Call via: firebase functions:shell
 * Then: notifyTeacherTest('teacherId')
 */
exports.notifyTeacherTest = functions.https.onCall(async (data, context) => {
  try {
    const teacherId = data.teacherId;
    if (!teacherId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'teacherId is required'
      );
    }

    const userSnap = await admin.firestore()
      .collection('users')
      .doc(teacherId)
      .get();

    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Teacher not found');
    }

    const tokens = userSnap.data().fcmTokens || [];
    if (tokens.length === 0) {
      throw new functions.https.HttpsError('not-found', 'No tokens registered');
    }

    const response = await admin.messaging().sendMulticast({
      tokens: tokens,
      notification: {
        title: 'Test Notification',
        body: 'This is a test FCM notification from Cloud Function',
      },
      data: {
        type: 'test',
      },
    });

    return {
      success: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
    };
  } catch (error) {
    console.error('Error in notifyTeacherTest:', error);
    throw error;
  }
});
