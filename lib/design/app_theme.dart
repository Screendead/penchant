import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// Chrome is ink on paper (paper on ink in dark). The five habit colours are
// kept out of every ColorScheme role, so no control shares a habit's colour.
ColorScheme dialColorScheme(DialPalette p) => ColorScheme(
  brightness: p.brightness,
  primary: p.accent,
  onPrimary: p.onAccent,
  primaryContainer: p.surface2,
  onPrimaryContainer: p.text,
  // Selection (navigation indicator, selected segment and chip) is ink.
  secondary: p.muted,
  onSecondary: p.bg,
  secondaryContainer: p.accent,
  onSecondaryContainer: p.onAccent,
  tertiary: p.muted,
  onTertiary: p.bg,
  tertiaryContainer: p.surface2,
  onTertiaryContainer: p.text,
  error: p.danger,
  onError: p.surface,
  errorContainer: p.dangerContainer,
  onErrorContainer: p.text,
  surface: p.bg,
  onSurface: p.text,
  onSurfaceVariant: p.muted,
  surfaceDim: p.surface2,
  surfaceBright: p.surface,
  surfaceContainerLowest: p.surface,
  surfaceContainerLow: p.surface,
  surfaceContainer: p.surface,
  surfaceContainerHigh: p.surface2,
  surfaceContainerHighest: p.surface2,
  outline: p.spoke,
  outlineVariant: p.line,
  shadow: const Color(0xFF141B2D),
  scrim: p.scrim,
  inverseSurface: p.text,
  onInverseSurface: p.bg,
  inversePrimary: p.onAccent,
  surfaceTint: Colors.transparent,
);

TextTheme dialTextTheme(DialPalette p) {
  TextStyle display(FontWeight weight, double size, double line) => TextStyle(
    fontFamily: DialFonts.display,
    fontWeight: weight,
    fontSize: size,
    height: line / size,
    fontFeatures: DialFonts.tabular,
  );
  TextStyle text(FontWeight weight, double size, double line) => TextStyle(
    fontFamily: DialFonts.text,
    fontWeight: weight,
    fontSize: size,
    height: line / size,
    fontFeatures: DialFonts.tabular,
  );

  return TextTheme(
    displayLarge: display(FontWeight.w900, 57, 64),
    displayMedium: display(FontWeight.w900, 45, 52),
    displaySmall: display(FontWeight.w900, 36, 44),
    headlineLarge: DialTypeScale.displayXL,
    headlineMedium: DialTypeScale.displayL,
    headlineSmall: display(FontWeight.w700, 20, 26),
    titleLarge: display(FontWeight.w700, 20, 26),
    titleMedium: DialTypeScale.bodyL.copyWith(fontWeight: FontWeight.w600),
    titleSmall: DialTypeScale.label.copyWith(fontSize: 13, height: 18 / 13),
    bodyLarge: DialTypeScale.bodyL,
    bodyMedium: DialTypeScale.body,
    bodySmall: DialTypeScale.bodyS,
    labelLarge: DialTypeScale.label,
    labelMedium: DialTypeScale.label.copyWith(fontSize: 13, height: 18 / 13),
    labelSmall: text(FontWeight.w500, 11, 14),
  ).apply(bodyColor: p.text, displayColor: p.text);
}

