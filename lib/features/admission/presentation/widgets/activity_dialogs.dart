import 'package:flutter/material.dart';

import '../../../../core/regional/school_time.dart';
import '../../domain/admission_activity.dart';
import '../providers/admission_providers.dart';
import 'admission_widgets.dart';
import 'activity_widgets.dart';

String _iso(DateTime d) => SchoolTime.keyOf(d);

/// A date field that opens the picker. [first] is the earliest pickable date.
class _DateField extends StatelessWidget {
  final String label;
  final String? value;
  final DateTime first;
  final ValueChanged<String> onPicked;
  final String? errorText;

  const _DateField({
    required this.label,
    required this.value,
    required this.first,
    required this.onPicked,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final initial = DateTime.tryParse(value ?? '') ?? first;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial.isBefore(first) ? first : initial,
          firstDate: first,
          lastDate: DateTime(first.year + 3),
        );
        if (picked != null) onPicked(_iso(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value == null ? 'Select date' : shortDate(value)),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _TimeField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parts = (value ?? '10:00').split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 10,
            minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
          ),
        );
        if (picked != null) {
          onChanged(
            '${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Time (optional)',
          suffixIcon: value == null
              ? const Icon(Icons.schedule, size: 18)
              : IconButton(
                  tooltip: 'Clear time',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(value == null ? 'Any time' : timeText(value)),
      ),
    );
  }
}

/// Result of the schedule dialog.
typedef ScheduleResult = ActivityInput;

/// Plan a follow-up: type, date, optional time, who, remarks. Used both to
/// schedule a new activity and to plan "the next contact" when completing one.
class ScheduleActivityDialog extends StatefulWidget {
  final String title;
  final List<Assignee> people;

  /// The enquiry's assignee, offered as the default.
  final String? defaultAssignee;
  final bool askWho;

  /// Book a school visit: the type is fixed and a purpose is asked for.
  final bool visit;

  const ScheduleActivityDialog({
    super.key,
    required this.people,
    this.title = 'Schedule follow-up',
    this.defaultAssignee,
    this.askWho = true,
    this.visit = false,
  });

  @override
  State<ScheduleActivityDialog> createState() => _ScheduleActivityDialogState();
}

