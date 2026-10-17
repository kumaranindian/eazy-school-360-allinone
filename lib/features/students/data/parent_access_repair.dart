import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/logging/app_logger.dart';

/// Asks the server to rebuild the signed-in parent's own `parentAccess` index
/// (`refreshMyParentAccess`). The leave, results, homework and timetable
/// screens are authorised by that index, so a family whose index was never
/// built (older data, an import) would otherwise see "permission denied"
/// until an admin pressed "Refresh parent access".
///
/// The server derives the index from the link and student documents, so
/// calling it can only repair, never widen, access. Best effort: a failure is
/// logged and the screens behave as they would have without it.
class ParentAccessRepair {
  final FirebaseFunctions Function() _functions;

  ParentAccessRepair([FirebaseFunctions Function()? functions])
    : _functions = functions ?? appFunctions;

  Future<void> ensure() async {
    try {
      await _functions().httpsCallable('refreshMyParentAccess').call();
    } catch (error) {
      AppLogger.warning(
        'Could not refresh the family access index: $error',
        tag: 'ParentAccessRepair',
      );
    }
  }
}
