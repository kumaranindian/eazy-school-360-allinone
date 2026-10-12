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
      final school = await ref
          .watch(schoolRepositoryProvider)
          .getSchool(key.schoolId);
      final branches = await ref
          .watch(schoolRepositoryProvider)
          .watchBranches(key.schoolId)
          .first;
      final years = await ref
          .watch(academicStructureRepositoryProvider)
          .watchAcademicYears(key.schoolId, key.branchId)
          .first;

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

        final classes = await ref
            .watch(academicStructureRepositoryProvider)
            .watchClasses(
              yearKey.schoolId,
              yearKey.branchId,
              yearKey.academicYearId,
            )
            .first;
        hasAnyClass = classes.isNotEmpty;

        for (final schoolClass in classes) {
          final sections = await ref
              .watch(academicStructureRepositoryProvider)
              .watchSections(
                key.schoolId,
                key.branchId,
                currentYear.academicYearId,
                schoolClass.classId,
              )
              .first;
          if (sections.isNotEmpty) {
            hasAnySection = true;
            break;
          }
        }

        final subjects = await ref
            .watch(academicStructureRepositoryProvider)
            .watchSubjects(
              yearKey.schoolId,
              yearKey.branchId,
              yearKey.academicYearId,
            )
            .first;
        hasAnySubject = subjects.isNotEmpty;

        final holidays = await ref
            .watch(calendarRepositoryProvider)
            .watchHolidays(
              key.schoolId,
              key.branchId,
              currentYear.academicYearId,
            )
            .first;
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
