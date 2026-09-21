#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Update the Flutter dependencies to their newest versions, then prove the app still works.
#
#   scripts/update-deps.sh [--dry-run] [--no-verify]
#
#   --dry-run    show what would change, change nothing
#   --no-verify  skip `flutter analyze` and `flutter test` afterwards
#
# Raises the constraints in app/pubspec.yaml to the newest major versions (`pub upgrade --major-versions`), and
# everything else (transitive packages) to the newest that fits. Packages in KEEP are left alone on purpose.
# A package that another one caps (dbus is capped by yaru) rises only as far as that allows. Review the
# diff, run the app once, then commit pubspec.yaml and pubspec.lock.
set -euo pipefail
cd "$(dirname "$0")/../app"

# name -> why it stays
declare -A KEEP=(
    [tray_manager]="0.7's native API registers no tray icon on KDE Plasma; 0.5.x (appindicator) works"
)

dry=() verify=1
for arg in "$@"; do
    case $arg in
    --dry-run) dry=(--dry-run) ;;
    --no-verify) verify=0 ;;
    -h | --help) sed -n 4,15p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# the packages with a version in pubspec.yaml (not `flutter`/`flutter_test`, which come from the SDK)
mapfile -t all < <(awk '/^(dependencies|dev_dependencies):/ {on=1; next} /^[^ #]/ {on=0}
                        on && match($0, /^  [a-z0-9_]+: +[\^<>=0-9]/) {sub(/:.*/, "", $1); print $1}' pubspec.yaml)
upgrade=()
for pkg in "${all[@]}"; do
    if [[ -n ${KEEP[$pkg]:-} ]]; then echo "keeping $pkg: ${KEEP[$pkg]}"; else upgrade+=("$pkg"); fi
done

flutter pub upgrade --major-versions "${dry[@]}" "${upgrade[@]}" # the newest major of each package we depend on
flutter pub upgrade "${dry[@]}"                                  # and the newest of everything below them

if [[ ${#dry[@]} -eq 0 ]]; then
    echo; echo "still behind (held back by a constraint or by KEEP):"
    flutter pub outdated --no-dev-dependencies --transitive 2>/dev/null | sed -n '1,/^$/p' | head -20 || true
    ((verify)) && { flutter analyze && flutter test; }
    echo; git diff --stat -- pubspec.yaml pubspec.lock
fi
