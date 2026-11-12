import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../domain/public_portal.dart';
import '../providers/admission_providers.dart';
import '../providers/public_portal_providers.dart';

/// `/admission/{slug}`: the school's public enquiry form. Open to anyone, no
/// sign-in; the server decides which school and branch it belongs to.
class PublicEnquiryPage extends ConsumerWidget {
  final String slug;
  const PublicEnquiryPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(publicPortalProvider(slug));
    return Scaffold(
      appBar: AppBar(
        title: Text(info.value?.schoolName ?? 'Admission enquiry'),
      ),
      body: SafeArea(
        child: info.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(userMessageFor(e), textAlign: TextAlign.center),
            ),
          ),
          data: (p) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _EnquiryForm(slug: slug, info: p),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnquiryForm extends ConsumerStatefulWidget {
  final String slug;
  final PublicPortalInfo info;
  const _EnquiryForm({required this.slug, required this.info});

  @override
  ConsumerState<_EnquiryForm> createState() => _EnquiryFormState();
}

class _EnquiryFormState extends ConsumerState<_EnquiryForm> {
  final _form = GlobalKey<FormState>();
  // One id per form: pressing Send twice or retrying never sends two enquiries.
  final _requestId = AdmissionWriteController.newRequestId();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _guardian = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _dob = TextEditingController();
  String? _gender;
  String? _yearId;
  String? _classId;
  String _relationship = 'Mother';
  bool _consent = false;
  bool _busy = false;
  String? _error;
  String? _reference;

  @override
  void dispose() {
    for (final c in [_first, _last, _guardian, _phone, _email, _dob]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 5),
      firstDate: DateTime(now.year - 25),
      lastDate: now,
    );
    if (d == null) return;
    _dob.text =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_consent) {
      setState(() => _error = 'Please tick the box to agree before sending.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reference = await ref
          .read(publicAdmissionRepositoryProvider)
          .submit(
            slug: widget.slug,
            requestId: _requestId,
            consentVersion: widget.info.consentVersion,
            input: PublicEnquiryInput(
              firstName: _first.text.trim(),
              lastName: _last.text.trim(),
              dateOfBirth: _dob.text.trim().isEmpty ? null : _dob.text.trim(),
              gender: _gender,
              academicYearId: _yearId!,
              classId: _classId!,
              guardianName: _guardian.text.trim(),
              guardianPhone: _phone.text.trim(),
              guardianEmail: _email.text.trim().isEmpty
                  ? null
                  : _email.text.trim(),
              relationship: _relationship,
            ),
          );
      if (mounted) setState(() => _reference = reference);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final info = widget.info;
    if (_reference != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Thank you. We have your enquiry.',
            style: t.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (_reference!.isNotEmpty)
            Text(
              'Your reference is $_reference. The school will contact you.',
              textAlign: TextAlign.center,
            )
          else
            const Text(
              'The school will contact you.',
              textAlign: TextAlign.center,
            ),
        ],
      );
    }
    final classes = info.years
        .where((y) => y.id == _yearId)
        .expand((y) => y.classes)
        .toList();
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (info.introText.isNotEmpty) ...[
            Text(info.introText, style: t.bodyLarge),
            const SizedBox(height: 16),
          ],
          Text('Student', style: t.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'First name *'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the first name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Last name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _dob,
            readOnly: true,
            onTap: _pickDob,
            decoration: const InputDecoration(
              labelText: 'Date of birth',
              suffixIcon: Icon(Icons.calendar_today_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _gender,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
              DropdownMenuItem(value: 'MALE', child: Text('Male')),
              DropdownMenuItem(value: 'OTHER', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _yearId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Academic year *'),
            items: [
              for (final y in info.years)
                DropdownMenuItem(value: y.id, child: Text(y.name)),
            ],
            onChanged: (v) => setState(() {
              _yearId = v;
              _classId = null;
            }),
            validator: (v) => v == null ? 'Choose the academic year' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _classId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Class *'),
            items: [
              for (final c in classes)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _classId = v),
            validator: (v) => v == null ? 'Choose the class' : null,
          ),
          const SizedBox(height: 20),
          Text('Parent or guardian', style: t.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _guardian,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name *'),
            validator: (v) =>
                (v ?? '').trim().length < 2 ? 'Enter your name' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _relationship,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Relationship'),
            items: const [
              DropdownMenuItem(value: 'Mother', child: Text('Mother')),
              DropdownMenuItem(value: 'Father', child: Text('Father')),
              DropdownMenuItem(value: 'Guardian', child: Text('Guardian')),
            ],
            onChanged: (v) => setState(() => _relationship = v ?? 'Mother'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number *'),
            validator: (v) {
              final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return d.length < 7 || d.length > 15
                  ? 'Enter a valid mobile number'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) {
              final s = (v ?? '').trim();
              return s.isEmpty ||
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                  ? null
                  : 'Enter a valid email';
            },
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: Text(info.consentText),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send enquiry'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
