import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_calendar_repository.dart';
import '../../domain/calendar_repository.dart';
import '../../domain/holiday.dart';
import '../../domain/working_days.dart';
import 'academic_setup_keys.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return FirebaseCalendarRepository(ref.watch(firestoreProvider));
});

final workingDaysProvider = FutureProvider.autoDispose
    .family<WorkingDays, BranchKey>((ref, key) {
      return ref
          .watch(calendarRepositoryProvider)
          .getWorkingDays(key.schoolId, key.branchId);
    });

final holidaysProvider = StreamProvider.autoDispose
    .family<List<Holiday>, AcademicYearKey>((ref, key) {
      return ref
          .watch(calendarRepositoryProvider)
          .watchHolidays(key.schoolId, key.branchId, key.academicYearId);
    });

/// Drives the working-days toggle list and the holiday create/edit dialog.
class CalendarWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final calendarWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<CalendarWriteController, void>(
      CalendarWriteController.new,
    );
