# Re-take Exam Feature

## Overview

Students can now **re-take a completed exam** if they need another attempt. This feature allows flexibility for students who missed the exam window or want to improve their score.

---

## How It Works

### Student Flow

1. Student completes an exam (status = "completed")
2. View Result page shows two buttons:
   - **View Result** — See their current score/feedback
   - **Re-take Exam** — Start a new attempt (with confirmation)

3. When re-taking:
   - Confirmation dialog appears asking "Are you sure?"
   - Upon confirmation, a new attempt is created
   - `previousAttempts` counter increments
   - `retakeAttemptedAt` timestamp is recorded
   - Student is redirected to exam page to start fresh

### Data Structure

**Firestore: `examResults/{examId}/{studentId}/result`**

```json
{
  "examId": "exam123",
  "studentId": "student456",
  "status": "in-progress",      // Status changes back to in-progress
  "startedAt": <timestamp>,
  "completedAt": <timestamp>,
  "score": 85,
  "previousAttempts": 1,        // NEW: Tracks retake count
  "retakeAttemptedAt": <timestamp> // NEW: When retake was started
}
```

---

## Features

✅ **Confirmation Dialog** — Prevents accidental retakes  
✅ **Attempt Tracking** — Records how many times student retook  
✅ **Timestamp Logging** — Tracks when retake was initiated  
✅ **Non-destructive** — Previous result is saved before retake  
✅ **UI Button** — Blue "Re-take Exam" button next to "View Result"

---

## Teacher Controls (Optional Enhancement)

Teachers can:
1. **View retake attempts** in the student's exam result history
2. **Limit retakes** by setting a `maxRetakes` field on the exam document
3. **Monitor student behavior** via the `previousAttempts` counter

### Example Teacher Dashboard Enhancement

```dart
if (result['previousAttempts'] > 0) {
  print('Student has retaken this exam ${result['previousAttempts']} time(s)');
}
```

---

## Firestore Security Rules (Recommended)

Add to your Firestore rules to ensure only students can retake their own exams:

```firestore
match /examResults/{examId}/{studentId}/result {
  // Allow students to update their own results
  allow write: if request.auth.uid == studentId;
  allow read: if request.auth.uid == studentId 
    || request.auth.uid == get(/databases/$(database)/documents/exams/$(examId)).data.teacherId;
}
```

---

## Testing

1. **Run the app** as a student
2. **Complete an exam** (submit answers)
3. **View Result page** should show both "View Result" and "Re-take Exam" buttons
4. **Click "Re-take Exam"**
5. **Confirm** in the dialog
6. **Verify** you're taken back to the exam page to start fresh
7. **Check Firestore** to see `previousAttempts` incremented

---

## Files Modified

- `lib/pages/exams/take_exam_page.dart`
  - Updated "Completed" button section to show both buttons
  - Added `_retakeExam()` method with confirmation dialog
  - Tracks attempt count and timestamp

---

## Future Enhancements

- [ ] Add retake limit per exam (teacher can set max retakes)
- [ ] Show retake history/timeline in student results
- [ ] Notify teacher when student retakes exam
- [ ] Compare scores across retakes
- [ ] Auto-randomize questions on retake (if applicable)

---

## Troubleshooting

**Button doesn't appear:**
- Verify exam status is "completed" in Firestore
- Check that `StreamBuilder` is properly listening to result updates

**Retake doesn't work:**
- Ensure `studentId` is not null
- Check Firestore permissions allow the update
- Verify `FieldValue.increment()` is properly imported

**Previous score is lost:**
- All exam data is preserved before retake starts
- Previous attempt data is accessible via Firestore history

