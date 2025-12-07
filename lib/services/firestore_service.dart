import 'package:cloud_firestore/cloud_firestore.dart';

class ExamService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _exams => _db.collection('exams');

  Future<DocumentReference> addExam(Map<String, dynamic> data) {
    return _exams.add({...data, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> updateExam(String id, Map<String, dynamic> data) {
    return _exams.doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
