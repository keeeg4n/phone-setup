# Shared helpers for the phone-* tools. Source this file; don't run it.
#
# Each phone set up with `phone-setup` has a file in $PC_DIR/<serial>.conf:
#   NAME, SERIAL, WIFI_IP, BT_MAC, KDEC_ID, DEVICE_TYPE (phone|tablet)
# pc_select picks a reachable phone and sets those variables plus
# ADB_ID (what to pass to adb -s / scrcpy -s), TRANSPORT (usb|wifi) and CONF.

PC_DIR="$HOME/.config/phone-continuity/devices"
ADB="$HOME/.local/bin/adb"
SCRCPY="$HOME/.local/bin/scrcpy"
ADB_PORT=5555

pc_notify() {
  notify-send -i phone "Phone" "$*" 2>/dev/null
  echo "$*" >&2
}

pc_load() {
  NAME="" SERIAL="" WIFI_IP="" BT_MAC="" KDEC_ID="" DEVICE_TYPE=""
  CONF="$1"
  # shellcheck disable=SC1090
  source "$1"
}

pc_confs() {
  local c
  for c in "$PC_DIR"/*.conf; do [ -e "$c" ] && echo "$c"; done
}

# Phone name for display: all-lowercase words get a capital first letter ("moto g13" ->
# "Moto G13"); words that already have capitals stay ("iPhone", "OnePlus"). The stored
# NAME is left as is.
pc_display_name() {
  local w out=() words
  read -ra words <<< "$1"
  for w in "${words[@]}"; do
    if [[ "$w" == *[[:upper:]]* ]]; then out+=("$w"); else out+=("${w^}"); fi
  done
  echo "${out[*]}"
}

# App-menu launcher for the loaded phone: phone (or tablet) icon, named after the device. Its
# StartupWMClass matches the window class `phone` gives that phone's scrcpy window,
# so the dock and Alt-Tab show this icon and name too.
pc_write_launcher() {
  local apps="$HOME/.local/share/applications" label favs icon=phone-continuity
  [[ "$SERIAL" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [ "$DEVICE_TYPE" = tablet ] && icon=phone-continuity-tablet
  label=$(pc_display_name "$NAME" | tr -d '[:cntrl:]' | sed 's/\\/\\\\/g')
  mkdir -p "$apps"
  cat > "$apps/phone-$SERIAL.desktop" <<EOF
[Desktop Entry]
Name=$label
Comment=Show and control $label on this computer
Exec=$HOME/.local/bin/phone --phone $SERIAL
Icon=$icon
Terminal=false
Type=Application
Categories=Utility;
StartupWMClass=phone-$SERIAL
EOF
  # Move a dock pin of the old generic launcher over to this phone's launcher
  if command -v gsettings >/dev/null; then
    favs=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)
    if [[ "$favs" == *"'phone-scrcpy.desktop'"* ]]; then
      gsettings set org.gnome.shell favorite-apps "${favs/\'phone-scrcpy.desktop\'/\'phone-$SERIAL.desktop\'}"
    fi
  fi
}

# Current LAN address of a phone as KDE Connect sees it (empty if unknown).
pc_kdec_ip() {
  [ -n "$1" ] || return 0
  kdeconnect-cli -l 2>/dev/null | sed -n "s/.*: $1 on \([0-9.]*\) via LAN.*/\1/p" | head -1
}

pc_kdec_reachable() {
  [ -n "$1" ] && kdeconnect-cli -a --id-only 2>/dev/null | grep -qx "$1"
}

pc_adb_shell() { "$ADB" -s "$ADB_ID" shell "$@"; }

# Try to reach the loaded phone over USB, then Wi-Fi (saved address, then the
# address KDE Connect reports). Sets ADB_ID/TRANSPORT. Remembers a new address.
pc_reach() {
  if "$ADB" devices | awk -v s="$SERIAL" '$1==s && $2=="device"{f=1} END{exit !f}'; then
    ADB_ID="$SERIAL"; TRANSPORT=usb; return 0
  fi
  local ip got
  for ip in "$WIFI_IP" "$(pc_kdec_ip "$KDEC_ID")"; do
    [ -n "$ip" ] || continue
    if ! "$ADB" devices | grep -qE "^$ip:$ADB_PORT\s+device$"; then
      timeout 4 "$ADB" connect "$ip:$ADB_PORT" >/dev/null 2>&1
    fi
    got=$(timeout 4 "$ADB" -s "$ip:$ADB_PORT" shell getprop ro.serialno 2>/dev/null | tr -d '\r')
    if [ "$got" = "$SERIAL" ]; then
      ADB_ID="$ip:$ADB_PORT"; TRANSPORT=wifi
      if [ "$ip" != "$WIFI_IP" ]; then
        sed -i "s|^WIFI_IP=.*|WIFI_IP=\"$ip\"|" "$CONF"; WIFI_IP="$ip"
      fi
      return 0
    fi
  done
  return 1
}

