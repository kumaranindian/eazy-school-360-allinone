import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../../users/domain/user_profile.dart';
import '../domain/paged_result.dart';
import '../domain/parent.dart';
import '../domain/parent_repository.dart';
import '../domain/student.dart';

/// `/schools/{s}/branches/{b}/parents/{parentId}`. [getChildrenForParent]
/// is the one method here that reaches outside this collection — a
/// `collectionGroup('parentLinks')` query across every student's
/// `parentLinks` subcollection, which is how "which students does this
/// parent have" is answered without denormalizing a student list onto
/// [Parent] (see that class's doc comment and
/// `docs/milestone-3-student-parent-management.md` → "Querying both
/// directions").
class FirebaseParentRepository implements ParentRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  FirebaseParentRepository(this._firestore, this._storage);

  CollectionReference<Map<String, dynamic>> _parentsCollection(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.parentsCollection);

  DocumentReference<Map<String, dynamic>> _parentDoc(
    String schoolId,
    String branchId,
    String parentId,
  ) => _parentsCollection(schoolId, branchId).doc(parentId);

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection(FirestoreFields.usersCollection).doc(userId);

  DocumentReference<Map<String, dynamic>> _studentDoc(
    String schoolId,
    String branchId,
    String studentId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.studentsCollection)
      .doc(studentId);

  DocumentSnapshot<Map<String, dynamic>>? _cursorOf(Object? cursor) =>
      cursor as DocumentSnapshot<Map<String, dynamic>>?;

  PagedResult<Parent> _toPage(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int pageSize,
    String schoolId,
    String branchId,
  ) {
    final hasMore = docs.length > pageSize;
    final pageDocs = hasMore ? docs.sublist(0, pageSize) : docs;
    return PagedResult(
      items: pageDocs
          .map((d) => Parent.fromFirestore(schoolId, branchId, d.id, d.data()))
          .toList(),
      nextCursor: hasMore ? pageDocs.last : null,
    );
  }

  @override
  Future<PagedResult<Parent>> fetchParents({
    required String schoolId,
    required String branchId,
    ActivationStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _parentsCollection(
        schoolId,
        branchId,
      );
      if (status != null) {
        query = query.where(
          FirestoreFields.status,
          isEqualTo: status.wireValue,
        );
      }
      query = query.orderBy('displayNameLower').limit(pageSize + 1);
      final startAfter = _cursorOf(cursor);
      if (startAfter != null) query = query.startAfterDocument(startAfter);

      final snapshot = await query.get();
      return _toPage(snapshot.docs, pageSize, schoolId, branchId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<PagedResult<Parent>> searchParentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final lower = query.trim().toLowerCase();
      Query<Map<String, dynamic>> q = _parentsCollection(schoolId, branchId)
          .orderBy('displayNameLower')
          .startAt([lower])
          .endAt(['$lower'])
          .limit(pageSize + 1);
      final startAfter = _cursorOf(cursor);
      if (startAfter != null) {
        q = _parentsCollection(schoolId, branchId)
            .orderBy('displayNameLower')
            .startAfterDocument(startAfter)
            .endAt(['$lower'])
            .limit(pageSize + 1);
      }
      final snapshot = await q.get();
      return _toPage(snapshot.docs, pageSize, schoolId, branchId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Parent?> getParent(
    String schoolId,
    String branchId,
    String parentId,
  ) async {
    try {
      final snapshot = await _parentDoc(schoolId, branchId, parentId).get();
      if (!snapshot.exists) return null;
      return Parent.fromFirestore(
        schoolId,
        branchId,
        parentId,
        snapshot.data()!,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Parent?> watchParent(
    String schoolId,
    String branchId,
    String parentId,
  ) {
    return _parentDoc(schoolId, branchId, parentId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return Parent.fromFirestore(
            schoolId,
            branchId,
            parentId,
            snapshot.data()!,
          );
        })
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<String> createParent(
    Parent parent, {
    required String createdBy,
  }) async {
    try {
      final ref = _parentsCollection(parent.schoolId, parent.branchId).doc();
      await ref.set(parent.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateParent(Parent parent, {required String updatedBy}) async {
    try {
      await _parentDoc(
        parent.schoolId,
        parent.branchId,
        parent.parentId,
      ).update(parent.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  /// Without a timeout a missing bucket or blocked rule retries for a long
  /// time and the screen just spins.
  static const _uploadTimeout = Duration(seconds: 30);

  @override
  Future<String> uploadParentPhoto({
    required String schoolId,
    required String branchId,
    required String parentId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) async {
    try {
      final ref = _storage.ref(
        'schools/$schoolId/branches/$branchId/parents/$parentId/photo.$fileExtension',
      );
      await ref
          .putData(
            Uint8List.fromList(fileBytes),
            SettableMetadata(contentType: _contentTypeFor(fileExtension)),
          )
          .timeout(_uploadTimeout);
      final url = await ref.getDownloadURL().timeout(_uploadTimeout);
      await _parentDoc(schoolId, branchId, parentId).update({
        'photoUrl': url,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
      return url;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Student>> getChildrenForParent({
    required String schoolId,
    required String parentId,
  }) async {
    try {
      final links = await _firestore
          .collectionGroup(FirestoreFields.parentLinksCollection)
          .where('schoolId', isEqualTo: schoolId)
          .where('parentId', isEqualTo: parentId)
          .get();

      final students = <Student>[];
      for (final link in links.docs) {
        final data = link.data();
        // Only children this parent may actually open: an ACTIVE link with
        // portal access. (Firestore rules refuse the student document
        // otherwise, which would fail the whole list.)
        if (data['canAccessPortal'] != true || data['status'] != 'ACTIVE') {
          continue;
        }
        final branchId = data[FirestoreFields.branchId] as String;
        final studentId = data['studentId'] as String;
        try {
          final studentSnapshot = await _studentDoc(
            schoolId,
            branchId,
            studentId,
          ).get();
          if (studentSnapshot.exists) {
            students.add(
              Student.fromFirestore(
                schoolId,
                branchId,
                studentId,
                studentSnapshot.data()!,
              ),
            );
          }
        } on FirebaseException catch (error) {
          // One unreadable child must not hide the others.
          if (error.code != 'permission-denied') rethrow;
        }
      }
      return students;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> linkPortalAccess({
    required String schoolId,
    required String branchId,
    required String parentId,
    required String userId,
    required String updatedBy,
  }) async {
    try {
      final batch = _firestore.batch()
        ..update(_parentDoc(schoolId, branchId, parentId), {
          'linkedUserId': userId,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: updatedBy,
        })
        ..update(
          _userDoc(userId),
          UserProfile.firestoreParentLink(
            parentId: parentId,
            updatedBy: updatedBy,
          ),
        );
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
