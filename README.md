# FileTransfer

**Your iPod as a Wi-Fi drive: browse, upload and download from any browser – no cable, no iTunes.**

Start the app, scan the QR code with your phone or open the address on your computer, enter the 4-digit PIN shown on the iPod, done. Drag files in, download photos and music, add pictures and videos to the camera roll.

## What it can do

- File browser with sorting, search, hidden files and drag-and-drop upload.
- **Photos** and **Music** views that collect everything from the camera roll and music folders.
- Upload images and videos straight into the **camera roll** (formats iOS 6 can play: JPG, PNG, GIF, H.264).
- Install and remove apps (`.deb` and `.ipa`) from the browser – every install has to be confirmed on the iPod itself.
- Optional web shell, switched on per session with its own one-time password.
- Downloads support resuming (HTTP range requests).

## Security

A file server on an old device has to be careful, so:

- **Only your local network** can connect (private address ranges); requests with a foreign host name are refused, which blocks DNS-rebinding attacks from websites.
- **New random PIN on every start**, sent only in a header; 5 wrong attempts lock it for 30 seconds.
- **Path checks:** every path is resolved and must stay inside the shared folder, symlinks included; system folders can't be deleted or renamed.
- **Installer helper:** the root helper only answers the real Files app, copies the package to a root-only folder and checks its SHA-256 against what you confirmed, so it can't be swapped in between.
- **Web shell** turns itself off after 10 idle minutes or 5 wrong passwords.

## Under the hood

A hand-written HTTP/1.1 server on BSD sockets (port 8080), the web interface compiled into the binary, and a small QR encoder written from the spec.

## Runs on

iOS 6.1.6 · jailbroken iPod touch 4 · any browser on the same Wi-Fi

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/dateien/releases/latest), `dpkg -i`, then `uicache`.

Build it yourself with [Theos](https://theos.dev): `make package` (iOS 6.0+, armv7).

## License

GPL-3.0 – see [LICENSE](LICENSE).
Not affiliated with Apple. iPod is a trademark of Apple Inc.
