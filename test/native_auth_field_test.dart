import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/widgets/auth_parts.dart';
import 'package:tracker/widgets/native_auth_field.dart';

const StandardMethodCodec _codec = StandardMethodCodec();

Future<void> _fromNative(String channel, String method, Object? args) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel,
          _codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeAuthFieldsChannel', () {
    late List<MethodCall> sent;
    late NativeAuthFieldsChannel channel;
    final List<Map<String, String>> changed = <Map<String, String>>[];
    final List<String> events = <String>[];

    setUp(() {
      sent = <MethodCall>[];
      changed.clear();
      events.clear();
      channel = NativeAuthFieldsChannel(
        7,
        onChanged: changed.add,
        onSubmitted: (String field, String text) =>
            events.add('submitted $field $text'),
        onFocusChanged: (String field, bool focused) =>
            events.add('focus $field $focused'),
        onTab: (String field, bool forward) =>
            events.add('tab $field $forward'),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel.name), (
            MethodCall call,
          ) async {
            sent.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel.name), null);
      channel.dispose();
    });

    test('is named for its view', () {
      expect(channel.name, 'penchant/auth_fields/7');
    });

    test('sends text, focus, obscuring, configuration and layout, '
        'each naming its field', () async {
      await channel.setText('email', 'a@b.co');
      await channel.setObscured('password', false);
      await channel.focus('password');
      await channel.blur('email');
      await channel.configure(
        'password',
        NativeAuthFieldsChannel.configuration(
          kind: NativeAuthFieldKind.newPassword,
          placeholder: 'Password',
          textColor: const Color(0xFF102030),
          placeholderColor: const Color(0x80405060),
          caretColor: const Color(0xFFFF0000),
        ),
      );
      await channel.layout(<String, List<double>>{
        'email': <double>[0, 0, 200, 52],
      });
      expect(sent.map((MethodCall c) => c.method), <String>[
        'setText',
        'setObscured',
        'focus',
        'blur',
        'configure',
        'layout',
      ]);
      expect(sent[0].arguments, <String, Object>{
        'field': 'email',
        'text': 'a@b.co',
      });
      expect(sent[1].arguments, <String, Object>{
        'field': 'password',
        'obscured': false,
      });
      expect(sent[2].arguments, <String, Object>{'field': 'password'});
      expect(sent[4].arguments, <String, Object>{
        'field': 'password',
        'kind': 'newPassword',
        'placeholder': 'Password',
        'textColor': 0xFF102030,
        'placeholderColor': 0x80405060,
        'caretColor': 0xFFFF0000,
      });
      expect(sent[5].arguments, <String, Object>{
        'email': <double>[0, 0, 200, 52],
      });
    });

    test('hands native events to its callbacks', () async {
      await _fromNative(channel.name, 'changed', <String, Object>{
        'email': 'me@example.com',
        'password': 'secret',
      });
      await _fromNative(channel.name, 'submitted', <String, Object>{
        'field': 'password',
        'text': 'secret',
      });
      await _fromNative(channel.name, 'focusChanged', <String, Object>{
        'field': 'email',
        'focused': true,
      });
      await _fromNative(channel.name, 'tab', <String, Object>{
        'field': 'password',
        'forward': false,
      });
      expect(changed, <Map<String, String>>[
        <String, String>{'email': 'me@example.com', 'password': 'secret'},
      ]);
      expect(events, <String>[
        'submitted password secret',
        'focus email true',
        'tab password false',
      ]);
    });
  });

  testWidgets('forced native AuthFields share one view over their text areas, '
      'keep their controllers in step and still validate with the form', (
    WidgetTester tester,
  ) async {
    debugUseNativeAuthFields = true;
    addTearDown(() => debugUseNativeAuthFields = null);
    final List<MethodCall> viewCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (MethodCall call) async {
        viewCalls.add(call);
        return null;
      },
    );
    const String fieldsChannel = 'penchant/auth_fields/0';
    final List<MethodCall> fieldCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(fieldsChannel),
      (MethodCall call) async {
        fieldCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform_views, null)
        ..setMockMethodCallHandler(const MethodChannel(fieldsChannel), null);
    });

    final TextEditingController email = TextEditingController();
    final TextEditingController password = TextEditingController();
    addTearDown(email.dispose);
    addTearDown(password.dispose);
    final GlobalKey<FormState> form = GlobalKey<FormState>();
    final List<String> emailChanges = <String>[];
    final List<String> passwordChanges = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: NativeAuthFieldsHost(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AuthField(
                    controller: email,
                    hint: 'Email',
                    glyph: DialGlyph.mail,
                    nativeKind: NativeAuthFieldKind.email,
                    onChanged: emailChanges.add,
                    validator: (String? value) =>
                        (value ?? '').isEmpty ? 'Enter your email' : null,
                  ),
                  const SizedBox(height: 10),
                  AuthField(
                    controller: password,
                    hint: 'Password',
                    glyph: DialGlyph.lock,
                    obscurable: true,
                    nativeKind: NativeAuthFieldKind.password,
                    onChanged: passwordChanges.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextFormField), findsNothing);
    final MethodCall create = viewCalls.singleWhere(
      (MethodCall c) => c.method == 'create',
    );
    final Map<Object?, Object?> createArgs =
        create.arguments as Map<Object?, Object?>;
    expect(createArgs['viewType'], nativeAuthFieldsViewType);
    expect(find.byType(AppKitView), findsOneWidget);
    final Rect view = tester.getRect(find.byType(AppKitView));
    expect(view.height, 52 + 10 + 52);
    // The eye beside Password stays outside the native view.
    final Rect eye = tester.getRect(find.byType(IconButton));
    expect(eye.left, greaterThanOrEqualTo(view.right));

    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(
      tester.getRect(find.byType(AppKitView)).height,
      greaterThan(52 + 10 + 52),
      reason: 'the error line under Email moves Password down',
    );
    expect(fieldCalls.last.method, 'layout');

    await _fromNative(fieldsChannel, 'changed', <String, Object>{
      'email': 'me@example.com',
      'password': 'secret',
    });
    expect(email.text, 'me@example.com');
    expect(password.text, 'secret');
    expect(emailChanges, <String>['me@example.com']);
    expect(passwordChanges, <String>['secret']);
    expect(
      fieldCalls.where((MethodCall c) => c.method == 'setText'),
      isEmpty,
      reason: 'a native change is not echoed back',
    );
    expect(form.currentState!.validate(), isTrue);

    email.text = 'other@example.com';
    expect(fieldCalls.last.method, 'setText');
    expect(fieldCalls.last.arguments, <String, Object>{
      'field': 'email',
      'text': 'other@example.com',
    });

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(
      fieldCalls
          .where((MethodCall c) => c.method == 'setObscured')
          .last
          .arguments,
      <String, Object>{'field': 'password', 'obscured': false},
    );
  });
}
