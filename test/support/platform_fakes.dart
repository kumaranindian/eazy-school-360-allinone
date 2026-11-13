import 'dart:async';

import 'package:eazy_school_360/features/platform_admin/domain/audit_entry.dart';
import 'package:eazy_school_360/features/platform_admin/domain/deletion_review.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_admin_entry.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_console_repository.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_school.dart';
import 'package:eazy_school_360/features/platform_admin/domain/school_overview.dart';
import 'package:eazy_school_360/features/platform_admin/domain/support_grant.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_admin_repository.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';

PlatformAdminEntry fakeAdmin({
  String uid = 'a1',
  String name = 'Asha Rao',
  String email = 'asha@avail404.com',
  PlatformRole? role = PlatformRole.support,
  bool roleAssigned = true,
  bool active = true,
  bool mfa = true,
  bool self = false,
}) => PlatformAdminEntry(
  uid: uid,
  name: name,
  email: email,
  role: role,
  roleAssigned: roleAssigned,
  active: active,
  mfaEnrolled: mfa,
  lastSignIn: 'Mon, 09 Nov 2026 10:00:00 GMT',
  isSelf: self,
);

class FakePlatformAdminRepository implements PlatformAdminRepository {
  List<PlatformAdminEntry> admins;
  Object? error;
  final created = <({String name, String email, PlatformRole role})>[];
  final roles = <({String uid, PlatformRole role})>[];
  final statuses = <({String uid, bool active})>[];

  FakePlatformAdminRepository([this.admins = const []]);

  @override
  Future<List<PlatformAdminEntry>> list() async {
    final e = error;
    if (e != null) throw e;
    return admins;
  }

  @override
  Future<String> create({
    required String name,
    required String email,
    required PlatformRole role,
  }) async {
    final e = error;
    if (e != null) throw e;
    created.add((name: name, email: email, role: role));
    return email.trim().toLowerCase();
  }

  @override
  Future<void> setRole({
    required String uid,
    required PlatformRole role,
  }) async {
    final e = error;
    if (e != null) throw e;
    roles.add((uid: uid, role: role));
  }

  @override
  Future<void> setActive({required String uid, required bool active}) async {
    final e = error;
    if (e != null) throw e;
    statuses.add((uid: uid, active: active));
  }
}

// ---- platform console ---------------------------------------------------------

SchoolOverview fakeOverview({
  String id = 'school-1',
  String name = 'Rosewood High',
  String status = 'ACTIVE',
  int students = 120,
  int staff = 14,
  int parents = 98,
  List<Map<String, dynamic>> grants = const [],
}) => SchoolOverview.fromMap({
  'school': {
    'id': id,
    'name': name,
    'code': 'RW',
    'status': status,
    'email': 'office@rosewood.example',
    'phone': '044 123',
    'city': 'Chennai',
    'state': 'TN',
    'country': 'IN',
    'currency': 'INR',
    'timezone': 'Asia/Kolkata',
    'createdAtMs': DateTime(2026, 1, 5).millisecondsSinceEpoch,
  },
  'branches': [
    {'id': 'main', 'name': 'Main campus', 'status': 'ACTIVE'},
  ],
  'counts': {'students': students, 'staff': staff, 'parents': parents},
  'admins': [
    {
      'uid': 'sa1',
      'name': 'Head Teacher',
      'email': 'head@rosewood.example',
      'status': 'ACTIVE',
    },
  ],
  'activeGrants': grants,
  'recentActions': [
    {
      'action': 'SUPPORT_ACCESS_GRANTED',
      'actorEmail': 'asha@avail404.com',
      'reason': 'Invoice question',
      'atMs': DateTime(2026, 11, 12).millisecondsSinceEpoch,
    },
  ],
});

PlatformSchool fakeSchool({
  String id = 'school-1',
  String name = 'Rosewood High',
  String status = 'ACTIVE',
  String city = 'Chennai',
}) => PlatformSchool(
  id: id,
  name: name,
  code: id.toUpperCase(),
  status: status,
  city: city,
  country: 'IN',
  createdAt: DateTime(2026, 1, 5),
);

DeletionReviewItem fakeDeletion({
  String reference = 'DEL-AAAAAAAAAAAAAAAA',
  String status = 'UNDER_REVIEW',
  String? reason,
}) => DeletionReviewItem.fromMap({
  'reference': reference,
  'status': status,
  'reason': reason,
  'source': 'APP',
  'role': 'PARENT',
  'schoolName': 'Rosewood High',
  'createdAt': DateTime(2026, 11, 10).millisecondsSinceEpoch,
  'updatedAt': DateTime(2026, 11, 11).millisecondsSinceEpoch,
  'history': [
    {
      'status': 'UNDER_REVIEW',
      'at': DateTime(2026, 11, 10).millisecondsSinceEpoch,
    },
  ],
});

