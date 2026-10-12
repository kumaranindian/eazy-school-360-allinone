import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Lays form fields out in two columns when there is room and a single
/// column otherwise (mobile / narrow windows), without any fixed pixel
/// widths. A field that should always span the full row is wrapped in
/// [FormGrid.full].
class FormGrid extends StatelessWidget {
  final List<Widget> children;

  const FormGrid({super.key, required this.children});

  static Widget full(Widget child) => _FullWidth(child: child);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              SizedBox(
                width: child is _FullWidth ? constraints.maxWidth : itemWidth,
                child: child is _FullWidth ? child.child : child,
              ),
          ],
        );
      },
    );
  }
}

class _FullWidth extends StatelessWidget {
  final Widget child;

  const _FullWidth({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// A date picker that behaves like a form field: shows the chosen date (or a
/// prompt), reports a validation error under the field, and opens the
/// platform date picker on tap.
class DateFormField extends FormField<DateTime> {
  DateFormField({
    super.key,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onChanged,
    required String Function(DateTime date) format,
    required DateTime firstDate,
    required DateTime lastDate,
    DateTime? initialPickerDate,
    bool required = true,
  }) : super(
         initialValue: value,
         validator: (v) => required && v == null ? '$label is required.' : null,
         builder: (state) {
           final context = state.context;
           return InputDecorator(
             decoration: InputDecoration(
               labelText: label,
               errorText: state.errorText,
             ),
             child: InkWell(
               onTap: () async {
                 final picked = await showDatePicker(
                   context: context,
                   initialDate:
                       state.value ?? initialPickerDate ?? DateTime.now(),
                   firstDate: firstDate,
                   lastDate: lastDate,
                 );
                 if (picked != null) {
                   state.didChange(picked);
                   onChanged(picked);
                 }
               },
               child: Padding(
                 padding: const EdgeInsets.symmetric(vertical: 4),
                 child: Row(
                   children: [
                     Expanded(
                       child: Text(
                         state.value == null
                             ? 'Select date'
                             : format(state.value!),
                       ),
                     ),
                     const Icon(Icons.calendar_today_outlined, size: 18),
                   ],
                 ),
               ),
             ),
           );
         },
       );
}
