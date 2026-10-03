# phone-setup

Mac-style "Continuity" between an **Android phone** and a **Linux desktop**:
mirror and control the phone, use it as a webcam, take photos straight into a folder,
browse its files, take and make calls, and play the laptop's sound through the phone.
All of it is glue around existing open-source tools:
[scrcpy](https://github.com/Genymobile/scrcpy),
[KDE Connect](https://kdeconnect.kde.org/),
PipeWire's Bluetooth telephony, and
[Audio Share](https://github.com/mkckr0/audio-share).

Used daily on **Fedora 44 + GNOME 50** with a Motorola moto g13 (Android 14).
The installer also supports **Linux Mint / Ubuntu / Debian** (apt) and the **Nemo** file
manager — see [Supported systems](#supported-systems).

## Features

| Feature | How you use it |
|---|---|
| **Phone mirroring** — full control from the laptop; phone's own screen stays dark | App menu → your phone's name (e.g. *Moto G13*), or `phone` |
| **No PIN while near the laptop** — Android *Extend Unlock* with the laptop as a trusted Bluetooth device | Automatic |
| **PIN after a restart** — typed in a laptop dialog (the PIN pad can't be mirrored) | Automatic |
| **Lock on close** — closing the window leaves the phone locked on its home screen | Automatic |
| **Phone as webcam** (1080p) for any video app | App menu → *Phone Camera* (toggle), or `phone-cam [--front]` |
| **Take Photo** into any folder | Files or Nemo → right-click → *Take Photo with ‹phone›* |
| **Phone storage** in the Files sidebar, kept connected | Sidebar bookmark, or *Phone Files* |
| **Calls** — ring + Answer/Decline on the laptop; call audio on the laptop's speakers or Bluetooth earbuds | Automatic; *Phone Dialer*, *Call History* |
| **Laptop sound on the phone** (e.g. wired headphones on the phone) | App menu → *Phone Audio* (toggle) |
| **Clipboard, notifications, SMS, send files** | KDE Connect |
| **Several phones** — every tool finds whichever set-up phone is reachable (asks if several) | `--phone NAME` on any command |

## Install

```bash
git clone https://github.com/keeeg4n/phone-setup.git
cd phone-setup
./install.sh
```

The installer (asks for `sudo` for packages):

1. installs KDE Connect, `sshfs`, `zenity`, `pactl` and the file-manager plugin bindings
   with `dnf` or `apt`
2. downloads **scrcpy 3.3.4** and **Audio Share 0.3.4** from their GitHub releases and
   checks them against the published SHA-256 checksums
3. puts the `phone-*` commands in `~/.local/bin`, adds menu entries and the right-click
   *Take Photo* item for GNOME Files and/or Nemo
4. enables the user services (storage auto-mount, Bluetooth audio guard, and calls if
   PipeWire is new enough)
5. optionally installs the **v4l2loopback** webcam driver (RPM Fusion on Fedora,
   `v4l2loopback-dkms` on Mint/Ubuntu)

Then plug the phone in by USB and run:

```bash
phone-setup
```

`phone-setup` turns on wireless debugging, installs and pairs KDE Connect, installs the
Audio Share app, pairs Bluetooth and walks you through **Extend Unlock**. It skips steps
that are already done, so re-run it any time — in particular **after the phone restarts**
(Android turns wireless debugging off on every reboot; only USB can turn it back on).

### Before you start, on the phone

Settings → About phone → tap *Build number* 7 times → Settings → System →
Developer options → **USB debugging** on.

## Commands

| Command | What it does |
|---|---|
| `phone-setup` | Set up or repair a phone (needs USB) |
| `phone` | Mirror and control the phone |
| `phone-unlock` | Type the phone's PIN from the terminal |
| `phone-cam [--front]` | Toggle the phone as webcam (`/dev/video10`, "Phone Camera") |
| `phone-photo [folder]` | Open the phone camera, copy the new photo into the folder |
| `phone-files` | Open the phone's storage in Files |
| `phone-audio` | Toggle laptop sound → phone |
| `phone-dial [number]` | Call someone (no number: pick from contacts/recent calls) |
| `phone-call-log` | Call history; double-click to call back |

Each accepts `--phone NAME` to choose a phone when several are set up.

## How it works

- Each phone gets `~/.config/phone-continuity/devices/<serial>.conf` (name, serial,
  Wi-Fi address, Bluetooth address, KDE Connect ID), written by `phone-setup`.
- `lib/common.sh` finds a reachable phone: USB first, then its saved Wi-Fi address, then
  the address KDE Connect reports (and remembers it if the router changed it).
- **Extend Unlock only keeps a phone unlocked** — after the laptop was off it needs the PIN
  once, which `phone` asks for in a dialog.
- A phone can only hold a Bluetooth link to the laptop through its audio profiles, which
  made Android play media on the laptop. `phone-bt-noaudio` drops just the media (A2DP)
  profile; the hands-free (HFP) link stays, keeping Bluetooth up and powering calls.
- Calls use PipeWire's `org.pipewire.Telephony` service (HFP hands-free). Between calls
  the laptop rejects call audio, so calls you take on the phone stay on the phone.

## Supported systems

| | Fedora 42+ | Mint / Ubuntu on 26.04+ | Mint 22 / Ubuntu 24.04 |
|---|---|---|---|
| Mirroring, webcam, photos, files, audio | ✅ | ✅ | ✅ |
| Calls (needs PipeWire ≥ 1.4) | ✅ | ✅ | ❌ PipeWire 1.0 — skipped by the installer |

Installer tested on Fedora 44 and in Linux Mint containers (Ubuntu 24.04 and 26.04 bases).

**Desktops:** GNOME (Files) and Cinnamon (Nemo) get the right-click *Take Photo* item and
the sidebar bookmark. On **KDE Plasma** everything else works; Dolphin shows KDE Connect
phones by itself.

On Mint/Ubuntu with **Secure Boot**, installing the webcam driver asks you to set a
password; reboot and choose *Enroll MOK* to allow the driver to load.

## Limitations

- After a **phone** restart: plug in USB and re-run `phone-setup`, and enter the PIN once.
- The phone's PIN pad can't be shown in the mirror window (Android hides it from capture).
- *Phone Audio* needs both devices on the same Wi-Fi (Audio Share uses UDP).
- Calls rely on PipeWire ≥ 1.4 Bluetooth telephony and haven't been tested end-to-end
  with a real call yet; call quality depends on the phone's Bluetooth hands-free support.

## Uninstall

```bash
./uninstall.sh            # keeps phone settings
./uninstall.sh --purge    # also removes them and the Files bookmarks
```

## License

MIT — see [LICENSE](LICENSE). scrcpy, KDE Connect and Audio Share are separate projects
under their own licenses and are downloaded, not bundled.
