import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';

/// `schools/{s}/parentEmails/{key}`: one parent per email address in a
/// school (STU-02-DEF-01). Written with the parent in one transaction and
/// required by the `parents` create/update rules, so a second parent with
/// the same email is refused by the server, not only by the form. A parent
/// copied to another branch keeps its id, so the same reservation covers it.
class ParentEmailReservation {
  const ParentEmailReservation._();

  /// The document id: the lower-cased address ('/' is not allowed in an id).
  /// The rules compute the same key (`parentEmailKey`).
  static String key(String email) =>
      email.trim().toLowerCase().replaceAll('/', '%2F');

  static String path(String schoolId, String email) =>
      'schools/$schoolId/${FirestoreFields.parentEmailsCollection}/'
      '${key(email)}';

  static Map<String, dynamic> data({
    required String schoolId,
    required String branchId,
    required String parentId,
    required String email,
    required String actorId,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'parentId': parentId,
    'email': email.trim().toLowerCase(),
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
  };
}

/// Shown when the email already belongs to another parent of the school.
const parentEmailInUseMessage =
    'This email already belongs to another parent in this school. '
    'Link that parent instead.';
