import 'package:intl/intl.dart';

/// Shared date display format for this app (`dd/MM/yyyy`) — matches
/// `AcademicSettings.dateFormat`'s default. Centralized so every
/// date-picker field (academic years, holidays, ...) renders consistently
/// instead of each dialog hand-rolling its own `'${d.day}/${d.month}...'`.
final DateFormat _displayDateFormat = DateFormat('dd/MM/yyyy');

String formatDisplayDate(DateTime date) => _displayDateFormat.format(date);

final DateFormat _instantFormat = DateFormat('d MMM y, h:mm a');

/// A moment in time — when something was applied, decided, recorded or
/// changed — as "3 Aug 2026, 4:05 PM" in the viewer's local time zone. Use
/// this (not [formatDisplayDate]) for every event timestamp so the time of day
/// is never dropped; `—` when the server has not stamped it yet.
String formatInstant(DateTime? at) =>
    at == null ? '—' : _instantFormat.format(at.toLocal());
