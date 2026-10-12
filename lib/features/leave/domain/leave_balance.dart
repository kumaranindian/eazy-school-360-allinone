import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../attendance/domain/attendance_date.dart';
import 'leave_enums.dart';
import 'leave_type.dart';
import 'leave_units.dart';

/// `.../leaveBalances/{staffId}__{typeId}__{academicYearId}` — one staff
/// member's balance of one leave type for one leave year (= academic year).
///
/// The document stores only the **movements**; the figures a screen shows are
/// always derived by [LeaveBalanceMath], never recomputed in a widget. The
/// entitlement and accrual rule are snapshotted at creation, so editing the
/// leave type later does not rewrite a year already in progress.
class LeaveBalance {
  final String balanceId;
  final String schoolId;
  final String branchId;
  final String staffId;
  final String typeId;
  final String academicYearId;
  final String leaveYearStartKey;
  final int entitlementUnits;
  final AccrualMode accrual;
  final ExceedPolicy exceedPolicy;
  final int carryForwardUnits;
  final int adjustmentUnits;
  final int consumedUnits;
  final DateTime? updatedAt;

  const LeaveBalance({
    required this.balanceId,
    required this.schoolId,
    required this.branchId,
    required this.staffId,
    required this.typeId,
    required this.academicYearId,
    required this.leaveYearStartKey,
    required this.entitlementUnits,
    this.accrual = AccrualMode.upfront,
    this.exceedPolicy = ExceedPolicy.block,
    this.carryForwardUnits = 0,
    this.adjustmentUnits = 0,
    this.consumedUnits = 0,
    this.updatedAt,
  });

  static String idFor(String staffId, String typeId, String yearId) =>
      '${staffId}__${typeId}__$yearId';

  /// A balance never yet created: the policy's figures with nothing used.
  factory LeaveBalance.fromPolicy({
    required String schoolId,
    required String branchId,
    required String staffId,
    required LeaveType type,
    required String academicYearId,
    required String leaveYearStartKey,
    int carryForwardUnits = 0,
  }) => LeaveBalance(
    balanceId: idFor(staffId, type.typeId, academicYearId),
    schoolId: schoolId,
    branchId: branchId,
    staffId: staffId,
    typeId: type.typeId,
    academicYearId: academicYearId,
    leaveYearStartKey: leaveYearStartKey,
    entitlementUnits: type.annualEntitlementUnits ?? 0,
    accrual: type.accrual,
    exceedPolicy: type.exceedPolicy,
    carryForwardUnits: carryForwardUnits,
  );

  factory LeaveBalance.fromFirestore(Map<String, dynamic> d, String id) =>
      LeaveBalance(
        balanceId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        staffId: d['staffId'] as String,
        typeId: d['typeId'] as String,
        academicYearId: d['academicYearId'] as String,
        leaveYearStartKey: d['leaveYearStartKey'] as String,
        entitlementUnits: (d['entitlementUnits'] as num).toInt(),
        accrual: AccrualMode.fromWireValue(d['accrual'] as String),
        exceedPolicy: ExceedPolicy.fromWireValue(d['exceedPolicy'] as String),
        carryForwardUnits: (d['carryForwardUnits'] as num?)?.toInt() ?? 0,
        adjustmentUnits: (d['adjustmentUnits'] as num?)?.toInt() ?? 0,
        consumedUnits: (d['consumedUnits'] as num?)?.toInt() ?? 0,
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'staffId': staffId,
    'typeId': typeId,
    'academicYearId': academicYearId,
    'leaveYearStartKey': leaveYearStartKey,
    'entitlementUnits': entitlementUnits,
    'accrual': accrual.wireValue,
    'exceedPolicy': exceedPolicy.wireValue,
    'carryForwardUnits': carryForwardUnits,
    'adjustmentUnits': adjustmentUnits,
    'consumedUnits': consumedUnits,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };
}

/// The figures a balance screen shows. All in half-day units.
class LeaveBalanceFigures {
  /// What the policy grants for the whole leave year.
  final int entitlement;

  /// Granted so far under the accrual rule (== entitlement when up front).
  final int accrued;
  final int carryForward;
  final int adjustments;
  final int consumed;

  /// Applications awaiting a decision. NOT deducted: this module does not
  /// reserve pending days (see the milestone doc), so it is informational.
  final int pending;

  /// accrued + carryForward + adjustments - consumed
  final int available;

  /// entitlement + carryForward + adjustments - consumed: the most the year
  /// can ever allow, regardless of accrual to date. The hard ceiling.
  final int yearCeilingRemaining;

  const LeaveBalanceFigures({
    required this.entitlement,
    required this.accrued,
    required this.carryForward,
    required this.adjustments,
    required this.consumed,
    required this.pending,
    required this.available,
    required this.yearCeilingRemaining,
  });

  /// Available after the pending requests are (hypothetically) approved.
  int get availableIfPendingApproved => available - pending;
}

