import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_preview.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_repository.dart';

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
    int? baseVersion,
  }) async {
    _maybeFail();
    savedSettings.add(unmarkedDays);
    settings = PayrollSettings(
      unmarkedDays: unmarkedDays,
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
