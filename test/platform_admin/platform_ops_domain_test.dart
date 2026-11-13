import 'package:eazy_school_360/features/platform_admin/domain/platform_ops_models.dart';
import 'package:eazy_school_360/features/platform_admin/domain/school_overview.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:flutter_test/flutter_test.dart';

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
        expect(o.featureOn('publicAdmission'), isTrue);
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
          isTrue,
        );
      },
    );
  });
}
