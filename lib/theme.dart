import 'package:flutter/material.dart';

ThemeData appTheme({String? fontFamily}) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.pink,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    fontFamily: fontFamily,
    inputDecorationTheme: const InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelAlignment: FloatingLabelAlignment.center,
      border: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.pink),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red),
      ),
    ),
  );
}
