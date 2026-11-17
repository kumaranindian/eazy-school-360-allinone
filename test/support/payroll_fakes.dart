import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_preview.dart';
import 'package:eazy_school_360/features/expenses/domain/expense.dart'
    show PaymentMode;
import 'package:eazy_school_360/features/payroll/domain/payroll_repository.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_run.dart';

/// In-memory [PayrollRepository]. Records what the app asks for so tests can
/// check the request, and can be told to fail.
class FakePayrollRepository implements PayrollRepository {
  final List<PayComponent> items = [
    const PayComponent(
      id: 'pc_basic',
      name: 'Basic salary',
      kind: PayKind.earning,
      calc: PayCalc.fixed,
      system: true,
    ),
    const PayComponent(
      id: 'pc_hra',
      name: 'HRA',
      kind: PayKind.earning,
      calc: PayCalc.percent,
      basisComponentId: 'pc_basic',
      percentBp: 4000,
    ),
    const PayComponent(
      id: 'pc_pf',
      name: 'Provident fund',
      kind: PayKind.deduction,
      calc: PayCalc.percent,
      basisComponentId: 'pc_basic',
      percentBp: 1200,
    ),
  ];
  final List<StaffPaySummary> staff = [];
  final Map<String, List<SalaryStructure>> versions = {};
  bool canManage = true;
  bool canEdit = true;
  Object? failWith;
  String currency = 'INR';

  final List<Map<String, Object?>> savedStructures = [];
  final List<Map<String, Object?>> savedComponents = [];
  int staffPayCalls = 0;

