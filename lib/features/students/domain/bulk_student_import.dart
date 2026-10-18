import '../../../core/regional/school_time.dart';
import 'blood_group.dart';
import 'gender.dart';
import 'relationship_type.dart';

/// Bulk student upload: the CSV template, a small RFC-4180 reader/writer,
/// and row-by-row validation. Pure Dart (no Flutter / Firebase) so it is
/// unit-testable; persistence lives in `BulkStudentImporter`.

/// Upper bound per upload — keeps the preview responsive and the import to
/// a few minutes (each row is its own atomic admission).
const int bulkStudentMaxRows = 500;

/// Template columns, in order. `required` columns must be present in the
/// header AND non-empty in every row.
class BulkStudentColumn {
  final String key;

  /// Admin-facing name used in error messages.
  final String label;
  final String example;
  final String help;
  final bool required;

  const BulkStudentColumn(
    this.key,
    this.label,
    this.example,
    this.help, {
    this.required = false,
  });
}

const List<BulkStudentColumn> bulkStudentColumns = [
  BulkStudentColumn(
    'admission_number',
    'Admission number',
    'ADM-1001',
    'Unique per branch',
    required: true,
  ),
  BulkStudentColumn(
    'first_name',
    'First name',
    'Asha',
    'Student first name',
    required: true,
  ),
  BulkStudentColumn('middle_name', 'Middle name', '', 'Optional'),
  BulkStudentColumn(
    'last_name',
    'Last name',
    'Kumar',
    'Student last name',
    required: true,
  ),
  BulkStudentColumn(
    'date_of_birth',
    'Date of birth',
    '2015-06-30',
    'YYYY-MM-DD or DD/MM/YYYY',
    required: true,
  ),
  BulkStudentColumn(
    'gender',
    'Gender',
    'Female',
    'Male, Female or Other',
    required: true,
  ),
  BulkStudentColumn(
    'blood_group',
    'Blood group',
    'O+',
    'A+, A-, B+, B-, AB+, AB-, O+, O-; optional',
  ),
  BulkStudentColumn('email', 'Email', '', 'Optional'),
  BulkStudentColumn('phone', 'Phone', '', 'Optional'),
  BulkStudentColumn('address', 'Address', '', 'Optional'),
  BulkStudentColumn('city', 'City', '', 'Optional'),
  BulkStudentColumn(
    'admission_date',
    'Admission date',
    '2026-06-01',
    'YYYY-MM-DD or DD/MM/YYYY; blank = today',
  ),
  BulkStudentColumn(
    'class',
    'Class',
    'Grade 1',
    'Must match a class name in the chosen academic year',
    required: true,
  ),
  BulkStudentColumn(
    'section',
    'Section',
    'A',
    'Must match a section of that class',
    required: true,
  ),
  BulkStudentColumn('roll_number', 'Roll number', '1', 'Optional'),
  BulkStudentColumn(
    'parent_first_name',
    'Parent first name',
    'Ravi',
    'Optional; parent_last_name and parent_phone then required',
  ),
  BulkStudentColumn('parent_last_name', 'Parent last name', 'Kumar', ''),
  BulkStudentColumn(
    'parent_phone',
    'Parent phone',
    '9876543210',
    'Rows with the same phone share ONE parent record',
  ),
  BulkStudentColumn(
    'parent_relationship',
    'Parent relationship',
    'Father',
    'Father, Mother, Guardian or Other; blank = Guardian',
  ),
  BulkStudentColumn(
    'parent_email',
    'Parent email',
    'ravi@example.com',
    'Optional; saved in lowercase, used for the parent\'s login; one email per parent',
  ),
];

String _label(String key) =>
    bulkStudentColumns.firstWhere((c) => c.key == key).label;

/// The downloadable sample: header + one example row, UTF-8 BOM so Excel
/// opens it with the right encoding.
String bulkStudentTemplateCsv() {
  return '\uFEFF${encodeCsv([
    [for (final c in bulkStudentColumns) c.key],
    [for (final c in bulkStudentColumns) c.example],
  ])}';
}