class BalanceCheck {
  final bool allowed;
  final bool warning;
  final String? message;

  const BalanceCheck.ok() : allowed = true, warning = false, message = null;
  const BalanceCheck.warn(this.message) : allowed = true, warning = true;
  const BalanceCheck.block(this.message) : allowed = false, warning = false;
}

/// The one implementation of the balance model:
///
///     available = accrued(entitlement, accrual, today)
///               + carry-forward + adjustments − consumed
///
/// Everything else (checks on apply and approve, the staff portal, reports)
/// calls this.
abstract final class LeaveBalanceMath {
  /// The entitlement that has accrued by [todayKey].
  /// UPFRONT: all of it. MONTHLY: floor(entitlement × months / 12), where
  /// months counts the leave-year months started so far (1..12). Floored in
  /// half-day units so no fraction below a half day is ever granted.
  static int accruedUnits({
    required int entitlementUnits,
    required AccrualMode mode,
    required String leaveYearStartKey,
    required String todayKey,
  }) {
    if (mode == AccrualMode.upfront) return entitlementUnits;
    final start = AttendanceDate.parse(leaveYearStartKey);
    final today = AttendanceDate.parse(todayKey);
    var months =
        (today.year - start.year) * 12 + (today.month - start.month) + 1;
    if (today.day < start.day) months -= 1;
    months = months.clamp(0, 12);
    return (entitlementUnits * months) ~/ 12;
  }

  static LeaveBalanceFigures figures({
    required LeaveBalance balance,
    required String todayKey,
    int pendingUnits = 0,
  }) {
    final accrued = accruedUnits(
      entitlementUnits: balance.entitlementUnits,
      mode: balance.accrual,
      leaveYearStartKey: balance.leaveYearStartKey,
      todayKey: todayKey,
    );
    final available =
        accrued +
        balance.carryForwardUnits +
        balance.adjustmentUnits -
        balance.consumedUnits;
    final ceiling =
        balance.entitlementUnits +
        balance.carryForwardUnits +
        balance.adjustmentUnits -
        balance.consumedUnits;
    return LeaveBalanceFigures(
      entitlement: balance.entitlementUnits,
      accrued: accrued,
      carryForward: balance.carryForwardUnits,
      adjustments: balance.adjustmentUnits,
      consumed: balance.consumedUnits,
      pending: pendingUnits,
      available: available,
      yearCeilingRemaining: ceiling,
    );
  }

  /// Whether [requestUnits] may be applied for / approved against [figures],
  /// per the balance's [policy]. Unpaid and untracked types never reach this.
  static BalanceCheck check({
    required LeaveBalanceFigures figures,
    required int requestUnits,
    required ExceedPolicy policy,
  }) {
    if (requestUnits <= figures.available) return const BalanceCheck.ok();
    final message =
        'This needs ${LeaveUnits.formatDays(requestUnits)} but only '
        '${LeaveUnits.formatDays(figures.available < 0 ? 0 : figures.available)} '
        'is available.';
    return policy == ExceedPolicy.block
        ? BalanceCheck.block(message)
        : BalanceCheck.warn(message);
  }

  /// A carry-forward into a new year is capped by the type's maximum and can
  /// never be negative or exceed what was actually left.
  static int carryForwardInto({
    required int closingAvailableUnits,
    required int maxCarryUnits,
  }) {
    if (closingAvailableUnits <= 0 || maxCarryUnits <= 0) return 0;
    return closingAvailableUnits < maxCarryUnits
        ? closingAvailableUnits
        : maxCarryUnits;
  }
}

/// `.../leaveLedger/{id}` — append-only. CONSUME / RESTORE ids are
/// deterministic (`{applicationId}__consume`, `…__restore`), so a retried
/// approval or cancellation cannot deduct or restore twice.
class LeaveLedgerEntry {
  final String entryId;
  final String staffId;
  final String typeId;
  final String academicYearId;
  final LedgerEntryType type;
  final int units;
  final String? applicationId;
  final String? reason;
  final String actorId;
  final String actorName;
  final DateTime? at;

  const LeaveLedgerEntry({
    required this.entryId,
    required this.staffId,
    required this.typeId,
    required this.academicYearId,
    required this.type,
    required this.units,
    this.applicationId,
    this.reason,
    required this.actorId,
    required this.actorName,
    this.at,
  });

  static String consumeId(String applicationId) => '${applicationId}__consume';
  static String restoreId(String applicationId) => '${applicationId}__restore';

  factory LeaveLedgerEntry.fromFirestore(Map<String, dynamic> d, String id) =>
      LeaveLedgerEntry(
        entryId: id,
        staffId: d['staffId'] as String,
        typeId: d['typeId'] as String,
        academicYearId: d['academicYearId'] as String,
        type: LedgerEntryType.fromWireValue(d['entryType'] as String),
        units: (d['units'] as num).toInt(),
        applicationId: d['applicationId'] as String?,
        reason: d['reason'] as String?,
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}