  void _maybeFail() {
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<({List<PayComponent> components, bool canManage})> components(
    String schoolId, {
    bool includeInactive = false,
  }) async {
    _maybeFail();
    return (
      components: [
        for (final c in items)
          if (includeInactive || c.active) c,
      ],
      canManage: canManage,
    );
  }

  @override
  Future<String> saveComponent(
    String schoolId, {
    String? componentId,
    required String name,
    PayKind? kind,
    PayCalc? calc,
    String? basisComponentId,
    int? percentBp,
    bool? active,
  }) async {
    _maybeFail();
    savedComponents.add({
      'id': componentId,
      'name': name,
      'kind': kind,
      'calc': calc,
      'basis': basisComponentId,
      'percentBp': percentBp,
      'active': active,
    });
    return componentId ?? 'pc_new';
  }

  @override
  Future<({List<StaffPaySummary> staff, String currency})> staffPay(
    String schoolId,
    String branchId,
  ) async {
    _maybeFail();
    staffPayCalls++;
    return (staff: staff, currency: currency);
  }

  @override
  Future<SalaryStructureView> structure(
    String schoolId,
    String branchId,
    String staffId,
  ) async {
    _maybeFail();
    final all = versions[staffId] ?? const <SalaryStructure>[];
    final sorted = [...all]..sort((a, b) => b.seq.compareTo(a.seq));
    return SalaryStructureView(
      staff: StaffPay(
        id: staffId,
        name: 'Asha Rao',
        employeeCode: 'E1',
        status: 'ACTIVE',
      ),
      current: sorted.isEmpty ? null : sorted.first,
      history: sorted,
      canEdit: canEdit,
      currency: currency,
    );
  }

  @override
  Future<int> saveStructure(
    String schoolId,
    String branchId,
    String staffId, {
    required String effectiveFrom,
    required List<SalaryLineInput> lines,
    String? reason,
    int? baseSeq,
  }) async {
    _maybeFail();
    savedStructures.add({
      'staffId': staffId,
      'effectiveFrom': effectiveFrom,
      'lines': [for (final l in lines) l.toRequest()],
      'reason': reason,
      'baseSeq': baseSeq,
    });
    return (baseSeq ?? 0) + 1;
  }

  PayrollSettings settings = const PayrollSettings();
  PayPreviewBranch? branchPreview;
  PayPreviewStaff? staffPreview;
  final List<({String branch, String? staff, String period})> previewCalls = [];
  final List<UnmarkedDays> savedSettings = [];
  final List<bool> savedSelfApproval = [];

  @override
  Future<({PayrollSettings settings, bool canManage})> payrollSettings(
    String schoolId,
  ) async {
    _maybeFail();
    return (settings: settings, canManage: canManage);
  }

  @override
  Future<int> savePayrollSettings(
    String schoolId,
    UnmarkedDays unmarkedDays, {
    bool allowSelfApproval = false,
    int? baseVersion,
  }) async {
    _maybeFail();
    savedSettings.add(unmarkedDays);
    savedSelfApproval.add(allowSelfApproval);
    settings = PayrollSettings(
      unmarkedDays: unmarkedDays,
      allowSelfApproval: allowSelfApproval,
      version: settings.version + 1,
    );
    return settings.version;
  }

  @override
  Future<PayPreviewBranch> previewBranch(
    String schoolId,
    String branchId,
    String period,
  ) async {
    _maybeFail();
    previewCalls.add((branch: branchId, staff: null, period: period));
    return branchPreview ??
        PayPreviewBranch(
          period: period,
          currency: currency,
          workingDays: 21,
          unmarkedDays: settings.unmarkedDays,
          rows: const [],
        );
  }

  @override
  Future<PayPreviewStaff> previewStaff(
    String schoolId,
    String branchId,
    String staffId,
    String period,
  ) async {
    _maybeFail();
    previewCalls.add((branch: branchId, staff: staffId, period: period));
    return staffPreview!;
  }

  // ---- runs (phase P3) ----
  final List<PayrollRun> runItems = [];
  final Map<String, List<PayslipRow>> runSlips = {};
  final Map<String, Payslip> slipDetails = {};
  bool canPrepare = true;
  bool canApprove = true;
  bool canPay = true;
  bool allowSelf = false;
  final List<String> runCalls = [];
  final List<Map<String, Object?>> runArgs = [];

  void _call(String name, [Map<String, Object?> args = const {}]) {
    runCalls.add(name);
    runArgs.add({'call': name, ...args});
  }

  @override
  Future<PayrollRunList> runs(String schoolId, String branchId) async {
    _maybeFail();
    return PayrollRunList(
      runs: [...runItems],
      canPrepare: canPrepare,
      canApprove: canApprove,
      canPay: canPay,
    );
  }

  @override
  Future<PayrollRunDetail> run(
    String schoolId,
    String branchId,
    String period,
  ) async {
    _maybeFail();
    final r = runItems.firstWhere((x) => x.period == period);
    return PayrollRunDetail(
      run: r,
      payslips: runSlips[period] ?? const [],
      skipped: r.skippedCount,
      canPrepare: canPrepare,
      canApprove: canApprove,
      canPay: canPay,
      allowSelfApproval: allowSelf,
    );
  }

  @override
  Future<Payslip> payslip(
    String schoolId,
    String branchId,
    String period,
    String staffId,
  ) async {
    _maybeFail();
    return slipDetails[staffId]!;
  }

  @override
  Future<List<RunHistoryEntry>> runHistory(
    String schoolId,
    String branchId,
    String period,
  ) async => const [
    RunHistoryEntry(
      seq: 1,
      action: 'create',
      to: 'CALCULATED',
      actorName: 'Fay Finance',
    ),
  ];

  @override
  Future<void> createRun(
    String schoolId,
    String branchId,
    String period,
  ) async {
    _maybeFail();
    _call('createRun', {'period': period});
    runItems.insert(
      0,
      PayrollRun(
        period: period,
        status: RunStatus.calculated,
        version: 2,
        currency: currency,
        payslipCount: 1,
        netMinor: 100,
        grossMinor: 100,
      ),
    );
  }

  @override
  Future<void> recalculateRun(
    String schoolId,
    String branchId,
    String period, {
    int? baseVersion,
  }) async {
    _maybeFail();
    _call('recalculate', {'period': period, 'baseVersion': baseVersion});
  }

  @override
  Future<void> addAdjustment(
    String schoolId,
    String branchId,
    String period,
    String staffId, {
    required PayKind kind,
    required String label,
    required int amountMinor,
    required String reason,
    int? baseVersion,
  }) async {
    _maybeFail();
    _call('adjust', {
      'staffId': staffId,
      'kind': kind,
      'label': label,
      'amountMinor': amountMinor,
      'reason': reason,
    });
  }

  @override
  Future<void> removeAdjustment(
    String schoolId,
    String branchId,
    String period,
    String staffId,
    String adjustmentId, {
    int? baseVersion,
  }) async {
    _maybeFail();
    _call('removeAdjustment', {'staffId': staffId, 'id': adjustmentId});
  }

  @override
  Future<void> approveRun(
    String schoolId,
    String branchId,
    String period, {
    required bool acknowledgeWarnings,
    int? baseVersion,
  }) async {
    _maybeFail();
    _call('approve', {'ack': acknowledgeWarnings, 'baseVersion': baseVersion});
  }

  @override
  Future<void> payRun(
    String schoolId,
    String branchId,
    String period, {
    required PaymentMode mode,
    String? reference,
    String? paidDate,
    int? baseVersion,
  }) async {
    _maybeFail();
    _call('pay', {'mode': mode, 'reference': reference});
  }

  @override
  Future<void> cancelRun(
    String schoolId,
    String branchId,
    String period, {
    required String reason,
    int? baseVersion,
  }) async {
    _maybeFail();
    _call('cancel', {'reason': reason});
  }
}

SalaryStructure fakeStructure({
  int seq = 1,
  String from = '2026-04-01',
  int basic = 3000000,
  bool latest = true,
}) => SalaryStructure(
  id: 'st1_0000$seq',
  staffId: 'st1',
  seq: seq,
  effectiveFrom: from,
  currency: 'INR',
  lines: [
    SalaryLine(
      componentId: 'pc_basic',
      name: 'Basic salary',
      kind: PayKind.earning,
      calc: PayCalc.fixed,
      amountMinor: basic,
    ),
  ],
  grossMinor: basic,
  deductionsMinor: 0,
  netMinor: basic,
  latest: latest,
);
