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

# Quick Share top-bar controls (rQuickShare itself is a system package; left installed)
RQS_UUID=quick-share@phone-setup
gnome-extensions disable "$RQS_UUID" 2>/dev/null
rm -rf "$SHARE/gnome-shell/extensions/$RQS_UUID" "$SHARE/cinnamon/applets/$RQS_UUID"
if command -v gnome-shell >/dev/null; then
  python3 - "$RQS_UUID" <<'EOF'
import ast, subprocess, sys
out = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True).stdout.strip().removeprefix("@as ")
cur = ast.literal_eval(out) if out else []
new = [e for e in cur if e != sys.argv[1]]
if new != cur:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(new)])
EOF
fi
if command -v cinnamon >/dev/null; then
  python3 - "$RQS_UUID" <<'EOF'
import ast, subprocess, sys
cur = ast.literal_eval(subprocess.run(["gsettings", "get", "org.cinnamon", "enabled-applets"],
                                      capture_output=True, text=True).stdout.strip().removeprefix("@as "))
new = [a for a in cur if f":{sys.argv[1]}:" not in a]
if new != cur:
    subprocess.run(["gsettings", "set", "org.cinnamon", "enabled-applets", str(new)])
EOF
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/phone-continuity"
  sed -i '/\/storage\/emulated\/0 /d' "$HOME/.config/gtk-3.0/bookmarks" 2>/dev/null
  echo "Removed, including phone settings and Files bookmarks."
else
  echo "Removed. Phone settings kept in ~/.config/phone-continuity (use --purge to delete)."
fi
echo "Not touched: KDE Connect and Bluetooth pairings, the v4l2loopback driver, system packages"
echo "(including rQuickShare: remove it with your package manager, package r-quick-share)."
