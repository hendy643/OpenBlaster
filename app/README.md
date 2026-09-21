# OpenBlaster app

The whole product: a Flutter/Dart desktop app. See ../DEVELOPMENT.md and ../docs/ARCHITECTURE.md.

    flutter pub get && flutter test
    flutter run -d linux --dart-entrypoint-args=--demo --dart-entrypoint-args=--no-tray

Flags: `--background` (start hidden in the tray), `--no-tray`, `--verbose`, `--demo`.
