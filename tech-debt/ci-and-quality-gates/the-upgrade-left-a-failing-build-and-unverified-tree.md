# error.log records a Dart compile failure whose source matches neither HEAD nor the working tree

**Severity:** high

The log opens with an iOS build failure whose immediately visible Xcode output is simulator device-metadata warnings, but the fatal cause hundreds of lines later is a front-end compile error: `ViceChart` declared as a `ConsumerWidget` while its build method still carried the older single-argument signature and referenced an undefined `ref`, which failed kernel-snapshot compilation and would equally have failed a web build.

That text matches neither the committed version of `vice_chart.dart` nor the current working-tree version, so the file was edited again after the failing run captured it. No later successful build, analyze or test run is recorded anywhere in the tree for that file or for the other uncommitted files from the same refactor.

## Evidence

- `error.log:4` — `Failed to build iOS app`
- `error.log:11` — `** BUILD FAILED **`
- `error.log:547` — `lib/vice_chart.dart:20:10: Error: The method 'ViceChart.build' has fewer positional arguments than those of overridden method 'ConsumerWidget.build'.`
- `error.log:568` — `Target kernel_snapshot_program failed: Exception`
- `lib/vice_chart.dart:19` — `Widget build(BuildContext context, WidgetRef ref) {`
- **`git show HEAD:lib/vice_chart.dart | sed -n '13,20p'`** → `class ViceChart extends ConsumerStatefulWidget {\n  const ViceChart({super.key});\n\n  @override\n  ConsumerState<ViceChart> createState() => ViceChartState();`
