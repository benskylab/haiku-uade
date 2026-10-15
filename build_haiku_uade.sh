#!/bin/bash
# Native UADE 3.05 package build for Haiku OS (x86_64)
# One-shot script: builds and packages the libzakalwe dependency, installs
# it, then extracts, patches, builds and packages UADE itself.
#
# Produces (in /boot/home/out):
#   libzakalwe-1.0.0-1-x86_64.hpkg
#   uade-3.05-1-x86_64.hpkg
#
# Usage: ./build_haiku_uade.sh [source-dir]
#   source-dir must contain:
#     uade-3.05.tar.bz2         upstream UADE source
#     uade-3.05.patchset        our Haiku patchset (git mailbox format,
#                               applies with: patch -p1)
#     libzakalwe-1.0.0.tar.gz   libzakalwe source (gitlab archive of commit
#                               f40771d472d1a3846969678d893846a48c16b025)
#   (default: /boot/home/build/uade-src)
#
# Prerequisites (package names):
#   pkgman install libao_devel bencode_tools_devel
set -e

UADE_VERSION="3.05"
UADE_REVISION="1"
ZAK_VERSION="1.0.0"
ZAK_REVISION="1"

SRCDIR="${1:-/boot/home/build/uade-src}"
WORK="/boot/home/build/uade-work"
OUT="/boot/home/out"
STAGE_UADE="/boot/home/build/stage-uade"
STAGE_ZAK="/boot/home/build/stage-zakalwe"
SYSTEM_PREFIX="/boot/system"

# ---- 0. preflight checks ----
command -v gcc >/dev/null 2>&1 || {
	echo "ERROR: gcc not found. Install the Haiku development tools first."
	exit 1
}
command -v pkg-config >/dev/null 2>&1 || {
	echo "ERROR: pkg-config not found (pkgman install pkg_config)."
	exit 1
}
pkg-config --exists ao 2>/dev/null || {
	echo "ERROR: libao development files not found (pkgman install libao_devel)."
	exit 1
}
test -e "$SYSTEM_PREFIX/develop/headers/bencodetools/bencode.h" 2>/dev/null || {
	echo "ERROR: bencode-tools development files not found (pkgman install bencode_tools_devel)."
	exit 1
}
for f in uade-$UADE_VERSION.tar.bz2 uade-$UADE_VERSION.patchset libzakalwe-$ZAK_VERSION.tar.gz; do
	test -e "$SRCDIR/$f" || {
		echo "ERROR: missing $SRCDIR/$f"
		exit 1
	}
done

rm -rf "$WORK" "$STAGE_UADE" "$STAGE_ZAK"
mkdir -p "$WORK/zakalwe" "$STAGE_ZAK" "$OUT/debuginfo"

# =====================================================================
# 1. libzakalwe (runtime dependency of uadecore and uade123)
# =====================================================================
echo "=== [1/4] building libzakalwe $ZAK_VERSION ==="
tar -C "$WORK/zakalwe" -xzf "$SRCDIR/libzakalwe-$ZAK_VERSION.tar.gz"
cd "$WORK/zakalwe"/libzakalwe-*

# configure is a bash feature-test script (not autoconf). It generates
# include/zakalwe/config.h and substitutes the compiler into Makefile.in.
./configure
make

