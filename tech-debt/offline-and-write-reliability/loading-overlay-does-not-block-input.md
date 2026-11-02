# The loading scrim is a plain Container and the Record button carries no loading guard

**Severity:** high

Both the editor and the record dialog show a translucent black `Container` through `Positioned.fill` while loading is true, with no explicit `AbsorbPointer`, `IgnorePointer`, or `ModalBarrier`. A `Container` with a `color` and no child builds a `ColoredBox`, whose render object sets `HitTestBehavior.opaque`, so touch and mouse hit-testing against the Stack siblings beneath it is already blocked. The semantics tree is unaffected by hit-testing, though, so a screen reader can still reach and re-activate the fields and buttons underneath.

The dialog's Record button also lacks the loading guard its editor counterparts use, so a second activation while the first write is in flight — a screen-reader user re-activating a control that looks disabled, since a pointer double-tap is already stopped by the scrim — creates a second document through a fresh reference.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:314` — `Positioned.fill(\n            child: Container(\n              color: Colors.black.withValues(alpha: 0.5),\n            ),\n          ),`
- `lib/vice_activity_editor_page.dart:172` — `onPressed: loading ? null : _deleteActivity,`
- `lib/widgets/record_new_activity_dialog.dart:234` — `onPressed: () async {`
- Flutter SDK `packages/flutter/lib/src/widgets/basic.dart:8528-8532` — `class _RenderColoredBox extends RenderProxyBoxWithHitTestBehavior {\n  ...\n    : ...\n      super(behavior: HitTestBehavior.opaque);`
