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

  group('NativeAuthFieldChannel', () {
    late List<MethodCall> sent;
    late NativeAuthFieldChannel channel;
    final List<String> changed = <String>[];
    final List<String> submitted = <String>[];
    final List<bool> focus = <bool>[];
    final List<bool> tabs = <bool>[];

    setUp(() {
      sent = <MethodCall>[];
      changed.clear();
      submitted.clear();
      focus.clear();
      tabs.clear();
      channel = NativeAuthFieldChannel(
        7,
        onChanged: changed.add,
        onSubmitted: submitted.add,
        onFocusChanged: focus.add,
        onTab: tabs.add,
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
      expect(channel.name, 'penchant/auth_field/7');
    });

    test('sends text, focus, obscuring and configuration', () async {
      await channel.setText('a@b.co');
      await channel.setObscured(false);
      await channel.focus();
      await channel.blur();
      await channel.configure(
        NativeAuthFieldChannel.configuration(
          kind: NativeAuthFieldKind.newPassword,
          placeholder: 'Password',
          textColor: const Color(0xFF102030),
          placeholderColor: const Color(0x80405060),
          caretColor: const Color(0xFFFF0000),
        ),
      );
      expect(sent.map((MethodCall c) => c.method), <String>[
        'setText',
        'setObscured',
        'focus',
        'blur',
        'configure',
      ]);
      expect(sent[0].arguments, <String, Object>{'text': 'a@b.co'});
      expect(sent[1].arguments, <String, Object>{'obscured': false});
      expect(sent[4].arguments, <String, Object>{
        'kind': 'newPassword',
        'placeholder': 'Password',
        'textColor': 0xFF102030,
        'placeholderColor': 0x80405060,
        'caretColor': 0xFFFF0000,
      });
    });

    test('hands native events to its callbacks', () async {
      await _fromNative(channel.name, 'changed', <String, Object>{
        'text': 'filled',
      });
      await _fromNative(channel.name, 'submitted', <String, Object>{
        'text': 'filled',
      });
      await _fromNative(channel.name, 'focusChanged', <String, Object>{
        'focused': true,
      });
      await _fromNative(channel.name, 'tab', <String, Object>{
        'forward': false,
      });
      expect(changed, <String>['filled']);
      expect(submitted, <String>['filled']);
      expect(focus, <bool>[true]);
      expect(tabs, <bool>[false]);
    });
  });

  testWidgets('a forced native AuthField keeps its controller in step and '
      'still validates with the form', (WidgetTester tester) async {
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
    const String fieldChannel = 'penchant/auth_field/0';
    final List<MethodCall> fieldCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(fieldChannel),
      (MethodCall call) async {
        fieldCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform_views, null)
        ..setMockMethodCallHandler(const MethodChannel(fieldChannel), null);
    });

    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    final GlobalKey<FormState> form = GlobalKey<FormState>();
    final List<String> changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: AuthField(
              controller: controller,
              hint: 'Email',
              glyph: DialGlyph.mail,
              nativeKind: NativeAuthFieldKind.email,
              onChanged: changes.add,
              validator: (String? value) =>
                  (value ?? '').isEmpty ? 'Enter your email' : null,
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
    expect(
      (create.arguments as Map<Object?, Object?>)['viewType'],
      nativeAuthFieldViewType,
    );
    expect(tester.getSize(find.byType(AppKitView)).height, 52);

    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);

    await _fromNative(fieldChannel, 'changed', <String, Object>{
      'text': 'me@example.com',
    });
    expect(controller.text, 'me@example.com');
    expect(changes, <String>['me@example.com']);
    expect(
      fieldCalls.where((MethodCall c) => c.method == 'setText'),
      isEmpty,
      reason: 'a native change is not echoed back',
    );
    expect(form.currentState!.validate(), isTrue);

    controller.text = 'other@example.com';
    expect(fieldCalls.last.method, 'setText');
    expect(fieldCalls.last.arguments, <String, Object>{
      'text': 'other@example.com',
    });
  });
}
