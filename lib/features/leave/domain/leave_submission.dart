import '../../academic_setup/domain/holiday.dart';
import '../../academic_setup/domain/working_days.dart';
import 'leave_application.dart';
import 'leave_balance.dart';
import 'leave_days.dart';
import 'leave_enums.dart';
import 'leave_type.dart';
import 'leave_units.dart';
import 'leave_workflow.dart';

/// Everything a submission screen needs to show *before* the user commits:
/// the counted days, any blocking error, any (non-blocking) warning.
class SubmissionPlan {
  final LeaveDaySpan? span;
  final String? error;
  final String? warning;
  final LeaveBalanceFigures? figures;

  const SubmissionPlan({this.span, this.error, this.warning, this.figures});

  bool get canSubmit => error == null && (span?.isValid ?? false);
  int get units => span?.units ?? 0;
}

/// The single place a leave application is validated and priced. The forms,
/// the portals and the admin on-behalf flow all call this — day counting,
/// type policy, overlap and balance are never re-derived in a widget.
abstract final class LeaveSubmissionPlanner {
  static SubmissionPlan plan({
    required LeaveType? type,
    required String startKey,
    required String endKey,
    required HalfDay halfDay,
    required String? reason,
    required int attachmentCount,
    required WorkingDays workingDays,
    required Iterable<Holiday> calendarEntries,
    required String yearStartKey,
    required String yearEndKey,
    required Iterable<LeaveApplication> existing,
    required String applicantRole,
    String? employmentType,
    LeaveBalance? balance,
    int pendingUnits = 0,
    required String todayKey,
    String? ignoreApplicationId,
  }) {
    if (type == null) {
      return const SubmissionPlan(error: 'Choose a leave type.');
    }
    final span = LeaveDayCalculator.compute(
      startKey: startKey,
      endKey: endKey,
      halfDay: halfDay,
      type: type,
      workingDays: workingDays,
      calendarEntries: calendarEntries,
      yearStartKey: yearStartKey,
      yearEndKey: yearEndKey,
    );
    if (!span.isValid) return SubmissionPlan(span: span, error: span.error);

    final policyError = LeaveWorkflow.checkApply(
      type: type,
      spanUnits: span.units,
      reason: reason,
      attachmentCount: attachmentCount,
      applicantRole: applicantRole,
      employmentType: employmentType,
    );
    if (policyError != null) {
      return SubmissionPlan(span: span, error: policyError);
    }

    final overlap = LeaveWorkflow.findOverlap(
      existing: existing,
      countedDateKeys: span.countedDateKeys,
      halfDay: halfDay,
      ignoreApplicationId: ignoreApplicationId,
    );
    if (overlap != null) {
      return SubmissionPlan(
        span: span,
        error: LeaveWorkflow.overlapMessage(overlap),
      );
    }

    LeaveBalanceFigures? figures;
    String? warning;
    if (type.tracksBalance) {
      final b =
          balance ??
          LeaveBalance.fromPolicy(
            schoolId: type.schoolId,
            branchId: type.branchId,
            staffId: '-',
            type: type,
            academicYearId: '-',
            leaveYearStartKey: yearStartKey,
          );
      figures = LeaveBalanceMath.figures(
        balance: b,
        todayKey: todayKey,
        pendingUnits: pendingUnits,
      );
      final check = LeaveBalanceMath.check(
        figures: figures,
        requestUnits: span.units,
        policy: b.exceedPolicy,
      );
      if (!check.allowed) {
        return SubmissionPlan(
          span: span,
          figures: figures,
          error: check.message,
        );
      }
      if (check.warning) {
        warning =
            '${check.message} The application can be submitted, but the '
            'reviewer will see that it exceeds the balance.';
      } else if (pendingUnits > 0 &&
          span.units > figures.availableIfPendingApproved) {
        warning =
            'You already have ${LeaveUnits.formatDays(pendingUnits)} awaiting '
            'approval; if those are approved there may not be enough left.';
      }
    }
    return SubmissionPlan(span: span, warning: warning, figures: figures);
  }
}

/// Which approved leaves cover which subjects on one date — what attendance
/// screens overlay. Read-only: attendance records are never written from here.
abstract final class LeaveAttendanceOverlay {
  static Map<String, LeaveCalendarEntry> forDate(
    Iterable<LeaveCalendarEntry> entries,
    String dateKey,
  ) {
    final result = <String, LeaveCalendarEntry>{};
    for (final e in entries) {
      if (!e.coversDate(dateKey)) continue;
      final existing = result[e.subjectId];
      // A full-day entry wins over a half-day one for display.
      if (existing == null || existing.halfDay != HalfDay.none) {
        result[e.subjectId] = e;
      }
    }
    return result;
  }

  static String label(LeaveCalendarEntry e) => switch (e.halfDay) {
    HalfDay.none => 'On approved leave',
    HalfDay.first => 'On approved leave (first half)',
    HalfDay.second => 'On approved leave (second half)',
  };
}
