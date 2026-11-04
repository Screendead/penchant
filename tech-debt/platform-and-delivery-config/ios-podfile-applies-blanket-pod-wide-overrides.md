# post_install relaxes modular includes for every pod target, and forces the deployment target on all of them

**Severity:** low

ios/Podfile's post_install hook sets the iOS deployment target to 15.0 on every pod target and allows non-modular includes in framework modules for every target. The deployment target override is needed: without it several pods build at 9.0 to 12.0 and Xcode refuses them (tried 2026-11-04). It does hide a pod that genuinely needs a higher minimum. The modular-includes relaxation is unverified: `flutter build ios --simulator --debug` fails at the Flutter.framework unpack step on this machine with or without it, so removal could not be tested.

## Evidence

- `ios/Podfile:43` — `config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'`
- `ios/Podfile:44` — `config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'`
