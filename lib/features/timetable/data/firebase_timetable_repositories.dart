import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/period_set.dart';
import '../domain/substitution.dart';
import '../domain/timetable.dart';
import '../domain/timetable_enums.dart';
import '../domain/timetable_repositories.dart';
import '../domain/timetable_validation.dart';
import 'timetable_writes.dart';

class _Paths {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String branchId;

  _Paths(this.firestore, this.schoolId, this.branchId);

  DocumentReference<Map<String, dynamic>> get branch => firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> c(String name) =>
      branch.collection(name);

  CollectionReference<Map<String, dynamic>> get periodSets =>
      c(FirestoreFields.periodSetsCollection);
  CollectionReference<Map<String, dynamic>> get timetables =>
      c(FirestoreFields.timetablesCollection);
  CollectionReference<Map<String, dynamic>> get entries =>
      c(FirestoreFields.timetableEntriesCollection);
  CollectionReference<Map<String, dynamic>> get counters =>
      c(FirestoreFields.timetableCountersCollection);
  DocumentReference<Map<String, dynamic>> get lock =>
      c(FirestoreFields.timetableLocksCollection).doc('branch');
  CollectionReference<Map<String, dynamic>> get history =>
      c(FirestoreFields.timetableHistoryCollection);
  CollectionReference<Map<String, dynamic>> get substitutions =>
      c(FirestoreFields.substitutionsCollection);
  CollectionReference<Map<String, dynamic>> get days =>
      c(FirestoreFields.substitutionDaysCollection);
  CollectionReference<Map<String, dynamic>> get substitutionHistory =>
      c(FirestoreFields.substitutionHistoryCollection);
  CollectionReference<Map<String, dynamic>> get notifications =>
      c(FirestoreFields.notificationsCollection);
}

Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}

String _date(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
}

class FirebasePeriodSetRepository implements PeriodSetRepository {
  final FirebaseFirestore _firestore;

  FirebasePeriodSetRepository(this._firestore);

  @override
  Stream<List<PeriodSet>> watchPeriodSets(
    String schoolId,
    String branchId,
    String academicYearId,
  ) {
    return _Paths(_firestore, schoolId, branchId).periodSets
        .where('academicYearId', isEqualTo: academicYearId)
        .snapshots()
        .map(
          (s) =>
              [for (final d in s.docs) PeriodSet.fromFirestore(d.data(), d.id)]
                ..sort((a, b) => a.name.compareTo(b.name)),
        );
  }

