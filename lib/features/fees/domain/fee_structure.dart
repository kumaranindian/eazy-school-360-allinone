import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import 'fee_enums.dart';

/// A `.../branches/{branchId}/feeStructures/{yearId}__{codeLower}` document:
/// one fee head ("Tuition – Class 5") for one academic year.
///
/// The id embeds the lower-cased [code], so a code exists once per branch and
/// year (duplicate configurations are impossible, not just discouraged).
/// Editing a structure changes only what is billed **from then on**: issued
/// invoices carry their own snapshot of the amounts and descriptions and are
/// never touched.
class FeeStructure {
  final String structureId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String code;
  final String name;
  final FeeCategory category;
  final String? customCategoryLabel;
  final FeeFrequency frequency;
  final int amountMinor;

  /// Null = every class of the year.
  final String? classId;

  /// Null = every section of [classId].
  final String? sectionId;

  /// An optional fee (e.g. transport) is never assigned in bulk unless chosen.
  final bool isOptional;

  /// `yyyy-MM-dd`; the structure bills only for issue dates inside this window.
  final String? effectiveFromKey;
  final String? effectiveToKey;

  /// Days after the issue date that an invoice containing this fee falls due.
  final int dueOffsetDays;
  final String? description;
  final String? paymentInstructions;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const FeeStructure({
    required this.structureId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.code,
    required this.name,
    required this.category,
    this.customCategoryLabel,
    required this.frequency,
    required this.amountMinor,
    this.classId,
    this.sectionId,
    this.isOptional = false,
    this.effectiveFromKey,
    this.effectiveToKey,
    this.dueOffsetDays = 15,
    this.description,
    this.paymentInstructions,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  static final RegExp codePattern = RegExp(r'^[A-Za-z0-9_-]{2,20}$');
  static const int maxAmountMinor = 1000000000; // 10 million major units

  static String idFor(String academicYearId, String code) =>
      '${academicYearId}__${code.trim().toLowerCase()}';

  bool get isActive => status == ActivationStatus.active;

  String get categoryLabel =>
      category == FeeCategory.other &&
          (customCategoryLabel ?? '').trim().isNotEmpty
      ? customCategoryLabel!.trim()
      : category.displayName;

  /// Whether the structure applies to a student in [classId]/[sectionId].
  bool appliesTo({required String classId, required String? sectionId}) {
    if (this.classId != null && this.classId != classId) return false;
    if (this.sectionId != null && this.sectionId != sectionId) return false;
    return true;
  }

  /// Whether [issueDateKey] is inside the effective window.
  bool isEffectiveOn(String issueDateKey) {
    if (effectiveFromKey != null &&
        issueDateKey.compareTo(effectiveFromKey!) < 0) {
      return false;
    }
    if (effectiveToKey != null && issueDateKey.compareTo(effectiveToKey!) > 0) {
      return false;
    }
    return true;
  }

  /// Configuration problems, empty if valid. Mirrors what `firestore.rules`
  /// checks for the scalar fields.
  List<String> validate() {
    return [
      if (!codePattern.hasMatch(code.trim()))
        'Code must be 2-20 letters, digits, "-" or "_".',
      if (name.trim().length < 2) 'Enter a fee name.',
      if (amountMinor <= 0) 'The amount must be greater than zero.',
      if (amountMinor > maxAmountMinor) 'The amount is too large.',
      if (sectionId != null && classId == null)
        'Choose a class before choosing a section.',
      if (dueOffsetDays < 0 || dueOffsetDays > 365)
        'Days until due must be between 0 and 365.',
      if (effectiveFromKey != null &&
          effectiveToKey != null &&
          effectiveFromKey!.compareTo(effectiveToKey!) > 0)
        'The effective-from date is after the effective-to date.',
      if (category == FeeCategory.other &&
          (customCategoryLabel ?? '').trim().isEmpty)
        'Name the category for an "Other" fee.',
    ];
  }

  factory FeeStructure.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> d,
  ) {
    return FeeStructure(
      structureId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: d['academicYearId'] as String? ?? '',
      code: d['code'] as String? ?? '',
      name: d[FirestoreFields.name] as String? ?? '',
      category: FeeCategory.fromWireValue(d['category'] as String),
      customCategoryLabel: d['customCategoryLabel'] as String?,
      frequency: FeeFrequency.fromWireValue(d['frequency'] as String),
      amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
      classId: d['classId'] as String?,
      sectionId: d['sectionId'] as String?,
      isOptional: d['isOptional'] as bool? ?? false,
      effectiveFromKey: d['effectiveFromKey'] as String?,
      effectiveToKey: d['effectiveToKey'] as String?,
      dueOffsetDays: (d['dueOffsetDays'] as num?)?.toInt() ?? 15,
      description: d['description'] as String?,
      paymentInstructions: d['paymentInstructions'] as String?,
      status: ActivationStatus.fromWireValue(
        d[FirestoreFields.status] as String,
      ),
      createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: d[FirestoreFields.createdBy] as String?,
      updatedBy: d[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> _editable() => {
    FirestoreFields.name: name.trim(),
    'category': category.wireValue,
    'customCategoryLabel': category == FeeCategory.other
        ? customCategoryLabel?.trim()
        : null,
    'frequency': frequency.wireValue,
    'amountMinor': amountMinor,
    'classId': classId,
    'sectionId': sectionId,
    'isOptional': isOptional,
    'effectiveFromKey': effectiveFromKey,
    'effectiveToKey': effectiveToKey,
    'dueOffsetDays': dueOffsetDays,
    'description': description,
    'paymentInstructions': paymentInstructions,
    FirestoreFields.status: status.wireValue,
  };

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'code': code.trim(),
    ..._editable(),
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: createdBy,
    FirestoreFields.updatedBy: createdBy,
  };

  /// The year and code are the document id, so they are not editable.
  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) => {
    ..._editable(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: updatedBy,
  };
}
