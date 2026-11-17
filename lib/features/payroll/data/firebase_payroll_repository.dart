import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/payroll.dart';
import '../../expenses/domain/expense.dart' show PaymentMode;
import '../domain/payroll_preview.dart';
import '../domain/payroll_run.dart';
import '../domain/payroll_repository.dart';

class FirebasePayrollRepository implements PayrollRepository {
  final FirebaseFunctions _functions;

  FirebasePayrollRepository({FirebaseFunctions? functions})
    : _functions = functions ?? appFunctions();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return (r.data as Map?)?.cast<String, dynamic>() ?? const {};
    } on FirebaseFunctionsException catch (e, st) {
      final cause = (e.details is Map ? (e.details as Map)['cause'] : null)
          ?.toString();
      switch (e.code) {
        case 'invalid-argument':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'Some details were not accepted. Check and try again.'
                : 'Some details were not accepted ($cause).',
          );
        case 'permission-denied':
          throw const PermissionFailure(
            'You do not have permission to see or change pay here.',
          );
        case 'not-found':
          throw const NotFoundFailure('That item could not be found.');
        case 'aborted':
          throw const ValidationFailure(
            'This was changed by someone else. Reload and try again.',
          );
        case 'already-exists':
          throw const ValidationFailure(
            'A component with that name already exists.',
          );
        case 'failed-precondition':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'That is not possible right now.'
                : cause,
          );
        default:
          throw mapExceptionToFailure(e, st);
      }
    } catch (e, st) {
      if (e is AppFailure) rethrow;
      throw mapExceptionToFailure(e, st);
    }
  }

  Map<String, dynamic> _map(Object? v) =>
      Map<String, dynamic>.from((v as Map?) ?? const {});

  @override
  Future<({List<PayComponent> components, bool canManage})> components(
    String schoolId, {
    bool includeInactive = false,
  }) async {
    final out = await _call('listPayComponents', {
      'schoolId': schoolId,
      'includeInactive': includeInactive,
    });
    return (
      components: [
        for (final c in (out['components'] as List? ?? const []))
          PayComponent.fromMap(_map(c)),
      ],
      canManage: out['canManage'] == true,
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
    final out = await _call('savePayComponent', {
      'schoolId': schoolId,
      'componentId': ?componentId,
      'name': name,
      'kind': ?kind?.wire,
      'calc': ?calc?.wire,
      'basisComponentId': ?basisComponentId,
      'percentBp': ?percentBp,
      'active': ?active,
    });
    return (out['id'] as String?) ?? '';
  }

  StaffPay _staff(Map<String, dynamic> m, {String idKey = 'id'}) => StaffPay(
    id: (m[idKey] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    employeeCode: (m['employeeCode'] as String?) ?? '',
    status: (m['status'] as String?) ?? '',
  );

  @override
  Future<({List<StaffPaySummary> staff, String currency})> staffPay(
    String schoolId,
    String branchId,
  ) async {
    final out = await _call('listSalaryStructures', {
      'schoolId': schoolId,
      'branchId': branchId,
    });
    return (
      currency: (out['currency'] as String?) ?? '',
      staff: [
        for (final r in (out['staff'] as List? ?? const []))
          StaffPaySummary(
            staff: _staff(_map(r), idKey: 'staffId'),
            hasStructure: _map(r)['hasStructure'] == true,
            effectiveFrom: _map(r)['effectiveFrom'] as String?,
            grossMinor: (_map(r)['grossMinor'] as num?)?.toInt(),
            deductionsMinor: (_map(r)['deductionsMinor'] as num?)?.toInt(),
            netMinor: (_map(r)['netMinor'] as num?)?.toInt(),
          ),
      ],
    );
  }

  @override
  Future<SalaryStructureView> structure(
    String schoolId,
    String branchId,
    String staffId,
  ) async {
    final out = await _call('getSalaryStructure', {
      'schoolId': schoolId,
      'branchId': branchId,
      'staffId': staffId,
    });
    return SalaryStructureView(
      staff: _staff(_map(out['staff'])),
      current: out['current'] == null
          ? null
          : SalaryStructure.fromMap(_map(out['current'])),
      history: [
        for (final h in (out['history'] as List? ?? const []))
          SalaryStructure.fromMap(_map(h)),
      ],
      canEdit: out['canEdit'] == true,
      currency: (out['currency'] as String?) ?? '',
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
    final out = await _call('saveSalaryStructure', {
      'schoolId': schoolId,
      'branchId': branchId,
      'staffId': staffId,
      'effectiveFrom': effectiveFrom,
      'lines': [for (final l in lines) l.toRequest()],
      'reason': ?reason,
      'baseSeq': ?baseSeq,
    });
    return (out['seq'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<({PayrollSettings settings, bool canManage})> payrollSettings(
    String schoolId,
  ) async {
    final out = await _call('getPayrollSettings', {'schoolId': schoolId});
    return (
      settings: PayrollSettings.fromMap(_map(out['settings'])),
      canManage: out['canManage'] == true,
    );
  }

  @override
  Future<int> savePayrollSettings(
    String schoolId,
    UnmarkedDays unmarkedDays, {
    bool allowSelfApproval = false,
    int? baseVersion,
  }) async {
    final out = await _call('savePayrollSettings', {
      'schoolId': schoolId,
      'settings': {
        'unmarkedDays': unmarkedDays.wire,
        'allowSelfApproval': allowSelfApproval,
      },
      'baseVersion': ?baseVersion,
    });
    return (out['version'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<PayPreviewBranch> previewBranch(
    String schoolId,
    String branchId,
    String period,
  ) async {
    final out = await _call('previewPayroll', {
      'schoolId': schoolId,
      'branchId': branchId,
      'period': period,
    });
    return PayPreviewBranch(
      period: (out['period'] as String?) ?? period,
      currency: (out['currency'] as String?) ?? '',
      workingDays: (out['workingDays'] as num?)?.toInt() ?? 0,
      unmarkedDays: UnmarkedDays.fromWire(
        _map(out['settings'])['unmarkedDays'],
      ),
      rows: [
        for (final r in (out['staff'] as List? ?? const [])) _row(_map(r)),
      ],
    );
  }

  PayPreviewRow _row(Map<String, dynamic> r) {
    final c = r['calculation'] == null ? null : _map(r['calculation']);
    return PayPreviewRow(
      staff: _staff(r, idKey: 'staffId'),
      hasStructure: r['hasStructure'] == true,
      workingDays: (c?['workingDays'] as num?)?.toInt() ?? 0,
      paidDays: (c?['paidDays'] as num?)?.toDouble() ?? 0,
      unpaidDays: (c?['unpaidDays'] as num?)?.toDouble() ?? 0,
      netMinor: (c?['netMinor'] as num?)?.toInt() ?? 0,
      unrecoveredDeductionMinor:
          (c?['unrecoveredDeductionMinor'] as num?)?.toInt() ?? 0,
      warningCount: (c?['warningCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<PayPreviewStaff> previewStaff(
    String schoolId,
    String branchId,
    String staffId,
    String period,
  ) async {
    final out = await _call('previewPayroll', {
      'schoolId': schoolId,
      'branchId': branchId,
      'staffId': staffId,
      'period': period,
    });
    return PayPreviewStaff(
      period: (out['period'] as String?) ?? period,
      currency: (out['currency'] as String?) ?? '',
      staff: _staff(_map(out['staff'])),
      structure: out['structure'] == null
          ? null
          : SalaryStructure.fromMap(_map(out['structure'])),
      calculation: out['calculation'] == null
          ? null
          : PayCalculation.fromMap(_map(out['calculation'])),
    );
  }

  // ---- runs (phase P3) ----

  Map<String, dynamic> _scope(
    String schoolId,
    String branchId,
    String period,
  ) => {'schoolId': schoolId, 'branchId': branchId, 'period': period};

  @override
  Future<PayrollRunList> runs(String schoolId, String branchId) async {
    final out = await _call('listPayrollRuns', {
      'schoolId': schoolId,
      'branchId': branchId,
    });
    return PayrollRunList(
      runs: [
        for (final r in (out['runs'] as List? ?? const []))
          PayrollRun.fromMap(_map(r)),
      ],
      canPrepare: out['canPrepare'] == true,
      canApprove: out['canApprove'] == true,
      canPay: out['canPay'] == true,
    );
  }

  PayslipRow _slipRow(Map<String, dynamic> m) => PayslipRow.fromMap(m);

  @override
  Future<PayrollRunDetail> run(
    String schoolId,
    String branchId,
    String period,
  ) async {
    final out = await _call(
      'getPayrollRun',
      _scope(schoolId, branchId, period),
    );
    return PayrollRunDetail(
      run: PayrollRun.fromMap(_map(out['run'])),
      payslips: [
        for (final p in (out['payslips'] as List? ?? const []))
          _slipRow(_map(p)),
      ],
      skipped: (out['skippedStaffIds'] as List? ?? const []).length,
      canPrepare: out['canPrepare'] == true,
      canApprove: out['canApprove'] == true,
      canPay: out['canPay'] == true,
      allowSelfApproval: out['allowSelfApproval'] == true,
    );
  }

  @override
  Future<Payslip> payslip(
    String schoolId,
    String branchId,
    String period,
    String staffId,
  ) async {
    final out = await _call('getPayslip', {
      ..._scope(schoolId, branchId, period),
      'staffId': staffId,
    });
    final p = _map(out['payslip']);
    return Payslip(
      row: _slipRow(p),
      currency: (p['currency'] as String?) ?? '',
      lines: [
        for (final l in (p['lines'] as List? ?? const []))
          PayLineSnapshot(
            name: (_map(l)['name'] as String?) ?? '',
            kind: PayKind.fromWire(_map(l)['kind']),
            plannedMinor: (_map(l)['plannedMinor'] as num?)?.toInt() ?? 0,
            amountMinor: (_map(l)['amountMinor'] as num?)?.toInt() ?? 0,
          ),
      ],
      adjustments: [
        for (final a in (p['adjustments'] as List? ?? const []))
          PayAdjustment.fromMap(_map(a)),
      ],
      warnings: [
        for (final w in (p['warnings'] as List? ?? const []))
          PayWarning.fromMap(_map(w)).text,
      ],
      baseGrossMinor: (p['baseGrossMinor'] as num?)?.toInt() ?? 0,
      unrecoveredDeductionMinor:
          (p['unrecoveredDeductionMinor'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<RunHistoryEntry>> runHistory(
    String schoolId,
    String branchId,
    String period,
  ) async {
    final out = await _call(
      'getPayrollRunHistory',
      _scope(schoolId, branchId, period),
    );
    return [
      for (final h in (out['history'] as List? ?? const []))
        RunHistoryEntry(
          seq: (_map(h)['seq'] as num?)?.toInt() ?? 0,
          action: (_map(h)['action'] as String?) ?? '',
          from: _map(h)['from'] as String?,
          to: _map(h)['to'] as String?,
          reason: _map(h)['reason'] as String?,
          actorName: _map(h)['actorName'] as String?,
          actorRole: _map(h)['actorRole'] as String?,
          atMs: (_map(h)['atMs'] as num?)?.toInt(),
        ),
    ];
  }

  @override
  Future<void> createRun(String schoolId, String branchId, String period) =>
      _call('createPayrollRun', _scope(schoolId, branchId, period));

  @override
  Future<void> recalculateRun(
    String schoolId,
    String branchId,
    String period, {
    int? baseVersion,
  }) => _call('calculatePayrollRun', {
    ..._scope(schoolId, branchId, period),
    'baseVersion': ?baseVersion,
  });

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
  }) => _call('adjustPayslip', {
    ..._scope(schoolId, branchId, period),
    'staffId': staffId,
    'adjustment': {
      'kind': kind.wire,
      'label': label,
      'amountMinor': amountMinor,
      'reason': reason,
    },
    'baseVersion': ?baseVersion,
  });

  @override
  Future<void> removeAdjustment(
    String schoolId,
    String branchId,
    String period,
    String staffId,
    String adjustmentId, {
    int? baseVersion,
  }) => _call('removePayslipAdjustment', {
    ..._scope(schoolId, branchId, period),
    'staffId': staffId,
    'adjustmentId': adjustmentId,
    'baseVersion': ?baseVersion,
  });

  @override
  Future<void> approveRun(
    String schoolId,
    String branchId,
    String period, {
    required bool acknowledgeWarnings,
    int? baseVersion,
  }) => _call('approvePayrollRun', {
    ..._scope(schoolId, branchId, period),
    'acknowledgeWarnings': acknowledgeWarnings,
    'baseVersion': ?baseVersion,
  });

  @override
  Future<void> payRun(
    String schoolId,
    String branchId,
    String period, {
    required PaymentMode mode,
    String? reference,
    String? paidDate,
    int? baseVersion,
  }) => _call('payPayrollRun', {
    ..._scope(schoolId, branchId, period),
    'payment': {
      'paymentMode': mode.wire,
      'paymentReference': ?reference,
      'paidDate': ?paidDate,
    },
    'baseVersion': ?baseVersion,
  });

  @override
  Future<void> cancelRun(
    String schoolId,
    String branchId,
    String period, {
    required String reason,
    int? baseVersion,
  }) => _call('cancelPayrollRun', {
    ..._scope(schoolId, branchId, period),
    'reason': reason,
    'baseVersion': ?baseVersion,
  });
}
