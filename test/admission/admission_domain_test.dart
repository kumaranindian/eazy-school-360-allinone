import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/admission/domain/admission_activity.dart';
import 'package:eazy_school_360/features/admission/domain/admission_enquiry.dart';
import 'package:eazy_school_360/features/notifications/domain/feed_item.dart';
import 'package:eazy_school_360/features/admission/domain/admission_settings.dart';
import 'package:eazy_school_360/features/admission/domain/admission_status.dart';
import 'package:eazy_school_360/features/admission/domain/enquiry_query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admission_fakes.dart';

void main() {
  group('AdmissionStatus', () {
    test('wire values round-trip and unknown values are null', () {
      for (final s in AdmissionStatus.values) {
        expect(AdmissionStatus.tryParse(s.wire), s);
      }
      expect(AdmissionStatus.tryParse('NOPE'), isNull);
      expect(AdmissionStatus.tryParse(null), isNull);
    });

    test('closed, open and reason rules', () {
      expect(AdmissionStatus.rejected.isClosed, isTrue);
      expect(AdmissionStatus.admissionConfirmed.isClosed, isTrue);
      expect(AdmissionStatus.onHold.isClosed, isFalse);
      expect(AdmissionStatus.notInterested.isOpen, isFalse);
      expect(AdmissionStatus.interested.isOpen, isTrue);
      expect(AdmissionStatus.rejected.needsReason, isTrue);
      expect(AdmissionStatus.withdrawn.needsReason, isTrue);
      expect(AdmissionStatus.notInterested.needsReason, isFalse);
    });

    // The same table is pinned in functions/admission.test.js against the
    // server's state machine: a change to one fails the other.
    test('the options offered from each status match the server table', () {
      const alt = ['NOT_INTERESTED', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'];
      const expected = <AdmissionStatus, List<String>>{
        AdmissionStatus.newEnquiry: ['CONTACTED', 'INTERESTED', ...alt],
        AdmissionStatus.contacted: ['INTERESTED', ...alt],
        AdmissionStatus.interested: alt,
        AdmissionStatus.visitScheduled: ['INTERESTED', ...alt],
        AdmissionStatus.visitCompleted: ['INTERESTED', ...alt],
        AdmissionStatus.applicationSubmitted: [
          'ON_HOLD',
          'REJECTED',
          'WITHDRAWN',
        ],
        AdmissionStatus.underReview: ['ON_HOLD', 'REJECTED', 'WITHDRAWN'],
        AdmissionStatus.approved: ['ON_HOLD', 'REJECTED', 'WITHDRAWN'],
        AdmissionStatus.onHold: [
          'RESUME',
          'NOT_INTERESTED',
          'REJECTED',
          'WITHDRAWN',
        ],
        AdmissionStatus.notInterested: ['CONTACTED', 'INTERESTED'],
        AdmissionStatus.rejected: [],
        AdmissionStatus.withdrawn: [],
        AdmissionStatus.admissionConfirmed: [],
      };
      for (final s in AdmissionStatus.values) {
        expect(s.manualOptions(), expected[s], reason: s.name);
      }
    });

    test('no option ever jumps to a status owned by another workflow', () {
      const owned = {
        'VISIT_SCHEDULED',
        'VISIT_COMPLETED',
        'APPLICATION_SUBMITTED',
        'UNDER_REVIEW',
        'APPROVED',
        'ADMISSION_CONFIRMED',
      };
      for (final s in AdmissionStatus.values) {
        expect(s.manualOptions().toSet().intersection(owned), isEmpty);
      }
    });
  });

  group('EnquirySearch.parse', () {
    test('empty is no search', () {
      expect(EnquirySearch.parse('  '), isNull);
    });

    test('an enquiry number is upper-cased', () {
      final s = EnquirySearch.parse('enq-2026-00012')!;
      expect(s.kind, EnquirySearchKind.number);
      expect(s.value, 'ENQ-2026-00012');
    });

    test('a mobile number keeps the last ten digits', () {
      final s = EnquirySearch.parse('+91 98765-43210')!;
      expect(s.kind, EnquirySearchKind.phone);
      expect(s.value, '9876543210');
      expect(EnquirySearch.parse('0987654321')!.kind, EnquirySearchKind.phone);
    });

    test('short digit runs and words are names', () {
      expect(EnquirySearch.parse('12345')!.kind, EnquirySearchKind.name);
      final n = EnquirySearch.parse('  Asha   NAIR ')!;
      expect(n.kind, EnquirySearchKind.name);
      expect(n.value, 'asha nair');
    });
  });

  group('EnquiryQueryPlan', () {
    final a = fakeEnquiry('1', classId: 'c5', source: 'Walk-in');
    final b = fakeEnquiry(
      '2',
      classId: 'c6',
      source: 'Website',
      status: AdmissionStatus.interested,
    );

    test('no filters: no server filter and everything passes', () {
      final plan = EnquiryQueryPlan.of(const EnquiryFilters());
      expect(plan.server, isNull);
      expect(plan.clientTest(a), isTrue);
    });

    test('one filter goes to the server', () {
      final plan = EnquiryQueryPlan.of(
        const EnquiryFilters(status: AdmissionStatus.interested),
      );
      expect(plan.server, ('status', 'INTERESTED'));
      expect(plan.clientTest(a), isTrue, reason: 'nothing left to test');
    });

    test('only one equality filter is sent; the rest are tested in memory', () {
      final plan = EnquiryQueryPlan.of(
        const EnquiryFilters(
          status: AdmissionStatus.interested,
          source: 'Website',
          classId: 'c6',
        ),
      );
      expect(plan.server, ('status', 'INTERESTED'));
      expect(plan.clientTest(b), isTrue);
      expect(plan.clientTest(a), isFalse);
    });

    test('dates are inclusive bounds on the enquiry date', () {
      final plan = EnquiryQueryPlan.of(
        const EnquiryFilters(fromDate: '2026-11-02', toDate: '2026-11-02'),
      );
      expect(plan.server, isNull);
      expect(plan.clientTest(a), isTrue);
      expect(
        EnquiryQueryPlan.of(
          const EnquiryFilters(fromDate: '2026-11-03'),
        ).clientTest(a),
        isFalse,
      );
      expect(
        EnquiryQueryPlan.of(
          const EnquiryFilters(toDate: '2026-11-01'),
        ).clientTest(a),
        isFalse,
      );
    });

    test('copyWith can clear a filter with null', () {
      const f = EnquiryFilters(academicYearId: 'y1', classId: 'c5');
      final cleared = f.copyWith(academicYearId: null, classId: null);
      expect(cleared.isEmpty, isTrue);
      expect(f.copyWith(source: 'Website').academicYearId, 'y1');
    });
  });

  group('models', () {
    test('settings: defaults, parsing and wire payload', () {
      expect(const AdmissionSettings().enabled, isFalse);
      final s = AdmissionSettings.fromMap({
        'enabled': true,
        'enquiryPrefix': 'ENQ',
        'sources': ['Walk-in', 7, 'Web'],
        'followUpDays': 5,
        'version': 3,
      });
      expect(s.enabled, isTrue);
      expect(s.sources, ['Walk-in', 'Web']);
      expect(s.version, 3);
      final wire = s.copyWith(followUpDays: 7).toWire();
      expect(wire['followUpDays'], 7);
      expect(wire.containsKey('version'), isFalse);
      expect(AdmissionSettings.fromMap(null).sources, isNotEmpty);
    });

    test('an enquiry is parsed, tolerating missing fields', () {
      final e = fakeEnquiry(
        '4',
        status: AdmissionStatus.onHold,
        heldFrom: 'INTERESTED',
      );
      expect(e.studentName, 'Asha Nair');
      expect(e.primaryGuardian!.phone, '9876543210');
      expect(e.heldFrom, AdmissionStatus.interested);
      final bare = AdmissionEnquiry.fromMap('x', const {});
      expect(bare.status, AdmissionStatus.newEnquiry);
      expect(bare.guardians, isEmpty);
      expect(bare.revision, 1);
    });

    test('the payload never carries identity or audit fields', () {
      const input = EnquiryInput(
        firstName: 'Asha',
        lastName: 'Nair',
        academicYearId: 'y1',
        interestedClassId: 'c5',
        source: 'Walk-in',
        guardians: [EnquiryGuardian(name: 'Meena', phone: '9876543210')],
      );
      final wire = input.toWire();
      for (final k in [
        'schoolId',
        'branchId',
        'status',
        'enquiryNumber',
        'createdBy',
        'revision',
      ]) {
        expect(wire.containsKey(k), isFalse, reason: k);
      }
      expect(wire.containsKey('enquiryDate'), isFalse);
      expect(
        const EnquiryInput(
          firstName: 'A',
          lastName: '',
          academicYearId: 'y',
          interestedClassId: 'c',
          source: 's',
          guardians: [],
          enquiryDate: '2026-01-01',
        ).toWire()['enquiryDate'],
        '2026-01-01',
      );
    });

    test('editing starts from the stored values', () {
      final e = fakeEnquiry('1', remarks: 'Call after 5');
      final input = e.toInput();
      expect(input.firstName, 'Asha');
      expect(input.remarks, 'Call after 5');
      expect(input.guardians.single.name, 'Meena Nair');
    });
  });

  group('follow-up activities', () {
    test('types and statuses round-trip; unknown values are null', () {
      for (final t in ActivityType.values) {
        expect(ActivityType.tryParse(t.wire), t);
      }
      for (final s in ActivityStatus.values) {
        expect(ActivityStatus.tryParse(s.wire), s);
      }
      expect(ActivityType.tryParse('FAX'), isNull);
      expect(ActivityStatus.tryParse(null), isNull);
    });

    test('the six types of the brief exist', () {
      expect(ActivityType.values.map((t) => t.label), [
        'Phone call',
        'WhatsApp',
        'Email',
        'School visit',
        'Meeting',
        'Other',
      ]);
    });

    test('an activity is parsed and knows when it is overdue', () {
      final a = fakeActivity('1', date: '2026-11-05');
      expect(a.isOpen, isTrue);
      expect(a.isOverdue('2026-11-07'), isTrue);
      expect(
        a.isOverdue('2026-11-05'),
        isFalse,
        reason: 'due today is not overdue',
      );
      expect(a.isOverdue('2026-11-01'), isFalse);
      final done = fakeActivity(
        '2',
        date: '2026-11-05',
        status: ActivityStatus.completed,
      );
      expect(
        done.isOverdue('2026-11-07'),
        isFalse,
        reason: 'finished work is never overdue',
      );
      final bare = AdmissionActivity.fromMap('x', const {});
      expect(bare.type, ActivityType.other);
      expect(bare.status, ActivityStatus.scheduled);
      expect(bare.rescheduleCount, 0);
    });

    test('the schedule payload sends an assignee only when chosen', () {
      const plain = ActivityInput(
        type: ActivityType.email,
        scheduledDate: '2026-11-10',
      );
      expect(plain.toWire().containsKey('assignedTo'), isFalse);
      const explicitNobody = ActivityInput(
        type: ActivityType.email,
        scheduledDate: '2026-11-10',
        assignExplicitly: true,
      );
      expect(explicitNobody.toWire()['assignedTo'], isNull);
      expect(explicitNobody.toWire().containsKey('assignedTo'), isTrue);
      expect(plain.toWire()['type'], 'EMAIL');
    });

    test('the payload carries no identity or status the server owns', () {
      final wire = const ActivityInput(
        type: ActivityType.phoneCall,
        scheduledDate: '2026-11-10',
        scheduledTime: '10:00',
      ).toWire();
      for (final k in [
        'schoolId',
        'branchId',
        'status',
        'createdBy',
        'outcome',
      ]) {
        expect(wire.containsKey(k), isFalse, reason: k);
      }
    });

    test('counts expose each bucket', () {
      const c = FollowUpCounts(
        today: 1,
        overdue: 2,
        upcoming: 3,
        mine: 4,
        unassigned: 5,
        completed: 6,
      );
      expect(
        [for (final b in FollowUpBucket.values) c.of(b)],
        [1, 2, 3, 4, 5, 6],
      );
    });

    test('an enquiry reads its follow-up counters', () {
      final e = AdmissionEnquiry.fromMap('1', {
        'activityCount': 3,
        'openActivityCount': 1,
      });
      expect([e.activityCount, e.openActivityCount], [3, 1]);
      expect(AdmissionEnquiry.fromMap('1', const {}).activityCount, 0);
    });

    test('settings carry the reminder choices, on by default at 09:00', () {
      const d = AdmissionSettings();
      expect([d.remindersEnabled, d.reminderTime], [true, '09:00']);
      final s = AdmissionSettings.fromMap({
        'remindersEnabled': false,
        'reminderTime': '18:00',
      });
      expect([s.remindersEnabled, s.reminderTime], [false, '18:00']);
      expect(s.toWire()['reminderTime'], '18:00');
      expect(AdmissionSettings.fromMap({}).remindersEnabled, isTrue);
    });
  });

  group('follow-up notifications', () {
    FeedItem n(String type, {String? ref}) => FeedItem(
      id: 'n',
      source: FeedSource.targeted,
      branchId: 'main',
      type: type,
      title: 't',
      refId: ref,
    );

    test('open the enquiry for staff who manage admissions', () {
      for (final type in [
        'ADMISSION_FOLLOWUP_DUE',
        'ADMISSION_FOLLOWUP_OVERDUE',
      ]) {
        for (final role in [UserRole.schoolAdmin, UserRole.branchAdmin]) {
          expect(
            NotificationNavigator.routeFor(n(type, ref: 'e1'), role),
            '/admissions/enquiries/e1',
          );
        }
      }
    });

    test('without a reference they open the follow-up dashboard', () {
      expect(
        NotificationNavigator.routeFor(
          n('ADMISSION_FOLLOWUP_DUE'),
          UserRole.branchAdmin,
        ),
        '/admissions/follow-ups',
      );
    });

    test('nobody else is sent there', () {
      for (final role in [
        UserRole.teacher,
        UserRole.finance,
        UserRole.parent,
      ]) {
        expect(
          NotificationNavigator.routeFor(
            n('ADMISSION_FOLLOWUP_DUE', ref: 'e1'),
            role,
          ),
          isNull,
        );
      }
    });
  });
}
