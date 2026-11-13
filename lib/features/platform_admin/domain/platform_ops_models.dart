import 'package:flutter/foundation.dart';

DateTime? _ms(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// The status values a platform owner can set. A suspended school is paused for
/// every one of its users until reactivated.
enum SchoolStatusChoice {
  active('ACTIVE'),
  suspended('SUSPENDED');

  final String wire;
  const SchoolStatusChoice(this.wire);
}

/// The modules the platform can switch off per school (missing = on).
enum PlatformFeature {
  admission(
    'admission',
    'Admission management',
    'Enquiries, applications and conversion',
  ),
  publicAdmission(
    'publicAdmission',
    'Public admission page',
    'The website enquiry form parents use',
  );

  final String key;
  final String label;
  final String description;
  const PlatformFeature(this.key, this.label, this.description);
}

/// What an owner enters to create a school and its first administrator.
class NewSchoolInput {
  final String schoolName;
  final String adminName;
  final String adminEmail;
  final String? schoolEmail;
  final String? phone;
  final String countryCode;
  final String countryName;
  final String currency;
  final String timezone;
  final String dateFormat;

  const NewSchoolInput({
    required this.schoolName,
    required this.adminName,
    required this.adminEmail,
    this.schoolEmail,
    this.phone,
    required this.countryCode,
    required this.countryName,
    required this.currency,
    required this.timezone,
    required this.dateFormat,
  });

  Map<String, dynamic> toCallable() => {
    'schoolName': schoolName.trim(),
    'adminName': adminName.trim(),
    'adminEmail': adminEmail.trim(),
    if (schoolEmail != null && schoolEmail!.trim().isNotEmpty)
      'schoolEmail': schoolEmail!.trim(),
    if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
    'countryName': countryName,
    'regional': {
      'countryCode': countryCode,
      'currency': currency,
      'timezone': timezone,
      'dateFormat': dateFormat,
    },
  };
}

/// One manual billing record (what Avail404 invoices a school for).
class PlatformBillingRecord {
  final String id;
  final String schoolId;
  final String schoolName;
  final String period;
  final int amountMinor;
  final String currency;
  final String dueDate; // yyyy-MM-dd
  final String status; // DUE | PAID | WAIVED | VOID
  final String? paidDate;
  final String? reference;
  final String? note;

  const PlatformBillingRecord({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.period,
    required this.amountMinor,
    required this.currency,
    required this.dueDate,
    required this.status,
    required this.paidDate,
    required this.reference,
    required this.note,
  });

  bool get isDue => status == 'DUE';

  /// Past its due date and still unpaid (the school's local day is not known
  /// here, so the owner's today is used).
  bool isOverdueOn(String todayKey) => isDue && dueDate.compareTo(todayKey) < 0;

  factory PlatformBillingRecord.fromMap(Map<String, dynamic> m) =>
      PlatformBillingRecord(
        id: m['id'] as String,
        schoolId: (m['schoolId'] as String?) ?? '',
        schoolName: (m['schoolName'] as String?) ?? '',
        period: (m['period'] as String?) ?? '',
        amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
        currency: (m['currency'] as String?) ?? '',
        dueDate: (m['dueDate'] as String?) ?? '',
        status: (m['status'] as String?) ?? '',
        paidDate: m['paidDate'] as String?,
        reference: m['reference'] as String?,
        note: m['note'] as String?,
      );
}

/// Records plus what is still owed, per currency.
class BillingSummary {
  final List<PlatformBillingRecord> records;
  final Map<String, ({int dueMinor, int overdueMinor})> owed;

  const BillingSummary({required this.records, required this.owed});

  factory BillingSummary.fromMap(Map<String, dynamic> m) => BillingSummary(
    records: [
      for (final r in (m['records'] as List? ?? const []))
        PlatformBillingRecord.fromMap(Map<String, dynamic>.from(r as Map)),
    ],
    owed: {
      for (final e in Map<String, dynamic>.from(
        (m['owed'] as Map?) ?? const {},
      ).entries)
        e.key: (
          dueMinor: ((e.value as Map)['dueMinor'] as num?)?.toInt() ?? 0,
          overdueMinor:
              ((e.value as Map)['overdueMinor'] as num?)?.toInt() ?? 0,
        ),
    },
  );
}

/// The dashboard numbers (`platformStats/current`, computed nightly).
class PlatformStats {
  final int schoolsTotal;
  final int schoolsActive;
  final int schoolsSuspended;
  final int schoolsInactive;
  final int newSchools30d;
  final int students;
  final int staff;
  final int parents;
  final int branches;
  final int users;
  final int active1d;
  final int active7d;
  final int active30d;
  final bool activityPartial;
  final int openDeletionRequests;
  final int activeSupportGrants;
  final int offboardingOpen;
  final int billingOverdue;
  final DateTime? computedAt;

  const PlatformStats({
    required this.schoolsTotal,
    required this.schoolsActive,
    required this.schoolsSuspended,
    required this.schoolsInactive,
    required this.newSchools30d,
    required this.students,
    required this.staff,
    required this.parents,
    required this.branches,
    required this.users,
    required this.active1d,
    required this.active7d,
    required this.active30d,
    required this.activityPartial,
    required this.openDeletionRequests,
    required this.activeSupportGrants,
    required this.offboardingOpen,
    required this.billingOverdue,
    required this.computedAt,
  });

  /// Older than a day and a half: the nightly job probably did not run.
  bool isStale(DateTime now) =>
      computedAt == null ||
      now.difference(computedAt!) > const Duration(hours: 36);

  factory PlatformStats.fromMap(Map<String, dynamic> m) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final schools = Map<String, dynamic>.from(
      (m['schools'] as Map?) ?? const {},
    );
    final users = Map<String, dynamic>.from((m['users'] as Map?) ?? const {});
    final backlog = Map<String, dynamic>.from(
      (m['backlog'] as Map?) ?? const {},
    );
    return PlatformStats(
      schoolsTotal: n(schools['total']),
      schoolsActive: n(schools['active']),
      schoolsSuspended: n(schools['suspended']),
      schoolsInactive: n(schools['inactive']),
      newSchools30d: n(m['newSchools30d']),
      students: n(m['students']),
      staff: n(m['staff']),
      parents: n(m['parents']),
      branches: n(m['branches']),
      users: n(users['total']),
      active1d: n(users['active1d']),
      active7d: n(users['active7d']),
      active30d: n(users['active30d']),
      activityPartial: users['partial'] == true,
      openDeletionRequests: n(backlog['openDeletionRequests']),
      activeSupportGrants: n(backlog['activeSupportGrants']),
      offboardingOpen: n(backlog['offboardingOpen']),
      billingOverdue: n(backlog['billingOverdue']),
      computedAt: _ms(m['computedAtMs']),
    );
  }
}