// ---------------------------------------------------------------------------
// CSV reader / writer
// ---------------------------------------------------------------------------

/// Parses [input] into rows of cells. Handles a leading BOM, CRLF/LF/CR,
/// quoted cells, `""` escapes and embedded newlines. Fully blank lines are
/// skipped.
List<List<String>> parseCsv(String input) {
  var text = input;
  if (text.startsWith('﻿')) text = text.substring(1);

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var cellWasQuoted = false;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
    cellWasQuoted = false;
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"' && cell.isEmpty && !cellWasQuoted) {
      inQuotes = true;
      cellWasQuoted = true;
    } else if (ch == ',') {
      endCell();
    } else if (ch == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else if (ch == '\n') {
      endRow();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty || cellWasQuoted) endRow();
  return rows;
}

String encodeCsv(List<List<String>> rows) {
  String esc(String v) =>
      (v.contains(',') ||
          v.contains('"') ||
          v.contains('\n') ||
          v.contains('\r'))
      ? '"${v.replaceAll('"', '""')}"'
      : v;
  return rows.map((r) => r.map(esc).join(',')).join('\r\n');
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Lower-cases and collapses whitespace so "Grade  1 " matches "grade 1".
String normName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// What the sheet's class/section names resolve to for the chosen academic
/// year. Keys are [normName]d names.
class PlacementLookup {
  final Map<String, ClassPlacement> classesByName;
  const PlacementLookup(this.classesByName);

  List<String> get classNames =>
      [for (final c in classesByName.values) c.name]..sort();
}

class ClassPlacement {
  final String classId;
  final String name;

  /// [normName]d section name -> sectionId.
  final Map<String, String> sectionIdsByName;

  /// Section names as the admin sees them (for "available: …" hints).
  final List<String> sectionNames;

  const ClassPlacement(
    this.classId,
    this.name,
    this.sectionIdsByName, [
    this.sectionNames = const [],
  ]);
}

/// One thing wrong with one cell, phrased for the admin.
class BulkCellError {
  /// Template column key, or `row` for whole-row problems.
  final String column;
  final String label;
  final String value;

  /// What is wrong.
  final String message;

  /// What to do about it.
  final String fix;

  /// Allowed values when the column takes one of a fixed set (class names,
  /// genders…) — the review screen offers them as a picker. Empty = free
  /// text.
  final List<String> choices;

  const BulkCellError({
    required this.column,
    required this.label,
    required this.value,
    required this.message,
    required this.fix,
    this.choices = const [],
  });

  @override
  String toString() => '$label: $message $fix';
}

class BulkParentData {
  final String firstName;
  final String lastName;
  final String phone;
  final RelationshipType relationship;
  final String? email;
  const BulkParentData({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.relationship,
    this.email,
  });

  /// Rows with the same phone (digits only) are the same parent.
  String get key => phone.replaceAll(RegExp(r'\D'), '');
}

class BulkStudentData {
  final String admissionNumber;
  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime dateOfBirth;
  final Gender gender;
  final BloodGroup? bloodGroup;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final DateTime admissionDate;
  final String classId;
  final String sectionId;
  final String? rollNumber;
  final BulkParentData? parent;

  const BulkStudentData({
    required this.admissionNumber,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    this.bloodGroup,
    this.email,
    this.phone,
    this.address,
    this.city,
    required this.admissionDate,
    required this.classId,
    required this.sectionId,
    this.rollNumber,
    this.parent,
  });
}

/// One sheet row after validation: [data] is non-null iff [errors] is empty.
class BulkStudentRow {
  /// 1-based line in the file (header = 1), so it matches what the admin
  /// sees in Excel.
  final int line;
  final List<String> cells;
  final List<BulkCellError> errors;
  final BulkStudentData? data;

  /// "Admission no / name" for display next to errors.
  final String who;

  const BulkStudentRow({
    required this.line,
    required this.cells,
    required this.errors,
    this.data,
    this.who = '',
  });

  bool get isValid => errors.isEmpty && data != null;

  /// All problems as one readable sentence list (CSV `error` column, logs).
  String get errorSummary => errors.map((e) => e.toString()).join(' | ');

  BulkStudentRow withErrors(List<BulkCellError> more) => BulkStudentRow(
    line: line,
    cells: cells,
    errors: [...errors, ...more],
    who: who,
  );
}

class BulkStudentParseResult {
  /// Set when the file as a whole is unusable (empty, missing columns,
  /// too many rows, nothing to match against). Rows are empty then.
  final String? fileError;
  final List<String> header;
  final List<BulkStudentRow> rows;

  const BulkStudentParseResult({
    this.fileError,
    this.header = const [],
    this.rows = const [],
  });

  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.length - validCount;
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Emails are compared and stored trimmed and lowercase, so `Asha@X.com` and
/// `asha@x.com` are the same login.
String normalizeImportEmail(String raw) => raw.trim().toLowerCase();

bool isValidImportEmail(String normalized) =>
    _emailPattern.hasMatch(normalized);
final RegExp _phonePattern = RegExp(r'^[0-9+\-\s()]{7,20}$');

/// Accepts `YYYY-MM-DD` and day-first `DD/MM/YYYY` / `DD-MM-YYYY` (the
/// formats Excel produces for Indian locales). Returns null if it is not a
/// real calendar date.
DateTime? parseSheetDate(String raw) {
  final s = raw.trim();
  int y, m, d;
  var match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (match != null) {
    y = int.parse(match.group(1)!);
    m = int.parse(match.group(2)!);
    d = int.parse(match.group(3)!);
  } else {
    match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(s);
    if (match == null) return null;
    d = int.parse(match.group(1)!);
    m = int.parse(match.group(2)!);
    y = int.parse(match.group(3)!);
  }
  final date = DateTime(y, m, d);
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}

Gender? _parseGender(String v) {
  switch (v.trim().toLowerCase()) {
    case 'male':
    case 'm':
      return Gender.male;
    case 'female':
    case 'f':
      return Gender.female;
    case 'other':
    case 'o':
      return Gender.other;
  }
  return null;
}

BloodGroup? _parseBloodGroup(String v) {
  final s = v.trim().toUpperCase().replaceAll(' ', '');
  for (final g in BloodGroup.values) {
    if (g.displayName == s) return g;
  }
  return null;
}

RelationshipType? _parseRelationship(String v) {
  for (final r in RelationshipType.values) {
    if (r.displayName.toLowerCase() == v.trim().toLowerCase()) return r;
  }
  return null;
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

int _editDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// The closest of [options] to [value] when it is plausibly a typo.
String? suggestClosest(String value, Iterable<String> options) {
  final v = normName(value).replaceAll(RegExp(r'[^a-z0-9]'), '');
  String? best;
  var bestScore = 3;
  for (final o in options) {
    final n = normName(o).replaceAll(RegExp(r'[^a-z0-9]'), '');
    // "Grade 7" is a different class from "Grade 1", not a typo of it.
    if (_digits(n) != _digits(v)) continue;
    final score = n == v ? 0 : _editDistance(v, n);
    if (score < bestScore && score <= (n.length <= 3 ? 1 : 2)) {
      bestScore = score;
      best = o;
    }
  }
  return best;
}

String joinForHint(Iterable<String> items, {int max = 12}) {
  final l = items.toList();
  if (l.isEmpty) return '(none set up)';
  return l.length <= max
      ? l.join(', ')
      : '${l.take(max).join(', ')} … (+${l.length - max} more)';
}

/// Parses and validates a whole sheet. [today] is injectable for tests;
/// [academicYearName] only appears in messages.
BulkStudentParseResult parseBulkStudentCsv(
  String csvText, {
  required PlacementLookup placements,
  String academicYearName = 'the chosen academic year',
  DateTime? today,
}) {
  final now = today ?? SchoolTime.wallNow();
  final table = parseCsv(csvText);
  if (table.isEmpty) {
    return const BulkStudentParseResult(
      fileError:
          'The file is empty. Download the sample sheet, fill it in '
          'and upload it again.',
    );
  }

  final header = [for (final h in table.first) _norm(h)];
  final missing = [
    for (final c in bulkStudentColumns)
      if (c.required && !header.contains(c.key)) c.key,
  ];
  if (missing.isNotEmpty) {
    return BulkStudentParseResult(
      fileError:
          'The header row is missing these required columns: '
          '${missing.join(', ')}. Do not rename or delete columns — '
          'download the sample sheet and copy your data into it.',
      header: header,
    );
  }

  final dataRows = table.skip(1).toList();
  if (dataRows.isEmpty) {
    return BulkStudentParseResult(
      fileError: 'The file has a header row but no student rows.',
      header: header,
    );
  }
  if (dataRows.length > bulkStudentMaxRows) {
    return BulkStudentParseResult(
      fileError:
          'The file has ${dataRows.length} student rows; the limit is '
          '$bulkStudentMaxRows per upload. Split it into smaller files.',
      header: header,
    );
  }
  final seenAdmission = <String, int>{};
  final rows = <BulkStudentRow>[];

  for (var i = 0; i < dataRows.length; i++) {
    final cells = dataRows[i];
    final line = i + 2;
    String get(String key) {
      final idx = header.indexOf(key);
      if (idx < 0 || idx >= cells.length) return '';
      final v = cells[idx].trim();
      return key == 'email' || key == 'parent_email' ? v.toLowerCase() : v;
    }

    final errors = <BulkCellError>[];
    void err(
      String column,
      String message,
      String fix, {
      List<String> choices = const [],
    }) => errors.add(
      BulkCellError(
        column: column,
        label: _label(column),
        value: get(column),
        message: message,
        fix: fix,
        choices: choices,
      ),
    );

    for (final c in bulkStudentColumns) {
      if (c.required && get(c.key).isEmpty) {
        err(
          c.key,
          'is empty.',
          'Enter the ${c.label.toLowerCase()} — it is required.',
        );
      }
    }

    final admission = get('admission_number');
    if (admission.isNotEmpty) {
      final k = admission.toLowerCase();
      final first = seenAdmission[k];
      if (first != null) {
        err(
          'admission_number',
          '"$admission" is already used on line $first of this file.',
          'Give every student a different admission number.',
        );
      } else {
        seenAdmission[k] = line;
      }
    }

    const dateFix =
        'Write it as YYYY-MM-DD (2015-06-30) or DD/MM/YYYY (30/06/2015).';
    DateTime? dob;
    if (get('date_of_birth').isNotEmpty) {
      dob = parseSheetDate(get('date_of_birth'));
      if (dob == null) {
        err(
          'date_of_birth',
          '"${get('date_of_birth')}" is not a valid date.',
          dateFix,
        );
      } else if (dob.isAfter(now) || dob.year < 1900) {
        err(
          'date_of_birth',
          '"${get('date_of_birth')}" is in the future or too far in the past.',
          'Check the year.',
        );
        dob = null;
      }
    }

    var admissionDate = DateTime(now.year, now.month, now.day);
    if (get('admission_date').isNotEmpty) {
      final parsed = parseSheetDate(get('admission_date'));
      if (parsed == null) {
        err(
          'admission_date',
          '"${get('admission_date')}" is not a valid date.',
          '$dateFix Leave it blank to use today.',
        );
      } else {
        admissionDate = parsed;
      }
    }

    Gender? gender;
    if (get('gender').isNotEmpty) {
      gender = _parseGender(get('gender'));
      if (gender == null) {
        err(
          'gender',
          '"${get('gender')}" is not recognised.',
          'Use Male, Female or Other.',
          choices: const ['Male', 'Female', 'Other'],
        );
      }
    }

    BloodGroup? blood;
    if (get('blood_group').isNotEmpty) {
      blood = _parseBloodGroup(get('blood_group'));
      if (blood == null) {
        err(
          'blood_group',
          '"${get('blood_group')}" is not recognised.',
          'Use one of A+, A-, B+, B-, AB+, AB-, O+, O- — or leave it blank.',
          choices: [for (final g in BloodGroup.values) g.displayName],
        );
      }
    }

    if (get('email').isNotEmpty && !_emailPattern.hasMatch(get('email'))) {
      err(
        'email',
        '"${get('email')}" is not a valid email address.',
        'Use the form name@example.com — or leave it blank.',
      );
    }
    if (get('phone').isNotEmpty && !_phonePattern.hasMatch(get('phone'))) {
      err(
        'phone',
        '"${get('phone')}" is not a valid phone number.',
        'Use 7–20 digits (may include + - ( ) and spaces) — or leave it blank.',
      );
    }

    // Class / section are matched against what is set up in the database
    // for the chosen academic year.
    String? classId;
    String? sectionId;
    final className = get('class');
    final sectionName = get('section');
    if (className.isNotEmpty) {
      final cls = placements.classesByName[normName(className)];
      if (cls == null) {
        final names = placements.classNames;
        final hint = suggestClosest(className, names);
        err(
          'class',
          names.isEmpty
              ? 'No class named "$className" — $academicYearName has no '
                    'classes set up yet.'
              : 'No class named "$className" exists in $academicYearName.',
          names.isEmpty
              ? 'Create the classes and sections under Academic setup first, '
                    'then upload again (or choose a different academic year).'
              : '${hint != null ? 'Did you mean "$hint"? ' : ''}'
                    'Classes available: ${joinForHint(names)}. Pick one below '
                    '(or add the class in Academic setup first).',
          choices: names,
        );
      } else if (sectionName.isNotEmpty) {
        sectionId = cls.sectionIdsByName[normName(sectionName)];
        if (sectionId == null) {
          final hint = suggestClosest(sectionName, cls.sectionNames);
          err(
            'section',
            'Class ${cls.name} has no section named "$sectionName".',
            '${hint != null ? 'Did you mean "$hint"? ' : ''}'
                'Sections of ${cls.name}: ${joinForHint(cls.sectionNames)}. '
                'Pick one below (or add the section in Academic setup).',
            choices: cls.sectionNames,
          );
        } else {
          classId = cls.classId;
        }
      }
    }

    BulkParentData? parent;
    final pFirst = get('parent_first_name');
    final pLast = get('parent_last_name');
    final pPhone = get('parent_phone');
    final pRel = get('parent_relationship');
    final pEmail = get('parent_email');
    if ([pFirst, pLast, pPhone, pRel, pEmail].any((v) => v.isNotEmpty)) {
      final before = errors.length;
      const need =
          'A parent was started on this row, so first name, last name and '
          'phone are all needed. Fill all three, or clear the parent columns.';
      if (pFirst.isEmpty) err('parent_first_name', 'is empty.', need);
      if (pLast.isEmpty) err('parent_last_name', 'is empty.', need);
      if (pPhone.isEmpty) {
        err('parent_phone', 'is empty.', need);
      } else if (!_phonePattern.hasMatch(pPhone)) {
        err(
          'parent_phone',
          '"$pPhone" is not a valid phone number.',
          'Use 7–20 digits (may include + - ( ) and spaces).',
        );
      }
      if (pEmail.isNotEmpty && !_emailPattern.hasMatch(pEmail)) {
        err(
          'parent_email',
          '"$pEmail" is not a valid email address.',
          'Use a full address like name@example.com, or leave it blank.',
        );
      }
      var rel = RelationshipType.guardian;
      if (pRel.isNotEmpty) {
        final parsed = _parseRelationship(pRel);
        if (parsed == null) {
          err(
            'parent_relationship',
            '"$pRel" is not recognised.',
            'Use Father, Mother, Guardian or Other — or leave it blank '
                '(Guardian).',
            choices: [for (final r in RelationshipType.values) r.displayName],
          );
        } else {
          rel = parsed;
        }
      }
      if (errors.length == before) {
        parent = BulkParentData(
          firstName: pFirst,
          lastName: pLast,
          phone: pPhone,
          relationship: rel,
          email: pEmail.isEmpty ? null : pEmail,
        );
      }
    }

    BulkStudentData? data;
    if (errors.isEmpty) {
      String? opt(String k) => get(k).isEmpty ? null : get(k);
      data = BulkStudentData(
        admissionNumber: admission,
        firstName: get('first_name'),
        middleName: opt('middle_name'),
        lastName: get('last_name'),
        dateOfBirth: dob!,
        gender: gender!,
        bloodGroup: blood,
        email: opt('email'),
        phone: opt('phone'),
        address: opt('address'),
        city: opt('city'),
        admissionDate: admissionDate,
        classId: classId!,
        sectionId: sectionId!,
        rollNumber: opt('roll_number'),
        parent: parent,
      );
    }

    final who = [
      if (admission.isNotEmpty) admission,
      [
        get('first_name'),
        get('last_name'),
      ].where((e) => e.isNotEmpty).join(' '),
    ].where((e) => e.isNotEmpty).join(' · ');

    rows.add(
      BulkStudentRow(
        line: line,
        cells: cells,
        errors: errors,
        data: data,
        who: who,
      ),
    );
  }

  return BulkStudentParseResult(
    header: header,
    rows: flagDuplicateParentEmails(rows),
  );
}

/// One email can sign in only one parent. Rows that reuse an email already
/// given to a *different* parent (different phone) earlier in the file are
/// flagged — never silently merged or dropped. The same parent repeated for
/// siblings (same phone) is fine.
List<BulkStudentRow> flagDuplicateParentEmails(List<BulkStudentRow> rows) {
  final owner = <String, ({String phoneKey, int line})>{};
  return [
    for (final r in rows)
      if (!r.isValid || r.data!.parent?.email == null)
        r
      else
        () {
          final p = r.data!.parent!;
          final email = p.email!;
          final first = owner[email];
          if (first == null) {
            owner[email] = (phoneKey: p.key, line: r.line);
            return r;
          }
          if (first.phoneKey == p.key) return r;
          return r.withErrors([
            BulkCellError(
              column: 'parent_email',
              label: 'Parent email',
              value: email,
              message:
                  '"$email" is already used on line ${first.line} by a parent with a different phone number.',
              fix:
                  'Each parent needs their own email to sign in. Change it, or leave it blank.',
            ),
          ]);
        }(),
  ];
}

/// CSV of the rows that did not import, with an `error` column, ready to be
/// fixed and re-upload (the extra column is ignored on upload).
String bulkStudentErrorsCsv(
  List<String> header,
  List<({BulkStudentRow row, String error})> failed,
) {
  final cols = [for (final c in bulkStudentColumns) c.key];
  String cell(BulkStudentRow r, String key) {
    final idx = header.indexOf(key);
    return (idx < 0 || idx >= r.cells.length) ? '' : r.cells[idx];
  }

  return '﻿${encodeCsv([
    [...cols, 'error'],
    for (final f in failed) [for (final k in cols) cell(f.row, k), f.error],
  ])}';
}

/// Returns [csv] with one column's cell changed — either one row ([line],
/// 1-based file line as shown in the review) or every row whose cell equals
/// [oldValue] ([line] null). Used by the review screen's inline fixes; the
/// result is re-parsed and re-validated like a fresh upload.
String editCsvCells(
  String csv, {
  required String columnKey,
  required String newValue,
  int? line,
  String? oldValue,
}) {
  final hadBom = csv.startsWith('\uFEFF');
  final table = parseCsv(csv);
  if (table.isEmpty) return csv;
  final col = table.first.map(_norm).toList().indexOf(columnKey);
  if (col < 0) return csv;

  void setCell(List<String> row) {
    while (row.length <= col) {
      row.add('');
    }
    row[col] = newValue;
  }

  if (line != null) {
    if (line >= 2 && line <= table.length) setCell(table[line - 1]);
  } else {
    for (final row in table.skip(1)) {
      final current = col < row.length ? row[col].trim() : '';
      if (current == (oldValue ?? '').trim()) setCell(row);
    }
  }
  return '${hadBom ? '\uFEFF' : ''}${encodeCsv(table)}';
}
