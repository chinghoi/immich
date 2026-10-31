import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/embedded_network/transport_refresh_queue.dart';

void main() {
  test('transport changes during an in-flight native handoff are not lost', () async {
    final queue = TransportRefreshQueue(), gate = Completer<void>(), started = Completer<void>();
    var count = 0, active = 0, overlap = false;
    Future<void> refresh() async {
      if (++active > 1) overlap = true;
      count++;
      if (count == 1) { started.complete(); await gate.future; }
      active--;
    }
    final first = queue.run(refresh);
    await started.future;
    final second = queue.run(refresh, refresh: true);
    final third = queue.run(refresh, refresh: true);
    gate.complete();
    await Future.wait([first, second, third]);
    expect(count, 2);
    expect(overlap, isFalse);
  });
  test('a failed refresh can be retried instead of poisoning later resumes', () async {
    final queue = TransportRefreshQueue();
    await expectLater(queue.run(() async { throw StateError('fixture'); }), throwsStateError);
    var recovered = false;
    await queue.run(() async { recovered = true; });
    expect(recovered, isTrue);
  });
}
