import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../school_setup/presentation/providers/school_providers.dart';
import '../../domain/setup_status.dart';
import 'academic_setup_keys.dart';
import 'academic_structure_providers.dart';
import 'calendar_providers.dart';

/// Composes [SetupStatus] from the school/branch/academic-structure/
/// calendar repositories — a read-only aggregation, not its own
/// repository, exactly like `TenantContext` composes `users`/
/// `school_setup` for routing. Recomputed from the real collections on
/// every read (see `SetupStatus`'s own doc comment) rather than cached, so
/// it can never silently go stale.
final setupStatusProvider = FutureProvider.autoDispose
    .family<SetupStatus, BranchKey>((ref, key) async {
      // Watch the live streams (not one-shot reads) so the checklist
      // updates the moment a profile, branch, year, class, section,
      // subject or holiday is saved — no manual refresh.
      final school = await ref
          .watch(schoolRepositoryProvider)
          .getSchool(key.schoolId);
      final branches = await ref.watch(
        branchesStreamProvider(key.schoolId).future,
      );
      final years = await ref.watch(academicYearsProvider(key).future);

      var hasAnyClass = false;
      var hasAnySection = false;
      var hasAnySubject = false;
      var hasAnyHoliday = false;

      if (years.isNotEmpty) {
        // "Current" year for this check: most recently started one — the
        // same tie-breaker `watchAcademicYears` already orders by.
        final currentYear = years.first;
        final yearKey = (
          schoolId: key.schoolId,
          branchId: key.branchId,
          academicYearId: currentYear.academicYearId,
        );

        final classes = await ref.watch(classesProvider(yearKey).future);
        hasAnyClass = classes.isNotEmpty;

        for (final schoolClass in classes) {
          final sections = await ref.watch(
            sectionsProvider((
              schoolId: key.schoolId,
              branchId: key.branchId,
              academicYearId: currentYear.academicYearId,
              classId: schoolClass.classId,
            )).future,
          );
          if (sections.isNotEmpty) {
            hasAnySection = true;
            break;
          }
        }

        final subjects = await ref.watch(subjectsProvider(yearKey).future);
        hasAnySubject = subjects.isNotEmpty;

        final holidays = await ref.watch(holidaysProvider(yearKey).future);
        hasAnyHoliday = holidays.isNotEmpty;
      }

      final workingDaysConfigured = await ref
          .watch(calendarRepositoryProvider)
          .hasWorkingDaysConfigured(key.schoolId, key.branchId);

      return SetupStatus(
        items: [
          SetupItem(
            label: 'School Profile',
            isComplete: school != null,
            isRequired: true,
          ),
          SetupItem(
            label: 'Branch',
            isComplete: branches.isNotEmpty,
            isRequired: true,
          ),
          SetupItem(
            label: 'Academic Year',
            isComplete: years.isNotEmpty,
            isRequired: true,
          ),
          SetupItem(
            label: 'Classes',
            isComplete: hasAnyClass,
            isRequired: true,
          ),
          SetupItem(
            label: 'Sections',
            isComplete: hasAnySection,
            isRequired: true,
          ),
          SetupItem(
            label: 'Subjects',
            isComplete: hasAnySubject,
            isRequired: true,
          ),
          SetupItem(
            label: 'Working Days',
            isComplete: workingDaysConfigured,
            isRequired: true,
          ),
          SetupItem(
            label: 'Holiday Calendar',
            isComplete: hasAnyHoliday,
            isRequired: false,
          ),
        ],
      );
    });
