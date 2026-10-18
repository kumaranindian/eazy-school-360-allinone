import 'package:eazy_school_360/core/regional/regional_settings.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/auth_repository.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/authentication/domain/phone_otp.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_repository.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_repository.dart';

/// In-memory [AuthRepository] fake. These tests never touch real
/// Firebase — the whole point of the repository interfaces.
class FakeAuthRepository implements AuthRepository {
  AppUser? _current;

  /// How the fake session was "established" (checked against `login`).
  LoginMethod? signInMethod;

  /// When set, phone OTP calls throw it; [verifiedCodes] records good codes.
  Object? otpError;
  final List<String> requestedPhones = [];
  final List<String> verifiedCodes = [];

  FakeAuthRepository({
    AppUser? signedInAs,
    this.signInMethod = LoginMethod.password,
  }) : _current = signedInAs;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_current);

  @override
  AppUser? get currentUser => _current;

  @override
  Future<AppUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _current = AppUser(uid: 'fake-uid', email: email);
    return _current!;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    _current = const AppUser(
      uid: 'fake-google-uid',
      email: 'fake-google@example.com',
    );
    return _current!;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _current = AppUser(uid: 'fake-uid', email: email);
    return _current!;
  }

  @override
  Future<OtpChallenge> requestPhoneOtp(String phone) async {
    if (otpError != null) throw otpError!;
    requestedPhones.add(phone);
    return const OtpChallenge(
      challengeId: 'fake-challenge',
      expiresIn: Duration(minutes: 5),
      resendAfter: Duration(seconds: 60),
    );
  }

  @override
  Future<AppUser> verifyPhoneOtp({
    required String challengeId,
    required String code,
  }) async {
    if (otpError != null) throw otpError!;
    verifiedCodes.add(code);
    _current = const AppUser(uid: 'fake-phone-uid', email: null);
    signInMethod = LoginMethod.phoneOtp;
    return _current!;
  }

  @override
  Future<LoginMethod?> currentSignInMethod() async => signInMethod;

  @override
  Future<void> signOut() async {
    _current = null;
  }
}

class FakeUserRepository implements UserRepository {
  final Map<String, UserProfile> profiles;

  FakeUserRepository([Map<String, UserProfile>? profiles])
    : profiles = profiles ?? {};

  @override
  Future<UserProfile?> getUserProfile(String userId) async => profiles[userId];

  @override
  Stream<UserProfile?> watchUserProfile(String userId) =>
      Stream.value(profiles[userId]);

  @override
  Future<void> updateOwnProfile(UserProfile profile) async {
    profiles[profile.userId] = profile;
  }
}

class FakeSchoolRepository implements SchoolRepository {
  final Map<String, School> schools;
  final Map<String, Branch> branches;

  FakeSchoolRepository({
    Map<String, School>? schools,
    Map<String, Branch>? branches,
  }) : schools = schools ?? {},
       branches = branches ?? {};

  @override
  Future<School?> getSchool(String schoolId) async => schools[schoolId];

  @override
  Future<Branch?> getBranch(String schoolId, String branchId) async =>
      branches['$schoolId/$branchId'];

  @override
  Stream<List<Branch>> watchBranches(String schoolId) {
    return Stream.value(
      branches.values.where((b) => b.schoolId == schoolId).toList(),
    );
  }

  @override
  Future<void> updateSchoolProfile(
    School school, {
    required String updatedBy,
  }) async {
    schools[school.schoolId] = school;
  }

  @override
  Future<void> updateSchoolRegional(
    School school, {
    required String updatedBy,
  }) async {
    schools[school.schoolId] = school;
  }

  @override
  Future<String> uploadSchoolLogo({
    required String schoolId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) async {
    return 'https://fake.storage/schools/$schoolId/logo.$fileExtension';
  }

  @override
  Future<String> createBranch(
    Branch branch, {
    required String createdBy,
  }) async {
    final id = branch.branchId.isEmpty
        ? 'fake-branch-${branches.length}'
        : branch.branchId;
    branches['${branch.schoolId}/$id'] = Branch(
      branchId: id,
      schoolId: branch.schoolId,
      name: branch.name,
      code: branch.code,
      email: branch.email,
      phone: branch.phone,
      status: branch.status,
    );
    return id;
  }

  @override
  Future<void> updateBranch(Branch branch, {required String updatedBy}) async {
    branches['${branch.schoolId}/${branch.branchId}'] = branch;
  }

  @override
  Future<String> createSchoolForCurrentUser({
    required String userId,
    required String userName,
    required String userEmail,
    required String schoolName,
    required String schoolEmail,
    String? schoolPhone,
    required RegionalSettings regional,
  }) async {
    throw UnimplementedError('Not needed by current tests');
  }
}
