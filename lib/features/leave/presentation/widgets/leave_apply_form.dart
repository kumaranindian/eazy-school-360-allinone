import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../academic_setup/presentation/providers/calendar_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_balance.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../../domain/leave_submission.dart';
import '../../domain/leave_type.dart';
import '../../domain/leave_units.dart';
import '../../domain/leave_workflow.dart';
import '../providers/leave_providers.dart';
import 'leave_widgets.dart';

/// Who the leave is for, resolved by the page that hosts the form.
class LeaveSubject {
  final LeaveKind kind;
  final String id;
  final String name;
  final String? code;
  final String? classId;
  final String? className;
  final String? sectionId;
  final String? sectionName;

  const LeaveSubject({
    required this.kind,
    required this.id,
    required this.name,
    this.code,
    this.classId,
    this.className,
    this.sectionId,
    this.sectionName,
  });
}

/// The application form: leave type, dates, session, reason, documents — with
/// the counted days, any blocking error and any warning shown **before**
/// submitting. All of that comes from [LeaveSubmissionPlanner]; this widget
/// only collects input and displays the plan.
///
/// The application id is created once per form, so a double-tap or a retry
/// after a network failure cannot file the application twice. Uploaded files
/// are kept across retries (not uploaded again).
class LeaveApplyForm extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final AcademicYear year;
  final LeaveSubject subject;
  final LeaveActor actor;
  final String applicantRole;
  final ApplicantRelation relation;
  final String? employmentType;

  /// A RETURNED application being corrected (resubmit) — or null for new.
  final LeaveApplication? resubmitting;
  final VoidCallback onDone;

  const LeaveApplyForm({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.year,
    required this.subject,
    required this.actor,
    required this.applicantRole,
    required this.relation,
    this.employmentType,
    this.resubmitting,
    required this.onDone,
  });

  @override
  ConsumerState<LeaveApplyForm> createState() => _LeaveApplyFormState();
}

class _LeaveApplyFormState extends ConsumerState<LeaveApplyForm> {
  final _reason = TextEditingController();
  late final String _applicationId;
  String? _typeId;
  DateTime? _start;
  DateTime? _end;
  HalfDay _half = HalfDay.none;
  final List<LeaveAttachment> _uploaded = [];
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.resubmitting;
    _applicationId = r?.applicationId ?? LeaveApplication.newId();
    if (r != null) {
      _typeId = r.typeId;
      _start = AttendanceDate.parse(r.startDateKey);
      _end = AttendanceDate.parse(r.endDateKey);
      _half = r.halfDay;
      _reason.text = r.reason ?? '';
      _uploaded.addAll(r.attachments);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String? _key(DateTime? d) => d == null ? null : AttendanceDate.key(d);

  Future<void> _pickDate({required bool start}) async {
    final y = widget.year;
    final first = DateTime.utc(
      y.startDate.toUtc().year,
      y.startDate.toUtc().month,
      y.startDate.toUtc().day,
    );
    final last = DateTime.utc(
      y.endDate.toUtc().year,
      y.endDate.toUtc().month,
      y.endDate.toUtc().day,
    );
    final today = DateTime.now();
    var initial =
        (start ? _start : _end) ??
        DateTime.utc(today.year, today.month, today.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: start ? 'First day of leave' : 'Last day of leave',
    );
    if (picked == null) return;
    setState(() {
      final d = DateTime.utc(picked.year, picked.month, picked.day);
      if (start) {
        _start = d;
        if (_end == null || _end!.isBefore(d)) _end = d;
      } else {
        _end = d;
        if (_start == null || _start!.isAfter(d)) _start = d;
      }
      if (_start != _end) _half = HalfDay.none;
    });
  }

  Future<void> _addFile() async {
    if (_uploaded.length >= LeaveWorkflow.maxAttachments) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final attachment = await ref
          .read(leaveAttachmentStoreProvider)
          .upload(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            applicantUserId: widget.actor.userId,
            applicationId: _applicationId,
            fileName: file.name,
            bytes: bytes,
          );
      if (mounted) setState(() => _uploaded.add(attachment));
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit(SubmissionPlan plan, LeaveType type) async {
    if (_saving || !plan.canSubmit) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final s = widget.subject;
    final application = LeaveApplication(
      applicationId: _applicationId,
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      kind: s.kind,
      subjectId: s.id,
      subjectName: s.name,
      subjectCode: s.code,
      academicYearId: widget.year.academicYearId,
      classId: s.classId,
      className: s.className,
      sectionId: s.sectionId,
      sectionName: s.sectionName,
      applicantUserId: widget.actor.userId,
      applicantName: widget.actor.name,
      relation: widget.relation,
      typeId: type.typeId,
      typeName: type.name,
      payType: type.payType,
      startDateKey: _key(_start)!,
      endDateKey: _key(_end)!,
      halfDay: _half,
      units: plan.units,
      countedDateKeys: plan.span!.countedDateKeys,
      reason: _reason.text,
      attachments: List.of(_uploaded),
      balanceId: type.tracksBalance
          ? LeaveBalance.idFor(s.id, type.typeId, widget.year.academicYearId)
          : null,
      leaveYearStartKey: AttendanceDate.key(widget.year.startDate.toUtc()),
    );
    final repo = ref.read(leaveApplicationRepositoryProvider);
    try {
      if (widget.resubmitting != null) {
        await repo.resubmit(application, actor: widget.actor);
      } else {
        await repo.submit(application, actor: widget.actor);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.resubmitting != null
                ? 'Leave application resubmitted.'
                : 'Leave application submitted for approval.',
          ),
        ),
      );
      ref.invalidate(subjectLeaveProvider);
      widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.subject;
    final BranchKey branchKey = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
    );
    final AcademicYearKey yearKey = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: widget.year.academicYearId,
    );
    final typesAsync = ref.watch(
      activeLeaveTypesProvider((
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        kind: s.kind,
      )),
    );
    final workingDaysAsync = ref.watch(workingDaysProvider(branchKey));
    final holidays = ref.watch(holidaysProvider(yearKey)).value ?? const [];
    final existing =
        ref
            .watch(
              subjectLeaveProvider((
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                kind: s.kind,
                subjectId: s.id,
              )),
            )
            .value ??
        const <LeaveApplication>[];

