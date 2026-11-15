import '../../school_setup/domain/branch.dart';
import '../../school_setup/domain/school.dart';

/// The school details printed at the top of every bill, invoice and receipt.
/// The branch's own address and contacts win; the school's fill any gap.
class FeeLetterhead {
  final String schoolName;
  final String branchName;
  final List<String> addressLines;
  final String contactLine;

  const FeeLetterhead({
    this.schoolName = '',
    this.branchName = '',
    this.addressLines = const [],
    this.contactLine = '',
  });

  /// Only what the stored document snapshot knows (used when the school or
  /// branch record cannot be read; printing must never fail because of it).
  factory FeeLetterhead.named(String schoolName, String branchName) =>
      FeeLetterhead(schoolName: schoolName, branchName: branchName);

  static String _clean(String? v) => (v ?? '').trim();

  factory FeeLetterhead.from({
    required School? school,
    required Branch? branch,
    String fallbackSchoolName = '',
    String fallbackBranchName = '',
  }) {
    String pick(String? a, String? b) =>
        _clean(a).isNotEmpty ? _clean(a) : _clean(b);

    final line1 = pick(branch?.addressLine1, school?.addressLine1);
    final useBranchAddress = _clean(branch?.addressLine1).isNotEmpty;
    final line2 = useBranchAddress
        ? _clean(branch?.addressLine2)
        : _clean(school?.addressLine2);
    final city = useBranchAddress ? _clean(branch?.city) : _clean(school?.city);
    final state = useBranchAddress
        ? _clean(branch?.state)
        : _clean(school?.state);
    final postal = useBranchAddress
        ? _clean(branch?.postalCode)
        : _clean(school?.postalCode);
    final cityLine = [
      [city, state].where((e) => e.isNotEmpty).join(', '),
      postal,
    ].where((e) => e.isNotEmpty).join(' - ');

    final phone = pick(branch?.phone, school?.phone);
    final email = pick(branch?.email, school?.email);
    final website = _clean(school?.website);
    final contact = [
      if (phone.isNotEmpty) 'Ph: $phone',
      if (email.isNotEmpty) email,
      if (website.isNotEmpty) website,
    ].join('  |  ');

    final schoolName = _clean(school?.name).isNotEmpty
        ? _clean(school?.name)
        : fallbackSchoolName;
    final branchName = _clean(branch?.name).isNotEmpty
        ? _clean(branch?.name)
        : fallbackBranchName;

    return FeeLetterhead(
      schoolName: schoolName,
      branchName: branchName,
      addressLines: [
        for (final l in [line1, line2, cityLine])
          if (l.isNotEmpty) l,
      ],
      contactLine: contact,
    );
  }
}
