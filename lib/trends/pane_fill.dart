import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Sizes a [Column] holding one [PaneFillSlot] (under an [Expanded]) so that
/// the slot takes the height the rest of the column leaves in [height],
/// kept between [minSlot] and [maxSlot]: below [minSlot] the column grows
/// past [height] (its scroll view scrolls), above [maxSlot] it stops short.
///
/// The rest of the column is measured, not estimated: the column is laid out
/// at [height], the slot reports what it was given, and the column is laid
/// out again at the height that gives the slot its share. Without a slot the
/// column takes its own height.
class PaneFill extends SingleChildRenderObjectWidget {
  const PaneFill({
    super.key,
    required this.height,
    required this.minSlot,
    required this.maxSlot,
    required Widget super.child,
  });

  final double height;
  final double minSlot;
  final double maxSlot;

  @override
  RenderPaneFill createRenderObject(BuildContext context) =>
      RenderPaneFill(height: height, minSlot: minSlot, maxSlot: maxSlot);

  @override
  void updateRenderObject(BuildContext context, RenderPaneFill renderObject) {
    renderObject
      ..height = height
      ..minSlot = minSlot
      ..maxSlot = maxSlot;
  }
}

/// The part of a [PaneFill] that takes the spare height.
class PaneFillSlot extends SingleChildRenderObjectWidget {
  const PaneFillSlot({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSlot();
}

class RenderPaneFill extends RenderProxyBox {
  RenderPaneFill({
    required double height,
    required double minSlot,
    required double maxSlot,
  }) : _height = height,
       _minSlot = minSlot,
       _maxSlot = maxSlot;

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  double _minSlot;
  set minSlot(double value) {
    if (value == _minSlot) return;
    _minSlot = value;
    markNeedsLayout();
  }

  double _maxSlot;
  set maxSlot(double value) {
    if (value == _maxSlot) return;
    _maxSlot = value;
    markNeedsLayout();
  }

  _RenderSlot? _slotBox;

  double? get _slot => _slotBox?.constraints.maxHeight;

  // More than the rest of any pane could take, and small enough to subtract
  // from without losing precision.
  static const double _measureRoom = 100000;

  // Loose, so a change inside the column lays this out again too.
  void _layoutAt(double height) => child!.layout(
    BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: height),
    parentUsesSize: true,
  );

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final double viewport = max(0, _height);
    _layoutAt(viewport);
    double? given = _slot;
    if (given == 0) {
      // The rest overflowed the viewport, so the column's height says
      // nothing about it: measure it where it fits.
      _layoutAt(viewport + _measureRoom);
      given = _slot;
    }
    if (given == null) {
      _layoutAt(double.infinity);
    } else {
      final double rest = child!.size.height - given;
      final double slot = (viewport - rest).clamp(
        _minSlot,
        max(_minSlot, _maxSlot),
      );
      if ((rest + slot - child!.size.height).abs() > 1e-6) {
        _layoutAt(rest + slot);
      }
    }
    size = constraints.constrain(child!.size);
  }
}

class _RenderSlot extends RenderProxyBox {
  RenderPaneFill? _fill;

  @override
  void performLayout() {
    super.performLayout();
    _fill ??= _findFill();
    _fill?._slotBox = this;
  }

  RenderPaneFill? _findFill() {
    for (RenderObject? node = parent; node != null; node = node.parent) {
      if (node is RenderPaneFill) return node;
    }
    return null;
  }

  @override
  void detach() {
    if (_fill?._slotBox == this) _fill!._slotBox = null;
    _fill = null;
    super.detach();
  }
}
