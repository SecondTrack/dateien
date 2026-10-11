# Dateien

**Fotos & Musik per WLAN rüberziehen**

Sieh dir Fotos, Musik und Dateien des iPods auf Handy oder Computer an – ohne Kabel, einfach im Browser. QR-Code scannen, fertig.

## Das kann die App

- Fotos, Musik und Dateien im Browser ansehen
- Verbindung per QR-Code und PIN
- Hoch- und runterladen ohne Kabel
- Nur im eigenen WLAN erreichbar

## Läuft auf

iOS 6.1.6 · gejailbreakter iPod touch

## Installieren

Am einfachsten über den **[Reboot Appstore](https://github.com/SecondTrack/reboot)** direkt auf dem iPod.
Von Hand: das `.deb` aus dem [neuesten Release](https://github.com/SecondTrack/dateien/releases/latest) laden und mit `dpkg -i` installieren, danach `uicache`.

## Selbst bauen

Mit [Theos](https://theos.dev) (iOS-SDK mit armv7):

```sh
make package
```

## Teil von Reboot

Diese App gehört zu **Reboot** von [Second Track](https://secondtrack.de) – neue Apps für alte iPods.
Alle Apps: [SecondTrack](https://github.com/SecondTrack).

## Lizenz

GPL-3.0 – siehe [LICENSE](LICENSE). Mitgelieferte Bibliotheken unter `vendor/` behalten ihre eigenen Lizenzen.
Nicht mit Apple verbunden. iPod ist eine Marke von Apple Inc.
