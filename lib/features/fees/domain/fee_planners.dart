import 'billing_period.dart';
import 'fee_structure.dart';
import 'invoice.dart';
import 'student_fee_assignment.dart';

/// A student as the planners see them (already resolved by the repository).
class FeeStudent {
  final String studentId;
  final String name;
  final String admissionNumber;
  final String classId;
  final String className;
  final String? sectionId;
  final String sectionName;

  /// Active in the school and placed in the academic year being billed.
  final bool isEnrolled;

  const FeeStudent({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.classId,
    required this.className,
    this.sectionId,
    required this.sectionName,
    required this.isEnrolled,
  });
}

class SkippedItem {
  final String studentName;
  final String reason;

  const SkippedItem(this.studentName, this.reason);
}

// ---------------------------------------------------------------------------
// Bulk assignment
// ---------------------------------------------------------------------------

class PlannedAssignment {
  final FeeStudent student;
  final FeeStructure structure;

  const PlannedAssignment(this.student, this.structure);
}

class AssignmentPlan {
  final List<PlannedAssignment> toCreate;
  final List<SkippedItem> skipped;

  const AssignmentPlan({required this.toCreate, required this.skipped});

  /// Fee head name -> (students, total of the structure amounts, before any concession).
  Map<String, ({int students, int totalMinor})> get breakdown {
    final result = <String, ({int students, int totalMinor})>{};
    for (final p in toCreate) {
      final current = result[p.structure.name] ?? (students: 0, totalMinor: 0);
      result[p.structure.name] = (
        students: current.students + 1,
        totalMinor: current.totalMinor + p.structure.amountMinor,
      );
    }
    return result;
  }

  int get totalMinor => toCreate.fold(0, (s, p) => s + p.structure.amountMinor);
}

/// Decides, from facts only, who gets which fee head. Never charges a student
/// who is not eligible, and never creates a second assignment for the same
/// student and fee head.
abstract final class AssignmentPlanner {
  static AssignmentPlan plan({
    required List<FeeStudent> students,
    required List<FeeStructure> structures,
    required String academicYearId,
    required Set<String> existingAssignmentIds,
  }) {
    final toCreate = <PlannedAssignment>[];
    final skipped = <SkippedItem>[];

    for (final student in students) {
      if (!student.isEnrolled) {
        skipped.add(
          SkippedItem(
            student.name,
            'Not currently enrolled in this academic year',
          ),
        );
        continue;
      }
      for (final structure in structures) {
        if (!structure.isActive) {
          skipped.add(
            SkippedItem(student.name, '${structure.name} is inactive'),
          );
          continue;
        }
        if (structure.academicYearId != academicYearId) {
          skipped.add(
            SkippedItem(
              student.name,
              '${structure.name} belongs to a different academic year',
            ),
          );
          continue;
        }
        if (!structure.appliesTo(
          classId: student.classId,
          sectionId: student.sectionId,
        )) {
          skipped.add(
            SkippedItem(
              student.name,
              '${structure.name} does not apply to ${student.className} ${student.sectionName}',
            ),
          );
          continue;
        }
        if (existingAssignmentIds.contains(
          StudentFeeAssignment.idFor(student.studentId, structure.structureId),
        )) {
          skipped.add(
            SkippedItem(student.name, '${structure.name} is already assigned'),
          );
          continue;
        }
        toCreate.add(PlannedAssignment(student, structure));
      }
    }
    return AssignmentPlan(toCreate: toCreate, skipped: skipped);
  }
}

// ---------------------------------------------------------------------------
// Invoice generation
// ---------------------------------------------------------------------------

/// A student's active assignment paired with the structure it points at.
class BillableAssignment {
  final StudentFeeAssignment assignment;
  final FeeStructure? structure;

  const BillableAssignment(this.assignment, this.structure);
}

class ProposedInvoice {
  final FeeStudent student;
  final String invoiceId;
  final List<InvoiceLine> lines;
  final String dueDateKey;

  const ProposedInvoice({
    required this.student,
    required this.invoiceId,
    required this.lines,
    required this.dueDateKey,
  });

  int get subtotalMinor => InvoiceMath.subtotal(lines);
  int get discountMinor => InvoiceMath.discount(lines);
  int get payableMinor => subtotalMinor - discountMinor;
}

class InvoicePlan {
  final List<ProposedInvoice> proposals;
  final List<SkippedItem> skipped;

  const InvoicePlan({required this.proposals, required this.skipped});

  int get subtotalMinor => proposals.fold(0, (s, p) => s + p.subtotalMinor);
  int get discountMinor => proposals.fold(0, (s, p) => s + p.discountMinor);
  int get payableMinor => proposals.fold(0, (s, p) => s + p.payableMinor);
}

