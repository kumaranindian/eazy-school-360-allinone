import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/firebase_login_access_repository.dart';
import '../../data/firestore_email_lookup.dart';
import '../../domain/email_lookup.dart';
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

final emailLookupProvider = Provider<EmailLookup>(
  (ref) => FirestoreEmailLookup(FirebaseFirestore.instance),
  retry: (retryCount, error) => null,
);
