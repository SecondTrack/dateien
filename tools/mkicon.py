#!/usr/bin/env python3
# Erzeugt Resources/Icon.png (57) + Icon@2x.png (114): RGBA, 8 bit/Kanal, transparente runde Ecken (r=10/20).
# Nur Standardbibliothek. iOS 6 auf dem iPod rundet NICHT selbst ab (UIPrerenderedIcon=true).
import math, struct, zlib, os

def sd_rrect(x, y, cx, cy, hw, hh, r):        # signierte Distanz zu abgerundetem Rechteck
    qx, qy = abs(x - cx) - hw + r, abs(y - cy) - hh + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r

def cov(d, aa):                                # Abdeckung aus Distanz (weiche Kante, aa = 1 px)
    return max(0.0, min(1.0, 0.5 - d / aa))

def render(S, R):
    u = S / 114.0                              # Entwurf auf 114er-Raster
    top, bot = (90, 200, 250), (0, 110, 240)   # Verlauf hell -> iOS-Blau
    px = bytearray()
    for j in range(S):
        px.append(0)                           # PNG-Filter „None“
        for i in range(S):
            x, y = i + 0.5, j + 0.5
            t = y / S
            bg = [top[k] * (1 - t) + bot[k] * t for k in range(3)]
            a_icon = cov(sd_rrect(x, y, S / 2, S / 2, S / 2, S / 2, R), 1.0)
            col = bg
            # Ordner: Reiter + Körper (weiß), Vorderseite leicht abgesetzt
            tab = cov(sd_rrect(x, y, 38 * u, 35 * u, 16 * u, 7 * u, 4 * u), 1.0)
            body = cov(sd_rrect(x, y, 57 * u, 61 * u, 35 * u, 25 * u, 6 * u), 1.0)
            front = cov(sd_rrect(x, y, 57 * u, 66 * u, 35 * u, 20 * u, 6 * u), 1.0)
            back = max(tab, body)
            col = [c * (1 - back) + w * back for c, w in zip(col, (222, 238, 255))]
            col = [c * (1 - front) + 255 * front for c in col]
            # WLAN-Bögen auf der Vorderseite (blau)
            cx, cy = 57 * u, 79 * u
            dx, dy = x - cx, y - cy
            dist = math.hypot(dx, dy)
            wifi = 0.0
            if dy < 0 and abs(dx) < -dy * 1.05:            # Fächer nach oben
                for rad in (8 * u, 16 * u):
                    wifi = max(wifi, cov(abs(dist - rad) - 2.6 * u, 1.0))
            wifi = max(wifi, cov(dist - 3.6 * u, 1.0))     # Punkt
            wifi *= front
            col = [c * (1 - wifi) + b * wifi for c, b in zip(col, (0, 122, 255))]
            px += bytes([int(round(c)) for c in col] + [int(round(255 * a_icon))])
    return bytes(px)

def png(path, S, data):
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', S, S, 8, 6, 0, 0, 0)    # 8 bit, Farbtyp 6 = RGBA
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(data, 9)) + chunk(b'IEND', b''))

here = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources')
png(os.path.join(here, 'Icon.png'), 57, render(57, 10))
png(os.path.join(here, 'Icon@2x.png'), 114, render(114, 20))
