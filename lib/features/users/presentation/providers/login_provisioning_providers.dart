import '../../../../core/config/functions_region.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_login_provisioner.dart';
import '../../domain/login_provisioning.dart';

final loginProvisionerProvider = Provider<LoginProvisioner>(
  (ref) => FirebaseLoginProvisioner(appFunctions()),
  retry: (retryCount, error) => null,
);
