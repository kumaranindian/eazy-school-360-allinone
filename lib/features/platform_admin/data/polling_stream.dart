import 'dart:async';

/// Emits [fetch]'s result now and then every [every], while someone listens. A
/// failed fetch is reported as an error event and polling carries on, so a
/// network blip heals itself. Used for platform data the Firestore rules do not
/// expose (read through callables instead).
Stream<T> pollingStream<T>(Future<T> Function() fetch, Duration every) {
  late final StreamController<T> controller;
  Timer? timer;
  var busy = false;

  Future<void> tick() async {
    if (busy || controller.isClosed) return;
    busy = true;
    try {
      final value = await fetch();
      if (!controller.isClosed) controller.add(value);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      busy = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      unawaited(tick());
      timer = Timer.periodic(every, (_) => unawaited(tick()));
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  return controller.stream;
}
