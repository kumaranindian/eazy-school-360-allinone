import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/timetable/data/timetable_writes.dart';
import 'package:eazy_school_360/features/timetable/domain/period_set.dart';
import 'package:eazy_school_360/features/timetable/domain/substitution.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_enums.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exports the exact documents the Dart timetable/substitution code writes,
/// step by step through each workflow, to
/// `firestore-tests/fixtures/timetable-write-plans.json`. The emulator test
/// `timetable-contract.test.mjs` replays them under the real
/// `firestore.rules`; every step must be accepted.
const _school = '__SCHOOL__';
const _branch = 'north';
const _admin = TimetableActor(userId: 'tt-admin', name: 'Admin');

Object? _encode(Object? v) {
  if (v is FieldValue) return {r'$serverTimestamp': true};
  if (v is Timestamp) return {r'$time': v.toDate().toUtc().toIso8601String()};
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _encode(e.value)};
  }
  if (v is List) return [for (final e in v) _encode(e)];
  return v;
}

class _Batch {
  final String as;
  final String label;
  final List<Map<String, Object?>> ops = [];

  _Batch(this.as, this.label);

  void set(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'set', 'path': path, 'data': _encode(data)});
  void update(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'update', 'path': path, 'data': _encode(data)});

  Map<String, Object?> toJson() => {'as': as, 'label': label, 'ops': ops};
}

Timetable _tt(
  String section,
  int version, {
  String from = '2026-06-01',
  String? to,
  int entryCount = 0,
  List<String> teachers = const [],
}) => Timetable(
  timetableId: Timetable.idFor('y1__c5__$section', version),
  schoolId: _school,
  branchId: _branch,
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: section,
  className: 'Class 5',
  sectionName: section.toUpperCase(),
  name: 'Term 1',
  version: version,
  dayPeriodSets: const {'MONDAY': 'y1__regular', 'TUESDAY': 'y1__regular'},
  effectiveFromKey: from,
  effectiveToKey: to,
  entryCount: entryCount,
  teacherIds: teachers,
);

TimetableEntry _entry(
  Timetable t,
  String slot,
  int period,
  int start,
  int end,
  String subject,
  String teacher, {
  String? room,
  Weekday weekday = Weekday.monday,
}) => TimetableEntry(
  entryId: TimetableEntry.idFor(t.timetableId, weekday, slot),
  timetableId: t.timetableId,
  schoolId: _school,
  branchId: _branch,
  academicYearId: 'y1',
  classId: t.classId,
  sectionId: t.sectionId,
  weekday: weekday,
  slotId: slot,
  periodNumber: period,
  startMin: start,
  endMin: end,
  subjectId: subject,
  subjectName: subject,
  teacherStaffId: teacher,
  teacherName: teacher,
  room: room,
);

String _p(String c, String id) => '$c/$id';

_Batch _create(Timetable t, {required bool counterExists}) {
  final b = _Batch('tt-admin', 'create draft v${t.version}');
  b.set(
    _p('timetableCounters', t.sectionKeyValue),
    TimetableWrites.counter(
      schoolId: _school,
      branchId: _branch,
      last: t.version,
      exists: false,
      uid: 'tt-admin',
    ),
  );
  if (counterExists) {
    b.ops.removeLast();
    b.update(
      _p('timetableCounters', t.sectionKeyValue),
      TimetableWrites.counter(
        schoolId: _school,
        branchId: _branch,
        last: t.version,
        exists: true,
        uid: 'tt-admin',
      ),
    );
  }
  b.set(
    _p('timetables', t.timetableId),
    t.toFirestoreCreate(actorId: 'tt-admin'),
  );
  b.set(
    _p('timetableHistory', TimetableWrites.historyId(t.timetableId, 1)),
    TimetableWrites.history(
      timetable: t,
      revision: 1,
      toStatus: TimetableStatus.draft,
      event: TimetableEvent.created,
      actor: _admin,
    ),
  );
  return b;
}

_Batch _putEntries(List<TimetableEntry> entries) {
  final b = _Batch('tt-admin', 'save cells');
  for (final e in entries) {
    b.set(_p('timetableEntries', e.entryId), e.toFirestore());
  }
  return b;
}