  @override
  Future<void> savePeriodSet(
    PeriodSet set, {
    required bool isNew,
    required String actorId,
  }) async {
    final problem = set.validate();
    if (problem != null) throw ValidationFailure(problem);
    final ref = _Paths(
      _firestore,
      set.schoolId,
      set.branchId,
    ).periodSets.doc(set.periodSetId);
    try {
      if (isNew) {
        await _firestore.runTransaction((tx) async {
          if ((await tx.get(ref)).exists) {
            throw const ValidationFailure(
              'A schedule with this name already exists.',
            );
          }
          tx.set(ref, set.toFirestoreCreate(actorId: actorId));
        });
      } else {
        await ref.update(set.toFirestoreUpdate(actorId: actorId));
      }
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

class FirebaseTimetableRepository implements TimetableRepository {
  final FirebaseFirestore _firestore;

  FirebaseTimetableRepository(this._firestore);

  _Paths _p(String s, String b) => _Paths(_firestore, s, b);

  Object _stale(Object error, StackTrace st) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return const ConflictFailure(
        'This timetable was changed by someone else, or the change is not '
        'allowed. Reload and try again.',
      );
    }
    return mapExceptionToFailure(error, st);
  }

  @override
  Stream<List<Timetable>> watchTimetables(
    String schoolId,
    String branchId,
    String academicYearId,
  ) {
    return _p(schoolId, branchId).timetables
        .where('academicYearId', isEqualTo: academicYearId)
        .snapshots()
        .map(
          (s) =>
              [for (final d in s.docs) Timetable.fromFirestore(d.data(), d.id)]
                ..sort((a, b) {
                  final c = a.sectionKeyValue.compareTo(b.sectionKeyValue);
                  return c != 0 ? c : b.version.compareTo(a.version);
                }),
        );
  }

  @override
  Stream<Timetable?> watchTimetable(
    String schoolId,
    String branchId,
    String timetableId,
  ) => _p(schoolId, branchId).timetables
      .doc(timetableId)
      .snapshots()
      .map((s) => s.exists ? Timetable.fromFirestore(s.data()!, s.id) : null);

  @override
  Future<List<TimetableEntry>> fetchEntries(
    String schoolId,
    String branchId,
    String timetableId,
  ) async {
    try {
      final snap = await _p(
        schoolId,
        branchId,
      ).entries.where('timetableId', isEqualTo: timetableId).get();
      return [
        for (final d in snap.docs) TimetableEntry.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  List<TimetableBundle> _bundle(
    List<Timetable> timetables,
    List<TimetableEntry> entries,
  ) {
    final byTimetable = <String, List<TimetableEntry>>{};
    for (final e in entries) {
      (byTimetable[e.timetableId] ??= []).add(e);
    }
    return [
      for (final t in timetables)
        TimetableBundle(t, byTimetable[t.timetableId] ?? const []),
    ];
  }

  @override
  Future<List<TimetableBundle>> fetchPublished(
    String schoolId,
    String branchId,
    String academicYearId,
  ) async {
    try {
      final p = _p(schoolId, branchId);
      final tts = await p.timetables
          .where('academicYearId', isEqualTo: academicYearId)
          .where(FirestoreFields.status, isEqualTo: 'PUBLISHED')
          .get();
      final es = await p.entries
          .where('academicYearId', isEqualTo: academicYearId)
          .where('live', isEqualTo: true)
          .get();
      return _bundle(
        [for (final d in tts.docs) Timetable.fromFirestore(d.data(), d.id)],
        [for (final d in es.docs) TimetableEntry.fromFirestore(d.data(), d.id)],
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<TimetableBundle>> fetchPublishedForSection({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
  }) async {
    try {
      final p = _p(schoolId, branchId);
      final tts = await p.timetables
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where(FirestoreFields.status, isEqualTo: 'PUBLISHED')
          .get();
      final es = await p.entries
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where('live', isEqualTo: true)
          .get();
      return _bundle(
        [for (final d in tts.docs) Timetable.fromFirestore(d.data(), d.id)],
        [for (final d in es.docs) TimetableEntry.fromFirestore(d.data(), d.id)],
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<TimetableBundle>> fetchPublishedForTeacher({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String teacherStaffId,
  }) async {
    try {
      final p = _p(schoolId, branchId);
      final es = await p.entries
          .where('academicYearId', isEqualTo: academicYearId)
          .where('teacherStaffId', isEqualTo: teacherStaffId)
          .where('live', isEqualTo: true)
          .get();
      final entries = [
        for (final d in es.docs) TimetableEntry.fromFirestore(d.data(), d.id),
      ];
      final ids = {for (final e in entries) e.timetableId}.toList();
      final timetables = <Timetable>[];
      for (final chunk in _chunks(ids, 10)) {
        final docs = await Future.wait([
          for (final id in chunk) p.timetables.doc(id).get(),
        ]);
        for (final d in docs) {
          if (d.exists) {
            timetables.add(Timetable.fromFirestore(d.data()!, d.id));
          }
        }
      }
      return _bundle(timetables, entries);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> publishSequence(String schoolId, String branchId) async {
    try {
      final s = await _p(schoolId, branchId).lock.get();
      return s.exists ? (s.data()!['publishSeq'] as num).toInt() : 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Timetable> createDraft({
    required Timetable template,
    required List<TimetableEntry> entries,
    required TimetableActor actor,
  }) async {
    final p = _p(template.schoolId, template.branchId);
    final key = template.sectionKeyValue;
    final counterRef = p.counters.doc(key);
    try {
      final created = await _firestore.runTransaction<Timetable>((tx) async {
        final counter = await tx.get(counterRef);
        final last = counter.exists
            ? (counter.data()!['last'] as num).toInt()
            : 0;
        final version = last + 1;
        final t = Timetable(
          timetableId: Timetable.idFor(key, version),
          schoolId: template.schoolId,
          branchId: template.branchId,
          academicYearId: template.academicYearId,
          classId: template.classId,
          sectionId: template.sectionId,
          className: template.className,
          sectionName: template.sectionName,
          name: template.name,
          version: version,
          dayPeriodSets: template.dayPeriodSets,
          effectiveFromKey: template.effectiveFromKey,
          effectiveToKey: template.effectiveToKey,
          copiedFrom: template.copiedFrom,
        );
        tx.set(
          counterRef,
          TimetableWrites.counter(
            schoolId: t.schoolId,
            branchId: t.branchId,
            last: version,
            exists: counter.exists,
            uid: actor.userId,
          ),
        );
        tx.set(
          p.timetables.doc(t.timetableId),
          t.toFirestoreCreate(actorId: actor.userId),
        );
        tx.set(
          p.history.doc(TimetableWrites.historyId(t.timetableId, 1)),
          TimetableWrites.history(
            timetable: t,
            revision: 1,
            toStatus: TimetableStatus.draft,
            event: TimetableEvent.created,
            actor: actor,
            note: template.copiedFrom == null
                ? null
                : 'Copied from ${template.copiedFrom}',
          ),
        );
        return t;
      });
      if (entries.isEmpty) return created;
      final remapped = [
        for (final e in entries)
          e.copyWith(
            timetableId: created.timetableId,
            classId: created.classId,
            sectionId: created.sectionId,
            live: false,
          ),
      ];
      final teachers = {for (final e in remapped) e.teacherStaffId}.toList();
      await _writeEntries(p, upserts: remapped, removals: const []);
      final withCount = created.copyWith(
        entryCount: remapped.length,
        teacherIds: teachers,
      );
      final batch = _firestore.batch();
      batch.update(
        p.timetables.doc(created.timetableId),
        TimetableWrites.draftEditUpdate(
          timetable: withCount,
          revision: 2,
          uid: actor.userId,
        ),
      );
      batch.set(
        p.history.doc(TimetableWrites.historyId(created.timetableId, 2)),
        TimetableWrites.history(
          timetable: withCount,
          revision: 2,
          toStatus: TimetableStatus.draft,
          event: TimetableEvent.edited,
          actor: actor,
          note: 'Cells copied',
        ),
      );
      await batch.commit();
      return withCount.copyWith(revision: 2);
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  Future<void> _writeEntries(
    _Paths p, {
    required List<TimetableEntry> upserts,
    required List<TimetableEntry> removals,
  }) async {
    // Ten cells per commit keeps each commit inside the rules' per-request
    // document-access limit (every cell checks its teacher's assignment slot).
    final ops = <(TimetableEntry, bool)>[
      for (final e in upserts) (e, true),
      for (final e in removals) (e, false),
    ];
    for (final chunk in _chunks(ops, 10)) {
      final batch = _firestore.batch();
      for (final (e, upsert) in chunk) {
        final ref = p.entries.doc(e.entryId);
        if (upsert) {
          batch.set(ref, e.copyWith(live: false).toFirestore());
        } else {
          batch.delete(ref);
        }
      }
      await batch.commit();
    }
  }

  @override
  Future<void> saveDraft({
    required Timetable timetable,
    required List<TimetableEntry> upserts,
    required List<TimetableEntry> removals,
    required List<String> teacherIds,
    required int entryCount,
    required TimetableActor actor,
  }) async {
    final p = _p(timetable.schoolId, timetable.branchId);
    final ref = p.timetables.doc(timetable.timetableId);
    try {
      final current = await ref.get();
      if (!current.exists) {
        throw const NotFoundFailure('This timetable could not be found.');
      }
      final fresh = Timetable.fromFirestore(current.data()!, current.id);
      if (!fresh.isDraft) {
        throw const ValidationFailure(
          'Only a draft can be edited. Create a new version to change a '
          'published timetable.',
        );
      }
      if (fresh.revision != timetable.revision) {
        throw const ConflictFailure(
          'This draft was changed by someone else. Reload to see the latest.',
        );
      }
      await _writeEntries(p, upserts: upserts, removals: removals);
      final rev = fresh.revision + 1;
      final updated = timetable.copyWith(
        entryCount: entryCount,
        teacherIds: teacherIds,
      );
      final batch = _firestore.batch();
      batch.update(
        ref,
        TimetableWrites.draftEditUpdate(
          timetable: updated,
          revision: rev,
          uid: actor.userId,
        ),
      );
      batch.set(
        p.history.doc(TimetableWrites.historyId(timetable.timetableId, rev)),
        TimetableWrites.history(
          timetable: updated,
          revision: rev,
          toStatus: TimetableStatus.draft,
          event: TimetableEvent.edited,
          actor: actor,
        ),
      );
      await batch.commit();
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  @override
  Future<void> publish({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    required SupersessionPlan supersession,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  }) async {
    final p = _p(timetable.schoolId, timetable.branchId);
    final ref = p.timetables.doc(timetable.timetableId);
    try {
      // Cells of the versions being replaced: they stop being live with them.
      final replacedEntries = <String, List<TimetableEntry>>{};
      for (final t in supersession.archive) {
        replacedEntries[t.timetableId] = await fetchEntries(
          t.schoolId,
          t.branchId,
          t.timetableId,
        );
      }
      await _firestore.runTransaction((tx) async {
        final lock = await tx.get(p.lock);
        final seq = lock.exists
            ? (lock.data()!['publishSeq'] as num).toInt()
            : 0;
        if (seq != expectedSequence) {
          throw const ConflictFailure(
            'Another timetable was published while you were checking. '
            'Validate again, then publish.',
          );
        }
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw const NotFoundFailure('This timetable could not be found.');
        }
        final fresh = Timetable.fromFirestore(snap.data()!, snap.id);
        if (!fresh.isDraft || fresh.revision != timetable.revision) {
          throw const ConflictFailure(
            'This draft changed or was already published. Reload to continue.',
          );
        }
        final replaced = <String, Timetable>{};
        for (final t in [
          ...supersession.archive,
          for (final x in supersession.truncate) x.timetable,
        ]) {
          final s = await tx.get(p.timetables.doc(t.timetableId));
          if (!s.exists) continue;
          final f = Timetable.fromFirestore(s.data()!, s.id);
          if (!f.isPublished || f.revision != t.revision) {
            throw const ConflictFailure(
              'A published version changed while you were checking. '
              'Validate again, then publish.',
            );
          }
          replaced[f.timetableId] = f;
        }

        final newSeq = seq + 1;
        tx.set(
          p.lock,
          TimetableWrites.publishLock(
            schoolId: timetable.schoolId,
            branchId: timetable.branchId,
            sequence: newSeq,
            exists: lock.exists,
            uid: actor.userId,
          ),
        );
        final rev = fresh.revision + 1;
        tx.update(
          ref,
          TimetableWrites.publishUpdate(
            revision: rev,
            lockSequence: newSeq,
            uid: actor.userId,
          ),
        );
        tx.set(
          p.history.doc(TimetableWrites.historyId(timetable.timetableId, rev)),
          TimetableWrites.history(
            timetable: fresh,
            revision: rev,
            toStatus: TimetableStatus.published,
            event: TimetableEvent.published,
            actor: actor,
          ),
        );
        for (final e in entries) {
          tx.update(p.entries.doc(e.entryId), TimetableWrites.entryLive(true));
        }
        for (final t in supersession.archive) {
          final f = replaced[t.timetableId];
          if (f == null) continue;
          final r = f.revision + 1;
          tx.update(
            p.timetables.doc(f.timetableId),
            TimetableWrites.supersedeUpdate(
              revision: r,
              supersededBy: timetable.timetableId,
              lockSequence: newSeq,
              uid: actor.userId,
            ),
          );
          tx.set(
            p.history.doc(TimetableWrites.historyId(f.timetableId, r)),
            TimetableWrites.history(
              timetable: f,
              revision: r,
              toStatus: TimetableStatus.archived,
              event: TimetableEvent.superseded,
              actor: actor,
              note: 'Replaced by v${fresh.version}',
            ),
          );
          for (final e in replacedEntries[t.timetableId] ?? const []) {
            if (e.live) {
              tx.update(
                p.entries.doc(e.entryId),
                TimetableWrites.entryLive(false),
              );
            }
          }
        }
        for (final x in supersession.truncate) {
          final f = replaced[x.timetable.timetableId];
          if (f == null) continue;
          final r = f.revision + 1;
          tx.update(
            p.timetables.doc(f.timetableId),
            TimetableWrites.truncateUpdate(
              revision: r,
              newEndKey: x.newEndKey,
              supersededBy: timetable.timetableId,
              lockSequence: newSeq,
              uid: actor.userId,
            ),
          );
          tx.set(
            p.history.doc(TimetableWrites.historyId(f.timetableId, r)),
            TimetableWrites.history(
              timetable: f,
              revision: r,
              toStatus: TimetableStatus.published,
              event: TimetableEvent.truncated,
              actor: actor,
              note: 'Ends ${_date(x.newEndKey)}; v${fresh.version} takes over',
            ),
          );
        }
        // Notices: written with the publish, so one exists exactly when it
        // happened and a retried publish (which fails above) writes none.
        for (final r in recipients) {
          tx.set(
            p.notifications.doc(
              TimetableWrites.publishedNoticeId(
                timetable.timetableId,
                rev,
                r.userId,
              ),
            ),
            TimetableWrites.notification(
              schoolId: timetable.schoolId,
              branchId: timetable.branchId,
              recipientUserId: r.userId,
              type: 'TIMETABLE_PUBLISHED',
              title: 'New timetable published',
              body:
                  '${fresh.title} · v${fresh.version} · from '
                  '${_date(fresh.effectiveFromKey)}',
              createdBy: actor.userId,
              timetableId: timetable.timetableId,
              revision: rev,
            ),
          );
        }
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  @override
  Future<void> archive({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    required String reason,
    required TimetableActor actor,
  }) async {
    final p = _p(timetable.schoolId, timetable.branchId);
    final ref = p.timetables.doc(timetable.timetableId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw const NotFoundFailure('This timetable could not be found.');
        }
        final fresh = Timetable.fromFirestore(snap.data()!, snap.id);
        if (fresh.status == TimetableStatus.archived) return;
        if (fresh.revision != timetable.revision) {
          throw const ConflictFailure(
            'This timetable changed. Reload to continue.',
          );
        }
        final rev = fresh.revision + 1;
        int? lockSeq;
        if (fresh.isPublished) {
          final lock = await tx.get(p.lock);
          final seq = lock.exists
              ? (lock.data()!['publishSeq'] as num).toInt()
              : 0;
          lockSeq = seq + 1;
          tx.set(
            p.lock,
            TimetableWrites.publishLock(
              schoolId: timetable.schoolId,
              branchId: timetable.branchId,
              sequence: lockSeq,
              exists: lock.exists,
              uid: actor.userId,
            ),
          );
          for (final e in entries) {
            tx.update(
              p.entries.doc(e.entryId),
              TimetableWrites.entryLive(false),
            );
          }
        }
        tx.update(
          ref,
          TimetableWrites.archiveUpdate(
            revision: rev,
            lockSequence: lockSeq,
            uid: actor.userId,
          ),
        );
        tx.set(
          p.history.doc(TimetableWrites.historyId(timetable.timetableId, rev)),
          TimetableWrites.history(
            timetable: fresh,
            revision: rev,
            toStatus: TimetableStatus.archived,
            event: TimetableEvent.archived,
            actor: actor,
            note: reason,
          ),
        );
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  @override
  Stream<List<TimetableHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => _p(schoolId, branchId).history
      .where('academicYearId', isEqualTo: academicYearId)
      .orderBy('at', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs) TimetableHistoryEntry.fromFirestore(d.data()),
        ],
      );
}

class FirebaseSubstitutionRepository implements SubstitutionRepository {
  final FirebaseFirestore _firestore;

  FirebaseSubstitutionRepository(this._firestore);

  _Paths _p(String s, String b) => _Paths(_firestore, s, b);

  List<Substitution> _map(QuerySnapshot<Map<String, dynamic>> s) => [
    for (final d in s.docs) Substitution.fromFirestore(d.data(), d.id),
  ];

  @override
  Future<List<Substitution>> fetchRange({
    required String schoolId,
    required String branchId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final s = await _p(schoolId, branchId).substitutions
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .limit(500)
          .get();
      return _map(s);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Substitution>> fetchForTeacher({
    required String schoolId,
    required String branchId,
    required String teacherStaffId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final p = _p(schoolId, branchId);
      final asSub = await p.substitutions
          .where('substituteTeacherId', isEqualTo: teacherStaffId)
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .get();
      final asOriginal = await p.substitutions
          .where('originalTeacherId', isEqualTo: teacherStaffId)
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .get();
      final all = {
        for (final s in [..._map(asSub), ..._map(asOriginal)])
          s.substitutionId: s,
      };
      return all.values.toList()
        ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Substitution>> fetchForSection({
    required String schoolId,
    required String branchId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final s = await _p(schoolId, branchId).substitutions
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where(FirestoreFields.status, isEqualTo: 'ACTIVE')
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .get();
      return _map(s);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> daySequence(
    String schoolId,
    String branchId,
    String dateKey,
  ) async {
    try {
      final s = await _p(schoolId, branchId).days.doc(dateKey).get();
      return s.exists ? (s.data()!['seq'] as num).toInt() : 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Object _stale(Object error, StackTrace st) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return const ConflictFailure(
        'This substitution was changed by someone else, or the change is not '
        'allowed. Reload and try again.',
      );
    }
    return mapExceptionToFailure(error, st);
  }

  void _dayLock(
    Transaction tx,
    _Paths p,
    DocumentSnapshot<Map<String, dynamic>> day,
    Substitution s,
    String uid,
  ) {
    final seq = day.exists ? (day.data()!['seq'] as num).toInt() : 0;
    tx.set(
      p.days.doc(s.dateKey),
      TimetableWrites.dayLock(
        schoolId: s.schoolId,
        branchId: s.branchId,
        dateKey: s.dateKey,
        sequence: seq + 1,
        exists: day.exists,
        uid: uid,
      ),
    );
  }

  void _notify(
    Transaction tx,
    _Paths p,
    Substitution s,
    int revision,
    String event,
    String type,
    String title,
    List<Recipient> recipients,
    TimetableActor actor,
  ) {
    for (final r in recipients) {
      tx.set(
        p.notifications.doc(
          TimetableWrites.substitutionNoticeId(
            s.substitutionId,
            revision,
            event,
            r.userId,
          ),
        ),
        TimetableWrites.notification(
          schoolId: s.schoolId,
          branchId: s.branchId,
          recipientUserId: r.userId,
          type: type,
          title: title,
          body:
              '${s.classLabel ?? s.classId} · ${s.subjectName} · period '
              '${s.periodNumber} (${s.timeLabel}) · ${_date(s.dateKey)}',
          createdBy: actor.userId,
          substitutionId: s.substitutionId,
          revision: revision,
        ),
      );
    }
  }

  @override
  Future<void> assign({
    required Substitution substitution,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  }) async {
    final s = substitution;
    final p = _p(s.schoolId, s.branchId);
    final ref = p.substitutions.doc(s.substitutionId);
    try {
      await _firestore.runTransaction((tx) async {
        final day = await tx.get(p.days.doc(s.dateKey));
        final seq = day.exists ? (day.data()!['seq'] as num).toInt() : 0;
        if (seq != expectedSequence) {
          throw const ConflictFailure(
            'Substitutions for this date changed while you were checking. '
            'Review the date again, then confirm.',
          );
        }
        final existing = await tx.get(ref);
        if (existing.exists) {
          final cur = Substitution.fromFirestore(existing.data()!, existing.id);
          if (cur.isActive) {
            // The same cover again (a retry) is fine; a different one is not.
            if (cur.substituteTeacherId == s.substituteTeacherId) return;
            throw const ValidationFailure(
              'This period already has a substitute for that date. '
              'Change or cancel it instead.',
            );
          }
          final rev = cur.revision + 1;
          final reinstated = Substitution.fromFirestore({
            ...existing.data()!,
            'revision': rev,
          }, existing.id);
          _dayLock(tx, p, day, s, actor.userId);
          tx.update(
            ref,
            TimetableWrites.substitutionReinstate(s, rev, actor.userId),
          );
          tx.set(
            p.substitutionHistory.doc(
              TimetableWrites.substitutionHistoryId(s.substitutionId, rev),
            ),
            TimetableWrites.substitutionHistory(
              s: s,
              revision: rev,
              event: SubstitutionEvent.reinstated,
              substituteTeacherName: s.substituteTeacherName,
              actor: actor,
              note: s.reason,
            ),
          );
          _notify(
            tx,
            p,
            reinstated,
            rev,
            'REINSTATED',
            'SUBSTITUTION_ASSIGNED',
            'You are covering a period',
            recipients,
            actor,
          );
          return;
        }
        _dayLock(tx, p, day, s, actor.userId);
        tx.set(ref, TimetableWrites.substitutionCreate(s, actor.userId));
        tx.set(
          p.substitutionHistory.doc(
            TimetableWrites.substitutionHistoryId(s.substitutionId, 1),
          ),
          TimetableWrites.substitutionHistory(
            s: s,
            revision: 1,
            event: SubstitutionEvent.assigned,
            substituteTeacherName: s.substituteTeacherName,
            actor: actor,
            note: s.reason,
          ),
        );
        _notify(
          tx,
          p,
          s,
          1,
          'ASSIGNED',
          'SUBSTITUTION_ASSIGNED',
          'You are covering a period',
          recipients,
          actor,
        );
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  @override
  Future<void> change({
    required Substitution current,
    required String substituteTeacherId,
    required String substituteTeacherName,
    required String reason,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  }) async {
    final c = current;
    final p = _p(c.schoolId, c.branchId);
    final ref = p.substitutions.doc(c.substitutionId);
    try {
      await _firestore.runTransaction((tx) async {
        final day = await tx.get(p.days.doc(c.dateKey));
        final seq = day.exists ? (day.data()!['seq'] as num).toInt() : 0;
        if (seq != expectedSequence) {
          throw const ConflictFailure(
            'Substitutions for this date changed while you were checking. '
            'Review the date again, then confirm.',
          );
        }
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw const NotFoundFailure('This substitution could not be found.');
        }
        final fresh = Substitution.fromFirestore(snap.data()!, snap.id);
        if (!fresh.isActive || fresh.revision != c.revision) {
          throw const ConflictFailure(
            'This substitution changed. Reload to continue.',
          );
        }
        final rev = fresh.revision + 1;
        _dayLock(tx, p, day, fresh, actor.userId);
        tx.update(
          ref,
          TimetableWrites.substitutionChange(
            substituteTeacherId: substituteTeacherId,
            substituteTeacherName: substituteTeacherName,
            reason: reason,
            revision: rev,
            uid: actor.userId,
          ),
        );
        final after = Substitution.fromFirestore({
          ...snap.data()!,
          'substituteTeacherId': substituteTeacherId,
          'substituteTeacherName': substituteTeacherName,
          'revision': rev,
        }, snap.id);
        tx.set(
          p.substitutionHistory.doc(
            TimetableWrites.substitutionHistoryId(fresh.substitutionId, rev),
          ),
          TimetableWrites.substitutionHistory(
            s: after,
            revision: rev,
            event: SubstitutionEvent.changed,
            substituteTeacherName: substituteTeacherName,
            actor: actor,
            note: reason,
          ),
        );
        _notify(
          tx,
          p,
          after,
          rev,
          'CHANGED',
          'SUBSTITUTION_CHANGED',
          'A cover arrangement changed',
          recipients,
          actor,
        );
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  @override
  Future<void> cancel({
    required Substitution current,
    required String reason,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  }) async {
    final c = current;
    final p = _p(c.schoolId, c.branchId);
    final ref = p.substitutions.doc(c.substitutionId);
    try {
      await _firestore.runTransaction((tx) async {
        final day = await tx.get(p.days.doc(c.dateKey));
        final seq = day.exists ? (day.data()!['seq'] as num).toInt() : 0;
        if (seq != expectedSequence) {
          throw const ConflictFailure(
            'Substitutions for this date changed while you were checking. '
            'Review the date again, then confirm.',
          );
        }
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw const NotFoundFailure('This substitution could not be found.');
        }
        final fresh = Substitution.fromFirestore(snap.data()!, snap.id);
        if (!fresh.isActive) return; // already cancelled: idempotent
        if (fresh.revision != c.revision) {
          throw const ConflictFailure(
            'This substitution changed. Reload to continue.',
          );
        }
        final rev = fresh.revision + 1;
        _dayLock(tx, p, day, fresh, actor.userId);
        tx.update(
          ref,
          TimetableWrites.substitutionCancel(
            reason: reason,
            revision: rev,
            uid: actor.userId,
          ),
        );
        tx.set(
          p.substitutionHistory.doc(
            TimetableWrites.substitutionHistoryId(fresh.substitutionId, rev),
          ),
          TimetableWrites.substitutionHistory(
            s: fresh,
            revision: rev,
            event: SubstitutionEvent.cancelled,
            substituteTeacherName: fresh.substituteTeacherName,
            actor: actor,
            note: reason,
          ),
        );
        _notify(
          tx,
          p,
          fresh,
          rev,
          'CANCELLED',
          'SUBSTITUTION_CANCELLED',
          'A cover arrangement was cancelled',
          recipients,
          actor,
        );
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _stale(error, stackTrace);
    }
  }

  @override
  Stream<List<SubstitutionHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String substitutionId,
  ) => _p(schoolId, branchId).substitutionHistory
      .where('substitutionId', isEqualTo: substitutionId)
      .orderBy('revision')
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            SubstitutionHistoryEntry.fromFirestore(d.data()),
        ],
      );
}
