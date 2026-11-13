import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/regional/school_time.dart';

import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../staff/domain/staff_status.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_admission_repository.dart';
import '../../domain/admission_activity.dart';
import '../../domain/admission_application.dart';
import '../../domain/admission_conversion.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_report.dart';
import '../../domain/admission_fee.dart';
import '../../domain/admission_repository.dart';
import '../../domain/admission_settings.dart';
import '../../domain/admission_status.dart';

final admissionRepositoryProvider = Provider<AdmissionRepository>((ref) {
  // Reads go through Firestore (rules-gated); writes through callables.
  return FirebaseAdmissionRepository(db: ref.watch(firestoreProvider));
});

/// The bytes of admission documents (Storage). Overridden in tests.
final admissionDocumentStoreProvider = Provider<AdmissionDocumentStore>(
  (ref) => FirebaseAdmissionDocumentStore(
    storage: ref.watch(firebaseStorageProvider),
  ),
);

final admissionSettingsProvider = StreamProvider.autoDispose
    .family<AdmissionSettings, String>(
      (ref, schoolId) =>
          ref.watch(admissionRepositoryProvider).watchSettings(schoolId),
    );

typedef EnquiryKey = ({String schoolId, String branchId, String enquiryId});

final enquiryProvider = StreamProvider.autoDispose
    .family<AdmissionEnquiry?, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .watchEnquiry(key.schoolId, key.branchId, key.enquiryId),
    );

/// The status history; re-read when the enquiry's revision changes.
final enquiryHistoryProvider = FutureProvider.autoDispose
    .family<List<StatusHistoryEntry>, (EnquiryKey, int)>(
      (ref, args) => ref
          .watch(admissionRepositoryProvider)
          .fetchHistory(args.$1.schoolId, args.$1.branchId, args.$1.enquiryId),
    );

/// Every activity event of one enquiry, newest first. Activity changes do not
/// bump the enquiry's revision, so [lastActivityAt] (millis) is part of the key.
final enquiryActivityHistoryProvider = FutureProvider.autoDispose
    .family<List<ActivityHistoryEntry>, (EnquiryKey, int)>(
      (ref, args) => ref
          .watch(admissionRepositoryProvider)
          .fetchActivityHistory(
            args.$1.schoolId,
            args.$1.branchId,
            args.$1.enquiryId,
          ),
    );

final admissionCountsProvider = FutureProvider.autoDispose
    .family<Map<AdmissionStatus, int>, BranchKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .countByStatus(key.schoolId, key.branchId),
    );

/// Every follow-up of one enquiry. Invalidated by the UI after each change.
final enquiryActivitiesProvider = FutureProvider.autoDispose
    .family<List<AdmissionActivity>, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchActivitiesForEnquiry(key.schoolId, key.branchId, key.enquiryId),
    );

typedef FollowUpKey = ({String schoolId, String branchId, String userId});

/// Counts for the follow-up dashboard; "today" is the SCHOOL's today.
final followUpCountsProvider = FutureProvider.autoDispose
    .family<FollowUpCounts, FollowUpKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .countFollowUps(
            schoolId: key.schoolId,
            branchId: key.branchId,
            todayKey: SchoolTime.todayKey(),
            userId: key.userId,
          ),
    );

/// The application of an enquiry (null until one is started).
final applicationProvider = StreamProvider.autoDispose
    .family<AdmissionApplication?, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .watchApplication(key.schoolId, key.branchId, key.enquiryId),
    );

/// The document records of an application. Invalidated after each change.
final enquiryDocumentsProvider = FutureProvider.autoDispose
    .family<List<AdmissionDocument>, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchDocuments(key.schoolId, key.branchId, key.enquiryId),
    );

/// The fee records of an enquiry and their payments. Invalidated after each change.
final enquiryFeesProvider = FutureProvider.autoDispose
    .family<List<AdmissionFee>, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchFees(key.schoolId, key.branchId, key.enquiryId),
    );

/// Open admission fees of a branch (Finance's collection list).
final openAdmissionFeesProvider = FutureProvider.autoDispose
    .family<List<AdmissionFee>, BranchKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchOpenFees(key.schoolId, key.branchId),
    );

