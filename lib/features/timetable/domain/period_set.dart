import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import 'timetable_enums.dart';

/// Minutes since local midnight. Timetable times are **school-local
/// wall-clock** values: no timezone is attached, so a period at 09:00 is at
/// 09:00 for everyone in the branch and can never shift with a device's
/// timezone. (Dates elsewhere are civil `yyyy-MM-dd` keys, same idea.)
abstract final class MinuteOfDay {
  static String format(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String range(int start, int end) => '${format(start)}–${format(end)}';

  /// "09:05" -> 545, or null when malformed.
  static int? parse(String text) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  static bool overlaps(int aStart, int aEnd, int bStart, int bEnd) =>
      aStart < bEnd && bStart < aEnd;
}

/// One slot of a bell schedule. [slotId] is stable: entries reference it, so
/// reordering or relabelling never detaches a timetable cell. Non-teaching
/// slots (break, lunch, assembly…) carry no teacher or subject.
class PeriodSlot {
  final String slotId;

  /// 1, 2, 3… for teaching slots in time order; null for non-teaching.
  final int? number;
  final SlotKind kind;
  final String label;
  final int startMin;
  final int endMin;

  const PeriodSlot({
    required this.slotId,
    this.number,
    required this.kind,
    required this.label,
    required this.startMin,
    required this.endMin,
  });

  int get durationMin => endMin - startMin;
  bool get isTeaching => kind.isTeaching;
  String get timeLabel => MinuteOfDay.range(startMin, endMin);
  String get displayName =>
      isTeaching ? 'Period ${number ?? ''}'.trim() : label;

  factory PeriodSlot.fromMap(Map<String, dynamic> m) => PeriodSlot(
    slotId: m['slotId'] as String,
    number: (m['number'] as num?)?.toInt(),
    kind: SlotKind.fromWireValue(m['kind'] as String),
    label: m['label'] as String? ?? '',
    startMin: (m['startMin'] as num).toInt(),
    endMin: (m['endMin'] as num).toInt(),
  );

  Map<String, dynamic> toMap() => {
    'slotId': slotId,
    'number': number,
    'kind': kind.wireValue,
    'label': label,
    'startMin': startMin,
    'endMin': endMin,
  };
}

/// `.../branches/{b}/periodSets/{id}` — a named bell schedule. A timetable
/// maps each working weekday to one of these, so different days can follow
/// different schedules (a short Saturday, say).
class PeriodSet {
  final String periodSetId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String name;
  final List<PeriodSlot> slots;
  final ActivationStatus status;
  final DateTime? updatedAt;

  const PeriodSet({
    required this.periodSetId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.name,
    required this.slots,
    this.status = ActivationStatus.active,
    this.updatedAt,
  });

  static const int maxSlots = 20;
  static final RegExp slotIdPattern = RegExp(r'^[a-z0-9_]{1,12}$');

  static String idFor(String academicYearId, String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${academicYearId}__$slug';
  }

  List<PeriodSlot> get teachingSlots => [
    for (final s in slots)
      if (s.isTeaching) s,
  ];

  PeriodSlot? slot(String slotId) =>
      slots.where((s) => s.slotId == slotId).firstOrNull;

  /// A user-readable reason this schedule is invalid, or null.
  String? validate() {
    final n = name.trim();
    if (n.length < 2 || n.length > 40) {
      return 'The schedule name must be 2-40 characters.';
    }
    if (slots.isEmpty) return 'Add at least one period.';
    if (slots.length > maxSlots) {
      return 'A schedule can have at most $maxSlots slots.';
    }
    if (teachingSlots.isEmpty) return 'Add at least one teaching period.';
    final ids = <String>{};
    for (final s in slots) {
      if (!slotIdPattern.hasMatch(s.slotId)) {
        return 'A slot has an invalid id.';
      }
      if (!ids.add(s.slotId)) return 'Slot ids must be unique.';
      if (s.startMin < 0 || s.endMin > 24 * 60) {
        return '${s.displayName}: times must be within one day.';
      }
      if (s.endMin <= s.startMin) {
        return '${s.displayName}: the end time must be after the start time.';
      }
      if (!s.isTeaching && s.label.trim().isEmpty) {
        return 'Name the ${s.kind.displayName.toLowerCase()}.';
      }
      if (s.isTeaching && (s.number == null || s.number! < 1)) {
        return 'A teaching period needs a number.';
      }
    }
    final ordered = [...slots]
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    for (var i = 1; i < ordered.length; i++) {
      final a = ordered[i - 1];
      final b = ordered[i];
      if (MinuteOfDay.overlaps(a.startMin, a.endMin, b.startMin, b.endMin)) {
        return '${a.displayName} (${a.timeLabel}) overlaps '
            '${b.displayName} (${b.timeLabel}).';
      }
    }
    final numbers = [
      for (final s in ordered)
        if (s.isTeaching) s.number!,
    ];
    for (var i = 0; i < numbers.length; i++) {
      if (numbers[i] != i + 1) {
        return 'Teaching periods must be numbered 1, 2, 3… in time order.';
      }
    }
    return null;
  }

  /// Renumbers teaching slots 1..n in time order (used by the editor).
  PeriodSet normalized() {
    final ordered = [...slots]
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    var n = 0;
    return PeriodSet(
      periodSetId: periodSetId,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      name: name,
      status: status,
      slots: [
        for (final s in ordered)
          PeriodSlot(
            slotId: s.slotId,
            number: s.isTeaching ? ++n : null,
            kind: s.kind,
            label: s.label,
            startMin: s.startMin,
            endMin: s.endMin,
          ),
      ],
    );
  }

  factory PeriodSet.fromFirestore(Map<String, dynamic> d, String id) =>
      PeriodSet(
        periodSetId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        name: d['name'] as String,
        slots: [
          for (final s in d['slots'] as List? ?? [])
            PeriodSlot.fromMap(Map<String, dynamic>.from(s as Map)),
        ],
        status: ActivationStatus.fromWireValue(
          d[FirestoreFields.status] as String? ?? 'ACTIVE',
        ),
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> _body() => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'name': name.trim(),
    'slots': [for (final s in slots) s.toMap()],
    FirestoreFields.status: status.wireValue,
  };

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    ..._body(),
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };

  Map<String, dynamic> toFirestoreUpdate({required String actorId}) => {
    ..._body(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: actorId,
  };
}
