# Teacher Dashboard Overview Connection Guide

## Overview
Your teacher dashboard displays three key metrics that are connected to your Firestore database:
1. **Total Students** - Number of students assigned to this teacher
2. **Ongoing Exams** - Number of active exams being taken
3. **Flagged Students** - Number of students marked as flagged

---

## How It Works

### Current Implementation in `teacher_dashboard_page.dart`

Your dashboard is already connected! Here's the flow:

#### 1. **Data Loading** (in `initState`)
```dart
@override
void initState() {
  super.initState();
  _loadDashboardData();
}
```
This method is called when the page loads and retrieves fresh data from Firestore.

#### 2. **Fetching Total Students**
```dart
final studentsSnapshot = await db
    .collection('students')
    .where('teacherId', isEqualTo: widget.teacherId)
    .get();

setState(() {
  totalStudents = studentsSnapshot.size;
});
```

**What it does:**
- Queries the `students` collection
- Filters for students where `teacherId` matches the current teacher's ID
- Counts the total number of documents returned
- Updates the UI with this count

**Firestore requirement:**
Your `students` collection must have a `teacherId` field:
```json
{
  "id": "student123",
  "name": "John Doe",
  "teacherId": "teacher456",
  "average_score": 85,
  "flagged": false
}
```

#### 3. **Fetching Ongoing Exams**
```dart
final examsSnapshot = await db
    .collection('exams')
    .where('teacherId', isEqualTo: widget.teacherId)
    .where('isActive', isEqualTo: true)
    .get();

setState(() {
  ongoingExams = examsSnapshot.size;
});
```

**What it does:**
- Queries the `exams` collection
- Filters for exams where `teacherId` matches the current teacher's ID
- Filters for exams where `isActive` is `true`
- Counts active exams

**Firestore requirement:**
Your `exams` collection must have both `teacherId` and `isActive` fields:
```json
{
  "id": "exam789",
  "title": "Final Exam",
  "teacherId": "teacher456",
  "isActive": true,
  "createdAt": "timestamp"
}
```

#### 4. **Fetching Flagged Students**
```dart
final flaggedSnapshot = await db
    .collection('students')
    .where('teacherId', isEqualTo: widget.teacherId)
    .where('flagged', isEqualTo: true)
    .get();

setState(() {
  flaggedStudents = flaggedSnapshot.size;
});
```

**What it does:**
- Queries the `students` collection
- Filters for students where `teacherId` matches the current teacher's ID
- Filters for students where `flagged` is `true`
- Counts flagged students

**Firestore requirement:**
Your `students` collection must have a `flagged` boolean field:
```json
{
  "id": "student123",
  "name": "John Doe",
  "teacherId": "teacher456",
  "flagged": false  // Set to true for flagged students
}
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│         Teacher Dashboard Page Loads                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │  _loadDashboardData()  │
        └────────────────────────┘
           /              |           \
          /               |            \
         ▼                ▼             ▼
    ┌──────────┐    ┌──────────┐   ┌──────────┐
    │ Students │    │  Exams   │   │ Students │
    │ (by      │    │ (active) │   │ (flagged)│
    │teacherId)│    │          │   │          │
    └──────────┘    └──────────┘   └──────────┘
         │                │             │
         ▼                ▼             ▼
    Total Count     Ongoing Count  Flagged Count
         │                │             │
         └────────┬───────┴────────┬────┘
                  ▼                ▼
            setState() Updates UI
                  │
                  ▼
        Display in Info Cards
```

---

## Making It Dynamic with Real-Time Updates

Currently, your data is loaded **once** when the page loads. To make it **real-time** (updates when data changes), modify `_loadDashboardData()` to use **Streams**:

### Option 1: Keep Current Approach (Simple)
✅ Good for: Dashboards that don't need to update constantly
- User can pull-to-refresh via `RefreshIndicator`
- Less database reads = lower costs

### Option 2: Real-Time StreamBuilder (Recommended)
✅ Good for: Live dashboards

Replace your current code in the `_buildOverviewSection()` method with StreamBuilders:

