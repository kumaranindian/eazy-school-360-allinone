import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_payroll_repository.dart';
import '../../domain/payroll.dart';
import '../../domain/payroll_preview.dart';
import '../../domain/payroll_run.dart';
import '../../domain/payroll_repository.dart';

final payrollRepositoryProvider = Provider<PayrollRepository>(
  (ref) => FirebasePayrollRepository(),
);

/// Active components (what a structure can use).
final payComponentsProvider = FutureProvider.autoDispose
    .family<({List<PayComponent> components, bool canManage}), String>(
      (ref, schoolId) =>
          ref.watch(payrollRepositoryProvider).components(schoolId),
    );

/// Every component including switched-off ones (the management page).
final payAllComponentsProvider = FutureProvider.autoDispose
    .family<({List<PayComponent> components, bool canManage}), String>(
      (ref, schoolId) => ref
          .watch(payrollRepositoryProvider)
          .components(schoolId, includeInactive: true),
    );

typedef PayBranchKey = ({String schoolId, String branchId});

final staffPayProvider = FutureProvider.autoDispose
    .family<({List<StaffPaySummary> staff, String currency}), PayBranchKey>(
      (ref, k) =>
          ref.watch(payrollRepositoryProvider).staffPay(k.schoolId, k.branchId),
    );

typedef SalaryKey = ({String schoolId, String branchId, String staffId});

final salaryStructureProvider = FutureProvider.autoDispose
    .family<SalaryStructureView, SalaryKey>(
      (ref, k) => ref
          .watch(payrollRepositoryProvider)
          .structure(k.schoolId, k.branchId, k.staffId),
    );

final payrollSettingsProvider = FutureProvider.autoDispose
    .family<({PayrollSettings settings, bool canManage}), String>(
      (ref, schoolId) =>
          ref.watch(payrollRepositoryProvider).payrollSettings(schoolId),
    );

typedef PreviewKey = ({String schoolId, String branchId, String period});

final payPreviewProvider = FutureProvider.autoDispose
    .family<PayPreviewBranch, PreviewKey>(
      (ref, k) => ref
          .watch(payrollRepositoryProvider)
          .previewBranch(k.schoolId, k.branchId, k.period),
    );

typedef PreviewStaffKey = ({
  String schoolId,
  String branchId,
  String staffId,
  String period,
});

final payPreviewStaffProvider = FutureProvider.autoDispose
    .family<PayPreviewStaff, PreviewStaffKey>(
      (ref, k) => ref
          .watch(payrollRepositoryProvider)
          .previewStaff(k.schoolId, k.branchId, k.staffId, k.period),
    );

final payrollRunsProvider = FutureProvider.autoDispose
    .family<PayrollRunList, PayBranchKey>(
      (ref, k) =>
          ref.watch(payrollRepositoryProvider).runs(k.schoolId, k.branchId),
    );

typedef RunKey = ({String schoolId, String branchId, String period});

final payrollRunProvider = FutureProvider.autoDispose
    .family<PayrollRunDetail, RunKey>(
      (ref, k) => ref
          .watch(payrollRepositoryProvider)
          .run(k.schoolId, k.branchId, k.period),
    );

typedef PayslipKey = ({
  String schoolId,
  String branchId,
  String period,
  String staffId,
});

final payslipProvider = FutureProvider.autoDispose.family<Payslip, PayslipKey>(
  (ref, k) => ref
      .watch(payrollRepositoryProvider)
      .payslip(k.schoolId, k.branchId, k.period, k.staffId),
);

final payrollRunHistoryProvider = FutureProvider.autoDispose
    .family<List<RunHistoryEntry>, RunKey>(
      (ref, k) => ref
          .watch(payrollRepositoryProvider)
          .runHistory(k.schoolId, k.branchId, k.period),
    );