    if (typesAsync.isLoading || workingDaysAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (typesAsync.hasError || workingDaysAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          userMessageFor((typesAsync.error ?? workingDaysAsync.error)!),
        ),
      );
    }
    final allTypes = typesAsync.value ?? const <LeaveType>[];
    final types = [
      for (final t in allTypes)
        if (s.kind == LeaveKind.student ||
            (t.appliesToRole(widget.applicantRole) &&
                t.appliesToEmployment(widget.employmentType)))
          t,
    ];
    if (types.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No leave types are available yet. Please ask the school office '
          'to set them up.',
        ),
      );
    }
    final type = types.where((t) => t.typeId == _typeId).firstOrNull;

    LeaveBalance? balance;
    var pendingUnits = 0;
    if (s.kind == LeaveKind.staff && type != null && type.tracksBalance) {
      final balances =
          ref
              .watch(
                staffLeaveBalancesProvider((
                  schoolId: widget.schoolId,
                  branchId: widget.branchId,
                  staffId: s.id,
                  academicYearId: widget.year.academicYearId,
                )),
              )
              .value ??
          const <LeaveBalance>[];
      balance = balances.where((b) => b.typeId == type.typeId).firstOrNull;
      pendingUnits = existing
          .where(
            (a) =>
                a.status == LeaveStatus.pending &&
                a.typeId == type.typeId &&
                a.academicYearId == widget.year.academicYearId &&
                a.applicationId != _applicationId,
          )
          .fold(0, (sum, a) => sum + a.units);
    }

    final yearStart = AttendanceDate.key(widget.year.startDate.toUtc());
    final yearEnd = AttendanceDate.key(widget.year.endDate.toUtc());
    final plan = (type == null || _start == null || _end == null)
        ? SubmissionPlan(
            error: type == null ? 'Choose a leave type.' : 'Choose the dates.',
          )
        : LeaveSubmissionPlanner.plan(
            type: type,
            startKey: _key(_start)!,
            endKey: _key(_end)!,
            halfDay: _half,
            reason: _reason.text,
            attachmentCount: _uploaded.length,
            workingDays: workingDaysAsync.requireValue,
            calendarEntries: holidays,
            yearStartKey: yearStart,
            yearEndKey: yearEnd,
            existing: existing,
            applicantRole: widget.applicantRole,
            employmentType: widget.employmentType,
            balance: balance,
            pendingUnits: pendingUnits,
            todayKey: AttendanceDate.key(DateTime.now()),
            ignoreApplicationId: _applicationId,
          );

    final canPickHalf =
        type != null &&
        type.allowHalfDay &&
        _start != null &&
        _end != null &&
        _start == _end;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Leave for ${s.name}'
          '${s.className == null ? '' : ' · ${s.className}${s.sectionName == null ? '' : ' ${s.sectionName}'}'}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: type?.typeId,
          decoration: const InputDecoration(labelText: 'Leave type'),
          items: [
            for (final t in types)
              DropdownMenuItem(value: t.typeId, child: Text(t.name)),
          ],
          onChanged: widget.resubmitting != null
              ? null
              : (v) => setState(() {
                  _typeId = v;
                  _half = HalfDay.none;
                }),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickDate(start: true),
              icon: const Icon(Icons.event),
              label: Text(
                _start == null
                    ? 'First day'
                    : 'From ${leaveDate(AttendanceDate.key(_start!))}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(start: false),
              icon: const Icon(Icons.event_available),
              label: Text(
                _end == null
                    ? 'Last day'
                    : 'To ${leaveDate(AttendanceDate.key(_end!))}',
              ),
            ),
          ],
        ),
        if (canPickHalf) ...[
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<HalfDay>(
            isExpanded: true,
            value: _half,
            decoration: const InputDecoration(labelText: 'Session'),
            items: [
              for (final h in HalfDay.values)
                DropdownMenuItem(value: h, child: Text(h.displayName)),
            ],
            onChanged: (v) => setState(() => _half = v ?? HalfDay.none),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _reason,
          maxLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: type?.requiresReason == false
                ? 'Reason (optional)'
                : 'Reason',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Documents(
          required: type?.requiresDocument ?? false,
          files: _uploaded,
          uploading: _uploading,
          canAdd: _uploaded.length < LeaveWorkflow.maxAttachments,
          onAdd: _addFile,
          readOnlyExisting: widget.resubmitting?.attachments.length ?? 0,
        ),
        const SizedBox(height: AppSpacing.md),
        _PlanSummary(plan: plan, type: type),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed:
                (_saving || _uploading || !plan.canSubmit || type == null)
                ? null
                : () => _submit(plan, type),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(
              widget.resubmitting != null ? 'Resubmit' : 'Submit application',
            ),
          ),
        ),
      ],
    );
  }
}

