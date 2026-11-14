import 'package:flutter/widgets.dart';

/// A text field's `onTapOutside` for the number pad, which has no Done key:
/// a touch anywhere else puts the keyboard away.
void closeKeyboardOnTapOutside(PointerDownEvent _) =>
    FocusManager.instance.primaryFocus?.unfocus();