# pc_choose <title> <name>...  -> prints the chosen index (0-based)
pc_choose() {
  local title="$1"; shift
  local pick
  pick=$(zenity --list --title="$title" --text="More than one phone is connected." \
    --column="Phone" "$@" --height=260 2>/dev/null) || return 1
  local i=0 n
  for n in "$@"; do [ "$n" = "$pick" ] && { echo $i; return 0; }; i=$((i+1)); done
  return 1
}

# pc_select [name-or-serial]: choose a reachable phone (asks if several).
pc_select() {
  local want="$1" c found=() ids=() tr=() names=()
  local confs; confs=$(pc_confs)
  if [ -z "$confs" ]; then
    pc_notify "No phones set up yet. Plug one in by USB and run: phone-setup"; return 1
  fi
  while read -r c; do
    pc_load "$c"
    if [ -n "$want" ] && [ "$NAME" != "$want" ] && [ "$SERIAL" != "$want" ]; then continue; fi
    if pc_reach; then found+=("$c"); ids+=("$ADB_ID"); tr+=("$TRANSPORT"); names+=("$NAME"); fi
  done <<< "$confs"

  local idx=0
  case ${#found[@]} in
    0) pc_notify "Couldn't reach ${want:-any of your phones}. Same Wi-Fi? Restarted? (then plug in USB and run phone-setup)"; return 1 ;;
    1) idx=0 ;;
    *) idx=$(pc_choose "Choose a phone" "${names[@]}") || return 1 ;;
  esac
  pc_load "${found[$idx]}"; ADB_ID="${ids[$idx]}"; TRANSPORT="${tr[$idx]}"
}

# Like pc_select but only needs KDE Connect (used for file browsing).
pc_select_kdec() {
  local want="$1" c found=() names=()
  while read -r c; do
    [ -n "$c" ] || continue
    pc_load "$c"
    if [ -n "$want" ] && [ "$NAME" != "$want" ] && [ "$SERIAL" != "$want" ]; then continue; fi
    pc_kdec_reachable "$KDEC_ID" && { found+=("$c"); names+=("$NAME"); }
  done <<< "$(pc_confs)"
  local idx=0
  case ${#found[@]} in
    0) pc_notify "No phone reachable through KDE Connect. Same Wi-Fi, KDE Connect app running?"; return 1 ;;
    1) idx=0 ;;
    *) idx=$(pc_choose "Choose a phone" "${names[@]}") || return 1 ;;
  esac
  pc_load "${found[$idx]}"
}

# Wake the screen and dismiss a non-secure lock screen (Extend Unlock).
pc_wake() {
  pc_adb_shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  sleep 0.5
  pc_adb_shell wm dismiss-keyguard >/dev/null 2>&1
}

pc_locked() { pc_adb_shell dumpsys window 2>/dev/null | grep -q "isKeyguardShowing=true"; }

# Reconnect Bluetooth and give Extend Unlock a moment to kick in (matters right
# after the laptop boots, when the Bluetooth link is still coming up).
pc_bt_connect() {
  [ -n "$BT_MAC" ] || return 0
  bluetoothctl info "$BT_MAC" 2>/dev/null | grep -q "Connected: yes" && return 0
  timeout 8 bluetoothctl connect "$BT_MAC" >/dev/null 2>&1
  local i
  for i in 1 2 3 4 5 6; do
    pc_adb_shell dumpsys trust 2>/dev/null | grep -A1 "auth.trustagent.GoogleTrustAgent$" | grep -q "trusted=1" && return 0
    sleep 1
  done
}

# Unlock with a PIN. Everything runs in one adb call because the lock screen
# goes back to sleep within seconds.
pc_unlock_pin() {
  local pin="$1" size w h
  size=$(pc_adb_shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1); w=${size%x*}; h=${size#*x}
  pc_adb_shell "input keyevent KEYCODE_WAKEUP; sleep 0.4; input swipe $((w/2)) $((h*8/10)) $((w/2)) $((h*2/10)) 200; sleep 0.6; input text '$pin'; input keyevent KEYCODE_ENTER" >/dev/null 2>&1
  sleep 1
  ! pc_locked
}

# Wake the phone; if it's still PIN-locked (Extend Unlock can't unlock a phone that
# fully locked, e.g. after the laptop was off), ask for the PIN in a laptop dialog.
# (The phone hides its PIN pad from screen capture, so it can't be typed in the
# scrcpy window, and the user prefers not to pick up the phone.)
pc_wake_unlock() {
  pc_bt_connect
  pc_wake
  sleep 0.5
  pc_locked || return 0
  local pin tries
  for tries in 1 2 3; do
    pin=$(zenity --password --title="Unlock $NAME" 2>/dev/null) || return 1
    [ -n "$pin" ] || return 1
    pc_unlock_pin "$pin" && return 0
    zenity --error --text="Wrong PIN, or the phone didn't unlock. Try again." 2>/dev/null
  done
  return 1
}

# Parse a leading "--phone NAME" option. Sets PHONE_ARG; caller shifts by PC_SHIFT.
pc_phone_opt() {
  PHONE_ARG="" PC_SHIFT=0
  if [ "$1" = "--phone" ] && [ -n "$2" ]; then PHONE_ARG="$2"; PC_SHIFT=2; fi
}
