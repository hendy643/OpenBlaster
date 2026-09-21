#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run OpenBlaster from source for manual testing.
#
#   scripts/dev-run.sh [--real] [flutter run args...]
#
#   (default)  a made-up AE-5 Plus (--demo): nothing on your card changes
#   --real     your real card: what you click changes real settings. The LEDs need the udev rule
#              (install/70-openblaster.rules) or a run as root; without either, the Lighting page is
#              missing and the window says so.
#
# The app talks to the card itself: there is no server to start. --verbose is always on so the terminal
# shows what the window asks of the card.
set -euo pipefail
cd "$(dirname "$0")/../app"

# Arguments for the app go through --dart-entrypoint-args; anything after a bare `--` would be read by
# flutter as the file to run, and a bare --verbose would turn on flutter's own logging.
args=(--dart-entrypoint-args=--no-tray --dart-entrypoint-args=--verbose)
if [[ ${1:-} == --real ]]; then shift; else args+=(--dart-entrypoint-args=--demo); fi
flutter pub get >/dev/null
exec flutter run -d linux "${args[@]}" "$@"