_Batch _edit(Timetable t, int revision) {
  final b = _Batch('tt-admin', 'save draft metadata');
  b.update(
    _p('timetables', t.timetableId),
    TimetableWrites.draftEditUpdate(
      timetable: t,
      revision: revision,
      uid: 'tt-admin',
    ),
  );
  b.set(
    _p('timetableHistory', TimetableWrites.historyId(t.timetableId, revision)),
    TimetableWrites.history(
      timetable: t,
      revision: revision,
      toStatus: TimetableStatus.draft,
      event: TimetableEvent.edited,
      actor: _admin,
    ),
  );
  return b;
}

Substitution _sub(
  String date,
  Timetable t,
  TimetableEntry e, {
  required String substitute,
  int revision = 1,
}) => Substitution(
  substitutionId: Substitution.idFor(date, t.timetableId, e.slotId),
  schoolId: _school,
  branchId: _branch,
  academicYearId: 'y1',
  dateKey: date,
  timetableId: t.timetableId,
  timetableVersion: t.version,
  entryId: e.entryId,
  slotId: e.slotId,
  weekday: e.weekday,
  periodNumber: e.periodNumber,
  startMin: e.startMin,
  endMin: e.endMin,
  classId: t.classId,
  sectionId: t.sectionId,
  classLabel: t.title,
  subjectId: e.subjectId,
  subjectName: e.subjectName,
  originalTeacherId: e.teacherStaffId,
  originalTeacherName: e.teacherName,
  substituteTeacherId: substitute,
  substituteTeacherName: substitute,
  reasonKind: SubstitutionReasonKind.leave,
  reason: 'Approved leave',
  revision: revision,
);

