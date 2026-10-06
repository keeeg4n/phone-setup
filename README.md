# phone-setup

Mirror and control an **Android phone** from a **Linux desktop** with
[scrcpy](https://github.com/Genymobile/scrcpy): one app-menu entry per phone, over USB
or Wi-Fi, with the phone's own screen kept dark while you use it.

Used daily on **Fedora 44 + GNOME 50** with a Motorola moto g13 (Android 14).
The installer also supports **Linux Mint / Ubuntu / Debian** (apt).

## Features

| Feature | How you use it |
|---|---|
| **Phone mirroring** — full control from the laptop; phone's own screen stays dark | App menu → your phone's name (e.g. *Moto G13*), or `phone` |
| **USB or Wi-Fi** — USB if plugged in, otherwise wireless debugging | Automatic |
| **PIN from the laptop** — if the phone is locked, it's asked for in a dialog (the PIN pad can't be mirrored) | Automatic |
| **Lock on close** — closing the window leaves the phone locked on its home screen | Automatic |
| **Several phones** — finds whichever set-up phone is reachable (asks if several) | `--phone NAME` on any command |

## Install

```bash
git clone https://github.com/keeeg4n/phone-setup.git
cd phone-setup
./install.sh
```

The installer (asks for `sudo` for packages):

1. installs `zenity` and `notify-send` with `dnf` or `apt`
2. downloads **scrcpy 3.3.4** (with its bundled `adb`) from its GitHub release and checks
   it against the published SHA-256 checksums
3. puts the `phone-*` commands in `~/.local/bin` and adds a menu entry per phone

Re-running it on a machine with an older version removes the features older versions
had (webcam, photos, files, calls, audio, Quick Share and their background services).

Then plug the phone in by USB and run:

```bash
phone-setup
```

`phone-setup` turns on wireless debugging and adds the phone to the app menu. Re-run it
any time — in particular **after the phone restarts** (Android turns wireless debugging
off on every reboot; only USB can turn it back on) or when its Wi-Fi address changes.

### Before you start, on the phone

Settings → About phone → tap *Build number* 7 times → Settings → System →
Developer options → **USB debugging** on.

## Commands

| Command | What it does |
|---|---|
| `phone-setup` | Set up or repair a phone (needs USB) |
| `phone` | Mirror and control the phone (extra options are passed to scrcpy) |
| `phone-unlock` | Type the phone's PIN from the terminal |

Each accepts `--phone NAME` to choose a phone when several are set up.

## How it works

- Each phone gets `~/.config/phone-continuity/devices/<serial>.conf` (name, serial,
  Wi-Fi address, phone or tablet), written by `phone-setup`.
- `lib/common.sh` finds a reachable phone: USB first, then its saved Wi-Fi address.
- Each phone's scrcpy window gets its own window class, so the dock shows that phone's
  launcher (icon and name).

## Limitations

- After a **phone** restart: plug in USB and re-run `phone-setup`.
- A locked phone needs its PIN each time you open it (asked in a dialog).
- The phone's PIN pad can't be shown in the mirror window (Android hides it from capture).

## Uninstall

```bash
./uninstall.sh            # keeps phone settings
./uninstall.sh --purge    # also removes them
```

## License

MIT — see [LICENSE](LICENSE). scrcpy is a separate project under its own license and is
downloaded, not bundled.