class _ScheduleActivityDialogState extends State<ScheduleActivityDialog> {
  ActivityType _type = ActivityType.phoneCall;
  VisitPurpose _purpose = VisitPurpose.campusTour;
  String? _date;
  String? _time;
  String? _who;
  bool _whoTouched = false;
  final _remarks = TextEditingController();
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    _who = widget.defaultAssignee;
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  void _submit() {
    if (_date == null) {
      setState(() => _tried = true);
      return;
    }
    final remarks = _remarks.text.trim();
    Navigator.pop(
      context,
      ActivityInput(
        type: widget.visit ? ActivityType.schoolVisit : _type,
        purpose: widget.visit ? _purpose : null,
        scheduledDate: _date!,
        scheduledTime: _time,
        remarks: remarks.isEmpty ? null : remarks,
        assignExplicitly: widget.askWho && _whoTouched,
        assignedTo: _who,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = SchoolTime.today();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.visit)
                DropdownButtonFormField<VisitPurpose>(
                  value: _purpose,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Purpose *'),
                  items: [
                    for (final p in VisitPurpose.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) => setState(() => _purpose = v ?? _purpose),
                )
              else
                DropdownButtonFormField<ActivityType>(
                  value: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    // Visits have their own booking (they also move the
                    // enquiry's status).
                    for (final t in ActivityType.values)
                      if (t != ActivityType.schoolVisit)
                        DropdownMenuItem(
                          value: t,
                          child: Row(
                            children: [
                              Icon(activityIcon(t), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              const SizedBox(height: 12),
              _DateField(
                label: 'Date *',
                value: _date,
                first: today,
                errorText: _tried && _date == null ? 'Pick a date' : null,
                onPicked: (v) => setState(() => _date = v),
              ),
              const SizedBox(height: 12),
              _TimeField(
                value: _time,
                onChanged: (v) => setState(() => _time = v),
              ),
              if (widget.askWho) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: widget.people.any((p) => p.userId == _who)
                      ? _who
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Assigned to'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    for (final p in widget.people)
                      DropdownMenuItem<String?>(
                        value: p.userId,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _who = v;
                    _whoTouched = true;
                  }),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _remarks,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.visit ? 'Book visit' : 'Schedule'),
        ),
      ],
    );
  }
}

class CompleteResult {
  final ActivityCompletion completion;
  final ActivityInput? next;
  const CompleteResult(this.completion, this.next);
}

/// Record the outcome of a follow-up, and optionally plan the next one.
class CompleteActivityDialog extends StatefulWidget {
  final AdmissionActivity activity;
  const CompleteActivityDialog({super.key, required this.activity});

  @override
  State<CompleteActivityDialog> createState() => _CompleteActivityDialogState();
}

class _CompleteActivityDialogState extends State<CompleteActivityDialog> {
  final _outcome = TextEditingController();
  final _feedback = TextEditingController();
  final _remarks = TextEditingController();
  bool _planNext = false;
  ActivityType _nextType = ActivityType.phoneCall;
  String? _nextDate;
  bool _tried = false;

  @override
  void dispose() {
    _outcome.dispose();
    _feedback.dispose();
    _remarks.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    final outcomeOk = _outcome.text.trim().length >= 3;
    final nextOk = !_planNext || _nextDate != null;
    if (!outcomeOk || !nextOk) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(
      context,
      CompleteResult(
        ActivityCompletion(
          outcome: _outcome.text.trim(),
          parentFeedback: _clean(_feedback),
          remarks: _clean(_remarks),
        ),
        _planNext
            ? ActivityInput(type: _nextType, scheduledDate: _nextDate!)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = SchoolTime.today();
    return AlertDialog(
      title: Text(
        widget.activity.isVisit
            ? 'Complete visit'
            : 'Complete ${widget.activity.type.label.toLowerCase()}',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _outcome,
                maxLength: 500,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.activity.isVisit
                      ? 'Visit notes *'
                      : 'Outcome *',
                  helperText: widget.activity.isVisit
                      ? 'What did the family see and say?'
                      : 'What happened?',
                  errorText: _tried && _outcome.text.trim().length < 3
                      ? 'Please describe the outcome'
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _feedback,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Parent feedback (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _remarks,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Internal remarks (optional)',
                  helperText: 'Never shown to parents',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Plan the next contact'),
                value: _planNext,
                onChanged: (v) => setState(() => _planNext = v),
              ),
              if (_planNext) ...[
                DropdownButtonFormField<ActivityType>(
                  value: _nextType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Next type'),
                  items: [
                    for (final t in ActivityType.values)
                      if (t != ActivityType.schoolVisit)
                        DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _nextType = v ?? _nextType),
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'Next date *',
                  value: _nextDate,
                  first: today,
                  errorText: _tried && _nextDate == null ? 'Pick a date' : null,
                  onPicked: (v) => setState(() => _nextDate = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Mark completed')),
      ],
    );
  }
}

typedef RescheduleResult = ({String date, String? time, String? reason});

/// Move an open activity to another date; the old date stays in its history.
class RescheduleActivityDialog extends StatefulWidget {
  final AdmissionActivity activity;
  const RescheduleActivityDialog({super.key, required this.activity});

  @override
  State<RescheduleActivityDialog> createState() =>
      _RescheduleActivityDialogState();
}

class _RescheduleActivityDialogState extends State<RescheduleActivityDialog> {
  String? _date;
  String? _time;
  final _reason = TextEditingController();
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    _time = widget.activity.scheduledTime;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reschedule'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Currently ${shortDate(widget.activity.scheduledDate)}'
                '${widget.activity.scheduledTime == null ? '' : ' · ${timeText(widget.activity.scheduledTime)}'}.',
              ),
              const SizedBox(height: 12),
              _DateField(
                label: 'New date *',
                value: _date,
                first: SchoolTime.today(),
                errorText: _tried && _date == null ? 'Pick a date' : null,
                onPicked: (v) => setState(() => _date = v),
              ),
              const SizedBox(height: 12),
              _TimeField(
                value: _time,
                onChanged: (v) => setState(() => _time = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_date == null) {
              setState(() => _tried = true);
              return;
            }
            final r = _reason.text.trim();
            Navigator.pop<RescheduleResult>(context, (
              date: _date!,
              time: _time,
              reason: r.isEmpty ? null : r,
            ));
          },
          child: const Text('Reschedule'),
        ),
      ],
    );
  }
}

/// Ask for a required reason (cancelling a follow-up).
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String action,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(title: title, action: action),
);

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String action;
  const _ReasonDialog({required this.title, required this.action});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _reason.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _reason,
        maxLength: 200,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Reason *'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: ok
              ? () => Navigator.pop(context, _reason.text.trim())
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
