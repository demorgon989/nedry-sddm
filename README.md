# 🦖 Nedry Login / Lock Fail

> *"You didn't say the magic word!"*

<img src="nedry.png" width="35%">

Plays the Jurassic Park Nedry clip — video fullscreen + audio — whenever someone enters a wrong password at the **SDDM login screen** and/or the **KDE lock screen**.

## Requirements

- Fedora with KDE Plasma 6 (or any distro running Plasma 6 + PipeWire)
- SDDM login manager (for login screen support)
- A compatible KDE SDDM theme (for login screen support — see below)
- `alsa-utils` package (`sudo dnf install alsa-utils`)
- `paplay` / `pipewire-pulse` (for lock screen audio — installed by default on Fedora KDE)

## Compatible SDDM Themes

The installer scans all installed SDDM themes and lists only compatible ones. A theme is compatible if it:

- Has an `onLoginFailed` handler
- Does **not** use the deprecated `org.kde.plasma.core 2.0` module (Plasma 5 only)

The installer handles three `onLoginFailed` styles automatically:
- Signal handler: `onLoginFailed: { ... }`
- Function: `function onLoginFailed() { ... }`
- Single-line: `onLoginFailed: notificationMessage = "..."` (expanded automatically)

Root block types supported: `Item`, `Rectangle`, `FocusScope`, `Control`, and others.

Confirmed working:
- `breeze` ✅
- `Noir-SDDM-6` ✅
- Most KDE Plasma 6 community themes ✅

Incompatible:
- Themes using `org.kde.plasma.core 2.0` (Plasma 5 era) ❌

## Package Contents

```
nedry-sddm/
├── install.sh       ← Run this first
├── uninstall.sh     ← Restores everything to its original state
├── configure.sh     ← Change SDDM audio device after install
├── fail_h264.mp4    ← The Nedry video clip (H.264)
├── fail.wav         ← Audio extracted from the clip
└── README.md
```

## Installation

```bash
cd nedry-sddm/
sudo ./install.sh
```

The installer will:
1. Ask whether to install on the **SDDM login screen**, **KDE lock screen**, or **both**
2. *(SDDM)* List only compatible themes and let you pick one
3. *(SDDM)* Back up the original `Main.qml` as `Main.qml.bak`
4. *(SDDM)* Surgically patch the theme's `Main.qml`
5. List your available audio output devices and let you pick one
6. Play a test sound to confirm the device works
7. Patch the relevant QML file(s) and copy media files
8. Save config file(s) to the patched directory

**To test SDDM:** fully log out (don't lock), then enter a wrong password.  
**To test lock screen:** lock with `Super+L`, then enter a wrong password.

> **Note on the audio test:** The test sound runs via `sudo` which has no PipeWire
> session, so it may not play even if the device is correct. This is a false negative —
> audio will work correctly from the actual login/lock screen. Lock your screen and
> enter a wrong password to confirm.

## Uninstall

```bash
sudo ./uninstall.sh
```

Detects whatever is installed (SDDM, lock screen, or both) and offers a menu. Restores all original QML files from their backups and removes all Nedry files.

## Changing Audio Device Later

If you swap headsets, plug in new speakers, or add/remove USB audio devices:

```bash
sudo ./configure.sh
```

Detects what's installed and offers to reconfigure accordingly. The **SDDM** audio device can be changed (it uses `aplay`/ALSA directly). The **lock screen** audio needs no reconfiguration — it uses `paplay` via your PipeWire session and follows your normal system audio automatically.

Device names are stored as `sysdefault:CARD=Name` rather than `hw:0,0` style numbers so they survive reboots and USB changes without needing reconfiguration.

## How It Works

### SDDM Login Screen

SDDM runs as the `sddm` system user before any login. PipeWire is unavailable at this stage, so:

- Video plays via `QtMultimedia` (`MediaPlayer` + `VideoOutput`, z: 100)
- Audio plays via `PlasmaCore.DataSource` executable engine calling `aplay` directly to ALSA
- Both fire on the `onLoginFailed` signal
- A spam guard (`playingFail` flag) prevents retriggering while the clip is playing
- A 10-second safety timer force-stops the video if `MediaPlayer` stalls

### KDE Lock Screen

The lock screen patches `LockScreenUi.qml` in the `plasma-desktop` shell — a system file shared across all look-and-feel themes. The `onFailed(kind)` signal fires on authentication failure; `kind == 0` is a password failure, `kind != 0` is fingerprint/smartcard (ignored).

- Video plays via `QtMultimedia` (`MediaPlayer` + `VideoOutput`, z: 200)
- Audio plays via a helper script (`nedry-play.sh`) that sets `XDG_RUNTIME_DIR` and calls `paplay`
- `paplay` uses your existing PipeWire session — **audio mixes correctly with browsers and other apps**
- Same spam guard and safety timer as SDDM

> **Note:** The lock screen QML is owned by the `plasma-workspace` package. A package
> update will overwrite the patch. Run `sudo ./install.sh` again after
> `plasma-workspace` updates to restore it.

## Audio Device Notes

### SDDM
Uses `aplay -L` to list devices by stable card name (e.g. `sysdefault:CARD=Generic_1`) rather than numeric index (e.g. `hw:2,0`). On Fedora (PipeWire), devices appear as:
- `sysdefault:CARD=Generic_1` — motherboard analog output (3.5mm jack)
- `sysdefault:CARD=HyperSense` — USB headset
- `hdmi:CARD=NVidia,DEV=0` — HDMI audio output

### Lock Screen
No device selection needed. Audio goes through PipeWire and respects your system volume and default output device automatically.

## Troubleshooting

**No audio at SDDM login:** Run `sudo ./configure.sh` and pick a different device. Try `sysdefault:CARD=<yourcard>` over `hdmi:` devices — HDMI audio may not be active at the login screen.

**No audio at lock screen with browser open:** This should work — the lock screen uses PipeWire which mixes audio. If it doesn't, check that `paplay` is installed (`command -v paplay`) and that `pipewire-pulse` is running (`systemctl --user status pipewire-pulse`).

**No video (either screen):** Check that `fail_h264.mp4` is in the correct directory and is valid H.264.

**QML errors / black screen on logout (SDDM):** Clear the SDDM cache and test:
```bash
sudo rm -rf /var/cache/sddm/* /root/.cache/sddm* /var/lib/sddm/.cache
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/<yourtheme>
```

**Lock screen stopped working after system update:** `plasma-workspace` was updated and overwrote `LockScreenUi.qml`. Run `sudo ./install.sh` and choose lock screen to repatch.

**Theme not listed by SDDM installer:** The theme uses `org.kde.plasma.core 2.0` (Plasma 5, not supported) or has no `onLoginFailed` handler.

**Broke something:** Run `sudo ./uninstall.sh` to restore all originals, then reinstall.