```dart
Widget _buildOverviewSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Class Overview",
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      
      // Total Students - Real-time
      StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('students')
            .where('teacherId', isEqualTo: widget.teacherId)
            .snapshots(),
        builder: (context, snapshot) {
          int count = snapshot.data?.docs.length ?? 0;
          return _buildInfoCard(
            "Total Students",
            count.toString(),
            Icons.people,
            Colors.blue,
          );
        },
      ),
      
      // Ongoing Exams - Real-time
      StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('exams')
            .where('teacherId', isEqualTo: widget.teacherId)
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          int count = snapshot.data?.docs.length ?? 0;
          return _buildInfoCard(
            "Ongoing Exams",
            count.toString(),
            Icons.access_time,
            Colors.orange,
          );
        },
      ),
      
      // Flagged Students - Real-time
      StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('students')
            .where('teacherId', isEqualTo: widget.teacherId)
            .where('flagged', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          int count = snapshot.data?.docs.length ?? 0;
          return _buildInfoCard(
            "Flagged Students",
            count.toString(),
            Icons.warning,
            Colors.redAccent,
          );
        },
      ),
      
      const SizedBox(height: 30),
      const Text(
        "Quick Actions",
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              context.push(
                '/edit-exam',
                extra: {'docId': null, 'existing': null},
              );
            },
            icon: const Icon(Icons.create),
            label: const Text("Create Exam"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              context.push('/teacher-monitoring');
            },
            icon: const Icon(Icons.monitor),
            label: const Text("Monitor Exams"),
          ),
        ],
      ),
    ],
  );
}
```

---

## Firestore Database Structure Requirements

Make sure your Firestore collections are structured correctly:

### `students` Collection
```
students/
├── student_id_1/
│   ├── id: "student_id_1"
│   ├── name: "Alice Johnson"
│   ├── email: "alice@example.com"
│   ├── teacherId: "teacher_id_1"
│   ├── average_score: 85.5
│   └── flagged: false
│
└── student_id_2/
    ├── id: "student_id_2"
    ├── name: "Bob Smith"
    ├── email: "bob@example.com"
    ├── teacherId: "teacher_id_1"
    ├── average_score: 72.0
    └── flagged: true  ← This student is flagged
```

### `exams` Collection
```
exams/
├── exam_id_1/
│   ├── id: "exam_id_1"
│   ├── title: "Midterm Exam"
│   ├── teacherId: "teacher_id_1"
│   ├── isActive: true  ← Currently active
│   ├── subject: "Math"
│   └── createdAt: timestamp
│
└── exam_id_2/
    ├── id: "exam_id_2"
    ├── title: "Quiz 1"
    ├── teacherId: "teacher_id_1"
    ├── isActive: false  ← Not active
    ├── subject: "Science"
    └── createdAt: timestamp
```

---

## Common Issues & Solutions

### Issue 1: "Total Students shows 0"
**Cause:** No students in the database with matching `teacherId`

**Solution:**
1. Check if student documents have the `teacherId` field
2. Verify the `teacherId` value matches exactly (case-sensitive)
3. Check Firebase console to confirm documents exist

### Issue 2: "Ongoing Exams shows 0 even though exams exist"
**Cause:** `isActive` field missing or set to `false`

**Solution:**
1. When creating an exam, ensure `isActive` is set to `true`
2. When exam completes, set `isActive: false`

### Issue 3: "Flagged Students doesn't update when I flag a student"
**Cause:** Using the current approach with `initState()` only loads data once

**Solution:** Use the **StreamBuilder approach** (Option 2 above) for real-time updates

### Issue 4: "Permission Denied errors"
**Cause:** Firestore security rules blocking queries

**Solution:** Check your Firestore rules. For testing:
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

## Testing Your Connection

### Manual Test Steps:
1. **Add a test student** in Firebase Console:
   - Collection: `students`
   - Document ID: `test_student_1`
   - Fields: `teacherId: "YOUR_TEACHER_ID"`, `flagged: false`, `average_score: 0`

2. **Verify Total Students increases by 1**

3. **Flag the student** by setting `flagged: true`

4. **Verify Flagged Students increases by 1**

5. **Create a test exam** with:
   - Collection: `exams`
   - Fields: `teacherId: "YOUR_TEACHER_ID"`, `isActive: true`

6. **Verify Ongoing Exams increases by 1**

---

## Summary

✅ Your dashboard is **already connected** to Firestore!

**Current behavior:**
- Loads data once when page opens
- User can refresh with pull-to-refresh gesture
- Shows accurate counts based on filters

**To improve:** Consider using StreamBuilders for real-time updates instead of one-time loads.

