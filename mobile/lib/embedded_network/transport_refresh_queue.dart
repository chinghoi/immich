import 'dart:async';

/// Serialize a refresh and remember a transport change that arrives mid-handoff.
class TransportRefreshQueue {
  Future<void>? _running;
  bool _pending = false;

  Future<void> run(Future<void> Function() operation, {bool refresh = false}) {
    final running = _running;
    if (running != null) {
      _pending = _pending || refresh;
      return running;
    }
    return _running = Future<void>(() async {
      do {
        _pending = false;
        await operation();
      } while (_pending);
    }).whenComplete(() => _running = null);
  }
}
