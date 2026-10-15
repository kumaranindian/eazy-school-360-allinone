import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../homework/data/homework_firestore.dart';
import '../../homework/data/homework_writes.dart';
import '../../homework/domain/homework_repositories.dart';
import '../domain/announcement.dart';
import '../domain/audience_fallback.dart';
import 'announcement_writes.dart';

/// Announcements. Same discipline as homework: each change is one batch of
/// (announcement update, append-only history, and for publication/update the
/// audience notice), the revision is read fresh, and an already-applied
/// change returns quietly so a retry cannot duplicate history or notices.
/// Archiving never deletes; a published announcement's audience is immutable.
class FirebaseAnnouncementRepository implements AnnouncementRepository {
  final FirebaseFirestore _firestore;

  FirebaseAnnouncementRepository(this._firestore);

  HomeworkCollections _c(String schoolId, String branchId) =>
      HomeworkCollections(_firestore, schoolId, branchId);

  static bool _denied(Object e) =>
      e is FirebaseException && e.code == 'permission-denied';

  Future<T> _withParentFallback<T>(
    String viewerRole,
    Future<T> Function(List<String> audiences) run,
  ) => runWithParentFallback(
    isParent: viewerRole == 'PARENT',
    run: run,
    isDenied: _denied,
  );

  Future<Announcement?> _read(HomeworkCollections c, String id) async {
    final snap = await c.announcements.doc(id).get();
    if (!snap.exists) return null;
    return Announcement.fromFirestore(snap.data()!, snap.id);
  }

