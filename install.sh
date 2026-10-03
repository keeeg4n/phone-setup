#!/bin/bash
# Install phone-setup: Android ↔ Linux continuity (mirroring, webcam, photos,
# files, calls, audio) built on scrcpy, KDE Connect, PipeWire and Audio Share.
# Supports Fedora (dnf) and Linux Mint / Ubuntu / Debian (apt), with GNOME Files
# or Nemo. Safe to re-run (updates in place).
#
#   ./install.sh            install everything (asks before the optional webcam driver)
#   ./install.sh --no-webcam
set -euo pipefail

SCRCPY_VERSION=3.3.4        # tested version; v4 changed options, bump deliberately
AUDIOSHARE_VERSION=0.3.4
MIN_PIPEWIRE_FOR_CALLS=1.4  # first release with Bluetooth telephony (org.pipewire.Telephony)

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
# version_ge A B: true if version A >= B
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# ── What are we installing onto? ───────────────────────────────────────────
if command -v dnf >/dev/null; then PM=dnf
elif command -v apt-get >/dev/null; then PM=apt
else PM=none; fi
FILE_MANAGERS=()
command -v nautilus >/dev/null && FILE_MANAGERS+=(nautilus)
command -v nemo >/dev/null && FILE_MANAGERS+=(nemo)

# ── 1. System packages ─────────────────────────────────────────────────────
bold "1. System packages (sudo)"
case $PM in
  dnf)
    pkgs=(kde-connect sshfs zenity libnotify pulseaudio-utils bluez python3-gobject curl tar unzip)
    [[ " ${FILE_MANAGERS[*]} " == *" nautilus "* ]] && pkgs+=(nautilus-python)
    [[ " ${FILE_MANAGERS[*]} " == *" nemo "* ]] && pkgs+=(nemo-python)
    sudo dnf install -y --setopt=install_weak_deps=False "${pkgs[@]}" >/dev/null
    ;;
  apt)
    pkgs=(kdeconnect sshfs zenity libnotify-bin pulseaudio-utils bluez python3-gi
          desktop-file-utils curl tar unzip)
    [[ " ${FILE_MANAGERS[*]} " == *" nautilus "* ]] && pkgs+=(python3-nautilus)
    [[ " ${FILE_MANAGERS[*]} " == *" nemo "* ]] && pkgs+=(nemo-python)
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" >/dev/null
    ;;
  none)
    warn "Neither dnf nor apt found — install these yourself: KDE Connect, sshfs, zenity,"
    warn "notify-send, pactl, bluez, Python GObject bindings, nautilus-python or nemo-python."
    pkgs=()
    ;;
