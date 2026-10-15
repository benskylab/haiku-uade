# UADE 3.05 on Haiku — port feasibility result

**Verdict: YES, UADE ports to Haiku (x86_64) essentially unmodified.**
Three small patches (recorded in `src/uade-3.05.patchset`) are all that's
needed. The result was built and run on the live Haiku R1~beta6 VM and it
**plays Amiga music**: the bundled AHX tune renders 94.8 s of correct
44.1 kHz stereo audio, and eagleplayer end-detection works.

Operational details (VM access, exact build commands, gotchas, open issues)
live in [AGENTS.md](AGENTS.md).

## What UADE is
UADE (Unix Amiga Delitracker Emulator) plays Amiga music formats
(modules, AHX, custom player formats…) through a UAE-derived m68k
emulator. Architecture on Haiku:

- `uadecore` — the emulator daemon (m68k CPU emulation + Amiga custom chips).
- `uade123` — CLI frontend; talks to `uadecore` over a `socketpair()` IPC
  and outputs audio through **libao**.
- `players/` + `score` — Amiga-side (m68k) eagleplayers and the score
  helper, both executed *inside the emulator*; the tarball ships `score`
  prebuilt, so **vasm is not required**.

## The patches (3)
| # | Problem on Haiku | Fix |
|---|---|---|
| 1 | `socketpair()` is in `libnetwork`, not `libroot` | `configure`: add `Haiku` OS case → `ARCHLIBS += -lnetwork` |
| 2 | `strsep()` missing from libroot | `compat/strseptest.c` + `compat/strseprep.{c,h}` + configure test, using upstream's own memmem/canonrep replacement mechanism |
| 3 | `uade123 -f -`/`-c` rewrite `-` to `/dev/stdout`, which Haiku lacks (libao handles `-` itself) | `uade123.c`: keep `-` under `__HAIKU__` |

All three are upstream-friendly (auto-detecting / `#ifdef`-guarded).

## Dependencies
- HaikuPorts: `libao_devel`, `bencode_tools_devel` — no patches needed.
- **libzakalwe** (gitlab.com/hors/libzakalwe) — not in HaikuPorts; builds
  clean on Haiku, but its `make install` ignores `--prefix`, so copy
  `libzakalwe.so*` + `include/zakalwe` by hand (see AGENTS.md).
- Not needed: zlib, fuse (`uadefs`), vasm, python (`write_audio`) — all
  disabled via configure flags.

## Evidence from the VM
```
$ uade123 -1 -f /tmp/AHX.wav songs/AHX.Cruisin
... Playing time position 94.8s ...
song end: player
song end: No more subsongs left
$ ls -l /tmp/AHX.wav     # 16736172 B = 94.875 s * 44100 * 2ch * 2B (+44B hdr)
$ md5sum /tmp/AHX.wav    # 8423eecd684a77afc76be2e3da45a3b7 (reproducible)
```

## Known limitation (environment, not UADE)
**Live audio couldn't be verified on this VM**: the VM's Media Kit has no
audio-output node (`BMediaRoster::GetAudioOutput()` → `B_NAME_NOT_FOUND`,
`BSoundPlayer::InitCheck()` → `B_ERROR`), so libao's native `haiku` Media
Kit driver can't open. Haiku's own `media_client play` fails identically.
The kernel HDA driver is bound (`/dev/audio/hmulti/hda` exists), so this
looks like a VM-guest-audio configuration issue. File output (`-f file`)
and streaming (`-f -`, `-c`) are fully working and are the recommended way
to use UADE on Haiku until the audio stack is sorted out (e.g. convert with
`uade123 -c -e raw` → pipe into a player, or write WAVs).

## Next steps
1. Verify live playback on a Haiku machine with working audio.
2. Write the HaikuPorts recipe + hpkg (needs a libzakalwe recipe first),
   following the `../rsync` and `../whois` model.
