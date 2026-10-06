# Development

OpenBlaster is one Flutter/Dart application. There is no server and no C or C++ of ours: it talks to the
card from inside the app, through `dart:ffi` bindings to the system's own libasound (the ALSA controls) and
libc (`mmap` of the card's BAR2 window for the LEDs).

## Requirements

`scripts/dev_setup.sh` installs everything for Ubuntu/Debian, Fedora and Arch-based distributions (it uses sudo):

* the Flutter SDK (cloned from Flutter's git repository at a fixed version, since only the AUR packages it) and the
  Linux desktop toolchain it needs: clang, CMake, Ninja, GTK 3
* the libraries the app is built and run with: `libasound` (ALSA) and `libayatana-appindicator3` (the tray icon)
* the tools of the test scripts (`amixer`, `pactl`, `pw-cat`), `gh` for `scripts/release.sh`, and `appstreamcli`
* the packaging tools, on every distribution, so any of them can build all four packages: `fpm` (from RubyGems),
  `rpmbuild`, `zstd` and `bsdtar`

`scripts/dev_setup.sh --check` only reports what is missing; `--dry-run` shows what it would install; `--help` lists
the rest.

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
2. Tag that commit and check it out:

   ```sh
   git tag v0.2.0 && git checkout v0.2.0        # v0.2.0-rc.1 makes a pre-release of 0.2.0
   ```

3. Run `scripts/release.sh`. It takes the most recent tag and checks that it is the checked-out commit, is on
   `origin/master`, matches the pubspec version and that the tree is clean; runs analyze and the tests; runs
   `scripts/package.sh`; writes `SHA256SUMS` and the release notes (the commits since the previous release, the
   packages and their checksums, a link to the full changelog); pushes the tag if GitHub does not have it and
   publishes everything with the `gh` CLI (it must be logged in). `--dry-run` does all of it except the pushes, so
   you can read the notes first; `--help` lists the other options. A tag that is already on GitHub at another commit
   is an error: it is never moved for you. An existing release for the tag is updated, with its files replaced.

`scripts/package.sh` builds the release bundle **once**, stages it (`scripts/install.sh` into a `/usr` + `/etc`
tree) and packages that tree with [fpm](https://fpm.readthedocs.io), so every package ships the same files.

| Package | Made by |
|---|---|
| tarball | `scripts/package.sh tar` |
| `.deb` | `scripts/package.sh deb` (fpm) |
| `.rpm` | `scripts/package.sh rpm` (fpm, rpmbuild) |
| Arch `.pkg.tar.zst` | `scripts/package.sh pacman` (fpm) |

All of them and `SHA256SUMS` go on the GitHub release. `scripts/package.sh` needs `fpm`, `rpmbuild` and `zstd`
(`gem install --user-install fpm`, and put `~/.local/share/gem/ruby/*/bin` on PATH). Dependencies per distro are in
`scripts/package.sh`.

The bundle needs at least the glibc of the machine that built it, so release from the oldest distribution you want to
support (Ubuntu 24.04 means glibc 2.39: Ubuntu 24.04+, Debian 13+, Fedora 40+, current Arch).

Lighting: the packages install the udev rule; add yourself to the `audio` group. Publishing to the AUR or an apt/dnf
repository is not automated.
