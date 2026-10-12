import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import 'leave_enums.dart';

/// A configurable leave type (`.../branches/{b}/leaveTypes/{kind}__{code}`).
///
/// Nothing about entitlements is hard-coded: a school defines the types and
/// their policy. A type is never deleted — only deactivated — and an
/// application snapshots the type's name and pay type, so changing or
/// deactivating a type never rewrites history.
class LeaveType {
  final String typeId;
  final String schoolId;
  final String branchId;
  final LeaveKind kind;
  final String code;
  final String name;
  final LeavePayType payType;
  final bool requiresDocument;
  final bool requiresReason;
  final bool allowHalfDay;

  /// Count holidays and weekends as leave days too (e.g. maternity leave).
  final bool countNonWorkingDays;

  /// Longest single application, in days. Null = the global cap.
  final int? maxDaysPerRequest;

  /// Roles that may use this type (UserRole wire values). Empty = all.
  final List<String> applicableRoles;

  /// Employment types (staff only, EmploymentType wire values). Empty = all.
  final List<String> applicableEmploymentTypes;

  /// Staff only. Null = no balance is tracked for this type.
  final int? annualEntitlementUnits;
  final AccrualMode accrual;
  final int carryForwardMaxUnits;
  final ExceedPolicy exceedPolicy;
  final ActivationStatus status;
  final DateTime? updatedAt;

  const LeaveType({
    required this.typeId,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.code,
    required this.name,
    this.payType = LeavePayType.paid,
    this.requiresDocument = false,
    this.requiresReason = true,
    this.allowHalfDay = true,
    this.countNonWorkingDays = false,
    this.maxDaysPerRequest,
    this.applicableRoles = const [],
    this.applicableEmploymentTypes = const [],
    this.annualEntitlementUnits,
    this.accrual = AccrualMode.upfront,
    this.carryForwardMaxUnits = 0,
    this.exceedPolicy = ExceedPolicy.block,
    this.status = ActivationStatus.active,
    this.updatedAt,
  });

  /// The longest an application may span, whatever the type says. Bounds the
  /// number of day-locks one application writes.
  static const int globalMaxDays = 60;

  static String idFor(LeaveKind kind, String code) =>
      '${kind.wireValue}__${code.trim().toLowerCase()}';

  bool get isActive => status == ActivationStatus.active;

  /// A balance is tracked only for staff types with an entitlement.
  bool get tracksBalance =>
      kind == LeaveKind.staff &&
      annualEntitlementUnits != null &&
      payType != LeavePayType.unpaid;

  int get effectiveMaxDays {
    final m = maxDaysPerRequest;
    return m == null || m > globalMaxDays ? globalMaxDays : m;
  }

  bool appliesToRole(String roleWire) =>
      applicableRoles.isEmpty || applicableRoles.contains(roleWire);

  bool appliesToEmployment(String? employmentWire) =>
      applicableEmploymentTypes.isEmpty ||
      (employmentWire != null &&
          applicableEmploymentTypes.contains(employmentWire));

  static final RegExp _codePattern = RegExp(r'^[A-Za-z0-9_-]{2,20}$');

  /// A user-readable reason this configuration is invalid, or null.
  String? validate() {
    if (!_codePattern.hasMatch(code.trim())) {
      return 'Code must be 2-20 letters, digits, "-" or "_".';
    }
    if (name.trim().length < 2 || name.trim().length > 60) {
      return 'Name must be 2-60 characters.';
    }
    if (kind == LeaveKind.student && payType != LeavePayType.notApplicable) {
      return 'Student leave is not paid or unpaid; use "Not applicable".';
    }
    if (kind == LeaveKind.staff && payType == LeavePayType.notApplicable) {
      return 'Choose paid or unpaid for staff leave.';
    }
    final m = maxDaysPerRequest;
    if (m != null && (m < 1 || m > globalMaxDays)) {
      return 'Longest request must be between 1 and $globalMaxDays days.';
    }
    final e = annualEntitlementUnits;
    if (kind == LeaveKind.student && e != null) {
      return 'Student leave has no entitlement.';
    }
    if (payType == LeavePayType.unpaid && e != null) {
      return 'Unpaid leave has no entitlement balance.';
    }
    if (e != null && (e < 1 || e > 366 * 2)) {
      return 'Annual entitlement must be between 0.5 and 366 days.';
    }
    if (carryForwardMaxUnits < 0 || (e == null && carryForwardMaxUnits > 0)) {
      return 'Carry-forward needs an entitlement and cannot be negative.';
    }
    return null;
  }