ThemeData appTheme(Brightness brightness) {
  final DialPalette p = DialPalette.of(brightness);
  final ColorScheme scheme = dialColorScheme(p);
  final TextTheme textTheme = dialTextTheme(p);
  final TextStyle label = textTheme.labelLarge!;

  const StadiumBorder pill = StadiumBorder();
  final RoundedRectangleBorder card = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(DialRadius.card),
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(DialRadius.input),
        borderSide: BorderSide(color: color, width: width),
      );

  final ButtonStyle primaryButton = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> s) =>
          s.contains(WidgetState.disabled) ? p.surface2 : p.accent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> s) =>
          s.contains(WidgetState.disabled) ? p.muted : p.onAccent,
    ),
    overlayColor: WidgetStatePropertyAll<Color>(
      p.onAccent.withValues(alpha: 0.12),
    ),
    elevation: const WidgetStatePropertyAll<double>(0),
    textStyle: WidgetStatePropertyAll<TextStyle>(label),
    minimumSize: const WidgetStatePropertyAll<Size>(
      Size(64, DialSize.pillHeight),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsets>(
      EdgeInsets.symmetric(horizontal: DialSpace.xl),
    ),
    shape: const WidgetStatePropertyAll<OutlinedBorder>(pill),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    fontFamily: DialFonts.text,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.line,
    extensions: <ThemeExtension<dynamic>>[
      DialColors.fromPalette(p),
      DialType.colored(p.text, p.muted),
    ],
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.22),
      selectionHandleColor: p.accent,
    ),
    iconTheme: IconThemeData(color: p.text),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: DialTypeScale.displayL.copyWith(
        fontSize: 21,
        height: 26 / 21,
        color: p.text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelAlignment: FloatingLabelAlignment.center,
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DialSpace.l,
        vertical: DialSpace.m,
      ),
      labelStyle: textTheme.bodyLarge!.copyWith(color: p.muted),
      floatingLabelStyle: textTheme.bodyLarge!.copyWith(color: p.text),
      hintStyle: textTheme.bodyLarge!.copyWith(
        color: p.muted,
        fontWeight: FontWeight.w400,
      ),
      prefixIconColor: p.muted,
      suffixIconColor: p.muted,
      border: inputBorder(p.spoke),
      enabledBorder: inputBorder(p.spoke),
      focusedBorder: inputBorder(p.accent, 2),
      errorBorder: inputBorder(p.danger),
      focusedErrorBorder: inputBorder(p.danger, 2),
      disabledBorder: inputBorder(p.line),
      errorStyle: textTheme.bodySmall!.copyWith(color: p.danger),
    ),
    filledButtonTheme: FilledButtonThemeData(style: primaryButton),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        textStyle: label,
        minimumSize: const Size(64, DialSize.pillHeight),
        side: BorderSide(color: p.spoke),
        shape: pill,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.text,
        textStyle: label,
        minimumSize: const Size(DialSize.minTapTarget, DialSize.minTapTarget),
        shape: pill,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.text),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
      largeSizeConstraints: const BoxConstraints.tightFor(
        width: DialSize.logButton,
        height: DialSize.logButton,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? p.accent : p.surface2,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => s.contains(WidgetState.disabled)
              ? p.muted.withValues(alpha: 0.5)
              : s.contains(WidgetState.selected)
              ? p.onAccent
              : p.muted,
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(textTheme.labelMedium!),
        side: const WidgetStatePropertyAll<BorderSide>(BorderSide.none),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(pill),
      ),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? p.accent : p.surface2,
      ),
      labelStyle: textTheme.labelMedium!.copyWith(
        color: WidgetStateColor.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? p.onAccent : p.text,
        ),
      ),
      checkmarkColor: p.onAccent,
      iconTheme: IconThemeData(color: p.muted, size: 18),
      side: BorderSide.none,
      shape: pill,
      padding: const EdgeInsets.symmetric(horizontal: DialSpace.xxs),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: p.accent,
      indicatorShape: pill,
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.onAccent : p.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> s) => textTheme.labelMedium!.copyWith(
          fontSize: 12,
          color: s.contains(WidgetState.selected) ? p.text : p.muted,
        ),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.surface,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: p.text,
      unselectedItemColor: p.muted,
      selectedLabelStyle: textTheme.labelMedium!.copyWith(fontSize: 12),
      unselectedLabelStyle: textTheme.labelMedium!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.text,
      contentTextStyle: textTheme.bodyMedium!.copyWith(
        color: p.bg,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      actionTextColor: p.bg,
      closeIconColor: p.bg,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(
        DialSpace.m,
        0,
        DialSpace.m,
        DialSpace.m,
      ),
      // Half the pill height: a one-line bar is a pill, a longer one stays
      // rounded without clipping its text.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DialSize.pillHeight / 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: card,
      barrierColor: p.scrim,
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: p.scrim,
      dragHandleColor: p.text.withValues(alpha: 0.18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DialRadius.sheet),
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      scrimColor: p.scrim,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DialRadius.card),
        side: BorderSide(color: p.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.muted,
      textColor: p.text,
      subtitleTextStyle: textTheme.bodySmall!.copyWith(color: p.muted),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.surface2,
      circularTrackColor: Colors.transparent,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.surface2,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.12),
      valueIndicatorColor: p.text,
      valueIndicatorTextStyle: textTheme.labelMedium!.copyWith(color: p.bg),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.text,
        borderRadius: BorderRadius.circular(DialRadius.tile),
      ),
      textStyle: textTheme.bodySmall!.copyWith(color: p.bg),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: card,
      textStyle: textTheme.bodyLarge,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(p.surface),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        elevation: const WidgetStatePropertyAll<double>(2),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DialRadius.tile),
          ),
        ),
      ),
    ),
  );
}