  @override
  Future<void> saveDraft(
    Announcement announcement, {
    required HomeworkActor actor,
  }) async {
    final c = _c(announcement.schoolId, announcement.branchId);
    try {
      final fresh = await _read(c, announcement.announcementId);
      final batch = _firestore.batch();
      if (fresh == null) {
        batch.set(
          c.announcements.doc(announcement.announcementId),
          announcement.toFirestoreCreate(),
        );
        batch.set(
          c.announcementHistory.doc(
            AnnouncementWrites.historyId(announcement.announcementId, 1),
          ),
          AnnouncementWrites.history(
            a: announcement,
            revision: 1,
            event: AnnouncementEvent.created,
            toStatus: AnnouncementStatus.draft,
            actor: actor,
          ),
        );
      } else {
        if (fresh.status != AnnouncementStatus.draft) {
          throw const ConflictFailure(
            'Only a draft can be edited this way. Reload and try again.',
          );
        }
        final rev = fresh.revision + 1;
        batch.update(
          c.announcements.doc(fresh.announcementId),
          AnnouncementWrites.draftEdit(announcement, rev, actor.userId),
        );
        batch.set(
          c.announcementHistory.doc(
            AnnouncementWrites.historyId(fresh.announcementId, rev),
          ),
          AnnouncementWrites.history(
            a: fresh,
            revision: rev,
            event: AnnouncementEvent.edited,
            toStatus: AnnouncementStatus.draft,
            actor: actor,
          ),
        );
      }
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> publish(
    Announcement announcement, {
    required DateTime publishAt,
    required HomeworkActor actor,
  }) async {
    final c = _c(announcement.schoolId, announcement.branchId);
    try {
      final fresh = await _read(c, announcement.announcementId);
      if (fresh == null) {
        throw const NotFoundFailure('This announcement could not be found.');
      }
      if (fresh.status != AnnouncementStatus.draft) return; // already done
      final problem = announcement.validate(now: DateTime.now());
      if (problem != null) throw ValidationFailure(problem);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.announcements.doc(fresh.announcementId),
        AnnouncementWrites.publish(
          publishAt: publishAt,
          expiresAt: announcement.expiresAt,
          revision: rev,
          uid: actor.userId,
        ),
      );
      batch.set(
        c.announcementHistory.doc(
          AnnouncementWrites.historyId(fresh.announcementId, rev),
        ),
        AnnouncementWrites.history(
          a: fresh,
          revision: rev,
          event: AnnouncementEvent.published,
          toStatus: AnnouncementStatus.published,
          actor: actor,
        ),
      );
      batch.set(
        c.notices.doc(
          HomeworkWrites.noticeId(fresh.announcementId, 'PUBLISHED', rev),
        ),
        _notice(fresh, 'ANNOUNCEMENT_PUBLISHED', rev, actor.userId),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Map<String, dynamic> _notice(
    Announcement a,
    String type,
    int rev,
    String uid,
  ) => HomeworkWrites.broadcastNotice(
    schoolId: a.schoolId,
    branchId: a.branchId,
    type: type,
    audienceKind: a.audience.wireValue,
    classId: a.classId,
    sectionId: a.sectionId,
    title: type == 'ANNOUNCEMENT_PUBLISHED'
        ? 'New announcement'
        : 'Announcement updated',
    body: a.title,
    refType: 'ANNOUNCEMENT',
    refId: a.announcementId,
    revision: rev,
    createdBy: uid,
  );

  @override
  Future<void> update(
    Announcement announcement, {
    required HomeworkActor actor,
    required bool notify,
  }) async {
    final c = _c(announcement.schoolId, announcement.branchId);
    try {
      final fresh = await _read(c, announcement.announcementId);
      if (fresh == null) {
        throw const NotFoundFailure('This announcement could not be found.');
      }
      if (fresh.status != AnnouncementStatus.published) {
        throw const ConflictFailure(
          'Only a published announcement can be updated.',
        );
      }
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.announcements.doc(fresh.announcementId),
        AnnouncementWrites.updatePublished(announcement, rev, actor.userId),
      );
      batch.set(
        c.announcementHistory.doc(
          AnnouncementWrites.historyId(fresh.announcementId, rev),
        ),
        AnnouncementWrites.history(
          a: fresh,
          revision: rev,
          event: AnnouncementEvent.updated,
          toStatus: AnnouncementStatus.published,
          actor: actor,
        ),
      );
      if (notify) {
        batch.set(
          c.notices.doc(
            HomeworkWrites.noticeId(fresh.announcementId, 'UPDATED', rev),
          ),
          _notice(fresh, 'ANNOUNCEMENT_UPDATED', rev, actor.userId),
        );
      }
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> archive(
    Announcement announcement, {
    required HomeworkActor actor,
  }) async {
    final c = _c(announcement.schoolId, announcement.branchId);
    try {
      final fresh = await _read(c, announcement.announcementId);
      if (fresh == null) {
        throw const NotFoundFailure('This announcement could not be found.');
      }
      if (fresh.status == AnnouncementStatus.archived) return;
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.announcements.doc(fresh.announcementId),
        AnnouncementWrites.archive(rev, actor.userId),
      );
      batch.set(
        c.announcementHistory.doc(
          AnnouncementWrites.historyId(fresh.announcementId, rev),
        ),
        AnnouncementWrites.history(
          a: fresh,
          revision: rev,
          event: AnnouncementEvent.archived,
          toStatus: AnnouncementStatus.archived,
          actor: actor,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Announcement?> watch(String schoolId, String branchId, String id) =>
      _c(schoolId, branchId).announcements
          .doc(id)
          .snapshots()
          .map(
            (s) =>
                s.exists ? Announcement.fromFirestore(s.data()!, s.id) : null,
          );

  static bool _isAdmin(String role) =>
      role == 'SCHOOL_ADMIN' ||
      role == 'BRANCH_ADMIN' ||
      role == 'PLATFORM_ADMIN';

  /// Queries are shaped so the rules can prove them: admins read everything
  /// of the branch; others read PUBLISHED ones (parents additionally pinned
  /// to the audiences a parent may be addressed by) and, for the author's own
  /// drafts, a second query on `authorId`.
  @override
  Future<List<Announcement>> fetch({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    String? viewerUserId,
    bool includeDrafts = false,
    int limit = 100,
  }) async {
    try {
      final c = _c(schoolId, branchId);
      final list = <Announcement>[];
      if (_isAdmin(viewerRole)) {
        final snap = await c.announcements
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
        list.addAll([
          for (final d in snap.docs) Announcement.fromFirestore(d.data(), d.id),
        ]);
      } else {
        final snap = await _withParentFallback(viewerRole, (audiences) {
          Query<Map<String, dynamic>> q = c.announcements.where(
            'status',
            isEqualTo: AnnouncementStatus.published.wireValue,
          );
          if (audiences.isNotEmpty) {
            q = q.where('audienceKind', whereIn: audiences);
          }
          return q.orderBy('publishAt', descending: true).limit(limit).get();
        });
        list.addAll([
          for (final d in snap.docs) Announcement.fromFirestore(d.data(), d.id),
        ]);
        if (includeDrafts && viewerUserId != null) {
          final own = await c.announcements
              .where('authorId', isEqualTo: viewerUserId)
              .orderBy('createdAt', descending: true)
              .limit(limit)
              .get();
          final seen = {for (final a in list) a.announcementId};
          for (final d in own.docs) {
            if (seen.add(d.id)) {
              list.add(Announcement.fromFirestore(d.data(), d.id));
            }
          }
        }
      }
      return list;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<BroadcastNotice>> watchNotices({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    int limit = 30,
  }) async* {
    Stream<List<BroadcastNotice>> watch(List<String> audiences) {
      Query<Map<String, dynamic>> q = _c(schoolId, branchId).notices;
      if (audiences.isNotEmpty) {
        q = q.where('audienceKind', whereIn: audiences);
      }
      return q
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                BroadcastNotice.fromFirestore(d.data(), d.id),
            ],
          );
    }

    if (viewerRole != 'PARENT') {
      yield* watch(const []);
      return;
    }
    try {
      await for (final x in watch(parentAudiences)) {
        yield x;
      }
    } catch (e) {
      if (!_denied(e)) rethrow;
      yield* watch(schoolWideAudience);
    }
  }

  @override
  Future<List<BroadcastNotice>> fetchNotices({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    int limit = 50,
  }) async {
    try {
      final snap = await _withParentFallback(viewerRole, (audiences) {
        Query<Map<String, dynamic>> q = _c(schoolId, branchId).notices;
        if (audiences.isNotEmpty) {
          q = q.where('audienceKind', whereIn: audiences);
        }
        return q.orderBy('createdAt', descending: true).limit(limit).get();
      });
      return [
        for (final d in snap.docs)
          BroadcastNotice.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
