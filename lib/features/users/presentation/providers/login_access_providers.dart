import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_login_access_repository.dart';
import '../../domain/login_access.dart';

final loginAccessRepositoryProvider = Provider<LoginAccessRepository>(
  (ref) => FirebaseLoginAccessRepository(FirebaseFunctions.instance),
  retry: (retryCount, error) => null,
);

/// The school's own sign-in switches (admins only; server-checked).
final schoolAuthSettingsProvider = FutureProvider.autoDispose
    .family<SchoolAuthSettings, String>(
      (ref, schoolId) =>
          ref.watch(loginAccessRepositoryProvider).getSchoolSettings(schoolId),
      retry: (retryCount, error) => null,
    );
