import 'dart:async';

import 'package:eazy_school_360/features/notifications/domain/push_gateway.dart';

/// A scriptable device-side messaging service.
class FakePushGateway implements PushGateway {
  @override
  bool supported;
  @override
  String platform;
  @override
  bool requiresUserGesture;
  PushPermission current;

  /// What the OS answers when asked.
  bool grantsWhenAsked;
  String? token;
  Map<String, String>? launch;

  final List<String> calls = [];
  final refresh = StreamController<String>.broadcast();
  final opened = StreamController<Map<String, String>>.broadcast();

  FakePushGateway({
    this.supported = true,
    this.platform = 'android',
    this.requiresUserGesture = false,
    this.current = PushPermission.undetermined,
    this.grantsWhenAsked = true,
    this.token = 'tokenAAAAAAAAAAAAAAAAAAAAAAAA',
    this.launch,
  });

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<bool> requestPermission() async {
    calls.add('request');
    if (grantsWhenAsked) current = PushPermission.granted;
    return grantsWhenAsked;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> deleteToken() async => calls.add('deleteToken');

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Stream<Map<String, String>> get onOpened => opened.stream;

  @override
  Future<Map<String, String>?> launchedBy() async => launch;
}
