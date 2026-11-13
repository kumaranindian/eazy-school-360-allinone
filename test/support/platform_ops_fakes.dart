import 'dart:async';

import 'package:eazy_school_360/features/platform_admin/domain/platform_ops_models.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_ops_repository.dart';
import 'package:eazy_school_360/features/platform_admin/domain/school_overview.dart';

import 'platform_fakes.dart';

PlatformStats fakeStats({
  DateTime? computedAt,
  int deletions = 0,
  int grants = 0,
  int offboarding = 0,
  int overdue = 0,
}) => PlatformStats.fromMap({
  'schools': {'total': 12, 'active': 9, 'suspended': 2, 'inactive': 1},
  'newSchools30d': 3,
  'students': 4200,
  'staff': 310,
  'parents': 3800,
  'branches': 15,
  'users': {
    'total': 4500,
    'active1d': 600,
    'active7d': 2100,
    'active30d': 3300,
    'partial': false,
  },
  'backlog': {
    'openDeletionRequests': deletions,
    'activeSupportGrants': grants,
    'offboardingOpen': offboarding,
    'billingOverdue': overdue,
  },
  'computedAtMs': (computedAt ?? DateTime.now()).millisecondsSinceEpoch,
});

PlatformBillingRecord fakeBill({
  String id = 'b1',
  String status = 'DUE',
  String due = '2099-01-01',
  int amount = 1500000,
  String currency = 'INR',
  String school = 'Rosewood High',
  String period = 'Nov 2026',
}) => PlatformBillingRecord(
  id: id,
  schoolId: 'school-1',
  schoolName: school,
  period: period,
  amountMinor: amount,
  currency: currency,
  dueDate: due,
  status: status,
  paidDate: status == 'PAID' ? '2026-11-01' : null,
  reference: 'INV-1',
  note: null,
);

SchoolNotice fakeSchoolNotice({
  String id = 'n1',
  String title = 'Planned maintenance',
  String body = 'Read-only on Sunday 2-4am.',
  NoticeSeverity severity = NoticeSeverity.warning,
  Duration starts = const Duration(hours: -1),
  Duration ends = const Duration(days: 2),
  bool withdrawn = false,
}) => SchoolNotice(
  id: id,
  title: title,
  body: body,
  severity: severity,
  startsAt: DateTime.now().add(starts),
  endsAt: DateTime.now().add(ends),
  withdrawn: withdrawn,
);

PlatformNotice fakePlatformNotice({
  String id = 'n1',
  String title = 'Planned maintenance',
  bool live = true,
  String status = 'ACTIVE',
  bool all = true,
}) => PlatformNotice(
  id: id,
  title: title,
  body: 'Read-only on Sunday.',
  severity: NoticeSeverity.warning,
  audienceAll: all,
  schoolIds: all ? const [] : const ['school-1'],
  startsAt: DateTime.now(),
  endsAt: DateTime.now().add(const Duration(days: 2)),
  status: status,
  live: live,
  createdByEmail: 'asha@avail404.com',
);

SchoolOverview overviewWith({
  String status = 'ACTIVE',
  String reason = '',
  Map<String, bool> features = const {},
  Map<String, dynamic>? offboarding,
}) {
  final base = fakeOverview();
  return SchoolOverview.fromMap({
    'school': {
      'id': base.id,
      'name': base.name,
      'code': base.code,
      'status': status,
      'statusReason': reason,
      'features': features,
      'currency': 'INR',
      'timezone': 'Asia/Kolkata',
    },
    'branches': [
      {'id': 'main', 'name': 'Main campus', 'status': 'ACTIVE'},
    ],
    'counts': {'students': 120, 'staff': 14, 'parents': 98},
    'admins': [
      {
        'uid': 'sa1',
        'name': 'Head Teacher',
        'email': 'head@rosewood.example',
        'status': 'ACTIVE',
      },
    ],
    'activeGrants': <Map<String, dynamic>>[],
    'recentActions': <Map<String, dynamic>>[],
    'offboarding': ?offboarding,
  });
}

class FakePlatformOpsRepository implements PlatformOpsRepository {
  Object? error;
  PlatformStats? stats;
  bool refreshFresh = true;
  BillingSummary summary;
  List<PlatformNotice> noticeList;
  bool emailsFail = false;

  final calls = <String>[];
  final statusCalls =
      <({String schoolId, SchoolStatusChoice status, String? reason})>[];
  final created = <NewSchoolInput>[];
  final admins = <({String schoolId, String name, String email})>[];
  final resets = <({String schoolId, String uid})>[];
  final featureCalls = <({String schoolId, Map<String, bool> features})>[];
  final offboardCalls = <String>[];
  final billSaved =
      <
        ({
          String schoolId,
          String period,
          int amountMinor,
          String currency,
          String dueDate,
        })
      >[];
  final billSet = <({String id, String status, String? paidDate})>[];
  final published =
      <
        ({
          String title,
          bool all,
          List<String> schools,
          NoticeSeverity severity,
        })
      >[];
  final withdrawn = <String>[];
  final requirementCalls =
      <({int android, int ios, bool on, String? message, DateTime? until})>[];

