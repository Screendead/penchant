# Jetifier, direct buildDir assignment, and a stale applicationId TODO left from the original scaffold

**Severity:** low

gradle.properties still enables Jetifier, a bridge for legacy android.support libraries that the installed Flutter SDK's own template no longer emits, in a project with nothing to jetify. The root build.gradle assigns the root and subproject build directories directly while Flutter's current template uses the Gradle Provider API through layout.buildDirectory.

app/build.gradle keeps the boilerplate comment instructing the reader to choose a unique application id directly above the line where the id was already changed away from the com.example default.

## Evidence

- `android/gradle.properties:3` — `android.enableJetifier=true`
- `android/build.gradle:8` — `rootProject.buildDir = "../build"`
- `android/build.gradle:10` — `project.buildDir = "${rootProject.buildDir}/${project.name}"`
- `android/app/build.gradle:37` — `// TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).`
- `android/app/build.gradle:38` — `applicationId = "com.screendead.tracker.tracker"`
