import 'admission_enquiry.dart';
import 'admission_status.dart';

/// What the enquiry list is filtered by. All fields optional.
class EnquiryFilters {
  final AdmissionStatus? status;
  final String? academicYearId;
  final String? classId;
  final String? source;
  final String? assignedTo;

  /// yyyy-mm-dd bounds on the enquiry date, inclusive.
  final String? fromDate;
  final String? toDate;

  const EnquiryFilters({
    this.status,
    this.academicYearId,
    this.classId,
    this.source,
    this.assignedTo,
    this.fromDate,
    this.toDate,
  });

  bool get isEmpty =>
      status == null &&
      academicYearId == null &&
      classId == null &&
      source == null &&
      assignedTo == null &&
      fromDate == null &&
      toDate == null;

  EnquiryFilters copyWith({
    Object? status = _keep,
    Object? academicYearId = _keep,
    Object? classId = _keep,
    Object? source = _keep,
    Object? assignedTo = _keep,
    Object? fromDate = _keep,
    Object? toDate = _keep,
  }) => EnquiryFilters(
    status: identical(status, _keep) ? this.status : status as AdmissionStatus?,
    academicYearId: identical(academicYearId, _keep)
        ? this.academicYearId
        : academicYearId as String?,
    classId: identical(classId, _keep) ? this.classId : classId as String?,
    source: identical(source, _keep) ? this.source : source as String?,
    assignedTo: identical(assignedTo, _keep)
        ? this.assignedTo
        : assignedTo as String?,
    fromDate: identical(fromDate, _keep) ? this.fromDate : fromDate as String?,
    toDate: identical(toDate, _keep) ? this.toDate : toDate as String?,
  );

  static const Object _keep = Object();
}

/// How a typed search is understood.
enum EnquirySearchKind { name, phone, number }

class EnquirySearch {
  final EnquirySearchKind kind;

  /// The normalised value to query: lower-case name prefix, digits of a
  /// mobile number, or the upper-case enquiry number.
  final String value;
  const EnquirySearch(this.kind, this.value);

  /// Classifies [raw]: an enquiry number (`ENQ-2026-00001`, a prefix and a
  /// digit run), a mobile number (seven or more digits), otherwise a name
  /// prefix. Returns null for an empty box.
  static EnquirySearch? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'^[A-Za-z]{2,6}-\d{4}-\d+$').hasMatch(text)) {
      return EnquirySearch(EnquirySearchKind.number, text.toUpperCase());
    }
    final digits = text.replaceAll(RegExp(r'\D'), '');
    final onlyPhoneChars = RegExp(r'^[\d\s+()-]+$').hasMatch(text);
    if (onlyPhoneChars && digits.length >= 7) {
      return EnquirySearch(
        EnquirySearchKind.phone,
        digits.length > 10 ? digits.substring(digits.length - 10) : digits,
      );
    }
    return EnquirySearch(
      EnquirySearchKind.name,
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
    );
  }
}

/// Splits [EnquiryFilters] into the ONE equality filter sent to Firestore and
/// the rest, applied in memory to each fetched page. Firestore needs a
/// composite index per equality-filter combination; with one server-side
/// filter plus the date order, the index set stays small and bounded
/// (`firestore.indexes.json`) while every combination of filters still works.
class EnquiryQueryPlan {
  /// Field name and value of the server-side equality filter, if any.
  final (String field, Object value)? server;
  final bool Function(AdmissionEnquiry) clientTest;

  const EnquiryQueryPlan(this.server, this.clientTest);

  /// Server-side filter priority: the most selective first.
  static EnquiryQueryPlan of(EnquiryFilters f) {
    (String, Object)? server;
    bool Function(AdmissionEnquiry) test = (_) => true;
    void need(bool Function(AdmissionEnquiry) t) {
      final prev = test;
      test = (e) => prev(e) && t(e);
    }

    void pick(String field, Object? value, bool Function(AdmissionEnquiry) t) {
      if (value == null) return;
      if (server == null) {
        server = (field, value);
      } else {
        need(t);
      }
    }

    pick('assignedTo', f.assignedTo, (e) => e.assignedTo == f.assignedTo);
    pick('status', f.status?.wire, (e) => e.status == f.status);
    pick(
      'interestedClassId',
      f.classId,
      (e) => e.interestedClassId == f.classId,
    );
    pick(
      'academicYearId',
      f.academicYearId,
      (e) => e.academicYearId == f.academicYearId,
    );
    pick('source', f.source, (e) => e.source == f.source);
    final from = f.fromDate;
    final to = f.toDate;
    if (from != null) need((e) => e.enquiryDate.compareTo(from) >= 0);
    if (to != null) need((e) => e.enquiryDate.compareTo(to) <= 0);
    return EnquiryQueryPlan(server, test);
  }
}
