import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/label/label_reading.dart';
import 'package:tracker/label/label_source.dart';
import 'package:tracker/widgets/amount_sheet_frame.dart';
import 'package:tracker/widgets/pill_toggle.dart';

/// What the person chose to fill in from a label. Only proposed: the habit
/// form shows it in its fields and nothing is saved until the form is.
@immutable
class LabelPick {
  const LabelPick({this.abv, this.servingMl, this.caffeineMg});

  final double? abv;
  final double? servingMl;
  final double? caffeineMg;
}

/// Reads a drink's label from a photo; [one] names a serving ("pint").
Future<LabelPick?> showLabelSheet(
  BuildContext context, {
  required LabelSource source,
  required String one,
}) => showModalBottomSheet<LabelPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => LabelSheet(source: source, one: one),
);

class LabelSheet extends StatefulWidget {
  const LabelSheet({super.key, required this.source, required this.one});

  static const String title = 'Read a label';
  static const String takeLabel = 'Take a photo';
  static const String chooseLabel = 'Choose a photo';
  static const String fillLabel = 'Fill in';
  static const String againLabel = 'Try another photo';
  static const String privacy =
      'Read on this phone. The photo and the words in it are not kept and '
      'are sent nowhere.';
  static const String nothingTitle = 'Nothing to fill in';
  static const String noCamera =
      'This device has no camera. Choose a photo instead.';
  static const String failed =
      'Penchant couldn’t read that photo. Try another.';

  final LabelSource source;
  final String one;

  @override
  State<LabelSheet> createState() => _LabelSheetState();
}

enum _Stage { start, reading, result }

class _LabelSheetState extends State<LabelSheet> {
  _Stage _stage = _Stage.start;
  LabelReading? _reading;
  String? _error;
  double? _abv;
  double? _serving;
  double? _caffeine;

  Future<void> _scan(LabelPhoto from) async {
    setState(() {
      _stage = _Stage.reading;
      _error = null;
    });
    final LabelScan scan = await widget.source.scan(from);
    if (!mounted) return;
    setState(() {
      switch (scan.status) {
        case LabelScanStatus.read:
          final LabelReading reading = readLabel(scan.lines);
          _reading = reading;
          // The form holds alcohol or caffeine, not both. A stated strength
          // makes it alcohol; else a stated caffeine figure makes it caffeine,
          // which has no size to fill.
          _abv = reading.abv.proposed?.value;
          _caffeine = _abv == null ? reading.caffeine.proposed?.value : null;
          _serving = _caffeine == null ? reading.volume.proposed?.value : null;
          _stage = _Stage.result;
        case LabelScanStatus.cancelled:
          _stage = _reading == null ? _Stage.start : _Stage.result;
        case LabelScanStatus.noCamera:
          _error = LabelSheet.noCamera;
          _stage = _Stage.start;
        case LabelScanStatus.failed:
          _error = LabelSheet.failed;
          _stage = _Stage.start;
      }
    });
  }

