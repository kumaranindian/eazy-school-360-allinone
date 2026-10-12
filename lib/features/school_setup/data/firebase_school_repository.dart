import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/permissions/user_role.dart';
import '../../users/domain/user_profile.dart';
import '../../users/domain/user_status.dart';
import '../domain/branch.dart';
import '../domain/school.dart';
import '../domain/school_repository.dart';
import '../domain/school_status.dart';
import '../domain/branch_status.dart';

/// Self-signup writes the school, the caller's SCHOOL_ADMIN profile, and
/// the default branch in ONE atomic [WriteBatch] — all three exist or none
/// do. `firestore.rules` cross-checks the three writes with
/// `getAfter()`/`existsAfter()` so a profile can only ever claim a school
/// the same caller is creating in the same batch. See
/// FIRESTORE_ARCHITECTURE.md → "School creation".
///
/// Accounts created before this was a single batch may have a profile but
/// no default branch; calling [createSchoolForCurrentUser] again repairs
/// that by creating only the missing branch.
class FirebaseSchoolRepository implements SchoolRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  FirebaseSchoolRepository(this._firestore, this._storage);

  DocumentReference<Map<String, dynamic>> _schoolDoc(String schoolId) =>
      _firestore.collection(FirestoreFields.schoolsCollection).doc(schoolId);

  CollectionReference<Map<String, dynamic>> _branchesCollection(
    String schoolId,
  ) => _schoolDoc(schoolId).collection(FirestoreFields.branchesCollection);

  DocumentReference<Map<String, dynamic>> _branchDoc(
    String schoolId,
    String branchId,
  ) => _branchesCollection(schoolId).doc(branchId);

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection(FirestoreFields.usersCollection).doc(userId);

  Branch _defaultBranch(String schoolId) => Branch(
    branchId: AppConstants.defaultBranchId,
    schoolId: schoolId,
    name: 'Main Branch',
    status: BranchStatus.active,
  );

  @override
  Future<School?> getSchool(String schoolId) async {
    try {
      final snapshot = await _schoolDoc(schoolId).get();
      if (!snapshot.exists) return null;
      return School.fromFirestore(schoolId, snapshot.data()!);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateSchoolProfile(
    School school, {
    required String updatedBy,
  }) async {
    try {
      await _schoolDoc(
        school.schoolId,
      ).update(school.toFirestoreProfileUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> uploadSchoolLogo({
    required String schoolId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) async {
    try {
      // A fixed path (not a generated filename) means re-uploading always
      // replaces the previous logo instead of accumulating orphaned files.
      final ref = _storage.ref('schools/$schoolId/logo.$fileExtension');
      AppLogger.debug(
        'Logo upload: start path=${ref.fullPath} bucket=${ref.bucket} '
        'bytes=${fileBytes.length}',
        tag: 'Storage',
      );
      // Without a timeout a missing bucket / blocked rule just retries
      // forever and the UI spins; fail with a diagnosable error instead.
      await ref
          .putData(
            Uint8List.fromList(fileBytes),
            SettableMetadata(contentType: _contentTypeFor(fileExtension)),
          )
          .timeout(_storageTimeout);
      AppLogger.debug(
        'Logo upload: bytes stored; fetching URL',
        tag: 'Storage',
      );
      final url = await ref.getDownloadURL().timeout(_storageTimeout);
      AppLogger.debug('Logo upload: updating school doc', tag: 'Storage');
      await _schoolDoc(schoolId).update({
        'logoUrl': url,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
      AppLogger.debug('Logo upload: done', tag: 'Storage');
      return url;
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.error(
        'Logo upload timed out after ${_storageTimeout.inSeconds}s. Usual '
        'causes: Firebase Storage not set up for this project (Console → '
        'Storage → Get started), storage.rules not deployed, or no network.',
        tag: 'Storage',
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnknownFailure(
        'Logo upload timed out. Please check your connection and try again.',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Logo upload failed',
        tag: 'Storage',
        error: error,
        stackTrace: stackTrace,
      );
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  static const _storageTimeout = Duration(seconds: 30);

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

  @override
  Future<Branch?> getBranch(String schoolId, String branchId) async {
    try {
      final snapshot = await _branchDoc(schoolId, branchId).get();
      if (!snapshot.exists) return null;
      return Branch.fromFirestore(schoolId, branchId, snapshot.data()!);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<Branch>> watchBranches(String schoolId) {
    return _schoolDoc(schoolId)
        .collection(FirestoreFields.branchesCollection)
        .orderBy(FirestoreFields.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Branch.fromFirestore(schoolId, doc.id, doc.data()))
              .toList(),
        )
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<String> createBranch(
    Branch branch, {
    required String createdBy,
  }) async {
    try {
      final ref = _branchesCollection(branch.schoolId).doc();
      await ref.set(branch.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateBranch(Branch branch, {required String updatedBy}) async {
    try {
      await _branchDoc(
        branch.schoolId,
        branch.branchId,
      ).update(branch.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> createSchoolForCurrentUser({
    required String userId,
    required String userName,
    required String userEmail,
    required String schoolName,
    required String schoolEmail,
    String? schoolPhone,
  }) async {
    try {
      final existingProfile = await _userDoc(userId).get();

      if (existingProfile.exists) {
        final schoolId =
            existingProfile.data()![FirestoreFields.schoolId] as String;
        final branchRef = _branchDoc(schoolId, AppConstants.defaultBranchId);
        if (!(await branchRef.get()).exists) {
          await branchRef.set(
            _defaultBranch(schoolId).toFirestoreCreate(createdBy: userId),
          );
        }
        return schoolId;
      }

      final schoolId = _firestore
          .collection(FirestoreFields.schoolsCollection)
          .doc()
          .id;
      final school = School(
        schoolId: schoolId,
        name: schoolName,
        email: schoolEmail,
        phone: schoolPhone,
        status: SchoolStatus.active,
      );
      final adminProfile = UserProfile(
        userId: userId,
        schoolId: schoolId,
        branchId: AppConstants.defaultBranchId,
        name: userName,
        email: userEmail,
        role: UserRole.schoolAdmin,
        status: UserStatus.active,
      );

      final batch = _firestore.batch()
        ..set(_schoolDoc(schoolId), school.toFirestoreCreate(createdBy: userId))
        ..set(
          _userDoc(userId),
          adminProfile.toFirestoreCreate(createdBy: userId),
        )
        ..set(
          _branchDoc(schoolId, AppConstants.defaultBranchId),
          _defaultBranch(schoolId).toFirestoreCreate(createdBy: userId),
        );
      await batch.commit();

      return schoolId;
    } catch (error, stackTrace) {
      // Log detailed error information for debugging
      AppLogger.error(
        'School creation failed',
        error: error,
        stackTrace: stackTrace,
        tag: 'SchoolCreation',
      );

      // Add additional context for Firebase errors
      if (error is FirebaseException) {
        AppLogger.error(
          'Firebase error details: code=${error.code}, message=${error.message}',
          tag: 'SchoolCreation',
        );
      }

      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
