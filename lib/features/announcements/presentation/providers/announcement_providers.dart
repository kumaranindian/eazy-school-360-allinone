import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../fees/presentation/pages/parent_fees_page.dart'
    show linkedChildrenProvider;
import '../../../homework/presentation/providers/homework_providers.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../domain/announcement.dart';

typedef ViewerKey = ({
  String schoolId,
  String branchId,
  String userId,
  String role,
  String? parentId,
});

/// Who is looking, from relationships the system already holds: a parent's
/// linked children's placements, a teacher's active teaching assignments.
/// Used only to *filter what is shown*; what may be *read* is the rules' job.
final announcementViewerProvider = FutureProvider.autoDispose
    .family<AnnouncementViewer, ViewerKey>((ref, key) async {
      if (key.role == 'PARENT') {
        final parentId = key.parentId;
        if (parentId == null) {
          return AnnouncementViewer(role: key.role, branchId: key.branchId);
        }
        final children = await ref.watch(
          linkedChildrenProvider((
            schoolId: key.schoolId,
            parentId: parentId,
          )).future,
        );
        return AnnouncementViewer(
          role: key.role,
          branchId: key.branchId,
          children: [
            for (final c in children)
              if (c.currentClassId != null && c.currentSectionId != null)
                (
                  branchId: c.branchId,
                  classId: c.currentClassId!,
                  sectionId: c.currentSectionId!,
                ),
          ],
        );
      }
      if (key.role == 'TEACHER') {
        final staff = await ref.watch(
          ownStaffProvider((
            schoolId: key.schoolId,
            branchId: key.branchId,
            userId: key.userId,
          )).future,
        );
        if (staff == null) {
          return AnnouncementViewer(role: key.role, branchId: key.branchId);
        }
        final BranchKey bk = (schoolId: key.schoolId, branchId: key.branchId);
        final years = await ref.watch(academicYearsProvider(bk).future);
        final active = years.where(
          (y) => y.status == AcademicYearStatus.active,
        );
        if (active.isEmpty) {
          return AnnouncementViewer(role: key.role, branchId: key.branchId);
        }
        final facts = await ref.watch(
          yearAssignmentsProvider((
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: active.first.academicYearId,
          )).future,
        );
        final seen = <String>{};
        return AnnouncementViewer(
          role: key.role,
          branchId: key.branchId,
          teaching: [
            for (final f in facts)
              if (f.teacherStaffId == staff.staffId &&
                  seen.add('${f.classId}/${f.sectionId}'))
                (classId: f.classId, sectionId: f.sectionId),
          ],
        );
      }
      return AnnouncementViewer(role: key.role, branchId: key.branchId);
    });

typedef VisibleKey = ({
  String schoolId,
  String branchIds,
  String role,
  String userId,
  String? parentId,
  bool includeDrafts,
});

/// Announcements of one or more branches (a parent's children may attend
/// several), merged and de-duplicated. Audience and time filtering happen in
/// the caller with [AnnouncementVisibility].
final visibleAnnouncementsProvider = FutureProvider.autoDispose
    .family<List<Announcement>, VisibleKey>((ref, key) async {
      final merged = <String, Announcement>{};
      for (final branchId in key.branchIds.split(',')) {
        final list = await ref.watch(
          announcementsProvider((
            schoolId: key.schoolId,
            branchId: branchId,
            role: key.role,
            userId: key.userId,
            parentId: key.parentId,
            includeDrafts: key.includeDrafts,
          )).future,
        );
        for (final a in list) {
          merged[a.announcementId] = a;
        }
      }
      return merged.values.toList();
    });

typedef VisibleNoticesKey = ({
  String schoolId,
  String branchIds,
  String role,
  String? parentId,
});

final visibleNoticesProvider = FutureProvider.autoDispose
    .family<List<BroadcastNotice>, VisibleNoticesKey>((ref, key) async {
      final merged = <BroadcastNotice>[];
      for (final branchId in key.branchIds.split(',')) {
        merged.addAll(
          await ref.watch(
            noticesProvider((
              schoolId: key.schoolId,
              branchId: branchId,
              role: key.role,
              parentId: key.parentId,
            )).future,
          ),
        );
      }
      merged.sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
      return merged;
    });

/// Whether a notice is addressed to this viewer (same relationships as an
/// announcement of that audience).
bool noticeAddressedTo(BroadcastNotice n, AnnouncementViewer v) {
  return AnnouncementVisibility.addressedTo(
    Announcement(
      announcementId: n.noticeId,
      schoolId: '',
      branchId: n.branchId,
      audience: n.audience,
      classId: n.classId,
      sectionId: n.sectionId,
      title: n.title,
      body: n.body ?? '',
      authorId: '',
      authorName: '',
      authorRole: '',
    ),
    v,
  );
}
