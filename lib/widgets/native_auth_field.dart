import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// On macOS the Email and Password fields are AppKit text fields hosted as
// platform views (macos/Runner/AuthFieldPlatformView.swift): Flutter's macOS
// text input offers no AutoFill, a native field with a content type does.

/// Set in tests to force the native fields on or off.
@visibleForTesting
bool? debugUseNativeAuthFields;

bool get useNativeAuthFields =>
    debugUseNativeAuthFields ??
    (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        !Platform.environment.containsKey('FLUTTER_TEST'));

const String nativeAuthFieldViewType = 'penchant/auth_field';

/// The AppKit content type a native field takes.
enum NativeAuthFieldKind { email, password, newPassword }

/// The Dart end of one native field's channel.
class NativeAuthFieldChannel {
  NativeAuthFieldChannel(
    int viewId, {
    required this.onChanged,
    required this.onSubmitted,
    required this.onFocusChanged,
    required this.onTab,
  }) : _channel = MethodChannel('$nativeAuthFieldViewType/$viewId') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<bool> onFocusChanged;
  final ValueChanged<bool> onTab;

  String get name => _channel.name;

  Future<void> _handle(MethodCall call) async {
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ??
        const <Object?, Object?>{};
    switch (call.method) {
      case 'changed':
        onChanged(args['text'] as String? ?? '');
      case 'submitted':
        onSubmitted(args['text'] as String? ?? '');
      case 'focusChanged':
        onFocusChanged(args['focused'] as bool? ?? false);
      case 'tab':
        onTab(args['forward'] as bool? ?? true);
      default:
        throw MissingPluginException(call.method);
    }
  }

  static Map<String, Object> configuration({
    required NativeAuthFieldKind kind,
    required String placeholder,
    required Color textColor,
    required Color placeholderColor,
    required Color caretColor,
  }) => <String, Object>{
    'kind': kind.name,
    'placeholder': placeholder,
    'textColor': textColor.toARGB32(),
    'placeholderColor': placeholderColor.toARGB32(),
    'caretColor': caretColor.toARGB32(),
  };

  Future<void> configure(Map<String, Object> configuration) =>
      _channel.invokeMethod<void>('configure', configuration);

  Future<void> setText(String text) =>
      _channel.invokeMethod<void>('setText', <String, Object>{'text': text});

  Future<void> setObscured(bool obscured) => _channel.invokeMethod<void>(
    'setObscured',
    <String, Object>{'obscured': obscured},
  );

  Future<void> focus() => _channel.invokeMethod<void>('focus');

  Future<void> blur() => _channel.invokeMethod<void>('blur');

  void dispose() => _channel.setMethodCallHandler(null);
}

/// A native field inside [decoration], kept in step with [controller] and
/// validated with the enclosing [Form].
class NativeAuthField extends StatefulWidget {
  const NativeAuthField({
    super.key,
    required this.controller,
    required this.kind,
    required this.hint,
    required this.decoration,
    required this.textStyle,
    required this.obscured,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final NativeAuthFieldKind kind;
  final String hint;
  final InputDecoration decoration;
  final TextStyle textStyle;
  final bool obscured;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  State<NativeAuthField> createState() => _NativeAuthFieldState();
}

class _NativeAuthFieldState extends State<NativeAuthField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'NativeAuthField');
  NativeAuthFieldChannel? _channel;
  late String _lastNative = widget.controller.text;
  bool _nativeFocused = false;
  Map<String, Object> _configuration = const <String, Object>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    _focusNode.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reconfigure();
  }

  @override
  void didUpdateWidget(NativeAuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    if (oldWidget.obscured != widget.obscured) {
      _channel?.setObscured(widget.obscured);
    }
    _reconfigure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _channel?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reconfigure() {
    final ThemeData theme = Theme.of(context);
    final Map<String, Object> next = NativeAuthFieldChannel.configuration(
      kind: widget.kind,
      placeholder: widget.hint,
      textColor: widget.textStyle.color ?? theme.colorScheme.onSurface,
      placeholderColor:
          widget.decoration.hintStyle?.color ??
          theme.inputDecorationTheme.hintStyle?.color ??
          theme.hintColor,
      caretColor:
          theme.textSelectionTheme.cursorColor ?? theme.colorScheme.primary,
    );
    if (!mapEquals(next, _configuration)) {
      _configuration = next;
      _channel?.configure(next);
    }
  }

  void _created(int viewId) {
    final NativeAuthFieldChannel channel = NativeAuthFieldChannel(
      viewId,
      onChanged: _nativeChanged,
      onSubmitted: _nativeSubmitted,
      onFocusChanged: _nativeFocusChanged,
      onTab: (bool forward) =>
          forward ? _focusNode.nextFocus() : _focusNode.previousFocus(),
    );
    _channel = channel;
    // Catch up with anything that changed while the view was being made.
    channel.configure(_configuration);
    channel.setObscured(widget.obscured);
    if (widget.controller.text != _lastNative) {
      _lastNative = widget.controller.text;
      channel.setText(_lastNative);
    }
  }

  void _nativeChanged(String text) {
    _lastNative = text;
    if (widget.controller.text != text) {
      widget.controller.text = text;
    }
    widget.onChanged?.call(text);
  }

  void _nativeSubmitted(String text) {
    _nativeChanged(text);
    if (widget.textInputAction == TextInputAction.next) {
      _focusNode.nextFocus();
    }
    widget.onSubmitted?.call(text);
  }

  void _nativeFocusChanged(bool focused) {
    _nativeFocused = focused;
    if (focused && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    } else if (!focused && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
    setState(() {});
  }

  void _controllerChanged() {
    final String text = widget.controller.text;
    if (text != _lastNative) {
      _lastNative = text;
      _channel?.setText(text);
    }
  }

  // Both calls are no-ops on the native side when it is already in that
  // state, so the order they meet the engine's own text input does not
  // matter.
  void _focusChanged() {
    if (_focusNode.hasFocus && !_nativeFocused) {
      _channel?.focus();
    } else if (!_focusNode.hasFocus && _nativeFocused) {
      _channel?.blur();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(widget.controller.text),
      builder: (FormFieldState<String> field) => InputDecorator(
        decoration: widget.decoration.copyWith(
          contentPadding: EdgeInsets.zero,
          errorText: field.errorText,
        ),
        isFocused: _focusNode.hasFocus,
        child: SizedBox(
          height: 52,
          child: Focus(
            focusNode: _focusNode,
            // The view's own focus node sends TextInput.setPlatformViewClient,
            // an iOS embedder call; this node stands in for it.
            child: ExcludeFocus(
              child: AppKitView(
                viewType: nativeAuthFieldViewType,
                creationParams: <String, Object>{
                  ..._configuration,
                  'text': widget.controller.text,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _created,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
