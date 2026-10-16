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

  /// Server-written (`setBranchAccess` / provisioning): the role this login
  /// holds in branches OTHER than its home branch. Only branch-scoped staff
  /// roles can appear; unknown or invalid entries are dropped on read.
  final Map<String, UserRole> branchRoles;

  /// The account's own branch and role. [branchId]/[role] describe the branch
  /// the user is currently acting in (see [activeIn]); these never change.
  final String? _homeBranchId;
  final UserRole? _homeRole;

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
    this.branchRoles = const {},
    String? homeBranchId,
    UserRole? homeRole,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  }) : _homeBranchId = homeBranchId,
       _homeRole = homeRole;

  String? get homeBranchId => _homeBranchId ?? branchId;
  UserRole get homeRole => _homeRole ?? role;

  /// Branches this login can act in, home branch first. Empty for roles that
  /// are not branch-scoped (school/platform admins reach every branch another
  /// way) and for parents.
  List<String> get workingBranchIds {
    if (homeRole == UserRole.parent || !homeRole.isBranchScoped) {
      return const [];
    }
    final home = homeBranchId;
    final others = branchRoles.keys.where((b) => b != home).toList()..sort();
    return [?home, ...others];
  }

  bool get worksInMultipleBranches => workingBranchIds.length > 1;

  /// This profile as seen while acting in [branchId]: that branch and the role
  /// held there. An unknown branch leaves the profile unchanged (no access is
  /// ever invented client-side; firestore.rules decide).
  UserProfile activeIn(String branchId) {
    if (branchId == this.branchId && role == (branchRoles[branchId] ?? role)) {
      return this;
    }
    final isHome = branchId == homeBranchId;
    final next = isHome ? homeRole : branchRoles[branchId];
    if (next == null) return this;
    return UserProfile(
      userId: userId,
      schoolId: schoolId,
      branchId: branchId,
      name: name,
      email: email,
      phone: phone,
      photoUrl: photoUrl,
      role: next,
      status: status,
      linkedParentId: linkedParentId,
      login: login,
      branchRoles: branchRoles,
      homeBranchId: homeBranchId,
      homeRole: homeRole,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

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
      branchRoles: _parseBranchRoles(data['branchRoles']),
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  static const _staffRoles = {
    UserRole.branchAdmin,
    UserRole.teacher,
    UserRole.finance,
  };

  static Map<String, UserRole> _parseBranchRoles(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, UserRole>{};
    for (final e in raw.entries) {
      if (e.key is! String || e.value is! String) continue;
      try {
        final r = UserRole.fromWireValue(e.value as String);
        if (_staffRoles.contains(r)) out[e.key as String] = r;
      } on StateError {
        // An unknown role grants nothing.
      }
    }
    return Map.unmodifiable(out);
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