esac
[ ${#pkgs[@]} -gt 0 ] && ok "${pkgs[*]}"

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
mkdir -p "$BIN" "$SHARE/man/man1"
ln -sf "$SHARE/scrcpy/scrcpy" "$BIN/scrcpy"
ln -sf "$SHARE/scrcpy/adb" "$BIN/adb"
cp "$SHARE/scrcpy/scrcpy.1" "$SHARE/man/man1/" 2>/dev/null || true

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

# ── 4. Calls need PipeWire's Bluetooth telephony ───────────────────────────
PW_VERSION=$( (pipewire --version 2>/dev/null | grep -E 'Linked with' || pipewire --version 2>/dev/null) |
  grep -oE 'libpipewire [0-9.]+' | head -1 | cut -d' ' -f2 || true)
if [ -n "$PW_VERSION" ] && version_ge "$PW_VERSION" "$MIN_PIPEWIRE_FOR_CALLS"; then
  CALLS=yes
else
  CALLS=no
fi

# ── 5. Phone tools ─────────────────────────────────────────────────────────
bold "4. Phone tools"
mkdir -p "$LIB" "$SHARE/applications" "$UNITS"
install -m 755 "$SRC"/bin/* "$BIN/"
install -m 644 "$SRC/lib/common.sh" "$LIB/"
for f in "$SRC"/applications/*.desktop; do
  name=$(basename "$f")
  if [ $CALLS = no ] && [[ $name == phone-dialer.desktop || $name == phone-call-log.desktop ]]; then
    rm -f "$SHARE/applications/$name"; continue
  fi
  sed "s|@BINDIR@|$BIN|g" "$f" > "$SHARE/applications/$name"
done
install -Dm644 -t "$SHARE/icons/hicolor/scalable/apps" "$SRC"/icons/*.svg
gtk-update-icon-cache -q -t "$SHARE/icons/hicolor" 2>/dev/null || true
# One launcher per phone already set up (phone-setup makes them for new phones)
( set +eu; source "$LIB/common.sh"
  while read -r c; do [ -n "$c" ] && pc_load "$c" && pc_write_launcher; done <<< "$(pc_confs)" )
rm -f "$SHARE/applications/phone-scrcpy.desktop"   # old generic launcher
update-desktop-database "$SHARE/applications" 2>/dev/null || true
ok "Commands in $BIN and app-menu entries"

for fm in "${FILE_MANAGERS[@]}"; do
  mkdir -p "$SHARE/$fm-python/extensions"
  install -m 644 "$SRC/file-manager/phone_photo.py" "$SHARE/$fm-python/extensions/"
  ok "\"Take Photo\" right-click item for ${fm^}"
done
[ ${#FILE_MANAGERS[@]} -eq 0 ] && warn "No GNOME Files or Nemo found — skipping the right-click \"Take Photo\" item (phone-photo still works)."

# ── 6. Background services ─────────────────────────────────────────────────
bold "5. Background services"
install -m 644 "$SRC"/systemd/*.service "$UNITS/"
systemctl --user daemon-reload
services=(phone-automount phone-bt-noaudio)
if [ $CALLS = yes ]; then
  services+=(phone-calls)
else
  systemctl --user disable --now phone-calls.service >/dev/null 2>&1 || true
  rm -f "$UNITS/phone-calls.service"
fi
for s in "${services[@]}"; do
  systemctl --user enable --now "$s.service" >/dev/null 2>&1 && ok "$s" || warn "$s didn't start"
done
if [ $CALLS = no ]; then
  warn "Calls skipped: they need PipeWire $MIN_PIPEWIRE_FOR_CALLS or newer (found: ${PW_VERSION:-none})."
  warn "Everything else works. Upgrade the OS (Fedora 42+, or Mint/Ubuntu based on 26.04+) and re-run to get calls."
fi

# ── 7. Webcam driver (optional) ────────────────────────────────────────────
bold "6. Phone-as-webcam driver (v4l2loopback)"
WEBCAM_OPTS='options v4l2loopback video_nr=10 card_label="Phone Camera" exclusive_caps=1'
if lsmod | grep -q '^v4l2loopback' && [ -e /dev/video10 ]; then
  ok "Already set up"
else
  if [ "$WEBCAM" = ask ]; then
    read -rp "  Install the virtual webcam driver (sudo)? [Y/n] " a
    [[ "$a" =~ ^[Nn] ]] && WEBCAM=no || WEBCAM=yes
  fi
  if [ "$WEBCAM" = yes ]; then
    case $PM in
      dnf)
        if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
          sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" >/dev/null
        fi
        sudo dnf install -y akmod-v4l2loopback v4l2loopback >/dev/null
        sudo akmods --force >/dev/null 2>&1 || true
        SB_HINT="sudo mokutil --import /etc/pki/akmods/certs/public_key.der   (then reboot)" ;;
      apt)
        # Builds via DKMS; with Secure Boot on, Ubuntu/Mint asks to enroll a key (MOK)
        sudo apt-get install -y v4l2loopback-dkms
        SB_HINT="reboot and choose \"Enroll MOK\" in the blue screen (password from the install)" ;;
      none)
        SB_HINT="" ;;
    esac
    echo "$WEBCAM_OPTS" | sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null
    echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf >/dev/null
    if sudo modprobe v4l2loopback 2>/dev/null; then
      ok "\"Phone Camera\" at /dev/video10"
    else
      warn "Driver installed but didn't load. With Secure Boot on: $SB_HINT"
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
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on your PATH — log out and back in (or add it) to use the commands from a terminal." ;; esac
