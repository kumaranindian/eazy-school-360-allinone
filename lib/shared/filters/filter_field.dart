import 'package:flutter/material.dart';

/// One filter of a list page, as [FilterBar] needs to see it: a label, what
/// is currently applied (for the chips and the count), how to clear it, and
/// the control that edits it.
///
/// It is deliberately not generic so a page can hand [FilterBar] a mixed list
/// (a status filter, a department filter, ...) without casts; the typed part
/// is captured inside [FilterField.dropdown].
class FilterField {
  final String label;

  /// Display text of the applied value, or null when the filter is at its
  /// default ("All ...") and so does not count as active.
  final String? appliedLabel;

  /// Resets this filter to its default.
  final VoidCallback onClear;

  /// Builds the editing control. [enabled] is false while filters are paused
  /// (searching).
  final Widget Function(BuildContext context, bool enabled) controlBuilder;

  const FilterField({
    required this.label,
    required this.appliedLabel,
    required this.onClear,
    required this.controlBuilder,
  });

  bool get isApplied => appliedLabel != null;

  /// A dropdown filter. A `null` option value means "not filtered": it is
  /// the default, is what [onClear] selects, and never shows as a chip.
  ///
  /// A null [onChanged] shows the control disabled. Set [countsAsFilter] to
  /// false for a control that picks context rather than narrowing the list
  /// (an academic year): it still appears, but never as a chip or in the
  /// "Filters · n" count.
  static FilterField dropdown<T>({
    required String label,
    required T? value,
    required List<(T?, String)> options,
    required ValueChanged<T?>? onChanged,
    bool countsAsFilter = true,
  }) {
    String? applied;
    if (countsAsFilter && value != null) {
      for (final (v, text) in options) {
        if (v == value) applied = text;
      }
    }
    return FilterField(
      label: label,
      appliedLabel: applied,
      onClear: () => onChanged?.call(null),
      controlBuilder: (context, enabled) => DropdownButtonFormField<T?>(
        isExpanded: true,
        value: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final (v, text) in options)
            DropdownMenuItem<T?>(
              value: v,
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
