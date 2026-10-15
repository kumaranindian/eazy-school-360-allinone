import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/permissions/user_role.dart';
import '../../authentication/domain/login_method.dart';
import 'user_status.dart';

/// The `/users/{uid}` document. `schoolId`/`branchId` are nullable because
/// [UserRole.platformAdmin] is not scoped to any single school, and
/// [UserRole.schoolAdmin] is not scoped to any single branch — see
/// `UserRole.isSchoolScoped`/`.isBranchScoped`.
/// The server-written `login` map on `/users/{uid}` (see functions/access.js).
/// Absent on legacy accounts, which keep working as before.
class LoginState {
  final bool enabled;
  final List<LoginMethod> methods;

  /// Permitted methods ∩ the school's enabled methods — what firestore.rules
  /// checks the current sign-in against.
  final List<LoginMethod> effective;

  const LoginState({
    required this.enabled,
    required this.methods,
    required this.effective,
  });

  static LoginState? fromData(Object? raw) {
    if (raw is! Map) return null;
    return LoginState(
      enabled: raw['enabled'] == true,
      methods: LoginMethod.listFromWire(raw['methods']),
      effective: LoginMethod.listFromWire(raw['effective']),
    );
  }

  bool allows(LoginMethod? method) =>
      enabled && method != null && effective.contains(method);
}

/// A `/users/{uid}` document that exists but cannot be used: its role or
/// status is missing or not one this app knows (a typo, a lowercase value, a
/// role from another system). Surfaced as "account not set up correctly"
/// instead of a crash or an endless loading screen.
///
/// An [Error], not an `Exception`, so Riverpod does not retry it.
class InvalidProfileException extends Error {
  final String field;
  InvalidProfileException(this.field);

  @override
  String toString() => 'InvalidProfileException(field: $field)';
}

class UserProfile {
  final String userId;
  final String? schoolId;
  final String? branchId;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final UserRole role;
  final UserStatus status;

  /// For [UserRole.parent] only: the linked `/schools/{s}/branches/{b}/
  /// parents/{parentId}` record's id, set once portal access is granted —
  /// see `docs/milestone-3-student-parent-management.md` → "Parent portal
  /// access foundation". Null for every other role, and null for a parent
  /// whose contact record exists but has no login account yet.
  final String? linkedParentId;

  /// Null for legacy accounts (no restriction beyond [status]).
  final LoginState? login;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const UserProfile({
    required this.userId,
    required this.schoolId,
    required this.branchId,
    required this.name,
    required this.email,
    this.phone,
    this.photoUrl,
    required this.role,
    required this.status,
    this.linkedParentId,
    this.login,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  bool get isActive => status == UserStatus.active;

  factory UserProfile.fromFirestore(String userId, Map<String, dynamic> data) {
    return UserProfile(
      userId: userId,
      schoolId: data[FirestoreFields.schoolId] as String?,
      branchId: data[FirestoreFields.branchId] as String?,
      name: data[FirestoreFields.name] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String?,
      photoUrl: data['photoUrl'] as String?,
      role: _parse(
        data[FirestoreFields.role],
        FirestoreFields.role,
        UserRole.fromWireValue,
      ),
      status: _parse(
        data[FirestoreFields.status],
        FirestoreFields.status,
        UserStatus.fromWireValue,
      ),
      linkedParentId: data['linkedParentId'] as String?,
      login: LoginState.fromData(data['login']),
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  static T _parse<T>(Object? raw, String field, T Function(String) parse) {
    if (raw is! String) throw InvalidProfileException(field);
    try {
      return parse(raw);
    } on StateError {
      throw InvalidProfileException(field);
    }
  }

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      FirestoreFields.name: name,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      FirestoreFields.role: role.wireValue,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Links a (PARENT-role) account to its `/parents/{parentId}` record — a
  /// school/branch admin action, never self-service. Static: no existing
  /// [UserProfile] instance is needed, just the uid being updated. See
  /// `docs/milestone-3-student-parent-management.md` → "Parent portal
  /// access foundation".
  static Map<String, dynamic> firestoreParentLink({
    required String parentId,
    required String updatedBy,
  }) {
    return {
      'linkedParentId': parentId,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  /// Fields a user is allowed to change on their own profile — must match
  /// exactly what `firestore.rules`' self-update rule permits.
  Map<String, dynamic> toFirestoreSelfUpdate({required String updatedBy}) {
    return {
      FirestoreFields.name: name,
      'phone': phone,
      'photoUrl': photoUrl,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