  LeaveType copyWith({
    String? name,
    LeavePayType? payType,
    bool? requiresDocument,
    bool? requiresReason,
    bool? allowHalfDay,
    bool? countNonWorkingDays,
    int? maxDaysPerRequest,
    bool clearMaxDays = false,
    List<String>? applicableRoles,
    List<String>? applicableEmploymentTypes,
    int? annualEntitlementUnits,
    bool clearEntitlement = false,
    AccrualMode? accrual,
    int? carryForwardMaxUnits,
    ExceedPolicy? exceedPolicy,
    ActivationStatus? status,
  }) {
    return LeaveType(
      typeId: typeId,
      schoolId: schoolId,
      branchId: branchId,
      kind: kind,
      code: code,
      name: name ?? this.name,
      payType: payType ?? this.payType,
      requiresDocument: requiresDocument ?? this.requiresDocument,
      requiresReason: requiresReason ?? this.requiresReason,
      allowHalfDay: allowHalfDay ?? this.allowHalfDay,
      countNonWorkingDays: countNonWorkingDays ?? this.countNonWorkingDays,
      maxDaysPerRequest: clearMaxDays
          ? null
          : (maxDaysPerRequest ?? this.maxDaysPerRequest),
      applicableRoles: applicableRoles ?? this.applicableRoles,
      applicableEmploymentTypes:
          applicableEmploymentTypes ?? this.applicableEmploymentTypes,
      annualEntitlementUnits: clearEntitlement
          ? null
          : (annualEntitlementUnits ?? this.annualEntitlementUnits),
      accrual: accrual ?? this.accrual,
      carryForwardMaxUnits: carryForwardMaxUnits ?? this.carryForwardMaxUnits,
      exceedPolicy: exceedPolicy ?? this.exceedPolicy,
      status: status ?? this.status,
      updatedAt: updatedAt,
    );
  }

  factory LeaveType.fromFirestore(Map<String, dynamic> d, String id) {
    return LeaveType(
      typeId: id,
      schoolId: d[FirestoreFields.schoolId] as String,
      branchId: d[FirestoreFields.branchId] as String,
      kind: LeaveKind.fromWireValue(d['kind'] as String),
      code: d['code'] as String,
      name: d['name'] as String,
      payType: LeavePayType.fromWireValue(d['payType'] as String),
      requiresDocument: d['requiresDocument'] as bool? ?? false,
      requiresReason: d['requiresReason'] as bool? ?? true,
      allowHalfDay: d['allowHalfDay'] as bool? ?? true,
      countNonWorkingDays: d['countNonWorkingDays'] as bool? ?? false,
      maxDaysPerRequest: (d['maxDaysPerRequest'] as num?)?.toInt(),
      applicableRoles: List<String>.from(d['applicableRoles'] as List? ?? []),
      applicableEmploymentTypes: List<String>.from(
        d['applicableEmploymentTypes'] as List? ?? [],
      ),
      annualEntitlementUnits: (d['annualEntitlementUnits'] as num?)?.toInt(),
      accrual: AccrualMode.fromWireValue(d['accrual'] as String? ?? 'UPFRONT'),
      carryForwardMaxUnits: (d['carryForwardMaxUnits'] as num?)?.toInt() ?? 0,
      exceedPolicy: ExceedPolicy.fromWireValue(
        d['exceedPolicy'] as String? ?? 'BLOCK',
      ),
      status: ActivationStatus.fromWireValue(
        d[FirestoreFields.status] as String? ?? 'ACTIVE',
      ),
      updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> _body() => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'kind': kind.wireValue,
    'code': code.trim(),
    'name': name.trim(),
    'payType': payType.wireValue,
    'requiresDocument': requiresDocument,
    'requiresReason': requiresReason,
    'allowHalfDay': allowHalfDay,
    'countNonWorkingDays': countNonWorkingDays,
    'maxDaysPerRequest': maxDaysPerRequest,
    'applicableRoles': applicableRoles,
    'applicableEmploymentTypes': applicableEmploymentTypes,
    'annualEntitlementUnits': annualEntitlementUnits,
    'accrual': accrual.wireValue,
    'carryForwardMaxUnits': carryForwardMaxUnits,
    'exceedPolicy': exceedPolicy.wireValue,
    FirestoreFields.status: status.wireValue,
  };

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    ..._body(),
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };

  Map<String, dynamic> toFirestoreUpdate({required String actorId}) => {
    ..._body(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: actorId,
  };
}
