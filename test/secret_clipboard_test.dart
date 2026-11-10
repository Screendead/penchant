import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/journal_key/secret_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(SecretClipboard.channelName);
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const String secret = 'ABCD-EFGH-JKLM';

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends the text and lifetime to the native pasteboard only', () async {
    final List<MethodCall> calls = <MethodCall>[];
    final List<MethodCall> platformCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      platformCalls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await const SecretClipboard().copy(secret);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'copy');
    expect(calls.single.arguments, <String, Object>{
      'text': secret,
      'seconds': SecretClipboard.lifetime.inSeconds,
    });
    expect(
      platformCalls.where((MethodCall c) => c.method == 'Clipboard.setData'),
      isEmpty,
    );
  });

  test('a native failure throws without the secret', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'x', message: secret);
    });

    await expectLater(
      const SecretClipboard().copy(secret),
      throwsA(
        isA<SecretClipboardException>().having(
          (SecretClipboardException e) => e.toString(),
          'message',
          isNot(contains(secret)),
        ),
      ),
    );
  });

  test('no native handler throws rather than falling back', () async {
    await expectLater(
      const SecretClipboard().copy(secret),
      throwsA(isA<SecretClipboardException>()),
    );
  });
}
