#!/bin/bash
# Install phone-setup: mirror and control an Android phone from Linux with scrcpy.
# Supports Fedora (dnf) and Linux Mint / Ubuntu / Debian (apt). Safe to re-run
# (updates in place, and removes the extra features older versions installed).
set -euo pipefail

SCRCPY_VERSION=3.3.4        # tested version; v4 changed options, bump deliberately

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
LIB="$HOME/.local/lib/phone-continuity"
SHARE="$HOME/.local/share"

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
# quiet <command...>: run it, showing its output only if it fails (dnf5 prints its
# progress to stderr even with -q)
quiet() { local out; out=$("$@" 2>&1) || { echo "$out"; return 1; }; }

# ── 1. System packages ─────────────────────────────────────────────────────
bold "1. System packages (sudo)"
pkgs=(zenity curl tar)
if command -v dnf >/dev/null; then
  pkgs+=(libnotify)
  quiet sudo dnf install -y --setopt=install_weak_deps=False "${pkgs[@]}"
  ok "${pkgs[*]}"
elif command -v apt-get >/dev/null; then
  pkgs+=(libnotify-bin desktop-file-utils)
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" >/dev/null
  ok "${pkgs[*]}"
else
  warn "Neither dnf nor apt found — install zenity, notify-send, curl and tar yourself."
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
mkdir -p "$BIN" "$SHARE/man/man1"
ln -sf "$SHARE/scrcpy/scrcpy" "$BIN/scrcpy"
ln -sf "$SHARE/scrcpy/adb" "$BIN/adb"
cp "$SHARE/scrcpy/scrcpy.1" "$SHARE/man/man1/" 2>/dev/null || true

# ── 3. Phone tools ─────────────────────────────────────────────────────────
bold "3. Phone tools"
"$SRC/uninstall.sh" --old-features   # webcam, files, calls, audio, Quick Share from older versions
mkdir -p "$LIB" "$SHARE/applications"
install -m 755 "$SRC"/bin/* "$BIN/"
install -m 644 "$SRC/lib/common.sh" "$LIB/"
install -Dm644 -t "$SHARE/icons/hicolor/scalable/apps" "$SRC"/icons/*.svg
gtk-update-icon-cache -q -t "$SHARE/icons/hicolor" 2>/dev/null || true
# One launcher per phone already set up (phone-setup makes them for new phones)
( set +eu; source "$LIB/common.sh"
  while read -r c; do
    if [ -n "$c" ]; then pc_load "$c" && pc_write_launcher; fi
  done <<< "$(pc_confs)"
  true )   # no phones set up yet is fine
update-desktop-database "$SHARE/applications" 2>/dev/null || true
ok "Commands in $BIN and a menu entry per phone"

bold "Done."
cat <<EOF
  Next: plug your Android phone in by USB (with USB debugging on) and run:

      phone-setup

  It turns on wireless debugging and adds the phone to the app menu.
  Re-run it whenever the phone restarts.
EOF
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on your PATH — log out and back in (or add it) to use the commands from a terminal." ;; esac