final enquiryFeePaymentsProvider = FutureProvider.autoDispose
    .family<List<AdmissionFeePayment>, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchFeePayments(key.schoolId, key.branchId, key.enquiryId),
    );

/// The conversion record of an enquiry (null until converted).
final enquiryConversionProvider = FutureProvider.autoDispose
    .family<AdmissionConversion?, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchConversion(key.schoolId, key.branchId, key.enquiryId),
    );

/// What a report is about. [branchId] null = every branch (school admins).
typedef ReportKey = ({
  String schoolId,
  String? branchId,
  String? academicYearId,
  String? from,
  String? to,
});

/// The server-computed admission report for [ReportKey].
final admissionReportProvider = FutureProvider.autoDispose
    .family<AdmissionReport, ReportKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchReport(
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            from: key.from,
            to: key.to,
          ),
    );

/// The application's history; every application event bumps its revision,
/// which is part of the key.
final applicationHistoryProvider = FutureProvider.autoDispose
    .family<List<ApplicationEvent>, (EnquiryKey, int)>(
      (ref, args) => ref
          .watch(admissionRepositoryProvider)
          .fetchApplicationHistory(
            args.$1.schoolId,
            args.$1.branchId,
            args.$1.enquiryId,
          ),
    );

final applicationCountsProvider = FutureProvider.autoDispose
    .family<Map<ApplicationStatus, int>, BranchKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .countApplications(key.schoolId, key.branchId),
    );

/// A person an enquiry can be assigned to: staff of the branch that have a
/// login (the server additionally checks the account is active and in scope).
typedef Assignee = ({String userId, String name});

final assigneesProvider = FutureProvider.autoDispose
    .family<List<Assignee>, BranchKey>((ref, key) async {
      final page = await ref
          .watch(staffRepositoryProvider)
          .fetchStaff(
            schoolId: key.schoolId,
            branchId: key.branchId,
            status: StaffStatus.active,
            pageSize: 100,
          );
      return [
        for (final s in page.items)
          if (s.userId != null)
            (
              userId: s.userId!,
              name: [
                s.firstName,
                s.lastName,
              ].where((p) => p.isNotEmpty).join(' '),
            ),
      ];
    });

