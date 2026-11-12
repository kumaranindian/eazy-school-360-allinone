import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_application.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_settings.dart';
import '../providers/admission_providers.dart';
import '../providers/document_picker.dart';
import 'activity_dialogs.dart';
import 'admission_widgets.dart';
import 'application_widgets.dart';
import 'conversion_card.dart';

/// The application of one enquiry: start it, edit the draft, submit, take it
/// into review, approve or reject (where allowed), and add review comments.
class ApplicationTab extends ConsumerStatefulWidget {
  final AdmissionEnquiry enquiry;
  final EnquiryKey keyData;
  final AdmissionSettings settings;
  const ApplicationTab({
    super.key,
    required this.enquiry,
    required this.keyData,
    required this.settings,
  });

  @override
  ConsumerState<ApplicationTab> createState() => _ApplicationTabState();
}

class _ApplicationTabState extends ConsumerState<ApplicationTab> {
  EnquiryKey get _k => widget.keyData;

  Future<void> _run(Future<bool> Function() action, String done) async {
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      ref.invalidate(applicationHistoryProvider);
      ref.invalidate(enquiryDocumentsProvider);
      ref.invalidate(applicationCountsProvider);
      context.showSnackBar(done);
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'That did not work.' : userMessageFor(err),
        isError: true,
      );
    }
  }

  AdmissionWriteController get _c =>
      ref.read(admissionWriteControllerProvider.notifier);

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _start() => _run(
    () => _c.createApplication(
      schoolId: _k.schoolId,
      branchId: _k.branchId,
      enquiryId: _k.enquiryId,
    ),
    'Application started.',
  );

  Future<void> _submit(AdmissionApplication a) async {
    if (!await _confirm(
      'Submit this application?',
      'It can no longer be edited after submission. The enquiry moves to '
          '"Application submitted".',
      'Submit',
    )) {
      return;
    }
    await _run(
      () => _c.submitApplication(
        schoolId: _k.schoolId,
        branchId: _k.branchId,
        application: a,
      ),
      'Application submitted.',
    );
  }

  Future<void> _startReview(AdmissionApplication a) => _run(
    () => _c.reviewApplication(
      schoolId: _k.schoolId,
      branchId: _k.branchId,
      application: a,
      action: 'START',
    ),
    'Review started.',
  );

  Future<void> _comment(AdmissionApplication a) async {
    final text = await askReason(
      context,
      title: 'Review comment',
      action: 'Add comment',
      label: 'Comment *',
    );
    if (text == null || !mounted) return;
    await _run(
      () => _c.reviewApplication(
        schoolId: _k.schoolId,
        branchId: _k.branchId,
        application: a,
        action: 'COMMENT',
        comment: text,
      ),
      'Comment added.',
    );
  }

  Future<void> _approve(AdmissionApplication a) async {
    if (!await _confirm(
      'Approve this application?',
      'All required documents must be verified. The enquiry moves to '
          '"Approved".',
      'Approve',
    )) {
      return;
    }
    await _run(
      () => _c.decideApplication(
        schoolId: _k.schoolId,
        branchId: _k.branchId,
        application: a,
        decision: 'APPROVE',
      ),
      'Application approved.',
    );
  }

  Future<void> _reject(AdmissionApplication a) async {
    final reason = await askReason(
      context,
      title: 'Reject this application?',
      action: 'Reject application',
      label: 'Reason *',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => _c.decideApplication(
        schoolId: _k.schoolId,
        branchId: _k.branchId,
        application: a,
        decision: 'REJECT',
        comment: reason,
      ),
      'Application rejected.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(applicationProvider(_k));
    final busy = ref.watch(admissionWriteControllerProvider).isLoading;
    final tenant = ref.watch(tenantContextProvider).value;
    final canDecide =
        tenant != null &&
        (tenant.can(Permission.decideAdmissions) ||
            (tenant.can(Permission.manageAdmissions) &&
                widget.settings.branchAdminsMayApprove));
    return app.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ParentsCard(child: Text(userMessageFor(e))),
      data: (a) {
        if (a == null) return _noApplication(busy);
        return _Application(
          application: a,
          keyData: _k,
          settings: widget.settings,
          canDecide: canDecide,
          busy: busy,
          onSubmit: () => _submit(a),
          onStartReview: () => _startReview(a),
          onApprove: () => _approve(a),
          onReject: () => _reject(a),
          onComment: () => _comment(a),
        );
      },
    );
  }

  Widget _noApplication(bool busy) {
    final can = widget.enquiry.status.canStartApplication;
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ParentsSectionTitle(
            icon: Icons.description_outlined,
            title: 'No application yet',
          ),
          const SizedBox(height: 8),
          Text(
            can
                ? 'Start an application when the family decides to apply. It '
                      'copies the details from this enquiry and gets its own '
                      'application number.'
                : widget.enquiry.status.isClosed
                ? 'This enquiry is closed.'
                : 'An application can be started once the enquiry is '
                      'Interested, or has a visit booked or completed '
                      '(currently ${widget.enquiry.status.label}).',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: can && !busy ? _start : null,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Start application'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Application extends ConsumerWidget {
  final AdmissionApplication application;
  final EnquiryKey keyData;
  final AdmissionSettings settings;
  final bool canDecide;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onStartReview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onComment;

  const _Application({
    required this.application,
    required this.keyData,
    required this.settings,
    required this.canDecide,
    required this.busy,
    required this.onSubmit,
    required this.onStartReview,
    required this.onApprove,
    required this.onReject,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    final a = application;
    final classes =
        ref
            .watch(
              classesProvider((
                schoolId: keyData.schoolId,
                branchId: keyData.branchId,
                academicYearId: a.academicYearId,
              )),
            )
            .value ??
        const [];
    final years =
        ref
            .watch(
              academicYearsProvider((
                schoolId: keyData.schoolId,
                branchId: keyData.branchId,
              )),
            )
            .value ??
        const [];
    final cls = classes
        .where((c) => c.classId == a.classId)
        .map((c) => c.name)
        .firstOrNull;
    final year = years
        .where((y) => y.academicYearId == a.academicYearId)
        .map((y) => y.name)
        .firstOrNull;
    final guardian = a.guardians.isEmpty ? null : a.guardians.first;
    final actions = <Widget>[
      if (a.status == ApplicationStatus.draft) ...[
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => context.push(
                  '/admissions/enquiries/${a.enquiryId}/application/edit',
                ),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit details'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Submit application'),
        ),
      ],
      if (a.status == ApplicationStatus.submitted)
        FilledButton.icon(
          onPressed: busy ? null : onStartReview,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Start review'),
        ),
      if (a.status == ApplicationStatus.underReview && canDecide) ...[
        FilledButton.icon(
          onPressed: busy ? null : onApprove,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Approve'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onReject,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Reject'),
        ),
      ],
      if (a.status == ApplicationStatus.submitted ||
          a.status == ApplicationStatus.underReview)
        OutlinedButton.icon(
          onPressed: busy ? null : onComment,
          icon: const Icon(Icons.comment_outlined),
          label: const Text('Add comment'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParentsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    a.applicationNumber,
                    style: t.titleLarge?.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  ApplicationStatusBadge(a.status),
                ],
              ),
              if (a.status == ApplicationStatus.underReview && !canDecide) ...[
                const SizedBox(height: 6),
                Text(
                  'A school administrator decides this application.',
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              if (a.decisionComment != null) ...[
                const SizedBox(height: 6),
                Text('Decision note: ${a.decisionComment}'),
              ],
              const SizedBox(height: 8),
              ParentsFactRow(
                icon: Icons.child_care_outlined,
                label: 'Student',
                text: a.studentName,
              ),
              if (a.dateOfBirth != null)
                ParentsFactRow(
                  icon: Icons.cake_outlined,
                  label: 'Date of birth',
                  text: shortDate(a.dateOfBirth),
                ),
              ParentsFactRow(
                icon: Icons.class_outlined,
                label: 'Class and year',
                text: [
                  if (cls != null) 'Class $cls',
                  if (year != null) year,
                ].join(' · '),
              ),
              if (guardian != null)
                ParentsFactRow(
                  icon: Icons.family_restroom_outlined,
                  label: 'Parent / guardian',
                  text: '${guardian.name} · ${guardian.phone}',
                ),
              if (a.submissionNotes != null)
                ParentsFactRow(
                  icon: Icons.notes_outlined,
                  label: 'Notes',
                  text: a.submissionNotes!,
                ),
              if (a.submittedAt != null)
                ParentsFactRow(
                  icon: Icons.send_outlined,
                  label: 'Submitted',
                  text: shortDate(
                    '${a.submittedAt!.toLocal().year}-'
                    '${a.submittedAt!.toLocal().month.toString().padLeft(2, '0')}-'
                    '${a.submittedAt!.toLocal().day.toString().padLeft(2, '0')}',
                  ),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
        if (a.status == ApplicationStatus.approved) ...[
          const SizedBox(height: 12),
          ConversionCard(
            application: a,
            keyData: keyData,
            canConvert: canDecide,
          ),
        ],
      ],
    );
  }
}

/// The documents of an application, by type, with upload, view, verify,
/// reject and remove. A progress line says how many required documents are
/// still not verified.
class DocumentsTab extends ConsumerStatefulWidget {
  final EnquiryKey keyData;
  final AdmissionSettings settings;
  const DocumentsTab({
    super.key,
    required this.keyData,
    required this.settings,
  });

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  EnquiryKey get _k => widget.keyData;
  String? _uploadingType;

  AdmissionWriteController get _c =>
      ref.read(admissionWriteControllerProvider.notifier);

  void _report(bool ok, String done) {
    if (!mounted) return;
    if (ok) {
      ref.invalidate(enquiryDocumentsProvider(_k));
      ref.invalidate(applicationHistoryProvider);
      context.showSnackBar(done);
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      // A failed upload may still have created the record; refresh the list.
      ref.invalidate(enquiryDocumentsProvider(_k));
      context.showSnackBar(
        err == null ? 'That did not work.' : userMessageFor(err),
        isError: true,
      );
    }
  }

  Future<void> _upload(String type) async {
    final picked = await ref
        .read(documentPickerProvider)
        .pick(photoOnly: photoDocumentTypes.contains(type));
    if (picked == null || !mounted) return;
    setState(() => _uploadingType = type);
    final ok = await _c.uploadDocument(
      schoolId: _k.schoolId,
      branchId: _k.branchId,
      enquiryId: _k.enquiryId,
      type: type,
      fileName: picked.name,
      bytes: picked.bytes,
    );
    if (mounted) setState(() => _uploadingType = null);
    _report(ok, 'Document uploaded.');
  }

  Future<void> _verify(AdmissionDocument d) async {
    final ok = await _c.verifyDocument(
      schoolId: _k.schoolId,
      branchId: _k.branchId,
      enquiryId: _k.enquiryId,
      document: d,
      verify: true,
    );
    _report(ok, 'Document verified.');
  }

  Future<void> _reject(AdmissionDocument d) async {
    final reason = await askReason(
      context,
      title: 'Reject this document?',
      action: 'Reject document',
      label: 'Reason *',
    );
    if (reason == null || !mounted) return;
    final ok = await _c.verifyDocument(
      schoolId: _k.schoolId,
      branchId: _k.branchId,
      enquiryId: _k.enquiryId,
      document: d,
      verify: false,
      reason: reason,
    );
    _report(ok, 'Document rejected.');
  }

  Future<void> _remove(AdmissionDocument d) async {
    final reason = await askReason(
      context,
      title: 'Remove this document?',
      action: 'Remove document',
      label: 'Reason (optional)',
      required: false,
    );
    if (reason == null || !mounted) return;
    final ok = await _c.removeDocument(
      schoolId: _k.schoolId,
      branchId: _k.branchId,
      enquiryId: _k.enquiryId,
      document: d,
      reason: reason.isEmpty ? null : reason,
    );
    _report(ok, 'Document removed.');
  }

  Future<void> _view(AdmissionDocument d) => showDialog<void>(
    context: context,
    builder: (_) => DocumentViewerDialog(document: d),
  );

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(applicationProvider(_k));
    final docs = ref.watch(enquiryDocumentsProvider(_k));
    final busy = ref.watch(admissionWriteControllerProvider).isLoading;
    final p = AdminDashboardPalette.of(context);
    final application = app.value;
    if (app.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (application == null) {
      return const ParentsCard(
        child: Text('Start the application first; documents belong to it.'),
      );
    }
    final open = application.status.isOpen;
    final types = widget.settings.documentTypes;
    final required = widget.settings.requiredDocumentTypes.toSet();
    return docs.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ParentsCard(child: Text(userMessageFor(e))),
      data: (all) {
        final listed = all.where((d) => d.status.isListed).toList();
        final verifiedTypes = {
          for (final d in listed)
            if (d.status == DocumentStatus.verified) d.type,
        };
        final missing = [
          for (final r in widget.settings.requiredDocumentTypes)
            if (!verifiedTypes.contains(r)) types[r] ?? r,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ParentsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ParentsSectionTitle(
                    icon: Icons.folder_open_outlined,
                    title: 'Required documents',
                  ),
                  const SizedBox(height: 6),
                  if (required.isEmpty)
                    const Text('This school requires no documents.')
                  else if (missing.isEmpty)
                    Text(
                      'All ${required.length} required documents are verified.',
                      style: TextStyle(color: p.success),
                    )
                  else
                    Text(
                      '${required.length - missing.length} of ${required.length} '
                      'required documents verified. Still needed: '
                      '${missing.join(', ')}.',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in types.entries) ...[
              _TypeCard(
                typeKey: entry.key,
                label: entry.value,
                required: required.contains(entry.key),
                documents: [
                  for (final d in listed)
                    if (d.type == entry.key) d,
                ],
                open: open,
                busy: busy,
                uploading: _uploadingType == entry.key,
                onUpload: () => _upload(entry.key),
                onView: _view,
                onVerify: _verify,
                onReject: _reject,
                onRemove: _remove,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String typeKey;
  final String label;
  final bool required;
  final List<AdmissionDocument> documents;
  final bool open;
  final bool busy;
  final bool uploading;
  final VoidCallback onUpload;
  final void Function(AdmissionDocument) onView;
  final void Function(AdmissionDocument) onVerify;
  final void Function(AdmissionDocument) onReject;
  final void Function(AdmissionDocument) onRemove;

  const _TypeCard({
    required this.typeKey,
    required this.label,
    required this.required,
    required this.documents,
    required this.open,
    required this.busy,
    required this.uploading,
    required this.onUpload,
    required this.onView,
    required this.onVerify,
    required this.onReject,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                label,
                style: t.titleMedium?.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (required)
                const ParentsBadge('Required', tone: ParentsTone.warning),
            ],
          ),
          if (documents.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Nothing uploaded yet.',
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          for (final d in documents) ...[
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  d.isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: p.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.fileName,
                        style: t.bodyLarge?.copyWith(color: p.textPrimary),
                      ),
                      Text(
                        fileSizeText(d.sizeBytes),
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                      if (d.rejectionReason != null &&
                          d.status == DocumentStatus.rejected)
                        Text(
                          'Reason: ${d.rejectionReason}',
                          style: t.bodySmall?.copyWith(color: p.warning),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DocumentStatusBadge(d.status),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => onView(d),
                  child: const Text('View'),
                ),
                if (open && d.status == DocumentStatus.uploaded) ...[
                  FilledButton.tonal(
                    onPressed: busy ? null : () => onVerify(d),
                    child: const Text('Verify'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => onReject(d),
                    child: const Text('Reject'),
                  ),
                ],
                if (open)
                  TextButton(
                    onPressed: busy ? null : () => onRemove(d),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ],
          if (open) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onUpload,
                icon: uploading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text(uploading ? 'Uploading…' : 'Upload'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows a stored document. The bytes come through the authenticated Storage
/// SDK (the rules decide who may read); no shareable link is created. Images
/// are drawn from memory, PDFs rendered in place.
class DocumentViewerDialog extends ConsumerStatefulWidget {
  final AdmissionDocument document;
  const DocumentViewerDialog({super.key, required this.document});

  @override
  ConsumerState<DocumentViewerDialog> createState() =>
      _DocumentViewerDialogState();
}

class _DocumentViewerDialogState extends ConsumerState<DocumentViewerDialog> {
  late final Future<List<int>> _bytes = ref
      .read(admissionWriteControllerProvider.notifier)
      .readDocument(widget.document);

  @override
  Widget build(BuildContext context) {
    final d = widget.document;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${d.label} · ${d.fileName}',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<int>>(
                future: _bytes,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError || snap.data == null) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snap.hasError
                            ? userMessageFor(snap.error!)
                            : 'That file could not be opened.',
                      ),
                    );
                  }
                  final bytes = Uint8List.fromList(snap.data!);
                  if (d.isImage) {
                    return InteractiveViewer(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('That image could not be shown.'),
                        ),
                      ),
                    );
                  }
                  if (d.isPdf) {
                    return SizedBox(
                      height: 520,
                      child: PdfPreview(
                        build: (_) async => bytes,
                        allowPrinting: false,
                        allowSharing: false,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This file type cannot be previewed.'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
