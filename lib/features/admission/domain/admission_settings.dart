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
    version: version,
  );
}
