import 'package:flutter_riverpod/flutter_riverpod.dart';

// Stays false until the whole stack (#115, #117, #114, #116) and the key
// service are on master: a sealed document is unreadable to a build without
// the key, so no single PR may start sealing.
const bool e2eeEnabled = false;

final e2eeEnabledProvider = Provider<bool>((ref) => e2eeEnabled);
