# Development

OpenBlaster is one Flutter/Dart application. There is no server and no C or C++ of ours: it talks to the
card from inside the app, through `dart:ffi` bindings to the system's own libasound (the ALSA controls) and
libc (`mmap` of the card's BAR2 window for the LEDs).

## Requirements

* the Flutter SDK with its Linux desktop toolchain (`flutter doctor`), which brings CMake, Ninja, clang
  and GTK 3
* `libayatana-appindicator3` (the tray icon) and `libasound2` at run time

Arch/CachyOS: `sudo pacman -S flutter alsa-lib libayatana-appindicator` (flutter is in the AUR).
Ubuntu: `sudo apt install libgtk-3-dev libayatana-appindicator3-dev libasound2-dev` and Flutter from its installer.

## Test

```sh
cd app
flutter analyze
flutter test
```

Everything runs against in-memory hardware (`MemoryAlsaIo`, `MemoryBar2`, `MemoryStore`) except
`test/hw/real_card_test.dart`, which only *reads* your real card if there is one and is skipped otherwise.

## Run

```sh
scripts/dev-run.sh            # a made-up AE-5 Plus: nothing on your card changes
scripts/dev-run.sh --real     # your real card; changes real settings
```

## Lighting needs one permission

The LEDs are driven through `/sys/class/sound/card<N>/device/resource2`, which is root-only. Install
`install/70-openblaster.rules` (`scripts/install.sh` does), be in the `audio` group, and re-plug or reboot.
For a quick try without that: `sudo chgrp $USER /sys/bus/pci/devices/<pci-address>/resource2 && sudo chmod 660 ...`.
Without access the app works and shows a notice; only the Lighting page is missing.

## Adding a control

If the in-tree driver exposes it, it is one line in `app/lib/src/hw/catalog.dart`: the stable id, the page,
the label and the ALSA control's name (`amixer -c<card> controls` lists them). The kind, range and choices
come from the card and the window builds its pages from what it finds. Add a test in `test/hw/alsa_test.dart`
if it needs anything special (an inverted switch, say).

## Layout

```
app/lib/main.dart            start-up, command line
app/lib/src/hw/              the hardware, pure Dart: catalogue, ALSA backend + libasound bindings,
                             lighting (settings, renderer, APA102 encoder, BAR2 port), discovery, stores
app/lib/src/local_client.dart  the cards, their timers (poll, animate, save), as the window sees them
app/lib/src/{app_state,app,ui/} the window (Yaru theme), state holder, tray
app/test/                    unit, widget and in-process integration tests
install/                     desktop entries, udev rule       scripts/  dev-run.sh, install.sh
```

## Releasing

1. Set `version:` in `app/pubspec.yaml` (e.g. `0.2.0+1`) and merge to master.
2. Tag that commit and push the tag:

   ```sh
   git tag v0.2.0 && git push origin v0.2.0        # v0.2.0-rc.1 makes a pre-release of 0.2.0
   ```

`.github/workflows/release.yml` then checks the tag is on master and matches the pubspec, runs analyze and the
tests, and runs `scripts/package.sh`: it builds the release bundle **once**, stages it (`scripts/install.sh` into a
`/usr` + `/etc` tree) and packages that tree with [fpm](https://fpm.readthedocs.io), so every package ships the same
files.

| Package | Made by | Checked in CI |
|---|---|---|
| tarball | `scripts/package.sh tar` | |
| `.deb` | `scripts/package.sh deb` (fpm) | installed on Ubuntu 24.04, libraries resolve |
| `.rpm` | `scripts/package.sh rpm` (fpm, rpmbuild) | installed on Fedora, libraries resolve |
| Arch `.pkg.tar.zst` | `scripts/package.sh pacman` (fpm) | installed on Arch, libraries resolve |

All of them and `SHA256SUMS` go on a GitHub release. Locally: `scripts/package.sh` (needs `fpm`, `rpmbuild`, `zstd`;
`gem install --user-install fpm` and put `~/.local/share/gem/ruby/*/bin` on PATH). Dependencies per distro are in
`scripts/package.sh`.

The bundle is built on Ubuntu 24.04, so it needs glibc 2.39 or newer (Ubuntu 24.04+, Debian 13+, Fedora 40+, current Arch).

Lighting: the packages install the udev rule; add yourself to the `audio` group. Publishing to the AUR or an apt/dnf
repository is not automated.
