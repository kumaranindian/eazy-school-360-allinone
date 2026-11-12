import 'admission_application.dart';

/// School-wide admission settings (`schools/{s}/admissionSettings/config`),
/// written only by the `saveAdmissionSettings` callable.
class AdmissionSettings {
  final bool enabled;
  final String enquiryPrefix;
  final String applicationPrefix;
  final List<String> sources;
  final int followUpDays;

  /// Staff are reminded of due and overdue follow-ups once a day at
  /// [reminderTime] (school time zone) when [remindersEnabled].
  final bool remindersEnabled;
  final String reminderTime;

  /// Empty means "all academic years / classes are open for admissions".
  final List<String> academicYearIds;
  final List<String> classIds;

  /// Documents that must be VERIFIED before an application can be approved.
  final List<String> requiredDocumentTypes;
  final List<CustomDocumentType> customDocumentTypes;

  /// Whether branch administrators may approve or reject applications.
  final bool branchAdminsMayApprove;
  final int version;

  const AdmissionSettings({
    this.enabled = false,
    this.enquiryPrefix = 'ENQ',
    this.applicationPrefix = 'APP',
    this.sources = defaultSources,
    this.followUpDays = 3,
    this.remindersEnabled = true,
    this.reminderTime = '09:00',
    this.academicYearIds = const [],
    this.classIds = const [],
    this.requiredDocumentTypes = const ['BIRTH_CERTIFICATE', 'STUDENT_PHOTO'],
    this.customDocumentTypes = const [],
    this.branchAdminsMayApprove = false,
    this.version = 0,
  });

  static const List<String> defaultSources = [
    'Walk-in',
    'Phone call',
    'Website',
    'WhatsApp',
    'Social media',
    'Referral',
    'Existing parent',
    'Advertisement',
    'Other',
  ];

  factory AdmissionSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const AdmissionSettings();
    List<String> strings(Object? v, List<String> fallback) => v is List
        ? [
            for (final e in v)
              if (e is String) e,
          ]
        : fallback;
    return AdmissionSettings(
      enabled: data['enabled'] == true,
      enquiryPrefix: data['enquiryPrefix'] as String? ?? 'ENQ',
      applicationPrefix: data['applicationPrefix'] as String? ?? 'APP',
      sources: strings(data['sources'], defaultSources),
      followUpDays: data['followUpDays'] is int
          ? data['followUpDays'] as int
          : 3,
      remindersEnabled: data['remindersEnabled'] != false,
      reminderTime: data['reminderTime'] as String? ?? '09:00',
      academicYearIds: strings(data['academicYearIds'], const []),
      classIds: strings(data['classIds'], const []),
      requiredDocumentTypes: strings(data['requiredDocumentTypes'], const [
        'BIRTH_CERTIFICATE',
        'STUDENT_PHOTO',
      ]),
      customDocumentTypes: [
        for (final c in (data['customDocumentTypes'] as List? ?? const []))
          if (c is Map && c['id'] is String && c['label'] is String)
            CustomDocumentType(
              id: c['id'] as String,
              label: c['label'] as String,
            ),
      ],
      branchAdminsMayApprove: data['branchAdminsMayApprove'] == true,
      version: data['version'] is int ? data['version'] as int : 0,
    );
  }

  /// The payload of `saveAdmissionSettings` (the server validates it).
  Map<String, dynamic> toWire() => {
    'enabled': enabled,
    'enquiryPrefix': enquiryPrefix,
    'applicationPrefix': applicationPrefix,
    'sources': sources,
    'followUpDays': followUpDays,
    'remindersEnabled': remindersEnabled,
    'reminderTime': reminderTime,
    'academicYearIds': academicYearIds,
    'classIds': classIds,
    'requiredDocumentTypes': requiredDocumentTypes,
    'customDocumentTypes': [for (final c in customDocumentTypes) c.toWire()],
    'branchAdminsMayApprove': branchAdminsMayApprove,
  };

  AdmissionSettings copyWith({
    bool? enabled,
    String? enquiryPrefix,
    String? applicationPrefix,
    List<String>? sources,
    int? followUpDays,
    bool? remindersEnabled,
    String? reminderTime,
    List<String>? academicYearIds,
    List<String>? classIds,
    List<String>? requiredDocumentTypes,
    List<CustomDocumentType>? customDocumentTypes,
    bool? branchAdminsMayApprove,
  }) => AdmissionSettings(
    enabled: enabled ?? this.enabled,
    enquiryPrefix: enquiryPrefix ?? this.enquiryPrefix,
    applicationPrefix: applicationPrefix ?? this.applicationPrefix,
    sources: sources ?? this.sources,
    followUpDays: followUpDays ?? this.followUpDays,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    reminderTime: reminderTime ?? this.reminderTime,
    academicYearIds: academicYearIds ?? this.academicYearIds,
    classIds: classIds ?? this.classIds,
    requiredDocumentTypes: requiredDocumentTypes ?? this.requiredDocumentTypes,
    customDocumentTypes: customDocumentTypes ?? this.customDocumentTypes,
    branchAdminsMayApprove:
        branchAdminsMayApprove ?? this.branchAdminsMayApprove,
    version: version,
  );

  /// Every document type this school uses (built-in then its own), as
  /// key → label, in display order.
  Map<String, String> get documentTypes => {
    ...builtInDocumentTypes,
    for (final c in customDocumentTypes) c.id: c.label,
  };
}