/// Works out the invoices a billing run would create — the preview shown
/// before anything is written, and the exact list that is then written.
///
/// A line is billed when: the student is enrolled; the assignment is active;
/// its structure exists, is active, matches this period's kind and is
/// effective on the issue date; and that (assignment, period) has not already
/// been charged (`feeCharges`; a one-time fee only ever once). A student whose
/// invoice for this period already exists is skipped — which is also what
/// makes retrying a half-finished bulk run safe.
abstract final class InvoicePlanner {
  static InvoicePlan plan({
    required List<FeeStudent> students,
    required Map<String, List<BillableAssignment>> assignmentsByStudent,
    required BillingPeriod period,
    required String academicYearId,
    required String issueDateKey,
    String? dueDateKeyOverride,
    required Set<String> existingChargeIds,
    required Set<String> existingInvoiceIds,
    required String Function(String issueDateKey, int days) addDays,
  }) {
    final proposals = <ProposedInvoice>[];
    final skipped = <SkippedItem>[];

    for (final student in students) {
      final invoiceId = BillingPeriod.invoiceId(
        student.studentId,
        academicYearId,
        period.key,
      );
      if (existingInvoiceIds.contains(invoiceId)) {
        skipped.add(
          SkippedItem(student.name, 'Already invoiced for ${period.label}'),
        );
        continue;
      }
      if (!student.isEnrolled) {
        skipped.add(
          SkippedItem(
            student.name,
            'Not currently enrolled in this academic year',
          ),
        );
        continue;
      }

      final lines = <InvoiceLine>[];
      // Why an assigned fee was left off — surfaced when nothing is billed,
      // so "nothing to invoice" is never a mystery.
      final whyNot = <String>{};
      var maxOffset = 0;
      var sawAssignment = false;
      for (final item
          in assignmentsByStudent[student.studentId] ??
              const <BillableAssignment>[]) {
        final a = item.assignment;
        final s = item.structure;
        if (!a.isActive || a.academicYearId != academicYearId) continue;
        sawAssignment = true;
        if (s == null) {
          whyNot.add('an assigned fee structure no longer exists');
          continue;
        }
        if (!s.isActive) {
          whyNot.add('"${s.name}" is inactive');
          continue;
        }
        if (s.frequency != period.kind) {
          whyNot.add(
            '"${s.name}" is ${s.frequency.displayName.toLowerCase()}, '
            'not ${period.kind.displayName.toLowerCase()}',
          );
          continue;
        }
        if (!s.isEffectiveOn(issueDateKey)) {
          whyNot.add('"${s.name}" is not effective on the issue date');
          continue;
        }
        final chargeId =
            '${a.assignmentId}__${BillingPeriod.chargeKeyFor(s.frequency, period.key)}';
        if (existingChargeIds.contains(chargeId)) {
          whyNot.add('"${s.name}" was already billed for ${period.label}');
          continue;
        }

        final discount = a.concessionFor(s.amountMinor);
        lines.add(
          InvoiceLine(
            assignmentId: a.assignmentId,
            structureId: s.structureId,
            name: s.name,
            category: s.category,
            description: s.description,
            amountMinor: s.amountMinor,
            discountMinor: discount,
            concessionNote: discount > 0 ? a.concessionReason : null,
            chargeId: chargeId,
          ),
        );
        if (s.dueOffsetDays > maxOffset) maxOffset = s.dueOffsetDays;
      }

      if (lines.isEmpty) {
        skipped.add(
          SkippedItem(
            student.name,
            sawAssignment
                ? 'No ${period.kind.displayName.toLowerCase()} fees to bill for ${period.label}'
                      '${whyNot.isEmpty ? '' : ' — ${whyNot.join('; ')}'}'
                : 'No fees assigned',
          ),
        );
        continue;
      }
      final proposal = ProposedInvoice(
        student: student,
        invoiceId: invoiceId,
        lines: lines,
        dueDateKey: dueDateKeyOverride ?? addDays(issueDateKey, maxOffset),
      );
      if (proposal.payableMinor <= 0) {
        skipped.add(
          SkippedItem(student.name, 'Fully concessed — nothing to bill'),
        );
        continue;
      }
      proposals.add(proposal);
    }
    return InvoicePlan(proposals: proposals, skipped: skipped);
  }
}

// ---------------------------------------------------------------------------
// Student-wise summary
// ---------------------------------------------------------------------------

/// A student's position across invoices (void invoices excluded).
class StudentFeeSummary {
  final int payableMinor;
  final int waivedMinor;
  final int paidMinor;
  final int balanceMinor;
  final int overdueMinor;
  final int upcomingMinor;

  const StudentFeeSummary({
    required this.payableMinor,
    required this.waivedMinor,
    required this.paidMinor,
    required this.balanceMinor,
    required this.overdueMinor,
    required this.upcomingMinor,
  });

  factory StudentFeeSummary.of(
    Iterable<Invoice> invoices, {
    required String todayKey,
  }) {
    var payable = 0,
        waived = 0,
        paid = 0,
        balance = 0,
        overdue = 0,
        upcoming = 0;
    for (final i in invoices.where((i) => !i.isVoid)) {
      payable += i.payableMinor;
      waived += i.waivedMinor;
      paid += i.paidMinor;
      balance += i.balanceMinor;
      if (i.isOverdue(todayKey)) {
        overdue += i.balanceMinor;
      } else if (i.status.isOpen) {
        upcoming += i.balanceMinor;
      }
    }
    return StudentFeeSummary(
      payableMinor: payable,
      waivedMinor: waived,
      paidMinor: paid,
      balanceMinor: balance,
      overdueMinor: overdue,
      upcomingMinor: upcoming,
    );
  }
}
