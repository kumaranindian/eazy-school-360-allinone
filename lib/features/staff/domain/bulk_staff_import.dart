import '../../students/domain/blood_group.dart';
import '../../students/domain/bulk_student_import.dart'
    show
        BulkCellError,
        encodeCsv,
        isValidImportEmail,
        joinForHint,
        normName,
        parseCsv,
        parseSheetDate,
        suggestClosest;
import '../../students/domain/gender.dart';
import 'employment_type.dart';
import 'staff.dart';

/// Bulk staff / teacher upload and export: the CSV template, row
/// validation against the branch's real departments and designations, and
/// the export builder. Pure Dart so it is unit-testable; persistence lives
/// in `BulkStaffImporter`. Shares the CSV codec and error type with the
/// student upload.

const int bulkStaffMaxRows = 500;

class BulkStaffColumn {
  final String key;
  final String label;
  final String example;
  final bool required;

  const BulkStaffColumn(
    this.key,
    this.label,
    this.example, {
    this.required = false,
  });
}

const List<BulkStaffColumn> bulkStaffColumns = [
  BulkStaffColumn('employee_code', 'Employee code', 'EMP-001', required: true),
  BulkStaffColumn('first_name', 'First name', 'Meena', required: true),
  BulkStaffColumn('middle_name', 'Middle name', ''),
  BulkStaffColumn('last_name', 'Last name', 'Iyer', required: true),
  BulkStaffColumn(
    'date_of_birth',
    'Date of birth',
    '1988-04-12',
    required: true,
  ),
  BulkStaffColumn('gender', 'Gender', 'Female', required: true),
  BulkStaffColumn('blood_group', 'Blood group', 'B+'),
  BulkStaffColumn('phone', 'Phone', '9876500001', required: true),
  BulkStaffColumn('alternate_phone', 'Alternate phone', ''),
  BulkStaffColumn('email', 'Email', 'meena.iyer@example.com'),
  BulkStaffColumn('address', 'Address', ''),
  BulkStaffColumn('city', 'City', ''),
  BulkStaffColumn('state', 'State', ''),
  BulkStaffColumn('country', 'Country', ''),
  BulkStaffColumn('postal_code', 'Postal code', ''),
  BulkStaffColumn('joining_date', 'Joining date', '2024-06-01', required: true),
  BulkStaffColumn('employment_type', 'Employment type', 'Full time'),
  BulkStaffColumn('department', 'Department', 'Academics', required: true),
  BulkStaffColumn('designation', 'Designation', 'Teacher', required: true),
  BulkStaffColumn('is_teacher', 'Is teacher', 'Yes'),
];

String _label(String key) =>
    bulkStaffColumns.firstWhere((c) => c.key == key).label;

/// Plain-language help shown on the page beside the download button.
const String bulkStaffHelp =
    'Date format YYYY-MM-DD or DD/MM/YYYY. Gender: Male, Female, Other. '
    'Employment type: Full time, Part time, Contract, Temporary, Intern, '
    'Other (blank = Full time). Department and designation must match a '
    'name or code set up under Staff → Departments / Designations. '
    'Is teacher: Yes or No. '
    'Email is optional; it is saved in lowercase and used for the person\'s '
    'login, so each email can appear only once (in the file and in the '
    'branch).';

String bulkStaffTemplateCsv({bool teachers = false}) =>
    '﻿${encodeCsv([
      [for (final c in bulkStaffColumns) c.key],
      [for (final c in bulkStaffColumns) c.key == 'is_teacher' ? (teachers ? 'Yes' : 'No') : c.example],
    ])}';

/// Names (and codes) the sheet's department/designation cells may use.
/// Keys are [normName]d; both name and code of each active record map to
/// its id.
class StaffReferenceLookup {
  final Map<String, String> departmentIds;
  final List<String> departmentNames;
  final Map<String, String> designationIds;
  final List<String> designationNames;

  const StaffReferenceLookup({
    required this.departmentIds,
    required this.departmentNames,
    required this.designationIds,
    required this.designationNames,
  });
}

class BulkStaffData {
  final String employeeCode;
  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime dateOfBirth;
  final Gender gender;
  final BloodGroup? bloodGroup;
  final String phone;
  final String? alternatePhone;
  final String? email;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final DateTime joiningDate;
  final EmploymentType employmentType;
  final String departmentId;
  final String designationId;
  final bool isTeacher;

