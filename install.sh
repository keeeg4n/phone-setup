#!/bin/bash
# Install phone-setup: Android ↔ Linux continuity (mirroring, webcam, photos,
# files, calls, audio) built on scrcpy, KDE Connect, PipeWire and Audio Share.
# Tested on Fedora 44 + GNOME 50. Safe to re-run (updates in place).
#
#   ./install.sh            install everything (asks before the optional webcam driver)
#   ./install.sh --no-webcam
set -euo pipefail

SCRCPY_VERSION=3.3.4        # tested version; v4 changed options, bump deliberately
AUDIOSHARE_VERSION=0.3.4

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
LIB="$HOME/.local/lib/phone-continuity"
SHARE="$HOME/.local/share"
UNITS="$HOME/.config/systemd/user"
WEBCAM=ask
[ "${1:-}" = "--no-webcam" ] && WEBCAM=no

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# download <url> <file> ; verify <file> <expected-sha256>
download() { curl -fsSL --retry 3 -o "$2" "$1"; }
verify() {
  local got; got=$(sha256sum "$1" | cut -d' ' -f1)
  [ "$got" = "$2" ] || { echo "  Checksum mismatch for $(basename "$1") — aborting."; exit 1; }
}

# ── 1. System packages ─────────────────────────────────────────────────────
bold "1. System packages (sudo)"
if command -v dnf >/dev/null; then
  sudo dnf install -y --setopt=install_weak_deps=False \
    kde-connect sshfs zenity libnotify pulseaudio-utils bluez \
    python3-gobject nautilus-python curl tar unzip >/dev/null
  ok "kde-connect, sshfs, zenity, pactl, nautilus-python, …"
else
  warn "Not a dnf system — install these yourself: kde-connect sshfs zenity libnotify pactl bluez python3-gobject nautilus-python"
fi

# ── 2. scrcpy (+ bundled adb) ──────────────────────────────────────────────
bold "2. scrcpy $SCRCPY_VERSION"
if [ -x "$SHARE/scrcpy/scrcpy" ] && "$SHARE/scrcpy/scrcpy" --version 2>/dev/null | grep -q "scrcpy $SCRCPY_VERSION"; then
  ok "Already installed"
else
  base="https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION"
  tarball="scrcpy-linux-x86_64-v$SCRCPY_VERSION.tar.gz"
  download "$base/$tarball" "$TMP/$tarball"
  download "$base/SHA256SUMS.txt" "$TMP/SHA256SUMS.txt"
  verify "$TMP/$tarball" "$(awk -v f="$tarball" '$2==f || $2=="*"f {print $1}' "$TMP/SHA256SUMS.txt")"
  rm -rf "$SHARE/scrcpy"; mkdir -p "$SHARE/scrcpy"
  tar xzf "$TMP/$tarball" -C "$SHARE/scrcpy" --strip-components=1
  ok "Downloaded and checksum-verified"
fi
mkdir -p "$BIN" "$SHARE/man/man1" "$SHARE/icons/hicolor/256x256/apps"
ln -sf "$SHARE/scrcpy/scrcpy" "$BIN/scrcpy"
ln -sf "$SHARE/scrcpy/adb" "$BIN/adb"
cp "$SHARE/scrcpy/scrcpy.1" "$SHARE/man/man1/" 2>/dev/null || true
cp "$SHARE/scrcpy/icon.png" "$SHARE/icons/hicolor/256x256/apps/scrcpy.png" 2>/dev/null || true

# ── 3. Audio Share (laptop sound → phone) ──────────────────────────────────
bold "3. Audio Share $AUDIOSHARE_VERSION"
AS_DIR="$SHARE/audio-share"
if [ -x "$AS_DIR/bin/as-cmd" ] && [ -f "$AS_DIR/audio-share-app.apk" ]; then
  ok "Already installed"
else
  base="https://github.com/mkckr0/audio-share/releases/download/v$AUDIOSHARE_VERSION"
  for f in audio-share-server-cmd-linux.tar.gz "audio-share-app-$AUDIOSHARE_VERSION-release.apk"; do
    download "$base/$f" "$TMP/$f"; download "$base/$f.sha256" "$TMP/$f.sha256"
    verify "$TMP/$f" "$(grep -oE '[0-9a-fA-F]{64}' "$TMP/$f.sha256" | head -1 | tr A-F a-f)"
  done
  mkdir -p "$AS_DIR"
  tar xzf "$TMP/audio-share-server-cmd-linux.tar.gz" -C "$AS_DIR" --strip-components=1
  cp "$TMP/audio-share-app-$AUDIOSHARE_VERSION-release.apk" "$AS_DIR/audio-share-app.apk"
  ok "Downloaded and checksum-verified"
fi

# ── 4. Phone tools ─────────────────────────────────────────────────────────
bold "4. Phone tools"
mkdir -p "$LIB" "$SHARE/nautilus-python/extensions" "$SHARE/applications" "$UNITS"
install -m 755 "$SRC"/bin/* "$BIN/"
install -m 644 "$SRC/lib/common.sh" "$LIB/"
install -m 644 "$SRC/nautilus/phone_photo.py" "$SHARE/nautilus-python/extensions/"
for f in "$SRC"/applications/*.desktop; do
  sed "s|@BINDIR@|$BIN|g" "$f" > "$SHARE/applications/$(basename "$f")"
done
update-desktop-database "$SHARE/applications" 2>/dev/null || true
ok "Commands in $BIN, menu entries, Files right-click item"

# ── 5. Background services ─────────────────────────────────────────────────
bold "5. Background services"
install -m 644 "$SRC"/systemd/*.service "$UNITS/"
systemctl --user daemon-reload
for s in phone-automount phone-bt-noaudio phone-calls; do
  systemctl --user enable --now "$s.service" >/dev/null 2>&1 && ok "$s" || warn "$s didn't start"
done

# ── 6. Webcam driver (optional, needs RPM Fusion) ──────────────────────────
bold "6. Phone-as-webcam driver (v4l2loopback)"
if lsmod | grep -q '^v4l2loopback' && [ -e /dev/video10 ]; then
  ok "Already set up"
else
  if [ "$WEBCAM" = ask ]; then
    read -rp "  Install the virtual webcam driver (needs RPM Fusion, sudo)? [Y/n] " a
    [[ "$a" =~ ^[Nn] ]] && WEBCAM=no || WEBCAM=yes
  fi
  if [ "$WEBCAM" = yes ]; then
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
      sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" >/dev/null
    fi
    sudo dnf install -y akmod-v4l2loopback v4l2loopback >/dev/null
    echo 'options v4l2loopback video_nr=10 card_label="Phone Camera" exclusive_caps=1' | sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null
    echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf >/dev/null
    sudo akmods --force >/dev/null 2>&1 || true
    if sudo modprobe v4l2loopback 2>/dev/null; then
      ok "\"Phone Camera\" at /dev/video10"
    else
      warn "Driver built but didn't load. With Secure Boot on, enroll the akmods key:"
      warn "  sudo mokutil --import /etc/pki/akmods/certs/public_key.der   (then reboot)"
    fi
  else
    warn "Skipped — Phone Camera won't work until you re-run with the driver."
  fi
fi

bold "Done."
cat <<EOF
  Next: plug your Android phone in by USB (with USB debugging on) and run:

      phone-setup

  It pairs KDE Connect and Bluetooth, turns on wireless debugging and walks you
  through Extend Unlock. Re-run it whenever the phone restarts.
EOF
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on your PATH — add it to use the commands from a terminal." ;; esac
