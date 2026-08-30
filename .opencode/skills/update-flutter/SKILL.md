---
name: update-flutter
description: Flutterのアップデート手順スキルです
---
Use this skill whenever the user asks to upgrade a Flutter project to a newer SDK release.

## Workflow

1. Determine the current Flutter SDK version.
2. Determine the target Flutter SDK version.
3. Read the corresponding release notes from references/.
4. Identify breaking changes.
5. Update project configuration (SDK constraints, dependencies, platform settings).
6. Apply migrations (`dart fix` if applicable).
7. Run:
    - flutter pub get
    - dart fix --apply
    - dart format .
    - flutter analyze
    - flutter test
8. Summarize manual actions required.
