import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_public_admission_repository.dart';
import '../../domain/public_portal.dart';

final publicAdmissionRepositoryProvider = Provider<PublicAdmissionRepository>(
  (ref) => FirebasePublicAdmissionRepository(),
);

/// What the public page for [slug] shows (or the reason it cannot be shown).
final publicPortalProvider = FutureProvider.autoDispose
    .family<PublicPortalInfo, String>(
      (ref, slug) => ref.watch(publicAdmissionRepositoryProvider).load(slug),
    );
