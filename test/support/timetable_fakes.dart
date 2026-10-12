import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/timetable/domain/period_set.dart';
import 'package:eazy_school_360/features/timetable/domain/substitution.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_enums.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_repositories.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_validation.dart';

class FakePeriodSetRepository implements PeriodSetRepository {
  List<PeriodSet> sets;
  final List<PeriodSet> saved = [];

  FakePeriodSetRepository({this.sets = const []});

  @override
  Stream<List<PeriodSet>> watchPeriodSets(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(sets);

  @override
  Future<void> savePeriodSet(
    PeriodSet set, {
    required bool isNew,
    required String actorId,
  }) async {
    final problem = set.validate();
    if (problem != null) throw ValidationFailure(problem);
    saved.add(set);
  }
}

/// An in-memory timetable store that behaves like the real one where it
/// matters: versions increase, a publish needs the current lock sequence,
/// published versions cannot be edited, and a publish replaces/ends others.
class FakeTimetableRepository implements TimetableRepository {
  final Map<String, Timetable> timetables = {};
  final Map<String, List<TimetableEntry>> entries = {};
  final List<String> events = [];
  int lockSequence = 0;
  Object? publishError;

  FakeTimetableRepository({
    List<Timetable> timetables = const [],
    Map<String, List<TimetableEntry>> entries = const {},
  }) {
    for (final t in timetables) {
      this.timetables[t.timetableId] = t;
    }
    this.entries.addAll({
      for (final e in entries.entries) e.key: List.of(e.value),
    });
  }

  final List<({Timetable timetable, int expected, int recipients})> publishes =
      [];
  final List<Timetable> created = [];
  final List<({int upserts, int removals})> saves = [];

  @override
  Stream<List<Timetable>> watchTimetables(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(timetables.values.toList());

  @override
  Stream<Timetable?> watchTimetable(
    String schoolId,
    String branchId,
    String timetableId,
  ) => Stream.value(timetables[timetableId]);

  @override
  Future<List<TimetableEntry>> fetchEntries(
    String schoolId,
    String branchId,
    String timetableId,
  ) async => List.of(entries[timetableId] ?? const []);

  List<TimetableBundle> _published() => [
    for (final t in timetables.values)
      if (t.isPublished)
        TimetableBundle(t, [
          for (final e in entries[t.timetableId] ?? const <TimetableEntry>[])
            e.copyWith(live: true),
        ]),
  ];

  @override
  Future<List<TimetableBundle>> fetchPublished(
    String schoolId,
    String branchId,
    String academicYearId,
  ) async => _published();

  @override
  Future<List<TimetableBundle>> fetchPublishedForSection({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
  }) async => [
    for (final b in _published())
      if (b.timetable.classId == classId && b.timetable.sectionId == sectionId)
        b,
  ];

  @override
  Future<List<TimetableBundle>> fetchPublishedForTeacher({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String teacherStaffId,
  }) async => [
    for (final b in _published())
      if (b.entries.any((e) => e.teacherStaffId == teacherStaffId))
        TimetableBundle(b.timetable, [
          for (final e in b.entries)
            if (e.teacherStaffId == teacherStaffId) e,
        ]),
  ];

  @override
  Future<int> publishSequence(String schoolId, String branchId) async =>
      lockSequence;

  @override
  Future<Timetable> createDraft({
    required Timetable template,
    required List<TimetableEntry> entries,
    required TimetableActor actor,
  }) async {
    final version =
        1 +
        timetables.values
            .where((t) => t.sectionKeyValue == template.sectionKeyValue)
            .fold<int>(0, (m, t) => t.version > m ? t.version : m);
    final t = Timetable(
      timetableId: Timetable.idFor(template.sectionKeyValue, version),
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
      entryCount: entries.length,
    );
    timetables[t.timetableId] = t;
    this.entries[t.timetableId] = [
      for (final e in entries) e.copyWith(timetableId: t.timetableId),
    ];
    created.add(t);
    return t;
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
    final cur = timetables[timetable.timetableId]!;
    if (!cur.isDraft) {
      throw const ValidationFailure('Only a draft can be edited.');
    }
    if (cur.revision != timetable.revision) {
      throw const ConflictFailure();
    }
    final list = entries.putIfAbsent(timetable.timetableId, () => []);
    list.removeWhere(
      (e) =>
          upserts.any((u) => u.entryId == e.entryId) ||
          removals.any((r) => r.entryId == e.entryId),
    );
    list.addAll(upserts);
    timetables[timetable.timetableId] = cur.copyWith(
      entryCount: entryCount,
      teacherIds: teacherIds,
      revision: cur.revision + 1,
    );
    saves.add((upserts: upserts.length, removals: removals.length));
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
    if (publishError != null) throw publishError!;
    publishes.add((
      timetable: timetable,
      expected: expectedSequence,
      recipients: recipients.length,
    ));
    if (expectedSequence != lockSequence) {
      throw const ConflictFailure(
        'Another timetable was published while you were checking. '
        'Validate again, then publish.',
      );
    }
    lockSequence++;
    timetables[timetable.timetableId] = timetable.copyWith(
      status: TimetableStatus.published,
      revision: timetable.revision + 1,
    );
    for (final t in supersession.archive) {
      timetables[t.timetableId] = t.copyWith(status: TimetableStatus.archived);
    }
    for (final x in supersession.truncate) {
      timetables[x.timetable.timetableId] = x.timetable.copyWith(
        effectiveToKey: x.newEndKey,
      );
    }
    events.add('published ${timetable.timetableId}');
  }

  @override
  Future<void> archive({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    required String reason,
    required TimetableActor actor,
  }) async {
    timetables[timetable.timetableId] = timetable.copyWith(
      status: TimetableStatus.archived,
    );
    if (timetable.isPublished) lockSequence++;
    events.add('archived ${timetable.timetableId}');
  }

  @override
  Stream<List<TimetableHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(const []);
}

class FakeSubstitutionRepository implements SubstitutionRepository {
  final List<Substitution> items;
  final Map<String, int> sequences = {};
  final List<Substitution> assigned = [];
  final List<({String id, String reason})> cancelled = [];
  final List<({String id, String substitute})> changed = [];
  int recipientCount = 0;
  Object? error;

