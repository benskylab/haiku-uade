# UADE 3.05 on Haiku

UADE (Unix Amiga Delitracker Emulator) plays Amiga music formats (modules,
AHX, custom player formats) through a UAE-derived m68k emulator. This repo
ports UADE 3.05 to Haiku (x86_64) and packages it as installable
`.hpkg` files plus official-format HaikuPorts recipes.

**Status: working.** It builds and plays Amiga music, both from a file and
live through Haiku's Media Kit.

## What you get

- `uade123` - the CLI frontend. Detects the player automatically, prints
  song info with `-g`, and outputs audio through libao (including Haiku's
  native Media Kit driver).
- `uadecore` - the emulator daemon (m68k CPU + Amiga custom chips), talking
  to `uade123` over a `socketpair()`.
- `players/` + `score` - Amiga-side (m68k) eagleplayers and the score
  helper, run inside the emulator. The tarball ships `score` prebuilt, so
  vasm is not required.

## Install

Prebuilt packages are in `haikuports/packages/`:

```
libzakalwe-1.0.0-1-x86_64.hpkg        # runtime dependency
uade-3.05-1-x86_64.hpkg               # the player
```

Install both with Haiku's package manager (uade depends on libzakalwe, so
install them together):

```
cd haikuports/packages
pkgman install -y ./libzakalwe-1.0.0-1-x86_64.hpkg ./uade-3.05-1-x86_64.hpkg
```

Devel and debuginfo packages are also provided. Once installed, `uade123`
is on the default PATH:

```
$ uade123 -g song.mod
$ uade123 -1 song.mod                 # play live
$ uade123 -1 -f out.wav song.mod      # render to WAV
```

## Building

Two independent paths are provided, both validated on Haiku.

### 1. Hand-built package script

`build_haiku_uade.sh` builds both `.hpkg` files from source in one step.
It compiles libzakalwe and UADE, stages them, and packages them. It is
idempotent (safe to re-run).

### 2. HaikuPorts recipes

Standard recipes live under `haikuports/`:

- `dev-libs/libzakalwe/libzakalwe-1.0.0.recipe`
- `media-sound/uade/uade-3.05.recipe`

Build them with haikuporter (libzakalwe first, since uade depends on it):

```
haikuporter --test libzakalwe
haikuporter --test uade
```

The uade recipe's `TEST()` verifies player detection and renders the
bundled demo song to a WAV file, so `--test` needs no audio device.

## Dependencies

- **libao** and **bencode-tools** - from HaikuPorts, no patches needed.
  Haiku's libao ships a native `haiku` Media Kit output driver.
- **libzakalwe** - not in HaikuPorts; provided here as its own recipe and
  hand-build script. It builds clean on Haiku.
- Not needed: zlib, fuse (`uadefs`), vasm, python (`write_audio`). All are
  disabled via configure flags; uadecore links only `-lm -lzakalwe`
  (plus `-lnetwork`).

## The Haiku patches

Three small, upstream-friendly patches (recorded in
`src/uade-3.05.patchset` and applied by the recipe) make UADE build and
run on Haiku:

| # | Problem on Haiku | Fix |
|---|---|---|
| 1 | `socketpair()` lives in `libnetwork`, not `libroot` | `configure`: add a `Haiku` OS case so `ARCHLIBS += -lnetwork` |
| 2 | `strsep()` is missing from libroot | add a `compat/` replacement plus a configure test, using upstream's own memmem/canonrep mechanism |
| 3 | `uade123 -f -` / `-c` rewrite `-` to `/dev/stdout`, which Haiku lacks | `uade123.c`: keep `-` as `-` under `__HAIKU__` (libao handles `-` itself) |

## Live audio

Live playback through Haiku's Media Kit tested and working.


## Layout

```
build_haiku_uade.sh       hand-built .hpkg build script
haikuports/               HaikuPorts recipes + built packages
  dev-libs/libzakalwe/
  media-sound/uade/
  packages/               the .hpkg files
src/uade-3.05.patchset    the Haiku patches (mailbox format)
src/uade-3.05.tar.bz2     upstream source tarball
uade-3.05/                patched source tree
```

## License

GPL v2; the `src/frontends/common/` parts are LGPL v2.1. libzakalwe is
BSD (2-clause).