enum NoticeSeverity {
  info('INFO', 'Information'),
  warning('WARNING', 'Warning'),
  critical('CRITICAL', 'Critical');

  final String wire;
  final String label;
  const NoticeSeverity(this.wire, this.label);

  static NoticeSeverity parse(Object? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => NoticeSeverity.info);
}

/// A notice as the platform console lists it.
class PlatformNotice {
  final String id;
  final String title;
  final String body;
  final NoticeSeverity severity;
  final bool audienceAll;
  final List<String> schoolIds;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final bool live;
  final String createdByEmail;

  const PlatformNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.audienceAll,
    required this.schoolIds,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.live,
    required this.createdByEmail,
  });

  factory PlatformNotice.fromMap(Map<String, dynamic> m) => PlatformNotice(
    id: m['id'] as String,
    title: (m['title'] as String?) ?? '',
    body: (m['body'] as String?) ?? '',
    severity: NoticeSeverity.parse(m['severity']),
    audienceAll: m['audienceAll'] == true,
    schoolIds: [for (final s in (m['schoolIds'] as List? ?? const [])) '$s'],
    startsAt: _ms(m['startsAtMs']),
    endsAt: _ms(m['endsAtMs']),
    status: (m['status'] as String?) ?? '',
    live: m['live'] == true,
    createdByEmail: (m['createdByEmail'] as String?) ?? '',
  );
}

/// A notice a school administrator sees in the app.
class SchoolNotice {
  final String id;
  final String title;
  final String body;
  final NoticeSeverity severity;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool withdrawn;

  const SchoolNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.startsAt,
    required this.endsAt,
    required this.withdrawn,
  });

  bool isLiveAt(DateTime now) =>
      !withdrawn &&
      (startsAt == null || !now.isBefore(startsAt!)) &&
      endsAt != null &&
      now.isBefore(endsAt!);
}

/// Maintenance mode and the oldest app build still allowed
/// (`platformSettings/app`, readable even when signed out).
@immutable
class AppRequirements {
  final int minBuildAndroid;
  final int minBuildIos;
  final bool maintenanceOn;
  final String maintenanceMessage;
  final DateTime? maintenanceUntil;

  const AppRequirements({
    this.minBuildAndroid = 0,
    this.minBuildIos = 0,
    this.maintenanceOn = false,
    this.maintenanceMessage = '',
    this.maintenanceUntil,
  });

  static const none = AppRequirements();

  /// Maintenance is in force at [now] (an end time in the past means it lapsed).
  bool maintenanceActiveAt(DateTime now) =>
      maintenanceOn &&
      (maintenanceUntil == null || now.isBefore(maintenanceUntil!));

  /// This build is older than the platform allows. Web always runs the latest.
  bool buildTooOld({
    required int build,
    required bool isAndroid,
    required bool isIos,
  }) {
    if (isAndroid) return build < minBuildAndroid;
    if (isIos) return build < minBuildIos;
    return false;
  }

  /// [raw] is the document data with `until` already converted to a DateTime.
  factory AppRequirements.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return none;
    final mb = Map<String, dynamic>.from((raw['minBuild'] as Map?) ?? const {});
    final m = Map<String, dynamic>.from(
      (raw['maintenance'] as Map?) ?? const {},
    );
    final until = m['until'];
    return AppRequirements(
      minBuildAndroid: (mb['android'] as num?)?.toInt() ?? 0,
      minBuildIos: (mb['ios'] as num?)?.toInt() ?? 0,
      maintenanceOn: m['enabled'] == true,
      maintenanceMessage: (m['message'] as String?) ?? '',
      maintenanceUntil: until is DateTime ? until : null,
    );
  }
}
