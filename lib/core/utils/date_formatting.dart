import '../regional/school_time.dart';

/// A calendar date in the school's date format (Regional settings;
/// `dd/MM/yyyy` until a school is signed in). Centralized so every
/// date-picker field renders consistently.
String formatDisplayDate(DateTime date) => SchoolTime.formatDate(date);

/// A moment in time - when something was applied, decided, recorded or
/// changed - as "3 Aug 2026, 4:05 PM" **in the school's time zone**, so staff
/// and parents on devices set to other zones all read the same time. Use this
/// (not [formatDisplayDate]) for every event timestamp so the time of day is
/// never dropped; `—` when the server has not stamped it yet.
String formatInstant(DateTime? at) =>
    at == null ? '—' : SchoolTime.formatInstant(at);
