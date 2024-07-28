import 'package:flutter/material.dart';

class InfoBox extends StatelessWidget {
  const InfoBox({
    super.key,
    required this.message,
    required this.color,
  });

  final String message;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1,
      child: ColoredBox(
        color: color.shade800,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