  final requirements = StreamController<AppRequirements>.broadcast();
  final schoolNotices = StreamController<List<SchoolNotice>>.broadcast();
  AppRequirements initialRequirements = AppRequirements.none;
  List<SchoolNotice> initialNotices = const [];

  FakePlatformOpsRepository({
    this.stats,
    BillingSummary? summary,
    this.noticeList = const [],
  }) : summary = summary ?? const BillingSummary(records: [], owed: {});

  void _maybeFail() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<void> setSchoolStatus({
    required String schoolId,
    required SchoolStatusChoice status,
    String? reason,
  }) async {
    _maybeFail();
    statusCalls.add((schoolId: schoolId, status: status, reason: reason));
  }

  @override
  Future<void> refreshSchoolAccess(String schoolId) async {
    _maybeFail();
    calls.add('refresh:$schoolId');
  }

  @override
  Future<({String schoolId, String adminEmail})> createSchool(
    NewSchoolInput input,
  ) async {
    _maybeFail();
    created.add(input);
    return (
      schoolId: 'school-1',
      adminEmail: input.adminEmail.trim().toLowerCase(),
    );
  }

  @override
  Future<String> addSchoolAdmin({
    required String schoolId,
    required String name,
    required String email,
  }) async {
    _maybeFail();
    admins.add((schoolId: schoolId, name: name, email: email));
    return email.trim().toLowerCase();
  }

  @override
  Future<String> resetSchoolAdminAccess({
    required String schoolId,
    required String uid,
  }) async {
    _maybeFail();
    resets.add((schoolId: schoolId, uid: uid));
    return 'head@rosewood.example';
  }

  @override
  Future<void> setFeatures({
    required String schoolId,
    required Map<String, bool> features,
  }) async {
    _maybeFail();
    featureCalls.add((schoolId: schoolId, features: features));
  }

  @override
  Future<void> requestOffboarding({
    required String schoolId,
    required String reason,
  }) async {
    _maybeFail();
    offboardCalls.add('request:$reason');
  }

  @override
  Future<void> approveOffboarding(String schoolId) async {
    _maybeFail();
    offboardCalls.add('approve');
  }

  @override
  Future<void> cancelOffboarding(String schoolId) async {
    _maybeFail();
    offboardCalls.add('cancel');
  }

  @override
  Future<BillingSummary> billing({String? schoolId}) async {
    _maybeFail();
    return summary;
  }

  @override
  Future<void> saveBillingRecord({
    required String schoolId,
    required String period,
    required int amountMinor,
    required String currency,
    required String dueDate,
    String? reference,
    String? note,
  }) async {
    _maybeFail();
    billSaved.add((
      schoolId: schoolId,
      period: period,
      amountMinor: amountMinor,
      currency: currency,
      dueDate: dueDate,
    ));
  }

  @override
  Future<void> setBillingStatus({
    required String id,
    required String status,
    String? paidDate,
    String? note,
  }) async {
    _maybeFail();
    billSet.add((id: id, status: status, paidDate: paidDate));
  }

  @override
  Stream<PlatformStats?> watchStats() => Stream.value(stats);

  @override
  Future<bool> refreshStats() async {
    _maybeFail();
    calls.add('refreshStats');
    return refreshFresh;
  }

  @override
  Future<List<PlatformNotice>> notices() async {
    _maybeFail();
    return noticeList;
  }

  @override
  Future<void> publishNotice({
    required String title,
    required String body,
    required NoticeSeverity severity,
    required bool audienceAll,
    List<String> schoolIds = const [],
    DateTime? startsAt,
    required DateTime endsAt,
  }) async {
    _maybeFail();
    published.add((
      title: title,
      all: audienceAll,
      schools: schoolIds,
      severity: severity,
    ));
  }

  @override
  Future<void> withdrawNotice(String id) async {
    _maybeFail();
    withdrawn.add(id);
  }

  @override
  Stream<List<SchoolNotice>> watchSchoolNotices(String schoolId) async* {
    yield initialNotices;
    yield* schoolNotices.stream;
  }

  @override
  Stream<AppRequirements> watchAppRequirements() async* {
    yield initialRequirements;
    yield* requirements.stream;
  }

  @override
  Future<void> setAppRequirements({
    required int minBuildAndroid,
    required int minBuildIos,
    required bool maintenanceOn,
    String? message,
    DateTime? until,
  }) async {
    _maybeFail();
    requirementCalls.add((
      android: minBuildAndroid,
      ios: minBuildIos,
      on: maintenanceOn,
      message: message,
      until: until,
    ));
  }
}
