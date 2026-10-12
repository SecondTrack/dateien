# Files

**Move photos & music over Wi-Fi**

View your iPod's photos, music and files on your phone or computer – no cable, right in the browser. Scan the QR code and you're done.

## Features

- Browse photos, music and files in the browser
- Connect via QR code and PIN
- Upload and download without a cable
- Only reachable on your own Wi-Fi

## Runs on

iOS 6.1.6 · jailbroken iPod touch

## Install

The easiest way is the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod.
By hand: download the `.deb` from the [latest release](https://github.com/SecondTrack/dateien/releases/latest), install it with `dpkg -i`, then run `uicache`.

## Build it yourself

With [Theos](https://theos.dev) (iOS SDK with armv7):

```sh
make package
```

## Part of Reboot

This app is part of **Reboot** by **Second Track** – new apps for old iPods.
All apps: [SecondTrack](https://github.com/SecondTrack).

## License

GPL-3.0 – see [LICENSE](LICENSE). Bundled libraries under `vendor/` keep their own licenses.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
