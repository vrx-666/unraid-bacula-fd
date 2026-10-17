#!/bin/bash
# Check that the built package runs on a given Unraid release, without Unraid:
# unpack the release's root filesystem and run bacula-fd in a chroot.
# Usage: ./test-unraid.sh <unraid-version> [package.txz]
set -euo pipefail

VER=${1:?usage: $0 <unraid-version> [package.txz]}
PKG=$(realpath "${2:-$(ls out/bacula-fd-*.txz | head -1)}")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

read -r URL SHA < <(curl -fsSL https://releases.unraid.net/json |
  jq -r --arg v "$VER" '.[] | select(.version == $v) | "\(.url) \(.sha256)"') || true
if [ -z "${URL:-}" ]; then   # not stable: try the current beta/rc (the zip sits next to its changelog .txt)
  read -r URL SHA < <(curl -fsSL "https://releases.unraid.net/os?branch=next" |
    jq -r --arg v "$VER" 'select(.version == $v) | "\(.changelog | sub("\\.txt$"; ".zip")) \(.sha256)"') || true
fi
[ -n "${URL:-}" ] || { echo "Unraid $VER not found in release list" >&2; exit 1; }

echo "Downloading Unraid $VER"
# Big download: a stalled connection never ends on its own, so abort below 100 kB/s for 60 s and retry.
curl -fsSL --retry 3 --retry-all-errors --speed-limit 102400 --speed-time 60 -o "$WORK/unraid.zip" "$URL"
echo "$SHA  $WORK/unraid.zip" | sha256sum -c --quiet -
python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2], ["bzroot", "bzmodules", "bzfirmware"])' \
  "$WORK/unraid.zip" "$WORK"
rm "$WORK/unraid.zip"
cp "$PKG" "$WORK/pkg.txz"

# bzroot = uncompressed microcode cpio, then the root cpio compressed with zstd (7.3) or xz.
# /usr is not in bzroot but in a squashfs: bzfirmware up to 7.2, bzmodules from 7.3.
docker run --rm -v "$WORK:/w" debian:trixie-slim bash -euc '
  apt-get -qq update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y xz-utils zstd cpio squashfs-tools >/dev/null
  END=$(grep -obUa "TRAILER!!!" /w/bzroot | head -1 | cut -d: -f1)
  tail -c +$((END + 1)) /w/bzroot > /w/rest
  ZST=$(grep -obUaP "\x28\xB5\x2F\xFD" /w/rest | head -1 | cut -d: -f1); ZST=${ZST:-999999999}
  XZ=$(grep -obUaP "\xFD7zXZ\x00" /w/rest | head -1 | cut -d: -f1); XZ=${XZ:-999999999}
  if [ "$ZST" -lt "$XZ" ]; then OFF=$ZST; DEC="zstd -dc"; else OFF=$XZ; DEC="xz -dc"; fi
  mkdir /r && cd /r
  tail -c +$((OFF + 1)) /w/rest | $DEC | cpio -idm --quiet 2>/dev/null || true
  [ -f /r/etc/unraid-version ] || { echo "FAIL: could not unpack bzroot"; exit 1; }
  for IMG in /w/bzmodules /w/bzfirmware; do   # whichever image carries lib64 is /usr
    if unsquashfs -l "$IMG" lib64 2>/dev/null | grep -q "^squashfs-root/lib64/"; then
      unsquashfs -q -n -f -d /r/usr "$IMG" lib64 >/dev/null
    fi
  done
  mkdir -p /r/dev && cp -a /dev/null /dev/random /dev/urandom /r/dev/   # OpenSSL needs a seed source
  echo "Unraid root: $(cat /r/etc/unraid-version)"
  tar xJf /w/pkg.txz -C /r && (cd /r && sh install/doinst.sh)
  cat > /r/tmp/fd.conf <<EOF
Director { Name = test-dir; Password = "x" }
FileDaemon { Name = test-fd; WorkingDirectory = /tmp; Pid Directory = /tmp; Plugin Directory = /usr/lib64/bacula }
Messages { Name = Standard; director = test-dir = all }
EOF
  if chroot /r /lib64/ld-linux-x86-64.so.2 --list /usr/sbin/bacula-fd | grep "not found"; then
    echo "FAIL: missing libraries"; exit 1
  fi
  chroot /r /usr/sbin/bacula-fd -t -c /tmp/fd.conf
  chroot /r /usr/sbin/bacula-fd -? 2>&1 | head -2
  echo "PASS"
'
