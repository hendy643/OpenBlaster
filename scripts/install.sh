#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build OpenBlaster and install it.
#
#   scripts/install.sh [--no-build] [PREFIX]   (default /usr/local; DESTDIR is honoured)
#
# --no-build installs the release bundle that is already built (app/build/linux/*/release/bundle).
# Installs the app bundle, an `openblaster` link, the menu and login-autostart entries, the icon, the
# AppStream metadata, the licence and the udev rule that lets the audio group drive the LEDs. The packages
# are made from a DESTDIR install of this script (scripts/package.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

build=1
if [[ ${1:-} == --no-build ]]; then build=0; shift; fi
prefix=${1:-/usr/local}
dest=${DESTDIR:-}

arch=x64; [[ $(uname -m) == aarch64 ]] && arch=arm64
bundle=app/build/linux/$arch/release/bundle
# DESTDIR is for our own install below: flutter's cmake install would honour it and put the bundle there.
# A release is always built from clean: flutter's incremental cache can believe build/native_assets exists after
# it is gone, and then its cmake install fails.
if ((build)); then (cd app && unset DESTDIR && flutter clean >/dev/null && flutter pub get && flutter build linux --release); fi
[[ -x $bundle/openblaster ]] || { echo "no release bundle at $bundle: run without --no-build" >&2; exit 1; }

# the metainfo carries the release it belongs to
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' app/pubspec.yaml)
metainfo=$(mktemp)
trap 'rm -f "$metainfo"' EXIT
sed "s/@VERSION@/$version/; s/@DATE@/$(date -u +%F)/" packaging/org.openblaster.OpenBlaster.metainfo.xml >"$metainfo"

install -d "$dest$prefix/lib/openblaster" "$dest$prefix/bin" "$dest$prefix/share/applications" \
    "$dest$prefix/share/icons/hicolor/scalable/apps" "$dest$prefix/share/metainfo" \
    "$dest$prefix/share/licenses/openblaster" "$dest$prefix/lib/udev/rules.d" "$dest/etc/xdg/autostart"
cp -a "$bundle/." "$dest$prefix/lib/openblaster/"
ln -sf "../lib/openblaster/openblaster" "$dest$prefix/bin/openblaster"
install -m 644 install/org.openblaster.OpenBlaster.desktop "$dest$prefix/share/applications/"
install -m 644 install/org.openblaster.OpenBlaster-autostart.desktop \
    "$dest/etc/xdg/autostart/org.openblaster.OpenBlaster.desktop"
install -m 644 app/assets/openblaster.svg \
    "$dest$prefix/share/icons/hicolor/scalable/apps/org.openblaster.OpenBlaster.svg"
install -m 644 "$metainfo" "$dest$prefix/share/metainfo/org.openblaster.OpenBlaster.metainfo.xml"
install -m 644 LICENSES/Apache-2.0.txt "$dest$prefix/share/licenses/openblaster/Apache-2.0.txt"
install -m 644 install/70-openblaster.rules "$dest$prefix/lib/udev/rules.d/70-openblaster.rules"
# the virtual-surround impulse responses, if there are any (see hrtf/README.md)
if [[ -n $(find hrtf \( -name '*.wav' -o -name '*.sofa' \) -print -quit 2>/dev/null) ]]; then
    install -d "$dest$prefix/share/openblaster"
    cp -a hrtf "$dest$prefix/share/openblaster/hrtf"
    rm -f "$dest$prefix/share/openblaster/hrtf/README.md"
fi
if [[ -z $dest ]]; then
    echo "installed. For the LEDs: add yourself to the audio group, then reboot (or: sudo udevadm control --reload && sudo udevadm trigger -s pci)."
fi
