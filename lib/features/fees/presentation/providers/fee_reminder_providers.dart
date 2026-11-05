import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_fee_reminder_settings_repository.dart';
import '../../domain/fee_reminder_settings.dart';

final feeReminderSettingsRepositoryProvider =
    Provider<FeeReminderSettingsRepository>(
      (ref) => FirebaseFeeReminderSettingsRepository(),
      retry: (retryCount, error) => null,
    );

/// The saved policy, or [FeeReminderSettings.defaults] for a school that never
/// saved one (that is what the scheduler runs for it too).
final feeReminderSettingsProvider = FutureProvider.autoDispose
    .family<FeeReminderSettings, String>((ref, schoolId) async {
      final saved = await ref
          .watch(feeReminderSettingsRepositoryProvider)
          .load(schoolId);
      return saved ?? FeeReminderSettings.defaults();
    }, retry: (retryCount, error) => null);