AuditEntry fakeAudit({
  String id = 'e1',
  String action = 'SUPPORT_ACCESS_GRANTED',
  String actor = 'asha@avail404.com',
  String reason = 'Invoice question for the November run',
}) => AuditEntry(
  id: id,
  action: action,
  actorEmail: actor,
  actorRole: 'SUPPORT',
  targetEmail: '',
  schoolId: 'school-1',
  reason: reason,
  result: 'OK',
  source: 'CALLABLE',
  at: DateTime(2026, 11, 12, 10),
);

class FakePlatformConsoleRepository implements PlatformConsoleRepository {
  List<PlatformSchool> schools;
  SchoolOverview overview;
  List<AuditEntry> audit;
  List<DeletionReviewItem> openRequests;
  List<DeletionReviewItem> closedRequests;
  Object? error;
  Object? requestError;
  DateTime? grantEnds;

  final requested =
      <({String schoolId, String reason, String? ticket, int minutes})>[];
  final revoked = <({String schoolId, String? adminUid})>[];
  final reviews =
      <({String reference, DeletionDecision decision, String? reasonCode})>[];

  final myGrants = StreamController<List<SupportGrant>>.broadcast();
  final schoolGrants = StreamController<List<SupportGrant>>.broadcast();
  final accessLog = StreamController<List<SupportAccessLogEntry>>.broadcast();
  List<SupportGrant> initialGrants;
  List<SupportGrant> initialSchoolGrants;
  List<SupportAccessLogEntry> initialLog;

  FakePlatformConsoleRepository({
    List<PlatformSchool>? schools,
    SchoolOverview? overview,
    this.audit = const [],
    this.openRequests = const [],
    this.closedRequests = const [],
    this.initialGrants = const [],
    this.initialSchoolGrants = const [],
    this.initialLog = const [],
  }) : schools = schools ?? [fakeSchool()],
       overview = overview ?? fakeOverview();

  @override
  Future<List<PlatformSchool>> listSchools() async {
    final e = error;
    if (e != null) throw e;
    return schools;
  }

  @override
  Future<SchoolOverview> schoolOverview(String schoolId) async {
    final e = error;
    if (e != null) throw e;
    return overview;
  }

  @override
  Future<DateTime> requestSupportAccess({
    required String schoolId,
    required String reason,
    String? ticket,
    required int minutes,
  }) async {
    final e = requestError;
    if (e != null) throw e;
    requested.add((
      schoolId: schoolId,
      reason: reason,
      ticket: ticket,
      minutes: minutes,
    ));
    return grantEnds ?? DateTime.now().add(Duration(minutes: minutes));
  }

  @override
  Future<void> revokeSupportAccess({
    required String schoolId,
    String? adminUid,
  }) async {
    final e = requestError;
    if (e != null) throw e;
    revoked.add((schoolId: schoolId, adminUid: adminUid));
  }

  @override
  Stream<List<SupportGrant>> watchMyGrants(String uid) async* {
    yield initialGrants;
    yield* myGrants.stream;
  }

  @override
  Stream<List<SupportGrant>> watchSchoolGrants(String schoolId) async* {
    yield initialSchoolGrants;
    yield* schoolGrants.stream;
  }

  @override
  Stream<List<SupportAccessLogEntry>> watchSupportAccessLog(
    String schoolId,
  ) async* {
    yield initialLog;
    yield* accessLog.stream;
  }

  @override
  Future<List<AuditEntry>> recentAudit() async {
    final e = error;
    if (e != null) throw e;
    return audit;
  }

  @override
  Future<List<DeletionReviewItem>> deletionRequests({
    required bool closed,
  }) async {
    final e = error;
    if (e != null) throw e;
    return closed ? closedRequests : openRequests;
  }

  @override
  Future<void> reviewDeletion({
    required String reference,
    required DeletionDecision decision,
    String? reasonCode,
  }) async {
    final e = requestError;
    if (e != null) throw e;
    reviews.add((
      reference: reference,
      decision: decision,
      reasonCode: reasonCode,
    ));
  }
}

SupportGrant fakeGrant({
  String schoolId = 'school-1',
  String adminUid = 'uid-1',
  String adminName = 'Asha Rao',
  Duration left = const Duration(minutes: 30),
  bool revoked = false,
  String reason = 'Parent cannot see the November invoice',
}) => SupportGrant(
  schoolId: schoolId,
  adminUid: adminUid,
  adminName: adminName,
  adminEmail: 'asha@avail404.com',
  reason: reason,
  ticket: 'INC-1',
  expiresAt: DateTime.now().add(left),
  revoked: revoked,
);

SupportAccessLogEntry fakeLogEntry({
  String event = 'GRANTED',
  String name = 'Asha Rao',
  String reason = 'Parent cannot see the November invoice',
}) => SupportAccessLogEntry(
  event: event,
  adminName: name,
  adminEmail: 'asha@avail404.com',
  reason: reason,
  ticket: 'INC-1',
  expiresAt: DateTime(2026, 11, 12, 11),
  at: DateTime(2026, 11, 12, 10),
  revokedBy: null,
);