/// Runs the admission write callables and exposes loading/error like the
/// other write controllers. Each method returns its result, or null/false on
/// failure (the error stays in [state] for the UI to show).
class AdmissionWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AdmissionRepository get _repo => ref.read(admissionRepositoryProvider);

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    T? out;
    state = await AsyncValue.guard(() async => out = await action());
    return state.hasError ? null : out;
  }

  Future<CreatedEnquiry?> create({
    required String schoolId,
    required String branchId,
    required EnquiryInput input,
    String? assignedTo,
  }) => _run(
    () => _repo.createEnquiry(
      schoolId: schoolId,
      branchId: branchId,
      input: input,
      assignedTo: assignedTo,
    ),
  );

  Future<bool> updateEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required EnquiryInput input,
    int? baseRevision,
  }) async =>
      await _run(
        () => _repo.updateEnquiry(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          input: input,
          baseRevision: baseRevision,
        ),
      ) !=
      null;

  Future<bool> assign({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String? assignedTo,
  }) async =>
      await _run(
        () => _repo.assignEnquiry(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          assignedTo: assignedTo,
        ),
      ) !=
      null;

  Future<bool> changeStatus({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String status,
    String? reason,
    int? baseRevision,
  }) async =>
      await _run(
        () => _repo.changeStatus(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          status: status,
          reason: reason,
          baseRevision: baseRevision,
        ),
      ) !=
      null;

  /// A fresh idempotency key: a retry of the same save never duplicates.
  static String newRequestId() {
    final r = Random.secure();
    return List.generate(20, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  Future<bool> scheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async =>
      await _run(
        () => _repo.scheduleActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          input: input,
          requestId: requestId,
        ),
      ) !=
      null;

  Future<bool> scheduleVisit({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async =>
      await _run(
        () => _repo.scheduleVisit(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          input: input,
          requestId: requestId,
        ),
      ) !=
      null;

  Future<bool> rescheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required String scheduledDate,
    String? scheduledTime,
    String? reason,
  }) async =>
      await _run(
        () => _repo.rescheduleActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          scheduledDate: scheduledDate,
          scheduledTime: scheduledTime,
          reason: reason,
          baseRevision: activity.revision,
        ),
      ) !=
      null;

  Future<bool> reassignActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required String? assignedTo,
  }) async =>
      await _run(
        () => _repo.reassignActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          assignedTo: assignedTo,
          baseRevision: activity.revision,
        ),
      ) !=
      null;

  Future<bool> cancelActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required String reason,
  }) async =>
      await _run(
        () => _repo.cancelActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          reason: reason,
          baseRevision: activity.revision,
        ),
      ) !=
      null;

  Future<bool> completeActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required ActivityCompletion completion,
    ActivityInput? next,
  }) async =>
      await _run<String?>(() async {
        await _repo.completeActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          completion: completion,
          next: next,
          baseRevision: activity.revision,
        );
        return 'ok';
      }) !=
      null;

  AdmissionDocumentStore get _store => ref.read(admissionDocumentStoreProvider);

  Future<bool> createApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
  }) async =>
      await _run(
        () => _repo.createApplication(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
        ),
      ) !=
      null;

  Future<bool> updateApplication({
    required String schoolId,
    required String branchId,
    required AdmissionApplication application,
    required ApplicationInput input,
  }) async =>
      await _run(
        () => _repo.updateApplication(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: application.enquiryId,
          input: input,
          baseRevision: application.revision,
        ),
      ) !=
      null;

  Future<bool> submitApplication({
    required String schoolId,
    required String branchId,
    required AdmissionApplication application,
  }) async =>
      await _run(
        () => _repo.submitApplication(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: application.enquiryId,
          baseRevision: application.revision,
        ),
      ) !=
      null;

  Future<bool> reviewApplication({
    required String schoolId,
    required String branchId,
    required AdmissionApplication application,
    required String action,
    String? comment,
  }) async =>
      await _run(
        () => _repo.reviewApplication(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: application.enquiryId,
          action: action,
          comment: comment,
          baseRevision: action == 'COMMENT' ? null : application.revision,
        ),
      ) !=
      null;

  Future<bool> decideApplication({
    required String schoolId,
    required String branchId,
    required AdmissionApplication application,
    required String decision,
    String? comment,
  }) async =>
      await _run(
        () => _repo.decideApplication(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: application.enquiryId,
          decision: decision,
          comment: comment,
          baseRevision: application.revision,
        ),
      ) !=
      null;

  /// How long to wait before re-sending bytes that failed to upload (shortened
  /// in tests).
  static Duration uploadRetryDelay = const Duration(seconds: 2);

  /// Uploads one file: ask the server, put the bytes at the approved path
  /// (retrying a few times — a flaky network must not lose the document), then
  /// ask the server to confirm what arrived. A file that fails the local limits
  /// is never sent.
  Future<bool> uploadDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String type,
    required String fileName,
    required List<int> bytes,
  }) async {
    final photo = photoDocumentTypes.contains(type);
    final problem = DocumentLimits.problem(
      fileName: fileName,
      sizeBytes: bytes.length,
      photo: photo,
    );
    if (problem != null) {
      state = AsyncError(ValidationFailure(problem), StackTrace.current);
      return false;
    }
    final contentType = DocumentLimits.contentTypeFor(fileName, photo: photo)!;
    return await _run(() async {
          final intent = await _repo.requestDocumentUpload(
            schoolId: schoolId,
            branchId: branchId,
            enquiryId: enquiryId,
            type: type,
            fileName: fileName,
            contentType: contentType,
            sizeBytes: bytes.length,
            requestId: newRequestId(),
          );
          Object? last;
          for (var attempt = 0; attempt < 3; attempt++) {
            try {
              await _store.upload(
                path: intent.storagePath,
                bytes: bytes,
                contentType: contentType,
              );
              last = null;
              break;
            } catch (e) {
              last = e;
              if (attempt < 2) await Future<void>.delayed(uploadRetryDelay);
            }
          }
          if (last != null) throw last;
          await _repo.confirmDocumentUpload(
            schoolId: schoolId,
            branchId: branchId,
            enquiryId: enquiryId,
            documentId: intent.id,
          );
          return true;
        }) ??
        false;
  }

  // ---- admission fees (phase 7) ---------------------------------------

  Future<bool> setFee({
    required EnquiryKey key,
    required FeeCategory category,
    required int amountMinor,
    String? feeStructureId,
    String? dueDate,
    String? note,
    int? baseRevision,
  }) async =>
      await _run(() async {
        await _repo.setFee(
          schoolId: key.schoolId,
          branchId: key.branchId,
          enquiryId: key.enquiryId,
          category: category,
          amountMinor: amountMinor,
          feeStructureId: feeStructureId,
          dueDate: dueDate,
          note: note,
          baseRevision: baseRevision,
        );
        return true;
      }) ??
      false;

  Future<bool> cancelFee({
    required EnquiryKey key,
    required FeeCategory category,
    required String reason,
  }) async =>
      await _run(() async {
        await _repo.cancelFee(
          schoolId: key.schoolId,
          branchId: key.branchId,
          enquiryId: key.enquiryId,
          category: category,
          reason: reason,
        );
        return true;
      }) ??
      false;

  Future<bool> waiveFee({
    required EnquiryKey key,
    required FeeCategory category,
    required String reason,
  }) async =>
      await _run(() async {
        await _repo.waiveFee(
          schoolId: key.schoolId,
          branchId: key.branchId,
          enquiryId: key.enquiryId,
          category: category,
          reason: reason,
        );
        return true;
      }) ??
      false;

  /// The receipt number, or null on failure. [requestId] is created once per
  /// dialog so a double tap or a retry never records the payment twice.
  Future<String?> recordPayment({
    required EnquiryKey key,
    required FeeCategory category,
    required String requestId,
    required int amountMinor,
    required AdmissionPaymentMethod method,
    String? referenceNo,
    String? paymentDate,
    String? notes,
  }) => _run(
    () => _repo.recordPayment(
      schoolId: key.schoolId,
      branchId: key.branchId,
      enquiryId: key.enquiryId,
      category: category,
      requestId: requestId,
      amountMinor: amountMinor,
      method: method,
      referenceNo: referenceNo,
      paymentDate: paymentDate,
      notes: notes,
    ),
  );

  Future<bool> refund({
    required EnquiryKey key,
    required FeeCategory category,
    required String requestId,
    required int amountMinor,
    required AdmissionPaymentMethod method,
    required String reason,
    String? referenceNo,
  }) async =>
      await _run(() async {
        await _repo.refund(
          schoolId: key.schoolId,
          branchId: key.branchId,
          enquiryId: key.enquiryId,
          category: category,
          requestId: requestId,
          amountMinor: amountMinor,
          method: method,
          reason: reason,
          referenceNo: referenceNo,
        );
        return true;
      }) ??
      false;

  /// Converts the approved application into a student; null on failure.
  Future<ConversionResult?> convertToStudent({
    required EnquiryKey key,
    required ConversionInput input,
  }) => _run(
    () => _repo.convertToStudent(
      schoolId: key.schoolId,
      branchId: key.branchId,
      enquiryId: key.enquiryId,
      input: input,
    ),
  );

  Future<bool> verifyDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionDocument document,
    required bool verify,
    String? reason,
  }) async =>
      await _run(() async {
        await _repo.verifyDocument(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          documentId: document.id,
          decision: verify ? 'VERIFY' : 'REJECT',
          reason: reason,
          baseRevision: document.revision,
        );
        return true;
      }) ??
      false;

  Future<bool> removeDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionDocument document,
    String? reason,
  }) async =>
      await _run(() async {
        await _repo.removeDocument(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          documentId: document.id,
          reason: reason,
        );
        return true;
      }) ??
      false;

  /// The bytes of a stored document, for the viewer.
  Future<List<int>> readDocument(AdmissionDocument d) =>
      _store.read(d.storagePath);

  Future<bool> saveSettings({
    required String schoolId,
    required AdmissionSettings settings,
  }) async =>
      await _run(
        () => _repo.saveSettings(
          schoolId: schoolId,
          settings: settings,
          baseVersion: settings.version,
        ),
      ) !=
      null;
}

final admissionWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<AdmissionWriteController, void>(
      AdmissionWriteController.new,
    );
