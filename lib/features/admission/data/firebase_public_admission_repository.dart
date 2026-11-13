import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/public_portal.dart';

/// Calls the two public callables. They need no sign-in; the school and
/// branch are decided by the server from the page address.
class FirebasePublicAdmissionRepository implements PublicAdmissionRepository {
  final FirebaseFunctions _functions;
  FirebasePublicAdmissionRepository({FirebaseFunctions? functions})
    : _functions = functions ?? appFunctions();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return (r.data as Map?)?.cast<String, dynamic>() ?? const {};
    } on FirebaseFunctionsException catch (e, st) {
      final cause = (e.details is Map ? (e.details as Map)['cause'] : null)
          ?.toString();
      switch (e.code) {
        case 'not-found':
          throw const NotFoundFailure(
            'This enquiry page is not available. Check the link.',
          );
        case 'resource-exhausted':
          throw const ValidationFailure(
            'Too many enquiries were sent from here. Please try again later.',
          );
        case 'invalid-argument':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'Some details were not accepted. Check the form.'
                : 'Some details were not accepted ($cause).',
          );
        case 'failed-precondition':
          throw const ValidationFailure(
            'The page has changed. Reload it and send the enquiry again.',
          );
        case 'permission-denied':
          throw const ValidationFailure(
            'The verification check failed. Reload the page and try again.',
          );
        default:
          throw mapExceptionToFailure(e, st);
      }
    } catch (e, st) {
      if (e is AppFailure) rethrow;
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<PublicPortalInfo> load(String slug) async => PublicPortalInfo.fromMap(
    await _call('getAdmissionPortal', {'slug': slug}),
  );

  @override
  Future<String> submit({
    required String slug,
    required String requestId,
    required PublicEnquiryInput input,
    required int consentVersion,
    String? captchaToken,
  }) async {
    final r = await _call('submitPublicAdmissionEnquiry', {
      'slug': slug,
      'requestId': requestId,
      'enquiry': input.toWire(),
      'consent': {'accepted': true, 'version': consentVersion},
      'captchaToken': ?captchaToken,
    });
    return r['reference'] as String? ?? '';
  }
}
