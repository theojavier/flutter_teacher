import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> deleteStudentExamResult({
  required String examId,
  required String studentId,
}) async {
  final db = FirebaseFirestore.instance;
  final studentRef = db
      .collection('examResults')
      .doc(examId)
      .collection('students')
      .doc(studentId);

  Future<void> deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(400).get();
      if (snapshot.docs.isEmpty) return;

      final batch = db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  await deleteSubcollection(studentRef.collection('answers'));
  await deleteSubcollection(studentRef.collection('cheatClips'));
  await deleteSubcollection(studentRef.collection('strikeEvents')); 
  await deleteSubcollection(studentRef.collection('strikeState')); 
  await studentRef.delete();
}
