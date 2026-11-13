import 'package:eazy_school_360/features/platform_admin/domain/platform_admin_entry.dart';
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
