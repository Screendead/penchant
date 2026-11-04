import 'package:flutter/material.dart';

ThemeData appTheme() {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.pink,
    brightness: Brightness.dark,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelAlignment: FloatingLabelAlignment.center,
      border: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.pink),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error),
      ),
    ),
  );
}
