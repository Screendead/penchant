import 'package:flutter/material.dart';

class InfoBox extends StatelessWidget {
  const InfoBox({
    super.key,
    required this.message,
    this.isError = false,
    this.onRetry,
  });

  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSurface;

    return Center(
      heightFactor: 1,
      child: Semantics(
        liveRegion: isError,
        child: ColoredBox(
          color: isError
              ? scheme.errorContainer
              : scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(foregroundColor: foreground),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// An error in place of a whole screen's content.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: InfoBox(message: message, isError: true, onRetry: onRetry),
      ),
    );
  }
}
