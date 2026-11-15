/// A school's expense settings (docs/expense-management/). Written only by
/// the `saveExpenseSettings` callable; the server validates the same rules.
library;

import '../../../core/permissions/user_role.dart';

class ExpenseSettings {
  /// Whether a submitted expense needs approval before it can be paid. When
  /// off, submitting approves it at once (the step is still recorded).
  final bool approvalRequired;

  /// Whether the person who submitted an expense may also approve it.
  final bool allowSelfApproval;

  /// Roles that may approve (school admin always; branch admin when listed).
  final List<UserRole> approverRoles;

  /// A receipt is required for amounts above this (minor units); null = never.
  final int? receiptRequiredOverMinor;

  /// For the optimistic update check on save.
  final int version;

  const ExpenseSettings({
    this.approvalRequired = true,
    this.allowSelfApproval = false,
    this.approverRoles = const [UserRole.schoolAdmin],
    this.receiptRequiredOverMinor,
    this.version = 0,
  });

  /// The roles a school may choose as approvers.
  static const choosableApprovers = [
    UserRole.schoolAdmin,
    UserRole.branchAdmin,
  ];

  factory ExpenseSettings.fromMap(Map<String, dynamic> m) {
    final roles = <UserRole>[];
    for (final r in (m['approverRoles'] as List? ?? const [])) {
      try {
        roles.add(UserRole.fromWireValue(r as String));
      } catch (_) {
        // An unknown role from a newer server is ignored, never trusted.
      }
    }
    return ExpenseSettings(
      approvalRequired: m['approvalRequired'] != false,
      allowSelfApproval: m['allowSelfApproval'] == true,
      approverRoles: roles.isEmpty ? const [UserRole.schoolAdmin] : roles,
      receiptRequiredOverMinor: (m['receiptRequiredOverMinor'] as num?)
          ?.toInt(),
      version: (m['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toRequest() => {
    'approvalRequired': approvalRequired,
    'allowSelfApproval': allowSelfApproval,
    'approverRoles': [for (final r in approverRoles) r.wireValue],
    'receiptRequiredOverMinor': receiptRequiredOverMinor,
  };

  /// Whether [role] may approve under these settings (school admin always).
  bool canApprove(UserRole role) =>
      role == UserRole.schoolAdmin || approverRoles.contains(role);

  ExpenseSettings copyWith({
    bool? approvalRequired,
    bool? allowSelfApproval,
    List<UserRole>? approverRoles,
    Object? receiptRequiredOverMinor = _keep,
  }) => ExpenseSettings(
    approvalRequired: approvalRequired ?? this.approvalRequired,
    allowSelfApproval: allowSelfApproval ?? this.allowSelfApproval,
    approverRoles: approverRoles ?? this.approverRoles,
    receiptRequiredOverMinor: identical(receiptRequiredOverMinor, _keep)
        ? this.receiptRequiredOverMinor
        : receiptRequiredOverMinor as int?,
    version: version,
  );

  static const Object _keep = Object();
}
