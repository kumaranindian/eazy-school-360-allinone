import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/admission/domain/admission_activity.dart';
import 'package:eazy_school_360/features/admission/domain/admission_application.dart';
import 'package:eazy_school_360/features/admission/domain/admission_enquiry.dart';
import 'package:eazy_school_360/features/admission/domain/admission_fee.dart';
import 'package:eazy_school_360/features/notifications/domain/feed_item.dart';
import 'package:eazy_school_360/features/admission/domain/admission_settings.dart';
import 'package:eazy_school_360/features/admission/domain/admission_status.dart';
import 'package:eazy_school_360/features/admission/domain/admission_timeline.dart';
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
        visits: 4,
        mine: 5,
        unassigned: 6,
        completed: 7,
      );
      expect(
        [for (final b in FollowUpBucket.values) c.of(b)],
        [1, 2, 3, 4, 5, 6, 7],
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

  group('school visits', () {
    test('purposes round-trip; unknown is null', () {
      for (final p in VisitPurpose.values) {
        expect(VisitPurpose.tryParse(p.wire), p);
      }
      expect(VisitPurpose.tryParse('PARTY'), isNull);
      expect(VisitPurpose.values.map((p) => p.label), [
        'Campus tour',
        'Meet the principal',
        'Assessment',
        'Counselling',
        'Other',
      ]);
    });

    test('a visit is an activity of type school visit with a purpose', () {
      final v = fakeActivity(
        '1',
        type: ActivityType.schoolVisit,
        purpose: VisitPurpose.assessment,
      );
      expect(v.isVisit, isTrue);
      expect(v.purpose, VisitPurpose.assessment);
      expect(fakeActivity('2').isVisit, isFalse);
      expect(fakeActivity('2').purpose, isNull);
    });

    test(
      'the visit payload carries the purpose; a plain follow-up does not',
      () {
        const visit = ActivityInput(
          type: ActivityType.schoolVisit,
          purpose: VisitPurpose.campusTour,
          scheduledDate: '2026-11-10',
          scheduledTime: '10:00',
        );
        expect(visit.toWire()['purpose'], 'CAMPUS_TOUR');
        expect(visit.toWire()['type'], 'SCHOOL_VISIT');
        const plain = ActivityInput(
          type: ActivityType.email,
          scheduledDate: '2026-11-10',
        );
        expect(plain.toWire().containsKey('purpose'), isFalse);
      },
    );

    test('a history entry reads what changed', () {
      final e = ActivityHistoryEntry.fromMap({
        'activityId': 'a1',
        'revision': 2,
        'event': 'RESCHEDULED',
        'type': 'SCHOOL_VISIT',
        'purpose': 'MEET_PRINCIPAL',
        'from': {'scheduledDate': '2026-11-10'},
        'to': {'scheduledDate': '2026-11-18', 'scheduledTime': '09:00'},
        'reason': 'Travelling',
        'actorId': 'u1',
      });
      expect(e.event, ActivityEvent.rescheduled);
      expect(e.isVisit, isTrue);
      expect(
        [e.fromDate, e.toDate, e.toTime, e.reason],
        ['2026-11-10', '2026-11-18', '09:00', 'Travelling'],
      );
      final bare = ActivityHistoryEntry.fromMap(const {});
      expect(bare.event, ActivityEvent.created);
      expect(bare.type, ActivityType.other);
    });

    test('the timeline merges status and activity history, newest first', () {
      DateTime t(int m) => DateTime(2026, 11, 7, 10, m);
      final status = [
        StatusHistoryEntry(
          revision: 1,
          to: AdmissionStatus.newEnquiry,
          actorId: 'a',
          at: t(0),
        ),
        StatusHistoryEntry(
          revision: 2,
          from: AdmissionStatus.newEnquiry,
          to: AdmissionStatus.visitScheduled,
          actorId: 'a',
          at: t(5),
        ),
      ];
      final activity = [
        ActivityHistoryEntry(
          activityId: 'v',
          revision: 1,
          event: ActivityEvent.created,
          type: ActivityType.schoolVisit,
          actorId: 'a',
          at: t(5),
        ),
        ActivityHistoryEntry(
          activityId: 'c',
          revision: 1,
          event: ActivityEvent.created,
          type: ActivityType.phoneCall,
          actorId: 'a',
          at: t(2),
        ),
        ActivityHistoryEntry(
          activityId: 'v',
          revision: 2,
          event: ActivityEvent.completed,
          type: ActivityType.schoolVisit,
          actorId: 'a',
          at: t(9),
        ),
      ];
      final items = mergeTimeline(status, activity);
      String label(TimelineItem i) => switch (i) {
        StatusTimelineItem(:final entry) => 'S${entry.revision}',
        ActivityTimelineItem(:final entry) =>
          '${entry.activityId}${entry.revision}',
        ApplicationTimelineItem(:final entry) => 'A${entry.revision}',
      };
      expect(
        items.map(label),
        ['v2', 'S2', 'v1', 'c1', 'S1'],
        reason:
            'same minute: the status change reads above the booking that caused it',
      );
    });

    test('an entry whose server time has not arrived yet is the newest', () {
      final items = mergeTimeline(
        [
          StatusHistoryEntry(
            revision: 1,
            to: AdmissionStatus.newEnquiry,
            actorId: 'a',
            at: DateTime(2026, 11, 7),
          ),
        ],
        const [
          ActivityHistoryEntry(
            activityId: 'x',
            revision: 1,
            event: ActivityEvent.created,
            type: ActivityType.email,
            actorId: 'a',
          ),
        ],
      );
      expect(items.first, isA<ActivityTimelineItem>());
      expect(mergeTimeline(const [], const []), isEmpty);
    });
  });

  group('applications and documents', () {
    test('statuses round-trip; open and final are as the server sees them', () {
      for (final st in ApplicationStatus.values) {
        expect(ApplicationStatus.tryParse(st.wire), st);
      }
      for (final st in DocumentStatus.values) {
        expect(DocumentStatus.tryParse(st.wire), st);
      }
      expect(ApplicationStatus.tryParse('NOPE'), isNull);
      expect(ApplicationStatus.values.where((s) => s.isOpen), [
        ApplicationStatus.draft,
        ApplicationStatus.submitted,
        ApplicationStatus.underReview,
      ]);
      expect(ApplicationStatus.approved.isOpen, isFalse);
      expect(ApplicationStatus.rejected.isFinal, isTrue);
      expect(ApplicationStatus.approved.isFinal, isFalse);
      expect(DocumentStatus.values.where((s) => s.isListed), [
        DocumentStatus.uploaded,
        DocumentStatus.verified,
        DocumentStatus.rejected,
      ]);
    });

    test(
      'an application can be started from the same enquiry statuses as on the server',
      () {
        final can = AdmissionStatus.values
            .where((s) => s.canStartApplication)
            .toList();
        expect(can, [
          AdmissionStatus.interested,
          AdmissionStatus.visitScheduled,
          AdmissionStatus.visitCompleted,
        ]);
      },
    );

    test(
      'an application is parsed and starts the edit form from its values',
      () {
        final a = fakeApplication(
          '1',
          status: ApplicationStatus.submitted,
          revision: 4,
        );
        expect(
          [a.applicationNumber, a.studentName, a.classId, a.status, a.revision],
          ['APP-2026-00001', 'Asha Nair', 'c5', ApplicationStatus.submitted, 4],
        );
        final input = a.toInput();
        expect(input.details.firstName, 'Asha');
        expect(input.details.guardians.single.phone, '9876543210');
        final wire = input.toWire();
        expect(wire.containsKey('submissionNotes'), isTrue);
        for (final k in [
          'status',
          'schoolId',
          'branchId',
          'applicationNumber',
          'revision',
        ]) {
          expect(wire.containsKey(k), isFalse, reason: k);
        }
        final bare = AdmissionApplication.fromMap('x', const {});
        expect(bare.status, ApplicationStatus.draft);
      },
    );

    test('a document is parsed; images and PDFs are told apart', () {
      expect(fakeDocument('d1').isPdf, isTrue);
      final photo = fakeDocument(
        'd2',
        contentType: 'image/png',
        fileName: 'p.png',
      );
      expect(photo.isImage, isTrue);
      expect(photo.isPdf, isFalse);
      expect(
        AdmissionDocument.fromMap('x', const {}).status,
        DocumentStatus.uploading,
      );
    });

    test(
      'upload limits: size, empty, extension, and photographs must be images',
      () {
        String? check(String name, int size, {bool photo = false}) =>
            DocumentLimits.problem(
              fileName: name,
              sizeBytes: size,
              photo: photo,
            );
        expect(check('birth.pdf', 100), isNull);
        expect(check('scan.JPG', 100), isNull);
        expect(check('a.jpeg', 100), isNull);
        expect(check('a.webp', 100), isNull);
        expect(
          check('x.pdf', 5 * 1024 * 1024),
          isNull,
          reason: '5 MB exactly is fine',
        );
        expect(check('x.pdf', 5 * 1024 * 1024 + 1), contains('5 MB'));
        expect(check('x.pdf', 0), contains('empty'));
        expect(check('x.exe', 100), isNotNull);
        expect(check('noextension', 100), isNotNull);
        expect(check('x.pdf', 100, photo: true), contains('Photographs'));
        expect(check('x.png', 100, photo: true), isNull);
        expect(
          DocumentLimits.contentTypeFor('a.pdf', photo: false),
          'application/pdf',
        );
        expect(
          DocumentLimits.contentTypeFor('a.png', photo: false),
          'image/png',
        );
        expect(DocumentLimits.contentTypeFor('a.gif', photo: false), isNull);
      },
    );

    test('the school-defined type id is one the server accepts', () {
      final ok = RegExp(r'^[A-Z][A-Z0-9_]{2,23}$');
      for (final label in [
        'Caste certificate',
        'Aadhaar card',
        '  medical  report ',
        'ID',
        '2nd form',
        'x',
        'A very long document type name that goes on',
      ]) {
        final id = CustomDocumentType.idFor(label);
        expect(ok.hasMatch(id), isTrue, reason: '$label -> $id');
      }
      expect(
        CustomDocumentType.idFor('Caste certificate'),
        'CASTE_CERTIFICATE',
      );
    });

    test(
      'settings carry required documents, custom types and the approval switch',
      () {
        const d = AdmissionSettings();
        expect(d.requiredDocumentTypes, ['BIRTH_CERTIFICATE', 'STUDENT_PHOTO']);
        expect(d.branchAdminsMayApprove, isFalse);
        expect(d.documentTypes.keys, builtInDocumentTypes.keys);
        final s = AdmissionSettings.fromMap({
          'requiredDocumentTypes': ['ADDRESS_PROOF'],
          'customDocumentTypes': [
            {'id': 'CASTE_CERT', 'label': 'Caste certificate'},
            {'id': 5},
          ],
          'branchAdminsMayApprove': true,
        });
        expect(s.requiredDocumentTypes, ['ADDRESS_PROOF']);
        expect(s.documentTypes['CASTE_CERT'], 'Caste certificate');
        expect(s.branchAdminsMayApprove, isTrue);
        final wire = s.toWire();
        expect(wire['customDocumentTypes'], [
          {'id': 'CASTE_CERT', 'label': 'Caste certificate'},
        ]);
        expect(wire['branchAdminsMayApprove'], isTrue);
      },
    );

    test(
      'the timeline includes application events, ahead of activities in a tie',
      () {
        DateTime t(int m) => DateTime(2026, 11, 7, 10, m);
        final items = mergeTimeline(
          [
            StatusHistoryEntry(
              revision: 3,
              from: AdmissionStatus.interested,
              to: AdmissionStatus.applicationSubmitted,
              actorId: 'a',
              at: t(5),
            ),
          ],
          [
            ActivityHistoryEntry(
              activityId: 'v',
              revision: 1,
              event: ActivityEvent.created,
              type: ActivityType.email,
              actorId: 'a',
              at: t(5),
            ),
          ],
          [
            ApplicationEvent(
              revision: 2,
              event: 'SUBMITTED',
              actorId: 'a',
              at: t(5),
            ),
          ],
        );
        expect(items.map((i) => i.runtimeType.toString()), [
          'StatusTimelineItem',
          'ApplicationTimelineItem',
          'ActivityTimelineItem',
        ]);
        expect(
          ApplicationEvent.fromMap(const {
            'event': 'APPROVED',
            'from': 'UNDER_REVIEW',
            'to': 'APPROVED',
            'revision': 5,
          }).to,
          ApplicationStatus.approved,
        );
      },
    );
  });

  group('admission fees', () {
    AdmissionFee f({
      int amount = 1000,
      int waived = 0,
      int paid = 0,
      int refunded = 0,
      AdmissionFeeStatus st = AdmissionFeeStatus.due,
    }) => AdmissionFee(
      id: 'x',
      category: FeeCategory.application,
      currency: 'INR',
      amountMinor: amount,
      waivedMinor: waived,
      paidMinor: paid,
      refundedMinor: refunded,
      status: st,
    );

    test('balance and net paid', () {
      expect(f(paid: 300, waived: 100).balanceMinor, 600);
      expect(f(paid: 1000, refunded: 400).netPaidMinor, 600);
      expect(f(paid: 1000, refunded: 400).balanceMinor, 400);
      expect(f(st: AdmissionFeeStatus.cancelled).balanceMinor, 0);
      expect(
        f(paid: 1000, st: AdmissionFeeStatus.paid).canTakePayment,
        isFalse,
      );
      expect(f().canTakePayment, isTrue);
    });

    test('summary ignores cancelled fees', () {
      final s = AdmissionFeeSummary.of([
        f(paid: 300),
        f(amount: 500, st: AdmissionFeeStatus.cancelled),
      ]);
      expect((s.amountMinor, s.netPaidMinor, s.balanceMinor), (1000, 300, 700));
    });

    test('wire values parse; unknown categories and methods are null', () {
      expect(FeeCategory.tryParse('ADMISSION'), FeeCategory.admission);
      expect(FeeCategory.tryParse('x'), isNull);
      expect(AdmissionPaymentMethod.tryParse('UPI')!.needsReference, isTrue);
      expect(AdmissionPaymentMethod.cash.needsReference, isFalse);
      expect(AdmissionFeeStatus.parse('???'), AdmissionFeeStatus.due);
    });

    test('fromMap reads the stored record', () {
      final x = AdmissionFee.fromMap('e__ADMISSION', {
        'category': 'ADMISSION',
        'amountMinor': 5000,
        'paidMinor': 2000,
        'status': 'PARTIAL',
        'revision': 3,
      });
      expect(
        (x.category, x.balanceMinor, x.status, x.revision),
        (FeeCategory.admission, 3000, AdmissionFeeStatus.partial, 3),
      );
    });
  });
}