void main() {
  test('exports the Dart timetable write plans for the rules contract test', () {
    final scenarios = <Map<String, Object?>>[];

    // ---- section sa: draft v1 -> cells -> edit -> publish -------------------
    final v1 = _tt('sa', 1, entryCount: 2, teachers: const ['st1', 'st2']);
    final v1Cells = [
      _entry(v1, 'p1', 1, 540, 580, 'math', 'st1', room: 'Room 5'),
      _entry(v1, 'p2', 2, 590, 630, 'eng', 'st2'),
    ];
    final publishV1 = _Batch('tt-admin', 'publish v1');
    publishV1.set(
      _p('timetableLocks', 'branch'),
      TimetableWrites.publishLock(
        schoolId: _school,
        branchId: _branch,
        sequence: 1,
        exists: false,
        uid: 'tt-admin',
      ),
    );
    publishV1.update(
      _p('timetables', v1.timetableId),
      TimetableWrites.publishUpdate(
        revision: 3,
        lockSequence: 1,
        uid: 'tt-admin',
      ),
    );
    publishV1.set(
      _p('timetableHistory', TimetableWrites.historyId(v1.timetableId, 3)),
      TimetableWrites.history(
        timetable: v1,
        revision: 3,
        toStatus: TimetableStatus.published,
        event: TimetableEvent.published,
        actor: _admin,
      ),
    );
    for (final e in v1Cells) {
      publishV1.update(
        _p('timetableEntries', e.entryId),
        TimetableWrites.entryLive(true),
      );
    }
    for (final r in const [('tt-t1', 'st1'), ('tt-t2', 'st2')]) {
      publishV1.set(
        _p(
          'notifications',
          TimetableWrites.publishedNoticeId(v1.timetableId, 3, r.$1),
        ),
        TimetableWrites.notification(
          schoolId: _school,
          branchId: _branch,
          recipientUserId: r.$1,
          type: 'TIMETABLE_PUBLISHED',
          title: 'New timetable published',
          body: v1.title,
          createdBy: 'tt-admin',
          timetableId: v1.timetableId,
          revision: 3,
        ),
      );
    }

    // ---- v2 of the same section starting later: truncates v1 ---------------
    final v2 = _tt(
      'sa',
      2,
      from: '2026-09-01',
      entryCount: 1,
      teachers: const ['st1'],
    );
    final v2Cells = [_entry(v2, 'p1', 1, 540, 580, 'math', 'st1')];
    final publishV2 = _Batch('tt-admin', 'publish v2 (truncates v1)');
    publishV2.update(
      _p('timetableLocks', 'branch'),
      TimetableWrites.publishLock(
        schoolId: _school,
        branchId: _branch,
        sequence: 2,
        exists: true,
        uid: 'tt-admin',
      ),
    );
    publishV2.update(
      _p('timetables', v2.timetableId),
      TimetableWrites.publishUpdate(
        revision: 3,
        lockSequence: 2,
        uid: 'tt-admin',
      ),
    );
    publishV2.set(
      _p('timetableHistory', TimetableWrites.historyId(v2.timetableId, 3)),
      TimetableWrites.history(
        timetable: v2,
        revision: 3,
        toStatus: TimetableStatus.published,
        event: TimetableEvent.published,
        actor: _admin,
      ),
    );
    publishV2.update(
      _p('timetableEntries', v2Cells.first.entryId),
      TimetableWrites.entryLive(true),
    );
    publishV2.update(
      _p('timetables', v1.timetableId),
      TimetableWrites.truncateUpdate(
        revision: 4,
        newEndKey: '2026-08-31',
        supersededBy: v2.timetableId,
        lockSequence: 2,
        uid: 'tt-admin',
      ),
    );
    publishV2.set(
      _p('timetableHistory', TimetableWrites.historyId(v1.timetableId, 4)),
      TimetableWrites.history(
        timetable: v1,
        revision: 4,
        toStatus: TimetableStatus.published,
        event: TimetableEvent.truncated,
        actor: _admin,
        note: 'Ends 31/08/2026',
      ),
    );

    // ---- v3 starting before v1: replaces (archives) v1 outright ------------
    final v3 = _tt(
      'sa',
      3,
      from: '2026-05-01',
      entryCount: 1,
      teachers: const ['st1'],
    );
    final v3Cells = [_entry(v3, 'p1', 1, 540, 580, 'math', 'st1')];
    final publishV3 = _Batch('tt-admin', 'publish v3 (replaces v1)');
    publishV3.update(
      _p('timetableLocks', 'branch'),
      TimetableWrites.publishLock(
        schoolId: _school,
        branchId: _branch,
        sequence: 3,
        exists: true,
        uid: 'tt-admin',
      ),
    );
    publishV3.update(
      _p('timetables', v3.timetableId),
      TimetableWrites.publishUpdate(
        revision: 3,
        lockSequence: 3,
        uid: 'tt-admin',
      ),
    );
    publishV3.set(
      _p('timetableHistory', TimetableWrites.historyId(v3.timetableId, 3)),
      TimetableWrites.history(
        timetable: v3,
        revision: 3,
        toStatus: TimetableStatus.published,
        event: TimetableEvent.published,
        actor: _admin,
      ),
    );
    publishV3.update(
      _p('timetableEntries', v3Cells.first.entryId),
      TimetableWrites.entryLive(true),
    );
    publishV3.update(
      _p('timetables', v1.timetableId),
      TimetableWrites.supersedeUpdate(
        revision: 5,
        supersededBy: v3.timetableId,
        lockSequence: 3,
        uid: 'tt-admin',
      ),
    );
    publishV3.set(
      _p('timetableHistory', TimetableWrites.historyId(v1.timetableId, 5)),
      TimetableWrites.history(
        timetable: v1,
        revision: 5,
        toStatus: TimetableStatus.archived,
        event: TimetableEvent.superseded,
        actor: _admin,
      ),
    );
    for (final e in v1Cells) {
      publishV3.update(
        _p('timetableEntries', e.entryId),
        TimetableWrites.entryLive(false),
      );
    }

    scenarios.add({
      'name': 'section sa: v1 draft, publish, v2 truncates, v3 replaces',
      'batches': [
        _create(
          v1.copyWith(entryCount: 0, teacherIds: const []),
          counterExists: false,
        ).toJson(),
        _putEntries(v1Cells).toJson(),
        _edit(v1, 2).toJson(),
        publishV1.toJson(),
        _create(
          v2.copyWith(entryCount: 0, teacherIds: const []),
          counterExists: true,
        ).toJson(),
        _putEntries(v2Cells).toJson(),
        _edit(v2, 2).toJson(),
        publishV2.toJson(),
        _create(
          v3.copyWith(entryCount: 0, teacherIds: const []),
          counterExists: true,
        ).toJson(),
        _putEntries(v3Cells).toJson(),
        _edit(v3, 2).toJson(),
        publishV3.toJson(),
      ],
    });

    // ---- substitution on v2 (live, covers 2026-09-07 a Monday) -------------
    {
      final date = '2026-09-07';
      final cell = v2Cells.first;
      final s1 = _sub(date, v2, cell, substitute: 'st3');
      final id = s1.substitutionId;
      final recipients = const ['tt-t3', 'tt-t1'];

      _Batch assign() {
        final b = _Batch('tt-admin', 'assign cover');
        b.set(
          _p('substitutionDays', date),
          TimetableWrites.dayLock(
            schoolId: _school,
            branchId: _branch,
            dateKey: date,
            sequence: 1,
            exists: false,
            uid: 'tt-admin',
          ),
        );
        b.set(
          _p('substitutions', id),
          TimetableWrites.substitutionCreate(s1, 'tt-admin'),
        );
        b.set(
          _p(
            'substitutionHistory',
            TimetableWrites.substitutionHistoryId(id, 1),
          ),
          TimetableWrites.substitutionHistory(
            s: s1,
            revision: 1,
            event: SubstitutionEvent.assigned,
            substituteTeacherName: 'st3',
            actor: _admin,
            note: 'Approved leave',
          ),
        );
        for (final r in recipients) {
          b.set(
            _p(
              'notifications',
              TimetableWrites.substitutionNoticeId(id, 1, 'ASSIGNED', r),
            ),
            TimetableWrites.notification(
              schoolId: _school,
              branchId: _branch,
              recipientUserId: r,
              type: 'SUBSTITUTION_ASSIGNED',
              title: 'You are covering a period',
              body: 'x',
              createdBy: 'tt-admin',
              substitutionId: id,
              revision: 1,
            ),
          );
        }
        return b;
      }

      _Batch step(
        String label,
        int seq,
        int rev,
        SubstitutionEvent event,
        String noticeEvent,
        String noticeType,
        Map<String, dynamic> update,
        String substitute,
      ) {
        final b = _Batch('tt-admin', label);
        b.update(
          _p('substitutionDays', date),
          TimetableWrites.dayLock(
            schoolId: _school,
            branchId: _branch,
            dateKey: date,
            sequence: seq,
            exists: true,
            uid: 'tt-admin',
          ),
        );
        b.update(_p('substitutions', id), update);
        b.set(
          _p(
            'substitutionHistory',
            TimetableWrites.substitutionHistoryId(id, rev),
          ),
          TimetableWrites.substitutionHistory(
            s: s1,
            revision: rev,
            event: event,
            substituteTeacherName: substitute,
            actor: _admin,
            note: 'note text',
          ),
        );
        b.set(
          _p(
            'notifications',
            TimetableWrites.substitutionNoticeId(id, rev, noticeEvent, 'tt-t2'),
          ),
          TimetableWrites.notification(
            schoolId: _school,
            branchId: _branch,
            recipientUserId: 'tt-t2',
            type: noticeType,
            title: 't',
            body: 'x',
            createdBy: 'tt-admin',
            substitutionId: id,
            revision: rev,
          ),
        );
        return b;
      }

      final reinstated = _sub(date, v2, cell, substitute: 'st3', revision: 4);
      scenarios.add({
        'name': 'substitution: assign, change, cancel, reinstate',
        'batches': [
          assign().toJson(),
          step(
            'change substitute',
            2,
            2,
            SubstitutionEvent.changed,
            'CHANGED',
            'SUBSTITUTION_CHANGED',
            TimetableWrites.substitutionChange(
              substituteTeacherId: 'st2',
              substituteTeacherName: 'st2',
              reason: 'Approved leave',
              revision: 2,
              uid: 'tt-admin',
            ),
            'st2',
          ).toJson(),
          step(
            'cancel',
            3,
            3,
            SubstitutionEvent.cancelled,
            'CANCELLED',
            'SUBSTITUTION_CANCELLED',
            TimetableWrites.substitutionCancel(
              reason: 'Teacher returned',
              revision: 3,
              uid: 'tt-admin',
            ),
            'st2',
          ).toJson(),
          step(
            'reinstate',
            4,
            4,
            SubstitutionEvent.reinstated,
            'REINSTATED',
            'SUBSTITUTION_ASSIGNED',
            TimetableWrites.substitutionReinstate(reinstated, 4, 'tt-admin'),
            'st3',
          ).toJson(),
        ],
      });
    }

    // ---- withdraw a published version ---------------------------------------
    {
      final b = _Batch('tt-admin', 'withdraw v2');
      b.update(
        _p('timetableLocks', 'branch'),
        TimetableWrites.publishLock(
          schoolId: _school,
          branchId: _branch,
          sequence: 4,
          exists: true,
          uid: 'tt-admin',
        ),
      );
      b.update(
        _p('timetables', v2.timetableId),
        TimetableWrites.archiveUpdate(
          revision: 4,
          lockSequence: 4,
          uid: 'tt-admin',
        ),
      );
      b.set(
        _p('timetableHistory', TimetableWrites.historyId(v2.timetableId, 4)),
        TimetableWrites.history(
          timetable: v2,
          revision: 4,
          toStatus: TimetableStatus.archived,
          event: TimetableEvent.archived,
          actor: _admin,
          note: 'Withdrawn',
        ),
      );
      b.update(
        _p('timetableEntries', v2Cells.first.entryId),
        TimetableWrites.entryLive(false),
      );
      scenarios.add({
        'name': 'withdraw a published version',
        'batches': [b.toJson()],
      });
    }

    // ---- discard a draft + period sets --------------------------------------
    {
      final sb = _tt('sb', 1);
      final discard = _Batch('tt-admin', 'discard draft');
      discard.update(
        _p('timetables', sb.timetableId),
        TimetableWrites.archiveUpdate(
          revision: 2,
          lockSequence: null,
          uid: 'tt-admin',
        ),
      );
      discard.set(
        _p('timetableHistory', TimetableWrites.historyId(sb.timetableId, 2)),
        TimetableWrites.history(
          timetable: sb,
          revision: 2,
          toStatus: TimetableStatus.archived,
          event: TimetableEvent.archived,
          actor: _admin,
          note: 'Not needed',
        ),
      );
      final set = PeriodSet(
        periodSetId: 'y1__regular',
        schoolId: _school,
        branchId: _branch,
        academicYearId: 'y1',
        name: 'Regular',
        slots: const [
          PeriodSlot(
            slotId: 'p1',
            number: 1,
            kind: SlotKind.teaching,
            label: '',
            startMin: 540,
            endMin: 580,
          ),
          PeriodSlot(
            slotId: 'brk',
            kind: SlotKind.breakSlot,
            label: 'Break',
            startMin: 580,
            endMin: 590,
          ),
          PeriodSlot(
            slotId: 'p2',
            number: 2,
            kind: SlotKind.teaching,
            label: '',
            startMin: 590,
            endMin: 630,
          ),
        ],
      );
      expect(set.validate(), isNull);
      final ps = _Batch('tt-admin', 'create then update a period set');
      ps.set(
        _p('periodSets', set.periodSetId),
        set.toFirestoreCreate(actorId: 'tt-admin'),
      );
      final ps2 = _Batch('tt-admin', 'update a period set');
      ps2.update(
        _p('periodSets', set.periodSetId),
        set.toFirestoreUpdate(actorId: 'tt-admin'),
      );
      scenarios.add({
        'name': 'draft discard, then bell schedules',
        'batches': [
          _create(sb, counterExists: false).toJson(),
          discard.toJson(),
          ps.toJson(),
          ps2.toJson(),
        ],
      });
    }

    final file = File('firestore-tests/fixtures/timetable-write-plans.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'scenarios': scenarios}),
    );

    expect(scenarios, hasLength(4));
    final first = (scenarios.first['batches'] as List).first as Map;
    final create =
        (first['ops'] as List).firstWhere(
              (o) => (o as Map)['path'].toString().startsWith('timetables/'),
            )
            as Map;
    final data = create['data'] as Map;
    expect(data['status'], 'DRAFT');
    expect(data['version'], 1);
    expect(data['revision'], 1);
    expect(data['createdAt'], {r'$serverTimestamp': true});
  });
}
