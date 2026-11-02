# post_install forces one deployment target and relaxes modular includes for every pod target

**Severity:** low

ios/Podfile's post_install hook unconditionally sets the iOS deployment target to 15.0 on every pod target regardless of what each podspec declares, and separately allows non-modular includes in framework modules for every target.

The forced target arrived with the 2026 switch to static framework linkage, and the modular-includes relaxation predates it and was carried through unchanged. Both apply to the entire pod graph rather than the specific pods that needed them, so a future pod requiring a genuinely higher minimum is silently downgraded rather than flagged.

## Evidence

- `ios/Podfile:43` — `config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'`
- `ios/Podfile:44` — `config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'`
