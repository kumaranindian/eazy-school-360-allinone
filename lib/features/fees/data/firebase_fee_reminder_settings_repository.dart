import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/fee_reminder_settings.dart';

/// Reads `schools/{s}/feeReminderSettings/config` (school admins may read it)
/// and saves through the `updateFeeReminderSettings` callable: the rules deny
/// client writes, so the server is the only place values are validated.
class FirebaseFeeReminderSettingsRepository
    implements FeeReminderSettingsRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  FirebaseFeeReminderSettingsRepository({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  }) : _db = db ?? FirebaseFirestore.instance,
       _functions = functions ?? appFunctions();

  @override
  Future<FeeReminderSettings?> load(String schoolId) async {
    try {
      final snap = await _db
          .collection(FirestoreFields.schoolsCollection)
          .doc(schoolId)
          .collection('feeReminderSettings')
          .doc('config')
          .get();
      final data = snap.data();
      return data == null ? null : FeeReminderSettings.fromMap(data);
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<void> save(String schoolId, FeeReminderSettings settings) async {
    try {
      await _functions.httpsCallable('updateFeeReminderSettings').call({
        'schoolId': schoolId,
        'settings': settings.toCallable(),
      });
    } on FirebaseFunctionsException catch (e, st) {
      switch (e.code) {
        case 'invalid-argument':
          throw const ValidationFailure(
            'These settings were not accepted. Check the times and days and '
            'try again.',
          );
        case 'permission-denied':
          throw const PermissionFailure(
            'Only the school administrator can change fee reminders.',
          );
        default:
          throw mapExceptionToFailure(e, st);
      }
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }
}
