#!/bin/bash
# Remove phone-setup from this user account. Phone settings files are kept unless
# you pass --purge. System packages and the webcam driver are left installed.
set -u
BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share"

for s in phone-automount phone-bt-noaudio phone-calls; do
  systemctl --user disable --now "$s.service" 2>/dev/null
  rm -f "$HOME/.config/systemd/user/$s.service"
done
systemctl --user daemon-reload

for f in phone phone-setup phone-unlock phone-cam phone-photo phone-files phone-automount \
         phone-bt-noaudio phone-audio phone-calls-daemon phone-dial phone-call-log; do
  rm -f "$BIN/$f"
done
rm -f "$BIN/scrcpy" "$BIN/adb"
rm -rf "$HOME/.local/lib/phone-continuity" "$SHARE/scrcpy" "$SHARE/audio-share"
rm -f "$SHARE/nautilus-python/extensions/phone_photo.py" "$SHARE/nemo-python/extensions/phone_photo.py"
for f in phone-scrcpy phone-cam phone-files phone-audio phone-dialer phone-call-log; do
  rm -f "$SHARE/applications/$f.desktop"
done
grep -lxE "Icon=phone-continuity(-tablet)?" "$SHARE/applications"/phone-*.desktop 2>/dev/null | xargs -r rm -f
rm -f "$SHARE/icons/hicolor/scalable/apps"/phone-continuity*.svg
update-desktop-database "$SHARE/applications" 2>/dev/null || true

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/phone-continuity"
  sed -i '/\/storage\/emulated\/0 /d' "$HOME/.config/gtk-3.0/bookmarks" 2>/dev/null
  echo "Removed, including phone settings and Files bookmarks."
else
  echo "Removed. Phone settings kept in ~/.config/phone-continuity (use --purge to delete)."
fi
echo "Not touched: KDE Connect and Bluetooth pairings, the v4l2loopback driver, system packages."
