import 'admission_application.dart';

/// School-wide admission settings (`schools/{s}/admissionSettings/config`),
/// written only by the `saveAdmissionSettings` callable.
/// The public enquiry page (`admission/{slug}`). [consentVersion] is managed by
/// the server: it grows whenever the consent text changes.
class PublicPortalSettings {
  final bool enabled;
  final String slug;
  final String branchId;
  final String introText;
  final String consentText;
  final int consentVersion;

  const PublicPortalSettings({
    this.enabled = false,
    this.slug = '',
    this.branchId = '',
    this.introText = '',
    this.consentText = '',
    this.consentVersion = 0,
  });

  factory PublicPortalSettings.fromMap(Object? data) {
    if (data is! Map) return const PublicPortalSettings();
    return PublicPortalSettings(
      enabled: data['enabled'] == true,
      slug: data['slug'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      introText: data['introText'] as String? ?? '',
      consentText: data['consentText'] as String? ?? '',
      consentVersion: data['consentVersion'] is int
          ? data['consentVersion'] as int
          : 0,
    );
  }

  Map<String, dynamic> toWire() => {
    'enabled': enabled,
    'slug': slug,
    'branchId': branchId,
    'introText': introText,
    'consentText': consentText,
  };

  /// The path visitors open.
  String get path => '/admission/$slug';

  static final RegExp slugPattern = RegExp(
    r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$',
  );
}

/// The admission events that notify people, in display order (key, label).
const List<(String, String)> admissionNotificationSwitches = [
  ('newEnquiry', 'A new enquiry arrives (branch administrators)'),
  ('assignment', 'An enquiry is assigned to someone (the assignee)'),
  ('applicationSubmitted', 'An application is submitted (who may approve)'),
  ('decision', 'An application is approved or not approved (the owner)'),
  ('confirmed', 'An admission is confirmed (the owner)'),
  ('parentConfirmed', 'Tell the parents when the admission is confirmed'),
];

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
  final PublicPortalSettings publicPortal;

  /// Which events notify people; a missing key means on.
  final Map<String, bool> notifications;
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
    this.publicPortal = const PublicPortalSettings(),
    this.notifications = const {},
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
      publicPortal: PublicPortalSettings.fromMap(data['publicPortal']),
      notifications: {
        if (data['notifications'] is Map)
          for (final e in (data['notifications'] as Map).entries)
            if (e.key is String && e.value is bool)
              e.key as String: e.value as bool,
      },
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
    'publicPortal': publicPortal.toWire(),
    'notifications': {
      for (final (key, _) in admissionNotificationSwitches) key: notifies(key),
    },
  };

  /// Whether the event [key] notifies people (on unless switched off).
  bool notifies(String key) => notifications[key] != false;

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
    PublicPortalSettings? publicPortal,
    Map<String, bool>? notifications,
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
    publicPortal: publicPortal ?? this.publicPortal,
    notifications: notifications ?? this.notifications,
    version: version,
  );

  /// Every document type this school uses (built-in then its own), as
  /// key → label, in display order.
  Map<String, String> get documentTypes => {
    ...builtInDocumentTypes,
    for (final c in customDocumentTypes) c.id: c.label,
  };
}
