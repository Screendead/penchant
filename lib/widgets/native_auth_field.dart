import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// On macOS the Email and Password fields are AppKit text fields hosted in one
// platform view (macos/Runner/AuthFieldPlatformView.swift): Flutter's macOS
// text input offers no AutoFill, a native field with a content type does, and
// AppKit fills a username and password pair only when both fields sit in the
// same view. Flutter draws the pills; the view lies over their text areas.

/// Set in tests to force the native fields on or off.
@visibleForTesting
bool? debugUseNativeAuthFields;

bool get useNativeAuthFields =>
    debugUseNativeAuthFields ??
    (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        !Platform.environment.containsKey('FLUTTER_TEST'));

const String nativeAuthFieldsViewType = 'penchant/auth_fields';

/// The AppKit content type a native field takes.
enum NativeAuthFieldKind {
  email,
  password,
  newPassword;

  /// The field's name on the channel.
  String get field => this == email ? 'email' : 'password';
}

/// The Dart end of the native view's channel. Every call names its field,
/// `email` or `password`.
class NativeAuthFieldsChannel {
  NativeAuthFieldsChannel(
    int viewId, {
    required this.onChanged,
    required this.onSubmitted,
    required this.onFocusChanged,
    required this.onTab,
  }) : _channel = MethodChannel('$nativeAuthFieldsViewType/$viewId') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// The new text of each field that changed, keyed by field.
  final ValueChanged<Map<String, String>> onChanged;
  final void Function(String field, String text) onSubmitted;
  final void Function(String field, bool focused) onFocusChanged;
  final void Function(String field, bool forward) onTab;

  String get name => _channel.name;