  FakeSubstitutionRepository({List<Substitution> items = const []})
    : items = List.of(items);

  @override
  Future<List<Substitution>> fetchRange({
    required String schoolId,
    required String branchId,
    required String fromKey,
    required String toKey,
  }) async => [
    for (final s in items)
      if (s.dateKey.compareTo(fromKey) >= 0 && s.dateKey.compareTo(toKey) <= 0)
        s,
  ];

  @override
  Future<List<Substitution>> fetchForTeacher({
    required String schoolId,
    required String branchId,
    required String teacherStaffId,
    required String fromKey,
    required String toKey,
  }) async => [
    for (final s in items)
      if ((s.substituteTeacherId == teacherStaffId ||
              s.originalTeacherId == teacherStaffId) &&
          s.dateKey.compareTo(fromKey) >= 0 &&
          s.dateKey.compareTo(toKey) <= 0)
        s,
  ];

  @override
  Future<List<Substitution>> fetchForSection({
    required String schoolId,
    required String branchId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  }) async => [
    for (final s in items)
      if (s.classId == classId &&
          s.sectionId == sectionId &&
          s.isActive &&
          s.dateKey.compareTo(fromKey) >= 0 &&
          s.dateKey.compareTo(toKey) <= 0)
        s,
  ];

  @override
  Future<int> daySequence(
    String schoolId,
    String branchId,
    String dateKey,
  ) async => sequences[dateKey] ?? 0;

  @override
  Future<void> assign({
    required Substitution substitution,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  }) async {
    if (error != null) throw error!;
    if ((sequences[substitution.dateKey] ?? 0) != expectedSequence) {
      throw const ConflictFailure('Substitutions for this date changed.');
    }
    final existing = items
        .where((s) => s.substitutionId == substitution.substitutionId)
        .firstOrNull;
    if (existing != null && existing.isActive) {
      if (existing.substituteTeacherId == substitution.substituteTeacherId) {
        return;
      }
      throw const ValidationFailure('This period already has a substitute.');
    }
    sequences[substitution.dateKey] = expectedSequence + 1;
    assigned.add(substitution);
    items.add(substitution);
    recipientCount += recipients.length;
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
    sequences[current.dateKey] = (sequences[current.dateKey] ?? 0) + 1;
    changed.add((id: current.substitutionId, substitute: substituteTeacherId));
  }

  @override
  Future<void> cancel({
    required Substitution current,
    required String reason,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  }) async {
    sequences[current.dateKey] = (sequences[current.dateKey] ?? 0) + 1;
    cancelled.add((id: current.substitutionId, reason: reason));
  }

  @override
  Stream<List<SubstitutionHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String substitutionId,
  ) => Stream.value(const []);
}
