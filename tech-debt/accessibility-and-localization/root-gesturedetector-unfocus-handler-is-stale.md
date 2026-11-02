# The tap-to-dismiss-keyboard handler captures whichever node held focus at rebuild time

**Severity:** medium

`main.dart` wraps the `MaterialApp` in a `GestureDetector` whose `onTap` is a property read and method tear-off of the current primary focus, evaluated once per `MyApp` rebuild, which happens only when `userProvider` changes.

The callback permanently holds whichever `FocusNode` was primary at that moment, and unfocusing a node that no longer holds focus is a no-op, so the behaviour stops working as soon as focus moves. `excludeFromSemantics` is not set, so on the rare rebuild where the callback is non-null the detector also publishes an unlabeled tap action on the app's root semantics node, above every other element's own semantics.

## Evidence

- `lib/main.dart:37` — `return GestureDetector(\n      onTap: FocusManager.instance.primaryFocus?.unfocus,`