  bool get _picked => _abv != null || _serving != null || _caffeine != null;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final LabelReading? reading = _reading;
    final bool showResult = _stage == _Stage.result && reading != null;
    final bool found = reading?.found ?? false;
    return AmountSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              showResult
                  ? (found ? 'From the label' : LabelSheet.nothingTitle)
                  : LabelSheet.title,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: DialSpace.xs),
          if (!showResult)
            Text(
              'Take or choose a photo of the can or bottle where it shows '
              'its size and strength. Penchant fills in what it finds for you '
              'to check.',
              style: DialTypeScale.body.copyWith(color: colors.muted),
            )
          else if (!found)
            Text(
              'No strength, size or caffeine was found in that photo. Try '
              'closer, with the label flat and well lit, or type them in.',
              style: DialTypeScale.body.copyWith(color: colors.muted),
            ),
          if (showResult && found) ..._result(context, reading),
          if (showResult)
            for (final String note in reading.notes) ...<Widget>[
              const SizedBox(height: DialSpace.xs),
              Text(
                note,
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ],
          const SizedBox(height: DialSpace.m),
          _privacy(context),
          if (_error case final String error) ...<Widget>[
            const SizedBox(height: DialSpace.s),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: DialTypeScale.bodyS.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: DialSpace.m),
          if (_stage == _Stage.reading)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: DialSpace.s),
                child: Text(
                  'Reading the label on this phone…',
                  textAlign: TextAlign.center,
                  style: DialTypeScale.body.copyWith(color: colors.muted),
                ),
              ),
            )
          else if (showResult && found) ...<Widget>[
            FilledButton(
              onPressed: _picked
                  ? () => Navigator.of(context).pop(
                      LabelPick(
                        abv: _abv,
                        servingMl: _serving,
                        caffeineMg: _caffeine,
                      ),
                    )
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(LabelSheet.fillLabel),
            ),
            const SizedBox(height: DialSpace.xs),
            TextButton(
              onPressed: () => setState(() {
                _stage = _Stage.start;
                _reading = null;
              }),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(DialSize.minTapTarget),
              ),
              child: const Text(LabelSheet.againLabel),
            ),
            Text(
              'Nothing is saved until you save the habit.',
              textAlign: TextAlign.center,
              style: DialTypeScale.bodyS.copyWith(color: colors.muted),
            ),
          ] else ...<Widget>[
            FilledButton.icon(
              onPressed: () => _scan(LabelPhoto.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text(LabelSheet.takeLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: DialSpace.xs),
            OutlinedButton.icon(
              onPressed: () => _scan(LabelPhoto.library),
              icon: const Icon(Icons.photo_outlined),
              label: const Text(LabelSheet.chooseLabel),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _privacy(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(Icons.lock_outline, size: 16, color: colors.muted),
        ),
        const SizedBox(width: DialSpace.xs),
        Expanded(
          child: Text(
            LabelSheet.privacy,
            style: DialTypeScale.bodyS.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }

  List<Widget> _result(BuildContext context, LabelReading reading) => <Widget>[
    if (!reading.abv.isEmpty)
      _section(
        context,
        title: 'Usual strength',
        field: reading.abv,
        unit: '%',
        picked: _abv,
        onPick: (double? v) => setState(() {
          _abv = v;
          if (v != null) _caffeine = null;
        }),
        others:
            'Picked: the one marked as alcohol by volume. The others are '
            'not, so pick one only if it is.',
        single:
            'Not marked as alcohol by volume on the label: pick it '
            'only if it is.',
      ),
    if (!reading.volume.isEmpty)
      _section(
        context,
        title: 'Each ${widget.one}',
        field: reading.volume,
        unit: ' ml',
        picked: _serving,
        onPick: (double? v) => setState(() {
          _serving = v;
          if (v != null) _caffeine = null;
        }),
        help:
            'The whole can or bottle. Tap it again to leave it out if '
            'your ${widget.one} is less.',
      ),
    if (!reading.caffeine.isEmpty)
      _section(
        context,
        title: 'Caffeine, each ${widget.one}',
        field: reading.caffeine,
        unit: ' mg',
        picked: _caffeine,
        onPick: (double? v) => setState(() {
          _caffeine = v;
          if (v != null) {
            _abv = null;
            _serving = null;
          }
        }),
      ),
  ];

  Widget _section(
    BuildContext context, {
    required String title,
    required LabelField field,
    required String unit,
    required double? picked,
    required ValueChanged<double?> onPick,
    String? single,
    String? help,
    String? others,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final String? hint = field.proposed != null
        ? (field.choices.length > 1 ? others ?? help : help)
        : field.choices.length > 1
        ? 'The label gives more than one: pick one, or leave it.'
        : single ?? help;
    final List<String> workings = <String>[
      for (final LabelValue v in field.choices)
        if (v.read.contains('×')) '${formatAmount(v.value)}$unit is ${v.read}.',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: DialSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              title,
              style: DialTypeScale.bodyS.copyWith(color: colors.muted),
            ),
          ),
          const SizedBox(height: DialSpace.xs),
          Wrap(
            spacing: DialSpace.xs,
            runSpacing: DialSpace.xs,
            children: <Widget>[
              for (final LabelValue v in field.choices)
                PillToggle(
                  selected: picked == v.value,
                  exclusive: false,
                  onPressed: () => onPick(picked == v.value ? null : v.value),
                  color: colors.surface2,
                  selectedColor: scheme.surfaceContainerLow,
                  selectedSide: BorderSide(color: scheme.onSurface, width: 1.5),
                  restForeground: scheme.onSurface,
                  minHeight: DialSize.minTapTarget,
                  child: Text(_pill(v, unit)),
                ),
            ],
          ),
          for (final String line in <String>[...workings, ?hint]) ...<Widget>[
            const SizedBox(height: DialSpace.xxs),
            Text(
              line,
              style: DialTypeScale.bodyS.copyWith(color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }

  // "750 ml · 75 cl", "355 ml · 12 fl oz US", "5.2%".
  static String _pill(LabelValue v, String unit) {
    final String main = '${formatAmount(v.value)}$unit';
    final String as = '${v.read}${v.note == null ? '' : ' ${v.note}'}';
    return v.read == main || v.read.contains('×') ? main : '$main · $as';
  }
}
