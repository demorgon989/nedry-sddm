# 🦖 Nedry SDDM Login Fail

> *"You didn't say the magic word!"*

<img src="nedry.png" width="35%">

Plays the Jurassic Park Nedry clip — video fullscreen + audio — whenever someone enters a wrong password at the SDDM login screen.

## Requirements

- Fedora with KDE Plasma 6
- SDDM login manager
- A compatible KDE SDDM theme (see below)
- `alsa-utils` package (`sudo dnf install alsa-utils`)

## Compatible Themes

The installer only lists themes that are compatible. A theme is compatible if it:

- Uses `org.kde.breeze.components` (standard KDE base)
- Has an `onLoginFailed` handler
- Does **not** use the deprecated `org.kde.plasma.core 2.0` module

Confirmed working:
- `breeze` ✅
- `Noir-SDDM-6` ✅
- Most other themes derived from the KDE Breeze template ✅

Incompatible (older/non-standard themes):
- Themes using `org.kde.plasma.core 2.0` ❌
- Fully custom themes that don't use the KDE Breeze base ❌

## Package Contents

```
nedry-sddm/
├── install.sh       ← Run this first
├── uninstall.sh     ← Restores your theme to its original state
├── configure.sh     ← Change audio device after install
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
1. List only compatible SDDM themes and let you pick one
2. Back up the original `Main.qml` as `Main.qml.bak`
3. Surgically patch the theme's `Main.qml` — preserving all its original structure
4. Inject `import org.kde.plasma.plasma5support` if the theme doesn't already have it
5. Copy the video and audio files into the theme directory
6. List your available audio output devices and let you pick one
7. Play a test sound to confirm it works
8. Save a `nedry.conf` config file to the theme directory

**To test:** fully log out (don't lock), then enter a wrong password.

## Uninstall

```bash
sudo ./uninstall.sh
```

Restores the original `Main.qml` from the backup and removes all Nedry files. If you installed into multiple themes it will ask which one(s) to restore.

## Changing Audio Device Later

If you swap headsets, plug in new speakers, or your device numbering shifts at boot:

```bash
sudo ./configure.sh
```

Re-lists your devices, lets you pick, tests the audio, and updates everything automatically.

## How It Works

- Video plays via Qt6 `QtMultimedia` (`MediaPlayer` + `VideoOutput`)
- Audio plays separately via `PlasmaCore.DataSource` executable engine calling `aplay`
- This bypasses QtMultimedia's broken audio path in SDDM's restricted pre-login environment
- Both fire simultaneously on the `onLoginFailed` signal

## Troubleshooting

**No audio:** Run `sudo ./configure.sh` and pick a different device.  
**No video:** Check that `fail_h264.mp4` is in the theme directory and is valid H.264.  
**QML errors:** Run `sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/<yourtheme>` and check output.  
**Card number changed:** ALSA card numbers can shift when USB devices are added/removed at boot. Run `sudo ./configure.sh` to fix.  
**Broke my theme:** Run `sudo ./uninstall.sh` to restore the original, then reinstall.
