import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/writes/quit_when_synced.dart';

void main() {
  test('exits at once when nothing is pending', () async {
    expect(await exitWhenSynced(() async {}), AppExitResponse.exit);
  });

  test('waits for the acknowledgement, then exits', () {
    fakeAsync((FakeAsync async) {
      final Completer<void> acknowledged = Completer<void>();
      AppExitResponse? answer;
      exitWhenSynced(() => acknowledged.future).then((a) => answer = a);
      async.elapse(const Duration(seconds: 1));
      expect(answer, isNull);
      acknowledged.complete();
      async.flushMicrotasks();
      expect(answer, AppExitResponse.exit);
    });
  });

  test('exits after the limit when the server never answers', () {
    fakeAsync((FakeAsync async) {
      AppExitResponse? answer;
      exitWhenSynced(() => Completer<void>().future).then((a) => answer = a);
      async.elapse(quitSyncLimit - const Duration(milliseconds: 1));
      expect(answer, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(answer, AppExitResponse.exit);
    });
  });

  test('exits when the wait fails', () async {
    expect(
      await exitWhenSynced(() async => throw StateError('terminated')),
      AppExitResponse.exit,
    );
  });
}
