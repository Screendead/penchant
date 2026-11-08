import 'package:flutter_riverpod/flutter_riverpod.dart';

// A sealed document is unreadable to a build without the key, so turning this
// back off strands every journal already sealed.
const bool e2eeEnabled = true;

final e2eeEnabledProvider = Provider<bool>((ref) => e2eeEnabled);
