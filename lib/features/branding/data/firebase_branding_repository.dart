import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/branding/tenant_branding.dart';
import '../../../core/config/functions_region.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/branding_repository.dart';

class FirebaseBrandingRepository implements BrandingRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  FirebaseBrandingRepository({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  }) : _db = db ?? FirebaseFirestore.instance,
       _functions = functions ?? appFunctions();

  @override
  Stream<TenantBranding?> watchSchool(String schoolId) => _db
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection('branding')
      .doc('config')
      .snapshots()
      .map((s) => TenantBranding.fromMap(s.data(), expectedSchoolId: schoolId));

  @override
  Future<TenantBranding?> fetchSchool(String schoolId) async {
    try {
      final s = await _db
          .collection(FirestoreFields.schoolsCollection)
          .doc(schoolId)
          .collection('branding')
          .doc('config')
          .get(const GetOptions(source: Source.server));
      return TenantBranding.fromMap(s.data(), expectedSchoolId: schoolId);
    } catch (e) {
      AppLogger.trace('fetchSchool failed: $e', tag: 'Theme');
      return null;
    }
  }

  @override
  Stream<PlatformBranding> watchPlatform() => _db
      .collection('platformBranding')
      .doc('default')
      .snapshots()
      .map((s) => PlatformBranding.fromMap(s.data()));

  Future<int> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      final v = (r.data as Map?)?['version'];
      return v is int ? v : 0;
    } on FirebaseFunctionsException catch (e, st) {
      switch (e.code) {
        case 'invalid-argument':
          throw ValidationFailure(
            'These colours were not accepted. Check that text stays readable '
            'and try again.',
          );
        case 'permission-denied':
          throw const PermissionFailure(
            'Only the school administrator can change the school theme.',
          );
        case 'aborted':
          throw const ValidationFailure(
            'The theme was changed by someone else. Reload and try again.',
          );
        default:
          throw mapExceptionToFailure(e, st);
      }
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<int> saveSchool({
    required String schoolId,
    required String presetId,
    required BrandColors colors,
    required BrandingAppearance appearance,
    int? baseVersion,
  }) => _call('updateSchoolBranding', {
    'schoolId': schoolId,
    'branding': {
      'preset': presetId,
      'colors': colors.toMap(),
      'appearance': appearance.wire,
    },
    'baseVersion': ?baseVersion,
  });

  @override
  Future<int> resetSchool({required String schoolId, int? baseVersion}) =>
      _call('updateSchoolBranding', {
        'schoolId': schoolId,
        'reset': true,
        'baseVersion': ?baseVersion,
      });

  @override
  Future<int> savePlatform(PlatformBranding branding) =>
      _call('updatePlatformBranding', {
        'branding': {
          'defaultPreset': branding.defaultPreset,
          'presets': {
            for (final p in branding.customPresets)
              p.id: {'label': p.label, 'colors': p.colors.toMap()},
          },
        },
      });
}
