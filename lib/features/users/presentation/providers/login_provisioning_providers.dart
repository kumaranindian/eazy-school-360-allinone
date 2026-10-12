import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_login_provisioner.dart';
import '../../domain/login_provisioning.dart';

final loginProvisionerProvider = Provider<LoginProvisioner>(
  (ref) => FirebaseLoginProvisioner(FirebaseFunctions.instance),
  retry: (retryCount, error) => null,
);
