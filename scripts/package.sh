#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build the release bundle once and package it with fpm (https://fpm.readthedocs.io):
#
#   scripts/package.sh [--no-build] [FORMAT...]      FORMAT: tar deb rpm pacman   (default: all four)
#
# Writes to dist/: openblaster-VERSION-linux-ARCH.tar.gz (a /usr + /etc tree), openblaster_VERSION_ARCH.deb, openblaster-VERSION-1.ARCH.rpm and
# and openblaster-VERSION-1-ARCH.pkg.tar.zst. All of them contain the same files, staged once by scripts/install.sh.
# deb, rpm and pacman need fpm; rpm also needs rpmbuild and pacman needs zstd.
set -euo pipefail
cd "$(dirname "$0")/.."

build=()
[[ ${1:-} == --no-build ]] && { build=(--no-build); shift; }
formats=("$@")
((${#formats[@]})) || formats=(tar deb rpm pacman)

version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' app/pubspec.yaml)
machine=$(uname -m)
stage=$PWD/dist/stage
rm -rf "$stage" && mkdir -p "$stage"
trap 'rm -rf "$stage"' EXIT
DESTDIR=$stage scripts/install.sh "${build[@]}" /usr

fpm_common=(
    -s dir -C "$stage" -n openblaster -v "$version" --iteration 1
    --license Apache-2.0 --url https://github.com/hendy643/SBX
    --maintainer 'hendy643 <hendy643@users.noreply.github.com>'
    --description 'Control Creative Sound Blaster cards: outputs, effects, equalizer, microphone and LED lighting'
    --category sound
    --after-install packaging/postinst.sh
    --force
)

tarball=dist/openblaster-$version-linux-$machine.tar.gz
tar --owner=0 --group=0 --numeric-owner -C "$stage" -czf "$tarball" .

for format in "${formats[@]}"; do
    case $format in
    tar) ;;
    deb)
        case $machine in x86_64) a=amd64 ;; aarch64) a=arm64 ;; *) echo "no deb architecture for $machine" >&2; exit 1 ;; esac
        fpm "${fpm_common[@]}" -t deb -a "$a" -p dist/ --deb-user root --deb-group root \
            --deb-priority optional --deb-recommends udev \
            -d 'libgtk-3-0t64 | libgtk-3-0' -d libayatana-appindicator3-1 -d 'libasound2t64 | libasound2' \
            usr etc
        ;;
    rpm)
        # the bundle's own libraries are private: no automatic requires, and rpmbuild must not strip or rewrite them
        fpm "${fpm_common[@]}" -t rpm -a "$machine" -p dist/ --rpm-user root --rpm-group root \
            --rpm-rpmbuild-define '__strip /bin/true' --rpm-rpmbuild-define '__os_install_post %{nil}' \
            --rpm-rpmbuild-define '_build_id_links none' --rpm-rpmbuild-define 'debug_package %{nil}' \
            -d gtk3 -d alsa-lib -d libayatana-appindicator-gtk3 \
            usr etc
        ;;
    pacman)
        fpm "${fpm_common[@]}" -t pacman -a "$machine" -p dist/ \
            -d gtk3 -d libayatana-appindicator -d alsa-lib \
            usr etc
        ;;
    *) echo "unknown format: $format (tar deb rpm pacman)" >&2; exit 2 ;;
    esac
done
rm -rf "$stage"
ls -1 dist
