import 'package:intl/intl.dart';

/// Shared date display format for this app (`dd/MM/yyyy`) — matches
/// `AcademicSettings.dateFormat`'s default. Centralized so every
/// date-picker field (academic years, holidays, ...) renders consistently
/// instead of each dialog hand-rolling its own `'${d.day}/${d.month}...'`.
final DateFormat _displayDateFormat = DateFormat('dd/MM/yyyy');

String formatDisplayDate(DateTime date) => _displayDateFormat.format(date);