  const BulkStaffData({
    required this.employeeCode,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    this.bloodGroup,
    required this.phone,
    this.alternatePhone,
    this.email,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    required this.joiningDate,
    required this.employmentType,
    required this.departmentId,
    required this.designationId,
    required this.isTeacher,
  });
}

class BulkStaffRow {
  final int line;
  final List<String> cells;
  final List<BulkCellError> errors;
  final BulkStaffData? data;
  final String who;

  const BulkStaffRow({
    required this.line,
    required this.cells,
    required this.errors,
    this.data,
    this.who = '',
  });

  bool get isValid => errors.isEmpty && data != null;

  String get errorSummary => errors.map((e) => e.toString()).join(' | ');

  BulkStaffRow withErrors(List<BulkCellError> more) => BulkStaffRow(
    line: line,
    cells: cells,
    errors: [...errors, ...more],
    who: who,
  );
}

class BulkStaffParseResult {
  final String? fileError;
  final List<String> header;
  final List<BulkStaffRow> rows;

  const BulkStaffParseResult({
    this.fileError,
    this.header = const [],
    this.rows = const [],
  });
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

final RegExp _phonePattern = RegExp(r'^[0-9+\-\s()]{7,20}$');

Gender? _gender(String v) {
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

BloodGroup? _blood(String v) {
  final s = v.trim().toUpperCase().replaceAll(' ', '');
  for (final g in BloodGroup.values) {
    if (g.displayName == s) return g;
  }
  return null;
}

EmploymentType? _employment(String v) {
  final s = normName(v).replaceAll('_', ' ').replaceAll('-', ' ');
  for (final t in EmploymentType.values) {
    if (t.displayName.toLowerCase() == s) return t;
    if (t.wireValue.toLowerCase().replaceAll('_', ' ') == s) return t;
  }
  return null;
}

bool? _yesNo(String v) {
  switch (v.trim().toLowerCase()) {
    case 'yes':
    case 'y':
    case 'true':
    case '1':
      return true;
    case 'no':
    case 'n':
    case 'false':
    case '0':
      return false;
  }
  return null;
}

/// Parses and validates a whole sheet. [defaultIsTeacher] is what a blank
/// `is_teacher` cell means (true on the Teachers screen).
BulkStaffParseResult parseBulkStaffCsv(
  String csvText, {
  required StaffReferenceLookup references,
  bool defaultIsTeacher = false,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final table = parseCsv(csvText);
  if (table.isEmpty) {
    return const BulkStaffParseResult(
      fileError:
          'The file is empty. Download the sample sheet, fill it in and '
          'upload it again.',
    );
  }
  final header = [for (final h in table.first) _norm(h)];
  final missing = [
    for (final c in bulkStaffColumns)
      if (c.required && !header.contains(c.key)) c.key,
  ];
  if (missing.isNotEmpty) {
    return BulkStaffParseResult(
      fileError:
          'The header row is missing these required columns: '
          '${missing.join(', ')}. Do not rename or delete columns — '
          'download the sample sheet and copy your data into it.',
      header: header,
    );
  }
  final dataRows = table.skip(1).toList();
  if (dataRows.isEmpty) {
    return BulkStaffParseResult(
      fileError: 'The file has a header row but no staff rows.',
      header: header,
    );
  }
  if (dataRows.length > bulkStaffMaxRows) {
    return BulkStaffParseResult(
      fileError:
          'The file has ${dataRows.length} rows; the limit is '
          '$bulkStaffMaxRows per upload. Split it into smaller files.',
      header: header,
    );
  }
  final seenCodes = <String, int>{};
  final rows = <BulkStaffRow>[];

  for (var i = 0; i < dataRows.length; i++) {
    final cells = dataRows[i];
    final line = i + 2;
    String get(String key) {
      final idx = header.indexOf(key);
      if (idx < 0 || idx >= cells.length) return '';
      final v = cells[idx].trim();
      return key == 'email' ? v.toLowerCase() : v;
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

    for (final c in bulkStaffColumns) {
      if (c.required && get(c.key).isEmpty) {
        err(
          c.key,
          'is empty.',
          'Enter the ${c.label.toLowerCase()} — it is required.',
        );
      }
    }

    final code = get('employee_code');
    if (code.isNotEmpty) {
      if (!Staff.employeeCodePattern.hasMatch(code)) {
        err(
          'employee_code',
          '"$code" is not a valid employee code.',
          'Use 2–20 letters, digits, "-" or "_" (no spaces).',
        );
      } else {
        final k = Staff.normalizeEmployeeCode(code);
        final first = seenCodes[k];
        if (first != null) {
          err(
            'employee_code',
            '"$code" is already used on line $first of this file.',
            'Give every staff member a different employee code.',
          );
        } else {
          seenCodes[k] = line;
        }
      }
    }

    const dateFix =
        'Write it as YYYY-MM-DD (1988-04-12) or DD/MM/YYYY (12/04/1988).';
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
    DateTime? joining;
    if (get('joining_date').isNotEmpty) {
      joining = parseSheetDate(get('joining_date'));
      if (joining == null) {
        err(
          'joining_date',
          '"${get('joining_date')}" is not a valid date.',
          dateFix,
        );
      }
    }

    Gender? gender;
    if (get('gender').isNotEmpty) {
      gender = _gender(get('gender'));
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
      blood = _blood(get('blood_group'));
      if (blood == null) {
        err(
          'blood_group',
          '"${get('blood_group')}" is not recognised.',
          'Use one of A+, A-, B+, B-, AB+, AB-, O+, O- — or leave it blank.',
          choices: [for (final g in BloodGroup.values) g.displayName],
        );
      }
    }

    if (get('phone').isNotEmpty && !_phonePattern.hasMatch(get('phone'))) {
      err(
        'phone',
        '"${get('phone')}" is not a valid phone number.',
        'Use 7–20 digits (may include + - ( ) and spaces).',
      );
    }
    if (get('alternate_phone').isNotEmpty &&
        !_phonePattern.hasMatch(get('alternate_phone'))) {
      err(
        'alternate_phone',
        '"${get('alternate_phone')}" is not a valid phone number.',
        'Use 7–20 digits — or leave it blank.',
      );
    }
    if (get('email').isNotEmpty && !isValidImportEmail(get('email'))) {
      err(
        'email',
        '"${get('email')}" is not a valid email address.',
        'Use the form name@example.com — or leave it blank.',
      );
    }

    var employment = EmploymentType.fullTime;
    if (get('employment_type').isNotEmpty) {
      final parsed = _employment(get('employment_type'));
      if (parsed == null) {
        err(
          'employment_type',
          '"${get('employment_type')}" is not recognised.',
          'Use one of: ${EmploymentType.values.map((t) => t.displayName).join(', ')} '
              '— or leave it blank (Full time).',
          choices: [for (final t in EmploymentType.values) t.displayName],
        );
      } else {
        employment = parsed;
      }
    }

    // Department / designation: matched against the active records that
    // exist in this branch right now, by name or code.
    String? departmentId;
    if (get('department').isNotEmpty) {
      departmentId = references.departmentIds[normName(get('department'))];
      if (departmentId == null) {
        final names = references.departmentNames;
        final hint = suggestClosest(get('department'), names);
        err(
          'department',
          names.isEmpty
              ? 'No department named "${get('department')}" — this branch has '
                    'no departments set up yet.'
              : 'No department named "${get('department')}" exists in this '
                    'branch.',
          names.isEmpty
              ? 'Create "${get('department')}" with the button below (or add '
                    'departments under Staff → Departments), then re-check.'
              : '${hint != null ? 'Did you mean "$hint"? ' : ''}'
                    'Departments available: ${joinForHint(names)}. Pick one '
                    'below, or create "${get('department')}" with the button '
                    'below.',
          choices: names,
        );
      }
    }
    String? designationId;
    if (get('designation').isNotEmpty) {
      designationId = references.designationIds[normName(get('designation'))];
      if (designationId == null) {
        final names = references.designationNames;
        final hint = suggestClosest(get('designation'), names);
        err(
          'designation',
          names.isEmpty
              ? 'No designation named "${get('designation')}" — this branch '
                    'has no designations set up yet.'
              : 'No designation named "${get('designation')}" exists in this '
                    'branch.',
          names.isEmpty
              ? 'Create "${get('designation')}" with the button below (or '
                    'add designations under Staff → Designations), then '
                    're-check.'
              : '${hint != null ? 'Did you mean "$hint"? ' : ''}'
                    'Designations available: ${joinForHint(names)}. Pick one '
                    'below, or create "${get('designation')}" with the '
                    'button below.',
          choices: names,
        );
      }
    }

    var isTeacher = defaultIsTeacher;
    if (get('is_teacher').isNotEmpty) {
      final parsed = _yesNo(get('is_teacher'));
      if (parsed == null) {
        err(
          'is_teacher',
          '"${get('is_teacher')}" is not recognised.',
          'Write Yes or No — or leave it blank '
              '(${defaultIsTeacher ? 'Yes' : 'No'}).',
          choices: const ['Yes', 'No'],
        );
      } else {
        isTeacher = parsed;
      }
    }

    BulkStaffData? data;
    if (errors.isEmpty) {
      String? opt(String k) => get(k).isEmpty ? null : get(k);
      data = BulkStaffData(
        employeeCode: code,
        firstName: get('first_name'),
        middleName: opt('middle_name'),
        lastName: get('last_name'),
        dateOfBirth: dob!,
        gender: gender!,
        bloodGroup: blood,
        phone: get('phone'),
        alternatePhone: opt('alternate_phone'),
        email: opt('email'),
        address: opt('address'),
        city: opt('city'),
        state: opt('state'),
        country: opt('country'),
        postalCode: opt('postal_code'),
        joiningDate: joining!,
        employmentType: employment,
        departmentId: departmentId!,
        designationId: designationId!,
        isTeacher: isTeacher,
      );
    }

    final who = [
      if (code.isNotEmpty) code,
      [
        get('first_name'),
        get('last_name'),
      ].where((e) => e.isNotEmpty).join(' '),
    ].where((e) => e.isNotEmpty).join(' · ');

    rows.add(
      BulkStaffRow(
        line: line,
        cells: cells,
        errors: errors,
        data: data,
        who: who,
      ),
    );
  }
  return BulkStaffParseResult(
    header: header,
    rows: flagDuplicateStaffEmails(rows),
  );
}

/// An email can belong to one staff member: later rows that repeat an email
/// already used earlier in the file are flagged, not silently skipped.
List<BulkStaffRow> flagDuplicateStaffEmails(List<BulkStaffRow> rows) {
  final firstLine = <String, int>{};
  return [
    for (final r in rows)
      if (!r.isValid || r.data!.email == null)
        r
      else
        () {
          final email = r.data!.email!;
          final first = firstLine[email];
          if (first == null) {
            firstLine[email] = r.line;
            return r;
          }
          return r.withErrors([
            BulkCellError(
              column: 'email',
              label: 'Email',
              value: email,
              message: '"$email" is already used on line $first.',
              fix:
                  'Each staff member needs their own email to sign in. Change it, or leave it blank.',
            ),
          ]);
        }(),
  ];
}

/// CSV of rows that did not import, with an `error` column.
String bulkStaffErrorsCsv(
  List<String> header,
  List<({BulkStaffRow row, String error})> failed,
) {
  final cols = [for (final c in bulkStaffColumns) c.key];
  String cell(BulkStaffRow r, String key) {
    final idx = header.indexOf(key);
    return (idx < 0 || idx >= r.cells.length) ? '' : r.cells[idx];
  }

  return '﻿${encodeCsv([
    [...cols, 'error'],
    for (final f in failed) [for (final k in cols) cell(f.row, k), f.error],
  ])}';
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Export: the template's columns (so the file can be edited and used as a
/// reference sheet) plus `status`. Department/designation are written as
/// names. Cells that start with `= + - @` are prefixed with `'` so a
/// spreadsheet never evaluates them as formulas.
String staffExportCsv(
  List<Staff> staff, {
  required Map<String, String> departmentNames,
  required Map<String, String> designationNames,
}) {
  String safe(String v) =>
      v.isNotEmpty && '=+-@'.contains(v[0]) && !RegExp(r'^[+-]?\d').hasMatch(v)
      ? "'$v"
      : v;

  final header = [for (final c in bulkStaffColumns) c.key, 'status'];
  final rows = <List<String>>[
    for (final s in staff)
      [
        s.employeeCode,
        s.firstName,
        s.middleName ?? '',
        s.lastName,
        _isoDate(s.dateOfBirth),
        s.gender.displayName,
        s.bloodGroup?.displayName ?? '',
        s.phone,
        s.alternatePhone ?? '',
        s.email ?? '',
        s.address ?? '',
        s.city ?? '',
        s.state ?? '',
        s.country ?? '',
        s.postalCode ?? '',
        _isoDate(s.joiningDate),
        s.employmentType.displayName,
        departmentNames[s.departmentId] ?? s.departmentId,
        designationNames[s.designationId] ?? s.designationId,
        s.isTeacher ? 'Yes' : 'No',
        s.status.displayName,
      ].map(safe).toList(),
  ];
  return '﻿${encodeCsv([header, ...rows])}';
}