# Stage the install tree: shared library into lib/, headers and a
# development symlink into develop/. Upstream's "make install" hardcodes
# PREFIX=/usr/local, so the files are copied by hand.
mkdir -p "$STAGE_ZAK/lib" "$STAGE_ZAK/develop/lib" "$STAGE_ZAK/develop/headers/zakalwe"
cp -a libzakalwe.so "$STAGE_ZAK/lib/"
cp -a include/zakalwe/*.h "$STAGE_ZAK/develop/headers/zakalwe/"
ln -s ../../lib/libzakalwe.so "$STAGE_ZAK/develop/lib/libzakalwe.so"

# strip the shared library, keep a debug copy alongside the packages
cp "$STAGE_ZAK/lib/libzakalwe.so" "$OUT/debuginfo/libzakalwe.so.debug"
strip "$STAGE_ZAK/lib/libzakalwe.so"

cat > "$STAGE_ZAK/.PackageInfo" <<EOF
name			libzakalwe
version			$ZAK_VERSION-$ZAK_REVISION
architecture		x86_64
summary			"C utility library with data structures and strings"
description		"libzakalwe is a small C library providing dynamic arrays, maps, trees, strings and other data structures. It is a dependency of the UADE Amiga music player. This package contains the shared library and the development headers."
packager			"Native UADE for Haiku build"
vendor			"libzakalwe project (gitlab.com/hors/libzakalwe)"
licenses {
	"BSD (2-clause)"
}
copyrights {
	"2026 Heikki Orsila"
}
provides {
	libzakalwe = $ZAK_VERSION-$ZAK_REVISION
	lib:libzakalwe = $ZAK_VERSION-$ZAK_REVISION
	libzakalwe_devel = $ZAK_VERSION-$ZAK_REVISION
	devel:libzakalwe = $ZAK_VERSION-$ZAK_REVISION
}
requires {
	haiku
}
urls {
	"https://gitlab.com/hors/libzakalwe"
}
EOF

rm -f "$OUT/libzakalwe-$ZAK_VERSION-$ZAK_REVISION-x86_64.hpkg"
package create -C "$STAGE_ZAK" \
	"$OUT/libzakalwe-$ZAK_VERSION-$ZAK_REVISION-x86_64.hpkg"
echo "created: $OUT/libzakalwe-$ZAK_VERSION-$ZAK_REVISION-x86_64.hpkg"

# Install it so the UADE build below can link and run against it, and so
# the uade package's lib:libzakalwe dependency resolves on this machine.
# pkgman cannot re-activate an already-installed package of the same
# version from a local file ("Name in use"), so drop any previous
# installation first.
pkgman uninstall -y libzakalwe >/dev/null 2>&1 || true
pkgman install -y "$OUT/libzakalwe-$ZAK_VERSION-$ZAK_REVISION-x86_64.hpkg"

# =====================================================================
# 2. extract and patch UADE
# =====================================================================
echo "=== [2/4] extracting and patching UADE $UADE_VERSION ==="
tar -C "$WORK" -xf "$SRCDIR/uade-$UADE_VERSION.tar.bz2"
cd "$WORK/uade-$UADE_VERSION"
patch -p1 < "$SRCDIR/uade-$UADE_VERSION.patchset"

# =====================================================================
# 3. build UADE
# =====================================================================
echo "=== [3/4] building UADE ==="
# The compile-time include path for bencode-tools and libzakalwe headers.
# The libraries themselves are found below via --bencode-tools-prefix /
# --libzakalwe-prefix (both point at /boot/system, which is also where the
# installed package will load them from at runtime).
export CFLAGS="-I$SYSTEM_PREFIX/develop/headers"

./configure \
	--prefix="$SYSTEM_PREFIX" \
	--bindir="$SYSTEM_PREFIX/bin" \
	--mandir="$SYSTEM_PREFIX/documentation/man/man1" \
	--bencode-tools-prefix="$SYSTEM_PREFIX" \
	--libzakalwe-prefix="$SYSTEM_PREFIX" \
	--without-libuade \
	--without-uadefs \
	--without-write-audio \
	--without-uadesimple

make

make install DESTDIR="$STAGE_UADE"

# hpkg file entries are relative to /boot/system, so flatten the staged
# /boot/system tree to the stage root: the stage holds
# {bin,lib,share,documentation}/... directly under it, matching how hpkg
# archives are laid out.
cp -a "$STAGE_UADE$SYSTEM_PREFIX/." "$STAGE_UADE/"
rm -rf "$STAGE_UADE/boot"

# ---- sanity check: player auto-detection and info printout, offline ----
src/frontends/uade123/uade123 --basedir=. -u src/uadecore \
	-S amigasrc/score/score -P players/AbyssHighestExperience \
	-g songs/AHX.Cruisin > "$WORK/get-info.txt" 2>&1
grep -q "playername: AHX v2" "$WORK/get-info.txt" || {
	echo "ERROR: smoke test failed, uade123 -g output was:"
	cat "$WORK/get-info.txt"
	exit 1
}

# ---- strip binaries; keep debug copies alongside the packages ----
mkdir -p "$OUT/debuginfo"
cp "$STAGE_UADE/bin/uade123" "$OUT/debuginfo/uade123.debug"
cp "$STAGE_UADE/lib/uade/uadecore" "$OUT/debuginfo/uadecore.debug"
strip "$STAGE_UADE/bin/uade123"
strip "$STAGE_UADE/lib/uade/uadecore"

# =====================================================================
# 4. package UADE
# =====================================================================
echo "=== [4/4] creating package ==="
cat > "$STAGE_UADE/.PackageInfo" <<EOF
name			uade
version			$UADE_VERSION-$UADE_REVISION
architecture		x86_64
summary			"Plays Amiga music formats through emulation"
description		"UADE (Unix Amiga Delitracker Emulator) plays music formats from the Commodore Amiga era by running the original 68k player programs inside an emulator core. Covers module formats, AHX, Startrekker and many tracker and custom player formats; the package includes the player binaries and their licenses. Provides the uade123 command line frontend with libao audio output, including the native Haiku Media Kit driver."
packager			"Native UADE for Haiku build"
vendor			"UADE project (zakalwe.fi/uade)"
licenses {
	"GNU GPL v2"
	"GNU LGPL v2.1"
}
copyrights {
	"2000-2024 Heikki Orsila, Michael Doering, and others"
}
provides {
	uade = $UADE_VERSION-$UADE_REVISION
	cmd:uade123 = $UADE_VERSION-$UADE_REVISION
}
requires {
	haiku >= r1~beta5
	lib:libao
	lib:libbencodetools
	lib:libzakalwe >= $ZAK_VERSION
}
urls {
	"https://zakalwe.fi/uade/"
}
EOF

rm -f "$OUT/uade-$UADE_VERSION-$UADE_REVISION-x86_64.hpkg"
package create -C "$STAGE_UADE" \
	"$OUT/uade-$UADE_VERSION-$UADE_REVISION-x86_64.hpkg"

echo "=== packages created ==="
ls -la "$OUT"/*.hpkg
echo
echo "=== package contents (uade) ==="
package list "$OUT/uade-$UADE_VERSION-$UADE_REVISION-x86_64.hpkg"
echo
echo "To install (the libzakalwe package is already installed by this script):"
echo "  pkgman install $OUT/uade-$UADE_VERSION-$UADE_REVISION-x86_64.hpkg"
echo "Then try:"
echo "  uade123 -g <song file>     # detect player without playing"
echo "  uade123 <song file>        # play through the system audio output"
