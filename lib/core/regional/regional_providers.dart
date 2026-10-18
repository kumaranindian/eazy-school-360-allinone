import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_context_provider.dart';
import 'regional_settings.dart';
import 'school_clock.dart';

/// The signed-in school's regional setup (country, currency, time zone, date
/// format). Every screen reads it from here; a school that has not set it yet
/// behaves as [RegionalSettings.legacy].
final regionalSettingsProvider = Provider<RegionalSettings>((ref) {
  final tenant = ref.watch(tenantContextProvider).value;
  return tenant?.school?.regional ?? RegionalSettings.legacy;
});

/// "Now" / "today" in the school's time zone (see [SchoolClock]).
final schoolClockProvider = Provider<SchoolClock>(
  (ref) => SchoolClock(ref.watch(regionalSettingsProvider).timezone),
);
