import 'package:flutter_riverpod/flutter_riverpod.dart';

// False until #115 → #117 → #114 → #116 are merged and the key service lands.
const bool e2eeEnabled = false;

/// [e2eeEnabled], as a provider so tests can turn the encryption UI on.
final e2eeEnabledProvider = Provider<bool>((ref) => e2eeEnabled);
