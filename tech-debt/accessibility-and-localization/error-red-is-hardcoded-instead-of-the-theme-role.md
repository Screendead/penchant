# Eleven sites pick Colors.red directly rather than the colour scheme's error role

**Severity:** medium

`main.dart` seeds a dark `ColorScheme` from a pink seed, which derives its own error colour, and then hardcodes `Colors.red` for the `InputDecorationTheme`'s `errorBorder`; the same literal is reused for error text in the editor page, the record dialog, the not-found page, both charts and `register.dart`.

Two different reds end up representing the same error concept on screen: the framework-derived one used by `TextFormField`'s own validation text, and the hardcoded one used wherever the app renders its own message. Neither was checked against the other or against the seeded dark surface.

## Evidence

- `lib/errors/not_found.dart:23` — `color: Colors.red,`
- `lib/vice_chart.dart:33` — `color: Colors.red,`
- `lib/usage_graph_view.dart:82` — `color: Colors.red,`
- `lib/register.dart:94` — `color: emailIsValid! ? Colors.green : Colors.red,`
- `lib/main.dart:58` — `color: Colors.red,`
- `lib/vice_activity_editor_page.dart:296` — `style: const TextStyle(color: Colors.red),`
