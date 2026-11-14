import 'package:eazy_school_360/features/platform_admin/domain/platform_ops_models.dart';
import 'package:eazy_school_360/features/platform_admin/domain/school_overview.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/widgets/subscription_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eazy_school_360/features/platform_admin/domain/platform_school.dart';
import '../support/platform_fakes.dart';

import '../support/platform_ops_fakes.dart';

void main() {
  group('AppRequirements', () {
    final now = DateTime(2026, 11, 13, 10);

    test(
      'maintenance is in force until its end time, and indefinitely without one',
      () {
        expect(const AppRequirements().maintenanceActiveAt(now), isFalse);
        expect(
          const AppRequirements(maintenanceOn: true).maintenanceActiveAt(now),
          isTrue,
        );
        expect(
          AppRequirements(
            maintenanceOn: true,
            maintenanceUntil: now.add(const Duration(hours: 1)),
          ).maintenanceActiveAt(now),
          isTrue,
        );
        expect(
          AppRequirements(
            maintenanceOn: true,
            maintenanceUntil: now,
          ).maintenanceActiveAt(now),
          isFalse,
          reason: 'the end instant is over',
        );
        expect(
          AppRequirements(
            maintenanceOn: true,
            maintenanceUntil: now.subtract(const Duration(minutes: 1)),
          ).maintenanceActiveAt(now),
          isFalse,
        );
        expect(
          AppRequirements(
            maintenanceOn: false,
            maintenanceUntil: now.add(const Duration(hours: 1)),
          ).maintenanceActiveAt(now),
          isFalse,
        );
      },
    );

    test(
      'a build is too old only against its own platform; the web is never held back',
      () {
        const r = AppRequirements(minBuildAndroid: 14, minBuildIos: 5);
        expect(r.buildTooOld(build: 13, isAndroid: true, isIos: false), isTrue);
        expect(
          r.buildTooOld(build: 14, isAndroid: true, isIos: false),
          isFalse,
        );
        expect(r.buildTooOld(build: 4, isAndroid: false, isIos: true), isTrue);
        expect(r.buildTooOld(build: 5, isAndroid: false, isIos: true), isFalse);
        expect(
          r.buildTooOld(build: 1, isAndroid: false, isIos: false),
          isFalse,
          reason: 'web',
        );
        expect(
          const AppRequirements().buildTooOld(
            build: 0,
            isAndroid: true,
            isIos: false,
          ),
          isFalse,
          reason: 'no minimum',
        );
      },
    );

    test('fromMap reads the document, tolerating a sparse or missing one', () {
      final until = DateTime(2026, 11, 14);
      final r = AppRequirements.fromMap({
        'minBuild': {'android': 14, 'ios': 3},
        'maintenance': {
          'enabled': true,
          'message': 'Back soon',
          'until': until,
        },
      });
      expect(
        (
          r.minBuildAndroid,
          r.minBuildIos,
          r.maintenanceOn,
          r.maintenanceMessage,
          r.maintenanceUntil,
        ),
        (14, 3, true, 'Back soon', until),
      );
      expect(AppRequirements.fromMap(null).maintenanceOn, isFalse);
      expect(AppRequirements.fromMap({}).minBuildAndroid, 0);
      expect(
        AppRequirements.fromMap({
          'maintenance': {'until': 'junk'},
        }).maintenanceUntil,
        isNull,
      );
    });
  });

  group('SchoolNotice.isLiveAt', () {
    final now = DateTime(2026, 11, 13, 10);
    SchoolNotice n({
      DateTime? starts,
      DateTime? ends,
      bool withdrawn = false,
    }) => SchoolNotice(
      id: 'n',
      title: 't',
      body: 'b',
      severity: NoticeSeverity.info,
      startsAt: starts,
      endsAt: ends,
      withdrawn: withdrawn,
    );

    test('between start and end only', () {
      final h = const Duration(hours: 1);
      expect(
        n(starts: now.subtract(h), ends: now.add(h)).isLiveAt(now),
        isTrue,
      );
      expect(
        n(starts: now, ends: now.add(h)).isLiveAt(now),
        isTrue,
        reason: 'starts now',
      );
      expect(
        n(starts: now.add(h), ends: now.add(h * 2)).isLiveAt(now),
        isFalse,
        reason: 'not yet',
      );
      expect(
        n(starts: now.subtract(h * 2), ends: now).isLiveAt(now),
        isFalse,
        reason: 'ended',
      );
      expect(
        n(
          starts: now.subtract(h),
          ends: now.add(h),
          withdrawn: true,
        ).isLiveAt(now),
        isFalse,
      );
      expect(
        n(starts: now.subtract(h), ends: null).isLiveAt(now),
        isFalse,
        reason: 'no end: never live',
      );
    });

    test('an unknown severity reads as information', () {
      expect(NoticeSeverity.parse('LOUD'), NoticeSeverity.info);
      expect(NoticeSeverity.parse('CRITICAL'), NoticeSeverity.critical);
    });
  });

  group('PlatformStats', () {
    test('reads the rollup document', () {
      final s = fakeStats(deletions: 2, grants: 1, offboarding: 3, overdue: 4);
      expect(
        (
          s.schoolsTotal,
          s.schoolsActive,
          s.schoolsSuspended,
          s.schoolsInactive,
        ),
        (12, 9, 2, 1),
      );
      expect(
        (s.students, s.staff, s.parents, s.branches),
        (4200, 310, 3800, 15),
      );
      expect(
        (s.users, s.active1d, s.active7d, s.active30d),
        (4500, 600, 2100, 3300),
      );
      expect(
        (
          s.openDeletionRequests,
          s.activeSupportGrants,
          s.offboardingOpen,
          s.billingOverdue,
        ),
        (2, 1, 3, 4),
      );
    });

    test(
      'numbers older than a day and a half (or never computed) are stale',
      () {
        final now = DateTime(2026, 11, 13, 10);
        expect(
          fakeStats(
            computedAt: now.subtract(const Duration(hours: 35)),
          ).isStale(now),
          isFalse,
        );
        expect(
          fakeStats(
            computedAt: now.subtract(const Duration(hours: 37)),
          ).isStale(now),
          isTrue,
        );
        expect(PlatformStats.fromMap({}).isStale(now), isTrue);
        expect(PlatformStats.fromMap({}).schoolsTotal, 0);
      },
    );
  });

  group('billing', () {
    test('overdue means due, and past its day', () {
      expect(fakeBill(due: '2026-11-01').isOverdueOn('2026-11-13'), isTrue);
      expect(
        fakeBill(due: '2026-11-13').isOverdueOn('2026-11-13'),
        isFalse,
        reason: 'due today is not overdue',
      );
      expect(
        fakeBill(due: '2026-11-01', status: 'PAID').isOverdueOn('2026-11-13'),
        isFalse,
      );
      expect(
        fakeBill(due: '2026-11-01', status: 'VOID').isOverdueOn('2026-11-13'),
        isFalse,
      );
    });

    test('the summary reads records and what is owed per currency', () {
      final b = BillingSummary.fromMap({
        'records': [
          {
            'id': 'a',
            'schoolId': 's',
            'amountMinor': 100,
            'currency': 'INR',
            'dueDate': '2026-11-01',
            'status': 'DUE',
          },
        ],
        'owed': {
          'INR': {'dueMinor': 100, 'overdueMinor': 100},
        },
      });
      expect(b.records.single.amountMinor, 100);
      expect(b.owed['INR']!.overdueMinor, 100);
      expect(BillingSummary.fromMap({}).owed, isEmpty);
    });
  });

  group('NewSchoolInput', () {
    test(
      'sends trimmed text and regional settings; optional fields only when given',
      () {
        const i = NewSchoolInput(
          schoolName: '  Horizon School ',
          adminName: ' Asha ',
          adminEmail: ' a@h.example ',
          countryCode: 'IN',
          countryName: 'India',
          currency: 'INR',
          timezone: 'Asia/Kolkata',
          dateFormat: 'dd/MM/yyyy',
        );
        final m = i.toCallable();
        expect(
          (m['schoolName'], m['adminName'], m['adminEmail']),
          ('Horizon School', 'Asha', 'a@h.example'),
        );
        expect(m.containsKey('phone'), isFalse);
        expect(m.containsKey('schoolEmail'), isFalse);
        expect(m['regional'], {
          'countryCode': 'IN',
          'currency': 'INR',
          'timezone': 'Asia/Kolkata',
          'dateFormat': 'dd/MM/yyyy',
        });
      },
    );
  });

  group('SchoolOverview', () {
    test(
      'suspended and inactive schools read as paused; features default to on',
      () {
        expect(overviewWith(status: 'SUSPENDED').isSuspended, isTrue);
        expect(overviewWith(status: 'INACTIVE').isSuspended, isTrue);
        expect(overviewWith().isSuspended, isFalse);
        final o = overviewWith(features: {'admission': false});
        expect(o.featureOn('admission'), isFalse);
        expect(
          o.featureOn('publicAdmission'),
          isFalse,
          reason: 'a dependant goes off with its dependency',
        );
        expect(o.featureOn('fees'), isTrue);
        expect(o.featureOn('anything-new'), isTrue);
      },
    );

    test('offboarding is open while requested or approved only', () {
      OverviewOffboarding off(String s) =>
          OverviewOffboarding.fromMap({'state': s});
      expect(off('REQUESTED').isOpen, isTrue);
      expect(off('APPROVED').isOpen, isTrue);
      expect(off('CANCELLED').isOpen, isFalse);
      expect(overviewWith().offboarding, isNull);
      expect(
        overviewWith(
          offboarding: {
            'state': 'REQUESTED',
            'requestedBy': 'u',
            'graceUntilMs': 5,
          },
        ).offboarding!.requestedBy,
        'u',
      );
    });
  });

  group('School modules', () {
    School school(Map<String, bool> f) => School(
      schoolId: 's',
      name: 'n',
      email: 'e@x.com',
      status: SchoolStatus.active,
      features: f,
    );

    test(
      'a missing entry means on; only an explicit false switches a module off',
      () {
        expect(school(const {}).moduleEnabled('admission'), isTrue);
        expect(
          school(const {'admission': true}).moduleEnabled('admission'),
          isTrue,
        );
        expect(
          school(const {'admission': false}).moduleEnabled('admission'),
          isFalse,
        );
        expect(
          school(const {'admission': false}).moduleEnabled('publicAdmission'),
          isFalse,
          reason: 'its dependency is off',
        );
        expect(
          school(const {'admission': false}).moduleEnabled('fees'),
          isTrue,
        );
      },
    );
  });

  group('SchoolStatus', () {
    test('every lifecycle state round-trips; only ACTIVE is not paused', () {
      for (final st in SchoolStatus.values) {
        expect(SchoolStatus.fromWireValue(st.wireValue), st);
        expect(st.isPaused, st != SchoolStatus.active);
      }
      expect(SchoolStatus.values.map((e) => e.wireValue), [
        'ACTIVE',
        'INACTIVE',
        'SUSPENDED',
        'EXPIRED',
        'CLOSED',
      ]);
    });

    test(
      'an unknown state from a newer server pauses (never guesses ACTIVE)',
      () {
        expect(SchoolStatus.fromWireValue('ARCHIVED'), SchoolStatus.inactive);
        expect(SchoolStatus.fromWireValue(''), SchoolStatus.inactive);
      },
    );
  });

  group('UserProfile school access', () {
    Map<String, dynamic> data(Object? access) => {
      'role': 'TEACHER',
      'status': 'ACTIVE',
      'name': 'T',
      'email': 't@x.com',
      'schoolId': 's',
      'branchId': 'b',
      if (access != null) 'schoolAccess': access,
    };

    test('the mirrored state is read; absent means not paused', () {
      final p = UserProfile.fromFirestore('u', data('EXPIRED'));
      expect((p.schoolPaused, p.schoolAccessState), (true, 'EXPIRED'));
      final q = UserProfile.fromFirestore('u', data(null));
      expect((q.schoolPaused, q.schoolAccessState), (false, null));
    });
  });

  group('PlatformSchool search and registration filter', () {
    test('matches by contact email as well as name', () {
      final s = fakeSchool(email: 'Owner@Rosewood.edu');
      expect(s.matches('owner@rosewood'), isTrue);
      expect(s.matches('nobody@x'), isFalse);
    });

    test('registeredWithin counts whole days; unknown date never matches', () {
      final now = DateTime(2026, 11, 14);
      expect(
        fakeSchool(createdAt: DateTime(2026, 11, 10)).registeredWithin(7, now),
        isTrue,
      );
      expect(
        fakeSchool(createdAt: DateTime(2026, 11, 7)).registeredWithin(7, now),
        isFalse,
      );
      expect(
        fakeSchool(createdAt: DateTime(2026, 11, 8)).registeredWithin(7, now),
        isTrue,
      );
      expect(
        const PlatformSchool(
          id: 'x',
          name: 'n',
          code: 'c',
          status: 'ACTIVE',
          city: '',
          country: '',
          createdAt: null,
        ).registeredWithin(90, now),
        isFalse,
      );
    });
  });

  group('PlatformNotification', () {
    test('reads the callable row; missing fields are safe', () {
      final n = PlatformNotification.fromMap({
        'id': 'n1',
        'type': 'SCHOOL_SUSPENDED',
        'title': 'T',
        'body': 'B',
        'severity': 'CRITICAL',
        'requiresAck': true,
        'state': 'DELIVERED',
        'createdAtMs': 1700000000000,
      });
      expect(
        (n.id, n.severity, n.pendingAck, n.acknowledged),
        ('n1', NoticeSeverity.critical, true, false),
      );
      expect(n.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      final bare = PlatformNotification.fromMap(const {});
      expect(
        (bare.requiresAck, bare.state, bare.createdAt),
        (true, 'CREATED', null),
      );
    });

    test('only an unacknowledged, acknowledgement-required one is pending', () {
      PlatformNotification n(String state, bool ack) =>
          PlatformNotification.fromMap({'state': state, 'requiresAck': ack});
      expect(n('CREATED', true).pendingAck, isTrue);
      expect(n('DELIVERED', true).pendingAck, isTrue);
      expect(n('ACKNOWLEDGED', true).pendingAck, isFalse);
      expect(n('DISMISSED', true).pendingAck, isFalse);
      expect(n('DELIVERED', false).pendingAck, isFalse);
    });
  });

  group('subscription models', () {
    test('OverviewSubscription reads the server view; blocking states', () {
      final s = OverviewSubscription.fromMap({
        'planName': 'Annual',
        'classification': 'TRIAL',
        'startDate': '2026-04-01',
        'endDate': '2027-03-31',
        'gracePeriodDays': 3,
        'status': 'GRACE_PERIOD',
      });
      expect(
        (s.planName, s.classification, s.gracePeriodDays, s.blocking),
        ('Annual', 'TRIAL', 3, false),
      );
      for (final st in ['EXPIRED', 'CANCELLED']) {
        expect(
          OverviewSubscription.fromMap({'status': st}).blocking,
          isTrue,
          reason: st,
        );
      }
      for (final st in ['NOT_STARTED', 'TRIAL', 'ACTIVE', 'GRACE_PERIOD']) {
        expect(
          OverviewSubscription.fromMap({'status': st}).blocking,
          isFalse,
          reason: st,
        );
      }
      expect(
        OverviewSubscription.fromMap(const {}).status,
        'EXPIRED',
        reason: 'unknown never reads as allowed',
      );
    });

    test('labels are plain words', () {
      expect(OverviewSubscription.statusLabel('GRACE_PERIOD'), 'Grace period');
      expect(OverviewSubscription.statusLabel('NOT_STARTED'), 'Not started');
      expect(PlatformPlan.periodLabel('HALF_YEARLY'), 'Half-yearly');
      expect(PlatformPlan.periodLabel('WEIRD'), 'Custom');
    });

    test('validCalendarDate refuses impossible dates', () {
      for (final ok in ['2026-02-28', '2028-02-29', ' 2026-04-01 ']) {
        expect(validCalendarDate(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '2026-02-30',
        '2027-02-29',
        '2026-13-01',
        '2026-4-1',
        '',
        'tomorrow',
        '2026-04-31',
      ]) {
        expect(validCalendarDate(bad), isFalse, reason: bad);
      }
    });

    test('history entries label system changes and read the actor', () {
      final sys = SubscriptionHistoryEntry.fromMap({
        'id': 'a',
        'event': 'SUBSCRIPTION_STATUS_CHANGED',
        'actorKind': 'SYSTEM',
        'atMs': 1700000000000,
      });
      expect((sys.actor, sys.label), ('System', 'Status changed'));
      final own = SubscriptionHistoryEntry.fromMap({
        'id': 'b',
        'event': 'SUBSCRIPTION_RENEWED',
        'actorEmail': 'o@avail404.com',
      });
      expect(
        (own.actor, own.label, own.at),
        ('o@avail404.com', 'Renewed', null),
      );
    });
  });
}