  Future<void> _handle(MethodCall call) async {
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ??
        const <Object?, Object?>{};
    final String field = args['field'] as String? ?? '';
    switch (call.method) {
      case 'changed':
        onChanged(<String, String>{
          for (final MapEntry<Object?, Object?> entry in args.entries)
            if (entry.key is String && entry.value is String)
              entry.key! as String: entry.value! as String,
        });
      case 'submitted':
        onSubmitted(field, args['text'] as String? ?? '');
      case 'focusChanged':
        onFocusChanged(field, args['focused'] as bool? ?? false);
      case 'tab':
        onTab(field, args['forward'] as bool? ?? true);
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

  Future<void> _call(
    String method,
    String field, [
    Map<String, Object>? args,
  ]) => _channel.invokeMethod<void>(method, <String, Object>{
    'field': field,
    ...?args,
  });

  Future<void> configure(String field, Map<String, Object> configuration) =>
      _call('configure', field, configuration);

  Future<void> setText(String field, String text) =>
      _call('setText', field, <String, Object>{'text': text});

  Future<void> setObscured(String field, bool obscured) =>
      _call('setObscured', field, <String, Object>{'obscured': obscured});

  Future<void> focus(String field) => _call('focus', field);

  Future<void> blur(String field) => _call('blur', field);

  /// Each field's text area within the view, as `[x, y, width, height]`.
  Future<void> layout(Map<String, List<double>> rects) =>
      _channel.invokeMethod<void>('layout', rects);

  void dispose() => _channel.setMethodCallHandler(null);
}

/// Hosts the one native view for the [NativeAuthField]s below it, laid over
/// their text areas.
class NativeAuthFieldsHost extends StatefulWidget {
  const NativeAuthFieldsHost({super.key, required this.child});

  final Widget child;

  @override
  State<NativeAuthFieldsHost> createState() => _NativeAuthFieldsHostState();
}

class _HostScope extends InheritedWidget {
  const _HostScope({required this.host, required super.child});

  final _NativeAuthFieldsHostState host;

  @override
  bool updateShouldNotify(_HostScope oldWidget) => host != oldWidget.host;
}

class _NativeAuthFieldsHostState extends State<NativeAuthFieldsHost> {
  final GlobalKey _stackKey = GlobalKey();
  final Map<String, _NativeAuthFieldState> _fields =
      <String, _NativeAuthFieldState>{};
  NativeAuthFieldsChannel? channel;
  Map<String, Rect> _rects = const <String, Rect>{};
  bool _measureQueued = false;

  @override
  void dispose() {
    channel?.dispose();
    super.dispose();
  }

  void register(_NativeAuthFieldState field) {
    _fields[field.name] = field;
    scheduleMeasure();
  }

  void unregister(_NativeAuthFieldState field) {
    if (_fields[field.name] == field) {
      _fields.remove(field.name);
      scheduleMeasure();
    }
  }

  // The pills can move without this widget rebuilding (an error line under
  // Email), so their text areas are measured after any frame that may have
  // moved them.
  void scheduleMeasure() {
    if (_measureQueued) {
      return;
    }
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) {
        _measure();
      }
    });
  }

  void _measure() {
    final RenderObject? stack = _stackKey.currentContext?.findRenderObject();
    if (stack is! RenderBox || !stack.hasSize) {
      return;
    }
    final Map<String, Rect> next = <String, Rect>{};
    for (final MapEntry<String, _NativeAuthFieldState> entry
        in _fields.entries) {
      final RenderObject? slot = entry.value.slotKey.currentContext
          ?.findRenderObject();
      if (slot is RenderBox && slot.hasSize) {
        next[entry.key] =
            slot.localToGlobal(Offset.zero, ancestor: stack) & slot.size;
      }
    }
    if (mapEquals(next, _rects)) {
      return;
    }
    final Map<String, List<double>> before = _fieldRects;
    setState(() => _rects = next);
    final Map<String, List<double>> after = _fieldRects;
    if (!mapEquals(before.map(_join), after.map(_join))) {
      channel?.layout(after);
    }
  }

  static MapEntry<String, String> _join(String key, List<double> value) =>
      MapEntry<String, String>(key, value.join(','));

  /// The view's rect: across both text areas, and no wider than the
  /// narrower one, so the eye beside Password stays a Flutter button.
  Rect? get _container {
    final Rect? email = _rects['email'];
    final Rect? password = _rects['password'];
    if (email == null || password == null) {
      return null;
    }
    final double left = email.left > password.left ? email.left : password.left;
    final double right = email.right < password.right
        ? email.right
        : password.right;
    final double top = email.top < password.top ? email.top : password.top;
    final double bottom = email.bottom > password.bottom
        ? email.bottom
        : password.bottom;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Map<String, List<double>> get _fieldRects {
    final Rect? container = _container;
    if (container == null) {
      return const <String, List<double>>{};
    }
    return <String, List<double>>{
      for (final MapEntry<String, Rect> entry in _rects.entries)
        entry.key: <double>[
          0,
          entry.value.top - container.top,
          container.width,
          entry.value.height,
        ],
    };
  }

  void _created(int viewId) {
    final NativeAuthFieldsChannel created = NativeAuthFieldsChannel(
      viewId,
      onChanged: (Map<String, String> changed) {
        for (final MapEntry<String, String> entry in changed.entries) {
          _fields[entry.key]?.nativeChanged(entry.value);
        }
      },
      onSubmitted: (String field, String text) =>
          _fields[field]?.nativeSubmitted(text),
      onFocusChanged: (String field, bool focused) =>
          _fields[field]?.nativeFocusChanged(focused),
      onTab: (String field, bool forward) => _fields[field]?.nativeTab(forward),
    );
    channel = created;
    // Catch up with anything that changed while the view was being made.
    for (final _NativeAuthFieldState field in _fields.values) {
      field.attached(created);
    }
    created.layout(_fieldRects);
  }

  @override
  Widget build(BuildContext context) {
    final Rect? container = _container;
    return _HostScope(
      host: this,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          scheduleMeasure();
          return Stack(
            key: _stackKey,
            children: <Widget>[
              widget.child,
              if (container != null)
                Positioned.fromRect(
                  rect: container,
                  // Each field's own Focus node stands in for the view's,
                  // which would send TextInput.setPlatformViewClient, an iOS
                  // embedder call.
                  child: ExcludeFocus(
                    child: AppKitView(
                      viewType: nativeAuthFieldsViewType,
                      creationParams: <String, Object>{
                        'layout': _fieldRects,
                        for (final _NativeAuthFieldState field
                            in _fields.values)
                          field.name: field.creationParams(),
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _created,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A pill whose text area the [NativeAuthFieldsHost] above it covers with a
/// native field, kept in step with [controller] and validated with the
/// enclosing [Form].
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
  final GlobalKey slotKey = GlobalKey();
  _NativeAuthFieldsHostState? _host;
  late String _lastNative = widget.controller.text;
  bool _nativeFocused = false;
  bool _reclaim = false;
  Map<String, Object> _configuration = const <String, Object>{};

  String get name => widget.kind.field;

  NativeAuthFieldsChannel? get _channel => _host?.channel;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    _focusNode.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _NativeAuthFieldsHostState? host = context
        .dependOnInheritedWidgetOfExactType<_HostScope>()
        ?.host;
    assert(host != null, 'A NativeAuthField needs a NativeAuthFieldsHost.');
    if (host != _host) {
      _host?.unregister(this);
      _host = host;
      host?.register(this);
    }
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
      _channel?.setObscured(name, widget.obscured);
    }
    _reconfigure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _host?.unregister(this);
    _focusNode.dispose();
    super.dispose();
  }

  void _reconfigure() {
    final ThemeData theme = Theme.of(context);
    final Map<String, Object> next = NativeAuthFieldsChannel.configuration(
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
      _channel?.configure(name, next);
    }
  }

  Map<String, Object> creationParams() {
    _lastNative = widget.controller.text;
    return <String, Object>{
      ..._configuration,
      'text': _lastNative,
      'obscured': widget.obscured,
    };
  }

  void attached(NativeAuthFieldsChannel channel) {
    channel.configure(name, _configuration);
    channel.setObscured(name, widget.obscured);
    if (widget.controller.text != _lastNative) {
      _lastNative = widget.controller.text;
      channel.setText(name, _lastNative);
    }
    if (_focusNode.hasFocus) {
      channel.focus(name);
    }
  }

  void nativeChanged(String text) {
    _lastNative = text;
    if (widget.controller.text != text) {
      widget.controller.text = text;
    }
    widget.onChanged?.call(text);
  }

  void nativeSubmitted(String text) {
    nativeChanged(text);
    if (widget.textInputAction == TextInputAction.next) {
      _focusNode.nextFocus();
    }
    widget.onSubmitted?.call(text);
  }

  void nativeTab(bool forward) =>
      forward ? _focusNode.nextFocus() : _focusNode.previousFocus();

  void nativeFocusChanged(bool focused) {
    _nativeFocused = focused;
    if (focused && !_focusNode.hasFocus) {
      // Taking focus from a Flutter text field (Confirm) ends its input
      // session, which may hand first responder back to the Flutter view;
      // that one loss, in this frame, is taken back once. Focus moving
      // between the native fields or from nowhere never re-grabs, since a
      // second makeFirstResponder restarts the AutoFill prompt.
      final FocusNode? before = FocusManager.instance.primaryFocus;
      _reclaim =
          before != null &&
          before is! FocusScopeNode &&
          before.context?.findAncestorStateOfType<_NativeAuthFieldState>() ==
              null;
      if (_reclaim) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reclaim = false);
      }
      _focusNode.requestFocus();
    } else if (!focused && _focusNode.hasFocus) {
      if (_reclaim) {
        _reclaim = false;
        _channel?.focus(name);
      } else {
        _focusNode.unfocus();
      }
    }
    setState(() {});
  }

  void _controllerChanged() {
    final String text = widget.controller.text;
    if (text != _lastNative) {
      _lastNative = text;
      _channel?.setText(name, text);
    }
  }

  // Native focus is moved only when Flutter focus arrived from elsewhere
  // (Shift-Tab from Confirm) or left for a Flutter widget; both calls are
  // no-ops natively when the field is already in that state.
  void _focusChanged() {
    if (_focusNode.hasFocus && !_nativeFocused) {
      _channel?.focus(name);
    } else if (!_focusNode.hasFocus && _nativeFocused) {
      _channel?.blur(name);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(widget.controller.text),
      builder: (FormFieldState<String> field) {
        // An error line under this pill moves the ones below it.
        _host?.scheduleMeasure();
        return InputDecorator(
          decoration: widget.decoration.copyWith(
            contentPadding: EdgeInsets.zero,
            errorText: field.errorText,
          ),
          isFocused: _focusNode.hasFocus,
          child: Focus(
            focusNode: _focusNode,
            child: SizedBox(key: slotKey, width: double.infinity, height: 52),
          ),
        );
      },
    );
  }
}
