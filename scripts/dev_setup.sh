#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Install what is needed to develop OpenBlaster and to build every package from any machine: Ubuntu/Debian, Fedora
# and Arch-based distributions (Manjaro, CachyOS, EndeavourOS ...).
#
#   scripts/dev_setup.sh [--check] [--dry-run] [--no-flutter] [--no-packaging] [--flutter-version V] [--flutter-dir DIR]
#
#   --check              install nothing: say what is missing (exit 1 if something is)
#   --dry-run            print the commands instead of running them
#   --no-flutter         do not install the Flutter SDK
#   --no-packaging       skip the packaging tools (fpm, rpmbuild, zstd, bsdtar)
#   --flutter-version V  the Flutter SDK to install if there is none on PATH (default 3.47.6)
#   --flutter-dir DIR    where it goes (default ~/.local/share/flutter; linked into ~/.local/bin)
#
# Installs, with sudo, the Linux desktop toolchain (clang, cmake, ninja, GTK 3), the libraries the app uses (ALSA,
# the tray icon), the tools of the test scripts (amixer, pactl, pw-cat), gh for scripts/release.sh and, so that each of
# deb, rpm, pacman and tar can be built on any of these distributions, rpmbuild, zstd, bsdtar and fpm (from RubyGems).
# Flutter is not in the Ubuntu or Fedora repositories and only in the AUR on Arch, so it is cloned from Flutter's git
# repository at a fixed version. Safe to run again.
set -euo pipefail

check=0 dry=0 flutter=1 packaging=1 flutter_version=3.47.6 flutter_dir=$HOME/.local/share/flutter
while (($#)); do
    case $1 in
    --check) check=1; shift ;;
    --dry-run) dry=1; shift ;;
    --no-flutter) flutter=0; shift ;;
    --no-packaging) packaging=0; shift ;;
    --flutter-version) flutter_version=${2:?--flutter-version needs a version}; shift 2 ;;
    --flutter-dir) flutter_dir=${2:?--flutter-dir needs a directory}; shift 2 ;;
    -h | --help) sed -n 3,19p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done
die() { echo "dev_setup: $*" >&2; exit 1; }
run() { echo "+ $*"; ((dry)) || "$@"; }

# ---- which distribution (OS_RELEASE is for testing)
# shellcheck disable=SC1090
. "${OS_RELEASE:-/etc/os-release}"
case " ${ID:-} ${ID_LIKE:-} " in
*" arch "*) family=pacman ;;
*" fedora "* | *" rhel "*) family=dnf ;;
*" debian "* | *" ubuntu "*) family=apt ;;
*) die "unsupported distribution: ${PRETTY_NAME:-${ID:-unknown}} (Ubuntu/Debian, Fedora and Arch-based are)" ;;
esac

# What each list is for: build = the Linux desktop toolchain and the libraries the app is built against (Flutter's
# own tool runs `which`, which minimal Fedora and Arch images lack);
# tools = the test scripts, scripts/release.sh and AppStream validation; packaging = fpm's own needs (fpm itself
# comes from RubyGems) and the tools for all four formats (deb needs ar and tar; rpm needs rpmbuild; pacman needs
# bsdtar and zstd), so any of these systems can build every package.
case $family in
apt)
    build=(git curl unzip xz-utils zip clang cmake ninja-build pkg-config build-essential liblzma-dev
        libgtk-3-dev libayatana-appindicator3-dev libasound2-dev)
    tools=(alsa-utils pulseaudio-utils pipewire-bin python3 gh appstream udev)
    pack=(ruby ruby-dev rpm zstd libarchive-tools binutils tar)
    install_cmd=(apt-get install -y)
    refresh=(apt-get update)
    ;;
dnf)
    build=(git curl unzip xz zip which clang cmake ninja-build pkgconf-pkg-config gcc-c++ xz-devel
        gtk3-devel libayatana-appindicator-gtk3-devel alsa-lib-devel)
    tools=(alsa-utils pulseaudio-utils pipewire-utils python3 gh appstream systemd-udev)
    pack=(ruby ruby-devel rubygems rpm-build redhat-rpm-config gcc make zstd bsdtar binutils tar)
    install_cmd=(dnf install -y)
    refresh=()
    ;;
pacman)
    build=(git curl unzip xz zip which clang cmake ninja pkgconf gcc make gtk3 libayatana-appindicator alsa-lib)
    tools=(alsa-utils libpulse pipewire python github-cli appstream)
    pack=(ruby ruby-erb rpm-tools zstd libarchive binutils tar)  # Arch splits erb out of ruby; fpm needs it
    install_cmd=(pacman -S --needed --noconfirm)
    refresh=()
    ;;
esac

sudo=()
if ((EUID != 0)); then
    command -v sudo >/dev/null || die "not root and there is no sudo"
    sudo=(sudo)
fi

# ---- what is missing
# The commands the repository's scripts call, and the package that brings each is covered above; this is the check.
required=(git clang cmake ninja pkg-config gh pactl amixer python3)
((packaging)) && required+=(rpmbuild zstd bsdtar ar fpm)
((flutter)) && required+=(flutter)
missing() {
    local c
    for c in "${required[@]}"; do command -v "$c" >/dev/null || echo "$c"; done
}
user_gem_bin() { ruby -e 'puts Gem.user_dir + "/bin"' 2>/dev/null || true; }
# fpm from RubyGems lands in the user's gem bin directory, and Flutter is linked into ~/.local/bin: neither may be on
# PATH yet
add_path() { [[ -z $1 ]] || PATH=$1:$PATH; }
add_path "$(user_gem_bin)"
add_path "$HOME/.local/bin"

if ((check)); then
    list=$(missing | tr '\n' ' ')
    if [[ -n $list ]]; then echo "missing: $list"; exit 1; fi
    echo "everything is installed ($family)"
    exit 0
fi

# ---- system packages
pkgs=("${build[@]}" "${tools[@]}")
((packaging)) && pkgs+=("${pack[@]}")
echo "== $family: ${#pkgs[@]} packages"
((${#refresh[@]})) && run "${sudo[@]}" "${refresh[@]}"
run "${sudo[@]}" "${install_cmd[@]}" "${pkgs[@]}"

# ---- fpm
if ((packaging)) && ! command -v fpm >/dev/null; then
    echo "== fpm"
    run gem install --user-install --no-document fpm
    add_path "$(user_gem_bin)"
fi

# ---- Flutter
if ((flutter)) && ! command -v flutter >/dev/null; then
    echo "== Flutter $flutter_version in $flutter_dir"
    if [[ ! -d $flutter_dir/.git ]]; then
        run git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$flutter_dir"
    fi
    run mkdir -p "$HOME/.local/bin"
    run ln -sf "$flutter_dir/bin/flutter" "$HOME/.local/bin/flutter"
    run ln -sf "$flutter_dir/bin/dart" "$HOME/.local/bin/dart"
    export PATH=$flutter_dir/bin:$PATH
    run flutter precache --linux
fi

# ---- done
if ((dry)); then echo "dry run: nothing was installed"; exit 0; fi
list=$(missing | tr '\n' ' ')
[[ -z $list ]] || die "still missing: $list"
((flutter)) && flutter --version | head -1
echo "ready. Add to your shell profile if they are not on PATH already:"
echo "  export PATH=\"\$HOME/.local/bin:$(user_gem_bin):\$PATH\""
echo "then: cd app && flutter pub get && flutter test      (scripts/package.sh builds the packages)"