class _Documents extends StatelessWidget {
  final bool required;
  final List<LeaveAttachment> files;
  final bool uploading;
  final bool canAdd;
  final VoidCallback onAdd;
  final int readOnlyExisting;

  const _Documents({
    required this.required,
    required this.files,
    required this.uploading,
    required this.canAdd,
    required this.onAdd,
    required this.readOnlyExisting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              required
                  ? 'Supporting document (required)'
                  : 'Supporting document (optional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            TextButton.icon(
              onPressed: canAdd && !uploading ? onAdd : null,
              icon: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: const Text('Attach'),
            ),
          ],
        ),
        Text(
          'PDF, JPEG or PNG, up to 5 MB each, at most '
          '${LeaveWorkflow.maxAttachments} files. Only you and the school '
          'office can open them.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final f in files)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(f.name, overflow: TextOverflow.ellipsis),
            subtitle: Text('${(f.sizeBytes / 1024).ceil()} KB'),
          ),
      ],
    );
  }
}

class _PlanSummary extends StatelessWidget {
  final SubmissionPlan plan;
  final LeaveType? type;

  const _PlanSummary({required this.plan, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = plan.span;
    final skipped = span?.skipped ?? const {};
    return Card(
      margin: EdgeInsets.zero,
      color: plan.error != null && span != null
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (span != null && span.isValid)
              Text(
                'This application counts as ${LeaveUnits.formatDays(span.units)}.',
                style: theme.textTheme.titleSmall,
              )
            else
              Text(
                plan.error ?? 'Choose the dates.',
                style: theme.textTheme.bodyMedium,
              ),
            if (span != null && span.isValid && plan.error != null) ...[
              const SizedBox(height: 4),
              Text(
                plan.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (plan.warning != null) ...[
              const SizedBox(height: 4),
              Text(plan.warning!, style: theme.textTheme.bodySmall),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Not counted: ${skipped.entries.map((e) => '${leaveDate(e.key)} (${e.value})').join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (plan.figures != null) ...[
              const SizedBox(height: 4),
              Text(
                'Available: ${LeaveUnits.formatDays(plan.figures!.available)} '
                'of ${LeaveUnits.formatDays(plan.figures!.accrued + plan.figures!.carryForward + plan.figures!.adjustments)} '
                '(${LeaveUnits.formatDays(plan.figures!.consumed)} used).',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
